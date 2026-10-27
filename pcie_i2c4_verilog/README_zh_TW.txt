純 Verilog-2001 Testbench: AXI-Lite + 4 I2C Master 交互匯流排觀察
============================================================

檔案：
  tb_axil_i2c4_loopback.v       純 Verilog-2001 testbench
  axil_i2c4_regs.v            對應的 RTL，內含 4 個 i2c_device_ctrl 實例
  i2c_device_ctrl.v           整合後的 I2C 控制器 RTL
  run_tb_axil_i2c4.sh         Linux / macOS 的 Icarus Verilog 執行腳本
  run_tb_axil_i2c4.bat        Windows 的 Icarus Verilog 執行腳本

測試架構：
  I2C0 --- SCL/SDA 開漏共線 --- I2C1
  I2C2 --- SCL/SDA 開漏共線 --- I2C3

  4 個實例都是 I2C Master；沒有 I2C Slave Model，也沒有測試端 ACK 驅動。
  當其中一個 Master 送資料時，另一個 Master 的 scl_in/sda_in 與
  發送端共用同一條線。Testbench 使用純被動 sniffer 取樣另一端的
  輸入腳位，確認 START、7-bit Address + W 與 NACK。

涵蓋的測試：
  - 全域 ID / VERSION 與 Reset 值
  - AXI-Lite 32-bit 寫入、讀回、WSTRB=0 與 4 bank 獨立性
  - I2C0 -> I2C1, I2C1 -> I2C0, I2C2 -> I2C3, I2C3 -> I2C2
  - Direct Write 與 Direct Read 的起始 address phase
  - 無 Slave 情境下 NACK 的傳遞、direct_done 和 IRQ/IRQ clear
  - Auto Polling 啟動；無 ACK 時不應報告 auto_valid
  - VCD 波形與 PASS/FAIL 文字輸出

**重要功能限制**
  目前 i2c_device_ctrl.v 只有 I2C Master 模式，並沒有被定址後接收並
  回覆 ACK 的 I2C Slave 功能。因此另一個 I2C Controller 並不會
  接收資料存入暫存器，測試也不會成功完成 I2C Write/Read Payload。
  本測試是「Master 發送 / 另一 Master 腳位被動觀察」，不是
  「Master-to-Slave 真實資料交易」。要驗證對方 ACK 與 payload，
  需新增 I2C Slave RTL 或接真實 I2C Slave 裝置（本套件均未採用）。

執行（Icarus Verilog）：
  Linux: ./run_tb_axil_i2c4.sh
  Windows: run_tb_axil_i2c4.bat

手動執行：
  iverilog -g2001 -s tb_axil_i2c4_loopback -o sim.out \
    i2c_device_ctrl.v axil_i2c4_regs.v tb_axil_i2c4_loopback.v
  vvp sim.out
  gtkwave tb_axil_i2c4_loopback.vcd

其他模擬器，例如 Questa/ModelSim：
  vlog -vlog01compat i2c_device_ctrl.v axil_i2c4_regs.v tb_axil_i2c4_loopback.v
  vsim -c tb_axil_i2c4_loopback -do "run -all; quit -f"

此環境沒有安裝 Verilog 模擬器；testbench 尚未執行編譯與模擬。
原有 RTL 不做修改。若 testbench 顯示 FAIL，先檢查波形再判定原因。
