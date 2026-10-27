`timescale 1ns/1ps
// STATIC mode selection, NOT a live arbiter. Latch cpu_mode only during reset
// and hold fixed for all outstanding transactions. Never toggle mode on the fly.
module axil_master_mode_mux (
 input wire cpu_mode,
 input wire [15:0] c_awaddr,input wire c_awvalid,output wire c_awready,
 input wire [31:0] c_wdata,input wire [3:0] c_wstrb,input wire c_wvalid,output wire c_wready,
 output wire [1:0] c_bresp,output wire c_bvalid,input wire c_bready,
 input wire [15:0] c_araddr,input wire c_arvalid,output wire c_arready,
 output wire [31:0] c_rdata,output wire [1:0] c_rresp,output wire c_rvalid,input wire c_rready,
 input wire [15:0] h_awaddr,input wire h_awvalid,output wire h_awready,
 input wire [31:0] h_wdata,input wire [3:0] h_wstrb,input wire h_wvalid,output wire h_wready,
 output wire [1:0] h_bresp,output wire h_bvalid,input wire h_bready,
 input wire [15:0] h_araddr,input wire h_arvalid,output wire h_arready,
 output wire [31:0] h_rdata,output wire [1:0] h_rresp,output wire h_rvalid,input wire h_rready,
 output wire [15:0] s_awaddr,output wire s_awvalid,input wire s_awready,
 output wire [31:0] s_wdata,output wire [3:0] s_wstrb,output wire s_wvalid,input wire s_wready,
 input wire [1:0] s_bresp,input wire s_bvalid,output wire s_bready,
 output wire [15:0] s_araddr,output wire s_arvalid,input wire s_arready,
 input wire [31:0] s_rdata,input wire [1:0] s_rresp,input wire s_rvalid,output wire s_rready
);
 assign s_awaddr=cpu_mode?c_awaddr:h_awaddr;
 assign s_awvalid=cpu_mode?c_awvalid:h_awvalid;
 assign s_wdata=cpu_mode?c_wdata:h_wdata;
 assign s_wstrb=cpu_mode?c_wstrb:h_wstrb;
 assign s_wvalid=cpu_mode?c_wvalid:h_wvalid;
 assign s_bready=cpu_mode?c_bready:h_bready;
 assign s_araddr=cpu_mode?c_araddr:h_araddr;
 assign s_arvalid=cpu_mode?c_arvalid:h_arvalid;
 assign s_rready=cpu_mode?c_rready:h_rready;
 assign c_awready=cpu_mode?s_awready:1'b0;
 assign h_awready=cpu_mode?1'b0:s_awready;
 assign c_wready=cpu_mode?s_wready:1'b0;
 assign h_wready=cpu_mode?1'b0:s_wready;
 assign c_bresp=s_bresp;assign h_bresp=s_bresp;
 assign c_bvalid=cpu_mode?s_bvalid:1'b0;
 assign h_bvalid=cpu_mode?1'b0:s_bvalid;
 assign c_arready=cpu_mode?s_arready:1'b0;
 assign h_arready=cpu_mode?1'b0:s_arready;
 assign c_rdata=s_rdata; assign h_rdata=s_rdata;
 assign c_rresp=s_rresp; assign h_rresp=s_rresp;
 assign c_rvalid=cpu_mode?s_rvalid:1'b0;
 assign h_rvalid=cpu_mode?1'b0:s_rvalid;
endmodule
