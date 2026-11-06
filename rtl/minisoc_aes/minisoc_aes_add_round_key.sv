module minisoc_aes_add_round_key (
  input  logic [127:0] i_state,
  input  logic [127:0] i_round_key,
  output logic [127:0] o_state
);
  assign o_state = i_state ^ i_round_key;
endmodule
