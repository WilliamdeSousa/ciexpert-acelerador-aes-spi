module minisoc_aes_inv_mix_columns (
  input  logic [127:0] i_state,
  output logic [127:0] o_state
);
  // multiplicacao por 02 em GF(2^8), reduzida por x^8 + x^4 + x^3 + x + 1
  function automatic logic [7:0] xtime(input logic [7:0] b);
    return {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
  endfunction

  // 09 = 08 ^ 01, 0b = 08 ^ 02 ^ 01, 0d = 08 ^ 04 ^ 01, 0e = 08 ^ 04 ^ 02
  function automatic logic [7:0] mul09(input logic [7:0] b);
    return xtime(xtime(xtime(b))) ^ b;
  endfunction

  function automatic logic [7:0] mul0b(input logic [7:0] b);
    return xtime(xtime(xtime(b))) ^ xtime(b) ^ b;
  endfunction

  function automatic logic [7:0] mul0d(input logic [7:0] b);
    return xtime(xtime(xtime(b))) ^ xtime(xtime(b)) ^ b;
  endfunction

  function automatic logic [7:0] mul0e(input logic [7:0] b);
    return xtime(xtime(xtime(b))) ^ xtime(xtime(b)) ^ xtime(b);
  endfunction

  for (genvar c = 0; c < 4; c++) begin : g_col
    logic [7:0] s0, s1, s2, s3;

    assign {s0, s1, s2, s3} = i_state[127-32*c -: 32];

    assign o_state[127-32*c -: 32] = {
      mul0e(s0) ^ mul0b(s1) ^ mul0d(s2) ^ mul09(s3),
      mul09(s0) ^ mul0e(s1) ^ mul0b(s2) ^ mul0d(s3),
      mul0d(s0) ^ mul09(s1) ^ mul0e(s2) ^ mul0b(s3),
      mul0b(s0) ^ mul0d(s1) ^ mul09(s2) ^ mul0e(s3)
    };
  end
endmodule
