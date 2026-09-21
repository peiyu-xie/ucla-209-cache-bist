module Chip(
    input   clk,
    input   rst_n,
    input   BIST_EN,
    input   CE,
    input   WC,
    input   Bus_dir, //1: cache to outside; 0: outside to cache
    input   Bus_load_en,
    output  Hit,
    output  BIST_DONE,
    output  BIST_PASS, 
    inout   [15:0] Data_bus 
);
    wire    [15:0] addr_to_cache;
    wire    [4:0]  write_addr_to_cache; 
    wire    [127:0] data_to_cache;
    wire    [127:0] data_from_cache;

    reg [15:0] s_in;
    reg [15:0] s_out;
    wire [15:0] P2S_out;

    reg dir;
    reg load_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir     <= 1'b0;
            load_en <= 1'b0;
            s_in    <= 16'b0;
            s_out   <= 16'b0;
        end else begin
            dir     <= Bus_dir;
            load_en <= Bus_load_en;
            s_in    <= Data_bus;
            s_out   <= P2S_out;

        end
    end

    assign Data_bus = (dir) ? s_out : 16'bz;

    Cache_BIST_Top cache_bist_top_inst(
        .clk(clk), .rst_n(rst_n), .BIST_EN(BIST_EN), .CE_norm(CE), .WC_norm(WC), 
        .Addr_norm(addr_to_cache), .Write_addr_norm(write_addr_to_cache), .Data_i(data_to_cache), .Data_o(data_from_cache), 
        .Hit(Hit), .BIST_DONE(BIST_DONE), .BIST_PASS(BIST_PASS)
    );

    S2P S2P_inst(
        .clk(clk), .rst_n(rst_n), .load_en(load_en && !dir), .S_in(s_in), 
        .Addr(addr_to_cache), .Write_addr(write_addr_to_cache), .Data(data_to_cache)
    );

    P2S P2S_inst(
        .clk(clk), .rst_n(rst_n), .load_en(load_en && dir), .P_in(data_from_cache), .S_out(P2S_out)
    );

endmodule