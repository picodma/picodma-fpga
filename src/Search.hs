{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ApplicativeDo       #-}
{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE RankNTypes          #-}

module Search where

import           Dma.Prelude

data SearchTarget = None | S16 U16 | S32 U32
  deriving (Generic, Eq, ShowX, NFDataX)
type SearchState = (SearchTarget, BitVector 24, BitVector 32, Bool)
type SearchResult = BitVector 32

toSearch :: U32 -> U32 -> SearchTarget
toSearch 0 _ = None
toSearch 1 v = S16 (resize v)
toSearch 2 v = S32 v
toSearch _ _ = None

searchT
  :: SearchState
  -> (Maybe SearchTarget, Stream r (Maybe U64))
  -> (SearchState, Stream r (Maybe SearchResult))
searchT _ (Just i@S32{}, _) = ((i, 0, -3, True), Item Nothing)
searchT _ (Just i@S16{}, _) = ((i, 0, -1, True), Item Nothing)

searchT s (Nothing, Done r) = (s, Done r)

searchT s (Nothing, Item Nothing) = (s, Item Nothing)
searchT s (Nothing, _) | (None, _, _, _) <- s = (s, Item Nothing)

searchT (target, buff, offset, isFirst) (Nothing, Item (Just x))
  = ((target,slice d63 d40 x,offset+8,False), Item m)
 where
  m = collate
    $ imap (\i -> match target i . pack)
    $ reverse
    $ windows1d d4 $ bitCoerce @_ @(Vec _ U8) $ x ++# buff
  match (S32 t) i v | t == v && not (isFirst && i < 3) = Just i
  match (S16 t) i (slice d31 d16 -> v) | t == v && not (isFirst && i == 0) = Just i
  match _ _ _ = Nothing
  collate = fmap ((+) offset . resize . pack) . fold (<|>)

search
  :: (HiddenClockResetEnable domain)
  => Unbundled domain (Maybe SearchTarget, Stream r (Maybe U64))
  -> Signal domain (Stream r (Maybe SearchResult))
search = mealy searchT (None, 0, 0, False) . bundle
