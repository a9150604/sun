#include "common.h"
uint32_t clk_hz=125000000u;
uint8_t led_flags=0;
uint8_t current_dev[4]={0x50,0x50,0x50,0x50};
static uint32_t hb_start=0;
static uint8_t hb=0;
static uint32_t read32(uint32_t addr){return MMIO(addr);}
static void write32(uint32_t addr,uint32_t v){MMIO(addr)=v;}
static uint32_t now(void){return read32(IO_CYCLES);}
static uint32_t ticks_ms(uint32_t ms){return (clk_hz/1000u)*ms;}
static int timedout(uint32_t start,uint32_t ms){return (uint32_t)(now()-start)>=ticks_ms(ms);}
void heartbeat(void){
 if((uint32_t)(now()-hb_start) >= ticks_ms(250u)){
  hb_start=now();hb^=1u;
  write32(IO_LED,(led_flags&0x7eu)|hb);
 }
}
void led_set(uint8_t clear_mask,uint8_t set_mask){
 led_flags=(uint8_t)((led_flags & (uint8_t)~clear_mask)|set_mask);
 write32(IO_LED,(led_flags&0x7eu)|hb);
}
void delay_ms(uint32_t ms){
 // handle long waits in bounded steps to keep 32-bit cycles counter wrap safe
 while(ms--){uint32_t start=now();while(!timedout(start,1u)) heartbeat();}
}
void uart_putc(char c){write32(IO_TX,(uint8_t)c);}
void uart_puts(const char *s){while(*s){if(*s=='\n')uart_putc('\r');uart_putc(*s++);}}
static void hx4(uint8_t v){uart_putc((char)(v<10?'0'+v:'A'+v-10));}
void print_hex8(uint8_t v){hx4((uint8_t)(v>>4));hx4((uint8_t)(v&15));}
void print_hex16(uint16_t v){print_hex8((uint8_t)(v>>8));print_hex8((uint8_t)v);}
void print_hex32(uint32_t v){print_hex16((uint16_t)(v>>16));print_hex16((uint16_t)v);}
void print_result(const char *s,int rc){uart_puts(s);uart_puts(rc==RC_OK?" PASS\n":" FAIL rc=0x");if(rc){print_hex8((uint8_t)rc);uart_puts("\n");}}
uint32_t dev_base(unsigned channel){return AXI_BASE+(channel+1u)*0x100u;}
static int owner_ok(void){return (read32(IO_OWNER_ACT)&1u)!=0u;}
void set_dev_addr(unsigned ch,uint8_t addr){
 if(ch>=4||addr>=128)return;
 current_dev[ch]=addr;
 if(owner_ok()){
  uint32_t b=dev_base(ch),old=read32(b+DEV_CFG);
  write32(b+DEV_CFG,(old&~0x7fu)|addr);
 }
}
static int wait_idle(unsigned ch,uint32_t ms){
 uint32_t t=now();while(!timedout(t,ms)){
  if((read32(dev_base(ch)+DEV_STATUS)&ST_BUSY)==0)return RC_OK;
  heartbeat();
 }return RC_TIMEOUT;
}
static int wait_done(unsigned ch,uint32_t ms,uint32_t *st){
 uint32_t t=now();while(!timedout(t,ms)){
  uint32_t x=read32(dev_base(ch)+DEV_STATUS);
  if(x&ST_DONE){if(st)*st=x;return (x&ST_NACK)?RC_NACK:RC_OK;}
  heartbeat();
 }
 if(st)*st=read32(dev_base(ch)+DEV_STATUS);
 return RC_TIMEOUT;
}
static int prepare_direct(unsigned ch,uint32_t timeout_ms){
 if(ch>=4)return RC_ARG;
 if(!owner_ok())return RC_OWNER;
 uint32_t b=dev_base(ch);
 write32(b+DEV_CTRL,0u);
 int rc=wait_idle(ch,timeout_ms);if(rc)return rc;
 write32(b+DEV_CTRL,CTRL_CLEAR);
 uint32_t cfg=read32(b+DEV_CFG);
 write32(b+DEV_CFG,(cfg&~0x7fu)|current_dev[ch]);
 return RC_OK;
}
int direct_read(unsigned ch,uint8_t reg,uint8_t *value,uint32_t timeout_ms){
 if(!value)return RC_ARG;
 int rc=prepare_direct(ch,timeout_ms);if(rc)return rc;
 uint32_t b=dev_base(ch),st=0;
 write32(b+DEV_CMD,reg);
 write32(b+DEV_CTRL,CTRL_START|CTRL_RD);
 rc=wait_done(ch,timeout_ms,&st);
 if(rc==RC_OK)*value=(uint8_t)read32(b+DEV_RD);
 return rc;
}
int direct_write(unsigned ch,uint8_t reg,uint8_t data,uint32_t timeout_ms){
 int rc=prepare_direct(ch,timeout_ms);if(rc)return rc;
 uint32_t b=dev_base(ch),st=0;
 write32(b+DEV_CMD,((uint32_t)data<<8)|reg);
 write32(b+DEV_CTRL,CTRL_START);
 return wait_done(ch,timeout_ms,&st);
}
// Only use for vendor-certified ordinary RW registers. Never W1C/volatile/latches.
// On failure, make best-effort restore and report restoration failure separately.
int direct_write_restore(unsigned ch,uint8_t reg,uint8_t test_value,uint32_t timeout_ms){
 uint8_t original=0,got=0,restored=0;
 int rc=direct_read(ch,reg,&original,timeout_ms);
 if(rc)return rc;
 rc=direct_write(ch,reg,test_value,timeout_ms);
 if(!rc)rc=direct_read(ch,reg,&got,timeout_ms);
 if(!rc && got!=test_value)rc=RC_MISMATCH;
 int rr=direct_write(ch,reg,original,timeout_ms);
 if(!rr)rr=direct_read(ch,reg,&restored,timeout_ms);
 if(!rr && restored!=original)rr=RC_MISMATCH;
 publish(ch,EV_WRITE,reg,test_value,got,rr?RC_MISMATCH:rc,0,
         (rr?0x8000u:0)|read32(dev_base(ch)+DEV_STATUS));
 if(rr){led_set(0,LED_FAIL);return RC_MISMATCH;}
 return rc;
}
void publish(unsigned ch,unsigned kind,unsigned reg,unsigned expected,
             unsigned actual,unsigned rc,unsigned slot,uint32_t status){
 uint32_t aux=((uint32_t)current_dev[ch&3u]<<24)|((slot&0xffu)<<16)|(status&0xffffu);
 uint32_t evt=(1u<<31)|((rc==RC_OK?1u:0u)<<30)|((kind&3u)<<28)|
              ((ch&3u)<<26)|((reg&0xffu)<<18)|((expected&0xffu)<<10)|
              ((actual&0xffu)<<2)|(rc&3u);
 write32(IO_DBG_AUX,aux);
 write32(IO_DBG_EVT,evt); // Capture event and increment Reveal toggle/pulse.
}
int poll_read(unsigned ch,const uint8_t poll_addrs[8],uint16_t gap,
              uint32_t timeout_ms,uint8_t out[8]){
 if(ch>=4 || !poll_addrs||!out)return RC_ARG;
 if(!owner_ok())return RC_OWNER;
 uint32_t b=dev_base(ch);
 write32(b+DEV_CTRL,0u);
 int rc=wait_idle(ch,timeout_ms);if(rc)return rc;
 uint32_t cfg=read32(b+DEV_CFG);
 write32(b+DEV_CFG,((uint32_t)gap<<16)|(cfg&0x0000ff80u)|current_dev[ch]);
 for(unsigned i=0;i<8;i++) write32(b+DEV_PADDR+4u*i,poll_addrs[i]);
 write32(b+DEV_CTRL,CTRL_AUTO);
 // auto_valid is sticky; rely on TWO full poll index wraps for fresh values.
 uint32_t st=read32(b+DEV_STATUS),t=now();
 unsigned prev=(unsigned)((st>>4)&7u),wraps=0;
 while(!timedout(t,timeout_ms)){
  st=read32(b+DEV_STATUS);
  unsigned idx=(unsigned)((st>>4)&7u);
  if(prev==7u && idx==0u){if(++wraps>=2u)break;}
  prev=idx;heartbeat();
 }
 write32(b+DEV_CTRL,0u);
 int idle_rc=wait_idle(ch,timeout_ms);
 st=read32(b+DEV_STATUS);
 rc=(wraps>=2u && idle_rc==RC_OK && (st&ST_AUTOVALID)) ? RC_OK:RC_TIMEOUT;
 for(unsigned i=0;i<8;i++){
  out[i]=(uint8_t)read32(b+DEV_SHADOW+4u*i);
  publish(ch,EV_POLL,poll_addrs[i],0,out[i],rc,i,st);
 }
 // WARNING: current slave provides no per-slot poll ACK status. Successful
 // auto_valid only proves some auto read succeeded; individual slots may be stale.
 return rc;
}
void report_read(unsigned ch,uint8_t reg,int rc,uint8_t value){
 uart_puts("OSFP");print_hex8((uint8_t)ch);uart_puts(" dev=0x");print_hex8(current_dev[ch]);
 uart_puts(" reg=0x");print_hex8(reg);uart_puts(" value=0x");print_hex8(value);
 print_result(" DIRECT_READ",rc);
 publish(ch,EV_READ,reg,0,value,rc,0,read32(dev_base(ch)+DEV_STATUS));
}
void init_common(void){
 clk_hz=read32(IO_CLK);
 for(unsigned i=0;i<4;i++) set_dev_addr(i,0x50u);
 led_set(0xffu,0);
 hb_start=now();
}
void start_test(void){led_set(LED_DONE|LED_PASS|LED_FAIL|LED_NACK|LED_TIMEOUT,LED_RUNNING);}
void end_test(int rc){
 uint8_t flags=LED_DONE|(rc==RC_OK?LED_PASS:LED_FAIL);
 if(rc==RC_NACK)flags|=LED_NACK;
 if(rc==RC_TIMEOUT)flags|=LED_TIMEOUT;
 led_set(LED_RUNNING|LED_PASS|LED_FAIL|LED_NACK|LED_TIMEOUT,flags);
}

// Optional automatic transfer of AXI-Lite slave to PCIe after one-shot test.
// In real systems host driver MUST still coordinate quiescence and start.
void request_pcie_after_test(unsigned enable){
 if(!enable)return;
 MMIO(IO_OWNER_REQ)=0u;
 // CPU keeps running and can still access local LEDs/UART after release.
}
