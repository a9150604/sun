@echo off
setlocal
cd /d "%~dp0\.."
if not exist build mkdir build
riscv-none-elf-gcc -march=rv32im -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles -DENABLE_MSI_LOOPBACK_TEST=0 -DREQUIRE_REAL_HOST_MSI=1 -Wl,--gc-sections -T fw\linker.ld fw\start.S fw\main.c -o build\firmware_host.elf
if errorlevel 1 exit /b 1
riscv-none-elf-objcopy -O binary build\firmware_host.elf build\firmware_host.bin
if errorlevel 1 exit /b 1
python scripts\bin_to_hex.py build\firmware_host.bin firmware_host.hex
if errorlevel 1 exit /b 1
echo firmware_host.hex ready
endlocal
