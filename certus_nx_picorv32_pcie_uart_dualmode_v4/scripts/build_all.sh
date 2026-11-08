#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CC=${CC:-clang}
LD=${LD:-ld.lld}
OBJCOPY=${OBJCOPY:-llvm-objcopy}
mkdir -p build firmware
"$CC" --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 \
  -Os -ffreestanding -fno-builtin -fno-stack-protector \
  -fdata-sections -ffunction-sections -nostdlib -I fw \
  -c fw/common.c -o build/common.o
"$CC" --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 \
  -c fw/start.S -o build/start.o
for mode in interactive auto_direct_read auto_direct_write auto_poll_read; do
  src="fw/${mode}.c"
  if [[ "$mode" == "interactive" ]]; then src=fw/interactive_main.c; fi
  "$CC" --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 \
    -Os -ffreestanding -fno-builtin -fno-stack-protector \
    -fdata-sections -ffunction-sections -nostdlib -I fw -c "$src" -o "build/$mode.o"
  "$LD" -m elf32lriscv -T fw/linker.ld --gc-sections \
     -Map="build/$mode.map" build/start.o build/common.o "build/$mode.o" \
     -o "build/$mode.elf"
  "$OBJCOPY" -O binary "build/$mode.elf" "build/$mode.bin"
  python3 scripts/bin_to_hex.py "build/$mode.bin" "firmware/$mode.hex" --ram-kb 32
done

python3 scripts/select_firmware.py interactive
