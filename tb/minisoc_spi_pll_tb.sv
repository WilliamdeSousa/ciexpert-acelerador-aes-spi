// ==========================================================
// Testbench dirigido: SPI front-end e PLL mock
// ==========================================================
// minisoc_spi e minisoc_pll_mock ligados como no minisoc_top
// (PLL_ENABLE, PLL_DIV_SEL e PLL_LOCKED). Um mestre SPI Mode 0
// de 40 bits verifica:
//   - escrita e leitura de todos os registradores R/W;
//   - registradores R não alterados por escrita;
//   - AES_STATUS refletindo o status do AES (BLOCKS_DONE em Gray);
//   - START como write-one-pulse;
//   - NOP e endereços livres;
//   - PLL travando nos quatro divisores, com sys_clk parado antes
//     do lock e na frequência certa depois (passos 8 e 9, seção 9).
`timescale 1ns/1ps

module minisoc_spi_pll_tb;

  localparam real CLK_HALF  = 0.25;  // clk de 2 GHz
  localparam real SCLK_HALF = 20.0;  // spi_sclk de 25 MHz
  localparam logic [31:0] VERSION = 32'h0001_0000;

  // endereços
  localparam logic [5:0] A_AES_CONTROL = 6'h0B;
  localparam logic [5:0] A_AES_STATUS  = 6'h0C;
  localparam logic [5:0] A_VERSION     = 6'h0D;
  localparam logic [5:0] A_SYS_CONTROL = 6'h0E;
  localparam logic [5:0] A_SYS_STATUS  = 6'h0F;
  localparam logic [5:0] A_NOP         = 6'h3F;

  // ========================================================
  // Sinais e DUTs
  // ========================================================
  logic         clk = 1'b0;
  logic         rst_n;
  logic         spi_sclk, spi_cs_n, spi_mosi, spi_miso;
  logic [127:0] cfg_key, cfg_iv;
  logic [63:0]  cfg_counter;
  logic [31:0]  cfg_num_blocks;
  logic [2:0]   cfg_mode;
  logic         cfg_decrypt, start_toggle;
  logic         aes_busy, aes_done, aes_error;
  logic [8:0]   aes_blocks_done_gray;
  logic         mem_sel_aes, pll_enable, pll_locked, sys_clk;
  logic [1:0]   pll_div_sel;

  always #(CLK_HALF) clk = ~clk;

  minisoc_spi #(.VERSION(VERSION)) u_spi (
    .i_clk                  (clk),
    .i_rst_n                (rst_n),
    .i_spi_sclk             (spi_sclk),
    .i_spi_cs_n             (spi_cs_n),
    .i_spi_mosi             (spi_mosi),
    .o_spi_miso             (spi_miso),
    .o_cfg_key              (cfg_key),
    .o_cfg_iv               (cfg_iv),
    .o_cfg_counter          (cfg_counter),
    .o_cfg_num_blocks       (cfg_num_blocks),
    .o_cfg_mode             (cfg_mode),
    .o_cfg_decrypt          (cfg_decrypt),
    .o_start_toggle         (start_toggle),
    .i_aes_busy             (aes_busy),
    .i_aes_done             (aes_done),
    .i_aes_error            (aes_error),
    .i_aes_blocks_done_gray (aes_blocks_done_gray),
    .o_mem_sel_aes          (mem_sel_aes),
    .o_pll_enable           (pll_enable),
    .o_pll_div_sel          (pll_div_sel),
    .i_pll_locked           (pll_locked)
  );

  minisoc_pll_mock u_pll (
    .i_clk     (clk),
    .i_rst_n   (rst_n),
    .i_enable  (pll_enable),
    .i_div_sel (pll_div_sel),
    .o_sys_clk (sys_clk),
    .o_locked  (pll_locked)
  );

  // ========================================================
  // Verificação
  // ========================================================
  int checks = 0;
  int errors = 0;

  task automatic check(string what, logic [31:0] got, logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("[FAIL] %s: obtido %08h, esperado %08h", what, got, exp);
    end
  endtask

  // ========================================================
  // Mestre SPI: Mode 0, MSB-first, 40 bits
  // ========================================================
  // MOSI muda com sclk baixo; MISO é amostrado na borda de subida
  task automatic spi_xfer(input logic [39:0] tx, output logic [39:0] rx);
    spi_cs_n = 1'b0;
    #(SCLK_HALF);
    for (int i = 39; i >= 0; i--) begin
      spi_mosi = tx[i];
      #(SCLK_HALF);
      spi_sclk = 1'b1;
      rx[i]    = spi_miso;
      #(SCLK_HALF);
      spi_sclk = 1'b0;
    end
    #(SCLK_HALF);
    spi_cs_n = 1'b1;
    #(2 * SCLK_HALF);  // intervalo entre transações
  endtask

  task automatic spi_write(input logic [5:0] addr, input logic [31:0] data);
    logic [39:0] rx;
    spi_xfer({1'b0, addr, 1'b0, data}, rx);
  endtask

  // leitura em duas transações: READ request e retorno com o NOP
  task automatic spi_read(input logic [5:0] addr, output logic [31:0] data);
    logic [39:0] rx;
    spi_xfer({1'b1, addr, 1'b0, 32'h0}, rx);
    spi_xfer({1'b1, A_NOP, 1'b0, 32'h0}, rx);
    check($sformatf("bits 39:32 do retorno (addr %02h)", addr), {24'h0, rx[39:32]}, 32'h0);
    data = rx[31:0];
  endtask

  function automatic logic [8:0] bin2gray(input logic [8:0] b);
    return b ^ (b >> 1);
  endfunction

  // ========================================================
  // Testes
  // ========================================================
  logic [31:0] wval [11];  // valores escritos em 0x00 a 0x0A
  logic [31:0] rdata;

  // registradores R/W de 32 bits: 0x00 a 0x0A
  task automatic test_rw_regs();
    for (int a = 0; a <= 10; a++) begin
      wval[a] = $urandom;
      spi_write(a[5:0], wval[a]);
    end
    for (int a = 0; a <= 10; a++) begin
      spi_read(a[5:0], rdata);
      check($sformatf("leitura do registrador %02h", a), rdata, wval[a]);
    end
    // saídas de configuração
    check("cfg_key[127:96]", cfg_key[127:96], wval[0]);
    check("cfg_key[95:64]",  cfg_key[95:64],  wval[1]);
    check("cfg_key[63:32]",  cfg_key[63:32],  wval[2]);
    check("cfg_key[31:0]",   cfg_key[31:0],   wval[3]);
    check("cfg_iv[127:96]",  cfg_iv[127:96],  wval[4]);
    check("cfg_iv[95:64]",   cfg_iv[95:64],   wval[5]);
    check("cfg_iv[63:32]",   cfg_iv[63:32],   wval[6]);
    check("cfg_iv[31:0]",    cfg_iv[31:0],    wval[7]);
    check("cfg_counter[63:32]", cfg_counter[63:32], wval[8]);
    check("cfg_counter[31:0]",  cfg_counter[31:0],  wval[9]);
    check("cfg_num_blocks", cfg_num_blocks, wval[10]);

    // AES_CONTROL: MODE e DECRYPT, sem START (bits reservados lidos em 0)
    spi_write(A_AES_CONTROL, 32'hFFFF_FFFE);
    spi_read(A_AES_CONTROL, rdata);
    check("AES_CONTROL", rdata, 32'h0000_001E);
    check("cfg_mode", {29'h0, cfg_mode}, 32'h7);
    check("cfg_decrypt", {31'h0, cfg_decrypt}, 32'h1);
    spi_write(A_AES_CONTROL, 32'h0000_0014);  // MODE = CTR, DECRYPT = 0
    spi_read(A_AES_CONTROL, rdata);
    check("AES_CONTROL (CTR)", rdata, 32'h0000_0014);

    // SYSTEM_CONTROL: PLL_ENABLE fica em 0 aqui
    spi_write(A_SYS_CONTROL, 32'hFFFF_FFFD);
    spi_read(A_SYS_CONTROL, rdata);
    check("SYSTEM_CONTROL", rdata, 32'h0000_000D);
    check("mem_sel_aes", {31'h0, mem_sel_aes}, 32'h1);
    check("pll_div_sel", {30'h0, pll_div_sel}, 32'h3);
    spi_write(A_SYS_CONTROL, 32'h0000_0000);
  endtask

  // registradores somente leitura, NOP e endereços livres
  task automatic test_ro_regs();
    spi_write(A_AES_STATUS, 32'hFFFF_FFFF);
    spi_write(A_VERSION,    32'h1234_5678);
    spi_write(A_SYS_STATUS, 32'hFFFF_FFFF);
    spi_read(A_AES_STATUS, rdata);
    check("AES_STATUS após escrita", rdata, 32'h0);
    spi_read(A_VERSION, rdata);
    check("VERSION após escrita", rdata, VERSION);
    spi_read(A_SYS_STATUS, rdata);
    check("SYSTEM_STATUS após escrita", rdata, 32'h0);

    // escrita no NOP e em endereços livres não altera nada
    spi_write(A_NOP, 32'hDEAD_BEEF);
    spi_write(6'h10, 32'hDEAD_BEEF);
    spi_write(6'h2A, 32'hDEAD_BEEF);
    for (int a = 0; a <= 10; a++) begin
      spi_read(a[5:0], rdata);
      check($sformatf("registrador %02h após escritas inválidas", a), rdata, wval[a]);
    end
    spi_read(6'h10, rdata);
    check("endereço livre 0x10", rdata, 32'h0);
    spi_read(6'h2A, rdata);
    check("endereço livre 0x2A", rdata, 32'h0);
  endtask

  // AES_STATUS: BUSY, DONE, ERROR e BLOCKS_DONE (em Gray na entrada)
  task automatic test_aes_status();
    int unsigned bd_list [5] = '{0, 1, 4, 255, 256};
    foreach (bd_list[i]) begin
      logic [8:0] bd;
      logic [2:0] flags;
      bd    = bd_list[i][8:0];
      flags = 3'($urandom);
      {aes_error, aes_done, aes_busy} = flags;
      aes_blocks_done_gray = bin2gray(bd);
      spi_read(A_AES_STATUS, rdata);
      check($sformatf("AES_STATUS (BLOCKS_DONE = %0d)", bd), rdata, {20'h0, bd, flags});
    end
    {aes_error, aes_done, aes_busy} = 3'b000;
    aes_blocks_done_gray = '0;
  endtask

  // START: write-one-pulse
  task automatic test_start();
    logic tgl;
    tgl = start_toggle;
    spi_write(A_AES_CONTROL, 32'h0000_0001);  // START, MODE = ECB
    check("START inverte o toggle", {31'h0, start_toggle}, {31'h0, ~tgl});
    spi_read(A_AES_CONTROL, rdata);
    check("START lido como 0", rdata, 32'h0);
    spi_write(A_AES_CONTROL, 32'h0000_0002);  // DECRYPT, sem START
    check("escrita sem START não inverte", {31'h0, start_toggle}, {31'h0, ~tgl});
    spi_write(A_AES_CONTROL, 32'h0000_0007);  // START de novo
    check("segundo START", {31'h0, start_toggle}, {31'h0, tgl});
  endtask

  // PLL: enable, espera PLL_LOCKED pelo SPI e mede o sys_clk
  int sys_edges;
  always @(posedge sys_clk) sys_edges++;

  task automatic test_pll(input logic [1:0] div);
    realtime t0, t1, exp_period;
    int polls;
    exp_period = 2.0 * CLK_HALF * (1 << div);

    spi_write(A_SYS_CONTROL, 32'h0);  // desabilita
    check($sformatf("/%0d: locked em 0 desabilitado", 1 << div), {31'h0, pll_locked}, 32'h0);
    sys_edges = 0;
    #50;
    check($sformatf("/%0d: sys_clk parado desabilitado", 1 << div), sys_edges, 0);

    // passo 8: PLL_DIV_SEL e PLL_ENABLE na mesma escrita
    spi_write(A_SYS_CONTROL, {28'h0, div, 2'b10});
    // passo 9: lê SYSTEM_STATUS até PLL_LOCKED = 1
    polls = 0;
    do begin
      spi_read(A_SYS_STATUS, rdata);
      polls++;
    end while (rdata[0] !== 1'b1 && polls < 20);
    check($sformatf("/%0d: PLL_LOCKED", 1 << div), rdata, 32'h1);

    // frequência do sys_clk
    @(posedge sys_clk) t0 = $realtime;
    repeat (8) @(posedge sys_clk);
    t1 = $realtime;
    checks++;
    if ((t1 - t0) / 8 != exp_period) begin
      errors++;
      $display("[FAIL] /%0d: período do sys_clk %0.3f ns, esperado %0.3f ns",
               1 << div, (t1 - t0) / 8, exp_period);
    end
  endtask

  // sys_clk não pode pulsar antes do lock
  always @(posedge sys_clk) begin
    if (!pll_locked) begin
      errors++;
      $display("[FAIL] borda de sys_clk com PLL_LOCKED = 0 em %0t", $realtime);
    end
  end

  // tempo de aquisição: medido em ciclos de clk entre enable e locked
  int lock_cycles;
  always @(posedge clk) begin
    if (pll_enable && !pll_locked) lock_cycles++;
    else if (!pll_enable) lock_cycles = 0;
  end

  initial begin
    $fsdbDumpfile("minisoc_spi_pll_tb.fsdb");
    $fsdbDumpvars(0, minisoc_spi_pll_tb);
  end

  initial begin
    rst_n                = 1'b0;
    spi_sclk             = 1'b0;
    spi_cs_n             = 1'b1;
    spi_mosi             = 1'b0;
    aes_busy             = 1'b0;
    aes_done             = 1'b0;
    aes_error            = 1'b0;
    aes_blocks_done_gray = '0;
    #10 rst_n = 1'b1;
    #10;

    spi_read(A_VERSION, rdata);
    check("VERSION", rdata, VERSION);
    spi_read(A_SYS_STATUS, rdata);
    check("PLL_LOCKED após reset", rdata, 32'h0);

    test_rw_regs();
    test_ro_regs();
    test_aes_status();
    test_start();
    for (int d = 0; d < 4; d++) begin
      test_pll(d[1:0]);
      $display("PLL /%0d travou após %0d ciclos de clk", 1 << d, lock_cycles);
    end

    // desabilitar derruba o lock
    spi_write(A_SYS_CONTROL, 32'h0);
    spi_read(A_SYS_STATUS, rdata);
    check("PLL_LOCKED após desabilitar", rdata, 32'h0);

    $display("==========================================================");
    if (errors == 0)
      $display("PASS: %0d verificações, 0 erros", checks);
    else
      $display("FAIL: %0d verificações, %0d erros", checks, errors);
    $display("==========================================================");
    $finish;
  end

endmodule
