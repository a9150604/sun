// Direct Write is DISABLED by default. Confirm target register with vendor CMIS map.
#define TEST_CH           0u
#define TEST_DEV_ADDR     0x50u
#define TEST_REG_ADDR     0x80u
#define TEST_WRITE_DATA   0x55u
#define START_DELAY_MS    3000u
#define TIMEOUT_MS        500u
#define ENABLE_WRITE_TEST 0u // change to 1 only for vendor-approved ordinary RW register
#define RESTORE_ORIGINAL  1u // 1: read original/write/read/restore/verify
// DO NOT target W1C, volatile, action-trigger, reserved, paging/bank select.

#define RETURN_TO_PCIE_AFTER_TEST 0u // 1: request PCIe owner after auto test (host driver must coordinate)
