#!/usr/bin/env python3
"""Execute the new RV32I HEX against an ideal, deterministic MMIO model.

This is firmware/command validation, not a substitute for real RTL UART timing,
I2C electrical behavior, or board synthesis. RX has a one-byte holding register;
tests deliver bytes individually or schedule them while TX is occupied.
"""
import argparse
from collections import Counter, deque
from pathlib import Path
import unittest

MASK = 0xffffffff
PROMPT = "osfp> "
IMAGE = None


def sx(value, bits=32):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


class MMIO:
    def __init__(self):
        self.cpu = None
        self.rx = None
        self.rx_overrun = 0
        self.rx_reads = 0
        self.tx = []
        self.tx_busy_steps = 0
        self.tx_ready_step = 0
        self.schedule = deque()
        self.time_offset = 0
        self.cycles_per_step = 32
        self.owner = 1
        self.owner_request = 1
        self.owner_ack = True
        self.local = {0x10000010: 0, 0x10000028: 0}
        self.device = {}
        self.channels = [
            dict(cfg=0x50 + i, cmd=0, status=0, rd=0, auto=False,
                 index=0, wraps=0, paddrs=list(range(8)), shadow=[0]*8)
            for i in range(4)
        ]
        self.operations = []
        self.axi_accesses = []
        self.events = []
        self.faults = deque()
        self.default_fault = "ok"
        self.corrupt_test_read = False
        self.poll_valid = True

    @property
    def cycles(self):
        return (self.time_offset + self.cpu.steps * self.cycles_per_step) & MASK

    def inject(self, value):
        if self.rx is None:
            self.rx = value
        else:
            self.rx_overrun = 1

    def tick(self):
        while self.schedule and self.schedule[0][0] <= self.cpu.steps:
            _, value = self.schedule.popleft()
            self.inject(value)

    def memory_value(self, channel, register):
        dev = self.channels[channel]["cfg"] & 0x7f
        return self.device.get((channel, dev, register), (register ^ 0x5a) & 255)

    def read(self, address):
        if address == 0x10000000:
            return 125000000
        if address == 0x10000008 or address == 0x10000004:
            return int(self.cpu.steps >= self.tx_ready_step)
        if address == 0x1000000c:
            return self.cycles
        if address == 0x1000001c:
            return int(self.rx is not None) | (self.rx_overrun << 1)
        if address == 0x10000018:
            value = self.rx if self.rx is not None else 0
            self.rx = None
            self.rx_overrun = 0
            self.rx_reads += 1
            return value
        if address == 0x10000020:
            return self.owner_request
        if address == 0x10000024:
            return self.owner
        if address >> 16 == 0x4000:
            assert self.owner, "AXI read attempted while PCIe owns slave"
            self.axi_accesses.append(("r", address, None))
            if address == 0x40000000:
                return 0x49324334
            if address == 0x40000004:
                return 0x00020000
            channel = ((address >> 8) & 15) - 1
            assert 0 <= channel < 4, hex(address)
            offset = address & 255
            c = self.channels[channel]
            if offset == 0:
                return c["cfg"]
            if offset == 4:
                return int(c["auto"])
            if offset == 8:
                return c["cmd"]
            if offset == 12:
                if c["auto"]:
                    c["index"] = (c["index"] + 1) & 7
                    if c["index"] == 0:
                        c["wraps"] += 1
                        c["shadow"] = [self.memory_value(channel, r)
                                       for r in c["paddrs"]]
                    c["status"] = ((c["index"] << 4)
                                   | (8 if c["wraps"] and self.poll_valid else 0))
                return c["status"]
            if offset == 16:
                return c["rd"]
            if 0x20 <= offset <= 0x3c:
                return c["shadow"][(offset - 0x20) >> 2]
            if 0x40 <= offset <= 0x5c:
                return c["paddrs"][(offset - 0x40) >> 2]
            raise AssertionError(f"Unexpected AXI read {address:08x}")
        return self.local.get(address, 0)

    def write(self, address, value):
        value &= MASK
        if address == 0x10000004:
            assert self.cpu.steps >= self.tx_ready_step, "TX written while not ready"
            self.tx.append(chr(value & 255))
            self.tx_ready_step = self.cpu.steps + self.tx_busy_steps
            return
        if address == 0x10000020:
            self.owner_request = value & 1
            if self.owner_ack:
                self.owner = self.owner_request
            return
        if address == 0x10000030:
            self.events.append((self.local.get(0x10000034, 0), value))
        if address >> 16 == 0x4000:
            assert self.owner, "AXI write attempted while PCIe owns slave"
            self.axi_accesses.append(("w", address, value))
            channel = ((address >> 8) & 15) - 1
            assert 0 <= channel < 4, hex(address)
            c = self.channels[channel]
            offset = address & 255
            if offset == 0:
                c["cfg"] = value
            elif offset == 8:
                c["cmd"] = value
            elif 0x40 <= offset <= 0x5c:
                c["paddrs"][(offset - 0x40) >> 2] = value & 255
            elif offset == 4:
                c["auto"] = bool(value & 1)
                if value & 16:
                    c["status"] &= ~6
                if value & 2:
                    register = c["cmd"] & 255
                    data = (c["cmd"] >> 8) & 255
                    reading = bool(value & 4)
                    fault = self.faults.popleft() if self.faults else self.default_fault
                    self.operations.append((channel, reading, register, data, fault))
                    if fault == "timeout":
                        c["status"] = 1
                    elif fault == "nack":
                        c["status"] = 6
                    else:
                        if reading:
                            c["rd"] = self.memory_value(channel, register)
                            if self.corrupt_test_read and c["rd"] == 0xa5:
                                c["rd"] ^= 1
                        else:
                            self.device[(channel, c["cfg"] & 127, register)] = data
                        c["status"] = 2
                elif value == 0:
                    c["status"] &= ~1
            else:
                raise AssertionError(f"Unexpected AXI write {address:08x}")
            return
        self.local[address] = value


class CPU:
    """Small RV32I interpreter; only word transfers are accepted."""
    def __init__(self, image):
        self.ram = bytearray().join(int(w, 16).to_bytes(4, "little")
                                   for w in image.split())
        self.x = [0] * 32
        self.pc = 0
        self.steps = 0
        self.ops = Counter()
        self.io = MMIO()
        self.io.cpu = self

    def load(self, address, size=4):
        assert size == 4 and address % 4 == 0, (
            f"Non-word or unaligned load at {address:08x}")
        if 0 <= address <= len(self.ram) - size:
            return int.from_bytes(self.ram[address:address+size], "little")
        return self.io.read(address)

    def store(self, address, value, size=4):
        assert size == 4 and address % 4 == 0, (
            f"Non-word or unaligned store at {address:08x}")
        if 0 <= address <= len(self.ram) - size:
            self.ram[address:address+size] = (value & MASK).to_bytes(size, "little")
        else:
            self.io.write(address, value)

    def step(self):
        self.io.tick()
        pc = self.pc
        instruction = self.load(pc)
        op = instruction & 127
        rd = instruction >> 7 & 31
        f3 = instruction >> 12 & 7
        rs1 = instruction >> 15 & 31
        rs2 = instruction >> 20 & 31
        f7 = instruction >> 25
        left, right = self.x[rs1], self.x[rs2]
        sl, sr = sx(left), sx(right)
        immediate = sx(instruction >> 20, 12)
        next_pc = pc + 4
        value = None
        self.ops[op] += 1
        if op == 0x37:
            value = instruction & 0xfffff000
        elif op == 0x17:
            value = pc + (instruction & 0xfffff000)
        elif op == 0x6f:
            jump = (((instruction >> 31) << 20)
                    | ((instruction >> 12 & 255) << 12)
                    | ((instruction >> 20 & 1) << 11)
                    | ((instruction >> 21 & 1023) << 1))
            value, next_pc = pc + 4, pc + sx(jump, 21)
        elif op == 0x67 and f3 == 0:
            value, next_pc = pc + 4, (left + immediate) & ~1
        elif op == 0x63:
            jump = (((instruction >> 31) << 12)
                    | ((instruction >> 7 & 1) << 11)
                    | ((instruction >> 25 & 63) << 5)
                    | ((instruction >> 8 & 15) << 1))
            condition = {0: left == right, 1: left != right,
                         4: sl < sr, 5: sl >= sr,
                         6: left < right, 7: left >= right}[f3]
            if condition:
                next_pc = pc + sx(jump, 13)
        elif op == 0x03:
            assert f3 == 2, "Firmware unexpectedly uses non-word load"
            value = self.load((left + immediate) & MASK)
        elif op == 0x23:
            assert f3 == 2, "Firmware unexpectedly uses non-word store"
            offset = sx((instruction >> 25 << 5) | (instruction >> 7 & 31), 12)
            self.store((left + offset) & MASK, right)
        elif op == 0x13:
            shift = instruction >> 20 & 31
            if f3 == 0: value = left + immediate
            elif f3 == 1 and f7 == 0: value = left << shift
            elif f3 == 2: value = int(sl < immediate)
            elif f3 == 3: value = int(left < (immediate & MASK))
            elif f3 == 4: value = left ^ immediate
            elif f3 == 5 and f7 == 0: value = left >> shift
            elif f3 == 5 and f7 == 0x20: value = sl >> shift
            elif f3 == 6: value = left | immediate
            elif f3 == 7: value = left & immediate
            else: raise AssertionError(f"Invalid OP-IMM {instruction:08x}")
        elif op == 0x33:
            assert f7 in (0, 0x20), "Firmware unexpectedly uses M extension"
            if f3 == 0: value = left - right if f7 else left + right
            elif f3 == 1 and f7 == 0: value = left << (right & 31)
            elif f3 == 2 and f7 == 0: value = int(sl < sr)
            elif f3 == 3 and f7 == 0: value = int(left < right)
            elif f3 == 4 and f7 == 0: value = left ^ right
            elif f3 == 5: value = sl >> (right & 31) if f7 else left >> (right & 31)
            elif f3 == 6 and f7 == 0: value = left | right
            elif f3 == 7 and f7 == 0: value = left & right
            else: raise AssertionError(f"Invalid OP {instruction:08x}")
        elif op == 0x0f:
            pass
        else:
            raise AssertionError(f"Unexpected instruction {instruction:08x} at {pc:08x}")
        if value is not None and rd:
            self.x[rd] = value & MASK
        self.pc = next_pc & MASK
        self.steps += 1

    @property
    def output(self):
        return "".join(self.io.tx)

    def run(self, steps):
        for _ in range(steps):
            self.step()

    def until(self, predicate, budget=1000000):
        for _ in range(budget):
            self.step()
            if predicate():
                return
        raise AssertionError(f"Budget exceeded PC={self.pc:08x}; tail={self.output[-200:]!r}")

    def boot(self):
        self.until(lambda: self.output.endswith(PROMPT))
        self.run(500)
        return self

    def reboot(self):
        """Reset CPU/SoC registers while retaining initialized FPGA RAM."""
        devices = self.io.device
        self.x = [0] * 32
        self.pc = 0
        self.steps = 0
        self.ops = Counter()
        self.io = MMIO()
        self.io.cpu = self
        self.io.device = devices
        return self.boot()

    def send(self, text):
        for character in text:
            assert self.io.rx is None
            self.io.inject(ord(character))
            self.until(lambda: self.io.rx is None)
            self.run(400)

    def command(self, text, newline="\r", budget=1000000):
        start = len(self.output)
        prompts = self.output.count(PROMPT)
        self.send(text + newline)
        self.until(lambda: self.output.count(PROMPT) > prompts
                   and self.output.endswith(PROMPT), budget=budget)
        self.run(500)
        return self.output[start:]


class FirmwareTests(unittest.TestCase):
    def setUp(self):
        self.cpu = CPU(IMAGE).boot()

    def test_boot_echo_and_empty_enter(self):
        c = self.cpu
        self.assertIn("OSFP CLI REWRITE v1 (RV32I WORD IO)\r\n", c.output)
        self.assertNotIn("DIRECT_READ", c.output)
        self.assertEqual(c.io.axi_accesses, [], "Boot must not touch AXI/I2C")
        before = len(c.output)
        c.send("A")
        c.until(lambda: c.output[before:] == "A")
        self.assertEqual(c.command(""), "\r\nERR unknown command; help\r\nosfp> ")
        self.assertEqual(c.command(""), "\r\nosfp> ")

    def test_crlf_lf_and_visible_editing(self):
        c = self.cpu
        response = c.command("status", newline="\r\n")
        self.assertEqual(response.count(PROMPT), 1)
        self.assertIn("owner_cpu=1", response)
        self.assertIn("ch=0 dev=0x50 reg=0x00 data=0x00", response)
        self.assertIn("clock_hz=0x07735940", response)
        self.assertEqual(c.command("", newline="\n"), "\r\nosfp> ")
        response = c.command("statuX\bs", newline="\n")
        self.assertIn("statuX\b \bs\r\n", response)
        self.assertIn("owner_cpu=1", response)
        response = c.command("statuX\x7fs")
        self.assertIn("\b \b", response)
        self.assertIn("owner_cpu=1", response)

    def test_help_and_configuration(self):
        c = self.cpu
        help_text = c.command("help")
        for command in ("writeverify", "pollset", "mode cpu|pcie", "timeout"):
            self.assertIn(command, help_text)
        for command in ("ch\t2", "dev 0x51", "reg 20", "data A5",
                        "timeout 0xA", "pollgap ffff", "pollset 7 ff"):
            self.assertIn("OK", c.command(command), command)
        state = c.command("status")
        self.assertIn("ch=2 dev=0x51 reg=0x20 data=0xA5", state)
        self.assertIn("timeout_ms=0x0000000A poll_gap=0xFFFF", state)
        self.assertEqual(c.io.channels[2]["cfg"] & 127, 0x51)

    def test_argument_counts_and_numeric_overflow(self):
        c = self.cpu
        cases = (
            ("help extra", "usage: help"),
            ("status extra", "usage: status"),
            ("status a b c d", "ERR too many arguments"),
            ("read 20 30", "usage: read"),
            ("write 20 A5 extra", "usage: write|writeverify"),
            ("reg 100", "usage: reg"),
            ("reg 100000000", "usage: reg"),
            ("reg 0x", "usage: reg"),
            ("reg -1", "usage: reg"),
            ("dev 00", "usage: dev"),
            ("dev 80", "usage: dev"),
            ("ch 4", "usage: ch"),
            ("timeout 09", "usage: timeout"),
            ("timeout 1389", "usage: timeout"),
            ("pollgap 10000", "usage: pollgap"),
            ("pollset 8 20", "usage: pollset"),
            ("delay 4294967296", "usage: delay"),
            ("delay 600001", "usage: delay"),
            ("delay 0x10", "usage: delay"),
        )
        for command, expected in cases:
            with self.subTest(command=command):
                self.assertIn(expected, c.command(command))
        self.assertEqual(c.io.operations, [])
        state = c.command("status")
        self.assertIn("ch=0 dev=0x50 reg=0x00 data=0x00", state)
        self.assertIn("timeout_ms=0x000001F4 poll_gap=0x03E8", state)

    def test_overlength_line_never_executes_truncated_unlock(self):
        c = self.cpu
        response = c.command("unlock" + " " * 100)
        self.assertIn("ERR line too long; command discarded", response)
        self.assertIn("ERR writes locked", c.command("write 20 A5"))
        self.assertIn("owner_cpu=1", c.command("status" + " " * 90))
        self.assertEqual(c.io.operations, [])

    def test_locked_and_bank_page_writes(self):
        c = self.cpu
        self.assertIn("ERR writes locked", c.command("write 20 A5"))
        self.assertIn("ERR writes locked", c.command("writeverify 20 A5"))
        self.assertIn("OK writes unlocked", c.command("unlock"))
        for command in ("write 7e 11", "write 7f 11",
                        "writeverify 7e 11", "writeverify 7f 11"):
            self.assertIn("ERR bank/page register", c.command(command))
        self.assertEqual(c.io.operations, [])
        self.assertIn("OK writes locked", c.command("lock"))

    def test_mode_and_owner_guards(self):
        c = self.cpu
        self.assertIn("AXI ID=0x49324334 VERSION=0x00020000", c.command("id"))
        self.assertIn("owner_cpu=0 rc=0x00", c.command("mode pcie"))
        before = len(c.io.axi_accesses)
        self.assertIn("ERR PCIe owns I2C", c.command("id"))
        self.assertIn("rc=0x05", c.command("read"))
        self.assertIn("OK", c.command("dev 51"))
        self.assertIn("OK writes unlocked", c.command("unlock"))
        self.assertIn("rc=0x05", c.command("write 20 A5"))
        self.assertEqual(len(c.io.axi_accesses), before)
        self.assertIn("owner_cpu=1 rc=0x00", c.command("mode cpu"))
        self.assertIn("AXI ID=0x49324334", c.command("id"))
        self.assertIn("dev=0x51", c.command("status"))

    def test_read_write_and_restore(self):
        c = self.cpu
        key = (0, 0x50, 0x20)
        c.io.device[key] = 0x55
        self.assertIn("READ ch=0 reg=0x20 value=0x55 rc=0x00",
                      c.command("read 20"))
        c.command("unlock")
        self.assertIn("WRITE reg=0x20 data=0x5A rc=0x00",
                      c.command("write 20 5a"))
        self.assertEqual(c.io.device[key], 0x5a)
        before = len(c.io.operations)
        response = c.command("writeverify 20 A5")
        self.assertIn("original=0x5A observed=0xA5 restore_rc=0x00", response)
        self.assertIn("rc=0x00", response)
        self.assertEqual(c.io.device[key], 0x5a)
        self.assertEqual([event[1] for event in c.io.operations[before:]],
                         [True, False, True, False, True])
        self.assertEqual(c.io.local[0x10000010] & 0x7e, 0x0c)

    def test_verify_mismatch_restores_original(self):
        c = self.cpu
        c.io.device[(0, 0x50, 0x20)] = 0x55
        c.io.corrupt_test_read = True
        c.command("unlock")
        response = c.command("writeverify 20 A5")
        self.assertIn("original=0x55 observed=0xA4 restore_rc=0x00", response)
        self.assertIn("rc=0x03", response)
        self.assertEqual(c.io.device[(0, 0x50, 0x20)], 0x55)

    def test_restore_failure_is_reported_separately(self):
        c = self.cpu
        c.io.device[(0, 0x50, 0x20)] = 0x55
        c.io.faults.extend(["ok", "ok", "ok", "nack"])
        c.command("unlock")
        response = c.command("writeverify 20 A5")
        self.assertIn("restore_rc=0x01", response)
        self.assertIn("rc=0x03", response)
        self.assertEqual(c.io.device[(0, 0x50, 0x20)], 0xa5)
        self.assertTrue(c.io.events[-1][0] & 0x8000)
        self.assertFalse(c.io.events[-1][1] & 0x40000000)

    def test_failed_write_still_attempts_restoration(self):
        c = self.cpu
        c.io.device[(0, 0x50, 0x20)] = 0x55
        c.io.faults.extend(["ok", "nack", "ok", "ok"])
        c.command("unlock")
        response = c.command("writeverify 20 A5")
        self.assertIn("restore_rc=0x00", response)
        self.assertIn("rc=0x01", response)
        self.assertEqual(c.io.device[(0, 0x50, 0x20)], 0x55)
        self.assertEqual([entry[1] for entry in c.io.operations],
                         [True, False, False, True])

    def test_nack_and_timeout_paths(self):
        c = self.cpu
        c.io.default_fault = "nack"
        self.assertIn("value=0x00 rc=0x01", c.command("read 20"))
        self.assertEqual(c.io.local[0x10000010] & 0x7e, 0x34)
        c.io.default_fault = "timeout"
        c.io.cycles_per_step = 4096
        c.command("timeout a")
        self.assertIn("rc=0x02", c.command("read 20"))
        self.assertEqual(c.io.local[0x10000010] & 0x7e, 0x54)
        self.assertGreater(len([e for e in c.io.axi_accesses
                               if e[0] == "r" and e[1] == 0x4000010c]), 2)

    def test_poll_uses_two_wraps_and_returns_eight_slots(self):
        c = self.cpu
        c.command("pollset 7 20")
        c.command("pollgap 0010")
        response = c.command("poll")
        self.assertEqual(response.count("POLL slot="), 8)
        self.assertIn("POLL slot=7 reg=0x20 value=0x7A", response)
        self.assertIn("POLL rc=0x00", response)
        self.assertIn("per-slot ACK unavailable", response)
        self.assertGreaterEqual(c.io.channels[0]["wraps"], 2)
        self.assertEqual(c.io.channels[0]["cfg"] >> 16, 0x10)
        self.assertFalse(c.io.channels[0]["auto"])

    def test_poll_without_autovalid_times_out(self):
        c = self.cpu
        c.io.poll_valid = False
        c.io.cycles_per_step = 16384
        response = c.command("poll")
        self.assertIn("POLL rc=0x02", response)
        self.assertFalse(c.io.channels[0]["auto"])

    def test_hardware_overrun_discards_damaged_line(self):
        c = self.cpu
        c.io.inject(ord("u"))
        c.io.inject(ord("n"))
        c.until(lambda: "ERR UART input lost; press Enter\r\n" in c.output)
        response = c.command("lock")
        self.assertIn("ERR command discarded", response)
        self.assertIn("ERR writes locked", c.command("write 20 A5"))
        self.assertIn("hardware_overruns=0x00000001", c.command("status"))
        self.assertEqual(c.io.operations, [])

    def test_uart_receives_while_help_waits_for_tx(self):
        c = self.cpu
        c.io.tx_busy_steps = 200
        start = len(c.output)
        prompts = c.output.count(PROMPT)
        c.send("help\r")
        c.until(lambda: "Commands (hex numbers;" in c.output[start:])
        c.io.schedule = deque((c.steps + 300 * (index + 1), ord(ch))
                              for index, ch in enumerate("status\r"))
        c.until(lambda: c.output.count(PROMPT) >= prompts + 2
                and c.output.endswith(PROMPT))
        self.assertIn("owner_cpu=1", c.output[start:])
        self.assertIn("hardware_overruns=0x00000000 queue_drops=0x00000000",
                      c.output[start:])
        self.assertEqual(c.io.rx_overrun, 0)

    def test_software_queue_loss_rejects_suffix(self):
        c = self.cpu
        c.io.cycles_per_step = 1
        c.send("delay 1000\r")
        c.until(lambda: c.output.endswith("DELAY\r\n"))
        c.run(2000)
        c.io.schedule = deque((c.steps + 300 * (index + 1), ord(ch))
                              for index, ch in enumerate("u" * 150))
        c.run(50000)
        self.assertFalse(c.io.schedule)
        c.io.time_offset += 125000000
        c.until(lambda: "ERR UART input lost; press Enter\r\n" in c.output)
        c.command("")
        response = c.command("status")
        self.assertIn("hardware_overruns=0x00000000", response)
        self.assertNotIn("queue_drops=0x00000000", response)
        self.assertIn("ERR writes locked", c.command("write 20 A5"))

    def test_zero_delay_and_heartbeat(self):
        c = self.cpu
        self.assertIn("DELAY\r\nOK\r\n", c.command("delay 0"))
        before = c.io.local[0x10000010] & 1
        c.io.time_offset += 31250000
        c.until(lambda: (c.io.local[0x10000010] & 1) != before)
        self.assertEqual(c.io.local[0x10000010] & 0x80, 0)

    def test_warm_reset_reinitializes_defaults_without_reloading_ram(self):
        c = self.cpu
        for command in ("unlock", "ch 3", "dev 51", "reg 20", "data A5",
                        "timeout a", "pollgap ffff", "pollset 7 ff"):
            c.command(command)
        c.reboot()
        state = c.command("status")
        self.assertIn("ch=0 dev=0x50 reg=0x00 data=0x00 writes_unlocked=0", state)
        self.assertIn("timeout_ms=0x000001F4 poll_gap=0x03E8", state)
        self.assertIn("POLL slot=7 reg=0x07", c.command("poll"))
        self.assertIn("ERR writes locked", c.command("write 20 A5"))


def main():
    global IMAGE
    project = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hex", type=Path,
                        default=project / "firmware/osfp_cli_rewrite_v1.hex")
    args, rest = parser.parse_known_args()
    IMAGE = args.hex.read_text()
    unittest.main(argv=[str(Path(__file__)), *rest])


if __name__ == "__main__":
    main()
