#include "common.h"
#define BUFLEN 96
static unsigned selected_ch=0;
static uint8_t selected_reg=0,selected_data=0;
static uint8_t allow_write=0;
static uint16_t poll_gap=1000;
static uint32_t timeout_ms=500;
static uint8_t polls[8]={0,1,2,3,4,5,6,7};
static char line[BUFLEN];
static unsigned llen=0;
static int overrun_reported=0;
static int same(const char*a,const char*b){while(*a&&*b&&*a==*b){a++;b++;}return *a==*b;}
static unsigned hex_number(const char*s,int *ok){
 unsigned x=0,n=0;*ok=0;
 if(s[0]=='0'&&(s[1]=='x'||s[1]=='X'))s+=2;
 for(;*s;s++){
  unsigned digit;
  if(*s>='0'&&*s<='9')digit=(unsigned)(*s-'0');
  else if(*s>='a'&&*s<='f')digit=(unsigned)(*s-'a'+10);
  else if(*s>='A'&&*s<='F')digit=(unsigned)(*s-'A'+10);
  else return 0;
  if(n++>=8)return 0;
  x=(x<<4)|digit;
 }
 if(n==0)return 0;
 *ok=1;return x;
}
static unsigned dec_number(const char*s,int *ok){
 unsigned x=0,n=0;*ok=0;
 for(;*s;s++){
  if(*s<'0'||*s>'9'||n++>9)return 0;
  if(x>429496729u)return 0;
  x=(x<<3)+(x<<1)+(unsigned)(*s-'0');
 } *ok=(n>0);return x;
}
static void show_help(void){
 uart_puts("Commands (hex by default, except 'delay' in decimal ms):\n"
 " help, status, id, mode cpu|pcie\n"
 " ch 0|1|2|3, dev 0x50, reg 0x00, data 0xA5\n"
 " read [addr], unlock, lock, write [addr] [data]\n"
 " writeverify [addr] [data] (read/write/read/restore)\n"
 " pollset <slot 0..7> <addr>, pollgap <hex>, poll\n"
 " timeout <hex ms>, delay <decimal ms>\n"
 " UART does NOT handle CMIS multi-byte bank/page atomic writes.\n");
}
static void show_status(void){
 uart_puts("owner CPU=");print_hex8((uint8_t)MMIO(IO_OWNER_ACT));
 uart_puts(" ch=");print_hex8((uint8_t)selected_ch);
 uart_puts(" dev=0x");print_hex8(current_dev[selected_ch]);
 uart_puts(" reg=0x");print_hex8(selected_reg);
 uart_puts(" data=0x");print_hex8(selected_data);
 uart_puts(" irq=0x");print_hex8((uint8_t)MMIO(IO_IRQ));
 uart_puts(" write_unlock=");print_hex8(allow_write);uart_puts("\n");
}
static void do_read(uint8_t reg){
 start_test();uint8_t v=0;
 int rc=direct_read(selected_ch,reg,&v,timeout_ms);
 report_read(selected_ch,reg,rc,v);end_test(rc);
}
static void do_write(uint8_t reg,uint8_t value,int restore){
 if(!allow_write){uart_puts("LOCKED: type 'unlock' first (vendor-approved RW only)\n");return;}
 if(reg==0x7eu||reg==0x7fu){uart_puts("DENIED: bank/page select requires separate CMIS workflow\n");return;}
 start_test();int rc;
 if(restore)rc=direct_write_restore(selected_ch,reg,value,timeout_ms);
 else{
  rc=direct_write(selected_ch,reg,value,timeout_ms);
  publish(selected_ch,EV_WRITE,reg,value,value,rc,0,
          MMIO(dev_base(selected_ch)+DEV_STATUS));
 }
 uart_puts("OSFP write reg=0x");print_hex8(reg);
 uart_puts(" data=0x");print_hex8(value);
 print_result(restore?" WRITEVERIFY":" WRITE",rc);
 end_test(rc);
}
static void do_poll(void){
 start_test();uint8_t result[8]={0};
 int rc=poll_read(selected_ch,polls,poll_gap,2000u,result);
 uart_puts("POLL ch=");print_hex8((uint8_t)selected_ch);uart_puts("\n");
 for(unsigned i=0;i<8;i++){
  uart_puts(" slot=");print_hex8((uint8_t)i);
  uart_puts(" reg=0x");print_hex8(polls[i]);
  uart_puts(" shadow=0x");print_hex8(result[i]);uart_puts("\n");
 }
 print_result("POLL (index wraps / auto_valid; no per-slot ACK flag)",rc);
 end_test(rc);
}
static void parse_line(char*s){
 char *argv[4]={0,0,0,0};unsigned argc=0;
 while(*s&&argc<4){while(*s==' '||*s=='\t')s++;if(!*s)break;argv[argc++]=s;
  while(*s&&*s!=' '&&*s!='\t')s++;
  if(*s)*s++=0;
 }
 if(argc==0)return;
 int ok=0;unsigned n=0;
 if(same(argv[0],"help")){show_help();return;}
 if(same(argv[0],"status")){show_status();return;}
 if(same(argv[0],"id")){
  if(!MMIO(IO_OWNER_ACT)){uart_puts("PCIe owns slave; switch mode cpu first\n");return;}
  uart_puts("AXI ID=0x");print_hex32(MMIO(AXI_BASE+AXI_ID));
  uart_puts(" VER=0x");print_hex32(MMIO(AXI_BASE+AXI_VERSION));uart_puts("\n");return;
 }
 if(same(argv[0],"mode")&&argc>=2){
  if(same(argv[1],"cpu")) MMIO(IO_OWNER_REQ)=1;
  else if(same(argv[1],"pcie"))MMIO(IO_OWNER_REQ)=0;
  else{uart_puts("mode cpu|pcie\n");return;}
  uart_puts("Switch requested. Quiesce host driver before switching.\n");
  uint32_t expect=MMIO(IO_OWNER_REQ),t=MMIO(IO_CYCLES);
  while(MMIO(IO_OWNER_ACT)!=expect && (uint32_t)(MMIO(IO_CYCLES)-t)<clk_hz/4u)heartbeat();
  uart_puts("owner now=");print_hex8((uint8_t)MMIO(IO_OWNER_ACT));uart_puts("\n");return;
 }
 if(same(argv[0],"unlock")){allow_write=1;uart_puts("WRITE UNLOCKED (volatile; reset locks)\n");return;}
 if(same(argv[0],"lock")){allow_write=0;uart_puts("WRITE LOCKED\n");return;}
 if(same(argv[0],"ch")&&argc>=2){n=hex_number(argv[1],&ok);if(ok&&n<4)selected_ch=n;else uart_puts("ch 0..3\n");return;}
 if(same(argv[0],"dev")&&argc>=2){n=hex_number(argv[1],&ok);if(ok&&n<128)set_dev_addr(selected_ch,(uint8_t)n);else uart_puts("dev 0x01..0x7F\n");return;}
 if(same(argv[0],"reg")&&argc>=2){n=hex_number(argv[1],&ok);if(ok&&n<256)selected_reg=(uint8_t)n;else uart_puts("reg 0x00..0xFF\n");return;}
 if(same(argv[0],"data")&&argc>=2){n=hex_number(argv[1],&ok);if(ok&&n<256)selected_data=(uint8_t)n;else uart_puts("data 0x00..0xFF\n");return;}
 if(same(argv[0],"timeout")&&argc>=2){n=hex_number(argv[1],&ok);if(ok&&n>=10&&n<=5000)timeout_ms=n;else uart_puts("timeout hex 0x0A..0x1388 ms\n");return;}
 if(same(argv[0],"pollgap")&&argc>=2){n=hex_number(argv[1],&ok);if(ok&&n<=65535)poll_gap=(uint16_t)n;else uart_puts("pollgap hex 0x0..0xFFFF\n");return;}
 if(same(argv[0],"delay")&&argc>=2){n=dec_number(argv[1],&ok);if(ok&&n<=600000){uart_puts("delaying...\n");delay_ms(n);uart_puts("done\n");}else uart_puts("delay decimal 0..600000ms\n");return;}
 if(same(argv[0],"pollset")&&argc>=3){
  unsigned slot=hex_number(argv[1],&ok);if(!ok||slot>7){uart_puts("slot 0..7\n");return;}
  n=hex_number(argv[2],&ok);if(ok&&n<256){polls[slot]=(uint8_t)n;uart_puts("pollset OK\n");}
  else uart_puts("addr 0x00..0xFF\n");return;
 }
 if(same(argv[0],"read")){
  uint8_t r=selected_reg;
  if(argc>=2){n=hex_number(argv[1],&ok);if(!ok||n>255){uart_puts("invalid addr\n");return;}r=(uint8_t)n;}
  do_read(r);return;
 }
 if(same(argv[0],"write")||same(argv[0],"writeverify")){
  uint8_t r=selected_reg,d=selected_data;
  if(argc>=2){n=hex_number(argv[1],&ok);if(!ok||n>255){uart_puts("bad addr\n");return;}r=(uint8_t)n;}
  if(argc>=3){n=hex_number(argv[2],&ok);if(!ok||n>255){uart_puts("bad data\n");return;}d=(uint8_t)n;}
  do_write(r,d,same(argv[0],"writeverify"));return;
 }
 if(same(argv[0],"poll")){do_poll();return;}
 uart_puts("Unknown command; help\n");
}
int main(void){
 init_common();uart_puts("\nPicoRV32 OSFP UART CLI (RV32I)\n");show_help();uart_puts("osfp> ");
 for(;;){
  heartbeat();
  if((MMIO(IO_RXSTATUS)&2u) && !overrun_reported){
    overrun_reported=1;
    uart_puts("[UART RX overrun; send slower]\n");
  }
  if(MMIO(IO_RXSTATUS)&1u){
   char c=(char)(MMIO(IO_RX)&0xffu);
   overrun_reported=0;
   if(c=='\r'||c=='\n'){
    if(llen){line[llen]=0;uart_puts("\n");parse_line(line);llen=0;uart_puts("osfp> ");}
   }else if(c==8||c==127){if(llen)llen--;}
   else if(c>=32&&c<=126){if(llen<BUFLEN-1){line[llen++]=c;uart_putc(c);}}
  }
 }
}
