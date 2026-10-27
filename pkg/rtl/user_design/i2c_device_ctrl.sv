`timescale 1ns/1ps
import i2c4_pkg::*;

// -----------------------------------------------------------------------------
// One I2C device controller.
// - Auto polling: repeatedly reads register 0..7 and stores shadow data.
// - Direct command: CPU can read/write any one register through AXI-Lite regs.
// - Direct command priority is higher than auto polling when this block is idle.
// - Three-block FSM style.
// -----------------------------------------------------------------------------
module i2c_device_ctrl #(
  parameter int CLK_DIV = 250
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        auto_enable,
  input  logic [6:0]  dev_addr,
  input  logic [15:0] poll_gap,

  input  logic        direct_start,
  input  logic        direct_rw,
  input  logic [7:0]  direct_reg_addr,
  input  logic [7:0]  direct_wr_data,
  input  logic [7:0]  poll_reg_addr0,
  input  logic [7:0]  poll_reg_addr1,
  input  logic [7:0]  poll_reg_addr2,
  input  logic [7:0]  poll_reg_addr3,
  input  logic [7:0]  poll_reg_addr4,
  input  logic [7:0]  poll_reg_addr5,
  input  logic [7:0]  poll_reg_addr6,
  input  logic [7:0]  poll_reg_addr7,
  output logic [7:0]  direct_rd_data,
  output logic        direct_done,
  output logic        direct_ack_error,

  output logic        busy,
  output logic        auto_valid,
  output logic [2:0]  auto_poll_idx,
  output logic        irq,
  input  logic        irq_clear,

  output logic [7:0]  shadow_r0,
  output logic [7:0]  shadow_r1,
  output logic [7:0]  shadow_r2,
  output logic [7:0]  shadow_r3,
  output logic [7:0]  shadow_r4,
  output logic [7:0]  shadow_r5,
  output logic [7:0]  shadow_r6,
  output logic [7:0]  shadow_r7,

  input  logic        scl_in,
  input  logic        sda_in,
  output logic        scl_oen,
  output logic        sda_oen
);

  dev_ctrl_state_e state_q, state_d;
  op_src_e         op_src_q, op_src_d;

  logic [15:0] gap_cnt_q;
  logic        mst_start;
  logic        mst_rw;
  logic [7:0]  mst_reg_addr;
  logic [7:0]  mst_wr_data;
  logic        mst_busy;
  logic        mst_done;
  logic        mst_ack_error;
  logic [7:0]  mst_rd_data;
  logic [7:0]  shadow_q [8];
  logic [7:0]  poll_reg_addr_mux;

  always_comb begin
    unique case (auto_poll_idx)
      3'd0: poll_reg_addr_mux = poll_reg_addr0;
      3'd1: poll_reg_addr_mux = poll_reg_addr1;
      3'd2: poll_reg_addr_mux = poll_reg_addr2;
      3'd3: poll_reg_addr_mux = poll_reg_addr3;
      3'd4: poll_reg_addr_mux = poll_reg_addr4;
      3'd5: poll_reg_addr_mux = poll_reg_addr5;
      3'd6: poll_reg_addr_mux = poll_reg_addr6;
      default: poll_reg_addr_mux = poll_reg_addr7;
    endcase
  end

  assign shadow_r0 = shadow_q[0];
  assign shadow_r1 = shadow_q[1];
  assign shadow_r2 = shadow_q[2];
  assign shadow_r3 = shadow_q[3];
  assign shadow_r4 = shadow_q[4];
  assign shadow_r5 = shadow_q[5];
  assign shadow_r6 = shadow_q[6];
  assign shadow_r7 = shadow_q[7];

  i2c_master_byte #(.CLK_DIV(CLK_DIV)) u_i2c_master_byte (
    .clk(clk),
    .rst_n(rst_n),
    .start(mst_start),
    .rw(mst_rw),
    .dev_addr(dev_addr),
    .reg_addr(mst_reg_addr),
    .wr_data(mst_wr_data),
    .busy(mst_busy),
    .done(mst_done),
    .ack_error(mst_ack_error),
    .rd_data(mst_rd_data),
    .scl_in(scl_in),
    .sda_in(sda_in),
    .scl_oen(scl_oen),
    .sda_oen(sda_oen)
  );

  // 1) FSM state register.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= DEV_ST_IDLE;
      op_src_q <= OP_AUTO;
    end else begin
      state_q  <= state_d;
      op_src_q <= op_src_d;
    end
  end

  // 2) Next-state combinational logic.
  always_comb begin
    state_d  = state_q;
    op_src_d = op_src_q;

    unique case (state_q)
      DEV_ST_IDLE: begin
        if (direct_start) begin
          state_d  = DEV_ST_START_DIR;
          op_src_d = OP_DIR;
        end else if (auto_enable) begin
          state_d  = DEV_ST_GAP;
          op_src_d = OP_AUTO;
        end
      end
      DEV_ST_GAP: begin
        if (direct_start) begin
          state_d  = DEV_ST_START_DIR;
          op_src_d = OP_DIR;
        end else if (!auto_enable) begin
          state_d = DEV_ST_IDLE;
        end else if (gap_cnt_q >= poll_gap) begin
          state_d  = DEV_ST_START_AUTO;
          op_src_d = OP_AUTO;
        end
      end
      DEV_ST_START_AUTO: state_d = DEV_ST_WAIT;
      DEV_ST_START_DIR : state_d = DEV_ST_WAIT;
      DEV_ST_WAIT      : if (mst_done) state_d = DEV_ST_SAVE;
      DEV_ST_SAVE      : state_d = DEV_ST_IDLE;
      default          : state_d = DEV_ST_IDLE;
    endcase
  end

  // 3) Registered outputs and datapath.
  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mst_start        <= 1'b0;
      mst_rw           <= 1'b0;
      mst_reg_addr     <= '0;
      mst_wr_data      <= '0;
      direct_rd_data   <= '0;
      direct_done      <= 1'b0;
      direct_ack_error <= 1'b0;
      busy             <= 1'b0;
      auto_valid       <= 1'b0;
      auto_poll_idx    <= 3'd0;
      irq              <= 1'b0;
      gap_cnt_q        <= '0;
      for (i = 0; i < 8; i++) shadow_q[i] <= '0;
    end else begin
      mst_start   <= 1'b0;

      if (irq_clear) begin
        irq              <= 1'b0;
        direct_done      <= 1'b0;
        direct_ack_error <= 1'b0;
      end

      unique case (state_q)
        DEV_ST_IDLE: begin
          busy      <= 1'b0;
          gap_cnt_q <= '0;
        end
        DEV_ST_GAP: begin
          busy <= 1'b0;
          if (gap_cnt_q < poll_gap) gap_cnt_q <= gap_cnt_q + 16'd1;
        end
        DEV_ST_START_AUTO: begin
          busy         <= 1'b1;
          mst_start    <= 1'b1;
          mst_rw       <= 1'b1;
          mst_reg_addr <= poll_reg_addr_mux;
          mst_wr_data  <= 8'd0;
          gap_cnt_q    <= '0;
        end
        DEV_ST_START_DIR: begin
          busy             <= 1'b1;
          mst_start        <= 1'b1;
          // Clear stale completion/error state at the start of a new direct command.
          direct_done      <= 1'b0;
          direct_ack_error <= 1'b0;
          irq              <= 1'b0;
          mst_rw           <= direct_rw;
          mst_reg_addr <= direct_reg_addr;
          mst_wr_data  <= direct_wr_data;
          gap_cnt_q    <= '0;
        end
        DEV_ST_WAIT: begin
          busy <= 1'b1;
        end
        DEV_ST_SAVE: begin
          busy <= 1'b0;
          if (op_src_q == OP_DIR) begin
            direct_rd_data   <= mst_rd_data;
            direct_ack_error <= mst_ack_error;
            direct_done      <= 1'b1;
            irq              <= 1'b1;
          end else begin
            if (!mst_ack_error) begin
              shadow_q[auto_poll_idx] <= mst_rd_data;
              auto_valid              <= 1'b1;
            end
            auto_poll_idx <= (auto_poll_idx == 3'd7) ? 3'd0 : auto_poll_idx + 3'd1;
          end
        end
        default: ;
      endcase
    end
  end
endmodule
