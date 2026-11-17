#!/usr/bin/env python3
"""Build an isolated one-NOP load/use-gap variant of the pinned HW self-test.

Only the eight formatter LW/SW pairs receive a NOP. Other loads retain their
original spacing. Base firmware, sources, expected output and manifest are
never overwritten. This is a diagnostic discriminator, not a hardware fix.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


BASE_INPUTS = {
    "firmware/rv32i_hw_selftest.hex": "41918e6e02702f892d1773b38c76bd7b82fcc65863f52cc3c528818170e84a2a",
    "diagnostics/rv32i_hw_selftest/selftest.S": "45e9470977547f4a94801f7992c8a1b89e7489b51b91ba747b023ed99d89950e",
    "diagnostics/rv32i_hw_selftest/link.ld": "f0de31473c2141d30bcf34d5e96d037cb2b3007e1d403fd18a493b523d089e14",
    "diagnostics/rv32i_hw_selftest/build_selftest.py": "2a4b36ed00d36efd62ce0e8ef1ecd155781d26c78eba60396cb0e27cfedea013",
    "diagnostics/rv32i_hw_selftest/manifest.json": "f4951dee693025a0db4c7e44d0465f2f960725dacaac7c9b119460b9bc7515b1",
    "diagnostics/rv32i_hw_selftest/expected_output.txt": "cc585ac1609f1f7f46cf93568b24bc95a69214fb20c28cfa0551ecbd1d26cd3c",
    "diagnostics/rv32i_hw_selftest/expected_protocol.json": "a9ca06ada336be7dda9d87998fc31061c97f7bc49b18e4f636b452bf1f0ec5cb",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def words(data):
    return [int.from_bytes(data[i:i+4], "little") for i in range(0, len(data), 4)]


def decode_image(data):
    values = [int(x, 16) for x in data.split()]
    if len(values) != 8192:
        raise SystemExit("Expected exactly 8192 RAM words")
    return b"".join(x.to_bytes(4, "little") for x in values)


def main():
    source = Path(__file__).resolve().parent
    project = source.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", default="riscv64-unknown-elf-")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--build", type=Path)
    args = parser.parse_args()
    output = args.output or project / "firmware/rv32i_hw_selftest_gap1.hex"
    build = args.build or project / "build/rv32i_load_gap"
    if output.resolve() in {(project / name).resolve() for name in BASE_INPUTS}:
        raise SystemExit("Refusing to overwrite a pinned base input")
    build.mkdir(parents=True, exist_ok=True)
    before = {}
    for name, expected_sha in BASE_INPUTS.items():
        data = (project / name).read_bytes()
        if digest(data) != expected_sha:
            raise SystemExit("Base input differs from pinned version: " + name)
        before[name] = data
    base_source = project / "diagnostics/rv32i_hw_selftest"
    assembly = before["diagnostics/rv32i_hw_selftest/selftest.S"].decode()
    marker = "print_hex:\n"
    if assembly.count(marker) != 1:
        raise SystemExit("Unexpected formatter label")
    main_part, formatter = assembly.split(marker)
    pair = "    lw t1, 0(t0)\n    sw t1, 0(s0)\n"
    if formatter.count(pair) != 8 or main_part.count(pair):
        raise SystemExit("Expected exactly eight formatter load/use sites")
    if main_part.count("    li t0, 118\n") != 1:
        raise SystemExit("Unexpected header v character")
    main_part = main_part.replace("    li t0, 118\n", "    li t0, 71\n")
    main_part = main_part.replace("SELFTEST v1", "SELFTEST G1")
    formatter = formatter.replace(pair,
        "    lw t1, 0(t0)\n    nop\n    sw t1, 0(s0)\n")
    changed_source = main_part + marker + formatter
    expected = before["diagnostics/rv32i_hw_selftest/expected_output.txt"]
    if expected.count(b"RV32I HW SELFTEST v1") != 1:
        raise SystemExit("Unexpected base header")
    expected = expected.replace(b"RV32I HW SELFTEST v1", b"RV32I HW SELFTEST G1")
    protocol = before["diagnostics/rv32i_hw_selftest/expected_protocol.json"]
    (source / "expected_output.txt").write_bytes(expected)
    (source / "expected_protocol.json").write_bytes(protocol)
    (build / "selftest_gap1.S").write_text(changed_source)
    with tempfile.TemporaryDirectory(prefix="rv32i-gap1-") as temporary:
        temporary = Path(temporary)
        temp_source = temporary / "project/diagnostics/rv32i_hw_selftest"
        temp_source.mkdir(parents=True)
        (temp_source / "selftest.S").write_text(changed_source)
        for name in ["link.ld", "build_selftest.py"]:
            shutil.copyfile(base_source / name, temp_source / name)
        (temp_source / "expected_output.txt").write_bytes(expected)
        (temp_source / "expected_protocol.json").write_bytes(protocol)
        result = subprocess.run([
            "python3", str(temp_source / "build_selftest.py"),
            "--prefix", args.prefix, "--output", str(output.resolve()),
            "--build", str(build.resolve())], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        generated = json.loads((temp_source / "manifest.json").read_text())
    base_manifest = json.loads(before["diagnostics/rv32i_hw_selftest/manifest.json"])
    if generated["protocol"]["branch_tests"] != base_manifest["protocol"]["branch_tests"]:
        raise SystemExit("Original main branch addresses/targets changed")
    if generated["program_bytes"] != base_manifest["program_bytes"] + 32:
        raise SystemExit("Gap variant grew by more than eight NOP words")
    if generated["program_bytes"] > 0x2000:
        raise SystemExit("Gap variant overlaps tested data")
    base_binary = decode_image(before["firmware/rv32i_hw_selftest.hex"])
    binary = decode_image(output.read_bytes())
    nm = shutil.which(args.prefix + "nm")
    if not nm:
        raise SystemExit("Cannot find nm")
    symbol_text = subprocess.check_output(
        [nm, "-n", "--defined-only", str(build / "rv32i_hw_selftest.elf")], text=True)
    symbols = {parts[2]:int(parts[0], 16) for line in symbol_text.splitlines()
               if len(parts := line.split()) == 3}
    start = symbols["print_hex"]
    original_words = words(base_binary[start:start+49*4])
    variant_words = words(binary[start:start+57*4])
    expected_words = []
    gap_sites = []
    for index, word in enumerate(original_words):
        new_address = start + 4*len(expected_words)
        expected_words.append(word)
        if word == 0x0002a303:  # LW t1,0(t0)
            if index+1 >= len(original_words) or original_words[index+1] != 0x00642023:
                raise SystemExit("Unexpected formatter consumer")
            expected_words.append(0x00000013)
            gap_sites.append({"base_load_pc":hex(start+index*4),
                              "gap_load_pc":hex(new_address),
                              "nop_pc":hex(new_address+4),
                              "gap_consumer_pc":hex(new_address+8)})
    if len(gap_sites) != 8 or expected_words != variant_words:
        raise SystemExit("Compiled formatter is not exactly eight single-NOP gaps")
    main_changes = [hex(i) for i in range(0, start, 4)
                    if base_binary[i:i+4] != binary[i:i+4]]
    if len(main_changes) != 2:
        raise SystemExit("Unexpected main code differences: " + repr(main_changes))
    # The header immediate changes v -> G. The relocated table changes LA s1.
    for name, data in before.items():
        if (project / name).read_bytes() != data:
            raise SystemExit("Base input was altered: " + name)
    manifest = {
        "kind": "targeted formatter load/use-gap diagnostic, not a hardware fix",
        "base_inputs_sha256": BASE_INPUTS,
        "base_inputs_unchanged": True,
        "output_file": str(output.relative_to(project)) if output.is_relative_to(project) else str(output),
        "output_sha256": digest(output.read_bytes()),
        "header": "RV32I HW SELFTEST G1", "inserted_nops": 8,
        "gap_scope": "one NOP after each of eight formatter LW t1,0(t0), before SW t1,0(s0); other loads unchanged",
        "gap_sites": gap_sites, "main_word_changes": main_changes,
        "main_changes_reason": "Header v->G and relocated hex_digits table pointer",
        "main_branch_addresses_unchanged": True,
        "modified_assembly_sha256": digest(changed_source.encode()),
        "expected_output_bytes": len(expected), "expected_output_sha256": digest(expected),
        "sources_sha256": {name:digest((source/name).read_bytes()) for name in
                           ["build_gap.py","expected_output.txt","expected_protocol.json"]},
        "build_audit": generated,
        "limitations": "NOP changes timing and placement. A successful output narrows a load/use dependency issue but does not establish a hardware root cause or repair."
    }
    (source / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"output":str(output),"sha256":manifest["output_sha256"],
                      "program_bytes":generated["program_bytes"],
                      "gap_count":len(gap_sites), "main_word_changes":main_changes,
                      "expected_uart_bytes":len(expected)},indent=2))


if __name__ == "__main__":
    main()
