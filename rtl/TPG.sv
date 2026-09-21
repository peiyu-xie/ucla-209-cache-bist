// LFSR
module LFSR #(
    parameter WIDTH = 32
)(
    input clk,
    input rst_n,
    input enable,
    output reg [WIDTH-1:0] lfsr_out
);
    wire feedback;

    // x^32 + x^22 + x^2 + x^1 + 1
    assign feedback = lfsr_out[31] ^ lfsr_out[21] ^ lfsr_out[1] ^ lfsr_out[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr_out <= 32'hACE12481; 
        else if (enable)
            lfsr_out <= {lfsr_out[WIDTH-2:0], feedback};
    end
endmodule

// Phase Shifter
module Phase_Shifter #(
    parameter WIDTH_LFSR = 32,
    parameter WIDTH_SHIFTER = 144  // Changed from 151
) (
    input [WIDTH_LFSR-1:0] from_lfsr,
    output wire [WIDTH_SHIFTER-1:0] shifter_out
);
    genvar i;
    generate
        // first 32 bits
        assign shifter_out[WIDTH_LFSR-1:0] = from_lfsr;

        // remaining bits (to 143)
        for (i = WIDTH_LFSR; i < WIDTH_SHIFTER; i = i + 1) begin : phase_shift_loop
            assign shifter_out[i] = from_lfsr[i % WIDTH_LFSR] ^ from_lfsr[(i+7) % WIDTH_LFSR];
        end
    endgenerate
endmodule

// Top-Level TPG 
module TPG (
    input clk,
    input rst_n,
    input enable,
    output [143:0] tpg_pattern // Changed range to [143:0] for 144 bits
);
    wire [31:0] internal_lfsr;

    LFSR #(.WIDTH(32)) lfsr_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .lfsr_out(internal_lfsr)
    );

    Phase_Shifter #(.WIDTH_LFSR(32), .WIDTH_SHIFTER(144)) ps_inst (
        .from_lfsr(internal_lfsr),
        .shifter_out(tpg_pattern)
    );
endmodule