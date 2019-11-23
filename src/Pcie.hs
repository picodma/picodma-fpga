{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver    #-}

{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE TypeApplications #-}

module Pcie where

import Dma.Prelude

newtype Address (alignment :: Nat)
  = Address (BitVector (64 - alignment))

data Addressable (alignment :: Nat) a
  = Addressable (Address alignment) a
  deriving Functor

address
  :: forall align1 align2 .
  ( KnownNat align1
  , KnownNat align2
  , align1 <= 64
  )
  => Address align1
  -> Address align2
address (Address a) = Address $ slice d63 (SNat @align2) full
 where
  full = a ++# 0 :: BitVector 64

-- addressable :: f (Addressable a) -> Addressable (f a)

