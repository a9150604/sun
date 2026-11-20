OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
}
PHDRS {
    code PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS {
    . = ORIGIN(RAM);
    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
        . = ALIGN(4);
    } > RAM :code
    .rodata : ALIGN(4) {
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > RAM :code
    .data : ALIGN(4) {
        __data_start = .;
        *(.sdata .sdata.*)
        *(.data .data.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM :data
    __global_pointer$ = __data_start + 0x800;
    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM :data
    __image_end = .;
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    __stack_reserved = 4096;
    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
    }
}
ASSERT(_start == ORIGIN(RAM), "Reset entry must be address zero");
ASSERT((__bss_start & 3) == 0 && (__bss_end & 3) == 0,
       "BSS must be word aligned");
ASSERT(__image_end <= __stack_top - __stack_reserved,
       "Firmware/BSS overlap the reserved 4 KiB stack");

