# Mission Boss — PIC16F877A

Firmware (CCS C) del controlador de misión que comanda el ruteo del BPB por UART.

| Archivo | Contenido |
| --- | --- |
| `config.h` | Fuses, registros, baud (`CFG_SPBRG`), bits de selección en PORTD y rieles en PORTB |
| `link_proto.c` | Protocolo de enlace: sync `0x5A 0xC3`, seq, cmd, len, payload (≤8 B) y CRC-8 |
| `payload_ctrl.c` | Comandos: `PING`, `GET_STATUS`, `SET_ROUTE`, `SET_RAILS`, `SAFE_MODE`, `CLEAR_CNT` |
| `main.c` | ISR de RX con ring buffer, Timer2 a 1 ms, timeout entre bytes, WDT y heartbeat |

Compilar `main.c` con CCS C (incluye los otros `.c` directamente).
