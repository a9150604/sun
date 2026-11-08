`timescale 1ns/1ps
import i2c4_pkg::*;

// -----------------------------------------------------------------------------
// AXI4-Lite slave register block for four I2C device controllers.
// This module is intended to connect to the AXI-Lite master side of the Lattice
// PCIe Endpoint IP generated in Bridge Mode / Non-DMA mode.
// -----------------------------------------------------------------------------
module axil_i2c4_regs #(
  parameter int CLK_DIV = 250
)(
  input  logic         ACLK,
  input  logic         ARESETn,

  input  logic [15:0]  S_AXI_AWADDR,
  input  logic         S_AXI_AWVALID,
  output logic         S_AXI_AWREADY,
  input  logic [31:0]  S_AXI_WDATA,
  input  logic [3:0]   S_AXI_WSTRB,
  input  logic         S_AXI_WVALID,
  output logic         S_AXI_WREADY,
  output logic [1:0]   S_AXI_BRESP,
  output logic         S_AXI_BVALID,
  input  logic         S_AXI_BREADY,

  input  logic [15:0]  S_AXI_ARADDR,
  input  logic         S_AXI_ARVALID,
  output logic         S_AXI_ARREADY,
  output logic [31:0]  S_AXI_RDATA,
  output logic [1:0]   S_AXI_RRESP,
  output logic         S_AXI_RVALID,
  input  logic         S_AXI_RREADY,

  input  logic [3:0]   i2c_scl_in,
  input  logic [3:0]   i2c_sda_in,
  output logic [3:0]   i2c_scl_oen,
  output logic [3:0]   i2c_sda_oen,
  output logic [3:0]   dev_irq
);

  logic [6:0]  dev_addr         [4];
  logic [15:0] poll_gap         [4];
  logic        auto_enable      [4];
  logic        direct_rw        [4];
  logic [7:0]  direct_reg_addr  [4];
  logic [7:0]  direct_wr_data   [4];
  logic [7:0]  poll_reg_addr    [4][8];
  logic        direct_start_pulse [4];
  logic        irq_clear_pulse    [4];

  logic [7:0] direct_rd_data [4];
  logic       direct_done [4];
  logic       direct_ack_error [4];
  logic       ctrl_busy [4];
  logic       auto_valid [4];
  logic [2:0] auto_poll_idx [4];
  logic [7:0] shadow [4][8];

  genvar gi;
  generate
    for (gi = 0; gi < 4; gi++) begin : g_dev
      i2c_device_ctrl #(.CLK_DIV(CLK_DIV)) u_i2c_device_ctrl (
        .clk(ACLK),
        .rst_n(ARESETn),
        .auto_enable(auto_enable[gi]),
        .dev_addr(dev_addr[gi]),
        .poll_gap(poll_gap[gi]),
        .direct_start(direct_start_pulse[gi]),
        .direct_rw(direct_rw[gi]),
        .direct_reg_addr(direct_reg_addr[gi]),
        .direct_wr_data(direct_wr_data[gi]),
        .poll_reg_addr0(poll_reg_addr[gi][0]),
        .poll_reg_addr1(poll_reg_addr[gi][1]),
        .poll_reg_addr2(poll_reg_addr[gi][2]),
        .poll_reg_addr3(poll_reg_addr[gi][3]),
        .poll_reg_addr4(poll_reg_addr[gi][4]),
        .poll_reg_addr5(poll_reg_addr[gi][5]),
        .poll_reg_addr6(poll_reg_addr[gi][6]),
        .poll_reg_addr7(poll_reg_addr[gi][7]),
        .direct_rd_data(direct_rd_data[gi]),
        .direct_done(direct_done[gi]),
        .direct_ack_error(direct_ack_error[gi]),
        .busy(ctrl_busy[gi]),
        .auto_valid(auto_valid[gi]),
        .auto_poll_idx(auto_poll_idx[gi]),
        .irq(dev_irq[gi]),
        .irq_clear(irq_clear_pulse[gi]),
        .shadow_r0(shadow[gi][0]),
        .shadow_r1(shadow[gi][1]),
        .shadow_r2(shadow[gi][2]),
        .shadow_r3(shadow[gi][3]),
        .shadow_r4(shadow[gi][4]),
        .shadow_r5(shadow[gi][5]),
        .shadow_r6(shadow[gi][6]),
        .shadow_r7(shadow[gi][7]),
        .scl_in(i2c_scl_in[gi]),
        .sda_in(i2c_sda_in[gi]),
        .scl_oen(i2c_scl_oen[gi]),
        .sda_oen(i2c_sda_oen[gi])
      );
    end
  endgenerate

  function automatic logic dev_addr_hit(input logic [15:0] addr);
    return (addr[15:12] == 4'h0) && (addr[11:8] >= 4'h1) && (addr[11:8] <= 4'h4);
  endfunction

  function automatic int unsigned dev_sel(input logic [15:0] addr);
    return int'(addr[11:8]) - 1;
  endfunction

  function automatic logic [7:0] dev_off(input logic [15:0] addr);
    return addr[7:0];
  endfunction

  function automatic logic [31:0] read_mux(input logic [15:0] addr);
    int unsigned d;
    logic [7:0] off;
    begin
      d   = dev_sel(addr);
      off = dev_off(addr);
      unique case (addr)
        16'h0000: read_mux = ID_VALUE;
        16'h0004: read_mux = VERSION_VALUE;
        16'h0008: read_mux = {28'd0, auto_enable[3], auto_enable[2], auto_enable[1], auto_enable[0]};
        16'h000C: read_mux = {28'd0, dev_irq[3], dev_irq[2], dev_irq[1], dev_irq[0]};
        default: begin
          if (dev_addr_hit(addr)) begin
            unique case (off)
              8'h00: read_mux = {poll_gap[d], 9'd0, dev_addr[d]};
              8'h04: read_mux = {27'd0, 1'b0, direct_rw[d], 1'b0, 1'b0, auto_enable[d]};
              8'h08: read_mux = {16'd0, direct_wr_data[d], direct_reg_addr[d]};
              8'h0C: read_mux = {25'd0, auto_poll_idx[d], auto_valid[d], direct_ack_error[d], direct_done[d], ctrl_busy[d]};
              8'h10: read_mux = {24'd0, direct_rd_data[d]};
              8'h40: read_mux = {24'd0, poll_reg_addr[d][0]};
              8'h44: read_mux = {24'd0, poll_reg_addr[d][1]};
              8'h48: read_mux = {24'd0, poll_reg_addr[d][2]};
              8'h4C: read_mux = {24'd0, poll_reg_addr[d][3]};
              8'h50: read_mux = {24'd0, poll_reg_addr[d][4]};
              8'h54: read_mux = {24'd0, poll_reg_addr[d][5]};
              8'h58: read_mux = {24'd0, poll_reg_addr[d][6]};
              8'h5C: read_mux = {24'd0, poll_reg_addr[d][7]};
              8'h20: read_mux = {24'd0, shadow[d][0]};
              8'h24: read_mux = {24'd0, shadow[d][1]};
              8'h28: read_mux = {24'd0, shadow[d][2]};
              8'h2C: read_mux = {24'd0, shadow[d][3]};
              8'h30: read_mux = {24'd0, shadow[d][4]};
              8'h34: read_mux = {24'd0, shadow[d][5]};
              8'h38: read_mux = {24'd0, shadow[d][6]};
              8'h3C: read_mux = {24'd0, shadow[d][7]};
              default: read_mux = 32'hDEAD_BEEF;
            endcase
          end else begin
            read_mux = 32'hBAD0_ADD0;
          end
        end
      endcase
    end
  endfunction

  integer k;
  // wdev intentionally not needed; device select is computed in helper functions.

  // ---------------------------------------------------------------------------
  // AXI4-Lite write channel
  // ---------------------------------------------------------------------------
  // AXI4-Lite AW and W channels are independent. The master is allowed to send
  // AWVALID and WVALID in different cycles. Therefore this slave must capture
  // address and data independently, then perform the register write only after
  // both have been received. This fixes the earlier implementation that only
  // accepted a write when AWVALID and WVALID were high in the same cycle.
  logic        aw_valid_q;
  logic [15:0] awaddr_q;
  logic        w_valid_q;
  logic [31:0] wdata_q;
  logic [3:0]  wstrb_q;

  assign S_AXI_AWREADY = (!aw_valid_q) && (!S_AXI_BVALID);
  assign S_AXI_WREADY  = (!w_valid_q)  && (!S_AXI_BVALID);

  task automatic do_reg_write(
    input logic [15:0] addr,
    input logic [31:0] data,
    input logic [3:0]  strb
  );
    int unsigned d;
    begin
      if (dev_addr_hit(addr)) begin
        d = dev_sel(addr);
        unique case (dev_off(addr))
          8'h00: begin
            if (strb[0]) dev_addr[d] <= data[6:0];
            if (strb[2] || strb[3]) poll_gap[d] <= data[31:16];
          end
          8'h04: begin
            if (strb[0]) begin
              auto_enable[d] <= data[0];
              direct_rw[d]   <= data[2];
              if (data[1]) direct_start_pulse[d] <= 1'b1;
              if (data[4]) irq_clear_pulse[d]    <= 1'b1;
            end
          end
          8'h08: begin
            if (strb[0]) direct_reg_addr[d] <= data[7:0];
            if (strb[1]) direct_wr_data[d]  <= data[15:8];
          end
          8'h40: if (strb[0]) poll_reg_addr[d][0] <= data[7:0];
          8'h44: if (strb[0]) poll_reg_addr[d][1] <= data[7:0];
          8'h48: if (strb[0]) poll_reg_addr[d][2] <= data[7:0];
          8'h4C: if (strb[0]) poll_reg_addr[d][3] <= data[7:0];
          8'h50: if (strb[0]) poll_reg_addr[d][4] <= data[7:0];
          8'h54: if (strb[0]) poll_reg_addr[d][5] <= data[7:0];
          8'h58: if (strb[0]) poll_reg_addr[d][6] <= data[7:0];
          8'h5C: if (strb[0]) poll_reg_addr[d][7] <= data[7:0];
          default: begin
            // Undefined per-device write address: OKAY response, no side effect.
          end
        endcase
      end
    end
  endtask

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      aw_valid_q <= 1'b0;
      awaddr_q   <= '0;
      w_valid_q  <= 1'b0;
      wdata_q    <= '0;
      wstrb_q    <= '0;
      S_AXI_BRESP   <= 2'b00;
      S_AXI_BVALID  <= 1'b0;
      for (k = 0; k < 4; k++) begin
        dev_addr[k]           <= 7'h50 + k;
        poll_gap[k]           <= 16'd1000;
        auto_enable[k]        <= 1'b0;
        direct_rw[k]          <= 1'b1;
        direct_reg_addr[k]    <= 8'd0;
        direct_wr_data[k]     <= 8'd0;
        direct_start_pulse[k] <= 1'b0;
        irq_clear_pulse[k]    <= 1'b0;
        for (int pr = 0; pr < 8; pr++) begin
          poll_reg_addr[k][pr] <= pr[7:0];
        end
      end
    end else begin
      for (k = 0; k < 4; k++) begin
        direct_start_pulse[k] <= 1'b0;
        irq_clear_pulse[k]    <= 1'b0;
      end

      // Capture write address channel independently.
      if (S_AXI_AWVALID && S_AXI_AWREADY) begin
        aw_valid_q <= 1'b1;
        awaddr_q   <= S_AXI_AWADDR;
      end

      // Capture write data channel independently.
      if (S_AXI_WVALID && S_AXI_WREADY) begin
        w_valid_q <= 1'b1;
        wdata_q   <= S_AXI_WDATA;
        wstrb_q   <= S_AXI_WSTRB;
      end

      // Complete one write only after both AW and W have been captured.
      if (S_AXI_BVALID) begin
        if (S_AXI_BREADY) begin
          S_AXI_BVALID <= 1'b0;
        end
      end else if (aw_valid_q && w_valid_q) begin
        do_reg_write(awaddr_q, wdata_q, wstrb_q);
        aw_valid_q   <= 1'b0;
        w_valid_q    <= 1'b0;
        S_AXI_BRESP  <= 2'b00; // OKAY
        S_AXI_BVALID <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // AXI4-Lite read channel
  // ---------------------------------------------------------------------------
  // Accept one AXI-Lite read request at a time. This simple slave has no read
  // command FIFO, so ARREADY is asserted only when there is no pending RVALID.
  assign S_AXI_ARREADY = (!S_AXI_RVALID);

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      S_AXI_RDATA   <= '0;
      S_AXI_RRESP   <= 2'b00;
      S_AXI_RVALID  <= 1'b0;
    end else begin
      if (S_AXI_ARVALID && S_AXI_ARREADY) begin
        S_AXI_RDATA  <= read_mux(S_AXI_ARADDR);
        S_AXI_RRESP  <= 2'b00; // OKAY
        S_AXI_RVALID <= 1'b1;
      end else if (S_AXI_RVALID && S_AXI_RREADY) begin
        S_AXI_RVALID <= 1'b0;
      end
    end
  end
endmodule
