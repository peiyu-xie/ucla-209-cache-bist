`timescale 1ns / 1ps

module MISR #(
    parameter WIDTH = 129)(
    input clk,
    input rst_n,
    input enable,
    input [WIDTH-1:0]data_in,  
    output reg [WIDTH-1:0] signature
);

    wire feedback = signature[WIDTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signature <= '0; 
        end 
        else if (enable) begin
            // x^129 + X^5 + x^2 + x^1 + 1
            signature[0]   <= feedback ^ data_in[0];
            signature[1]   <= (signature[0] ^ feedback) ^ data_in[1]; // Tap at x^1
            signature[2]   <= (signature[1] ^ feedback) ^ data_in[2]; // Tap at x^2
            signature[3]   <= signature[2] ^ data_in[3];
            signature[4]   <= signature[3] ^ data_in[4];
            signature[5]   <= (signature[4] ^ feedback) ^ data_in[5]; // Tap at x^5
            
            // For the remaining bits (6 to 128) where there are no taps
            signature[WIDTH-1:6] <= (signature[WIDTH-2:5]) ^ data_in[WIDTH-1:6];
        end
    end

endmodule