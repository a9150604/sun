# G1：一條 NOP 的載入／使用相依對照

## 為何新增這個對照

實板自測的前兩行已由使用者確認為：

```text
CONST1=13579BD
CONST2=F5A5AA5A
```

正常應為 `13579BDF`、`5A5AA5A5`。照片其他數字也呈現上一筆最後一碼帶到下一筆的規律。數字 formatter 原本逐字執行：

```text
lw t1, 0(t0)
sw t1, 0(s0)
```

人工故障模型若讓 LW 的下一條使用者讀到舊的 t1，就會產生第一筆不可見 NUL＋13579BD，然後 F5A5AA5A，並能重現先前 RXTRACE 不回顯與 RXPATH 無按鍵全零列印的現象。

**這是與觀測吻合的假說，不是已取得實板合成網表的根因證明。** 照片只確認可見文字，沒有取得實板原始 UART byte capture，因此不能宣稱實板的不可見 NUL 已被量測證實。

## 板上操作

1. 下載 `firmware/rv32i_hw_selftest_gap1.hex`。
2. 原本 Top 的 `FIRMWARE_HEX` 改指向該檔，保留目前 CPU、UART、125 MHz、115200、POR 及腳位設定。
3. 重新合成、產生 bitstream 並燒錄，清空終端畫面後觀察開機輸出，不需按鍵。
4. 確認標題為 **`RV32I HW SELFTEST G1`**。
5. 回報完整結果，尤其以下四行是否恢復：

```text
CONST1=13579BDF
CONST2=5A5AA5A5
S4=00003000
S9=00000009
```

正常會印一次報告、顯示 END 後停止；這仍是開機自測，不接收 CLI 命令。

G1 HEX SHA-256：`b3348414f21d5d20d26c802f33015bd765323312ea59878e9ebb7e2816a76881`。

## 唯一刻意改動的資料相依

八個 formatter 配對各加入一條 NOP：

```text
lw t1, 0(t0)
nop
sw t1, 0(s0)
```

其他 load 間隔及主程式分支位址保留。程式增加 32 bytes；字表跟著重定位，主程式另有字表指標與標題 v→G 的兩個 word 差異。所有變更及位址由 `manifest.json` 核對。

PicoRV32 是多週期核心，一條 NOP 不等於僅增加一個 clock。RV32I 正常實作不應要求軟體手動加入這個 NOP 才能正確取得已完成 load 的值。

原始 HEX、組合語言、建置輸入及測試檔均保留；建置器拒絕覆寫固定基準輸入。

## 驗證與判讀界線

- 原版及 G1 在健康的理想 CPU／原始 RTL 上，輸出只差標題 v1→G1。
- `tests/test_gap.py` 共 5 項機器碼模型測試通過。明確注入「立即使用 LW 舊值」的模型能重現照片可見數字、A／Tab 無回顯、以及 RXPATH 的無按鍵全零列印；同一模型執行 G1 時數字恢復。
- 這些人工故障只存在於 `tests/load_use_model.py`，沒有加入下載 HEX、PicoRV32 或 UART RTL。
- 真實官方 PicoRV32＋13 個 Git blob 校驗一致的原始 DUT，CPU diagnostic Top、125 MHz／115200、使用者 20-bit POR：928 個 TX wire bytes 完整比對通過，RX read=0、trap=0、overrun=0；END 後 2 ms 安靜。
- UART 輸出及逐檔證據見 `results/uart_wire.log`、`results/rtl_result.json`；完整預期輸出為 `expected_output.txt`。

若實板 G1 恢復數字，會支持載入後立即使用路徑的相依／時序問題；仍需核對暫存器檔映射、寫回與讀取、實際時鐘約束及合成後電路。NOP 改變執行時間及少量程式配置，成功不等於已證明某一項合成根因，亦不代表 CLI 已修復。

## 重跑

```bash
python3 diagnostics/rv32i_load_gap/build_gap.py --prefix riscv64-unknown-elf-
python3 diagnostics/rv32i_load_gap/tests/test_gap.py
python3 diagnostics/rv32i_load_gap/tests/run_rtl.py
```

RTL 測試使用原本的 `tb_hw_selftest.sv`，不改測試平台或任何 production RTL。需 Verilator 5 與 C++ 編譯工具。
