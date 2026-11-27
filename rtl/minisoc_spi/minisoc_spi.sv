module minisoc_spi #(
  parameter logic [31:0] VERSION = 32'h0001_0000  // v1.0.0
) (
  // domínio always-on
  input  logic         i_clk,
  input  logic         i_rst_n,

  // SPI (Mode 0, MSB-first)
  input  logic         i_spi_sclk,
  input  logic         i_spi_cs_n,
  input  logic         i_spi_mosi,
  output logic         o_spi_miso,

  // configuração do AES (domínio clk, estável durante a operação)
  output logic [127:0] o_cfg_key,
  output logic [127:0] o_cfg_iv,
  output logic [63:0]  o_cfg_counter,
  output logic [31:0]  o_cfg_num_blocks,
  output logic [2:0]   o_cfg_mode,
  output logic         o_cfg_decrypt,
  output logic         o_start_toggle,   // inverte a cada START = 1

  // status do AES (domínio sys_clk, sincronizado aqui)
  input  logic         i_aes_busy,
  input  logic         i_aes_done,
  input  logic         i_aes_error,
  input  logic [8:0]   i_aes_blocks_done_gray,

  // sistema
  output logic         o_mem_sel_aes,
  output logic         o_pll_enable,
  output logic [1:0]   o_pll_div_sel,
  input  logic         i_pll_locked      // assíncrono, sincronizado aqui
);
  // endereços (Block Guide, seção 6)
  localparam logic [5:0] A_KEY0        = 6'h00;
  localparam logic [5:0] A_KEY1        = 6'h01;
  localparam logic [5:0] A_KEY2        = 6'h02;
  localparam logic [5:0] A_KEY3        = 6'h03;
  localparam logic [5:0] A_IV0         = 6'h04;
  localparam logic [5:0] A_IV1         = 6'h05;
  localparam logic [5:0] A_IV2         = 6'h06;
  localparam logic [5:0] A_IV3         = 6'h07;
  localparam logic [5:0] A_COUNTER_HI  = 6'h08;
  localparam logic [5:0] A_COUNTER_LO  = 6'h09;
  localparam logic [5:0] A_NUM_BLOCKS  = 6'h0A;
  localparam logic [5:0] A_AES_CONTROL = 6'h0B;
  localparam logic [5:0] A_AES_STATUS  = 6'h0C;
  localparam logic [5:0] A_VERSION     = 6'h0D;
  localparam logic [5:0] A_SYS_CONTROL = 6'h0E;
  localparam logic [5:0] A_SYS_STATUS  = 6'h0F;

  // ========================================================
  // Domínio spi_sclk: recepção do frame de 40 bits
  // ========================================================
  // spi_cs_n = 1 zera o contador de bits (reset assíncrono)
  logic        sclk_rst_n;
  logic [5:0]  bit_cnt_q;    // bits recebidos no frame atual (0 a 39)
  logic [38:0] rx_sr_q;      // 39 primeiros bits do frame
  logic [39:0] frame_q;      // último frame completo (estável até o próximo)
  logic        frame_tgl_q;  // inverte a cada frame completo
  logic [31:0] rdata_q;      // dado de leitura (domínio clk, estável no 2º frame)
  logic        miso_q;

  assign sclk_rst_n = i_rst_n & ~i_spi_cs_n;

  logic frame_end;  // 40º bit sendo amostrado

  assign frame_end = (bit_cnt_q == 6'd39);

  always_ff @(posedge i_spi_sclk or negedge sclk_rst_n) begin
    if (!sclk_rst_n)
      bit_cnt_q <= 6'd0;
    else
      bit_cnt_q <= frame_end ? 6'd0 : bit_cnt_q + 6'd1;
  end

  // MOSI amostrado na borda de subida (sem reset: dado)
  always_ff @(posedge i_spi_sclk) begin
    rx_sr_q <= {rx_sr_q[37:0], i_spi_mosi};
    if (frame_end)
      frame_q <= {rx_sr_q, i_spi_mosi};
  end

  // frame completo: sinalizado por toggle, que só é zerado por rst_n
  always_ff @(posedge i_spi_sclk or negedge i_rst_n) begin
    if (!i_rst_n)
      frame_tgl_q <= 1'b0;
    else if (frame_end)
      frame_tgl_q <= ~frame_tgl_q;
  end

  // MISO atualizado na borda de descida. A resposta ocupa o campo
  // DATA do frame: os bits 39 a 32 saem em 0 e os bits 31 a 0 trazem
  // rdata_q, que só muda ao fim de um READ request (1º frame).
  logic [39:0] tx_word;
  assign tx_word = {8'h00, rdata_q};

  always_ff @(negedge i_spi_sclk or negedge sclk_rst_n) begin
    if (!sclk_rst_n)
      miso_q <= 1'b0;               // bit 39, já válido na descida de spi_cs_n
    else
      miso_q <= tx_word[6'd39 - bit_cnt_q];
  end

  assign o_spi_miso = i_spi_cs_n ? 1'b0 : miso_q;

  // ========================================================
  // CDC spi_sclk -> clk: toggle + 2 FF + detector de mudança
  // ========================================================
  logic [2:0] frame_sync_q;
  logic       frame_valid;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      frame_sync_q <= 3'b000;
    else
      frame_sync_q <= {frame_sync_q[1:0], frame_tgl_q};
  end

  assign frame_valid = frame_sync_q[2] ^ frame_sync_q[1];

  logic       rwb;
  logic [5:0] addr;
  logic [31:0] wdata;

  assign rwb   = frame_q[39];
  assign addr  = frame_q[38:33];
  assign wdata = frame_q[31:0];

  // ========================================================
  // CDC sys_clk/PLL -> clk: status com 2 FF
  // ========================================================
  // BLOCKS_DONE chega em código Gray: só 1 bit muda por incremento
  logic [12:0] status_meta_q, status_q;
  logic        aes_busy, aes_done, aes_error, pll_locked;
  logic [8:0]  blocks_done_gray, blocks_done;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      status_meta_q <= '0;
      status_q      <= '0;
    end else begin
      status_meta_q <= {i_aes_blocks_done_gray, i_aes_error, i_aes_done, i_aes_busy, i_pll_locked};
      status_q      <= status_meta_q;
    end
  end

  assign {blocks_done_gray, aes_error, aes_done, aes_busy, pll_locked} = status_q;

  // Gray -> binário: b[i] = g[8] ^ ... ^ g[i]
  always_comb begin
    blocks_done[8] = blocks_done_gray[8];
    for (int i = 7; i >= 0; i--)
      blocks_done[i] = blocks_done[i+1] ^ blocks_done_gray[i];
  end

  // ========================================================
  // Banco de registradores (domínio clk)
  // ========================================================
  logic [31:0] key_q [4];
  logic [31:0] iv_q  [4];
  logic [31:0] counter_hi_q, counter_lo_q;
  logic [31:0] num_blocks_q;
  logic [2:0]  mode_q;
  logic        decrypt_q;
  logic        start_tgl_q;
  logic        mem_sel_aes_q, pll_enable_q;
  logic [1:0]  pll_div_sel_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      for (int i = 0; i < 4; i++) begin
        key_q[i] <= '0;
        iv_q[i]  <= '0;
      end
      counter_hi_q  <= '0;
      counter_lo_q  <= '0;
      num_blocks_q  <= '0;
      mode_q        <= '0;
      decrypt_q     <= 1'b0;
      start_tgl_q   <= 1'b0;
      mem_sel_aes_q <= 1'b0;
      pll_enable_q  <= 1'b0;
      pll_div_sel_q <= '0;
    end else if (frame_valid && !rwb) begin
      // escrita; registradores R, NOP e endereços livres são ignorados
      case (addr)
        A_KEY0:        key_q[0]     <= wdata;
        A_KEY1:        key_q[1]     <= wdata;
        A_KEY2:        key_q[2]     <= wdata;
        A_KEY3:        key_q[3]     <= wdata;
        A_IV0:         iv_q[0]      <= wdata;
        A_IV1:         iv_q[1]      <= wdata;
        A_IV2:         iv_q[2]      <= wdata;
        A_IV3:         iv_q[3]      <= wdata;
        A_COUNTER_HI:  counter_hi_q <= wdata;
        A_COUNTER_LO:  counter_lo_q <= wdata;
        A_NUM_BLOCKS:  num_blocks_q <= wdata;
        A_AES_CONTROL: begin
          mode_q    <= wdata[4:2];
          decrypt_q <= wdata[1];
          if (wdata[0])
            start_tgl_q <= ~start_tgl_q;  // START: write-one-pulse
        end
        A_SYS_CONTROL: begin
          pll_div_sel_q <= wdata[3:2];
          pll_enable_q  <= wdata[1];
          mem_sel_aes_q <= wdata[0];
        end
        default: ;
      endcase
    end
  end

  // leitura: o READ request guarda o valor em rdata_q
  logic [31:0] rd_mux;

  always_comb begin
    case (addr)
      A_KEY0:        rd_mux = key_q[0];
      A_KEY1:        rd_mux = key_q[1];
      A_KEY2:        rd_mux = key_q[2];
      A_KEY3:        rd_mux = key_q[3];
      A_IV0:         rd_mux = iv_q[0];
      A_IV1:         rd_mux = iv_q[1];
      A_IV2:         rd_mux = iv_q[2];
      A_IV3:         rd_mux = iv_q[3];
      A_COUNTER_HI:  rd_mux = counter_hi_q;
      A_COUNTER_LO:  rd_mux = counter_lo_q;
      A_NUM_BLOCKS:  rd_mux = num_blocks_q;
      A_AES_CONTROL: rd_mux = {27'h0, mode_q, decrypt_q, 1'b0};  // START lido como 0
      A_AES_STATUS:  rd_mux = {20'h0, blocks_done, aes_error, aes_done, aes_busy};
      A_VERSION:     rd_mux = VERSION;
      A_SYS_CONTROL: rd_mux = {28'h0, pll_div_sel_q, pll_enable_q, mem_sel_aes_q};
      A_SYS_STATUS:  rd_mux = {31'h0, pll_locked};
      default:       rd_mux = 32'h0;
    endcase
  end

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      rdata_q <= '0;
    else if (frame_valid && rwb)
      rdata_q <= rd_mux;
  end

  // ========================================================
  // Saídas
  // ========================================================
  assign o_cfg_key        = {key_q[0], key_q[1], key_q[2], key_q[3]};
  assign o_cfg_iv         = {iv_q[0], iv_q[1], iv_q[2], iv_q[3]};
  assign o_cfg_counter    = {counter_hi_q, counter_lo_q};
  assign o_cfg_num_blocks = num_blocks_q;
  assign o_cfg_mode       = mode_q;
  assign o_cfg_decrypt    = decrypt_q;
  assign o_start_toggle   = start_tgl_q;
  assign o_mem_sel_aes    = mem_sel_aes_q;
  assign o_pll_enable     = pll_enable_q;
  assign o_pll_div_sel    = pll_div_sel_q;
endmodule
