library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ghash_core is
    port(
        clk : in std_logic;
        rst : in std_logic;

        -- Prerequisite
        H : in std_logic_vector(127 downto 0);
        start_block : in std_logic;

        -- Input
        data_in : in std_logic_vector(127 downto 0);
        data_in_valid : in std_logic;
        is_last_in : in std_logic;

        -- Output
        data_out : out std_logic_vector(127 downto 0);
        data_out_valid : out std_logic
    );
end ghash_core;

architecture rtl of ghash_core is

    signal mob_start : std_logic;
    signal mob_done  : std_logic;

    signal mob_X   : std_logic_vector(127 downto 0);
    signal mob_out : std_logic_vector(127 downto 0);

    signal Y_tmp : std_logic_vector(127 downto 0);

    type state_type is (OK, WAIT_MOB_START, WAIT_MOB_DONE, DONE);
    signal state : state_type;

begin

    multiplier : entity work.mob
        port map (
            clk   => clk,
            rst   => rst,
            start => mob_start,
            X     => mob_X,
            Y     => H,
            Z     => mob_out,
            done  => mob_done
        );

    process(clk)
    begin
        if rising_edge(clk) then

            -- Default values
            mob_start <= '0';
            data_out_valid <= '0';

            if rst = '1' then
                state <= OK;
                Y_tmp <= (others => '0');
                mob_X <= (others => '0');
                data_out <= (others => '0');

            else
                if start_block = '1' then
                    state <= OK;
                    Y_tmp <= (others => '0');
                end if;

                case state is

                    when OK =>
                        if data_in_valid = '1' then
                            mob_X <= Y_tmp xor data_in;
                            mob_start <= '1';
                            
                            state <= WAIT_MOB_START;
                        end if;

                    when WAIT_MOB_START =>
                        if mob_done = '0' then
                            state <= WAIT_MOB_DONE;
                        end if;

                    when WAIT_MOB_DONE =>
                        -- Now we can safely wait for the math to finish
                        if mob_done = '1' then
                            Y_tmp <= mob_out;
                            state <= DONE;
                        end if;

                    when DONE =>
                        data_out <= Y_tmp;
                        data_out_valid <= '1';
                        state <= OK;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;