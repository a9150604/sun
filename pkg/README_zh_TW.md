# Certus-NX PicoRV32 + AXI4-Lite + UART TX + 四組 QSFP I2C 測試套件

**平台**：Lattice Certus-NX LFD2NX-65-9BG484C、Radiant 2025.2.1、Windows、QuestaSim Lattice Edition。

**本次已產生**：可綜合 PicoRV32 周邊子系統、原生 bus → AXI-Lite Master Bridge、UART TX、64KiB RAM、CPU/PCIe Host 靜態模式切換、MSI source controller、原本四組 I2C Slave registers、完整 Bare-metal C 測試、startup/linker/編譯腳本、預編譯 `firmware.hex`、Questa testbench、整合說明。

**仍需要**：官方原版 `picorv32.v`（避免修改或再散佈第三方 CPU RTL）、你的開發板 PDC pin map、實際 QSFP module 與板級電氣確認，以及你當前產生的 PCIe IP wrapper。**本環境已用 Clang LLVM 編譯 firmware，但是沒有 Radiant/Questa，沒有聲稱 FPGA 已編譯或板上測試通過。**

## 1. 先在開發板啟動 CPU（不需要 PCIe）

1. 解壓 package，例如 `D:\FPGA\qsfp_picorv32`。PowerShell 執行 `scripts\get_picorv32.ps1`；或從 https://github.com/YosysHQ/picorv32 下載 `picorv32.v` 到 `third_party/picorv32.v`。官方 `picorv32.v` 同時收錄 CPU、AXI adapter 等 module。
2. 在 Lattice Radiant 2025.2.1 新建你的 `LFD2NX-65-9BG484C` 專案，依 `rtl/soc/rtl_sources.f` **順序**加入檔案。先使用 Top `certus_nx_picorv32_qsfp_standalone_top`。
3. 以你開發板原理圖設定 `clk_in/reset_n/led/uart_tx/qsfp_scl/qsfp_sda` 的真實 pins 與 I/O voltage；沒有 PDC 提供是刻意避免虛構 pin。確認 QSFP MODSEL_N / RESET_N / LPMode 狀態。
4. `firmware.hex` 已預先生成，加入 Radiant 工程工作目錄並確認 synthesis 的 `$readmemh` 解析到了正確檔案。若工具不接受相對路徑，使用該工具支援的初始化檔設定，或把 hex 放到 build working directory。
5. 先用 50MHz oscillator（其他頻率同時改 CLK_HZ）、115200 8N1，並把 UART TX 以 3.3V/1.8V 相容 USB-UART adapter 接到 Windows 的 USB serial port。
6. 執行 synthesis、Map、P&R、STA、bitstream、Lattice Programmer 燒 FPGA。PC 用 PuTTY/Tera Term 選 COM、115200、8N1。
7. 重設 FPGA → UART 印 `PicoRV32 / Certus-NX / 4xQSFP BIST` → TC1..TC9 → FINAL PASS/FAIL；LED0 代表執行，LED1 PASS，LED7 FAIL。全部 QSFP 裝妥之前，TC4..8 fail 為預期。

## 2. 硬體 Memory Map

| PicoRV32 bus | Register | Description |
|---|---|---|
| 0x0000_0000–0x0000_FFFF | 64KiB RAM | code/data/stack（$readmemh 啟動） |
| 0x1000_0000 | CLK_HZ (R) | clock frequency |
| 0x1000_0004 | UART_TX_DATA (W) | 發送一字元，busy 時 CPU wait |
| 0x1000_0008 | UART_TX_READY (R) | bit0 = 1 when idle |
| 0x1000_000C | CYCLE_COUNTER (R) | 32-bit CPU sys clock timer |
| 0x1000_0010 | LED (R/W) | bit[7:0] |
| 0x1000_0014 | GPIO_IN (R) | switches[3:0] at [7:4], buttons[3:0] at [3:0] |
| 0x1000_0020 | MSI_ENABLE (R/W) | bit0 CPU MSI gate |
| 0x1000_0024 | DEV_IRQ (R) | four sticky IRQ sources |
| 0x1000_0028 | MSI_STATUS (R) | bit0 req, bit1 ack, bit[17:2] ACK count |
| 0x4000_0000–0x4000_FFFF | AXI4-Lite | AXI4-Lite Master bridge → axil_i2c4_regs |

內部 AXI offset 0x0000 ID, 0x0004 VER, 0x000C GLOBAL_IRQ；QSFP0/1/2/3 base 分別是 0x0100/0x0200/0x0300/0x0400。

## 3. 使用 C 測試

測試程式在 `fw/main.c`，以 MMIO（`volatile uint32_t`）讀寫；UART 印出 actual data 和 PASS/FAIL。外部 QSFP 不會任意寫入；軟體只改 FPGA 本地 AXI register。詳見 `docs/HARDWARE_AND_TESTS.md`。

如果要修改 FW：安裝 xPack GNU RISC-V Embedded GCC，執行 `scripts\build_firmware_windows.bat`。CPU 已開啟 RV32IM（MUL/DIV），編譯參數 `-march=rv32im -mabi=ilp32`。檔案輸出 `build/firmware.elf`、`build/firmware.bin`、根目錄 `firmware.hex`。編譯之後重新產生 bitstream，不能把 ELF 當成直接燒入 FPGA 的程式。

本 package 另附 LLVM/Clang 編譯過的 `build/firmware.elf` 與已初始化的 `firmware.hex`，可以先不裝 GCC 測試第一版。PCIe Host Mode 還有 `firmware_host.hex`（MSI loopback 測試標記 SKIP）。

## 4. QuestaSim RTL simulation

置身 package 根目錄，執行 `do sim/run_questa.do`；`tb_soc` 包含 4 顆簡易 I2C slave model（都是 address 0x50）、pull-up 與 UART monitor。Model 不等同真實 QSFP SFF-8636/CMIS，主要驗證 AXI/I2C/CPU/UART 載入與控制路徑。此機器未安裝 Questa；請在你自己的 Lattice-Edition 測試。

## 5. 整合回 PCIe Gen2 x1 Endpoint

閱讀 `docs/INTEGRATION_TO_PCIE_TOP.md`。保留實際 `pcie_i2c4_top.sv` 所 instantiate 的原始 Radiant PCIe IP，利用它的 AXI-Lite Manager (m0_axil_*) 接 `pcie_i2c4_top_cpu_fabric` 的 `host_*`。它的 `cpu_mode_select` 會在 reset 捕捉，兩個 Master **目前不能同時工作**。CPU 測試選 1，Host PCIe 存取選 0；切換要 reset。

本版 CPU 使用 **PicoRV32 native memory + synthesizable AXI-Lite Master bridge**，而不是讓 CPU 取指也從 AXI-Lite RAM slave 走；這是為了使 Block RAM boot 比較單純。CPU 對 QSFP 的讀寫仍然由真實 AXI-Lite AW/W/B/AR/R 交易完成。

## 6. MSI 測試的真實限制

Standalone top 的 `MSI_ACK_LOOPBACK=1`：只模擬 MSI request/ack，**不能證明 MSI TLP 到達 Host**。在 PCIe 版本務必設為 0，連接真實 IP `usr_int_req_i`、`usr_int_ack_o`，並由 Host driver 完成 MSI 配置；必要時使用 firmware host build，將 `ENABLE_MSI_LOOPBACK_TEST` 改為 0，避免沒有 ACK 時 false fail。

## 7. Package 非保證可直接綜合到你現有 top

`rtl/user_design` 是你之前提供的設計 snapshot。PCIe IP instance、actual AXI clock/reset、不同 PCIe 版本 port 與你開發板 pin table 在本次對話中不可逐項核對，所以不會虛構成可直接連線的完整頂層。已提供能合成的 standalone top 與完全明確的 PCIe fabric port，讓你可安全合併到真正的 top。
