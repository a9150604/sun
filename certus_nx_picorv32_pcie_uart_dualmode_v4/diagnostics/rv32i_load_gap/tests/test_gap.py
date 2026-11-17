#!/usr/bin/env python3
"""Validate the G1 discriminator with ideal and explicitly faulty CPU models.

The injected fault is a hypothesis fixture, not a board/netlist model.
"""
from pathlib import Path
import sys
import unittest

from load_use_model import LoadUseOldValue

PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT / "fw/cli_rewrite_v1/tests"))
from test_firmware import CPU


def image(name):
    return (PROJECT / "firmware" / name).read_text()


def execute(cls, name):
    cpu = cls(image(name))
    cpu.until(lambda: cpu.output.endswith("END\r\n"))
    output = cpu.output
    cpu.run(10000)
    assert cpu.output == output
    return cpu


class GapTests(unittest.TestCase):
    def test_healthy_base_and_gap(self):
        base = execute(CPU, "rv32i_hw_selftest.hex")
        gap = execute(CPU, "rv32i_hw_selftest_gap1.hex")
        expected = (PROJECT / "diagnostics/rv32i_load_gap/expected_output.txt").read_bytes().decode()
        self.assertEqual(gap.output, expected)
        self.assertEqual(gap.output, base.output.replace("SELFTEST v1", "SELFTEST G1"))
        self.assertEqual(gap.io.rx_reads, 0)

    def test_old_value_fixture_matches_visible_board_pattern(self):
        cpu = execute(LoadUseOldValue, "rv32i_hw_selftest.hex")
        self.assertGreater(cpu.fault_uses, 0)
        self.assertIn("CONST1=\x0013579BD\r\n", cpu.output)
        visible = cpu.output.replace("\x00", "")
        for line in ["CONST1=13579BD", "CONST2=F5A5AA5A", "S4=50000300",
                     "S9=00000000", "X16=9A510001", "RAM3000_P1=01122334",
                     "RAM3000_P2=4A5C35A9", "ADDR2000=6C300200"]:
            self.assertIn(line, visible.splitlines())

    def test_gap_separates_the_injected_dependency_fault(self):
        cpu = execute(LoadUseOldValue, "rv32i_hw_selftest_gap1.hex")
        expected = (PROJECT / "diagnostics/rv32i_load_gap/expected_output.txt").read_bytes().decode()
        self.assertEqual(cpu.output, expected)

    def test_same_fault_reproduces_rxtrace_A_and_Tab_loss(self):
        cpu = LoadUseOldValue(image("osfp_cli_rewrite_v1_rxtrace.hex"))
        cpu.until(lambda: cpu.output.endswith("osfp> "))
        cpu.run(20000)
        for value in [0x41, 0x0d, 0x09, 0x0d]:
            start = len(cpu.output)
            self.assertIsNone(cpu.io.rx)
            cpu.io.inject(value)
            cpu.run(40000)
            expected = ("\r\nRXTRACE RAW=%08X C=%08X L=00 BAD=0 "
                        "HW=00000000 DROP=00000000\r\n" % (value, value))
            if value == 0x0d:
                expected += "\r\nosfp> "
            self.assertEqual(cpu.output[start:], expected)

    def test_same_fault_reproduces_no_key_rxpath_zero_rows(self):
        cpu = LoadUseOldValue(image("osfp_cli_rewrite_v1_rxpath_probe.hex"))
        cpu.until(lambda: cpu.output.endswith("osfp> "))
        cpu.run(20000)
        rows = [line for line in cpu.output.splitlines() if line.startswith("RXPATH RET=")]
        self.assertGreaterEqual(len(rows), 2)
        for row in rows[:2]:
            self.assertTrue(all(field.split("=", 1)[1] == "00000000"
                                for field in row.split()[1:]))
        self.assertEqual(cpu.io.rx_reads, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
