#!/usr/bin/env python3
"""Synthetic one-instruction load-use old-value fixture; NOT a hardware diagnosis."""
from pathlib import Path
import sys
PROJECT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(PROJECT/'fw/cli_rewrite_v1/tests'))
from test_firmware import CPU
class LoadUseOldValue(CPU):
    """Next instruction reading a preceding LW destination sees its old value.
    The ideal CPU itself is unchanged; this explicit injected fault is solely
    a hypothesis fixture, not a model extracted from the synthesized FPGA.
    """
    def __init__(self,image):
        super().__init__(image); self.pending=None; self.fault_uses=0
    def step(self):
        insn=self.load(self.pc); op=insn&127; rd=(insn>>7)&31
        rs1=(insn>>15)&31; rs2=(insn>>20)&31
        sources=set()
        if op in [0x03,0x13,0x67,0x23,0x63,0x33]: sources.add(rs1)
        if op in [0x23,0x63,0x33]: sources.add(rs2)
        destination=rd if op in [0x03,0x13,0x17,0x33,0x37,0x67,0x6f] else 0
        before_rd=self.x[rd]; altered=None
        if self.pending and self.pending[0] in sources:
            reg,old=self.pending; altered=(reg,self.x[reg]); self.x[reg]=old
            self.fault_uses+=1
        self.pending=None
        super().step()
        if altered and destination!=altered[0]: self.x[altered[0]]=altered[1]
        if op==0x03 and rd: self.pending=(rd,before_rd)
