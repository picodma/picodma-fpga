{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE ApplicativeDo         #-}
{-# LANGUAGE BinaryLiterals        #-}
{-# LANGUAGE BlockArguments        #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE NoStarIsType          #-}
{-# LANGUAGE NumericUnderscores    #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskellQuotes #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module Dma.Prelude
  (
    module Clash.Minilude
  , module Control.Applicative
  , module Data.Bifunctor
  , module Data.Maybe
  , module Data.Bits
  , module Control.Lens
  , module Clash.Prelude

  , module Control.Monad.State

  , U8, U16, U32 ,U64
  , Diff
  , (<$$>)
  , (.++#.)
  , (#<<+)
  , ite
  , bool
  , toMaybe
  , unpackMaybe
  , reduce
  , DoublePort(..)
  , portCount
  , Stream (..)
  , unstream
  , undone
  , streamCount
  , realignWordsT
  , realignWords

  -- , String, Show (show)
  )
  where

import           Prelude
import           Clash.Minilude
import           Clash.Prelude hiding (String, Show, read)

import           Control.Applicative
import           Data.Bifunctor
import           Control.Monad.State hiding (lift)
import           Data.Bits
import           Data.Maybe
import           Control.Lens                   ( makeLenses
                                                , makePrisms
                                                , (^.)
                                                , (^?)
                                                , (^?!)
                                                , (.~)
                                                , (%~)
                                                , (.=)
                                                , (+=)
                                                , (%=)
                                                , _1, _2, _3, _4
                                                , _Just
                                                , (&)
                                                , (<&>)
                                                , ix
                                                , mapped
                                                , use, uses
                                                , zoom
                                                , view
                                                )

import           Clash.Sized.Internal.Index     ( fromSNat )

type U8  = BitVector 8
type U16 = BitVector 16
type U32 = BitVector 32
type U64 = BitVector 64

type Diff a = ("p" ::: a, "n" ::: a)

infixl 4 <$$>

(<$$>) :: (Functor f, Functor g) => (a -> b) -> f (g a) -> f (g b)
(<$$>) = fmap . fmap

(.++#.)
  :: (KnownNat n, KnownNat m, Applicative f)
  => f (BitVector n)
  -> f (BitVector m)
  -> f (BitVector (n+m))
(.++#.) = liftA2 (++#)

ite i t e = if i then t else e
bool f t x = ite x t f

toMaybe :: Bool -> a -> Maybe a
toMaybe False _ = Nothing
toMaybe True  x = Just x

unpackMaybe :: (NFDataX a) => Maybe a -> (Bool, a)
unpackMaybe (Just a) = (True, a)
unpackMaybe _        = (False, deepErrorX "NFDataX unpackMaybe!")

infixl 4 #<<+
(#<<+) :: (KnownNat n) => BitVector n -> Bit -> BitVector n
xs #<<+ b = v2bv . flip (<<+) b $ bv2v xs
{-# INLINE (#<<+) #-}

reduce
  :: forall n m i. (KnownNat n, KnownNat m)
  => BitVector (n+m+1) -> BitVector (n+1)
reduce v =
  let lo = slice (SNat @n) d0 v                :: BitVector (n+1)
      hi = slice (SNat @(m+n)) (SNat @(n+1)) v :: BitVector m
  in  if reduceOr hi == high then maxBound else lo

data DoublePort a
  = Zero
  | One a
  | Two a a
  deriving (Eq, Generic, ShowX, NFDataX)

portCount :: Num b => DoublePort a -> b
portCount Zero = 0
portCount One{} = 1
portCount Two{} = 2

data Stream r a
  = Done r
  | Item a
  deriving (Eq, Functor, Generic, ShowX, NFDataX)

unstream :: b -> (a -> b) -> Stream r a -> b
unstream b _ (Done _) = b
unstream _ f (Item a) = f a

undone :: b -> (a -> b) -> Stream a x -> b
undone _ f (Done r) = f r
undone b _ (Item _) = b

streamCount :: (Num a) => a -> Stream r (Maybe b) -> a
streamCount v = maybe v (const $ v + 1) . unstream Nothing id

realignWordsT
  :: Maybe U32
  -> Stream r (DoublePort U32)
  -> (Maybe U32, Stream r (Maybe U64))

realignWordsT Nothing  (Done r)         = (Nothing, Done r)
realignWordsT a        (Done _)         = (Nothing, Item $ fmap resize a)
realignWordsT (Just a) (Item (Two b c)) = (Just c,  Item $ Just $ b ++# a)
realignWordsT Nothing  (Item (Two b c)) = (Nothing, Item $ Just $ c ++# b)
realignWordsT (Just a) (Item (One b  )) = (Nothing, Item $ Just $ b ++# a)
realignWordsT Nothing  (Item (One b  )) = (Just b,  Item Nothing)
realignWordsT a        (Item Zero     ) = (a, Item Nothing)

realignWords
  :: (HiddenClockResetEnable domain)
  => Signal domain (Stream r (DoublePort U32))
  -> Signal domain (Stream r (Maybe U64))
realignWords = mealy realignWordsT def
