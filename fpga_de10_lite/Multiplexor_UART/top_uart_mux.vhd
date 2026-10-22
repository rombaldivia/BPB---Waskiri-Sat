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

    -- Antirrebote: 10 ms a 50 MHz
    constant DEBOUNCE_CYCLES : natural := 500000;

    -- 0 = conectar ESP<->DYP, 1 = romper (estado guardado por KEY0)
    signal sel_reg    : std_logic := '0';
    -- sel_effect = lo que realmente ve el uart_mux (incluye KEY1)
    signal sel_effect : std_logic := '0';

    -- Sincronizadores (KEY es asincrono respecto al reloj)
    signal key_s1     : std_logic_vector(1 downto 0) := (others => '1');
    signal key_s2     : std_logic_vector(1 downto 0) := (others => '1');

    -- Valores filtrados (estables DEBOUNCE_CYCLES ciclos)
    signal key_db     : std_logic_vector(1 downto 0) := (others => '1');
    signal key0_prev  : std_logic := '1';
    signal cnt0       : natural range 0 to DEBOUNCE_CYCLES := 0;
    signal cnt1       : natural range 0 to DEBOUNCE_CYCLES := 0;

begin

    ----------------------------------------------------------------
    -- Sincronizacion + antirrebote de KEY0 y KEY1
    -- Un valor nuevo solo se acepta si se mantiene DEBOUNCE_CYCLES
    -- ciclos seguidos. Sin esto, el rebote mecanico hacia toggles
    -- multiples con una sola pulsacion.
    ----------------------------------------------------------------
    process (MAX10_CLK1_50)
    begin
        if rising_edge(MAX10_CLK1_50) then
            key_s1 <= KEY;
            key_s2 <= key_s1;

            if key_s2(0) = key_db(0) then
                cnt0 <= 0;
            elsif cnt0 = DEBOUNCE_CYCLES then
                key_db(0) <= key_s2(0);
                cnt0      <= 0;
            else
                cnt0 <= cnt0 + 1;
            end if;

            if key_s2(1) = key_db(1) then
                cnt1 <= 0;
            elsif cnt1 = DEBOUNCE_CYCLES then
                key_db(1) <= key_s2(1);
                cnt1      <= 0;
            else
                cnt1 <= cnt1 + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Lógica de KEY0 para hacer toggle de sel_reg
    -- KEY(0) es activo en bajo: presionado cuando key_db(0) = '0'
    ----------------------------------------------------------------
    process (MAX10_CLK1_50)
    begin
        if rising_edge(MAX10_CLK1_50) then
            -- Flanco de "presionado": de '1' a '0' (ya filtrado)
            if (key_db(0) = '0' and key0_prev = '1') then
                sel_reg <= not sel_reg;
            end if;

            key0_prev <= key_db(0);
        end if;
    end process;

    ----------------------------------------------------------------
    -- KEY1 como "break":
    -- Si KEY(1) está presionado (='0') → forzamos sel_effect = '1' (romper)
    -- Si no, usamos el valor de sel_reg (de KEY0).
    ----------------------------------------------------------------
    sel_effect <= '1' when key_db(1) = '0' else sel_reg;

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
