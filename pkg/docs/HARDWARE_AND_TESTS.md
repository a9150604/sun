# Certus-NX 接線、QSFP 安全性、Test Plan

## 開發板線路

此 package 不含實際 PDC location：必須由你的開發板 schematic 填入。`LFD2NX-65-9BG484C` 僅是 FPGA 料號，並不能推定 pin map。

| Board pin | Top port | 注意 |
|---|---|---|
| oscillator | `clk_in` | 預設 CLK_HZ = 50 MHz，若板上不是 50 MHz 必須修改參數 |
| push button/reset IC | `reset_n` | 低有效，需依板子完成去抖與 reset release |
| LEDs 0..7 | `led[7:0]` | 需核對正/負邏輯；板上負邏輯時請外面反相 |
| USB-UART RX | `uart_tx` | FPGA TX→USB-UART RX，共地、I/O 電壓相容；115200 8N1 |
| QSFP0..3 SCL | `qsfp_scl[3:0]` | 4 組分開、open-drain、外接正確 pull-up |
| QSFP0..3 SDA | `qsfp_sda[3:0]` | 4 組分開、open-drain、外接正確 pull-up |
| MODSEL_N/RESET_N/LPMode | 板級控制 | 依實際 QSFP module/board 正確拉位準；本範例沒有定義這些 pin |
| host PCIe clock/lanes | user original top | 不在 standalone top 內 |

**禁止**硬接 3.3V 到 1.8V FPGA bank；QSFP Vcc、I2C pull-up 電壓、level shifting 需依板子規格確認。

## Firmware testcases（預設唯讀）

| 測試 | 內容 | 判定 |
|---|---|---|
| TC1 | AXI-Lite ID/VERSION read | ID 0x49324334, version 非全0或全1 |
| TC2 | 4路 DEV_CFG 寫入與讀回 | readback 相同；強制各 channel I2C 0x50 |
| TC3 | Invalid AXI address | 回 0xBAD0ADD0（取自 snapshot RTL） |
| TC4 | 4 QSFP 0x00 direct read | ACK、DONE、回值非0x00/0xFF；並印出 Identifier |
| TC5 | 4 QSFP重複讀取 | 同 channel 的 Identifier 一致 |
| TC6 | 4 QSFP IRQ sticky | GLOBAL_IRQ對應bit和DONE有效 |
| TC7 | 4 QSFP IRQ clear | 寫 CONTROL[4] 清除 sticky IRQ |
| TC8 | 4 QSFP auto polling | 將 POLL_ADDR0 設為0x00，SHADOW0等於 direct Identifier |
| TC9 | MSI source/ack | Standalone FPGA內部 ACK loopback，不代表 Host 收到 MSI |
| TC10 | 可選 absent I2C addr NACK | 預設關閉，需確認 0x55 沒有其他 slave |
| QSFP Write | 可選讀寫測試 | 預設禁止；需依 vendor 提供安全可寫位址自行實作備份/寫入/讀回/還原 |

**資料驗證層級**：ACK/DONE 保證通訊完成？不是。Identifier value 的合法性仍需搭配真實 SFF-8636/CMIS spec、模組類型、vendor datasheet、以及另一台已驗證 I2C 儀器交叉比對。Auto polling 与 Direct Read 可能共享相同 RTL bug，不能視為獨立 golden checker。

**注意**：QSFP 4個模組 address 皆為 `0x50`（獨立 I2C bus），snapshot reset 是 `0x50..0x53`，本 FW 在開始測試前改成 `0x50`。下方主機上先選 `cpu_mode=1`、對 FPGA reset，再進行 standalone 測試。

## UART LED 判定

`LED[0]`：測試執行中，`LED[1]`：PASS，`LED[7]`：FAIL。若 LED 為 active-low，需於 board top 反相；不可誤以為預設極性正確。

`uart_tx` 固定 Baud=`BAUD` 參數（預設 115200），不是軟體動態設 baud；CPU MMIO UART 寫入會在 TX 忙碌時 stall，因此不會丟字元。UART 只有 TX，沒有 RX。

## 常見失敗定位

- UART 無輸出：先確認 pin、clock、reset、baud、`firmware.hex` 載入、PicoRV32 source 是否用原版，以及 `cpu_trap`。
- AXI ID mismatch：看 `native_to_axil_master` 的 ARVALID/ARREADY/RVALID/RREADY，以及 mode mux 是否在 CPU mode。
- 四 QSFP 都 NACK：檢查 MODSEL_N、供電、SCL/SDA 上拉、QSFP address 0x50、I/O bank 電壓、RESET_N。
- 一個 channel NACK：針對該路查 pin map、ACK timing 與 I2C waveforms；Lattice Reveal 捕捉 SDA/SCL。
- MSI loopback PASS 但 OS ISR 不跑：這是預期限制。用實際 PCIe Root Port + driver 的 `request_irq`/MSI configuration 另測。

## Golden Identifier

若已知四顆 QSFP 的實際 Identifier，可在編譯時加入 `-DGOLDEN_QSFP0_ID=0x0d` 等編譯參數；未設定時 BIST 只做非 00/FF 的基本 sanity 檢查，**不能宣稱與 QSFP 標準 Golden Data 比對通過**。
