`timescale 1ns / 1ps

module Cache(clk, rst_n, CE, WC, Addr, Write_addr, Data_i, Data_o, Hit);
    input clk, rst_n, CE, WC;
    input [15:0] Addr;
    input [4:0] Write_addr;
    input [127:0] Data_i;
    output [127:0] Data_o;
    output Hit;

    // Registering inputs to match your pipeline design 
    reg CE_dff, WC_dff;
    reg [15:0] Addr_dff;
    reg [4:0] Write_addr_dff;
    reg [127:0] Data_in_dff;
    wire [127:0] Data_out_logic;

    // Instantiate with Clock/Reset
    cache_logic c0 (
        .clk(clk), .rst_n(rst_n), 
        .CE(CE_dff), .WC(WC_dff), 
        .Addr(Addr_dff), .Write_addr(Write_addr_dff), 
        .Data_in(Data_in_dff), .Data_out(Data_out_logic), .Hit(Hit)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            CE_dff <= 0;
        end else begin
            CE_dff <= CE;
            WC_dff <= WC;
            Addr_dff <= Addr;
            Write_addr_dff <= Write_addr;
            Data_in_dff <= Data_i;
        end
    end

    assign Data_o = Data_out_logic;
endmodule

module cache_logic(
    input clk, rst_n,        // Added clock and reset for stable synthesis
    input CE, WC,
    input [15:0] Addr,
    input [4:0] Write_addr,
    input [127:0] Data_in,
    output reg [127:0] Data_out,
    output reg Hit
);
    reg [15:0]  addr_mem [0:31];
    reg [127:0] data_mem [0:31];
    reg found;
    integer i;

    // 1. Synchronous Memory Update (Fixes sim-syn hang)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                addr_mem[i] <= 16'hFFFF; // Initialize to avoid false matches at 0
                data_mem[i] <= 128'h0;
            end
        end else if (CE && WC) begin
            addr_mem[Write_addr] <= Addr;
            data_mem[Write_addr] <= Data_in;
        end
    end

    // 2. Combinatorial Search with Strict Priority (0 to 31)
    always @(*) begin
        Data_out = 128'd0;
        Hit = 0;
        found = 0;

        if (CE && !WC) begin
            for (i = 0; i < 32; i = i + 1) begin
                // Priority: first 'i' to match sets 'found' and blocks others
                if ((addr_mem[i] == Addr) && !found) begin 
                    Data_out = data_mem[i]; 
                    Hit = 1; 
                    found = 1; 
                end
            end
        end
    end
endmodule