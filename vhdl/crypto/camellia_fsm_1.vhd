library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;
use work.gcm_pkg.all;

entity camellia_core is
    Port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        data_in   : in  std_logic_vector(127 downto 0);
        key       : in  std_logic_vector(127 downto 0);
        valid_in  : in  std_logic;
        ready     : out std_logic; -- [MODIFIED] Added ready signal
        data_out  : out std_logic_vector(127 downto 0);
        valid_out : out std_logic
    );
end camellia_core;

architecture rtl of camellia_core is

    type state_t is (IDLE,
                     RND_1,  RND_2,  RND_3,  RND_4,  RND_5,  RND_6,
                     FL_1,
                     RND_7,  RND_8,  RND_9,  RND_10, RND_11, RND_12,
                     FL_2,
                     RND_13, RND_14, RND_15, RND_16, RND_17, RND_18);
    
    signal state : state_t := IDLE;
    signal L_reg, R_reg : camellia_w64_t := (others => '0');

    signal L_next, R_next : camellia_w64_t := (others => '0');
    signal current_k : camellia_w64_t := (others => '0');
    signal FL_L_out, FL_R_out : camellia_w64_t := (others => '0');
    
    signal current_kl1, current_kl2 : camellia_w64_t := (others => '0');

    -- REGISTERED key storage
    signal kw1, kw2, kw3, kw4 : camellia_w64_t;
    signal k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18 : camellia_w64_t;
    signal kl1, kl2, kl3, kl4 : camellia_w64_t;

begin

    -- Ready flag
    ready <= '1' when state = IDLE else '0';

    -------------------------------------------------------------------
    -- 1. SINGLE ROUND COMBINATORIAL COMPUTATION
    -------------------------------------------------------------------
    
    L_next <= R_reg xor camellia_f(L_reg, current_k);
    R_next <= L_reg;

    -------------------------------------------------------------------
    -- 2. FL/FLINV COMBINATORIAL COMPUTATION
    -------------------------------------------------------------------
    FL_L_out <= camellia_fl(L_reg, current_kl1);
    FL_R_out <= camellia_fl_inv(R_reg, current_kl2);

    -------------------------------------------------------------------
    -- 3. COMBINATORIAL KEY MULTIPLEXING
    -------------------------------------------------------------------
    process(state, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, kl1, kl2, kl3, kl4)
    begin
        current_k   <= (others => '0');
        current_kl1 <= (others => '0');
        current_kl2 <= (others => '0');

        case state is
            when RND_1  => current_k <= k1;
            when RND_2  => current_k <= k2;
            when RND_3  => current_k <= k3;
            when RND_4  => current_k <= k4;
            when RND_5  => current_k <= k5;
            when RND_6  => current_k <= k6;
            when FL_1   => current_kl1 <= kl1; current_kl2 <= kl2;
            when RND_7  => current_k <= k7;
            when RND_8  => current_k <= k8;
            when RND_9  => current_k <= k9;
            when RND_10 => current_k <= k10;
            when RND_11 => current_k <= k11;
            when RND_12 => current_k <= k12;
            when FL_2   => current_kl1 <= kl3; current_kl2 <= kl4;
            when RND_13 => current_k <= k13;
            when RND_14 => current_k <= k14;
            when RND_15 => current_k <= k15;
            when RND_16 => current_k <= k16;
            when RND_17 => current_k <= k17;
            when RND_18 => current_k <= k18;
            when others => null;
        end case;
    end process;

    -------------------------------------------------------------------
    -- 4. SEQUENTIAL CONTROLLER
    -------------------------------------------------------------------
    process(clk)
        variable K_w128, KA_w128 : camellia_w128_t;
        variable temp_data_w128  : camellia_w128_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                valid_out  <= '0';
                L_reg      <= (others => '0');
                R_reg      <= (others => '0');
                data_out   <= (others => '0');
            else
                valid_out <= '0';

                case state is
                    when IDLE =>
                        if valid_in = '1' then
                            K_w128  := camellia_w128_t(key);
                            KA_w128 := camellia_key_sched(K_w128);

                            kw1 <= K_w128(0 to 63);
                            kw2 <= K_w128(64 to 127);
                            kw3 <= rotate_left128(KA_w128, 111)(0 to 63);
                            kw4 <= rotate_left128(KA_w128, 111)(64 to 127);

                            k1  <= KA_w128(0 to 63);
                            k2  <= KA_w128(64 to 127);
                            k3  <= rotate_left128(K_w128, 15)(0 to 63);
                            k4  <= rotate_left128(K_w128, 15)(64 to 127);
                            k5  <= rotate_left128(KA_w128, 15)(0 to 63);
                            k6  <= rotate_left128(KA_w128, 15)(64 to 127);
                            k7  <= rotate_left128(K_w128, 45)(0 to 63);
                            k8  <= rotate_left128(K_w128, 45)(64 to 127);
                            k9  <= rotate_left128(KA_w128, 45)(0 to 63);
                            k10 <= rotate_left128(K_w128, 60)(64 to 127);
                            k11 <= rotate_left128(KA_w128, 60)(0 to 63);
                            k12 <= rotate_left128(KA_w128, 60)(64 to 127);
                            k13 <= rotate_left128(K_w128, 94)(0 to 63);
                            k14 <= rotate_left128(K_w128, 94)(64 to 127);
                            k15 <= rotate_left128(KA_w128, 94)(0 to 63);
                            k16 <= rotate_left128(KA_w128, 94)(64 to 127);
                            k17 <= rotate_left128(K_w128, 111)(0 to 63);
                            k18 <= rotate_left128(K_w128, 111)(64 to 127);

                            kl1 <= rotate_left128(KA_w128, 30)(0 to 63);
                            kl2 <= rotate_left128(KA_w128, 30)(64 to 127);
                            kl3 <= rotate_left128(K_w128, 77)(0 to 63);
                            kl4 <= rotate_left128(K_w128, 77)(64 to 127);
                            
                            -- Latch data using the variables immediately
                            temp_data_w128 := camellia_w128_t(data_in);
                            L_reg <= temp_data_w128(0 to 63) xor K_w128(0 to 63);
                            R_reg <= temp_data_w128(64 to 127) xor K_w128(64 to 127);
                            
                            state <= RND_1;
                        end if;

                    when RND_1 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_2;

                    when RND_2 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_3;

                    when RND_3 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_4;

                    when RND_4 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_5;

                    when RND_5 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_6;

                    when RND_6 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= FL_1;

                    when FL_1 =>
                        L_reg <= FL_L_out;
                        R_reg <= FL_R_out;
                        state <= RND_7;

                    when RND_7 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_8;

                    when RND_8 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_9;

                    when RND_9 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_10;

                    when RND_10 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_11;

                    when RND_11 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_12;

                    when RND_12 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= FL_2;

                    when FL_2 =>
                        L_reg <= FL_L_out;
                        R_reg <= FL_R_out;
                        state <= RND_13;

                    when RND_13 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_14;

                    when RND_14 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_15;

                    when RND_15 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_16;

                    when RND_16 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_17;

                    when RND_17 =>
                        L_reg <= L_next;
                        R_reg <= R_next;
                        state <= RND_18;

                    when RND_18 =>
                        data_out  <= std_logic_vector((L_reg xor kw3) & (L_next xor kw4));
                        valid_out <= '1';
                        state     <= IDLE;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;
end architecture rtl;