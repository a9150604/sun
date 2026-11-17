#!/usr/bin/env python3
"""Run unmodified, Git-blob-verified project RTL through Verilator UART wires.

Requires Verilator 5 with --binary --timing and a C++ build toolchain.
Both repository Tops are supported; all DUT source files remain unmodified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


COMMON = [
    "rtl/user_design/i2c4_pkg.sv", "rtl/user_design/i2c_master_byte.sv",
    "rtl/user_design/i2c_device_ctrl.sv", "rtl/user_design/axil_i2c4_regs.sv",
    "third_party/picorv32.v", "rtl/soc/native_to_axil_master.v",
    "rtl/soc/uart_tx_mmio.v", "rtl/soc/uart_rx_byte.v",
    "rtl/soc/axil_master_mode_mux.sv", "rtl/soc/axil_owner_switch.v",
]
TOPS = {
    "standalone": ["rtl/soc/picorv32_cpu_axil_uart.v",
                   "rtl/soc/pcie_i2c4_top_cpu_fabric.sv",
                   "rtl/soc/certus_nx_picorv32_uart_standalone_top.sv"],
    "cpu-diag": ["diagnostics/uart_cpu_trace/picorv32_cpu_axil_uart_diag.v",
                 "diagnostics/uart_cpu_trace/pcie_i2c4_top_cpu_diag_fabric.sv",
                 "diagnostics/uart_cpu_trace/certus_nx_picorv32_uart_cpu_diag_top.sv"],
}


def file_info(path):
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "git_blob_sha1": hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()}


def main():
    tests = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=tests.parents[2])
    parser.add_argument("--top", choices=TOPS, required=True)
    parser.add_argument("--clock-hz", type=int, default=125000000)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--por", action="store_true",
                        help="Use the user-supplied 20-bit power-on reset counter")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    project = args.project.resolve()
    default_group = "exact-user-por" if args.por else "exact"
    output = (args.output or project / "build/cli_rewrite_v1_rxtrace" /
              default_group / args.top).resolve()
    output.mkdir(parents=True, exist_ok=True)
    expected = json.loads((tests / "rxtrace_exact_sources.json").read_text())
    sources = COMMON + TOPS[args.top]
    firmware = "firmware/osfp_cli_rewrite_v1_rxtrace.hex"
    infos = {name: file_info(project / name) for name in sources + [firmware]}
    for name, info in infos.items():
        if info["git_blob_sha1"] != expected["git_blob_sha1"][name]:
            raise SystemExit("Source differs from pinned GitHub bytes: " + name)
    print("PASS: all 13 DUT source Git blobs and HEX match pinned GitHub commit "
          + expected["source_commit"], flush=True)
    bench = tests / "tb_rxtrace_exact.sv"
    bench_info = file_info(bench)
    uart_log = output / "uart_wire.log"
    command = [args.verilator, "--binary", "--timing", "-Wno-fatal",
               "--top-module", "tb_rxtrace_exact", "--Mdir", str(output / "obj"),
               "-j", str(args.jobs), "-GCLOCK_HZ=" + str(args.clock_hz),
               "-GBAUD=" + str(args.baud)]
    if args.top == "cpu-diag":
        command.append("-DTEST_CPU_DIAG")
    if args.por:
        command.append("-DTEST_USER_POR")
    command += sources + [str(bench)]
    version = subprocess.check_output([args.verilator, "--version"], text=True).strip()
    manifest = {
        "repository": expected["repository"],
        "source_commit": expected["source_commit"], "simulator": version,
        "dut_top": "certus_nx_picorv32_uart_cpu_diag_top" if args.top == "cpu-diag"
                   else "certus_nx_picorv32_uart_standalone_top",
        "clock_hz": args.clock_hz, "baud": args.baud, "led_active_low": 1,
        "firmware": firmware, "dut_sources_unmodified": True,
        "reset_source": {
            "type": "user_20bit_por" if args.por else "testbench_external_reset",
            "hold_clock_edges": 1048575 if args.por else 20,
            "por_in_testbench_drives_top_reset_port": args.por,
        },
        "source_files": infos, "testbench": {"file": bench.name, **bench_info},
        "compile_command": command, "result": "pending",
        "limitations": "RTL simulation only; ideal clock, no Radiant netlist/PDC, "
                        "FPGA startup-init verification or gate-level reset glitches. "
                        "User's full modified board Top has not been provided.",
    }
    manifest_path = output / "source_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    with (output / "compile.log").open("w") as log:
        subprocess.run(command, cwd=project, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    with (output / "simulation.log").open("w") as log:
        subprocess.run([str(output / "obj/Vtb_rxtrace_exact"),
                        "+UART_LOG=" + str(uart_log)], cwd=project,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    banner = (b"\r\nOSFP CLI REWRITE v1 RXTRACE\r\n"
              b"One key at a time; RAW is the word read from IO_RX.\r\nosfp> ")
    a = (b"\r\nRXTRACE RAW=00000041 C=00000041 L=00 BAD=0 HW=00000000 DROP=00000000\r\nA")
    enter = (b"\r\nRXTRACE RAW=0000000D C=0000000D L=01 BAD=0 HW=00000000 DROP=00000000"
             b"\r\n\r\nERR unknown command; help\r\nosfp> ")
    if uart_log.read_bytes() != banner + a + enter:
        raise SystemExit("UART output mismatch; inspect " + str(uart_log))
    for name, info in infos.items():
        if file_info(project / name) != info:
            raise SystemExit("Source changed during simulation: " + name)
    if file_info(bench) != bench_info:
        raise SystemExit("Testbench changed during simulation")
    manifest.update(result="PASS", uart_bytes=270,
                    uart_sha256=hashlib.sha256(uart_log.read_bytes()).hexdigest())
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print((output / "simulation.log").read_text(), end="", flush=True)
    print("PASS: unmodified GitHub DUT RTL; A echoed before Enter, CR L=01; "
          + args.top, flush=True)
    print("Source manifest:", manifest_path, flush=True)


if __name__ == "__main__":
    main()
