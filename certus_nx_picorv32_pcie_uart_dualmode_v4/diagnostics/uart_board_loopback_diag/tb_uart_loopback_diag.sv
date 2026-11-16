`timescale 1ns/1ps
// Observe the actual UART TX wire; do not infer echo from internal tx_fire.
module tb_uart_loopback_diag;
  localparam integer CLK_HZ=125000000;
  localparam integer BAUD=115200;
  localparam realtime BIT_NS=1000000000.0/BAUD;
  reg clk=0;
  always #4 clk=~clk;
  reg resetn=0;
  reg uart_rx=1;
  wire uart_tx_low,uart_tx_high;
  wire [7:0] leds_low,leds_high;
  tri1 [3:0] scl_low,sda_low,scl_high,sda_high;
  integer received_count=0;
  reg [7:0] received[0:127];
  reg [7:0] decoded;
  integer k;
  integer i;
  integer baseline;
  integer checks=0;
  reg [111:0] banner={"UART RX DIAG",8'h0d,8'h0a};

  certus_nx_uart_loopback_diag_top #(
    .CLK_HZ(CLK_HZ),.BAUD(BAUD),.LED_ACTIVE_LOW(1)
  ) dut_low (
    .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(uart_tx_low),
    .leds(leds_low),.i2c_scl(scl_low),.i2c_sda(sda_low)
  );
  certus_nx_uart_loopback_diag_top #(
    .CLK_HZ(CLK_HZ),.BAUD(BAUD),.LED_ACTIVE_LOW(0)
  ) dut_high (
    .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(uart_tx_high),
    .leds(leds_high),.i2c_scl(scl_high),.i2c_sda(sda_high)
  );

  always @(posedge clk) begin
    #1;
    if(resetn) begin
      if(leds_low !== ~leds_high) $fatal(1,"LED polarity mismatch");
      if(uart_tx_low !== uart_tx_high) $fatal(1,"LED polarity affects UART TX");
      if(leds_low[7] !== 1 || leds_high[7] !== 0)
        $fatal(1,"LED7 must remain logically off in diagnostic top");
    end
  end

  initial forever begin
    @(negedge uart_tx_low);
    if(resetn) begin
      #(BIT_NS/2.0);
      if(uart_tx_low !== 0) $fatal(1,"Invalid UART start bit");
      for(k=0;k<8;k=k+1) begin
        #(BIT_NS);
        decoded[k]=uart_tx_low;
      end
      #(BIT_NS);
      if(uart_tx_low !== 1) $fatal(1,"Invalid UART stop bit");
      if(received_count>=128) $fatal(1,"RX monitor overflow");
      received[received_count]=decoded;
      received_count=received_count+1;
    end
  end

  task automatic wait_count(input integer wanted);
    integer cycles;
    begin
      cycles=0;
      while(received_count<wanted && cycles<300000) begin
        @(negedge clk);
        cycles=cycles+1;
      end
      if(received_count!=wanted)
        $fatal(1,"UART receive count wanted %0d got %0d",wanted,received_count);
    end
  endtask

  task automatic send_and_check(input [7:0] value);
    integer bitnum;
    integer before_count;
    begin
      before_count=received_count;
      @(negedge clk);
      uart_rx=0;
      #(BIT_NS);
      for(bitnum=0;bitnum<8;bitnum=bitnum+1) begin
        uart_rx=value[bitnum];
        #(BIT_NS);
      end
      uart_rx=1;
      #(BIT_NS);
      wait_count(before_count+1);
      if(received[before_count] !== value)
        $fatal(1,"Echo expected %02x got %02x",value,received[before_count]);
      #(BIT_NS*2);
      checks=checks+1;
    end
  endtask

  task automatic check_banner(input integer start_index);
    integer j;
    begin
      wait_count(start_index+14);
      for(j=0;j<14;j=j+1)
        if(received[start_index+j] !== banner[(13-j)*8 +: 8])
          $fatal(1,"Banner byte %0d incorrect: %02x",j,received[start_index+j]);
      #(BIT_NS*2);
      checks=checks+1;
    end
  endtask

  initial begin
    repeat(8) @(negedge clk);
    resetn=1;
    check_banner(0);
    if(leds_high[4:1] !== 4'b0000) $fatal(1,"Banner incorrectly sets RX/echo LEDs");
    send_and_check(8'h41);
    send_and_check(8'h7a);
    send_and_check(8'h0d);
    send_and_check(8'h0a);
    if(leds_high[3:1] !== 3'b111 || leds_high[4] !== 0)
      $fatal(1,"Sticky RX/valid/echo/overrun LEDs incorrect: %b",leds_high);
    checks=checks+1;
    #(BIT_NS*3);
    if(leds_high[3:1] !== 3'b111) $fatal(1,"Activity LEDs are not sticky");
    baseline=received_count;
    @(negedge clk);resetn=0;
    repeat(8) @(negedge clk);
    if(leds_high[4:1] !== 0 || leds_low[4:1] !== 4'hf)
      $fatal(1,"Reset failed to clear sticky LEDs");
    checks=checks+1;
    resetn=1;
    check_banner(baseline);
    if(leds_high[4:1] !== 0) $fatal(1,"Reset banner sets RX LEDs");
    $display("PASS: %0d checks; serial banner twice; A/z/CR/LF echo; sticky/reset LEDs; active-low/high complement; LED7 off",checks);
    $finish;
  end

  initial begin
    #10000000;
    $fatal(1,"Global timeout");
  end
endmodule
