library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_in is
    port(
        aclk: in  std_ulogic;
        aresetn: in  std_ulogic;

        start: in  std_ulogic;
        aad_base_addr: in  std_ulogic_vector(31 downto 0);
        aad_byte_length: in  std_ulogic_vector(31 downto 0);
        payload_base_addr: in  std_ulogic_vector(31 downto 0);
        payload_byte_length: in  std_ulogic_vector(31 downto 0);
        idle: out std_ulogic;

        araddr: out std_ulogic_vector(29 downto 0);
        arvalid: out std_ulogic;
        arready: in  std_ulogic;
        rdata: in  std_ulogic_vector(31 downto 0);
        rresp: in  std_ulogic_vector(1 downto 0);
        rvalid: in  std_ulogic;
        rready: out std_ulogic;

        data_out: out std_ulogic_vector(127 downto 0);
        data_out_valid: out std_ulogic;
        data_out_ready: in  std_ulogic;
        is_last_out: out std_ulogic;
        
        -- 00: Idle, 01: Reading A, 10: Reading P
        state: out std_ulogic_vector(1 downto 0)
    );
end entity dma_in;

architecture rtl of dma_in is

    signal fifo_write, fifo_read, fifo_empty, fifo_full : std_ulogic;
    signal fifo_rdata      : std_ulogic_vector(31 downto 0);
    
    signal join_in_ready   : std_ulogic;
    signal join_out_valid  : std_ulogic;

    type dma_state_type is (IDLE_STATE, READING_A, READING_P);
    signal current_state : dma_state_type;

    signal current_addr      : unsigned(29 downto 0);
    signal bytes_to_fetch    : unsigned(31 downto 0);
    signal outstanding_reads : integer range 0 to 32;
    signal blocks_to_send    : unsigned(27 downto 0); 
    
    signal payload_addr_reg   : unsigned(29 downto 0);
    signal payload_bytes_reg  : unsigned(31 downto 0);
    signal payload_blocks_reg : unsigned(27 downto 0);

    signal ar_valid_int      : std_ulogic;
    signal r_ready_int       : std_ulogic;

begin

    -- FIFO
    fifo: entity work.fifo
        generic map(w => 32, d => 32)
        port map(
            aclk => aclk,
            aresetn => aresetn,
            write => fifo_write,
            wdata => rdata,
            read => fifo_read,
            rdata => fifo_rdata,
            empty => fifo_empty,
            full => fifo_full
        );

    -- Join Component
    join: entity work.dma_join
        port map(
            aclk => aclk,
            aresetn => aresetn,
            data_in => fifo_rdata,
            data_in_valid => not fifo_empty,
            data_in_ready => join_in_ready,
            data_out => data_out,
            data_out_valid => join_out_valid,
            data_out_ready => data_out_ready
        );

    data_out_valid <= join_out_valid;

    fifo_read <= join_in_ready and not fifo_empty;
    
    r_ready_int <= not fifo_full;
    rready <= r_ready_int;
    fifo_write <= rvalid and r_ready_int;

    ar_valid_int <= '1' when (current_state = READING_A or current_state = READING_P) and (bytes_to_fetch > 0) and (outstanding_reads < 16) else '0';
    arvalid <= ar_valid_int;
    araddr <= std_ulogic_vector(current_addr);

    is_last_out <= '1' when ((current_state = READING_P and blocks_to_send = 1 and join_out_valid = '1') or
                             (current_state = READING_A and payload_bytes_reg = 0 and blocks_to_send = 1 and join_out_valid = '1')) else '0';

    -- Combinatorial state output to align with the active data block stream
    state <= "01" when current_state = READING_A else
             "10" when current_state = READING_P else
             "00";

    -- AXI read
    process(aclk)
        variable ar_fire : boolean;
        variable r_fire : boolean;
        variable out_fire : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                current_state <= IDLE_STATE;
                current_addr <= (others => '0');
                bytes_to_fetch <= (others => '0');
                blocks_to_send <= (others => '0');
                outstanding_reads <= 0;
                idle <= '1';
                payload_addr_reg <= (others => '0');
                payload_bytes_reg <= (others => '0');
                payload_blocks_reg <= (others => '0');
            else
                ar_fire := (ar_valid_int = '1' and arready = '1');
                r_fire := (rvalid = '1' and r_ready_int = '1');
                out_fire := (join_out_valid = '1' and data_out_ready = '1');

                if ar_fire and not r_fire then
                    outstanding_reads <= outstanding_reads + 1;
                elsif not ar_fire and r_fire then
                    outstanding_reads <= outstanding_reads - 1;
                end if;

                case current_state is
                    when IDLE_STATE =>
                        if start = '1' then
                            -- Store payload parameters to execute right after AAD finishes
                            payload_addr_reg   <= unsigned(payload_base_addr(29 downto 0));
                            payload_bytes_reg  <= unsigned(payload_byte_length);
                            payload_blocks_reg <= unsigned(payload_byte_length(31 downto 4));
                            
                            if unsigned(aad_byte_length) > 0 then
                                current_state <= READING_A;
                                current_addr <= unsigned(aad_base_addr(29 downto 0));
                                bytes_to_fetch <= unsigned(aad_byte_length);
                                blocks_to_send <= unsigned(aad_byte_length(31 downto 4));
                                idle <= '0';
                            elsif unsigned(payload_byte_length) > 0 then
                                current_state <= READING_P;
                                current_addr <= unsigned(payload_base_addr(29 downto 0));
                                bytes_to_fetch <= unsigned(payload_byte_length);
                                blocks_to_send <= unsigned(payload_byte_length(31 downto 4));
                                idle <= '0';
                            end if;
                        end if;

                    when READING_A =>
                        if ar_fire then
                            current_addr <= current_addr + 4;
                            bytes_to_fetch <= bytes_to_fetch - 4;
                        end if;

                        if out_fire then
                            blocks_to_send <= blocks_to_send - 1;
                            
                            if blocks_to_send = 1 then
                                if payload_bytes_reg > 0 then
                                    current_state <= READING_P;
                                    current_addr <= payload_addr_reg;
                                    bytes_to_fetch <= payload_bytes_reg;
                                    blocks_to_send <= payload_blocks_reg;
                                else
                                    current_state <= IDLE_STATE; 
                                    idle <= '1';
                                end if;
                            end if;
                        end if;

                    when READING_P =>
                        if ar_fire then
                            current_addr <= current_addr + 4;
                            bytes_to_fetch <= bytes_to_fetch - 4;
                        end if;

                        if out_fire then
                            blocks_to_send <= blocks_to_send - 1;
                            
                            if blocks_to_send = 1 then
                                current_state <= IDLE_STATE; 
                                idle <= '1';
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;