`timescale 1ns/1ps
// Board-only bringup top. Uses physical clock, reset, 4x QSFP open drain pins,
// UART TX and LEDs. Pin assignments must be supplied from YOUR board schematic.
module certus_nx_picorv32_qsfp_standalone_top #(
 parameter integer CLK_HZ=50000000,
 parameter integer BAUD=115200,
 parameter integer I2C_CLK_DIV=250,
 parameter FIRMWARE_HEX="firmware.hex"
)(
 input wire clk_in,input wire reset_n,
 input wire [3:0] buttons,input wire [3:0] switches,
 output wire [7:0] led,output wire uart_tx,output wire cpu_trap,
 inout wire [3:0] qsfp_scl,inout wire [3:0] qsfp_sda,
 output wire [3:0] debug_irq
);
 wire unused_req;
 pcie_i2c4_top_cpu_fabric #(
  .CLK_HZ(CLK_HZ),.BAUD(BAUD),.CLK_DIV(I2C_CLK_DIV),
  .FIRMWARE_HEX(FIRMWARE_HEX),.MSI_ACK_LOOPBACK(1)
 ) u_soc (
  .clk(clk_in),.resetn(reset_n),.cpu_mode_select(1'b1),
  .buttons(buttons),.switches(switches),
  .leds(led),.uart_tx(uart_tx),.cpu_trap(cpu_trap),
  .i2c_scl(qsfp_scl),.i2c_sda(qsfp_sda),
  .dev_irq(debug_irq),.usr_int_req(unused_req),.usr_int_ack(1'b0),
  .host_msi_enable(1'b0),
  .host_awaddr(16'd0),.host_awvalid(1'b0),.host_awready(),
  .host_wdata(32'd0),.host_wstrb(4'd0),.host_wvalid(1'b0),.host_wready(),
  .host_bresp(),.host_bvalid(),.host_bready(1'b0),
  .host_araddr(16'd0),.host_arvalid(1'b0),.host_arready(),
  .host_rdata(),.host_rresp(),.host_rvalid(),.host_rready(1'b0)
 );
endmodule
