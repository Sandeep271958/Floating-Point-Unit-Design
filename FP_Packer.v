module FP_Packer(

    input sign,
    input [8:0] exp, // Input exp might be > 255 (9 bits) or < 0 before rounding
    input [23:0] frac, // Input frac might be > 23 bits before rounding

    input guard_bit, // G
    input round_bit, // R
    input sticky_bit, // S

    output [31:0] result

);
    wire [7:0] final_exp;
    wire [22:0] final_frac;


    wire lsb = frac[0]; // L

    // ---------- rounding logic -----------------------
    wire roundup;
    wire carryout;
    wire [22:0] frac_round;
    assign roundup = guard_bit & (lsb | round_bit | sticky_bit);

    assign {carryout , frac_round} = frac + roundup;

    // ---------- Mantessa Overflow handeling ----------
    wire [8:0] exp_round;
    wire [22:0] final_frac_round;

    wire mantoverflow = carryout;

    always @(*) begin
        if (mantoverflow) 
            begin
                final_frac_round = 23'h000000;
                exp_round = exp + 1;
            end
        else 
            begin
                final_frac_round = frac_round;
                exp_round = exp;
            end


    end



    // --------- overflow / underflow check ------------
    wire overflow;
    wire underflow;

    assign overflow = (exp_round > 254); // Becomes Infinity
    assign underflow = (exp_round < 1); // Becomes Zero

    assign final_exp = (overflow) ? 8'hFF : // Infinity
                        (underflow) ? 8'h00 : // Zero
                         exp_round [7:0]; // Normal Case
    
    assign final_frac = (overflow | underflow) ? 23'h000000 : final_frac_round ;

    assign result = {sign, final_exp, final_frac};

endmodule
