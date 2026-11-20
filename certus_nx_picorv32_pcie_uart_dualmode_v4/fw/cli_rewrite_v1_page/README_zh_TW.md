# OSFP CLI REWRITE v1 PAGE WRITE

這是獨立於原版的 page-write 韌體，提供明確解鎖後的 `write 7F <page>`。它也允許對 7E 的原始單 byte 寫入，但這不代表實作完整的 CMIS bank 切換流程。原版 `osfp_cli_rewrite_v1.hex`、原始碼、核心及 RTL 都保留原樣。

可直接使用的映像：`firmware/osfp_cli_rewrite_v1_page.hex`。開機標示應為：

```text
OSFP CLI REWRITE v1 PAGE WRITE (RV32I WORD IO)
```

## 為何原版擋住 7E／7F

原版將 bank/page selector 與一般資料暫存器一起擋住，限制過大。0x7F 是 page selector，可用來選取 upper memory 的 page；0x7E 是適用 CMIS 模組／頁面的 bank selector。實際支援的 page、bank 及切換時序，仍依模組規格。

這些位址不是普通測試資料。`writeverify` 會讀原值、測試寫入、讀回，再恢復原值；對 selector 執行這種流程會改變後續 upper-memory 存取的上下文。因此此版允許 plain `write` 選頁，但保留 `writeverify 7E/7F` 的阻擋，且在任何 I2C 交易前拒絕該操作。所有寫入仍先要求 `unlock`。

## Radiant 使用

沿用已成功的 `picorv32_wb_forward.v`、Top、時脈、POR 與腳位設定，只把 `FIRMWARE_HEX` 指向：

```text
firmware/osfp_cli_rewrite_v1_page.hex
```

重新合成、布局繞線、產生 bitstream 並燒錄。這個 HEX 是 RAM 初值，單改電腦裡的檔案不會改變 FPGA 已載入內容。

## 手動選擇 upper page 的例子

以下假設 OSFP 接 channel 0、七位元 I2C 位址為 0x50，而且模組支援 page 0x01，且該 page 是 unbanked，或目前已處於所需的 bank。請依實際接線與模組規格調整。

```text
mode cpu
ch 0
dev 50
unlock
write 7F 01
delay 10
read 7F
read 80
read 81
write 7F 00
lock
```

`write 7F 01` 選擇 upper page 0x01。之後 `read 80`、`read 81` 讀的是該 page 的 0x80、0x81 offsets，不是讀 page 0x80、0x81。Lower memory 0x00～0x7F 不因 page 選擇而改變其地址視窗。

例子中的 `delay 10` 是十進位 10 ms，僅示範切換後等待，並非所有模組的保證值。請使用模組文件要求的等待／ready 流程，並核對 `read 7F` 的回覆。要求不支援的 page 時，模組可能返回 page 0x00，不能只憑寫入 ACK 判定選頁成功。

依 [CMIS 5.3 §8.2.15](https://www.oiforum.com/wp-content/uploads/OIF-CMIS-05.3.pdf)，同一 bank 中改 page，或選 unbanked page，可以只寫 PageSelect。**需要改 bank index 時，BankSelect 與 PageSelect 必須在同一筆 WRITE access 中寫入。** 本專案的 I2C master 目前只有單 byte register write；`write 7E xx` 再 `write 7F yy` 是兩筆含各自 STOP 的交易，不能當作上述完整 bank 切換流程。此版未新增該多 byte 能力。

每次寫入請確認回覆的 `rc=0x00`；若寫入失敗，先停止後續讀取。即使控制器回報成功，也仍須依板上的 I2C 電位與裝置實際回應驗證選頁結果。本版不會自動還原 selector，`lock` 也只鎖定後續寫入；例子的 `write 7F 00` 是明確返回 page 0x00。需要返回原 page/bank 時，仍須依上述規範與模組要求操作。

## 修改範圍

- `main.c`：只讓已解鎖的 plain write 通過 7E／7F，保留 writeverify 限制；更新 help 與版本標示。
- `build.py`：預設輸出改為 page 專用 HEX 與 build 目錄。可選的 `--rx-trace` 亦使用 page 專用名稱。
- `start.S`、`platform.c/.h`、`i2c.c/.h`、`linker.ld`：與原版逐位元組相同，包含 driver 的 writeverify selector 防護。

完整差異見 `baseline_vs_page.diff`。來源／映像校驗與指令稽核見 `release_manifest.json`。此變更不修正底層 I2C 電氣或 RTL 時序，也尚未宣稱完成實際 OSFP 模組的 upper-page 驗證。

## 已完成驗證

- 軟體機器碼／MMIO 模型：43 項通過，包含原版 19、新版回歸 19，以及選頁 fixture 5 項；記錄見 [results/model_results.json](results/model_results.json)。
- 完整 UART → 旁路 PicoRV32 → AXI → 原始 I2C RTL：947 個 UART bytes 完整比對通過，RX=152、16 次提示符、9 筆 I2C 交易（7 讀、2 寫）、9 次 STOP；記錄見 [results/rtl_results.json](results/rtl_results.json) 與 [results/uart_wire.log](results/uart_wire.log)。
- 模型中的 upper offset 80：page 00 回傳 11，選 page 01 後回傳 A5，手動回 page 00 後再次回傳 11；offset 81 在 page 01 回傳 5A，lower offset 00 仍回傳 19。這些是測試資料，不是對實際模組內容的預測。
- 鎖定時的 selector write，以及 writeverify 7E／7F 均未產生 I2C 交易；軟體模型另驗證 NACK、timeout、ownership 與 lock 不還原選頁。
- 原始 DUT、已驗證旁路核心、HEX 與測試輸入有雜湊核對，兩份結果均為 `changed_inputs=[]`。

RTL 測試使用 125 MHz、115200、使用者的 20-bit POR，以及理想 open-drain／不拉伸 SCL 的裝置 fixture。沒有實際 OSFP、類比 I2C 延遲或 Radiant P&R／SDF 驗證。Raw 7E 單 byte 寫入不構成完整 CMIS bank 切換測試。

重跑測試：

```text
python fw/cli_rewrite_v1_page/tests/test_firmware.py
python fw/cli_rewrite_v1_page/tests/run_rtl.py
```

RTL 測試需 Verilator 5 與 C++ 編譯工具；`--project` 可指定另一個 DUT checkout，但來源必須符合腳本核對的已發布 Git blob。

## 重新建置

從專案根目錄執行：

```text
python fw/cli_rewrite_v1_page/build.py
```

工具不在 PATH 時可加 `--cc` 指定支援 RV32I／ilp32 的 bare-metal RISC-V GCC。預設產物為 `build/cli_rewrite_v1_page/` 與 `firmware/osfp_cli_rewrite_v1_page.hex`，不覆寫原版。
