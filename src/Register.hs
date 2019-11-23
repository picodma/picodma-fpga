{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE DeriveFunctor       #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoStarIsType        #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE StandaloneDeriving  #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE ViewPatterns        #-}

module Register
  (
    RegisterHandler
  , RegisterHandler'
  , deviceRegisters
  , Permission(..)
  , PermissionMap
  , RegisterSlot(..)
  ) where

import           Dma.Prelude

data Permission
  = Permission
  { canWrite :: Bool
  , canRead :: Bool
  } deriving (Generic, ShowX, NFDataX)

instance Default Permission where
  def = Permission False False

type PermissionMap n = Vec n Permission

checkWriteRead :: MonadPlus m => Bool -> Permission -> m ()
checkWriteRead True  (Permission True _   ) = return ()
checkWriteRead False (Permission _    True) = return ()
checkWriteRead _     (Permission _    _   ) = mzero

data RegisterSlot n a
  = RegisterSlot (Index n) a
  deriving (Functor, Generic, NFDataX, ShowX)

byteToRegisterSlot
  :: forall n a
   . (KnownNat n, n <= 127, 1 <= n)
  => PermissionMap n
  -> U8
  -> (Bool -> a)
  -> Maybe (RegisterSlot n a)
byteToRegisterSlot perms b f =
  let isWrite = bitToBool (msb b)
      check   = checkWriteRead isWrite
      idx     = unpack (resize $ slice d6 d0 b)
  in RegisterSlot idx (f isWrite) <$ (perms ^? ix idx >>= check)

type Indexer = Index (2^16)
data Stage = InitRead | InitWrite | Read Indexer | Write Indexer U8
  deriving (Generic, NFDataX, ShowX)

makePrisms ''Stage

type Decoded n = Maybe (RegisterSlot n (Indexer, Maybe U8))
type XS n = Maybe (RegisterSlot n Stage)

toDecoded :: XS n -> Decoded n
toDecoded Nothing = Nothing
toDecoded (Just (RegisterSlot n InitRead)) = Just (RegisterSlot n (0, Nothing))
toDecoded (Just (RegisterSlot _ InitWrite)) = Nothing
toDecoded (Just (RegisterSlot n (Read i))) = Just (RegisterSlot n (i, Nothing))
toDecoded (Just (RegisterSlot n (Write i w))) = Just (RegisterSlot n (i, Just w))

decoderT
  :: forall n
   . (KnownNat n, n <= 127, 1 <= n)
  => PermissionMap n
  -> XS n
  -> (Bool, Maybe U8)
  -> (XS n, Decoded n)
decoderT _ _ (False, _      ) = (def, def)
decoderT _ s (True , Nothing) = (s, toDecoded s)

decoderT m Nothing (True, Just b) = (byteToRegisterSlot m b build, def)
 where
  build :: Bool -> Stage
  build True = InitWrite
  build False = InitRead

decoderT _ (Just c) (True, Just b) =
  ( Just
      $ c
      & mapped . _Read %~ satAdd SatBound 1
      & mapped . _Write %~ (\(i,_) -> (satAdd SatBound 1 i, b))
      & mapped %~ \case
        InitRead  -> Read 1
        InitWrite -> Write 0 b
        x -> x
  , toDecoded $ Just c)

decoder
  :: forall domain n
   . (HiddenClockResetEnable domain, KnownNat n, n <= 127, 1 <= n)
  => PermissionMap n
  -> Signal domain (Bool, Maybe U8)
  -> Signal domain (Decoded n)
decoder m = mealy (decoderT m) def

readDeviceRegistersT
  :: forall n
  . ( KnownNat n)
  => Decoded n
  -> Vec n U32
  -> U8
readDeviceRegistersT Nothing _ = 0
readDeviceRegistersT (Just (RegisterSlot i (idx, _))) vs =
  let el = vs ^?! ix i
      lo = slice d1 d0 (pack idx :: BitVector 16)
  in  flip (!!) lo . reverse . bitCoerce @_ @(Vec 4 U8) $ el

writeDeviceRegistersT
  :: forall n i i1
  . ( KnownNat n)
  => Decoded n
  -> Vec n U32
  -> Vec n U32
writeDeviceRegistersT Nothing = id
writeDeviceRegistersT (Just command) = imap (write command)
 where
  write :: RegisterSlot n (Indexer, Maybe U8) -> Index n -> U32 -> U32
  write (RegisterSlot i (idx, Just x)) j y | i==j =
    let lo = slice d1 d0 (pack idx :: BitVector 16)
    in  bitCoerceMap @(Vec 4 U8) (reverse . replace' lo x . reverse) y
  write _ _ x = x

  replace' :: BitVector 2 -> U8 -> Vec 4 U8 -> Vec 4 U8
  replace' 0 x (_:>b:>c:>d:>Nil) = (x:>b:>c:>d:>Nil)
  replace' 1 x (a:>_:>c:>d:>Nil) = (a:>x:>c:>d:>Nil)
  replace' 2 x (a:>b:>_:>d:>Nil) = (a:>b:>x:>d:>Nil)
  replace' 3 x (a:>b:>c:>_:>Nil) = (a:>b:>c:>x:>Nil)

type RegisterHandler domain n
  = Signal domain (Maybe (RegisterSlot n (Indexer)))
    -> Signal domain (Vec n U32)
    -> Signal domain (Vec n U32)

type RegisterHandler' n
  = Maybe (RegisterSlot n (Indexer))
    -> Vec n U32
    -> Vec n U32

deviceRegisters
  :: forall domain n
  .  ( KnownNat n
     , n <= 127, 1 <= n
     , HiddenClockResetEnable domain)
  => (Signal domain Bool, Signal domain (Maybe U8))
  -> RegisterHandler domain n
  -> Vec n Permission
  -> (Vec n (Signal domain U32), Signal domain U8)
deviceRegisters spi update permissions = (unbundle registers, read)
 where
  cmd = decoder permissions $ bundle spi
  cmd' = cmd <&> _Just . mapped %~ fst
  registers = register (repeat 0) write
  read = readDeviceRegistersT <$> cmd <*> registers
  write = writeDeviceRegistersT <$> cmd <*> update cmd' registers
