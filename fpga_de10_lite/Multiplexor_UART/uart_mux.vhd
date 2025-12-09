library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity uart_mux is
    Port (
        sel    : in  std_logic;  -- 0 = conectar ESP<->DYP, 1 = romper

        esp_tx : in  std_logic;  -- TX de la ESP32 hacia la FPGA
        esp_rx : out std_logic;  -- RX de la ESP32 desde la FPGA

        dyp_tx : in  std_logic;  -- TX del DYP06 hacia la FPGA
        dyp_rx : out std_logic   -- RX del DYP06 desde la FPGA
    );
end uart_mux;

architecture Behavioral of uart_mux is
begin
    -- sel = '0'  → puente UART normal ESP <-> DYP (full duplex)
    -- sel = '1'  → se rompe la conexión: ambos RX quedan en '1' (idle UART)

    esp_rx <= dyp_tx when sel = '0' else '1';
    dyp_rx <= esp_tx when sel = '0' else '1';

end Behavioral;
