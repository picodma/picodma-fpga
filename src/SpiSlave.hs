{-# LANGUAGE LambdaCase          #-}

module SpiSlave
  ( spiSlave
  , SpiI
  )
  where

import           Dma.Prelude
import           Control.Lens

type SpiI = ("clock" ::: Bit, "select" ::: Bool, "mosi" ::: Bit)

data SpiState
  = SpiState
  { _recv    :: U8
  , _recvIdx :: BitVector 3
  , _sendIdx :: BitVector 3
  , _clkBuf  :: BitVector 2
  , _miso    :: Bit
  , _rxValid :: Bool
  } deriving (ShowX, Eq, Generic, NFDataX)

instance Bundle SpiState

makeLenses ''SpiState

receiveByte :: SpiState -> Maybe U8
receiveByte s = toMaybe (s ^. rxValid) (s ^. recv)

spiSlaveT :: ((Bit, Bool, Bit), U8)
          -> State SpiState (Bool, Maybe U8, Bit)
spiSlaveT ((clock, slaveSelect, mosi), next) = do
  (rising, falling) <- uses clkBuf $ \case
        0b01 -> (True, False)
        0b10 -> (False, True)
        _    -> (False, False)
  clkBuf %= (#<<+ clock)

  rxValid .= False

  if not slaveSelect then do
    recvIdx .= 0
    sendIdx .= 0
    recv .= 0
    clkBuf .= 0
    miso <~ boolToBit . testBit next . (7 - ) . fromEnum <$> use sendIdx
  else do
    when falling $ do
      sendIdx += 1
      miso <~ boolToBit . testBit next . (7 - ) . fromEnum <$> use sendIdx
    when rising $ do
      recv %= (#<<+ mosi)
      recvIdx' <- recvIdx <+= 1
      when (recvIdx' == 0) (rxValid .= True)

  get >>= \s -> return (slaveSelect, receiveByte s, _miso s)

{-# NOINLINE spiSlave #-}
spiSlave :: (HiddenClockResetEnable sys)
         => Unbundled sys ((Bit, Bool, Bit), U8)
         -> Unbundled sys (Bool, Maybe U8, Bit)
spiSlave
  = mealyStateB spiSlaveT (SpiState 0 0 0 0 0b11 False)
