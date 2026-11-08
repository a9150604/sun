# LFD2NX-65-9BG484C GPIO/UART 操作手冊

## 電氣接線

| FPGA 開發板 | USB-to-UART (TTL/CMOS compatible) |
|---|---|
| UART TX | RXD |
| UART RX | TXD |
| GND | GND |

- 確認 FPGA UART bank IO 電壓與 USB-to-UART 相容；**不可**直接接正負高壓 RS-232。
- UART 和四個 OSFP I2C 完全獨立，**不占用**原本 4x SCL + 4x SDA。
- 四條 I2C 皆為 open-drain，需要適當的上拉；請依實際 OSFP 管腳電壓、線長
  及電容設計。OSFP 供電/Reset/Low Power Mode 等並非這八條 I2C 自動管理。
- 125 MHz 時脈與 LED I/O Pin 編號取決於開發板原理圖，**沒有提供虛構的 PDC**。
- Tera Term / PuTTY：115200, 8N1, no flow control；用 CR/LF 傳送命令。

## 檔案與選擇模式

初次測試 Top：`certus_nx_picorv32_uart_standalone_top.sv`。
整合 PCIe Top：例化 `pcie_i2c4_top_cpu_fabric.sv`（詳 `CONNECT_TO_EXISTING_PCIE_TOP.md`）。

對應 Firmware：

- `firmware/interactive.hex`：上電後進入 UART CLI。
- `firmware/auto_direct_read.hex`：設定延遲後自動 Direct Read。
- `firmware/auto_direct_write.hex`：設定延遲後自動 Direct Write；**預設不寫**。
- `firmware/auto_poll_read.hex`：設定延遲後自動 Poll Read。

將**所選** firmware hex 複製成 Radiant/RTL 參數 `FIRMWARE_HEX` 引用的
`firmware.hex`；確認 Project 內的 .hex 檔能被 `$readmemh` 找到，再完成
Synthesis → Map → PAR → bitstream。**更改韌體後需要重做 FPGA bitstream**。

## UART 互動模式操作示範

```
help
status
mode cpu
id
ch 0
dev 0x50
reg 0x00
read
read 0x01
pollset 0 0x00
pollset 1 0x01
pollgap 0x03E8
poll
mode pcie
mode cpu
```

命令使用 HEX 數字（`ch 0` 及 `ch 3` 仍有效）；`delay` 使用十進位 ms。

對經**原廠確認安全可寫、可讀回、沒有副作用**的 byte register，才可執行：

```
mode cpu
ch 0
dev 0x50
reg 0x90
data 0x55
unlock
writeverify
lock
```

`0x90` 與 `0x55` **只是示範命令，不表示 OSFP 的 0x90 保證可安全寫入**。
**Write 不允許對 0x7E/0x7F (CMIS bank/page) 做任意單 byte 寫入**。
對多 Byte 的 page/bank 操作、W1C、reset、control、volatile 欄位禁止盲測。

`mode pcie` 只改變 FPGA AXI-Lite Slave 控制權，不會改變 PCIe
Host Driver 本身的配置。切換前需要讓 Host Driver quiesce，並避免中途交易。
CPU 在 PCIe 模式仍執行 UART CLI，但對 I2C Slave 的讀寫會回錯誤/拒絕。

## 無 UART 輸入的自動測試

修改 `fw/config/direct_read_config.h`、`direct_write_config.h`、
`poll_read_config.h` 內的 `TEST_CH`, `TEST_DEV_ADDR`, `TEST_REG_ADDR`,
`TEST_WRITE_DATA`, `POLL_ADDR0..7`, `START_DELAY_MS`、
`RETURN_TO_PCIE_AFTER_TEST` 等參數，執行
`scripts/build_all_windows.bat`，重新產生 HEX、重新做 bitstream。

預設 `START_DELAY_MS=3000` 表示 CPU reset 解除後約 3 秒開始測試（依設定的
`CLK_HZ` 正確性）；不保證 OSFP 在 3 秒內已上電準備好，需要依模組規格調整。

## LED (假設 8 顆、high-active；active-low 則 Top 反相)

| LED | 意義 |
|---|---|
| LED0 | CPU 活動 heartbeat，持續閃爍 |
| LED1 | TEST RUNNING |
| LED2 | TEST DONE，測試有跑完（**不代表 PASS**）|
| LED3 | PASS |
| LED4 | FAIL |
| LED5 | I2C NACK |
| LED6 | Timeout |
| LED7 | CPU trap |

Write test 未授權時 LED2 DONE 亮，但沒有 PASS/FAIL；請查看 Firmware
及 Reveal，勿以 DONE 誤判 PASS。

## Reveal 小資源建議

第一階段只 probe `u_cpu_i2c_fabric.dbg_event[31:0]` + `dbg_pulse` (33 bits)，
不必直接抓 SCL/SDA、四組 I2C FSM 或 CPU 全套 AXI-Lite。Trigger 用
`dbg_pulse` 的高準位/上升沿，單組 Reveal、16～32 depth 開始。
`dbg_event[31]`=VALID；`[30]`=PASS；`[29:28]`=kind (Read=0, Write=1, Poll=2,
Error=3)；`[27:26]`=channel；`[25:18]`=register address；`[17:10]`=
expected / write data；`[9:2]`=actual / read data；`[1:0]`=rc 的低兩位。
可額外 probe `dbg_aux[31:0]`：`[31:24]`=I2C slave address；
`[23:16]`=poll slot；`[15:0]`=status/restore flag。

重要：這是**Firmware 觀察 AXI register 後鎖存的摘要**，不是 OSFP
實體匯流排的獨立證據。Auto Poll 的 shadow valid 是 sticky，沒有每個
slot 的 per-slot ACK flag，因此即使整體 PASS 也不能推論所有 OSFP
slot 都 ACK 且資料新鮮。若需位元精確檢驗，應配合 I2C 主機
內部完成時事件或外部 I2C analyzer 與 Golden Data 比較。

Timing 策略：Reveal 只觀察寄存器輸出；不以 Reveal 改變 I2C
FSM 或 AXI READY。先保留不含 Reveal 的時序報告作 baseline；加上
Reveal 後比較 WNS/TNS，若有 regression 查看真正的路由/扇出。

## 目前驗證層級

- C source 已編譯成 RV32IM ELF、BIN 與 HEX，檔案可重建。
- **沒有**聲稱在實際 Lattice Radiant 2025.2.1 / QuestaSim 或開發板
  綜合、P&R、Timing Closure 與 UART/I2C 功能驗證通過。
- 官方 PicoRV32 RTL、Radiant 生成的 PCIe Hard IP、正確的 board PDC、
  OSFP vendor register map 均需依你的真實工程補齊。

### 獨立測試後可選擇交還 PCIe

`RETURN_TO_PCIE_AFTER_TEST=1` 時，CPU 完成測試後會寫入 owner request=PCIe。
**這不代表 Host Driver 已安全同步、已收到通知、或 PCIe link 已可收發**；
實際 PCIe Driver 須自行確保 Host 側沒有未完成 transaction，並建立同步方式。
若只是 standalone 開發板測試，請保持 `0`，不必切換。
