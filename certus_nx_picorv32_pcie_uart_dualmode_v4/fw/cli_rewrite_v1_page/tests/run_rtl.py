#!/usr/bin/env python3
"""Validate page writes through real UART, CPU, AXI and original I2C RTL.

The slave is an ideal non-stretching open-drain fixture, not an OSFP model or
the user's placed-and-routed netlist. All expected register contents are test
values. Original DUT files, the validated CPU candidate and firmware are pinned.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

PROJECT = Path(__file__).resolve().parents[3]
COMMON = [
    "rtl/user_design/i2c4_pkg.sv", "rtl/user_design/i2c_master_byte.sv",
    "rtl/user_design/i2c_device_ctrl.sv", "rtl/user_design/axil_i2c4_regs.sv",
    "rtl/soc/native_to_axil_master.v", "rtl/soc/uart_tx_mmio.v",
    "rtl/soc/uart_rx_byte.v", "rtl/soc/axil_master_mode_mux.sv",
    "rtl/soc/axil_owner_switch.v", "rtl/soc/picorv32_cpu_axil_uart.v",
    "rtl/soc/pcie_i2c4_top_cpu_fabric.sv",
    "rtl/soc/certus_nx_picorv32_uart_standalone_top.sv",
]
CORE_SHA = "c51201ed368df602fb1c2499795ad5eef12c335abb05c11b7f24bd9437b5943d"
HEX_SHA = "dd0eb3e29d697bd80e344a72bd0000bb8050a3066b04f160b212ae64d02546fb"


def metadata(path):
    raw = path.read_bytes()
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
            "git_blob_sha1": hashlib.sha1(b"blob " + str(len(raw)).encode()
                                         + b"\0" + raw).hexdigest()}


def expected_uart():
    unknown_selector = "ERR bank/page register: use plain write, not writeverify\r\n"
    locked = "ERR writes locked; type unlock first\r\n"
    def read(reg, value):
        return f"READ ch=0 reg=0x{reg:02X} value=0x{value:02X} rc=0x00\r\n"
    def write(reg, value):
        return f"WRITE reg=0x{reg:02X} data=0x{value:02X} rc=0x00\r\n"
    commands = [
        ("write 7F 01", locked), ("unlock", "OK writes unlocked\r\n"),
        ("read 80", read(0x80, 0x11)), ("write 7F 01", write(0x7f, 1)),
        ("read 7F", read(0x7f, 1)), ("read 80", read(0x80, 0xa5)),
        ("read 81", read(0x81, 0x5a)), ("read 00", read(0, 0x19)),
        ("writeverify 7F 00", unknown_selector),
        ("writeverify 7E 00", unknown_selector),
        ("write 7F 00", write(0x7f, 0)), ("read 80", read(0x80, 0x11)),
        ("lock", "OK writes locked\r\n"), ("write 7F 01", locked),
        ("read 7F", read(0x7f, 0)),
    ]
    text = ("\r\nOSFP CLI REWRITE v1 PAGE WRITE (RV32I WORD IO)\r\n"
            "Type help for commands. Numbers are hex; delay is decimal ms.\r\nosfp> ")
    for command, response in commands:
        text += command + "\r\n" + response + "osfp> "
    return text.encode("ascii"), commands


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=PROJECT,
                        help="DUT checkout; every source must match published Git blobs")
    parser.add_argument("--core", type=Path, default=PROJECT / "diagnostics/picorv32_wb_forward/picorv32_wb_forward.v")
    parser.add_argument("--hex", type=Path, dest="hex_image", default=PROJECT / "firmware/osfp_cli_rewrite_v1_page.hex")
    parser.add_argument("--build-dir", type=Path, default=PROJECT / "build/cli_rewrite_v1_page_rtl")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    project, core, firmware = args.project.resolve(), args.core.resolve(), args.hex_image.resolve()
    output = args.build_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    bench = Path(__file__).with_name("tb_page_write.sv")
    pins_path = PROJECT / "diagnostics/picorv32_wb_forward/results/regression_results.json"
    pins = json.loads(pins_path.read_text())["source_files"]
    sources = {name: metadata(project / name) for name in COMMON}
    for name, info in sources.items():
        if info["git_blob_sha1"] != pins[name]["git_blob_sha1"]:
            raise SystemExit("Original DUT differs from validated source: " + name)
    if metadata(core)["sha256"] != CORE_SHA or metadata(firmware)["sha256"] != HEX_SHA:
        raise SystemExit("Core or firmware hash does not match release")
    inputs = [project / name for name in COMMON] + [core, firmware, bench, Path(__file__), pins_path]
    before = {str(path): metadata(path) for path in inputs}
    found = shutil.which(args.verilator) or args.verilator
    verilator = Path(found).resolve()
    env = os.environ.copy()
    root_guess = verilator.parent.parent / "share/verilator"
    if root_guess.is_dir() and "VERILATOR_ROOT" not in env:
        env["VERILATOR_ROOT"] = str(root_guess)
    command = [str(verilator), "--binary", "--timing", "-Wno-fatal",
               "--top-module", "tb_page_write", "--Mdir", str(output / "obj"),
               "-j", str(args.jobs), "-GFIRMWARE_HEX=" + json.dumps(str(firmware))]
    command += [str(project / name) for name in COMMON] + [str(core), str(bench)]
    with (output / "compile.log").open("w") as log:
        subprocess.run(command, env=env, cwd=project, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    uart_log = output / "uart_wire.log"
    with (output / "simulation.log").open("w") as log:
        subprocess.run([str(output / "obj/Vtb_page_write"), "+UART_LOG=" + str(uart_log)],
                       env=env, cwd=project, stdout=log, stderr=subprocess.STDOUT, check=True)
    wire = uart_log.read_bytes()
    expected, commands = expected_uart()
    if wire != expected:
        raise SystemExit("UART transcript differs; inspect " + str(uart_log))
    changed = [str(path) for path in inputs if metadata(path) != before[str(path)]]
    if changed:
        raise SystemExit("Inputs changed during validation: " + repr(changed))
    report = {
        "result": "PASS", "clock_hz": 125000000, "baud": 115200,
        "reset_source": "user 20-bit saturating POR; 1048575 clock edges",
        "source_files": sources, "core": metadata(core), "firmware": metadata(firmware),
        "inputs": before, "changed_inputs": changed, "compile_command": command,
        "uart": metadata(uart_log), "uart_bytes": len(wire),
        "injected_and_consumed_rx_bytes": sum(len(c) + 1 for c, _ in commands),
        "prompts": 16, "i2c_transactions": 9, "reads": 7, "writes": 2, "stops": 9,
        "checks": ["locked selector writes issue no I2C transaction",
                   "plain page writes persist until explicitly changed",
                   "same-bank page0/page1 upper-window values are distinct",
                   "lower register00 remains common",
                   "writeverify 7E and 7F issue no I2C transaction",
                   "every A0/register/Sr/A1 read and A0/register/data write is checked",
                   "every read ends with master NACK; every transaction ends with STOP",
                   "complete UART wire transcript matches; CPU trap=0 and RX overrun=0"],
        "limitations": "Ideal non-stretching bit-level slave fixture with test contents; not actual OSFP, analog I2C timing, Radiant P&R/SDF, or board validation.",
    }
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"result": "PASS", "uart_bytes": len(wire), "prompts": 16,
                      "i2c_transactions": 9, "report": str(output / "results.json")}))


if __name__ == "__main__":
    main()
