`timescale 1ns/1ps
// Isolated AXI-Lite peripheral test: no PicoRV32 official source required.
module tb_native_axil_bridge;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg mem_valid=0;
  reg [31:0] mem_addr=0,mem_wdata=0;
  reg [3:0] mem_wstrb=0;
  wire mem_ready;
  wire [31:0] mem_rdata;
  wire [15:0] awaddr,araddr;
  wire awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;
  wire [31:0] wdata,rdata;
  wire [3:0] wstrb;
  wire [1:0] bresp,rresp;
  wire [3:0] scl_oen,sda_oen,dev_irq;
  reg [31:0] result;
  native_to_axil_master u_bridge (
   .clk(clk),.resetn(rst_n),
   .mem_valid(mem_valid),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
   .mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),
   .m_awaddr(awaddr),.m_awvalid(awvalid),.m_awready(awready),
   .m_wdata(wdata),.m_wstrb(wstrb),.m_wvalid(wvalid),.m_wready(wready),
   .m_bresp(bresp),.m_bvalid(bvalid),.m_bready(bready),
   .m_araddr(araddr),.m_arvalid(arvalid),.m_arready(arready),
   .m_rdata(rdata),.m_rresp(rresp),.m_rvalid(rvalid),.m_rready(rready)
  );
  axil_i2c4_regs #(.CLK_DIV(8)) u_regs (
   .ACLK(clk),.ARESETn(rst_n),
   .S_AXI_AWADDR(awaddr),.S_AXI_AWVALID(awvalid),.S_AXI_AWREADY(awready),
   .S_AXI_WDATA(wdata),.S_AXI_WSTRB(wstrb),.S_AXI_WVALID(wvalid),.S_AXI_WREADY(wready),
   .S_AXI_BRESP(bresp),.S_AXI_BVALID(bvalid),.S_AXI_BREADY(bready),
   .S_AXI_ARADDR(araddr),.S_AXI_ARVALID(arvalid),.S_AXI_ARREADY(arready),
   .S_AXI_RDATA(rdata),.S_AXI_RRESP(rresp),.S_AXI_RVALID(rvalid),.S_AXI_RREADY(rready),
   .i2c_scl_in(4'hf),.i2c_sda_in(4'hf),
   .i2c_scl_oen(scl_oen),.i2c_sda_oen(sda_oen),.dev_irq(dev_irq)
  );
  task automatic cpu_write(input [31:0] a,input [31:0] d,input [3:0] strobe);
    begin
      @(negedge clk);
      mem_addr=a;mem_wdata=d;mem_wstrb=strobe;mem_valid=1;
      @(posedge mem_ready);
      @(negedge clk);mem_valid=0;mem_wstrb=0;
      repeat(3)@(posedge clk);
    end
  endtask
  task automatic cpu_read(input [31:0] a,output [31:0] d);
    begin
      @(negedge clk);
      mem_addr=a;mem_wstrb=0;mem_valid=1;
      @(posedge mem_ready);
      @(negedge clk);d=mem_rdata;mem_valid=0;
      repeat(3)@(posedge clk);
    end
  endtask
  initial begin
    #100;rst_n=1;
    cpu_read(32'h40000000,result);
    if(result!==32'h49324334)$fatal(1,"BAD ID %08x",result);
    cpu_write(32'h40000100,32'h00000450,4'hf);
    cpu_read(32'h40000100,result);
    if(result!==32'h00000450)$fatal(1,"BAD CFG %08x",result);
    cpu_write(32'h40000100,32'h00000051,4'h1);
    cpu_read(32'h40000100,result);
    if(result!==32'h00000451)$fatal(1,"BAD STROBE %08x",result);
    $display("AXI_LITE_BRIDGE PASS - basic R/W + WSTRB");
    $finish;
  end
  initial begin #100000; $fatal(1,"AXI BRIDGE TIMEOUT");end
endmodule
