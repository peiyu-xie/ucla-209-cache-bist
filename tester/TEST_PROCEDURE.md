# Test procedure — emulator and real chip

Lab reference. Stage 1 (emulator) and Stage 2 (silicon) use the **same tester
bitstream and the same commands**. Only what sits on the other end changes.

---

## 0. The two VIO primitives

Everything below is built from these. Set all probe radices to **Hex**.

| Probe | Meaning |
|---|---|
| `probe_out0` | `reg_addr` — register byte offset |
| `probe_out1` | `reg_wdata` — data to write |
| `probe_out2` | `reg_we` — write trigger |
| `probe_in0` | `reg_rdata` — value read back |

**WRITE a register**
1. `probe_out0` = address
2. `probe_out1` = data
3. `probe_out2` = `1`
4. `probe_out2` = `0`

**READ a register**
1. `probe_out0` = address
2. read `probe_in0` (combinational — the value appears immediately)

> Leaving `probe_out2` at 1 does nothing extra. The RTL converts the level into
> a single-cycle pulse, so one 0→1→0 performs exactly one write.

### Register quick reference

| Addr | Name | R/W |
|---|---|---|
| `0x00` | CTRL — `[3:0]` opcode, `[8]` START | W |
| `0x04` | STATUS | R |
| `0x08` | CLKDIV | RW |
| `0x0C` | ADDR — `[15:0]` addr, `[20:16]` waddr | RW |
| `0x10`–`0x1C` | WDATA0–3 | RW |
| `0x20`–`0x2C` | RDATA0–3 | R |
| `0x3C` | MAGIC = `0x00C0FFEE` | R |

### Opcodes (write to `0x00`, OR with `0x100` to start)

| Value | Op |
|---|---|
| `0x101` | RESET |
| `0x102` | RUN_BIST |
| `0x103` | WRITE |
| `0x104` | READ |
| `0x105` | ABORT |

### STATUS decode (`0x04`)

| Bit | Name |
|---|---|
| 0 | busy |
| 1 | done |
| 2 | **timeout** |
| 3 | hit |
| 4 | bist_done |
| 5 | bist_pass |

| Value | Meaning |
|---|---|
| **`0x32`** | **BIST passed** |
| `0x12` | BIST ran and **FAILED** |
| `0x06` | **timeout** — DUT never responded |
| `0x0A` | READ done, **hit** |
| `0x02` | op done, no hit |
| odd number | still busy — keep polling |

### CLKDIV (`0x08`)

`f = 125 / (2 × (CLKDIV + 1))` MHz, or set bit 7 for the 95 MHz MMCM.

| Value | f |
|---|---|
| `62` | 1.0 MHz ← bring-up |
| `11` | 5.2 MHz |
| `5` | 10.4 MHz ← routine |
| `2` | 20.8 MHz |
| `1` | 31.3 MHz |
| `0` | 62.5 MHz |
| `0x80` | **95 MHz** (MMCM) |

**Only change CLKDIV while `busy = 0`.** Changing the divider mid-operation
produces an irregular clock edge that can skip or repeat an FSM state.

---

# STAGE 1 — Emulator

## Setup

| Board | Bitstream | Label it |
|---|---|---|
| Tester | `tester_top.bit` | **TESTER** |
| Emulator | `Chip.bit` | **EMULATOR** |

Both on micro-USB. Hardware Manager shows two `xc7z020_1` targets — they look
identical, so label the boards physically. Programming the wrong one wastes an
afternoon on a failure that makes no sense.

Open the VIO **on the tester**.

## Step 0 — prove the transport (no cable)

```
probe_out0 = 0x3C   ->   probe_in0 = 0x00C0FFEE
```

Until this returns, nothing else you read means anything. It validates VIO,
JTAG, the address decode and the clock, with zero DUT involvement.

This is the digital version of the proofing step on page 2 of the lecture
notes: connect the RF generator to the spectrum analyser and prove both
instruments work *before* testing your PLL.

**If it fails:** wrong board selected; VIO probe widths wrong (check
`probe_in0` is 32 bits, not 1); bitstream not actually reloaded.

## Step 1 — BIST (5 wires + ground)

| Wire | Both boards, RPi pin |
|---|---|
| clk | 11 |
| rst_n | 28 |
| BIST_EN | 27 |
| BIST_DONE | 36 |
| BIST_PASS | 35 |
| **GND** | 6 or 9 |

| # | addr | wdata | |
|---|---|---|---|
| 1 | `0x08` | `0x3E` | CLKDIV = 62 → 1 MHz |
| 2 | `0x00` | `0x102` | RUN_BIST |
| 3 | `0x04` | — | poll until bit0 = 0 |

**Expect `STATUS = 0x32`.**

You do not need to reset first — `OP_BIST` pulses `rst_n` itself, because BIST
is single-shot per reset (`misr_en_delayed` latches high and the MISR only
clears on `rst_n`, so re-running without a reset always computes a garbage
signature and a good chip reads FAIL).

| Result | Means |
|---|---|
| `0x32` | **Stage 1 milestone reached** |
| `0x12` | BIST ran, signature mismatch |
| `0x06` | timeout — DUT never raised BIST_DONE |
| stays busy | clock not reaching the DUT |

## Step 2 — cache write / read (all 26 wires)

Same vector as `Chip_tb.sv`, so you can compare against the simulation.

| # | addr | wdata | |
|---|---|---|---|
| 1 | `0x08` | `0x05` | CLKDIV = 5 → 10.4 MHz |
| 2 | `0x0C` | `0x000AAAAA` | waddr = 10, addr = `0xAAAA` |
| 3 | `0x10` | `0xDDEEFF00` | WDATA0 = Data[31:0] |
| 4 | `0x14` | `0x99AABBCC` | WDATA1 |
| 5 | `0x18` | `0x55667788` | WDATA2 |
| 6 | `0x1C` | `0x11223344` | WDATA3 = Data[127:96] |
| 7 | `0x00` | `0x103` | **WRITE** → poll busy |
| 8 | `0x0C` | `0x0000AAAA` | address to look up |
| 9 | `0x00` | `0x104` | **READ** → poll busy |

Then read back:

| addr | expect |
|---|---|
| `0x20` | `0xDDEEFF00` |
| `0x24` | `0x99AABBCC` |
| `0x28` | `0x55667788` |
| `0x2C` | `0x11223344` |
| `0x04` | bit3 (**hit**) = 1 |

**If the data is shifted or rotated**, the `S_RD_WAIT` constant is wrong. See
"Measuring the read latency" below.

## Step 3 — find the setup's ceiling

Only after Steps 1 and 2 both pass. Change one variable at a time.

| CLKDIV | Re-run |
|---|---|
| `2` → `1` → `0` | BIST and WRITE/READ |
| `0x80` (95 MHz) | **BIST only** |

Record where each stops working. **Those ceilings belong to the ribbon and the
headers, not to the chip** — the board's I/O guidance is ~50 MHz and the cable
is unterminated.

BIST goes higher than the bus because only the *clock* crosses the cable during
BIST: `Cache_BIST_Top` muxes out `CE`, `WC`, `Addr_norm` and `Data_i`, so all
16 bus lines sit idle. The bus test switches 19 lines at once.

> **Worth doing:** repeat the sweep with a visibly shorter cable. If the ceiling
> moves, you have proven the cable is the limit rather than asserting it. That
> control experiment is worth a paragraph in the report.

## Measuring the read latency

`S_RD_WAIT` waits 2 cycles. That was derived, not measured — `Chip.sv` passes
P2S output through its `s_out` register, and our input is double-synchronised.

1. Add `(* mark_debug = "true" *)` to `state`, `cnt`, `data_i`, `dut_data_oe`
2. Synthesis → **Set Up Debug**, clock = **`seq_clk`** (one sample per DUT cycle)
3. Trigger on `dut_bus_load_en` rising
4. Count cycles until real data appears on `data_i`
5. Adjust the constant, rebuild

Do this once in Stage 1. The number may shift in Stage 2 when level shifters
add propagation delay.

## Use the emulator's visibility while you still have it

The emulator is an FPGA running your RTL, so an ILA inside it can probe
`cache_bist_top_inst/controller_inst/state`, `signature`, `misr_en_wire`,
`S2P_inst/parallel` — near-simulation insight into *why* something failed.

**The real chip has 10 output pins and nothing else.** Anything you can
diagnose in Stage 1, diagnose there.

---

# STAGE 2 — Real chip

## What changes

| | Emulator | Chip |
|---|---|---|
| I/O level | 3.3 V | **1.8 V** — level shifters mandatory |
| Supply | USB | **bench supply, adjustable, with current readout** |
| `shifter_oe_n` | unused | **drives the bus shifters' OE** |
| Internal visibility | ILA | **none** |

| | Unchanged |
|---|---|
| Tester bitstream | same |
| All commands and addresses | same |
| Expected values | same |

`shifter_oe_n` controls **only the bus shifters (U3/U4)**. The control and
status shifters (U1, U2) stay enabled — the chip needs its clock and reset at
all times.

## Power-up — the order matters

1. Bench supply: **1.8 V**, current limit **~50 mA**, output **OFF**
2. Connect **grounds first** — FPGA header GND, supply GND, DUT board GND
3. Power the FPGA, load the tester bitstream
   (`shifter_oe_n` resets high, so the bus shifters are high-Z)
4. Turn the **1.8 V on** and immediately check the current
5. Only then run any command

**Shut down in reverse.**

| Current at step 4 | |
|---|---|
| near 0 | not connected, or supply off |
| a few mA | **normal for a quiescent 180 nm die** |
| at the limit | **short — power off now**, check for solder bridges |

Supply current is your single best health indicator. Keep the meter visible
during every run.

## First contact

Exactly Step 0 → Step 1 from Stage 1, at **CLKDIV = 62 (1 MHz)**.

Nothing else until `STATUS = 0x32`. If BIST passes on silicon, the die is
alive, the clock tree works, the cache and the MISR work, and your whole
harness is verified against real hardware.

| Result | First thing to check |
|---|---|
| `0x06` timeout | scope the clock **at the chip pin**; check reset reaches it |
| `0x12` fail | lower the frequency; check supply isn't drooping under BIST activity |
| current spike | power off |

Scope VDD at the die while BIST runs. Supply collapse during the switching
activity looks exactly like a logic failure — the lecture notes flag this on
page 1 ("use oscilloscope to debug signals, **including supply**").

## Shmoo

Your sign-off corners, from the `.lib` files:

| Corner | Process | Temp | Voltage |
|---|---|---|---|
| bc | FF | 0 °C | **1.98 V** |
| tc | TT | 25 °C | **1.80 V** |
| wc | SS | 125 °C | **1.62 V** |

Sweep **VDD 1.62 → 1.98 V** against frequency, recording BIST pass/fail.

- Mark your level shifter's **VCCB minimum** on the plot. If it is an
  LVC8T245 (1.65 V) it gives out before the chip does, and that failure is the
  shifter's, not the silicon's. An AVC8T245 (1.2 V) clears the whole range.
- You are at **25 °C**, so you only hit the voltage axis of the `wc` corner,
  never its temperature. Expect to beat the `wc` simulation.
- The corners are *sign-off conditions*, not a guarantee about your particular
  die. Landing between `wc` and `bc` is normal.

## Report the two numbers separately

**BIST and the bus cover different logic.** `Cache_BIST_Top` muxes out
`Addr_norm`, `Data_i`, `CE` and `WC` during BIST, so S2P, P2S and the three
pipeline registers in `Chip.sv` are **never exercised by BIST**.

| Passing at f | Proves |
|---|---|
| BIST | cache, TPG, MISR, BIST controller |
| WRITE/READ | S2P, P2S, bus interface, turnaround |

"BIST passes at 95 MHz" does **not** mean the chip is usable at 95 MHz. State
both, and state what limited each.

---

## Troubleshooting

| Symptom | Look at |
|---|---|
| MAGIC wrong | wrong board; VIO widths; bitstream not reloaded |
| busy never clears | clock not reaching DUT — scope RPi 11 at the far end |
| `timeout` on BIST | clock or reset wire; BIST_DONE wire; DUT unpowered |
| BIST fails, bus works | lower frequency; check supply under load |
| read data rotated | `S_RD_WAIT` constant — measure with ILA |
| read data all `0xFFFF` | bus not driven — check `Bus_dir` wire and turnaround |
| read data all `0x0000` | shifters disabled, or bus wires not connected |
| intermittent at high f | cable. Shorten it, or drop CLKDIV |
| works slow, fails fast | expected — find the ceiling and record it |

**One variable at a time.** Frequency, voltage, cable length — change one,
re-run, record. That discipline is what makes the numbers mean anything.
