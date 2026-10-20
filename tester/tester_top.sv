//=============================================================================
// tester_top -- Stage-1 tester, VIO transport
//
// CLOCK ARCHITECTURE
//
//   sysclk 125 MHz ─┬─ divider ──> clk_slow  (1 .. 62.5 MHz)  ─┐
//                   │                                          ├─ BUFGMUX ─> seq_clk
//                   └─ MMCM ─────> clk_fast (95 MHz)          ─┘      │
//                                                                      ├─> bus_sequencer
//                                                                      └─> ODDR ─> dut_clk pin
//
// The sequencer runs ON seq_clk, and the very same clock is forwarded to the
// DUT. They are synchronous by construction at ANY frequency, so cycle-accurate
// bus read/write works at 95 MHz exactly as it does at 1 MHz.
//
// This is why an external function generator is NOT wanted: its clock would be
// asynchronous to the FSM, which would restrict high-speed testing to BIST only
// (BIST needs no cycle-accurate handshake; the bus protocol does).
//
//   CLKDIV[7]   = 0 -> divider,  f = 125 / (2 * (CLKDIV[6:0] + 1)) MHz
//               = 1 -> MMCM,     f = 95 MHz
//
// CLKDIV lives HERE, in the sysclk domain, because it controls the divider
// that generates seq_clk -- it cannot live in the domain it creates.
//
//-----------------------------------------------------------------------------
// VIO PROBES  (component name must be: vio_reg)
//
//   probe_in0  [31:0]  reg_rdata
//   probe_out0  [5:0]  reg_addr
//   probe_out1 [31:0]  reg_wdata
//   probe_out2  [0:0]  reg_we      pulse 0 -> 1 -> 0 to write
//
// FIRST MILESTONE, no cable needed:
//   probe_out0 = 0x3C   ->   probe_in0 reads 0x00C0FFEE
//=============================================================================

module tester_top (
    input  wire        sysclk,           // H16, 125 MHz

    output wire        dut_clk,          // RPi 11
    output wire        dut_rst_n,        // RPi 28
    output wire        dut_bist_en,      // RPi 27
    output wire        dut_ce,           // RPi 5
    output wire        dut_wc,           // RPi 3
    output wire        dut_bus_dir,      // RPi 40
    output wire        dut_bus_load_en,  // RPi 38
    output wire        shifter_oe_n,     // Pmod B -- Stage-2 level shifters
    output wire        shifter_dir,      // Pmod JB2 -- U1/U3 DIR, 1 = chip drives
    input  wire        dut_hit,          // RPi 37
    input  wire        dut_bist_done,    // RPi 36
    input  wire        dut_bist_pass,    // RPi 35
    inout  wire [15:0] dut_data_bus
);

    //=========================================================================
    // Power-on reset (sysclk domain)
    //=========================================================================
    reg [7:0] por_s = 8'hFF;
    always @(posedge sysclk) if (por_s != 8'd0) por_s <= por_s - 8'd1;
    wire rst_sys = (por_s != 8'd0);

    //=========================================================================
    // VIO -- stays on sysclk so it is responsive even when the DUT clock is
    // slow. A VIO clocked at 1 MHz would be painfully sluggish to poll.
    //=========================================================================
    wire [5:0]  reg_addr;
    wire [31:0] reg_wdata;
    wire        reg_we_raw;
    wire [31:0] rdata_seq;      // from the sequencer (seq_clk domain)
    reg  [31:0] rdata_sync0, rdata_sync1;
    reg  [31:0] reg_rdata_mux;

    vio_reg u_vio (
        .clk        (sysclk),
        .probe_in0  (reg_rdata_mux),
        .probe_out0 (reg_addr),
        .probe_out1 (reg_wdata),
        .probe_out2 (reg_we_raw)
    );

    //=========================================================================
    // CLKDIV register -- sysclk domain
    //
    // Written directly here rather than inside the sequencer, because it sets
    // the divider that produces the sequencer's own clock.
    //=========================================================================
    reg [7:0] clkdiv = 8'd62;              // ~1 MHz: slow and safe at power-on

    // Turn the VIO's level into a single-cycle write pulse in sysclk.
    reg [2:0] we_sys = 3'b000;
    always @(posedge sysclk) we_sys <= {we_sys[1:0], reg_we_raw};
    wire we_pulse_sys = we_sys[1] & ~we_sys[2];

    always @(posedge sysclk)
        if (we_pulse_sys && reg_addr[5:2] == 4'h2) clkdiv <= reg_wdata[7:0];

    //=========================================================================
    // Slow clock: divide sysclk
    //=========================================================================
    reg [6:0] div_cnt   = 7'd0;
    reg       clk_div_r = 1'b0;

    always @(posedge sysclk) begin
        if (div_cnt >= clkdiv[6:0]) begin
            div_cnt   <= 7'd0;
            clk_div_r <= ~clk_div_r;
        end else begin
            div_cnt <= div_cnt + 7'd1;
        end
    end

    wire clk_slow;
    BUFG bufg_slow (.I(clk_div_r), .O(clk_slow));

    //=========================================================================
    // Fast clock: MMCM, 125 x 38/5 = 950 MHz VCO, /10 = 95.000 MHz exactly
    //
    // Generate with the Clocking Wizard, component name clk_wiz_95:
    //   input  125 MHz (sysclk)
    //   output  95 MHz (clk_fast)
    // The wizard finds M=38 D=5 O=10 on its own -- just type 95.000.
    //=========================================================================
    wire clk_fast, mmcm_locked;

    clk_wiz_95 u_mmcm (
        .clk_in1  (sysclk),
        .clk_out1 (clk_fast),
        .locked   (mmcm_locked),
        .reset    (1'b0)
    );

    //=========================================================================
    // Clock select -- BUFGMUX switches glitch-free, and both sources run
    // continuously, which is what makes that guarantee hold.
    //=========================================================================
    wire seq_clk;
    BUFGMUX bufgmux_seq (
        .I0 (clk_slow),
        .I1 (clk_fast),
        .S  (clkdiv[7]),
        .O  (seq_clk)
    );

    //=========================================================================
    // Forward seq_clk to the DUT through an ODDR
    //
    // Routing a fabric-divided register straight to a pin gives a poor edge
    // and extra jitter. ODDR is the proper way to get a clock off-chip, and it
    // keeps the DUT's clock source-synchronous with the sequencer's.
    //
    // INVERTED (D1=0, D2=1): the DUT's rising edge lands on seq_clk's FALLING
    // edge. Our outputs change on seq_clk's rising edge, so the DUT samples
    // them half a period later -- like Chip_tb.sv, which changes inputs
    // between clock edges. Non-inverted, the DUT sampled on the very edge we
    // launched on, and different pins resolved that race differently:
    // Bus_load_en arrived a cycle ahead of Data_bus, so S2P captured the
    // previous transaction's address.
    //=========================================================================
    ODDR #(
        .DDR_CLK_EDGE ("SAME_EDGE"),
        .INIT         (1'b0),
        .SRTYPE       ("SYNC")
    ) oddr_clk (
        .Q  (dut_clk),
        .C  (seq_clk),
        .CE (1'b1),
        .D1 (1'b0),
        .D2 (1'b1),
        .R  (1'b0),
        .S  (1'b0)
    );

    //=========================================================================
    // Reset into the sequencer's domain
    //=========================================================================
    reg [2:0] rst_seq_sync = 3'b111;
    always @(posedge seq_clk) rst_seq_sync <= {rst_seq_sync[1:0], rst_sys};
    wire rst_seq = rst_seq_sync[2];

    //=========================================================================
    // Register interface CDC: sysclk (VIO) -> seq_clk (sequencer)
    //
    // reg_addr and reg_wdata are quasi-static -- the VIO holds them for
    // milliseconds before the write pulse arrives -- so only the CONTROL
    // signal needs synchronising. That is the standard "stable data, sync the
    // control" crossing, and it is correct here precisely because a human (or
    // a Tcl script) sets the operands first and pulses write afterwards.
    //=========================================================================
    reg [2:0] we_seq = 3'b000;
    always @(posedge seq_clk) we_seq <= {we_seq[1:0], reg_we_raw};
    wire reg_we_seq = we_seq[1] & ~we_seq[2];

    // Read data back into sysclk. STATUS changes while an operation runs, so a
    // sample taken mid-change can be briefly inconsistent -- harmless, because
    // software polls until busy clears and only then reads the results, by
    // which point every bit is stable.
    always @(posedge sysclk) begin
        rdata_sync0 <= rdata_seq;
        rdata_sync1 <= rdata_sync0;
    end

    // CLKDIV reads are answered here; everything else comes from the sequencer.
    always @(*) begin
        if (reg_addr[5:2] == 4'h2) reg_rdata_mux = {24'd0, clkdiv};
        else                       reg_rdata_mux = rdata_sync1;
    end

    //=========================================================================
    // Bus IOBUFs
    //
    // FPGAs have no internal tristate, so these must sit at the top level with
    // dut_data_bus reaching real pins. Check the implemented design reports
    // exactly 16 IOBUFs -- anything else means the bus will not work.
    //=========================================================================
    wire [15:0] data_o, data_i;
    wire        data_oe;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_bus
            IOBUF iobuf_inst (
                .I  (data_o[i]),
                .O  (data_i[i]),
                .T  (~data_oe),        // IOBUF T is active-low-to-drive
                .IO (dut_data_bus[i])
            );
        end
    endgenerate

    //=========================================================================
    // Sequencer -- DUT clock domain
    //=========================================================================
    bus_sequencer u_seq (
        .clk             (seq_clk),
        .rst             (rst_seq),

        .reg_addr        (reg_addr),
        .reg_wdata       (reg_wdata),
        .reg_we          (reg_we_seq),
        .reg_rdata       (rdata_seq),

        .dut_rst_n       (dut_rst_n),
        .dut_bist_en     (dut_bist_en),
        .dut_ce          (dut_ce),
        .dut_wc          (dut_wc),
        .dut_bus_dir     (dut_bus_dir),
        .dut_bus_load_en (dut_bus_load_en),
        .shifter_oe_n    (shifter_oe_n),
        .shifter_dir     (shifter_dir),
        .dut_hit         (dut_hit),
        .dut_bist_done   (dut_bist_done),
        .dut_bist_pass   (dut_bist_pass),
        .dut_data_o      (data_o),
        .dut_data_oe     (data_oe),
        .dut_data_i      (data_i)
    );

endmodule
