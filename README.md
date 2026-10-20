# ucla-209-cache-bist

A 32x128-bit fully associative cache with single-cycle CAM tag lookup and an
LFSR/MISR built-in self-test (BIST) engine, taken from RTL to GDSII in 180nm
CMOS and taped out — plus the FPGA tester built to bring the chip up in the
lab. UCLA EC ENGR 209AS/209BS (tapeout course sequence), 2026.

## The chip

| Block | File | What it does |
|---|---|---|
| Cache | `rtl/Cache.sv` | 32 entries x 128-bit data; a CAM priority engine compares every tag in parallel in one cycle |
| BIST controller | `rtl/BIST_Controller.sv` | FSM that sequences write and compare phases over the whole array |
| Test-pattern generator | `rtl/TPG.sv` | LFSR producing pseudo-random write data and addresses |
| Response compactor | `rtl/MISR.sv` | 129-bit multiple-input signature register; the final signature is the pass/fail check |
| Serial I/O | `rtl/P2S.sv`, `rtl/S2P.sv`, `rtl/bidirectional_P2S_S2P.sv` | Moves 128-bit words through the pin-limited pad frame |
| Top | `rtl/Cache_BIST_Top.sv`, `rtl/Chip.sv` | Integration and pad-level top |

**Verification.** Unit- and chip-level SystemVerilog testbenches (`*_tb.sv`)
with randomized address/data stimulus, plus `Chip_post_sim_tb.sv`, a
post-layout gate-level simulation back-annotated with SDF from Innovus.

**Implementation.** Hammer-driven Genus synthesis and Innovus place and route
(MMMC setup in `flow/mmmc_ori.tcl`), DRC/LVS, and post-layout parasitic
extraction before tapeout sign-off.

## The tester (`tester/`)

Silicon validation runs on a Xilinx Zynq board (PYNQ-Z2, `xc7z020clg400-1`).

- **`bus_sequencer.sv`** — 14-state FSM that owns the DUT clock and all
  protocol timing: reset, RUN_BIST, write, compare, and read with bus
  turnaround for the bidirectional data pins. It runs *in the DUT clock
  domain*, so read/write transactions stay cycle-accurate at any test
  frequency, up to the 95 MHz MMCM clock.
- **`tester_top.sv`** — clocking and transport: a 95 MHz MMCM and a
  programmable divider switched glitch-free by a BUFGMUX, the DUT clock
  forwarded off-chip through an ODDR, IOBUFs for the bidirectional bus, and
  synchronizers on the clock-domain crossings of the register interface.
- **`register_map.md`** — the PC-to-FPGA register contract (CTRL, STATUS,
  CLKDIV, ADDR, WDATA0-3, RDATA0-3, ...).
- **`TEST_PROCEDURE.md`** — step-by-step bring-up, first against a chip
  emulator, then against silicon with the same bitstream and commands.
- `tester_top.xdc`, `xdc/chip_emulator.xdc`, `stage1.tcl` — pin constraints and
  Vivado build script.

See `tester/README.md` for build instructions.

## Not included

- `Chip_ckt.v` — Innovus post-layout netlist; it instantiates TSMC standard
  cells (foundry PDK, NDA).
- Course handouts, pad-frame and tapeout documents (instructor / foundry material).
- The chip carrier PCB, which my project partner designed; the tester drives
  its level shifters through `shifter_oe_n` / `shifter_dir`.
- Generated build outputs (bitstreams, Vivado runs).

---

Author: Pei-yu Xie
