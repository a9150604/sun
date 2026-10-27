`timescale 1ns/1ps
module tb_soc;
 reg clk=0;always #10 clk=~clk; // 50MHz
 reg resetn=0;
 reg [3:0] buttons=0,switches=0;
 wire [7:0] leds;
 wire uart_tx,cpu_trap;
 tri [3:0] scl,sda;
 wire [3:0] dev_irq;
 // Faster UART and I2C are used in simulation only.
 certus_nx_picorv32_qsfp_standalone_top #(
   .CLK_HZ(50000000),.BAUD(1000000),.I2C_CLK_DIV(16),
   .FIRMWARE_HEX("firmware.hex")
 ) dut (
   .clk_in(clk),.reset_n(resetn),.buttons(buttons),.switches(switches),
   .led(leds),.uart_tx(uart_tx),.cpu_trap(cpu_trap),
   .qsfp_scl(scl),.qsfp_sda(sda),.debug_irq(dev_irq)
 );
 genvar i;
 generate for(i=0;i<4;i=i+1) begin: g_slave
   pullup (scl[i]); pullup(sda[i]);
   i2c_slave_model #(.DEV_ADDR(7'h50)) u_slave (.scl(scl[i]),.sda(sda[i]));
 end endgenerate
 // UART monitor: 1Mbaud 8N1, printed to simulator transcript.
 reg [7:0] uart_byte;
 integer bitnum;
 initial begin
   forever begin
     @(negedge uart_tx);
     #1500; // 1.5 bit times -> sample data[0] center
     for(bitnum=0;bitnum<8;bitnum=bitnum+1) begin
       uart_byte[bitnum]=uart_tx;
       #1000;
     end
     $write("%c",uart_byte);
   end
 end
 initial begin
   #200; resetn=1;
   #200000000;
   $display("\nSIM TIMEOUT/END, LEDs=%02h, CPU trap=%b",leds,cpu_trap);
   $finish;
 end
 always @(posedge clk) if(cpu_trap) begin
   $display("CPU TRAP at t=%0t",$time);
   $finish;
 end
endmodule
