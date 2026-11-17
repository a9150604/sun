OUTPUT_ARCH(riscv)
ENTRY(probe_init)
SECTIONS {
  .patch_init 0x1408 : { *(.patch_init) }
  .patch_poll 0x14c8 : { *(.patch_poll) }
  .patch_check 0x15e0 : { *(.patch_check) }
  .patch_load 0x15f0 : { *(.patch_load) }
  .patch_append 0x2578 : { *(.patch_append) }
  .text 0x4000 : { *(.text) *(.text.*) }
  .rodata : ALIGN(4) { *(.rodata) *(.rodata.*) }
  __probe_end = .;
  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
ASSERT(SIZEOF(.patch_init) == 8, "init patch must be exactly 8 bytes");
ASSERT(SIZEOF(.patch_poll) == 8, "poll patch must be exactly 8 bytes");
ASSERT(SIZEOF(.patch_check) == 8, "check patch must be exactly 8 bytes");
ASSERT(SIZEOF(.patch_load) == 4, "load patch must be exactly 4 bytes");
ASSERT(SIZEOF(.patch_append) == 8, "append patch must be exactly 8 bytes");
ASSERT(__probe_end <= 0x6000, "probe overlaps snapshot data");
