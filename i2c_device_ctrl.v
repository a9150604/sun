`timescale 1ns/1ps

module i2c_device_ctrl #(
    parameter CLK_DIV = 625
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        auto_enable,
    input  wire [6:0]  dev_addr,
    input  wire [15:0] poll_gap,

    input  wire        direct_start,
    input  wire        direct_rw,
    input  wire        direct_burst_en,
    input  wire [7:0]  direct_reg_addr,
    input  wire [7:0]  direct_wr_data,
    input  wire [7:0]  poll_reg_addr0,
    input  wire [7:0]  poll_reg_addr1,
    input  wire [7:0]  poll_reg_addr2,
    input  wire [7:0]  poll_reg_addr3,
    input  wire [7:0]  poll_reg_addr4,
    input  wire [7:0]  poll_reg_addr5,
    input  wire [7:0]  poll_reg_addr6,
    input  wire [7:0]  poll_reg_addr7,
    output reg [7:0]  direct_rd_data,
    output reg        direct_done,
    output reg        direct_ack_error,

    output reg        busy,
    output reg        auto_valid,
    output reg [2:0]  auto_poll_idx,
    output reg        irq,
    input  wire        irq_clear,

    output wire [7:0]  shadow_r0,
    output wire [7:0]  shadow_r1,
    output wire [7:0]  shadow_r2,
    output wire [7:0]  shadow_r3,
    output wire [7:0]  shadow_r4,
    output wire [7:0]  shadow_r5,
    output wire [7:0]  shadow_r6,
    output wire [7:0]  shadow_r7,

    input  wire        scl_in,
    input  wire        sda_in,
    output reg         scl_oen,
    output reg         sda_oen
);

    localparam [2:0] DEV_ST_IDLE = 3'd0;
    localparam [2:0] DEV_ST_GAP = 3'd1;
    localparam [2:0] DEV_ST_START_AUTO = 3'd2;
    localparam [2:0] DEV_ST_START_DIR = 3'd3;
    localparam [2:0] DEV_ST_WAIT = 3'd4;
    localparam [2:0] DEV_ST_SAVE = 3'd5;
    localparam OP_AUTO = 1'b0;
    localparam OP_DIR  = 1'b1;

    reg [2:0] state_q, state_d;
    reg op_src_q, op_src_d;

    reg [15:0] gap_cnt_q;
    reg        mst_start;
    reg        mst_rw;
    reg        mst_burst_en;
    reg [7:0]  mst_reg_addr;
    reg [7:0]  mst_wr_data;
    reg        mst_busy;
    reg        mst_done;
    reg        mst_ack_error;
    reg [7:0]   mst_rd_data;
    reg [7:0] shadow_q0;
    reg [7:0] shadow_q1;
    reg [7:0] shadow_q2;
    reg [7:0] shadow_q3;
    reg [7:0] shadow_q4;
    reg [7:0] shadow_q5;
    reg [7:0] shadow_q6;
    reg [7:0] shadow_q7;
    reg [7:0]  poll_reg_addr_mux;

    always @(*) begin
        case (auto_poll_idx)
            3'd0: poll_reg_addr_mux = poll_reg_addr0;
            3'd1: poll_reg_addr_mux = poll_reg_addr1;
            3'd2: poll_reg_addr_mux = poll_reg_addr2;
            3'd3: poll_reg_addr_mux = poll_reg_addr3;
            3'd4: poll_reg_addr_mux = poll_reg_addr4;
            3'd5: poll_reg_addr_mux = poll_reg_addr5;
            3'd6: poll_reg_addr_mux = poll_reg_addr6;
            default: poll_reg_addr_mux = poll_reg_addr7;
        endcase
    end

    assign shadow_r0 = shadow_q0;
    assign shadow_r1 = shadow_q1;
    assign shadow_r2 = shadow_q2;
    assign shadow_r3 = shadow_q3;
    assign shadow_r4 = shadow_q4;
    assign shadow_r5 = shadow_q5;
    assign shadow_r6 = shadow_q6;
    assign shadow_r7 = shadow_q7;

    // Byte-level I2C controller is flattened below (no submodule instance).

    // FSM process 2: combinational next-state logic.
    always @(*) begin
        state_d = state_q;
        op_src_d = op_src_q;

        case (state_q)
            DEV_ST_IDLE: begin
                if (direct_start) begin
                    state_d  = DEV_ST_START_DIR;
                    op_src_d = OP_DIR;
                end else if (auto_enable) begin
                    state_d  = DEV_ST_GAP;
                    op_src_d = OP_AUTO;
                end
            end
            DEV_ST_GAP: begin
                if (direct_start) begin
                    state_d  = DEV_ST_START_DIR;
                    op_src_d = OP_DIR;
                end else if (!auto_enable) begin
                    state_d = DEV_ST_IDLE;
                end else if (gap_cnt_q >= poll_gap) begin
                    state_d  = DEV_ST_START_AUTO;
                    op_src_d = OP_AUTO;
                end
            end
            DEV_ST_START_AUTO: state_d = DEV_ST_WAIT;
            DEV_ST_START_DIR : state_d = DEV_ST_WAIT;
            DEV_ST_WAIT      : if (mst_done) state_d = DEV_ST_SAVE;
            DEV_ST_SAVE      : state_d = DEV_ST_IDLE;
            default          : state_d = DEV_ST_IDLE;
        endcase
    end

    // FSM process 1: state and registered datapath/outputs.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q          <= DEV_ST_IDLE;
            op_src_q         <= OP_AUTO;
            mst_start        <= 1'b0;
            mst_rw           <= 1'b0;
            mst_burst_en     <= 1'b0;
            mst_reg_addr     <= 0;
            mst_wr_data      <= 0;
            direct_rd_data   <= 0;
            direct_done      <= 1'b0;
            direct_ack_error <= 1'b0;
            busy             <= 1'b0;
            auto_valid       <= 1'b0;
            auto_poll_idx    <= 3'd0;
            irq              <= 1'b0;
            gap_cnt_q        <= 0;
            shadow_q0 <= 8'd0;
            shadow_q1 <= 8'd0;
            shadow_q2 <= 8'd0;
            shadow_q3 <= 8'd0;
            shadow_q4 <= 8'd0;
            shadow_q5 <= 8'd0;
            shadow_q6 <= 8'd0;
            shadow_q7 <= 8'd0;
        end else begin
            state_q   <= state_d;
            op_src_q  <= op_src_d;
            mst_start <= 1'b0;

            if (irq_clear) begin
                irq              <= 1'b0;
                direct_done      <= 1'b0;
                direct_ack_error <= 1'b0;
            end

            case (state_q)
                DEV_ST_IDLE: begin
                    busy      <= 1'b0;
                    gap_cnt_q <= 0;
                end
                DEV_ST_GAP: begin
                    busy <= 1'b0;
                    if (gap_cnt_q < poll_gap) gap_cnt_q <= gap_cnt_q + 16'd1;
                end
                DEV_ST_START_AUTO: begin
                    busy         <= 1'b1;
                    mst_start    <= 1'b1;
                    mst_rw       <= 1'b1;
                    mst_burst_en <= 1'b0;
                    mst_reg_addr <= poll_reg_addr_mux;
                    mst_wr_data  <= 8'd0;
                    gap_cnt_q    <= 0;
                end
                DEV_ST_START_DIR: begin
                    busy             <= 1'b1;
                    mst_start        <= 1'b1;
                    direct_done      <= 1'b0;
                    direct_ack_error <= 1'b0;
                    irq              <= 1'b0;
                    mst_rw           <= direct_rw;
                    mst_burst_en     <= direct_burst_en;
                    mst_reg_addr     <= direct_reg_addr;
                    mst_wr_data      <= direct_wr_data;
                    gap_cnt_q        <= 0;
                end
                DEV_ST_WAIT: begin
                    busy <= 1'b1;
                end
                DEV_ST_SAVE: begin
                    busy <= 1'b0;
                    if (op_src_q == OP_DIR) begin
                        direct_rd_data   <= mst_rd_data;
                        direct_ack_error <= mst_ack_error;
                        direct_done      <= 1'b1;
                        irq              <= 1'b1;
                    end else begin
                        if (!mst_ack_error) begin
                            case (auto_poll_idx)
                                3'd0: shadow_q0 <= mst_rd_data;
                                3'd1: shadow_q1 <= mst_rd_data;
                                3'd2: shadow_q2 <= mst_rd_data;
                                3'd3: shadow_q3 <= mst_rd_data;
                                3'd4: shadow_q4 <= mst_rd_data;
                                3'd5: shadow_q5 <= mst_rd_data;
                                3'd6: shadow_q6 <= mst_rd_data;
                                default: shadow_q7 <= mst_rd_data;
                            endcase
                            auto_valid              <= 1'b1;
                        end
                        auto_poll_idx <= (auto_poll_idx == 3'd7) ? 3'd0 : auto_poll_idx + 3'd1;
                    end
                end
                default: ;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Original i2c_master_byte RTL integrated at signal/logic level.
    // There is no second module and no separate I2C byte instance.
    // ---------------------------------------------------------------
    // Flattened byte controller: local state encodings, registers, and 2-process FSM.
    localparam [4:0] I2C_ST_IDLE = 5'd0;
    localparam [4:0] I2C_ST_START_A = 5'd1;
    localparam [4:0] I2C_ST_START_B = 5'd2;
    localparam [4:0] I2C_ST_BURST_START = 5'd3;
    localparam [4:0] I2C_ST_LOAD_BYTE = 5'd4;
    localparam [4:0] I2C_ST_BIT_LOW = 5'd5;
    localparam [4:0] I2C_ST_BIT_HIGH = 5'd6;
    localparam [4:0] I2C_ST_ACK_LOW = 5'd7;
    localparam [4:0] I2C_ST_ACK_HIGH = 5'd8;
    localparam [4:0] I2C_ST_RX_LOW = 5'd9;
    localparam [4:0] I2C_ST_RX_HIGH = 5'd10;
    localparam [4:0] I2C_ST_MACK_LOW = 5'd11;
    localparam [4:0] I2C_ST_MACK_HIGH = 5'd12;
    localparam [4:0] I2C_ST_RESTART_A = 5'd13;
    localparam [4:0] I2C_ST_RESTART_B = 5'd14;
    localparam [4:0] I2C_ST_RESTART_C = 5'd15;
    localparam [4:0] I2C_ST_STOP_A = 5'd16;
    localparam [4:0] I2C_ST_STOP_B = 5'd17;
    localparam [4:0] I2C_ST_DONE = 5'd18;
    localparam [2:0] I2C_PH_ADDR_W = 3'd0;
    localparam [2:0] I2C_PH_REG = 3'd1;
    localparam [2:0] I2C_PH_WDATA = 3'd2;
    localparam [2:0] I2C_PH_ADDR_R = 3'd3;
    localparam [2:0] I2C_PH_RDATA = 3'd4;

    reg [4:0] byte_state_q, byte_state_d;
    reg [2:0] byte_phase_q, byte_phase_d;

    reg [15:0] byte_div_cnt_q;
    reg        byte_tick_q;
    reg [7:0]  byte_shifter_q;
    reg [2:0]  byte_bit_cnt_q;
    reg        byte_op_rw_q;
    reg [6:0]  byte_op_dev_addr_q;
    reg [7:0]  byte_op_reg_addr_q;
    reg [7:0]  byte_op_wr_data_q;
    reg        byte_start_brust;

    // FSM process 2: combinational next-state logic.
    always @(*) begin
        byte_state_d = byte_state_q;
        byte_phase_d = byte_phase_q;

        case (byte_state_q)
            I2C_ST_IDLE: begin
                if (mst_start) begin
                    byte_state_d = I2C_ST_START_A;
                    byte_phase_d = I2C_PH_ADDR_W;
                end
            end
            I2C_ST_START_A:   if (byte_tick_q) byte_state_d = I2C_ST_START_B;
            I2C_ST_START_B:   if (byte_tick_q) byte_state_d = I2C_ST_LOAD_BYTE;
            I2C_ST_BURST_START: if (byte_tick_q) byte_state_d = (byte_start_brust) ? I2C_ST_LOAD_BYTE : I2C_ST_BURST_START;
            I2C_ST_LOAD_BYTE: if (byte_tick_q) byte_state_d = (byte_phase_q == I2C_PH_RDATA) ? I2C_ST_RX_LOW : I2C_ST_BIT_LOW;
            I2C_ST_BIT_LOW:   if (byte_tick_q) byte_state_d = I2C_ST_BIT_HIGH;
            I2C_ST_BIT_HIGH:  if (byte_tick_q) byte_state_d = (byte_bit_cnt_q == 3'd0) ? I2C_ST_ACK_LOW : I2C_ST_BIT_LOW;
            I2C_ST_ACK_LOW:   if (byte_tick_q) byte_state_d = I2C_ST_ACK_HIGH;
            I2C_ST_ACK_HIGH:  if (byte_tick_q) begin
                if (mst_ack_error) begin
                    byte_state_d = I2C_ST_STOP_A;
                end else begin
                    case (byte_phase_q)
                        I2C_PH_ADDR_W: begin
                            byte_state_d = I2C_ST_LOAD_BYTE;
                            byte_phase_d = I2C_PH_REG;
                        end
                        I2C_PH_REG: begin
                            if (byte_op_rw_q) begin
                                byte_state_d = I2C_ST_RESTART_A;
                                byte_phase_d = I2C_PH_ADDR_R;
                            end else begin
                                byte_state_d = I2C_ST_LOAD_BYTE;
                                byte_phase_d = I2C_PH_WDATA;
                            end
                        end
                        I2C_PH_WDATA: begin
                            byte_state_d = (mst_burst_en) ? I2C_ST_BURST_START : I2C_ST_STOP_A;
                        end
                        I2C_PH_ADDR_R: begin
                            byte_state_d = I2C_ST_LOAD_BYTE;
                            byte_phase_d = I2C_PH_RDATA;
                        end
                        default: byte_state_d = I2C_ST_STOP_A;
                    endcase
                end
            end
            I2C_ST_RX_LOW:     if (byte_tick_q) byte_state_d = I2C_ST_RX_HIGH;
            I2C_ST_RX_HIGH:    if (byte_tick_q) byte_state_d = (byte_bit_cnt_q == 3'd0) ? I2C_ST_MACK_LOW : I2C_ST_RX_LOW;
            I2C_ST_MACK_LOW:   if (byte_tick_q) byte_state_d = I2C_ST_MACK_HIGH;
            I2C_ST_MACK_HIGH:  if (byte_tick_q) byte_state_d = (mst_burst_en) ? I2C_ST_BURST_START : I2C_ST_STOP_A;
            I2C_ST_RESTART_A:  if (byte_tick_q) byte_state_d = I2C_ST_RESTART_B;
            I2C_ST_RESTART_B:  if (byte_tick_q) byte_state_d = I2C_ST_RESTART_C;
            I2C_ST_RESTART_C:  if (byte_tick_q) byte_state_d = I2C_ST_LOAD_BYTE;
            I2C_ST_STOP_A:     if (byte_tick_q) byte_state_d = I2C_ST_STOP_B;
            I2C_ST_STOP_B:     if (byte_tick_q) byte_state_d = I2C_ST_DONE;
            I2C_ST_DONE:       if (byte_tick_q) byte_state_d = I2C_ST_IDLE;
            default:                      byte_state_d = I2C_ST_IDLE;
        endcase
    end

    // FSM process 1: state and registered datapath/outputs.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_div_cnt_q    <= 16'd0;
            byte_tick_q       <= 1'b0;
            byte_start_brust  <= 1'b0;
            byte_state_q        <= I2C_ST_IDLE;
            byte_phase_q        <= I2C_PH_ADDR_W;
            mst_busy           <= 1'b0;
            mst_done           <= 1'b0;
            mst_ack_error      <= 1'b0;
            mst_rd_data        <= 0;
            scl_oen        <= 1'b1;
            sda_oen        <= 1'b1;
            byte_shifter_q      <= 0;
            byte_bit_cnt_q      <= 3'd7;
            byte_op_rw_q        <= 1'b0;
            byte_op_dev_addr_q  <= 0;
            byte_op_reg_addr_q  <= 0;
            byte_op_wr_data_q   <= 0;
        end else begin
            byte_state_q <= byte_state_d;
            byte_phase_q <= byte_phase_d;
            byte_start_brust <= mst_start;
            // Divider from original byte-master RTL; ticks only while active.
            if (mst_busy) begin
                if (byte_div_cnt_q == CLK_DIV-1) begin
                    byte_div_cnt_q <= 16'd0;
                    byte_tick_q    <= 1'b1;
                end else begin
                    byte_div_cnt_q <= byte_div_cnt_q + 16'd1;
                    byte_tick_q    <= 1'b0;
                end
            end else begin
                byte_div_cnt_q <= 16'd0;
                byte_tick_q    <= 1'b0;
            end
            mst_done <= 1'b0;

            if (byte_state_q == I2C_ST_IDLE && mst_start) begin
                mst_busy           <= 1'b1;
                mst_ack_error      <= 1'b0;
                byte_op_rw_q        <= mst_rw;
                byte_op_dev_addr_q  <= dev_addr;
                byte_op_reg_addr_q  <= mst_reg_addr;
                byte_op_wr_data_q   <= mst_wr_data;
            end

            if (byte_tick_q) begin
                case (byte_state_q)
                    I2C_ST_START_A: begin
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_START_B: begin
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b0;
                    end
                    I2C_ST_BURST_START: begin
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b0;
                        mst_done    <= 1'b1;
                    end
                    I2C_ST_LOAD_BYTE: begin
                        scl_oen <= 1'b0;
                        sda_oen <= 1'b1;
                        byte_bit_cnt_q <= 3'd7;
                        case (byte_phase_q)
                            I2C_PH_ADDR_W: byte_shifter_q <= {byte_op_dev_addr_q, 1'b0};
                            I2C_PH_REG:    byte_shifter_q <= byte_op_reg_addr_q;
                            I2C_PH_WDATA:  byte_shifter_q <= byte_op_wr_data_q;
                            I2C_PH_ADDR_R: byte_shifter_q <= {byte_op_dev_addr_q, 1'b1};
                            default:       byte_shifter_q <= 8'hFF;
                        endcase
                    end
                    I2C_ST_BIT_LOW: begin
                        scl_oen <= 1'b0;
                        sda_oen <= byte_shifter_q[7] ? 1'b1 : 1'b0;
                    end
                    I2C_ST_BIT_HIGH: begin
                        scl_oen <= 1'b1;
                        if (byte_bit_cnt_q != 3'd0) begin
                            byte_shifter_q <= {byte_shifter_q[6:0], 1'b0};
                            byte_bit_cnt_q <= byte_bit_cnt_q - 3'd1;
                        end
                    end
                    I2C_ST_ACK_LOW: begin
                        scl_oen <= 1'b0;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_ACK_HIGH: begin
                        scl_oen <= 1'b1;
                        if (sda_in) mst_ack_error <= 1'b1;
                    end
                    I2C_ST_RX_LOW: begin
                        scl_oen <= 1'b0;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_RX_HIGH: begin
                        scl_oen <= 1'b1;
                        mst_rd_data[byte_bit_cnt_q] <= sda_in;
                        if (byte_bit_cnt_q != 3'd0) byte_bit_cnt_q <= byte_bit_cnt_q - 3'd1;
                    end
                    I2C_ST_MACK_LOW: begin
                        scl_oen <= 1'b0;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_MACK_HIGH: begin
                        scl_oen <= 1'b1;
                    end
                    I2C_ST_RESTART_A: begin
                        scl_oen <= 1'b0;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_RESTART_B: begin
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_RESTART_C: begin
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b0;
                    end
                    I2C_ST_STOP_A: begin
                        scl_oen <= 1'b0;
                        sda_oen <= 1'b0;
                    end
                    I2C_ST_STOP_B: begin
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b1;
                    end
                    I2C_ST_DONE: begin
                        mst_busy    <= 1'b0;
                        mst_done    <= 1'b1;
                        scl_oen <= 1'b1;
                        sda_oen <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
