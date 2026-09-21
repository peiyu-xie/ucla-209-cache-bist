module P2S(
    input   clk,
    input   rst_n,
    input   load_en,
    input   [127:0] P_in,
    output  [15:0] S_out
);

reg [127:0] buffer; // 128/16=8
assign S_out = buffer[15:0];

always@(posedge clk or negedge rst_n)begin
    if (!rst_n)begin
        buffer <= 128'b0;
    end
    else begin
        if (load_en)begin
            buffer <= P_in;
        end
        else begin
            buffer <= {16'b0, buffer[127:16]};
        end
    end
end
endmodule