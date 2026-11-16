# UART 板端硬體回送診斷

用途：在終端機流控、接線、PDC 已確認後，用板端測試區分 UART 接收／傳送與原本的 CPU／韌體整合問題。此測試不需要 HEX、PicoRV32 或 I2C 控制器。

## Radiant 操作

1. 建立原工程的診斷用副本，保留同一顆 FPGA、相同 clock／reset 來源及外部腳位 PDC。
2. 加入三個檔案：certus_nx_uart_loopback_diag_top.v、uart_rx_byte.v、uart_tx_mmio.v。套件附帶原專案同一份 RX/TX 模組；工程中每個 UART 模組只加入一份。
3. Top module 設為 **certus_nx_uart_loopback_diag_top**。其外部 port 名稱與原 standalone top 相同；沿用對應的外部腳位約束，依新 top 調整任何舊內部階層約束。
4. CLK_HZ 必須等於實際輸入 clk 頻率，預設 125000000；BAUD=115200；依使用者現有設定預設 LED_ACTIVE_LOW=1。診斷版不需設定 FIRMWARE_HEX。
5. 重新執行 synthesis、map、PAR、bitstream 並燒錄；確認 timing report 無未解決的時序違反。不要沿用舊 bitstream。
6. 終端機維持 115200／8N1／Flow control=None，關閉 local echo。開機應顯示 **UART RX DIAG**，不是 osfp>。
7. 等 banner 完成後慢速按 A，應立即回傳 A。Enter 會回傳同一個 CR／LF byte，沒有命令解析或提示符。若看到 AA，先確認 local echo 是否仍開啟。

此診斷已通過 Icarus 模擬；仍需在使用者的 Radiant 工程及板上驗證。

## LED 定義

下表以原理圖極性與 LED_ACTIVE_LOW 設定正確為前提。LED1～4 為 sticky，發生事件後保持點亮到 reset。

| LED | 意義 |
|---|---|
| 0 | 硬體 heartbeat，約每 250 ms 切換；此版本不代表 CPU 活動 |
| 1 | 同步後的 RX 曾出現低電位 |
| 2 | UART RX 曾收妥有效 byte |
| 3 | 曾將收到的 byte 交給 UART TX 回傳；不計開機 banner |
| 4 | 曾出現 RX overrun；等待 banner 完成並慢速輸入後再試 |
| 5、6、7 | 固定熄滅（原始邏輯值為 0，輸出再套用 LED 極性） |

## 判讀

| 板端結果 | 定位方向 |
|---|---|
| 沒有 UART RX DIAG | 先確認診斷 bitstream／top、clock／reset 與 TX；本次 RX 結果還不能判讀 |
| 有 banner；按 A 後 LED1 未亮 | 邏輯未觀察到 RX 低電位，量測 FPGA 實際輸入波形 |
| LED1 亮、LED2 未亮 | 有 RX 活動但沒有有效 UART frame；量測實際 clock、鮑率、idle/stop bit 與電位 |
| LED2 亮、LED3 未亮 | byte 已接收但未送交 TX；觀察 rx_valid、tx_ready 與 reset |
| LED3 亮、仍看不到 A | 確認終端機顯示與 TX 線波形；LED3 代表送交 TX，不代表電腦已收到 |
| A 正常回傳 | 基本板端 RX/TX 能工作；回查原工程 CPU/MMIO、使用的 RTL／HEX 版本、reset 與 timing |
| LED7 仍亮 | 此診斷沒有 CPU trap；核對 LED 實體編號／PDC、極性，以及是否真的燒入此版本 |

回報四件事即可：**有無診斷 banner、A 有無回傳、按鍵前後 LED1～4 狀態、LED7 是否熄滅**。

通過此測試不會單獨證明原 CPU 程式有 bug；不同 top 的資源配置與繞線也會不同，原工程仍需檢查 timing。

## 已完成模擬

125 MHz／115200，從模擬中的 UART TX 串列波形解碼驗證開機 banner、A／z／CR／LF 原樣回送、LED 事件保持、reset 清除事件並重送 banner，以及 LED_ACTIVE_LOW=0／1 兩實例的 LED 輸出互反。正常慢速測試無 RX overrun。

測試檔：tb_uart_loopback_diag.sv。模擬不代表 Radiant synthesis、PAR 或板端驗證已通過。
