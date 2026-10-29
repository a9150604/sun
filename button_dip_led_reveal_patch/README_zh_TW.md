# Certus-NX PicoRV32：4 DIP + 4 Button + 8 LED + Reveal 板上操作版

這是**修改前一版 OSFP 完整套件的 PATCH**，不是獨立全部 RTL。
基礎專案：`certus_nx_picorv32_osfp_direct_rw_poll_full_v3.zip`。

> 重要：以前的 v3 韌體「Reset 後自動跑完」，**沒有按鍵選單**。本 PATCH 才真正實作下述控制。

## 1. 版本與測試條件

- Target: Certus-NX `LFD2NX-65-9BG484C`，板卡 GPIO Clock/Reset/PDC 由使用者配對。
- 4 組獨立 OSFP SCL/SDA，共 8 GPIO，每組 OSFP 的管理 I2C 7-bit Address 為 `0x50`。
- `pcie_i2c4_top_cpu_fabric.sv` 的 `MSI_ACK_LOOPBACK=1` 是 **Standalone 測試假 ACK**，不表示 PCIe Host 有收到 MSI。
- 預設沒有對 OSFP 執行 Direct Write。寫入需要廠商確認的普通 RW bit profile、編譯時兩個授權巨集、以及下方限制。
- 不需接 UART；將 `uart_tx` 不配置/不使用即可。原 UART 邏輯可被工具按需求最佳化。
- 本 PATCH 只做了 **RV32IM C Firmware 編譯** 與檔案一致性檢查，**尚未在用戶開發板/Radiant/QuestaSim 實測**。

## 2. 需要替換哪些檔案

| PATCH | 放到舊專案 | 用途 |
|---|---|---|
| `fw/main.c` | `fw/main.c` | Button/DIP 控制 FSM（C 輪詢），Direct/Poll/Write/IRQ 測試 |
| `rtl/soc/picorv32_cpu_axil_uart.v` | `rtl/soc/picorv32_cpu_axil_uart.v` | 增加 2 個 Reveal Debug 資料暫存器及 16-bit sequence counter |
| `firmware.hex` | `firmware.hex` | 已用 clang/LLVM 編譯的 64KiB RAM 初始化影像 |
| `fw/osfp_test_config.h` | `fw/osfp_test_config.h` | 保持與上版相容，預設禁止寫 OSFP |

其他全部 RTL（`certus_nx_picorv32_qsfp_standalone_top.sv`、`pcie_i2c4_top_cpu_fabric.sv`、`axil_i2c4_regs.sv`、I2C Master 等）**保持原樣**。舊的 `picorv32_bringup_top.v` 只用於 LED startup 示範，**不支援**此版本 OSFP 功能；請選擇正確的 Standalone Top。

放好新的 `firmware.hex` 後，在 Radiant **重新跑 synthesis/map/P&R 與 bitstream 並重新燒錄**。只換磁碟上的 hex 不會修改已燒入 FPGA 的程式。

Windows 重編 C Firmware：`scripts\\build_firmware_windows.bat`，需要 `riscv-none-elf-gcc` 和 Python。或者直接使用 PATCH 預編譯的 `firmware.hex`。

## 3. 4 個 DIP Switch —— 選什麼

GPIO -> FPGA Top `switches[3:0]`。**DIP OFF/ON 電位是否為 0/1 必須以開發板實際接線為準**，表格是邏輯 0/1，不代表實際 ON/OFF 方向。

- `SW[1:0]` 選通道：`00=OSFP0`, `01=OSFP1`, `10=OSFP2`, `11=OSFP3`
- `SW[3:2]` 選測試：`00=Direct Read`, `01=Auto Polling Read`, `10=Direct Write / Readback / Restore`, `11=IRQ + Standalone MSI 握手模擬`

| SW[3:0] | 選擇 |
|---|---|
| `0000` | OSFP0 Direct Read |
| `0001` | OSFP1 Direct Read |
| `0010` | OSFP2 Direct Read |
| `0011` | OSFP3 Direct Read |
| `0100` | OSFP0 Auto Polling |
| `0101` | OSFP1 Auto Polling |
| `1000` | OSFP0 Direct Write（預設 SKIP） |
| `1100` | OSFP0 IRQ / 模擬 MSI ACK |

## 4. 4 個按鈕 —— 做什麼

| Button | 功能 | 注意 |
|---|---|---|
| BTN0 | **START**：測試目前選擇的 OSFP/模式/地址 | 測試執行期間不接受其他鍵 |
| BTN1 | **NEXT**：切換 register / polling slot | Direct Read 只在 byte `0x00, 0x01, 0x02` 循環；Polling 在 slot0..7 循環 |
| BTN2 | **DISPLAY**：LED 在「結果狀態」與「讀回 8-bit 資料」間切換 | 下次測試沿用所選顯示模式 |
| BTN3 | **CLEAR DISPLAY**：清除目前 LED 測試結果 | 不會重設 CPU 或清除硬體 IRQ |

**按鈕輸入預設低有效**。如開發板 BTN 按下變成高，請在 `fw/main.c` 把 `BUTTON_ACTIVE_LOW` 改為 0，重編 Firmware。`SWITCH_ACTIVE_LOW` 預設為 0；若 DIP 所見狀態相反，改為 1 並重新編譯。

## 5. 八顆 LED 有三種顯示狀態

### (A) 尚未執行／按 NEXT 後：顯示選擇

- LED7=1 表示**選擇畫面**，此時**不是 FAIL**。
- LED6:5=OSFP channel（兩 bit）。
- LED4:3=Test mode（兩 bit）。
- LED2:0=Register index 或 Polling Slot（3 bit）。

例：`SW=0000`、slot0 -> `LED=8'h80`；按 BTN1 一次 -> `LED=8'h81`。

### (B) 按 BTN0 後：結果顯示（按 BTN2 切回）

| LED | 意義 |
|---|---|
| LED0 | BUSY，執行中亮，完成熄滅 |
| LED1 | PASS |
| LED2 | FAIL |
| LED3 | I2C NACK（ACK error） |
| LED4 | Timeout |
| LED5 | SKIP（例如未授權 OSFP Direct Write） |
| LED6 | Read data valid / 可顯示資料 |
| LED7 | Write/Restore 無法正確還原（嚴重） |

### (C) 按 BTN2：資料顯示

八顆 LED 直接顯示 8-bit actual data：`LED7=bit7 ... LED0=bit0`。

例如讀到 byte `0x19` = `00011001b`，LED4/LED3/LED0 亮起，其餘滅。**請先在結果頁確認 PASS，再切到資料頁；0 值不代表 NACK。**

所有 LED 說明以 FPGA 輸出為**高有效**；若板上的 LED 為 low-active，請在頂層對輸出反相，不能只在 C 程式改 1/0 觀念。

## 6. 實際操作範例

### A. OSFP0 Direct Read register 0x00

1. `SW[3:0]=0000`（邏輯位準）。確認 LED 顯示選擇畫面 `0x80`。
2. 按 BTN0 一次 → PicoRV32 → AXI-Lite → I2C0 → OSFP0 讀 byte0。
3. 完成後若 PASS：LED1 及 LED6 亮；FAIL：LED2 亮，NACK 會連 LED3 亮。
4. 按 BTN2 → 看 LED7..0 的 byte 值（例如 `0x19`；僅為舉例）。
5. 按 BTN1 → index 1（OSFP byte `0x01`），再按 BTN0 讀取；再按 BTN1 → index2（byte `0x02`）。

### B. OSFP2 Auto Polling SHADOW slot3

1. `SW[3:0]=0110`（mode=01, channel=10）。
2. 按 BTN1 三次選 slot3；選擇畫面 LED2:0=011。
3. 按 BTN0，韌體先取得 8 slot direct baseline，配置 POLL_ADDR0..7，開啟 auto，等待兩輪，再停止並核對八組 SHADOW，恢復原 polling config。
4. LED1 PASS 表示八組資料符合 baseline；按 BTN2 可顯示 **slot3 實際 SHADOW byte**。

### C. OSFP1 Direct Write（預設不動真正光模組）

1. `SW[3:0]=1001`。按 BTN0 → 只會顯示 LED5 SKIP。
2. 真的要寫時，須先在 `fw/osfp_test_config.h` 設定該 channel 經廠商認證的 lower-memory 普通 RW bit、expected ID、mask、延遲，以及兩個獨立 enable/auth 巨集，重編 Firmware / bitstream。
3. 寫入流程：Read Original → Write Test Pattern → Readback → **Restore Original → Verify Restore**。若還原失敗，LED7 亮。
4. 此 Button 版故意**不提供 Upper Page/Bank 寫入**。CMIS Bank 切換可能要求 multi-byte 原子性寫入，現有 I2C Master 是單 byte 模式，不適合直接用此測試。

### D. OSFP3 IRQ / 模擬 MSI

1. `SW[3:0]=1111`，按 BTN0。
2. PicoRV32 觸發 OSFP3 Direct Read，檢查 GLOBAL_IRQ[3] sticky，啟用 MSI source controller 觀察 ACK 計數，再清 IRQ。
3. PASS 說明**FPGA內部IRQ與 standalone ACK loopback** 可運作；**不是 Host 已收到 MSI TLP**。

## 7. Reveal 最省資源的擷取方式

在 Radiant Reveal 只抓 `u_soc.u_cpu_subsystem` （實際 hierarchy 以你的 netlist 為準）內的三個 register：

- `dbg_event_q[31:0]`：**32 bits**（OSFP channel、測試類型、register 地址、Actual/Expected、PASS/FAIL/SKIP）。
- `dbg_sequence_q[0]`：**1 bit**，每個測試結果提交時翻轉，可供觸發。
- 若需要 Write 原值/寫入值、Polling slot、NACK/timeout，才加抓 `dbg_aux_q[31:0]`。

首先只抓 33 bits 就夠；資料為保存的 snapshot，不需要追蹤 SCL/SDA waveform。Reveal Capture Depth 可先試 16 或 32；先比對不加 Reveal 和加入 Reveal 的 STA 結果。

`dbg_event_q` 格式：

| Bits | 意義 |
|---|---|
| `[7:0]` | actual data |
| `[15:8]` | expected data；Direct Read 沒有指定 golden 時為 0（不表示預期一定是 0） |
| `[23:16]` | OSFP memory byte address |
| `[25:24]` | channel 0..3 |
| `[27:26]` | mode: 0=Direct, 1=Poll, 2=Write, 3=IRQ |
| `[28]` | PASS |
| `[29]` | FAIL |
| `[30]` | SKIP |
| `[31]` | event valid |

`dbg_aux_q` 格式：`[7:0] original`, `[15:8] written test value`, `[18:16] selected index`, `[19] NACK`, `[20] Timeout`, `[21] restore_failed`。

`dbg_sequence_q` 每寫入新 `dbg_event_q` 自動加 1，所以可用 sequence bit toggle 判定有新結果。若使用 Reveal 單次 Edge Trigger，Capture 前先 Arm，再按 BTN0。若想直接檢查最後鎖住的值，可暫停測試後使用 Reveal 觀察 snapshot；不是所有版本的 Reveal 都能在不發生 trigger 時直接讀目前的暫存器狀態。

**抓到的資料是 CPU 讀到的 register 值而非直接 I2C 線路的獨立驗證**。若要確認 I2C byte/ACK 的硬體時序，需要針對失敗 channel 另外抓 SCL/SDA 或使用邏輯分析儀。

## 8. FPGA GPIO 與板級檢查

- 你已經透過 `switches` 直接接 LED 的實驗確認 DIP Pin Assignment 基本正確。
- 這次 `buttons` 經 FPGA Top 送到 CPU 的 MMIO `0x10000014[3:0]`。如果按 BTN0 完全不跑，請先用 RTL 直通 LED 檢查按鈕 PDC 與按鍵極性，並確認 CPU 實際讀到該 MMIO address。
- 必須有 FPGA 主時脈、Reset、OSFP module power and reset、4 組 I2C open-drain 連接與適當電壓/上拉。
- 四個 OSFP 是四組各自獨立的 I2C bus；不應將四組的 SDA/SCL 短接。
- 若 `BTN0` 的測試執行期間卡住，C 使用有界 timeout；除非 AXI 硬體 Slave/Bridge 本身永久不回 READY（此時 CPU 可能卡在 bus transaction）。

## 9. 限制 / 驗證狀態

- 依舊採用最初 `native_to_axil_master.v` 轉成 AXI-Lite；不是用 CPU 原生指令直接擷取 AXI protocol 波形。
- 本版測試 direct 三個安全預設 lower bytes，poll 八個可配置 lower bytes，不會自動讀完整 CMIS pages。
- 一次 Button 操作完成一種選定測試；不是一次同時測四條 I2C。
- `ENABLE_IRQ` 在 PicoRV32 核心本身仍是 0；IRQ 測試是 CPU polling Global IRQ，不是 RISC-V ISR。
- 沒有 PCIe Host 的時候只能驗證 MSI source + ACK loopback，無法證明 PCIe MSI 送達 Host。
- 本版已用 Clang/LLVM 成功編譯 RV32IM firmware（`firmware.elf`、`firmware.hex`），**RTL 尚未在 Radiant/QuestaSim 或實際板上驗證**。驗證後如有 port/pin/timing 問題需依設計環境修正。
