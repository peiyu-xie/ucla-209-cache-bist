module Cache_BIST_Top (
    input  clk,
    input  rst_n,
    input  BIST_EN,
    input  CE_norm,
    input  WC_norm,
    input  [15:0] Addr_norm,
    input  [4:0]  Write_addr_norm,
    input  [127:0] Data_i, 
    output [127:0] Data_o,
    output Hit,
    output BIST_DONE,
    output BIST_PASS
);
    // from Controller
    wire is_compare, tpg_en_wire, misr_en_wire;
    wire [4:0] bist_write_idx;
    
    // TPG
    wire [143:0] tpg_pattern; 
    reg [15:0] addr_storage [0:31]; // the 32 addresses here

    //To Cache
    wire [127:0] Data_i_to_cache;
    // wire [127:0] Data_o;

    wire [128:0] signature;
    
    
    TPG tpg_inst (.clk(clk), .rst_n(rst_n), .enable(tpg_en_wire), .tpg_pattern(tpg_pattern));

    // Address Memorization
    always_ff @(posedge clk) begin
        if (BIST_EN && !is_compare) 
            addr_storage[bist_write_idx] <= tpg_pattern[15:0];
    end

    // Mux 
    // During Compare: 50/50 chance to use stored addr or new random addr
    wire [15:0] bist_addr = is_compare ? 
                (tpg_pattern[143] ? addr_storage[tpg_pattern[4:0]] : tpg_pattern[15:0]) : 
                tpg_pattern[15:0];

    wire CE_mux = BIST_EN ? 1'b1 : CE_norm;
    wire WC_mux = BIST_EN ? !is_compare : WC_norm; // Write only in Write Phase
    wire [15:0] Addr_mux = BIST_EN ? bist_addr : Addr_norm;
    wire [4:0]  WAddr_mux = BIST_EN ? bist_write_idx : Write_addr_norm;

    // Data_io Control
    // Drive bus during WRITE, release during COMPARE 
    // assign Data_io = (BIST_EN && !is_compare) ? tpg_pattern[143:16] : 128'bz;
    /*wire internal_bus_drive_en = BIST_EN ? is_compare : (CE_norm && !WC_norm);
    assign Data_io = (internal_bus_drive_en) ? Data_o : 128'bz;*/
    assign Data_i_to_cache = BIST_EN ? tpg_pattern[143:16] : Data_i;
    // Cache
    Cache cache_inst (
        .clk(clk), .rst_n(rst_n), .CE(CE_mux), .WC(WC_mux), .Addr(Addr_mux),
        .Write_addr(WAddr_mux), .Data_i(Data_i_to_cache), .Data_o(Data_o), .Hit(Hit)
    );

    // MISR
    MISR #(.WIDTH(129)) misr_inst (
        .clk(clk), .rst_n(rst_n), .enable(misr_en_wire),
        .data_in({Hit, Data_o}), .signature(signature)
    );

    // Controller
    BIST_Controller controller_inst (
        .clk(clk), .rst_n(rst_n), .enable(BIST_EN),
        .actual_signature(signature), .tpg_en(tpg_en_wire),
        .misr_en(misr_en_wire), .write_addr(bist_write_idx),
        .is_compare(is_compare), .done(BIST_DONE), .pass_fail(BIST_PASS)
    );

endmodule