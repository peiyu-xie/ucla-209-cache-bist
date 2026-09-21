`timescale 1ns / 1ps

module tb;

    // Parameters
    parameter CLK_PERIOD = 10;

    // DUT Signals
    logic clk;
    logic rst_n;
    //logic cache_rst_n;
    logic BIST_EN;
    logic CE_norm;
    logic WC_norm;
    logic [15:0] Addr_norm;
    logic [4:0]  Write_addr_norm;
    logic [127:0] Data_i;
    wire  [127:0] Data_o;
    wire  Hit;
    wire  BIST_DONE;
    wire  BIST_PASS;

    // Tristate control for normal mode
    /*logic drive_data;
    logic [127:0] data_to_drive;
    assign Data_io = (drive_data) ? data_to_drive : 128'bz;*/

    // Instantiate Top Level Design [cite: 34]
    Cache_BIST_Top dut (
        .clk(clk),
        .rst_n(rst_n),
        .BIST_EN(BIST_EN),
        .CE_norm(CE_norm),
        .WC_norm(WC_norm),
        .Addr_norm(Addr_norm),
        .Write_addr_norm(Write_addr_norm),
        .Data_i(Data_i),
        .Data_o(Data_o),
        .Hit(Hit),
        .BIST_DONE(BIST_DONE),
        .BIST_PASS(BIST_PASS)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test Sequence
    initial begin
        // 1. Initialization & Reset
        $display("--- System Reset ---");
        rst_n = 0;
        //cache_rst_n = 0;
        BIST_EN = 0;
        CE_norm = 0;
        WC_norm = 0;
        Addr_norm = 0;
        Write_addr_norm = 0;
        //drive_data = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        //cache_rst_n = 1;
        #(CLK_PERIOD * 2);

        // 2. Normal Mode Test (Standard Cache Access)
        $display("--- Testing Normal Cache Mode ---");
        //drive_data = 1;
        CE_norm = 1;
        WC_norm = 1; // Write [cite: 29]
        Addr_norm = 16'hAAAA;
        Write_addr_norm = 5'd10;
        Data_i = 128'hDEADBEEF_CAFEF00D_12345678_87654321;
        #(CLK_PERIOD);
        
        //drive_data = 0;
        # 1;
        WC_norm = 0; // Read/Compare [cite: 30]
        #(CLK_PERIOD * 2); // Account for CAM_Cache internal pipeline 
        if (Hit) 
            $display("[SUCCESS] Normal Mode Hit detected at Addr %h", Addr_norm);
        else
            $display("[ERROR] Normal Mode Hit failed!");

        // 3. Trigger BIST Mode
        $display("--- Starting BIST Sequence ---");
        #(CLK_PERIOD * 2);
        BIST_EN = 1; // Start BIST Controller [cite: 7]
        
        // Wait for DONE signal [cite: 10, 20]
        //#(CLK_PERIOD * 100);
        wait(BIST_DONE);
        
        // 4. Evaluate Results
        $display("BIST Finished.");
        
        if (BIST_PASS)
            $display("********* BIST STATUS: PASSED *********");
        else
            $display("********* BIST STATUS: FAILED *********");

        #(CLK_PERIOD * 5);
        BIST_EN = 0;
        $display("Simulation Finished.");
        $finish;
    end

    // Waveform Generation [cite: 111]
    initial begin
        $fsdbDumpfile("waveform.fsdb"); 
        $fsdbDumpvars(0, tb);
    end

endmodule