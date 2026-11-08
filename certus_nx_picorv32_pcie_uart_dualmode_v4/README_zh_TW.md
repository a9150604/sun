# Certus-NX PicoRV32 + PCIe/CPU AXI-Lite + UART TX/RX + OSFP test (v4)

本套件以你提供/先前已建立的四個 I2C 檔案為基礎：

- `rtl/user_design/i2c4_pkg.sv`
- `rtl/user_design/i2c_master_byte.sv`
- `rtl/user_design/i2c_device_ctrl.sv`
- `rtl/user_design/axil_i2c4_regs.sv`

## 新增部分

- `rtl/soc/picorv32_cpu_axil_uart.v`：PicoRV32、32 KiB firmware RAM、UART TX/RX、LED、debug events
- `rtl/soc/native_to_axil_master.v`：CPU native memory → AXI4-Lite master bridge
- `rtl/soc/axil_master_mode_mux.sv` + `axil_owner_switch.v`：PCIe / CPU mode selection
- `rtl/soc/uart_tx_mmio.v` + `uart_rx_byte.v`：8N1 serial TX/RX
- `rtl/soc/pcie_i2c4_top_cpu_fabric.sv`：共用 AXI-Lite Slave 與四個 I2C Master
- `rtl/soc/certus_nx_picorv32_uart_standalone_top.sv`：無 PCIe 的初始板級測試 Top
- `fw/interactive_main.c`：UART 命令列
- `fw/auto_direct_read.c`, `auto_direct_write.c`, `auto_poll_read.c`：獨立測試映像
- `fw/config/*.h`：通道、device addr、register、固定開始延遲等編譯選項
- `firmware/*.hex`：對應 4 種測試的初始化檔
- `scripts/build_all_windows.bat`：Windows RISC-V GCC 重新產生 HEX

**請先讀**：`docs/BOARD_UART_AND_TEST_GUIDE_zh_TW.md`，再讀
`docs/CONNECT_TO_EXISTING_PCIE_TOP.md`。

## 注意

1. 官方 `picorv32.v` **未打包**。請由 https://github.com/YosysHQ/picorv32
   取得官方 `picorv32.v`，放到 `third_party/picorv32.v`。
2. 你的原 `pcie_i2c4_top.sv` 沒有完整 PCIe IP generated wrapper，
   需按實際 IP port 把 `pcie_i2c4_top_cpu_fabric` 接入。未宣稱可直接
   取代原 Top 即 compile。
3. 預設 AXI 同步 clock 125 MHz、UART 115200、四條獨立 I2C，
   OSFP slave addr 的預設 0x50 在 Firmware 內設定。
4. Direct Write 只在 UART `unlock` 後可用；Auto Write Firmware
   在 `ENABLE_WRITE_TEST=0` 時預設停用。
5. I2C Master 為單 byte direct operation，CMIS 跨 page/bank 及
   multi-byte atomic 操作未完整支援。
6. 本套件尚未經開發板、Radiant 或 QuestaSim 測試認證。
