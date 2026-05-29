library ieee;
use ieee.std_logic_1164.all;

entity crypto is
    port(
        aclk:           in  std_ulogic;
        aresetn:        in  std_ulogic;
        s0_axi_araddr:  in  std_ulogic_vector(11 downto 0);
        s0_axi_arvalid: in  std_ulogic;
        s0_axi_arready: out std_ulogic;
        s0_axi_awaddr:  in  std_ulogic_vector(11 downto 0);
        s0_axi_awvalid: in  std_ulogic;
        s0_axi_awready: out std_ulogic;
        s0_axi_wdata:   in  std_ulogic_vector(31 downto 0);
        s0_axi_wstrb:   in  std_ulogic_vector(3 downto 0);
        s0_axi_wvalid:  in  std_ulogic;
        s0_axi_wready:  out std_ulogic;
        s0_axi_rdata:   out std_ulogic_vector(31 downto 0);
        s0_axi_rresp:   out std_ulogic_vector(1 downto 0);
        s0_axi_rvalid:  out std_ulogic;
        s0_axi_rready:  in  std_ulogic;
        s0_axi_bresp:   out std_ulogic_vector(1 downto 0);
        s0_axi_bvalid:  out std_ulogic;
        s0_axi_bready:  in  std_ulogic;
        m0_axi_araddr:  out std_ulogic_vector(29 downto 0);
        m0_axi_arvalid: out std_ulogic;
        m0_axi_arready: in  std_ulogic;
        m0_axi_awaddr:  out std_ulogic_vector(29 downto 0);
        m0_axi_awvalid: out std_ulogic;
        m0_axi_awready: in  std_ulogic;
        m0_axi_wdata:   out std_ulogic_vector(31 downto 0);
        m0_axi_wstrb:   out std_ulogic_vector(3 downto 0);
        m0_axi_wvalid:  out std_ulogic;
        m0_axi_wready:  in  std_ulogic;
        m0_axi_rdata:   in  std_ulogic_vector(31 downto 0);
        m0_axi_rresp:   in  std_ulogic_vector(1 downto 0);
        m0_axi_rvalid:  in  std_ulogic;
        m0_axi_rready:  out std_ulogic;
        m0_axi_bresp:   in  std_ulogic_vector(1 downto 0);
        m0_axi_bvalid:  in  std_ulogic;
        m0_axi_bready:  out std_ulogic;
        irq:            out std_ulogic;
        sw:             in  std_ulogic_vector(3 downto 0);
        btn:            in  std_ulogic_vector(3 downto 0);
        led:            out std_ulogic_vector(3 downto 0)
    );

end entity crypto;

architecture rtl of crypto is
    signal reg_start: std_ulogic := '0';
    signal reg_aad_base_addr: std_ulogic_vector(31 downto 0) := (others => '0');
    signal reg_aad_byte_length: std_ulogic_vector(31 downto 0) := (others => '0');
    signal reg_payload_base_addr: std_ulogic_vector(31 downto 0) := (others => '0');
    signal reg_payload_byte_length: std_ulogic_vector(31 downto 0) := (others => '0');
    signal reg_cipher_base_addr: std_ulogic_vector(31 downto 0) := (others => '0');
    signal reg_cipher_byte_length: std_ulogic_vector(31 downto 0) := (others => '0');
    
    signal reg_key: std_ulogic_vector(127 downto 0) := (others => '0');
    signal reg_iv: std_ulogic_vector(95 downto 0)  := (others => '0');
    signal reg_tag : std_ulogic_vector(127 downto 0) := (others => '0');
    signal reg_done: std_ulogic := '0';

    -- AXI

    signal s0_axi_awready_int : std_ulogic := '0';
    signal s0_axi_wready_int  : std_ulogic := '0';
    signal s0_axi_bvalid_int  : std_ulogic := '0';
    signal s0_axi_bresp_int   : std_ulogic_vector(1 downto 0) := "00";

    signal s0_axi_arready_int : std_ulogic := '0';
    signal s0_axi_rvalid_int  : std_ulogic := '0';
    signal s0_axi_rresp_int   : std_ulogic_vector(1 downto 0) := "00";
    signal s0_axi_rdata_int   : std_ulogic_vector(31 downto 0) := (others => '0');

    -- DMA

    signal dma_in_idle : std_ulogic;
    signal dma_out_idle : std_ulogic;
    signal dma_in_state : std_ulogic_vector(1 downto 0);

    -- DMA_IN -> GCM
    signal dma_gcm_data : std_ulogic_vector(127 downto 0);
    signal dma_gcm_valid : std_ulogic;
    signal dma_gcm_ready : std_ulogic;
    signal dma_gcm_last : std_ulogic;

    -- GCM -> DMA_OUT
    signal gcm_dma_data : std_ulogic_vector(127 downto 0);
    signal gcm_dma_valid : std_ulogic;
    signal gcm_dma_ready : std_ulogic;

    signal gcm_rst : std_logic;
    signal gcm_T : std_logic_vector(127 downto 0);
    signal gcm_T_valid : std_logic;
    signal gcm_C_data : std_logic_vector(127 downto 0);

begin
    s0_axi_awready <= s0_axi_awready_int;
    s0_axi_wready <= s0_axi_wready_int;
    s0_axi_bvalid <= s0_axi_bvalid_int;
    s0_axi_bresp <= s0_axi_bresp_int;

    s0_axi_arready <= s0_axi_arready_int;
    s0_axi_rvalid <= s0_axi_rvalid_int;
    s0_axi_rresp <= s0_axi_rresp_int;
    s0_axi_rdata <= s0_axi_rdata_int;

    -- DMA in
    dma_in: entity work.dma_in
    port map(
        aclk => aclk,
        aresetn => aresetn,
        
        start => reg_start,
        aad_base_addr => reg_aad_base_addr,
        aad_byte_length => reg_aad_byte_length,
        payload_base_addr => reg_payload_base_addr,
        payload_byte_length => reg_payload_byte_length,
        idle => dma_in_idle,
        state => dma_in_state,

        araddr => m0_axi_araddr,
        arvalid => m0_axi_arvalid,
        arready => m0_axi_arready,
        rdata => m0_axi_rdata,
        rresp => m0_axi_rresp,
        rvalid => m0_axi_rvalid,
        rready => m0_axi_rready,

        data_out => dma_gcm_data,
        data_out_valid => dma_gcm_valid,
        data_out_ready => dma_gcm_ready,
        is_last_out => dma_gcm_last
    );

    -- GCM

    gcm_rst <= not std_logic(aresetn);

    gcm_inst: entity work.gcm
    port map(
        clk        => std_logic(aclk),
        rst        => gcm_rst,
        start      => std_logic(reg_start),
        
        ready      => dma_gcm_ready,

        -- Key and IV coming statically from registers
        key        => std_logic_vector(reg_key),
        IV         => std_logic_vector(reg_iv),

        data_state => dma_in_state,
        data_in    => std_logic_vector(dma_gcm_data),
        valid_in   => std_logic(dma_gcm_valid),
        last_in    => std_logic(dma_gcm_last),
        bytes_in   => "0000", -- Always 16 bytes

        C_data     => gcm_C_data,
        C_valid    => gcm_dma_valid,
        C_last     => open,
        C_bytes    => open,

        T          => gcm_T,
        T_valid    => gcm_T_valid
    );

    gcm_dma_data <= std_ulogic_vector(gcm_C_data);

    -- DMA out
    dma_out: entity work.dma_out
    port map(
        aclk => aclk,
        aresetn => aresetn,
        
        start => reg_start,
        payload_base_addr => reg_cipher_base_addr,
        payload_byte_length => reg_payload_byte_length,
        idle => dma_out_idle,

        awaddr => m0_axi_awaddr,
        awvalid => m0_axi_awvalid,
        awready => m0_axi_awready,
        wdata => m0_axi_wdata,
        wstrb => m0_axi_wstrb,
        wvalid => m0_axi_wvalid,
        wready => m0_axi_wready,
        bresp => m0_axi_bresp,
        bvalid => m0_axi_bvalid,
        bready => m0_axi_bready,

        data_in => gcm_dma_data,
        data_in_valid => gcm_dma_valid,
        data_in_ready => gcm_dma_ready
    );
        
    -- AXI Write Process
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                s0_axi_awready_int <= '0';
                s0_axi_wready_int  <= '0';
                s0_axi_bvalid_int  <= '0';
                s0_axi_bresp_int   <= "00";
                reg_start <= '0';
            else
                if reg_start = '1' then
                    reg_start <= '0';
                end if;

                -- Handshake
                if s0_axi_awvalid = '1' and s0_axi_wvalid = '1' and s0_axi_awready_int = '0' and s0_axi_bvalid_int = '0' then
                    s0_axi_awready_int <= '1';
                    s0_axi_wready_int  <= '1';
                    s0_axi_bvalid_int  <= '1';
                    s0_axi_bresp_int   <= "00";

                    case s0_axi_awaddr(11 downto 2) is
                        when "0000000000" => -- 0x00: Bit 0 = Start
                            reg_start <= s0_axi_wdata(0);
                        when "0000000001" => -- 0x04: AAD Base Addr
                            reg_aad_base_addr <= s0_axi_wdata;
                        when "0000000010" => -- 0x08: AAD Length
                            reg_aad_byte_length <= s0_axi_wdata;
                        when "0000000011" => -- 0x0C: Plaintext Base Addr
                            reg_payload_base_addr <= s0_axi_wdata;
                        when "0000000100" => -- 0x10: Plaintext Length
                            reg_payload_byte_length <= s0_axi_wdata;
                        when "0000000101" => -- 0x14: Ciphertext Base Addr
                            reg_cipher_base_addr <= s0_axi_wdata;
                        when "0000000110" => -- 0x18: Ciphertext Length
                            reg_cipher_byte_length <= s0_axi_wdata;

                        -- KEY
                        when "0000001000" => reg_key(127 downto 96) <= s0_axi_wdata;
                        when "0000001001" => reg_key(95 downto 64)  <= s0_axi_wdata;
                        when "0000001010" => reg_key(63 downto 32)  <= s0_axi_wdata;
                        when "0000001011" => reg_key(31 downto 0)   <= s0_axi_wdata;

                        -- IV
                        when "0000001100" => reg_iv(95 downto 64)   <= s0_axi_wdata;
                        when "0000001101" => reg_iv(63 downto 32)   <= s0_axi_wdata;
                        when "0000001110" => reg_iv(31 downto 0)    <= s0_axi_wdata;

                        when others =>
                            s0_axi_bresp_int <= "11"; 
                    end case;
                else
                    s0_axi_awready_int <= '0';
                    s0_axi_wready_int  <= '0';
                end if;

                if s0_axi_bvalid_int = '1' and s0_axi_bready = '1' then
                    s0_axi_bvalid_int <= '0';
                end if;
            end if;
        end if;
    end process;

    -- AXI4 Read
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                s0_axi_arready_int <= '0';
                s0_axi_rvalid_int  <= '0';
                s0_axi_rresp_int   <= "00";
                s0_axi_rdata_int   <= (others => '0');
            else
                if s0_axi_arvalid = '1' and s0_axi_arready_int = '0' and s0_axi_rvalid_int = '0' then
                    s0_axi_arready_int <= '1';
                    s0_axi_rvalid_int  <= '1';
                    s0_axi_rresp_int   <= "00";

                    case s0_axi_araddr(11 downto 2) is
                        when "0000000000" =>
                            s0_axi_rdata_int <= (1 => reg_done, others => '0');
                        when "0000000001" => s0_axi_rdata_int <= reg_aad_base_addr;
                        when "0000000010" => s0_axi_rdata_int <= reg_aad_byte_length;
                        when "0000000011" => s0_axi_rdata_int <= reg_payload_base_addr;
                        when "0000000100" => s0_axi_rdata_int <= reg_payload_byte_length;
                        when "0000000101" => s0_axi_rdata_int <= reg_cipher_base_addr;
                        when "0000000110" => s0_axi_rdata_int <= reg_cipher_byte_length;

                        -- TAG
                        when "0000010000" => s0_axi_rdata_int <= reg_tag(127 downto 96);
                        when "0000010001" => s0_axi_rdata_int <= reg_tag(95 downto 64);
                        when "0000010010" => s0_axi_rdata_int <= reg_tag(63 downto 32);
                        when "0000010011" => s0_axi_rdata_int <= reg_tag(31 downto 0);

                        when others =>
                            s0_axi_rresp_int <= "11"; 
                            s0_axi_rdata_int <= (others => '0');
                    end case;
                else
                    s0_axi_arready_int <= '0';
                end if;

                if s0_axi_rvalid_int = '1' and s0_axi_rready = '1' then
                    s0_axi_rvalid_int <= '0';
                end if;
            end if;
        end if;
    end process;

    led <= (0 => reg_done, others => '0');
    irq <= reg_done;

    -- Latch the Tag and Done
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                reg_tag  <= (others => '0');
                reg_done <= '0';
            else
                if reg_start = '1' then
                    reg_done <= '0';
                elsif gcm_T_valid = '1' then
                    reg_tag  <= std_ulogic_vector(gcm_T);
                    reg_done <= '1';
                end if;
            end if;
        end if;
    end process;
          
end architecture rtl;
-- vim: set tabstop=4 softtabstop=4 shiftwidth=4 expandtab textwidth=0:
