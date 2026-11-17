#!/usr/bin/env python3
"""Test the rewrite HEX through the original SoC and UART wires with Icarus.

Supply the external upstream PicoRV32 RTL used by the project. The temporary
I2C compatibility copy only rewrites three enum ternaries as equal if/else.
This is RTL simulation, not a Radiant/board timing result.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--picorv32", type=Path, required=True)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--ivl-base")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--smoke", action="store_true",
                        help="Only boot, single A echo and Enter response")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    tests = Path(__file__).resolve().parent
    project = tests.parents[2]
    core = args.picorv32.resolve()
    if not core.is_file():
        parser.error("The supplied PicoRV32 RTL does not exist")
    output = (args.output or project / "build/cli_rewrite_v1/rtl").resolve()
    output.mkdir(parents=True, exist_ok=True)
    firmware = project / "firmware/osfp_cli_rewrite_v1.hex"
    firmware_sha = hashlib.sha256(firmware.read_bytes()).hexdigest()
    print("Firmware HEX SHA256:", firmware_sha, flush=True)
    source = (project / "rtl/user_design/i2c_master_byte.sv").read_text()
    replacements = {
        "state_d = (phase_q == I2C_PH_RDATA) ? I2C_ST_RX_LOW : I2C_ST_BIT_LOW;":
            "begin if (phase_q == I2C_PH_RDATA) state_d = I2C_ST_RX_LOW; else state_d = I2C_ST_BIT_LOW; end",
        "state_d = (bit_cnt_q == 3'd0) ? I2C_ST_ACK_LOW : I2C_ST_BIT_LOW;":
            "begin if (bit_cnt_q == 3'd0) state_d = I2C_ST_ACK_LOW; else state_d = I2C_ST_BIT_LOW; end",
        "state_d = (bit_cnt_q == 3'd0) ? I2C_ST_MACK_LOW : I2C_ST_RX_LOW;":
            "begin if (bit_cnt_q == 3'd0) state_d = I2C_ST_MACK_LOW; else state_d = I2C_ST_RX_LOW; end",
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise SystemExit("Unexpected I2C master source; inspect simulator compatibility before testing")
        source = source.replace(old, new)
    uart_log = output / "uart_wire.log"
    simulation_log = output / "simulation.log"
    with tempfile.TemporaryDirectory(prefix="cli-rewrite-rtl-") as temporary:
        temporary = Path(temporary)
        master = temporary / "i2c_master_byte_iverilog.sv"
        master.write_text(source)
        image = temporary / "test.vvp"
        command = [args.iverilog]
        if args.ivl_base:
            command += ["-B", args.ivl_base]
        command += [
            "-g2012", "-s", "tb_cli_rewrite",
            "-P", f"tb_cli_rewrite.BAUD={args.baud}",
            "-P", f"tb_cli_rewrite.SMOKE={int(args.smoke)}",
            "-o", str(image),
            "rtl/user_design/i2c4_pkg.sv", str(master),
            "rtl/user_design/i2c_device_ctrl.sv",
            "rtl/user_design/axil_i2c4_regs.sv", str(core),
            "rtl/soc/native_to_axil_master.v", "rtl/soc/uart_tx_mmio.v",
            "rtl/soc/uart_rx_byte.v", "rtl/soc/axil_master_mode_mux.sv",
            "rtl/soc/axil_owner_switch.v", "rtl/soc/picorv32_cpu_axil_uart.v",
            "rtl/soc/pcie_i2c4_top_cpu_fabric.sv",
            "rtl/soc/certus_nx_picorv32_uart_standalone_top.sv",
            str(tests / "tb_cli_rewrite.sv"),
        ]
        with simulation_log.open("w") as log:
            log.write("Firmware HEX SHA256: " + firmware_sha + "\n")
            log.flush()
            subprocess.run(command, cwd=project, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
            process = subprocess.Popen(
                [args.vvp, str(image), "+UART_LOG=" + str(uart_log)],
                cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
            )
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
                log.flush()
            if process.wait() != 0:
                raise SystemExit("RTL simulation failed; see " + str(simulation_log))
    data = uart_log.read_bytes()
    assert hashlib.sha256(firmware.read_bytes()).hexdigest() == firmware_sha, "Firmware changed during simulation"
    banner = b"\r\nOSFP CLI REWRITE v1 (RV32I WORD IO)\r\n"
    assert data.startswith(banner), repr(data[:100])
    assert b"osfp> A\r\nERR unknown command; help\r\nosfp> " in data
    assert data.count(b"osfp> ") == (2 if args.smoke else 7), repr(data)
    if not args.smoke:
        assert data.count(b"owner_cpu=1 ch=0 dev=0x50 reg=0x00 data=0x00") == 2
        assert data.count(b"hardware_overruns=0x00000000 queue_drops=0x00000000") == 2
        assert b"stax\x08 \x08tus\r\nowner_cpu=" in data
        assert b"locx\x08 \x08k\r\nOK writes locked\r\nosfp> " in data
    assert b"DIRECT_READ" not in data
    print("PASS: exact wire-decoded banner and replies"
          + ("; two-prompt smoke" if args.smoke else
             "; edited lines, seven prompts and clean UART counters"), flush=True)
    print("UART wire log:", uart_log)
    print("Simulation log:", simulation_log)


if __name__ == "__main__":
    main()
