#! /usr/bin/env runhaskell

{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE QuasiQuotes #-}

import Development.Shake hiding ((~>))
import Development.Shake.Command
import Development.Shake.FilePath
import Development.Shake.Config
import Development.Shake.Util

import System.Directory (copyFile)

import Data.String.Interpolate
import Data.String.Interpolate.Util

import Data.ByteString (ByteString)
import qualified Data.ByteString as B hiding (unpack, putStrLn)
import qualified Data.ByteString.Char8 as B (unpack, putStrLn)

import Text.Regex.TDFA
import qualified Data.Text as T

import Data.String (fromString)

import Clash.Driver.Types

topModule = "Top"
topName   = "board"

artifactDir = ".shake"
hdl       = "verilog"
envDir    = artifactDir </> hdl </> topModule </> topName
manifest  = envDir </> topName <.> "manifest"

copyTo dir n = copyFile' n (dir </> takeFileName n)

readManifest content = [ envDir </> f <.> "v" | f <- files ]
 where
  files = map T.unpack (componentNames $ read content)

getManifestOutputs = do
  need [manifest]
  readManifest <$> readFile' manifest

testReport = artifactDir </> "test-report.txt"

main :: IO ()
main = shakeArgs shakeOptions
  { shakeThreads = 0
  , shakeColor = True
  -- , shakeLint = Just LintFSATrace
  } $ do
  want [testReport]

  phony "clean" $ do
    putNormal "Removing build files and generated HDL"
    removeFilesAfter artifactDir ["//*"]

  testReport %> \o -> do
    getDirectoryFiles "" ["src//*.hs"] >>= need
    getDirectoryFiles "" ["tests//*.hs"] >>= need

    need ["picodma-fpga.cabal"]

    Stdout (out :: ByteString) <- cmd "cabal run tests"
    let s = out =~ "Expected successes(\n*.*)*"
    liftIO $ B.writeFile o s
    putNormal (B.unpack s)

  phony "test" $ do
    need [testReport]
    readFile' testReport >>= putNormal

  manifest %> \o -> do
    need [testReport]

    getDirectoryFiles "" ["src//*.hs"] >>= need

    withTempDir $ \trash -> do
      let odir = trash </> "odir"
      let hidir = trash </> "hidir"
      let top = "src/Top.hs"
      let opts =
            ["--verilog", "-isrc"
            , "-odir", odir
            , "-hidir", hidir
            , "-fclash-inline-limit=200"
            , "-fclash-hdldir", artifactDir
            , "-fclash-hdlsyn", "Xilinx"
            ]
            ++ [top]
      cmd_ "clash" opts

    hdl <- readManifest <$> liftIO (readFile manifest)
    produces hdl

  phony "clash" $ need [manifest]

  phony "yosys" $ do
    need [manifest]
    stubs <- getDirectoryFiles "" ["ip//*.v"]
    need stubs

    source <- getManifestOutputs

    (Stdout (out :: ByteString), Stderr (err :: ByteString))
      <- cmd "yosys -p synth_xilinx" stubs source

    liftIO $ B.putStrLn $ out =~ "=== design hierarchy ===(\n*.*)*Number of cells.*(\n.+)*"
    liftIO $ B.writeFile "hdl/.yosys" $ out =~ "Printing statistics(\n*.*)*"

  "picodma.bit" %> \o -> do
    let mcs = takeDirectory o </> "picodma.mcs"

    need [manifest]

    source      <- getManifestOutputs

    ip          <- getDirectoryFiles "" ["ip//*.xci"]
    constraints <- getDirectoryFiles "" ["constraints.xdc"]
    need (ip <> constraints)

    withTempFile $ \tclFile -> do
      writeFile' tclFile
          $ vivadoTcl
            source
            ip
            constraints

      vivadoCmd tclFile

    produces [takeDirectory o </> "picodma.mcs"]

  phony "vivado" $ need ["picodma.bit"]

  phony "programFpga" $ do
    alwaysRerun

    need ["picodma.bit"]

    withTempFile $ \tclFile -> do
      writeFile' tclFile programFpgaTcl

      vivadoCmd tclFile

  phony "flashFpga" $ do
    alwaysRerun

    need ["picodma.mcs"]

    withTempFile $ \tclFile -> do
      writeFile' tclFile flashFpgaTcl

      vivadoCmd tclFile

--- * Vivado scripts

vivadoCmd tclFile = cmd_ [i|vivado -nolog -nojournal -mode batch -source #{tclFile}|]

vivadoTcl source ip constraints = unindent [i|
  set_part xc7a50tcsg325-2

  read_verilog #{unwords source}
  read_ip #{unwords ip}
  read_xdc #{unwords constraints}

  synth_ip [get_ips]

  synth_design -top board

  opt_design -sweep -retarget -propconst -bram_power_opt -remap
  opt_design -directive Explore

  place_design

  # phys_opt_design -directive Explore
  route_design -directive Explore

  # phys_opt_design -directive Explore

  report_utilization
  report_timing

  write_bitstream -force picodma.bit

  write_cfgmem -force -format mcs -size 4 -interface SPIx4 -loadbit {up 0x00000000 "picodma.bit" } -file "picodma.mcs"
  |]

connectHw = unindent [i|
  open_hw_manager

  connect_hw_server

  # fpga connection errors - vivado bug?
  set i 0
  while {[catch {open_hw_target -xvc_url localhost:2542} issue] && $i < 5} {
      puts "Failed to connect to FPGA : $issue"
      after 500
      incr i
  }

  set i 0
  while {[catch {refresh_hw_target} issue] && $i < 5} {
      puts "Failed to connect to FPGA : $issue"
      after 500
      incr i
  }

  set i 0
  while {[catch {get_hw_devices} issue] && $i < 5} {
      puts "Failed to connect to FPGA : $issue"
      after 500
      incr i
  }
  |]



programFpgaTcl = connectHw <> unindent [i|
  create_hw_bitstream -hw_device [lindex [get_hw_devices xc7a50t_0] 0] "picodma.bit"
  program_hw_devices [get_hw_devices xc7a50t_0]
  |]

flashFpgaTcl = connectHw <> unindent [i|
  # from https://github.com/RHSResearchLLC/PicoEVB/blob/master/Sample-Projects/Project-0/FPGA/tcl/prog-flash.tcl

  # Add flash part, s25fl132k; default to erase and program (no verify)
  create_hw_cfgmem -hw_device [lindex [get_hw_devices xc7a50t_0] 0] [lindex [get_cfgmem_parts {s25fl132k-spi-x1_x2_x4}] 0]
  set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.ERASE  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.VERIFY  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.CHECKSUM  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  refresh_hw_device [lindex [get_hw_devices xc7a50t_0] 0]
  set_property PROGRAM.ADDRESS_RANGE  {use_file} [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.FILES [list "picodma.mcs" ] [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.PRM_FILE {} [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]
  set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]

  # Program the fabric with the flash loader
  startgroup
  if {![string equal [get_property PROGRAM.HW_CFGMEM_TYPE  [lindex [get_hw_devices xc7a50t_0] 0]] [get_property MEM_TYPE [get_property CFGMEM_PART [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]]]] }  { create_hw_bitstream -hw_device [lindex [get_hw_devices xc7a50t_0] 0] [get_property PROGRAM.HW_CFGMEM_BITFILE [ lindex [get_hw_devices xc7a50t_0] 0]]; program_hw_devices [lindex [get_hw_devices xc7a50t_0] 0]; };

  # Finally, program the flash
  program_hw_cfgmem -hw_cfgmem [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a50t_0] 0]]

  |]

