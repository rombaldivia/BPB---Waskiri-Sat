# UART/SPI MUX 2x2 — MAX II (EPM240T100C5)

Multiplexor en paralelo para el BPB de Waskiri-Sat:

```
                 ┌── UART0 (bpb_uart_*)
ESP32 UART ──mux─┤
                 └── UART1 (bpb_uart1_*)

                 ┌── SPI0 / SD (bpb_sd_*)
ESP32 SPI  ──mux─┤
                 └── SPI1 (bpb_spi1_*)
```

- UART y SPI son canales independientes: pueden estar activos al mismo tiempo.
- Dentro de un canal solo se conecta un esclavo. Si se piden los dos (p. ej. UART0 y UART1), ese canal queda desconectado.
- Lineas no conectadas en estado seguro: UART RX = `1`, SCK = `0`, MOSI = `0`, CS = `1`, MISO hacia la ESP32 = `1`.
- Logica 100 % combinacional (no necesita reloj).

## Control (botones activos en bajo, mantener presionado)

| Boton | Pin | Conecta | LED |
|---|---|---|---|
| `key_uart`  | 37 | UART0   | `led[0]` (pin 21) |
| `key_uart1` | 35 | UART1   | `led[1]` (pin 20) |
| `key_sd`    | 38 | SPI0/SD | `led[2]` (pin 19) |
| `key_spi1`  | 36 | SPI1    | `led[3]` (pin 18) |

## Pines de datos (ejemplo, ajustar al cableado)

| Señal | Pin | Señal | Pin |
|---|---|---|---|
| `esp_uart_tx` | 41 | `esp_sd_sck`  | 48 |
| `esp_uart_rx` | 42 | `esp_sd_mosi` | 49 |
| `bpb_uart_tx` | 43 ⚠️ | `esp_sd_cs`   | 50 |
| `bpb_uart_rx` | 47 | `esp_sd_miso` | 51 |
| `bpb_uart1_tx` | 56 | `bpb_sd_sck`  | 52 |
| `bpb_uart1_rx` | 57 | `bpb_sd_mosi` | 53 |
| | | `bpb_sd_cs`   | 54 |
| | | `bpb_sd_miso` | 55 |
| | | `bpb_spi1_sck`  | 58 |
| | | `bpb_spi1_mosi` | 61 |
| | | `bpb_spi1_cs`   | 66 |
| | | `bpb_spi1_miso` | 67 |

Pines que NO se deben usar en el EPM240T100: JTAG 22–25, VCC 9/13/31/45/59/63/80/94, GND 10/11/32/46/60/65/79/93, GCLK 12/14/62/64, DEV_CLRn 44.

⚠️ El pin 43 es `IO/DEV_OE`: funciona como I/O mientras la opcion *Enable device-wide output enable* este desactivada en Quartus (por defecto lo esta).

Los pines de LEDs y botones son candidatos: confirmar contra el esquematico de la placa.

## Simulacion

```
ghdl -a BIRDS5_UART_SD_MUX.vhd tb_BIRDS5_UART_SD_MUX.vhd
ghdl -r tb_BIRDS5_UART_SD_MUX
```

El testbench recorre las 16 combinaciones de botones y verifica ruteo, aislamiento, estados seguros y LEDs.
