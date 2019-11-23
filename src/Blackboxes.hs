{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

{-# OPTIONS_GHC -Wno-partial-type-signatures #-}

{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE BinaryLiterals      #-}
{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE MagicHash           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE NoStarIsType        #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}

module Blackboxes where

import           Clash.Primitives.Scaffold

makeScaffold "xilinxDiff" "IBUFDS_GTE2" []
  [ [ ClkOut "O"
    , ClkIn "I"
    , ClkIn "IB"
    ]
  ]

makeScaffold "xilinxPcie" "pcie_7xi" []

  [ [ ClkIn "sys_clk"
    , In "sys_rst_n" 1
    , In "pci_exp_rxp" 1
    , In "pci_exp_rxn" 1

    , Out "pci_exp_txp" 1
    , Out "pci_exp_txn" 1
    ]

  , [ In "s_axis_tx_tdata" 64
    , In "s_axis_tx_tkeep" 8
    , In "s_axis_tx_tlast" 1
    , In "s_axis_tx_tuser" 4
    , In "s_axis_tx_tvalid" 1
    , In "m_axis_rx_tready" 1
    , In "cfg_mgmt_dwaddr" 10
    , In "cfg_mgmt_byte_en" 4
    , In "cfg_mgmt_rd_en" 1
    , In "cfg_mgmt_wr_readonly" 1
    , In "cfg_mgmt_wr_rw1c_as_rw" 1
    , In "cfg_mgmt_di" 32
    , In "cfg_mgmt_wr_en" 1
    , In "cfg_dsn" 64
    , In "cfg_pm_force_state" 2
    , In "cfg_pm_force_state_en" 1
    , In "cfg_pm_halt_aspm_l0s" 1
    , In "cfg_pm_halt_aspm_l1" 1
    , In "cfg_pm_send_pme_to" 1
    , In "cfg_pm_wake" 1
    , In "rx_np_ok" 1
    , In "rx_np_req" 1
    , In "cfg_trn_pending" 1
    , In "cfg_turnoff_ok" 1
    , In "tx_cfg_gnt" 1

    , In "cfg_interrupt_assert" 1
    , In "cfg_interrupt" 1
    , In "cfg_interrupt_stat" 1
    , In "cfg_interrupt_di" 8
    , In "cfg_pciecap_interrupt_msgnum" 5

    , Out "s_axis_tx_tready" 1
    , Out "m_axis_rx_tdata" 64
    , Out "m_axis_rx_tkeep" 8
    , Out "m_axis_rx_tlast" 1
    , Out "m_axis_rx_tuser" 22
    , Out "m_axis_rx_tvalid" 1
    , Out "cfg_mgmt_do" 32
    , Out "cfg_mgmt_rd_wr_done" 1
    , Out "cfg_command" 16
    , Out "cfg_bus_number" 8
    , Out "cfg_device_number" 5
    , Out "cfg_function_number" 3
    , Out "cfg_bridge_serr_en" 1
    , Out "cfg_dcommand" 16
    , Out "cfg_dcommand2" 16
    , Out "cfg_dstatus" 16
    , Out "cfg_lcommand" 16
    , Out "cfg_lstatus" 16
    , Out "cfg_pcie_link_state" 3
    , Out "cfg_pmcsr_pme_en" 1
    , Out "cfg_pmcsr_pme_status" 1
    , Out "cfg_pmcsr_powerstate" 2
    , Out "cfg_received_func_lvl_rst" 1
    , Out "cfg_slot_control_electromech_il_ctl_pulse" 1
    , Out "cfg_status" 16
    , Out "cfg_to_turnoff" 1
    , Out "tx_buf_av" 6
    , Out "tx_cfg_req" 1
    , Out "tx_err_drop" 1
    , Out "cfg_vc_tcvc_map" 7

    , ClkOut "user_clk_out"

    , Out "user_reset_out" 1
    , Out "user_lnk_up" 1
    , Out "user_app_rdy" 1
    ]
  ]
