{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE ApplicativeDo       #-}
{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE NoStarIsType        #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE ViewPatterns        #-}

module Tlp
  (
    Tag
  , Tx(..)

  , TlpHeader(..)
  , tlpTag
  , tlpLowerAddress
  , tlpBytesRemaining
  , tlpDone
  , tlpStatus
  , tlpHeaderPulse

  , completionStream
  , transactionWriter

  ) where

import           Dma.Prelude

import           Axi

type Tag = BitVector 8
data Tx = ReadTx U64 (BitVector 10) Tag | WriteTx U64 U64 Tag
  deriving (Eq, ShowX, Generic, NFDataX)

-- * Tlp parsing

data TlpHeader
  = TlpHeader
  { _tlpTag            :: Tag
  , _tlpLowerAddress   :: BitVector 7
  , _tlpBytesRemaining :: BitVector 12
  , _tlpDone           :: Bool
  , _tlpStatus         :: BitVector 3
  , _tlpHeaderPulse    :: Bool
  } deriving (Generic, NFDataX, ShowX, Eq, BitPack)

data CompletionStreamState
  = CompletionStreamState
  { _packetIndex :: Index 4
  , _packetHeader :: TlpHeader
  , _packetFlush :: Bool
  } deriving (Generic, NFDataX)

makeLenses ''TlpHeader
makeLenses ''CompletionStreamState

instance Default TlpHeader where
  def = TlpHeader 0 0 0 False 0 False
instance Default CompletionStreamState where
  def = CompletionStreamState 0 def False

data ParseTlpU32 = Flush | Consumed | IsData U32
  deriving (Eq, ShowX, Generic, NFDataX)

getData :: ParseTlpU32 -> Maybe U32
getData (IsData x) = Just x
getData _          = Nothing

parseTlpU32 :: Bool -> U32 -> State CompletionStreamState ParseTlpU32
parseTlpU32 False _     = return Consumed
parseTlpU32 True  data_ = do
  index <- use packetIndex
  packetIndex .= satAdd SatBound index 1
  zoom packetHeader $ case index of
    0 -> do
      let _length = slice d9 d0 data_
          type_  = slice d28 d24 data_

      if type_ /= 0xa then return Flush else return Consumed

    1 -> do
      let byteCount = slice d11 d0 data_
          status_   = slice d15 d13 data_

      tlpBytesRemaining .= byteCount

      tlpStatus .= status_
      if status_ /= 0 then return Flush else return Consumed

    2 -> do
      let tag     = slice d15 d8 data_
      let lowAddr = slice d6 d0 data_

      tlpLowerAddress .= lowAddr
      tlpTag .= tag
      tlpHeaderPulse .= True

      return Consumed
    _ -> do
      tlpLowerAddress += 4
      tlpBytesRemaining %= flip (satSub SatBound) 4
      return $ IsData (bitCoerceMap @(Vec 4 U8) reverse data_)

completionStreamT
  :: AxiSimpleStream 8 n
  -> State CompletionStreamState (Maybe (TlpHeader, DoublePort U32))
completionStreamT (_axis_valid -> False) = return Nothing
completionStreamT rx                     = do
  let data2En = case rx ^. axis_keep of
        0x0F -> False
        0xFF -> True
        _    -> errorX "Xilinx PCIe core violation"
  let (data2, data1) = split $ rx ^. axis_data

  p1 <- parseTlpU32 True data1
  p2 <- parseTlpU32 data2En data2

  when (p1 == Flush || p2 == Flush) (packetFlush .= True)
  zoom packetHeader $ tlpHeaderPulse .= False
  flushing <- use packetFlush
  index    <- use packetIndex

  if rx ^. axis_last
    then do
      packetFlush .= False
      zoom packetHeader $ tlpDone .= True
      packetIndex .= 0
    else zoom packetHeader $ tlpDone .= False

  if flushing
    then return Nothing
    else do
      header' <- use packetHeader
      let data_ = case (getData p1, getData p2) of
            (Just x1, Just x2) -> Two x1 x2
            (Nothing, Just x2) -> One x2
            (Just x1, Nothing) -> One x1
            (_      , _      ) -> Zero
      return $ if index == 3 then Just (header', data_) else Nothing

-- {-# NOINLINE completionStream #-}
completionStream
  :: (HiddenClockResetEnable dom)
  => Signal dom (AxiSimpleStream 8 n)
  -> Signal dom (Maybe (TlpHeader, DoublePort U32))
completionStream = mealyState completionStreamT def

--- * Transaction writer

type TransactionWriterState = (Index 4, Maybe Tx)

txLen :: Tx -> BitVector 10
txLen (ReadTx  _ len _) = len
txLen WriteTx {} = 2

txFlag :: Tx -> BitVector 2
txFlag ReadTx {} = 0b00
txFlag WriteTx {} = 0b01

txAddr :: Tx -> BitVector 64
txAddr (ReadTx  x _ _) = x
txAddr (WriteTx x _ _) = x

tx32Bit :: Tx -> Bool
tx32Bit x = 0x1_0000_0000 > txAddr x

txType :: Tx -> BitVector 3
txType t | tx32Bit t = txFlag t ++# 0b0
         | otherwise = txFlag t ++# 0b1

txTag :: Tx -> Tag
txTag (ReadTx  _ _ tag) = tag
txTag (WriteTx _ _ tag) = tag

transactionWriterT
  :: KnownNat n
  => TransactionWriterState
  -> (BitVector 16, Maybe Tx, Bool, BitVector 6)
  -> (TransactionWriterState, (AxiSimpleStream 8 n, Bool, Bool))

transactionWriterT (0, tx) (_, _, _, downStreamBuffers)
  | downStreamBuffers < 3 = ((0,tx), (def, not (isJust tx), False))
transactionWriterT (i, Just tx) (requester, nxTx, pciReady, _buffers)
  | i == fromSNat d0
  = let w1 :: BitVector 32 = txType tx ++# 0 ++# txLen tx
        w2 :: BitVector 32 = requester ++# txTag tx ++# (if txLen tx > 1 then 0xFF else 0x0F)
    in  (s', (mkAxisWrite (w2 ++# w1), False, pciReady))
  | i == fromSNat d1
  = case tx of
    ReadTx {} ->
      let w | tx32Bit tx = mkAxisWrite (0 ++# lo) & axis_keep .~ 0xF
            | otherwise  = mkAxisWrite (lo ++# hi)
      in  (z, (w & axis_last .~ True, pciReady, False))
    WriteTx _ v _ ->
      let (_, vlo) = split v
          w | tx32Bit tx = rev vlo ++# lo
            | otherwise  = lo ++# hi
      in  (s', (mkAxisWrite w, False, False))
  | i == fromSNat d2
  = case tx of
    ReadTx {} -> errorX "Reached invalid state for read transaction!"
    WriteTx _ v _ ->
      let (vhi, vlo) = split v
          w | tx32Bit tx = mkAxisWrite (0 ++# rev vhi) & axis_keep .~ 0xF
            | otherwise  = mkAxisWrite (rev vhi ++# rev vlo)
      in  (z, (w & axis_last .~ True, pciReady, False))
 where
  z                        = if pciReady then (0, nxTx) else (i, Just tx)
  s'                       = if pciReady then (i + 1, Just tx) else (i, Just tx)

  mask                     = 0xFFFF_FFFC
  (hi :: BitVector 32, lo) = second (mask .&.) $ split (txAddr tx)
  rev                      = pack . reverse @4 @U8 . unpack :: U32 -> U32

transactionWriterT (_, _) (_, nxTx, _, _) = ((0, nxTx), (def, True, False))

-- {-# NOINLINE transactionWriter #-}
transactionWriter
  :: (KnownNat n, HiddenClockResetEnable dom)
  => Unbundled dom (BitVector 16, Maybe Tx, Bool, BitVector 6)
  -> Unbundled dom (AxiSimpleStream 8 n, Bool, Bool)
transactionWriter = transactionWriterT <^> def
