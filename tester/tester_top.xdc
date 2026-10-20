#=============================================================================
# tester_top constraints -- PYNQ-Z2 TESTER board
#
# Pin numbers are IDENTICAL to the emulator's XDC: a straight-through ribbon
# connects header pin N to header pin N, so the same physical pin carries the
# same signal on both boards. Only the DIRECTIONS differ, and those come from
# the RTL, not from here.
#
# Every assignment below was verified ON HARDWARE with rpi_probe:
#   - jumpering 3V3 to header pins 11, 13 and 40 drove the expected probe bits
#   - RPi 3, 5, 27, 28 carry PASSIVE pull-ups (each drives cleanly to 0)
#   - RPi 13 / V7 IS connected, despite being absent from the board XDC
#
# !! Ribbon: remove the conductors at RPi pins 1, 2, 4, 17 (3V3 / 5V).
#    Two independently powered boards share GROUNDS ONLY.
# !! Connect all 8 grounds: RPi 6, 9, 14, 20, 25, 30, 34, 39.
#=============================================================================

#--- 125 MHz board oscillator ------------------------------------------------
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -period 8.000 -name sysclk [get_ports sysclk]

#--- Sequencer clock ---------------------------------------------------------
# The sequencer runs on seq_clk, the BUFGMUX output. Its two sources are the
# sysclk divider (worst case 62.5 MHz when CLKDIV[6:0]=0) and the MMCM at
# 95 MHz. Vivado derives both automatically; they are mutually exclusive by
# construction, so tell the timing engine not to analyse paths between them.
create_generated_clock -name clk_slow -source [get_ports sysclk] -divide_by 2 \
    [get_pins bufg_slow/O]

# THREE asynchronous groups. Every path between them is a real clock-domain
# crossing that the RTL already handles, so the timing engine must not analyse
# them -- left in, it computes meaningless sub-nanosecond requirements between
# unrelated clock edges and reports violations that cannot be fixed because
# there is nothing wrong.
#
#   sysclk      VIO transport, CLKDIV register, the divider itself
#   clk_slow    sequencer when CLKDIV[7]=0   (BUFGMUX-exclusive with clk_fast)
#   clk_wiz_95  sequencer when CLKDIV[7]=1
#
# What makes the exclusion legitimate, not a cover-up:
#   * reg_we_raw crosses through a 2-flop synchroniser in the destination
#     domain (we_seq) before any edge is detected
#   * reg_addr / reg_wdata are quasi-static -- VIO holds them for milliseconds
#     before the write pulse arrives. Stable data, synchronised control: the
#     standard crossing, and correct here precisely because operands are always
#     set before the write is pulsed
#   * rdata_seq is double-registered back into sysclk, and software polls until
#     busy clears before reading results
set_clock_groups -asynchronous \
    -group [get_clocks sysclk] \
    -group [get_clocks clk_slow] \
    -group [get_clocks -include_generated_clocks clk_out1_clk_wiz_95]

#--- Level shifter output enable (Stage 2) -----------------------------------
# Parks the DUT board's level shifters in high-Z during bus turnaround, so
# they cannot drive against the chip while Chip.sv's registered dir is still
# catching up. Unused in Stage 1; routed now so the PCB can rely on it.
# Both shifter controls are on the RPi header (pins 10 and 12) -- see below.
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports shifter_oe_n]  ;# RPi 12 -> PCB J20.5 Data_bus_OE_n_3p3V
# U1/U3 DIR (PCB net Shifter_dir_3p3V): 1 = chip drives the bus, 0 = tester.
# The PCB pulls it low (R37), i.e. tester -> chip, when this pin is not driven.
set_property -dict {PACKAGE_PIN Y6  IOSTANDARD LVCMOS33} [get_ports shifter_dir]   ;# RPi 10 -> PCB J21.1 Shifter_dir_3p3V

#--- DUT clock out (chip pin 26) ---------------------------------------------
set_property -dict {PACKAGE_PIN U7  IOSTANDARD LVCMOS33} [get_ports dut_clk]       ;# RPi 11  clock-capable

#--- Data bus, bidirectional (chip pins 1-16) --------------------------------
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[0]}]   ;# chip 1  -> RPi 7
set_property -dict {PACKAGE_PIN V6  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[1]}]   ;# chip 2  -> RPi 8
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[2]}]   ;# chip 3  -> RPi 13
set_property -dict {PACKAGE_PIN U8  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[3]}]   ;# chip 4  -> RPi 15
set_property -dict {PACKAGE_PIN W6  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[4]}]   ;# chip 5  -> RPi 16
set_property -dict {PACKAGE_PIN Y7  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[5]}]   ;# chip 6  -> RPi 18
set_property -dict {PACKAGE_PIN V8  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[6]}]   ;# chip 7  -> RPi 19
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[7]}]   ;# chip 8  -> RPi 21
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[8]}]   ;# chip 9  -> RPi 22
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[9]}]   ;# chip 10 -> RPi 23
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[10]}]  ;# chip 11 -> RPi 24
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[11]}]  ;# chip 12 -> RPi 26
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[12]}]  ;# chip 13 -> RPi 29
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[13]}]  ;# chip 14 -> RPi 31
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[14]}]  ;# chip 15 -> RPi 32
set_property -dict {PACKAGE_PIN W8  IOSTANDARD LVCMOS33} [get_ports {dut_data_bus[15]}]  ;# chip 16 -> RPi 33

# The bus genuinely floats for a tick during turnaround. A KEEPER holds the
# last driven value -- no mid-rail float, no fighting either driver, and it
# never invents plausible-looking data the way a pull-up would.
set_property PULLTYPE KEEPER [get_ports {dut_data_bus[*]}]

#--- Status inputs from the DUT (chip pins 17-19) ----------------------------
# Pulled DOWN on purpose: a broken or unplugged wire then reads 0 = FAIL,
# the SAFE direction. A pull-up would make a disconnected BIST_PASS read PASS
# and hide a dead chip in Stage 2.
set_property -dict {PACKAGE_PIN Y8  IOSTANDARD LVCMOS33} [get_ports dut_bist_pass]  ;# chip 17 -> RPi 35
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports dut_bist_done]  ;# chip 18 -> RPi 36
set_property -dict {PACKAGE_PIN W9  IOSTANDARD LVCMOS33} [get_ports dut_hit]        ;# chip 19 -> RPi 37

set_property PULLTYPE PULLDOWN [get_ports dut_bist_pass]
set_property PULLTYPE PULLDOWN [get_ports dut_bist_done]
set_property PULLTYPE PULLDOWN [get_ports dut_hit]

#--- Bus control outputs (chip pins 20-21) -----------------------------------
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports dut_bus_load_en] ;# chip 20 -> RPi 38
set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports dut_bus_dir]     ;# chip 21 -> RPi 40

#--- Control outputs (chip pins 22-25) ---------------------------------------
# On the board's pulled-up I2C / HAT-ID pins. Harmless here: these are driven
# outputs, and sinking a 1.8k pull-up costs ~1.8 mA (~3.7 mA with both boards'
# pull-ups in parallel) against an 8-24 mA I/O. Measured, not assumed.
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports dut_wc]       ;# chip 22 -> RPi 3
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports dut_ce]       ;# chip 23 -> RPi 5
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports dut_bist_en]  ;# chip 24 -> RPi 27
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports dut_rst_n]    ;# chip 25 -> RPi 28

#--- DUT-facing paths are asynchronous ---------------------------------------
# dut_clk is a fabric-divided output with no timing relationship to constrain
# against the DUT, and the status/bus inputs are synchronised in RTL.
set_false_path -to   [get_ports {dut_clk dut_rst_n dut_bist_en dut_ce dut_wc dut_bus_dir dut_bus_load_en}]
set_false_path -from [get_ports {dut_hit dut_bist_done dut_bist_pass}]
set_false_path -to   [get_ports {dut_data_bus[*]}]
set_false_path -from [get_ports {dut_data_bus[*]}]

#--- Drive strength and slew rate ---------------------------------------------
# The PYNQ-Z2's headers are not impedance-controlled and carry no termination,
# which is where the board's "~50 MHz I/O limit" comes from. These settings are
# the cheapest lever available against it.
#
# CLOCK: fastest edges, strongest drive. It is a single line with both ribbon
# neighbours (RPi 10 and 12) deliberately left free, so the extra ringing and
# EMI that FAST slew costs are affordable here -- and edge rate is exactly what
# limits a clock.
set_property SLEW  FAST [get_ports dut_clk]
set_property DRIVE 16   [get_ports dut_clk]

# BUS: deliberately SLOW slew. All 16 lines switch at once, and fast edges on
# 16 simultaneous outputs produce serious ground bounce (SSO noise) that would
# corrupt the very data being read back. The bus runs well below the clock's
# frequency anyway, so there is nothing to gain and real noise to lose.
set_property SLEW  SLOW [get_ports {dut_data_bus[*]}]
set_property DRIVE 8    [get_ports {dut_data_bus[*]}]

# Control and status: slow, they change at most once per transaction.
set_property SLEW SLOW [get_ports {dut_rst_n dut_bist_en dut_ce dut_wc dut_bus_dir dut_bus_load_en shifter_oe_n shifter_dir}]

#--- Unused pins -------------------------------------------------------------
# RPi 10 (Y6) and 12 (C20) were the clock's quiet ribbon neighbours; with
# individual jumpers in Stage 2 they now carry shifter_dir / shifter_oe_n.
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]
