# Driver FPGA (tester board)

Stage-1 test harness for the EE209BS cache+BIST chip. Drives the emulator
board now, the real chip later — the design does not change between them.

| File | What it is |
|---|---|
| `bus_sequencer.sv` | the FSM — owns the DUT clock and all protocol timing |
| `tester_top.sv` | top level: IOBUFs + VIO transport |
| `tester_top.xdc` | pin constraints, verified on hardware |
| `REGISTER_MAP.md` | the PC↔FPGA contract (in `C:\FPGA\Cache_tester\`) |

---

## Build

1. New RTL project, part **`xc7z020clg400-1`**
2. Add `bus_sequencer.sv`, `tester_top.sv`, `tester_top.xdc`
3. Create **both** IP cores. The design will not elaborate without them —
   `tester_top.sv` instantiates `vio_reg` and `clk_wiz_95` by name.

### 3a. Clocking Wizard — component name must be `clk_wiz_95`

Generates the 95 MHz DUT clock (125 × 38/5 = 950 MHz VCO, ÷10 = 95.000 MHz
exactly). Just ask for 95.000 and the wizard finds M/D/O on its own.

```tcl
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_95
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ                {125.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  {95.000}  \
  CONFIG.USE_LOCKED                  {true}    \
  CONFIG.USE_RESET                   {true}    \
] [get_ips clk_wiz_95]
generate_target all [get_ips clk_wiz_95]
```

### 3b. VIO — component name must be `vio_reg`

Set it with Tcl, not the GUI table (the width/init cells silently revert if
you don't commit them before clicking OK):

```tcl
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_reg
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN        {1} \
  CONFIG.C_NUM_PROBE_OUT       {3} \
  CONFIG.C_PROBE_IN0_WIDTH     {32} \
  CONFIG.C_PROBE_OUT0_WIDTH    {6}  \
  CONFIG.C_PROBE_OUT1_WIDTH    {32} \
  CONFIG.C_PROBE_OUT2_WIDTH    {1}  \
  CONFIG.C_PROBE_OUT0_INIT_VAL {0x3C} \
  CONFIG.C_PROBE_OUT1_INIT_VAL {0x0}  \
  CONFIG.C_PROBE_OUT2_INIT_VAL {0x0}  \
] [get_ips vio_reg]
generate_target all [get_ips vio_reg]
```

Verify before building — this is the step that bit us on `rpi_probe`:

```tcl
puts "in0=[get_property CONFIG.C_PROBE_IN0_WIDTH [get_ips vio_reg]]"
```

4. Set `tester_top` as top, generate bitstream, program the **tester** board.

### Check the build

```tcl
open_run impl_1
puts "IOBUF = [llength [get_cells -hier -filter {REF_NAME =~ IOBUF*}]]"   ;# expect 16
puts "BUFG  = [llength [get_cells -hier -filter {REF_NAME =~ BUFG*}]]"    ;# expect >= 1
```

**IOBUF must be 16.** Anything else means the tristate did not reach real
pins and the bus will not work.

---

## Using it

Set `probe_out0` (address) and `probe_out1` (data), then pulse `probe_out2`
(`reg_we`) **0 → 1 → 0**. The RTL turns that level into a single-cycle write
pulse, so one toggle performs exactly one register write.

Set all probe radices to **Hex**.

### Milestone 0 — prove the transport (no cable needed)

```
probe_out0 = 0x3C        ->  probe_in0 reads 0x00C0FFEE
```

Until that returns, nothing else you read means anything. This is the digital
version of the proofing step on page 2 of the lecture notes: connect the RF
generator to the spectrum analyser and prove both instruments work before
testing your PLL.

### Milestone 1 — BIST against the emulator (5 wires + ground)

| Wire | Both boards, RPi pin |
|---|---|
| `clk` | 11 |
| `rst_n` | 28 |
| `BIST_EN` | 27 |
| `BIST_DONE` | 36 |
| `BIST_PASS` | 35 |
| **GND** | 6 or 9 — **do not skip** |

Then:

| Step | addr | wdata | |
|---|---|---|---|
| 1 | `0x08` | `62` | CLKDIV → ~1 MHz |
| 2 | `0x00` | `0x102` | CTRL = RUN_BIST \| START |
| 3 | `0x04` | — | poll until bit0 (`busy`) = 0 |
| 4 | `0x04` | — | bit4 `bist_done`, bit5 `bist_pass`, bit2 `timeout` |

**bit5 = 1 is Stage 1 complete.** Two boards, cable, clock, reset, BIST path
and MISR signature all verified.

`timeout = 1` means `BIST_DONE` never arrived — a dead link or a dead chip.
That is a completely different diagnosis from "ran and failed", which is
exactly why the bit exists. `Chip_tb.sv` uses `wait(BIST_DONE)`, fine in
simulation; on silicon it would hang forever.

### Milestone 2 — cache write/read (all 26 wires)

```
0x0C = {waddr[20:16], addr[15:0]}
0x10..0x1C = write data, 4 × 32 bits
0x00 = 0x103        WRITE | START      -> poll busy
0x00 = 0x104        READ  | START      -> poll busy
0x20..0x2C          read data back
0x04 bit3           hit
```

---

## Frequency sweep

```
f_dut = 125 / (2 * (CLKDIV + 1))  MHz
```

| CLKDIV | ≈ |
|---|---|
| 62 | 1.0 MHz |
| 11 | 5.2 MHz |
| 5 | 10.4 MHz |
| 2 | 20.8 MHz |

Raise it until BIST stops passing. **That ceiling belongs to the ribbon, not
the chip** — the PYNQ-Z2 I/O limit is ~50 MHz and an unterminated ribbon will
give out well before that. Useful to know before Stage 2; not a silicon
result. Keep the two numbers in separate columns.

---

## The one number to measure, not derive

`S_RD_WAIT` in `bus_sequencer.sv` waits 2 ticks for read data to come back.
That covers `Chip.sv`'s `s_out` pipeline register plus our input
synchronisers, but it is easier to measure than to reason about.

Put an **ILA** on `dut_data_bus`, `dut_bus_dir`, `dut_bus_load_en` and the
FSM state, trigger on `dut_bus_load_en` rising, and count the ticks until
real data appears. Adjust the constant to match.

---

## Stage 1 sees more than Stage 2 will

The emulator is an FPGA running your RTL, so you can put an ILA **inside**
`Chip` — probe `cache_bist_top_inst/controller_inst/state`, `signature`,
`misr_en_wire`. Near-simulation visibility into why a BIST failed.

The real chip has 10 output pins and nothing else.

**So anything you can diagnose in Stage 1, diagnose there.**

---

## Rules the hardware enforces for you

- **BIST is single-shot per reset.** `misr_en_delayed` latches high and the
  MISR only clears on `rst_n`, so re-triggering without a reset always
  computes a garbage signature and clears `pass_fail` — a good chip would
  read FAIL. `OP_BIST` pulses reset itself rather than trust the caller.
- **The address goes last on a WRITE.** S2P is a 160-bit shifter loaded from
  the top, so the first word sent lands at the bottom: Data[15:0] …
  Data[127:112], then Write_addr, then Addr.
- **Turnaround.** `Chip.sv` registers `dir`, so the chip starts and stops
  driving one tick after `Bus_dir` changes. `S_TURN_A` / `S_TURN_B` exist to
  guarantee `fpga_oe` and `chip_oe` are never both true. Between two FPGAs an
  overlap is survivable; against the real 1.8 V chip through level shifters
  it is not.
