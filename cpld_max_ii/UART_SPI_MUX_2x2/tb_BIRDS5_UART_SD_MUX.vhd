library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity tb_BIRDS5_UART_SD_MUX is end;
architecture s of tb_BIRDS5_UART_SD_MUX is
  signal k : std_logic_vector(3 downto 0) := "1111"; -- u0,u1,s0,s1 (activo bajo)
  signal etx,erx,b0tx,b0rx,b1tx,b1rx : std_logic := '1';
  signal sck,mosi,cs,miso : std_logic := '1';
  signal s0sck,s0mosi,s0cs,s0miso,s1sck,s1mosi,s1cs,s1miso : std_logic := '1';
  signal led : std_logic_vector(3 downto 0);
  signal errs : natural := 0;
begin
  dut: entity work.BIRDS5_UART_SD_MUX port map(
    key_uart=>k(3), key_uart1=>k(2), key_sd=>k(1), key_spi1=>k(0),
    esp_uart_tx=>etx, esp_uart_rx=>erx, bpb_uart_tx=>b0tx, bpb_uart_rx=>b0rx,
    bpb_uart1_tx=>b1tx, bpb_uart1_rx=>b1rx,
    esp_sd_sck=>sck, esp_sd_mosi=>mosi, esp_sd_cs=>cs, esp_sd_miso=>miso,
    bpb_sd_sck=>s0sck, bpb_sd_mosi=>s0mosi, bpb_sd_cs=>s0cs, bpb_sd_miso=>s0miso,
    bpb_spi1_sck=>s1sck, bpb_spi1_mosi=>s1mosi, bpb_spi1_cs=>s1cs, bpb_spi1_miso=>s1miso,
    led=>led);
  process
    procedure chk(c: boolean; m: string) is begin if not c then report "FALLO: "&m severity error; errs<=errs+1; end if; end;
    variable u0,u1,s0,s1 : boolean;
  begin
    for i in 0 to 15 loop
      k <= std_logic_vector(to_unsigned(i,4));
      wait for 1 ns;
      u0 := k(3)='0' and k(2)='1'; u1 := k(2)='0' and k(3)='1';
      s0 := k(1)='0' and k(0)='1'; s1 := k(0)='0' and k(1)='1';
      -- ESP -> esclavos
      etx<='0'; sck<='1'; mosi<='1'; cs<='0'; wait for 5 ns;
      chk((b0rx='0')=u0 and (b1rx='0')=u1, "UART demux combo "&integer'image(i));
      chk((s0sck='1' and s0mosi='1' and s0cs='0')=s0, "SPI0 combo "&integer'image(i));
      chk((s1sck='1' and s1mosi='1' and s1cs='0')=s1, "SPI1 combo "&integer'image(i));
      if not s0 then chk(s0sck='0' and s0mosi='0' and s0cs='1', "SPI0 no seguro "&integer'image(i)); end if;
      if not s1 then chk(s1sck='0' and s1mosi='0' and s1cs='1', "SPI1 no seguro "&integer'image(i)); end if;
      etx<='1'; sck<='0'; mosi<='0'; cs<='1';
      -- esclavos -> ESP: solo el seleccionado llega
      b0tx<='0'; b1tx<='1'; wait for 5 ns; chk((erx='0')=u0, "UART0->ESP "&integer'image(i));
      b0tx<='1'; b1tx<='0'; wait for 5 ns; chk((erx='0')=u1, "UART1->ESP "&integer'image(i));
      b1tx<='1';
      s0miso<='0'; s1miso<='1'; wait for 5 ns; chk((miso='0')=s0, "MISO0->ESP "&integer'image(i));
      s0miso<='1'; s1miso<='0'; wait for 5 ns; chk((miso='0')=s1, "MISO1->ESP "&integer'image(i));
      s1miso<='1';
      chk((led(0)='1')=u0 and (led(1)='1')=u1 and (led(2)='1')=s0 and (led(3)='1')=s1, "LEDs "&integer'image(i));
    end loop;
    wait for 1 ns;
    if errs=0 then report "OK: 16 combinaciones de botones"; else report integer'image(errs)&" FALLOS" severity failure; end if;
    wait;
  end process;
end;
