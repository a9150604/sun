#!/usr/bin/env python3
"""Overlay observation wrappers onto the NEW rewritten RXTRACE firmware only.

Four original callsites are redirected. A fifth hook captures the original
character-load result and replays the replaced LI instruction. All original
handler branch instructions, data, and addresses remain unchanged. The added
wrappers alter stack activity and execution time; this is a diagnostic image.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

BASE_SHA256 = "f82ebb0509444b118f8793b3f7b6b8821403df9c9cdb08faee2f7cdc3dc23697"
PROBE_START = 0x4000
SCRATCH_START = 0x6000
SCRATCH_BYTES = 60
PATCHES = {
    "init": (0x1408, (0xfffff097, 0x1a4080e7)),
    "poll": (0x14c8, (0xfffff097, 0xbe4080e7)),
    "check": (0x15e0, (0x00000097, 0xc68080e7)),
    "load": (0x15f0, (0x00d00713,)),
    "append": (0x2578, (0xffffe097, 0xe34080e7)),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(command):
    result = subprocess.run([str(x) for x in command],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout


def audit(disassembly):
    count = 0
    for line in disassembly.splitlines():
        match = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]{4,8})\s+(\S+)", line)
        if not match:
            continue
        address, encoded, mnemonic = match.groups()
        if len(encoded) != 8:
            raise SystemExit(f"Non-32-bit instruction at {address}: {mnemonic}")
        word = int(encoded, 16)
        opcode, funct3 = word & 127, (word >> 12) & 7
        if word & 3 != 3 or opcode not in {0x03,0x13,0x17,0x23,0x33,0x37,0x63,0x67,0x6f}:
            raise SystemExit(f"Unsupported instruction at {address}: {mnemonic}")
        if opcode in {0x03,0x23} and funct3 != 2:
            raise SystemExit(f"Non-word memory transfer at {address}: {mnemonic}")
        if opcode == 0x33 and word >> 25 == 1:
            raise SystemExit(f"M-extension instruction at {address}")
        count += 1
    if not count:
        raise SystemExit("No emitted instructions audited")
    return count


def main():
    source = Path(__file__).resolve().parent
    project = source.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", default="riscv64-unknown-elf-")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--build", type=Path)
    args = parser.parse_args()
    base_path = project / "firmware/osfp_cli_rewrite_v1_rxtrace.hex"
    output = args.output or project / "firmware/osfp_cli_rewrite_v1_rxpath_probe.hex"
    build = args.build or project / "build/rxpath_probe"
    build.mkdir(parents=True, exist_ok=True)
    base_text = base_path.read_bytes()
    if digest(base_text) != BASE_SHA256:
        raise SystemExit("Base RXTRACE image differs from pinned image; refusing to patch")
    words = [int(word, 16) for word in base_text.split()]
    if len(words) != 8192:
        raise SystemExit("Expected exactly 8192 little-endian RAM words")
    original = b"".join(word.to_bytes(4, "little") for word in words)
    for name, (address, expected) in PATCHES.items():
        if tuple(words[address//4:address//4+len(expected)]) != expected:
            raise SystemExit("Unexpected original callsite: " + name)
    tools = {}
    for tool in ["gcc", "objcopy", "objdump", "nm"]:
        tools[tool] = shutil.which(args.prefix + tool)
        if not tools[tool]:
            raise SystemExit("Missing tool: " + args.prefix + tool)
    patch_asm = build / "patches.S"
    patch_asm.write_text(".option norvc\n.option norelax\n" + "".join(
        f'.section .patch_{name},"ax",@progbits\n' +
        (f'j probe_{name}\n' if name == "load" else f'call probe_{name}\n')
        for name in PATCHES))
    elf = build / "rxpath_probe.elf"
    run([tools["gcc"], "-march=rv32i", "-mabi=ilp32", "-mno-relax",
         "-nostdlib", "-nostartfiles", "-Wl,--no-relax", "-Wl,-T," + str(source / "probe.ld"),
         "-Wl,-Map=" + str(build / "rxpath_probe.map"),
         str(source / "rxpath_probe.S"), str(patch_asm), "-o", str(elf)])
    disassembly = run([tools["objdump"], "-d", "-j", ".text", str(elf)])
    (build / "rxpath_probe.disasm").write_text(disassembly)
    audited = audit(disassembly)
    blob_path = build / "rxpath_probe.bin"
    run([tools["objcopy"], "-O", "binary", "-j", ".text", "-j", ".rodata", str(elf), str(blob_path)])
    blob = blob_path.read_bytes()
    if PROBE_START + len(blob) > SCRATCH_START:
        raise SystemExit("Overlay reaches snapshot memory")
    if any(original[PROBE_START:PROBE_START+len(blob)]):
        raise SystemExit("Probe region is not unused zero padding")
    if any(original[SCRATCH_START:SCRATCH_START+SCRATCH_BYTES]):
        raise SystemExit("Scratch region is not unused zero padding")
    changed = bytearray(original)
    changed[PROBE_START:PROBE_START+len(blob)] = blob
    patch_info = {}
    allowed = set(range(PROBE_START, PROBE_START+len(blob)))
    for name, (address, expected) in PATCHES.items():
        part = build / ("patch_" + name + ".bin")
        run([tools["objcopy"], "--dump-section", ".patch_" + name + "=" + str(part), str(elf)])
        patch = part.read_bytes()
        if len(patch) != len(expected)*4:
            raise SystemExit("Callsite patch has unexpected length: " + name)
        patched_words = [int.from_bytes(patch[k:k+4], "little") for k in range(0,len(patch),4)]
        if name == "load":
            if patched_words[0] & 0xfff != 0x06f:
                raise SystemExit("Load hook is not JAL x0")
        elif patched_words[0] & 0xfff != 0x097 or patched_words[1] & 0xfffff != 0x080e7:
            raise SystemExit("Callsite patch is not AUIPC ra/JALR ra: " + name)
        changed[address:address+len(patch)] = patch
        allowed.update(range(address,address+len(patch)))
        patch_info[name] = {"address": hex(address), "original_words": [f"{x:08x}" for x in expected],
                            "overlay_words": [f"{word:08x}" for word in patched_words]}
    actual_changes = [i for i, (a,b) in enumerate(zip(original,changed)) if a != b]
    if any(i not in allowed for i in actual_changes):
        raise SystemExit("Overlay changed an unapproved byte")
    image = "".join(f"{int.from_bytes(changed[k:k+4],'little'):08x}\n" for k in range(0,len(changed),4)).encode()
    if base_path.read_bytes() != base_text:
        raise SystemExit("Base image changed during build")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    manifest = {
        "base_file": str(base_path.relative_to(project)), "base_sha256": BASE_SHA256,
        "output_file": str(output.relative_to(project)) if output.is_relative_to(project) else str(output),
        "output_sha256": digest(image), "ram_bytes": len(changed),
        "probe_start": hex(PROBE_START), "probe_bytes": len(blob),
        "snapshot_address": hex(SCRATCH_START), "snapshot_bytes": SCRATCH_BYTES,
        "original_bss_end": "0x3108", "reserved_stack_start": "0x7000", "stack_top": "0x8000",
        "patches": patch_info, "changed_bytes": len(actual_changes),
        "all_other_original_bytes_preserved": True, "rv32i_word_only_instructions_audited": audited,
        "sources_sha256": {name:digest((source/name).read_bytes()) for name in ["rxpath_probe.S","probe.ld","build_probe.py"]},
        "snapshot_offsets": {"pending":0,"RET":4,"CPOST":8,"S9":12,"S4":16,"S5":20,
                             "BAD0":24,"LEN0":28,"APP":32,"ECHO":36,"LENA":40,"LEN1":44,"BUF1":48,
                             "LOAD":52,"CLOAD":56},
        "limitations": "Instrumentation adds stack traffic, RAM transactions and execution time. "
                       "CPOST is a wrapper read before the original reload; CLOAD records the original load result. "
                       "ECHO is a call argument, not TX acknowledgement."
    }
    (source / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"output":str(output),"sha256":manifest["output_sha256"],
                      "probe_bytes":len(blob),"audited_instructions":audited},indent=2))


if __name__ == "__main__":
    main()
