`timescale 1ns / 1ps

module tb;

    // Parameters
    parameter CLK_PERIOD = 10;

    // ---------------------------------------------------------
    // 26 PADS OF THE CHIP
    // ---------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic        BIST_EN;
    logic        CE;
    logic        WC;
    logic        Bus_dir;
    logic        Bus_load_en;
    wire         Hit;
    wire         BIST_DONE;
    wire         BIST_PASS;
    wire [15:0]  Data_bus; 

    // ---------------------------------------------------------
    // TESTBENCH INTERNAL CONTROL
    // ---------------------------------------------------------
    logic [15:0] tb_data_out;

    // Bi-directional Bus Logic: TB drives only when Bus_dir is 0
    assign Data_bus = (!Bus_dir) ? tb_data_out : 16'bz;

    // Instantiate the DUT
    Chip dut (
        .clk(clk), .rst_n(rst_n), .BIST_EN(BIST_EN),
        .CE(CE), .WC(WC), .Bus_dir(Bus_dir), .Bus_load_en(Bus_load_en),
        .Hit(Hit), .BIST_DONE(BIST_DONE), .BIST_PASS(BIST_PASS),
        .Data_bus(Data_bus)
    );

    // post Simulation
    initial begin
        $sdf_annotate("/w/home.06/home/peiyu0922/209b/ee209as/ee209-hammer-internal_test1/innovus_copy/output_0505/Chip.sdf", tb.dut, , "sdf.log", "MAXIMUM");
    end

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ---------------------------------------------------------
    // TASKS: Aligning with updated S2P (Addr at [159:144])
    // ---------------------------------------------------------

    // Task for Full Write (10 cycles of shifting)
    task automatic normal_write(input [4:0] waddr, input [15:0] addr, input [127:0] data);
        Bus_dir = 0; 
        CE = 1; WC = 1;
        // Shift 128-bit Data first (8 words) to fill parallel[127:0]
        for (int i = 0; i < 8; i++) begin
            tb_data_out = data[15:0];
            data = data >> 16;
            #(CLK_PERIOD);
        end
        // Shift Write_addr (1 word) to fill parallel[143:128]
        tb_data_out = {11'b0, waddr};
        #(CLK_PERIOD);
        // Shift Addr last (1 word) to fill parallel[159:144]
        tb_data_out = addr;
        #(CLK_PERIOD);
        
        // Pulse load_en
        Bus_load_en = 1;
        #(CLK_PERIOD);
        Bus_load_en = 0;
        tb_data_out = 16'bz;
        #(CLK_PERIOD); 
    endtask

    // Task for Fast Compare (Only 1 cycle of shifting)
    task automatic fast_compare(input [15:0] addr);
        Bus_dir = 0;
        CE = 1; WC = 0;
        // Shift Addr once. Because it's at the top of S2P mapping, 
        // it enters parallel[159:144] immediately.
        tb_data_out = addr;
        #(CLK_PERIOD);
        
        Bus_load_en = 1;
        #(CLK_PERIOD);
        Bus_load_en = 0;
        tb_data_out = 16'bz;
        #(CLK_PERIOD);
    endtask

    // ---------------------------------------------------------
    // MAIN TEST SEQUENCE
    // ---------------------------------------------------------
    initial begin
        // 1. Reset
        rst_n = 0; BIST_EN = 0; CE = 0; WC = 0; 
        Bus_dir = 0; Bus_load_en = 0; tb_data_out = 16'bz;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // 2. Normal Mode: Full Write
        $display("[%0t] --- Starting Normal Mode: Full Write ---", $time);
        normal_write(5'd10, 16'hAAAA, 128'h11223344_55667788_99AABBCC_DDEEFF00);
        #(CLK_PERIOD * 2);

        // 3. Normal Mode: Fast Compare & Read-back
        $display("[%0t] --- Starting Normal Mode: Fast Compare ---", $time);
        fast_compare(16'hAAAA); // Just 1 shift cycle!
        
        // Step A: Turnaround cycle for Bus_dir
        #(CLK_PERIOD);
        Bus_dir = 1;      // Switch Chip to Output mode
        // #(CLK_PERIOD);    // Wait for internal dir register delay [cite: 136]

        // Step B: Trigger P2S to capture Cache output
        Bus_load_en = 1;
        #(CLK_PERIOD);
        Bus_load_en = 0;
        
        // Step C: Observe 8 cycles of P2S output on Data_bus
        $display("[%0t] Reading Data_bus chunks (P2S):", $time);
        repeat (8) begin
            @(posedge clk);
            #(1); // Small offset to sample after clock edge
            $display("   Data_bus: %h (Hit=%b)", Data_bus, Hit);
        end
        #(CLK_PERIOD);

        // 4. BIST Mode
        $display("[%0t] --- Starting BIST Mode ---", $time);
        Bus_dir = 0; // Return to input mode for safety
        #(CLK_PERIOD);
        BIST_EN = 1;
        
        // Wait for BIST_DONE [cite: 131]
        wait(BIST_DONE);
        
        if (BIST_PASS)
            $display("********* BIST STATUS: PASSED *********");
        else
            $display("********* BIST STATUS: FAILED *********");

        #(CLK_PERIOD * 10);
        BIST_EN = 0;
        $display("[%0t] Simulation Finished.", $time);
        $finish;
    end

    // Waveform Generation
    initial begin
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars(0, tb);
    end

endmodule