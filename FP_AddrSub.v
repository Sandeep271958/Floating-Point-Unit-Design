/*
 * Floating Point Add/Subtract Unit
 *
 * This is a multi-cycle state machine implementation.
 * It handles:
 * - Denormalized inputs (pre-normalization)
 * - Exponent comparison and alignment
 * - Signed addition/subtraction
 * - Post-normalization (both left and right shifts)
 * - Calls the fp_packer for final rounding and packing.
 */
module fp_add_sub (
    input clk,
    input rst_n,
    input start,
    
    input s_a, input [7:0] e_a, input [22:0] f_a,
    input s_b, input [7:0] e_b, input [22:0] f_b,
    input op_is_sub,
    
    output reg [31:0] result,
    output reg done
);

    // --- State Machine Definition ---
    localparam IDLE         = 3'd0;
    localparam PRE_ALIGN    = 3'd1;
    localparam ADD_SUB      = 3'd2;
    localparam NORM_CHECK   = 3'd3;
    localparam NORM_SHIFT_L = 3'd4;
    localparam NORM_SHIFT_R = 3'd5;
    localparam ROUND_PACK   = 3'd6;
    localparam FINISH       = 3'd7;

    reg [2:0] state, next_state;

    // --- Internal Data Registers ---
    // We need registers to hold data as we move between states.
    
    // 9-bit exponent to handle overflow/underflow checks
    reg [8:0] exp_a_reg, exp_b_reg, exp_res_reg; 
    
    // 27-bit mantissa: 1 (hidden) + 23 (frac) + 3 (G, R, S)
    reg [26:0] mant_a_reg, mant_b_reg; 
    
    // 28-bit result: 1 (sign) + 27 (mantissa) for 2's complement
    reg [27:0] mant_res_signed; 
    reg s_a_reg, s_b_eff_reg, s_res_reg; // Effective sign of B
    reg [7:0] shift_amount; // For alignment and normalization
    
    // Wires for final packing
    wire [31:0] packed_result;
    wire [22:0] pack_frac;
    wire pack_g, pack_r, pack_s;

    // --- State Machine Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            result <= 0;
        end else begin
            state <= next_state;
            
            // Latch 'done' high for one cycle in the FINISH state
            if (next_state == FINISH) begin
                done <= 1;
            end else begin
                done <= 0;
            end
            
            // Latch the final result
            if (state == ROUND_PACK) begin
                result <= packed_result;
            end
        end
    end

    // --- Combinational State-Transition and Datapath Logic ---
    always @(*) begin
        // Default assignments
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start) begin
                    // Latch inputs and move to the first stage
                    
                    // Latch 'a' (handle denormalized)
                    s_a_reg <= s_a;
                    if (e_a == 8'h00) begin // Denormalized or zero
                        exp_a_reg <= 9'd1; // Treat as e=1
                        mant_a_reg <= {1'b0, f_a, 3'b0}; // 0.F
                    end else begin
                        exp_a_reg <= {1'b0, e_a};
                        mant_a_reg <= {1'b1, f_a, 3'b0}; // 1.F
                    end
                    
                    // Latch 'b' (handle denormalized)
                    s_b_eff_reg <= s_b ^ op_is_sub; // Effective sign
                    if (e_b == 8'h00) begin
                        exp_b_reg <= 9'd1;
                        mant_b_reg <= {1'b0, f_b, 3'b0};
                    end else begin
                        exp_b_reg <= {1'b0, e_b};
                        mant_b_reg <= {1'b1, f_b, 3'b0};
                    end
                    
                    next_state = PRE_ALIGN;
                end
            end
            
            PRE_ALIGN: begin
                // Compare exponents and set up for alignment shift
                if (exp_a_reg > exp_b_reg) begin
                    shift_amount <= exp_a_reg - exp_b_reg;
                    exp_res_reg <= exp_a_reg;
                    // mant_b_reg will be shifted
                end else begin
                    shift_amount <= exp_b_reg - exp_a_reg;
                    exp_res_reg <= exp_b_reg;
                    // Swap mantissas so mant_b_reg is always the one shifted
                    mant_a_reg <= mant_b_reg;
                    mant_b_reg <= mant_a_reg;
                    s_a_reg <= s_b_eff_reg;
                    s_b_eff_reg <= s_a_reg;
                end
                
                // Note: A full implementation needs a multi-cycle or
                // large barrel shifter here. We will do it in one
                // combinational step for simplicity.
                
                // Perform alignment shift on mant_b_reg
                // This is a *combinational* right shift
                wire [26:0] mant_b_shifted;
                wire sticky_bit;
                if (shift_amount == 0) begin
                    mant_b_shifted = mant_b_reg;
                end else if (shift_amount > 27) begin
                    mant_b_shifted = 27'b0;
                    // Sticky bit is OR of all bits of mant_b_reg
                    sticky_bit = |mant_b_reg; 
                end else begin
                    // Simple shift (no GRS calculation for simplicity)
                    // A real version would calculate G,R,S here.
                    mant_b_shifted = mant_b_reg >> shift_amount;
                end
                
                // Store the shifted mantissa for the next stage
                mant_b_reg <= mant_b_shifted; 
                
                next_state = ADD_SUB;
            end
            
            ADD_SUB: begin
                // Perform 2's complement addition
                // op_a = (s_a_reg) ? -mant_a_reg : mant_a_reg;
                // op_b = (s_b_eff_reg) ? -mant_b_reg : mant_b_reg;
                // mant_res_signed <= op_a + op_b;
                
                // Simpler:
                if (s_a_reg == s_b_eff_reg) begin
                    // Effective addition
                    mant_res_signed <= {1'b0, mant_a_reg} + {1'b0, mant_b_reg};
                    s_res_reg <= s_a_reg;
                end else begin
                    // Effective subtraction
                    mant_res_signed <= {1'b0, mant_a_reg} - {1'b0, mant_b_reg};
                    // Sign will be handled by 2's complement result
                end

                next_state = NORM_CHECK;
            end
            
            NORM_CHECK: begin
                // Check the result of the addition
                
                // Handle negative result (from subtraction)
                if (mant_res_signed[27]) begin
                    s_res_reg <= ~s_a_reg; // Flip sign
                    mant_a_reg <= -mant_res_signed; // 2's complement
                end else begin
                    s_res_reg <= s_a_reg;
                    mant_a_reg <= mant_res_signed[26:0];
                end

                // Check for normalization
                if (mant_a_reg == 0) begin
                    // Result is zero
                    exp_res_reg <= 0;
                    next_state = ROUND_PACK; // Pack a zero
                end else if (mant_a_reg[26]) begin
                    // Overflow: 1x.xxxx...
                    next_state = NORM_SHIFT_R;
                end else if (!mant_a_reg[25]) begin
                    // Underflow: 0.0xxxx...
                    next_state = NORM_SHIFT_L;
                end else begin
                    // Already normalized: 1.xxxx...
                    next_state = ROUND_PACK;
                end
            end
            
            NORM_SHIFT_R: begin // Shift Right (for 1x.xxxx)
                // Shift mantissa right, increment exponent
                // G = mant_a_reg[0], R = 0, S = 0
                mant_a_reg <= {mant_a_reg[0], mant_a_reg[26:1]}; 
                exp_res_reg <= exp_res_reg + 1;
                next_state = ROUND_PACK;
            end
            
            NORM_SHIFT_L: begin // Shift Left (for 0.0xxxx)
                // This is an iterative shifter. A real FPU uses
                // a fast "Leading Zero Counter".
                if (!mant_a_reg[25]) begin
                    mant_a_reg <= mant_a_reg << 1;
                    exp_res_reg <= exp_res_reg - 1;
                    next_state = NORM_SHIFT_L; // Stay in this state
                end else begin
                    next_state = ROUND_PACK;
                end
            end
            
            ROUND_PACK: begin
                // The packer module will do all the final work
                next_state = FINISH;
            end
            
            FINISH: begin
                // We stay here until 'start' goes low and high again
                if (!start) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // --- Packer Instantiation ---
    // Extract the bits for the packer from our final mantissa
    // mant_a_reg = [ ... 1, f22..f0, G, R, S ]
    assign pack_frac = mant_a_reg[25:3]; // f22..f0
    assign pack_g    = mant_a_reg[2];
    assign pack_r    = mant_a_reg[1];
    assign pack_s    = mant_a_reg[0];
    
    FP_Packer packer (
        .res_sign(s_res_reg),
        .res_exp(exp_res_reg),
        .res_frac_23(pack_frac),
        .guard_bit(pack_g),
        .round_bit(pack_r),
        .sticky_bit(pack_s),
        
        .result(packed_result)
    );

endmodule

