#define FW_MAJOR          1
#define FW_MINOR          0

#define CMD_PING          0x01
#define CMD_GET_STATUS    0x02
#define CMD_SET_ROUTE     0x10
#define CMD_SET_RAILS     0x20
#define CMD_SAFE_MODE     0x30
#define CMD_CLEAR_CNT     0x31

#define BUS_UART          0
#define BUS_SPI           1

#define TGT_DETACHED      0
#define TGT_PORT_A        1
#define TGT_PORT_B        2

#define RAIL_MASK         0x03

void io_route(int8 bus, int8 target);
void io_rails(int8 rails);

int8 pc_uart_target = TGT_DETACHED;
int8 pc_spi_target  = TGT_DETACHED;
int8 pc_rails       = 0;

int8 diag_parity   = 0;
int8 diag_framing  = 0;
int8 diag_crc      = 0;
int8 diag_overflow = 0;
int8 diag_boot     = 0;

void diag_bump(int8 *c)
{
    if (*c != 0xFF) (*c)++;
}

void pc_safe_mode(void)
{
    pc_rails = 0;
    io_rails(0);
    pc_uart_target = TGT_DETACHED;
    pc_spi_target  = TGT_DETACHED;
    io_route(BUS_UART, TGT_DETACHED);
    io_route(BUS_SPI,  TGT_DETACHED);
}

int8 pc_handle(lp_packet_t *rx, int8 *out)
{
    int8 bus, tgt, mask;

    out[0] = RC_OK;

    switch (rx->cmd) {
    case CMD_PING:
        if (rx->len != 0) break;
        out[1] = FW_MAJOR;
        out[2] = FW_MINOR;
        return 3;

    case CMD_GET_STATUS:
        if (rx->len != 0) break;
        out[1] = pc_uart_target | (pc_spi_target << 2);
        out[2] = pc_rails;
        out[3] = diag_parity;
        out[4] = diag_framing;
        out[5] = diag_crc;
        out[6] = diag_overflow;
        out[7] = diag_boot;
        return 8;

    case CMD_SET_ROUTE:
        if (rx->len != 2) break;
        bus = rx->data[0];
        tgt = rx->data[1];
        if (bus > BUS_SPI || tgt > TGT_PORT_B) break;
        if (bus == BUS_UART) pc_uart_target = tgt;
        else                 pc_spi_target  = tgt;
        io_route(bus, tgt);
        return 1;

    case CMD_SET_RAILS:
        if (rx->len != 2) break;
        mask = rx->data[0] & RAIL_MASK;
        pc_rails = (pc_rails & ~mask) | (rx->data[1] & mask);
        io_rails(pc_rails);
        return 1;

    case CMD_SAFE_MODE:
        if (rx->len != 0) break;
        pc_safe_mode();
        return 1;

    case CMD_CLEAR_CNT:
        if (rx->len != 0) break;
        diag_parity = diag_framing = diag_crc = diag_overflow = 0;
        return 1;

    default:
        out[0] = RC_UNKNOWN;
        return 1;
    }

    out[0] = RC_PARAM;
    return 1;
}

