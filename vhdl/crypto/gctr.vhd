library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gctr is
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
        ready: out std_logic;
        data_out: out std_logic_vector(127 downto 0);
        data_out_valid: out std_logic;
        is_last_out: out std_logic;
        bytes_valid_out: out std_logic_vector(3 downto 0);
        len_out: out std_logic_vector(63 downto 0)
    );
end gctr;

architecture rtl of gctr is
    signal current: std_logic_vector(127 downto 0);

    signal cb_to_camellia: std_logic_vector(127 downto 0);
    signal camellia_result: std_logic_vector(127 downto 0);
    signal camellia_valid: std_logic;
    signal camellia_ready: std_logic;

    signal saved_data : std_logic_vector(127 downto 0);
    signal saved_last : std_logic;
    signal saved_bytes: std_logic_vector(3 downto 0);
    
    signal len_C : unsigned(63 downto 0);
begin
    camellia: entity work.camellia_core
        port map (
            clk => clk,
            rst => rst,
            key => key,
            data_in => cb_to_camellia,
            valid_in => data_in_valid,
            ready => camellia_ready,
            data_out => camellia_result,
            valid_out => camellia_valid
        );

    ready <= camellia_ready;
    cb_to_camellia <= current;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current <= (others => '0');
                len_C <= (others => '0');

            elsif start = '1' then
                current <= ICB;
                len_C <= (others => '0');

            else
                if data_in_valid = '1' and camellia_ready = '1' then
                    current <= current(127 downto 32) & std_logic_vector(unsigned(current(31 downto 0)) + 1); 
                    
                    saved_data  <= data_in;
                    saved_last  <= is_last_in;
                    saved_bytes <= bytes_valid_in;
                    
                    if is_last_in = '0' then
                        len_C <= len_C + 128;
                    else
                        if bytes_valid_in = "0000" then
                            len_C <= len_C + 128;
                        else
                            len_C <= len_C + (unsigned(bytes_valid_in) * 8);
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    data_out <= camellia_result xor saved_data;
    data_out_valid <= camellia_valid;
    is_last_out <= saved_last;
    bytes_valid_out <= saved_bytes;
    len_out <= std_logic_vector(len_C);

end architecture rtl;