// Auto poll all eight slots on one I2C channel; each slot address configurable.
#define TEST_CH          0u
#define TEST_DEV_ADDR    0x50u
#define START_DELAY_MS   3000u
#define TIMEOUT_MS       2500u
#define POLL_GAP_CYCLES  1000u
#define POLL_ADDR0       0x00u
#define POLL_ADDR1       0x01u
#define POLL_ADDR2       0x02u
#define POLL_ADDR3       0x03u
#define POLL_ADDR4       0x04u
#define POLL_ADDR5       0x05u
#define POLL_ADDR6       0x06u
#define POLL_ADDR7       0x07u

#define RETURN_TO_PCIE_AFTER_TEST 0u // 1: request PCIe owner after auto test (host driver must coordinate)
