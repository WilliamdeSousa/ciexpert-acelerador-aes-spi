module minisoc_aes_dp (
  input  logic         i_clk,
  input  logic         i_rst_n,
  input  logic         i_start,
  input  logic         i_decrypt,
  input  logic [127:0] i_block,
  output logic [3:0]   o_round,
  input  logic [127:0] i_round_key,
  output logic [127:0] o_block,
  output logic         o_done
);
  logic [127:0] state_q;
  logic [3:0]   round_q;    // rodada em execucao (1 a 10)
  logic         decrypt_q;
  logic         busy_q;
  logic         done_q;
  logic         last;

  assign last = (round_q == 4'd10);

  // ========================================================
  // Round key: indice 0..10 na cifra e 10..0 na decifra
  // ========================================================
  always_comb begin
    if (busy_q)
      o_round = decrypt_q ? (4'd10 - round_q) : round_q;
    else
      o_round = i_decrypt ? 4'd10 : 4'd0;  // rodada 0, usada no start
  end

  // ========================================================
  // Rodada 0: AddRoundKey inicial
  // ========================================================
  logic [127:0] init_state;

  minisoc_aes_add_round_key u_ark_init (
    .i_state     (i_block),
    .i_round_key (i_round_key),
    .o_state     (init_state)
  );

  // ========================================================
  // Rodada direta: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
  // ========================================================
  logic [127:0] enc_sub, enc_shift, enc_mix, enc_out;

  minisoc_aes_sub_bytes u_sub_bytes (
    .i_state (state_q),
    .o_state (enc_sub)
  );

  minisoc_aes_shift_rows u_shift_rows (
    .i_state (enc_sub),
    .o_state (enc_shift)
  );

  minisoc_aes_mix_columns u_mix_columns (
    .i_state (enc_shift),
    .o_state (enc_mix)
  );

  // a rodada 10 nao tem MixColumns
  minisoc_aes_add_round_key u_ark_enc (
    .i_state     (last ? enc_shift : enc_mix),
    .i_round_key (i_round_key),
    .o_state     (enc_out)
  );

  // ========================================================
  // Rodada inversa: InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns
  // ========================================================
  logic [127:0] dec_shift, dec_sub, dec_ark, dec_mix, dec_out;

  minisoc_aes_inv_shift_rows u_inv_shift_rows (
    .i_state (state_q),
    .o_state (dec_shift)
  );

  minisoc_aes_inv_sub_bytes u_inv_sub_bytes (
    .i_state (dec_shift),
    .o_state (dec_sub)
  );

  minisoc_aes_add_round_key u_ark_dec (
    .i_state     (dec_sub),
    .i_round_key (i_round_key),
    .o_state     (dec_ark)
  );

  minisoc_aes_inv_mix_columns u_inv_mix_columns (
    .i_state (dec_ark),
    .o_state (dec_mix)
  );

  // a rodada 10 nao tem InvMixColumns
  assign dec_out = last ? dec_ark : dec_mix;

  // ========================================================
  // Controle: start carrega a rodada 0; uma rodada por ciclo
  // ========================================================
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      round_q   <= 4'd0;
      decrypt_q <= 1'b0;
      busy_q    <= 1'b0;
      done_q    <= 1'b0;
    end else begin
      done_q <= 1'b0;
      if (i_start) begin
        round_q   <= 4'd1;
        decrypt_q <= i_decrypt;
        busy_q    <= 1'b1;
      end else if (busy_q) begin
        round_q <= round_q + 4'd1;
        if (last) begin
          busy_q <= 1'b0;
          done_q <= 1'b1;
        end
      end
    end
  end

  // ========================================================
  // Registrador de estado (sem reset: dado)
  // ========================================================
  always_ff @(posedge i_clk) begin
    if (i_start)
      state_q <= init_state;
    else if (busy_q)
      state_q <= decrypt_q ? dec_out : enc_out;
  end

  assign o_block = state_q;
  assign o_done  = done_q;
endmodule
