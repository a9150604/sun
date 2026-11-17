`timescale 1ns/1ps
// Integration check: original standalone SoC + a separately supplied PicoRV32.
// All pass/fail text checks use bytes decoded from the actual UART TX wire.
module tb_cli_rewrite #(
  parameter integer BAUD=115200,
  parameter integer SMOKE=0,
  parameter FIRMWARE_HEX="firmware/osfp_cli_rewrite_v1.hex"
);
  localparam integer CLOCK_HZ=125000000;
  localparam integer BIT_TICKS=(CLOCK_HZ+BAUD/2)/BAUD;
  localparam realtime BIT_NS=1000000000.0/BAUD;
  reg clk=0;
  always #4 clk=~clk;
  reg resetn=0;
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
  certus_nx_picorv32_uart_standalone_top #(
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

  initial begin
    if(!$value$plusargs("UART_LOG=%s",log_path)) log_path="cli_rewrite_uart.log";
    fd=$fopen(log_path,"w");
    if(fd==0) $fatal(1,"Cannot open UART log");
    $display("Config: real CPU, CLK=%0d BAUD=%0d, UART TX wire decoding",
             CLOCK_HZ,BAUD);
    repeat(20) @(negedge clk);
    resetn=1;
    await_prompt(1);

    before_bytes=tx_bytes;
    send_byte("A");
    repeat(BIT_TICKS*20) @(negedge clk);
    if(tx_bytes!=before_bytes+1 || output_bytes[before_bytes]!==8'h41)
      $fatal(1,"A was not echoed exactly once before Enter");
    $display("PASS: single A echoes on UART wire before Enter");
    send_byte(8'h0d);
    await_prompt(2);
    if(SMOKE) begin
      if(rx_reads!=injected || rx_reads!=2)
        $fatal(1,"Smoke RX count mismatch: injected=%0d reads=%0d",injected,rx_reads);
      $display("PASS: rewritten CLI smoke: wire banner, A-before-Enter echo, Enter reply and second prompt; RX=2 trap=0 overrun=0");
      $fflush();
      $fclose(fd);
      $finish;
    end

    send_byte("s");send_byte("t");send_byte("a");send_byte("t");
    send_byte("u");send_byte("s");send_byte(8'h0d);
    await_prompt(3);

    // Empty Enter produces newline and another prompt.
    before_bytes=tx_bytes;
    send_byte(8'h0d);
    await_prompt(4);
    if(tx_bytes!=before_bytes+8)
      $fatal(1,"Empty Enter should emit CRLF and a six-byte prompt");

    // A terminal configured to send CRLF must execute only one empty line.
    send_byte(8'h0d);
    send_byte(8'h0a);
    await_prompt(5);
    before_prompts=prompts;
    repeat(BIT_TICKS*100) @(negedge clk);
    if(prompts!=before_prompts) $fatal(1,"CRLF generated a duplicate prompt");

    // stax<BS>tus is visibly edited to status.
    send_byte("s");send_byte("t");send_byte("a");send_byte("x");
    send_byte(8'h08);send_byte("t");send_byte("u");send_byte("s");
    send_byte(8'h0a);
    await_prompt(6);

    // locx<DEL>k edits to lock and proves that DEL follows the same path.
    send_byte("l");send_byte("o");send_byte("c");send_byte("x");
    send_byte(8'h7f);send_byte("k");send_byte(8'h0d);
    await_prompt(7);
    if(rx_reads!=injected)
      $fatal(1,"Injected=%0d but RX-data reads=%0d",injected,rx_reads);
    $display("PASS: rewritten CLI wire echo, A+Enter, status, empty Enter, CRLF, BS/DEL; RX=%0d trap=0 overrun=0",rx_reads);
    $fflush();
    $fclose(fd);
    $finish;
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
