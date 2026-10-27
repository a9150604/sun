`timescale 1ns/1ps

module axil_i2c4_regs #(
    parameter CLK_DIV = 625
)(
    input  wire         ACLK,
    input  wire         ARESETn,

    input  wire [15:0]  S_AXI_AWADDR,
    input  wire         S_AXI_AWVALID,
    output wire         S_AXI_AWREADY,
    input  wire [31:0]  S_AXI_WDATA,
    input  wire [3:0]   S_AXI_WSTRB,
    input  wire         S_AXI_WVALID,
    output wire         S_AXI_WREADY,
    output reg [1:0]   S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire         S_AXI_BREADY,

    input  wire [15:0]  S_AXI_ARADDR,
    input  wire         S_AXI_ARVALID,
    output wire         S_AXI_ARREADY,
    output reg [31:0]  S_AXI_RDATA,
    output reg [1:0]   S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire         S_AXI_RREADY,

    input  wire [3:0]   i2c_scl_in,
    input  wire [3:0]   i2c_sda_in,
    output wire [3:0]   i2c_scl_oen,
    output wire [3:0]   i2c_sda_oen
);

    // Four independent control/register banks (Verilog-2001).
    localparam [31:0] ID_VALUE = 32'h4932_4334;
    localparam [31:0] VERSION_VALUE = 32'h0002_0000;

    // Device 0: base address 0x0100
    reg [6:0] dev_addr_0;
    reg [15:0] poll_gap_0;
    reg auto_enable_0;
    reg direct_rw_0;
    reg direct_burst_en_0;
    reg [7:0] direct_reg_addr_0;
    reg [7:0] direct_wr_data_0;
    reg direct_start_pulse_0;
    reg irq_clear_pulse_0;
    reg [7:0] poll_reg_addr_0_0;
    reg [7:0] poll_reg_addr_0_1;
    reg [7:0] poll_reg_addr_0_2;
    reg [7:0] poll_reg_addr_0_3;
    reg [7:0] poll_reg_addr_0_4;
    reg [7:0] poll_reg_addr_0_5;
    reg [7:0] poll_reg_addr_0_6;
    reg [7:0] poll_reg_addr_0_7;
    wire [7:0] direct_rd_data_0;
    wire direct_done_0;
    wire direct_ack_error_0;
    wire ctrl_busy_0;
    wire auto_valid_0;
    wire [2:0] auto_poll_idx_0;
    wire dev_irq_0;
    wire [7:0] shadow_0_0;
    wire [7:0] shadow_0_1;
    wire [7:0] shadow_0_2;
    wire [7:0] shadow_0_3;
    wire [7:0] shadow_0_4;
    wire [7:0] shadow_0_5;
    wire [7:0] shadow_0_6;
    wire [7:0] shadow_0_7;

    // Device 1: base address 0x0200
    reg [6:0] dev_addr_1;
    reg [15:0] poll_gap_1;
    reg auto_enable_1;
    reg direct_rw_1;
    reg direct_burst_en_1;
    reg [7:0] direct_reg_addr_1;
    reg [7:0] direct_wr_data_1;
    reg direct_start_pulse_1;
    reg irq_clear_pulse_1;
    reg [7:0] poll_reg_addr_1_0;
    reg [7:0] poll_reg_addr_1_1;
    reg [7:0] poll_reg_addr_1_2;
    reg [7:0] poll_reg_addr_1_3;
    reg [7:0] poll_reg_addr_1_4;
    reg [7:0] poll_reg_addr_1_5;
    reg [7:0] poll_reg_addr_1_6;
    reg [7:0] poll_reg_addr_1_7;
    wire [7:0] direct_rd_data_1;
    wire direct_done_1;
    wire direct_ack_error_1;
    wire ctrl_busy_1;
    wire auto_valid_1;
    wire [2:0] auto_poll_idx_1;
    wire dev_irq_1;
    wire [7:0] shadow_1_0;
    wire [7:0] shadow_1_1;
    wire [7:0] shadow_1_2;
    wire [7:0] shadow_1_3;
    wire [7:0] shadow_1_4;
    wire [7:0] shadow_1_5;
    wire [7:0] shadow_1_6;
    wire [7:0] shadow_1_7;

    // Device 2: base address 0x0300
    reg [6:0] dev_addr_2;
    reg [15:0] poll_gap_2;
    reg auto_enable_2;
    reg direct_rw_2;
    reg direct_burst_en_2;
    reg [7:0] direct_reg_addr_2;
    reg [7:0] direct_wr_data_2;
    reg direct_start_pulse_2;
    reg irq_clear_pulse_2;
    reg [7:0] poll_reg_addr_2_0;
    reg [7:0] poll_reg_addr_2_1;
    reg [7:0] poll_reg_addr_2_2;
    reg [7:0] poll_reg_addr_2_3;
    reg [7:0] poll_reg_addr_2_4;
    reg [7:0] poll_reg_addr_2_5;
    reg [7:0] poll_reg_addr_2_6;
    reg [7:0] poll_reg_addr_2_7;
    wire [7:0] direct_rd_data_2;
    wire direct_done_2;
    wire direct_ack_error_2;
    wire ctrl_busy_2;
    wire auto_valid_2;
    wire [2:0] auto_poll_idx_2;
    wire dev_irq_2;
    wire [7:0] shadow_2_0;
    wire [7:0] shadow_2_1;
    wire [7:0] shadow_2_2;
    wire [7:0] shadow_2_3;
    wire [7:0] shadow_2_4;
    wire [7:0] shadow_2_5;
    wire [7:0] shadow_2_6;
    wire [7:0] shadow_2_7;

    // Device 3: base address 0x0400
    reg [6:0] dev_addr_3;
    reg [15:0] poll_gap_3;
    reg auto_enable_3;
    reg direct_rw_3;
    reg direct_burst_en_3;
    reg [7:0] direct_reg_addr_3;
    reg [7:0] direct_wr_data_3;
    reg direct_start_pulse_3;
    reg irq_clear_pulse_3;
    reg [7:0] poll_reg_addr_3_0;
    reg [7:0] poll_reg_addr_3_1;
    reg [7:0] poll_reg_addr_3_2;
    reg [7:0] poll_reg_addr_3_3;
    reg [7:0] poll_reg_addr_3_4;
    reg [7:0] poll_reg_addr_3_5;
    reg [7:0] poll_reg_addr_3_6;
    reg [7:0] poll_reg_addr_3_7;
    wire [7:0] direct_rd_data_3;
    wire direct_done_3;
    wire direct_ack_error_3;
    wire ctrl_busy_3;
    wire auto_valid_3;
    wire [2:0] auto_poll_idx_3;
    wire dev_irq_3;
    wire [7:0] shadow_3_0;
    wire [7:0] shadow_3_1;
    wire [7:0] shadow_3_2;
    wire [7:0] shadow_3_3;
    wire [7:0] shadow_3_4;
    wire [7:0] shadow_3_5;
    wire [7:0] shadow_3_6;
    wire [7:0] shadow_3_7;

    i2c_device_ctrl #(.CLK_DIV(CLK_DIV)) u_i2c_device_ctrl_0 (
        .clk(ACLK),
        .rst_n(ARESETn),
        .auto_enable(auto_enable_0),
        .dev_addr(dev_addr_0),
        .poll_gap(poll_gap_0),
        .direct_start(direct_start_pulse_0),
        .direct_rw(direct_rw_0),
        .direct_burst_en(direct_burst_en_0),
        .direct_reg_addr(direct_reg_addr_0),
        .direct_wr_data(direct_wr_data_0),
        .poll_reg_addr0(poll_reg_addr_0_0),
        .poll_reg_addr1(poll_reg_addr_0_1),
        .poll_reg_addr2(poll_reg_addr_0_2),
        .poll_reg_addr3(poll_reg_addr_0_3),
        .poll_reg_addr4(poll_reg_addr_0_4),
        .poll_reg_addr5(poll_reg_addr_0_5),
        .poll_reg_addr6(poll_reg_addr_0_6),
        .poll_reg_addr7(poll_reg_addr_0_7),
        .direct_rd_data(direct_rd_data_0),
        .direct_done(direct_done_0),
        .direct_ack_error(direct_ack_error_0),
        .busy(ctrl_busy_0),
        .auto_valid(auto_valid_0),
        .auto_poll_idx(auto_poll_idx_0),
        .irq(dev_irq_0),
        .irq_clear(irq_clear_pulse_0),
        .shadow_r0(shadow_0_0),
        .shadow_r1(shadow_0_1),
        .shadow_r2(shadow_0_2),
        .shadow_r3(shadow_0_3),
        .shadow_r4(shadow_0_4),
        .shadow_r5(shadow_0_5),
        .shadow_r6(shadow_0_6),
        .shadow_r7(shadow_0_7),
        .scl_in(i2c_scl_in[0]),
        .sda_in(i2c_sda_in[0]),
        .scl_oen(i2c_scl_oen[0]),
        .sda_oen(i2c_sda_oen[0])
    );

    i2c_device_ctrl #(.CLK_DIV(CLK_DIV)) u_i2c_device_ctrl_1 (
        .clk(ACLK),
        .rst_n(ARESETn),
        .auto_enable(auto_enable_1),
        .dev_addr(dev_addr_1),
        .poll_gap(poll_gap_1),
        .direct_start(direct_start_pulse_1),
        .direct_rw(direct_rw_1),
        .direct_burst_en(direct_burst_en_1),
        .direct_reg_addr(direct_reg_addr_1),
        .direct_wr_data(direct_wr_data_1),
        .poll_reg_addr0(poll_reg_addr_1_0),
        .poll_reg_addr1(poll_reg_addr_1_1),
        .poll_reg_addr2(poll_reg_addr_1_2),
        .poll_reg_addr3(poll_reg_addr_1_3),
        .poll_reg_addr4(poll_reg_addr_1_4),
        .poll_reg_addr5(poll_reg_addr_1_5),
        .poll_reg_addr6(poll_reg_addr_1_6),
        .poll_reg_addr7(poll_reg_addr_1_7),
        .direct_rd_data(direct_rd_data_1),
        .direct_done(direct_done_1),
        .direct_ack_error(direct_ack_error_1),
        .busy(ctrl_busy_1),
        .auto_valid(auto_valid_1),
        .auto_poll_idx(auto_poll_idx_1),
        .irq(dev_irq_1),
        .irq_clear(irq_clear_pulse_1),
        .shadow_r0(shadow_1_0),
        .shadow_r1(shadow_1_1),
        .shadow_r2(shadow_1_2),
        .shadow_r3(shadow_1_3),
        .shadow_r4(shadow_1_4),
        .shadow_r5(shadow_1_5),
        .shadow_r6(shadow_1_6),
        .shadow_r7(shadow_1_7),
        .scl_in(i2c_scl_in[1]),
        .sda_in(i2c_sda_in[1]),
        .scl_oen(i2c_scl_oen[1]),
        .sda_oen(i2c_sda_oen[1])
    );

    i2c_device_ctrl #(.CLK_DIV(CLK_DIV)) u_i2c_device_ctrl_2 (
        .clk(ACLK),
        .rst_n(ARESETn),
        .auto_enable(auto_enable_2),
        .dev_addr(dev_addr_2),
        .poll_gap(poll_gap_2),
        .direct_start(direct_start_pulse_2),
        .direct_rw(direct_rw_2),
        .direct_burst_en(direct_burst_en_2),
        .direct_reg_addr(direct_reg_addr_2),
        .direct_wr_data(direct_wr_data_2),
        .poll_reg_addr0(poll_reg_addr_2_0),
        .poll_reg_addr1(poll_reg_addr_2_1),
        .poll_reg_addr2(poll_reg_addr_2_2),
        .poll_reg_addr3(poll_reg_addr_2_3),
        .poll_reg_addr4(poll_reg_addr_2_4),
        .poll_reg_addr5(poll_reg_addr_2_5),
        .poll_reg_addr6(poll_reg_addr_2_6),
        .poll_reg_addr7(poll_reg_addr_2_7),
        .direct_rd_data(direct_rd_data_2),
        .direct_done(direct_done_2),
        .direct_ack_error(direct_ack_error_2),
        .busy(ctrl_busy_2),
        .auto_valid(auto_valid_2),
        .auto_poll_idx(auto_poll_idx_2),
        .irq(dev_irq_2),
        .irq_clear(irq_clear_pulse_2),
        .shadow_r0(shadow_2_0),
        .shadow_r1(shadow_2_1),
        .shadow_r2(shadow_2_2),
        .shadow_r3(shadow_2_3),
        .shadow_r4(shadow_2_4),
        .shadow_r5(shadow_2_5),
        .shadow_r6(shadow_2_6),
        .shadow_r7(shadow_2_7),
        .scl_in(i2c_scl_in[2]),
        .sda_in(i2c_sda_in[2]),
        .scl_oen(i2c_scl_oen[2]),
        .sda_oen(i2c_sda_oen[2])
    );

    i2c_device_ctrl #(.CLK_DIV(CLK_DIV)) u_i2c_device_ctrl_3 (
        .clk(ACLK),
        .rst_n(ARESETn),
        .auto_enable(auto_enable_3),
        .dev_addr(dev_addr_3),
        .poll_gap(poll_gap_3),
        .direct_start(direct_start_pulse_3),
        .direct_rw(direct_rw_3),
        .direct_burst_en(direct_burst_en_3),
        .direct_reg_addr(direct_reg_addr_3),
        .direct_wr_data(direct_wr_data_3),
        .poll_reg_addr0(poll_reg_addr_3_0),
        .poll_reg_addr1(poll_reg_addr_3_1),
        .poll_reg_addr2(poll_reg_addr_3_2),
        .poll_reg_addr3(poll_reg_addr_3_3),
        .poll_reg_addr4(poll_reg_addr_3_4),
        .poll_reg_addr5(poll_reg_addr_3_5),
        .poll_reg_addr6(poll_reg_addr_3_6),
        .poll_reg_addr7(poll_reg_addr_3_7),
        .direct_rd_data(direct_rd_data_3),
        .direct_done(direct_done_3),
        .direct_ack_error(direct_ack_error_3),
        .busy(ctrl_busy_3),
        .auto_valid(auto_valid_3),
        .auto_poll_idx(auto_poll_idx_3),
        .irq(dev_irq_3),
        .irq_clear(irq_clear_pulse_3),
        .shadow_r0(shadow_3_0),
        .shadow_r1(shadow_3_1),
        .shadow_r2(shadow_3_2),
        .shadow_r3(shadow_3_3),
        .shadow_r4(shadow_3_4),
        .shadow_r5(shadow_3_5),
        .shadow_r6(shadow_3_6),
        .shadow_r7(shadow_3_7),
        .scl_in(i2c_scl_in[3]),
        .sda_in(i2c_sda_in[3]),
        .scl_oen(i2c_scl_oen[3]),
        .sda_oen(i2c_sda_oen[3])
    );

    // Pure combinational register read decoder; no function is used.
    reg [31:0] rd_mux_data;
    always @(*) begin
        case (S_AXI_ARADDR)
            16'h0000: rd_mux_data = ID_VALUE;
            16'h0004: rd_mux_data = VERSION_VALUE;
            16'h0008: rd_mux_data = {28'd0, auto_enable_3, auto_enable_2, auto_enable_1, auto_enable_0};
            16'h000C: rd_mux_data = {28'd0, dev_irq_3, dev_irq_2, dev_irq_1, dev_irq_0};
            default: begin
                rd_mux_data = 32'hBAD0_ADD0;
                if (S_AXI_ARADDR[15:12] == 4'h0) begin
                    case (S_AXI_ARADDR[11:8])
                        4'h1: begin
                            case (S_AXI_ARADDR[7:0])
                                8'h00: rd_mux_data = {poll_gap_0, 9'd0, dev_addr_0};
                                8'h04: rd_mux_data = {27'd0, 1'b0, direct_rw_0, 1'b0, 1'b0, auto_enable_0};
                                8'h08: rd_mux_data = {16'd0, direct_wr_data_0, direct_reg_addr_0};
                                8'h0C: rd_mux_data = {25'd0, auto_poll_idx_0, auto_valid_0, direct_ack_error_0, direct_done_0, ctrl_busy_0};
                                8'h10: rd_mux_data = {24'd0, direct_rd_data_0};
                                8'h40: rd_mux_data = {24'd0, poll_reg_addr_0_0};
                                8'h44: rd_mux_data = {24'd0, poll_reg_addr_0_1};
                                8'h48: rd_mux_data = {24'd0, poll_reg_addr_0_2};
                                8'h4C: rd_mux_data = {24'd0, poll_reg_addr_0_3};
                                8'h50: rd_mux_data = {24'd0, poll_reg_addr_0_4};
                                8'h54: rd_mux_data = {24'd0, poll_reg_addr_0_5};
                                8'h58: rd_mux_data = {24'd0, poll_reg_addr_0_6};
                                8'h5C: rd_mux_data = {24'd0, poll_reg_addr_0_7};
                                8'h20: rd_mux_data = {24'd0, shadow_0_0};
                                8'h24: rd_mux_data = {24'd0, shadow_0_1};
                                8'h28: rd_mux_data = {24'd0, shadow_0_2};
                                8'h2C: rd_mux_data = {24'd0, shadow_0_3};
                                8'h30: rd_mux_data = {24'd0, shadow_0_4};
                                8'h34: rd_mux_data = {24'd0, shadow_0_5};
                                8'h38: rd_mux_data = {24'd0, shadow_0_6};
                                8'h3C: rd_mux_data = {24'd0, shadow_0_7};
                                default: rd_mux_data = 32'hDEAD_BEEF;
                            endcase
                        end
                        4'h2: begin
                            case (S_AXI_ARADDR[7:0])
                                8'h00: rd_mux_data = {poll_gap_1, 9'd0, dev_addr_1};
                                8'h04: rd_mux_data = {27'd0, 1'b0, direct_rw_1, 1'b0, 1'b0, auto_enable_1};
                                8'h08: rd_mux_data = {16'd0, direct_wr_data_1, direct_reg_addr_1};
                                8'h0C: rd_mux_data = {25'd0, auto_poll_idx_1, auto_valid_1, direct_ack_error_1, direct_done_1, ctrl_busy_1};
                                8'h10: rd_mux_data = {24'd0, direct_rd_data_1};
                                8'h40: rd_mux_data = {24'd0, poll_reg_addr_1_0};
                                8'h44: rd_mux_data = {24'd0, poll_reg_addr_1_1};
                                8'h48: rd_mux_data = {24'd0, poll_reg_addr_1_2};
                                8'h4C: rd_mux_data = {24'd0, poll_reg_addr_1_3};
                                8'h50: rd_mux_data = {24'd0, poll_reg_addr_1_4};
                                8'h54: rd_mux_data = {24'd0, poll_reg_addr_1_5};
                                8'h58: rd_mux_data = {24'd0, poll_reg_addr_1_6};
                                8'h5C: rd_mux_data = {24'd0, poll_reg_addr_1_7};
                                8'h20: rd_mux_data = {24'd0, shadow_1_0};
                                8'h24: rd_mux_data = {24'd0, shadow_1_1};
                                8'h28: rd_mux_data = {24'd0, shadow_1_2};
                                8'h2C: rd_mux_data = {24'd0, shadow_1_3};
                                8'h30: rd_mux_data = {24'd0, shadow_1_4};
                                8'h34: rd_mux_data = {24'd0, shadow_1_5};
                                8'h38: rd_mux_data = {24'd0, shadow_1_6};
                                8'h3C: rd_mux_data = {24'd0, shadow_1_7};
                                default: rd_mux_data = 32'hDEAD_BEEF;
                            endcase
                        end
                        4'h3: begin
                            case (S_AXI_ARADDR[7:0])
                                8'h00: rd_mux_data = {poll_gap_2, 9'd0, dev_addr_2};
                                8'h04: rd_mux_data = {27'd0, 1'b0, direct_rw_2, 1'b0, 1'b0, auto_enable_2};
                                8'h08: rd_mux_data = {16'd0, direct_wr_data_2, direct_reg_addr_2};
                                8'h0C: rd_mux_data = {25'd0, auto_poll_idx_2, auto_valid_2, direct_ack_error_2, direct_done_2, ctrl_busy_2};
                                8'h10: rd_mux_data = {24'd0, direct_rd_data_2};
                                8'h40: rd_mux_data = {24'd0, poll_reg_addr_2_0};
                                8'h44: rd_mux_data = {24'd0, poll_reg_addr_2_1};
                                8'h48: rd_mux_data = {24'd0, poll_reg_addr_2_2};
                                8'h4C: rd_mux_data = {24'd0, poll_reg_addr_2_3};
                                8'h50: rd_mux_data = {24'd0, poll_reg_addr_2_4};
                                8'h54: rd_mux_data = {24'd0, poll_reg_addr_2_5};
                                8'h58: rd_mux_data = {24'd0, poll_reg_addr_2_6};
                                8'h5C: rd_mux_data = {24'd0, poll_reg_addr_2_7};
                                8'h20: rd_mux_data = {24'd0, shadow_2_0};
                                8'h24: rd_mux_data = {24'd0, shadow_2_1};
                                8'h28: rd_mux_data = {24'd0, shadow_2_2};
                                8'h2C: rd_mux_data = {24'd0, shadow_2_3};
                                8'h30: rd_mux_data = {24'd0, shadow_2_4};
                                8'h34: rd_mux_data = {24'd0, shadow_2_5};
                                8'h38: rd_mux_data = {24'd0, shadow_2_6};
                                8'h3C: rd_mux_data = {24'd0, shadow_2_7};
                                default: rd_mux_data = 32'hDEAD_BEEF;
                            endcase
                        end
                        4'h4: begin
                            case (S_AXI_ARADDR[7:0])
                                8'h00: rd_mux_data = {poll_gap_3, 9'd0, dev_addr_3};
                                8'h04: rd_mux_data = {27'd0, 1'b0, direct_rw_3, 1'b0, 1'b0, auto_enable_3};
                                8'h08: rd_mux_data = {16'd0, direct_wr_data_3, direct_reg_addr_3};
                                8'h0C: rd_mux_data = {25'd0, auto_poll_idx_3, auto_valid_3, direct_ack_error_3, direct_done_3, ctrl_busy_3};
                                8'h10: rd_mux_data = {24'd0, direct_rd_data_3};
                                8'h40: rd_mux_data = {24'd0, poll_reg_addr_3_0};
                                8'h44: rd_mux_data = {24'd0, poll_reg_addr_3_1};
                                8'h48: rd_mux_data = {24'd0, poll_reg_addr_3_2};
                                8'h4C: rd_mux_data = {24'd0, poll_reg_addr_3_3};
                                8'h50: rd_mux_data = {24'd0, poll_reg_addr_3_4};
                                8'h54: rd_mux_data = {24'd0, poll_reg_addr_3_5};
                                8'h58: rd_mux_data = {24'd0, poll_reg_addr_3_6};
                                8'h5C: rd_mux_data = {24'd0, poll_reg_addr_3_7};
                                8'h20: rd_mux_data = {24'd0, shadow_3_0};
                                8'h24: rd_mux_data = {24'd0, shadow_3_1};
                                8'h28: rd_mux_data = {24'd0, shadow_3_2};
                                8'h2C: rd_mux_data = {24'd0, shadow_3_3};
                                8'h30: rd_mux_data = {24'd0, shadow_3_4};
                                8'h34: rd_mux_data = {24'd0, shadow_3_5};
                                8'h38: rd_mux_data = {24'd0, shadow_3_6};
                                8'h3C: rd_mux_data = {24'd0, shadow_3_7};
                                default: rd_mux_data = 32'hDEAD_BEEF;
                            endcase
                        end
                        default: ;
                    endcase
                end
            end
        endcase
    end

    reg        aw_valid_q;
    reg [15:0] awaddr_q;
    reg        w_valid_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;

    assign S_AXI_AWREADY = (!aw_valid_q) && (!S_AXI_BVALID);
    assign S_AXI_WREADY  = (!w_valid_q) && (!S_AXI_BVALID);



    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            aw_valid_q   <= 1'b0;
            awaddr_q     <= 16'd0;
            w_valid_q    <= 1'b0;
            wdata_q      <= 32'd0;
            wstrb_q      <= 4'd0;
            S_AXI_BRESP  <= 2'b00;
            S_AXI_BVALID <= 1'b0;
            dev_addr_0 <= 7'h50;
            poll_gap_0 <= 16'd1000;
            auto_enable_0 <= 1'b0;
            direct_rw_0 <= 1'b1;
            direct_burst_en_0 <= 1'b0;
            direct_reg_addr_0 <= 8'd0;
            direct_wr_data_0 <= 8'd0;
            direct_start_pulse_0 <= 1'b0;
            irq_clear_pulse_0 <= 1'b0;
            poll_reg_addr_0_0 <= 8'd0;
            poll_reg_addr_0_1 <= 8'd1;
            poll_reg_addr_0_2 <= 8'd2;
            poll_reg_addr_0_3 <= 8'd3;
            poll_reg_addr_0_4 <= 8'd4;
            poll_reg_addr_0_5 <= 8'd5;
            poll_reg_addr_0_6 <= 8'd6;
            poll_reg_addr_0_7 <= 8'd7;
            dev_addr_1 <= 7'h51;
            poll_gap_1 <= 16'd1000;
            auto_enable_1 <= 1'b0;
            direct_rw_1 <= 1'b1;
            direct_burst_en_1 <= 1'b0;
            direct_reg_addr_1 <= 8'd0;
            direct_wr_data_1 <= 8'd0;
            direct_start_pulse_1 <= 1'b0;
            irq_clear_pulse_1 <= 1'b0;
            poll_reg_addr_1_0 <= 8'd0;
            poll_reg_addr_1_1 <= 8'd1;
            poll_reg_addr_1_2 <= 8'd2;
            poll_reg_addr_1_3 <= 8'd3;
            poll_reg_addr_1_4 <= 8'd4;
            poll_reg_addr_1_5 <= 8'd5;
            poll_reg_addr_1_6 <= 8'd6;
            poll_reg_addr_1_7 <= 8'd7;
            dev_addr_2 <= 7'h52;
            poll_gap_2 <= 16'd1000;
            auto_enable_2 <= 1'b0;
            direct_rw_2 <= 1'b1;
            direct_burst_en_2 <= 1'b0;
            direct_reg_addr_2 <= 8'd0;
            direct_wr_data_2 <= 8'd0;
            direct_start_pulse_2 <= 1'b0;
            irq_clear_pulse_2 <= 1'b0;
            poll_reg_addr_2_0 <= 8'd0;
            poll_reg_addr_2_1 <= 8'd1;
            poll_reg_addr_2_2 <= 8'd2;
            poll_reg_addr_2_3 <= 8'd3;
            poll_reg_addr_2_4 <= 8'd4;
            poll_reg_addr_2_5 <= 8'd5;
            poll_reg_addr_2_6 <= 8'd6;
            poll_reg_addr_2_7 <= 8'd7;
            dev_addr_3 <= 7'h53;
            poll_gap_3 <= 16'd1000;
            auto_enable_3 <= 1'b0;
            direct_rw_3 <= 1'b1;
            direct_burst_en_3 <= 1'b0;
            direct_reg_addr_3 <= 8'd0;
            direct_wr_data_3 <= 8'd0;
            direct_start_pulse_3 <= 1'b0;
            irq_clear_pulse_3 <= 1'b0;
            poll_reg_addr_3_0 <= 8'd0;
            poll_reg_addr_3_1 <= 8'd1;
            poll_reg_addr_3_2 <= 8'd2;
            poll_reg_addr_3_3 <= 8'd3;
            poll_reg_addr_3_4 <= 8'd4;
            poll_reg_addr_3_5 <= 8'd5;
            poll_reg_addr_3_6 <= 8'd6;
            poll_reg_addr_3_7 <= 8'd7;
        end else begin
            direct_start_pulse_0 <= 1'b0;
            irq_clear_pulse_0 <= 1'b0;
            direct_start_pulse_1 <= 1'b0;
            irq_clear_pulse_1 <= 1'b0;
            direct_start_pulse_2 <= 1'b0;
            irq_clear_pulse_2 <= 1'b0;
            direct_start_pulse_3 <= 1'b0;
            irq_clear_pulse_3 <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_valid_q <= 1'b1;
                awaddr_q <= S_AXI_AWADDR;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_valid_q <= 1'b1;
                wdata_q <= S_AXI_WDATA;
                wstrb_q <= S_AXI_WSTRB;
            end
            if (S_AXI_BVALID) begin
                if (S_AXI_BREADY) begin
                    S_AXI_BVALID <= 1'b0;
                end
            end else if (aw_valid_q && w_valid_q) begin
                // Inline AXI-Lite register write decoder (no task).
                if (awaddr_q[15:12] == 4'h0) begin
                    case (awaddr_q[11:8])
                        4'h1: begin
                            case (awaddr_q[7:0])
                                8'h00: begin
                                    if (wstrb_q[0]) dev_addr_0 <= wdata_q[6:0];
                                    if (wstrb_q[2] || wstrb_q[3]) poll_gap_0 <= wdata_q[31:16];
                                end
                                8'h04: begin
                                    if (wstrb_q[0]) begin
                                        auto_enable_0 <= wdata_q[0];
                                        direct_rw_0 <= wdata_q[2];
                                        direct_burst_en_0 <= wdata_q[3];
                                        if (wdata_q[1]) direct_start_pulse_0 <= 1'b1;
                                        if (wdata_q[4]) irq_clear_pulse_0 <= 1'b1;
                                    end
                                end
                                8'h08: begin
                                    if (wstrb_q[0]) direct_reg_addr_0 <= wdata_q[7:0];
                                    if (wstrb_q[1]) direct_wr_data_0 <= wdata_q[15:8];
                                end
                                8'h40: if (wstrb_q[0]) poll_reg_addr_0_0 <= wdata_q[7:0];
                                8'h44: if (wstrb_q[0]) poll_reg_addr_0_1 <= wdata_q[7:0];
                                8'h48: if (wstrb_q[0]) poll_reg_addr_0_2 <= wdata_q[7:0];
                                8'h4C: if (wstrb_q[0]) poll_reg_addr_0_3 <= wdata_q[7:0];
                                8'h50: if (wstrb_q[0]) poll_reg_addr_0_4 <= wdata_q[7:0];
                                8'h54: if (wstrb_q[0]) poll_reg_addr_0_5 <= wdata_q[7:0];
                                8'h58: if (wstrb_q[0]) poll_reg_addr_0_6 <= wdata_q[7:0];
                                8'h5C: if (wstrb_q[0]) poll_reg_addr_0_7 <= wdata_q[7:0];
                                default: ;
                            endcase
                        end
                        4'h2: begin
                            case (awaddr_q[7:0])
                                8'h00: begin
                                    if (wstrb_q[0]) dev_addr_1 <= wdata_q[6:0];
                                    if (wstrb_q[2] || wstrb_q[3]) poll_gap_1 <= wdata_q[31:16];
                                end
                                8'h04: begin
                                    if (wstrb_q[0]) begin
                                        auto_enable_1 <= wdata_q[0];
                                        direct_rw_1 <= wdata_q[2];
                                        direct_burst_en_1 <= wdata_q[3];
                                        if (wdata_q[1]) direct_start_pulse_1 <= 1'b1;
                                        if (wdata_q[4]) irq_clear_pulse_1 <= 1'b1;
                                    end
                                end
                                8'h08: begin
                                    if (wstrb_q[0]) direct_reg_addr_1 <= wdata_q[7:0];
                                    if (wstrb_q[1]) direct_wr_data_1 <= wdata_q[15:8];
                                end
                                8'h40: if (wstrb_q[0]) poll_reg_addr_1_0 <= wdata_q[7:0];
                                8'h44: if (wstrb_q[0]) poll_reg_addr_1_1 <= wdata_q[7:0];
                                8'h48: if (wstrb_q[0]) poll_reg_addr_1_2 <= wdata_q[7:0];
                                8'h4C: if (wstrb_q[0]) poll_reg_addr_1_3 <= wdata_q[7:0];
                                8'h50: if (wstrb_q[0]) poll_reg_addr_1_4 <= wdata_q[7:0];
                                8'h54: if (wstrb_q[0]) poll_reg_addr_1_5 <= wdata_q[7:0];
                                8'h58: if (wstrb_q[0]) poll_reg_addr_1_6 <= wdata_q[7:0];
                                8'h5C: if (wstrb_q[0]) poll_reg_addr_1_7 <= wdata_q[7:0];
                                default: ;
                            endcase
                        end
                        4'h3: begin
                            case (awaddr_q[7:0])
                                8'h00: begin
                                    if (wstrb_q[0]) dev_addr_2 <= wdata_q[6:0];
                                    if (wstrb_q[2] || wstrb_q[3]) poll_gap_2 <= wdata_q[31:16];
                                end
                                8'h04: begin
                                    if (wstrb_q[0]) begin
                                        auto_enable_2 <= wdata_q[0];
                                        direct_rw_2 <= wdata_q[2];
                                        direct_burst_en_2 <= wdata_q[3];
                                        if (wdata_q[1]) direct_start_pulse_2 <= 1'b1;
                                        if (wdata_q[4]) irq_clear_pulse_2 <= 1'b1;
                                    end
                                end
                                8'h08: begin
                                    if (wstrb_q[0]) direct_reg_addr_2 <= wdata_q[7:0];
                                    if (wstrb_q[1]) direct_wr_data_2 <= wdata_q[15:8];
                                end
                                8'h40: if (wstrb_q[0]) poll_reg_addr_2_0 <= wdata_q[7:0];
                                8'h44: if (wstrb_q[0]) poll_reg_addr_2_1 <= wdata_q[7:0];
                                8'h48: if (wstrb_q[0]) poll_reg_addr_2_2 <= wdata_q[7:0];
                                8'h4C: if (wstrb_q[0]) poll_reg_addr_2_3 <= wdata_q[7:0];
                                8'h50: if (wstrb_q[0]) poll_reg_addr_2_4 <= wdata_q[7:0];
                                8'h54: if (wstrb_q[0]) poll_reg_addr_2_5 <= wdata_q[7:0];
                                8'h58: if (wstrb_q[0]) poll_reg_addr_2_6 <= wdata_q[7:0];
                                8'h5C: if (wstrb_q[0]) poll_reg_addr_2_7 <= wdata_q[7:0];
                                default: ;
                            endcase
                        end
                        4'h4: begin
                            case (awaddr_q[7:0])
                                8'h00: begin
                                    if (wstrb_q[0]) dev_addr_3 <= wdata_q[6:0];
                                    if (wstrb_q[2] || wstrb_q[3]) poll_gap_3 <= wdata_q[31:16];
                                end
                                8'h04: begin
                                    if (wstrb_q[0]) begin
                                        auto_enable_3 <= wdata_q[0];
                                        direct_rw_3 <= wdata_q[2];
                                        direct_burst_en_3 <= wdata_q[3];
                                        if (wdata_q[1]) direct_start_pulse_3 <= 1'b1;
                                        if (wdata_q[4]) irq_clear_pulse_3 <= 1'b1;
                                    end
                                end
                                8'h08: begin
                                    if (wstrb_q[0]) direct_reg_addr_3 <= wdata_q[7:0];
                                    if (wstrb_q[1]) direct_wr_data_3 <= wdata_q[15:8];
                                end
                                8'h40: if (wstrb_q[0]) poll_reg_addr_3_0 <= wdata_q[7:0];
                                8'h44: if (wstrb_q[0]) poll_reg_addr_3_1 <= wdata_q[7:0];
                                8'h48: if (wstrb_q[0]) poll_reg_addr_3_2 <= wdata_q[7:0];
                                8'h4C: if (wstrb_q[0]) poll_reg_addr_3_3 <= wdata_q[7:0];
                                8'h50: if (wstrb_q[0]) poll_reg_addr_3_4 <= wdata_q[7:0];
                                8'h54: if (wstrb_q[0]) poll_reg_addr_3_5 <= wdata_q[7:0];
                                8'h58: if (wstrb_q[0]) poll_reg_addr_3_6 <= wdata_q[7:0];
                                8'h5C: if (wstrb_q[0]) poll_reg_addr_3_7 <= wdata_q[7:0];
                                default: ;
                            endcase
                        end
                        default: ;
                    endcase
                end
                aw_valid_q <= 1'b0;
                w_valid_q <= 1'b0;
                S_AXI_BRESP <= 2'b00;
                S_AXI_BVALID <= 1'b1;
            end
        end
    end

    assign S_AXI_ARREADY = (!S_AXI_RVALID);

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            S_AXI_RDATA  <= 32'd0;
            S_AXI_RRESP  <= 2'b00;
            S_AXI_RVALID <= 1'b0;
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                S_AXI_RDATA <= rd_mux_data;
                S_AXI_RRESP <= 2'b00;
                S_AXI_RVALID <= 1'b1;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end
endmodule
