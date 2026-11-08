`timescale 1ns/1ps
// UART-requested AXI-Lite master owner switch: 1=CPU, 0=PCIe.
// Wait until the current master's outstanding AW/W/B and AR/R transfers drain.
// No automatic preemption; software must quiesce PCIe driver before mode switch.
module axil_owner_switch #(
 parameter INITIAL_CPU_OWNER=1
)(
 input wire clk,input wire resetn,input wire requested_cpu,
 input wire [15:0] s_awaddr,input wire s_awvalid,input wire s_awready,
 input wire s_wvalid,input wire s_wready,
 input wire s_bvalid,input wire s_bready,
 input wire s_arvalid,input wire s_arready,
 input wire s_rvalid,input wire s_rready,
 output reg cpu_owner,output wire idle
);
 reg got_aw,got_w,waiting_b,waiting_r;
 wire aw_fire=s_awvalid&&s_awready;
 wire w_fire=s_wvalid&&s_wready;
 wire b_fire=s_bvalid&&s_bready;
 wire ar_fire=s_arvalid&&s_arready;
 wire r_fire=s_rvalid&&s_rready;
 // Prevent switch when a valid request is present (even if not yet accepted).
 assign idle=!(got_aw||got_w||waiting_b||waiting_r||
          s_awvalid||s_wvalid||s_bvalid||s_arvalid||s_rvalid);
 always @(posedge clk or negedge resetn) begin
  if(!resetn) begin
    cpu_owner<=INITIAL_CPU_OWNER;got_aw<=0;got_w<=0;
    waiting_b<=0;waiting_r<=0;
  end else begin
    if(aw_fire)got_aw<=1;
    if(w_fire)got_w<=1;
    if((got_aw||aw_fire)&&(got_w||w_fire))begin
      got_aw<=0;got_w<=0;waiting_b<=1;
    end
    if(b_fire)waiting_b<=0;
    if(ar_fire)waiting_r<=1;
    if(r_fire)waiting_r<=0;
    if(idle)cpu_owner<=requested_cpu;
  end
 end
endmodule
