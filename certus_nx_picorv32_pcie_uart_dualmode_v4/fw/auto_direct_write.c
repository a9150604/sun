#include "common.h"
#include "config/direct_write_config.h"
int main(void){
 init_common();
 delay_ms(START_DELAY_MS);
 set_dev_addr(TEST_CH,TEST_DEV_ADDR);
#if ENABLE_WRITE_TEST
 if(TEST_REG_ADDR==0x7eu || TEST_REG_ADDR==0x7fu){
  start_test();end_test(RC_ARG);
 }else{
  start_test();int rc;
#if RESTORE_ORIGINAL
  rc=direct_write_restore(TEST_CH,TEST_REG_ADDR,TEST_WRITE_DATA,TIMEOUT_MS);
#else
  rc=direct_write(TEST_CH,TEST_REG_ADDR,TEST_WRITE_DATA,TIMEOUT_MS);
  publish(TEST_CH,EV_WRITE,TEST_REG_ADDR,TEST_WRITE_DATA,TEST_WRITE_DATA,
          rc,0,MMIO(dev_base(TEST_CH)+DEV_STATUS));
#endif
  end_test(rc);
 }
#else
 // Distinct state: LED DONE=1, no PASS or FAIL; test was intentionally skipped.
 led_set(LED_RUNNING,LED_DONE);
 publish(TEST_CH,EV_ERROR,TEST_REG_ADDR,TEST_WRITE_DATA,0,RC_ARG,0,0x8000u);
#endif
 request_pcie_after_test(RETURN_TO_PCIE_AFTER_TEST);
 for(;;)heartbeat();
}
