entity mob_core is
    port(
        clk: in std_logic;
        rst: in std_logic;
        
        -- Input
        X: in std_logic_vector(127 downto 0);
        Y: in std_logic_vector(127 downto 0);
        start: in std_logic;
        
        -- Output
        Z: out std_logic_vector(127 downto 0)
        done: out std_logic -- Indicate if the mob is finished
    );  
end mob_core;

architecture rtl of mob_core is
    signal V: std_logic_vector(127 downto 0);
    signal counter: integer range 0 to 128;

    constant R: std_logic_vector(127 downto 0) := x"E1000000000000000000000000000000";

begin
    process(clk)
    begin
        if rising_edge(clk) then
             if rst = '1' then
                counter <= '0';
                done <= '0';

            elsif start = '1' then
                Z <= (others => '0'); -- Z0
                V <= Y; -- V0
                counter <= '0';
                done <= '0';
            
            -- For loop of the algo
            elsif counter < 128 then
                if X(127 - counter) = '1' then -- x_i = 1
                    Z <= Z xor V;
                end if;
                V <= '0' & V(127 downto 1);
                if V(0) = '1' then -- LSB(V) = 1
                    V <= V xor R;
                end if;
            elsif counter = 128 then
                done <= '1';
            end if;
        end if;
    end process;

end architecture rtl;