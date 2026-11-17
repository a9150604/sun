#!/usr/bin/env python3
"""Verify the RXPATH overlay through the repository CPU/SoC and UART wires.

Requires Verilator 5 with --binary --timing and a C++ toolchain. This test
uses the CPU diagnostic Top, 125 MHz, 115200 baud, and the supplied 20-bit POR.
All 13 production RTL inputs are checked against pinned GitHub blob hashes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


DUT_SOURCES = [
    "rtl/user_design/i2c4_pkg.sv",
    "rtl/user_design/i2c_master_byte.sv",
    "rtl/user_design/i2c_device_ctrl.sv",
    "rtl/user_design/axil_i2c4_regs.sv",
    "third_party/picorv32.v",
    "rtl/soc/native_to_axil_master.v",
    "rtl/soc/uart_tx_mmio.v",
    "rtl/soc/uart_rx_byte.v",
    "rtl/soc/axil_master_mode_mux.sv",
    "rtl/soc/axil_owner_switch.v",
    "diagnostics/uart_cpu_trace/picorv32_cpu_axil_uart_diag.v",
    "diagnostics/uart_cpu_trace/pcie_i2c4_top_cpu_diag_fabric.sv",
    "diagnostics/uart_cpu_trace/certus_nx_picorv32_uart_cpu_diag_top.sv",
]
BASE_HEX = "firmware/osfp_cli_rewrite_v1_rxtrace.hex"
PROBE_HEX = "firmware/osfp_cli_rewrite_v1_rxpath_probe.hex"


def file_info(path):
    data = path.read_bytes()
    return {
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "git_blob_sha1": hashlib.sha1(
            b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest(),
    }


def rxtrace(character, length):
    return (f"\r\nRXTRACE RAW={character:08X} C={character:08X} L={length:02X} "
            "BAD=0 HW=00000000 DROP=00000000\r\n").encode()


def rxpath(character, length0, append, echo, lena, length1, buffer1):
    fields = dict(RET=0, CPOST=character, LOAD=1, CLOAD=character,
                  S9=9, S4=0x3000, S5=0x3000, BAD0=0, LEN0=length0,
                  APP=append, ECHO=echo, LENA=lena, LEN1=length1, BUF1=buffer1)
    text = "\r\nRXPATH " + " ".join(f"{k}={v:08X}" for k, v in fields.items()) + "\r\n"
    return text.encode(), fields


def expected_output():
    snapshots = [rxpath(0x41, 0, 1, 0x41, 1, 1, 0x41),
                 rxpath(0x0D, 1, 0, 0, 0, 0, 0x41),
                 rxpath(0x09, 0, 1, 0x09, 1, 1, 0x09),
                 rxpath(0x0D, 1, 0, 0, 0, 0, 0x09)]
    expected = (b"\r\nRXPATH PROBE v1\r\n"
                b"One key at a time; RXPATH follows RXTRACE.\r\n"
                b"\r\nOSFP CLI REWRITE v1 RXTRACE\r\n"
                b"One key at a time; RAW is the word read from IO_RX.\r\nosfp> ")
    expected += rxtrace(0x41, 0) + b"A" + snapshots[0][0]
    expected += (rxtrace(0x0D, 1) + b"\r\nERR unknown command; help\r\nosfp> "
                 + snapshots[1][0])
    expected += rxtrace(0x09, 0) + b"\t" + snapshots[2][0]
    expected += rxtrace(0x0D, 1) + b"\r\nosfp> " + snapshots[3][0]
    return expected, [fields for _, fields in snapshots]


def main():
    tests = Path(__file__).resolve().parent
    repository = tests.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=repository,
                        help="Project root containing the production RTL")
    parser.add_argument("--firmware", type=Path,
                        help="Probe HEX; defaults to <project>/" + PROBE_HEX)
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    project = args.project.resolve()
    firmware = (args.firmware or project / PROBE_HEX).resolve()
    output = (args.output or project / "build/rxpath_probe/rtl").resolve()
    output.mkdir(parents=True, exist_ok=True)
    pinned = json.loads((repository / "fw/cli_rewrite_v1/tests/"
                         "rxtrace_exact_sources.json").read_text())
    source_info = {name: file_info(project / name)
                   for name in DUT_SOURCES + [BASE_HEX]}
    for name, info in source_info.items():
        if info["git_blob_sha1"] != pinned["git_blob_sha1"][name]:
            raise SystemExit("Source differs from pinned GitHub bytes: " + name)
    firmware_info = file_info(firmware)
    bench = tests / "tb_rxpath_probe.sv"
    bench_info = file_info(bench)
    runner_info = file_info(Path(__file__))
    version = subprocess.check_output([args.verilator, "--version"], text=True).strip()
    command = [args.verilator, "--binary", "--timing", "-Wno-fatal",
               "--top-module", "tb_rxpath_probe", "--Mdir", str(output / "obj"),
               "-j", str(args.jobs), "-GCLOCK_HZ=125000000", "-GBAUD=115200",
               "-DTEST_CPU_DIAG", "-DTEST_USER_POR",
               "-GFIRMWARE_HEX=" + json.dumps(firmware.as_posix())]
    command += DUT_SOURCES + [str(bench)]
    expected, expected_snapshots = expected_output()
    (output / "expected_uart.log").write_bytes(expected)
    manifest = {
        "result": "pending", "repository": pinned["repository"],
        "source_commit": pinned["source_commit"], "simulator": version,
        "dut_top": "certus_nx_picorv32_uart_cpu_diag_top",
        "clock_hz": 125000000, "baud": 115200, "led_active_low": 1,
        "reset_source": {"type": "user_20bit_por", "hold_clock_edges": 1048575,
                         "por_in_testbench_drives_top_reset_port": True},
        "input_hex": ["41", "0D", "09", "0D"],
        "source_files": source_info, "dut_sources_unmodified": True,
        "firmware": {"path": str(firmware), **firmware_info},
        "testbench": {"path": str(bench), **bench_info},
        "runner": {"path": str(Path(__file__).resolve()), **runner_info},
        "compile_command": command,
        "limitations": "RTL wire simulation with ideal clock and supplied POR; "
                        "not the full modified board Top, Radiant netlist, or FPGA startup model.",
    }
    manifest_path = output / "source_manifest.json"

    def save_manifest():
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    save_manifest()
    print("PASS: all 13 DUT Git blobs and base HEX match " + pinned["source_commit"],
          flush=True)
    try:
        with (output / "compile.log").open("w") as log:
            subprocess.run(command, cwd=project, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        uart_log = output / "uart_wire.log"
        with (output / "simulation.log").open("w") as log:
            subprocess.run([str(output / "obj/Vtb_rxpath_probe"),
                            "+UART_LOG=" + str(uart_log)], cwd=project,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        data = uart_log.read_bytes()
        lines = [line for line in data.splitlines() if line.startswith(b"RXPATH RET=")]
        actual_snapshots = [{k.decode(): int(v, 16)
                             for k, v in re.findall(rb"([A-Z0-9]+)=([0-9A-F]+)", line)}
                            for line in lines]
        if actual_snapshots != expected_snapshots:
            raise ValueError("RXPATH snapshot mismatch: " + repr(actual_snapshots))
        if data != expected:
            raise ValueError("Full UART output mismatch; compare uart_wire.log and expected_uart.log")
        for name, info in source_info.items():
            if file_info(project / name) != info:
                raise ValueError("Source changed during simulation: " + name)
        if file_info(firmware) != firmware_info or file_info(bench) != bench_info:
            raise ValueError("Firmware or testbench changed during simulation")
        if file_info(Path(__file__)) != runner_info:
            raise ValueError("Runner changed during simulation")
        manifest.update(result="PASS", uart_bytes=len(data),
                        uart_sha256=hashlib.sha256(data).hexdigest(),
                        observed_snapshots=actual_snapshots, base_firmware_unchanged=True)
    except Exception as exc:
        manifest.update(result="FAIL", error=str(exc))
        save_manifest()
        raise SystemExit("RTL test failed: " + str(exc) + "; logs: " + str(output)) from exc
    save_manifest()
    print((output / "simulation.log").read_text(), end="", flush=True)
    print("PASS: all 1286 UART wire bytes and four 14-field RXPATH snapshots", flush=True)
    print("Probe HEX SHA256:", firmware_info["sha256"], flush=True)
    print("Source manifest:", manifest_path, flush=True)


if __name__ == "__main__":
    main()
