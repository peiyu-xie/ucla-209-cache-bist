`timescale 1ns / 1ps
`define  CYCLE 10

module tb;

reg clk, rst_n, CE, WC; // Added rst_n
reg [15:0] Addr;
reg [4:0] Write_addr;

reg [127:0] Data_i;
wire[127:0] Data_o;
wire Hit;

integer i;
reg [15:0] rand_addr;
reg [127:0] rand_data;

initial begin
    $fsdbDumpfile("waveform.fsdb"); 
    $fsdbDumpvars(0, tb);
    // Important: SDF annotation is critical for sim-syn [cite: 153, 172]
    // $sdf_annotate("./DEFAULT/syn-rundir/top_module.mapped.sdf", tb.dut,,,"maximum");
end

// Updated instantiation to include rst_n
Cache dut(
    .clk(clk), 
    .rst_n(rst_n), 
    .CE(CE), 
    .WC(WC), 
    .Addr(Addr), 
    .Write_addr(Write_addr), 
    .Data_i(Data_i), 
    .Data_o(Data_o), 
    .Hit(Hit)
);

initial clk = 1;
always #(`CYCLE/2) clk = ~clk;

initial begin
    // 1. Initialization and Reset 
    rst_n = 0;
    CE = 0; 
    WC = 0; 
    Addr = 0; 
    Write_addr = 0; 
    Data_i = 0;
    
    #(`CYCLE * 2); 
    rst_n = 1; // Release reset [cite: 177, 225]
    #(`CYCLE);

    // 2. Write Loop [cite: 156]
    // Drive inputs on the falling edge to ensure setup time for sim-syn
    for (i = 0; i < 32; i = i + 1) begin
        @(negedge clk);
        rand_addr = $random;
        rand_data = {$random, $random, $random, $random}; 

        CE = 1;
        WC = 1;
        Addr = rand_addr;
        Write_addr = i[4:0];
        Data_i = rand_data;
    end

    // 3. Specific Manual Writes [cite: 159]
    @(negedge clk);
    Addr = 16'd100; Write_addr = 5'd5; Data_i = 128'd418;
    @(negedge clk);
    Addr = 16'd500; Write_addr = 5'd16; Data_i = 128'd240;

    // 4. Compare (Read mode) [cite: 160]
    @(negedge clk);
    WC = 0; 
    Addr = 16'd0; // Expect Miss
    
    @(negedge clk);
    Addr = 16'd100; // Expect Hit (from index 5) [cite: 161]
    
    @(negedge clk);
    Addr = 16'd20; // Expect Miss
    
    @(negedge clk);
    Addr = 16'd500; // Expect Hit (from index 16)
    
    @(negedge clk);
    Addr = 16'd0;

    #(`CYCLE * 5);
    $display("Simulation Finished at %t", $time);
    $finish;
end

endmodule