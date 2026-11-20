#include "platform.h"

/* Independent RV32I platform layer. All mutable objects and RAM transfers are
 * word-sized. Literal output has an explicit length; no sentinel scan is used. */
#define RX_CAPACITY 128u
#define RX_MASK (RX_CAPACITY - 1u)
static uint32_t rx_queue[RX_CAPACITY];
static uint32_t rx_head, rx_tail, received_count, overrun_count, drop_count;
static uint32_t overrun_latched;
#if CLI_RX_TRACE
static uint32_t trace_taken_word;
#endif
static uint32_t clock_hz, ticks_per_ms, max_timeout_ms;
static uint32_t heartbeat_start, heartbeat_value, led_flags;

__attribute__((noinline)) uint32_t io_read(uint32_t address) {
    return *(volatile uint32_t *)(uintptr_t)address;
}

__attribute__((noinline)) void io_write(uint32_t address, uint32_t value) {
    *(volatile uint32_t *)(uintptr_t)address = value;
}

__attribute__((noinline)) uint32_t rom_byte(const void *address) {
    uintptr_t p = (uintptr_t)address;
    uint32_t word = *(const volatile uint32_t *)(p & ~(uintptr_t)3u);
    return (word >> ((p & 3u) << 3)) & 255u;
}

static uint32_t divide_u32(uint32_t numerator, uint32_t denominator) {
    uint32_t quotient = 0u, remainder = 0u, bits = 32u;
    if (denominator == 0u) return 0u;
    do {
        uint32_t carry = remainder >> 31;
        remainder = (remainder << 1) | (numerator >> 31);
        numerator <<= 1;
        quotient <<= 1;
        if (carry || remainder >= denominator) {
            remainder -= denominator;
            quotient |= 1u;
        }
    } while (--bits);
    return quotient;
}

static uint32_t multiply_u32(uint32_t left, uint32_t right) {
    uint32_t value = 0u;
    while (right) {
        if (right & 1u) value += left;
        left <<= 1;
        right >>= 1;
    }
    return value;
}

static void service_rx(void) {
    uint32_t status = io_read(IO_RXSTATUS);
    if (status & 2u) {
        if (!overrun_latched) ++overrun_count;
        overrun_latched = 1u;
    } else {
        overrun_latched = 0u;
    }
    if (status & 1u) {
#if CLI_RX_TRACE
        uint32_t character = io_read(IO_RX);
#else
        uint32_t character = io_read(IO_RX) & 255u;
#endif
        uint32_t next = (rx_head + 1u) & RX_MASK;
        ++received_count;
        /* A completed data read clears the hardware valid/overrun flags. */
        overrun_latched = 0u;
        if (next == rx_tail) {
            ++drop_count;
        } else {
            rx_queue[rx_head] = character;
            rx_head = next;
        }
    }
}

static void heartbeat(void) {
    uint32_t current = io_read(IO_CYCLES);
    uint32_t period = clock_hz >> 2;
    if ((uint32_t)(current - heartbeat_start) >= period) {
        heartbeat_start = current;
        heartbeat_value ^= 1u;
        io_write(IO_LED, led_flags | heartbeat_value);
    }
}

void platform_init(void) {
    rx_head = rx_tail = received_count = overrun_count = drop_count = 0u;
    overrun_latched = heartbeat_value = led_flags = 0u;
    clock_hz = io_read(IO_CLK);
    if (clock_hz < 1000u || clock_hz > 1000000000u) clock_hz = 125000000u;
    ticks_per_ms = divide_u32(clock_hz, 1000u);
    max_timeout_ms = divide_u32(0x7fffffffu, ticks_per_ms);
    heartbeat_start = io_read(IO_CYCLES);
    io_write(IO_LED, 0u);
    uart_discard_input();
}

void platform_poll(void) {
    service_rx();
    heartbeat();
}

uint32_t platform_clock_hz(void) { return clock_hz; }
uint32_t platform_now(void) { return io_read(IO_CYCLES); }

uint32_t platform_elapsed(uint32_t start, uint32_t milliseconds) {
    uint32_t budget = milliseconds > max_timeout_ms
        ? 0x7fffffffu : multiply_u32(ticks_per_ms, milliseconds);
    return (uint32_t)(platform_now() - start) >= budget;
}

void platform_delay(uint32_t milliseconds) {
    while (milliseconds) {
        uint32_t step = milliseconds > 1000u ? 1000u : milliseconds;
        uint32_t budget = multiply_u32(ticks_per_ms, step);
        uint32_t start = platform_now();
        while ((uint32_t)(platform_now() - start) < budget) platform_poll();
        milliseconds -= step;
    }
}

void platform_led(uint32_t clear_mask, uint32_t set_mask) {
    led_flags = ((led_flags & ~clear_mask) | set_mask) & 0x7eu;
    io_write(IO_LED, led_flags | heartbeat_value);
}

void platform_test_begin(void) { platform_led(0x7eu, LED_RUNNING); }

void platform_test_end(uint32_t result) {
    uint32_t flags = LED_DONE | (result == 0u ? LED_PASS : LED_FAIL);
    if (result == 1u) flags |= LED_NACK;
    if (result == 2u) flags |= LED_TIMEOUT;
    platform_led(0x7eu, flags);
}

void uart_put(uint32_t character) {
    /* Poll the TX-ready register first so the CPU can drain RX while waiting. */
    do {
        platform_poll();
    } while ((io_read(IO_TXSTATUS) & 1u) == 0u);
    io_write(IO_TX, character & 255u);
}

void uart_literal(const void *text, uint32_t length) {
    const uintptr_t address = (uintptr_t)text;
    uint32_t i;
    for (i = 0u; i < length; ++i) uart_put(rom_byte((const void *)(address + i)));
}

void uart_hex(uint32_t value, uint32_t digits) {
    uint32_t shift;
    if (digits == 0u || digits > 8u) return;
    shift = (digits - 1u) << 2;
    for (;;) {
        uint32_t nibble = (value >> shift) & 15u;
        uart_put(nibble < 10u ? nibble + 48u : nibble + 55u);
        if (shift == 0u) break;
        shift -= 4u;
    }
}

uint32_t uart_take(uint32_t *character) {
    platform_poll();
    if (rx_head == rx_tail) return 0u;
#if CLI_RX_TRACE
    trace_taken_word = rx_queue[rx_tail];
    *character = trace_taken_word & 255u;
#else
    *character = rx_queue[rx_tail];
#endif
    rx_tail = (rx_tail + 1u) & RX_MASK;
    return 1u;
}

uint32_t uart_received(void) { return received_count; }
uint32_t uart_hardware_overruns(void) { return overrun_count; }
uint32_t uart_queue_drops(void) { return drop_count; }
#if CLI_RX_TRACE
uint32_t uart_trace_word(void) { return trace_taken_word; }
#endif

void uart_discard_input(void) {
    rx_tail = rx_head;
    if (io_read(IO_RXSTATUS) & 1u) (void)io_read(IO_RX);
    overrun_latched = 0u;
}
