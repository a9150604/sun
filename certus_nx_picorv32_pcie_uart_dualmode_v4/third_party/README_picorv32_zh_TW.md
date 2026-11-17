# 模擬使用的 PicoRV32 固定版本

這份 `picorv32.v` 是本專案 UART／CLI 整合模擬實際使用的官方核心原檔，逐 byte 複製，沒有改寫核心邏輯或預設參數。來源與檔頭的 ISC 授權聲明一併保留；上游授權全文另附於 `COPYING.picorv32`。

## 來源與校驗

- 上游：https://github.com/YosysHQ/picorv32
- 上游 commit：`ef203c2b0a3fb793280f5114941416c425c5b461`
- 原檔：https://github.com/YosysHQ/picorv32/blob/ef203c2b0a3fb793280f5114941416c425c5b461/picorv32.v
- 檔案大小：94,657 bytes。
- Git blob SHA-1：`cc45fa998f1857b06a856ea59b931f6c37e06b34`
- SHA-256：`0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622`

Windows 可用 PowerShell 核對：

```powershell
Get-FileHash .\picorv32.v -Algorithm SHA256
```

## 在 Radiant 中使用

1. 從本目錄下載 `picorv32.v`。
2. 在工程的 active source list 中移除原本那份 `picorv32.v`，再加入本檔，確保只有一份定義同名核心模組的檔案。
3. Top Module 保持目前使用的專案 Top，例如 `certus_nx_picorv32_uart_cpu_diag_top` 或 `certus_nx_picorv32_uart_standalone_top`；不要把 Top 改成 `picorv32`。
4. 保留目前的 RXTRACE HEX、時鐘與腳位設定，先單獨比較核心檔案的差異。
5. 清理舊的實作輸出，重新執行合成、布局繞線及 bitstream 產生，再燒錄測試。

這份檔案的相關預設值如下；專案 wrapper 未覆寫它們：

| 參數 | 值 |
| --- | --- |
| `ENABLE_REGS_16_31` | `1` |
| `ENABLE_REGS_DUALPORT` | `1` |
| `LATCHED_MEM_RDATA` | `0` |
| `TWO_CYCLE_ALU` | `0` |
| `TWO_CYCLE_COMPARE` | `0` |

專案的 CPU wrapper 另外設定 `ENABLE_IRQ=0`、`ENABLE_MUL=1`、`ENABLE_DIV=1`、`COMPRESSED_ISA=0`、`PROGADDR_RESET=0`，以及 `STACKADDR=RAM_WORDS*4`；預設 RAM 為 32 KiB。

## 已執行的整合模擬

`fw/cli_rewrite_v1/tests/run_rxtrace_rtl.py` 搭配官方核心執行 `firmware/osfp_cli_rewrite_v1_rxtrace.hex`：從 UART RX 輸入 A，CPU 讀到 `RAW=00000041 C=00000041`，UART TX 在 Enter 前回顯 A；再輸入 CR 時 `L=01`，顯示未知命令訊息並重新出現 `osfp> `。

這是 RTL 模擬通過的版本；提供此檔供板上對照，尚未證明替換核心能解決目前實板上的異常。
