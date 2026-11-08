#ifndef COMMON_H
#define COMMON_H
#include <stdint.h>
#define MMIO(x) (*(volatile uint32_t *)(uintptr_t)(x))
#define IO_CLK       0x10000000u
#define IO_TX        0x10000004u
#define IO_CYCLES    0x1000000Cu
#define IO_LED       0x10000010u
#define IO_RX        0x10000018u
#define IO_RXSTATUS  0x1000001Cu
#define IO_OWNER_REQ 0x10000020u
#define IO_OWNER_ACT 0x10000024u
#define IO_IRQ       0x10000028u
#define IO_DBG_EVT   0x10000030u
#define IO_DBG_AUX   0x10000034u
#define AXI_BASE     0x40000000u
#define AXI_ID       0x0000u
#define AXI_VERSION  0x0004u
#define AXI_IRQ      0x000Cu
#define DEV_CFG      0x00u
#define DEV_CTRL     0x04u
#define DEV_CMD      0x08u
#define DEV_STATUS   0x0Cu
#define DEV_RD       0x10u
#define DEV_SHADOW   0x20u
#define DEV_PADDR    0x40u
#define CTRL_AUTO    1u
#define CTRL_START   2u
#define CTRL_RD      4u
#define CTRL_CLEAR   16u
#define ST_BUSY      1u
#define ST_DONE      2u
#define ST_NACK      4u
#define ST_AUTOVALID 8u
#define LED_HB       1u
#define LED_RUNNING  2u
#define LED_DONE     4u
#define LED_PASS     8u
#define LED_FAIL    16u
#define LED_NACK    32u
#define LED_TIMEOUT 64u
// LED7 is wired to CPU trap in RTL, not normal software control.
enum {RC_OK=0, RC_NACK=1, RC_TIMEOUT=2, RC_MISMATCH=3, RC_ARG=4, RC_OWNER=5};
enum {EV_READ=0,EV_WRITE=1,EV_POLL=2,EV_ERROR=3};
extern uint32_t clk_hz;
extern uint8_t led_flags;
extern uint8_t current_dev[4];
void heartbeat(void);
void delay_ms(uint32_t ms);
void led_set(uint8_t clear_mask,uint8_t set_mask);
void uart_putc(char c);
void uart_puts(const char *s);
void print_hex8(uint8_t v);
void print_hex16(uint16_t v);
void print_hex32(uint32_t v);
void print_result(const char *s,int rc);
uint32_t dev_base(unsigned channel);
void set_dev_addr(unsigned ch,uint8_t addr);
int direct_read(unsigned ch,uint8_t reg,uint8_t *value,uint32_t timeout_ms);
int direct_write(unsigned ch,uint8_t reg,uint8_t value,uint32_t timeout_ms);
int direct_write_restore(unsigned ch,uint8_t reg,uint8_t test_value,uint32_t timeout_ms);
int poll_read(unsigned ch,const uint8_t poll_addrs[8],uint16_t gap,
              uint32_t timeout_ms,uint8_t out[8]);
void publish(unsigned ch,unsigned kind,unsigned reg,unsigned expected,
             unsigned actual,unsigned rc,unsigned slot,uint32_t status);
void init_common(void);
void start_test(void);
void end_test(int rc);
void request_pcie_after_test(unsigned enable);
void report_read(unsigned ch,uint8_t reg,int rc,uint8_t value);
#endif
