library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gcm_pkg.all;

entity camellia_key_scheduler is
    Port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;
        key_in      : in  std_logic_vector(127 downto 0);
        
        -- Outputs only the generated KA parameter
        KA_out      : out camellia_w128_t;
        keys_ready  : out std_logic
    );
end camellia_key_scheduler;

architecture rtl of camellia_key_scheduler is

    type sched_state_t is (IDLE, CALC_SIGMA1, CALC_SIGMA2, XOR_KL, CALC_SIGMA3, CALC_SIGMA4, READY);
    signal state : sched_state_t;

    signal t0_reg, t1_reg : camellia_w64_t;
    signal K_reg : camellia_w128_t;

    constant sigma1: camellia_w64_t := x"A09E667F3BCC908B";
    constant sigma2: camellia_w64_t := x"B67AE8584CAA73B2";
    constant sigma3: camellia_w64_t := x"C6EF372FE94F82BE";
    constant sigma4: camellia_w64_t := x"54FF53A5F1D36F1C";

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                keys_ready <= '0';
                t0_reg     <= (others => '0');
                t1_reg     <= (others => '0');
                K_reg      <= (others => '0');
                KA_out     <= (others => '0');
            else
                case state is
                    when IDLE =>
                        keys_ready <= '0';
                        if start = '1' then
                            K_reg  <= camellia_w128_t(key_in);
                            t0_reg <= camellia_w64_t(key_in(127 downto 64)); 
                            t1_reg <= camellia_w64_t(key_in(63 downto 0)); 
                            state  <= CALC_SIGMA1;
                        end if;

                    when CALC_SIGMA1 =>
                        t1_reg <= t1_reg xor camellia_f(t0_reg, sigma1);
                        state  <= CALC_SIGMA2;

                    when CALC_SIGMA2 =>
                        t0_reg <= t0_reg xor camellia_f(t1_reg, sigma2);
                        state  <= XOR_KL;

                    when XOR_KL =>
                        t0_reg <= t0_reg xor K_reg(0 to 63);
                        t1_reg <= t1_reg xor K_reg(64 to 127);
                        state  <= CALC_SIGMA3;

                    when CALC_SIGMA3 =>
                        t1_reg <= t1_reg xor camellia_f(t0_reg, sigma3);
                        state  <= CALC_SIGMA4;

                    when CALC_SIGMA4 =>
                        t0_reg <= t0_reg xor camellia_f(t1_reg, sigma4);
                        state  <= READY;

                    when READY =>
                        KA_out     <= t0_reg & t1_reg;
                        keys_ready <= '1';
                        -- Wait for handshake from core to clear
                        if start = '0' then 
                            state <= IDLE;
                        end if;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;