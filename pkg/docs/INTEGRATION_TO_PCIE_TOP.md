# 將 RISC-V 子系統接到既有 pcie_i2c4_top.sv（實體 PCIe IP）

## 正確的位置

```
PCIE Gen2 x1 Endpoint IP ----------------------+
(host AXI4-Lite manager m0_axil_*)             |
                                               v
PicoRV32 -- native->AXI-Lite ------------- CPU/HOST 靜態模式 MUX
                                               |
                                               v
                                        axil_i2c4_regs
                                               |
                                     I2C0..3 → QSFP0..3
PicoRV32 → UART TX → PC terminal
I2C IRQ[3:0] → MSI source controller → IP usr_int_req_i[0]
```

此套件 `pcie_i2c4_top_cpu_fabric.sv` 已含 CPU、UART、MSI source、mux 與原本的 axil_i2c4_regs。
**原本的 `pcie_i2c4_top.sv` 請保持 PCIe PHY/refclk/reset/pin 等設計不變。** 在原 top 中移除舊的 `u_axil_i2c4_regs` instance，將原 PCIe IP 的 AXI-Lite Manager 改接此 fabric 的 `host_*`。不要在兩個地方重複 instance `axil_i2c4_regs`。

## 概念範例（真正連線請以 Radiant 產生的 PCIe wrapper 為準）

```systemverilog
wire [15:0] host_awaddr,host_araddr;
wire host_awvalid,host_awready,host_wvalid,host_wready;
wire host_bvalid,host_bready,host_arvalid,host_arready;
wire host_rvalid,host_rready;
wire [31:0] host_wdata,host_rdata;
wire [3:0] host_wstrb;
wire [1:0] host_bresp,host_rresp;
wire usr_int_req,usr_int_ack;

// Existing Radiant PCIE IP: adjust its port names & widths to actual IP.
// .m0_axil_awaddr_o(host_awaddr), .m0_axil_awvalid_o(host_awvalid),
// .m0_axil_awready_i(host_awready), .m0_axil_wdata_o(host_wdata),
// .m0_axil_wstrb_o(host_wstrb), .m0_axil_wvalid_o(host_wvalid),
// .m0_axil_wready_i(host_wready), .m0_axil_bresp_i(host_bresp),
// .m0_axil_bvalid_i(host_bvalid), .m0_axil_bready_o(host_bready),
// .m0_axil_araddr_o(host_araddr), .m0_axil_arvalid_o(host_arvalid),
// .m0_axil_arready_i(host_arready), .m0_axil_rdata_i(host_rdata),
// .m0_axil_rresp_i(host_rresp), .m0_axil_rvalid_i(host_rvalid),
// .m0_axil_rready_o(host_rready),
// .usr_int_req_i(usr_int_req), .usr_int_ack_o(usr_int_ack)

pcie_i2c4_top_cpu_fabric #(
 .CLK_HZ(50000000),.BAUD(115200),.CLK_DIV(250),
 .FIRMWARE_HEX("firmware.hex"),.MSI_ACK_LOOPBACK(0)
) u_cpu_i2c_fabric (
 .clk(axil_clk),.resetn(axil_rst_n),
 .cpu_mode_select(cpu_mode_sw),
 .buttons(buttons),.switches(switches),
 .leds(leds),.uart_tx(uart_tx),.cpu_trap(cpu_trap),
 .i2c_scl(i2c_scl),.i2c_sda(i2c_sda),
 .dev_irq(dev_irq),
 .usr_int_req(usr_int_req),.usr_int_ack(usr_int_ack),
 .host_msi_enable(host_msi_arm),
 .host_awaddr(host_awaddr),.host_awvalid(host_awvalid),.host_awready(host_awready),
 .host_wdata(host_wdata),.host_wstrb(host_wstrb),
 .host_wvalid(host_wvalid),.host_wready(host_wready),
 .host_bresp(host_bresp),.host_bvalid(host_bvalid),.host_bready(host_bready),
 .host_araddr(host_araddr),.host_arvalid(host_arvalid),.host_arready(host_arready),
 .host_rdata(host_rdata),.host_rresp(host_rresp),
 .host_rvalid(host_rvalid),.host_rready(host_rready)
);
```

### Clock / Reset

- `axil_clk` 必須是 PCIe Bridge AXI-Lite 的合法 clock domain。請勿未經檢查將 PCIe user clock `link0_clk_usr_o` 當成另一個 clock domain，或直接假設 `sys_clk` 與它相同。
- 此 MUX **沒有 Clock Domain Crossing**。Host AXI-Lite、CPU、I2C register slave 必須在同一 clock domain；若不同，需要另外的 AXI clock converter。
- `cpu_mode_sw` 必須在 reset 期間固定，按 reset 之後才可變更 mode；此 MUX **不是可同時工作的 2-master 仲裁器**。
- CPU_MODE=1 時，PCIe AXI-Lite Master 暫停（不能同時驅動 Slave）；CPU_MODE=0 時 CPU held in reset，PCIe正常存取。要真正兩邊並行需要另外設計 fair 2-master AXI arbitration。

### MSI

- `MSI_ACK_LOOPBACK=0` 必須用於實際 PCIe。
- `usr_int_req` 與 `usr_int_ack` 必須與實際生成的 MSI user interrupt interface 對應，通常是 `[0]`。
- 目前 `host_msi_enable` 必須由 Host 端完成 MSI 申請/初始化之後控制。這份套件**沒有新增 Host 可寫的 MSI_ARM CSR**；未實作時不要誤接到永遠 1。先可接 0 並只測 CPU MODE 的 source/MSI loopback；日後增設 ARM CSR。
- CPU firmware 的預設 TC9 **只有在 MSI_ACK_LOOPBACK=1 的 standalone mode 才有效**。接實際 PCIe 時需把 C 巨集 `ENABLE_MSI_LOOPBACK_TEST` 設成 0 並重建韌體，否則在 Host 沒有 ACK 時它會回報 FAIL。

### PCIe address vs CPU address

- CPU `0x4000_0100` → AXI-Lite low 16-bit offset `0x0100`。
- 原本 PCIe BFM `64'h0000_0000_81FE_0100` → BAR decode 後 AXI-Lite offset `0x0100`。
- **不應在 CPU C code 使用 PCIe BFM 0x81FE0000 位址。**

### Source version

`rtl/user_design/` 是從先前專案 ZIP 取出的 snapshot；如果你當前工作中的 RTL 已修改，請以實際最新 RTL 取代此 snapshot，尤其確認所有 PORT、控制暫存器與 clocks。
