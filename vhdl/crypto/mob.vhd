library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mob is
    port(
        clk: in std_logic;
        rst: in std_logic;
        
        -- Input
        X: in std_logic_vector(127 downto 0);
        Y: in std_logic_vector(127 downto 0);
        start: in std_logic;
        
        -- Output
        Z: out std_logic_vector(127 downto 0);
        done: out std_logic
    );
end mob;

architecture rtl of mob is
    signal V   : std_logic_vector(127 downto 0);
    signal Z_r : std_logic_vector(127 downto 0);
    signal counter : integer range 0 to 128;
    constant R : std_logic_vector(127 downto 0) :=
        x"E1000000000000000000000000000000";
begin
    Z <= Z_r;

    process(clk)
        variable V_v : std_logic_vector(127 downto 0);
        variable Z_v : std_logic_vector(127 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                counter <= 0;
                done    <= '0';
                Z_r     <= (others => '0');
                V       <= (others => '0');

            elsif start = '1' then
                Z_r     <= (others => '0');
                V       <= Y;
                counter <= 0;
                done    <= '0';

            elsif counter < 128 then
                V_v := V;
                Z_v := Z_r;

                for i in 0 to 3 loop
                    
                    if X(127 - (counter + i)) = '1' then
                        Z_v := Z_v xor V_v;
                    end if;
                    
                    if V_v(0) = '1' then
                        V_v := ('0' & V_v(127 downto 1)) xor R;
                    else
                        V_v := '0' & V_v(127 downto 1);
                    end if;
                    
                end loop;

                Z_r <= Z_v;
                V   <= V_v;
                counter <= counter + 4;

            elsif counter = 128 then
                done <= '1';
            end if;
        end if;
    end process;
end architecture rtl;