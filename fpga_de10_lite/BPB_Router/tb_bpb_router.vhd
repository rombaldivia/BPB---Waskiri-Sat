--------------------------------------------------------------------------------
-- tb_bpb_router.vhd
-- Testbench autoverificable para bpb_router (7 payloads, como el BIRDS-X)
--
-- Pruebas:
--   1. Reset: todas las lineas en estado seguro
--   2. Ruteo UART a cada payload + aislamiento del resto
--   3. Ruteo SPI (SCLK/MOSI/CS/MISO) + aislamiento
--   4. Cambio con skew entre bits de sel (3 -> 4): ninguna payload ajena se
--      conecta y nunca hay dos payloads activas (break-before-make)
--   5. No se cambia la ruta mientras CS del Mission Boss esta en '0'
--   6. sel = 0 desconecta todo
--
-- GHDL:
--   ghdl -a bpb_router.vhd tb_bpb_router.vhd
--   ghdl -e tb_bpb_router
--   ghdl -r tb_bpb_router --wave=tb.ghw
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_bpb_router is
end tb_bpb_router;

architecture sim of tb_bpb_router is

    constant N      : positive := 7;
    constant SW     : positive := 3;
    constant STABLE : positive := 4;
    constant TCLK   : time     := 20 ns;   -- 50 MHz (DE10-Lite)

    signal clk, rst              : std_logic := '0';
    signal sel                   : std_logic_vector(SW-1 downto 0) := (others => '0');
    signal uart_en, spi_en       : std_logic := '0';

    signal mb_uart_tx            : std_logic := '1';
    signal mb_uart_rx            : std_logic;
    signal pl_uart_tx            : std_logic_vector(N-1 downto 0) := (others => '1');
    signal pl_uart_rx            : std_logic_vector(N-1 downto 0);

    signal mb_spi_sclk, mb_spi_mosi : std_logic := '0';
    signal mb_spi_cs             : std_logic := '1';
    signal mb_spi_miso           : std_logic;
    signal pl_spi_sclk, pl_spi_mosi, pl_spi_cs : std_logic_vector(N-1 downto 0);
    signal pl_spi_miso           : std_logic_vector(N-1 downto 0) := (others => '0');

    signal active_sel            : std_logic_vector(SW-1 downto 0);
    signal uart_active, spi_active, switching : std_logic;

    -- Monitores
    signal forbidden_mask        : std_logic_vector(N-1 downto 0) := (others => '0');
    signal forbidden_hit         : boolean := false;
    signal multi_hit             : boolean := false;
    signal done                  : boolean := false;
    signal errors                : natural := 0;

    function count_low(v : std_logic_vector) return natural is
        variable c : natural := 0;
    begin
        for i in v'range loop
            if v(i) = '0' then c := c + 1; end if;
        end loop;
        return c;
    end function;

    function count_high(v : std_logic_vector) return natural is
        variable c : natural := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then c := c + 1; end if;
        end loop;
        return c;
    end function;

begin

    clk <= not clk after TCLK/2 when not done else '0';

    dut : entity work.bpb_router
        generic map (N_SLOTS => N, SEL_W => SW, STABLE_CYCLES => STABLE,
                     WAIT_SPI_IDLE => true)
        port map (
            clk => clk, rst => rst,
            sel => sel, uart_en => uart_en, spi_en => spi_en,
            mb_uart_tx => mb_uart_tx, mb_uart_rx => mb_uart_rx,
            pl_uart_tx => pl_uart_tx, pl_uart_rx => pl_uart_rx,
            mb_spi_sclk => mb_spi_sclk, mb_spi_mosi => mb_spi_mosi,
            mb_spi_cs => mb_spi_cs, mb_spi_miso => mb_spi_miso,
            pl_spi_sclk => pl_spi_sclk, pl_spi_mosi => pl_spi_mosi,
            pl_spi_cs => pl_spi_cs, pl_spi_miso => pl_spi_miso,
            active_sel => active_sel, uart_active => uart_active,
            spi_active => spi_active, switching => switching
        );

    -- Monitor continuo: nunca dos payloads conectadas a la vez
    -- (mb_uart_tx en '0' => todas las RX conectadas veran '0')
    mon_multi : process (pl_uart_rx, pl_spi_cs, pl_spi_sclk, mb_uart_tx)
    begin
        if count_low(pl_spi_cs) > 1 or count_high(pl_spi_sclk) > 1 then
            multi_hit <= true;
        end if;
        if mb_uart_tx = '0' and count_low(pl_uart_rx) > 1 then
            multi_hit <= true;
        end if;
    end process;

    -- Monitor de payloads prohibidas durante el cambio con skew
    mon_forbidden : process (pl_spi_cs, pl_uart_rx, forbidden_mask)
    begin
        for i in 0 to N-1 loop
            if forbidden_mask(i) = '1' and
               (pl_spi_cs(i) = '0' or pl_uart_rx(i) = '0') then
                forbidden_hit <= true;
            end if;
        end loop;
    end process;

    stim : process

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                report "FALLO: " & msg severity error;
                errors <= errors + 1;
            end if;
        end procedure;

        procedure wait_clk(cycles : natural) is
        begin
            for k in 1 to cycles loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Espera a que el router aplique y termine el cambio
        procedure settle is
        begin
            wait_clk(STABLE + 8);
            wait for 1 ns;
        end procedure;

        procedure check_safe(msg : string) is
        begin
            check(pl_uart_rx = (pl_uart_rx'range => '1'), msg & ": UART RX idle");
            check(pl_spi_cs  = (pl_spi_cs'range  => '1'), msg & ": CS en '1'");
            check(pl_spi_sclk = (pl_spi_sclk'range => '0'), msg & ": SCLK en '0'");
            check(pl_spi_mosi = (pl_spi_mosi'range => '0'), msg & ": MOSI en '0'");
            check(mb_uart_rx = '1', msg & ": RX del MB idle");
            check(mb_spi_miso = '0', msg & ": MISO del MB en '0'");
        end procedure;

        -- Verifica ruteo UART bidireccional hacia la payload k (0-based)
        procedure check_uart(k : natural) is
        begin
            mb_uart_tx <= '0';
            wait for 5 ns;
            for i in 0 to N-1 loop
                if i = k then
                    check(pl_uart_rx(i) = '0', "UART: payload " & integer'image(i) & " no recibe");
                else
                    check(pl_uart_rx(i) = '1', "UART: payload " & integer'image(i) & " no aislada");
                end if;
            end loop;
            mb_uart_tx <= '1';

            -- Payloads ajenas transmitiendo no deben llegar al MB
            pl_uart_tx <= (others => '0');
            pl_uart_tx(k) <= '1';
            wait for 5 ns;
            check(mb_uart_rx = '1', "UART: payload ajena llega al MB");
            pl_uart_tx(k) <= '0';
            wait for 5 ns;
            check(mb_uart_rx = '0', "UART: payload seleccionada no llega al MB");
            pl_uart_tx <= (others => '1');
            wait for 5 ns;
        end procedure;

        procedure select_slot(s : natural; u, p : std_logic) is
        begin
            sel     <= std_logic_vector(to_unsigned(s, SW));
            uart_en <= u;
            spi_en  <= p;
            settle;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- 1. Reset
        ------------------------------------------------------------------
        rst <= '1';
        wait_clk(3);
        rst <= '0';
        settle;
        check_safe("reset");

        ------------------------------------------------------------------
        -- 2. UART a cada payload
        ------------------------------------------------------------------
        for s in 1 to N loop
            select_slot(s, '1', '0');
            check(to_integer(unsigned(active_sel)) = s, "active_sel incorrecto");
            check(uart_active = '1' and spi_active = '0', "flags de estado UART");
            check_uart(s-1);
            check(pl_spi_cs = (pl_spi_cs'range => '1'), "SPI activo sin spi_en");
        end loop;

        ------------------------------------------------------------------
        -- 3. SPI hacia la payload 5 (sel = 5)
        ------------------------------------------------------------------
        select_slot(5, '0', '1');
        check(pl_uart_rx = (pl_uart_rx'range => '1'), "UART activo sin uart_en");
        mb_spi_cs <= '0'; mb_spi_sclk <= '1'; mb_spi_mosi <= '1';
        wait for 5 ns;
        for i in 0 to N-1 loop
            if i = 4 then
                check(pl_spi_cs(i) = '0' and pl_spi_sclk(i) = '1' and pl_spi_mosi(i) = '1',
                      "SPI: payload 4 no recibe");
            else
                check(pl_spi_cs(i) = '1' and pl_spi_sclk(i) = '0' and pl_spi_mosi(i) = '0',
                      "SPI: payload " & integer'image(i) & " no aislada");
            end if;
        end loop;
        pl_spi_miso <= (others => '1');
        pl_spi_miso(4) <= '0';
        wait for 5 ns;
        check(mb_spi_miso = '0', "SPI: MISO ajeno llega al MB");
        pl_spi_miso(4) <= '1';
        wait for 5 ns;
        check(mb_spi_miso = '1', "SPI: MISO seleccionado no llega al MB");
        pl_spi_miso <= (others => '0');
        mb_spi_cs <= '1'; mb_spi_sclk <= '0'; mb_spi_mosi <= '0';
        wait for 5 ns;

        ------------------------------------------------------------------
        -- 4. Cambio 3 -> 4 con skew entre bits (011 -> 100)
        --    Pasa por codigos intermedios (111, 101, 001, 000...).
        --    Solo pueden conectarse las payloads 2 (sel 3) y 3 (sel 4).
        ------------------------------------------------------------------
        select_slot(3, '1', '1');
        forbidden_mask <= (others => '1');
        forbidden_mask(2) <= '0';
        forbidden_mask(3) <= '0';
        mb_uart_tx <= '0';                -- cualquier payload conectada vera RX='0'
        wait for 1 ns;
        sel(2) <= '1'; wait for 50 ns;    -- 111 (2.5 ciclos, < filtro)
        sel(0) <= '0'; wait for 70 ns;    -- 110 (3.5 ciclos, < filtro)
        sel(1) <= '0';                    -- 100
        wait_clk(STABLE + 8);
        wait for 1 ns;
        check(not forbidden_hit, "skew: se conecto una payload ajena");
        check(to_integer(unsigned(active_sel)) = 4, "skew: no termino en sel=4");
        check(pl_uart_rx(3) = '0', "skew: payload 3 no conectada al final");
        mb_uart_tx <= '1';
        forbidden_mask <= (others => '0');
        wait for 5 ns;

        ------------------------------------------------------------------
        -- 5. CS activo bloquea el cambio
        ------------------------------------------------------------------
        mb_spi_cs <= '0';
        wait_clk(4);
        sel <= std_logic_vector(to_unsigned(6, SW));
        wait_clk(STABLE + 20);
        wait for 1 ns;
        check(to_integer(unsigned(active_sel)) = 4, "CS bajo: la ruta cambio en plena transferencia");
        check(pl_spi_cs(3) = '0', "CS bajo: payload en curso fue desconectada");
        mb_spi_cs <= '1';
        settle;
        check(to_integer(unsigned(active_sel)) = 6, "CS alto: no aplico el cambio pendiente");

        ------------------------------------------------------------------
        -- 6. sel = 0 -> todo desconectado
        ------------------------------------------------------------------
        select_slot(0, '1', '1');
        check_safe("sel=0");
        check(uart_active = '0' and spi_active = '0', "sel=0: flags activos");

        ------------------------------------------------------------------
        check(not multi_hit, "break-before-make: dos payloads conectadas a la vez");

        wait for 1 ns;
        if errors = 0 then
            report "TB bpb_router: TODAS LAS PRUEBAS PASARON" severity note;
        else
            report "TB bpb_router: " & integer'image(errors) & " FALLOS" severity failure;
        end if;
        done <= true;
        wait;
    end process;

end sim;
