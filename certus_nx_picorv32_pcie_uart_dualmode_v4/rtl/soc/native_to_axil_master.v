`timescale 1ns/1ps
// Converts PicoRV32 native bus accesses in 0x4000_xxxx to independent AXI4-Lite
// AW/W/B and AR/R transactions. One transaction outstanding at a time.
module native_to_axil_master(
  input wire clk, input wire resetn,
  input wire mem_valid, input wire [31:0] mem_addr,
  input wire [31:0] mem_wdata, input wire [3:0] mem_wstrb,
  output wire mem_ready, output wire [31:0] mem_rdata,
  output wire [15:0] m_awaddr, output wire m_awvalid, input wire m_awready,
  output wire [31:0] m_wdata, output wire [3:0] m_wstrb,
  output wire m_wvalid, input wire m_wready,
  input wire [1:0] m_bresp, input wire m_bvalid, output wire m_bready,
  output wire [15:0] m_araddr, output wire m_arvalid, input wire m_arready,
  input wire [31:0] m_rdata, input wire [1:0] m_rresp,
  input wire m_rvalid, output wire m_rready
);
  localparam ST_IDLE=0,ST_WR=1,ST_B=2,ST_RD=3,ST_R=4,ST_DONE=5;
  reg [2:0] state;
  reg [15:0] addr_q;
  reg [31:0] wdata_q, rdata_q;
  reg [3:0] wstrb_q;
  reg aw_done, w_done;
  assign mem_ready=(state==ST_DONE);
  assign mem_rdata=rdata_q;
  assign m_awaddr=addr_q;
  assign m_awvalid=(state==ST_WR && !aw_done);
  assign m_wdata=wdata_q; assign m_wstrb=wstrb_q;
  assign m_wvalid=(state==ST_WR && !w_done);
  assign m_bready=(state==ST_B);
  assign m_araddr=addr_q; assign m_arvalid=(state==ST_RD);
  assign m_rready=(state==ST_R);
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      state<=ST_IDLE; addr_q<=0; wdata_q<=0;
      wstrb_q<=0; rdata_q<=0; aw_done<=0; w_done<=0;
    end else case(state)
      ST_IDLE: if(mem_valid) begin
        addr_q<=mem_addr[15:0]; wdata_q<=mem_wdata; wstrb_q<=mem_wstrb;
        aw_done<=0;w_done<=0;
        if(mem_wstrb!=0) state<=ST_WR; else state<=ST_RD;
      end
      ST_WR: begin
        if(m_awvalid && m_awready) aw_done<=1;
        if(m_wvalid  && m_wready ) w_done <=1;
        if((aw_done || m_awready) && (w_done || m_wready)) state<=ST_B;
      end
      ST_B: if(m_bvalid) begin
        rdata_q<={30'd0,m_bresp}; state<=ST_DONE;
      end
      ST_RD: if(m_arready) state<=ST_R;
      ST_R: if(m_rvalid) begin
        // Error responses are returned as a sentinel for diagnostics.
        rdata_q<=(m_rresp==2'b00)?m_rdata:32'hBAD0_0000|{30'd0,m_rresp};
        state<=ST_DONE;
      end
      ST_DONE: state<=ST_IDLE;
      default: state<=ST_IDLE;
    endcase
  end
endmodule
