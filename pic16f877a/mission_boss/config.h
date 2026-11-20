#include <16F877A.h>

#fuses HS, WDT, PUT, BROWNOUT, NOLVP, NOPROTECT, NOCPD, NOWRT, NODEBUG

#define CFG_SPBRG          129
#define LP_ODD_PARITY      0
#define CFG_GAP_TIMEOUT_MS 25

#byte R_STATUS  = 0x03
#byte R_PORTB   = 0x06
#byte R_PORTD   = 0x08
#byte R_INTCON  = 0x0B
#byte R_PIR1    = 0x0C
#byte R_T2CON   = 0x12
#byte R_RCSTA   = 0x18
#byte R_TXREG   = 0x19
#byte R_RCREG   = 0x1A
#byte R_ADCON0  = 0x1F

#byte R_OPTION  = 0x81
#byte R_TRISB   = 0x86
#byte R_TRISC   = 0x87
#byte R_TRISD   = 0x88
#byte R_PIE1    = 0x8C
#byte R_PCON    = 0x8E
#byte R_PR2     = 0x92
#byte R_TXSTA   = 0x98
#byte R_SPBRG   = 0x99
#byte R_CMCON   = 0x9C
#byte R_ADCON1  = 0x9F

#bit  B_GIE     = R_INTCON.7
#bit  B_PEIE    = R_INTCON.6

#bit  B_TXIF    = R_PIR1.4
#bit  B_TMR2IF  = R_PIR1.1
#bit  B_RCIE    = R_PIE1.5
#bit  B_TMR2IE  = R_PIE1.1

#bit  B_TX9     = R_TXSTA.6
#bit  B_TXEN    = R_TXSTA.5
#bit  B_SYNC    = R_TXSTA.4
#bit  B_BRGH    = R_TXSTA.2
#bit  B_TX9D    = R_TXSTA.0

#bit  B_SPEN    = R_RCSTA.7
#bit  B_RX9     = R_RCSTA.6
#bit  B_CREN    = R_RCSTA.4
#bit  B_ADDEN   = R_RCSTA.3
#bit  B_FERR    = R_RCSTA.2
#bit  B_OERR    = R_RCSTA.1
#bit  B_RX9D    = R_RCSTA.0

#bit  B_POR     = R_PCON.1
#bit  B_BOR     = R_PCON.0

#define T2CON_1MS          0x25
#define PR2_1MS            249

#define OPTION_WDT_128     0xFF

#define ADCON1_ALL_DIGITAL 0x06
#define CMCON_OFF          0x07

#define SEL_UART_A_BIT     0
#define SEL_UART_B_BIT     1
#define SEL_SPI_A_BIT      2
#define SEL_SPI_B_BIT      3
#define SEL_IDLE           0x0F
#define RAIL0_BIT          4
#define RAIL1_BIT          5
#define HEARTBEAT_MASK     0x01
