#!/usr/bin/env python3
"""Check the no-input RV32I hardware self-test through the real UART TX wire.

Requires Verilator 5 --binary --timing and a C++ toolchain. Production RTL
is Git-blob checked and unmodified; the user POR runs at 125 MHz/115200.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


DUT_SOURCES = [
    "rtl/user_design/i2c4_pkg.sv", "rtl/user_design/i2c_master_byte.sv",
    "rtl/user_design/i2c_device_ctrl.sv", "rtl/user_design/axil_i2c4_regs.sv",
    "third_party/picorv32.v", "rtl/soc/native_to_axil_master.v",
    "rtl/soc/uart_tx_mmio.v", "rtl/soc/uart_rx_byte.v",
    "rtl/soc/axil_master_mode_mux.sv", "rtl/soc/axil_owner_switch.v",
    "diagnostics/uart_cpu_trace/picorv32_cpu_axil_uart_diag.v",
    "diagnostics/uart_cpu_trace/pcie_i2c4_top_cpu_diag_fabric.sv",
    "diagnostics/uart_cpu_trace/certus_nx_picorv32_uart_cpu_diag_top.sv",
]
BRANCH_CASES = [
    ("BEQ_ZERO", "beq", 0, 0), ("BNE_ZERO", "bne", 0, 0),
    ("BEQ_TAB", "beq", 9, 9), ("BNE_TAB", "bne", 9, 9),
    ("BEQ_A", "beq", 65, 65), ("BNE_DIFF", "bne", 9, 65),
    ("BLTU_RANGE", "bltu", 33, 94), ("BGEU_RANGE", "bgeu", 94, 33),
    ("BLTU_REVERSE", "bltu", 94, 33), ("BGEU_REVERSE", "bgeu", 33, 94),
    ("BEQ_LONG_ZERO", "beq", 0, 0), ("BNE_LONG_ZERO", "bne", 0, 0),
    ("BNE_LONG_NINE", "bne", 9, 0),
]
RAM_ADDRESSES = [0x3000, 0x3800, 0x6000, 0x7ED0, 0x7F00]
ALIAS_ADDRESSES = [0x2000] + RAM_ADDRESSES
RAM_PATTERNS = [("Z", 0), ("P1", 0x11223344), ("P2", 0xA5C35A96)]


def file_info(path):
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "git_blob_sha1": hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()}


def expected_output():
    # Reconstruct from independent arithmetic and branch comparisons instead
    # of accepting the firmware generator's expected output as an oracle.
    lines = ["RV32I HW SELFTEST v1", "CONST1=13579BDF", "CONST2=5A5AA5A5",
             "S4=00003000", "S5=00003000", "S9=00000009"]
    for register in range(16, 32):
        value = 0xA5000000 | (register << 16) | register
        lines.append(f"X{register}={value:08X}")
    for address in RAM_ADDRESSES:
        for label, value in RAM_PATTERNS:
            lines.append(f"RAM{address:04X}_{label}={value:08X}")
    for address in ALIAS_ADDRESSES:
        lines.append(f"ADDR{address:04X}={0xC3000000 | address:08X}")
    comparisons = {"beq": lambda a, b: a == b, "bne": lambda a, b: a != b,
                   "bltu": lambda a, b: (a & 0xFFFFFFFF) < (b & 0xFFFFFFFF),
                   "bgeu": lambda a, b: (a & 0xFFFFFFFF) >= (b & 0xFFFFFFFF)}
    branches = []
    for label, instruction, left, right in BRANCH_CASES:
        result = "T" if comparisons[instruction](left, right) else "F"
        lines.append(label + "=" + result)
        branches.append(dict(label=label, instruction=instruction,
                             left=left, right=right, expected=result))
    lines.append("END")
    return ("\r\n" + "\r\n".join(lines) + "\r\n").encode(), branches


def main():
    tests = Path(__file__).resolve().parent
    repository = tests.parents[2]
    diagnostic = tests.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=repository)
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    project = args.project.resolve()
    firmware = (args.firmware or project / "firmware/rv32i_hw_selftest.hex").resolve()
    output = (args.output or project / "build/rv32i_hw_selftest/rtl").resolve()
    output.mkdir(parents=True, exist_ok=True)
    pinned = json.loads((repository / "fw/cli_rewrite_v1/tests/"
                         "rxtrace_exact_sources.json").read_text())
    sources = {name: file_info(project / name) for name in DUT_SOURCES}
    for name, info in sources.items():
        if info["git_blob_sha1"] != pinned["git_blob_sha1"][name]:
            raise SystemExit("Source differs from pinned GitHub bytes: " + name)
    expected, branches = expected_output()
    generator_expected = diagnostic / "expected_output.txt"
    if generator_expected.read_bytes() != expected:
        raise SystemExit("Generator expected_output.txt differs from independent RTL test oracle")
    protocol = json.loads((diagnostic / "expected_protocol.json").read_text())
    if len(protocol["branch_tests"]) != len(branches):
        raise SystemExit("Protocol branch count differs from independent oracle")
    for actual, independent in zip(protocol["branch_tests"], branches):
        if any(actual.get(key) != value for key, value in independent.items()):
            raise SystemExit("Protocol branch case differs from independent oracle")
        if "LONG" in independent["label"] and actual.get("target_offset") != 0x278:
            raise SystemExit("Long-branch protocol offset is not 0x278")
    if ([int(x, 0) for x in protocol["ram_addresses"]] != RAM_ADDRESSES or
            [int(x, 0) for x in protocol["address_distinct_addresses"]] != ALIAS_ADDRESSES or
            [int(x, 0) for x in protocol["ram_patterns"]] != [x[1] for x in RAM_PATTERNS] or
            protocol["output_bytes"] != len(expected)):
        raise SystemExit("Protocol RAM values or output size differs from independent oracle")
    bench = tests / "tb_hw_selftest.sv"
    firmware_info, bench_info = file_info(firmware), file_info(bench)
    expected_info = file_info(generator_expected)
    protocol_info = file_info(diagnostic / "expected_protocol.json")
    runner_info = file_info(Path(__file__))
    version = subprocess.check_output([args.verilator, "--version"], text=True).strip()
    command = [args.verilator, "--binary", "--timing", "-Wno-fatal",
               "--top-module", "tb_hw_selftest", "--Mdir", str(output / "obj"),
               "-j", str(args.jobs), "-GCLOCK_HZ=125000000", "-GBAUD=115200",
               "-GFIRMWARE_HEX=" + json.dumps(firmware.as_posix())]
    command += DUT_SOURCES + [str(bench)]
    (output / "expected_uart.log").write_bytes(expected)
    manifest = {
        "result": "pending", "repository": pinned["repository"],
        "source_commit": pinned["source_commit"], "simulator": version,
        "dut_top": "certus_nx_picorv32_uart_cpu_diag_top",
        "clock_hz": 125000000, "baud": 115200, "led_active_low": 1,
        "reset_source": {"type": "user_20bit_por", "hold_clock_edges": 1048575,
                         "por_in_testbench_drives_top_reset_port": True},
        "uart_rx_held_idle": True, "no_extra_output_after_end_ms": 2,
        "source_files": sources, "dut_sources_unmodified": True,
        "firmware": {"path": str(firmware), **firmware_info},
        "testbench": {"path": str(bench), **bench_info},
        "runner": {"path": str(Path(__file__).resolve()), **runner_info},
        "independent_expected_uart_sha256": hashlib.sha256(expected).hexdigest(),
        "compile_command": command,
        "limitations": "RTL wire simulation with ideal clock and supplied POR; "
                        "not the full modified board Top, Radiant netlist, or FPGA startup model.",
    }
    manifest_path = output / "source_manifest.json"

    def save_manifest():
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    save_manifest()
    print("PASS: all 13 DUT Git blobs match " + pinned["source_commit"] +
          "; independent expected UART bytes=" + str(len(expected)), flush=True)
    try:
        with (output / "compile.log").open("w") as log:
            subprocess.run(command, cwd=project, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        uart_log = output / "uart_wire.log"
        with (output / "simulation.log").open("w") as log:
            subprocess.run([str(output / "obj/Vtb_hw_selftest"),
                            "+UART_LOG=" + str(uart_log)], cwd=project,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        data = uart_log.read_bytes()
        if data != expected:
            raise ValueError("Full UART output mismatch; compare uart_wire.log and expected_uart.log")
        for name, info in sources.items():
            if file_info(project / name) != info:
                raise ValueError("Source changed during simulation: " + name)
        if file_info(firmware) != firmware_info or file_info(bench) != bench_info:
            raise ValueError("Firmware or testbench changed during simulation")
        if (file_info(generator_expected) != expected_info or
                file_info(diagnostic / "expected_protocol.json") != protocol_info or
                file_info(Path(__file__)) != runner_info):
            raise ValueError("Test oracle or runner changed during simulation")
        manifest.update(result="PASS", uart_bytes=len(data), rx_data_reads=0,
                        trap=0, overrun=0, uart_sha256=hashlib.sha256(data).hexdigest(),
                        branch_cases=branches)
    except Exception as exc:
        manifest.update(result="FAIL", error=str(exc))
        save_manifest()
        raise SystemExit("RTL test failed: " + str(exc) + "; logs: " + str(output)) from exc
    save_manifest()
    print((output / "simulation.log").read_text(), end="", flush=True)
    print("PASS: entire independently expected UART output, RX=idle/read0, "
          "END followed by 2 ms silence", flush=True)
    print("Firmware SHA256:", firmware_info["sha256"], flush=True)
    print("Source manifest:", manifest_path, flush=True)


if __name__ == "__main__":
    main()
