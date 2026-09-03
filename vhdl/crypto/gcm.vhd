library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gcm is
    Port (
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;
        ready: out std_logic;
        key: in std_logic_vector(255 downto 0);
        key_len: in std_logic_vector(1 downto 0);
        IV: in std_logic_vector(95 downto 0);
        data_state: in std_ulogic_vector(1 downto 0);
        data_in: in std_logic_vector(127 downto 0);
        valid_in: in std_logic;
        last_in: in std_logic;
        C_data: out std_logic_vector(127 downto 0);
        C_valid: out std_logic;
        C_last: out std_logic;
        T: out std_logic_vector(127 downto 0);
        T_valid: out std_logic
    );
end gcm;

architecture rtl of gcm is
    
    signal H: std_logic_vector(127 downto 0);
    signal H_valid: std_logic;
    signal J0: std_logic_vector(127 downto 0);
    signal J0_incr: std_logic_vector(127 downto 0);

    signal A_data, P_data : std_logic_vector(127 downto 0);
    signal A_valid, P_valid : std_logic;
    signal A_last, P_last : std_logic;

    signal hash_data_in: std_logic_vector(127 downto 0);
    signal hash_data_valid: std_logic;
    signal hash_is_last: std_logic;

    signal hash_out: std_logic_vector(127 downto 0);
    signal hash_valid, hash_last: std_logic;

    signal A_done, C_done: std_logic;
    signal len_C, len_A: std_logic_vector(63 downto 0);
    signal len_A_tmp: unsigned(63 downto 0);
    signal len_C_tmp: unsigned(63 downto 0);

    signal A_complete, C_complete: std_logic_vector(127 downto 0);
    signal final_out: std_logic_vector(127 downto 0);
    signal final_valid, final_last: std_logic;

    signal len_valid: std_logic;

    signal gctr_data_in, gctr_data_out: std_logic_vector(127 downto 0);
    signal gctr_valid, gctr_valid_out: std_logic;
    signal gctr_is_last, gctr_is_last_out: std_logic;
    signal gctr_len: std_logic_vector(63 downto 0);
    signal gctr_ready: std_logic;
    signal ICB: std_logic_vector(127 downto 0);

    signal hash_busy: std_logic := '0';
    signal A_fire : std_logic;
    signal P_fire : std_logic;

    type state_type is (IDLE, START_GCTR_H, GCTR_H, HASH_A, WAIT_GHASH_A, START_GCTR_C, GCTR_C, WAIT_GHASH_C, SEND_LEN, HASH_LEN, START_GCTR_T, GCTR_T);
    signal current: state_type;

    signal generate_h: std_logic;
    signal gctr_start: std_logic;


begin
    J0 <= IV & x"00000001";
    J0_incr <= IV & x"00000002";

    A_complete <= A_data;
    C_complete <= C_data;

    A_data <= data_in  when data_state = "01" else (others => '0');
    A_valid <= valid_in when data_state = "01" else '0';
    A_last <= last_in  when data_state = "01" else '0';

    P_data <= data_in  when data_state = "10" else (others => '0');
    P_valid <= valid_in when data_state = "10" else '0';
    P_last <= last_in  when data_state = "10" else '0';

    A_fire <= '1' when (current = HASH_A and A_valid = '1' and hash_busy = '0') else '0';
    P_fire <= '1' when (current = GCTR_C and P_valid = '1' and hash_busy = '0' and gctr_ready = '1' and gctr_valid_out = '0') else '0';

    ready <= '1' when (current = HASH_A and hash_busy = '0' and data_state = "01") else
            '1' when (current = GCTR_C and hash_busy = '0' and gctr_ready = '1' and gctr_valid_out = '0' and data_state = "10") else
            '0';

    gctr_data_in <= (others => '0') when (current = GCTR_H or current = START_GCTR_H) else P_data when current = GCTR_C else hash_out;
    gctr_valid <= generate_h when (current = GCTR_H or current = START_GCTR_H) else
                P_fire when current = GCTR_C else
                final_valid;

    gctr_is_last <= '1' when (current = GCTR_H or current = START_GCTR_H) else P_last when current = GCTR_C else '1';

    ICB <= (others => '0') when (current = GCTR_H or current = START_GCTR_H or current = IDLE) else
            J0_incr         when (current = GCTR_C or current = START_GCTR_C or current = HASH_A) else
            J0; 

    C_data <= gctr_data_out when current = GCTR_C else (others => '0');
    C_valid <= gctr_valid_out when current = GCTR_C else '0';
    C_last <= gctr_is_last_out when current = GCTR_C else '0';

    T <= gctr_data_out when current = GCTR_T else (others => '0');
    T_valid <= gctr_valid_out when current = GCTR_T else '0';

    gctr: entity work.gctr
        port map (
            clk => clk,
            rst => rst,
            ICB => ICB,
            key => key,
            key_len => key_len,
            start => gctr_start,
            data_in => gctr_data_in,
            data_in_valid => gctr_valid,
            is_last_in => gctr_is_last,
            ready => gctr_ready,
            data_out => gctr_data_out,
            data_out_valid => gctr_valid_out,
            is_last_out => gctr_is_last_out,
            len_out => gctr_len
        );


    hash_data_in <= A_complete when current = HASH_A else C_complete when current = GCTR_C else len_A & len_C;
    hash_data_valid <= A_fire when current = HASH_A else gctr_valid_out when current = GCTR_C else len_valid;
    hash_is_last <= A_last when current = HASH_A else gctr_is_last_out when current = GCTR_C else '1';

    hash: entity work.ghash_core
        port map (
            clk => clk,
            rst => rst,
            H => H,
            start_block => start,
            data_in => hash_data_in,
            data_in_valid => hash_data_valid,
            is_last_in => hash_is_last,
            data_out => hash_out,
            data_out_valid => hash_valid
        );

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current <= IDLE;
                len_A_tmp <= (others => '0');
                len_C_tmp <= (others => '0');
                final_valid <= '0';
                len_valid <= '0';
                gctr_start <= '0';
                hash_busy <= '0';
                H_valid <= '0';
            elsif start = '1' then
                current <= START_GCTR_H;
                len_A_tmp <= (others => '0');
                len_C_tmp <= (others => '0');
                final_valid <= '0';
                len_valid <= '0';
                generate_h <= '0';
                gctr_start <= '1';
                hash_busy <= '0';
                H_valid <= '0';
            else
                final_valid <= '0';
                len_valid <= '0';
                generate_h <= '0'; 
                gctr_start <= '0';
                H_valid <= '0';

                if hash_valid = '1' then
                    hash_busy <= '0';
                elsif hash_data_valid = '1' then
                    hash_busy <= '1';
                end if;

                case current is
                    when IDLE =>
                        null;
                    when START_GCTR_H =>
                        current <= GCTR_H;
                        generate_h <= '1';
                    when GCTR_H =>
                        if gctr_valid_out = '1' then
                            H <= gctr_data_out;
                            H_valid <= '1';
                            current <= HASH_A;
                        end if;
                    when HASH_A =>
                        if data_state = "10" then
                            current <= START_GCTR_C;
                            gctr_start <= '1';
                        elsif A_fire = '1' then
                            if A_last = '1' then
                                len_A_tmp <= len_A_tmp + 128;
                                current <= WAIT_GHASH_A;
                            else
                                len_A_tmp <= len_A_tmp + 128;
                            end if;
                        elsif data_state = "00" then
                            current <= SEND_LEN;
                            len_valid <= '1';
                        end if;
                    when WAIT_GHASH_A =>
                        if data_state = "10" then
                            current <= START_GCTR_C;
                            gctr_start <= '1';
                        elsif data_state = "00" then
                            current <= WAIT_GHASH_C;
                        end if;
                    when START_GCTR_C =>
                        current <= GCTR_C;
                    when GCTR_C =>
                        if P_fire = '1' then
                            len_C_tmp <= len_C_tmp + 128;
                        end if;

                        if gctr_valid_out = '1' then
                            if gctr_is_last_out = '1' then
                                current <= WAIT_GHASH_C;
                            end if;
                        end if;
                    when WAIT_GHASH_C =>
                        if hash_valid = '1' then
                            current <= SEND_LEN;
                            len_valid <= '1';
                        end if;
                    when SEND_LEN =>
                        current <= HASH_LEN;
                    when HASH_LEN =>
                        if hash_valid = '1' then
                            current <= START_GCTR_T;
                            gctr_start <= '1';
                        end if;
                    when START_GCTR_T =>
                        current <= GCTR_T;
                        final_valid <= '1';
                    when GCTR_T =>
                        null;
                end case;

            end if; 
        end if;
    end process;

    len_A <= std_logic_vector(len_A_tmp);
    len_C <= std_logic_vector(len_C_tmp);
end architecture rtl;
