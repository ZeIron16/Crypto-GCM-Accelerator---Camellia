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
        data_out  : out std_logic_vector(127 downto 0);
        valid_out : out std_logic
    );
end camellia_core;

architecture rtl of camellia_core is

    type state_t is (IDLE, CYCLE_1, CYCLE_2, CYCLE_3, CYCLE_4, CYCLE_5, CYCLE_6);
    signal state : state_t;

    signal L_reg, R_reg : camellia_w64_t;

    signal L1, R1 : camellia_w64_t;
    signal L2, R2 : camellia_w64_t;
    signal L3, R3 : camellia_w64_t;
    signal FL_L_out, FL_R_out : camellia_w64_t;

    signal current_k1, current_k2, current_k3 : camellia_w64_t;
    signal current_kl1, current_kl2           : camellia_w64_t;

    -- REGISTERED key storage to keep key schedule off the critical path
    signal kw1, kw2, kw3, kw4 : camellia_w64_t;
    signal k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18 : camellia_w64_t;
    signal kl1, kl2, kl3, kl4 : camellia_w64_t;
    signal key_ready           : std_logic := '0';

begin

    -------------------------------------------------------------------
    -- 1. ROUNDS COMBINATORIAL COMPUTATIONS
    -------------------------------------------------------------------
    -- 1st round in current cycle
    L1 <= R_reg xor camellia_f(L_reg, current_k1);
    R1 <= L_reg;

    -- 2nd round in current cycle
    L2 <= R1 xor camellia_f(L1, current_k2);
    R2 <= L1;

    -- 3rd round in current cycle
    L3 <= R2 xor camellia_f(L2, current_k3);
    R3 <= L2;

    -- Combinatorial FL layers
    FL_L_out <= camellia_fl(L3, current_kl1);
    FL_R_out <= camellia_fl_inv(R3, current_kl2);

    -------------------------------------------------------------------
    -- 2. COMBINATORIAL KEY MULTIPLEXING
    -------------------------------------------------------------------
    process(state, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, kl1, kl2, kl3, kl4)
    begin
        current_k1  <= (others => '0');
        current_k2  <= (others => '0');
        current_k3  <= (others => '0');
        current_kl1 <= (others => '0');
        current_kl2 <= (others => '0');

        case state is
            when CYCLE_1 => 
                current_k1 <= k1;  current_k2 <= k2;  current_k3 <= k3;
            when CYCLE_2 => 
                current_k1 <= k4;  current_k2 <= k5;  current_k3 <= k6;
                current_kl1 <= kl1; current_kl2 <= kl2;
            when CYCLE_3 => 
                current_k1 <= k7;  current_k2 <= k8;  current_k3 <= k9;
            when CYCLE_4 => 
                current_k1 <= k10; current_k2 <= k11; current_k3 <= k12;
                current_kl1 <= kl3; current_kl2 <= kl4;
            when CYCLE_5 => 
                current_k1 <= k13; current_k2 <= k14; current_k3 <= k15;
            when CYCLE_6 => 
                current_k1 <= k16; current_k2 <= k17; current_k3 <= k18;
            when others => null;
        end case;
    end process;

    -------------------------------------------------------------------
    -- 3. SEQUENTIAL CONTROLLER (KEY EXPANSION & DATA STATE MACHINE)
    -------------------------------------------------------------------
    process(clk)
        variable K_w128, KA_w128 : camellia_w128_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                valid_out  <= '0';
                key_ready  <= '0';
                L_reg      <= (others => '0');
                R_reg      <= (others => '0');
                data_out   <= (others => '0');
            else
                valid_out <= '0';

                -- Key Schedule Expansion Logic (Runs once upon startup/reset)
                if key_ready = '0' then
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
                    
                    key_ready <= '1';
                end if;

                case state is
                    when IDLE =>
                        if valid_in = '1' and key_ready = '1' then
                            L_reg <= camellia_w128_t(data_in)(0 to 63) xor kw1;
                            R_reg <= camellia_w128_t(data_in)(64 to 127) xor kw2;
                            state <= CYCLE_1;
                        end if;

                    when CYCLE_1 =>
                        -- Store the output after rounds 1-3
                        L_reg <= L3; R_reg <= R3;
                        state <= CYCLE_2;

                    when CYCLE_2 =>
                        -- Store the output of the first FL layers (after rounds 1-6)
                        L_reg <= FL_L_out; R_reg <= FL_R_out;
                        state <= CYCLE_3;

                    when CYCLE_3 =>
                        -- Store the output after rounds 7-9
                        L_reg <= L3; R_reg <= R3;
                        state <= CYCLE_4;

                    when CYCLE_4 =>
                        -- Store the output after the second FL layers (after rounds 7-12)
                        L_reg <= FL_L_out; R_reg <= FL_R_out;
                        state <= CYCLE_5;

                    when CYCLE_5 =>
                        -- Store the output after rounds 13-15
                        L_reg <= L3; R_reg <= R3;
                        state <= CYCLE_6;

                    when CYCLE_6 =>
                        -- Output the final ciphertext (after rounds 13-18)
                        data_out <= std_logic_vector((R3 xor kw3) & (L3 xor kw4));
                        valid_out <= '1';
                        state     <= IDLE;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;