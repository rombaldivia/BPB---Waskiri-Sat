library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_uart_mux is
    Port (
        -- Reloj de la DE10-Lite
        MAX10_CLK1_50 : in  std_logic;

        -- Botones (activos en bajo en la DE10-Lite)
        KEY           : in  std_logic_vector(1 downto 0);
        -- KEY(0): toggle sel
        -- KEY(1): break mientras esté presionado

        -- UART ESP32
        ESP_TX        : in  std_logic;
        ESP_RX        : out std_logic;

        -- UART DYP06
        DYP_TX        : in  std_logic;
        DYP_RX        : out std_logic;

        -- LEDs
        LEDR          : out std_logic_vector(9 downto 0)
    );
end top_uart_mux;

architecture Behavioral of top_uart_mux is

    -- 0 = conectar ESP<->DYP, 1 = romper (estado guardado por KEY0)
    signal sel_reg    : std_logic := '0';
    -- sel_effect = lo que realmente ve el uart_mux (incluye KEY1)
    signal sel_effect : std_logic := '0';

    -- Para detectar flanco en KEY0
    signal key0_prev  : std_logic := '1';  -- KEY(0) no presionado al inicio

begin

    ----------------------------------------------------------------
    -- Lógica de KEY0 para hacer toggle de sel_reg
    -- KEY(0) es activo en bajo: presionado cuando KEY(0) = '0'
    ----------------------------------------------------------------
    process (MAX10_CLK1_50)
    begin
        if rising_edge(MAX10_CLK1_50) then
            -- Flanco de "presionado": de '1' a '0'
            if (KEY(0) = '0' and key0_prev = '1') then
                sel_reg <= not sel_reg;
            end if;

            key0_prev <= KEY(0);
        end if;
    end process;

    ----------------------------------------------------------------
    -- KEY1 como "break" directo:
    -- Si KEY(1) está presionado (='0') → forzamos sel_effect = '1' (romper)
    -- Si no, usamos el valor de sel_reg (de KEY0).
    ----------------------------------------------------------------
    sel_effect <= '1' when KEY(1) = '0' else sel_reg;

    ----------------------------------------------------------------
    -- Instancia de uart_mux
    ----------------------------------------------------------------
    u_mux : entity work.uart_mux
        port map (
            sel    => sel_effect,
            esp_tx => ESP_TX,
            esp_rx => ESP_RX,
            dyp_tx => DYP_TX,
            dyp_rx => DYP_RX
        );

    ----------------------------------------------------------------
    -- LEDs
    ----------------------------------------------------------------
    -- LEDR(0) muestra el estado real del mux:
    -- 0 = ESP<->DYP conectados
    -- 1 = conexión rota
    LEDR(0) <= sel_effect;

    -- El resto apagados por ahora
    LEDR(9 downto 1) <= (others => '0');

end Behavioral;
