{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver    #-}

{-# OPTIONS_GHC -Wno-partial-type-signatures          #-}

{-# LANGUAGE ApplicativeDo                            #-}
{-# LANGUAGE LambdaCase                               #-}
{-# LANGUAGE NumericUnderscores                       #-}
{-# LANGUAGE PartialTypeSignatures                    #-}
{-# LANGUAGE ScopedTypeVariables                      #-}
{-# LANGUAGE TupleSections                            #-}
{-# LANGUAGE TypeApplications                         #-}
{-# LANGUAGE ViewPatterns                             #-}

module Top where

import           Dma.Prelude                 hiding ( empty )
-- import           Clash.Prelude           hiding ( empty
--                                                 , read
--                                                 )
import           Clash.Annotations.TH
import           Control.Lens                   ( view )

import           Axi
import           Register
import           Search
import           SpiSlave
import           StreamReassembly
import           Tlp

import           Blackboxes

createDomain vSystem{vName="ExtClk", vPeriod=hzToPeriod 100e6}
createDomain vXilinxSystem{vName="Sys", vPeriod=hzToPeriod 125e6}
-- createDomain vXilinxSystem{vName="Spi", vPeriod=hzToPeriod 10e6}

type RegCount = 29

registerPerms :: Vec RegCount Permission
registerPerms

  =  a -- 0.  address 1 low
  :> a -- 1.  address 1 high
  :> a -- 2.  PCIe write trigger
  :> a -- 3.  search length
  :> a -- 4.  value 1 low
  :> a -- 5.  value 1 high

  :> a -- 6.  buffer select
  :> r -- 7.  buffer value
  :> r -- 8.  buffer offset

  :> r -- 9.  PCIe read busy
  :> w -- 10. PCIe read trigger
  :> r -- 11. PCIe read failed
  :> r -- 12. PCIe read stat length

  :> r -- 13. debug index

  :> r -- 14. PCIe search busy
  :> w -- 15. PCIe search trigger
  :> r -- 16. PCIe search failed
  :> r -- 17. PCIe search length
  :> a -- 18. PCIe search type
  :> a -- 19. PCIe search value

  :> r -- 20. debug requester
  :> r -- 21. debug pci tx buffers count
  :> r -- 22. debug transaction writer ready
  :> a -- 23. debug transaction error dropr- write to reset
  :> r -- 24. debug transaction sent count
  :> a -- 25. debug transaction ready flag - write to reset

  :> r -- 26. debug read trigger count
  :> r -- 27. debug search trigger count

  :> r -- 28. debug transaction receive count

  :> Nil

 where
  r = Permission False True
  w = Permission True False
  a = Permission True True

data CoreStats
  = CoreStats
  { requesterDebug  :: U16
  , txBufferDebug   :: BitVector 6
  , twReadyDebug    :: Bool
  , txErrorDrop     :: Bool
  , txSending       :: Bool
  , txHasBeenReady  :: Bool
  , readTriggered   :: Bool
  , searchTriggered :: Bool
  , rxIncoming      :: Bool
  }

update
  :: U64
  -> Stream Failed (Maybe U64)
  -> Stream Failed (Maybe _)
  -> CoreStats
  -> RegisterHandler' RegCount
update _ readStream searchStream s Nothing xs = imap
  (curry $ \case
    (2 , _) -> 0

    (8 , _) -> 0

    (9 , _) -> unstream 0 (const 1) readStream
    (10, v) -> ite (readTriggered s) 0 v
    (11, _) -> undone 0 (bool 0 1) readStream
    (12, v) -> ite (readTriggered s) 0 $ streamCount v readStream

    (14, _) -> unstream 0 (const 1) searchStream
    (15, v) -> ite (searchTriggered s) 0 v
    (16, _) -> undone 0 (bool 0 1) searchStream
    (17, v) -> ite (searchTriggered s) 0 $ streamCount v searchStream

    (20, _) -> resize (pack $ requesterDebug s)
    (21, _) -> resize (pack $ txBufferDebug s)
    (22, _) -> resize (pack $ twReadyDebug s)

    (23, v) -> v .|. resize (pack (txErrorDrop s))
    (24, v) -> ite (txSending s) (v + 1) v
    (25, v) -> v .|. resize (pack (txHasBeenReady s))

    (26, v) -> ite (readTriggered s) (v + 1) v
    (27, v) -> ite (searchTriggered s) (v + 1) v

    (28, v)  -> ite (rxIncoming s) (v + 1) v

    (_ , v) -> v
  )
  xs
update buff readStream searchStream s (Just (RegisterSlot _ idx)) xs = imap
  (curry $ \case
    (2 , _) -> 0

    (7 , _) -> ite (testBit idx 2) fst snd (split buff)
    (8 , _) -> resize (pack $ idx `shiftR` 3)

    (9 , _) -> unstream 0 (const 1) readStream
    (10, v) -> ite (readTriggered s) 0 v
    (11, _) -> undone 0 (bool 0 1) readStream
    (12, v) -> ite (readTriggered s) 0 $ streamCount v readStream

    (13, _) -> let x = resize (pack idx) in x ++# x ++# x ++# x

    (14, _) -> unstream 0 (const 1) searchStream
    (15, v) -> ite (searchTriggered s) 0 v
    (16, _) -> undone 0 (bool 0 1) searchStream
    (17, v) -> ite (searchTriggered s) 0 $ streamCount v searchStream

    (20, _) -> resize (pack $ requesterDebug s)
    (21, _) -> resize (pack $ txBufferDebug s)
    (22, _) -> resize (pack $ twReadyDebug s)

    (23, v) -> v .|. resize (pack (txErrorDrop s))
    (24, v) -> ite (txSending s) (v + 1) v
    (25, v) -> v .|. resize (pack (txHasBeenReady s))

    (26, v) -> ite (readTriggered s) (v + 1) v
    (27, v) -> ite (searchTriggered s) (v + 1) v

    (28, v)  -> ite (rxIncoming s) (v + 1) v

    (_ , v) -> v
  )
  xs

trigger
  :: ( HiddenClockResetEnable sys
     , KnownNat t
     , KnownNat b
     , (t + (t0 + 1)) ~ RegCount
     , (b + (b0 + 1)) ~ RegCount
     )
  => Vec RegCount (Signal sys U32)
  -> SNat t
  -> SNat b
  -> Signal sys a
  -> Signal sys (Maybe a)
trigger registers trig busy value = mux (t .&&. fmap not t')
  (Just <$> value)
  (pure Nothing)
 where
  t = fmap lsb (at trig registers) ./=. 0 .&&. fmap lsb (at busy registers) .==. 0
  t' = register False t

readRegister
  :: forall sys n n0 a
   . ( BitPack a
     , KnownNat (BitSize a)
     , KnownNat n
     , HiddenClockResetEnable sys
     , (n + (n0 + 1)) ~ RegCount
     )
  => Vec RegCount (Signal sys U32)
  -> SNat n
  -> Signal sys a
readRegister registers i = bitCoerce . resize <$> at i registers

limitAddress :: forall n. (KnownNat n, 1 <= n) => U32 -> Maybe (Unsigned n)
limitAddress x
  | x < fromInteger (natVal (SNat @n)) = Just . unpack . resize $ x
  | otherwise                          = Nothing

attach
  :: Signal dom (Maybe a)
  -> Signal dom (Maybe b)
  -> Signal dom (Maybe (a, b))
attach = liftA2 (liftA2 (,))

resultBuffer
  :: forall sys a n n0 .
  ( HiddenClockResetEnable sys
  , BitPack a, KnownNat (BitSize a), NFDataX a, Default a, 1 <= BitSize a
  , (n+(n0+1)) ~ RegCount
  )
  => Vec RegCount (Signal sys U32)
  -> SNat n
  -> Signal sys (Maybe a)
  -> Signal sys U64
resultBuffer registers writePointer writeValue
  = fmap (resize . pack)
  $ register def
  $ blockRamPow2
    (deepErrorX "Undefined initial ram value" :: Vec 512 a)
    -- (repeat def :: Vec 512 a)
    (readRegister registers d8)
    (flip attach writeValue $ fmap limitAddress (at writePointer registers))

fifoMealy
  :: forall addrSize a
   . KnownNat addrSize
  => (BitVector (addrSize + 1), BitVector (addrSize + 1), BitVector (addrSize + 1))
  -> (a, Bool, Bool)
  -> ( (BitVector (addrSize + 1), BitVector (addrSize + 1), BitVector (addrSize + 1))
     , (Bool, Bool, Maybe (BitVector addrSize, a), BitVector addrSize)
     )
fifoMealy (rptr,wptr,wptrr) (wdata,winc,rinc) =
  let raddr = truncateB rptr :: BitVector addrSize
      waddr = truncateB wptr :: BitVector addrSize

      wr | winc && not full = Just (waddr, wdata)
         | otherwise        = Nothing

      rptr' = rptr + boolToBV (rinc && not empty)
      wptr' = wptr + boolToBV (winc && not full)
      empty = rptr == wptrr
      full  = msb rptr /= msb wptr && raddr == waddr
  in  ((rptr',wptr',wptr), (empty,full,wr,truncateB rptr'))

fifo
  :: forall addrSize n a dom
   . ( HiddenClockResetEnable dom
     , NFDataX a
     , KnownNat addrSize
     , KnownNat n
     , n ~ (2 ^ addrSize) )
  => SNat n
  -> DataFlow dom Bool Bool a a
fifo _ = DF $ \i iV oR ->
  let initMem              = repeat  (errorX "fifoDF: undefined") :: Vec n a
      o                    = blockRam initMem rptr wr
      (empty,full,wr,rptr) = mealyB (fifoMealy @addrSize) (0,0,0) (i,iV,oR)
  in  (o,not <$> empty, not <$> full)

txFifo
  :: HiddenClockResetEnable sys
  => Signal sys (Maybe Tx)
  -> Signal sys Bool
  -> (Signal sys (Maybe Tx), Signal sys Bool)
txFifo tx' outReady = (toMaybe <$> oV <*> o, iR)
 where
  (txEn, tx) = unbundle $ unpackMaybe <$> tx'
  (o, oV, iR)= df (fifo d4) tx txEn outReady

dmaCore
  :: forall clk. (HiddenClockResetEnable clk)
  => Signal clk SpiI
      -- ^ spi
  -> Signal clk (AxiSimpleStream 8 22)
      -- ^ axi
  -> ( Signal clk (BitVector 8)
     , Signal clk (BitVector 5)
     , Signal clk (BitVector 3)
     )
      -- ^ pci status
  -> Signal clk Bool
      -- ^ axis ready
  -> Signal clk (BitVector 6)
      -- ^ buffers available
  -> Signal clk (BitVector 1)
      -- ^ Transmit Error Drop
  -> ( Signal clk Bit
     , Signal clk Bool
     , Signal clk (AxiSimpleStream 8 4)
     , Signal clk Bool
     )

dmaCore
  spiRx
  pciRx
  (pciBus, pciDevice, pciFunc)
  pciTxReady
  txBuffers
  txErrorDrop_
  = (miso, pure True, pciTx, pending)
 where
  requester = pciBus .++#. pciDevice .++#. pciFunc

  (spiEnabled, spiByte, miso)           = spiSlave (spiRx, spiTx)

  pciRxDebugStream = realignAxis (isJust <$> triggerPcieRead, pciRx)
  pciRxDebugStart = register True
                  ( mux (_axis_last <$> pciRx) (pure True)
                  $ mux (_axis_valid <$> pciRx) (pure False) pciRxDebugStart)

  pciRxStream = register def (completionStream pciRx)

  pciRxDebugStreamIdx = register (0 :: BitVector 16)
    $ mux (isJust <$> triggerPcieRead) 0
    $ mux (unstream False isJust <$> pciRxDebugStream) (pciRxDebugStreamIdx + 1) pciRxDebugStreamIdx

  pciTxDebugStreamIdx = register (0 :: BitVector 16)
    $ mux (isJust <$> triggerPcieRead) 0
    $ mux (fmap _axis_valid pciTx .&&. pciTxReady) (pciTxDebugStreamIdx + 1) pciTxDebugStreamIdx

  pciTxDebugMem = blockRam (replicate d1024 0) (readRegister registers d8)
    $ do
    a <- pciTxDebugStreamIdx
    v <- pciTx
    r <- pciTxReady
    return $ if _axis_valid v && r
            then Just (a, _axis_data v)
            else Nothing

  pciRxDebugMem = blockRam (replicate d1024 0) (readRegister registers d8)
    $ do
    a <- pciRxDebugStreamIdx
    v <- pciRxDebugStream
    return $ (,) <$> Just a <*> unstream Nothing id v

  (pciTx, twReady, twNewPacket) =
    transactionWriter (requester, tlpTx, pciTxReady, txBuffers)

  (registers, spiTx) =
    deviceRegisters
        (spiEnabled, spiByte)
        (\x y -> update
          <$> selectedBuffer
          <*> readStream
          <*> searchStream
          <*> ( CoreStats
                <$> requester
                <*> txBuffers
                <*> twReady
                <*> (unpack <$> txErrorDrop_)
                <*> twNewPacket
                <*> pciTxReady
                <*> (isJust <$> triggerPcieRead)
                <*> (isJust <$> triggerPcieSearch)
                <*> (_axis_valid <$> pciRx .&&. pciRxDebugStart)
              )
          <*> x
          <*> y
        )
        registerPerms

  triggerPcieRead = trigger registers d10 d9 $ do
    addr0 <- at d0 registers
    addr1 <- at d1 registers
    return (addr1 ++# slice d31 d2 addr0, 512)

  triggerPcieSearch = trigger registers d15 d14 $ do
    addr0     <- at d0 registers
    addr1     <- at d1 registers
    len       <- at d3 registers
    searchTy  <- at d18 registers
    searchVal <- at d19 registers
    return ((addr1 ++# slice d31 d2 addr0, resize len), toSearch searchTy searchVal)

  triggerPcieWrite = do
    t     <- at d2 registers
    addr0 <- at d0 registers
    addr1 <- at d1 registers
    val0  <- at d4 registers
    val1  <- at d5 registers
    return $ case lsb t of
             1 -> Just $ WriteTx (addr1 ++# addr0) (val1 ++# val0) 0
             _ -> Nothing

  selectedBuffer = do
    selected <- at d6 registers
    rb <- resultBuffer registers d12 (unstream Nothing id <$> readStream)
    sb <- resultBuffer registers d17 (unstream Nothing id <$> searchStream)
    rx <- pciRxDebugMem
    tx <- pciTxDebugMem
    return $ case selected of
               1 -> sb
               2 -> rx
               3 -> tx
               _ -> rb

  bufferStream :: (NFDataX a) => Signal clk (Stream Failed a) -> Signal clk (Stream Failed a)
  bufferStream = register (Done False)

  tagStream t trig
    = first (realignWords . bufferStream)
    . filterTag t
    . (pciRxStream, trig,)

  readPipe
    = tagStream 31 triggerPcieRead
  searchPipe
    = first (bufferStream . curry search (snd <$$> triggerPcieSearch))
    . tagStream 1 (fst <$$> triggerPcieSearch)

  (searchStream, readStream, tlpTx) =
      ( found, bytes
      , mux hasTx1 tx1
      $ mux hasTx2 tx2 tx3)
   where
    (found, tx1) = searchPipe twReady
    hasTx1 = fmap isJust tx1
    (bytes,  tx2) = readPipe (twReady .&&. fmap not hasTx1)
    hasTx2 = fmap isJust tx2
    (tx3, _) = txFifo triggerPcieWrite (twReady .&&. fmap not hasTx1 .&&. fmap not hasTx2)

  pending = view axis_valid <$> pciTx

board
  :: "sys_clk_p"     ::: Clock ExtClk
  -> "sys_clk_n"     ::: Clock ExtClk
  -> "sys_rst_n"     ::: Reset ExtClk
  -> "spi"           ::: Signal Sys SpiI
  -> "pcie_mgt_rx"   ::: Signal ExtClk (Diff Bit)
  -> ( "clkreq_l"    ::: Signal ExtClk Bit
     , "spi_miso"    ::: Signal Sys Bit
     , "pcie_mgt_tx" ::: Signal ExtClk (Diff Bit)
     , "status_leds" ::: Signal Sys (Bit,Bit,Bit)
     )
board sys_clk_p sys_clk_n sys_rst_n spi pcieRx
  =
  ( clkreq_l
  , spi_miso
  , bundle (bitCoerce <$> _pci_exp_txp pcie, bitCoerce <$> _pci_exp_txn pcie)
  , pure (low,low,low)
  )
 where
  (spi_miso, rxReady, tx, pending) =
    withClockResetEnable @Sys sysclk sysrst sysen
                $ dmaCore spi rx (bus, device, func) txReady txBuffers txErrDrop

  extClk = _O $ xilinxDiff (XilinxDiffI sys_clk_p sys_clk_n)

  pcie = xilinxPcie
     (xilinxPcieI extClk)
      { _sys_rst_n = bitCoerce <$> unsafeFromReset sys_rst_n
      , _pci_exp_rxp = fmap bitCoerce (fst <$> pcieRx)
      , _pci_exp_rxn = fmap bitCoerce (snd <$> pcieRx)
      , _s_axis_tx_tdata = view axis_data <$> tx
      , _s_axis_tx_tkeep = view axis_keep <$> tx
      , _s_axis_tx_tlast =  fmap pack (boolToBit . view axis_last <$> tx)
      , _s_axis_tx_tuser = view axis_user <$> tx
      , _s_axis_tx_tvalid = fmap pack (boolToBit . view axis_valid <$> tx)
      , _m_axis_rx_tready = fmap pack (boolToBit <$> rxReady)
      , _tx_cfg_gnt = 1
      , _rx_np_req = 1
      , _rx_np_ok = 1
      , _cfg_trn_pending = pack .boolToBit <$> pending
      }

  (rx, txReady, bus, device, func, sysclk, sysrst, sysen, txBuffers, txErrDrop)
    = ( AxiSimpleStream
          <$> fmap bitCoerce (_m_axis_rx_tvalid pcie)
          <*> _m_axis_rx_tdata pcie
          <*> fmap bitCoerce (_m_axis_rx_tlast pcie)
          <*> _m_axis_rx_tkeep pcie
          <*> _m_axis_rx_tuser pcie
      , bitToBool . unpack <$> _s_axis_tx_tready pcie
      , _cfg_bus_number pcie
      , _cfg_device_number pcie
      , _cfg_function_number pcie
      , _user_clk_out pcie
      , unsafeFromHighPolarity $ fmap bitCoerce (_user_reset_out pcie)
      , toEnable $ fmap bitCoerce (_user_lnk_up pcie)
      , _tx_buf_av pcie
      , _tx_err_drop pcie
      )

  clkreq_l = pure low

makeTopEntity 'board
