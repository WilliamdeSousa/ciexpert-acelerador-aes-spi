// Memória compartilhada 1024 x 32 (Block Guide, seção 7).
// Single-port síncrona, sem reset no conteúdo. MEM_SEL_AES define
// quem possui o porto: endereço, dado, write-enable e clock vêm da
// interface MEMORY DATA (0) ou do AES engine (1).
module minisoc_memory (
  input  logic        i_rst_n,         // só para o mux de clock
  input  logic        i_mem_sel_aes,   // domínio clk, quase estático

  // interface MEMORY DATA
  input  logic        i_mem_clk,
  input  logic [9:0]  i_mem_addr,
  input  logic [31:0] i_mem_data,
  input  logic        i_mem_wr_en,

  // AES engine
  input  logic        i_sys_clk,
  input  logic [9:0]  i_aes_addr,
  input  logic [31:0] i_aes_data,
  input  logic        i_aes_wr_en,

  output logic [31:0] o_rdata          // vai à interface externa e ao AES
);
  // ========================================================
  // Mux de clock sem glitch
  // ========================================================
  // Cada lado sincroniza a seleção no próprio clock (borda de subida)
  // e só libera o seu enable na borda de descida, com o clock em 0,
  // depois de o outro lado ter desligado o dele.
  logic aes_s1_q, aes_en_q;
  logic ext_s1_q, ext_en_q;

  always_ff @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) aes_s1_q <= 1'b0;
    else          aes_s1_q <= i_mem_sel_aes & ~ext_en_q;
  end

  always_ff @(negedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) aes_en_q <= 1'b0;
    else          aes_en_q <= aes_s1_q;
  end

  always_ff @(posedge i_mem_clk or negedge i_rst_n) begin
    if (!i_rst_n) ext_s1_q <= 1'b0;
    else          ext_s1_q <= ~i_mem_sel_aes & ~aes_en_q;
  end

  always_ff @(negedge i_mem_clk or negedge i_rst_n) begin
    if (!i_rst_n) ext_en_q <= 1'b0;
    else          ext_en_q <= ext_s1_q;
  end

  logic mem_clk_g;

  assign mem_clk_g = (i_sys_clk & aes_en_q) | (i_mem_clk & ext_en_q);

  // ========================================================
  // Mux do porto: segue o clock que está habilitado
  // ========================================================
  logic [9:0]  addr;
  logic [31:0] wdata;
  logic        wr_en;

  assign addr  = aes_en_q ? i_aes_addr  : i_mem_addr;
  assign wdata = aes_en_q ? i_aes_data  : i_mem_data;
  assign wr_en = aes_en_q ? i_aes_wr_en : i_mem_wr_en;

  // ========================================================
  // Matriz de memória (sem reset)
  // ========================================================
  logic [31:0] mem_q [1024];
  logic [31:0] rdata_q;

  // wr_en = 1: escrita; wr_en = 0: leitura, dado no ciclo seguinte
  always_ff @(posedge mem_clk_g) begin
    if (wr_en)
      mem_q[addr] <= wdata;
    else
      rdata_q <= mem_q[addr];
  end

  assign o_rdata = rdata_q;
endmodule
