#!/usr/bin/env python3
"""Validate the compile-time RXTRACE image using the RV32I/MMIO model.

These are machine-code tests with ideal MMIO, not board or UART-wire tests.
The high-bit RX fixture is deliberately synthetic: normal hardware exposes
only an eight-bit UART value, but trace must preserve an anomalous bus word.
"""
import argparse
from collections import deque
import hashlib
from pathlib import Path
import re
import sys
import unittest

from test_firmware import CPU, PROMPT

NORMAL_SHA256 = "1030f723833afa74bd3a38060cbb333d14be42d2bf75e04c4a767fcb576cae4e"
TRACE_IMAGE = None
NORMAL_IMAGE = None
TRACE_LINE = re.compile(
    r"\r\nRXTRACE RAW=([0-9A-F]{8}) C=([0-9A-F]{8}) "
    r"L=([0-9A-F]{2}) BAD=([0-9A-F]) HW=([0-9A-F]{8}) "
    r"DROP=([0-9A-F]{8})\r\n"
)
FIELD_NAMES = ("raw", "character", "length", "bad", "hardware", "drops")


def records(text):
    return [
        dict(zip(FIELD_NAMES, (int(value, 16) for value in match.groups())))
        for match in TRACE_LINE.finditer(text)
    ]


def inject_and_drain(cpu, value):
    """Supply one bus sample and wait for its complete, pre-filter trace."""
    assert cpu.io.rx is None
    before = len(cpu.output)
    cpu.io.inject(value)
    cpu.until(lambda: len(records(cpu.output[before:])) == 1)
    # Finish handling the byte (including its echo or Enter response).
    cpu.run(6000)
    return cpu.output[before:]


class RXTraceTests(unittest.TestCase):
    def setUp(self):
        self.cpu = CPU(TRACE_IMAGE).boot()

    def test_normal_image_unchanged(self):
        canonical = ("\n".join(NORMAL_IMAGE.split()) + "\n").encode("ascii")
        self.assertEqual(hashlib.sha256(canonical).hexdigest(), NORMAL_SHA256)
        normal = CPU(NORMAL_IMAGE).boot()
        self.assertIn("OSFP CLI REWRITE v1 (RV32I WORD IO)\r\n", normal.output)
        self.assertNotIn("RXTRACE", normal.output)

    def test_unique_trace_banner(self):
        self.assertEqual(
            self.cpu.output,
            "\r\nOSFP CLI REWRITE v1 RXTRACE\r\n"
            "One key at a time; RAW is the word read from IO_RX.\r\nosfp> ",
        )
        self.assertEqual(self.cpu.io.axi_accesses, [])

    def test_A_is_traced_before_echo(self):
        response = inject_and_drain(self.cpu, 0x41)
        self.assertEqual(
            response,
            "\r\nRXTRACE RAW=00000041 C=00000041 L=00 BAD=0 "
            "HW=00000000 DROP=00000000\r\nA",
        )
        self.assertEqual(self.cpu.io.rx_reads, 1)
        self.assertEqual(records(response)[0]["raw"], 0x41)

    def test_Enter_records_pre_handler_length_and_returns_prompt(self):
        inject_and_drain(self.cpu, 0x41)
        before_prompts = self.cpu.output.count(PROMPT)
        response = inject_and_drain(self.cpu, 0x0d)
        self.assertEqual(records(response), [{
            "raw": 0x0d, "character": 0x0d, "length": 1,
            "bad": 0, "hardware": 0, "drops": 0,
        }])
        self.assertIn("\r\nERR unknown command; help\r\nosfp> ", response)
        self.assertEqual(self.cpu.output.count(PROMPT), before_prompts + 1)

    def test_non_ascii_is_visible_in_trace_but_not_echoed_or_buffered(self):
        response = inject_and_drain(self.cpu, 0xc1)
        record = records(response)[0]
        self.assertEqual((record["raw"], record["character"]), (0xc1, 0xc1))
        self.assertEqual(record["length"], 0)
        self.assertEqual(response[TRACE_LINE.search(response).end():], "")
        enter = inject_and_drain(self.cpu, 0x0d)
        self.assertEqual(records(enter)[0]["length"], 0)
        self.assertNotIn("ERR unknown command", enter)
        self.assertTrue(enter.endswith("\r\nosfp> "))

    def test_full_bus_word_is_preserved_and_character_is_masked(self):
        response = inject_and_drain(self.cpu, 0xdead0041)
        record = records(response)[0]
        self.assertEqual(record["raw"], 0xdead0041)
        self.assertEqual(record["character"], 0x41)
        self.assertTrue(response.endswith("\r\nA"))

    def test_CRLF_still_executes_once(self):
        before_prompts = self.cpu.output.count(PROMPT)
        cr = inject_and_drain(self.cpu, 0x0d)
        lf = inject_and_drain(self.cpu, 0x0a)
        self.assertEqual(records(cr)[0]["raw"], 0x0d)
        self.assertEqual(records(lf)[0]["raw"], 0x0a)
        self.assertTrue(cr.endswith("\r\nosfp> "))
        self.assertEqual(lf[TRACE_LINE.search(lf).end():], "")
        self.assertEqual(self.cpu.output.count(PROMPT), before_prompts + 1)

    def test_status_command_still_executes_with_trace(self):
        before = len(self.cpu.output)
        prompts = self.cpu.output.count(PROMPT)
        for value in b"status\r":
            inject_and_drain(self.cpu, value)
        self.cpu.until(lambda: self.cpu.output.count(PROMPT) == prompts + 1
                       and self.cpu.output.endswith(PROMPT))
        response = self.cpu.output[before:]
        self.assertEqual([record["character"] for record in records(response)],
                         list(b"status\r"))
        self.assertEqual([record["length"] for record in records(response)],
                         list(range(7)))
        self.assertIn("owner_cpu=1 ch=0 dev=0x50 reg=0x00 data=0x00", response)
        self.assertTrue(response.endswith(PROMPT))

    def test_queued_samples_keep_their_own_raw_words_during_output(self):
        cpu = self.cpu
        before = len(cpu.output)
        prompts = cpu.output.count(PROMPT)
        cpu.io.tx_busy_steps = 80
        start = cpu.steps + 20
        cpu.io.schedule = deque([
            (start, 0xdead0041),
            (start + 800, 0xbeef0042),
            (start + 1600, 0x0d),
        ])
        cpu.until(lambda: cpu.output.count(PROMPT) == prompts + 1
                  and cpu.output.endswith(PROMPT))
        cpu.run(500)
        captured = records(cpu.output[before:])
        self.assertEqual([record["raw"] for record in captured],
                         [0xdead0041, 0xbeef0042, 0x0d])
        self.assertEqual([record["character"] for record in captured],
                         [0x41, 0x42, 0x0d])
        self.assertEqual([record["length"] for record in captured], [0, 1, 2])
        self.assertTrue(all(record["hardware"] == 0 and record["drops"] == 0
                            for record in captured))
        self.assertEqual(cpu.io.rx_reads, 3)


def main():
    global TRACE_IMAGE, NORMAL_IMAGE
    project = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hex", type=Path,
                        default=project / "firmware/osfp_cli_rewrite_v1_rxtrace.hex")
    parser.add_argument("--normal-hex", type=Path,
                        default=project / "firmware/osfp_cli_rewrite_v1.hex")
    args = parser.parse_args()
    TRACE_IMAGE = args.hex.read_text(encoding="ascii")
    NORMAL_IMAGE = args.normal_hex.read_text(encoding="ascii")
    print("Trace HEX SHA256:",
          hashlib.sha256(args.hex.read_bytes()).hexdigest(), flush=True)
    unittest.main(argv=[sys.argv[0]], verbosity=2)


if __name__ == "__main__":
    main()
