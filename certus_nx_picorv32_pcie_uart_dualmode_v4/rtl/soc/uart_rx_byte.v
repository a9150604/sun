`timescale 1ns/1ps
// Small UART RX, 8N1, 1-byte holding register, no FIFO. Read pop clears valid.
// Async input synchronizer; samples at middle of bit periods. Same sysclk domain.
module uart_rx_byte #(
 parameter integer CLK_HZ=125000000,
 parameter integer BAUD=115200
)(
 input wire clk, input wire resetn, input wire serial_rx,
 input wire pop, output reg [7:0] data,
 output reg valid, output reg overrun
);
 localparam integer D0=(CLK_HZ+BAUD/2)/BAUD;
 localparam integer DIV=(D0<4)?4:D0;
 reg rx_meta,rx_sync;
 reg [15:0] count;
 reg [3:0] bit_pos;
 reg [7:0] shift;
 reg [1:0] state;
 localparam IDLE=0,START=1,DATA=2,STOP=3;
 always @(posedge clk or negedge resetn) begin
  if(!resetn) begin
    rx_meta<=1;rx_sync<=1;count<=0;bit_pos<=0;shift<=0;
    state<=IDLE;data<=0;valid<=0;overrun<=0;
  end else begin
    rx_meta<=serial_rx;rx_sync<=rx_meta;
    if(pop) begin valid<=0;overrun<=0;end
    case(state)
      IDLE: if(!rx_sync) begin count<=DIV/2;state<=START;end
      START: if(count!=0) count<=count-1;
             else if(!rx_sync) begin count<=DIV-1;bit_pos<=0;state<=DATA;end
             else state<=IDLE;
      DATA: if(count!=0) count<=count-1;
            else begin
              shift[bit_pos]<=rx_sync;count<=DIV-1;
              if(bit_pos==7)state<=STOP;
              else bit_pos<=bit_pos+1;
            end
      STOP: if(count!=0) count<=count-1;
            else begin
              if(rx_sync) begin
                if(valid && !pop) overrun<=1;
                else begin data<=shift;valid<=1;end
              end
              state<=IDLE;
            end
      default:state<=IDLE;
    endcase
  end
 end
endmodule
