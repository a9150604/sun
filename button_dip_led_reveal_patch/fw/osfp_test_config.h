#ifndef OSFP_TEST_CONFIG_H
#define OSFP_TEST_CONFIG_H
/*
 * CMIS OSFP test profile for FOUR independent I2C buses, each slave 0x50.
 * Byte addresses 0..127 are Lower Memory; 128..255 are an Upper Page window.
 *
 * DO NOT enable writes unless the exact module part number, firmware,
 * CMIS version, byte/bit semantics, and field side effects are verified
 * against your module vendor's documentation.
 *
 * A writable bit is NOT necessarily a safe bit to toggle; masks for
 * W1C, SC, WO, password, laser, TxDisable, reset, data path, etc. are UNSAFE.
 * A test that changes a live control bit can interrupt optics operation.
 */
#include <stdint.h>

#define OSFP_I2C_ADDR             0x50u
#define OSFP_DIRECT_TIMEOUT_MS   1500u
#define OSFP_AUTO_TIMEOUT_MS     12000u

/* Extra independent software guard: set BOTH switches to 1 only AFTER
 * supplying a vendor-approved profile below. The default runs READ ONLY. */
#define OSFP_ALLOW_WRITE_TEST    0
#define OSFP_WRITE_AUTH_KEY      0u
#define OSFP_WRITE_KEY_VALUE     0x4F534650u /* ASCII 'OSFP' */

/* Automatically read 8 stable Lower Memory bytes. These are identifiers /
 * metadata in CMIS; do not use clear-on-read flags or volatile monitors. */
static const uint8_t osfp_poll_bytes[8] = {
    0x00u, 0x01u, 0x02u, 0x00u,
    0x01u, 0x02u, 0x00u, 0x01u
};

/* Per-module expected SFF-8024 identifier: 0 = do not enforce exact ID.
 * A typical OSFP (QSFP8X) Identifier is 0x19, but confirm your part. */
static const uint8_t osfp_id_expected[4] = {0u, 0u, 0u, 0u};

typedef struct {
    uint8_t enabled;           /* 0 is default, requires explicit opt-in */
    uint8_t expected_id;       /* mandatory for write test, 0 is forbidden */
    uint8_t byte_addr;         /* must be confirmed regular RW field */
    uint8_t toggle_mask;       /* ONLY vendor-approved normal-RW bits */
    uint8_t expected_page;     /* for Upper Memory (byte >= 0x80) */
    uint8_t expected_bank;     /* for Upper Memory */
    uint8_t allow_page_change; /* if 1, may write ONLY byte 127 (NOT bank 126) */
    uint16_t settle_ms;        /* vendor-specified write/readback settle */
} osfp_rw_target_t;

/* Edit this table once the vendor confirms a harmless ordinary RW byte.
 * Not even a "safe" example register is invented here: OSFP/CMIS modules
 * vary by vendor, module type, mode and firmware.
 *
 * For Upper Memory, changing the bank requires an atomic two-byte I2C WRITE
 * to bytes 126..127, which this single-byte RTL master CANNOT perform.
 * Therefore the firmware NEVER changes BankSelect.
 */
static const osfp_rw_target_t osfp_rw_targets[4] = {
    {0, 0, 0x00, 0x00, 0x00, 0x00, 0, 0},
    {0, 0, 0x00, 0x00, 0x00, 0x00, 0, 0},
    {0, 0, 0x00, 0x00, 0x00, 0x00, 0, 0},
    {0, 0, 0x00, 0x00, 0x00, 0x00, 0, 0}
};

#endif
