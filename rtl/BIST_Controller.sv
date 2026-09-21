module BIST_Controller #(
    parameter [128:0] GOLDEN_SIGNATURE = 129'h18f3aa1fa8f3aa1faf190650500cb48f6 // Update after first simulation
)(
    input clk,
    input rst_n,
    input enable,
    input [128:0] actual_signature,
    output reg tpg_en,
    output wire misr_en,         
    output reg [4:0] write_addr, 
    output reg is_compare,       
    output reg done,
    output reg pass_fail
);
    typedef enum logic [2:0] {IDLE, WRITE_PHASE, COMPARE_PHASE, EVALUATE, DONE} state_t;
    state_t state, next_state;
    reg [5:0] count;
    reg misr_en_delayed;

    // Use the delayed signal to account for CAM_Cache 1-cycle delay 
    assign misr_en = misr_en_delayed;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    // State 
    always_comb begin
        next_state = state;
        case (state)
            IDLE:          if (enable) next_state = WRITE_PHASE;
            WRITE_PHASE:   if (count == 31) next_state = COMPARE_PHASE;
            COMPARE_PHASE: if (count == 52) next_state = EVALUATE; // 50 comparisons + 1 for flush
            EVALUATE:      next_state = DONE;
            DONE:          if (!enable) next_state = IDLE;
        endcase
    end

    // delay for MISR enable
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) misr_en_delayed <= 0;
        else if (count == 1 & state == COMPARE_PHASE) misr_en_delayed <= 1;
        else  misr_en_delayed <=misr_en_delayed;
    end
    
    // Control & Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            tpg_en <= 0;
            is_compare <= 0;
            done <= 0;
            pass_fail <= 0;
            write_addr <= 0;
        end else begin
            case (state)
                IDLE: count <= 0;
                
                WRITE_PHASE: begin
                    tpg_en <= 1;
                    is_compare <= 0;
                    write_addr <= count[4:0];
                    count <= (count == 31) ? 0 : count + 1;
                end
                
                COMPARE_PHASE: begin
                    tpg_en <= 1;
                    is_compare <= 1;
                    count <= count + 1;
                end
                
                EVALUATE: begin
                    pass_fail <= (actual_signature == GOLDEN_SIGNATURE);
                    tpg_en <= 0;
                end
                
                DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule