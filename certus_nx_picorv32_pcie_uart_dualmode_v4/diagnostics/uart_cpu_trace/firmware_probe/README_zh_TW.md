# UART／CPU 文字探針韌體

板端已確認：純 UART 回送通過，CPU 診斷 Top 使用 GitHub 原 interactive.hex；清空終端並重置後，仍在正常提示符前出現 DIRECT_READ。原韌體的開機流程不會輸出這段文字，而它恰好接在 help 字串的終止 NUL 之後。本探針用直接讀值與分支檢查取得證據，尚未宣稱 RAM 或 CPU 已確定故障。

## 板端使用

1. 保持 Top 為 **certus_nx_picorv32_uart_cpu_diag_top**，沿用目前 CPU、RTL、PDC、clock 與 LED 設定。
2. 下載本專案 firmware/uart_cpu_probe.hex，將 Radiant 的 **FIRMWARE_HEX 改為 firmware/uart_cpu_probe.hex**，確認該檔能被 synthesis 找到。
3. 重新 synthesis、map、PAR、產生 bitstream 並燒錄。HEX 內容會嵌入 FPGA RAM 初始化，須隨新 bitstream 載入。
4. 終端機仍用 115200／8N1／Flow control=None。清空畫面、重置，預期先看到 CPU_UART_PROBE v1，接著是記憶體檢查與 RX READY。
5. 等 RX READY 後慢速按一次 A，再按 Enter。請貼上完整開機檢查文字，以及按鍵後的 RX 回報。A 的原始數值應為 0x41；Enter 通常為 0x0D 或 0x0A。

這不是原 CLI，不會顯示 osfp>。探針不執行原 CLI 的韌體 heartbeat，LED0 可能不閃；以 UART 文字判讀。

## 預期讀值

下表的四個 byte 依遞增位址排列。

| 位址 | LW 整字 | 四個 LBU |
|---|---|---|
| 0x1EB0 | 75000A29 | 29 0A 00 75 |
| 0x2038 | 6D6F4300 | 00 43 6F 6D |
| 0x21B8 | 4420000A | 0A 00 20 44 |
| 0x21C4 | 70004441 | 41 44 00 70 |

關鍵 NUL：0x1EB2、0x21B9、0x21C6 應讀到 00。整字與單 byte 的結果可以互相比對。探針的主要標籤以立即數寫 UART，不依賴原本的 NUL 字串掃描；原 uart_puts 比較項目另行標示。

## 判讀方向

MEM CHECK PASS 只涵蓋列出的 LW／LBU、NUL 分支，以及 0x1E10～0x237F 指定區間的 SUM／XOR，不是全 RAM 驗證。原 puts 仍需另比對 PUTS_BEGIN 與 PUTS_END 之間是否只有空白換行；RX 結果也需另行確認。

- LW 已不符：先查實際 RAM 初始化映像與整字讀值，不能直接歸因 UART RX。
- LW 正確但 LBU 不符：追 CPU byte-load／位址選擇及資料交握。
- NUL 讀值為 00，零值分支或原 puts 測試卻不符：追實際指令／分支執行路徑。
- 記憶體檢查正常且按 A 有 DATA=00000041：此探針能讀 RX；回查原 CLI 的狀態與執行路徑。
- 已到 RX READY，按 A 沒有回報：再配合診斷 LED／Reveal 追 RXSTATUS、CPU polling 與 data read。

不同程式的存取節奏可能掩蓋間歇問題，探針通過不代表原工程全部正常。

## 來源與重建

build_probe.py 使用 Python 標準函式庫產生 RV32I 程式，不需要 C 編譯器。它以 repository 的 firmware/interactive.hex 為基底並保留受測字串資料；manifest.json 記錄覆蓋範圍、雜湊與預期值，expected_output.txt 提供理想開機輸出。

從專案根目錄執行：

    python diagnostics/uart_cpu_trace/firmware_probe/build_probe.py --base-hex firmware/interactive.hex --output firmware/uart_cpu_probe.hex --manifest diagnostics/uart_cpu_trace/firmware_probe/manifest.json --expected-output diagnostics/uart_cpu_trace/firmware_probe/expected_output.txt

以自含 RV32I 解譯器檢查產生的映像：

    python diagnostics/uart_cpu_trace/firmware_probe/test_probe.py

原本的 interactive.hex 保持原樣。結束探針測試後，可將 FIRMWARE_HEX 設回 firmware/interactive.hex，再重新產生 bitstream，回到原 CLI。

## 已完成驗證

- 自含 RV32I 解譯器與既有 RV32IM 解譯器：298-byte 開機輸出與 expected_output.txt 完全一致；A／CR 分別回報 DATA=00000041／0000000D。
- 真 CPU／原 SoC 診斷 RTL 整合回歸：125 MHz／1,000,000 baud（加速模擬）。四組 LW／LBU、三個 NUL 與零值分支、checksum、原 puts 停止位置皆正確。Serial RX 注入 A／CR，兩次 data read、trap=0、無 overrun；TX 文字在 tx_fire 握手處記錄。
- 探針只覆蓋 reset word 與 0x400..0xF1B，原 puts 與 0x1000 後所有資料逐 byte 保留。原 interactive.hex 未改動。

板端仍使用 115200。整合模擬使用官方 PicoRV32 ef203c2b0a3fb793280f5114941416c425c5b461 與 Icarus 相容用 I2C enum 等價複本，不代表使用者實際 CPU／Radiant 實作已通過。此探針尚待使用者實板回報。
