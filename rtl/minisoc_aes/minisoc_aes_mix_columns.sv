module minisoc_aes_mix_columns (
  input  logic [127:0] i_state,
  output logic [127:0] o_state
);
  // multiplicacao por 02 em GF(2^8), reduzida por x^8 + x^4 + x^3 + x + 1
  function automatic logic [7:0] xtime(input logic [7:0] b);
    return {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
  endfunction

  for (genvar c = 0; c < 4; c++) begin : g_col
    logic [7:0] s0, s1, s2, s3;

    assign {s0, s1, s2, s3} = i_state[127-32*c -: 32];

    // 03*b = xtime(b) ^ b
    assign o_state[127-32*c -: 32] = {
      xtime(s0)      ^ xtime(s1) ^ s1 ^ s2             ^ s3,
      s0             ^ xtime(s1)      ^ xtime(s2) ^ s2 ^ s3,
      s0             ^ s1             ^ xtime(s2)      ^ xtime(s3) ^ s3,
      xtime(s0) ^ s0 ^ s1             ^ s2             ^ xtime(s3)
    };
  end
endmodule
