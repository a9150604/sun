@echo off
setlocal
cd /d "%~dp0\.."
if not exist build mkdir build
set CC=riscv-none-elf-gcc
set OBJCOPY=riscv-none-elf-objcopy
where %CC% >NUL 2>&1
if errorlevel 1 (
  echo ERROR: Install xPack riscv-none-elf-gcc and add bin to PATH.
  exit /b 1
)
%CC% -march=rv32im -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles -Wl,--gc-sections -Wl,-Map,build\firmware.map -T fw\linker.ld fw\start.S fw\main.c -o build\firmware.elf
if errorlevel 1 exit /b 1
%OBJCOPY% -O binary build\firmware.elf build\firmware.bin
if errorlevel 1 exit /b 1
python scripts\bin_to_hex.py build\firmware.bin firmware.hex
if errorlevel 1 exit /b 1
echo Firmware ready: firmware.hex
endlocal
