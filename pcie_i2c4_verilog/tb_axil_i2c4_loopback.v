`timescale 1ns/1ps

// tb_axil_i2c4_loopback.v -- Verilog-2001 self-checking testbench
// DUT: axil_i2c4_regs.v + i2c_device_ctrl.v
// NO I2C slave model, NO external ACK source.
// 0<->1 share open-drain bus 01; 2<->3 share open-drain bus 23.
// When a master transmits, the OTHER master's input pins see the same wire.
// Passive receivers below sample these input pins but NEVER drive SCL/SDA.
// IMPORTANT: DUT ports are master-only. The opposite DUT channel is NOT an
// I2C slave and cannot ACK/deserialize data into its registers. Thus expected
// result on this bus is NACK, while the transmitted address byte is checked.

module tb_axil_i2c4_loopback;
    localparam integer HALF_CLK_NS = 5;
    localparam integer I2C_DIV = 4;  // fast I2C simulation

    reg ACLK;
    reg ARESETn;

    reg  [15:0] S_AXI_AWADDR;
    reg         S_AXI_AWVALID;
    wire        S_AXI_AWREADY;
    reg  [31:0] S_AXI_WDATA;
    reg  [3:0]  S_AXI_WSTRB;
    reg         S_AXI_WVALID;
    wire        S_AXI_WREADY;
    wire [1:0]  S_AXI_BRESP;
    wire        S_AXI_BVALID;
    reg         S_AXI_BREADY;
    reg  [15:0] S_AXI_ARADDR;
    reg         S_AXI_ARVALID;
    wire        S_AXI_ARREADY;
    wire [31:0] S_AXI_RDATA;
    wire [1:0]  S_AXI_RRESP;
    wire        S_AXI_RVALID;
    reg         S_AXI_RREADY;

    wire [3:0] i2c_scl_in;
    wire [3:0] i2c_sda_in;
    wire [3:0] i2c_scl_oen;
    wire [3:0] i2c_sda_oen;

    // Four open-drain endpoints; two shared physical I2C buses.
    // Resolved pullup gives '1' if EVERY participant releases the line.
    tri1 scl_01;
    tri1 sda_01;
    tri1 scl_23;
    tri1 sda_23;

    assign scl_01 = i2c_scl_oen[0] ? 1'bz : 1'b0;
    assign scl_01 = i2c_scl_oen[1] ? 1'bz : 1'b0;
    assign sda_01 = i2c_sda_oen[0] ? 1'bz : 1'b0;
    assign sda_01 = i2c_sda_oen[1] ? 1'bz : 1'b0;
    assign scl_23 = i2c_scl_oen[2] ? 1'bz : 1'b0;
    assign scl_23 = i2c_scl_oen[3] ? 1'bz : 1'b0;
    assign sda_23 = i2c_sda_oen[2] ? 1'bz : 1'b0;
    assign sda_23 = i2c_sda_oen[3] ? 1'bz : 1'b0;

    assign i2c_scl_in = {scl_23, scl_23, scl_01, scl_01};
    assign i2c_sda_in = {sda_23, sda_23, sda_01, sda_01};

    axil_i2c4_regs #(.CLK_DIV(I2C_DIV)) dut (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID), .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP), .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY), .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP), .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        .i2c_scl_in(i2c_scl_in), .i2c_sda_in(i2c_sda_in),
        .i2c_scl_oen(i2c_scl_oen), .i2c_sda_oen(i2c_sda_oen)
    );

    always #HALF_CLK_NS ACLK = ~ACLK;

    integer checks;
    integer fails;
    reg [31:0] readback;
    reg [31:0] status;

    // Current TX DUT port (0 or 1, and 2 or 3 respectively).
    // The monitor samples the OTHER port's actual I2C input pins.
    integer tx_01;
    integer tx_23;
    wire rx_sda_01 = (tx_01 == 0) ? i2c_sda_in[1] : i2c_sda_in[0];
    wire rx_sda_23 = (tx_23 == 2) ? i2c_sda_in[3] : i2c_sda_in[2];

    // Non-intrusive I2C sniffer for bus 01, 8 bits + ACK/NACK bit.
    reg active_01;
    reg [7:0] shift_01;
    reg [7:0] addr_byte_01;
    integer bit_count_01;
    integer byte_count_01;
    integer address_count_01;
    integer start_count_01;
    integer stop_count_01;
    integer nack_count_01;

    always @(negedge sda_01) begin
        if (ARESETn && scl_01 === 1'b1) begin
            active_01 = 1'b1;
            bit_count_01 = 0;
            byte_count_01 = 0;
            shift_01 = 0;
            start_count_01 = start_count_01 + 1;
            $display("[I2C01] START at %0t (TX channel %0d, passive RX channel %0d)",
                     $time, tx_01, (tx_01 == 0) ? 1 : 0);
        end
    end
    always @(posedge scl_01) begin
        if (ARESETn && active_01) begin
            if (bit_count_01 < 8) begin
                shift_01 = {shift_01[6:0], rx_sda_01};
                bit_count_01 = bit_count_01 + 1;
                if (bit_count_01 == 8) begin
                    if (byte_count_01 == 0) begin
                        addr_byte_01 = shift_01;
                        address_count_01 = address_count_01 + 1;
                    end
                    $display("[I2C01] passive RX byte %0d = 0x%02h at %0t", byte_count_01,
                             shift_01, $time);
                end
            end else begin
                if (rx_sda_01 === 1'b1) nack_count_01 = nack_count_01 + 1;
                $display("[I2C01] ACK sample = %b (%s)", rx_sda_01,
                         (rx_sda_01 === 1'b1) ? "NACK" : "ACK");
                bit_count_01 = 0;
                byte_count_01 = byte_count_01 + 1;
                shift_01 = 0;
            end
        end
    end
    always @(posedge sda_01) begin
        if (ARESETn && active_01 && scl_01 === 1'b1) begin
            active_01 = 1'b0;
            stop_count_01 = stop_count_01 + 1;
            $display("[I2C01] STOP at %0t", $time);
        end
    end

    // Non-intrusive I2C sniffer for bus 23.
    reg active_23;
    reg [7:0] shift_23;
    reg [7:0] addr_byte_23;
    integer bit_count_23;
    integer byte_count_23;
    integer address_count_23;
    integer start_count_23;
    integer stop_count_23;
    integer nack_count_23;

    always @(negedge sda_23) begin
        if (ARESETn && scl_23 === 1'b1) begin
            active_23 = 1'b1;
            bit_count_23 = 0;
            byte_count_23 = 0;
            shift_23 = 0;
            start_count_23 = start_count_23 + 1;
            $display("[I2C23] START at %0t (TX channel %0d, passive RX channel %0d)",
                     $time, tx_23, (tx_23 == 2) ? 3 : 2);
        end
    end
    always @(posedge scl_23) begin
        if (ARESETn && active_23) begin
            if (bit_count_23 < 8) begin
                shift_23 = {shift_23[6:0], rx_sda_23};
                bit_count_23 = bit_count_23 + 1;
                if (bit_count_23 == 8) begin
                    if (byte_count_23 == 0) begin
                        addr_byte_23 = shift_23;
                        address_count_23 = address_count_23 + 1;
                    end
                    $display("[I2C23] passive RX byte %0d = 0x%02h at %0t", byte_count_23,
                             shift_23, $time);
                end
            end else begin
                if (rx_sda_23 === 1'b1) nack_count_23 = nack_count_23 + 1;
                $display("[I2C23] ACK sample = %b (%s)", rx_sda_23,
                         (rx_sda_23 === 1'b1) ? "NACK" : "ACK");
                bit_count_23 = 0;
                byte_count_23 = byte_count_23 + 1;
                shift_23 = 0;
            end
        end
    end
    always @(posedge sda_23) begin
        if (ARESETn && active_23 && scl_23 === 1'b1) begin
            active_23 = 1'b0;
            stop_count_23 = stop_count_23 + 1;
            $display("[I2C23] STOP at %0t", $time);
        end
    end

    task check_equal;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                fails = fails + 1;
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h at %0t",
                         label, actual, expected, $time);
            end else begin
                $display("[PASS] %0s: 0x%08h", label, actual);
            end
        end
    endtask

    // Independent AXI AW/W handshakes; supports legal channel decoupling.
    task axi_write;
        input [15:0] addr;
        input [31:0] data;
        input [3:0]  strobe;
        begin
            @(negedge ACLK);
            S_AXI_AWADDR  = addr;
            S_AXI_AWVALID = 1'b1;
            S_AXI_WDATA   = data;
            S_AXI_WSTRB   = strobe;
            S_AXI_WVALID  = 1'b1;
            S_AXI_BREADY  = 1'b1;
            fork
                begin
                    @(posedge ACLK);
                    while (S_AXI_AWREADY !== 1'b1) @(posedge ACLK);
                    @(negedge ACLK);
                    S_AXI_AWVALID = 1'b0;
                end
                begin
                    @(posedge ACLK);
                    while (S_AXI_WREADY !== 1'b1) @(posedge ACLK);
                    @(negedge ACLK);
                    S_AXI_WVALID = 1'b0;
                end
            join
            @(posedge ACLK);
            while (S_AXI_BVALID !== 1'b1) @(posedge ACLK);
            if (S_AXI_BRESP !== 2'b00) begin
                fails = fails + 1;
                $display("[FAIL] AXI write BRESP at 0x%04h = %b", addr, S_AXI_BRESP);
            end
            @(negedge ACLK);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    task axi_read;
        input  [15:0] addr;
        output [31:0] data;
        begin
            @(negedge ACLK);
            S_AXI_ARADDR = addr;
            S_AXI_ARVALID = 1'b1;
            S_AXI_RREADY = 1'b1;
            @(posedge ACLK);
            while (S_AXI_ARREADY !== 1'b1) @(posedge ACLK);
            @(negedge ACLK);
            S_AXI_ARVALID = 1'b0;
            @(posedge ACLK);
            while (S_AXI_RVALID !== 1'b1) @(posedge ACLK);
            data = S_AXI_RDATA;
            if (S_AXI_RRESP !== 2'b00) begin
                fails = fails + 1;
                $display("[FAIL] AXI read RRESP at 0x%04h = %b", addr, S_AXI_RRESP);
            end
            @(negedge ACLK);
            S_AXI_RREADY = 1'b0;
        end
    endtask

    task wait_direct_done;
        input [15:0] base;
        output [31:0] final_status;
        integer attempts;
        reg [31:0] tmp;
        begin
            attempts = 0;
            tmp = 0;
            while (tmp[1] !== 1'b1 && attempts < 1000) begin
                axi_read(base + 16'h000C, tmp);
                attempts = attempts + 1;
            end
            final_status = tmp;
            checks = checks + 1;
            if (tmp[1] !== 1'b1) begin
                fails = fails + 1;
                $display("[FAIL] direct_done timeout base=0x%04h, status=0x%08h", base, tmp);
            end else
                $display("[PASS] direct_done base=0x%04h after %0d AXI reads", base, attempts);
        end
    endtask

    task test_direct;
        input integer channel;
        input [6:0] slave_addr;
        input [7:0] reg_addr;
        input [7:0] wr_byte;
        input is_read;
        reg [15:0] base;
        reg [31:0] tmp;
        reg [31:0] irq_mask;
        integer before_addr;
        integer before_nack;
        integer before_starts;
        begin
            base = 16'h0100 + (channel * 16'h0100);
            irq_mask = 32'h1 << channel;
            if (channel < 2) begin
                tx_01 = channel;
                before_addr = address_count_01;
                before_nack = nack_count_01;
                before_starts = start_count_01;
            end else begin
                tx_23 = channel;
                before_addr = address_count_23;
                before_nack = nack_count_23;
                before_starts = start_count_23;
            end

            $display("\n---- Master I2C%0d -> passive input I2C%0d, direct_%s ----",
                     channel, (channel ^ 1), is_read ? "READ " : "WRITE");
            axi_write(base + 16'h0000, {16'd6, 9'd0, slave_addr}, 4'hF);
            axi_write(base + 16'h0008, {16'd0, wr_byte, reg_addr}, 4'hF);
            axi_read(base + 16'h0008, tmp);
            check_equal(tmp, {16'd0, wr_byte, reg_addr}, "direct configuration readback");

            // CONTROL: bit1 direct_start, bit2 R/W. auto_enable remains 0.
            axi_write(base + 16'h0004, is_read ? 32'h0000_0006 : 32'h0000_0002, 4'h1);
            wait_direct_done(base, status);
            check_equal({31'd0, status[2]}, 32'h1, "NACK propagates to direct_ack_error");
            axi_read(16'h000C, tmp);
            check_equal(tmp & irq_mask, irq_mask, "direct completion raises global IRQ");

            if (channel < 2) begin
                checks = checks + 1;
                if (start_count_01 <= before_starts || address_count_01 <= before_addr ||
                    addr_byte_01 !== {slave_addr, 1'b0}) begin
                    fails = fails + 1;
                    $display("[FAIL] passive RX I2C%0d: START/address mismatch got=0x%02h expected=0x%02h",
                             channel ^ 1, addr_byte_01, {slave_addr, 1'b0});
                end else
                    $display("[PASS] passive RX I2C%0d saw 0x%02h (7-bit addr 0x%02h + W)",
                             channel ^ 1, addr_byte_01, slave_addr);
                checks = checks + 1;
                if (nack_count_01 <= before_nack) begin
                    fails = fails + 1;
                    $display("[FAIL] no NACK detected on I2C01 bus");
                end else
                    $display("[PASS] NACK observed on shared 01 bus, no fake ACK driver");
            end else begin
                checks = checks + 1;
                if (start_count_23 <= before_starts || address_count_23 <= before_addr ||
                    addr_byte_23 !== {slave_addr, 1'b0}) begin
                    fails = fails + 1;
                    $display("[FAIL] passive RX I2C%0d: START/address mismatch got=0x%02h expected=0x%02h",
                             channel ^ 1, addr_byte_23, {slave_addr, 1'b0});
                end else
                    $display("[PASS] passive RX I2C%0d saw 0x%02h (7-bit addr 0x%02h + W)",
                             channel ^ 1, addr_byte_23, slave_addr);
                checks = checks + 1;
                if (nack_count_23 <= before_nack) begin
                    fails = fails + 1;
                    $display("[FAIL] no NACK detected on I2C23 bus");
                end else
                    $display("[PASS] NACK observed on shared 23 bus, no fake ACK driver");
            end

            // CONTROL bit4: IRQ clear. Does not trigger another direct start.
            axi_write(base + 16'h0004, 32'h0000_0010, 4'h1);
            axi_read(16'h000C, tmp);
            check_equal(tmp & irq_mask, 32'd0, "global IRQ clear");
        end
    endtask

    task test_poll_nack;
        reg [31:0] tmp;
        integer cnt0;
        integer j;
        begin
            $display("\n---- AUTO POLLING without any ACK-capable device ----");
            tx_01 = 0;
            // use I2C0; the other master port sees bits but does not reply.
            axi_write(16'h0140, 32'h0000_0020, 4'h1);
            axi_read(16'h0140, tmp);
            check_equal(tmp, 32'h0000_0020, "poll_reg_addr0 programming");
            axi_write(16'h0100, {16'd3, 9'd0, 7'h37}, 4'hF);
            cnt0 = address_count_01;
            axi_write(16'h0104, 32'h0000_0001, 4'h1); // auto_enable=1
            j = 0;
            while ((address_count_01 <= cnt0) && j < 1500) begin
                @(posedge ACLK);
                j = j + 1;
            end
            checks = checks + 1;
            if (address_count_01 <= cnt0) begin
                fails = fails + 1;
                $display("[FAIL] no polling I2C address activity detected");
            end else
                $display("[PASS] auto polling started (passive input captured I2C address)");
            axi_read(16'h010C, tmp);
            check_equal({31'd0, tmp[3]}, 32'd0, "no auto_valid without actual responder");
            // Disable auto before further testing. In-flight transaction may finish.
            axi_write(16'h0104, 32'h0000_0000, 4'h1);
            repeat (60) @(posedge ACLK);
        end
    endtask

    initial begin
        ACLK = 1'b0;
        ARESETn = 1'b0;
        S_AXI_AWADDR = 0;
        S_AXI_AWVALID = 0;
        S_AXI_WDATA = 0;
        S_AXI_WSTRB = 0;
        S_AXI_WVALID = 0;
        S_AXI_BREADY = 0;
        S_AXI_ARADDR = 0;
        S_AXI_ARVALID = 0;
        S_AXI_RREADY = 0;
        checks = 0;
        fails = 0;
        tx_01 = 0;
        tx_23 = 2;
        active_01 = 0;
        shift_01 = 0;
        addr_byte_01 = 0;
        bit_count_01 = 0;
        byte_count_01 = 0;
        address_count_01 = 0;
        start_count_01 = 0;
        stop_count_01 = 0;
        nack_count_01 = 0;
        active_23 = 0;
        shift_23 = 0;
        addr_byte_23 = 0;
        bit_count_23 = 0;
        byte_count_23 = 0;
        address_count_23 = 0;
        start_count_23 = 0;
        stop_count_23 = 0;
        nack_count_23 = 0;

        $dumpfile("tb_axil_i2c4_loopback.vcd");
        $dumpvars(0, tb_axil_i2c4_loopback);
        $display("=== AXI-Lite + four master-only I2C ports: passive cross-port loopback ===");
        repeat (8) @(negedge ACLK);
        ARESETn = 1'b1;
        repeat (5) @(negedge ACLK);

        axi_read(16'h0000, readback);
        check_equal(readback, 32'h4932_4334, "global ID register");
        axi_read(16'h0004, readback);
        check_equal(readback, 32'h0002_0000, "global VERSION register");
        axi_read(16'h0008, readback);
        check_equal(readback, 32'h0000_0000, "auto enable reset");
        axi_read(16'h000C, readback);
        check_equal(readback, 32'h0000_0000, "IRQ reset");

        // AXI byte-strobe and independent register banks (does not use I2C ACK).
        axi_write(16'h0200, 32'h1234_0055, 4'h0);
        axi_read(16'h0200, readback);
        check_equal(readback, {16'd1000, 9'd0, 7'h51}, "WSTRB=0 leaves bank1 config unchanged");
        axi_write(16'h0248, 32'h0000_007E, 4'h1);
        axi_read(16'h0248, readback);
        check_equal(readback, 32'h0000_007E, "bank1 polling register write/read");
        axi_read(16'h0148, readback);
        check_equal(readback, 32'h0000_0002, "bank0 unaffected by bank1 write");

        // The sender is real DUT controller; receiver is only a passive sampler
        // reading the physically connected *other* DUT channel input pins.
        test_direct(0, 7'h2A, 8'h12, 8'hA5, 1'b0);
        test_direct(1, 7'h35, 8'h22, 8'h5A, 1'b0);
        test_direct(2, 7'h46, 8'h31, 8'hC3, 1'b0);
        test_direct(3, 7'h52, 8'h40, 8'h3C, 1'b0);

        // A master read also starts with a write-address cycle. Without a slave
        // there is NO valid incoming payload; check only address and NACK.
        test_direct(0, 7'h2C, 8'h11, 8'h00, 1'b1);
        test_poll_nack;

        $display("\n==================== RESULT ====================");
        $display("Checks=%0d, Failures=%0d", checks, fails);
        $display("Bus 01: START=%0d STOP=%0d ADDR=%0d NACK=%0d",
                 start_count_01, stop_count_01, address_count_01, nack_count_01);
        $display("Bus 23: START=%0d STOP=%0d ADDR=%0d NACK=%0d",
                 start_count_23, stop_count_23, address_count_23, nack_count_23);
        if (fails == 0)
            $display("TB PASS: address transmission / passive capture / AXI / NACK checks.");
        else
            $display("TB FAIL: some requested behaviors differ from expectations.");
        $display("NOTE: no slave present; ACK-success, data receive and read payload NOT verified.");
        $finish;
    end

    // Independent global timeout so a stalled DUT or AXI interface terminates.
    initial begin
        #1000000;
        $display("[TIMEOUT] testbench did not complete by 1 ms");
        $finish;
    end
endmodule
