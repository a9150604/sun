`timescale 1ns/1ps
// Stub only the two fabrics: test the real top-level LED expression for every
// raw pattern, without CPU/firmware/UART simulation.
`define FABRIC_PARAMETERS \
 parameter integer CLK_HZ=125000000, BAUD=115200, CLK_DIV=625, \
 parameter integer INITIAL_CPU_OWNER=1, parameter FIRMWARE_HEX="unused.hex"
`define FABRIC_PORTS \
 input wire clk,resetn,uart_rx,output wire uart_tx,output reg [7:0] leds=0, \
 output wire cpu_trap,cpu_owner,output wire [31:0] dbg_event,dbg_aux, \
 output wire dbg_toggle,dbg_pulse,inout wire [3:0] i2c_scl,i2c_sda, \
 output wire [3:0] dev_irq, \
 input wire [15:0] host_awaddr,input wire host_awvalid,output wire host_awready, \
 input wire [31:0] host_wdata,input wire [3:0] host_wstrb, \
 input wire host_wvalid,output wire host_wready, \
 output wire [1:0] host_bresp,output wire host_bvalid,input wire host_bready, \
 input wire [15:0] host_araddr,input wire host_arvalid,output wire host_arready, \
 output wire [31:0] host_rdata,output wire [1:0] host_rresp, \
 output wire host_rvalid,input wire host_rready
`define FABRIC_BODY \
 assign uart_tx=1; \
 assign {cpu_trap,cpu_owner,dbg_event,dbg_aux,dbg_toggle,dbg_pulse,dev_irq, \
 host_awready,host_wready,host_bresp,host_bvalid,host_arready,host_rdata, \
 host_rresp,host_rvalid}='0; \
 assign i2c_scl=4'bzzzz;assign i2c_sda=4'bzzzz;

module pcie_i2c4_top_cpu_fabric #(`FABRIC_PARAMETERS)(`FABRIC_PORTS);
  `FABRIC_BODY
endmodule
module pcie_i2c4_top_cpu_diag_fabric #(`FABRIC_PARAMETERS)(`FABRIC_PORTS);
  `FABRIC_BODY
endmodule
`undef FABRIC_PARAMETERS
`undef FABRIC_PORTS
`undef FABRIC_BODY

module tb_led_polarity;
  localparam integer ACTIVE_LOW=1;
  wire [7:0] old_mask={8{ACTIVE_LOW}};
  wire [7:0] fixed_mask={8{ACTIVE_LOW != 0}};
  wire [7:0] standalone_high,standalone_low,diag_high,diag_low;
  wire tx0,tx1,tx2,tx3;
  tri [3:0] scl0,sda0,scl1,sda1,scl2,sda2,scl3,sda3;
  integer pattern;
  integer checks=0;
  reg [7:0] expected;
  certus_nx_picorv32_uart_standalone_top #(.LED_ACTIVE_LOW(0)) original_high (
    .clk(1'b0),.resetn(1'b1),.uart_rx(1'b1),.uart_tx(tx0),
    .leds(standalone_high),.i2c_scl(scl0),.i2c_sda(sda0)
  );
  certus_nx_picorv32_uart_standalone_top #(.LED_ACTIVE_LOW(1)) original_low (
    .clk(1'b0),.resetn(1'b1),.uart_rx(1'b1),.uart_tx(tx1),
    .leds(standalone_low),.i2c_scl(scl1),.i2c_sda(sda1)
  );
  certus_nx_picorv32_uart_cpu_diag_top #(.LED_ACTIVE_LOW(0)) trace_high (
    .clk(1'b0),.resetn(1'b1),.uart_rx(1'b1),.uart_tx(tx2),
    .leds(diag_high),.i2c_scl(scl2),.i2c_sda(sda2)
  );
  certus_nx_picorv32_uart_cpu_diag_top #(.LED_ACTIVE_LOW(1)) trace_low (
    .clk(1'b0),.resetn(1'b1),.uart_rx(1'b1),.uart_tx(tx3),
    .leds(diag_low),.i2c_scl(scl3),.i2c_sda(sda3)
  );
  initial begin
    #1;
    if(old_mask!==8'h01 || fixed_mask!==8'hff)
      $fatal(1,"Reproducer failed: old=%02x fixed=%02x",old_mask,fixed_mask);
    $display("REPRODUCED: integer LED_ACTIVE_LOW=1 yields old mask=%02x, corrected Boolean mask=%02x",old_mask,fixed_mask);
    for(pattern=0;pattern<256;pattern=pattern+1) begin
      expected=pattern[7:0];
      original_high.u_soc.leds=expected;
      original_low.u_soc.leds=expected;
      trace_high.u_soc.leds=expected;
      trace_low.u_soc.leds=expected;
      #1;
      if(standalone_high!==expected)
        $fatal(1,"Standalone active-high raw=%02x got=%02x",expected,standalone_high);
      if(standalone_low!==(~expected))
        $fatal(1,"Standalone active-low raw=%02x got=%02x",expected,standalone_low);
      if(diag_high!==expected)
        $fatal(1,"Diagnostic active-high raw=%02x got=%02x",expected,diag_high);
      if(diag_low!==(~expected))
        $fatal(1,"Diagnostic active-low raw=%02x got=%02x",expected,diag_low);
      checks=checks+4;
    end
    $display("PASS: %0d LED polarity checks (256 raw patterns x two polarities x standalone/CPU-diagnostic tops)",checks);
    $finish;
  end
endmodule
