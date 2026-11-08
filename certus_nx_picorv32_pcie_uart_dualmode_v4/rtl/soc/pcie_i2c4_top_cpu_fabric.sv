`timescale 1ns/1ps
// This module is the integration point INSIDE your existing pcie_i2c4_top.sv.
// PCIe Endpoint IP is not instantiated here: its module/ports are IP-generated.
// All host AXI and SoC system clocks MUST share the SAME ACLK clock domain.
// Mode is switched by UART command using CPU local MMIO; no button/DIP needed.
module pcie_i2c4_top_cpu_fabric #(
 parameter integer CLK_HZ=125000000,
 parameter integer BAUD=115200,
 parameter integer CLK_DIV=312,
 parameter integer INITIAL_CPU_OWNER=1,
 parameter FIRMWARE_HEX="firmware.hex"
)(
 input wire clk,input wire resetn,
 input wire uart_rx,output wire uart_tx,
 output wire [7:0] leds,output wire cpu_trap,
 output wire cpu_owner,output wire [31:0] dbg_event,
 output wire [31:0] dbg_aux,output wire dbg_toggle,output wire dbg_pulse,
 inout wire [3:0] i2c_scl,inout wire [3:0] i2c_sda,
 output wire [3:0] dev_irq,
 input wire [15:0] host_awaddr,input wire host_awvalid,output wire host_awready,
 input wire [31:0] host_wdata,input wire [3:0] host_wstrb,
 input wire host_wvalid,output wire host_wready,
 output wire [1:0] host_bresp,output wire host_bvalid,input wire host_bready,
 input wire [15:0] host_araddr,input wire host_arvalid,output wire host_arready,
 output wire [31:0] host_rdata,output wire [1:0] host_rresp,
 output wire host_rvalid,input wire host_rready
);
 wire requested_cpu;
 wire [15:0] ca,cr,sa,sr;
 wire cvaw,crdyaw,cvw,crdyw,cvb,crdyb,cvar,crdyar,cvr,crdyr;
 wire svaw,srdyaw,svw,srdyw,svb,srdyb,svar,srdyar,svr,srdyr;
 wire [31:0] cwd,crd,swd,srd;
 wire [3:0] cws,sws;
 wire [1:0] cbp,crp,sbp,srp;
 wire switch_idle;
 wire srdyr_dummy; // active owner drives the shared AXI BREADY
 picorv32_cpu_axil_uart #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),
  .INITIAL_CPU_OWNER(INITIAL_CPU_OWNER),.FIRMWARE_HEX(FIRMWARE_HEX))
  u_cpu_subsystem (
    .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.dev_irq(dev_irq),
    .cpu_owner(cpu_owner),.requested_cpu(requested_cpu),
    .leds(leds),.uart_tx(uart_tx),.cpu_trap(cpu_trap),
    .dbg_event_q(dbg_event),.dbg_aux_q(dbg_aux),
    .dbg_toggle(dbg_toggle),.dbg_pulse(dbg_pulse),
    .m_awaddr(ca),.m_awvalid(cvaw),.m_awready(crdyaw),
    .m_wdata(cwd),.m_wstrb(cws),.m_wvalid(cvw),.m_wready(crdyw),
    .m_bresp(cbp),.m_bvalid(cvb),.m_bready(crdyb),
    .m_araddr(cr),.m_arvalid(cvar),.m_arready(crdyar),
    .m_rdata(crd),.m_rresp(crp),.m_rvalid(cvr),.m_rready(crdyr)
  );
 axil_master_mode_mux u_mux(
    .cpu_mode(cpu_owner),
    .c_awaddr(ca),.c_awvalid(cvaw),.c_awready(crdyaw),
    .c_wdata(cwd),.c_wstrb(cws),.c_wvalid(cvw),.c_wready(crdyw),
    .c_bresp(cbp),.c_bvalid(cvb),.c_bready(crdyb),
    .c_araddr(cr),.c_arvalid(cvar),.c_arready(crdyar),
    .c_rdata(crd),.c_rresp(crp),.c_rvalid(cvr),.c_rready(crdyr),
    .h_awaddr(host_awaddr),.h_awvalid(host_awvalid),.h_awready(host_awready),
    .h_wdata(host_wdata),.h_wstrb(host_wstrb),.h_wvalid(host_wvalid),.h_wready(host_wready),
    .h_bresp(host_bresp),.h_bvalid(host_bvalid),.h_bready(host_bready),
    .h_araddr(host_araddr),.h_arvalid(host_arvalid),.h_arready(host_arready),
    .h_rdata(host_rdata),.h_rresp(host_rresp),.h_rvalid(host_rvalid),.h_rready(host_rready),
    .s_awaddr(sa),.s_awvalid(svaw),.s_awready(srdyaw),
    .s_wdata(swd),.s_wstrb(sws),.s_wvalid(svw),.s_wready(srdyw),
    .s_bresp(sbp),.s_bvalid(svb),.s_bready(srdyr_dummy),
    .s_araddr(sr),.s_arvalid(svar),.s_arready(srdyar),
    .s_rdata(srd),.s_rresp(srp),.s_rvalid(svr),.s_rready(srdyr)
 );
 axil_owner_switch #(.INITIAL_CPU_OWNER(INITIAL_CPU_OWNER)) u_owner(
   .clk(clk),.resetn(resetn),.requested_cpu(requested_cpu),
   .s_awaddr(sa),.s_awvalid(svaw),.s_awready(srdyaw),
   .s_wvalid(svw),.s_wready(srdyw),
   .s_bvalid(svb),.s_bready(srdyr_dummy),
   .s_arvalid(svar),.s_arready(srdyar),
   .s_rvalid(svr),.s_rready(srdyr),
   .cpu_owner(cpu_owner),.idle(switch_idle)
 );
 wire [3:0] scl_in,sda_in,scl_oen,sda_oen;
 genvar i;
 generate for(i=0;i<4;i=i+1)begin:g_od
   assign i2c_scl[i]=scl_oen[i]?1'bz:1'b0;
   assign i2c_sda[i]=sda_oen[i]?1'bz:1'b0;
   assign scl_in[i]=i2c_scl[i];
   assign sda_in[i]=i2c_sda[i];
 end endgenerate
 axil_i2c4_regs #(.CLK_DIV(CLK_DIV)) u_regs (
   .ACLK(clk),.ARESETn(resetn),
   .S_AXI_AWADDR(sa),.S_AXI_AWVALID(svaw),.S_AXI_AWREADY(srdyaw),
   .S_AXI_WDATA(swd),.S_AXI_WSTRB(sws),.S_AXI_WVALID(svw),.S_AXI_WREADY(srdyw),
   .S_AXI_BRESP(sbp),.S_AXI_BVALID(svb),.S_AXI_BREADY(srdyr_dummy),
   .S_AXI_ARADDR(sr),.S_AXI_ARVALID(svar),.S_AXI_ARREADY(srdyar),
   .S_AXI_RDATA(srd),.S_AXI_RRESP(srp),.S_AXI_RVALID(svr),.S_AXI_RREADY(srdyr),
   .i2c_scl_in(scl_in),.i2c_sda_in(sda_in),
   .i2c_scl_oen(scl_oen),.i2c_sda_oen(sda_oen),.dev_irq(dev_irq)
 );
endmodule
