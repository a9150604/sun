// Standalone RV32I QSFP BIST. No libc, printf, dynamic allocation or interrupts.
// C may also be compiled as freestanding C++ with minor build-system changes.
#include <stdint.h>
#define MMIO32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define UART_TX       0x10000004u
#define UART_ST       0x10000008u
#define CYCLE_COUNTER 0x1000000Cu
#define LEDS          0x10000010u
#define GPIO_IN       0x10000014u
#define MSI_CTRL      0x10000020u
#define IRQ_STATUS    0x10000024u
#define MSI_STATUS    0x10000028u
#define I2C_BASE      0x40000000u
#define ID_OFFSET     0x0000u
#define VER_OFFSET    0x0004u
#define IRQ_OFFSET    0x000Cu
#define DEV_CFG       0x00u
#define DEV_CTRL      0x04u
#define DEV_CMD       0x08u
#define DEV_STATUS    0x0Cu
#define DEV_RDDATA    0x10u
#define POLL0         0x40u
#define SHADOW0       0x20u
#define ST_BUSY       1u
#define ST_DONE       2u
#define ST_ACK_ERR    4u
#define ST_AUTO_VALID 8u
#define CTRL_AUTO     1u
#define CTRL_START    2u
#define CTRL_RD       4u
#define CTRL_CLEAR    16u
#define CH_COUNT      4u
#define QSFP_ADDR     0x50u
#define ID_EXPECTED   0x49324334u
#define MMIO8(a) (*(volatile uint8_t *)(uintptr_t)(a))
#ifndef GOLDEN_QSFP0_ID
#define GOLDEN_QSFP0_ID 0xffffffffu
#endif
#ifndef GOLDEN_QSFP1_ID
#define GOLDEN_QSFP1_ID 0xffffffffu
#endif
#ifndef GOLDEN_QSFP2_ID
#define GOLDEN_QSFP2_ID 0xffffffffu
#endif
#ifndef GOLDEN_QSFP3_ID
#define GOLDEN_QSFP3_ID 0xffffffffu
#endif
static const uint32_t golden_id[4]={GOLDEN_QSFP0_ID,GOLDEN_QSFP1_ID,GOLDEN_QSFP2_ID,GOLDEN_QSFP3_ID};

// QSFP write tests must NEVER be automatic for production optics.
#ifndef ENABLE_QSFP_WRITE
#define ENABLE_QSFP_WRITE 0
#endif
#ifndef ENABLE_NACK_TEST
#define ENABLE_NACK_TEST 0
#endif
#ifndef REQUIRE_REAL_HOST_MSI
#define REQUIRE_REAL_HOST_MSI 0
#endif
#ifndef ENABLE_MSI_LOOPBACK_TEST
#define ENABLE_MSI_LOOPBACK_TEST 1
#endif
// For boards using 50MHz / 115200, UART controller has correct fixed baud at RTL.

static uint32_t pass_count, fail_count;
static uint32_t cpu_clock_hz;
static uint8_t identifiers[CH_COUNT];
static uint32_t last_test;

static uint32_t rd(uint32_t addr) { return MMIO32(addr); }
static void wr(uint32_t addr,uint32_t value) { MMIO32(addr)=value; }
static uint32_t dev(unsigned ch) { return I2C_BASE + 0x100u * (ch+1u); }
static uint32_t cycles(void) { return rd(CYCLE_COUNTER); }
static uint32_t ms_to_cycles(unsigned ms) {
  uint32_t per_ms=cpu_clock_hz/1000u;
  return per_ms*(uint32_t)ms;
}
static int timed_out(uint32_t start,uint32_t max_cycles) {
  return (uint32_t)(cycles()-start)>max_cycles;
}

static void putc_(char c){ wr(UART_TX, (uint8_t)c); }
static void puts_(const char *s) { while(*s) {if(*s=='\n')putc_('\r');putc_(*s++);} }
static void hex_digit(uint8_t x) { putc_((char)(x<10?'0'+x:'A'+x-10)); }
static void hex8(uint8_t x) {hex_digit(x>>4);hex_digit(x&15);}
static void hex32(uint32_t x) {for(unsigned i=0;i<8;i++)hex_digit((uint8_t)((x>>(28-4*i))&15));}
static void dec_(uint32_t x) {char b[11];unsigned n=0;do { b[n++]=(char)('0'+(x%10));x/=10;}while(x);
 while(n)putc_(b[--n]); }
static void hdr(unsigned test,const char *s) {last_test=test;puts_("[TC");dec_(test);puts_("] ");puts_(s);puts_(" ... ");}
static void verdict(int ok) {if(ok){pass_count++;puts_("PASS\n");}else{fail_count++;puts_("FAIL\n");}}
static void print_val(const char *name,uint32_t val) {puts_(name);puts_("=0x");hex32(val);puts_("\n");}

static void clear_irq(unsigned ch) {
  wr(dev(ch)+DEV_CTRL,CTRL_CLEAR);
}
static int wait_done(unsigned ch, unsigned ms, uint32_t *status) {
  uint32_t start=cycles();
  while(!timed_out(start,ms_to_cycles(ms))) {
    uint32_t v=rd(dev(ch)+DEV_STATUS);
    if(v&ST_DONE) {if(status)*status=v;return 0;}
  }
  if(status)*status=rd(dev(ch)+DEV_STATUS);
  return -1;
}
static int wait_idle(unsigned ch,unsigned ms){
  uint32_t st=cycles();
  while(!timed_out(st,ms_to_cycles(ms)))
    if(!(rd(dev(ch)+DEV_STATUS)&ST_BUSY))return 0;
  return -1;
}
static int qsfp_read(unsigned ch, uint8_t reg,uint8_t *result) {
  if(ch>=CH_COUNT || result==0)return -4;
  const uint32_t b=dev(ch);
  // No auto polling while direct transaction is underway.
  wr(b+DEV_CTRL,0u);
  if(wait_idle(ch,1500)!=0)return -3;
  clear_irq(ch);
  // Leave poll_gap unchanged while forcing 7-bit QSFP address.
  uint32_t cfg=rd(b+DEV_CFG);
  wr(b+DEV_CFG,(cfg&~0x7fu)|QSFP_ADDR);
  wr(b+DEV_CMD,(uint32_t)reg);
  wr(b+DEV_CTRL,CTRL_START|CTRL_RD);
  uint32_t st=0;
  if(wait_done(ch,1500,&st)!=0)return -3;
  if(st&ST_ACK_ERR)return -2;
  *result=(uint8_t)rd(b+DEV_RDDATA);
  return 0;
}
static int qsfp_write(unsigned ch, uint8_t reg,uint8_t value) {
  if(ch>=CH_COUNT)return -4;
  uint32_t b=dev(ch);
  wr(b+DEV_CTRL,0);
  if(wait_idle(ch,1500)!=0)return -3;
  clear_irq(ch);
  wr(b+DEV_CMD,((uint32_t)value<<8)|reg);
  wr(b+DEV_CTRL,CTRL_START);
  uint32_t st=0;
  if(wait_done(ch,1500,&st)!=0)return -3;
  if(st&ST_ACK_ERR)return -2;
  return 0;
}

static void test_axi_registers(void) {
  hdr(1,"AXI ID/VERSION");
  uint32_t id=rd(I2C_BASE+ID_OFFSET);
  uint32_t ver=rd(I2C_BASE+VER_OFFSET);
  verdict(id==ID_EXPECTED && ver!=0 && ver!=0xffffffffu);
  print_val("  ID ",id);print_val("  VER",ver);
  hdr(2,"AXI cfg W/R/restore, 4 channel decode");
  int ok=1;
  for(unsigned ch=0;ch<CH_COUNT;ch++){
    uint32_t b=dev(ch);uint32_t saved=rd(b+DEV_CFG);
    uint32_t written=(saved&0xFFFF0000u)|QSFP_ADDR;
    wr(b+DEV_CFG,written);
    uint32_t got=rd(b+DEV_CFG);
    if(got!=written)ok=0;
    // Verify AXI WSTRB[0] with an 8-bit CPU store, without touching QSFP.
    MMIO8(b+DEV_CFG) = 0x51u;
    uint32_t partial=rd(b+DEV_CFG);
    if(partial!=((written&~0x7fu)|0x51u))ok=0;
    MMIO8(b+DEV_CFG) = QSFP_ADDR;
    if(rd(b+DEV_CFG)!=written)ok=0;
    print_val("  CFG",got);
  }
  verdict(ok);
  hdr(3,"AXI invalid address decode");
  verdict(rd(I2C_BASE+0x0800u)==0xBAD0ADD0u);
}
static void test_four_qsfp(void) {
  for(unsigned ch=0;ch<CH_COUNT;ch++){
    puts_("[TC4] QSFP");dec_(ch);puts_(" READ ID reg0x00 ... ");
    uint8_t id=0;
    int rc=qsfp_read(ch,0,&id);
    identifiers[ch]=id;
    if(rc==0){puts_("0x");hex8(id);puts_(" ");}
    else{puts_("ERR ");dec_((uint32_t)(-rc));puts_(" ");}
    // Read valid only: device identity must be checked against real module type.
    int valid=(rc==0 && id!=0xffu && id!=0x00u);
    if(golden_id[ch]!=0xffffffffu && id!=(uint8_t)golden_id[ch])valid=0;
    verdict(valid);
    uint8_t repeat=0;
    puts_("[TC5] QSFP");dec_(ch);puts_(" repeated ID ... ");
    int rc2=qsfp_read(ch,0,&repeat);
    verdict(rc==0 && rc2==0 && repeat==id);
    uint32_t pending=rd(I2C_BASE+IRQ_OFFSET);
    puts_("[TC6] QSFP");dec_(ch);puts_(" sticky IRQ/status ... ");
    verdict(rc2==0 && ((pending>>ch)&1u) && (rd(dev(ch)+DEV_STATUS)&ST_DONE));
    clear_irq(ch);
    // Clear pulse propagates to i2c_device_ctrl a few CPU cycles later.
    uint32_t t=cycles();
    while((rd(I2C_BASE+IRQ_OFFSET)&(1u<<ch)) && !timed_out(t,ms_to_cycles(10)));
    puts_("[TC7] QSFP");dec_(ch);puts_(" IRQ clear ... ");
    verdict((rd(I2C_BASE+IRQ_OFFSET)&(1u<<ch))==0);
  }
}
static void test_auto_poll(void) {
  for(unsigned ch=0;ch<CH_COUNT;ch++){
    uint32_t b=dev(ch);
    hdr(8,"QSFP auto poll SHADOW0");
    wr(b+POLL0,0x00u);  // Only polling reg0 required for this check.
    wr(b+DEV_CTRL,CTRL_AUTO);
    uint32_t t=cycles();
    int have=0;
    while(!timed_out(t,ms_to_cycles(4000))) {
      uint32_t st=rd(b+DEV_STATUS);
      if(st&ST_AUTO_VALID){ have=1;break; }
    }
    uint32_t shadow=rd(b+SHADOW0);
    wr(b+DEV_CTRL,0);
    verdict(have && (uint8_t)shadow==identifiers[ch]);
    puts_("  CH ");dec_(ch);puts_(" SHADOW0=0x");hex8((uint8_t)shadow);puts_("\n");
  }
}
static void test_msi_handshake(void) {
#if ENABLE_MSI_LOOPBACK_TEST
  // Only proves request/ack logic when the standalone top loops ACK locally.
  hdr(9,"MSI SRC+ACK loopback (NOT host MSI)");
  for(unsigned ch=0;ch<CH_COUNT;ch++)clear_irq(ch);
  wr(MSI_CTRL,1);
  uint32_t old_ack=(rd(MSI_STATUS)>>2)&0xffffu;
  uint8_t value;
  int rc=qsfp_read(0,0,&value);
  uint32_t t=cycles();
  while((((rd(MSI_STATUS)>>2)&0xffffu)==old_ack) &&
         !timed_out(t,ms_to_cycles(1000)));
  uint32_t acked=(rd(MSI_STATUS)>>2)&0xffffu;
  int ok=(rc==0 && acked!=old_ack);
  clear_irq(0);wr(MSI_CTRL,0);
  verdict(ok);
  puts_("  MSI_ACK count=");dec_(acked);puts_(" (internal simulation only)\n");
#elif REQUIRE_REAL_HOST_MSI
  hdr(9,"MSI Host ACK requires PCIe Root Complex");
  puts_("SKIP (see driver integration)\n");
#else
  puts_("[TC9] MSI end-to-end: SKIP (no PCIe Host)\n");
#endif
}
static void test_nack_optional(void) {
#if ENABLE_NACK_TEST
  // CAUTION: only enable after confirming 0x55 is unoccupied on every bus.
  hdr(10,"I2C absent address NACK");
  uint32_t b=dev(0),orig=rd(b+DEV_CFG);
  wr(b+DEV_CFG,(orig&~0x7fu)|0x55u);
  clear_irq(0); wr(b+DEV_CMD,0u);
  wr(b+DEV_CTRL,CTRL_START|CTRL_RD);
  uint32_t st=0;
  int rc=wait_done(0,1500,&st);
  wr(b+DEV_CFG,orig);
  verdict(rc==0 && (st&ST_ACK_ERR)!=0);
#endif
}
static void test_qsfp_write_optional(void) {
#if ENABLE_QSFP_WRITE
#error "Safe QSFP register not selected: NEVER write arbitrary QSFP addresses. Select a vendor-documented writable location and implement backup/write/read/restore first."
#endif
  (void)qsfp_write; // Suppress unused-function warning.
}
static void summary(void) {
  puts_("\n=========== FINAL ===========\n");
  puts_("PASS=");dec_(pass_count);
  puts_(" FAIL=");dec_(fail_count);puts_("\n");
  puts_("RESULT=");puts_(fail_count?"FAIL\n":"PASS\n");
  puts_("MSI Host delivery was NOT tested.\n");
  wr(LEDS,fail_count?0x80u:0x02u);
}
int main(void) {
  cpu_clock_hz=rd(0x10000000u);
  wr(LEDS,0x01u);wr(MSI_CTRL,0);
  puts_("\nPicoRV32 / Certus-NX / 4xQSFP BIST\n");
  print_val("CPU clock Hz ",cpu_clock_hz);
  puts_("I2C slave addresses: 4 independent buses, each 0x50\n");
  puts_("QSFP writes DISABLED by default; set GOLDEN_QSFPn_ID for exact checks.\n");
  test_axi_registers();test_four_qsfp();test_auto_poll();
  test_nack_optional();test_msi_handshake();test_qsfp_write_optional();
  summary();
  for(;;) { /* LED keeps final result; reset for another run. */ }
}
