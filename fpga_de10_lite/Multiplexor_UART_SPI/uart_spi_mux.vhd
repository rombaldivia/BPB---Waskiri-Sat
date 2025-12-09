library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity uart_spi_mux is
    Port (
        --------------------------------------------------------------------
        -- BOTONES (DE10-Lite: KEY0 y KEY1, activos en bajo)
        --------------------------------------------------------------------
        key0        : in  std_logic;      -- Habilita UART  (activo en 0)
        key1        : in  std_logic;      -- Habilita SPI   (activo en 0)
        enable_btn  : out std_logic;      -- '1' si UART o SPI están habilitados

        --------------------------------------------------------------------
        -- UART: ESP32 <--> BACKPLANE (como el uart_mux original)
        --------------------------------------------------------------------
        esp_uart_tx : in  std_logic;      -- TX de la ESP32 -> FPGA
        esp_uart_rx : out std_logic;      -- RX hacia la ESP32 <- FPGA

        bp_uart_tx  : in  std_logic;      -- TX del dispositivo del backplane -> FPGA
        bp_uart_rx  : out std_logic;      -- RX hacia el dispositivo del backplane <- FPGA

        --------------------------------------------------------------------
        -- SPI : ESP32 (maestro) <--> BACKPLANE (2x20, SD / flash / etc.)
        --------------------------------------------------------------------
        -- Lado ESP32 (pines tipo Arduino)
        esp_spi_sclk : in  std_logic;     -- SCLK desde la ESP32
        esp_spi_mosi : in  std_logic;     -- MOSI desde la ESP32
        esp_spi_miso : out std_logic;     -- MISO hacia la ESP32
        esp_spi_cs0  : in  std_logic;     -- CS0 generado por la ESP32

        -- Lado BACKPLANE (pines 2x20)
        bp_spi_sclk  : out std_logic;     -- SCLK hacia el dispositivo SPI
        bp_spi_mosi  : out std_logic;     -- MOSI hacia el dispositivo SPI
        bp_spi_miso  : in  std_logic;     -- MISO desde el dispositivo SPI
        bp_spi_cs0   : out std_logic      -- CS0 hacia el dispositivo SPI
    );
end uart_spi_mux;

architecture Behavioral of uart_spi_mux is

    -- Enables internos (activos en '1')
    signal uart_en : std_logic;
    signal spi_en  : std_logic;

begin

    ------------------------------------------------------------------------
    -- 1) ENABLES DESDE BOTONES (KEY activos en bajo)
    ------------------------------------------------------------------------
    uart_en <= not key0;  -- KEY0 presionado -> 0 -> uart_en = 1
    spi_en  <= not key1;  -- KEY1 presionado -> 0 -> spi_en  = 1

    -- LED / indicador: '1' si UART o SPI están habilitados
    enable_btn <= uart_en or spi_en;

    ------------------------------------------------------------------------
    -- 2) PUENTE UART: ESP32 <--> BACKPLANE (igual filosofía que uart_mux)
    --
    -- Cuando uart_en = '1':
    --   * esp_uart_rx recibe bp_uart_tx
    --   * bp_uart_rx recibe esp_uart_tx
    --
    -- Cuando uart_en = '0':
    --   * ambas RX quedan en '1' (idle UART, desconectado)
    ------------------------------------------------------------------------
    esp_uart_rx <= bp_uart_tx when uart_en = '1' else '1';
    bp_uart_rx  <= esp_uart_tx when uart_en = '1' else '1';

    ------------------------------------------------------------------------
    -- 3) PUENTE SPI: ESP32 <--> BACKPLANE
    --
    -- Cuando spi_en = '1':
    --   * Pasan SCLK, MOSI y CS0 de ESP32 al backplane
    --   * Pasa MISO del backplane hacia la ESP32
    --
    -- Cuando spi_en = '0':
    --   * Líneas quedan en estado "seguro":
    --       - SCLK = '0'
    --       - MOSI = '0'
    --       - CS0  = '1' (no seleccionado)
    --       - MISO hacia la ESP32 = '0'
    ------------------------------------------------------------------------
    bp_spi_sclk <= esp_spi_sclk when spi_en = '1' else '0';
    bp_spi_mosi <= esp_spi_mosi when spi_en = '1' else '0';
    bp_spi_cs0  <= esp_spi_cs0  when spi_en = '1' else '1';

    esp_spi_miso <= bp_spi_miso when spi_en = '1' else '0';

end Behavioral;
