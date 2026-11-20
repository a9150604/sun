#ifndef NX_CLI_PLATFORM_H
#define NX_CLI_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
#ifndef CLI_RX_TRACE
#define CLI_RX_TRACE 0
#endif

#define IO_CLK        0x10000000u
#define IO_TX         0x10000004u
#define IO_TXSTATUS   0x10000008u
#define IO_CYCLES     0x1000000cu
#define IO_LED        0x10000010u
#define IO_RX         0x10000018u
#define IO_RXSTATUS   0x1000001cu
#define IO_OWNER_REQ  0x10000020u
#define IO_OWNER_ACT  0x10000024u
#define IO_IRQ        0x10000028u
#define IO_DBG_EVT    0x10000030u
#define IO_DBG_AUX    0x10000034u
#define AXI_BASE      0x40000000u

#define LED_RUNNING  0x02u
#define LED_DONE     0x04u
#define LED_PASS     0x08u
#define LED_FAIL     0x10u
#define LED_NACK     0x20u
#define LED_TIMEOUT  0x40u

uint32_t io_read(uint32_t address);
void io_write(uint32_t address, uint32_t value);
uint32_t rom_byte(const void *address);
void platform_init(void);
void platform_poll(void);
uint32_t platform_clock_hz(void);
uint32_t platform_now(void);
uint32_t platform_elapsed(uint32_t start, uint32_t milliseconds);
void platform_delay(uint32_t milliseconds);
void platform_led(uint32_t clear_mask, uint32_t set_mask);
void platform_test_begin(void);
void platform_test_end(uint32_t result);
void uart_put(uint32_t character);
void uart_literal(const void *text, uint32_t length);
void uart_hex(uint32_t value, uint32_t digits);
uint32_t uart_take(uint32_t *character);
uint32_t uart_received(void);
uint32_t uart_hardware_overruns(void);
uint32_t uart_queue_drops(void);
void uart_discard_input(void);
#if CLI_RX_TRACE
uint32_t uart_trace_word(void);
#endif

#define OUT(literal) uart_literal((literal), (uint32_t)(sizeof(literal) - 1u))
#endif
