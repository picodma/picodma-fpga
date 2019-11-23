module Main where

import Prelude

import           Test.Tasty              hiding ( assertEqual
                                                , assert
                                                )
import           Test.Tasty.HUnit        hiding ( assertEqual
                                                , assert
                                                )

import qualified Test.DmaCore as DmaCore
-- import qualified Test.Tlp as Tlp
-- import qualified Test.Reassembly as Reassembly

main :: IO ()
main = defaultMain $
  testGroup "Expected successes"
  -- [ Tlp.tests
  -- , Reassembly.tests
  [ DmaCore.tests
  ]
