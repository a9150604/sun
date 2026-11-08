#!/usr/bin/env python3
import argparse,pathlib
p=argparse.ArgumentParser()
p.add_argument('infile');p.add_argument('outfile');p.add_argument('--ram-kb',type=int,default=32)
a=p.parse_args()
data=pathlib.Path(a.infile).read_bytes()
size=a.ram_kb*1024
if len(data)>size:raise SystemExit(f'firmware ({len(data)} bytes) exceeds {size}')
data=data.ljust(size,b'\0')
out=''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,size,4))
pathlib.Path(a.outfile).write_text(out)
print(a.outfile,len(data),'bytes')
