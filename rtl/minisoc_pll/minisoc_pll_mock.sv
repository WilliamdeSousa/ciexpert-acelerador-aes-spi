// Modelo RTL de integração do PLL (Block Guide, seção 4.1).
// Não é uma macro de implementação física (LIM-PLL-01).
module minisoc_pll_mock #(
  parameter int unsigned LOCK_MIN  = 64,   // ciclos mínimos de clk até o lock
  parameter int unsigned LOCK_BITS = 8     // parte pseudoaleatória: 0 a 2^LOCK_BITS - 1
) (
  input  logic       i_clk,       // referência de 2 GHz
  input  logic       i_rst_n,
  input  logic       i_enable,    // PLL_ENABLE (domínio clk)
  input  logic [1:0] i_div_sel,   // PLL_DIV_SEL: /1, /2, /4, /8
  output logic       o_sys_clk,
  output logic       o_locked     // domínio clk
);
  localparam int unsigned CNT_W = $clog2(LOCK_MIN + (1 << LOCK_BITS));

  // ========================================================
  // LFSR de 16 bits (x^16 + x^14 + x^13 + x^11 + 1), sempre rodando
  // ========================================================
  logic [15:0] lfsr_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      lfsr_q <= 16'hACE1;
    else
      lfsr_q <= {lfsr_q[14:0], lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]};
  end

  // ========================================================
  // Aquisição: desabilitado, recarrega o tempo de lock; habilitado,
  // conta até zero e trava. O divisor só pode mudar antes do lock,
  // para que o clock de sistema não troque de frequência em operação.
  // ========================================================
  logic [CNT_W-1:0] lock_cnt_q;
  logic             locked_q;
  logic [1:0]       div_sel_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      lock_cnt_q <= '0;
      locked_q   <= 1'b0;
    end else if (!i_enable) begin
      lock_cnt_q <= CNT_W'(LOCK_MIN) + CNT_W'(lfsr_q[LOCK_BITS-1:0]);
      locked_q   <= 1'b0;
    end else if (!locked_q) begin
      if (lock_cnt_q == '0)
        locked_q <= 1'b1;
      else
        lock_cnt_q <= lock_cnt_q - 1'b1;
    end
  end

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      div_sel_q <= 2'b00;
    else if (!locked_q)
      div_sel_q <= i_div_sel;
  end

  // ========================================================
  // Divisores: contador parado em 0 enquanto não travado, para que
  // os clocks divididos comecem em nível baixo (sem pulso curto)
  // ========================================================
  logic [2:0] div_cnt_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      div_cnt_q <= '0;
    else if (!locked_q || !i_enable)  // !i_enable: sem borda extra ao desabilitar
      div_cnt_q <= '0;
    else
      div_cnt_q <= div_cnt_q + 3'd1;
  end

  // /1: enable atualizado na borda de descida, com clk em nível baixo,
  // para que o AND não gere pulso curto
  logic gate_q;

  always_ff @(negedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      gate_q <= 1'b0;
    else
      gate_q <= locked_q;
  end

  always_comb begin
    case (div_sel_q)
      2'b00:   o_sys_clk = i_clk & gate_q;
      2'b01:   o_sys_clk = div_cnt_q[0];
      2'b10:   o_sys_clk = div_cnt_q[1];
      default: o_sys_clk = div_cnt_q[2];
    endcase
  end

  assign o_locked = locked_q;
endmodule
