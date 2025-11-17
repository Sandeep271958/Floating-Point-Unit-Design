module FP_Unpacker (
    input [31:0] in,

    output sign,
    output [7:0] exp,
    output [22:0] frac,

    output is_zero,
    output is_inf,
    output is_nan
);

    assign sign = in[31];
    assign exp = in[30:23];
    assign frac = in[22:0];

    wire e_all_zeros = (exp == 8'h00);
    wire e_all_ones = (exp == 8'hFF);
    wire f_all_zeros = (frac == 23'h000000);

    assign is_zero = e_all_zeros & f_all_zeros;
    assign is_inf = e_all_ones & f_all_zeros;
    assign is_nan = e_all_ones & !f_all_zeros;

    // Denormalised numbers are all (e_all_zeros & !f_all_zeros)

endmodule
