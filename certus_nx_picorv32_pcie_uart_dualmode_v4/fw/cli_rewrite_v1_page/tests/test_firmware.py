#!/usr/bin/env python3
"""Execute baseline and PAGE WRITE machine code in the inherited RV32I model.

The page-window fixture is ideal, not an OSFP electrical or CMIS bank-update model.
Original tests and published firmware remain unchanged.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

PROJECT = Path(__file__).resolve().parents[3]
BASE_PATH = PROJECT / "fw/cli_rewrite_v1/tests/test_firmware.py"
spec = importlib.util.spec_from_file_location("baseline_firmware_tests", BASE_PATH)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
PAGE_IMAGE = None
PAGE_BANNER = "OSFP CLI REWRITE v1 PAGE WRITE (RV32I WORD IO)\r\n"


class PageRegression(base.FirmwareTests):
    """Reuse the 19 existing tests; replace only the two intentional changes."""
    def setUp(self):
        self.cpu = base.CPU(PAGE_IMAGE).boot()

    def test_boot_echo_and_empty_enter(self):
        c = self.cpu
        self.assertIn(PAGE_BANNER, c.output)
        self.assertNotIn("DIRECT_READ", c.output)
        self.assertEqual(c.io.axi_accesses, [])
        start = len(c.output)
        c.send("A")
        c.until(lambda: c.output[start:] == "A")
        self.assertEqual(c.command(""), "\r\nERR unknown command; help\r\nosfp> ")
        self.assertEqual(c.command(""), "\r\nosfp> ")

    def test_locked_and_bank_page_writes(self):
        c = self.cpu
        for command in ("write 7e 01", "write 7f 01", "writeverify 7f 01"):
            self.assertIn("ERR writes locked", c.command(command))
        self.assertEqual(c.io.operations, [])
        self.assertIn("OK writes unlocked", c.command("unlock"))
        for register in (0x7e, 0x7f):
            command = f"write {register:02x} 01"
            self.assertIn(f"WRITE reg=0x{register:02X} data=0x01 rc=0x00", c.command(command))
        self.assertEqual([(op[1], op[2], op[3]) for op in c.io.operations],
                         [(False, 0x7e, 1), (False, 0x7f, 1)])
        before = len(c.io.operations)
        for register in (0x7e, 0x7f):
            self.assertIn("ERR bank/page register", c.command(f"writeverify {register:02x} 00"))
        self.assertEqual(len(c.io.operations), before)
        self.assertIn("OK writes locked", c.command("lock"))
        self.assertIn("ERR writes locked", c.command("write 7f 00"))
        self.assertEqual(len(c.io.operations), before)


class PageWindowMMIO(base.MMIO):
    """Ideal page window; raw 7E storage does not model CMIS atomic bank updates."""
    def __init__(self):
        super().__init__()
        self.selectors = {}
        self.upper = {}

    def selection(self, channel):
        dev = self.channels[channel]["cfg"] & 127
        return self.selectors.setdefault((channel, dev), [0, 0])

    def memory_value(self, channel, register):
        if register in (0x7e, 0x7f):
            return self.selection(channel)[register - 0x7e]
        if register >= 0x80:
            bank, page = self.selection(channel)
            dev = self.channels[channel]["cfg"] & 127
            return self.upper.get((channel, dev, 0, page, register),
                                  (register ^ page ^ 0x5a) & 255)
        return super().memory_value(channel, register)

    def write(self, address, value):
        before = len(self.operations)
        super().write(address, value)
        if len(self.operations) == before:
            return
        channel, reading, register, data, fault = self.operations[-1]
        if reading or fault != "ok":
            return
        if register in (0x7e, 0x7f):
            self.selection(channel)[register - 0x7e] = data
        elif register >= 0x80:
            bank, page = self.selection(channel)
            dev = self.channels[channel]["cfg"] & 127
            self.upper[(channel, dev, 0, page, register)] = data


class PageFixtureTests(unittest.TestCase):
    def setUp(self):
        self.cpu = base.CPU(PAGE_IMAGE)
        self.cpu.io = PageWindowMMIO()
        self.cpu.io.cpu = self.cpu
        self.cpu.io.device[(0, 0x50, 0)] = 0x19
        self.cpu.io.upper.update({(0, 0x50, 0, 0, 0x80): 0x11,
                                  (0, 0x50, 0, 1, 0x80): 0xa5,
                                  (0, 0x50, 0, 1, 0x81): 0x5a})
        self.cpu.boot()

    def test_page_select_persists_and_lower_memory_is_common(self):
        c = self.cpu
        self.assertIn("value=0x11 rc=0x00", c.command("read 80"))
        c.command("unlock")
        self.assertIn("WRITE reg=0x7F data=0x01 rc=0x00", c.command("write 7f 01"))
        self.assertEqual(c.io.selection(0), [0, 1])
        self.assertIn("value=0x01 rc=0x00", c.command("read 7f"))
        self.assertIn("value=0xA5 rc=0x00", c.command("read 80"))
        self.assertIn("value=0x5A rc=0x00", c.command("read 81"))
        self.assertIn("value=0x19 rc=0x00", c.command("read 00"))
        c.command("lock")
        self.assertEqual(c.io.selection(0), [0, 1], "lock must not restore a page")
        self.assertIn("value=0xA5 rc=0x00", c.command("read 80"))
        c.command("unlock")
        c.command("write 7f 00")
        self.assertIn("value=0x11 rc=0x00", c.command("read 80"))
        selector_writes = [(op[2], op[3]) for op in c.io.operations if not op[1]]
        self.assertEqual(selector_writes, [(0x7f, 1), (0x7f, 0)])

    def test_raw_bank_byte_and_channel_page_storage(self):
        c = self.cpu
        c.command("unlock")
        c.command("write 7f 01")
        c.command("write 7e 01")
        self.assertEqual(c.io.operations[-1][1:4], (False, 0x7e, 1))
        # This only checks a raw byte write, not a CMIS bank transition.
        self.assertIn("value=0x19 rc=0x00", c.command("read 00"))
        c.command("ch 2")
        c.command("dev 51")
        c.command("write 7f 02")
        self.assertEqual(c.io.selection(2), [0, 2])
        c.command("ch 0")
        self.assertEqual(c.io.selection(0), [1, 1])
        self.assertIn("value=0x01 rc=0x00", c.command("read 7f"))

    def test_selector_verify_has_no_transactions_or_page_changes(self):
        c = self.cpu
        c.command("unlock")
        c.command("write 7f 01")
        before = len(c.io.operations)
        for register in ("7e", "7f"):
            self.assertIn("ERR bank/page register", c.command(f"writeverify {register} 00"))
        self.assertEqual(len(c.io.operations), before)
        self.assertEqual(c.io.selection(0), [0, 1])
        self.assertIn("value=0xA5 rc=0x00", c.command("read 80"))

    def test_nack_and_timeout_do_not_select_a_page(self):
        c = self.cpu
        c.command("unlock")
        c.io.default_fault = "nack"
        self.assertIn("WRITE reg=0x7F data=0x01 rc=0x01", c.command("write 7f 01"))
        self.assertEqual(c.io.selection(0), [0, 0])
        c.io.default_fault = "timeout"
        c.io.cycles_per_step = 4096
        c.command("timeout a")
        self.assertIn("rc=0x02", c.command("write 7f 01"))
        self.assertEqual(c.io.selection(0), [0, 0])

    def test_pcie_owner_cannot_issue_selector_write(self):
        c = self.cpu
        c.command("unlock")
        c.command("mode pcie")
        before = len(c.io.axi_accesses)
        self.assertIn("rc=0x05", c.command("write 7f 01"))
        self.assertEqual(len(c.io.axi_accesses), before)
        self.assertEqual(c.io.operations, [])


def main():
    global PAGE_IMAGE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hex", type=Path, default=PROJECT / "firmware/osfp_cli_rewrite_v1_page.hex")
    parser.add_argument("--results-json", type=Path)
    args = parser.parse_args()
    inputs = [BASE_PATH, args.hex, PROJECT / "firmware/osfp_cli_rewrite_v1.hex", Path(__file__)]
    input_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    if input_hashes[str(BASE_PATH)] != "b19d60b03600fd06f0031f456ad7ddad8c669827397c548b09d60e121ecddb17":
        raise SystemExit("Baseline CPU/MMIO emulator differs from the published test source")
    if input_hashes[str(PROJECT / "firmware/osfp_cli_rewrite_v1.hex")] != "1030f723833afa74bd3a38060cbb333d14be42d2bf75e04c4a767fcb576cae4e":
        raise SystemExit("Original CLI HEX differs from the preserved release")
    PAGE_IMAGE = args.hex.read_text()
    base.IMAGE = (PROJECT / "firmware/osfp_cli_rewrite_v1.hex").read_text()
    loader = unittest.TestLoader()
    suite = unittest.TestSuite((loader.loadTestsFromTestCase(base.FirmwareTests),
                               loader.loadTestsFromTestCase(PageRegression),
                               loader.loadTestsFromTestCase(PageFixtureTests)))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    changed_inputs = [str(path) for path in inputs
                      if hashlib.sha256(path.read_bytes()).hexdigest() != input_hashes[str(path)]]
    if changed_inputs:
        raise SystemExit("Inputs changed during validation: " + repr(changed_inputs))
    summary = {"result": "PASS" if result.wasSuccessful() else "FAIL",
               "input_sha256": input_hashes, "changed_inputs": changed_inputs,
               "tests_run": result.testsRun, "failures": len(result.failures),
               "errors": len(result.errors),
               "normal_baseline_tests": loader.loadTestsFromTestCase(base.FirmwareTests).countTestCases(),
               "page_regression_tests": loader.loadTestsFromTestCase(PageRegression).countTestCases(),
               "page_fixture_tests": loader.loadTestsFromTestCase(PageFixtureTests).countTestCases(),
               "page_hex_sha256": hashlib.sha256(args.hex.read_bytes()).hexdigest(),
               "baseline_hex_sha256": hashlib.sha256((PROJECT / "firmware/osfp_cli_rewrite_v1.hex").read_bytes()).hexdigest(),
               "limitations": "RV32I software execution with ideal MMIO/page-window fixture; raw 7E transmission is not a CMIS atomic bank-update test; no physical OSFP or RTL timing validation."}
    if args.results_json:
        args.results_json.parent.mkdir(parents=True, exist_ok=True)
        args.results_json.write_text(json.dumps(summary, indent=2) + "\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
