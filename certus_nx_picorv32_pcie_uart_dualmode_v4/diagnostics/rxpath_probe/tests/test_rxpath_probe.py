#!/usr/bin/env python3
"""Execute probe machine code and test observation with synthetic fault fixtures.

Fault injection exists only in this ideal software model. Board firmware and
RTL are not modified by these tests. The fixtures do not claim a board cause.
"""
from pathlib import Path
import random
import re
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT / "fw/cli_rewrite_v1/tests"))
from test_firmware import CPU

BASE = None
PROBE = None
RECORD = re.compile(r"RXPATH RET=[^\r\n]*\r\n")


def records(text):
    return [dict((key, int(value, 16)) for key, value in
                 re.findall(r"([A-Z0-9]+)=([0-9A-F]{8})", match.group()))
            for match in RECORD.finditer(text)]


def receive(cpu, value, fault=None):
    start = len(cpu.output)
    assert cpu.io.rx is None
    cpu.io.inject(value)
    for _ in range(1500000):
        if fault:
            fault(cpu)
        cpu.step()
        found = records(cpu.output[start:])
        if found:
            cpu.run(1500)
            return found[-1], cpu.output[start:]
    raise AssertionError("No complete RXPATH record: " + repr(cpu.output[start:]))


class ProbeTests(unittest.TestCase):
    def boot(self, cls=CPU):
        cpu = cls(PROBE).boot()
        self.assertIn("RXPATH PROBE v1", cpu.output)
        return cpu

    def test_A_CR_Tab_CR(self):
        cpu = self.boot()
        for value, before_len, after_len, appended, buffer in [
                (0x41, 0, 1, 1, 0x41), (0x0d, 1, 0, 0, 0x41),
                (0x09, 0, 1, 1, 0x09), (0x0d, 1, 0, 0, 0x09)]:
            record, output = receive(cpu, value)
            self.assertEqual(record, {
                "RET": 0, "CPOST": value, "LOAD": 1, "CLOAD": value,
                "S9": 9, "S4": 0x3000, "S5": 0x3000,
                "BAD0": 0, "LEN0": before_len, "APP": appended,
                "ECHO": value if appended else 0,
                "LENA": 1 if appended else 0,
                "LEN1": after_len, "BUF1": buffer,
            })
            self.assertIn("RXTRACE RAW=%08X C=%08X" % (value, value), output)
            self.assertEqual(cpu.load(0x2f84), after_len)
            self.assertEqual(cpu.load(0x2f88), buffer)

    def test_status_and_warm_reset(self):
        cpu = self.boot()
        response = ""
        for value in b"status\r":
            _, output = receive(cpu, value)
            response += output
        self.assertIn("owner_cpu=1 ch=0 dev=0x50", response)
        self.assertEqual(cpu.load(0x2f84), 0)
        receive(cpu, 0x41)
        cpu.reboot()
        self.assertEqual(cpu.output.count("RXPATH PROBE v1"), 1)
        record, _ = receive(cpu, 0x09)
        self.assertEqual((record["LEN0"], record["APP"], record["LEN1"]), (0, 1, 1))

    def test_check_wrapper_preserves_original_register_outputs(self):
        for seed in range(3):
            cpus = [CPU(BASE).boot(), self.boot()]
            rng = random.Random(seed)
            seeded = {index: rng.getrandbits(32) for index in range(4, 32)}
            snapshots = []
            for cpu in cpus:
                cpu.io.inject(0x41)
                cpu.until(lambda: cpu.pc == 0x15e0)
                for index, value in seeded.items():
                    cpu.x[index] = value
                cpu.step()
                cpu.until(lambda: cpu.pc == 0x15e8)
                snapshots.append((list(cpu.x), bytes(cpu.ram[cpu.x[2]:0x8000])))
            self.assertEqual(snapshots[0], snapshots[1])

    def test_detects_guard_return_nonzero_fixture(self):
        cpu = self.boot()
        injected = []
        def fault(c):
            if not injected and c.pc == 0x12e4 and 0x4000 <= c.x[1] < 0x6000:
                c.x[10] = 1
                injected.append(True)
        record, _ = receive(cpu, 0x41, fault)
        self.assertTrue(injected)
        self.assertEqual((record["RET"], record["LOAD"], record["APP"], record["LEN1"]),
                         (1, 0, 0, 0))

    def test_detects_character_slot_change_before_check_fixture(self):
        cpu = self.boot()
        injected = []
        def fault(c):
            if not injected and c.pc == 0x15e0:
                c.store(c.x[2] + 28, 0)
                injected.append(True)
        record, output = receive(cpu, 0x41, fault)
        self.assertIn("RAW=00000041 C=00000041", output)
        self.assertEqual((record["CPOST"], record["CLOAD"], record["APP"]), (0, 0, 0))

    def test_detects_actual_reload_change_after_snapshot_fixture(self):
        cpu = self.boot()
        injected = []
        def fault(c):
            if not injected and c.pc == 0x15ec:
                c.store(c.x[2] + 28, 0)
                injected.append(True)
        record, _ = receive(cpu, 0x41, fault)
        self.assertEqual((record["CPOST"], record["LOAD"], record["CLOAD"], record["APP"]),
                         (0x41, 1, 0, 0))

    def test_detects_tab_comparison_register_change_fixture(self):
        cpu = self.boot()
        injected = []
        def fault(c):
            if not injected and c.pc == 0x15e0:
                c.x[25] = 0
                injected.append(True)
        record, _ = receive(cpu, 0x09, fault)
        self.assertEqual((record["CLOAD"], record["S9"], record["APP"], record["LEN1"]),
                         (9, 0, 0, 0))

    def test_detects_length_store_drop_fixture(self):
        class DroppedStore(CPU):
            dropped = False
            def store(self, address, value, size=4):
                if not self.dropped and self.pc == 0x2560 and address == 0x2f84:
                    self.dropped = True
                    return
                super().store(address, value, size)
        cpu = self.boot(DroppedStore)
        record, _ = receive(cpu, 0x41)
        self.assertTrue(cpu.dropped)
        self.assertEqual((record["APP"], record["ECHO"], record["LENA"], record["LEN1"], record["BUF1"]),
                         (1, 0x41, 0, 0, 0x41))


if __name__ == "__main__":
    BASE = (PROJECT / "firmware/osfp_cli_rewrite_v1_rxtrace.hex").read_text()
    PROBE = (PROJECT / "firmware/osfp_cli_rewrite_v1_rxpath_probe.hex").read_text()
    unittest.main(verbosity=2)
