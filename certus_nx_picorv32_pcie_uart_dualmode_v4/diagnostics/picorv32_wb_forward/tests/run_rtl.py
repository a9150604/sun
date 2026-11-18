#!/usr/bin/env python3
"""Regress the project-specific writeback-forwarding candidate on UART wires.

Requires Python 3, Verilator 5 (--binary --timing), make and a C++ compiler.
All four tests use 125 MHz, 115200 baud and the user's 20-bit POR. The
synthetic synchronous/read-first RF fixture is created only below --output;
it is a fault-injection experiment, not a source for FPGA synthesis.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess


CANDIDATE_SHA256 = "c51201ed368df602fb1c2499795ad5eef12c335abb05c11b7f24bd9437b5943d"
FAULT_SHA256 = "e68cf974cf4caf88e43ed0d17361fd0ff6233a58ea42f0ae58f014a3a8ef3aaf"
COMMON = [
    "rtl/user_design/i2c4_pkg.sv", "rtl/user_design/i2c_master_byte.sv",
    "rtl/user_design/i2c_device_ctrl.sv", "rtl/user_design/axil_i2c4_regs.sv",
    "rtl/soc/native_to_axil_master.v", "rtl/soc/uart_tx_mmio.v",
    "rtl/soc/uart_rx_byte.v", "rtl/soc/axil_master_mode_mux.sv",
    "rtl/soc/axil_owner_switch.v",
]
DIAG = [
    "diagnostics/uart_cpu_trace/picorv32_cpu_axil_uart_diag.v",
    "diagnostics/uart_cpu_trace/pcie_i2c4_top_cpu_diag_fabric.sv",
    "diagnostics/uart_cpu_trace/certus_nx_picorv32_uart_cpu_diag_top.sv",
]
PRODUCTION = [
    "rtl/soc/picorv32_cpu_axil_uart.v",
    "rtl/soc/pcie_i2c4_top_cpu_fabric.sv",
    "rtl/soc/certus_nx_picorv32_uart_standalone_top.sv",
]
PINNED_INPUTS = {
    "firmware/rv32i_hw_selftest.hex": "41918e6e02702f892d1773b38c76bd7b82fcc65863f52cc3c528818170e84a2a",
    "firmware/osfp_cli_rewrite_v1.hex": "1030f723833afa74bd3a38060cbb333d14be42d2bf75e04c4a767fcb576cae4e",
    "diagnostics/rv32i_hw_selftest/tests/tb_hw_selftest.sv": "f22b42dd9431d0a7f79f8988f8bac5a31e92f3ffa5246b886857185bdfd87b7c",
    "fw/cli_rewrite_v1/tests/tb_cli_rewrite.sv": "afb0f9410f5c5a4bc08a1745628d35421e99c7d1e66e1c8dac776290a9cafd54",
}


def file_info(path):
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "git_blob_sha1": hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()}


def selftest_expected():
    # Independent arithmetic/branch oracle, matching the existing selftest test.
    lines = ["RV32I HW SELFTEST v1", "CONST1=13579BDF", "CONST2=5A5AA5A5",
             "S4=00003000", "S5=00003000", "S9=00000009"]
    lines += [f"X{r}={0xA5000000 | (r << 16) | r:08X}" for r in range(16, 32)]
    addresses = [0x3000, 0x3800, 0x6000, 0x7ED0, 0x7F00]
    for address in addresses:
        for label, value in [("Z", 0), ("P1", 0x11223344), ("P2", 0xA5C35A96)]:
            lines.append(f"RAM{address:04X}_{label}={value:08X}")
    lines += [f"ADDR{a:04X}={0xC3000000 | a:08X}" for a in [0x2000] + addresses]
    comparisons = [("BEQ_ZERO", 0 == 0), ("BNE_ZERO", 0 != 0),
                   ("BEQ_TAB", 9 == 9), ("BNE_TAB", 9 != 9),
                   ("BEQ_A", 65 == 65), ("BNE_DIFF", 9 != 65),
                   ("BLTU_RANGE", 33 < 94), ("BGEU_RANGE", 94 >= 33),
                   ("BLTU_REVERSE", 94 < 33), ("BGEU_REVERSE", 33 >= 94),
                   ("BEQ_LONG_ZERO", 0 == 0), ("BNE_LONG_ZERO", 0 != 0),
                   ("BNE_LONG_NINE", 9 != 0)]
    lines += [label + "=" + ("T" if result else "F") for label, result in comparisons]
    return ("\r\n" + "\r\n".join(lines + ["END"]) + "\r\n").encode()


def cli_expected():
    status = ("owner_cpu=1 ch=0 dev=0x50 reg=0x00 data=0x00 writes_unlocked=0 irq=0x0\r\n"
              "clock_hz=0x07735940 timeout_ms=0x000001F4 poll_gap=0x03E8\r\n")
    result = ("\r\nOSFP CLI REWRITE v1 (RV32I WORD IO)\r\n"
              "Type help for commands. Numbers are hex; delay is decimal ms.\r\n"
              "osfp> A\r\nERR unknown command; help\r\nosfp> status\r\n" + status +
              "rx_bytes=0x00000009 hardware_overruns=0x00000000 queue_drops=0x00000000\r\n"
              "osfp> \r\nosfp> \r\nosfp> stax\x08 \x08tus\r\n" + status +
              "rx_bytes=0x00000015 hardware_overruns=0x00000000 queue_drops=0x00000000\r\n"
              "osfp> locx\x08 \x08k\r\nOK writes locked\r\nosfp> ")
    return result.encode()


def verify_cli_por_copy(original, adapted):
    """Reject accidental edits outside the copied bench's reset generator."""
    expected = original.read_text().replace(
        "// Integration check: original standalone SoC + a separately supplied PicoRV32.",
        "// Copied CLI integration bench; only reset changes to the user 20-bit POR.\n"
        "// Original standalone SoC + a separately supplied PicoRV32.")
    expected = expected.replace("  reg resetn=0;\n", """  // Same 20-bit power-on reset counter as the user's board Top.
  reg [19:0] por_cnt=20'd0;
  wire resetn=&por_cnt;
  always @(posedge clk) begin
    if(!resetn) por_cnt<=por_cnt+1'b1;
  end
  integer por_clock_edges=0;
  always @(posedge clk)
    if(!resetn) por_clock_edges=por_clock_edges+1;
""")
    expected = expected.replace("    repeat(20) @(negedge clk);\n    resetn=1;\n", """    #1;
    if(resetn!==0 || por_cnt!==0) $fatal(1,"POR initial state incorrect");
    @(posedge resetn);
    if(por_clock_edges!=1048575 || por_cnt!==20'hfffff)
      $fatal(1,"POR release state/count incorrect");
    $display("PASS: user POR released after %0d clock edges",por_clock_edges);
""")
    if adapted.read_text() != expected:
        raise ValueError("CLI POR bench differs beyond the documented reset adaptation")


def make_fault_fixture(candidate, destination, output):
    """Synthetic RF latency/read-first fault; never a deployable core."""
    if not destination.resolve().is_relative_to(output):
        raise ValueError("Fault fixture destination must be below the build output")
    if destination.name in {"picorv32.v", "picorv32_wb_forward.v"}:
        raise ValueError("Refusing to overwrite a deployable core filename")
    source = candidate.read_text()
    anchor = ("\talways @* begin\n\t\tdecoded_rs = 'bx;\n"
              "\t\tif (ENABLE_REGS_DUALPORT) begin\n`ifndef RISCV_FORMAL_BLACKBOX_REGS\n")
    injection = """\t// INTENTIONAL TEST FIXTURE, not the project candidate implementation.
\treg [31:0] fault_rf_q1, fault_rf_q2;
\talways @(posedge clk) begin
\t\tfault_rf_q1 <= decoded_rs1 ? cpuregs[decoded_rs1] : 0;
\t\tfault_rf_q2 <= decoded_rs2 ? cpuregs[decoded_rs2] : 0;
\tend
"""
    replacements = [(anchor, injection + anchor),
                    ("cpuregs_rs1 = decoded_rs1 ? cpuregs[decoded_rs1] : 0;",
                     "cpuregs_rs1 = decoded_rs1 ? fault_rf_q1 : 0;"),
                    ("cpuregs_rs2 = decoded_rs2 ? cpuregs[decoded_rs2] : 0;",
                     "cpuregs_rs2 = decoded_rs2 ? fault_rf_q2 : 0;")]
    for before, after in replacements:
        if source.count(before) != 1:
            raise ValueError("Fault injection anchor is not unique")
        source = source.replace(before, after)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(source)
    if file_info(destination)["sha256"] != FAULT_SHA256:
        raise ValueError("Synthetic fault fixture hash differs from reviewed experiment")


def main():
    tests = Path(__file__).resolve().parent
    release_project = tests.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=release_project,
                        help="checkout containing the pinned original RTL")
    parser.add_argument("--candidate", type=Path,
                        default=tests.parent / "picorv32_wb_forward.v")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--jobs", type=int, default=2, help="make jobs per compile")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    project, candidate = args.project.resolve(), args.candidate.resolve()
    output = (args.output or release_project / "build/picorv32_wb_forward/rtl").resolve()
    # Sources and released test inputs are read-only; generated RTL stays in build.
    protected = {project, release_project, tests.parent.resolve(), candidate.parent}
    protected.update((base / name).resolve() for base in (project, release_project)
                     for name in ["rtl", "firmware", "fw", "third_party", "diagnostics"])
    if output in protected or any(path.is_relative_to(output) for path in protected):
        parser.error("--output would contain/overwrite protected project inputs")
    if output.is_relative_to(tests.parent.resolve()):
        parser.error("--output must not be inside the released candidate directory")
    output.mkdir(parents=True, exist_ok=True)
    pinned_path = release_project / "fw/cli_rewrite_v1/tests/rxtrace_exact_sources.json"
    pinned = json.loads(pinned_path.read_text())
    tracked = {path: file_info(path) for path in [candidate, Path(__file__).resolve(), pinned_path]}
    if tracked[candidate]["sha256"] != CANDIDATE_SHA256:
        raise SystemExit("Candidate differs from the reviewed release SHA256")
    source_files = {}
    for name in dict.fromkeys(COMMON + DIAG + PRODUCTION):
        path = project / name
        info = file_info(path)
        if info["git_blob_sha1"] != pinned["git_blob_sha1"][name]:
            raise SystemExit("Source differs from pinned GitHub bytes: " + name)
        source_files[name] = info
        tracked[path] = info
    for name, sha256 in PINNED_INPUTS.items():
        path = release_project / name
        tracked[path] = file_info(path)
        if tracked[path]["sha256"] != sha256:
            raise SystemExit("Firmware/testbench differs from reviewed input: " + name)
    cli_bench = tests / "tb_cli_rewrite_por.sv"
    verify_cli_por_copy(release_project / "fw/cli_rewrite_v1/tests/tb_cli_rewrite.sv", cli_bench)
    tracked[cli_bench] = file_info(cli_bench)
    expected = {"selftest": selftest_expected(), "cli": cli_expected()}
    expected_hashes = {"selftest": "cc585ac1609f1f7f46cf93568b24bc95a69214fb20c28cfa0551ecbd1d26cd3c",
                       "cli": "8a06aa548ff6d224cc7d015e8559190a96ec4a63fba845dafb2deb5e421af80d"}
    for kind, data in expected.items():
        if hashlib.sha256(data).hexdigest() != expected_hashes[kind]:
            raise SystemExit("Independent expected UART oracle hash changed: " + kind)
    fault = output / "sync-read-fault/picorv32_wb_forward_fault_fixture.v"
    make_fault_fixture(candidate, fault, output)
    version = subprocess.check_output([args.verilator, "--version"], text=True).strip()
    manifest = {
        "result": "pending", "repository": pinned["repository"],
        "original_source_commit": pinned["source_commit"], "simulator": version,
        "clock_hz": 125000000, "baud": 115200, "led_active_low": 1,
        "reset_source": {"type": "user_20bit_por", "hold_clock_edges": 1048575,
                         "por_in_testbench_drives_top_reset_port": True},
        "source_files": source_files,
        "candidate": {"path": str(candidate), **tracked[candidate]},
        "synthetic_fault_fixture": {"path": str(fault), **file_info(fault),
                                    "for_simulation_only": True},
        "inputs": {str(p): info for p, info in tracked.items()},
        "limitations": "RTL simulation with ideal clock/POR; not Radiant synthesis, "
                       "placement/routing, SDF timing simulation, actual RF mapping, "
                       "or proof of the board's root cause.",
    }
    summary_path = output / "regression_results.json"
    summary_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("PASS: original DUT Git blobs and candidate/firmware SHA256 pins", flush=True)

    def test(profile, kind):
        work = output / profile / kind
        work.mkdir(parents=True, exist_ok=True)
        core = candidate if profile == "normal" else fault
        top = "tb_hw_selftest" if kind == "selftest" else "tb_cli_rewrite"
        bench = (release_project / "diagnostics/rv32i_hw_selftest/tests/tb_hw_selftest.sv"
                 if kind == "selftest" else cli_bench)
        firmware = release_project / ("firmware/rv32i_hw_selftest.hex" if kind == "selftest"
                                      else "firmware/osfp_cli_rewrite_v1.hex")
        tail = DIAG if kind == "selftest" else PRODUCTION
        command = [args.verilator, "--binary", "--timing", "-Wno-fatal",
                   "--top-module", top, "--Mdir", str(work / "obj"), "-j", str(args.jobs),
                   "-GBAUD=115200", "-GFIRMWARE_HEX=" + json.dumps(firmware.as_posix())]
        if kind == "selftest":
            command.append("-GCLOCK_HZ=125000000")
        command += [str(project / name) for name in COMMON]
        command += [str(core)] + [str(project / name) for name in tail] + [str(bench)]
        result = {"profile": profile, "test": kind, "result": "pending",
                  "core": {"path": str(core), **file_info(core)},
                  "original_dut_files_unmodified": True,
                  "core_is_synthetic_fault_fixture": profile != "normal",
                  "dut_source_count_including_candidate": 13, "compile_command": command}
        (work / "expected_uart.log").write_bytes(expected[kind])
        try:
            with (work / "compile.log").open("w") as log:
                subprocess.run(command, cwd=project, stdout=log,
                               stderr=subprocess.STDOUT, check=True)
            uart_log = work / "uart_wire.log"
            with (work / "simulation.log").open("w") as log:
                subprocess.run([str(work / ("obj/V" + top)), "+UART_LOG=" + str(uart_log)],
                               cwd=project, stdout=log, stderr=subprocess.STDOUT, check=True)
            data = uart_log.read_bytes()
            if data != expected[kind]:
                raise ValueError("Exact UART bytes differ; compare uart_wire.log and expected_uart.log")
            simulation_log = (work / "simulation.log").read_text()
            if "PASS: user POR released after 1048575 clock edges" not in simulation_log:
                raise ValueError("User POR release check missing")
            if kind == "selftest":
                if "no extra output for 2 ms, trap=0 overrun=0 RX=0 TX=928" not in simulation_log:
                    raise ValueError("END/quiet/RX-idle checks missing")
            else:
                if (data.count(b"osfp> ") != 7 or
                        "RX=28 trap=0 overrun=0" not in simulation_log or
                        "PASS: single A echoes on UART wire before Enter" not in simulation_log):
                    raise ValueError("CLI A echo, prompts or RX count check missing")
            result.update(result="PASS", uart_bytes=len(data),
                          uart_sha256=hashlib.sha256(data).hexdigest())
        except Exception as exc:
            result.update(result="FAIL", error=str(exc))
        (work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(f"{result['result']}: {profile} {kind}" +
              (f" UART={result['uart_bytes']} bytes" if result["result"] == "PASS"
               else ": " + result["error"]), flush=True)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(test, profile, kind)
                   for profile in ["normal", "sync-read-fault"]
                   for kind in ["selftest", "cli"]]
        results = [future.result() for future in futures]
    changed = [str(path) for path, info in tracked.items() if file_info(path) != info]
    manifest.update(result="PASS" if not changed and all(r["result"] == "PASS" for r in results)
                    else "FAIL", results=results, changed_inputs=changed)
    summary_path.write_text(json.dumps(manifest, indent=2) + "\n")
    if manifest["result"] != "PASS":
        raise SystemExit("Regression failed; inspect " + str(summary_path))
    print("PASS: four exact UART regressions; firmware and original RTL unchanged", flush=True)
    print("Results: " + str(summary_path), flush=True)


if __name__ == "__main__":
    main()
