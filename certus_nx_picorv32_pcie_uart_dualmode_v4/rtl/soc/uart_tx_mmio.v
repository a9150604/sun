`timescale 1ns/1ps
// 8N1 UART TX. CPU memory bus stalls until tx_ready, so no characters are lost.
module uart_tx_mmio #(
  parameter integer CLK_HZ=50000000,
  parameter integer BAUD=115200
)(
  input wire clk, input wire resetn,
  input wire tx_fire, input wire [7:0] tx_data,
  output wire tx_ready, output reg uart_tx
);
  localparam integer INIT_DIV=(CLK_HZ+BAUD/2)/BAUD;
  localparam integer DIV=(INIT_DIV<2)?2:INIT_DIV;
  reg [31:0] divider;
  reg [31:0] tick_count;
  reg [9:0] shift_q;
  reg [3:0] bits_left;
  assign tx_ready=(bits_left==0);
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      uart_tx<=1'b1; divider<=DIV; tick_count<=0;
      shift_q<=10'h3ff; bits_left<=0;
    end else if (tx_fire && tx_ready) begin
      // bit0 START=0, then 8 data bits LSB-first, then STOP=1.
      shift_q<={1'b1,tx_data,1'b0};
      uart_tx<=1'b0; bits_left<=10; tick_count<=DIV-1;
    end else if (bits_left!=0) begin
      if (tick_count!=0) tick_count<=tick_count-1;
      else begin
        tick_count<=divider-1;
        shift_q<={1'b1,shift_q[9:1]};
        bits_left<=bits_left-1;
        uart_tx<=shift_q[1];
      end
    end else uart_tx<=1'b1;
  end
endmodule
