{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE ApplicativeDo         #-}
{-# LANGUAGE BinaryLiterals        #-}
{-# LANGUAGE BlockArguments        #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
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
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module Clash.Minilude
  ( -- * Creating synchronous sequential circuits
    mealy
  , mealyB
  , mealyState
  , mealyStateB
  , (<^>)
  , registerB
  , module Clash.Signal
  , module Clash.Signal.Delayed
    -- ** Datatypes
    -- *** Bit vectors
  , module Clash.Sized.BitVector
  , module Clash.Prelude.BitIndex
  , module Clash.Prelude.BitReduction
    -- *** Arbitrary-width numbers
  , module Clash.Sized.Signed
  , module Clash.Sized.Unsigned
  , module Clash.Sized.Index
    -- *** Fixed size vectors
  , module Clash.Sized.Vector
    -- ** Type-level natural numbers
  , module GHC.TypeLits
  , module GHC.TypeLits.Extra
  , module Clash.Promoted.Nat
  , module Clash.Promoted.Nat.Literals
  , module Clash.Promoted.Nat.TH
    -- ** Type-level strings
  , module Clash.Promoted.Symbol
    -- ** Type classes
    -- *** Clash
  -- , module Clash.Class.AutoReg
  , autoReg, deriveAutoReg
  , module Clash.Class.BitPack
  , module Clash.Class.Exp
  , module Clash.Class.Num
  , module Clash.Class.Resize
    -- ** Exceptions
  , module Clash.XException
    -- ** Named types
  , module Clash.NamedTypes
  , undefined
  )
  where

import           Clash.Class.BitPack
import           Clash.Class.Exp
import           Clash.Class.Num
import           Clash.Class.Resize
import           Clash.NamedTypes
import           Clash.Prelude.BitIndex
import           Clash.Prelude.BitReduction
import           Clash.Prelude.Safe
import           Clash.Promoted.Nat
import           Clash.Promoted.Nat.TH
import           Clash.Promoted.Nat.Literals
import           Clash.Promoted.Symbol
import           Clash.Sized.BitVector
import           Clash.Sized.Index
import           Clash.Sized.Signed
import           Clash.Sized.Unsigned
import           Clash.Sized.Vector
import           Clash.Signal
import           Clash.Signal.Delayed
import           Clash.XException

import           Clash.Prelude
import           GHC.TypeLits
import           GHC.TypeLits.Extra

import           Control.Monad.State
import           Data.Tuple                     ( swap )

mealyState
  :: (HiddenClockResetEnable domain, NFDataX s)
  => (i -> State s o)
  -> s
  -> (Signal domain i -> Signal domain o)
mealyState f = mealy step
  where
    step s x = swap $ runState (f x) s

mealyStateB
  :: (HiddenClockResetEnable domain, NFDataX s, Bundle i, Bundle o)
  => (i -> State s o)
  -> s
  -> Unbundled domain i
  -> Unbundled domain o
mealyStateB f initial = step <^> initial
  where
    step s x = swap $ runState (f x) s

