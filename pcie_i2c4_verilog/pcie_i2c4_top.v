`timescale 1ns/1ps

module pcie_i2c4_top #(
    parameter CLK_DIV = 625
)(
    input  wire        refclk_p,
    input  wire        refclk_n,
    input  wire        perst_n,
    input  wire [0:0]  pcie_rx_p,
    input  wire [0:0]  pcie_rx_n,
    output wire [0:0]  pcie_tx_p,
    output wire [0:0]  pcie_tx_n,
    inout  wire  [3:0]  i2c_scl,
    inout  wire  [3:0]  i2c_sda,
    input  wire        sys_clk,
    input  wire        aux_clk,
    input  wire        refret,
    input  wire        rext,
    output wire        pl_link_up,
    output wire        dl_link_up,
    output wire        tl_link_up
);

    wire        axil_clk;
    wire        axil_rst_n;
    wire [15:0] m_axi_awaddr;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [15:0] m_axi_araddr;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    wire [2:0] m_axi_awprot;
    wire [2:0] m_axi_arprot;

    wire [3:0] i2c_scl_i;
    wire [3:0] i2c_sda_i;
    wire [3:0] i2c_scl_oen;
    wire [3:0] i2c_sda_oen;

    // Open-drain connections for four separate I2C buses.
    assign i2c_scl[0] = i2c_scl_oen[0] ? 1'bz : 1'b0;
    assign i2c_sda[0] = i2c_sda_oen[0] ? 1'bz : 1'b0;
    assign i2c_scl_i[0] = i2c_scl[0];
    assign i2c_sda_i[0] = i2c_sda[0];
    assign i2c_scl[1] = i2c_scl_oen[1] ? 1'bz : 1'b0;
    assign i2c_sda[1] = i2c_sda_oen[1] ? 1'bz : 1'b0;
    assign i2c_scl_i[1] = i2c_scl[1];
    assign i2c_sda_i[1] = i2c_sda[1];
    assign i2c_scl[2] = i2c_scl_oen[2] ? 1'bz : 1'b0;
    assign i2c_sda[2] = i2c_sda_oen[2] ? 1'bz : 1'b0;
    assign i2c_scl_i[2] = i2c_scl[2];
    assign i2c_sda_i[2] = i2c_sda[2];
    assign i2c_scl[3] = i2c_scl_oen[3] ? 1'bz : 1'b0;
    assign i2c_sda[3] = i2c_sda_oen[3] ? 1'bz : 1'b0;
    assign i2c_scl_i[3] = i2c_scl[3];
    assign i2c_sda_i[3] = i2c_sda[3];

    axil_i2c4_regs #(.CLK_DIV(CLK_DIV)) u_axil_i2c4_regs (
        .ACLK(sys_clk),
        .ARESETn(perst_n),
        .S_AXI_AWADDR(m_axi_awaddr),
        .S_AXI_AWVALID(m_axi_awvalid),
        .S_AXI_AWREADY(m_axi_awready),
        .S_AXI_WDATA(m_axi_wdata),
        .S_AXI_WSTRB(m_axi_wstrb),
        .S_AXI_WVALID(m_axi_wvalid),
        .S_AXI_WREADY(m_axi_wready),
        .S_AXI_BRESP(m_axi_bresp),
        .S_AXI_BVALID(m_axi_bvalid),
        .S_AXI_BREADY(m_axi_bready),
        .S_AXI_ARADDR(m_axi_araddr),
        .S_AXI_ARVALID(m_axi_arvalid),
        .S_AXI_ARREADY(m_axi_arready),
        .S_AXI_RDATA(m_axi_rdata),
        .S_AXI_RRESP(m_axi_rresp),
        .S_AXI_RVALID(m_axi_rvalid),
        .S_AXI_RREADY(m_axi_rready),
        .i2c_scl_in(i2c_scl_i),
        .i2c_sda_in(i2c_sda_i),
        .i2c_scl_oen(i2c_scl_oen),
        .i2c_sda_oen(i2c_sda_oen)
    );

    pcie_ep u_pcie_ep(.link0_rxp_i(pcie_rx_p),
        .link0_rxn_i(pcie_rx_n),
        .refclkp_i(refclk_p),
        .refclkn_i(refclk_n),
        .link0_aux_clk_i(aux_clk),
        .link0_txp_o(pcie_tx_p),
        .link0_txn_o(pcie_tx_n),
        .refret_i(refret),
        .rext_i(rext),
        .link0_perst_n_i(perst_n),
        .link0_rst_usr_n_i(perst_n),
        .sys_clk_i(sys_clk),
        .link0_clk_usr_o(),
        .link0_pl_link_up_o(pl_link_up),
        .link0_dl_link_up_o(dl_link_up),
        .link0_tl_link_up_o(tl_link_up),
        .m0_axil_awaddr_o(m_axi_awaddr),
        .m0_axil_awprot_o(m_axi_awprot),
        .m0_axil_awvalid_o(m_axi_awvalid),
        .m0_axil_wdata_o(m_axi_wdata),
        .m0_axil_wstrb_o(m_axi_wstrb),
        .m0_axil_wvalid_o(m_axi_wvalid),
        .m0_axil_bready_o(m_axi_bready),
        .m0_axil_araddr_o(m_axi_araddr),
        .m0_axil_arvalid_o(m_axi_arvalid),
        .m0_axil_arprot_o(m_axi_arprot),
        .m0_axil_rready_o(m_axi_rready),
        .m0_axil_awready_i(m_axi_awready),
        .m0_axil_wready_i(m_axi_wready),
        .m0_axil_bresp_i(m_axi_bresp),
        .m0_axil_bvalid_i(m_axi_bvalid),
        .m0_axil_arready_i(m_axi_arready),
        .m0_axil_rdata_i(m_axi_rdata),
        .m0_axil_rresp_i(m_axi_rresp),
        .m0_axil_rvalid_i(m_axi_rvalid),
        .usr_int_req_i(1'b0),
        .usr_int_ack_o(),
        .link0_user_aux_power_detected_i(1'b0),
        .link0_user_transactions_pending_i(1'b0),
        .usr_lmmi_clk_i(aux_clk),
        .usr_lmmi_resetn_i(perst_n),
        .usr_lmmi_request_i(1'b0),
        .usr_lmmi_wr_rdn_i(1'b0),
        .usr_lmmi_wdata_i(0),
        .usr_lmmi_offset_i(0),
        .usr_lmmi_rdata_o(),
        .usr_lmmi_rdata_valid_o(),
        .usr_lmmi_ready_o());

endmodule
