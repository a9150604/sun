# PicoRV32 寫回資料旁路：本專案上板候選

## 目前證據

使用者的原版無 NOP 自測曾出現 `CONST1=13579BD`、`CONST2=F5A5AA5A` 等逐筆帶入上一筆末碼的規律。G1 在八個 formatter LW／SW 中各加一條 NOP 後，板上照片的關鍵數值恢復並到達 END。

這支持載入後立即使用的相依路徑值得查核，但尚未取得實際 Radiant 映射網表與時序，不能認定官方 RTL 有錯，或已證明暫存器檔被合成為某一種 RAM。

本候選在內部雙讀埠 register file 增加「最近一次寫回資料」旁路：保存前一個上升緣寫入的有效位、暫存器編號與資料，下一條指令若讀取相同非零暫存器，優先使用這份新值。介面、CPU FSM、UART、RAM 握手及韌體都沿用原設計。

**此檔是本專案的修改候選，不是官方未修改原檔，也尚未在使用者板上驗證。** 官方原檔仍保留在 `third_party/picorv32.v`。

## Radiant：先測無 NOP 原版，再測 CLI

1. 下載本目錄的 `picorv32_wb_forward.v`。
2. 在 Radiant active source list 移除原本使用的 `picorv32.v`，加入這份；只保留一份定義 `picorv32` 模組的來源。原檔可留在磁碟上。
3. Top Module 維持目前使用的專案 Top，保留原本 125 MHz、115200、POR 和腳位設定。新檔的模組名稱仍是 `picorv32`，不用改 wrapper。
4. **先把 FIRMWARE_HEX 改回原版無 NOP 自測：**

```text
firmware/rv32i_hw_selftest.hex
```

完整重新合成、布局繞線及產生 bitstream，確認新的 125 MHz 時序結果後燒錄。畫面標題應為 `RV32I HW SELFTEST v1`，關鍵輸出應為：

```text
CONST1=13579BDF
CONST2=5A5AA5A5
S4=00003000
S9=00000009
```

完整預期報告見 `diagnostics/rv32i_hw_selftest/expected_output.txt`，最後應到達 END 並停止。此步使用的是沒有 G1 間隔的原始程式，以確認 RTL 端是否改善。

5. 原版自測正確後，保留這份核心，把 FIRMWARE_HEX 指向既有新 CLI：

```text
firmware/osfp_cli_rewrite_v1.hex
```

重新產生 bitstream、燒錄，確認 `OSFP CLI REWRITE v1 (RV32I WORD IO)` 標題。Local echo 保持關閉，測試：

- 單按 A：應在 Enter 前回顯 A。
- 按 Enter：A 不是命令，因此應顯示未知命令訊息及新提示符。
- 輸入 `status` 再 Enter：應列出狀態，不只是換行與提示符。

若仍有錯位、沒有回顯或停住，請保留對應標題與實際輸出；這仍是需要實板確認的修正候選。

## 檔案來源與修改範圍

- 上游：YosysHQ/picorv32 commit `ef203c2b0a3fb793280f5114941416c425c5b461`。
- 官方原檔 SHA-256：`0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622`。
- 候選 SHA-256：`c51201ed368df602fb1c2499795ad5eef12c335abb05c11b7f24bd9437b5943d`。
- 完整差異：[upstream_vs_candidate.diff](upstream_vs_candidate.diff)。原 ISC 授權與著作權聲明保留在核心檔頭。
- `build_core.py` 從固定官方原檔重建候選，會檢查來源與產物 SHA，保留官方原檔。

測試範圍為本專案的 RV32I、32 registers、內部雙讀埠 RF、IRQ 關閉。外部 RF、formal-blackbox 及兩個 intentional TESTBUG 巨集的預處理 token 保持上游一致；這是原始碼中立性檢查，不是 formal verification。單讀埠路徑保留原行為，未宣稱本候選能修復所有配置。

## 已完成驗證

[results/regression_results.json](results/regression_results.json) 記錄四組可重跑測試。其餘 DUT 來源逐檔 Git blob 核對，125 MHz／115200，兩種 testbench 都使用使用者的 20-bit POR。

| 暫存器檔條件 | 無 NOP 自測 | 正常 CLI |
| --- | --- | --- |
| 正常候選 | 928 bytes 完整 UART 比對通過 | 634 bytes 完整比對通過 |
| 刻意同步／read-first 故障模型＋旁路 | 928 bytes 通過 | 634 bytes 通過 |

自測包含 END 後 2 ms 無額外輸出。CLI 包含 A 在 Enter 前回顯、status、CRLF、BS／DEL，七個提示符、RX=28、trap=0、overrun=0。

故障模型只由測試程式產生於 build 輸出目錄，並非實板網表；**下載的 `picorv32_wb_forward.v` 沒有這些故障注入程式。** 正常與故障條件的通過，不代表實際板上 RF 模式已被辨識。

另有健康 RF 模型中的最近寫回不變式觀測：2497 次寫回檢查及 336 次匹配來源檢查，見 `results/invariant_checks.json`。這些是執行中的模擬檢查，不是所有狀態的形式證明。

## 仍需實板／實作確認

正常非同步 RF 下，旁路回傳值與原陣列讀值應相同。因此合成工具可能將它移除或實作為等價的寫入直通；需要確認實際映射後保留正確行為，並滿足 125 MHz 時序。

本候選尚未執行使用者工程的合成後／P&R／SDF 模擬，也尚未有候選本身的板上測試。若未改善，下一項證據應是實際 RF 推導、時序路徑，以及 load ACK→寫回→下一條來源讀取的板內波形。

## 重建與重跑

```bash
python3 diagnostics/picorv32_wb_forward/build_core.py
python3 diagnostics/picorv32_wb_forward/tests/run_rtl.py
```

測試需 Verilator 5、C++ 編譯工具。完整測試程式只在 build 輸出生成故障 fixture；請僅將本目錄的正式候選 `.v` 加入 FPGA 工程。
