--------------------------------------------------------------------------------
-- top_bpb_router_de10.vhd
-- Top de prueba del bpb_router en la DE10-Lite (MAX 10, 10M50DAF484C7G)
--
-- Fuente de control (SW9):
--   SW9 = 0 -> manual desde switches: SW2..SW0 = sel, SW3 = uart_en, SW4 = spi_en
--   SW9 = 1 -> desde el Mission Boss (PIC) por GPIO: MB_SEL, MB_UART_EN, MB_SPI_EN
--
-- KEY0 = reset (activo en bajo)
--
-- LEDs:
--   LEDR2..0 = sel aplicado, LEDR3 = UART activa, LEDR4 = SPI activa,
--   LEDR5 = cambiando (break-before-make), LEDR9 = control desde Mission Boss
--
-- STABLE_CYCLES = 50_000 -> 1 ms a 50 MHz (filtra rebote de switches y ruido
-- en las lineas del PIC). Las asignaciones de pines van en el .qsf.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_bpb_router_de10 is
    generic (
        N_SLOTS : positive := 4
    );
    port (
        MAX10_CLK1_50 : in  std_logic;
        KEY           : in  std_logic_vector(1 downto 0);
        SW            : in  std_logic_vector(9 downto 0);
        LEDR          : out std_logic_vector(9 downto 0);

        -- Control desde el Mission Boss (GPIO)
        MB_SEL        : in  std_logic_vector(2 downto 0);
        MB_UART_EN    : in  std_logic;
        MB_SPI_EN     : in  std_logic;

        -- UART del Mission Boss
        MB_UART_TX    : in  std_logic;
        MB_UART_RX    : out std_logic;

        -- SPI del Mission Boss
        MB_SPI_SCLK   : in  std_logic;
        MB_SPI_MOSI   : in  std_logic;
        MB_SPI_CS     : in  std_logic;
        MB_SPI_MISO   : out std_logic;

        -- Payloads
        PL_UART_TX    : in  std_logic_vector(N_SLOTS-1 downto 0);
        PL_UART_RX    : out std_logic_vector(N_SLOTS-1 downto 0);
        PL_SPI_SCLK   : out std_logic_vector(N_SLOTS-1 downto 0);
        PL_SPI_MOSI   : out std_logic_vector(N_SLOTS-1 downto 0);
        PL_SPI_CS     : out std_logic_vector(N_SLOTS-1 downto 0);
        PL_SPI_MISO   : in  std_logic_vector(N_SLOTS-1 downto 0)
    );
end top_bpb_router_de10;

architecture rtl of top_bpb_router_de10 is

    signal rst        : std_logic;
    signal sel_i      : std_logic_vector(2 downto 0);
    signal uart_en_i  : std_logic;
    signal spi_en_i   : std_logic;

    signal active_sel : std_logic_vector(2 downto 0);
    signal uart_act   : std_logic;
    signal spi_act    : std_logic;
    signal sw_act     : std_logic;

begin

    rst <= not KEY(0);

    -- Mux de la fuente de control (SW9). El cambio de fuente pasa por el
    -- filtro del router igual que cualquier otro cambio de sel.
    sel_i     <= MB_SEL     when SW(9) = '1' else SW(2 downto 0);
    uart_en_i <= MB_UART_EN when SW(9) = '1' else SW(3);
    spi_en_i  <= MB_SPI_EN  when SW(9) = '1' else SW(4);

    u_router : entity work.bpb_router
        generic map (
            N_SLOTS       => N_SLOTS,
            SEL_W         => 3,
            STABLE_CYCLES => 50000,
            WAIT_SPI_IDLE => true
        )
        port map (
            clk         => MAX10_CLK1_50,
            rst         => rst,
            sel         => sel_i,
            uart_en     => uart_en_i,
            spi_en      => spi_en_i,
            mb_uart_tx  => MB_UART_TX,
            mb_uart_rx  => MB_UART_RX,
            pl_uart_tx  => PL_UART_TX,
            pl_uart_rx  => PL_UART_RX,
            mb_spi_sclk => MB_SPI_SCLK,
            mb_spi_mosi => MB_SPI_MOSI,
            mb_spi_cs   => MB_SPI_CS,
            mb_spi_miso => MB_SPI_MISO,
            pl_spi_sclk => PL_SPI_SCLK,
            pl_spi_mosi => PL_SPI_MOSI,
            pl_spi_cs   => PL_SPI_CS,
            pl_spi_miso => PL_SPI_MISO,
            active_sel  => active_sel,
            uart_active => uart_act,
            spi_active  => spi_act,
            switching   => sw_act
        );

    LEDR(2 downto 0) <= active_sel;
    LEDR(3)          <= uart_act;
    LEDR(4)          <= spi_act;
    LEDR(5)          <= sw_act;
    LEDR(8 downto 6) <= (others => '0');
    LEDR(9)          <= SW(9);

end rtl;
