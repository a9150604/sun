#!/usr/bin/env python3
"""Validate actual selftest machine code with an ideal RV32I/MMIO model.

Synthetic corruptions exist only in this Python model, not in the board HEX.
"""
from pathlib import Path
import json
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT / "fw/cli_rewrite_v1/tests"))
from test_firmware import CPU

IMAGE = None
ADDRESSES = [0x3000, 0x3800, 0x6000, 0x7ed0, 0x7f00]
BRANCHES = {
    "BEQ_ZERO": "T", "BNE_ZERO": "F", "BEQ_TAB": "T", "BNE_TAB": "F",
    "BEQ_A": "T", "BNE_DIFF": "T", "BLTU_RANGE": "T", "BGEU_RANGE": "T",
    "BLTU_REVERSE": "F", "BGEU_REVERSE": "F", "BEQ_LONG_ZERO": "T",
    "BNE_LONG_ZERO": "F", "BNE_LONG_NINE": "T",
}


def run_image(cls=CPU):
    cpu = cls(IMAGE)
    cpu.until(lambda: cpu.output.endswith("END\r\n"), budget=1500000)
    before = cpu.output
    cpu.run(10000)
    assert cpu.output == before, "Selftest must not print repeatedly after END"
    fields = dict(line.split("=", 1) for line in cpu.output.splitlines() if "=" in line)
    return cpu, fields


class SelftestTests(unittest.TestCase):
    def test_immediates_registers_ram_and_branches(self):
        cpu, fields = run_image()
        self.assertTrue(cpu.output.startswith("\r\nRV32I HW SELFTEST v1\r\n"))
        self.assertEqual(fields["CONST1"], "13579BDF")
        self.assertEqual(fields["CONST2"], "5A5AA5A5")
        self.assertEqual([fields[name] for name in ["S4", "S5", "S9"]],
                         ["00003000", "00003000", "00000009"])
        for index in range(16, 32):
            self.assertEqual(int(fields[f"X{index}"], 16),
                             0xa5000000 | (index << 16) | index)
        for address in ADDRESSES:
            key = f"RAM{address:04X}"
            self.assertEqual(fields[key + "_Z"], "00000000")
            self.assertEqual(fields[key + "_P1"], "11223344")
            self.assertEqual(fields[key + "_P2"], "A5C35A96")
            self.assertEqual(int(fields[f"ADDR{address:04X}"], 16), 0xc3000000 | address)
        for key, value in BRANCHES.items():
            self.assertEqual(fields[key], value)
        self.assertEqual(fields["ADDR2000"], "C3002000")
        self.assertEqual(cpu.output.count("RV32I HW SELFTEST v1"), 1)
        self.assertEqual(cpu.output.count("END\r\n"), 1)
        self.assertEqual(cpu.io.rx_reads, 0)
        self.assertEqual(cpu.io.axi_accesses, [])

    def test_all_register_values_expose_an_alias_fixture(self):
        class AliasBank(list):
            def __getitem__(self, index):
                return super().__getitem__(16 if index == 17 else index)
            def __setitem__(self, index, value):
                super().__setitem__(16 if index == 17 else index, value)
        class AliasedRegisters(CPU):
            def __init__(self, image):
                super().__init__(image)
                self.x = AliasBank(self.x)
        _, fields = run_image(AliasedRegisters)
        self.assertEqual(fields["X16"], "A5110011")
        self.assertEqual(fields["X17"], "A5110011")
        self.assertNotEqual(fields["X16"], "A5100010")

    def test_branch_output_exposes_a_missed_equal_branch_fixture(self):
        manifest = json.loads((PROJECT / "diagnostics/rv32i_hw_selftest/manifest.json").read_text())
        branch = next(case for case in manifest["protocol"]["branch_tests"]
                      if case["label"] == "BEQ_ZERO")
        branch_pc = int(branch["instruction_address"], 16)
        class MissedBranch(CPU):
            missed = False
            def step(self):
                if not self.missed and self.pc == branch_pc:
                    self.pc += 4
                    self.steps += 1
                    self.missed = True
                    return
                super().step()
        cpu, fields = run_image(MissedBranch)
        self.assertTrue(cpu.missed)
        self.assertEqual(fields["BEQ_ZERO"], "F")
        self.assertEqual(fields["BEQ_TAB"], "T")

    def test_address_pair_exposes_an_A14_alias_fixture(self):
        class AliasedRAM(CPU):
            def load(self, address, size=4):
                if 0 <= address < 0x8000:
                    address &= 0x3fff
                return super().load(address, size)
            def store(self, address, value, size=4):
                if 0 <= address < 0x8000:
                    address &= 0x3fff
                super().store(address, value, size)
        _, fields = run_image(AliasedRAM)
        self.assertEqual(fields["RAM6000_P1"], "11223344")
        self.assertEqual(fields["ADDR2000"], "C3006000")
        self.assertEqual(fields["ADDR6000"], "C3006000")

    def test_wrong_long_target_stops_before_false_success_fixture(self):
        manifest = json.loads((PROJECT / "diagnostics/rv32i_hw_selftest/manifest.json").read_text())
        branch = next(case for case in manifest["protocol"]["branch_tests"]
                      if case["label"] == "BEQ_LONG_ZERO")
        branch_pc = int(branch["instruction_address"], 16)
        cpu = CPU(IMAGE)
        cpu.until(lambda: cpu.pc == branch_pc)
        # Synthetic lost immediate bit: target +0x078 instead of +0x278.
        cpu.pc = branch_pc + 0x78
        self.assertEqual(cpu.load(cpu.pc), 0x0000006f)
        stuck_pc = cpu.pc
        before = cpu.output
        cpu.run(128)
        self.assertEqual(cpu.pc, stuck_pc)
        self.assertEqual(cpu.output, before)
        self.assertNotIn("END\r\n", cpu.output)

    def test_readback_exposes_a_dropped_write_fixture(self):
        class DroppedWrite(CPU):
            dropped = False
            def store(self, address, value, size=4):
                if not self.dropped and address == 0x6000 and value == 0x11223344:
                    self.dropped = True
                    return
                super().store(address, value, size)
        cpu, fields = run_image(DroppedWrite)
        self.assertTrue(cpu.dropped)
        self.assertEqual(fields["RAM6000_P1"], "00000000")
        self.assertEqual(fields["RAM6000_P2"], "A5C35A96")
        self.assertEqual(fields["CONST1"], "13579BDF")

    def test_register_output_exposes_a_register_change_fixture(self):
        class ChangedRegister(CPU):
            changed = False
            def step(self):
                instruction = self.load(self.pc)
                # ADDI a0,s9,0: change the register immediately before its read.
                if not self.changed and instruction == 0x000c8513:
                    self.x[25] = 0
                    self.changed = True
                super().step()
        cpu, fields = run_image(ChangedRegister)
        self.assertTrue(cpu.changed)
        self.assertEqual(fields["S9"], "00000000")
        self.assertEqual(fields["CONST2"], "5A5AA5A5")


if __name__ == "__main__":
    IMAGE = (PROJECT / "firmware/rv32i_hw_selftest.hex").read_text()
    unittest.main(verbosity=2)
