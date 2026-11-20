#ifndef NX_CLI_I2C_H
#define NX_CLI_I2C_H
#include "platform.h"
enum {
    RC_OK = 0u, RC_NACK = 1u, RC_TIMEOUT = 2u, RC_MISMATCH = 3u,
    RC_ARGUMENT = 4u, RC_OWNER = 5u
};
#define DEV_CFG      0x00u
#define DEV_CTRL     0x04u
#define DEV_CMD      0x08u
#define DEV_STATUS   0x0cu
#define DEV_RD       0x10u
#define DEV_SHADOW   0x20u
#define DEV_PADDR    0x40u
#define ST_BUSY      0x01u
#define ST_DONE      0x02u
#define ST_NACK      0x04u
#define ST_AUTOVALID 0x08u

void bus_init(void);
uint32_t bus_address(uint32_t channel);
uint32_t bus_set_address(uint32_t channel, uint32_t address);
uint32_t bus_base(uint32_t channel);
uint32_t bus_owner(void);
uint32_t bus_set_owner(uint32_t cpu);
uint32_t bus_read(uint32_t channel, uint32_t reg, uint32_t *value, uint32_t timeout_ms);
uint32_t bus_write(uint32_t channel, uint32_t reg, uint32_t value, uint32_t timeout_ms);
uint32_t bus_write_verify(uint32_t channel, uint32_t reg, uint32_t value,
                          uint32_t timeout_ms, uint32_t *original,
                          uint32_t *observed, uint32_t *restore_result);
uint32_t bus_poll(uint32_t channel, const uint32_t addresses[8], uint32_t gap,
                  uint32_t timeout_ms, uint32_t values[8]);
void bus_publish(uint32_t channel, uint32_t kind, uint32_t reg,
                 uint32_t expected, uint32_t actual, uint32_t result,
                 uint32_t slot, uint32_t status);
#endif
