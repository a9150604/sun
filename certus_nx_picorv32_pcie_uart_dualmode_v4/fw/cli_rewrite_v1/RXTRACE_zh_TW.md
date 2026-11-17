# 新 CLI 的 RXTRACE 輸入觀測版

目前板端回報：新版開機標示正確、Local echo 關閉、每次 Enter 會出現新的 osfp>，但字母沒有回顯，盲打 status 也沒有命令結果。這些資訊仍不足以判定是 RTL、CPU/RAM 資料傳遞或收到的字元值不符預期。

本版針對新重寫的 CLI 記錄輸入，沿用同一套 RTL。一般版 osfp_cli_rewrite_v1.hex 的機器碼保持不變；本版是獨立的 firmware/osfp_cli_rewrite_v1_rxtrace.hex。

## 使用

1. 下載 firmware/osfp_cli_rewrite_v1_rxtrace.hex。
2. 沿用目前的 Top／RTL／PDC，將 FIRMWARE_HEX 設為 firmware/osfp_cli_rewrite_v1_rxtrace.hex，重新產生並燒錄 bitstream。
3. 終端機仍用 115200、8N1、Flow control=None、Local echo 關閉。開機應明確顯示：

       OSFP CLI REWRITE v1 RXTRACE
       One key at a time; RAW is the word read from IO_RX.
       osfp>

4. 使用英文半形，單按一次 A，暫停一秒，再按 Enter。請貼回兩次按鍵後的完整 RXTRACE 行；若按 A 完全沒有 RXTRACE，也請一併說明。

正常 A 的輸出：

    RXTRACE RAW=00000041 C=00000041 L=00 BAD=0 HW=00000000 DROP=00000000
    A

接著 Enter 的輸出包含：

    RXTRACE RAW=0000000D C=0000000D L=01 BAD=0 HW=00000000 DROP=00000000

之後 A 不是有效命令，預期會顯示 ERR unknown command 並回到 prompt。

## 欄位

| 欄位 | 意義 |
|---|---|
| RAW | 此字元對應的完整 IO_RX 32-bit 讀值；正常硬體的高 24 bits 為零 |
| C | 傳給字元處理器的 RAW & 0xFF |
| L | 處理本字元之前的命令長度 |
| BAD | 0=正常、1=過長行、2=資料遺失恢復狀態 |
| HW | 已觀測到的硬體 overrun 次數 |
| DROP | 已觀測到的軟體接收佇列滿／掉字次數 |

RAW 在接收佇列中與字元一起保存，從佇列取出後、字元篩選前輸出；不是輸出當下重新讀 RX 暫存器。未送入軟體佇列或因資料遺失被丟棄的字元不保證有 RXTRACE 行，錯誤回報與計數需一起判讀。

如果 C 為 00、非 ASCII 值或與實際按鍵不符，可據此追資料路徑；如果 C=41、BAD=0 卻無回顯，則需進一步比對後續 parser／TX 執行結果。HW 或 DROP 增加表示輸入遺失。

本版每個字元會產生較多 UART 輸出，請逐字慢速測試。文字追蹤也會改變存取節奏，測試通過不代表一般版在所有板端條件下都正常。

## 重建與驗證

    python fw/cli_rewrite_v1/build.py --rx-trace
    python fw/cli_rewrite_v1/tests/test_rxtrace.py

一般建置不加 --rx-trace；兩者的預設輸出檔名與 build 資料夾分開。正常版仍為 SHA256 1030f723833afa74bd3a38060cbb333d14be42d2bf75e04c4a767fcb576cae4e。

RXTRACE HEX SHA256：f82ebb0509444b118f8793b3f7b6b8821403df9c9cdb08faee2f7cdc3dc23697。

已通過 9 項新映像機器碼／理想 MMIO 測試，包括 RAW、遮罩、Enter、non-ASCII、CRLF、佇列逐字對應及一般 HEX 未變。

另以官方 PicoRV32 與原 SoC，在 125 MHz／1 Mbaud 進行真 UART TX 線解碼，逐 byte 驗證 270 bytes 的開機、A／CR trace、字元回顯與 prompt；trap=0、無 overrun、RX data read=2。此鮑率用於加速模擬，板端仍用 115200。

重跑 UART 線模擬：

    python fw/cli_rewrite_v1/tests/run_rxtrace_rtl.py --picorv32 third_party/picorv32.v --baud 1000000

目前尚無此版的實板結果。Timing 通過可排除報告中已檢查的時序違反，不能單獨證明 RTL／CPU／RAM 的功能行為都正確。
