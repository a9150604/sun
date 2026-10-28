`timescale 1ns/1ps
// Certus-NX PicoRV32 first-boot SoC. THIS IS NOT THE PCIe/AXI-Lite VERSION.
// Requires official third-party picorv32.v in the same Radiant project.
module picorv32_bringup_top #(
    parameter LED_ACTIVE_LOW = 0,
    parameter GPIO_DEBUG_MODE = 1
)(
    input  wire       clk_in,
    input  wire       btn_reset_n,
    input  wire [3:0] switches,
    output wire [7:0] led
);
    // Active-low asynchronous assertion, synchronous release.
    reg [1:0] reset_sync = 2'b00;
    always @(posedge clk_in or negedge btn_reset_n) begin
        if (!btn_reset_n) reset_sync <= 2'b00;
        else              reset_sync <= {reset_sync[0], 1'b1};
    end
    wire resetn = reset_sync[1];

    wire        trap;
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_4000),
        .COMPRESSED_ISA(0),
        .ENABLE_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0)
    ) cpu (
        .clk(clk_in), .resetn(resetn), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'd0)
    );

    // CPU program/data at 0x0000_0000..0x0000_3FFF (16 KiB).
    // Use synchronous memory read to favor EBR inference in Radiant.
    reg [31:0] ram [0:4095];
    initial $readmemh("firmware.hex", ram);

    wire sel_ram = (mem_addr[31:14] == 18'd0);
    wire sel_led = (mem_addr[31:2] == (32'h1000_0000 >> 2));
    wire sel_sw  = (mem_addr[31:2] == (32'h1000_0004 >> 2));
    wire ram_access = mem_valid && !mem_ready && sel_ram;
    reg [31:0] ram_rdata;
    always @(posedge clk_in) begin
        if (ram_access) begin
            ram_rdata <= ram[mem_addr[13:2]];
            if (mem_wstrb[0]) ram[mem_addr[13:2]][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) ram[mem_addr[13:2]][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) ram[mem_addr[13:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[mem_addr[13:2]][31:24] <= mem_wdata[31:24];
        end
    end

    reg [7:0] led_reg;
    reg [31:0] io_rdata;
    reg prev_is_ram;
    assign mem_rdata = prev_is_ram ? ram_rdata : io_rdata;
    // Keep a one-cycle response and do not re-accept the held valid request.
    always @(posedge clk_in or negedge resetn) begin
        if (!resetn) begin
            mem_ready   <= 1'b0;
            prev_is_ram <= 1'b0;
            io_rdata    <= 32'd0;
            led_reg     <= 8'd0;
        end else begin
            mem_ready <= 1'b0;
            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;
                prev_is_ram <= sel_ram;
                if (sel_led) begin
                    io_rdata <= {24'd0,led_reg};
                    if (mem_wstrb[0]) led_reg <= mem_wdata[7:0];
                end else if (sel_sw) begin
                    io_rdata <= {28'd0,switches};
                end else if (!sel_ram) begin
                    io_rdata <= 32'hDEAD_BEEF;
                end
            end
        end
    end

    // Diagnostic instrumentation: record a completed request directed at SW_REG.
    // Debug-mode LEDs: [7]=trap, [6]=SW read ever seen,
    // [5]=toggles at each SW read, [4:1]=sampled SW at read, [0]=CPU blink.
    reg [3:0] sw_sampled;
    reg       sw_read_seen;
    reg       sw_read_toggle;
    reg [31:0] sw_read_count;
    always @(posedge clk_in or negedge resetn) begin
        if (!resetn) begin
            sw_sampled <= 4'b0000;
            sw_read_seen <= 1'b0;
            sw_read_toggle <= 1'b0;
            sw_read_count <= 32'b0;
        end else if (mem_valid && !mem_ready && sel_sw && mem_wstrb == 4'b0000) begin
            sw_sampled <= switches;
            sw_read_seen <= 1'b1;
            sw_read_toggle <= ~sw_read_toggle;
            sw_read_count <= sw_read_count + 1'b1;
        end
    end

    // To compare: in debug mode LED[4:1] reflects the switch
    // sampled by the *bus request*, not firmware's value.
    wire [7:0] led_normal = {trap,led_reg[6:0]};
    wire [7:0] led_debug = {trap,sw_read_seen,sw_read_toggle,sw_sampled,led_reg[0]};
    wire [7:0] led_logic = GPIO_DEBUG_MODE ? led_debug : led_normal;
    assign led = led_logic ^ {8{LED_ACTIVE_LOW}};
endmodule
