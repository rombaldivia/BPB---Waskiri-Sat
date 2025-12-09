library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity uart_mux is
    Port (
        sel         : in  std_logic;      -- 0 = UART A, 1 = UART B

        uartA_tx    : in  std_logic;
        uartA_rx    : in  std_logic;

        uartB_tx    : in  std_logic;
        uartB_rx    : in  std_logic;

        uart_out_tx : out std_logic;
        uart_out_rx : out std_logic
    );
end uart_mux;

architecture Behavioral of uart_mux is
begin

    -- Multiplexor combinacional para UART TX
    uart_out_tx <= uartA_tx when sel = '0' else uartB_tx;

    -- Multiplexor combinacional para UART RX
    uart_out_rx <= uartA_rx when sel = '0' else uartB_rx;

end Behavioral;
