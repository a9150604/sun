# RXPATH PROBE v1：觀察 RXTRACE 之後的字元處理

此診斷對象是新寫的 `osfp_cli_rewrite_v1_rxtrace.hex`。實板已回報 A／Tab 的 RAW、C 正確，但接著 CR 時仍為 L=00；本映像增加後續執行路徑的快照，協助縮小差異。

## 板上使用

1. 下載專案 `firmware/osfp_cli_rewrite_v1_rxpath_probe.hex`。
2. Radiant Top 的 `FIRMWARE_HEX` 指向 `firmware/osfp_cli_rewrite_v1_rxpath_probe.hex`，重新產生 bitstream 並燒錄。沿用目前的 Top、125 MHz、115200 baud、POR 及腳位設定。
3. 清空終端機畫面，重新開機／配置後確認出現 **`RXPATH PROBE v1`**。後面仍會有原本的 RXTRACE 標題。
4. 按一次 A，等完整 `RXPATH` 印完，再按 Enter；回報這兩個字元各自的 RXTRACE、RXPATH 行。Local echo 維持關閉。

新 HEX SHA-256：`4d577cd804b272cf0ae0fb6b5510bfd6479989404564c16cb8b63894a8f8438c`。

## 如何解讀

RXTRACE 是既有的收字觀測；新增的 RXPATH 在該字元處理後、下一輪主迴圈印出。所有數值均為完整 32-bit 十六進位。

| 欄位 | 觀測內容 |
| --- | --- |
| `RET` | RXTRACE 之後，原 `check_input_loss()` 的回傳值；正常為 0。 |
| `CPOST` | 檢查函式返回後，額外讀取一次原字元堆疊位置的值。 |
| `LOAD` | 是否到達原字元 LW 後的觀測點；正常為 1。 |
| `CLOAD` | 原始 LW 指令讀出後，a0 暫存器的實際值。 |
| `S9` | Tab 比較使用的暫存器快照；正常為 9。 |
| `S4`／`S5` | 此固定基準映像中，命令狀態的位址基底；正常皆為 3000。 |
| `BAD0`／`LEN0` | 處理字元前的錯誤狀態與長度。 |
| `APP` | 是否到達 append 路徑中的 `uart_put` 呼叫位置；A／Tab 正常為 1。 |
| `ECHO` | 該呼叫的字元參數，並非 TX 完成確認。 |
| `LENA` | 到達該呼叫位置時，重新讀取的命令長度。 |
| `LEN1` | 字元處理後、印診斷文字前的命令長度。 |
| `BUF1` | 此時命令緩衝區第一個 word。 |

正常單獨輸入 A 後，關鍵值應為：

```text
RET=00000000 LOAD=00000001 CLOAD=00000041
APP=00000001 ECHO=00000041 LENA=00000001 LEN1=00000001 BUF1=00000041
```

接著 CR 的 `LEN0` 應為 1，`LEN1` 應回到 0；APP、ECHO、LENA 為 0。Tab 的 CLOAD／ECHO／BUF1 改為 09。

若 RET 非 0、LOAD 為 0、CPOST 與 CLOAD 不同，或 APP 已到達而長度讀回不同，會指向不同的後續查核路徑。這些欄位協助定位，單一欄位不能直接證明 CPU 或 RAM 故障。

## 映像內容與變更範圍

- 基準 HEX SHA-256：`f82ebb0509444b118f8793b3f7b6b8821403df9c9cdb08faee2f7cdc3dc23697`。
- 建置器拒絕套用到其他基準映像。
- 在四個原函式呼叫位置改接觀測 wrapper；另在原字元 LW 之後加入一次暫存器快照，再重播該位置原本的 LI 指令。
- 共 5 個 hook、9 個原始指令 word；新增程式與字串位於 0x4000，快照位於 0x6000。
- 原字元 LW、關鍵分支、命令緩衝區寫入指令與位址保留。其他原映像位元組保持，細節見 `manifest.json`。
- 啟動時清除新增快照，支援保留 RAM 的 CPU 暖重置。

新增 wrapper 仍會增加堆疊、RAM 存取及執行時間，可能影響實板上的故障表現。本映像是診斷工具，不代表已修復問題。快照本身也依賴 CPU 與 RAM 正確運作。

## 驗證

- `tests/test_rxpath_probe.py`：8 項理想 RV32I／MMIO 機器碼測試通過，包含 A／CR／Tab／CR、status、暖重置，以及基準與 probe 在原分支位置的暫存器輸出比對。
- 故障注入測試僅在軟體模型中，分別改變檢查回傳值、字元堆疊內容、原始 LW 的讀回、Tab 比較暫存器，以及略過長度 store，確認診斷欄位能區分這些情境；未將故障加入下載 HEX 或 RTL。
- 真實官方 PicoRV32＋專案 CPU diagnostic Top，125 MHz／115200、使用者提供的 20-bit POR：A／CR／Tab／CR 四次收字通過，1286 bytes UART TX 腳位解碼逐 byte 比對一致；trap=0、overrun=0。
- RTL 原始檔的大小、SHA-256 與 Git blob 校驗值見 `results/rtl_result.json`；完整輸出見 `results/uart_wire.log`。

## 重新建置與測試

需要 RISC-V 裸機 GCC 工具鏈：

```bash
python3 diagnostics/rxpath_probe/build_probe.py --prefix riscv64-unknown-elf-
python3 diagnostics/rxpath_probe/tests/test_rxpath_probe.py
```

RTL 測試需 Verilator 5 與 C++ 編譯工具：

```bash
python3 diagnostics/rxpath_probe/tests/run_rtl.py
```

RTL 模擬未包含 Radiant 合成後網表、器件啟動初始化或實體佈線延遲；實板根因仍待新快照確認。
