`timescale 1ns/1ps
// Non-destructive sticky IRQ aggregation. ACK means PCIe IP accepted the
// request for MSI transmission, not that a host ISR has completed.
module msi_source_controller(
 input wire clk,input wire resetn,input wire enable,
 input wire [3:0] irq_src, output reg req,input wire ack,
 output reg [3:0] notified, output reg [15:0] ack_count
);
 localparam IDLE=2'd0, WAIT_ACK=2'd1, WAIT_LOW=2'd2;
 reg [1:0] state;
 reg [3:0] active_mask;
 wire [3:0] unseen=irq_src & ~notified;
 always @(posedge clk or negedge resetn) begin
   if(!resetn) begin
     state<=IDLE;req<=0;notified<=0;ack_count<=0;active_mask<=0;
   end else begin
     notified<=notified & irq_src;
     case(state)
       IDLE: begin
         req<=0;
         if(enable && !ack && (|unseen)) begin
           active_mask<=unseen;req<=1;state<=WAIT_ACK;
         end
       end
       WAIT_ACK: if(ack) begin
         req<=0;
         notified<=(notified & irq_src) | (active_mask & irq_src);
         ack_count<=ack_count+1'b1;
         state<=WAIT_LOW;
       end
       WAIT_LOW: if(!ack) state<=IDLE;
       default: begin state<=IDLE;req<=0; end
     endcase
   end
 end
endmodule
