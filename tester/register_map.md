# Register Map — Tester FPGA

AXI4-Lite slave, 32-bit registers, word-aligned.
Base address assigned by the Vivado block design (typically `0x43C0_0000`).

This file is the contract between the Python driver and the RTL.
**Change it here first**, then update both sides.

---

## Summary

| Offset | Name | Access | Purpose |
|--------|------|--------|---------|
| `0x00` | `CTRL`      | W   | opcode + START |
| `0x04` | `STATUS`    | R   | busy / done / error / latched DUT outputs |
| `0x08` | `CLKDIV`    | RW  | DUT clock frequency |
| `0x0C` | `ADDR`      | RW  | `Addr[15:0]`, `Write_addr[4:0]` |
| `0x10` | `WDATA0`    | RW  | write data `[31:0]` |
| `0x14` | `WDATA1`    | RW  | write data `[63:32]` |
| `0x18` | `WDATA2`    | RW  | write data `[95:64]` |
| `0x1C` | `WDATA3`    | RW  | write data `[127:96]` |
| `0x20` | `RDATA0`    | R   | read data `[31:0]` |
| `0x24` | `RDATA1`    | R   | read data `[63:32]` |
| `0x28` | `RDATA2`    | R   | read data `[95:64]` |
| `0x2C` | `RDATA3`    | R   | read data `[127:96]` |
| `0x30` | `TIMING`    | RW  | tunable sequence delays |
| `0x34` | `CAPT_CTRL` | RW  | trace buffer arm / status |
| `0x38` | `CAPT_DATA` | R   | trace readout (auto-increment) |
| `0x3C` | `ID`        | R   | magic + version |

---

## `0x00` CTRL (write-only)

| Bits | Field | Notes |
|------|-------|-------|
| `[3:0]`  | `OPCODE` | see table below |
| `[8]`    | `START`  | write 1 to launch; self-clearing |
| `[16]`   | `ABORT`  | write 1 to force sequencer back to IDLE |

### Opcodes

| Code | Name | Action |
|------|------|--------|
| `0x0` | `NOP`      | no operation |
| `0x1` | `RESET`    | hold `rst_n` low for `TIMING.RST_LEN` ticks |
| `0x2` | `RUN_BIST` | assert `BIST_EN`, poll `BIST_DONE`, latch flags |
| `0x3` | `WRITE`    | 10-tick S2P shift + `load_en` pulse |
| `0x4` | `READ`     | compare + turnaround + 8-tick capture |

Writing `CTRL` while `STATUS.BUSY` is set is ignored (use `ABORT` first).

---

## `0x04` STATUS (read-only)

| Bits | Field | Notes |
|------|-------|-------|
| `[0]`    | `BUSY`          | sequencer not in IDLE |
| `[1]`    | `DONE`          | last operation completed |
| `[2]`    | `TIMEOUT`       | `BIST_DONE` never arrived, or op exceeded limit |
| `[3]`    | `OE_VIOLATION`  | **sticky** — our driver overlapped the chip's; cleared by `RESET` |
| `[8]`    | `HIT`           | latched `Hit` from last READ |
| `[9]`    | `BIST_DONE`     | latched |
| `[10]`   | `BIST_PASS`     | latched |
| `[19:16]`| `STATE`         | sequencer state, for debug |

`OE_VIOLATION` is computed as `fpga_oe && chip_oe_predicted`, where
`chip_oe_predicted` is `Bus_dir` delayed one tick (matching the registered
`dir` in `Chip.sv`). It catches FSM turnaround bugs on hardware.

---

## `0x08` CLKDIV

| Bits | Field |
|------|-------|
| `[15:0]` | `DIV` — sys_clk cycles per DUT half-period |

```
f_dut = 125 MHz / (2 x DIV)
```

| DIV | f_dut | Use |
|-----|-------|-----|
| 63 | ~1 MHz   | first bring-up |
| 12 | ~5.2 MHz | Stage 1 default |
| 5  | 12.5 MHz | |
| 3  | ~20.8 MHz| near ribbon limit |
| 2  | 31.25 MHz| |

Board I/O limit is ~50 MHz; an unterminated ribbon will cap you lower.

---

## `0x0C` ADDR

| Bits | Field |
|------|-------|
| `[15:0]`  | `ADDR` — the `Addr` word (sent **last** in the S2P sequence) |
| `[20:16]` | `WRITE_ADDR` — 5-bit cache line index |

---

## `0x10`-`0x1C` WDATA, `0x20`-`0x2C` RDATA

128-bit value, little-endian word order: `WDATA0` holds bits `[31:0]`.

---

## `0x30` TIMING

Tunable during bring-up — exact values are not known until hardware runs.

| Bits | Field | Default | Notes |
|------|-------|---------|-------|
| `[3:0]`  | `RST_LEN`    | 8 | ticks to hold `rst_n` low |
| `[7:4]`  | `CACHE_WAIT` | 2 | ticks after compare-load before P2S load (CAM has ~1 cycle latency) |
| `[11:8]` | `TURN`       | 2 | dead ticks on each bus turnaround (**minimum 1**) |

---

## `0x34` CAPT_CTRL

| Bits | Field | Notes |
|------|-------|-------|
| `[0]`     | `ARM`   | write 1 to arm and reset the read pointer |
| `[1]`     | `FULL`  | (read) buffer full |
| `[6:4]`   | `TRIG`  | 0 = on START, 1 = on `load_en`, 2 = on turnaround |
| `[31:16]` | `COUNT` | (read) valid samples |

## `0x38` CAPT_DATA (read, auto-increment)

One recorded tick per read:

| Bits | Field |
|------|-------|
| `[15:0]` | `Data_bus` |
| `[16]` | `Hit` |
| `[17]` | `BIST_DONE` |
| `[18]` | `BIST_PASS` |
| `[19]` | `fpga_oe` |
| `[20]` | `Bus_dir` |
| `[21]` | `Bus_load_en` |
| `[25:22]` | sequencer `STATE` |

Depth: 1024 ticks (one BRAM). This replaces the waveform viewer.

## `0x3C` ID (read-only)

| Bits | Field |
|------|-------|
| `[23:0]`  | `0xC0FFEE` |
| `[31:24]` | version |

First build returns `0x01C0FFEE`.

---

## Operation sequence

Every command follows the same handshake:

```python
# 1. load operands
write(ADDR,   addr | (wr_addr << 16))
write(WDATA0, data & 0xFFFFFFFF)
...
# 2. launch
write(CTRL, OPCODE | START)
# 3. wait
while read(STATUS) & BUSY: pass
# 4. check
assert not (read(STATUS) & (TIMEOUT | OE_VIOLATION))
# 5. collect
result = read(RDATA0) | (read(RDATA1) << 32) | ...
```

Python never participates in timing. One command in, one result out.

### BIST is single-shot per reset

`misr_en_delayed` in `BIST_Controller.sv` is only cleared by `rst_n`, so the
MISR free-runs after the first pass and any re-run computes a wrong signature.

**Always issue `RESET` immediately before `RUN_BIST`.**

---

## S2P word ordering (the #1 gotcha)

`S2P` shifts in from the top (`parallel <= {S_in, parallel[159:16]}`), so the
**first** word sent lands at the **bottom**. The sequencer must emit:

| Tick | Word |
|------|------|
| 0 | `WDATA0[15:0]`  -> `Data[15:0]` |
| 1 | `WDATA0[31:16]` |
| 2 | `WDATA1[15:0]` |
| 3 | `WDATA1[31:16]` |
| 4 | `WDATA2[15:0]` |
| 5 | `WDATA2[31:16]` |
| 6 | `WDATA3[15:0]` |
| 7 | `WDATA3[31:16]` -> `Data[127:112]` |
| 8 | `WRITE_ADDR` (low 5 bits used) |
| 9 | `ADDR` |
| 10 | `Bus_load_en` pulse |

`P2S` reads back in the same order: first captured word is `Data[15:0]`.

---

## Turnaround rule

`Chip.sv` registers `dir`, so the chip starts and stops driving **one tick
after** `Bus_dir` changes.

```
hand bus to chip:   drop fpga_oe  ->  raise Bus_dir   -> wait TURN ticks
take bus back:      drop Bus_dir  ->  wait TURN ticks -> raise fpga_oe
```

Invariant: `fpga_oe` and `chip_oe` are never both true.
`STATUS.OE_VIOLATION` exists to catch breaches of this on hardware.
