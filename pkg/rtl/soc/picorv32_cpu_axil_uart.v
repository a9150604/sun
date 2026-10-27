`timescale 1ns/1ps
// PicoRV32 native memory system + AXI-Lite peripheral master + UART TX.
// Download unmodified upstream picorv32.v to third_party/ before compilation.
module picorv32_cpu_axil_uart #(
 parameter integer CLK_HZ=50000000,
 parameter integer BAUD=115200,
 parameter integer RAM_WORDS=16384,
 parameter FIRMWARE_HEX="firmware.hex"
)(
 input wire clk,input wire resetn,
 input wire [3:0] buttons,input wire [3:0] switches,
 input wire [3:0] dev_irq,
 input wire msi_req,input wire msi_ack,
 input wire [15:0] msi_ack_count,
 output reg msi_enable,
 output reg [7:0] leds,output wire uart_tx,output wire cpu_trap,
 output wire [15:0] m_awaddr,output wire m_awvalid,input wire m_awready,
 output wire [31:0] m_wdata,output wire [3:0] m_wstrb,
 output wire m_wvalid,input wire m_wready,
 input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
 output wire [15:0] m_araddr,output wire m_arvalid,input wire m_arready,
 input wire [31:0] m_rdata,input wire [1:0] m_rresp,
 input wire m_rvalid,output wire m_rready
);
 wire mem_valid,mem_instr;reg mem_ready;
 wire [31:0] mem_addr,mem_wdata;
 wire [3:0] mem_wstrb;
 reg [31:0] mem_rdata;
 wire ram_sel=(mem_addr[31:16]==16'h0000);
 wire axil_sel=(mem_addr[31:16]==16'h4000);
 wire uart_sel=(mem_addr[31:4]==28'h1000000);
 wire gpio_sel=(mem_addr[31:4]==28'h1000001);
 wire msi_sel=(mem_addr[31:4]==28'h1000002 || mem_addr[31:4]==28'h1000003);
 wire [31:0] axil_rdata;
 wire axil_ready;
 reg ram_ready;
 reg [31:0] ram_rdata;
 reg [31:0] ram [0:RAM_WORDS-1];
 reg [31:0] uptime_cycles;
 always @(posedge clk or negedge resetn)
   if(!resetn) uptime_cycles<=0;
   else uptime_cycles<=uptime_cycles+1;
 initial $readmemh(FIRMWARE_HEX,ram);
 picorv32 #(
   .ENABLE_IRQ(0),.ENABLE_MUL(1),.ENABLE_DIV(1),
   .COMPRESSED_ISA(0),.PROGADDR_RESET(32'h00000000),
   .STACKADDR(RAM_WORDS*4)
 ) u_cpu (
   .clk(clk),.resetn(resetn),.trap(cpu_trap),
   .mem_valid(mem_valid),.mem_instr(mem_instr),
   .mem_ready(mem_ready),.mem_addr(mem_addr),
   .mem_wdata(mem_wdata),.mem_wstrb(mem_wstrb),.mem_rdata(mem_rdata),
   .irq(32'd0),.eoi(),.pcpi_wr(1'b0),.pcpi_rd(32'd0),
   .pcpi_wait(1'b0),.pcpi_ready(1'b0)
 );
 // Synchronous BRAM. ram_ready & rdata are registered; each CPU request
 // is serviced once. 16K words = 64 KiB RAM.
 always @(posedge clk or negedge resetn) begin
   if(!resetn) begin ram_ready<=0;ram_rdata<=0;end
   else begin
     ram_ready<=0;
     if(mem_valid && ram_sel && !ram_ready) begin
       ram_rdata<=ram[mem_addr[15:2]];
       if(mem_wstrb[0]) ram[mem_addr[15:2]][ 7: 0]<=mem_wdata[ 7: 0];
       if(mem_wstrb[1]) ram[mem_addr[15:2]][15: 8]<=mem_wdata[15: 8];
       if(mem_wstrb[2]) ram[mem_addr[15:2]][23:16]<=mem_wdata[23:16];
       if(mem_wstrb[3]) ram[mem_addr[15:2]][31:24]<=mem_wdata[31:24];
       ram_ready<=1;
     end
   end
 end
 native_to_axil_master u_bridge (
   .clk(clk),.resetn(resetn),
   .mem_valid(mem_valid && axil_sel),.mem_addr(mem_addr),
   .mem_wdata(mem_wdata),.mem_wstrb(mem_wstrb),
   .mem_ready(axil_ready),.mem_rdata(axil_rdata),
   .m_awaddr(m_awaddr),.m_awvalid(m_awvalid),.m_awready(m_awready),
   .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wvalid(m_wvalid),.m_wready(m_wready),
   .m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready),
   .m_araddr(m_araddr),.m_arvalid(m_arvalid),.m_arready(m_arready),
   .m_rdata(m_rdata),.m_rresp(m_rresp),.m_rvalid(m_rvalid),.m_rready(m_rready)
 );
 wire tx_ready;
 wire uart_write=(uart_sel && mem_valid && (mem_addr[3:0]==4'h4) && (|mem_wstrb));
 wire uart_fire=uart_write && tx_ready;
 uart_tx_mmio #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart (
   .clk(clk),.resetn(resetn),.tx_fire(uart_fire),
   .tx_data(mem_wdata[7:0]),.tx_ready(tx_ready),.uart_tx(uart_tx)
 );
 // TX register stalls writes until previous byte is finished.
 wire periph_ready=(uart_write ? tx_ready : 1'b1);
 always @(*) begin
   mem_ready=0;mem_rdata=32'hBAD0_ADD0;
   if(ram_sel) begin mem_ready=ram_ready;mem_rdata=ram_rdata;end
   else if(axil_sel) begin mem_ready=axil_ready;mem_rdata=axil_rdata;end
   else if(uart_sel || gpio_sel || msi_sel) begin
     mem_ready=mem_valid && periph_ready;
     case(mem_addr)
       32'h10000000: mem_rdata=CLK_HZ;
       32'h10000004: mem_rdata=32'h0000_0000;
       32'h10000008: mem_rdata={31'd0,tx_ready};
       32'h1000000C: mem_rdata=uptime_cycles;
       32'h10000010: mem_rdata={24'd0,leds};
       32'h10000014: mem_rdata={24'd0,switches,buttons};
       32'h10000020: mem_rdata={31'd0,msi_enable};
       32'h10000024: mem_rdata={28'd0,dev_irq};
       32'h10000028: mem_rdata={14'd0,msi_ack_count,msi_ack,msi_req};
       default: mem_rdata=32'hBAD0_ADD0;
     endcase
   end else if(mem_valid) mem_ready=1;
 end
 always @(posedge clk or negedge resetn) begin
   if(!resetn) begin leds<=0;msi_enable<=0;end
   else if(mem_valid && mem_ready && (|mem_wstrb)) begin
     if(mem_addr==32'h10000010) leds<=mem_wdata[7:0];
     if(mem_addr==32'h10000020) msi_enable<=mem_wdata[0];
   end
 end
endmodule
