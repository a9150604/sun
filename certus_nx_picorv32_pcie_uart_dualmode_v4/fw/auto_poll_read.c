#include "common.h"
#include "config/poll_read_config.h"
int main(void){
 init_common();
 delay_ms(START_DELAY_MS);start_test();
 set_dev_addr(TEST_CH,TEST_DEV_ADDR);
 const uint8_t poll_bytes[8]={POLL_ADDR0,POLL_ADDR1,POLL_ADDR2,POLL_ADDR3,
                              POLL_ADDR4,POLL_ADDR5,POLL_ADDR6,POLL_ADDR7};
 uint8_t values[8]={0};
 int rc=poll_read(TEST_CH,poll_bytes,POLL_GAP_CYCLES,TIMEOUT_MS,values);
 end_test(rc);
 request_pcie_after_test(RETURN_TO_PCIE_AFTER_TEST);
 for(;;)heartbeat();
}
