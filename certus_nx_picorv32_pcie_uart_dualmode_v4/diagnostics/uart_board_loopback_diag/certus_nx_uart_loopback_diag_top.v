`timescale 1ns/1ps
// Board diagnostic: original UART RX/TX, direct hardware echo, no CPU/firmware.
// Ports match certus_nx_picorv32_uart_standalone_top for existing board PDC.
module certus_nx_uart_loopback_diag_top #(
  parameter integer CLK_HZ = 125000000,
  parameter integer BAUD = 115200,
  parameter integer LED_ACTIVE_LOW = 1
)(
  input wire clk,
  input wire resetn,
  input wire uart_rx,
  output wire uart_tx,
  output wire [7:0] leds,
  inout wire [3:0] i2c_scl,
  inout wire [3:0] i2c_sda
);
  // This diagnostic does not initiate I2C transfers.
  assign i2c_scl = 4'bzzzz;
  assign i2c_sda = 4'bzzzz;

  wire [7:0] rx_data;
  wire rx_valid, rx_overrun, tx_ready;
  reg banner_active;
  reg [3:0] banner_index;
  wire echo_fire = !banner_active && rx_valid && tx_ready;
  wire tx_fire = tx_ready && (banner_active || rx_valid);
  wire [7:0] tx_data;

  function [7:0] banner_byte;
    input [3:0] index;
    begin
      case (index)
        0: banner_byte = "U";
        1: banner_byte = "A";
        2: banner_byte = "R";
        3: banner_byte = "T";
        4: banner_byte = " ";
        5: banner_byte = "R";
        6: banner_byte = "X";
        7: banner_byte = " ";
        8: banner_byte = "D";
        9: banner_byte = "I";
        10: banner_byte = "A";
        11: banner_byte = "G";
        12: banner_byte = 8'h0d;
        13: banner_byte = 8'h0a;
        default: banner_byte = 8'h20;
      endcase
    end
  endfunction
  assign tx_data = banner_active ? banner_byte(banner_index) : rx_data;

  uart_rx_byte #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart_rx (
    .clk(clk), .resetn(resetn), .serial_rx(uart_rx), .pop(echo_fire),
    .data(rx_data), .valid(rx_valid), .overrun(rx_overrun)
  );
  uart_tx_mmio #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart_tx (
    .clk(clk), .resetn(resetn), .tx_fire(tx_fire), .tx_data(tx_data),
    .tx_ready(tx_ready), .uart_tx(uart_tx)
  );

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      banner_active <= 1'b1;
      banner_index <= 0;
    end else if (banner_active && tx_fire) begin
      if (banner_index == 13) banner_active <= 1'b0;
      else banner_index <= banner_index + 1'b1;
    end
  end

  // Sticky event LEDs preserve short RX/echo events until reset.
  reg rx_meta, rx_sync;
  reg rx_low_seen, rx_valid_seen, echo_seen, overrun_seen;
  reg heartbeat;
  reg [31:0] heartbeat_count;
  localparam integer HEARTBEAT_TICKS = (CLK_HZ >= 4) ? CLK_HZ / 4 : 1;
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_meta <= 1'b1;
      rx_sync <= 1'b1;
      rx_low_seen <= 1'b0;
      rx_valid_seen <= 1'b0;
      echo_seen <= 1'b0;
      overrun_seen <= 1'b0;
      heartbeat <= 1'b0;
      heartbeat_count <= 0;
    end else begin
      rx_meta <= uart_rx;
      rx_sync <= rx_meta;
      if (!rx_sync) rx_low_seen <= 1'b1;
      if (rx_valid) rx_valid_seen <= 1'b1;
      if (echo_fire) echo_seen <= 1'b1;
      if (rx_overrun) overrun_seen <= 1'b1;
      if (heartbeat_count == HEARTBEAT_TICKS - 1) begin
        heartbeat_count <= 0;
        heartbeat <= !heartbeat;
      end else heartbeat_count <= heartbeat_count + 1'b1;
    end
  end

  // Logical LED7/6/5 are always off. LED0 is a HARDWARE heartbeat here.
  wire [7:0] led_raw = {3'b000, overrun_seen, echo_seen,
                        rx_valid_seen, rx_low_seen, heartbeat};
  assign leds = led_raw ^ {8{LED_ACTIVE_LOW != 0}};
endmodule
