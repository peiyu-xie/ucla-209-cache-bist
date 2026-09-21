`timescale 1ns / 1ps

module tb;

    reg clk, rst_n, dir, load_en;
    wire [15:0] data_bus;
    reg  [15:0] tb_drive_data;
    
    // Internal monitor wires
    wire [15:0]  Addr;
    wire [4:0]   Write_addr;
    wire [127:0] Data_to_cache;
    reg  [127:0] Data_from_cache;

    // Bidirectional Bus Control for Testbench
    assign data_bus = (!dir) ? tb_drive_data : 16'bz; 

    // Instantiate System
    bidirectional_P2S_S2P dut (
        .clk(clk), .rst_n(rst_n), .dir(dir), .load_en(load_en),
        .data_bus(data_bus), .Addr(Addr), .Write_addr(Write_addr),
        .Data_to_cache(Data_to_cache), .Data_from_cache(Data_from_cache)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // 1. Reset
        rst_n = 0; dir = 0; load_en = 0; tb_drive_data = 0;
        #20 rst_n = 1;
        
        // 2. S2P Phase: Shift in 10 cycles (Data, then Addr, then WAddr)
        $display("--- Starting S2P Input Phase ---");
        for (integer i = 0; i < 10; i++) begin
            @(negedge clk);
            if (i < 8)       tb_drive_data = 16'h1111 * (i+1); // Data Chunks
            else if (i == 8) tb_drive_data = 16'hAAAA;         // Addr
            else             tb_drive_data = 16'h0010;         // WAddr (5'd16)
        end
        
        // Latch data into S2P
        @(negedge clk);
        load_en = 1;
        #10 load_en = 0;
        $display("S2P Results: Addr=%h, WAddr=%h", Addr, Write_addr);

        // 3. Turnaround: Switch Direction
        $display("--- Bus Turnaround ---");
        @(negedge clk);
        dir = 1; // TB stops driving, DUT will take over
        #10;     // Dead cycle to avoid conflicts 

        // 4. P2S Phase: Capture and Shift Out
        $display("--- Starting P2S Output Phase ---");
        Data_from_cache = 128'hDEADBEEF_CAFEF00D_5555AAAA_3333CCCC;
        
        @(negedge clk);
        load_en = 1;
        #10 load_en = 0;

        // Observe 8 cycles of output
        repeat (8) begin
            @(posedge clk);
            #1 $display("Bus Read: %h", data_bus);
        end

        #50 $finish;
    end
    initial begin
        $fsdbDumpfile("waveform.fsdb"); 
        $fsdbDumpvars(0, tb);
    end
endmodule