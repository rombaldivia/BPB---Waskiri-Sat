--------------------------------------------------------------------------------
-- bpb_router.vhd
-- BPB Waskiri-Sat - Router UART/SPI N:1 controlado por el Mission Boss
--
-- Concepto (igual que el CPLD del BIRDS-X):
--   El OBC manda el comando por UART al Mission Boss (PIC). El Mission Boss
--   NO manda bytes al CPLD: solo pone niveles logicos en las lineas de
--   seleccion (sel, uart_en, spi_en). Este bloque conecta fisicamente la
--   UART/SPI del Mission Boss con la payload seleccionada.
--
-- Codificacion de sel:
--   sel = 0            -> ninguna payload conectada (equivale a APRS_OFFSET)
--   sel = 1..N_SLOTS   -> payload (sel-1)
--   sel > N_SLOTS      -> invalido, ninguna payload conectada
--
-- Seguridad:
--   * sel/uart_en/spi_en se sincronizan (2 FF) y deben quedar estables
--     STABLE_CYCLES ciclos antes de aplicarse (filtra skew entre bits y ruido).
--   * Break-before-make: apenas cambia la peticion se desconecta todo y
--     recien cuando es estable se conecta el nuevo destino. Nunca hay dos
--     payloads conectadas a la vez.
--   * Los habilitadores por payload son registros one-hot: no hay glitches
--     en CS por decodificacion combinacional de sel.
--   * Si WAIT_SPI_IDLE = true, no se cambia la ruta mientras el Mission Boss
--     tiene CS en '0' (transferencia SPI en curso).
--   * Lineas desconectadas en estado seguro:
--       UART RX -> '1' (idle)
--       SPI  SCLK -> '0', MOSI -> '0', CS -> '1', MISO hacia el MB -> '0'
--
-- La ruta de datos es combinacional (solo retardo de propagacion), el reloj
-- se usa unicamente para el control de seleccion.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bpb_router is
    generic (
        N_SLOTS       : positive := 7;      -- payloads en el backplane
        SEL_W         : positive := 3;      -- bits de sel (2**SEL_W > N_SLOTS)
        STABLE_CYCLES : positive := 16;     -- ciclos de clk que sel debe ser estable
        WAIT_SPI_IDLE : boolean  := true    -- no cambiar ruta con CS del MB activo
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;       -- reset asincrono, activo en '1'

        -- Lineas de control desde el Mission Boss (GPIO)
        sel          : in  std_logic_vector(SEL_W-1 downto 0);
        uart_en      : in  std_logic;
        spi_en       : in  std_logic;

        -- UART lado Mission Boss
        mb_uart_tx   : in  std_logic;       -- TX del MB -> router
        mb_uart_rx   : out std_logic;       -- router -> RX del MB

        -- UART lado payloads
        pl_uart_tx   : in  std_logic_vector(N_SLOTS-1 downto 0);
        pl_uart_rx   : out std_logic_vector(N_SLOTS-1 downto 0);

        -- SPI lado Mission Boss (maestro)
        mb_spi_sclk  : in  std_logic;
        mb_spi_mosi  : in  std_logic;
        mb_spi_cs    : in  std_logic;       -- activo en '0'
        mb_spi_miso  : out std_logic;

        -- SPI lado payloads (esclavos)
        pl_spi_sclk  : out std_logic_vector(N_SLOTS-1 downto 0);
        pl_spi_mosi  : out std_logic_vector(N_SLOTS-1 downto 0);
        pl_spi_cs    : out std_logic_vector(N_SLOTS-1 downto 0);
        pl_spi_miso  : in  std_logic_vector(N_SLOTS-1 downto 0);

        -- Estado (LEDs / telemetria)
        active_sel   : out std_logic_vector(SEL_W-1 downto 0); -- sel aplicado
        uart_active  : out std_logic;
        spi_active   : out std_logic;
        switching    : out std_logic        -- '1' durante break-before-make
    );
end bpb_router;

architecture rtl of bpb_router is

    constant REQ_W : natural := SEL_W + 2;  -- sel & uart_en & spi_en

    -- Sincronizadores
    signal req_s1, req_s2 : std_logic_vector(REQ_W-1 downto 0) := (others => '0');
    signal cs_s1, cs_s2   : std_logic := '1';

    -- Control
    signal req_prev : std_logic_vector(REQ_W-1 downto 0) := (others => '0');
    signal applied  : std_logic_vector(REQ_W-1 downto 0) := (others => '0');
    signal cnt      : integer range 0 to STABLE_CYCLES := 0;

    -- Habilitadores one-hot registrados
    signal uart_on  : std_logic_vector(N_SLOTS-1 downto 0) := (others => '0');
    signal spi_on   : std_logic_vector(N_SLOTS-1 downto 0) := (others => '0');

    signal sw_i     : std_logic := '0';

    -- Decodifica sel a one-hot (0 o invalido -> todo en cero)
    function decode(s : std_logic_vector; en : std_logic) return std_logic_vector is
        variable r   : std_logic_vector(N_SLOTS-1 downto 0) := (others => '0');
        variable idx : integer;
    begin
        idx := to_integer(unsigned(s));
        if en = '1' and idx >= 1 and idx <= N_SLOTS then
            r(idx-1) := '1';
        end if;
        return r;
    end function;

begin

    assert 2**SEL_W > N_SLOTS
        report "bpb_router: SEL_W insuficiente para N_SLOTS" severity failure;

    ----------------------------------------------------------------------------
    -- Control de seleccion
    ----------------------------------------------------------------------------
    process (clk, rst)
        variable req       : std_logic_vector(REQ_W-1 downto 0);
        variable spi_idle  : boolean;
    begin
        if rst = '1' then
            req_s1   <= (others => '0');
            req_s2   <= (others => '0');
            cs_s1    <= '1';
            cs_s2    <= '1';
            req_prev <= (others => '0');
            applied  <= (others => '0');
            cnt      <= 0;
            uart_on  <= (others => '0');
            spi_on   <= (others => '0');
            sw_i     <= '0';
        elsif rising_edge(clk) then
            -- 2 FF de sincronizacion
            req_s1 <= sel & uart_en & spi_en;
            req_s2 <= req_s1;
            cs_s1  <= mb_spi_cs;
            cs_s2  <= cs_s1;

            req      := req_s2;
            req_prev <= req;

            -- Filtro de estabilidad
            if req /= req_prev then
                cnt <= 0;
            elsif cnt < STABLE_CYCLES then
                cnt <= cnt + 1;
            end if;

            spi_idle := (not WAIT_SPI_IDLE) or (cs_s2 = '1');

            if req /= applied then
                if spi_idle then
                    -- BREAK: desconectar todo de inmediato
                    uart_on <= (others => '0');
                    spi_on  <= (others => '0');
                    sw_i    <= '1';
                    -- MAKE: aplicar solo cuando la peticion es estable
                    if req = req_prev and cnt = STABLE_CYCLES then
                        applied <= req;
                    end if;
                end if;
            else
                uart_on <= decode(applied(REQ_W-1 downto 2), applied(1));
                spi_on  <= decode(applied(REQ_W-1 downto 2), applied(0));
                sw_i    <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Ruta de datos UART (combinacional)
    ----------------------------------------------------------------------------
    gen_uart : for i in 0 to N_SLOTS-1 generate
        pl_uart_rx(i) <= mb_uart_tx when uart_on(i) = '1' else '1';
    end generate;

    -- Las payloads no seleccionadas aportan '1' (idle), asi que un AND
    -- funciona como mux sin decodificador.
    process (pl_uart_tx, uart_on)
        variable acc : std_logic;
    begin
        acc := '1';
        for i in 0 to N_SLOTS-1 loop
            acc := acc and (pl_uart_tx(i) or not uart_on(i));
        end loop;
        mb_uart_rx <= acc;
    end process;

    ----------------------------------------------------------------------------
    -- Ruta de datos SPI (combinacional)
    ----------------------------------------------------------------------------
    gen_spi : for i in 0 to N_SLOTS-1 generate
        pl_spi_sclk(i) <= mb_spi_sclk when spi_on(i) = '1' else '0';
        pl_spi_mosi(i) <= mb_spi_mosi when spi_on(i) = '1' else '0';
        pl_spi_cs(i)   <= mb_spi_cs   when spi_on(i) = '1' else '1';
    end generate;

    process (pl_spi_miso, spi_on)
        variable acc : std_logic;
    begin
        acc := '0';
        for i in 0 to N_SLOTS-1 loop
            acc := acc or (pl_spi_miso(i) and spi_on(i));
        end loop;
        mb_spi_miso <= acc;
    end process;

    ----------------------------------------------------------------------------
    -- Estado
    ----------------------------------------------------------------------------
    active_sel  <= applied(REQ_W-1 downto 2);
    uart_active <= '0' when uart_on = (uart_on'range => '0') else '1';
    spi_active  <= '0' when spi_on  = (spi_on'range  => '0') else '1';
    switching   <= sw_i;

end rtl;
