module bidirectional_P2S_S2P (
    input          clk,
    input          rst_n,
    input          dir,          // 0: Input (S2P), 1: Output (P2S)
    input          load_en,      // Latch/Capture pulse
    inout  [15:0]  data_bus,     
    // Internal Cache Connections
    output [15:0]  Addr,
    output [4:0]   Write_addr,
    output [127:0] Data_to_cache,
    input  [127:0] Data_from_cache
);

    wire [15:0] s_in;
    wire [15:0] s_out;

    // Tri-State Buffer Logic
    // dir=1: S_out -> pads. dir=0: release the bus.
    assign data_bus = (dir) ? s_out : 16'bz;
    assign s_in     = data_bus;

    // S2P Instance
    S2P S2P_inst (
        .clk(clk),
        .rst_n(rst_n),
        .load_en(load_en && !dir), // Only latch when in input mode
        .S_in(s_in),
        .Addr(Addr),
        .Write_addr(Write_addr),
        .Data(Data_to_cache)
    );

    // P2S Instance 
    P2S P2S_inst (
        .clk(clk),
        .rst_n(rst_n),
        .load_en(load_en && dir),   // Only capture when in output mode
        .P_in(Data_from_cache),
        .S_out(s_out)
    );

endmodule