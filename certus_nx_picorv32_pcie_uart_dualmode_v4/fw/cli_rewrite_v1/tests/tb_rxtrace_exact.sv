`timescale 1ns/1ps
// Exact-source integration: selects a repository Top using TEST_CPU_DIAG.
// Production RTL and firmware are never rewritten or driven internally.
// All pass/fail text checks use bytes decoded from the actual UART TX wire.
module tb_rxtrace_exact #(
  parameter integer CLOCK_HZ=125000000,
  parameter integer BAUD=115200,
  parameter FIRMWARE_HEX="firmware/osfp_cli_rewrite_v1_rxtrace.hex"
);
  localparam integer BIT_TICKS=(CLOCK_HZ+BAUD/2)/BAUD;
  localparam realtime BIT_NS=1000000000.0/BAUD;
  reg clk=0;
  always #(500000000.0/CLOCK_HZ) clk=~clk;
`ifdef TEST_USER_POR
  // User-supplied POR, unchanged apart from ASCII punctuation.
  reg [19:0] por_cnt = 20'd0;
  wire resetn_int = &por_cnt;
  always @(posedge clk) begin
    if(!resetn_int)
      por_cnt <= por_cnt + 1'b1;
  end
  wire resetn = resetn_int;
  integer por_clock_edges=0;
  reg por_released=0;
  always @(posedge clk)
    if(!resetn) por_clock_edges=por_clock_edges+1;
  always @(negedge resetn)
    if(por_released) $fatal(1,"POR asserted again after release");
`else
  reg resetn=0;
`endif
  reg uart_rx=1;
  wire uart_tx;
  wire [7:0] leds;
  tri1 [3:0] scl,sda;
  integer fd;
  integer tx_bytes=0;
  integer rx_reads=0;
  integer injected=0;
  integer prompts=0;
  integer before_bytes;
  integer before_prompts;
  integer i;
  reg [7:0] decoded;
  reg [7:0] output_bytes[0:4095];
  reg [47:0] suffix=0;
  string log_path;
`ifdef TEST_CPU_DIAG
  certus_nx_picorv32_uart_cpu_diag_top #(
`else
  certus_nx_picorv32_uart_standalone_top #(
`endif
    .CLK_HZ(CLOCK_HZ),.BAUD(BAUD),.LED_ACTIVE_LOW(1),
    .FIRMWARE_HEX(FIRMWARE_HEX)
  ) dut (
    .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(uart_tx),
    .leds(leds),.i2c_scl(scl),.i2c_sda(sda)
  );

  always @(posedge clk) begin
    if(resetn && dut.trap_unused)
      $fatal(1,"CPU trap PC=%h at %t",
        dut.u_soc.u_cpu_subsystem.u_cpu.reg_pc,$time);
    if(resetn && dut.u_soc.u_cpu_subsystem.rx_overrun)
      $fatal(1,"Hardware RX overrun at %t",$time);
    if(resetn && dut.u_soc.u_cpu_subsystem.local_rd &&
        dut.u_soc.u_cpu_subsystem.mem_addr==32'h10000018)
      rx_reads=rx_reads+1;
  end

  // Sample at the middle of START, eight DATA bits and STOP.
  initial forever begin
    @(negedge uart_tx);
    if(resetn) begin
      #(BIT_NS/2.0);
      if(uart_tx !== 0) $fatal(1,"Invalid UART start bit");
      for(i=0;i<8;i=i+1) begin
        #(BIT_NS);
        decoded[i]=uart_tx;
      end
      #(BIT_NS);
      if(uart_tx !== 1) $fatal(1,"Invalid UART stop bit");
      if(tx_bytes>=4096) $fatal(1,"UART monitor overflow");
      output_bytes[tx_bytes]=decoded;
      tx_bytes=tx_bytes+1;
      $fwrite(fd,"%c",decoded);
      $fflush(fd);
      suffix={suffix[39:0],decoded};
      if(suffix=="osfp> ") begin
        prompts=prompts+1;
        $display("Wire-decoded prompt %0d at %t; TX bytes=%0d",
                 prompts,$time,tx_bytes);
        $fflush();
      end
    end
  end

  task automatic send_byte(input [7:0] value);
    integer bitnum;
    begin
      @(negedge clk);
      uart_rx=0;
      injected=injected+1;
      repeat(BIT_TICKS) @(negedge clk);
      for(bitnum=0;bitnum<8;bitnum=bitnum+1) begin
        uart_rx=value[bitnum];
        repeat(BIT_TICKS) @(negedge clk);
      end
      uart_rx=1;
      repeat(BIT_TICKS*21) @(negedge clk);
    end
  endtask

  task automatic await_prompt(input integer wanted);
    integer cycles;
    begin
      cycles=0;
      while(prompts<wanted && cycles<6000000) begin
        @(negedge clk);
        cycles=cycles+1;
      end
      if(prompts!=wanted)
        $fatal(1,"Expected prompt %0d, got %0d; PC=%h",
                 wanted,prompts,dut.u_soc.u_cpu_subsystem.u_cpu.reg_pc);
      repeat(BIT_TICKS*2) @(negedge clk);
    end
  endtask

  task automatic check_text(input integer start_index, input string expected);
    integer cycles;
    integer index;
    begin
      cycles=0;
      while(tx_bytes < start_index+expected.len() && cycles<4000000) begin
        @(negedge clk); cycles=cycles+1;
      end
      if(tx_bytes != start_index+expected.len())
        $fatal(1,"Wrong trace length: expected %0d got %0d",expected.len(),tx_bytes-start_index);
      for(index=0;index<expected.len();index=index+1)
        if(output_bytes[start_index+index] !== expected[index])
          $fatal(1,"Trace mismatch at %0d: expected %02x got %02x",index,expected[index],output_bytes[start_index+index]);
      repeat(BIT_TICKS*2) @(negedge clk);
    end
  endtask

  initial begin
    if(!$value$plusargs("UART_LOG=%s",log_path)) log_path="rxtrace_uart.log";
    fd=$fopen(log_path,"w");
    if(fd==0) $fatal(1,"Cannot open UART log");
    $display("Config: RXTRACE real CPU CLK=%0d BAUD=%0d TX wire decoding",CLOCK_HZ,BAUD);
`ifdef TEST_USER_POR
    #1;
    if(resetn !== 0 || por_cnt !== 0) $fatal(1,"POR initial state incorrect");
    @(posedge resetn);
    if(por_clock_edges != 1048575 || por_cnt !== 20'hfffff)
      $fatal(1,"POR release count mismatch: edges=%0d counter=%h",por_clock_edges,por_cnt);
    por_released=1;
    $display("PASS: user POR released after %0d clock edges at %t",por_clock_edges,$time);
`else
    repeat(20) @(negedge clk);
    resetn=1;
`endif
    await_prompt(1);
    check_text(0,{8'h0d,8'h0a,"OSFP CLI REWRITE v1 RXTRACE",8'h0d,8'h0a,"One key at a time; RAW is the word read from IO_RX.",8'h0d,8'h0a,"osfp> "});
    before_bytes=tx_bytes;
    send_byte(8'h41);
    check_text(before_bytes,{8'h0d,8'h0a,"RXTRACE RAW=00000041 C=00000041 L=00 BAD=0 HW=00000000 DROP=00000000",8'h0d,8'h0a,"A"});
    $display("PASS: A raw word and character traced, then echoed before Enter");
    before_bytes=tx_bytes;
    send_byte(8'h0d);
    await_prompt(2);
    check_text(before_bytes,{8'h0d,8'h0a,"RXTRACE RAW=0000000D C=0000000D L=01 BAD=0 HW=00000000 DROP=00000000",8'h0d,8'h0a,8'h0d,8'h0a,"ERR unknown command; help",8'h0d,8'h0a,"osfp> "});
    if(rx_reads!=2 || injected!=2) $fatal(1,"RX count mismatch");
`ifdef TEST_USER_POR
    if(resetn !== 1 || por_cnt !== 20'hfffff)
      $fatal(1,"POR counter did not remain saturated");
`endif
    $display("PASS: RXTRACE banner, RAW/C for A and CR, parser state, wire echo; trap=0 overrun=0 RX=2");
    $fflush();$fclose(fd);$finish;
  end

  initial begin
    #150000000;
    $fatal(1,"Global timeout: prompts=%0d TX=%0d RX=%0d PC=%h",
      prompts,tx_bytes,rx_reads,dut.u_soc.u_cpu_subsystem.u_cpu.reg_pc);
  end
  initial forever begin
    #10000000;
    $display("Progress %t: decoded TX=%0d prompts=%0d RX=%0d",
             $time,tx_bytes,prompts,rx_reads);
    $fflush();
  end
endmodule
