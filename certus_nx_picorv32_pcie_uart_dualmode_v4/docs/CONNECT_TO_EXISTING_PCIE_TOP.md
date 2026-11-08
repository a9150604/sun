# 將 CPU Fabric 接回 pcie_i2c4_top.sv（重要：請按實際 IP Wrapper 接線）

**本文件不是已整合實際 PCIe Hard IP 的完整 Top**。目前可取得的舊版
`pcie_i2c4_top.sv` 只是 PCIe IP 的介面範本，沒有原廠生成的 PCIe IP instance。
因此無法驗證/取代你開發板專案中的真實 IP 訊號名稱與重置流程。

## 變更原則

1. 保留既有 PCIe IP Instance、PCIe Refclk、PERST#、RX/TX 與 PCIe MSI 信號。
2. 刪除原本 Top 中**直接**連到 PCIe AXI-Lite Master 的 `axil_i2c4_regs` Instance
   （**避免重複實例化**）。
3. 改為實例化 `pcie_i2c4_top_cpu_fabric`，此模組內部**已**包含
   `axil_i2c4_regs`、4 個 I2C Controller、PicoRV32、UART TX/RX、AXI mux。
4. 新增頂層 I/O：`uart_rx`, `uart_tx`, `leds[7:0]`。
5. 將 PCIe AXI-Lite Master 的 AW/W/B/AR/R channel 一對一接到 Fabric 的
   `host_*` pins：

| PCIe 端訊號例名 | Fabric Port |
|---|---|
| m_axi_awaddr[15:0] | host_awaddr |
| m_axi_awvalid / awready | host_awvalid / host_awready |
| m_axi_wdata[31:0], wstrb[3:0] | host_wdata, host_wstrb |
| m_axi_wvalid / wready | host_wvalid / host_wready |
| m_axi_bresp[1:0], bvalid, bready | host_bresp, host_bvalid, host_bready |
| m_axi_araddr[15:0], arvalid, arready | host_araddr, host_arvalid, host_arready |
| m_axi_rdata[31:0], rresp[1:0], rvalid, rready | host_rdata, host_rresp, host_rvalid, host_rready |

6. I2C port `i2c_scl[3:0]`/`i2c_sda[3:0]` 仍輸出為 open-drain。
   CPU Fabric 已自帶 I/O tri-state，原 Top 不要再次驅動這八條線。
7. **必須**讓 PCIe AXI-Lite Master、PicoRV32 與 AXI Slave 都使用相同 ACLK
   或在中間加正確的 AXI Clock Domain Crossing。`clk`、`resetn` 必須是
   與 PCIe AXI Master 同 clock domain 的時脈與同步釋放的 reset。
   PCIe PERST# 不一定可直接當成 CPU System Reset；需要依 IP Clock/Reset Guide 設計。
8. 若原 Top 的 AXI 地址寬是 32-bit，請確認高位的合法映射，再擷取 [15:0]
   送入此 16-bit Slave；PCIe BAR base 不應被重新編入 CPU 0x4000_0000。
9. **MSI 並未在本版自動接到 PCIe IP 的 MSI requester**。`dev_irq` 保持輸出，
   使用你既有的 MSI/ACK controller 連接真實 PCIe IP，勿把 dev_irq 直接當 MSI req。

## 最小 CPU Fabric 例化片段

```systemverilog
wire [7:0] board_led_raw;
wire cpu_owner, cpu_trap;
wire [31:0] dbg_event, dbg_aux;
wire dbg_toggle, dbg_pulse;
wire [3:0] dev_irq;
pcie_i2c4_top_cpu_fabric #(
  .CLK_HZ(125000000), .BAUD(115200), .CLK_DIV(312),
  .INITIAL_CPU_OWNER(1), .FIRMWARE_HEX("firmware.hex")
) u_cpu_i2c_fabric (
  .clk(axil_clk),.resetn(axil_rst_n),
  .uart_rx(uart_rx),.uart_tx(uart_tx),.leds(board_led_raw),
  .cpu_trap(cpu_trap),.cpu_owner(cpu_owner),
  .dbg_event(dbg_event),.dbg_aux(dbg_aux),
  .dbg_toggle(dbg_toggle),.dbg_pulse(dbg_pulse),
  .i2c_scl(i2c_scl),.i2c_sda(i2c_sda),.dev_irq(dev_irq),
  .host_awaddr(m_axi_awaddr),.host_awvalid(m_axi_awvalid),.host_awready(m_axi_awready),
  .host_wdata(m_axi_wdata),.host_wstrb(m_axi_wstrb),
  .host_wvalid(m_axi_wvalid),.host_wready(m_axi_wready),
  .host_bresp(m_axi_bresp),.host_bvalid(m_axi_bvalid),.host_bready(m_axi_bready),
  .host_araddr(m_axi_araddr),.host_arvalid(m_axi_arvalid),.host_arready(m_axi_arready),
  .host_rdata(m_axi_rdata),.host_rresp(m_axi_rresp),
  .host_rvalid(m_axi_rvalid),.host_rready(m_axi_rready)
);
assign leds = board_led_raw; // 如果板上 LED active-low，請改為 ~board_led_raw
```

上述假設與舊版使用相同名稱的 AXI-Lite 訊號；需要對照 IP-generated wrapper
修正，不能直接視為已完成實板整合。

## AXI owner 切換限制

CPU 管理 owner request，硬體只在沒有尚未完成的 AW/W/B、AR/R transaction
時才切換。尚未涵蓋 host driver、PCIe link reset、DMA、IP 特定交易撤銷等協定。
切到 PCIe 模式之前，OSFP auto polling 也應由 CPU 明確停用；Host driver 必須
在開始發新的 AXI command 前依正確方法同步 owner 狀態。

> **不能在 Host 發出任何 AXI-Lite 未完成交易時切換 owner。** 切換不是 PCIe
> 系統層級的 hot-swap。模式下鎖與退回應由整合設計/Host driver 負責。
