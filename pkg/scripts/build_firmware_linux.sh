#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
CC=${CC:-clang}
OBJCOPY=${OBJCOPY:-llvm-objcopy}
"$CC" --target=riscv32 -march=rv32im -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -fuse-ld=lld -Wl,--gc-sections -Wl,-Map,build/firmware.map -Wl,-T,fw/linker.ld fw/start.S fw/main.c -o build/firmware.elf
"$OBJCOPY" -O binary build/firmware.elf build/firmware.bin
python3 scripts/bin_to_hex.py build/firmware.bin firmware.hex
