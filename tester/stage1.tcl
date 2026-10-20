#=============================================================================
# stage1.tcl -- EE209BS Stage 1 bring-up, driven from the Vivado Tcl console
#
#   source {C:/.../driver_fpga/stage1.tcl}
#   t_connect
#   t_stage1
#
# Host-side only: nothing here depends on which copy of the RTL Vivado built.
# Register map and expected values follow TEST_PROCEDURE.md.
#=============================================================================

# Edit if your project moves. Leave as "" to use whatever PROBES.FILE the
# device already carries.
set T_LTX "C:/FPGA/Cache_tester/Cache_tester.runs/impl_1/tester_top.ltx"

set T_MAGIC 0x00C0FFEE

#--- connection -------------------------------------------------------------
# Re-run this after EVERY program_hw_devices or close/open target: those
# destroy the hw_vio object and leave your probe handles pointing at nothing.
proc t_connect {{ltx ""}} {
    global T_LTX t_vio t_addr t_wdata t_we t_rdata

    set dev [get_hw_devices xc7z020_1]
    if {[llength $dev] == 0} {
        error "no xc7z020_1 found -- open_hw_target first (device 0 is arm_dap_0)"
    }
    current_hw_device $dev

    if {$ltx eq ""} { set ltx $T_LTX }
    if {$ltx ne ""} { set_property PROBES.FILE $ltx $dev }
    if {[get_property PROBES.FILE $dev] eq ""} {
        error "PROBES.FILE is empty -- pass the .ltx path: t_connect {C:/.../tester_top.ltx}"
    }
    refresh_hw_device $dev

    set vios [get_hw_vios]
    if {[llength $vios] == 0} {
        error "no VIO visible -- wrong .ltx, wrong board, or device not programmed"
    }
    set t_vio [lindex $vios 0]

    set t_addr  [get_hw_probes reg_addr      -of_objects $t_vio]
    set t_wdata [get_hw_probes reg_wdata     -of_objects $t_vio]
    set t_we    [get_hw_probes reg_we_raw    -of_objects $t_vio]
    set t_rdata [get_hw_probes reg_rdata_mux -of_objects $t_vio]

    foreach p [list $t_addr $t_wdata $t_we] { set_property OUTPUT_VALUE_RADIX HEX $p }
    set_property INPUT_VALUE_RADIX HEX $t_rdata

    # Every output probe needs a parseable value before the first commit, or
    # commit_hw_vio throws "invalid string position" on the empty ones.
    set_property OUTPUT_VALUE 00       $t_addr
    set_property OUTPUT_VALUE 00000000 $t_wdata
    set_property OUTPUT_VALUE 0        $t_we
    commit_hw_vio $t_vio

    puts "connected to [get_property PART $dev], probes [file tail [get_property PROBES.FILE $dev]]"
}

#--- register primitives ----------------------------------------------------
proc t_rd {addr} {
    global t_vio t_addr t_rdata
    set_property OUTPUT_VALUE [format %02X [expr {$addr & 0x3F}]] $t_addr
    commit_hw_vio  $t_vio
    refresh_hw_vio $t_vio
    set s [get_property INPUT_VALUE $t_rdata]
    set v 0
    scan $s %x v
    return [expr {$v & 0xFFFFFFFF}]
}

proc t_wr {addr data} {
    global t_vio t_addr t_wdata t_we
    set_property OUTPUT_VALUE [format %02X [expr {$addr & 0x3F}]]       $t_addr
    set_property OUTPUT_VALUE [format %08X [expr {$data & 0xFFFFFFFF}]] $t_wdata
    commit_hw_vio $t_vio
    set_property OUTPUT_VALUE 1 $t_we ; commit_hw_vio $t_vio
    set_property OUTPUT_VALUE 0 $t_we ; commit_hw_vio $t_vio
}

proc t_poll {{tries 100}} {
    set s 1
    for {set i 0} {$i < $tries} {incr i} {
        set s [t_rd 0x04]
        if {($s & 1) == 0} { return $s }
    }
    error [format "busy never cleared (STATUS=%02X) -- clock not reaching the DUT?" $s]
}

proc t_decode {s} {
    set f {}
    if {$s & 0x01} { lappend f busy }
    if {$s & 0x02} { lappend f done }
    if {$s & 0x04} { lappend f TIMEOUT }
    if {$s & 0x08} { lappend f hit }
    if {$s & 0x10} { lappend f bist_done }
    if {$s & 0x20} { lappend f bist_pass }
    if {[llength $f] == 0} { return "(all clear)" }
    return [join $f " "]
}

#--- steps ------------------------------------------------------------------
proc t_step0 {} {
    global T_MAGIC
    set m [t_rd 0x3C]
    if {$m == $T_MAGIC} {
        puts [format "Step 0   MAGIC %08X   PASS" $m]
        return 1
    }
    puts [format "Step 0   MAGIC %08X   FAIL -- expected %08X" $m $T_MAGIC]
    if {$m == ($T_MAGIC >> 16)} {
        puts "         readback is shifted >>16: stale probe file. Re-run t_connect,"
        puts "         or close_hw_target / open_hw_target and t_connect again."
    }
    return 0
}

proc t_step1 {{clkdiv 0x3E}} {
    t_wr 0x08 $clkdiv
    t_wr 0x00 0x102
    set s [t_poll]
    set verdict "UNEXPECTED"
    # bit3 (hit) is latched from the last READ and BIST never clears it
    if {($s & ~0x08) == 0x32} { set verdict "PASS" }
    if {$s & 0x04}  { set verdict "TIMEOUT -- DUT never raised BIST_DONE" }
    if {($s & 0x30) == 0x10} { set verdict "FAIL -- signature mismatch" }
    puts [format "Step 1   BIST  STATUS %02X   %-12s  \[%s\]" $s $verdict [t_decode $s]]
    return $s
}

proc t_step2 {{clkdiv 0x05}} {
    t_wr 0x08 $clkdiv

    t_wr 0x0C 0x000AAAAA
    t_wr 0x10 0xDDEEFF00
    t_wr 0x14 0x99AABBCC
    t_wr 0x18 0x55667788
    t_wr 0x1C 0x11223344
    t_wr 0x00 0x103
    set sw [t_poll]

    t_wr 0x0C 0x0000AAAA
    t_wr 0x00 0x104
    set sr [t_poll]

    set r {}
    foreach a {0x20 0x24 0x28 0x2C} { lappend r [t_rd $a] }

    puts [format "Step 2   WRITE STATUS %02X   READ STATUS %02X  \[%s\]" $sw $sr [t_decode $sr]]
    foreach a {0x20 0x24 0x28 0x2C} v $r { puts [format "         %s  %08X" $a $v] }
    puts "         => [t_verdict $r $sr]"
    return $r
}

# Splits the read path from the write path. After a chip reset every tag in
# cache_logic is 0xFFFF, so a READ of 0xFFFF must hit line 0 with NO write:
#   A hit=1, B hit=0  -> read path good; the fault is in the WRITE
#   A hit=0           -> read path broken: WC (RPi 3), Bus_load_en (38), Hit (37)
#   A hit=1, B hit=1  -> Hit stuck high
proc t_diag {{clkdiv 0x3E}} {
    t_wr 0x08 $clkdiv
    t_wr 0x00 0x101
    t_poll

    foreach {tag expect} {0xFFFF 1 0x1234 0} {
        t_wr 0x0C $tag
        t_wr 0x00 0x104
        set s [t_poll]
        set r {}
        foreach a {0x20 0x24 0x28 0x2C} { lappend r [format %08X [t_rd $a]] }
        set hit [expr {($s >> 3) & 1}]
        set ok  [expr {$hit == $expect ? "ok" : "WRONG"}]
        puts [format "Diag     READ %04X  STATUS %02X  hit=%d (expect %d) %-5s  data %s" \
                  $tag $s $hit $expect $ok $r]
    }
}

# Debug: hold the bus in "chip drives" so the read path can be metered stage
# by stage. Writes the Step 2 vector, READs 0xAAAA (so S2P holds that tag),
# then parks: the chip drives Data[15:0] = 0xFF00 continuously.
# Clear with t_unpark before running anything else.
proc t_park {{clkdiv 0x3E}} {
    t_wr 0x08 $clkdiv
    t_wr 0x0C 0x000AAAAA
    t_wr 0x10 0xDDEEFF00
    t_wr 0x14 0x99AABBCC
    t_wr 0x18 0x55667788
    t_wr 0x1C 0x11223344
    t_wr 0x00 0x103 ; t_poll
    t_wr 0x0C 0x0000AAAA
    t_wr 0x00 0x104 ; t_poll
    t_wr 0x00 0x107 ; t_poll
    t_live
    puts "         parked: chip should drive 0xFF00 = D15..D8 high, D7..D0 low"
    puts "         meter J21.1 (Shifter_dir) 3.3 V, J20.5 (OE_n) 0 V, J18.1 (Bus_dir) 3.3 V"
    puts "         then the chip-side and header-side data pins.  t_unpark when done."
}

proc t_live {} {
    set v [t_rd 0x30]
    puts [format "LIVE     bus %04X  hit=%d  Bus_dir=%d shifter_dir=%d OE_n=%d load_en=%d CE=%d WC=%d" \
        [expr {$v & 0xFFFF}] [expr {($v>>16)&1}] [expr {($v>>20)&1}] [expr {($v>>21)&1}] \
        [expr {($v>>22)&1}] [expr {($v>>23)&1}] [expr {($v>>24)&1}] [expr {($v>>25)&1}]]
}

proc t_unpark {} { t_wr 0x00 0x105 ; t_poll ; t_live }

proc t_verdict {r s} {
    set ok    {0xDDEEFF00 0x99AABBCC 0x55667788 0x11223344}
    set early {0xFF000000 0xBBCCDDEE 0x778899AA 0x33445566}
    set late  {0xBBCCDDEE 0x778899AA 0x33445566 0x00001122}
    set keep  {0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA}
    set zero  {0 0 0 0}

    if {[t_eq $r $ok]}    { return "PASS -- Stage 1 milestone" }
    if {[t_eq $r $early]} { return "data one word LATE -- raise RDWAIT: t_rdwait [expr {[t_rdwait] + 1}]" }
    if {[t_eq $r $late]}  { return "data one word EARLY -- lower RDWAIT: t_rdwait [expr {[t_rdwait] - 1}]" }
    if {[t_eq $r $keep]} {
        if {$s & 0x08} { return "keeper held -- chip never drove. Bus_dir / RPi 40 open (hit=1 proves the rest)" }
        return "keeper held and no hit -- check Bus_dir (40), Bus_load_en (38), CE (5), WC (3)"
    }
    if {[t_eq $r $zero]} {
        if {$s & 0x08} { return "hit but zeros -- tag matched, stored data is zero; write data words did not arrive" }
        return "no hit -- the WRITE never landed"
    }
    return "unrecognised pattern -- compare against Chip_tb.sv"
}

#--- frequency sweep / repeatability (TEST_PLAN T12, criteria 13-14) --------
# Each bus iteration: RESET, WRITE a random 128-bit line to a random tag and
# line, READ it back (must hit, data must match), READ a different tag (must
# miss). Random data catches stuck and swapped bits a fixed vector can hide.
# Each BIST iteration: RUN_BIST, must report bist_done + bist_pass, no timeout.
#
#   t_sweep                       20 runs at every CLKDIV in the default list
#   t_sweep 1000 {0x05}           1000 runs at 10.4 MHz only (criterion 13)
#   t_sweep 20 {0x02} 0           no calibration: keep the current RDWAIT
#
# Calibration: above ~20 MHz the board's round trip (U6 on the clock, U1/U3 on
# the data) exceeds half a DUT period and read data arrives a whole cycle
# later -- intact, just late. Before counting, each step tries RDWAIT 1..6 on
# a few runs and keeps the best; the chosen value is printed. Report it: the
# extra cycles are board latency, not chip behaviour.
#
# Over JTAG a bus iteration takes ~1 s, so 1000 runs is ~15-20 min per step.
proc t_freq {d} {
    if {$d & 0x80} { return 95.0 }
    return [expr {125.0 / (2 * (($d & 0x7F) + 1))}]
}

proc t_rand16 {} { return [expr {int(rand() * 65536)}] }
proc t_rand32 {} { return [expr {([t_rand16] << 16) | [t_rand16]}] }

proc t_hexlist {l} {
    set o {}
    foreach v $l { lappend o [format %08X $v] }
    return [join $o " "]
}

proc t_bist_once {} {
    t_wr 0x00 0x102
    set s [t_poll]
    if {($s & 0x34) == 0x30} { return "" }
    return [format "STATUS %02X \[%s\]" $s [t_decode $s]]
}

proc t_bus_once {} {
    t_wr 0x00 0x101 ; t_poll                    ;# every tag back to 0xFFFF

    set tag [t_rand16]
    if {$tag == 0xFFFF} { set tag 0x1234 }      ;# 0xFFFF is the reset tag
    set miss [expr {$tag ^ 0x5A5A}]             ;# != tag; != 0xFFFF unless...
    if {$miss == 0xFFFF} { set miss 0xFFFE }    ;# ...tag was 0xA5A5
    set wa [expr {int(rand() * 32)}]
    set d {}
    foreach i {0 1 2 3} { lappend d [t_rand32] }

    t_wr 0x0C [expr {($wa << 16) | $tag}]
    foreach a {0x10 0x14 0x18 0x1C} v $d { t_wr $a $v }
    t_wr 0x00 0x103 ; t_poll

    t_wr 0x0C $tag
    t_wr 0x00 0x104
    set s [t_poll]
    set r {}
    foreach a {0x20 0x24 0x28 0x2C} { lappend r [t_rd $a] }
    if {!($s & 0x08)}   { return [format "line %d tag %04X: no hit" $wa $tag] }
    if {![t_eq $r $d]}  { return [format "line %d tag %04X: got %s  exp %s" \
                                      $wa $tag [t_hexlist $r] [t_hexlist $d]] }

    t_wr 0x0C $miss
    t_wr 0x00 0x104
    set s [t_poll]
    if {$s & 0x08}      { return [format "tag %04X: false hit" $miss] }
    return ""
}

# RDWAIT (0x34): read-latency calibration. No argument -> just read it.
proc t_rdwait {{w ""}} {
    if {$w ne ""} { t_wr 0x34 $w }
    return [t_rd 0x34]
}

# Try RDWAIT 1..6 with $tries bus runs each; set and return the best.
proc t_tune {{tries 3}} {
    set best 2 ; set besterr [expr {$tries + 1}]
    foreach w {1 2 3 4 5 6} {
        t_rdwait $w
        set e 0
        for {set i 0} {$i < $tries} {incr i} {
            if {[catch {t_bus_once} m] || $m ne ""} { incr e }
        }
        if {$e < $besterr} { set best $w ; set besterr $e }
    }
    t_rdwait $best
    return $best
}

proc t_sweep {{n 20} {divs {0x3E 0x0B 0x05 0x02 0x01 0x00 0x80}} {tune 1}} {
    expr {srand(209)}                           ;# same sequence every sweep
    puts [format "%-6s  %7s  %6s   %-13s  %-13s" CLKDIV MHz RDWAIT "BIST err/n" "BUS err/n"]
    foreach dv $divs {
        t_wr 0x08 $dv
        set w [expr {$tune ? [t_tune] : [t_rdwait]}]
        set eb 0 ; set eu 0 ; set fb "" ; set fu ""
        for {set i 0} {$i < $n} {incr i} {
            if {[catch {t_bist_once} m]} { set m "ERROR: $m" }
            if {$m ne ""} { incr eb ; if {$fb eq ""} { set fb $m } }
            if {[catch {t_bus_once} m]}  { set m "ERROR: $m" }
            if {$m ne ""} { incr eu ; if {$fu eq ""} { set fu $m } }
        }
        puts [format "0x%02X    %7.2f  %6d   %4d / %-6d  %4d / %-6d" $dv [t_freq $dv] $w $eb $n $eu $n]
        if {$fb ne ""} { puts "        first BIST fail: $fb" }
        if {$fu ne ""} { puts "        first BUS  fail: $fu" }
    }
    t_wr 0x08 0x3E                              ;# leave it at 1 MHz
    t_rdwait 2                                  ;# and the 1 MHz latency
    return ""
}

proc t_eq {a b} {
    foreach x $a y $b { if {$x != [expr {$y & 0xFFFFFFFF}]} { return 0 } }
    return 1
}

#--- the whole sequence -----------------------------------------------------
proc t_stage1 {} {
    if {![t_step0]} { puts "stopping: nothing below Step 0 is meaningful"; return }
    set s [t_step1]
    if {($s & ~0x08) != 0x32} { puts "stopping: fix BIST before touching the bus"; return }
    t_step2
}
