`timescale 1ns/1ps
// Standalone board smoke test (no PCIe IP required). Ideal as first bring-up.
// CPU is permanently the I2C AXI-Lite master. Same SOC as integrated version.
// 125 MHz sysclk is an EXAMPLE; set CLK_HZ and use your board's real clock.
module certus_nx_picorv32_uart_standalone_top #(
  parameter integer CLK_HZ=125000000,
  parameter integer BAUD=115200,
  parameter integer I2C_CLK_DIV=312,
  parameter integer LED_ACTIVE_LOW=0,
  parameter FIRMWARE_HEX="firmware.hex"
)(
  input wire clk, input wire resetn,
  input wire uart_rx, output wire uart_tx,
  output wire [7:0] leds,
  inout wire [3:0] i2c_scl,
  inout wire [3:0] i2c_sda
);
  wire [7:0] led_raw;
  wire [3:0] irq_unused;
  wire trap_unused,owner_unused,toggle_unused,pulse_unused;
  wire [31:0] dbg_unused,aux_unused;
  // No host traffic in this standalone build.
  pcie_i2c4_top_cpu_fabric #(
    .CLK_HZ(CLK_HZ),.BAUD(BAUD),.CLK_DIV(I2C_CLK_DIV),
    .INITIAL_CPU_OWNER(1),.FIRMWARE_HEX(FIRMWARE_HEX)
  ) u_soc (
    .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(uart_tx),
    .leds(led_raw),.cpu_trap(trap_unused),.cpu_owner(owner_unused),
    .dbg_event(dbg_unused),.dbg_aux(aux_unused),
    .dbg_toggle(toggle_unused),.dbg_pulse(pulse_unused),
    .i2c_scl(i2c_scl),.i2c_sda(i2c_sda),.dev_irq(irq_unused),
    .host_awaddr(16'd0),.host_awvalid(1'b0),.host_awready(),
    .host_wdata(32'd0),.host_wstrb(4'd0),.host_wvalid(1'b0),.host_wready(),
    .host_bresp(),.host_bvalid(),.host_bready(1'b0),
    .host_araddr(16'd0),.host_arvalid(1'b0),.host_arready(),
    .host_rdata(),.host_rresp(),.host_rvalid(),.host_rready(1'b0)
  );
  assign leds = led_raw ^ {8{LED_ACTIVE_LOW}};
endmodule
