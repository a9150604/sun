#!/usr/bin/env python3
"""Build the separate OSFP UART CLI page-write variant with RISC-V GCC.

Run with Python 3 on Linux or Windows. The original normal/RXTRACE images are
not changed; this command writes the separate page-write image. Pass --cc and
individual tool options if the tools are not on PATH.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

RAM_BYTES = 32 * 1024
STACK_BYTES = 4096
SOURCE_NAMES = ("start.S", "platform.c", "i2c.c", "main.c")
FLAGS = (
    "-march=rv32i", "-mabi=ilp32", "-mno-relax", "-msmall-data-limit=0",
    "-mno-save-restore", "-mstrict-align", "-Os", "-std=c11",
    "-ffreestanding", "-fno-builtin", "-fno-stack-protector",
    "-fno-strict-aliasing", "-fno-tree-loop-distribute-patterns",
    "-fdata-sections", "-ffunction-sections", "-fno-common",
    "-fno-unwind-tables", "-fno-asynchronous-unwind-tables",
    "-Wall", "-Wextra", "-Werror",
)


def tool_path(explicit, guesses, description):
    candidates = [explicit] if explicit else guesses
    for candidate in candidates:
        if not candidate:
            continue
        found = shutil.which(str(candidate))
        if found:
            return str(Path(found).resolve())
        path = Path(candidate).expanduser()
        if path.is_file():
            return str(path.resolve())
    raise SystemExit(f"Cannot find {description}; install a bare-metal RISC-V GCC toolchain or pass the matching option")


def related_tool(cc, explicit, suffix):
    name = Path(cc).name
    executable = ".exe" if name.lower().endswith(".exe") else ""
    stem = name[:-4] if executable else name
    prefix = stem[:-3] if stem.endswith("gcc") else "riscv64-unknown-elf-"
    guesses = [
        Path(cc).with_name(prefix + suffix + executable),
        prefix + suffix,
        "riscv64-unknown-elf-" + suffix,
        "riscv-none-elf-" + suffix,
    ]
    return tool_path(explicit, guesses, suffix)


def run(command, cwd):
    result = subprocess.run([str(x) for x in command], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(f"Command failed: {Path(str(command[0])).name}")
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def section_sizes(output):
    result = {}
    for line in output.splitlines():
        columns = line.split()
        if len(columns) >= 3 and columns[0].startswith("."):
            try:
                result[columns[0]] = int(columns[1], 10)
            except ValueError:
                pass
    return result


def audit(disassembly):
    """Audit actual emitted instructions, including any linked libgcc code."""
    pattern = re.compile(r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]{4,8})\s+(\S+)")
    allowed = {0x03, 0x0f, 0x13, 0x17, 0x23, 0x33, 0x37, 0x63, 0x67, 0x6f}
    count = 0
    problems = []
    for line in disassembly.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        address, encoded, mnemonic = match.groups()
        count += 1
        instruction = int(encoded, 16)
        opcode = instruction & 0x7f
        funct3 = (instruction >> 12) & 7
        if len(encoded) != 8 or instruction & 3 != 3:
            problems.append(f"0x{address}: compressed/non-32-bit encoding {encoded}")
        elif opcode not in allowed:
            problems.append(f"0x{address}: instruction outside supported RV32I subset: {mnemonic}")
        elif opcode == 0x03 and funct3 != 2:
            problems.append(f"0x{address}: non-word load {mnemonic}")
        elif opcode == 0x23 and funct3 != 2:
            problems.append(f"0x{address}: non-word store {mnemonic}")
        elif opcode == 0x33 and instruction >> 25 == 1:
            problems.append(f"0x{address}: M-extension instruction {mnemonic}")
        elif mnemonic.startswith(("mul", "div", "rem")):
            problems.append(f"0x{address}: M-extension instruction {mnemonic}")
    if count == 0:
        raise SystemExit("Instruction audit found no instructions")
    if problems:
        raise SystemExit("Instruction audit failed:\n" + "\n".join(problems))
    return count


def main():
    source_dir = Path(__file__).resolve().parent
    project = source_dir.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc")
    for name in ("objcopy", "objdump", "nm", "size"):
        parser.add_argument("--" + name)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--hex-output", type=Path)
    parser.add_argument("--rx-trace", action="store_true",
                        help="Build a separate RXTRACE image without replacing the normal CLI HEX")
    args = parser.parse_args()
    cc = tool_path(args.cc, ["riscv64-unknown-elf-gcc", "riscv-none-elf-gcc"],
                   "RISC-V GCC")
    tools = {name: related_tool(cc, getattr(args, name), name)
             for name in ("objcopy", "objdump", "nm", "size")}
    sources = [source_dir / name for name in SOURCE_NAMES]
    for path in sources + [source_dir / "linker.ld"]:
        if not path.is_file():
            raise SystemExit("Missing required source: " + str(path))
    firmware_name = "osfp_cli_rewrite_v1_page_rxtrace" if args.rx_trace else "osfp_cli_rewrite_v1_page"
    flags = (*FLAGS, "-DCLI_RX_TRACE=1") if args.rx_trace else FLAGS
    build_folder = "cli_rewrite_v1_page_rxtrace" if args.rx_trace else "cli_rewrite_v1_page"
    output_dir = (args.output_dir or project / "build" / build_folder).resolve()
    hex_output = (args.hex_output or project / "firmware" / (firmware_name + ".hex")).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    hex_output.parent.mkdir(parents=True, exist_ok=True)

    objects = []
    for source in sources:
        obj = output_dir / (source.stem + ".o")
        run([cc, *flags, "-I", source_dir, "-c", source, "-o", obj], project)
        objects.append(obj)
    stem = output_dir / firmware_name
    elf = stem.with_suffix(".elf")
    binary = stem.with_suffix(".bin")
    map_file = stem.with_suffix(".map")
    disassembly_file = stem.with_suffix(".disasm")
    link_flags = ("-nostdlib", "-Wl,--no-relax", "-Wl,--gc-sections",
                  "-Wl,--build-id=none", "-T", str(source_dir / "linker.ld"),
                  "-Wl,-Map=" + str(map_file))
    run([cc, *flags, *link_flags, *objects, "-lgcc", "-o", elf], project)
    undefined = run([tools["nm"], "-u", elf], project).strip()
    if undefined:
        raise SystemExit("Unresolved firmware symbols:\n" + undefined)
    disassembly = run([tools["objdump"], "-d", "-M", "no-aliases", elf], project)
    instruction_count = audit(disassembly)
    disassembly_file.write_text(disassembly, encoding="utf-8")
    run([tools["objcopy"], "-O", "binary", elf, binary], project)
    payload = binary.read_bytes()
    if len(payload) > RAM_BYTES - STACK_BYTES:
        raise SystemExit("Initialized image overlaps reserved stack")
    image = payload.ljust(RAM_BYTES, b"\0")
    hex_bytes = "".join(
        f"{int.from_bytes(image[pos:pos + 4], 'little'):08x}\n"
        for pos in range(0, RAM_BYTES, 4)
    ).encode("ascii")
    hex_output.write_bytes(hex_bytes)
    sizes = section_sizes(run([tools["size"], "-A", elf], project))
    bss = sizes.get(".bss", 0)
    # The linker independently checks aligned end-of-BSS against this limit.
    if len(payload) + bss > RAM_BYTES - STACK_BYTES:
        raise SystemExit("Initialized image plus BSS overlaps reserved stack")
    source_paths = sorted(
        path for path in source_dir.iterdir()
        if path.suffix in (".c", ".h", ".S", ".ld", ".py")
    )
    manifest = {
        "firmware": firmware_name,
        "architecture": "RV32I",
        "abi": "ilp32",
        "compiler": run([cc, "--version"], project).splitlines()[0],
        "objcopy": run([tools["objcopy"], "--version"], project).splitlines()[0],
        "compiler_flags": list(flags),
        "link_flags": ["-nostdlib", "--no-relax", "--gc-sections", "--build-id=none", "-lgcc"],
        "ram_bytes": RAM_BYTES,
        "reserved_stack_bytes": STACK_BYTES,
        "initialized_image_bytes": len(payload),
        "section_bytes": sizes,
        "text_bytes": sizes.get(".text", 0),
        "rodata_bytes": sizes.get(".rodata", 0),
        "data_bytes": sizes.get(".data", 0),
        "bss_bytes": bss,
        "audited_instruction_count": instruction_count,
        "instruction_audit": {
            "rv32i_only": True, "compressed_instructions": False,
            "m_extension_instructions": False, "byte_halfword_load_stores": False,
        },
        "source_sha256": {path.name: digest(path.read_bytes()) for path in source_paths},
        "elf_sha256": digest(elf.read_bytes()),
        "binary_sha256": digest(payload),
        "ram_image_sha256": digest(image),
        "hex_sha256": digest(hex_bytes),
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("Built", hex_output)
    print(f"RV32I audit: {instruction_count} instructions; no M/C or byte/halfword loads/stores")
    print(f"Code {manifest['text_bytes']} B, constants {manifest['rodata_bytes']} B, "
          f"data {manifest['data_bytes']} B, BSS {bss} B; stack reserve {STACK_BYTES} B")
    print("HEX SHA256:", manifest["hex_sha256"])


if __name__ == "__main__":
    main()
