/* Diagnostic overlay for the NEW rewritten RXTRACE image only.
 * Original handler branch instructions and addresses are retained.
 * All snapshot/instrumentation transfers are aligned LW/SW.
 */
.option norvc
.option norelax

.equ ORIGINAL_PLATFORM_INIT, 0x5ac
.equ ORIGINAL_PLATFORM_POLL, 0xac
.equ ORIGINAL_CHECK_LOSS, 0x1248
.equ ORIGINAL_UART_PUT, 0x3ac
.equ ORIGINAL_UART_LITERAL, 0x3fc
.equ ORIGINAL_UART_HEX, 0x448
.equ SNAPSHOT, 0x6000
.equ LINE_BAD, 0x2f80
.equ LINE_LENGTH, 0x2f84
.equ LINE_WORDS, 0x2f88
.equ ORIGINAL_AFTER_LOAD_HOOK, 0x15f4

/* 128-byte frame; offset 0 keeps the outer callsite return address.
 * The macros never alter another register before saving its value. */
.macro SAVE_NONRA
    sw gp, 4(sp)
    sw tp, 8(sp)
    sw t0, 12(sp)
    sw t1, 16(sp)
    sw t2, 20(sp)
    sw s0, 24(sp)
    sw s1, 28(sp)
    sw a0, 32(sp)
    sw a1, 36(sp)
    sw a2, 40(sp)
    sw a3, 44(sp)
    sw a4, 48(sp)
    sw a5, 52(sp)
    sw a6, 56(sp)
    sw a7, 60(sp)
    sw s2, 64(sp)
    sw s3, 68(sp)
    sw s4, 72(sp)
    sw s5, 76(sp)
    sw s6, 80(sp)
    sw s7, 84(sp)
    sw s8, 88(sp)
    sw s9, 92(sp)
    sw s10, 96(sp)
    sw s11, 100(sp)
    sw t3, 104(sp)
    sw t4, 108(sp)
    sw t5, 112(sp)
    sw t6, 116(sp)
.endm

.macro RESTORE_NONRA
    lw gp, 4(sp)
    lw tp, 8(sp)
    lw t0, 12(sp)
    lw t1, 16(sp)
    lw t2, 20(sp)
    lw s0, 24(sp)
    lw s1, 28(sp)
    lw a0, 32(sp)
    lw a1, 36(sp)
    lw a2, 40(sp)
    lw a3, 44(sp)
    lw a4, 48(sp)
    lw a5, 52(sp)
    lw a6, 56(sp)
    lw a7, 60(sp)
    lw s2, 64(sp)
    lw s3, 68(sp)
    lw s4, 72(sp)
    lw s5, 76(sp)
    lw s6, 80(sp)
    lw s7, 84(sp)
    lw s8, 88(sp)
    lw s9, 92(sp)
    lw s10, 96(sp)
    lw s11, 100(sp)
    lw t3, 104(sp)
    lw t4, 108(sp)
    lw t5, 112(sp)
    lw t6, 116(sp)
.endm

.macro RETURN_OUTER
    lw ra, 0(sp)
    addi sp, sp, 128
    ret
.endm

.macro OUT label
    la a0, \label
    addi a1, zero, %lo(\label\()_len)
    call ORIGINAL_UART_LITERAL
.endm

.macro FIELD label, offset
    OUT \label
    li t0, SNAPSHOT
    lw a0, \offset(t0)
    li a1, 8
    call ORIGINAL_UART_HEX
.endm

.section .text,"ax",@progbits
.balign 4
.globl probe_init
.type probe_init,@function
probe_init:
    addi sp, sp, -128
    sw ra, 0(sp)
    call ORIGINAL_PLATFORM_INIT
    /* Preserve the original callee's output register state. */
    SAVE_NONRA
    li t0, SNAPSHOT
    li t1, 60
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -4
    bnez t1, 1b
    OUT banner
    RESTORE_NONRA
    RETURN_OUTER
.size probe_init, .-probe_init

.globl probe_check
.type probe_check,@function
probe_check:
    addi sp, sp, -128
    sw ra, 0(sp)
    call ORIGINAL_CHECK_LOSS
    /* Preserve all post-callee register values, including returned a0. */
    SAVE_NONRA
    li t0, SNAPSHOT
    lw t1, 32(sp)
    sw t1, 4(t0)             /* RET */
    lw t1, 156(sp)           /* original main SP + 28 */
    sw t1, 8(t0)             /* CPOST: wrapper re-read before original LW */
    lw t1, 92(sp)
    sw t1, 12(t0)            /* S9 */
    lw t1, 72(sp)
    sw t1, 16(t0)            /* S4 */
    lw t1, 76(sp)
    sw t1, 20(t0)            /* S5 */
    li t1, LINE_BAD
    lw t2, 0(t1)
    sw t2, 24(t0)            /* BAD0 */
    lw t2, 4(t1)
    sw t2, 28(t0)            /* LEN0 */
    sw zero, 32(t0)          /* APP reset per character */
    sw zero, 36(t0)          /* ECHO */
    sw zero, 40(t0)          /* LENA */
    sw zero, 52(t0)          /* LOAD: original reload reached */
    sw zero, 56(t0)          /* CLOAD: result of original LW */
    li t1, 1
    sw t1, 0(t0)             /* pending */
    RESTORE_NONRA
    RETURN_OUTER
.size probe_check, .-probe_check

.globl probe_load
.type probe_load,@function
probe_load:
    /* Entered through JAL x0 replacing LI a4,13 at original PC 0x15f0.
     * Thus a0 is the actual result of the original LW at 0x15ec. */
    addi sp, sp, -128
    sw ra, 0(sp)
    SAVE_NONRA
    li t0, SNAPSHOT
    li t1, 1
    sw t1, 52(t0)
    lw t1, 32(sp)
    sw t1, 56(t0)
    RESTORE_NONRA
    lw ra, 0(sp)
    addi sp, sp, 128
    li a4, 13               /* Replay the single replaced original instruction. */
    j ORIGINAL_AFTER_LOAD_HOOK
.size probe_load, .-probe_load

.globl probe_append
.type probe_append,@function
probe_append:
    addi sp, sp, -128
    sw ra, 0(sp)
    SAVE_NONRA
    li t0, SNAPSHOT
    li t1, 1
    sw t1, 32(t0)            /* APP: reached append-site uart_put call */
    lw t1, 32(sp)
    sw t1, 36(t0)            /* ECHO: call argument, not TX acknowledgement */
    li t1, LINE_LENGTH
    lw t2, 0(t1)
    sw t2, 40(t0)            /* LENA: append-time length readback */
    RESTORE_NONRA
    call ORIGINAL_UART_PUT
    RETURN_OUTER
.size probe_append, .-probe_append

.globl probe_poll
.type probe_poll,@function
probe_poll:
    addi sp, sp, -128
    sw ra, 0(sp)
    SAVE_NONRA
    li t0, SNAPSHOT
    lw t1, 0(t0)
    beqz t1, 2f
    /* Capture post-handler memory BEFORE any diagnostic output helper. */
    li t1, LINE_LENGTH
    lw t2, 0(t1)
    sw t2, 44(t0)            /* LEN1 */
    lw t2, 4(t1)
    sw t2, 48(t0)            /* BUF1 */
    sw zero, 0(t0)
    OUT prefix
    FIELD label_ret, 4
    FIELD label_cpost, 8
    FIELD label_load, 52
    FIELD label_cload, 56
    FIELD label_s9, 12
    FIELD label_s4, 16
    FIELD label_s5, 20
    FIELD label_bad0, 24
    FIELD label_len0, 28
    FIELD label_app, 32
    FIELD label_echo, 36
    FIELD label_lena, 40
    FIELD label_len1, 44
    FIELD label_buf1, 48
    OUT newline
2:
    RESTORE_NONRA
    call ORIGINAL_PLATFORM_POLL
    RETURN_OUTER
.size probe_poll, .-probe_poll

.section .rodata,"a",@progbits
.balign 4
banner:
    .ascii "\r\nRXPATH PROBE v1\r\nOne key at a time; RXPATH follows RXTRACE.\r\n"
.set banner_len, .-banner
prefix:
    .ascii "\r\nRXPATH"
.set prefix_len, .-prefix
label_ret: .ascii " RET="
.set label_ret_len, .-label_ret
label_cpost: .ascii " CPOST="
.set label_cpost_len, .-label_cpost
label_load: .ascii " LOAD="
.set label_load_len, .-label_load
label_cload: .ascii " CLOAD="
.set label_cload_len, .-label_cload
label_s9: .ascii " S9="
.set label_s9_len, .-label_s9
label_s4: .ascii " S4="
.set label_s4_len, .-label_s4
label_s5: .ascii " S5="
.set label_s5_len, .-label_s5
label_bad0: .ascii " BAD0="
.set label_bad0_len, .-label_bad0
label_len0: .ascii " LEN0="
.set label_len0_len, .-label_len0
label_app: .ascii " APP="
.set label_app_len, .-label_app
label_echo: .ascii " ECHO="
.set label_echo_len, .-label_echo
label_lena: .ascii " LENA="
.set label_lena_len, .-label_lena
label_len1: .ascii " LEN1="
.set label_len1_len, .-label_len1
label_buf1: .ascii " BUF1="
.set label_buf1_len, .-label_buf1
newline: .ascii "\r\n"
.set newline_len, .-newline
.balign 4
