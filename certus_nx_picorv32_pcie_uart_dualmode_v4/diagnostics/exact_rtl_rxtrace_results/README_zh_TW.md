# GitHub 原始 RTL 的 RXTRACE 整合測試

本次用可直接編譯 SystemVerilog enum 的 Verilator，重新驗證專案的兩個 Top。所有 DUT RTL 逐 byte 對照 GitHub Git blob 後直接編譯；I2C 模組、UART、RAM、CPU wrapper 與 fabric 均未改寫。

## 與先前測試的差別

先前 `run_rxtrace_rtl.py` 使用 Icarus、standalone Top，最近一次執行的鮑率為 1,000,000；為了 Icarus 相容性，另外建立 I2C master 的暫存副本，將三處 enum 三元運算式改成等價 if/else。

這次新增 `run_rxtrace_exact_rtl.py` 與 `tb_rxtrace_exact.sv`，直接使用 GitHub 原始檔，並補測先前板上使用的 CPU diagnostic Top。舊測試的來源與板上工程設定並非完全一致，應以這份逐檔紀錄評估本次模擬條件。

## 固定條件與結果

- RTL 來源 commit：`365fcead5aae84356e2304541c688c7858b503ce`。
- 模擬器：Verilator 5.032；以 `--binary --timing` 編譯。
- 時鐘：125,000,000 Hz；UART：115200 baud，8N1。
- LED_ACTIVE_LOW：1。
- HEX：`firmware/osfp_cli_rewrite_v1_rxtrace.hex`。
- HEX SHA-256：`f82ebb0509444b118f8793b3f7b6b8821403df9c9cdb08faee2f7cdc3dc23697`。
- PicoRV32：專案 `third_party/picorv32.v`，Git blob `cc45fa998f1857b06a856ea59b931f6c37e06b34`。

| DUT Top | 結果 | UART 輸出／逐檔紀錄 |
| --- | --- | --- |
| `certus_nx_picorv32_uart_standalone_top` | PASS | [UART](standalone/uart_wire.log) · [模擬紀錄](standalone/simulation.log) · [檔案與參數](standalone/source_manifest.json) |
| `certus_nx_picorv32_uart_cpu_diag_top` | PASS | [UART](cpu-diag/uart_wire.log) · [模擬紀錄](cpu-diag/simulation.log) · [檔案與參數](cpu-diag/source_manifest.json) |

兩份 UART TX 腳位解碼輸出完全相同，共 270 bytes，SHA-256 為 `fe7490bc10898cefb4a5852722abbd3dae07905587baf63b446f7995f8fe7e05`。

測試平台只從 UART RX 腳位輸入 A 與 CR，從 UART TX 腳位取樣輸出。確認 A 在 Enter 前回顯，CR 對應的 RXTRACE 顯示 `L=01`，之後顯示未知命令訊息及新提示符。兩個字元皆被 CPU 讀取，trap=0、overrun=0。測試平台沒有 CPU stub、force/release、內部 RAM 寫入或 PC 修改。

## 實際編入的模組

兩個 Top 共用以下原始檔：

```text
rtl/user_design/i2c4_pkg.sv
rtl/user_design/i2c_master_byte.sv
rtl/user_design/i2c_device_ctrl.sv
rtl/user_design/axil_i2c4_regs.sv
third_party/picorv32.v
rtl/soc/native_to_axil_master.v
rtl/soc/uart_tx_mmio.v
rtl/soc/uart_rx_byte.v
rtl/soc/axil_master_mode_mux.sv
rtl/soc/axil_owner_switch.v
```

standalone 另編入：

```text
rtl/soc/picorv32_cpu_axil_uart.v
rtl/soc/pcie_i2c4_top_cpu_fabric.sv
rtl/soc/certus_nx_picorv32_uart_standalone_top.sv
```

CPU diagnostic 另編入：

```text
diagnostics/uart_cpu_trace/picorv32_cpu_axil_uart_diag.v
diagnostics/uart_cpu_trace/pcie_i2c4_top_cpu_diag_fabric.sv
diagnostics/uart_cpu_trace/certus_nx_picorv32_uart_cpu_diag_top.sv
```

每次測試各有 13 個 DUT 原始檔；額外的測試平台 `tb_rxtrace_exact.sv` 僅用於模擬。完整檔案大小、Git blob SHA-1、SHA-256、編譯命令和測試平台校驗值皆在各自的 `source_manifest.json`。

## 重跑

在 Linux／WSL 安裝支援 `--binary --timing` 的 Verilator 5 與 C++ 編譯工具後，於專案根目錄執行：

```bash
python3 fw/cli_rewrite_v1/tests/run_rxtrace_exact_rtl.py --top standalone --baud 115200
python3 fw/cli_rewrite_v1/tests/run_rxtrace_exact_rtl.py --top cpu-diag --baud 115200
```

來源會依 `fw/cli_rewrite_v1/tests/rxtrace_exact_sources.json` 逐 byte 檢查，包含檔尾換行。來源被修改或換行被轉換時會中止，避免把不同檔案的結果混在一起。輸出目錄預設為 `build/cli_rewrite_v1_rxtrace/exact/<top>/`。

## 結論的範圍

這次證明兩個 Top 的 GitHub 原始 RTL，在上列模擬條件下，能完成接收 A、回顯及 CR 時 `L=01` 的流程。目前仍未重現實板的異常。

模擬使用理想時鐘／重置、慢速逐鍵 UART 輸入與 Verilator 的兩態 RTL 模型；未使用使用者的 Radiant 工程、PDC、合成後網表或 EBR 模型。125 MHz 是本次明列的測試設定，並非重新量測板上時鐘的結果。這份結果不足以宣稱 Radiant 合成後電路或實板已通過驗證。
