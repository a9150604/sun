#!/usr/bin/env python3
"""Little-endian RV32 binary -> 32-bit $readmemh image padded to 64KiB."""
import pathlib,sys
inp=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);
data=inp.read_bytes()
size=65536
if len(data)>size: raise SystemExit(f'Firmware {len(data)} bytes > {size}')
data=data.ljust(size,b'\0')
out.write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,size,4)))
print(f'Generated {out} ({len(data)//4} words), payload {inp.stat().st_size} bytes')
