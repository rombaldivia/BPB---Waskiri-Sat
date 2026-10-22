library ieee;
use ieee.std_logic_1164.all;

--------------------------------------------------------------------------------
-- BIRDS5_UART_SD_MUX
-- Mux 2:1 para UART y 2:1 para SPI, en PARALELO.
--
--   ESP32 UART (full duplex) <-> UART0 (bpb_uart_*)  o  UART1 (bpb_uart1_*)
--   ESP32 SPI  (host)        <-> SPI0/SD (bpb_sd_*)  o  SPI1  (bpb_spi1_*)
--
-- Botones (activos en bajo, se mantienen presionados):
--   key_uart  -> UART0     key_uart1 -> UART1
--   key_sd    -> SPI0/SD   key_spi1  -> SPI1
--
-- Reglas:
--   * UART y SPI son canales independientes: pueden estar activos a la vez.
--   * Dentro de un canal solo puede haber UN esclavo conectado. Si se
--     presionan los dos botones del mismo canal (p.ej. key_uart y key_uart1)
--     ese canal queda desconectado en estado seguro: dos esclavos no pueden
--     manejar la misma linea RX/MISO de la ESP32.
--   * Lineas no conectadas en estado seguro:
--       UART RX -> '1' (idle)
--       SPI SCK -> '0', MOSI -> '0', CS -> '1', MISO hacia la ESP32 -> '1'
--------------------------------------------------------------------------------
entity BIRDS5_UART_SD_MUX is
port(
    --------------------------------------------------------------------
    -- Botones activos en bajo
    --------------------------------------------------------------------
    key_uart  : in  std_logic;     -- selecciona UART0
    key_uart1 : in  std_logic;     -- selecciona UART1
    key_sd    : in  std_logic;     -- selecciona SPI0 (SD)
    key_spi1  : in  std_logic;     -- selecciona SPI1

    --------------------------------------------------------------------
    -- UART lado ESP32 (full duplex)
    --------------------------------------------------------------------
    esp_uart_tx  : in  std_logic;  -- TX desde ESP32
    esp_uart_rx  : out std_logic;  -- RX hacia ESP32

    -- UART0: BPB / backplane
    bpb_uart_tx  : in  std_logic;
    bpb_uart_rx  : out std_logic;

    -- UART1: segundo dispositivo
    bpb_uart1_tx : in  std_logic;
    bpb_uart1_rx : out std_logic;

    --------------------------------------------------------------------
    -- SPI lado ESP32 (host)
    --------------------------------------------------------------------
    esp_sd_sck   : in  std_logic;
    esp_sd_mosi  : in  std_logic;
    esp_sd_cs    : in  std_logic;
    esp_sd_miso  : out std_logic;

    -- SPI0: SD / BPB
    bpb_sd_sck   : out std_logic;
    bpb_sd_mosi  : out std_logic;
    bpb_sd_cs    : out std_logic;
    bpb_sd_miso  : in  std_logic;

    -- SPI1: segundo dispositivo
    bpb_spi1_sck  : out std_logic;
    bpb_spi1_mosi : out std_logic;
    bpb_spi1_cs   : out std_logic;
    bpb_spi1_miso : in  std_logic;

    --------------------------------------------------------------------
    -- LEDs onboard
    --------------------------------------------------------------------
    led : out std_logic_vector(3 downto 0)
);
end BIRDS5_UART_SD_MUX;

architecture rtl of BIRDS5_UART_SD_MUX is

    -- Peticiones (botones activos en bajo)
    signal req_u0, req_u1 : std_logic;
    signal req_s0, req_s1 : std_logic;

    -- Conexion efectiva (solo una por canal)
    signal u0_on, u1_on   : std_logic;
    signal s0_on, s1_on   : std_logic;

begin

    req_u0 <= not key_uart;
    req_u1 <= not key_uart1;
    req_s0 <= not key_sd;
    req_s1 <= not key_spi1;

    -- Exclusion dentro de cada canal (ambos pedidos -> ninguno)
    u0_on <= req_u0 and not req_u1;
    u1_on <= req_u1 and not req_u0;
    s0_on <= req_s0 and not req_s1;
    s1_on <= req_s1 and not req_s0;

    --------------------------------------------------------------------
    -- UART: ESP32 -> esclavo seleccionado (demux)
    --------------------------------------------------------------------
    bpb_uart_rx  <= esp_uart_tx when u0_on = '1' else '1';
    bpb_uart1_rx <= esp_uart_tx when u1_on = '1' else '1';

    -- UART: esclavo seleccionado -> ESP32 (mux)
    esp_uart_rx <= bpb_uart_tx  when u0_on = '1' else
                   bpb_uart1_tx when u1_on = '1' else
                   '1';

    --------------------------------------------------------------------
    -- SPI: ESP32 -> esclavo seleccionado (demux)
    --------------------------------------------------------------------
    bpb_sd_sck    <= esp_sd_sck  when s0_on = '1' else '0';
    bpb_sd_mosi   <= esp_sd_mosi when s0_on = '1' else '0';
    bpb_sd_cs     <= esp_sd_cs   when s0_on = '1' else '1';

    bpb_spi1_sck  <= esp_sd_sck  when s1_on = '1' else '0';
    bpb_spi1_mosi <= esp_sd_mosi when s1_on = '1' else '0';
    bpb_spi1_cs   <= esp_sd_cs   when s1_on = '1' else '1';

    -- SPI: esclavo seleccionado -> ESP32 (mux)
    esp_sd_miso <= bpb_sd_miso   when s0_on = '1' else
                   bpb_spi1_miso when s1_on = '1' else
                   '1';

    --------------------------------------------------------------------
    -- LEDs activos en alto: que esta conectado
    -- (si se piden los dos de un canal, sus dos LEDs quedan apagados)
    --------------------------------------------------------------------
    led(0) <= u0_on;   -- LED1: UART0 conectada
    led(1) <= u1_on;   -- LED2: UART1 conectada
    led(2) <= s0_on;   -- LED3: SPI0 / SD conectado
    led(3) <= s1_on;   -- LED4: SPI1 conectado

end rtl;
