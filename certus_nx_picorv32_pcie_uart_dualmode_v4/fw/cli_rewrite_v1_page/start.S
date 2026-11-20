/* RV32I reset entry. RAM data is initialized by the FPGA HEX image. */
.section .text.start,"ax",@progbits
.option norvc
.option norelax
.globl _start
.type _start,@function
_start:
    la sp, __stack_top
    la gp, __global_pointer$
    la t0, __bss_start
    la t1, __bss_end
.Lclear_bss:
    bgeu t0, t1, .Lbss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j .Lclear_bss
.Lbss_done:
    call main
.Lreturned:
    j .Lreturned
.size _start, .-_start

