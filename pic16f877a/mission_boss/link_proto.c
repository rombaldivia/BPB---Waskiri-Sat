#define LP_SYNC0          0x5A
#define LP_SYNC1          0xC3
#define LP_MAX_PAYLOAD    8
#define LP_MAX_PACKET     (LP_MAX_PAYLOAD + 6)
#define LP_REPLY_FLAG     0x80
#define LP_CMD_NAK        0x7F

#define RC_OK             0x00
#define RC_CRC            0xE1
#define RC_UNKNOWN        0xE2
#define RC_PARAM          0xE3

#define LP_NONE           0
#define LP_PACKET         1
#define LP_BAD_CRC        2
#define LP_BAD_LEN        3

#define PH_SYNC0          0
#define PH_SYNC1          1
#define PH_SEQ            2
#define PH_CMD            3
#define PH_LEN            4
#define PH_PAYLOAD        5
#define PH_CRC            6

typedef struct {
    int8 seq;
    int8 cmd;
    int8 len;
    int8 data[LP_MAX_PAYLOAD];
} lp_packet_t;

int8        lp_phase = PH_SYNC0;
int8        lp_pos   = 0;
int8        lp_crc   = 0;
lp_packet_t lp_rx;

int8 lp_crc8_step(int8 crc, int8 b)
{
    int8 k;
    crc ^= b;
    for (k = 0; k < 8; k++) {
        if (crc & 0x80) crc = (crc << 1) ^ 0x07;
        else            crc = crc << 1;
    }
    return crc;
}

#inline
int1 lp_ninth_bit(int8 b)
{
    int8 ones, k;
    ones = 0;
    for (k = 0; k < 8; k++) {
        if (b & 1) ones++;
        b >>= 1;
    }
#if LP_ODD_PARITY
    return (int1)((ones & 1) == 0);
#else
    return (int1)(ones & 1);
#endif
}

void lp_restart(void)
{
    lp_phase = PH_SYNC0;
    lp_pos   = 0;
    lp_crc   = 0;
}

int1 lp_in_packet(void)
{
    return (int1)(lp_phase != PH_SYNC0);
}

int8 lp_decode(int8 b)
{
    switch (lp_phase) {
    case PH_SYNC0:
        if (b == LP_SYNC0) lp_phase = PH_SYNC1;
        return LP_NONE;

    case PH_SYNC1:
        if (b == LP_SYNC1)      lp_phase = PH_SEQ;
        else if (b != LP_SYNC0) lp_phase = PH_SYNC0;
        return LP_NONE;

    case PH_SEQ:
        lp_rx.seq = b;
        lp_crc    = lp_crc8_step(0, b);
        lp_phase  = PH_CMD;
        return LP_NONE;

    case PH_CMD:
        lp_rx.cmd = b;
        lp_crc    = lp_crc8_step(lp_crc, b);
        lp_phase  = PH_LEN;
        return LP_NONE;

    case PH_LEN:
        if (b > LP_MAX_PAYLOAD) {
            lp_restart();
            return LP_BAD_LEN;
        }
        lp_rx.len = b;
        lp_crc    = lp_crc8_step(lp_crc, b);
        lp_pos    = 0;
        lp_phase  = (b == 0) ? PH_CRC : PH_PAYLOAD;
        return LP_NONE;

    case PH_PAYLOAD:
        lp_rx.data[lp_pos] = b;
        lp_crc = lp_crc8_step(lp_crc, b);
        lp_pos++;
        if (lp_pos >= lp_rx.len) lp_phase = PH_CRC;
        return LP_NONE;

    case PH_CRC:
        lp_phase = PH_SYNC0;
        if (b == lp_crc) return LP_PACKET;
        return LP_BAD_CRC;
    }
    lp_restart();
    return LP_NONE;
}

int8 lp_encode(int8 seq, int8 cmd, int8 *payload, int8 len, int8 *out)
{
    int8 i, crc;
    if (len > LP_MAX_PAYLOAD) return 0;
    out[0] = LP_SYNC0;
    out[1] = LP_SYNC1;
    out[2] = seq;
    out[3] = cmd;
    out[4] = len;
    crc = lp_crc8_step(0, seq);
    crc = lp_crc8_step(crc, cmd);
    crc = lp_crc8_step(crc, len);
    for (i = 0; i < len; i++) {
        out[5 + i] = payload[i];
        crc = lp_crc8_step(crc, payload[i]);
    }
    out[5 + len] = crc;
    return len + 6;
}

