@echo off
setlocal
cd /d "%~dp0"
where iverilog >nul 2>nul
if errorlevel 1 (
    echo ERROR: iverilog was not found in PATH.
    exit /b 127
)
iverilog -g2001 -s tb_axil_i2c4_loopback -o tb_axil_i2c4_loopback.out i2c_device_ctrl.v axil_i2c4_regs.v tb_axil_i2c4_loopback.v
if errorlevel 1 exit /b 1
vvp tb_axil_i2c4_loopback.out > tb_axil_i2c4_loopback.log
if errorlevel 1 exit /b 1
type tb_axil_i2c4_loopback.log
findstr /C:"TB FAIL" /C:"[TIMEOUT]" /C:"[FAIL]" tb_axil_i2c4_loopback.log >nul
if not errorlevel 1 (
    echo FAIL: See tb_axil_i2c4_loopback.log
    exit /b 1
)
findstr /C:"TB PASS" tb_axil_i2c4_loopback.log >nul
if errorlevel 1 (
    echo FAIL: TB PASS not found in log.
    exit /b 1
)
echo PASS: Waveform file tb_axil_i2c4_loopback.vcd
exit /b 0
