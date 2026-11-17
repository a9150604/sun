OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  .text 0 : { KEEP(*(.text.start)) *(.text .text.*) }
  .rodata : ALIGN(4) { *(.rodata .rodata.*) }
  __image_end = .;
  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
ASSERT(_start == 0, "Reset entry must be zero");
ASSERT(__image_end <= 0x2000, "Diagnostic code overlaps first address-distinct test location");
