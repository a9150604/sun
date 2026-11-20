`timescale 1ns/1ps
// Ideal open-drain register/page fixture. No clock stretching or analog delays.
module tb_page_write #(
 parameter FIRMWARE_HEX="firmware/osfp_cli_rewrite_v1_page.hex"
);
 localparam integer CLOCK_HZ=125000000, BAUD=115200, BIT_TICKS=1085;
 localparam realtime BIT_NS=1000000000.0/BAUD;
 reg clk=0; always #4 clk=~clk;
 reg [19:0] por_cnt=0;
 wire resetn=&por_cnt;
 always @(posedge clk) if(!resetn) por_cnt<=por_cnt+1'b1;
 reg uart_rx=1; wire uart_tx; wire [7:0] leds;
 tri1 [3:0] scl,sda;
 reg slave_low=0;
 assign sda[0]=slave_low ? 1'b0 : 1'bz;
 certus_nx_picorv32_uart_standalone_top #(
  .CLK_HZ(CLOCK_HZ),.BAUD(BAUD),.LED_ACTIVE_LOW(1),
  .FIRMWARE_HEX(FIRMWARE_HEX)
 ) dut(.clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(uart_tx),
 .leds(leds),.i2c_scl(scl),.i2c_sda(sda));
 integer fd, tx_bytes=0,prompts=0,injected=0,rx_reads=0,i;
 integer transactions=0,reads=0,writes=0,stops=0;
 reg [7:0] page=0,decoded,addrw,regaddr,addrr,data;
 reg [47:0] suffix=0;
 string log_path;
 always @(posedge clk) begin
  if(resetn && dut.trap_unused) $fatal(1,"CPU trap");
  if(resetn && dut.u_soc.u_cpu_subsystem.rx_overrun) $fatal(1,"RX overrun");
  if(resetn && dut.u_soc.u_cpu_subsystem.local_rd &&
      dut.u_soc.u_cpu_subsystem.mem_addr==32'h10000018) rx_reads++;
 end
 initial forever begin
  @(negedge uart_tx);
  if(resetn) begin
   #(BIT_NS/2.0); if(uart_tx!==0) $fatal(1,"UART start");
   for(i=0;i<8;i++) begin #(BIT_NS);decoded[i]=uart_tx;end
   #(BIT_NS); if(uart_tx!==1) $fatal(1,"UART stop");
   tx_bytes++;$fwrite(fd,"%c",decoded);$fflush(fd);
   suffix={suffix[39:0],decoded};
   if(suffix=="osfp> ") begin prompts++; $display("Prompt %0d TX=%0d",prompts,tx_bytes);end
  end
 end
 task automatic send_byte(input [7:0] b);
  integer n;
  begin
   @(negedge clk);uart_rx=0;injected++;
   repeat(BIT_TICKS) @(negedge clk);
   for(n=0;n<8;n++) begin uart_rx=b[n];repeat(BIT_TICKS) @(negedge clk);end
   uart_rx=1;repeat(BIT_TICKS*21) @(negedge clk);
  end
 endtask
 task automatic await_prompt(input integer wanted);
  integer cycles;
  begin
   cycles=0;
   while(prompts<wanted && cycles<15000000) begin @(negedge clk);cycles++;end
   if(prompts!=wanted) $fatal(1,"wanted=%0d prompts=%0d",wanted,prompts);
   repeat(BIT_TICKS*2) @(negedge clk);
  end
 endtask
 task automatic command(input string cmd,input integer wanted,input integer expected_transactions);
  integer n;
  begin
   for(n=0;n<cmd.len();n++) send_byte(cmd[n]);
   send_byte(13);
   await_prompt(wanted);
   if(transactions!=expected_transactions || stops!=expected_transactions)
    $fatal(1,"After %s: transactions=%0d stops=%0d expected=%0d",cmd,transactions,stops,expected_transactions);
  end
 endtask
 task automatic receive_byte(output reg [7:0] b);
  integer n;
  begin for(n=7;n>=0;n--) begin @(posedge scl[0]);b[n]=sda[0];end end
 endtask
 task automatic ack_byte;
  begin
   @(negedge scl[0]);slave_low=1;
   @(posedge scl[0]);
   @(negedge scl[0]);slave_low=0;
  end
 endtask
 task automatic wait_start;
  begin
   @(negedge sda[0]);
   while(scl[0]!==1) @(negedge sda[0]);
  end
 endtask
 task automatic wait_stop;
  begin
   @(posedge sda[0]);
   while(scl[0]!==1) @(posedge sda[0]);
   stops++;
  end
 endtask
 task automatic send_data(input [7:0] b);
  integer n;
  begin
   for(n=7;n>=0;n--) begin
    slave_low=~b[n];
    @(posedge scl[0]);
    @(negedge scl[0]);
   end
   slave_low=0;
   @(posedge scl[0]);
   if(sda[0]!==1) $fatal(1,"Master should NACK final byte");
  end
 endtask
 function automatic bit expected_write(input integer n);
  return n==1 || n==6;
 endfunction
 function automatic [7:0] expected_reg(input integer n);
  case(n)
   0,3,7: return 8'h80;
   1,2,6,8: return 8'h7f;
   4: return 8'h81;
   5: return 8'h00;
   default: return 8'hff;
  endcase
 endfunction
 function automatic [7:0] read_value(input [7:0] reg_number);
  case(reg_number)
   8'h00: return 8'h19;
   8'h7f: return page;
   8'h80: return page==0 ? 8'h11 : 8'ha5;
   8'h81: return page==0 ? 8'h22 : 8'h5a;
   default: return 8'h66;
  endcase
 endfunction
 initial forever begin : slave
  integer n;
  reg [7:0] wanted_data;
  wait_start();
  n=transactions;
  if(n>=9) $fatal(1,"Unexpected extra I2C transaction");
  transactions++;
  receive_byte(addrw);
  if(addrw!==8'ha0) $fatal(1,"Wrong addressW %h",addrw);
  ack_byte();receive_byte(regaddr);
  if(regaddr!==expected_reg(n)) $fatal(1,"Transaction %0d reg=%h expected=%h",n,regaddr,expected_reg(n));
  ack_byte();
  if(expected_write(n)) begin
   receive_byte(data);
   wanted_data=n==1 ? 8'h01 : 8'h00;
   if(data!==wanted_data) $fatal(1,"Transaction %0d write=%h expected=%h",n,data,wanted_data);
   if(regaddr==8'h7f) page=data;
   else $fatal(1,"Unexpected write register %h",regaddr);
   ack_byte();writes++;
   $display("I2C WRITE reg=%h data=%h page=%h",regaddr,data,page);
  end else begin
   wait_start();receive_byte(addrr);
   if(addrr!==8'ha1) $fatal(1,"Wrong addressR %h",addrr);
   ack_byte();data=read_value(regaddr);
   send_data(data);reads++;
   $display("I2C READ reg=%h data=%h page=%h",regaddr,data,page);
  end
  wait_stop();
 end
 initial begin
  if(!$value$plusargs("UART_LOG=%s",log_path))log_path="uart.log";
  fd=$fopen(log_path,"w");if(!fd)$fatal(1,"log open");
  @(posedge resetn);await_prompt(1);
  command("write 7F 01",2,0);
  command("unlock",3,0);
  command("read 80",4,1);
  command("write 7F 01",5,2);
  command("read 7F",6,3);
  command("read 80",7,4);
  command("read 81",8,5);
  command("read 00",9,6);
  command("writeverify 7F 00",10,6);
  command("writeverify 7E 00",11,6);
  command("write 7F 00",12,7);
  command("read 80",13,8);
  command("lock",14,8);
  command("write 7F 01",15,8);
  command("read 7F",16,9);
  if(rx_reads!=injected)$fatal(1,"RX count mismatch");
  if(reads!=7 || writes!=2 || stops!=9 || page!=0)
   $fatal(1,"Bad final state reads=%0d writes=%0d stops=%0d page=%h",reads,writes,stops,page);
  $display("PASS RX=%0d prompts=%0d transactions=%0d reads=%0d writes=%0d stops=%0d",rx_reads,prompts,transactions,reads,writes,stops);
  $fclose(fd);$finish;
 end
 initial begin #800000000;$fatal(1,"global timeout");end
endmodule
