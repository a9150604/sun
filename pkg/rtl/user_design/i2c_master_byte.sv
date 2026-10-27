`timescale 1ns/1ps
import i2c4_pkg::*;

// -----------------------------------------------------------------------------
// SystemVerilog I2C single-byte master.
// Three-block FSM style:
//   1. state register: always_ff
//   2. next-state logic: always_comb
//   3. registered outputs/datapath: always_ff
//
// Supported transactions:
//   WRITE: START + slave_addr/W + reg_addr + wr_data + STOP
//   READ : START + slave_addr/W + reg_addr + repeated START + slave_addr/R
//          + rd_data + master NACK + STOP
//
// Open-drain rule:
//   scl_oen/sda_oen = 1 => release/high-Z
//   scl_oen/sda_oen = 0 => drive low
// -----------------------------------------------------------------------------
module i2c_master_byte #(
  parameter int CLK_DIV = 250
)(
  input  logic       clk,
  input  logic       rst_n,

  input  logic       start,
  input  logic       rw,          // 0=write, 1=read
  input  logic [6:0] dev_addr,
  input  logic [7:0] reg_addr,
  input  logic [7:0] wr_data,

  output logic       busy,
  output logic       done,
  output logic       ack_error,
  output logic [7:0] rd_data,

  input  logic       scl_in,
  input  logic       sda_in,
  output logic       scl_oen,
  output logic       sda_oen
);

  i2c_mst_state_e state_q, state_d;
  i2c_phase_e     phase_q, phase_d;

  logic [15:0] div_cnt_q;
  logic        tick_q;
  logic [7:0]  shifter_q;
  logic [2:0]  bit_cnt_q;
  logic        op_rw_q;
  logic [6:0]  op_dev_addr_q;
  logic [7:0]  op_reg_addr_q;
  logic [7:0]  op_wr_data_q;

  // Quarter-period tick generator for I2C state transitions.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_cnt_q <= '0;
      tick_q    <= 1'b0;
    end else begin
      if (busy) begin
        if (div_cnt_q == CLK_DIV-1) begin
          div_cnt_q <= '0;
          tick_q    <= 1'b1;
        end else begin
          div_cnt_q <= div_cnt_q + 16'd1;
          tick_q    <= 1'b0;
        end
      end else begin
        div_cnt_q <= '0;
        tick_q    <= 1'b0;
      end
    end
  end

  // 1) FSM state register.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= I2C_ST_IDLE;
      phase_q <= I2C_PH_ADDR_W;
    end else begin
      state_q <= state_d;
      phase_q <= phase_d;
    end
  end

  // 2) Next-state combinational logic.
  always_comb begin
    state_d = state_q;
    phase_d = phase_q;

    unique case (state_q)
      I2C_ST_IDLE: begin
        if (start) begin
          state_d = I2C_ST_START_A;
          phase_d = I2C_PH_ADDR_W;
        end
      end
      I2C_ST_START_A:   if (tick_q) state_d = I2C_ST_START_B;
      I2C_ST_START_B:   if (tick_q) state_d = I2C_ST_LOAD_BYTE;
      I2C_ST_LOAD_BYTE: if (tick_q) state_d = (phase_q == I2C_PH_RDATA) ? I2C_ST_RX_LOW : I2C_ST_BIT_LOW;
      I2C_ST_BIT_LOW:   if (tick_q) state_d = I2C_ST_BIT_HIGH;
      I2C_ST_BIT_HIGH:  if (tick_q) state_d = (bit_cnt_q == 3'd0) ? I2C_ST_ACK_LOW : I2C_ST_BIT_LOW;
      I2C_ST_ACK_LOW:   if (tick_q) state_d = I2C_ST_ACK_HIGH;
      I2C_ST_ACK_HIGH:  if (tick_q) begin
        if (ack_error) begin
          state_d = I2C_ST_STOP_A;
        end else begin
          unique case (phase_q)
            I2C_PH_ADDR_W: begin
              state_d = I2C_ST_LOAD_BYTE;
              phase_d = I2C_PH_REG;
            end
            I2C_PH_REG: begin
              if (op_rw_q) begin
                state_d = I2C_ST_RESTART_A;
                phase_d = I2C_PH_ADDR_R;
              end else begin
                state_d = I2C_ST_LOAD_BYTE;
                phase_d = I2C_PH_WDATA;
              end
            end
            I2C_PH_WDATA: begin
              state_d = I2C_ST_STOP_A;
            end
            I2C_PH_ADDR_R: begin
              state_d = I2C_ST_LOAD_BYTE;
              phase_d = I2C_PH_RDATA;
            end
            default: state_d = I2C_ST_STOP_A;
          endcase
        end
      end
      I2C_ST_RX_LOW:    if (tick_q) state_d = I2C_ST_RX_HIGH;
      I2C_ST_RX_HIGH:   if (tick_q) state_d = (bit_cnt_q == 3'd0) ? I2C_ST_MACK_LOW : I2C_ST_RX_LOW;
      I2C_ST_MACK_LOW:  if (tick_q) state_d = I2C_ST_MACK_HIGH;
      I2C_ST_MACK_HIGH: if (tick_q) state_d = I2C_ST_STOP_A;
      // Repeated START must first generate a SCL-low phase after the ACK bit.
      // This gives the slave a real SCL falling edge to release its ACK drive.
      // Then SDA is driven low while SCL is high, which the slave detects as
      // repeated START.
      I2C_ST_RESTART_A: if (tick_q) state_d = I2C_ST_RESTART_B;
      I2C_ST_RESTART_B: if (tick_q) state_d = I2C_ST_RESTART_C;
      I2C_ST_RESTART_C: if (tick_q) state_d = I2C_ST_LOAD_BYTE;
      I2C_ST_STOP_A:    if (tick_q) state_d = I2C_ST_STOP_B;
      I2C_ST_STOP_B:    if (tick_q) state_d = I2C_ST_DONE;
      I2C_ST_DONE:    if (tick_q) state_d = I2C_ST_IDLE;
      default:                      state_d = I2C_ST_IDLE;
    endcase
  end

  // 3) Registered outputs and datapath.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy          <= 1'b0;
      done          <= 1'b0;
      ack_error     <= 1'b0;
      rd_data       <= '0;
      scl_oen       <= 1'b1;
      sda_oen       <= 1'b1;
      shifter_q     <= '0;
      bit_cnt_q     <= 3'd7;
      op_rw_q       <= 1'b0;
      op_dev_addr_q <= '0;
      op_reg_addr_q <= '0;
      op_wr_data_q  <= '0;
    end else begin
      done <= 1'b0;

      if (state_q == I2C_ST_IDLE && start) begin
        busy          <= 1'b1;
        ack_error     <= 1'b0;
        op_rw_q       <= rw;
        op_dev_addr_q <= dev_addr;
        op_reg_addr_q <= reg_addr;
        op_wr_data_q  <= wr_data;
      end

      if (tick_q) begin
        unique case (state_q)
          I2C_ST_START_A: begin
            scl_oen <= 1'b1;
            sda_oen <= 1'b1;
          end
          I2C_ST_START_B: begin
            scl_oen <= 1'b1;
            sda_oen <= 1'b0;
          end
          I2C_ST_LOAD_BYTE: begin
            scl_oen   <= 1'b0;
            sda_oen   <= 1'b1;
            bit_cnt_q <= 3'd7;
            unique case (phase_q)
              I2C_PH_ADDR_W: shifter_q <= {op_dev_addr_q, 1'b0};
              I2C_PH_REG:    shifter_q <= op_reg_addr_q;
              I2C_PH_WDATA:  shifter_q <= op_wr_data_q;
              I2C_PH_ADDR_R: shifter_q <= {op_dev_addr_q, 1'b1};
              default:       shifter_q <= 8'hFF;
            endcase
          end
          I2C_ST_BIT_LOW: begin
            scl_oen <= 1'b0;
            sda_oen <= shifter_q[7] ? 1'b1 : 1'b0;
          end
          I2C_ST_BIT_HIGH: begin
            scl_oen <= 1'b1;
            if (bit_cnt_q != 3'd0) begin
              shifter_q <= {shifter_q[6:0], 1'b0};
              bit_cnt_q <= bit_cnt_q - 3'd1;
            end
          end
          I2C_ST_ACK_LOW: begin
            scl_oen <= 1'b0;
            sda_oen <= 1'b1;
          end
          I2C_ST_ACK_HIGH: begin
            scl_oen <= 1'b1;
            if (sda_in) ack_error <= 1'b1;
          end
          I2C_ST_RX_LOW: begin
            scl_oen <= 1'b0;
            sda_oen <= 1'b1;
          end
          I2C_ST_RX_HIGH: begin
            scl_oen <= 1'b1;
            rd_data[bit_cnt_q] <= sda_in;
            if (bit_cnt_q != 3'd0) bit_cnt_q <= bit_cnt_q - 3'd1;
          end
          I2C_ST_MACK_LOW: begin
            scl_oen <= 1'b0;
            sda_oen <= 1'b1; // NACK after one-byte read.
          end
          I2C_ST_MACK_HIGH: begin
            scl_oen <= 1'b1;
          end
          I2C_ST_RESTART_A: begin
            // Prepare repeated START after ACK: pull SCL low and release SDA.
            // The SCL falling edge allows the slave model/device to release ACK.
            scl_oen <= 1'b0;
            sda_oen <= 1'b1;
          end
          I2C_ST_RESTART_B: begin
            // Bring bus to repeated-START setup condition: SCL high, SDA high.
            scl_oen <= 1'b1;
            sda_oen <= 1'b1;
          end
          I2C_ST_RESTART_C: begin
            // Repeated START event: SDA falling while SCL is high.
            scl_oen <= 1'b1;
            sda_oen <= 1'b0;
          end
          I2C_ST_STOP_A: begin
            scl_oen <= 1'b0;
            sda_oen <= 1'b0;
          end
          I2C_ST_STOP_B: begin
            scl_oen <= 1'b1;
            sda_oen <= 1'b1;
          end
          I2C_ST_DONE: begin
            busy    <= 1'b0;
            done    <= 1'b1;
            scl_oen <= 1'b1;
            sda_oen <= 1'b1;
          end
          default: ;
        endcase
      end
    end
  end

  // Simple safety assertion for simulation/formal sanity.
`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      assert (!(done && busy)) else $error("done and busy should not be high together");
    end
  end
`endif
endmodule
