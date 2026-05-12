entity gctr_core is
    port(
        clk: in std_logic;
        rst: in std_logic;
        
        -- Input
        ICB: in std_logic_vector(127 downto 0);
        key: in std_logic_vector(127 downto 0);
        start: in std_logic;
        
        -- Input X
        data_in: in std_logic_vector(127 downto 0);
        data_in_valid: in std_logic;
        is_last_in: in std_logic;
        bytes_valid_in: in std_logic_vector(3 downto 0); -- "0000" = 16 , "0001" = 1 and "1111" = 15
        
        -- Output
        data_out: out std_logic_vector(127 downto 0);
        data_out_valid: out std_logic;
        is_last_out: out std_logic;
        bytes_valid_out: out std_logic_vector(3 downto 0);
        len_out: out std_logic_vector(63 downto 0)
    );
end gctr_core;

architecture gctr of gctr_core is
    signal current: std_logic_vector(127 downto 0);

    -- Camellia
    signal cb_to_camellia: std_logic_vector(127 downto 0);
    signal camellia_result: std_logic_vector(127 downto 0);
    signal camellia_valid: std_logic;

    -- FIFO (depth 1): used due to the delay introduiced by Camellia
    signal data_in_reg: std_logic_vector(127 downto 0);
    signal is_last_reg: std_logic;
    signal bytes_valid_reg: std_logic_vector(3 downto 0);

    signal len_C : unsigned(63 downto 0);
begin
    camellia: entity work.camellia_core
        port map (
            clk => clk,
            rst => rst,
            key => key,
            data_in => cb_to_camellia,
            valid_in => data_in_valid,
            data_out => camellia_result,
            valid_out => camellia_valid
        );

    cb_to_camellia <= current;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current <= (others => '0');
                data_in_reg <= (others => '0');
                is_last_reg <= '0';
                bytes_valid_reg <= (others => '0');
                len_C <= (others => '0');

            elsif start = '1' then
                current <= ICB;
                len_C <= (others => '0');

            elsif data_in_valid = '1' then
                current <= current(127 downto 32) & std_logic_vector(unsigned(current(31 downto 0)) + 1); -- Increment on the 32 right bit to avoid modifying IV
                data_in_reg <= data_in;
                is_last_reg <= is_last_in;
                bytes_valid_reg <= bytes_valid_in;
                if is_last_in = '0' then
                    len_C <= len_C + 128;
                else
                    len_C <= len_C + (unsigned(bytes_valid_in) * 8);
                end if;
            end if;
        end if;
    end process;

    data_out <= camellia_result xor data_in_reg;
    data_out_valid <= camellia_valid;
    is_last_out <= is_last_reg;
    bytes_valid_out <= bytes_valid_reg;
    len_out <= std_logic_vector(len_C);

end architecture gctr;