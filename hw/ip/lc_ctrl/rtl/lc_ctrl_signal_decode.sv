// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Life cycle signal decoder and sender module.

module lc_ctrl_signal_decode
  import lc_ctrl_pkg::*;
#(
  // Random netlist constants
  // SCRAP, RAW, TEST_LOCKED*, INVALID
  parameter lc_keymgr_div_t RndCnstLcKeymgrDivInvalid    = LcKeymgrDivWidth'(0),
  // TEST_UNLOCKED*, DEV, RMA
  parameter lc_keymgr_div_t RndCnstLcKeymgrDivTestDevRma = LcKeymgrDivWidth'(1),
  // PROD, PROD_END
  parameter lc_keymgr_div_t RndCnstLcKeymgrDivProduction = LcKeymgrDivWidth'(2)
  ) (
  input                  clk_i,
  input                  rst_ni,
  // Life cycle state vector.
  input  logic           lc_state_valid_i,
  input  lc_state_e      lc_state_i,
  input  lc_id_state_e   lc_id_state_i,
  input  fsm_state_e     fsm_state_i,
  // Escalation enable from escalation receiver.
  input                  esc_wipe_secrets_i,
  // Life cycle broadcast outputs.
  output lc_tx_t         lc_dft_en_o,
  output lc_tx_t         lc_nvm_debug_en_o,
  output lc_tx_t         lc_hw_debug_en_o,
  output lc_tx_t         lc_cpu_en_o,
  output lc_tx_t         lc_creator_seed_sw_rw_en_o,
  output lc_tx_t         lc_owner_seed_sw_rw_en_o,
  output lc_tx_t         lc_iso_part_sw_rd_en_o,
  output lc_tx_t         lc_iso_part_sw_wr_en_o,
  output lc_tx_t         lc_seed_hw_rd_en_o,
  output lc_tx_t         lc_keymgr_en_o,
  output lc_tx_t         lc_escalate_en_o,
  // State group diversification value for keymgr
  output lc_keymgr_div_t lc_keymgr_div_o
);

  //////////////////////////
  // Signal Decoder Logic //
  //////////////////////////

  lc_tx_t lc_dft_en_d, lc_dft_en_q;
  lc_tx_t lc_nvm_debug_en_d, lc_nvm_debug_en_q;
  lc_tx_t lc_hw_debug_en_d, lc_hw_debug_en_q;
  lc_tx_t lc_cpu_en_d, lc_cpu_en_q;
  lc_tx_t lc_creator_seed_sw_rw_en_d, lc_creator_seed_sw_rw_en_q;
  lc_tx_t lc_owner_seed_sw_rw_en_d, lc_owner_seed_sw_rw_en_q;
  lc_tx_t lc_iso_part_sw_rd_en_d, lc_iso_part_sw_rd_en_q;
  lc_tx_t lc_iso_part_sw_wr_en_d, lc_iso_part_sw_wr_en_q;
  lc_tx_t lc_seed_hw_rd_en_d, lc_seed_hw_rd_en_q;
  lc_tx_t lc_keymgr_en_d, lc_keymgr_en_q;
  lc_tx_t lc_escalate_en_d, lc_escalate_en_q;
  lc_keymgr_div_t lc_keymgr_div_d, lc_keymgr_div_q;

  always_comb begin : p_lc_signal_decode
    // Life cycle control signal defaults
    lc_dft_en_d                = Off;
    lc_nvm_debug_en_d          = Off;
    lc_hw_debug_en_d           = Off;
    lc_cpu_en_d                = Off;
    lc_creator_seed_sw_rw_en_d = Off;
    lc_owner_seed_sw_rw_en_d   = Off;
    lc_iso_part_sw_rd_en_d     = Off;
    lc_iso_part_sw_wr_en_d     = Off;
    lc_seed_hw_rd_en_d         = Off;
    lc_keymgr_en_d             = Off;
    lc_escalate_en_d           = Off;
    // Set to invalid diversification value by default.
    lc_keymgr_div_d            = RndCnstLcKeymgrDivInvalid;
    // The escalation life cycle signal is always decoded, no matter
    // which state we currently are in.
    if (esc_wipe_secrets_i) begin
      lc_escalate_en_d = On;
    end

    // Only broadcast during the following main FSM states
    if (lc_state_valid_i && fsm_state_i inside {IdleSt,
                                                ClkMuxSt,
                                                CntIncrSt,
                                                CntProgSt,
                                                TransCheckSt,
                                                FlashRmaSt,
                                                TokenHashSt,
                                                TokenCheck0St,
                                                TokenCheck1St}) begin
      unique case (lc_state_i)
        ///////////////////////////////////////////////////////////////////
        // Enable DFT and debug functionality, including the CPU in the
        // test unlocked states.
        LcStTestUnlocked0,
        LcStTestUnlocked1,
        LcStTestUnlocked2,
        LcStTestUnlocked3: begin
          lc_dft_en_d            = On;
          lc_nvm_debug_en_d      = On;
          lc_hw_debug_en_d       = On;
          lc_cpu_en_d            = On;
          lc_iso_part_sw_wr_en_d = On;
          lc_keymgr_div_d        = RndCnstLcKeymgrDivTestDevRma;
        end
        ///////////////////////////////////////////////////////////////////
        // Enable production functions
        LcStProd, LcStProdEnd: begin
          lc_cpu_en_d              = On;
          lc_keymgr_en_d           = On;
          lc_owner_seed_sw_rw_en_d = On;
          lc_iso_part_sw_wr_en_d   = On;
          lc_iso_part_sw_rd_en_d   = On;
          lc_keymgr_div_d          = RndCnstLcKeymgrDivProduction;
          // Only allow provisioning if the device has not yet been personalized.
          if (lc_id_state_i == LcIdBlank) begin
            lc_creator_seed_sw_rw_en_d = On;
          end
          // Only allow hardware to consume the seeds once personalized.
          if (lc_id_state_i == LcIdPersonalized) begin
            lc_seed_hw_rd_en_d = On;
          end

        end
        ///////////////////////////////////////////////////////////////////
        // Same functions as PROD, but with additional debug functionality.
        LcStDev: begin
          lc_hw_debug_en_d         = On;
          lc_cpu_en_d              = On;
          lc_keymgr_en_d           = On;
          lc_owner_seed_sw_rw_en_d = On;
          lc_iso_part_sw_wr_en_d   = On;
          lc_iso_part_sw_rd_en_d   = On;
          lc_keymgr_div_d          = RndCnstLcKeymgrDivTestDevRma;
          // Only allow provisioning if the device has not yet been personalized.
          if (lc_id_state_i == LcIdBlank) begin
            lc_creator_seed_sw_rw_en_d = On;
          end
          // Only allow hardware to consume the seeds once personalized.
          if (lc_id_state_i == LcIdPersonalized) begin
            lc_seed_hw_rd_en_d = On;
          end
        end
        ///////////////////////////////////////////////////////////////////
        // Enable all test and production functions.
        LcStRma: begin
          lc_dft_en_d                = On;
          lc_nvm_debug_en_d          = On;
          lc_hw_debug_en_d           = On;
          lc_cpu_en_d                = On;
          lc_keymgr_en_d             = On;
          lc_creator_seed_sw_rw_en_d = On;
          lc_owner_seed_sw_rw_en_d   = On;
          lc_iso_part_sw_wr_en_d     = On;
          lc_iso_part_sw_rd_en_d     = On;
          lc_seed_hw_rd_en_d         = On;
          lc_keymgr_div_d            = RndCnstLcKeymgrDivTestDevRma;
        end
        ///////////////////////////////////////////////////////////////////
        // Invalid or scrapped life cycle state, do not assert
        // any signals other than escalate_en and clk_byp_en.
        default: ;
      endcase // lc_state_i
    end
  end

  /////////////////////////////////
  // Control signal output flops //
  /////////////////////////////////

  assign lc_dft_en_o                = lc_dft_en_q;
  assign lc_nvm_debug_en_o          = lc_nvm_debug_en_q;
  assign lc_hw_debug_en_o           = lc_hw_debug_en_q;
  assign lc_cpu_en_o                = lc_cpu_en_q;
  assign lc_creator_seed_sw_rw_en_o = lc_creator_seed_sw_rw_en_q;
  assign lc_owner_seed_sw_rw_en_o   = lc_owner_seed_sw_rw_en_q;
  assign lc_iso_part_sw_rd_en_o     = lc_iso_part_sw_rd_en_q;
  assign lc_iso_part_sw_wr_en_o     = lc_iso_part_sw_wr_en_q;
  assign lc_seed_hw_rd_en_o         = lc_seed_hw_rd_en_q;
  assign lc_keymgr_en_o             = lc_keymgr_en_q;
  assign lc_escalate_en_o           = lc_escalate_en_q;
  assign lc_keymgr_div_o            = lc_keymgr_div_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if (!rst_ni) begin
      lc_dft_en_q                <= Off;
      lc_nvm_debug_en_q          <= Off;
      lc_hw_debug_en_q           <= Off;
      lc_cpu_en_q                <= Off;
      lc_creator_seed_sw_rw_en_q <= Off;
      lc_owner_seed_sw_rw_en_q   <= Off;
      lc_iso_part_sw_rd_en_q     <= Off;
      lc_iso_part_sw_wr_en_q     <= Off;
      lc_seed_hw_rd_en_q         <= Off;
      lc_keymgr_en_q             <= Off;
      lc_escalate_en_q           <= Off;
      lc_keymgr_div_q            <= RndCnstLcKeymgrDivInvalid;
    end else begin
      lc_dft_en_q                <= lc_dft_en_d;
      lc_nvm_debug_en_q          <= lc_nvm_debug_en_d;
      lc_hw_debug_en_q           <= lc_hw_debug_en_d;
      lc_cpu_en_q                <= lc_cpu_en_d;
      lc_creator_seed_sw_rw_en_q <= lc_creator_seed_sw_rw_en_d;
      lc_owner_seed_sw_rw_en_q   <= lc_owner_seed_sw_rw_en_d;
      lc_iso_part_sw_rd_en_q     <= lc_iso_part_sw_rd_en_d;
      lc_iso_part_sw_wr_en_q     <= lc_iso_part_sw_wr_en_d;
      lc_seed_hw_rd_en_q         <= lc_seed_hw_rd_en_d;
      lc_keymgr_en_q             <= lc_keymgr_en_d;
      lc_escalate_en_q           <= lc_escalate_en_d;
      lc_keymgr_div_q            <= lc_keymgr_div_d;
    end
  end

  ////////////////
  // Assertions //
  ////////////////

  // Need to make sure that the random netlist constants
  // are unique.
  `ASSERT_INIT(LcKeymgrDivUnique0_A,
      !(RndCnstLcKeymgrDivInvalid inside {RndCnstLcKeymgrDivTestDevRma,
                                          RndCnstLcKeymgrDivProduction}))
  `ASSERT_INIT(LcKeymgrDivUnique1_A, RndCnstLcKeymgrDivProduction != RndCnstLcKeymgrDivTestDevRma)

  `ASSERT(SignalsAreOffWhenNotEnabled_A,
      !lc_state_valid_i
      |=>
      lc_dft_en_o == Off &&
      lc_nvm_debug_en_o == Off &&
      lc_hw_debug_en_o == Off &&
      lc_cpu_en_o == Off &&
      lc_creator_seed_sw_rw_en_o == Off &&
      lc_owner_seed_sw_rw_en_o == Off &&
      lc_iso_part_sw_rd_en_o == Off &&
      lc_iso_part_sw_wr_en_o == Off &&
      lc_seed_hw_rd_en_o == Off &&
      lc_keymgr_en_o == Off &&
      lc_dft_en_o == Off &&
      lc_keymgr_div_o == RndCnstLcKeymgrDivInvalid)

  `ASSERT(EscalationAlwaysDecoded_A,
      (lc_escalate_en_o == On) == $past(esc_wipe_secrets_i))

endmodule : lc_ctrl_signal_decode
