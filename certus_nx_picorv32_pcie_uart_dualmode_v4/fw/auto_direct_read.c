#include "common.h"
#include "config/direct_read_config.h"
int main(void){
 init_common();
 delay_ms(START_DELAY_MS);start_test();
 set_dev_addr(TEST_CH,TEST_DEV_ADDR);
 uint8_t v=0;
 int rc=direct_read(TEST_CH,TEST_REG_ADDR,&v,TIMEOUT_MS);
 if(rc==RC_OK && EXPECTED_MASK && ((v^EXPECTED_VALUE)&EXPECTED_MASK))rc=RC_MISMATCH;
 report_read(TEST_CH,TEST_REG_ADDR,rc,v);
 end_test(rc);
 request_pcie_after_test(RETURN_TO_PCIE_AFTER_TEST);
 for(;;)heartbeat();
}
