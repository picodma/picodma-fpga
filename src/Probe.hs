{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ApplicativeDo       #-}
{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoStarIsType        #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE ViewPatterns        #-}

module Probe
  (
  )
  where

import           Prelude
import           Data.Default.Class
import           Control.Lens                   ( view
                                                , _3
                                                )

import           Tlp


-- (Addr, stride)
type ProbeRequest = (BitVector 64, BitVector 40)

-- type Failed = Bool

-- data ReassemblyState
--   = ReassemblyState
--   { _address :: BitVector 62
--   , _remaining :: BitVector 28
--   , _timer :: BitVector 20
--   , _bufferedTx :: Maybe Tx
--   , _failed :: Bool
--   } deriving (Eq, ShowX, Generic, NFDataX)

-- instance Default ReassemblyState where
--   def = ReassemblyState 0 0 0 Nothing False

-- reassemblyState (addr, len) tx = ReassemblyState addr len 0 tx False
-- done (_, len) = len == 0

-- nextRequest :: ReassemblyState -> BitVector 2 -> StreamRequest
-- nextRequest (ReassemblyState addr rem _ _ _) l =
--   ( truncateB $ add addr l
--   , truncateB $ sub rem l )

-- mkTlp tag (addr,len) = ReadTx (addr ++# 0) (nextLength addr len) tag

-- nextLength :: BitVector 62 -> BitVector 28 -> BitVector 10
-- nextLength addr l =
--   let loaddr    = resize addr :: BitVector 10
--       pageBound = 1 + complement loaddr
--   in  if loaddr == 0
--         then reduce l
--         else minimum (reduce l :> pageBound :> Nil)

-- filterTagT
--   :: Tag
--   -> ReassemblyState
--   -> (Maybe (TlpHeader, DoublePort U32), Maybe StreamRequest, Bool)
--   -> (ReassemblyState, (Stream Failed (DoublePort U32), Maybe Tx))

-- -- Start a new transaction
-- filterTagT tag _ (_, Just r, _) =
--   let tx       = mkTlp tag r
--   in  ( reassemblyState r (Just tx)
--       , (Item Zero, Nothing)
--       )

-- filterTagT _ s@(_remaining -> r) _ | r == 0       = (s, (Done False, Nothing))
-- filterTagT _ s@(_failed -> f) _    | f            = (s, (Done True, Nothing))
-- filterTagT _ (_timer -> t) _       | t == 500_000 = (def { _failed = True }, (Done True, Nothing))

-- -- Relevant packet received
-- filterTagT tag s (Just t, _, _)
--   | t ^. _1 . tlpTag == tag && not (_failed s)
--   = let sanity
--           | t ^. _1 . tlpHeaderPulse
--           = slice d4 d0 (_address s) == slice d6 d2 (t ^. _1 . tlpLowerAddress)
--           | otherwise = True

--         r = nextRequest s (portCount $ t ^. _2)

--         tx
--           | done r                          = Nothing
--           | t ^. _1 . tlpBytesRemaining == 0 = Just (mkTlp tag r)
--           | otherwise                        = Nothing

--     in  if sanity
--           then (reassemblyState r tx, (Item $ t ^. _2, Nothing))
--           else (def {_failed = True}, (Done True, Nothing))

-- filterTagT _ (ReassemblyState addr len t tx False) (view _3 -> txReady) =
--   ( ReassemblyState addr len (t + 1) (tx <* guard (not txReady)) False
--   , (Item Zero, tx)
--   )

-- filterTag
--   :: HiddenClockResetEnable domain
--   => Tag
--   -> Unbundled domain (Maybe (TlpHeader, DoublePort U32), Maybe StreamRequest, Bool)
--   -> Unbundled domain (Stream Failed (DoublePort U32), Maybe Tx)
-- filterTag tag = filterTagT tag <^> def
