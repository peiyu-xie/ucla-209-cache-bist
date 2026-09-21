module S2P(
    input   clk,
    input   rst_n,
    input   load_en,
    input   [15:0] S_in,
    output reg [15:0] Addr,
    output reg [4:0] Write_addr,
    output reg [127:0] Data
);

reg [159:0] parallel; // 16 * ceil(149/16)

always@(posedge clk or negedge rst_n)begin
    if (!rst_n)begin
        Addr <= 16'b0;
        Write_addr <= 5'b0;
        Data <= 128'b0;
        parallel <= 160'b0;
    end
    else begin
        if (load_en)begin
            Data <= parallel[127:0];
            Write_addr <= parallel[143:128];
            Addr <= parallel[159:144];
        end
        else begin
            parallel <= {S_in, parallel[159:16]};
        end
    end
end
endmodule