library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_out is
    port(
        aclk: in  std_ulogic;
        aresetn: in  std_ulogic;

        start: in  std_ulogic;
        payload_base_addr: in  std_ulogic_vector(31 downto 0);
        payload_byte_length: in  std_ulogic_vector(31 downto 0);
        idle: out std_ulogic;

        awaddr: out std_ulogic_vector(29 downto 0);
        awvalid: out std_ulogic;
        awready: in  std_ulogic;
        wdata: out std_ulogic_vector(31 downto 0);
        wstrb: out std_ulogic_vector(3 downto 0);
        wvalid: out std_ulogic;
        wready: in  std_ulogic;
        bresp: in  std_ulogic_vector(1 downto 0);
        bvalid: in  std_ulogic;
        bready: out std_ulogic;

        data_in: in  std_ulogic_vector(127 downto 0);
        data_in_valid: in  std_ulogic;
        data_in_ready: out std_ulogic
    );
end entity dma_out;

architecture rtl of dma_out is

    signal split_data: std_ulogic_vector(31 downto 0);
    signal split_valid: std_ulogic;
    signal split_ready: std_ulogic;

    signal fifo_write, fifo_read, fifo_empty, fifo_full: std_ulogic;
    signal fifo_rdata: std_ulogic_vector(31 downto 0);

    type state_type is (IDLE_STATE, WRITING);
    signal current_state: state_type;

    signal aw_addr: unsigned(29 downto 0);
    signal words_to_send: unsigned(29 downto 0);
    signal aw_sent: unsigned(29 downto 0);
    signal w_sent: unsigned(29 downto 0);
    signal b_recv: unsigned(29 downto 0);

    signal aw_valid_int: std_ulogic;
    signal w_valid_int: std_ulogic;

begin

    -- Spit Component
    split: entity work.dma_split
        port map(
            aclk => aclk,
            aresetn => aresetn,
            data_in => data_in,
            data_in_valid => data_in_valid,
            data_in_ready => data_in_ready,
            data_out => split_data,
            data_out_valid => split_valid,
            data_out_ready => split_ready
        );

    -- FIFO
    fifo: entity work.fifo
        generic map(w => 32, d => 32)
        port map(
            aclk => aclk,
            aresetn => aresetn,
            write => fifo_write,
            wdata => split_data,
            read => fifo_read,
            rdata => fifo_rdata,
            empty => fifo_empty,
            full => fifo_full
        );

    split_ready <= not fifo_full;
    fifo_write <= split_valid and not fifo_full;
    
    fifo_read <= wready and w_valid_int;

    wdata <= fifo_rdata;
    wstrb <= "1111"; -- Always write full 32-bit words
    wvalid <= w_valid_int;
    
    awaddr <= std_ulogic_vector(aw_addr);
    awvalid <= aw_valid_int;

    bready <= '1';

    -- AXI Write
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                current_state <= IDLE_STATE;
                aw_addr <= (others => '0');
                words_to_send <= (others => '0');
                aw_sent <= (others => '0');
                w_sent <= (others => '0');
                b_recv <= (others => '0');
                idle <= '1';
                aw_valid_int <= '0';
                w_valid_int <= '0';
            else
                case current_state is
                    when IDLE_STATE =>
                        if start = '1' then
                            aw_addr <= unsigned(payload_base_addr(29 downto 0));
                            words_to_send <= unsigned(payload_byte_length(31 downto 2));
                            aw_sent <= (others => '0');
                            w_sent <= (others => '0');
                            b_recv <= (others => '0');
                            aw_valid_int <= '0';
                            w_valid_int <= '0';
                            
                            if unsigned(payload_byte_length) > 0 then
                                current_state <= WRITING;
                                idle <= '0';
                            end if;
                        end if;

                    when WRITING =>
                        -- Address Write Channel
                        if aw_valid_int = '1' and awready = '1' then
                            aw_valid_int <= '0';
                            aw_addr <= aw_addr + 4;
                            aw_sent <= aw_sent + 1;
                        elsif aw_valid_int = '0' and aw_sent < words_to_send and aw_sent <= w_sent and fifo_empty = '0' then
                            aw_valid_int <= '1';
                        end if;

                        -- Data Write Channel
                        if w_valid_int = '1' and wready = '1' then
                            w_valid_int <= '0';
                            w_sent <= w_sent + 1;
                        elsif w_valid_int = '0' and w_sent < words_to_send and fifo_empty = '0' then
                            w_valid_int <= '1';
                        end if;

                        -- Response Channel
                        if bvalid = '1' and bready = '1' then
                            b_recv <= b_recv + 1;
                            if (b_recv + 1) = words_to_send then
                                current_state <= IDLE_STATE;
                                idle <= '1';
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;