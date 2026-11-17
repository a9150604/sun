#!/usr/bin/env python3
"""Build a one-shot RV32I hardware self-test with no C or stack accesses.

Output goes directly to the existing blocking UART TX MMIO register. No
RX input, UART-ready conditional loop, or snapshot RAM is involved.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(command):
    result = subprocess.run([str(x) for x in command], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout


def signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def jump_target(pc, word):
    imm = (((word >> 31) << 20) | (((word >> 12) & 255) << 12)
           | (((word >> 20) & 1) << 11) | (((word >> 21) & 1023) << 1))
    return pc + signed(imm, 21)


def branch_target(pc, word):
    imm = (((word >> 31) << 12) | (((word >> 7) & 1) << 11)
           | (((word >> 25) & 63) << 5) | (((word >> 8) & 15) << 1))
    return pc + signed(imm, 13)


def main():
    source = Path(__file__).resolve().parent
    project = source.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", default="riscv64-unknown-elf-")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--build", type=Path)
    args = parser.parse_args()
    output = args.output or project / "firmware/rv32i_hw_selftest.hex"
    build = args.build or project / "build/rv32i_hw_selftest"
    build.mkdir(parents=True, exist_ok=True)
    tools = {name: shutil.which(args.prefix + name)
             for name in ["gcc", "objcopy", "objdump", "nm"]}
    if not all(tools.values()):
        raise SystemExit("Install the bare-metal RISC-V GCC tools or set --prefix")
    elf = build / "rv32i_hw_selftest.elf"
    run([tools["gcc"], "-march=rv32i", "-mabi=ilp32", "-mno-relax",
         "-nostdlib", "-nostartfiles", "-Wl,--no-relax",
         "-Wl,-T," + str(source / "link.ld"),
         "-Wl,-Map=" + str(build / "rv32i_hw_selftest.map"),
         str(source / "selftest.S"), "-o", str(elf)])
    symbol_text = run([tools["nm"], "-n", "--defined-only", str(elf)])
    symbols = {}
    for line in symbol_text.splitlines():
        parts = line.split()
        if len(parts) == 3:
            symbols[parts[2]] = int(parts[0], 16)
    disassembly = run([tools["objdump"], "-d", "-j", ".text", str(elf)])
    (build / "rv32i_hw_selftest.disasm").write_text(disassembly)
    instructions = {}
    for line in disassembly.splitlines():
        match = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]{4,8})\s+(\S+)", line)
        if not match:
            continue
        address, encoded, mnemonic = match.groups()
        if len(encoded) != 8:
            raise SystemExit("Non-32-bit instruction at " + address)
        pc, word = int(address, 16), int(encoded, 16)
        opcode, rd = word & 127, (word >> 7) & 31
        funct3, rs1 = (word >> 12) & 7, (word >> 15) & 31
        if opcode not in {0x03,0x13,0x17,0x23,0x33,0x37,0x63,0x67,0x6f}:
            raise SystemExit(f"Unsupported opcode at {pc:x}: {mnemonic}")
        if opcode in {0x03,0x23} and (funct3 != 2 or rs1 == 2):
            raise SystemExit(f"Non-word or SP-based memory access at {pc:x}")
        if opcode == 0x33 and word >> 25 == 1:
            raise SystemExit(f"M-extension instruction at {pc:x}")
        if opcode not in {0x23,0x63} and rd == 2:
            raise SystemExit(f"Unexpected stack pointer write at {pc:x}")
        if opcode == 0x6f and rd == 1:
            if jump_target(pc, word) != symbols["print_hex"]:
                raise SystemExit(f"Call target is not the leaf formatter at {pc:x}")
            if pc >= symbols["print_hex"]:
                raise SystemExit("Nested call in leaf formatter")
        if opcode == 0x67 and word != 0x00008067:
            raise SystemExit(f"Unexpected indirect control transfer at {pc:x}")
        instructions[pc] = word
    if not instructions or symbols["_start"] != 0:
        raise SystemExit("Invalid reset image")
    protocol = json.loads((source / "expected_protocol.json").read_text())
    for case in protocol["branch_tests"]:
        start = symbols["branch_" + case["label"]]
        target = symbols["take_" + case["label"]]
        word = instructions[start]
        if word & 127 != 0x63 or branch_target(start, word) != target:
            raise SystemExit("Branch target mismatch: " + case["label"])
        case["instruction_address"] = hex(start)
        case["target_address"] = hex(target)
        if "target_offset" in case and target - start != case["target_offset"]:
            raise SystemExit("Long branch displacement changed")
    binary_path = build / "rv32i_hw_selftest.bin"
    run([tools["objcopy"], "-O", "binary", "-j", ".text", "-j", ".rodata",
         str(elf), str(binary_path)])
    binary = binary_path.read_bytes()
    if len(binary) > 0x2000:
        raise SystemExit("Diagnostic code overlaps tested RAM")
    padded = binary + bytes(32768-len(binary))
    image = "".join(f"{int.from_bytes(padded[i:i+4], 'little'):08x}\n"
                    for i in range(0,32768,4)).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    expected = (source / "expected_output.txt").read_bytes()
    if len(expected) != protocol["output_bytes"]:
        raise SystemExit("Expected output metadata mismatch")
    manifest = {
        "output_file": str(output.relative_to(project)) if output.is_relative_to(project) else str(output),
        "output_sha256": digest(image), "ram_bytes": 32768,
        "program_bytes": len(binary), "program_end": hex(symbols["__image_end"]),
        "instructions_audited": len(instructions), "stack_memory_accesses": 0,
        "stack_pointer_writes": 0, "nested_formatter_calls": 0,
        "uart_address": "0x10000004", "uart_write_uses_wrapper_backpressure": True,
        "no_uart_ready_poll_branch": True, "no_input_required": True,
        "output_once_then_halt": True, "halt_address": hex(symbols["halt"]),
        "expected_output_bytes": len(expected), "expected_output_sha256": digest(expected),
        "expected_output_lines": expected.decode().splitlines(),
        "protocol": protocol,
        "sources_sha256": {name:digest((source/name).read_bytes()) for name in
                           ["selftest.S","link.ld","build_selftest.py",
                            "expected_output.txt","expected_protocol.json"]},
        "limitations": "This diagnostic changes code layout and execution timing. "
                       "Correct output does not prove the CLI build or physical hardware is fault-free."
    }
    (source / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"output":str(output),"sha256":manifest["output_sha256"],
                      "program_bytes":len(binary),"instructions":len(instructions),
                      "expected_uart_bytes":len(expected)},indent=2))


if __name__ == "__main__":
    main()
