#!/usr/bin/env python3
"""Generate a small RV32I CPU/RAM/UART probe without a C toolchain.

Run from the project root; only the chosen output files are written. The source
interactive.hex is never changed. Instructions replace reset word 0 and a small
code area starting at 0x400. Original rodata and uart_puts at 0x130 are retained.
UART labels use immediate SW instructions, not NUL-terminated strings.
"""
import argparse
import hashlib
import json
from pathlib import Path

MASK = 0xffffffff
RAM_BYTES = 32768
UART = 8  # s0, not clobbered by the retained original uart_puts helper.
A0, A1, RA, SP = 10, 11, 1, 2
FAIL = 27  # s11, sticky memory-check failure flag.
WORD_ADDRESSES = (0x1eb0, 0x2038, 0x21b8, 0x21c4)
EXPECTED_WORDS = (0x75000a29, 0x6d6f4300, 0x4420000a, 0x70004441)
NUL_ADDRESSES = (0x1eb2, 0x21b9, 0x21c6)
CHECK_START, CHECK_END = 0x1e10, 0x2380
EXPECTED_SUM, EXPECTED_XOR = 0xe4fb71c7, 0x3d0a3b6b
PUTS_START, PUTS_END = 0x130, 0x164


def i_type(op, rd, f3, rs1, imm):
    assert -2048 <= imm <= 2047
    return ((imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(rs1, rs2, imm):
    assert -2048 <= imm <= 2047
    return (((imm & 0xfff) >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | ((imm & 31) << 7) | 0x23


def b_type(rs1, rs2, f3, delta):
    assert delta % 2 == 0 and -4096 <= delta < 4096
    x = delta & 0x1fff
    return ((x >> 12) << 31) | (((x >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (((x >> 1) & 15) << 8) | (((x >> 11) & 1) << 7) | 0x63


def j_type(rd, delta):
    assert delta % 2 == 0 and -(1 << 20) <= delta < (1 << 20)
    x = delta & 0x1fffff
    return ((x >> 20) << 31) | (((x >> 1) & 1023) << 21) | (((x >> 11) & 1) << 20) | (((x >> 12) & 255) << 12) | (rd << 7) | 0x6f


class Assembler:
    def __init__(self, origin):
        self.origin = origin
        self.words = []
        self.labels = {}
        self.fixups = []
        self.serial = 0

    @property
    def pc(self):
        return self.origin + 4 * len(self.words)

    def emit(self, value):
        self.words.append(value & MASK)

    def label(self, name):
        assert name not in self.labels
        self.labels[name] = self.pc

    def unique(self, stem):
        self.serial += 1
        return f'{stem}_{self.serial}'

    def li(self, rd, value):
        value &= MASK
        signed = value if value < 0x80000000 else value - (1 << 32)
        if -2048 <= signed <= 2047:
            self.addi(rd, 0, signed)
        else:
            high = (value + 0x800) >> 12
            low = value - (high << 12)
            self.emit(((high & 0xfffff) << 12) | (rd << 7) | 0x37)
            self.addi(rd, rd, low)

    def addi(self, rd, rs1, value):
        self.emit(i_type(0x13, rd, 0, rs1, value))

    def andi(self, rd, rs1, value):
        self.emit(i_type(0x13, rd, 7, rs1, value))

    def mov(self, rd, rs):
        self.addi(rd, rs, 0)

    def load(self, rd, base, offset=0, byte=False):
        self.emit(i_type(0x03, rd, 4 if byte else 2, base, offset))

    def store(self, rs, base, offset=0):
        self.emit(s_type(base, rs, offset))

    def alu(self, rd, rs1, rs2, f3, f7=0):
        self.emit((f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33)

    def branch(self, rs1, rs2, f3, target):
        self.fixups.append((len(self.words), 'branch', (rs1, rs2, f3, target)))
        self.emit(0)

    def jump(self, target, rd=0):
        self.fixups.append((len(self.words), 'jump', (rd, target)))
        self.emit(0)

    def text(self, text):
        # No data-memory string lookup: each ASCII byte is an immediate store.
        for value in text.encode('ascii'):
            self.li(31, value)
            self.store(31, UART, 4)

    def hex(self, rs, digits=8):
        self.mov(A0, rs)
        self.li(A1, (digits - 1) * 4)
        self.jump('hex_out', RA)

    def expect(self, rs, expected):
        ok = self.unique('expected')
        self.li(30, expected)
        self.branch(rs, 30, 0, ok)
        self.li(FAIL, 1)
        self.label(ok)

    def finish(self):
        for index, kind, args in self.fixups:
            pc = self.origin + index * 4
            if kind == 'branch':
                rs1, rs2, f3, target = args
                dest = self.labels[target] if isinstance(target, str) else target
                self.words[index] = b_type(rs1, rs2, f3, dest - pc)
            else:
                rd, target = args
                dest = self.labels[target] if isinstance(target, str) else target
                self.words[index] = j_type(rd, dest - pc)
        return b''.join(w.to_bytes(4, 'little') for w in self.words)


def build(base, origin=0x400, with_puts=True):
    assert len(base) == RAM_BYTES
    assert origin % 4 == 0 and 0x180 <= origin < 0x1000
    for address, expected in zip(WORD_ADDRESSES, EXPECTED_WORDS):
        assert int.from_bytes(base[address:address + 4], 'little') == expected, f'Unexpected base word at {address:04x}'
    assert base[PUTS_START:PUTS_START + 4] == bytes.fromhex('b7050010'), 'Unexpected original uart_puts entry'
    assert int.from_bytes(base[0x160:0x164], 'little') == 0x00008067, 'Unexpected uart_puts return'
    words = [int.from_bytes(base[a:a + 4], 'little') for a in range(CHECK_START, CHECK_END, 4)]
    total = sum(words) & MASK
    checksum = 0
    for word in words:
        checksum ^= word
    assert (total, checksum) == (EXPECTED_SUM, EXPECTED_XOR), 'Base rodata checksum differs from repository image'

    a = Assembler(origin)
    a.li(SP, RAM_BYTES)
    a.li(UART, 0x10000000)
    a.li(FAIL, 0)
    a.text('CPU_UART_PROBE v2\r\n')
    golden = 'CPU_UART_PROBE v2\r\n'

    for address, expected in zip(WORD_ADDRESSES, EXPECTED_WORDS):
        a.li(29, address)
        a.load(9, 29)
        for lane, reg in enumerate((18, 19, 20, 21)):
            a.load(reg, 29, lane, byte=True)
        a.expect(9, expected)
        for lane, reg in enumerate((18, 19, 20, 21)):
            a.expect(reg, (expected >> (lane * 8)) & 255)
        a.text(f'W@{address:04X}=')
        a.hex(9)
        a.text(' B=')
        for lane, reg in enumerate((18, 19, 20, 21)):
            a.hex(reg, 2)
            a.text(' ' if lane < 3 else '\r\n')
        golden += f'W@{address:04X}={expected:08X} B=' + ' '.join(f'{v:02X}' for v in expected.to_bytes(4, 'little')) + '\r\n'

    for address in NUL_ADDRESSES:
        zero, done = a.unique('zero'), a.unique('zero_done')
        a.li(29, address)
        a.load(22, 29, byte=True)
        # The first instruction after LBU tests zero, before any UART output.
        a.branch(22, 0, 0, zero)
        a.li(23, 0)
        a.li(FAIL, 1)
        a.jump(done)
        a.label(zero)
        a.li(23, 1)
        a.label(done)
        a.text(f'Z@{address:04X}=')
        a.hex(22, 2)
        a.text(' ZERO=')
        a.addi(31, 23, 48)
        a.store(31, UART, 4)
        a.text('\r\n')
        golden += f'Z@{address:04X}=00 ZERO=1\r\n'

    a.li(18, 0)
    a.li(19, 0)
    a.li(20, CHECK_START)
    a.li(21, CHECK_END)
    a.label('checksum_loop')
    a.load(22, 20)
    a.alu(18, 18, 22, 0)  # ADD
    a.alu(19, 19, 22, 4)  # XOR
    a.addi(20, 20, 4)
    a.branch(20, 21, 6, 'checksum_loop')
    a.expect(18, EXPECTED_SUM)
    a.expect(19, EXPECTED_XOR)
    a.text('SUM=')
    a.hex(18)
    a.text(' XOR=')
    a.hex(19)
    a.text('\r\n')
    golden += f'SUM={EXPECTED_SUM:08X} XOR={EXPECTED_XOR:08X}\r\n'
    a.branch(FAIL, 0, 1, 'memory_bad')
    a.text('MEM CHECK PASS\r\n')
    a.jump('memory_done')
    a.label('memory_bad')
    a.text('MEM CHECK FAIL\r\n')
    a.label('memory_done')
    golden += 'MEM CHECK PASS\r\n'

    if with_puts:
        a.text('PUTS_BEGIN\r\n')
        a.li(A0, 0x21b8)
        a.jump(PUTS_START, RA)
        a.text('PUTS_END\r\n')
        golden += 'PUTS_BEGIN\r\n\r\nPUTS_END\r\n'

    a.load(9, UART, 0x1c)
    a.text('RX INITIAL ST=')
    a.hex(9)
    a.load(26, UART, 0x00)  # s10: one-second period from the actual CLK_HZ MMIO.
    a.load(24, UART, 0x0c)  # s8: cycle timestamp, survives text/hex routines.
    a.text('\r\nRX READY\r\n')
    golden += 'RX INITIAL ST=00000000\r\nRX READY\r\n'
    a.label('rx_poll')
    a.load(9, UART, 0x1c)
    a.andi(25, 9, 1)  # s9 preserves this exact status mask through hex output.
    a.branch(25, 0, 1, 'rx_data')
    a.load(22, UART, 0x0c)
    a.alu(23, 22, 24, 0, 0x20)  # SUB; unsigned delta is safe across cycle wrap.
    a.branch(23, 26, 6, 'rx_poll')
    a.mov(24, 22)
    a.text('WAIT ST=')
    a.hex(9)
    a.text(' M=')
    a.hex(25)
    a.text('\r\n')
    a.jump('rx_poll')
    a.label('rx_data')
    a.load(18, UART, 0x18)
    a.text('RX ST=')
    a.hex(9)
    a.text(' DATA=')
    a.hex(18)
    a.text('\r\n')
    a.jump('rx_poll')

    a.label('hex_out')
    a.mov(5, A1)
    a.label('hex_loop')
    a.alu(6, A0, 5, 5)  # SRL
    a.andi(6, 6, 15)
    a.li(7, 10)
    a.branch(6, 7, 6, 'hex_digit')
    a.addi(6, 6, 55)
    a.jump('hex_emit')
    a.label('hex_digit')
    a.addi(6, 6, 48)
    a.label('hex_emit')
    a.store(6, UART, 4)
    a.addi(5, 5, -4)
    a.branch(5, 0, 5, 'hex_loop')  # BGE signed
    a.emit(i_type(0x67, 0, 0, RA, 0))

    program = a.finish()
    assert origin + len(program) <= 0x1000, 'Probe instructions would overwrite preserved high memory'
    output = bytearray(base)
    output[0:4] = j_type(0, origin).to_bytes(4, 'little')
    output[origin:origin + len(program)] = program
    assert output[0x1000:] == base[0x1000:]
    assert output[PUTS_START:PUTS_END] == base[PUTS_START:PUTS_END]
    info = {
        'architecture': 'RV32I', 'ram_words': RAM_BYTES // 4,
        'origin': origin, 'program_bytes': len(program), 'program_end_exclusive': origin + len(program),
        'reset_word': f'{int.from_bytes(output[:4], "little"):08x}',
        'range_after_0x1000_preserved': True,
        'original_puts_test_enabled': with_puts,
        'original_puts_entry': PUTS_START, 'original_puts_end_exclusive': PUTS_END,
        'original_puts_preserved': True,
        'probe_version': 2,
        'wait_report': {'format': 'WAIT ST=xxxxxxxx M=xxxxxxxx', 'period_cycles_source': 'IO_CLK 0x10000000', 'timestamp_source': 'IO_CYCLES 0x1000000c', 'only_on_no_data_path': True},
        'expected_words': {f'{addr:04x}': f'{word:08x}' for addr, word in zip(WORD_ADDRESSES, EXPECTED_WORDS)},
        'nul_addresses': [f'{addr:04x}' for addr in NUL_ADDRESSES],
        'checksum_range': {'start': CHECK_START, 'end_exclusive': CHECK_END, 'words': len(words), 'sum32': f'{EXPECTED_SUM:08x}', 'xor32': f'{EXPECTED_XOR:08x}'},
        'labels': {name: value for name, value in a.labels.items()},
    }
    return bytes(output), golden, info


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-hex', type=Path, default=Path('firmware/interactive.hex'))
    parser.add_argument('--output', type=Path, default=Path('firmware/uart_cpu_probe.hex'))
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--expected-output', type=Path)
    parser.add_argument('--origin', type=lambda value: int(value, 0), default=0x400)
    parser.add_argument('--skip-original-puts', action='store_true')
    args = parser.parse_args()
    source_text = args.base_hex.read_bytes()
    lines = source_text.decode('ascii').split()
    if len(lines) != RAM_BYTES // 4 or any(len(word) != 8 for word in lines):
        parser.error('Base HEX must contain exactly 8192 eight-digit words')
    base = b''.join(int(word, 16).to_bytes(4, 'little') for word in lines)
    output, expected, manifest = build(base, args.origin, not args.skip_original_puts)
    hex_text = ''.join(f'{int.from_bytes(output[pos:pos + 4], "little"):08x}\n' for pos in range(0, RAM_BYTES, 4)).encode('ascii')
    assert args.output.resolve() != args.base_hex.resolve(), 'Output must not overwrite the original interactive HEX'
    manifest.update({
        'base_hex_sha256': sha256(source_text), 'base_image_sha256': sha256(base),
        'output_hex_sha256': sha256(hex_text), 'output_image_sha256': sha256(output),
        'base_hex_git_blob_sha1': hashlib.sha1(b'blob ' + str(len(source_text)).encode() + b'\0' + source_text).hexdigest(),
    })
    manifest_path = args.manifest or args.output.with_name('manifest.json')
    expected_path = args.expected_output or args.output.with_name('expected_output.txt')
    for path in (args.output, manifest_path, expected_path):
        path.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(hex_text)
    expected_path.write_bytes(expected.encode('ascii'))
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    print(f'Generated {args.output}: reset JAL + {len(output)}-byte RAM image; probe code {manifest["program_bytes"]} bytes at 0x{args.origin:x}')
    print(f'Preserved all bytes at/above 0x1000 and original uart_puts [0x{PUTS_START:x},0x{PUTS_END:x})')


if __name__ == '__main__':
    main()
