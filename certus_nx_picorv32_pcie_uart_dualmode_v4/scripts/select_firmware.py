#!/usr/bin/env python3
from pathlib import Path
import shutil,sys
modes=('interactive','auto_direct_read','auto_direct_write','auto_poll_read')
if len(sys.argv)!=2 or sys.argv[1] not in modes:
    sys.exit('Usage: python scripts/select_firmware.py '+ '|'.join(modes))
root=Path(__file__).resolve().parent.parent
src=root/'firmware'/ (sys.argv[1]+'.hex')
if not src.is_file():sys.exit('Missing '+str(src))
dst=root/'firmware.hex'
shutil.copyfile(src,dst)
print('Selected',sys.argv[1],'=>',dst)
