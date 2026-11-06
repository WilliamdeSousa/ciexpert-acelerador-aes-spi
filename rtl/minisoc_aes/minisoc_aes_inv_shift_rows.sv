module minisoc_aes_inv_shift_rows (
  input  logic [127:0] i_state,
  output logic [127:0] o_state
);
  assign o_state = {
    i_state[127:120], i_state[ 23: 16], i_state[ 47: 40], i_state[ 71: 64],  // coluna 0: bytes  0, 13, 10,  7
    i_state[ 95: 88], i_state[119:112], i_state[ 15:  8], i_state[ 39: 32],  // coluna 1: bytes  4,  1, 14, 11
    i_state[ 63: 56], i_state[ 87: 80], i_state[111:104], i_state[  7:  0],  // coluna 2: bytes  8,  5,  2, 15
    i_state[ 31: 24], i_state[ 55: 48], i_state[ 79: 72], i_state[103: 96]   // coluna 3: bytes 12,  9,  6,  3
  };
endmodule
