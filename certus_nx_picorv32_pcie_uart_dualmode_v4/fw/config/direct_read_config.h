// Edit, then rebuild and re-implement FPGA to include the new HEX.
#define TEST_CH          0u          // 0..3
#define TEST_DEV_ADDR    0x50u       // 7-bit I2C slave address
#define TEST_REG_ADDR    0x00u       // CMIS register byte address
#define START_DELAY_MS   3000u       // delay after CPU reset and FPGA ready
#define TIMEOUT_MS       500u
// Optional known-data check. A zero MASK tests only I2C transfer success.
#define EXPECTED_VALUE   0x00u
#define EXPECTED_MASK    0x00u

#define RETURN_TO_PCIE_AFTER_TEST 0u // 1: request PCIe owner after auto test (host driver must coordinate)
