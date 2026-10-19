#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v iverilog >/dev/null 2>&1; then
  echo "ERROR: Icarus Verilog (iverilog) is not installed."
  echo "Install it or use the Questa/VCS commands in README_zh_TW.txt."
  exit 127
fi
iverilog -g2001 -s tb_axil_i2c4_loopback \
  -o tb_axil_i2c4_loopback.out \
  i2c_device_ctrl.v axil_i2c4_regs.v tb_axil_i2c4_loopback.v
vvp tb_axil_i2c4_loopback.out | tee tb_axil_i2c4_loopback.log
if grep -Eq 'TB FAIL|\[TIMEOUT\]|\[FAIL\]' tb_axil_i2c4_loopback.log; then
  echo 'FAIL: See tb_axil_i2c4_loopback.log'
  exit 1
fi
if ! grep -q 'TB PASS' tb_axil_i2c4_loopback.log; then
  echo 'FAIL: simulation did not report TB PASS'
  exit 1
fi
echo 'PASS: Waveform file tb_axil_i2c4_loopback.vcd'
