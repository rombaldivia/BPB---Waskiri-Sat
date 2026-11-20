#include "config.h"
#include "link_proto.c"
#include "payload_ctrl.c"

#define RING_SIZE   16
#define RING_MASK   (RING_SIZE - 1)

#define RXF_PARITY  0x01
#define RXF_FRAMING 0x02
#define RXF_OVERRUN 0x04

volatile int8  ring_byte[RING_SIZE];
volatile int8  ring_flag[RING_SIZE];
volatile int8  ring_head = 0;
volatile int8  ring_tail = 0;
volatile int8  ring_lost = 0;

volatile int16 ms_now = 0;

int8 portd_shadow = SEL_IDLE;
int8 portb_shadow = 0x00;

#priority rda, timer2

#int_rda
void isr_uart_rx(void)
{
    int8 flags, b, next, junk;
    int1 ninth;

    flags = 0;
    if (B_OERR) {
        junk = R_RCREG;
        junk = R_RCREG;
        B_CREN = 0;
        B_CREN = 1;
        b = 0;
        flags = RXF_OVERRUN;
    } else {
        ninth = B_RX9D;
        if (B_FERR) flags |= RXF_FRAMING;
        b = R_RCREG;
        if (ninth != lp_ninth_bit(b)) flags |= RXF_PARITY;
    }

    next = (ring_head + 1) & RING_MASK;
    if (next == ring_tail) {
        if (ring_lost != 0xFF) ring_lost++;
        return;
    }
    ring_byte[ring_head] = b;
    ring_flag[ring_head] = flags;
    ring_head = next;
}

#int_timer2
void isr_tick(void)
{
    B_TMR2IF = 0;
    ms_now++;
}

void wdt_kick(void)
{
#asm
    CLRWDT
#endasm
}

void settle(void)
{
    int8 i;
    for (i = 0; i < 20; i++) {
#asm
        NOP
        NOP
#endasm
    }
}

int16 millis(void)
{
    int16 t;
    B_GIE = 0;
    t = ms_now;
    B_GIE = 1;
    return t;
}

void uart_setup(void)
{
    R_TRISC |= 0xC0;
    R_SPBRG = CFG_SPBRG;
    B_BRGH  = 1;
    B_SYNC  = 0;
    B_TX9   = 1;
    B_RX9   = 1;
    B_ADDEN = 0;
    B_SPEN  = 1;
    B_TXEN  = 1;
    B_CREN  = 1;
}

void uart_tx(int8 b)
{
    while (!B_TXIF) wdt_kick();
    B_TX9D  = lp_ninth_bit(b);
    R_TXREG = b;
}

void send_reply(int8 seq, int8 cmd, int8 *payload, int8 len)
{
    int8 pkt[LP_MAX_PACKET];
    int8 n, i;
    n = lp_encode(seq, cmd, payload, len, pkt);
    for (i = 0; i < n; i++) uart_tx(pkt[i]);
}

void io_route(int8 bus, int8 target)
{
    int8 a_mask, b_mask;
    if (bus == BUS_UART) {
        a_mask = 1 << SEL_UART_A_BIT;
        b_mask = 1 << SEL_UART_B_BIT;
    } else {
        a_mask = 1 << SEL_SPI_A_BIT;
        b_mask = 1 << SEL_SPI_B_BIT;
    }

    portd_shadow |= (a_mask | b_mask);
    R_PORTD = portd_shadow;
    settle();
    if (target == TGT_PORT_A) portd_shadow &= ~a_mask;
    if (target == TGT_PORT_B) portd_shadow &= ~b_mask;
    R_PORTD = portd_shadow;
}

void io_rails(int8 rails)
{
    portd_shadow &= ~((1 << RAIL0_BIT) | (1 << RAIL1_BIT));
    if (rails & 0x01) portd_shadow |= (1 << RAIL0_BIT);
    if (rails & 0x02) portd_shadow |= (1 << RAIL1_BIT);
    R_PORTD = portd_shadow;
}

int8 read_boot_reason(void)
{
    int8 r;
    r = (R_STATUS & 0x18) | (R_PCON & 0x03);
    B_POR = 1;
    B_BOR = 1;
    return r;
}

void main(void)
{
    int8 reply[LP_MAX_PAYLOAD];
    int8 b, f, res, n, lost;
    int16 last_rx, beat;

    diag_boot = read_boot_reason();

    R_PORTD = portd_shadow;
    R_TRISD = 0x00;
    R_PORTB = portb_shadow;
    R_TRISB = 0x00;

    R_ADCON0 = 0x00;
    R_ADCON1 = ADCON1_ALL_DIGITAL;
    R_CMCON  = CMCON_OFF;
    wdt_kick();
    R_OPTION = OPTION_WDT_128;

    pc_safe_mode();
    lp_restart();

    R_PR2    = PR2_1MS;
    R_T2CON  = T2CON_1MS;
    uart_setup();

    B_TMR2IF = 0;
    B_TMR2IE = 1;
    B_RCIE   = 1;
    B_PEIE   = 1;
    B_GIE    = 1;

    last_rx = millis();
    beat    = last_rx;

    for (;;) {
        wdt_kick();

        B_GIE = 0;
        lost = ring_lost;
        ring_lost = 0;
        B_GIE = 1;
        if (lost) {
            diag_bump(&diag_overflow);
            lp_restart();
        }

        while (ring_tail != ring_head) {
            b = ring_byte[ring_tail];
            f = ring_flag[ring_tail];
            ring_tail = (ring_tail + 1) & RING_MASK;
            last_rx = millis();

            if (f) {
                if (f & RXF_PARITY)  diag_bump(&diag_parity);
                if (f & RXF_FRAMING) diag_bump(&diag_framing);
                if (f & RXF_OVERRUN) diag_bump(&diag_overflow);
                lp_restart();
                continue;
            }

            res = lp_decode(b);
            if (res == LP_PACKET) {
                n = pc_handle(&lp_rx, reply);
                send_reply(lp_rx.seq, lp_rx.cmd | LP_REPLY_FLAG, reply, n);
            } else if (res == LP_BAD_CRC) {
                diag_bump(&diag_crc);
                reply[0] = RC_CRC;
                send_reply(lp_rx.seq, LP_CMD_NAK, reply, 1);
            } else if (res == LP_BAD_LEN) {
                diag_bump(&diag_framing);
            }
        }

        if (lp_in_packet() && (millis() - last_rx) > CFG_GAP_TIMEOUT_MS) {
            diag_bump(&diag_framing);
            lp_restart();
        }

        if ((millis() - beat) >= 250) {
            beat += 250;
            portb_shadow ^= HEARTBEAT_MASK;
            R_PORTB = portb_shadow;
        }
    }
}
