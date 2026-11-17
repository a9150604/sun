# 使用者提供的 20-bit POR：RXTRACE 整合測試

## 本次收到的 POR

```verilog
reg [19:0] por_cnt = 20'd0;
wire resetn_int = &por_cnt;
always @(posedge clk) begin
    if (!resetn_int)
        por_cnt <= por_cnt + 1'b1;
end
```

計數器初值為 0，在第 1,048,575 個上升緣到達 `20'hFFFFF`，`resetn_int` 由低轉高，之後計數停止並保持。125 MHz 下等待時間約 8.3886 ms；50 MHz 下約 20.9715 ms。此程式不會自行溢位而反覆重置。

## 本次如何測試

在既有 `tb_rxtrace_exact.sv` 新增 `TEST_USER_POR` 選項，原樣加入上述計數器，將輸出作為原始專案 Top 的 reset 輸入。CPU、RAM、UART、fabric、I2C 及 HEX 均保留原始內容，並在測試前後核對 Git blob／SHA-256。

**使用者修改後的完整 Top 與 reset 接線尚未提供。** 這次驗證的是這段 POR 正確連接到原始 Top 時的 RTL 行為；不是對使用者完整 Radiant build 的驗證。

固定條件：

- CLK：125 MHz；UART：115200 baud，8N1。
- Firmware：`firmware/osfp_cli_rewrite_v1_rxtrace.hex`。
- HEX SHA-256：`f82ebb0509444b118f8793b3f7b6b8821403df9c9cdb08faee2f7cdc3dc23697`。
- DUT 原檔來源 commit：`365fcead5aae84356e2304541c688c7858b503ce`，每組 13 個原始檔。
- 模擬器：Verilator 5.032。

| Top | 結果 | 紀錄 |
| --- | --- | --- |
| `certus_nx_picorv32_uart_standalone_top` | PASS | [UART](standalone/uart_wire.log) · [模擬](standalone/simulation.log) · [來源與參數](standalone/source_manifest.json) |
| `certus_nx_picorv32_uart_cpu_diag_top` | PASS | [UART](cpu-diag/uart_wire.log) · [模擬](cpu-diag/simulation.log) · [來源與參數](cpu-diag/source_manifest.json) |

測試檢查了 POR 初值、低電位保持時鐘數、終值飽和保持及不再重置。接著從 UART RX 輸入 A、CR，從 UART TX 腳位解碼確認 A 在 Enter 前回顯、CR 時 `L=01`，trap=0、overrun=0。兩份 UART 輸出均為 270 bytes，SHA-256 為 `fe7490bc10898cefb4a5852722abbd3dae07905587baf63b446f7995f8fe7e05`。

## 重跑

於專案根目錄，使用 Verilator 5 與 C++ 編譯工具：

```bash
python3 fw/cli_rewrite_v1/tests/run_rxtrace_exact_rtl.py --top standalone --por --baud 115200
python3 fw/cli_rewrite_v1/tests/run_rxtrace_exact_rtl.py --top cpu-diag --por --baud 115200
```

預設輸出為 `build/cli_rewrite_v1_rxtrace/exact-user-por/<top>/`。沒有 `--por` 時，仍使用既有測試平台的 20-clock 外部 reset。

## 尚需核對的實板差異

- 原 Top 的實例使用 `.resetn(resetn)`；新增 `resetn_int` 後，應確認實際接到 `.resetn(resetn_int)`，或有正確的訊號連接。
- POR 使用的 clk 是板上時鐘還是 PLL 輸出；若有 PLL，需核對時鐘穩定與 locked 的處理。
- 宣告初值 `por_cnt = 20'd0` 是否落實到 FPGA 的啟動狀態。
- `&por_cnt` 是組合解碼；實體多位元進位可能有短暫毛刺。可考慮由暫存器輸出 reset，但目前未證明這就是實板症狀的原因。

這次為理想時鐘下的 RTL 模擬，未模擬合成後佈線延遲、reset 解碼毛刺或器件啟動行為。單憑此段 POR，仍未找到造成目前不回顯的確定根因。
