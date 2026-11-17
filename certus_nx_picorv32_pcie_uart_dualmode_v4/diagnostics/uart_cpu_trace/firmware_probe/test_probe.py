#!/usr/bin/env python3
"""Check the generated RV32I probe with an independent ideal-memory interpreter.

This does not validate physical RAM timing, RTL, or a board. UART writes are
captured at MMIO and incoming bytes are supplied one at a time after RX READY.
"""
from collections import deque
import argparse
import hashlib
import json
from pathlib import Path

MASK = 0xffffffff


def signed(value, width):
    value &= (1 << width) - 1
    return value - (1 << width) if value & (1 << (width - 1)) else value


class ProbeCPU:
    def __init__(self, data):
        self.ram = bytearray(data)
        self.x = [0] * 32
        self.pc = 0
        self.rx = deque()
        self.output = bytearray()
        self.instructions = 0
        self.rx_reads = 0
        self.cycle_offset = 0

    def load(self, address, size):
        assert size == 1 or address % 4 == 0, f'Unaligned load {address:08x}'
        if 0 <= address <= len(self.ram) - size:
            return int.from_bytes(self.ram[address:address + size], 'little')
        assert size == 4, 'Unexpected byte-sized MMIO'
        if address == 0x1000001c:
            return int(bool(self.rx))
        if address == 0x10000018:
            self.rx_reads += 1
            return self.rx.popleft() if self.rx else 0
        if address == 0x10000000:
            return 125000000
        if address == 0x1000000c:
            return (self.cycle_offset + self.instructions * 4) & MASK
        raise AssertionError(f'Unexpected MMIO read {address:08x}')

    def step(self):
        pc = self.pc
        ins = self.load(pc, 4)
        op, rd, f3 = ins & 127, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2 = (ins >> 15) & 31, (ins >> 20) & 31
        left, right = self.x[rs1], self.x[rs2]
        value = None
        next_pc = pc + 4
        if op == 0x37:
            value = ins & 0xfffff000
        elif op == 0x13:
            imm = signed(ins >> 20, 12)
            if f3 == 0:
                value = left + imm
            elif f3 == 7:
                value = left & imm
            else:
                raise AssertionError(f'Unexpected OP-IMM {ins:08x}')
        elif op == 0x33:
            f7 = ins >> 25
            assert f7 in (0, 0x20)
            if f3 == 0:
                value = left - right if f7 == 0x20 else left + right
            elif f3 == 4:
                assert f7 == 0
                value = left ^ right
            elif f3 == 5:
                assert f7 == 0
                value = left >> (right & 31)
            else:
                raise AssertionError(f'Unexpected OP {ins:08x}')
        elif op == 0x03:
            assert f3 in (2, 4)
            value = self.load((left + signed(ins >> 20, 12)) & MASK, 1 if f3 == 4 else 4)
        elif op == 0x23:
            assert f3 == 2
            imm = signed(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
            address = (left + imm) & MASK
            assert address == 0x10000004, f'Unexpected store {address:08x}'
            self.output.append(right & 255)
        elif op == 0x63:
            imm = ((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 63) << 5) | (((ins >> 8) & 15) << 1)
            condition = {0: left == right, 1: left != right,
                         5: signed(left, 32) >= signed(right, 32),
                         6: left < right}[f3]
            if condition:
                next_pc = pc + signed(imm, 13)
        elif op == 0x6f:
            imm = ((ins >> 31) << 20) | (((ins >> 12) & 255) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 1023) << 1)
            value, next_pc = pc + 4, pc + signed(imm, 21)
        elif op == 0x67:
            assert f3 == 0
            value, next_pc = pc + 4, (left + signed(ins >> 20, 12)) & ~1
        else:
            raise AssertionError(f'Unexpected instruction {ins:08x} at {pc:08x}')
        if value is not None and rd:
            self.x[rd] = value & MASK
        self.pc = next_pc & MASK
        self.instructions += 1

    def run_until(self, predicate, budget=200000):
        for _ in range(budget):
            self.step()
            if predicate():
                return
        raise AssertionError(f'Instruction budget exceeded at {self.pc:08x}')


def main():
    folder = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hex', dest='hex_path', type=Path,
                        default=folder.parents[2] / 'firmware' / 'uart_cpu_probe.hex')
    args = parser.parse_args()
    image_text = args.hex_path.read_bytes()
    image = b''.join(int(word, 16).to_bytes(4, 'little') for word in image_text.decode().split())
    expected = (folder / 'expected_output.txt').read_bytes()
    manifest = json.loads((folder / 'manifest.json').read_text())
    canonical_hex = ''.join(f'{int.from_bytes(image[i:i+4], "little"):08x}\n'
                            for i in range(0, len(image), 4)).encode('ascii')
    assert hashlib.sha256(canonical_hex).hexdigest() == manifest['output_hex_sha256']
    assert hashlib.sha256(image).hexdigest() == manifest['output_image_sha256']
    cpu = ProbeCPU(image)
    cpu.run_until(lambda: cpu.output.endswith(b'RX READY\r\n'))
    assert cpu.output == expected, f'Unexpected boot output:\n{cpu.output!r}'
    assert b'DIRECT_READ' not in cpu.output
    assert b'PUTS_BEGIN\r\n\r\nPUTS_END\r\n' in cpu.output
    print('PASS: exact boot output, LW/LBU words, NUL branches, checksums and original uart_puts stop at first NUL')
    before = len(cpu.output)
    for _ in range(1000):
        cpu.step()
    assert len(cpu.output) == before, 'WAIT output appeared before its one-second period'
    cpu.cycle_offset += 125000000
    cpu.run_until(lambda: bytes(cpu.output[before:]) == b'WAIT ST=00000000 M=00000000\r\n')
    print('PASS: one-second no-data WAIT reports raw status=0 and exact mask=0')
    before = len(cpu.output)
    for _ in range(1000):
        cpu.step()
    assert len(cpu.output) == before, 'WAIT output repeats without another elapsed second'
    # Exercise the same unsigned subtraction across a 32-bit uptime wrap.
    cpu.x[24] = 0xffffff00
    cpu.cycle_offset = (0xffffff00 - cpu.instructions * 4 + 125000000) & MASK
    cpu.run_until(lambda: bytes(cpu.output[before:]) == b'WAIT ST=00000000 M=00000000\r\n')
    print('PASS: WAIT does not flood, and unsigned elapsed-time check tolerates cycle-counter wrap')
    for byte in (0x41, 0x0d):
        before = len(cpu.output)
        cpu.rx.append(byte)
        line = f'RX ST=00000001 DATA={byte:08X}\r\n'.encode()
        cpu.run_until(lambda: bytes(cpu.output[before:]) == line)
        assert not cpu.rx
        print(f'PASS: raw RX byte {byte:02X} reported without CLI filtering')
    assert cpu.rx_reads == 2
    print(f'PASS: independent RV32I interpreter executed {cpu.instructions} instructions; RX reads=2; no unexpected memory stores')
    print(cpu.output.decode('ascii'))


if __name__ == '__main__':
    main()
