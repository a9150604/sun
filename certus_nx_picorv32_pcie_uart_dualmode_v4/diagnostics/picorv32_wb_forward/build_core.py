#!/usr/bin/env python3
"""Reproduce the pinned project-specific writeback-forwarding candidate.

The official core is read and hash-checked, never overwritten.
"""
from pathlib import Path
import difflib,hashlib,json
MAIN=Path(__file__).resolve().parents[2]
WORK=Path(__file__).resolve().parent
BASE_SHA='0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622'
base=(MAIN/'third_party/picorv32.v').read_bytes();assert hashlib.sha256(base).hexdigest()==BASE_SHA
text=base.decode()
header='''/* Project-specific diagnostic candidate for a9150604/sun UART SoC.
 * Derived from YosysHQ/picorv32 ef203c2b0a3fb793280f5114941416c425c5b461.
 * Original picorv32.v SHA256:
 * 0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622
 * Adds previous-edge writeback forwarding for the internal RF only.
 * Project validation: RV32I, 32 registers, dual read ports, IRQ disabled.
 * Not a generally verified upstream replacement; board validation pending.
 * External RF, formal-blackbox RF and intentional TESTBUG modes are unchanged.
 */
'''
text=text.replace('/* verilator lint_off WIDTH */',header+'\n/* verilator lint_off WIDTH */',1)
start=text.index('`ifndef PICORV32_REGS\n\talways @(posedge clk) begin',text.index('reg cpuregs_write'))
end=text.index('`else\n\twire[31:0] cpuregs_rdata1;',start)
body=text[start:end]
anchor="\talways @* begin\n\t\tdecoded_rs = 'bx;"
capture='''`ifndef RISCV_FORMAL_BLACKBOX_REGS
`ifndef PICORV32_TESTBUG_001
`ifndef PICORV32_TESTBUG_002
	// This copy represents the most recent completed architectural RF write.
	reg wb_recent_valid;
	reg [regindex_bits-1:0] wb_recent_rd;
	reg [31:0] wb_recent_data;
	always @(posedge clk) begin
		wb_recent_valid <= resetn && cpuregs_write && latched_rd;
		if (resetn && cpuregs_write && latched_rd) begin
			wb_recent_rd <= latched_rd;
			wb_recent_data <= cpuregs_wrdata;
		end
	end
`endif
`endif
`endif

'''
assert body.count(anchor)==1;body=body.replace(anchor,capture+anchor,1)
anchor='''			cpuregs_rs1 = decoded_rs1 ? cpuregs[decoded_rs1] : 0;
			cpuregs_rs2 = decoded_rs2 ? cpuregs[decoded_rs2] : 0;'''
replacement=anchor+'''
`ifndef PICORV32_TESTBUG_001
`ifndef PICORV32_TESTBUG_002
			if (decoded_rs1 && wb_recent_valid && decoded_rs1 == wb_recent_rd)
				cpuregs_rs1 = wb_recent_data;
			if (decoded_rs2 && wb_recent_valid && decoded_rs2 == wb_recent_rd)
				cpuregs_rs2 = wb_recent_data;
`endif
`endif'''
assert body.count(anchor)==1;body=body.replace(anchor,replacement,1)
text=text[:start]+body+text[end:]

expected_sha='c51201ed368df602fb1c2499795ad5eef12c335abb05c11b7f24bd9437b5943d'
encoded=text.encode()
if hashlib.sha256(encoded).hexdigest()!=expected_sha:
    raise SystemExit('Generated candidate differs from validated bytes')
output=WORK/'picorv32_wb_forward.v'
output.write_bytes(encoded)
(WORK/'upstream_vs_candidate.diff').write_text(''.join(difflib.unified_diff(base.decode().splitlines(True),text.splitlines(True),fromfile='third_party/picorv32.v',tofile='picorv32_wb_forward.v')))
manifest={
  'kind':'Project-specific internal dual-port register writeback-forwarding candidate',
  'upstream_commit':'ef203c2b0a3fb793280f5114941416c425c5b461',
  'original_file':'third_party/picorv32.v',
  'original_sha256':BASE_SHA,
  'candidate_file':'diagnostics/picorv32_wb_forward/picorv32_wb_forward.v',
  'candidate_sha256':expected_sha,
  'candidate_bytes':len(encoded),
  'original_preserved':(MAIN/'third_party/picorv32.v').read_bytes()==base,
  'tested_configuration':{'ENABLE_REGS_16_31':1,'ENABLE_REGS_DUALPORT':1,'ENABLE_IRQ':0,'COMPRESSED_ISA':0,'clock_hz':125000000,'baud':115200},
  'mechanism':'Capture the previous rising-edge nonzero register write and forward matching internal dual-port read operands.',
  'scope':'Board candidate, not an upstream change or established Radiant root-cause proof.',
  'unmodified_modes':['PICORV32_REGS external register file','RISCV_FORMAL_BLACKBOX_REGS','PICORV32_TESTBUG_001','PICORV32_TESTBUG_002','single-port read path'],
  'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
  'limitations':['Actual mapped RF and routing are not available.','Synthesis may remove redundant bypass logic; mapped retention or equivalent correct behavior and timing must be checked.','No post-route SDF simulation or board validation of this candidate has been performed.'],
}
(WORK/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'output':str(output),'sha256':expected_sha,'original_preserved':manifest['original_preserved']},indent=2))
