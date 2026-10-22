--------------------------------------------------------------------------------
-- uart_mux.vhd (Multiplexor_UART_SPI)
-- Mux UART 1 maestro -> 2 esclavos (A / B)
--
-- Correccion respecto a la version anterior: antes se multiplexaban los dos
-- TX y los dos RX como entradas, por lo que el TX del maestro nunca llegaba
-- a ningun esclavo. En una UART hay que:
--   * DEMULTIPLEXAR el TX del maestro hacia el RX del esclavo seleccionado
--   * MULTIPLEXAR el TX del esclavo seleccionado hacia el RX del maestro
-- El esclavo no seleccionado queda con su RX en '1' (idle).
--
-- Nota: este archivo esta en el .qsf de uart_spi_mux pero no se instancia
-- ahi; para N esclavos con seleccion desde el Mission Boss ver
-- ../BPB_Router/bpb_router.vhd
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity uart_mux is
    Port (
        sel      : in  std_logic;      -- 0 = esclavo A, 1 = esclavo B

        -- Maestro
        m_tx     : in  std_logic;      -- TX del maestro -> mux
        m_rx     : out std_logic;      -- mux -> RX del maestro

        -- Esclavo A
        a_tx     : in  std_logic;
        a_rx     : out std_logic;

        -- Esclavo B
        b_tx     : in  std_logic;
        b_rx     : out std_logic
    );
end uart_mux;

architecture Behavioral of uart_mux is
begin

    -- Maestro -> esclavo seleccionado (el otro queda en idle '1')
    a_rx <= m_tx when sel = '0' else '1';
    b_rx <= m_tx when sel = '1' else '1';

    -- Esclavo seleccionado -> maestro
    m_rx <= a_tx when sel = '0' else b_tx;

end Behavioral;
