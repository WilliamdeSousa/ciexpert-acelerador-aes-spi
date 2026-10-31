module minisoc_aes_sub_bytes (
  input  logic [127:0] i_state,
  output logic [127:0] o_state
);
  for (genvar n = 0; n < 16; n++) begin : g_sbox
    minisoc_aes_sbox u_sbox (
      .i_data (i_state[127-8*n -: 8]),
      .o_data (o_state[127-8*n -: 8])
    );
  end
endmodule
