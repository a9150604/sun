/* Independent length-delimited CLI. Data buffers contain 32-bit character words;
 * ROM text is read through rom_byte(), which uses aligned word loads.
 * No command parser or output routine depends on NUL termination. */
#include "i2c.h"

#define LINE_WORDS 96u
#define TOKEN_LIMIT 4u

typedef struct {
    uint32_t start;
    uint32_t length;
} token_t;

static uint32_t line_words[LINE_WORDS];
static uint32_t line_length;
static uint32_t line_bad;
static uint32_t after_cr;
static uint32_t selected_channel;
static uint32_t selected_register;
static uint32_t selected_data;
static uint32_t writes_unlocked;
static uint32_t timeout_ms;
static uint32_t poll_gap;
static uint32_t poll_addresses[8];
static uint32_t last_overruns;
static uint32_t last_drops;

#define MATCH(token, literal) token_matches(&(token), (literal), \
                                            (uint32_t)(sizeof(literal) - 1u))

static uint32_t token_matches(const token_t *token, const void *literal,
                              uint32_t length)
{
    uint32_t index;
    const unsigned char *bytes = (const unsigned char *)literal;
    if (token->length != length) return 0u;
    for (index = 0u; index < length; ++index) {
        if (line_words[token->start + index] != rom_byte(bytes + index)) return 0u;
    }
    return 1u;
}

static uint32_t whitespace(uint32_t character)
{
    return character == 32u || character == 9u;
}

/* Returning TOKEN_LIMIT+1 rejects extra arguments instead of ignoring them. */
static uint32_t split_tokens(token_t tokens[TOKEN_LIMIT])
{
    uint32_t position = 0u;
    uint32_t count = 0u;
    while (position < line_length) {
        while (position < line_length && whitespace(line_words[position])) ++position;
        if (position == line_length) break;
        if (count == TOKEN_LIMIT) return TOKEN_LIMIT + 1u;
        tokens[count].start = position;
        while (position < line_length && !whitespace(line_words[position])) ++position;
        tokens[count].length = position - tokens[count].start;
        ++count;
    }
    return count;
}

static uint32_t parse_hex(const token_t *token, uint32_t *number)
{
    uint32_t position = token->start;
    uint32_t end = position + token->length;
    uint32_t digits = 0u;
    uint32_t value = 0u;
    if (token->length >= 2u && line_words[position] == '0' &&
        (line_words[position + 1u] == 'x' || line_words[position + 1u] == 'X')) {
        position += 2u;
    }
    while (position < end) {
        uint32_t character = line_words[position++];
        uint32_t digit;
        if (character >= '0' && character <= '9') digit = character - '0';
        else if (character >= 'a' && character <= 'f') digit = character - 'a' + 10u;
        else if (character >= 'A' && character <= 'F') digit = character - 'A' + 10u;
        else return 0u;
        if (digits == 8u) return 0u;
        value = (value << 4) | digit;
        ++digits;
    }
    if (digits == 0u) return 0u;
    *number = value;
    return 1u;
}

static uint32_t parse_decimal(const token_t *token, uint32_t *number)
{
    uint32_t index;
    uint32_t value = 0u;
    if (token->length == 0u || token->length > 10u) return 0u;
    for (index = 0u; index < token->length; ++index) {
        uint32_t character = line_words[token->start + index];
        uint32_t digit;
        if (character < '0' || character > '9') return 0u;
        digit = character - '0';
        if (value > 429496729u || (value == 429496729u && digit > 5u)) return 0u;
        value = (value << 3) + (value << 1) + digit;
    }
    *number = value;
    return 1u;
}

static void result(uint32_t code)
{
    if (code == RC_OK) OUT("OK\r\n");
    else {
        OUT("ERR rc=0x");
        uart_hex(code, 2u);
        OUT("\r\n");
    }
}

static void prompt(void)
{
    OUT("osfp> ");
}

static void help(void)
{
    OUT("Commands (hex numbers; delay uses decimal milliseconds):\r\n"
        " help | status | id | mode cpu|pcie\r\n"
        " ch 0..3 | dev 01..7F | reg 00..FF | data 00..FF\r\n"
        " read [reg] | unlock | lock | write [reg] [data]\r\n"
        " writeverify [reg] [data]  (read, test, read, restore)\r\n"
        " pollset <slot 0..7> <reg> | pollgap <hex> | poll\r\n"
        " timeout <hex ms 0A..1388> | delay <decimal ms 0..600000>\r\n"
        " Writes start locked; bank/page registers 7E/7F are blocked.\r\n");
}

static void status(void)
{
    OUT("owner_cpu="); uart_hex(bus_owner(), 1u);
    OUT(" ch="); uart_hex(selected_channel, 1u);
    OUT(" dev=0x"); uart_hex(bus_address(selected_channel), 2u);
    OUT(" reg=0x"); uart_hex(selected_register, 2u);
    OUT(" data=0x"); uart_hex(selected_data, 2u);
    OUT(" writes_unlocked="); uart_hex(writes_unlocked, 1u);
    OUT(" irq=0x"); uart_hex(io_read(IO_IRQ) & 15u, 1u);
    OUT("\r\nclock_hz=0x"); uart_hex(platform_clock_hz(), 8u);
    OUT(" timeout_ms=0x"); uart_hex(timeout_ms, 8u);
    OUT(" poll_gap=0x"); uart_hex(poll_gap, 4u);
    OUT("\r\nrx_bytes=0x"); uart_hex(uart_received(), 8u);
    OUT(" hardware_overruns=0x"); uart_hex(uart_hardware_overruns(), 8u);
    OUT(" queue_drops=0x"); uart_hex(uart_queue_drops(), 8u);
    OUT("\r\n");
}

static uint32_t read_device_status(void)
{
    if (bus_owner() == 0u) return 0u;
    return io_read(bus_base(selected_channel) + DEV_STATUS);
}

static void direct_read(uint32_t reg)
{
    uint32_t value = 0u;
    uint32_t code;
    platform_test_begin();
    code = bus_read(selected_channel, reg, &value, timeout_ms);
    bus_publish(selected_channel, 0u, reg, 0u, value, code, 0u, read_device_status());
    OUT("READ ch="); uart_hex(selected_channel, 1u);
    OUT(" reg=0x"); uart_hex(reg, 2u);
    OUT(" value=0x"); uart_hex(value, 2u);
    OUT(" rc=0x"); uart_hex(code, 2u); OUT("\r\n");
    platform_test_end(code);
}

static void direct_write(uint32_t reg, uint32_t value, uint32_t verify)
{
    uint32_t code;
    if (writes_unlocked == 0u) {
        OUT("ERR writes locked; type unlock first\r\n");
        return;
    }
    if (reg == 0x7eu || reg == 0x7fu) {
        OUT("ERR bank/page register requires a separate CMIS sequence\r\n");
        return;
    }
    platform_test_begin();
    if (verify != 0u) {
        uint32_t original = 0u;
        uint32_t observed = 0u;
        uint32_t restore_code = RC_OK;
        code = bus_write_verify(selected_channel, reg, value, timeout_ms,
                                &original, &observed, &restore_code);
        OUT("WRITEVERIFY original=0x"); uart_hex(original, 2u);
        OUT(" observed=0x"); uart_hex(observed, 2u);
        OUT(" restore_rc=0x"); uart_hex(restore_code, 2u);
    } else {
        code = bus_write(selected_channel, reg, value, timeout_ms);
        bus_publish(selected_channel, 1u, reg, value, value, code, 0u, read_device_status());
        OUT("WRITE");
    }
    OUT(" reg=0x"); uart_hex(reg, 2u);
    OUT(" data=0x"); uart_hex(value, 2u);
    OUT(" rc=0x"); uart_hex(code, 2u); OUT("\r\n");
    platform_test_end(code);
}

static void poll(void)
{
    uint32_t values[8];
    uint32_t index;
    uint32_t code;
    for (index = 0u; index < 8u; ++index) values[index] = 0u;
    platform_test_begin();
    code = bus_poll(selected_channel, poll_addresses, poll_gap, 2000u, values);
    for (index = 0u; index < 8u; ++index) {
        OUT("POLL slot="); uart_hex(index, 1u);
        OUT(" reg=0x"); uart_hex(poll_addresses[index], 2u);
        OUT(" value=0x"); uart_hex(values[index], 2u); OUT("\r\n");
    }
    OUT("POLL rc=0x"); uart_hex(code, 2u);
    OUT(" (poll cycle check; per-slot ACK unavailable)\r\n");
    platform_test_end(code);
}

static void execute_line(void)
{
    token_t tokens[TOKEN_LIMIT];
    uint32_t count = split_tokens(tokens);
    uint32_t value;
    if (count == 0u) return;
    if (count > TOKEN_LIMIT) {
        OUT("ERR too many arguments\r\n");
        return;
    }
    if (MATCH(tokens[0], "help")) {
        if (count != 1u) OUT("usage: help\r\n");
        else help();
    } else if (MATCH(tokens[0], "status")) {
        if (count != 1u) OUT("usage: status\r\n");
        else status();
    } else if (MATCH(tokens[0], "id")) {
        if (count != 1u) OUT("usage: id\r\n");
        else if (bus_owner() == 0u) OUT("ERR PCIe owns I2C; mode cpu first\r\n");
        else {
            OUT("AXI ID=0x"); uart_hex(io_read(AXI_BASE), 8u);
            OUT(" VERSION=0x"); uart_hex(io_read(AXI_BASE + 4u), 8u);
            OUT("\r\n");
        }
    } else if (MATCH(tokens[0], "mode")) {
        if (count != 2u || (!MATCH(tokens[1], "cpu") && !MATCH(tokens[1], "pcie"))) {
            OUT("usage: mode cpu|pcie\r\n");
        } else {
            uint32_t code = bus_set_owner(MATCH(tokens[1], "cpu"));
            OUT("owner_cpu="); uart_hex(bus_owner(), 1u);
            OUT(" rc=0x"); uart_hex(code, 2u); OUT("\r\n");
        }
    } else if (MATCH(tokens[0], "unlock")) {
        if (count != 1u) OUT("usage: unlock\r\n");
        else { writes_unlocked = 1u; OUT("OK writes unlocked\r\n"); }
    } else if (MATCH(tokens[0], "lock")) {
        if (count != 1u) OUT("usage: lock\r\n");
        else { writes_unlocked = 0u; OUT("OK writes locked\r\n"); }
    } else if (MATCH(tokens[0], "ch")) {
        if (count != 2u || !parse_hex(&tokens[1], &value) || value > 3u) {
            OUT("usage: ch 0..3\r\n");
        } else {
            selected_channel = value;
            OUT("OK ch="); uart_hex(value, 1u); OUT("\r\n");
        }
    } else if (MATCH(tokens[0], "dev")) {
        if (count != 2u || !parse_hex(&tokens[1], &value) || value == 0u || value > 127u) {
            OUT("usage: dev 01..7F\r\n");
        } else result(bus_set_address(selected_channel, value));
    } else if (MATCH(tokens[0], "reg")) {
        if (count != 2u || !parse_hex(&tokens[1], &value) || value > 255u) {
            OUT("usage: reg 00..FF\r\n");
        } else { selected_register = value; OUT("OK\r\n"); }
    } else if (MATCH(tokens[0], "data")) {
        if (count != 2u || !parse_hex(&tokens[1], &value) || value > 255u) {
            OUT("usage: data 00..FF\r\n");
        } else { selected_data = value; OUT("OK\r\n"); }
    } else if (MATCH(tokens[0], "timeout")) {
        if (count != 2u || !parse_hex(&tokens[1], &value) || value < 10u || value > 5000u) {
            OUT("usage: timeout <hex ms 0A..1388>\r\n");
        } else { timeout_ms = value; OUT("OK\r\n"); }
    } else if (MATCH(tokens[0], "pollgap")) {
        if (count != 2u || !parse_hex(&tokens[1], &value) || value > 65535u) {
            OUT("usage: pollgap <hex 0000..FFFF>\r\n");
        } else { poll_gap = value; OUT("OK\r\n"); }
    } else if (MATCH(tokens[0], "delay")) {
        if (count != 2u || !parse_decimal(&tokens[1], &value) || value > 600000u) {
            OUT("usage: delay <decimal ms 0..600000>\r\n");
        } else {
            OUT("DELAY\r\n"); platform_delay(value); OUT("OK\r\n");
        }
    } else if (MATCH(tokens[0], "pollset")) {
        uint32_t address;
        if (count != 3u || !parse_hex(&tokens[1], &value) || value > 7u ||
            !parse_hex(&tokens[2], &address) || address > 255u) {
            OUT("usage: pollset <slot 0..7> <reg 00..FF>\r\n");
        } else { poll_addresses[value] = address; OUT("OK\r\n"); }
    } else if (MATCH(tokens[0], "read")) {
        value = selected_register;
        if (count > 2u || (count == 2u && (!parse_hex(&tokens[1], &value) || value > 255u))) {
            OUT("usage: read [reg 00..FF]\r\n");
        } else direct_read(value);
    } else if (MATCH(tokens[0], "write") || MATCH(tokens[0], "writeverify")) {
        uint32_t reg = selected_register;
        uint32_t data = selected_data;
        if (count > 3u ||
            (count >= 2u && (!parse_hex(&tokens[1], &reg) || reg > 255u)) ||
            (count == 3u && (!parse_hex(&tokens[2], &data) || data > 255u))) {
            OUT("usage: write|writeverify [reg 00..FF] [data 00..FF]\r\n");
        } else direct_write(reg, data, MATCH(tokens[0], "writeverify"));
    } else if (MATCH(tokens[0], "poll")) {
        if (count != 1u) OUT("usage: poll\r\n");
        else poll();
    } else OUT("ERR unknown command; help\r\n");
}

static uint32_t check_input_loss(void)
{
    uint32_t overruns = uart_hardware_overruns();
    uint32_t drops = uart_queue_drops();
    if (overruns != last_overruns || drops != last_drops) {
        last_overruns = overruns;
        last_drops = drops;
        line_length = 0u;
        /* Pending newlines may precede the dropped byte. Flush the queue, then
         * require a fresh Enter so a damaged suffix is never a command. */
        uart_discard_input();
        if (line_bad != 2u) OUT("\r\nERR UART input lost; press Enter\r\n");
        line_bad = 2u;
        after_cr = 0u;
        return 1u;
    }
    return 0u;
}

static void accept_character(uint32_t character)
{
    if (character == '\r' || character == '\n') {
        if (character == '\n' && after_cr != 0u) {
            after_cr = 0u;
            return;
        }
        after_cr = character == '\r';
        OUT("\r\n");
        if (line_bad == 1u) OUT("ERR line too long; command discarded\r\n");
        else if (line_bad != 0u) OUT("ERR command discarded\r\n");
        else execute_line();
        line_length = 0u;
        line_bad = 0u;
        prompt();
        return;
    }
    after_cr = 0u;
    if (line_bad != 0u) return;
    if (character == 8u || character == 127u) {
        if (line_length != 0u) {
            --line_length;
            OUT("\b \b");
        }
    } else if (character == 9u || (character >= 32u && character <= 126u)) {
        if (line_length == LINE_WORDS) {
            line_bad = 1u;
        } else {
            line_words[line_length++] = character;
            uart_put(character);
        }
    }
}

int main(void)
{
    uint32_t character;
    uint32_t index;
    platform_init();
    /* A CPU-only reset retains FPGA RAM: initialize mutable defaults in code. */
    timeout_ms = 500u;
    poll_gap = 1000u;
    for (index = 0u; index < 8u; ++index) poll_addresses[index] = index;
    last_overruns = uart_hardware_overruns();
    last_drops = uart_queue_drops();
    bus_init();
#if CLI_RX_TRACE
    OUT("\r\nOSFP CLI REWRITE v1 RXTRACE\r\n"
        "One key at a time; RAW is the word read from IO_RX.\r\n");
#else
    OUT("\r\nOSFP CLI REWRITE v1 (RV32I WORD IO)\r\n"
        "Type help for commands. Numbers are hex; delay is decimal ms.\r\n");
#endif
    prompt();
    for (;;) {
        platform_poll();
        (void)check_input_loss();
        if (uart_take(&character) != 0u) {
#if CLI_RX_TRACE
            OUT("\r\nRXTRACE RAW="); uart_hex(uart_trace_word(), 8u);
            OUT(" C="); uart_hex(character, 8u);
            OUT(" L="); uart_hex(line_length, 2u);
            OUT(" BAD="); uart_hex(line_bad, 1u);
            OUT(" HW="); uart_hex(uart_hardware_overruns(), 8u);
            OUT(" DROP="); uart_hex(uart_queue_drops(), 8u);
            OUT("\r\n");
#endif
            if (check_input_loss() == 0u) accept_character(character);
        }
    }
}
