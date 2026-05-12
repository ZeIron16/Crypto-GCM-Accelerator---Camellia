use work.gcm_pkg.all

entity camellia_core is
    Port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        data_in  : in  std_logic_vector(127 downto 0);
        key      : in  std_logic_vector(127 downto 0);
        data_out : out std_logic_vector(127 downto 0);

        valid_in  : in  std_logic;
        valid_out : out std_logic
    );
end camellia_core;

-- For now, this architecture is here to add 1 cycle of latency and support pipelining improvment in the future
-- (and make it more simple to implement)
architecture rtl of camellia_core is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_out <= '0';
                data_out  <= (others => '0');
            else
                data_out <= encr_camellia128(camellia_w128_t(data_in), camellia_w128_t(key));
                valid_out <= valid_in;
            end if;
        end if;
    end process;
end architecture rtl;
