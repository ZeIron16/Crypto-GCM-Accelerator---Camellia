entity ghash_core is
    port(
        clk: in std_logic;
        rst: in std_logic;
        
        -- Prerequisite
        H: in std_logic_vector(127 downto 0);
        start_block: in std_logic; -- Usefull to reset the Y_tmp signal

        -- Input (same kind of flow as in gstr)
        data_in: in std_logic_vector(127 downto 0);
        data_in_valid: in std_logic;
        is_last_in: in std_logic;
        
        -- Output
        data_out: out std_logic_vector(127 downto 0);
        data_out_valid: out std_logic
    );
end ghash_core;

architecture rtl of ghash_core is
    signal mob_start, mob_done, was_last: std_logic;
    signal mob_X: std_logic_vector(127 downto 0);
    signal mob_out: std_logic_vector(127 downto 0);

    signal Y_tmp: std_logic_vector(127 downto 0);

    type state_type is (OK, WAIT_MOB, DONE);
    signal state: state_type;

begin   
    multiplier : entity work.mob
        port map (
            clk   => clk,
            rst   => rst,
            start => mob_start,
            X     => mob_X,
            Y     => H_key,
            Z_out => mob_out,
            done => mob_done
        );

    mob_X <= Y_tmp xor data_in;

    process(clk)
    begin
        if rising_edge(clk) then

            mob_start <= '0';       -- |
            data_out_valid <= '0';  -- | Init default values

             if rst = '1' then
                data_out <= (others => '0');
                ready <= '0';
                last_block_flag <= '0';

            else
                case state is
                    when OK =>
                        if start_block = '1' then
                            Y_tmp <= (others => '0');
                        end if;
                        if data_in_valid = '1' then
                            mob_start <= '1';
                            was_last <= is_last_in;
                            state <= WAIT_MOB;
                        end if;
                    
                    when WAIT_MOB =>
                        if mob_done = '1' then
                            Y_tmp <= mob_out;
                            if was_last = '1' then
                                state <= DONE; -- We reached Y_m
                            else
                                state <= OK; -- We wait for another block (not at Y_m for now)
                            end if;
                        end if;
                    when DONE =>
                            data_out <= Y_tmp;
                            data_out_valid <= '1';
                            state <= OK; -- We can now start a new hash "sequence"
                end case;
            end if;
        end if;
    end process;

end architecture rtl;