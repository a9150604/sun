`timescale 1ns/1ps
// Read-only observation of the real CPU diagnostic SoC and serial TX pin.
// RX stays idle throughout; no CPU, PC, or internal RAM is driven by this TB.
module tb_hw_selftest #(
  parameter integer CLOCK_HZ=125000000,
  parameter integer BAUD=115200,
  parameter FIRMWARE_HEX="firmware/rv32i_hw_selftest.hex"
);
  localparam realtime BIT_NS=1000000000.0/BAUD;
  reg clk=0;
  always #(500000000.0/CLOCK_HZ) clk=~clk;
  // The user's exact power-on reset counter.
  reg [19:0] por_cnt = 20'd0;
  wire resetn_int = &por_cnt;
  always @(posedge clk) begin
    if(!resetn_int)
      por_cnt <= por_cnt + 1'b1;
  end
  integer por_clock_edges=0;
  reg por_released=0;
  always @(posedge clk)
    if(!resetn_int) por_clock_edges=por_clock_edges+1;
  always @(negedge resetn_int)
    if(por_released) $fatal(1,"POR asserted after release");

  wire uart_tx;
  wire [7:0] leds;
  tri1 [3:0] scl,sda;
  certus_nx_picorv32_uart_cpu_diag_top #(
    .CLK_HZ(CLOCK_HZ),.BAUD(BAUD),.LED_ACTIVE_LOW(1),
    .FIRMWARE_HEX(FIRMWARE_HEX)
  ) dut (
    .clk(clk),.resetn(resetn_int),.uart_rx(1'b1),.uart_tx(uart_tx),
    .leds(leds),.i2c_scl(scl),.i2c_sda(sda)
  );

  integer fd;
  integer tx_bytes=0;
  integer rx_reads=0;
  integer end_bytes=0;
  integer i;
  reg [7:0] decoded;
  reg [39:0] suffix=0;
  reg end_seen=0;
  string log_path;

  always @(posedge clk) begin
    if(resetn_int && dut.trap_unused)
      $fatal(1,"CPU trap PC=%h at %t",
        dut.u_soc.u_cpu_subsystem.u_cpu.reg_pc,$time);
    if(resetn_int && dut.u_soc.u_cpu_subsystem.rx_overrun)
      $fatal(1,"UART RX overrun with RX held idle");
    if(resetn_int && dut.u_soc.u_cpu_subsystem.local_rd &&
        dut.u_soc.u_cpu_subsystem.mem_addr==32'h10000018) begin
      rx_reads=rx_reads+1;
      $fatal(1,"Unexpected RX data read with RX held idle");
    end
  end

  initial forever begin
    @(negedge uart_tx);
    if(resetn_int) begin
      if(end_seen) $fatal(1,"Extra UART output began after END");
      #(BIT_NS/2.0);
      if(uart_tx !== 0) $fatal(1,"Invalid UART start bit");
      for(i=0;i<8;i=i+1) begin
        #(BIT_NS);decoded[i]=uart_tx;
      end
      #(BIT_NS);
      if(uart_tx !== 1) $fatal(1,"Invalid UART stop bit");
      tx_bytes=tx_bytes+1;
      if(tx_bytes>4096) $fatal(1,"UART output exceeded monitor bound");
      $fwrite(fd,"%c",decoded);$fflush(fd);
      suffix={suffix[31:0],decoded};
      if(suffix==40'h454e440d0a) begin
        end_seen=1;end_bytes=tx_bytes;
        $display("Wire-decoded END at %t; TX bytes=%0d",$time,tx_bytes);
      end
    end
  end

  initial begin
    if(!$value$plusargs("UART_LOG=%s",log_path)) log_path="hw_selftest_uart.log";
    fd=$fopen(log_path,"w");
    if(fd==0) $fatal(1,"Cannot open UART log");
    $display("Config: real CPU selftest CLK=%0d BAUD=%0d RX=idle TX wire decoding",CLOCK_HZ,BAUD);
    #1;
    if(resetn_int !== 0 || por_cnt !== 0) $fatal(1,"POR initial state incorrect");
    @(posedge resetn_int);
    if(por_clock_edges!=1048575 || por_cnt!==20'hfffff)
      $fatal(1,"POR release state/count incorrect");
    por_released=1;
    $display("PASS: user POR released after %0d clock edges at %t",por_clock_edges,$time);
    wait(end_seen);
    // Monitor another 2 ms: any new UART start bit is also an immediate failure.
    repeat(CLOCK_HZ/500) @(negedge clk);
    if(tx_bytes!=end_bytes || rx_reads!=0)
      $fatal(1,"Extra output or unexpected RX read after END");
    if(resetn_int!==1 || por_cnt!==20'hfffff) $fatal(1,"POR did not remain saturated");
    $display("PASS: selftest END, no extra output for 2 ms, trap=0 overrun=0 RX=0 TX=%0d",tx_bytes);
    $fflush();$fclose(fd);$finish;
  end

  initial begin
    #500000000;
    $fatal(1,"Global timeout: END=%0d TX=%0d RX=%0d PC=%h",end_seen,tx_bytes,
           rx_reads,dut.u_soc.u_cpu_subsystem.u_cpu.reg_pc);
  end
  initial forever begin
    #10000000;
    $display("Progress %t: decoded TX=%0d END=%0d RX=%0d",$time,tx_bytes,end_seen,rx_reads);
    $fflush();
  end
endmodule
