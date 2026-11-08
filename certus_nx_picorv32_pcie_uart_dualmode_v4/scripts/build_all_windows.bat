@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0.."
if not exist build mkdir build
if not exist firmware mkdir firmware
set "CC=riscv-none-elf-gcc"
set "OBJCOPY=riscv-none-elf-objcopy"
for %%M in (interactive auto_direct_read auto_direct_write auto_poll_read) do (
  set "SRC=fw\%%M.c"
  if "%%M"=="interactive" set "SRC=fw\interactive_main.c"
  echo Compiling %%M from !SRC! ...
  %CC% -march=rv32im -mabi=ilp32 -Os -ffreestanding -fno-builtin -fno-stack-protector -ffunction-sections -fdata-sections -nostdlib -I fw -T fw/linker.ld -Wl,--gc-sections -Wl,-Map=build\%%M.map fw\start.S fw\common.c !SRC! -o build\%%M.elf
  if errorlevel 1 goto :fail
  %OBJCOPY% -O binary build\%%M.elf build\%%M.bin
  if errorlevel 1 goto :fail
  py -3 scripts\bin_to_hex.py build\%%M.bin firmware\%%M.hex --ram-kb 32
  if errorlevel 1 goto :fail
)
py -3 scripts\select_firmware.py interactive
if errorlevel 1 goto :fail
echo SUCCESS: four independent firmware HEX images.
exit /b 0
:fail
echo Firmware build FAILED. Verify RISC-V GCC and Python on PATH.
exit /b 1
