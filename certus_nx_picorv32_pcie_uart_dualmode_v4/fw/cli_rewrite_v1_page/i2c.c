/*
 * Word-access I2C4 register driver for the independent CLI rewrite.
 * No I2C transactions are initiated at boot.  Waiting services the local UART
 * and heartbeat; only foreground command execution changes these registers.
 */
#include "i2c.h"

#define CHANNELS       4u
#define REGISTER_LIMIT 0xffu
#define CTRL_AUTO      0x01u
#define CTRL_START     0x02u
#define CTRL_READ      0x04u
#define CTRL_CLEAR     0x10u

static uint32_t device_addresses[CHANNELS];

void bus_init(void)
{
    uint32_t channel;
    for (channel = 0u; channel < CHANNELS; ++channel) {
        device_addresses[channel] = 0x50u;
    }
}

uint32_t bus_base(uint32_t channel)
{
    if (channel >= CHANNELS) {
        return 0u;
    }
    return AXI_BASE + ((channel + 1u) << 8);
}

uint32_t bus_address(uint32_t channel)
{
    return channel < CHANNELS ? device_addresses[channel] : 0u;
}

uint32_t bus_owner(void)
{
    return io_read(IO_OWNER_ACT) & 1u;
}

uint32_t bus_set_owner(uint32_t cpu)
{
    uint32_t started;
    if (cpu > 1u) {
        return RC_ARGUMENT;
    }
    io_write(IO_OWNER_REQ, cpu);
    started = platform_now();
    for (;;) {
        if (bus_owner() == cpu) {
            return RC_OK;
        }
        if (platform_elapsed(started, 250u)) {
            return RC_TIMEOUT;
        }
        platform_poll();
    }
}

uint32_t bus_set_address(uint32_t channel, uint32_t address)
{
    uint32_t base;
    uint32_t configuration;
    if (channel >= CHANNELS || address == 0u || address > 0x7fu) {
        return RC_ARGUMENT;
    }
    device_addresses[channel] = address;
    /* In PCIe mode, remember the choice for the next CPU command only. */
    if (bus_owner()) {
        base = bus_base(channel);
        configuration = io_read(base + DEV_CFG);
        io_write(base + DEV_CFG, (configuration & ~0x7fu) | address);
    }
    return RC_OK;
}

/* need_done=0 waits for an idle controller; need_done=1 waits for completion. */
static uint32_t await_status(uint32_t base, uint32_t timeout_ms,
                             uint32_t need_done, uint32_t *status)
{
    uint32_t started = platform_now();
    uint32_t sample;
    for (;;) {
        if (!bus_owner()) {
            return RC_OWNER;
        }
        sample = io_read(base + DEV_STATUS);
        if (status != NULL) {
            *status = sample;
        }
        if (need_done != 0u) {
            if ((sample & ST_DONE) != 0u) {
                return (sample & ST_NACK) != 0u ? RC_NACK : RC_OK;
            }
        } else if ((sample & ST_BUSY) == 0u) {
            return RC_OK;
        }
        if (platform_elapsed(started, timeout_ms)) {
            return RC_TIMEOUT;
        }
        platform_poll();
    }
}

static uint32_t prepare(uint32_t channel, uint32_t timeout_ms)
{
    uint32_t base = bus_base(channel);
    uint32_t configuration;
    uint32_t result;
    if (!bus_owner()) {
        return RC_OWNER;
    }
    /* Disable automatic polling, then let its current transaction drain. */
    io_write(base + DEV_CTRL, 0u);
    result = await_status(base, timeout_ms, 0u, NULL);
    if (result != RC_OK) {
        return result;
    }
    io_write(base + DEV_CTRL, CTRL_CLEAR);
    configuration = io_read(base + DEV_CFG);
    io_write(base + DEV_CFG,
             (configuration & ~0x7fu) | device_addresses[channel]);
    return RC_OK;
}

uint32_t bus_read(uint32_t channel, uint32_t reg, uint32_t *value,
                   uint32_t timeout_ms)
{
    uint32_t base;
    uint32_t result;
    if (value != NULL) {
        *value = 0u;
    }
    if (channel >= CHANNELS || reg > REGISTER_LIMIT ||
        value == NULL || timeout_ms == 0u) {
        return RC_ARGUMENT;
    }
    result = prepare(channel, timeout_ms);
    if (result != RC_OK) {
        return result;
    }
    base = bus_base(channel);
    io_write(base + DEV_CMD, reg);
    io_write(base + DEV_CTRL, CTRL_START | CTRL_READ);
    result = await_status(base, timeout_ms, 1u, NULL);
    if (result == RC_OK) {
        *value = io_read(base + DEV_RD) & 0xffu;
    }
    return result;
}

uint32_t bus_write(uint32_t channel, uint32_t reg, uint32_t value,
                    uint32_t timeout_ms)
{
    uint32_t result;
    uint32_t base;
    if (channel >= CHANNELS || reg > REGISTER_LIMIT ||
        value > 0xffu || timeout_ms == 0u) {
        return RC_ARGUMENT;
    }
    result = prepare(channel, timeout_ms);
    if (result != RC_OK) {
        return result;
    }
    base = bus_base(channel);
    io_write(base + DEV_CMD, (value << 8) | reg);
    io_write(base + DEV_CTRL, CTRL_START);
    return await_status(base, timeout_ms, 1u, NULL);
}

uint32_t bus_write_verify(uint32_t channel, uint32_t reg, uint32_t value,
                          uint32_t timeout_ms, uint32_t *original,
                          uint32_t *observed, uint32_t *restore_result)
{
    uint32_t operation_result;
    uint32_t restoration;
    uint32_t restored = 0u;
    uint32_t status = 0u;
    uint32_t result;
    if (original == NULL || observed == NULL || restore_result == NULL) {
        return RC_ARGUMENT;
    }
    *original = 0u;
    *observed = 0u;
    /* No restoration is needed until a write has actually been attempted. */
    *restore_result = RC_OK;
    if (channel >= CHANNELS || reg > REGISTER_LIMIT || value > 0xffu ||
        timeout_ms == 0u || reg == 0x7eu || reg == 0x7fu) {
        return RC_ARGUMENT;
    }
    operation_result = bus_read(channel, reg, original, timeout_ms);
    if (operation_result != RC_OK) {
        return operation_result;
    }

    operation_result = bus_write(channel, reg, value, timeout_ms);
    if (operation_result == RC_OK) {
        operation_result = bus_read(channel, reg, observed, timeout_ms);
        if (operation_result == RC_OK && *observed != value) {
            operation_result = RC_MISMATCH;
        }
    }

    /* A failed write can still have changed the device: always try restoring. */
    restoration = bus_write(channel, reg, *original, timeout_ms);
    if (restoration == RC_OK) {
        restoration = bus_read(channel, reg, &restored, timeout_ms);
        if (restoration == RC_OK && restored != *original) {
            restoration = RC_MISMATCH;
        }
    }
    *restore_result = restoration;
    result = restoration == RC_OK ? operation_result : RC_MISMATCH;
    if (bus_owner()) {
        status = io_read(bus_base(channel) + DEV_STATUS);
    }
    if (restoration != RC_OK) {
        /* Existing Reveal AUX status bit15 marks restoration failure. */
        status |= 0x8000u;
    }
    bus_publish(channel, 1u, reg, value, *observed, result, 0u, status);
    return result;
}

uint32_t bus_poll(uint32_t channel, const uint32_t addresses[8], uint32_t gap,
                   uint32_t timeout_ms, uint32_t values[8])
{
    uint32_t base;
    uint32_t configuration;
    uint32_t previous;
    uint32_t current;
    uint32_t wraps = 0u;
    uint32_t started;
    uint32_t status;
    uint32_t result = RC_TIMEOUT;
    uint32_t stop_result;
    uint32_t slot;
    if (addresses == NULL || values == NULL) {
        return RC_ARGUMENT;
    }
    for (slot = 0u; slot < 8u; ++slot) {
        values[slot] = 0u;
        if (addresses[slot] > REGISTER_LIMIT) {
            return RC_ARGUMENT;
        }
    }
    if (channel >= CHANNELS || gap > 0xffffu || timeout_ms == 0u) {
        return RC_ARGUMENT;
    }
    result = prepare(channel, timeout_ms);
    if (result != RC_OK) {
        return result;
    }
    base = bus_base(channel);
    configuration = io_read(base + DEV_CFG);
    io_write(base + DEV_CFG,
             (gap << 16) | (configuration & 0x0000ff80u) |
             device_addresses[channel]);
    for (slot = 0u; slot < 8u; ++slot) {
        io_write(base + DEV_PADDR + (slot << 2), addresses[slot]);
    }
    status = io_read(base + DEV_STATUS);
    previous = (status >> 4) & 7u;
    io_write(base + DEV_CTRL, CTRL_AUTO);
    started = platform_now();
    result = RC_TIMEOUT;
    for (;;) {
        if (!bus_owner()) {
            return RC_OWNER;
        }
        status = io_read(base + DEV_STATUS);
        current = (status >> 4) & 7u;
        if (previous == 7u && current == 0u) {
            ++wraps;
        }
        previous = current;
        if (wraps >= 2u && (status & ST_AUTOVALID) != 0u) {
            result = RC_OK;
            break;
        }
        if (platform_elapsed(started, timeout_ms)) {
            break;
        }
        platform_poll();
    }
    io_write(base + DEV_CTRL, 0u);
    stop_result = await_status(base, timeout_ms, 0u, &status);
    if (stop_result != RC_OK) {
        result = stop_result;
    }
    if (!bus_owner()) {
        return RC_OWNER;
    }
    status = io_read(base + DEV_STATUS);
    if (result == RC_OK && (status & ST_AUTOVALID) == 0u) {
        result = RC_TIMEOUT;
    }
    for (slot = 0u; slot < 8u; ++slot) {
        values[slot] = io_read(base + DEV_SHADOW + (slot << 2)) & 0xffu;
        bus_publish(channel, 2u, addresses[slot], 0u, values[slot],
                     result, slot, status);
    }
    /*
     * AUTOVALID is sticky and the controller has no per-slot ACK result.
     * Two observed wraps establish the freshness criterion used here only;
     * RC_OK must not be presented as proof that all eight slots ACKed.
     */
    return result;
}

void bus_publish(uint32_t channel, uint32_t kind, uint32_t reg,
                   uint32_t expected, uint32_t actual, uint32_t result,
                   uint32_t slot, uint32_t status)
{
    uint32_t event;
    uint32_t auxiliary;
    if (channel >= CHANNELS) {
        return;
    }
    auxiliary = (device_addresses[channel] << 24) |
                ((slot & 0xffu) << 16) | (status & 0xffffu);
    event = 0x80000000u | (result == RC_OK ? 0x40000000u : 0u) |
            ((kind & 3u) << 28) | ((channel & 3u) << 26) |
            ((reg & 0xffu) << 18) | ((expected & 0xffu) << 10) |
            ((actual & 0xffu) << 2) | (result & 3u);
    io_write(IO_DBG_AUX, auxiliary);
    io_write(IO_DBG_EVT, event);
}
