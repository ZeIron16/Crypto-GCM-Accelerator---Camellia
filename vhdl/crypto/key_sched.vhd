library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gcm_pkg.all;

entity camellia_key_scheduler is
    Port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;
        
        key_in      : in  std_logic_vector(255 downto 0);
        key_len     : in  std_logic_vector(1 downto 0);
        
        -- Outputs the generated KA and KB parameters depending on the key length
        KA_out      : out camellia_w128_t;
        KB_out      : out camellia_w128_t;
        keys_ready  : out std_logic
    );
end camellia_key_scheduler;

architecture rtl of camellia_key_scheduler is

    type sched_state_t is (IDLE, CALC_SIGMA1, CALC_SIGMA2, XOR_KL, CALC_SIGMA3, CALC_SIGMA4, 
                           CHECK_LEN, XOR_KR, CALC_SIGMA5, CALC_SIGMA6, READY);
    signal state : sched_state_t;

    signal t0_reg, t1_reg : camellia_w64_t;
    signal K_L_reg, K_R_reg : camellia_w128_t;
    signal KA_reg : camellia_w128_t;
    signal key_len_reg : std_logic_vector(1 downto 0);
    
    constant sigma1: camellia_w64_t := x"A09E667F3BCC908B";
    constant sigma2: camellia_w64_t := x"B67AE8584CAA73B2";
    constant sigma3: camellia_w64_t := x"C6EF372FE94F82BE";
    constant sigma4: camellia_w64_t := x"54FF53A5F1D36F1C";
    constant sigma5: camellia_w64_t := x"10E527FADE682D1D";
    constant sigma6: camellia_w64_t := x"B05688C2B3E6C1FD";

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                keys_ready <= '0';
                t0_reg     <= (others => '0');
                t1_reg     <= (others => '0');
                K_L_reg    <= (others => '0');
                K_R_reg    <= (others => '0');
                KA_reg     <= (others => '0');
                KA_out     <= (others => '0');
                KB_out     <= (others => '0');
                key_len_reg <= "00";
            else
                case state is
                    when IDLE =>
                        keys_ready <= '0';
                        if start = '1' then
                            key_len_reg <= key_len;
                            K_L_reg <= camellia_w128_t(key_in(255 downto 128));
                            
                            if key_len = "00" then -- 128-bit
                                K_R_reg <= (others => '0');
                                t0_reg <= camellia_w64_t(key_in(255 downto 192)); 
                                t1_reg <= camellia_w64_t(key_in(191 downto 128)); 
                            elsif key_len = "01" then -- 192-bit
                                K_R_reg <= camellia_w128_t(key_in(127 downto 64) & not key_in(127 downto 64));
                                t0_reg <= camellia_w64_t(key_in(255 downto 192)) xor camellia_w64_t(key_in(127 downto 64)); 
                                t1_reg <= camellia_w64_t(key_in(191 downto 128)) xor camellia_w64_t(not key_in(127 downto 64)); 
                            else -- 256-bit
                                K_R_reg <= camellia_w128_t(key_in(127 downto 0));
                                t0_reg <= camellia_w64_t(key_in(255 downto 192)) xor camellia_w64_t(key_in(127 downto 64)); 
                                t1_reg <= camellia_w64_t(key_in(191 downto 128)) xor camellia_w64_t(key_in(63 downto 0)); 
                            end if;
                            
                            state  <= CALC_SIGMA1;
                        end if;

                    when CALC_SIGMA1 =>
                        t1_reg <= t1_reg xor camellia_f(t0_reg, sigma1);
                        state  <= CALC_SIGMA2;

                    when CALC_SIGMA2 =>
                        t0_reg <= t0_reg xor camellia_f(t1_reg, sigma2);
                        state  <= XOR_KL;

                    when XOR_KL =>
                        t0_reg <= t0_reg xor K_L_reg(0 to 63);
                        t1_reg <= t1_reg xor K_L_reg(64 to 127);
                        state  <= CALC_SIGMA3;

                    when CALC_SIGMA3 =>
                        t1_reg <= t1_reg xor camellia_f(t0_reg, sigma3);
                        state  <= CALC_SIGMA4;

                    when CALC_SIGMA4 =>
                        t0_reg <= t0_reg xor camellia_f(t1_reg, sigma4);
                        state  <= CHECK_LEN;

                    when CHECK_LEN =>
                        KA_reg <= t0_reg & t1_reg;
                        if key_len_reg = "00" then
                            state <= READY;
                        else
                            state <= XOR_KR;
                        end if;
                        
                    when XOR_KR =>
                        t0_reg <= t0_reg xor K_R_reg(0 to 63);
                        t1_reg <= t1_reg xor K_R_reg(64 to 127);
                        state  <= CALC_SIGMA5;
                        
                    when CALC_SIGMA5 =>
                        t1_reg <= t1_reg xor camellia_f(t0_reg, sigma5);
                        state  <= CALC_SIGMA6;
                        
                    when CALC_SIGMA6 =>
                        t0_reg <= t0_reg xor camellia_f(t1_reg, sigma6);
                        state  <= READY;

                    when READY =>
                        KA_out <= KA_reg;
                        if key_len_reg /= "00" then
                            KB_out <= t0_reg & t1_reg;
                        else
                            KB_out <= (others => '0');
                        end if;
                        
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