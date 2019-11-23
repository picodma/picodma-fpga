-- | This file is is a modified version of
-- https://git.smart-cactus.org/ben/clash-testbench (BSD 3-clause "New" or "Revised" License)
--
-- Copyright (c) 2017, Ben Gamari

-- All rights reserved.

-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:

--     * Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.

--     * Redistributions in binary form must reproduce the above
--       copyright notice, this list of conditions and the following
--       disclaimer in the documentation and/or other materials provided
--       with the distribution.

--     * Neither the name of Ben Gamari nor the names of other
--       contributors may be used to endorse or promote products derived
--       from this software without specific prior written permission.

-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
-- LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
-- A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
-- OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
-- LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
-- DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
-- THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
-- OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE GADTs #-}

module Test.Test
    where

import GHC.Generics
import Control.DeepSeq
import Control.Monad.Free
import Control.Monad.Fail
import Control.Monad hiding (fail)
import Data.Semigroup
import Clash.Prelude hiding (fail)
import Clash.Signal.Internal (Signal(..))
import System.IO.Unsafe
import Data.IORef
import Data.List (foldr)

import Test.Tasty.HUnit (assertFailure)

data Stream i o = Stream o (i -> Stream i o)

-- | Convert a 'Signal' to a 'Stream', where the input to each timestep can be
-- computed as a function of previous outputs.
--
-- Note that the 'Stream' must be consumed linearly; that is, you can apply
-- the continuation associated with a particular stream element only once.
streamSignal :: forall clk i o. KnownDomain clk => (Signal clk i -> Signal clk o) -> i -> Stream i o
streamSignal dut input0 = unsafePerformIO $ mdo
    -- oh the horror...
    inputRefs <- infiniteRefList Nothing
    let goOut :: Int -> [IORef (Maybe i)] -> [o] -> IO (Stream i o)
        goOut !n (inRef:inRefs) (out:rest) = do
            let next :: i -> Stream i o
                next i = unsafePerformIO $ do
                    old <- atomicModifyIORef inRef (\old -> (Just i, old))
                    case old of
                      Nothing -> return ()
                      Just _  -> fail "streamIt: non-linear usage"
                    unsafeInterleaveIO $ goOut (n+1) inRefs rest
            return $ Stream out next
        goOut _ _  [] = fail "reached end of Signal"
        goOut _ [] _  = fail "impossible"

    let inputs = input0 : fmap readInput inputRefs
        readInput ref = unsafePerformIO $ do
            val <- readIORef ref
            case val of
              Nothing -> fail "bad news bears"
              Just x  -> return x
    goOut 0 inputRefs $ simulate_lazy dut inputs
{-# NOINLINE streamSignal #-}

infiniteRefList :: a -> IO [IORef a]
infiniteRefList val = go
  where
    go = do
        rest <- unsafeInterleaveIO go
        ref <- newIORef val
        return (ref : rest)

type DUT clk i o = Signal clk i -> Signal clk o

data TestF i o next
    = Tick i (o -> next)
    | Trace String next
    | Fail String
    deriving (Functor)

newtype TestM i o a = TestM (Free (TestF i o) a)
                    deriving stock (Functor)
                    deriving newtype (Applicative, Monad)

instance MonadFail (TestM i o) where
    fail = TestM . liftF . Fail

tick :: i -> TestM i o o
tick i = TestM $ liftF (Tick i id)

tick_ :: i -> TestM i o ()
tick_ = void . tick

tickUntil :: (NFData i)
          => i -> (o -> Bool) -> TestM i o o
tickUntil i cond = do
    o <- tick i
    if cond o
      then return o
      else tickUntil i cond

tickUntilJust :: (NFData i)
          => i -> (o -> Maybe a) -> TestM i o a
tickUntilJust i f = do
    o <- tick i
    case f o of
      Just o' -> return o'
      Nothing -> tickUntilJust i f

trace :: String -> TestM i o ()
trace msg = TestM $ liftF (Trace msg ())

assert :: Bool -> String -> TestM i o ()
assert cond msg
  | not cond  = fail msg
  | otherwise = return ()

assertEqual :: (ShowX a, Eq a) => String -> a -> a -> TestM i o ()
assertEqual msg expected actual
  | expected == actual = return ()
  | otherwise          = fail $ unlines [ msg
                                        , "Expected: " <> showX expected
                                        , "Actual:   " <> showX actual
                                        ]

data TestLog i o a = Ticked i o (TestLog i o a)
                   | TraceMsg String (TestLog i o a)
                   | Finished a
                   | Failed String
                   deriving stock (Show, Functor, Generic)
                   deriving anyclass (ShowX)

toTickList :: TestLog i o a -> [(i,o)]
toTickList (Ticked i o rest) = (i,o) : toTickList rest
toTickList (TraceMsg _ rest) = toTickList rest
toTickList (Failed s) = error $ "Failed "<>s
toTickList (Finished _) = []


runTestM :: forall clk i o a. KnownDomain clk => DUT clk i o -> TestM i o a -> TestLog i o a
runTestM dut (TestM m) =
    let f :: (i -> Stream i o) -> Free (TestF i o) a -> TestLog i o a
        f k (Free (Tick i k'))  = let Stream o rest = k i
                                  in Ticked i o (f rest (k' o))
        f k (Free (Trace s k')) = TraceMsg s (f k k')
        f _ (Free (Fail s))     = Failed s
        f _ (Pure x)            = Finished x
    in f (streamSignal dut) m


toTraceList :: TestLog i o a -> [String]
toTraceList (Ticked _ _ rest) = toTraceList rest
toTraceList (TraceMsg s rest) = s : toTraceList rest
toTraceList (Failed s) = error $ "Failed "<>s
toTraceList (Finished _) = []

testForError :: TestLog i o a -> IO ()
testForError (Ticked _ _ rest) = testForError rest
testForError (TraceMsg s rest) = testForError rest
testForError (Failed s) = assertFailure $ "Failed "<>s
testForError (Finished _) = pure ()

prepend :: (Eq a)  => a -> [a] -> [a]
prepend x [] = [x]
prepend x (y:ys) | x == y = y:ys
                 | otherwise = x : y:ys
uniq :: Eq a => [a] -> [a]
uniq = Data.List.foldr prepend []

-- | Split a log at step @n@.
splitLog :: Int -> TestLog i o a -> TestLog i o (Either (TestLog i o a) a)
splitLog 0 x                 = Finished $ Left x
splitLog n (Ticked i o rest) = Ticked i o (splitLog (n-1) rest)
splitLog n (TraceMsg s rest) = TraceMsg s (splitLog (n-1) rest)
splitLog _ (Finished x)      = Finished (Right x)
splitLog _ (Failed x)        = Failed x

data Truncated a = Truncated
                   -- ^ it was truncated before producing a result
                 | NotTruncated a
                   -- ^ it finished with a result
                 deriving (Show)

truncateLog :: Int -> TestLog i o a -> TestLog i o (Truncated a)
truncateLog n = fmap (either (const Truncated) NotTruncated) . splitLog  n
