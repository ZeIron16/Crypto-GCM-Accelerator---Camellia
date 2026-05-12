entity gcm is
    Port (
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;

        -- Input const
        key: in std_logic_vector(127 downto 0);
        IV: in std_logic_vector(95 downto 0);

        -- Input flow
        P_data: in  std_logic_vector(127 downto 0);
        P_valid: in  std_logic;
        P_last: in  std_logic;
        P_bytes: in  std_logic_vector(3 downto 0);

        A_data: in  std_logic_vector(127 downto 0);
        A_valid: in  std_logic;
        A_last: in  std_logic;
        A_bytes: in  std_logic_vector(3 downto 0);

        -- Output
        C_data: out std_logic_vector(127 downto 0);
        C_valid: out std_logic;
        C_last: out std_logic;
        C_bytes: out std_logic_vector(3 downto 0);

        T: out std_logic_vector(127 downto 0);
        T_valid: out std_logic
    );
end gcm;


architecture rtl of gcm is
    
    signal H: std_logic_vector(127 downto 0);
    signal H_valid: std_logic;

    signal J0: std_logic_vector(127 downto 0);
    signal J0_incr: std_logic_vector(127 downto 0);


    signal hash_data_in: std_logic_vector(127 downto 0);
    signal hash_data_valid: std_logic;
    signal hash_is_last: std_logic;
    signal hash_out: std_logic_vector(127 downto 0);
    signal hash_valid, hash_last: std_logic;

    signal A_done, C_done: std_logic;
    signal len_C, len_A: std_logic_vector(63 downto 0);
    signal len_A_tmp: unsigned(63 downto 0);
    signal A_complete, C_complete: std_logic_vector(127 downto 0);

    signal final_out: std_logic_vector(127 downto 0);
    signal final_valid, final_last: std_logic;

    signal J0_encr: std_logic_vector(127 downto 0);

    signal gctr_data_in, gctr_data_out: std_logic_vector(127 downto 0);
    signal gctr_valid, gctr_valid_out: std_logic;
    signal gctr_is_last, gctr_is_last_out: std_logic;
    signal gctr_byte, gctr_byte_out: std_logic_vector(3 downto 0);
    signal gctr_len: std_logic_vector(63 downto 0);
    signal ICB: std_logic_vector(127 downto 0);

    type state is (GCTR_H, GCTR_C, GCTR_T);
    signal current: state;
    signal generate_h: std_logic;
    signal gctr_start: std_logic;

begin
    J0 <= IV & x"00000001";
    J0_incr <= IV & x"00000002";

    -- GCTR MUX
    gctr_data_in <= (others => '0') when current = GCTR_H else P_data when current = GCTR_C else hash_out;

    gctr_valid <= generate_h when current = GCTR_H else P_valid when current = GCTR_C else hash_valid;

    gctr_is_last <= '1' when current = GCTR_H else P_last when current = GCTR_C else '1';

    gctr_byte <= "0000" when current = GCTR_H else P_bytes when current = GCTR_C else "0000";

    ICB <= (others => '0') when current = GCTR_H else J0_incr when current = GCTR_C else J0; 

    -- GCTR UN-MUX
    
    C_data <= gctr_data_out when current = GCTR_C else (others => '0');
    C_valid <= gctr_valid_out when current = GCTR_C else '0';
    C_last <= gctr_is_last_out when current = GCTR_C else '0';
    C_bytes <= gctr_byte_out when current = GCTR_C else (others => '0');
    len_C  <= gctr_len when current = GCTR_C else (others => '0');

    T <= gctr_data_out when current = GCTR_T else (others => '0');
    T_valid <= gctr_valid_out when current = GCTR_T else '0';

    -- GCTR
    gctr: entity work.gctr_core
        port map (
            clk => clk,
            rst => rst,
            ICB => ICB,
            key => key,
            start => gctr_start,
            data_in => gctr_data_in,
            data_in_valid => gctr_valid,
            is_last_in => gctr_is_last,
            bytes_valid_in => gctr_byte,
            data_out => gctr_data_out,
            data_out_valid => gctr_valid_out,
            is_last_out => gctr_is_last_out,
            bytes_valid_out => gctr_byte_out,
            len_out => gctr_len
        );

    -- GHASH MUX
    A_complete <= complete(A_data, A_bytes, A_last);
    C_complete <= complete(C_data, gctr_byte_out, C_last);

    hash_data_in <= A_complete when A_done = '0' else C_complete when C_done = '0' else len_A & len_C;
    hash_data_valid <= A_valid when A_done = '0' else C_valid when C_done = '0' else final_valid;
    hash_is_last <= A_last  when A_done = '0' else C_last  when C_done = '0' else '1';

    -- GHASH
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

    process(clk) -- Check if A or C has been entirely sent to GHASH
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current <= GCTR_H;
                A_done <= '0';
                C_done <= '0';
                len_A_tmp <= (others => '0');
                final_valid <= '0';
                gctr_start <= '0';
                
            elsif start = '1' then
                current <= GCTR_H;
                A_done <= '0';
                C_done <= '0';
                len_A_tmp <= (others => '0');
                final_valid <= '0';
                generate_h <= '1';
                gctr_start <= '1';

            else
                final_valid <= '0';
                generate_h <= '0'; -- Reset at next clock cycle
                gctr_start <= '0';

                case current is
                    when GCTR_H =>
                        if gctr_valid_out = '1' then
                            H <= gctr_data_out;
                            current <= GCTR_C;
                            gctr_start <= '1';
                        end if;
                        
                    when GCTR_C =>
                        if hash_valid = '1' then
                            current <= GCTR_T;
                            gctr_start <= '1';
                        end if;
                        
                    when GCTR_T =>
                        null;
                end case;

                if A_valid = '1' and A_done = '0' then
                    if A_last = '1' then
                        len_A_tmp <= len_A_tmp + (unsigned(A_bytes) * 8);
                        A_done <= '1';
                    else
                        len_A_tmp <= len_A_tmp + 128;
                    end if;
                end if;

                if C_valid = '1' and C_done = '0' then
                    if C_last = '1' then
                        C_done <= '1';
                        final_valid <= '1'; 
                    end if;
                end if;
            end if; 
        end if;
    end process;

    len_A <= std_logic_vector(len_A_tmp);

end architecture rtl;