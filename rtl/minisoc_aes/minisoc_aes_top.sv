// AES engine e controlador de acesso em blocos à memória (Block Guide, seção 8).
// v1.0: modos ECB, CBC e CTR. PCBC, CFB e OFB são rejeitados com ERROR
// até a semana 10 (limitação conhecida).
module minisoc_aes_top (
  input  logic         i_clk,              // sys_clk
  input  logic         i_rst_n,            // reset do domínio sys_clk

  // configuração (domínio clk; estável desde antes do START)
  input  logic         i_start_toggle,
  input  logic [127:0] i_cfg_key,
  input  logic [127:0] i_cfg_iv,
  input  logic [63:0]  i_cfg_counter,
  input  logic [31:0]  i_cfg_num_blocks,
  input  logic [2:0]   i_cfg_mode,
  input  logic         i_cfg_decrypt,

  // status (sincronizado no domínio clk pelo minisoc_spi)
  output logic         o_busy,
  output logic         o_done,
  output logic         o_error,
  output logic [8:0]   o_blocks_done_gray,

  // porto da memória
  output logic [9:0]   o_mem_addr,
  output logic [31:0]  o_mem_data,
  output logic         o_mem_wr_en,
  input  logic [31:0]  i_mem_rdata
);
  localparam logic [2:0] MODE_ECB = 3'b000;
  localparam logic [2:0] MODE_CBC = 3'b001;
  localparam logic [2:0] MODE_CTR = 3'b101;

  typedef enum logic [2:0] {
    S_IDLE,    // espera START; DONE fica sticky
    S_CHECK,   // valida NUM_BLOCKS e MODE
    S_KEY,     // expansão de chave
    S_READ,    // lê as 4 palavras do bloco
    S_CIPHER,  // dispara o dp
    S_WAIT,    // espera o dp
    S_WRITE    // escreve as 4 palavras no mesmo endereço
  } state_t;

  state_t state_q;

  function automatic logic [8:0] bin2gray(input logic [8:0] b);
    return b ^ (b >> 1);
  endfunction

  // ========================================================
  // CDC do START: toggle + 2 FF + detector de mudança
  // ========================================================
  // Nos 3 primeiros ciclos após o reset a cadeia se carrega com o
  // valor atual do toggle; mudanças nesse intervalo são ignoradas.
  logic [2:0] start_sync_q;
  logic [1:0] warmup_q;
  logic       start_evt;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      start_sync_q <= 3'b000;
      warmup_q     <= 2'd0;
    end else begin
      start_sync_q <= {start_sync_q[1:0], i_start_toggle};
      if (warmup_q != 2'd3)
        warmup_q <= warmup_q + 2'd1;
    end
  end

  assign start_evt = (warmup_q == 2'd3) && (start_sync_q[2] ^ start_sync_q[1]);

  // ========================================================
  // Configuração capturada no START
  // ========================================================
  logic [127:0] key_q, iv_q;
  logic [63:0]  ctr_q;
  logic [31:0]  num_blocks_q;
  logic [2:0]   mode_q;
  logic         decrypt_q;

  logic         cfg_valid;
  assign cfg_valid = (num_blocks_q >= 32'd1) && (num_blocks_q <= 32'd256) &&
                     (mode_q == MODE_ECB || mode_q == MODE_CBC || mode_q == MODE_CTR);

  // ========================================================
  // Expansão de chave e datapath
  // ========================================================
  logic         kexp_start, kexp_ready;
  logic [3:0]   round;
  logic [127:0] round_key;
  logic         dp_start, dp_decrypt, dp_done;
  logic [127:0] dp_in, dp_out;

  assign kexp_start = (state_q == S_CHECK) && cfg_valid;

  minisoc_aes_key_exp u_key_exp (
    .i_clk       (i_clk),
    .i_rst_n     (i_rst_n),
    .i_start     (kexp_start),
    .i_key       (key_q),
    .i_round     (round),
    .o_round_key (round_key),
    .o_ready     (kexp_ready)
  );

  minisoc_aes_dp u_dp (
    .i_clk       (i_clk),
    .i_rst_n     (i_rst_n),
    .i_start     (dp_start),
    .i_decrypt   (dp_decrypt),
    .i_block     (dp_in),
    .o_round     (round),
    .i_round_key (round_key),
    .o_block     (dp_out),
    .o_done      (dp_done)
  );

  // ========================================================
  // Lógica dos modos
  // ========================================================
  logic [127:0] in_q;      // bloco lido da memória
  logic [127:0] out_q;     // bloco a escrever
  logic [127:0] chain_q;   // vetor de encadeamento do CBC
  logic [127:0] mode_out;

  assign dp_start   = (state_q == S_CIPHER);
  assign dp_decrypt = decrypt_q && (mode_q != MODE_CTR);  // CTR sempre cifra

  always_comb begin
    case (mode_q)
      MODE_CBC: dp_in = decrypt_q ? in_q : (in_q ^ chain_q);
      MODE_CTR: dp_in = iv_q ^ {64'h0, ctr_q};
      default:  dp_in = in_q;                             // ECB
    endcase
  end

  always_comb begin
    case (mode_q)
      MODE_CBC: mode_out = decrypt_q ? (dp_out ^ chain_q) : dp_out;
      MODE_CTR: mode_out = in_q ^ dp_out;
      default:  mode_out = dp_out;                        // ECB
    endcase
  end

  // ========================================================
  // FSM
  // ========================================================
  logic [7:0] blk_q;        // índice do bloco atual (0 a 255)
  logic [2:0] word_q;       // contador de palavras na leitura/escrita
  logic [8:0] blocks_done_q;
  logic [8:0] blocks_done_gray_q;  // mesmo valor em Gray, para o CDC
  logic       busy_q, done_q, error_q;
  logic       last_blk;

  assign last_blk = ({1'b0, blk_q} == num_blocks_q[8:0] - 9'd1);

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      state_q       <= S_IDLE;
      blk_q         <= '0;
      word_q        <= '0;
      blocks_done_q <= '0;
      blocks_done_gray_q <= '0;
      busy_q        <= 1'b0;
      done_q        <= 1'b0;
      error_q       <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (start_evt) begin  // START aceito: limpa o status
            busy_q        <= 1'b1;
            done_q        <= 1'b0;
            error_q       <= 1'b0;
            blocks_done_q <= '0;
            blocks_done_gray_q <= '0;
            state_q       <= S_CHECK;
          end
        end

        S_CHECK: begin
          if (cfg_valid) begin
            blk_q   <= '0;
            state_q <= S_KEY;
          end else begin        // configuração inválida: encerra sem processar
            error_q <= 1'b1;
            done_q  <= 1'b1;
            busy_q  <= 1'b0;
            state_q <= S_IDLE;
          end
        end

        S_KEY: begin
          if (kexp_ready) begin
            word_q  <= '0;
            state_q <= S_READ;
          end
        end

        // endereço na palavra word_q; o dado volta um ciclo depois
        S_READ: begin
          word_q <= word_q + 3'd1;
          if (word_q == 3'd4)
            state_q <= S_CIPHER;
        end

        S_CIPHER: state_q <= S_WAIT;

        S_WAIT: begin
          if (dp_done) begin
            word_q  <= '0;
            state_q <= S_WRITE;
          end
        end

        S_WRITE: begin
          word_q <= word_q + 3'd1;
          if (word_q == 3'd3) begin
            blocks_done_q      <= blocks_done_q + 9'd1;
            blocks_done_gray_q <= bin2gray(blocks_done_q + 9'd1);
            word_q        <= '0;
            if (last_blk) begin
              done_q  <= 1'b1;
              busy_q  <= 1'b0;
              state_q <= S_IDLE;
            end else begin
              blk_q   <= blk_q + 8'd1;
              state_q <= S_READ;
            end
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // ========================================================
  // Registradores de dado (sem reset)
  // ========================================================
  always_ff @(posedge i_clk) begin
    if (state_q == S_IDLE && start_evt) begin
      key_q        <= i_cfg_key;
      iv_q         <= i_cfg_iv;
      ctr_q        <= i_cfg_counter;
      num_blocks_q <= i_cfg_num_blocks;
      mode_q       <= i_cfg_mode;
      decrypt_q    <= i_cfg_decrypt;
    end

    if (state_q == S_CHECK)
      chain_q <= iv_q;

    // palavra w lida no ciclo word_q = w + 1 (Word 0 em [127:96])
    if (state_q == S_READ && word_q != 3'd0)
      in_q[127 - 32*(word_q - 3'd1) -: 32] <= i_mem_rdata;

    if (state_q == S_WAIT && dp_done) begin
      out_q <= mode_out;
      if (mode_q == MODE_CBC)
        chain_q <= decrypt_q ? in_q : dp_out;
      if (mode_q == MODE_CTR)
        ctr_q <= ctr_q + 64'd1;
    end
  end

  // ========================================================
  // Porto da memória: bloco i nos endereços 4i a 4i+3
  // ========================================================
  assign o_mem_addr  = {blk_q, word_q[1:0]};
  assign o_mem_wr_en = (state_q == S_WRITE);
  assign o_mem_data  = out_q[127 - 32*word_q[1:0] -: 32];

  // ========================================================
  // Status: BLOCKS_DONE sai em Gray direto de um registrador
  // (1 bit muda por incremento) e muda na mesma borda que DONE
  // ========================================================
  assign o_busy             = busy_q;
  assign o_done             = done_q;
  assign o_error            = error_q;
  assign o_blocks_done_gray = blocks_done_gray_q;
endmodule
