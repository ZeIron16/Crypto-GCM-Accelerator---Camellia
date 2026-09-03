# build_zybo.tcl
# Zynq AES-GCM crypto accelerator – Zybo Z7-10 (xc7z010clg400-1)
#
# Architecture:
#   CPU (M_AXI_GP0) --> AXI Interconnect --> crypto_0/s0_axi   @ 0x43C00000
#   CPU (M_AXI_GP0) --> AXI Interconnect --> axi_bram_ctrl_0   @ 0x40000000
#                                                 |
#                                           blk_mem_gen_0 (True Dual Port)
#                                                 |
#   crypto_0/m0_axi --> axi_bram_ctrl_1    @ 0x00000000 (crypto local bus)

set project_name "crypto_zybo"
set board_part   "xc7z010clg400-1"

close_project -quiet
create_project -force $project_name ./$project_name -part $board_part

set vhdl_files [list \
    crypto.vhd gcm.vhd dma_in.vhd dma_out.vhd camellia_fsm1.vhd \
    fifo.vhd ghash.vhd gctr.vhd mob.vhd dma_split.vhd dma_join.vhd \
    key_sched.vhd gcm_pkg.vhd]

add_files $vhdl_files
set_property file_type {VHDL 2008} [get_files $vhdl_files]
set_property file_type {VHDL}      [get_files "*crypto.vhd"]

# Parse VHDL so crypto module ports are visible before BD references it
update_compile_order -fileset sources_1

create_bd_design "system"

# --- Zynq PS ---
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000}] \
    [get_bd_cells processing_system7_0]

# --- Crypto Engine ---
create_bd_cell -type module -reference crypto crypto_0

# --- Tie off board I/O ---
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_0
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {4}] \
    [get_bd_cells constant_0]
connect_bd_net [get_bd_pins constant_0/dout] [get_bd_pins crypto_0/sw]
connect_bd_net [get_bd_pins constant_0/dout] [get_bd_pins crypto_0/btn]

# ---------------------------------------------------------------------------
#    Port A  --> CPU  (via axi_bram_ctrl_0)
#    Port B  --> Crypto DMA (via axi_bram_ctrl_1)
#
#    Explicit width=32 on BOTH ports.  Without this, blk_mem_gen defaults
#    Port B to 18-bit when only Memory_Type is set, causing a width mismatch
#    that makes the AXI BRAM Controller return 0x00000008 on every CPU read.
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_0
set_property -dict [list \
    CONFIG.Memory_Type                                        {True_Dual_Port_RAM} \
    CONFIG.Write_Width_A                                      {32} \
    CONFIG.Read_Width_A                                       {32} \
    CONFIG.Write_Depth_A                                      {1024} \
    CONFIG.Write_Width_B                                      {32} \
    CONFIG.Read_Width_B                                       {32} \
    CONFIG.Enable_B                                           {Use_ENB_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives         {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives         {false} \
] [get_bd_cells blk_mem_gen_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_1

# Set single-port mode on each controller (each owns one BRAM port)
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells axi_bram_ctrl_0]
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells axi_bram_ctrl_1]

connect_bd_intf_net \
    [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] \
    [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTA]

connect_bd_intf_net \
    [get_bd_intf_pins axi_bram_ctrl_1/BRAM_PORTA] \
    [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTB]


# CPU --> Crypto register slave
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Slave "/crypto_0/s0_axi"} \
    [get_bd_intf_pins crypto_0/s0_axi]

# CPU --> BRAM Controller 0  (CPU read/write window into BRAM)
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Slave "/axi_bram_ctrl_0/S_AXI"} \
    [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]

# Crypto DMA master --> BRAM Controller 1  (crypto engine window into BRAM)
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/crypto_0/m0_axi" Slave "/axi_bram_ctrl_1/S_AXI"} \
    [get_bd_intf_pins axi_bram_ctrl_1/S_AXI]


assign_bd_address

# Print all segment names so mismatches are visible in the build log
puts "INFO: address segments after assign_bd_address:"
foreach seg [get_bd_addr_segs] { puts "  $seg" }

set_property offset 0x43C00000 \
    [get_bd_addr_segs {processing_system7_0/Data/SEG_crypto_0_reg0}]
set_property offset 0x40000000 \
    [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_0_Mem0}]
set_property offset 0x00000000 \
    [get_bd_addr_segs {crypto_0/m0_axi/SEG_axi_bram_ctrl_1_Mem0}]


save_bd_design
validate_bd_design

set wrapper_path [make_wrapper \
    -files [get_files ./$project_name/$project_name.srcs/sources_1/bd/system/system.bd] \
    -top]
add_files -norecurse $wrapper_path
set_property top system_wrapper [current_fileset]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis FAILED. Check:\n  ./$project_name/$project_name.runs/synth_1/runme.log"
}
puts "INFO: Synthesis complete."

launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation FAILED. Check:\n  ./$project_name/$project_name.runs/impl_1/runme.log"
}
puts "INFO: Implementation complete."

open_run impl_1
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force -bin_file fpga.bit

puts ""
puts "=============================================="
puts " SUCCESS: bitstream written to fpga.bit"
puts " Copy fpga.bit to the SD card and reboot."
puts "=============================================="
