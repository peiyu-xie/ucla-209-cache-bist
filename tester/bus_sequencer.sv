//=============================================================================
// bus_sequencer -- Stage-1 tester core for the EE209BS cache+BIST chip
//
// RUNS ENTIRELY IN THE DUT CLOCK DOMAIN.
//
// Earlier versions ran at 125 MHz and advanced the FSM on a clock-enable
// "tick". That made frequency sweeping free, but it also meant the DUT clock
// had to be an integer division of 125 MHz -- so an MMCM-generated 95 MHz
// clock would have been asynchronous to the FSM, and cycle-accurate bus
// transactions would have been impossible at that frequency.
//
// Clocking the FSM from the DUT clock itself removes that restriction: the
// two are synchronous by construction at ANY frequency, and bus read/write
// works at 95 MHz exactly as it does at 1 MHz. Every clock edge here is a DUT
// clock edge -- the FSM now reads almost exactly like Chip_tb.sv's tasks.
//
// The cost is one clock-domain crossing on the register interface, which is
// cheap because register accesses are milliseconds apart.
//
// CLKDIV is NOT here. It lives in tester_top's sysclk domain, because it
// controls the divider that *generates* this clock -- it cannot live in the
// domain it creates.
//
// See REGISTER_MAP.md for the register layout and the three sequencing rules
// this implements.
//=============================================================================

module bus_sequencer #(
    parameter [31:0] MAGIC        = 32'h00C0FFEE,
    parameter        RST_CYCLES   = 8,        // DUT clocks to hold rst_n low
    parameter        BIST_TIMEOUT = 16'd4000  // DUT clocks before giving up
)(
    input  wire        clk,            // DUT clock domain
    input  wire        rst,            // active high, synchronous

    //--- register interface (already synchronised into this domain) --------
    input  wire [5:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_we,         // one-cycle pulse in THIS domain
    output reg  [31:0] reg_rdata,

    //--- DUT pins -----------------------------------------------------------
    output reg         dut_rst_n,
    output reg         dut_bist_en,
    output reg         dut_ce,
    output reg         dut_wc,
    (* mark_debug = "true" *) output reg dut_bus_dir,
    (* mark_debug = "true" *) output reg dut_bus_load_en,
    output reg         shifter_oe_n,   // Stage-2 level shifter: 1 = high-Z
    output reg         shifter_dir,    // U1/U3 DIR: 1 = chip drives, 0 = tester
    input  wire        dut_hit,
    input  wire        dut_bist_done,
    input  wire        dut_bist_pass,
    output reg  [15:0] dut_data_o,
    (* mark_debug = "true" *) output reg dut_data_oe,   // 1 = FPGA drives the bus
    (* mark_debug = "true" *) input wire [15:0] dut_data_i
);

    //=========================================================================
    // Opcodes
    //=========================================================================
    localparam [3:0] OP_RESET = 4'h1,
                     OP_BIST  = 4'h2,
                     OP_WRITE = 4'h3,
                     OP_READ  = 4'h4,
                     OP_ABORT = 4'h5,
                     OP_DIRSET= 4'h6,   // debug only: park Bus_dir high so it
                                        // can be measured with a DC meter
                     OP_PARK  = 4'h7;   // debug only: park the whole bus in
                                        // "chip drives" -- see S_PARK

    //=========================================================================
    // Software-visible state
    //=========================================================================
    reg  [15:0]  addr_r;
    reg  [4:0]   waddr_r;
    reg  [127:0] wdata_r;
    reg  [127:0] rdata_r;

    reg          busy, op_done, op_timeout;
    reg          hit_r, bist_done_r, bist_pass_r;

    reg  [3:0]   opcode;
    reg  [3:0]   rd_wait_r;     // RDWAIT (0x34): read-latency calibration
    reg          start;

    //=========================================================================
    // Input synchronisers
    //
    // These return from the DUT after a cable round trip, so their edges are
    // skewed relative to our clock even though the DUT runs from the clock we
    // forwarded. Treat them as asynchronous.
    //=========================================================================
    reg [1:0]  hit_s, done_s, pass_s;
    reg [15:0] data_s0;
    (* mark_debug = "true" *) reg [15:0] data_s1;

    always @(posedge clk) begin
        hit_s   <= {hit_s[0],  dut_hit};
        done_s  <= {done_s[0], dut_bist_done};
        pass_s  <= {pass_s[0], dut_bist_pass};
        data_s0 <= dut_data_i;
        data_s1 <= data_s0;
    end

    wire sync_hit  = hit_s[1];
    wire sync_done = done_s[1];
    wire sync_pass = pass_s[1];

    //=========================================================================
    // FSM -- one state transition per DUT clock
    //=========================================================================
    localparam [3:0] S_IDLE      = 4'd0,
                     S_RST       = 4'd1,
                     S_BIST      = 4'd2,
                     S_WR_SHIFT  = 4'd3,
                     S_WR_LOAD   = 4'd4,
                     S_CMP_SHIFT = 4'd5,
                     S_CMP_LOAD  = 4'd6,
                     S_TURN_A    = 4'd7,   // hand the bus to the chip
                     S_RD_LOAD   = 4'd8,   // pulse load_en with dir=1 -> P2S
                     S_RD_WAIT   = 4'd9,   // pipeline latency through s_out
                     S_RD_CAP    = 4'd10,  // 8 words back
                     S_TURN_B    = 4'd11,  // take the bus back
                     S_DONE      = 4'd12,
                     S_PARK      = 4'd13;  // debug: hold chip-drives state

    (* mark_debug = "true" *) reg [3:0]  state;
    (* mark_debug = "true" *) reg [15:0] cnt;
    reg [127:0] shift_r;

    // Word order on a WRITE -- the ADDRESS GOES LAST.
    // S2P is a 160-bit shifter loaded from the top
    // (parallel <= {S_in, parallel[159:16]}), so the FIRST word sent ends up
    // at the BOTTOM. Sequence: Data[15:0] .. Data[127:112], Write_addr, Addr.
    wire [15:0] wr_word = (cnt <  8) ? shift_r[15:0]
                        : (cnt == 8) ? {11'b0, waddr_r}
                        :              addr_r;

    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            cnt             <= 16'd0;
            busy            <= 1'b0;
            op_done         <= 1'b0;
            op_timeout      <= 1'b0;
            dut_rst_n       <= 1'b1;
            dut_bist_en     <= 1'b0;
            dut_ce          <= 1'b0;
            dut_wc          <= 1'b0;
            dut_bus_dir     <= 1'b0;
            dut_bus_load_en <= 1'b0;
            dut_data_oe     <= 1'b0;
            dut_data_o      <= 16'd0;
            shifter_oe_n    <= 1'b1;        // shifters high-Z until we drive
            shifter_dir     <= 1'b0;        // tester -> chip
            hit_r           <= 1'b0;
            bist_done_r     <= 1'b0;
            bist_pass_r     <= 1'b0;
            rdata_r         <= 128'd0;
        end else begin

            //--- launch ---------------------------------------------------
            if (start && !busy) begin
                busy       <= 1'b1;
                op_done    <= 1'b0;
                op_timeout <= 1'b0;
                cnt        <= 16'd0;
                shift_r    <= wdata_r;
                case (opcode)
                    OP_RESET: begin
                        state     <= S_RST;
                        dut_rst_n <= 1'b0;
                    end
                    OP_BIST: begin
                        // BIST is SINGLE-SHOT per reset: misr_en_delayed latches
                        // high and the MISR only clears on rst_n, so a re-run
                        // without a reset always computes a garbage signature
                        // and a good chip reads FAIL. Pulse reset ourselves
                        // rather than trust the caller to remember.
                        state       <= S_RST;
                        dut_rst_n   <= 1'b0;
                        dut_bist_en <= 1'b1;
                    end
                    OP_WRITE: begin
                        state        <= S_WR_SHIFT;
                        // CE stays LOW during the shift: cache_logic writes on
                        // every edge with CE && WC, using whatever S2P holds --
                        // the previous op's Addr/Write_addr/Data. S_WR_LOAD
                        // raises CE once the new values have reached the cache.
                        dut_ce       <= 1'b0;
                        dut_wc       <= 1'b0;
                        dut_bus_dir  <= 1'b0;
                        dut_data_oe  <= 1'b1;
                        shifter_oe_n <= 1'b0;
                    end
                    OP_READ: begin
                        state        <= S_CMP_SHIFT;
                        // A read that never captures must read back 0,
                        // not the previous run's data. Nothing else in
                        // the register map can clear these.
                        rdata_r      <= 128'd0;
                        hit_r        <= 1'b0;
                        dut_ce       <= 1'b1;
                        dut_wc       <= 1'b0;
                        dut_bus_dir  <= 1'b0;
                        dut_data_oe  <= 1'b1;
                        shifter_oe_n <= 1'b0;
                    end
                    // Debug aid. Bus_dir is only cleared by S_TURN_B, reset
                    // and ABORT, so it stays high after this returns to idle.
                    // Measure RPi 40 at both ends, then clear with OP_ABORT.
                    OP_DIRSET: begin
                        state       <= S_DONE;
                        dut_bus_dir <= 1'b1;
                        dut_data_oe <= 1'b0;
                    end

                    // Debug aid: hold the bus in "chip drives" with no time
                    // limit, so every stage of the read path can be measured
                    // with a meter. CE=1/WC=0 keeps the compare live; S_PARK
                    // then holds Bus_load_en high, so P2S reloads the cache
                    // output every clock and the chip drives Data_o[15:0] of
                    // the line matching the last READ's address (0xFF00
                    // after Step 2). Read the live bus at 0x30. Clear with
                    // OP_ABORT.
                    OP_PARK: begin
                        state        <= S_PARK;
                        dut_ce       <= 1'b1;
                        dut_wc       <= 1'b0;
                        dut_data_oe  <= 1'b0;
                        shifter_oe_n <= 1'b1;
                    end

                    default: begin   // OP_ABORT and anything unknown
                        state           <= S_DONE;
                        dut_ce          <= 1'b0;
                        dut_wc          <= 1'b0;
                        dut_data_oe     <= 1'b0;
                        dut_bus_dir     <= 1'b0;
                        dut_bus_load_en <= 1'b0;
                        dut_bist_en     <= 1'b0;
                        shifter_oe_n    <= 1'b1;
                        shifter_dir     <= 1'b0;
                    end
                endcase

            //--- run ------------------------------------------------------
            end else if (busy) begin
                cnt <= cnt + 16'd1;

                case (state)

                //--- reset pulse ------------------------------------------
                S_RST: if (cnt >= RST_CYCLES) begin
                    dut_rst_n <= 1'b1;
                    cnt       <= 16'd0;
                    state     <= dut_bist_en ? S_BIST : S_DONE;
                end

                //--- BIST: wait for DONE, WITH A TIMEOUT -------------------
                // Chip_tb.sv uses wait(BIST_DONE), which is fine in simulation.
                // On silicon a dead chip would hang forever, and "timed out"
                // is a completely different diagnosis from "ran and failed".
                S_BIST: begin
                    if (sync_done) begin
                        bist_done_r <= 1'b1;
                        bist_pass_r <= sync_pass;
                        dut_bist_en <= 1'b0;
                        state       <= S_DONE;
                    end else if (cnt >= BIST_TIMEOUT) begin
                        op_timeout  <= 1'b1;
                        bist_done_r <= 1'b0;
                        bist_pass_r <= 1'b0;
                        dut_bist_en <= 1'b0;
                        state       <= S_DONE;
                    end
                end

                //--- WRITE: 10 shift cycles, address last ------------------
                S_WR_SHIFT: begin
                    dut_data_o <= wr_word;
                    if (cnt < 8) shift_r <= {16'd0, shift_r[127:16]};
                    if (cnt >= 9) begin
                        cnt   <= 16'd0;
                        state <= S_WR_LOAD;
                    end
                end

                // The write lands three registers after load_en: Chip.sv's
                // load_en flop -> S2P capture -> Cache.sv's CE/WC/Addr/Data
                // flops -> cache_logic writes on CE_dff && WC_dff.
                // Raise CE/WC two cycles after load_en, so CE_dff first goes
                // high on the same edge Addr_dff gets the new address -- any
                // earlier and the cache writes S2P's stale contents. Then hold
                // them a few cycles; the repeated writes are identical.
                S_WR_LOAD: begin
                    dut_bus_load_en <= (cnt == 0);
                    if (cnt == 2) begin
                        dut_ce <= 1'b1;
                        dut_wc <= 1'b1;
                    end
                    if (cnt >= 6) begin
                        dut_bus_load_en <= 1'b0;
                        dut_data_oe     <= 1'b0;
                        dut_ce          <= 1'b0;
                        dut_wc          <= 1'b0;
                        shifter_oe_n    <= 1'b1;
                        cnt             <= 16'd0;
                        state           <= S_DONE;
                    end
                end

                //--- READ: compare phase ----------------------------------
                // fast_compare in Chip_tb.sv shifts the ADDRESS ONCE: Addr
                // sits at the top of the S2P mapping (parallel[159:144]), so
                // a single shift puts it straight there.
                S_CMP_SHIFT: begin
                    dut_data_o <= addr_r;
                    cnt        <= 16'd0;
                    state      <= S_CMP_LOAD;
                end

                S_CMP_LOAD: begin
                    dut_bus_load_en <= 1'b1;
                    if (cnt >= 1) begin
                        dut_bus_load_en <= 1'b0;
                        cnt             <= 16'd0;
                        state           <= S_TURN_A;
                    end
                end

                //--- TURNAROUND: hand the bus to the chip -------------------
                // THE INVARIANT: fpga_oe and chip_oe must never both be true.
                // Chip.sv registers dir (dir <= Bus_dir), so the chip starts
                // driving one DUT clock AFTER Bus_dir rises. Release our
                // drivers FIRST, raise Bus_dir, and the gap comes for free.
                // Stage 2: U1/U3 must also flip to A->B (chip drives), and the
                // PCB rule is "change DIR only while /OE is H":
                //   cnt 0  we release the bus, shifters high-Z
                //   cnt 1  shifter DIR -> chip drives
                //   cnt 2  Bus_dir high, shifters on (chip drives half a
                //          cycle later, onto shifter inputs -- no fight)
                // Bus_dir still leads RD_LOAD's load_en by two edges, so the
                // chip's registered dir is 1 before load_en arrives and S2P
                // does not capture.
                S_TURN_A: begin
                    if (cnt == 0) begin
                        dut_data_oe  <= 1'b0;
                        shifter_oe_n <= 1'b1;
                    end
                    if (cnt == 1) shifter_dir <= 1'b1;
                    if (cnt == 2) begin
                        dut_bus_dir  <= 1'b1;
                        shifter_oe_n <= 1'b0;
                    end
                    if (cnt >= 3) begin
                        cnt   <= 16'd0;
                        state <= S_RD_LOAD;
                    end
                end

                //--- trigger P2S to capture the cache output ---------------
                S_RD_LOAD: begin
                    dut_bus_load_en <= 1'b1;
                    if (cnt >= 1) begin
                        dut_bus_load_en <= 1'b0;
                        cnt             <= 16'd0;
                        state           <= S_RD_WAIT;
                    end
                end

                //--- pipeline latency --------------------------------------
                // P2S output passes through Chip.sv's s_out register before it
                // reaches the pad, and our input is double-synchronised.
                // MEASURE THIS AGAINST THE EMULATOR WITH AN ILA -- it is the
                // one number here that is easier to measure than to derive,
                // and it may shift in Stage 2 once level shifters add delay.
                // 2 (the reset value) assumes the INVERTED forwarded clock and
                // a round trip shorter than half a DUT period. Above ~20 MHz
                // on the Stage-2 board (U6 on the clock, U1/U3 on the data,
                // jumpers both ways) the data arrives a whole cycle later --
                // intact, just late -- so the wait is a register (RDWAIT,
                // 0x34) that software calibrates per frequency.
                S_RD_WAIT: if (cnt >= {12'd0, rd_wait_r}) begin
                    cnt   <= 16'd0;
                    state <= S_RD_CAP;
                end

                //--- capture 8 words ---------------------------------------
                S_RD_CAP: begin
                    rdata_r <= {data_s1, rdata_r[127:16]};
                    hit_r   <= sync_hit;
                    if (cnt >= 7) begin
                        cnt   <= 16'd0;
                        state <= S_TURN_B;
                    end
                end

                //--- TURNAROUND: take the bus back --------------------------
                // Drop Bus_dir, then WAIT -- the chip keeps driving for one
                // more cycle because dir is registered. Only then may we drive.
                // Shifters go high-Z first, DIR flips back to tester -> chip
                // while /OE is H; the next WRITE/READ re-enables them.
                S_TURN_B: begin
                    if (cnt == 0) begin
                        dut_bus_dir  <= 1'b0;
                        shifter_oe_n <= 1'b1;
                    end
                    if (cnt == 1) shifter_dir <= 1'b0;
                    if (cnt >= 3) begin
                        dut_ce <= 1'b0;
                        cnt    <= 16'd0;
                        state  <= S_DONE;
                    end
                end

                //--- finish -------------------------------------------------
                S_DONE: begin
                    busy            <= 1'b0;
                    op_done         <= 1'b1;
                    dut_data_oe     <= 1'b0;
                    dut_bus_load_en <= 1'b0;
                    shifter_oe_n    <= 1'b1;
                    state           <= S_IDLE;
                end

                //--- debug park: same break-before-make as S_TURN_A ---------
                // Ends straight in IDLE, skipping S_DONE, so the pins stay put.
                S_PARK: begin
                    if (cnt == 1) shifter_dir <= 1'b1;
                    if (cnt == 2) begin
                        dut_bus_dir  <= 1'b1;
                        shifter_oe_n <= 1'b0;
                    end
                    if (cnt == 4) dut_bus_load_en <= 1'b1;   // dir=1 by now
                    if (cnt >= 5) begin
                        busy    <= 1'b0;
                        op_done <= 1'b1;
                        state   <= S_IDLE;
                    end
                end

                default: state <= S_DONE;
                endcase
            end
        end
    end

    //=========================================================================
    // Register file
    //=========================================================================
    wire [3:0] widx = reg_addr[5:2];

    always @(posedge clk) begin
        start <= 1'b0;                      // START is a one-shot

        if (rst) begin
            addr_r  <= 16'd0;
            waddr_r <= 5'd0;
            wdata_r <= 128'd0;
            opcode  <= 4'd0;
            rd_wait_r <= 4'd2;
        end else if (reg_we) begin
            case (widx)
                4'h0: begin                                    // CTRL
                    opcode <= reg_wdata[3:0];
                    start  <= reg_wdata[8];
                end
                4'h3: begin                                    // ADDR
                    addr_r  <= reg_wdata[15:0];
                    waddr_r <= reg_wdata[20:16];
                end
                4'h4: wdata_r[31:0]   <= reg_wdata;            // WDATA0
                4'h5: wdata_r[63:32]  <= reg_wdata;            // WDATA1
                4'h6: wdata_r[95:64]  <= reg_wdata;            // WDATA2
                4'h7: wdata_r[127:96] <= reg_wdata;            // WDATA3
                4'hD: rd_wait_r       <= reg_wdata[3:0];       // RDWAIT
                default: ;                                      // 0x08 CLKDIV
                                                                // lives in top
            endcase
        end
    end

    always @(*) begin
        case (widx)
            4'h1:    reg_rdata = {26'd0, bist_pass_r, bist_done_r,
                                  hit_r, op_timeout, op_done, busy};  // STATUS
            4'h3:    reg_rdata = {11'd0, waddr_r, addr_r};
            4'h4:    reg_rdata = wdata_r[31:0];
            4'h5:    reg_rdata = wdata_r[63:32];
            4'h6:    reg_rdata = wdata_r[95:64];
            4'h7:    reg_rdata = wdata_r[127:96];
            4'h8:    reg_rdata = rdata_r[31:0];                        // RDATA0
            4'h9:    reg_rdata = rdata_r[63:32];
            4'hA:    reg_rdata = rdata_r[95:64];
            4'hB:    reg_rdata = rdata_r[127:96];
            4'hC:    reg_rdata = {6'd0, dut_wc, dut_ce, dut_bus_load_en,   // LIVE
                                  shifter_oe_n, shifter_dir, dut_bus_dir,  // (debug)
                                  3'd0, sync_hit, data_s1};
            4'hD:    reg_rdata = {28'd0, rd_wait_r};                   // RDWAIT
            4'hF:    reg_rdata = MAGIC;                                // PING
            default: reg_rdata = 32'd0;
        endcase
    end

endmodule
