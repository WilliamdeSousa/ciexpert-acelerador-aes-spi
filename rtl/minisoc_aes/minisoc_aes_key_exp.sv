module minisoc_aes_key_exp (
  input  logic         i_clk,
  input  logic         i_rst_n,
  input  logic         i_start,
  input  logic [127:0] i_key,
  input  logic [3:0]   i_round,
  output logic [127:0] o_round_key,
  output logic         o_ready
);
  // constante de rodada: Rcon[i] = x^(i-1) em GF(2^8)
  function automatic logic [7:0] rcon(input logic [3:0] i);
    case (i)
      4'd1:    return 8'h01;
      4'd2:    return 8'h02;
      4'd3:    return 8'h04;
      4'd4:    return 8'h08;
      4'd5:    return 8'h10;
      4'd6:    return 8'h20;
      4'd7:    return 8'h40;
      4'd8:    return 8'h80;
      4'd9:    return 8'h1b;
      4'd10:   return 8'h36;
      default: return 8'h00;
    endcase
  endfunction

  logic [127:0] rk_q [11];  // round keys 0 a 10
  logic [127:0] last_q;     // ultima round key calculada
  logic [3:0]   idx_q;      // indice da proxima round key (1 a 10)
  logic         busy_q;
  logic         ready_q;

  // ========================================================
  // Proxima round key a partir de last_q
  // ========================================================
  logic [31:0]  w0, w1, w2, w3;
  logic [31:0]  rot_word, sub_word, temp;
  logic [127:0] next_key;

  assign {w0, w1, w2, w3} = last_q;

  // RotWord: [a b c d] -> [b c d a]
  assign rot_word = {w3[23:0], w3[31:24]};

  // SubWord: S-box em cada byte
  for (genvar n = 0; n < 4; n++) begin : g_sub_word
    minisoc_aes_sbox u_sbox (
      .i_data (rot_word[31-8*n -: 8]),
      .o_data (sub_word[31-8*n -: 8])
    );
  end

  assign temp = sub_word ^ {rcon(idx_q), 24'h0};

  assign next_key[127:96] = w0 ^ temp;
  assign next_key[ 95:64] = w1 ^ next_key[127:96];
  assign next_key[ 63:32] = w2 ^ next_key[ 95:64];
  assign next_key[ 31: 0] = w3 ^ next_key[ 63:32];

  // ========================================================
  // Controle: uma round key por ciclo apos o start
  // ========================================================
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      idx_q   <= 4'd0;
      busy_q  <= 1'b0;
      ready_q <= 1'b0;
    end else if (i_start) begin
      idx_q   <= 4'd1;
      busy_q  <= 1'b1;
      ready_q <= 1'b0;
    end else if (busy_q) begin
      idx_q <= idx_q + 4'd1;
      if (idx_q == 4'd10) begin
        busy_q  <= 1'b0;
        ready_q <= 1'b1;
      end
    end
  end

  // ========================================================
  // Armazenamento das round keys (sem reset: dado)
  // ========================================================
  always_ff @(posedge i_clk) begin
    if (i_start) begin
      rk_q[0] <= i_key;
      last_q  <= i_key;
    end else if (busy_q) begin
      rk_q[idx_q] <= next_key;
      last_q      <= next_key;
    end
  end

  assign o_round_key = (i_round <= 4'd10) ? rk_q[i_round] : 128'h0;
  assign o_ready     = ready_q;
endmodule
