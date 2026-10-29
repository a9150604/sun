/* Four-OSFP button/DIP BIST, no UART needed.
 * PicoRV32 original SOC register map; button active level configurable below.
 * Event/aux snapshots at 0x10000040/44 are latched for Lattice Reveal.
 * Read-only by default; OSFP writes require vendor-approved compile-time profile.
 */
#include <stdint.h>
#include "osfp_test_config.h"

#ifndef BUTTON_ACTIVE_LOW
#define BUTTON_ACTIVE_LOW 1
#endif
#ifndef SWITCH_ACTIVE_LOW
#define SWITCH_ACTIVE_LOW 0
#endif
#define MMIO(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define SYSCLK       0x10000000u
#define CYCLES       0x1000000cu
#define LEDS         0x10000010u
#define GPIO         0x10000014u
#define MSI_EN       0x10000020u
#define MSI_ST       0x10000028u
#define DBG_EVENT    0x10000040u
#define DBG_AUX      0x10000044u
#define FPGA_BASE    0x40000000u
#define GLOBAL_IRQ   (FPGA_BASE + 0x000cu)
#define DEV_CFG      0x00u
#define DEV_CTRL     0x04u
#define DEV_CMD      0x08u
#define DEV_STATUS   0x0cu
#define DEV_RD       0x10u
#define DEV_SHADOW0  0x20u
#define DEV_POLL0    0x40u
#define CTRL_AUTO    0x01u
#define CTRL_START   0x02u
#define CTRL_RD      0x04u
#define CTRL_CLEAR   0x10u
#define ST_BUSY      0x01u
#define ST_DONE      0x02u
#define ST_NACK      0x04u
#define ST_AUTOV     0x08u
#define ST_IDX(x)    (((x)>>4)&7u)
#define ERR_NACK     (-2)
#define ERR_TIMEOUT  (-3)
#define ERR_VERIFY   (-4)
#define ERR_UNSAFE   (-5)
#define MODE_DIRECT  0u
#define MODE_POLL    1u
#define MODE_WRITE   2u
#define MODE_IRQ     3u

static uint32_t clk_hz;
static volatile uint32_t last_event, last_aux;
static uint8_t current_mode, current_ch, current_idx;
static uint8_t last_value, last_valid, last_data_valid, last_pass, last_fail, last_skip;
static uint8_t last_nack, last_timeout, last_restore_fail;
static uint8_t led_data_mode;
static const uint8_t direct_bytes[3] = {0x00u,0x01u,0x02u};

static uint32_t read32(uint32_t a) {return MMIO(a);}
static void write32(uint32_t a,uint32_t d) {MMIO(a)=d;}
static uint32_t base(unsigned ch) {return FPGA_BASE+(ch+1u)*0x100u;}
static uint32_t cycles(void) {return read32(CYCLES);}
static uint32_t ms_ticks(uint32_t ms) {return (clk_hz/1000u)*ms;}
static int expired(uint32_t begin,uint32_t ms) {
    return (uint32_t)(cycles()-begin)>ms_ticks(ms);
}
static void pause_ms(uint32_t ms) {
    uint32_t t=cycles();while(!expired(t,ms)){}
}
static int wait_idle(unsigned ch,unsigned ms) {
    uint32_t t=cycles();
    while(!expired(t,ms)) if((read32(base(ch)+DEV_STATUS)&ST_BUSY)==0u)return 0;
    return ERR_TIMEOUT;
}
static int wait_done(unsigned ch,unsigned ms) {
    uint32_t t=cycles();
    while(!expired(t,ms)) {
        uint32_t st=read32(base(ch)+DEV_STATUS);
        if(st&ST_DONE)return (st&ST_NACK)?ERR_NACK:0;
    }
    return ERR_TIMEOUT;
}
static int prepare(unsigned ch) {
    uint32_t b=base(ch);
    write32(b+DEV_CTRL,0u);
    if(wait_idle(ch,OSFP_DIRECT_TIMEOUT_MS))return ERR_TIMEOUT;
    write32(b+DEV_CTRL,CTRL_CLEAR);
    uint32_t cfg=read32(b+DEV_CFG);
    write32(b+DEV_CFG,(cfg&~0x7fu)|OSFP_I2C_ADDR);
    return 0;
}
static int direct_read(unsigned ch,uint8_t addr,uint8_t *actual) {
    uint32_t b=base(ch);
    int rc=prepare(ch);
    if(rc)return rc;
    write32(b+DEV_CMD,(uint32_t)addr);
    write32(b+DEV_CTRL,CTRL_START|CTRL_RD);
    rc=wait_done(ch,OSFP_DIRECT_TIMEOUT_MS);
    if(rc)return rc;
    *actual=(uint8_t)read32(b+DEV_RD);
    return 0;
}
static int direct_write(unsigned ch,uint8_t addr,uint8_t value) {
    uint32_t b=base(ch);
    int rc=prepare(ch);
    if(rc)return rc;
    write32(b+DEV_CMD,((uint32_t)value<<8) | addr);
    write32(b+DEV_CTRL,CTRL_START);
    return wait_done(ch,OSFP_DIRECT_TIMEOUT_MS);
}
static void clear_result(void) {
    last_valid=0;last_data_valid=0;last_pass=0;last_fail=0;last_skip=0;
    last_nack=0;last_timeout=0;last_restore_fail=0;last_value=0;
}
static uint8_t get_switches(void) {
    uint8_t s=(uint8_t)((read32(GPIO)>>4)&15u);
#if SWITCH_ACTIVE_LOW
    s^=15u;
#endif
    return s;
}
static uint8_t get_buttons(void) {
    uint8_t b=(uint8_t)(read32(GPIO)&15u);
#if BUTTON_ACTIVE_LOW
    b^=15u;
#endif
    return b;
}
static uint8_t index_limit(unsigned mode) {return mode==MODE_POLL?8u:mode==MODE_DIRECT?3u:1u;}
static uint8_t led_status(void) {
    if(!last_valid) {
        /* selection view: LED7=1, [6:5]=channel, [4:3]=mode, [2:0]=index */
        return (uint8_t)(0x80u|((uint32_t)current_ch<<5)|((uint32_t)current_mode<<3)|current_idx);
    }
    if(led_data_mode)return last_value; /* All 8 LEDs show actual byte. */
    /* Result view: bit1 PASS, bit2 FAIL, bit3 NACK, bit4 TIMEOUT,
       bit5 SKIP, bit6 DATA_VALID, bit7 RESTORE_FAIL */
    return (uint8_t)((last_pass<<1)|(last_fail<<2)|(last_nack<<3)|
           (last_timeout<<4)|(last_skip<<5)|(last_data_valid<<6)|
           (last_restore_fail<<7));
}
static void leds_refresh(void) {write32(LEDS,led_status());}

static void report_event(unsigned mode,unsigned ch,unsigned idx,
                         uint8_t addr,uint8_t actual,uint8_t expected,
                         uint8_t orig,uint8_t written,int rc,int valid,
                         int restore_failed) {
    /* rc==1 is SKIP, rc==0 PASS, negative is FAIL */
    last_valid=1; /* any result including FAIL/SKIP should remain visible */
    last_data_valid=(uint8_t)!!valid;
    last_pass=(uint8_t)(rc==0);
    last_fail=(uint8_t)(rc<0);
    last_skip=(uint8_t)(rc==1);
    last_nack=(uint8_t)(rc==ERR_NACK);
    last_timeout=(uint8_t)(rc==ERR_TIMEOUT);
    last_restore_fail=(uint8_t)!!restore_failed;
    last_value=actual;
    uint32_t aux=(uint32_t)orig|((uint32_t)written<<8)|
                 ((idx&7u)<<16)|((uint32_t)last_nack<<19)|
                 ((uint32_t)last_timeout<<20)|((uint32_t)last_restore_fail<<21);
    uint32_t event=(uint32_t)actual|((uint32_t)expected<<8)|
                   ((uint32_t)addr<<16)|((ch&3u)<<24)|((mode&3u)<<26)|
                   ((uint32_t)last_pass<<28)|((uint32_t)last_fail<<29)|
                   ((uint32_t)last_skip<<30)|(1u<<31);
    last_aux=aux;last_event=event;
    write32(DBG_AUX,aux);
    write32(DBG_EVENT,event); /* Increments hardware sequence; trigger Reveal. */
}

static void test_direct(unsigned ch,unsigned idx) {
    uint8_t a=direct_bytes[idx%3u],v=0,expected=0;
    int rc=direct_read(ch,a,&v);
    /* Only strict compare Identifier if user specified a real per-channel golden. */
    if(a==0x00u && osfp_id_expected[ch]) {
        expected=osfp_id_expected[ch];
        if(rc==0 && v!=expected)rc=ERR_VERIFY;
    }
    report_event(MODE_DIRECT,ch,idx,a,v,expected,0,0,rc,(rc==0),0);
}

static void test_poll(unsigned ch,unsigned selected) {
    uint32_t b=base(ch),saved[8],old_control=0;
    uint8_t baseline[8]={0},actual=0;
    int rc=0,setup_started=0;
    for(unsigned i=0;i<8;i++) {
        rc=direct_read(ch,osfp_poll_bytes[i],&baseline[i]);
        if(rc)break;
    }
    if(rc)goto poll_report;
    old_control=read32(b+DEV_CTRL);
    for(unsigned i=0;i<8;i++) saved[i]=read32(b+DEV_POLL0+4u*i);
    setup_started=1;
    write32(b+DEV_CTRL,0);
    rc=wait_idle(ch,OSFP_DIRECT_TIMEOUT_MS);
    if(rc)goto poll_restore;
    for(unsigned i=0;i<8;i++) {
        write32(b+DEV_POLL0+4u*i,osfp_poll_bytes[i]);
        if((read32(b+DEV_POLL0+4u*i)&255u)!=osfp_poll_bytes[i]) {
            rc=ERR_VERIFY;goto poll_restore;
        }
    }
    write32(b+DEV_CTRL,CTRL_AUTO);
    {
        uint32_t t=cycles();unsigned prev=ST_IDX(read32(b+DEV_STATUS)),wraps=0;
        while(!expired(t,OSFP_AUTO_TIMEOUT_MS)) {
            unsigned next=ST_IDX(read32(b+DEV_STATUS));
            if(prev==7u && next==0u) {
                ++wraps;
                if(wraps>=2u)break;
            }
            prev=next;
        }
        if(wraps<2u)rc=ERR_TIMEOUT;
    }
    write32(b+DEV_CTRL,0u);
    if(wait_idle(ch,OSFP_DIRECT_TIMEOUT_MS))rc=ERR_TIMEOUT;
    if((read32(b+DEV_STATUS)&ST_AUTOV)==0u && rc==0)rc=ERR_VERIFY;
    for(unsigned i=0;i<8;i++) {
        uint8_t x=(uint8_t)read32(b+DEV_SHADOW0+4u*i);
        if(i==selected)actual=x;
        if(x!=baseline[i] && rc==0)rc=ERR_VERIFY;
    }
poll_restore:
    if(setup_started) {
        write32(b+DEV_CTRL,0u);
        if(wait_idle(ch,OSFP_DIRECT_TIMEOUT_MS))rc=ERR_TIMEOUT;
        else {
            for(unsigned i=0;i<8;i++) write32(b+DEV_POLL0+4u*i,saved[i]);
            for(unsigned i=0;i<8;i++) if(read32(b+DEV_POLL0+4u*i)!=saved[i])rc=ERR_VERIFY;
            /* Never restore command pulses, only auto enable and rw. */
            write32(b+DEV_CTRL,old_control&(CTRL_AUTO|CTRL_RD));
        }
    }
poll_report:
    report_event(MODE_POLL,ch,selected,osfp_poll_bytes[selected],actual,
                 baseline[selected],0,0,rc,(rc==0),0);
}

static void test_write(unsigned ch) {
    uint8_t original=0,test=0,readback=0,restored=0;
    int rc=1,restore_error=0,attempted=0;
    const osfp_rw_target_t *p=&osfp_rw_targets[ch];
#if OSFP_ALLOW_WRITE_TEST && (OSFP_WRITE_AUTH_KEY == OSFP_WRITE_KEY_VALUE)
    uint8_t id=0;
    /* Deliberately restrict button-mode writes to lower-memory ordinary-RW
       bytes. Never touch CMIS Bank/Page or upper-memory windows here. */
    rc=direct_read(ch,0u,&id);
    if(rc)goto write_report;
    if(!p->enabled || !p->expected_id || id!=p->expected_id ||
       !p->toggle_mask || p->byte_addr<3u || p->byte_addr>117u) {
        rc=1;goto write_report;
    }
    rc=direct_read(ch,p->byte_addr,&original);
    if(rc)goto write_report;
    test=(uint8_t)(original ^ p->toggle_mask);
    attempted=1;
    rc=direct_write(ch,p->byte_addr,test);
    if(rc==0) {
        pause_ms(p->settle_ms);
        rc=direct_read(ch,p->byte_addr,&readback);
        if(rc==0 && ((readback^test)&p->toggle_mask))rc=ERR_VERIFY;
    }
    /* Always try to restore if we attempted a write, even on failure. */
    if(attempted) {
        int rc_restore=direct_write(ch,p->byte_addr,original);
        if(rc_restore==0) {
            pause_ms(p->settle_ms);
            rc_restore=direct_read(ch,p->byte_addr,&restored);
            if(rc_restore==0 && ((restored^original)&p->toggle_mask))rc_restore=ERR_VERIFY;
        }
        if(rc_restore!=0) {
            restore_error=1;rc=ERR_VERIFY;
        }
    }
#else
    (void)attempted;(void)restored;
#endif
write_report:
    report_event(MODE_WRITE,ch,0u,p->byte_addr,readback,test,
                 original,test,rc,rc==0,restore_error);
}

static void test_irq(unsigned ch) {
    uint8_t v=0;
    uint32_t before=0,after=0;
    int rc;
    uint32_t b=base(ch);
    write32(MSI_EN,0u);
    /* Remove stale IRQ for channel. */
    write32(b+DEV_CTRL,CTRL_CLEAR);
    pause_ms(2);
    before=(read32(MSI_ST)>>2)&65535u;
    write32(MSI_EN,1u); /* Standalone ACK loopback ONLY; not Host MSI. */
    rc=direct_read(ch,0x00u,&v);
    if(rc==0 && (read32(GLOBAL_IRQ)&(1u<<ch))==0)rc=ERR_VERIFY;
    if(rc==0) {
        uint32_t start=cycles();
        while(!expired(start,100u)) {
            after=(read32(MSI_ST)>>2)&65535u;
            if((uint16_t)(after-before)!=0u)break;
        }
        if((uint16_t)(after-before)==0u)rc=ERR_TIMEOUT;
    }
    write32(b+DEV_CTRL,CTRL_CLEAR);
    if(wait_idle(ch,OSFP_DIRECT_TIMEOUT_MS))rc=ERR_TIMEOUT;
    if(read32(GLOBAL_IRQ)&(1u<<ch))rc=ERR_VERIFY;
    write32(MSI_EN,0u);
    report_event(MODE_IRQ,ch,0u,0x00u,v,0,0,0,rc,rc==0,0);
}

static void run_test(unsigned mode,unsigned ch,unsigned idx) {
    clear_result();
    write32(LEDS,0x01u); /* LED0 busy */
    switch(mode) {
      case MODE_DIRECT:test_direct(ch,idx);break;
      case MODE_POLL:test_poll(ch,idx);break;
      case MODE_WRITE:test_write(ch);break;
      default:test_irq(ch);break;
    }
    leds_refresh();
}

int main(void) {
    clk_hz=read32(SYSCLK);
    write32(MSI_EN,0u);
    clear_result();
    current_ch=0;current_mode=0;current_idx=0;led_data_mode=0;
    /* User changes mode/ch using DIPs, then BTN0 starts test. */
    uint8_t stable=get_buttons(),sample=stable,repeat_count=0;
    uint8_t prior_sw=0xff;
    while(1) {
        uint8_t sw=get_switches();
        if(sw!=prior_sw) {
            current_ch=sw&3u;
            current_mode=(sw>>2)&3u;
            current_idx=0;
            clear_result();
            prior_sw=sw;
        }
        uint8_t buttons=get_buttons();
        if(buttons==sample) {
            if(repeat_count<3u)repeat_count++;
        } else {
            sample=buttons;repeat_count=0;
        }
        if(repeat_count==3u && stable!=sample) {
            uint8_t pressed=(uint8_t)(sample & (uint8_t)~stable);
            stable=sample;
            if(pressed&1u) { /* BTN0: execute */
                run_test(current_mode,current_ch,current_idx);
            } else if(pressed&2u) { /* BTN1: next byte or slot */
                current_idx=(uint8_t)((current_idx+1u)%index_limit(current_mode));
                clear_result();
            } else if(pressed&4u) { /* BTN2: RESULT versus DATA */
                led_data_mode^=1u;
            } else if(pressed&8u) { /* BTN3: clear result */
                clear_result();
            }
        }
        leds_refresh();
        pause_ms(5u);
    }
}
