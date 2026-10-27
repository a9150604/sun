ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K }
SECTIONS {
  . = ORIGIN(RAM);
  .text : { KEEP(*(.text.init)) *(.text .text.*) *(.rodata .rodata.*) } > RAM
  . = ALIGN(4);
  .data : { *(.sdata .sdata.*) *(.data .data.*) } > RAM
  . = ALIGN(4);
  _sbss = .;
  .bss (NOLOAD) : { *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) } > RAM
  . = ALIGN(4);
  _ebss = .;
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
ASSERT(_ebss < (_stack_top - 2048), "RAM used beyond reserved 2 KiB stack");
