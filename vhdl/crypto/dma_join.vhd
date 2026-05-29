library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_join is
    port(
        aclk           : in  std_ulogic;
        aresetn        : in  std_ulogic;
        
        -- Input interface from 32-bit FIFO
        data_in        : in  std_ulogic_vector(31 downto 0);
        data_in_valid  : in  std_ulogic;
        data_in_ready  : out std_ulogic;

        -- Output interface to Crypto block (128-bit)
        data_out       : out std_ulogic_vector(127 downto 0);
        data_out_valid : out std_ulogic;
        data_out_ready : in  std_ulogic
    );
end entity dma_join;

architecture rtl of dma_join is  
    signal word_count  : unsigned(1 downto 0);
    signal buffer_128  : std_ulogic_vector(127 downto 0);
    signal out_val_reg : std_ulogic;
begin

    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                word_count  <= "00";
                buffer_128  <= (others => '0');
                out_val_reg <= '0';
            else
                -- 1. Output Side Handshake
                -- If downstream (Crypto) accepts the data, drop the valid flag
                if out_val_reg = '1' and data_out_ready = '1' then
                    out_val_reg <= '0';
                end if;

                -- 2. Input Side Handshake
                -- Accept new data if buffer is empty, or freeing up this cycle
                if (out_val_reg = '0' or data_out_ready = '1') then
                    
                    if data_in_valid = '1' then
                        -- AXI memory is little-endian:
                        -- Push new words to MSB, shift old ones to LSB.
                        -- Cycle 1 (addr 0x00) ends up at (31 downto 0) by cycle 4.
                        buffer_128 <= data_in & buffer_128(127 downto 32);
                        
                        if word_count = 3 then
                            word_count  <= "00";
                            out_val_reg <= '1'; -- Full 128-bit block is ready
                        else
                            word_count  <= word_count + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    data_in_ready  <= '1' when (out_val_reg = '0' or data_out_ready = '1') else '0';
    data_out_valid <= out_val_reg;
    data_out       <= buffer_128;

end architecture rtl;