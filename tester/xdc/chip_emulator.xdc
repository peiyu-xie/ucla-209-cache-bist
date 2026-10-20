#=============================================================================
# Chip emulator -- PYNQ-Z2 Raspberry Pi header
#
# Assignment follows the CHIP PAD ORDER (chip pin 1..26) so the Stage-2 DUT
# board routes with almost no crossovers:
#
#   chip  1..16  Data_bus[0..15]  -> RPi  7..33   (ascending, no crossovers)
#   chip 17..21  status/control   -> RPi 35..40   (ascending, no crossovers)
#   chip 22..25  control inputs   -> RPi  3,5,27,28  (the pulled-high pins)
#   chip 26      clk              -> RPi 11       (U7, clock-capable)
#
# The SAME pin assignments apply to the tester board; only the RTL port
# directions differ, so this file can be shared between both projects.
#
# Straight-through 40-pin ribbon, pin N <-> pin N.
# !! Remove the conductors for RPi pins 1, 2, 4, 17 (3V3 / 5V) -- never tie
#    the supplies of two independently powered boards together.
# !! Connect all 8 grounds (RPi pins 6, 9, 14, 20, 25, 30, 34, 39).
#
# RPi pins 10 AND 12 are deliberately LEFT UNASSIGNED, so the clock on pin 11
# has quiet neighbours on BOTH sides in the ribbon.
#
# NOTE on RPi pin 13 (V7): the board XDC omits it (it lists rpio_02..26 +
# sd/sc = 27 GPIO), but the manual says 28 pins are connected, and this was
# settled empirically with rpi_probe -- jumpering 3V3 to header pin 13 drives
# the corresponding probe bit high. V7 IS connected. The board XDC is simply
# missing a line for GPIO27. Every other pin below is verified against
# C:\Xilinx\2025.2\data\boards\board_files\PYNQ-Z2 v1.0.xdc
#
# Also verified on hardware with rpi_probe: RPi pins 3, 5, 27, 28 carry
# PASSIVE pull-ups (each one drives cleanly to 0 when the FPGA sinks it),
# not active drivers. Safe for the four control inputs assigned there.
#
# Pmod A is NOT an alternative: all 8 of its pins (ja[0..7]) are the same FPGA
# balls as RPi pins, including the two pulled-high ID-EEPROM pins. Pmod B
# (W14 Y14 T11 T10 V16 W16 V12 W13) is independent if more I/O is ever needed.
#=============================================================================

#--- Clock (chip pin 26) -----------------------------------------------------
# RPi pin 11 = U7, close to a BUFG (clock-capable). Must carry clk.
set_property -dict {PACKAGE_PIN U7  IOSTANDARD LVCMOS33} [get_ports clk]

# Stage 1 target: 10 MHz. Raise later if you sweep higher.
create_clock -period 100.000 -name dut_clk [get_ports clk]

#--- Data bus (chip pins 1-16) -----------------------------------------------
# All 16 on CLEAN pins so pull behaviour is uniform across the bus.
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {Data_bus[0]}]   ;# chip 1  -> RPi 7
set_property -dict {PACKAGE_PIN V6  IOSTANDARD LVCMOS33} [get_ports {Data_bus[1]}]   ;# chip 2  -> RPi 8
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS33} [get_ports {Data_bus[2]}]   ;# chip 3  -> RPi 13
set_property -dict {PACKAGE_PIN U8  IOSTANDARD LVCMOS33} [get_ports {Data_bus[3]}]   ;# chip 4  -> RPi 15
set_property -dict {PACKAGE_PIN W6  IOSTANDARD LVCMOS33} [get_ports {Data_bus[4]}]   ;# chip 5  -> RPi 16
set_property -dict {PACKAGE_PIN Y7  IOSTANDARD LVCMOS33} [get_ports {Data_bus[5]}]   ;# chip 6  -> RPi 18
set_property -dict {PACKAGE_PIN V8  IOSTANDARD LVCMOS33} [get_ports {Data_bus[6]}]   ;# chip 7  -> RPi 19
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {Data_bus[7]}]   ;# chip 8  -> RPi 21
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports {Data_bus[8]}]   ;# chip 9  -> RPi 22
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports {Data_bus[9]}]   ;# chip 10 -> RPi 23
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {Data_bus[10]}]  ;# chip 11 -> RPi 24
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {Data_bus[11]}]  ;# chip 12 -> RPi 26
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {Data_bus[12]}]  ;# chip 13 -> RPi 29
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {Data_bus[13]}]  ;# chip 14 -> RPi 31
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {Data_bus[14]}]  ;# chip 15 -> RPi 32
set_property -dict {PACKAGE_PIN W8  IOSTANDARD LVCMOS33} [get_ports {Data_bus[15]}]  ;# chip 16 -> RPi 33

# The bus genuinely floats during turnaround (neither side drives for a cycle).
# A KEEPER holds the last driven value -- prevents a mid-rail float without
# fighting either driver, and without ever faking plausible-looking data.
set_property PULLTYPE KEEPER [get_ports {Data_bus[*]}]

#--- Status outputs + bus control (chip pins 17-21) --------------------------
# BIST_PASS deliberately on a CLEAN pin: a pull-up would make a broken or
# disconnected pin read PASS, hiding a dead chip.
# Bus_dir likewise clean: floating high would make the chip drive the bus.
set_property -dict {PACKAGE_PIN Y8  IOSTANDARD LVCMOS33} [get_ports BIST_PASS]    ;# chip 17 -> RPi 35
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports BIST_DONE]    ;# chip 18 -> RPi 36
set_property -dict {PACKAGE_PIN W9  IOSTANDARD LVCMOS33} [get_ports Hit]          ;# chip 19 -> RPi 37
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports Bus_load_en]  ;# chip 20 -> RPi 38
set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports Bus_dir]      ;# chip 21 -> RPi 40

# ONE BITSTREAM FOR BOTH TEST STAGES.
# In the 7-wire BIST stage these two are not connected, and Chip.sv uses them
# outside the BIST mux (dir <= Bus_dir; load_en <= Bus_load_en), so they would
# float -- a mid-rail CMOS input draws crowbar current, and dir=1 would make
# the chip drive Data_bus unbidden.
#
# A weak internal pull-down parks both LOW when unwired. Once the full 26-wire
# harness is connected the tester's output overcomes it easily, so the same
# bitstream serves BIST and normal-mode testing with no rebuild.
#
# CE and WC need no equivalent: Cache_BIST_Top muxes them out whenever
# BIST_EN is high, so their floating state during BIST is harmless.
set_property PULLTYPE PULLDOWN [get_ports Bus_dir]
set_property PULLTYPE PULLDOWN [get_ports Bus_load_en]

#--- Control inputs (chip pins 22-25) ----------------------------------------
# These four sit on the board's PULLED-HIGH pins (RPi 3, 5, 27, 28).
# Safe here: all are actively driven by the tester, and their default-high
# state before configuration is benign (rst_n high = not reset).
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports WC]           ;# chip 22 -> RPi 3  (pull-high)
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports CE]           ;# chip 23 -> RPi 5  (pull-high)
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports BIST_EN]      ;# chip 24 -> RPi 27 (pull-high)
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports rst_n]        ;# chip 25 -> RPi 28 (pull-high)

#--- Unused pins -------------------------------------------------------------
# Leave unused I/O high-Z rather than driven, so nothing contends on the ribbon.
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]
