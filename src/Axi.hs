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
{-# LANGUAGE DeriveLift            #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MagicHash             #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE NoStarIsType          #-}
{-# LANGUAGE NumericUnderscores    #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TemplateHaskellQuotes #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module Axi where

import           Dma.Prelude

data AxiSimpleStream n m
  = AxiSimpleStream
  { _axis_valid :: "tvalid" ::: Bool
  , _axis_data  :: "tdata"  ::: BitVector (8*n)
  , _axis_last  :: "tlast"  ::: Bool
  , _axis_keep  :: "tkeep"  ::: BitVector n
  , _axis_user  :: "tuser"  ::: BitVector m
  } deriving (Generic, NFDataX, ShowX, Eq)

makeLenses ''AxiSimpleStream

instance (KnownNat n, KnownNat m) => Default (AxiSimpleStream n m) where
  def = AxiSimpleStream False 0 False 0 0

mkAxisWrite :: (KnownNat n, KnownNat m) => BitVector (8*n) -> AxiSimpleStream n m
mkAxisWrite data_ = def
                  & axis_valid .~ True
                  & axis_keep .~ complement 0
                  & axis_data .~ data_

realignAxis
  :: (HiddenClockResetEnable domain)
  => Unbundled domain (Bool, AxiSimpleStream 8 m)
  -> Signal domain (Stream () (Maybe U64))
realignAxis (flush,stream) = realignWords $ mkStream <$> flush <*> stream
 where
  mkStream True _ = Done ()
  mkStream False a | not (_axis_valid a) = Item Zero
  mkStream False a = Item
    $ uncurry (case _axis_keep a of
        0xFF -> Two
        0xF -> const One
        ) $ split $ _axis_data a

