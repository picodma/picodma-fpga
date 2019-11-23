{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# LANGUAGE ApplicativeDo         #-}
{-# LANGUAGE BlockArguments        #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE NumericUnderscores    #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecursiveDo           #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE ViewPatterns          #-}

{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE UndecidableInstances  #-}

module Test.DmaCore where

import Dma.Prelude
import qualified Data.Foldable                 as P
import qualified Data.List                 as P
import           Clash.Prelude           hiding ( fifoDF )
import qualified Clash.Prelude.Testbench       as TB
import qualified Clash.Explicit.Testbench       as TBE
import           Control.Lens            hiding ( index
                                                , Index
                                                , (:>)
                                                , (:<)
                                                , elements
                                                , at
                                                )
import           Control.Monad
import           Clash.Annotations.TH

import           Axi
import           SpiSlave
import           Tlp
import           Register
import           Top

import           Test.Test
import           Test.Tasty              hiding ( assertEqual
                                                , assert
                                                )
import           Test.Tasty.HUnit        hiding ( assertEqual
                                                , assert
                                                )

type DmaCoreI =
     ((Bit, Bool, Bit), AxiSimpleStream 8 22, (U8, BitVector 5, BitVector 3), Bool, BitVector 6)
type DmaCoreO = (Bit, Bool, AxiSimpleStream 8 4, Bool)
type DmaCoreTestM a
  = TestM
     DmaCoreI
     DmaCoreO
     a

onlySpi :: (Bit, Bool, Bit) -> DmaCoreI
onlySpi x = (x, def, (0xFF,0,0), True, complement 0)

onlyAxi :: AxiSimpleStream 8 22 -> DmaCoreI
onlyAxi x = ((0,False,0), x, (0xFF,0,0), True, complement 0)

silent = onlySpi (0, False, 0)

writeSpiBit :: Bit -> DmaCoreTestM DmaCoreO
writeSpiBit b = do
  tick $ onlySpi (0, True, b)
  tick $ onlySpi (0, True, b)
  tick $ onlySpi (0, True, b)
  o <- tick $ onlySpi (1, True, b)
  tick $ onlySpi (1, True, b)
  tick $ onlySpi (1, True, b)
  return o

writeSpiByte :: U8 -> DmaCoreTestM (Vec 8 DmaCoreO)
writeSpiByte b = traverse writeSpiBit (bv2v b)

writeSpiV :: (KnownNat n, 1 <= n) => Vec n U8 -> DmaCoreTestM (Vec n (Vec 8 DmaCoreO))
writeSpiV = traverse writeSpiByte

rwSpi :: (KnownNat n, 1 <= n) => U8 -> Vec n U8 -> DmaCoreTestM (Vec n U8)
rwSpi c v = do
  tick silent
  tick silent
  tick silent
  writeSpiByte c
  r <- writeSpiV v
  tick silent
  return $ fmap (v2bv . fmap (view _1)) r

testIdx :: DmaCoreTestM ()
testIdx =
  rwSpi 13 (replicate d8 0)
    >>= assertEqual "idx" $(listToVecTH [0,1::U8,2,3,4,5,6,7])

testWrite :: DmaCoreTestM ()
testWrite = do
  rwSpi 0 (replicate d4 0)
    >>= assertEqual "read #0 empty" $(listToVecTH [0::U8,0,0,0])
  rwSpi 1 (replicate d4 0)
    >>= assertEqual "read #1 empty" $(listToVecTH [0::U8,0,0,0])
  rwSpi 3 (replicate d4 0)
    >>= assertEqual "read #3 empty" $(listToVecTH [0::U8,0,0,0])
  rwSpi 128 $(listToVecTH [1::U8,0,2,0])
    >>= assertEqual "" $(listToVecTH [0::U8,1,0,2])
  rwSpi 129 $(listToVecTH [1::U8,9,8,7])
    >>= assertEqual "" $(listToVecTH [0::U8,1,9,8])
  rwSpi 131 $(listToVecTH [9::U8,10,11,12])
    >>= assertEqual "" $(listToVecTH [0::U8,9,10,11])
  rwSpi 0 (replicate d4 0)
    >>= assertEqual "read back #0" $(listToVecTH [1::U8,0,2,0])
  rwSpi 1 (replicate d4 0)
    >>= assertEqual "read back #1" $(listToVecTH [1::U8,9,8,7])
  rwSpi 3 (replicate d4 0)
    >>= assertEqual "read back #3" $(listToVecTH [9::U8,10,11,12])
    --
  return ()

testPcieReadStatus :: DmaCoreTestM ()
testPcieReadStatus = do
  rwSpi 138 (0:>0:>0:>1:>Nil)
  findAxiWrite >>= trace . showX
  findFailed
 where
  findAxiWrite = mdo
    x <- tick silent
    if x ^. _3 . axis_valid
      then return x
      else findAxiWrite
  alwaysFailed = mdo
    x :: U8 <- head <$> rwSpi 12 (replicate d4 0)
    assert (x == 1) $ "busy or failed: " <> showX x
    findFailed

  findFailed = mdo
    x :: U8 <- head <$> rwSpi 12 (replicate d4 0)
    assert (x == 2 || x == 1) $ "busy or failed: " <> showX x
    if x == 1
      then alwaysFailed
      else findFailed

testPcieRead :: DmaCoreTestM ()
testPcieRead = do
  rwSpi 11 (replicate d4 0)
    >>= assertEqual "read is done"
        $(listToVecTH [0,0,0,0 ::U8])

  rwSpi 138 (1:>0:>0:>0:>Nil)

  tick silent

  rwSpi 9 (replicate d4 0)
    >>= assertEqual "read is busy"
        $(listToVecTH [1,0,0,0 ::U8])
  rwSpi 11 (replicate d4 0)
    >>= assertEqual "read is not failed"
        $(listToVecTH [0,0,0,0 ::U8])

  rwSpi 26 (replicate d4 0)
    >>= assertEqual "read trigger count is 1"
        $(listToVecTH [1,0,0,0 ::U8])

  tick silent
  tick silent

  rwSpi 24 (replicate d4 0)
    >>= assertEqual "tx sent count is 1"
        $(listToVecTH [1,0,0,0 ::U8])

  -- tick $ onlyAxi $ mkAxisWrite  0x00000018_4a000006
  -- tick $ onlyAxi $ mkAxisWrite  0x12345678_00001f00
  -- tick $ onlyAxi $ mkAxisWrite  0x33333333_abcdef00
  -- tick $ onlyAxi $ mkAxisWrite  0x55555555_44444444
  -- tick $ onlyAxi $ mkAxisWrite  0x00000000_66666666 & axis_last .~ True & axis_keep .~ 0xF

  tick $ onlyAxi $ mkAxisWrite  0x00000018_4a000006 & axis_keep .~ 0xF
  tick $ onlyAxi $ mkAxisWrite  0x00000000_00000018 & axis_keep .~ 0xF
  tick $ onlyAxi $ mkAxisWrite  0x00000000_00000000 & axis_valid .~ False
  tick $ onlyAxi $ mkAxisWrite  0x12345678_00001f00 & axis_keep .~ 0xF
  tick $ onlyAxi $ mkAxisWrite  0x12345678_12345678 & axis_keep .~ 0xF
  tick $ onlyAxi $ mkAxisWrite  0x33333333_abcdef00
  tick $ onlyAxi $ mkAxisWrite  0x55555555_44444444
  tick $ onlyAxi $ mkAxisWrite  0x00000000_66666666 & axis_last .~ True & axis_keep .~ 0xF
  tick silent
  tick silent

  rwSpi 9 (replicate d4 0)
    >>= assertEqual "read is still busy"
        $(listToVecTH [1,0,0,0 ::U8])

  rwSpi 26 (replicate d4 0)
    >>= assertEqual "read trigger count is 1"
        $(listToVecTH [1,0,0,0 ::U8])

  rwSpi 7 (replicate d24 0)
    >>= assertEqual "ram val"
        $(listToVecTH
         [ 0x12, 0x34, 0x56, 0x78
         , 0xab, 0xcd, 0xef, 0x00
         , 0x33, 0x33, 0x33, 0x33
         , 0x44, 0x44, 0x44, 0x44
         , 0x55, 0x55, 0x55, 0x55
         , 0x66, 0x66, 0x66, 0x66
          :: U8])

  rwSpi 134 (2:>0:>0:>0:>Nil)

  rwSpi 7 (replicate d16 0)
    >>= assertEqual "raw tlp val"
        $(listToVecTH
         [ 0x06, 0x00, 0x00, 0x4a
         , 0x18, 0x00, 0x00, 0x00
         , 0x00, 0x1f, 0x00, 0x00
         , 0x78, 0x56, 0x34, 0x12
          :: U8])

testPcieSearch :: DmaCoreTestM ()
testPcieSearch = do
  rwSpi 134 (1:>0:>0:>0:>Nil) -- Select search

  rwSpi 14 (replicate d4 0)
    >>= assertEqual "search is done"
        $(listToVecTH [0,0,0,0 ::U8])
  rwSpi 16 (replicate d4 0)
    >>= assertEqual "search is not failed"
        $(listToVecTH [0,0,0,0 ::U8])

  rwSpi 131 (100:>0:>0:>0:>Nil) -- Search length
  rwSpi 146 (  1:>0:>0:>0:>Nil) -- Search type
  -- rwSpi 147 (0x00:>0x33:>0x0:>0x0:>Nil) -- Search val
  -- rwSpi 147 (0x12:>0x34:>0x0:>0x0:>Nil) -- Search val
  -- rwSpi 147 (0xab:>0xcd:>0x0:>0x0:>Nil) -- Search val
  rwSpi 147 (0x55:>0x55:>0x55:>0x55:>Nil) -- Search val
  rwSpi 143 ( 1:>0:>0:>0:>Nil) -- Trigger search

  tick silent

  rwSpi 14 (replicate d4 0)
    >>= assertEqual "search is busy"
        $(listToVecTH [1,0,0,0 ::U8])

  tick silent
  tick silent

  tick $ onlyAxi $ mkAxisWrite  0x00000018_4a000006
  tick $ onlyAxi $ mkAxisWrite  0x12345678_00000100
  tick $ onlyAxi $ mkAxisWrite  0x33333333_abcdef00
  tick $ onlyAxi $ mkAxisWrite  0x55555555_44444444
  tick $ onlyAxi $ mkAxisWrite  0x00000000_66666666 & axis_last .~ True & axis_keep .~ 0xF

  tick silent
  tick silent

  rwSpi 14 (replicate d4 0)
    >>= assertEqual "search is busy"
        $(listToVecTH [1,0,0,0 ::U8])
  rwSpi 16 (replicate d4 0)
    >>= assertEqual "search is not failed"
        $(listToVecTH [0,0,0,0 ::U8])

  rwSpi 17 (replicate d4 0)
    >>= assertEqual "search found"
        $(listToVecTH [1,0,0,0 ::U8])


  rwSpi 7 (replicate d8 0)
    >>= assertEqual "ram val"
        $(listToVecTH
         [ 0x10, 0x00, 0x00, 0x00
         , 0x00, 0x00, 0x00, 0x00
          :: U8])

dut :: DmaCoreTestM () -> TestLog DmaCoreI DmaCoreO ()
dut = runTestM dut
 where
  dut = withClockResetEnable systemClockGen systemResetGen enableGen $
    \(unbundle -> (a, b, unbundle -> c,d,e)) ->
      bundle $ dmaCore a b c d e 0

tests :: TestTree
tests = testGroup "DmaCore tests"
  [ testCase "idx" $ testForError (dut testIdx)
  , testCase "write register" $ testForError (dut testWrite)
  , testCase "pcie tx" $ testForError (truncateLog 10000 (dut testPcieReadStatus))
  , testCase "pcie read" $ testForError (truncateLog 10000 (dut testPcieRead))
  , testCase "pcie search" $ testForError (truncateLog 10000 (dut testPcieSearch ))
  ]
