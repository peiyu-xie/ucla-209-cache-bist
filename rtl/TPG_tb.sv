`timescale 1ns/1ps

module tb;

    // Parameters - Updated to match 144-bit design
    parameter WIDTH_LFSR = 32;
    parameter WIDTH_SHIFTER = 144; 
    parameter CLK_PERIOD = 10;

    // Signals
    logic clk;
    logic rst_n;
    logic enable;
    wire [WIDTH_SHIFTER-1:0] tpg_pattern;

    // Instantiate the Top Level TPG
    TPG dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .tpg_pattern(tpg_pattern)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test Procedure
    initial begin
        // Initialize signals
        rst_n = 0;
        enable = 0;

        // 1. Reset Phase
        $display("--- Starting Reset ---");
        #(CLK_PERIOD * 2);
        rst_n = 1;
        
        // Check if LFSR initialized to the seed (first 32 bits)
        // Seed was 32'hACE12481
        #(CLK_PERIOD);
        $display("Time: %0t | Post-Reset Pattern[31:0]: %h", $time, tpg_pattern[31:0]);

        // 2. Enable BIST (Start Pattern Generation)
        $display("--- Enabling TPG ---");
        enable = 1;

        // 3. Monitor several cycles of patterns
        // We'll display the first 32 bits and the last 32 bits of the 144-bit pattern
        $display("Time       | LFSR (LSB) | Phase Shifted (MSB)");
        $display("----------------------------------------------");
        repeat (10) begin
            @(posedge clk);
            $display("%0t | %h | %h", 
                     $time, 
                     tpg_pattern[31:0], 
                     tpg_pattern[WIDTH_SHIFTER-1:WIDTH_SHIFTER-32]);
        end

        // 4. Test Disable
        enable = 0;
        $display("--- Disabling TPG (Pattern should freeze) ---");
        repeat (3) @(posedge clk);
        $display("Time: %0t | Frozen Pattern[31:0]: %h", $time, tpg_pattern[31:0]);

        $display("--- Simulation Finished ---");
        $finish;
    end

    // Waveform Generation
    initial begin
        // Verilog/SystemVerilog standard dumping
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb);
        
        // Keep your tool-specific FSDB dumping if using Verdi/VCS
        // $fsdbDumpfile("waveform.fsdb"); 
        //