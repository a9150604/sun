# 建置與驗證紀錄

- 已用 Clang 17 / lld 產生 RV32IM `firmware.elf`、`firmware_host.elf`，並使用 llvm-objcopy/ Python 產生 `firmware.hex` 與 `firmware_host.hex`。
- firmware 大小 6,426 bytes；firmware_host 大小 5,851 bytes；均填補為 16,384 個 32-bit word（64 KiB）。
- 已確認所有本套件自有 RTL module 檔案存在、RAM HEX 格式正確。
- **未在本環境執行 HDL 編譯 / QuestaSim / Radiant Synthesis / P&R / FPGA 板測**：環境沒有 iverilog/Verilator/Questa/Radiant，且未包含第三方 upstream CPU `picorv32.v`。不能把「C 已編譯」當成「SoC 已通過硬體驗證」。
- 整合原始 PCIe IP 後，請先跑 `sim/run_bridge_questa.do`，再 `sim/run_questa.do`。留意舊版 `axil_i2c4_regs`、clock/reset、MSI 與 I/O 腳位差異。
