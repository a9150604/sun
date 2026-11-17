# RV32I HW SELFTEST v1

## 用途

實板的 RXPATH 在完全不按鍵時持續列印全零快照。現有欄位經過堆疊、快照 RAM 及原 C 格式化函式，不能直接當作真實暫存器值。本映像改用較小的純 RV32I 組合語言程式，直接輸出已知常數、暫存器值、RAM 讀回及分支結果，以取得另一組證據。

## 板上操作

1. 下載 `firmware/rv32i_hw_selftest.hex`。
2. 在目前 Radiant Top 將 `FIRMWARE_HEX` 指向 `firmware/rv32i_hw_selftest.hex`，重新合成、產生 bitstream 並燒錄。保留既有 125 MHz、115200、POR 及腳位設定。
3. 清空終端機後重新配置／開機，**不用按鍵**。
4. 應出現 `RV32I HW SELFTEST v1`，列印一份報告，最後顯示 `END` 並停止。
5. 回傳從標題到 END 的全部輸出；若中途停止、重複列印或未看到 END，也請保留最後停住的位置。

畫面約 58 行，可複製全部文字或分段拍照。這個自測完成後保持停止，按鍵沒有命令列回應是預期行為。

HEX SHA-256：`41918e6e02702f892d1773b38c76bd7b82fcc65863f52cc3c528818170e84a2a`。

## 測項與預期值

完整預期輸出見 [expected_output.txt](expected_output.txt)。

- 已知常數：`CONST1=13579BDF`、`CONST2=5A5AA5A5`。
- 初始狀態測項：S4／S5 為 00003000、S9 為 00000009。
- X16～X31 會另行同時寫入不同圖樣，再逐一讀出；因此後面的 X20／X21／X25 圖樣會與前面的 S4／S5／S9 測項不同。
- RAM 3000、3800、6000、7ED0、7F00：先後寫入 0、11223344、A5C35A96，再由實際 LW 直接輸出讀回值。
- 地址相異階段：先寫入 2000 及上述五個地址的不同圖樣，再逐一讀回。2000／6000 配對可檢查其中一種 A14 位址 alias。
- 13 組 BEQ、BNE、BLTU、BGEU 分支測項。T／F 表示實際走到的結果；不是每一行都應為 T，請依預期輸出比對。
- 三組長分支目標距離為 0x278；填充區為無條件 self-loop，避免錯誤目標落入 NOP 區後誤判通過。

## 實作界線

- 純 RV32I、32-bit 對齊 LW／SW，沒有 C、堆疊存取、快照 RAM 或巢狀函式呼叫。
- 每個值直接來自當時的暫存器或實際 RAM LW，交給不使用堆疊的 leaf hex formatter。
- 字元直接 SW 到 0x10000004；沿用專案 MMIO 的 TX backpressure。未用 UART-ready 輪詢分支，也不讀 UART RX。
- 程式與字表為 8036 bytes，結束於 0x1F64，低於第一個測試位址 0x2000。
- 完整 32 KiB HEX，使用專案原有 CPU／RAM／UART RTL。

這些是選定操作與位址的診斷，不是完整 CPU 或 RAM 認證。CONST 格式化仍依賴基本 ALU、字表讀取、leaf call/return 與 UART 握手；數值錯誤或截斷不能單憑一行就認定哪個元件故障。

## 驗證紀錄

- [manifest.json](manifest.json)：來源、指令稽核、程式範圍及分支目標位址。
- [results/model_result.json](results/model_result.json)：7 項理想 RV32I／MMIO 機器碼測試通過，含人工的暫存器變更／alias、漏寫 RAM、錯過分支、A14 alias 及長分支錯誤目標。這些人工故障只存在於軟體模型，沒有加入下載 HEX。
- [results/rtl_result.json](results/rtl_result.json)：13 個原始 DUT 檔案逐檔 Git blob 校驗，官方核心、CPU diagnostic Top、125 MHz／115200、使用者提供的 20-bit POR。UART RX 保持 idle，RX read=0、trap=0、overrun=0。
- [results/uart_wire.log](results/uart_wire.log)：928 bytes 實體 TX 腳位解碼輸出與獨立預期值完全一致；END 後再觀察 2 ms，沒有額外輸出。

UART 輸出 SHA-256：`cc585ac1609f1f7f46cf93568b24bc95a69214fb20c28cfa0551ecbd1d26cd3c`。

## 重建與重跑

需裸機 RISC-V GCC；RTL 測試另外需要 Verilator 5、C++ 編譯工具：

```bash
python3 diagnostics/rv32i_hw_selftest/build_selftest.py --prefix riscv64-unknown-elf-
python3 diagnostics/rv32i_hw_selftest/tests/test_selftest.py
python3 diagnostics/rv32i_hw_selftest/tests/run_rtl.py
```

目前仍未取得 Radiant 合成後網表及器件啟動模型；此自測的 RTL 模擬通過不代表實板問題已修復。
