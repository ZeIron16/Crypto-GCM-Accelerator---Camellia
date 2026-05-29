library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_split is
    port(
        aclk: in  std_ulogic;
        aresetn: in  std_ulogic;
        
        data_in: in  std_ulogic_vector(127 downto 0);
        data_in_valid: in  std_ulogic;
        data_in_ready: out std_ulogic;

        data_out: out std_ulogic_vector(31 downto 0);
        data_out_valid: out std_ulogic;
        data_out_ready: in  std_ulogic
    );
end entity dma_split;

architecture rtl of dma_split is  
    type state_t is (IDLE, SENDING);
    signal state: state_t;
    signal buffer_128: std_ulogic_vector(127 downto 0);
    signal word_count: unsigned(1 downto 0);
begin

    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= IDLE;
                buffer_128 <= (others => '0');
                word_count <= "00";
            else
                case state is
                    when IDLE =>
                        if data_in_valid = '1' then
                            buffer_128 <= data_in;
                            word_count <= "11";
                            state      <= SENDING;
                        end if;

                    when SENDING =>
                        if data_out_ready = '1' then
                            buffer_128 <= x"00000000" & buffer_128(127 downto 32);
                            
                            if word_count = "00" then
                                if data_in_valid = '1' then
                                    buffer_128 <= data_in;
                                    word_count <= "11";
                                else
                                    state <= IDLE;
                                end if;
                            else
                                word_count <= word_count - 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    data_in_ready <= '1' when (state = IDLE) or (state = SENDING and data_out_ready = '1' and word_count = "00") else '0';
    
    data_out_valid <= '1' when state = SENDING else '0';
    
    data_out <= buffer_128(31 downto 0);

end architecture rtl;