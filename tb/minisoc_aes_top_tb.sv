// ==========================================================
// Testbench de bloco: AES engine com a memória compartilhada
// ==========================================================
// minisoc_aes_top e minisoc_memory ligados como no minisoc_top.
// A configuração é aplicada direto nas entradas (papel do minisoc_spi),
// e a memória é carregada e lida pela interface MEMORY DATA.
// Para cada caso de tb/vectors (gerados por scripts/gen_aes_top_vectors.py):
//   1. escreve a imagem de entrada (1024 palavras) com MEM_SEL_AES = 0;
//   2. passa a memória ao AES, dá START e espera DONE;
//   3. devolve a memória e compara as 1024 palavras com o modelo;
//   4. confere BUSY, DONE, ERROR e BLOCKS_DONE.
// Depois, confere ERROR nas configurações inválidas.
`timescale 1ns/1ps

module minisoc_aes_top_tb;

  localparam int NUM_CASES = 18;
  localparam int MEM_WORDS = 1024;
  localparam real SYS_HALF = 0.5;   // sys_clk de 1 GHz
  localparam real MEM_HALF = 2.5;   // mem_clk de 200 MHz

  // ========================================================
  // Sinais e DUTs
  // ========================================================
  logic         sys_clk = 1'b0, mem_clk = 1'b0;
  logic         rst_n;
  logic         start_toggle;
  logic [127:0] cfg_key, cfg_iv;
  logic [63:0]  cfg_counter;
  logic [31:0]  cfg_num_blocks;
  logic [2:0]   cfg_mode;
  logic         cfg_decrypt;
  logic         busy, done, error;
  logic [8:0]   blocks_done_gray;
  logic [9:0]   aes_addr;
  logic [31:0]  aes_data, rdata;
  logic         aes_wr_en;
  logic         mem_sel_aes;
  logic [9:0]   mem_addr;
  logic [31:0]  mem_data;
  logic         mem_wr_en;

  always #(SYS_HALF) sys_clk = ~sys_clk;
  always #(MEM_HALF) mem_clk = ~mem_clk;

  minisoc_aes_top u_aes (
    .i_clk              (sys_clk),
    .i_rst_n            (rst_n),
    .i_start_toggle     (start_toggle),
    .i_cfg_key          (cfg_key),
    .i_cfg_iv           (cfg_iv),
    .i_cfg_counter      (cfg_counter),
    .i_cfg_num_blocks   (cfg_num_blocks),
    .i_cfg_mode         (cfg_mode),
    .i_cfg_decrypt      (cfg_decrypt),
    .o_busy             (busy),
    .o_done             (done),
    .o_error            (error),
    .o_blocks_done_gray (blocks_done_gray),
    .o_mem_addr         (aes_addr),
    .o_mem_data         (aes_data),
    .o_mem_wr_en        (aes_wr_en),
    .i_mem_rdata        (rdata)
  );

  minisoc_memory u_mem (
    .i_rst_n       (rst_n),
    .i_mem_sel_aes (mem_sel_aes),
    .i_mem_clk     (mem_clk),
    .i_mem_addr    (mem_addr),
    .i_mem_data    (mem_data),
    .i_mem_wr_en   (mem_wr_en),
    .i_sys_clk     (sys_clk),
    .i_aes_addr    (aes_addr),
    .i_aes_data    (aes_data),
    .i_aes_wr_en   (aes_wr_en),
    .o_rdata       (rdata)
  );

  // ========================================================
  // Vetores
  // ========================================================
  logic [127:0] cfg_vec [NUM_CASES * 6];
  logic [31:0]  mem_in  [NUM_CASES * MEM_WORDS];
  logic [31:0]  mem_out [NUM_CASES * MEM_WORDS];
  string        case_name [NUM_CASES];

  initial begin
    int fd;
    $readmemh("tb/vectors/aes_top_cfg.hex", cfg_vec);
    $readmemh("tb/vectors/aes_top_mem_in.hex", mem_in);
    $readmemh("tb/vectors/aes_top_mem_out.hex", mem_out);
    fd = $fopen("tb/vectors/aes_top_cases.txt", "r");
    for (int i = 0; i < NUM_CASES; i++) begin
      void'($fgets(case_name[i], fd));
      case_name[i] = case_name[i].substr(4, case_name[i].len() - 2);
    end
    $fclose(fd);
  end

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

  function automatic logic [8:0] gray2bin(input logic [8:0] g);
    logic [8:0] b;
    b[8] = g[8];
    for (int i = 7; i >= 0; i--) b[i] = b[i+1] ^ g[i];
    return b;
  endfunction

  // ========================================================
  // Interface MEMORY DATA (entradas mudam na borda de descida)
  // ========================================================
  task automatic mem_write(input logic [9:0] addr, input logic [31:0] data);
    @(negedge mem_clk);
    mem_addr  = addr;
    mem_data  = data;
    mem_wr_en = 1'b1;
    @(negedge mem_clk);
    mem_wr_en = 1'b0;
  endtask

  // leitura síncrona: o dado sai na borda seguinte ao endereço
  task automatic mem_read(input logic [9:0] addr, output logic [31:0] data);
    @(negedge mem_clk);
    mem_addr  = addr;
    mem_wr_en = 1'b0;
    @(negedge mem_clk);
    data = rdata;
  endtask

  // troca de ownership com o AES ocioso e sem acesso externo
  task automatic set_owner(input logic aes);
    @(negedge mem_clk);
    mem_sel_aes = aes;
    repeat (4) @(negedge mem_clk);
  endtask

  // ========================================================
  // Caso do modelo de referência
  // ========================================================
  task automatic run_case(int c);
    logic [31:0] d;
    int n, mism;
    logic done_cleared;
    n              = int'(cfg_vec[6*c + 2]);
    cfg_mode       = cfg_vec[6*c][2:0];
    cfg_decrypt    = cfg_vec[6*c + 1][0];
    cfg_num_blocks = cfg_vec[6*c + 2][31:0];
    cfg_key        = cfg_vec[6*c + 3];
    cfg_iv         = cfg_vec[6*c + 4];
    cfg_counter    = cfg_vec[6*c + 5][63:0];

    set_owner(1'b0);
    for (int a = 0; a < MEM_WORDS; a++)
      mem_write(a[9:0], mem_in[c*MEM_WORDS + a]);
    set_owner(1'b1);

    // START, conferindo que DONE (sticky da operação anterior) é limpo
    @(negedge sys_clk) start_toggle = ~start_toggle;
    done_cleared = 1'b0;
    for (int i = 0; i < 20; i++) begin
      @(negedge sys_clk);
      if (busy && !done) done_cleared = 1'b1;
    end
    check($sformatf("%s: BUSY = 1 e DONE limpo após START", case_name[c]), {31'h0, done_cleared}, 32'h1);
    for (int i = 0; i < 30 * n + 100 && !done; i++)
      @(negedge sys_clk);

    check($sformatf("%s: DONE", case_name[c]), {31'h0, done}, 32'h1);
    check($sformatf("%s: BUSY", case_name[c]), {31'h0, busy}, 32'h0);
    check($sformatf("%s: ERROR", case_name[c]), {31'h0, error}, 32'h0);
    check($sformatf("%s: BLOCKS_DONE", case_name[c]), {23'h0, gray2bin(blocks_done_gray)}, n);

    // DONE é sticky
    repeat (20) @(negedge sys_clk);
    check($sformatf("%s: DONE sticky", case_name[c]), {31'h0, done}, 32'h1);

    set_owner(1'b0);
    mism = 0;
    for (int a = 0; a < MEM_WORDS; a++) begin
      mem_read(a[9:0], d);
      checks++;
      if (d !== mem_out[c*MEM_WORDS + a]) begin
        errors++;
        if (mism++ < 4)
          $display("[FAIL] %s: mem[%0d] = %08h, esperado %08h",
                   case_name[c], a, d, mem_out[c*MEM_WORDS + a]);
      end
    end
  endtask

  // ========================================================
  // Configurações inválidas: ERROR, DONE e memória intacta
  // ========================================================
  task automatic run_invalid(string what, logic [2:0] mode, logic [31:0] num_blocks);
    logic [31:0] d;
    cfg_mode       = mode;
    cfg_decrypt    = 1'b0;
    cfg_num_blocks = num_blocks;
    set_owner(1'b0);
    for (int a = 0; a < 8; a++)
      mem_write(a[9:0], 32'hA5A5_0000 | a);
    set_owner(1'b1);
    @(negedge sys_clk) start_toggle = ~start_toggle;
    for (int i = 0; i < 50 && !(done && !busy && error); i++)
      @(negedge sys_clk);
    check($sformatf("%s: ERROR", what), {31'h0, error}, 32'h1);
    check($sformatf("%s: DONE", what), {31'h0, done}, 32'h1);
    check($sformatf("%s: BUSY", what), {31'h0, busy}, 32'h0);
    check($sformatf("%s: BLOCKS_DONE", what), {23'h0, gray2bin(blocks_done_gray)}, 32'h0);
    set_owner(1'b0);
    for (int a = 0; a < 8; a++) begin
      mem_read(a[9:0], d);
      check($sformatf("%s: mem[%0d] intacta", what, a), d, 32'hA5A5_0000 | a);
    end
  endtask

  initial begin
    $fsdbDumpfile("minisoc_aes_top_tb.fsdb");
    $fsdbDumpvars(0, minisoc_aes_top_tb);
  end

  initial begin
    rst_n          = 1'b0;
    start_toggle   = 1'b0;
    cfg_key        = '0;
    cfg_iv         = '0;
    cfg_counter    = '0;
    cfg_num_blocks = '0;
    cfg_mode       = '0;
    cfg_decrypt    = 1'b0;
    mem_sel_aes    = 1'b0;
    mem_addr       = '0;
    mem_data       = '0;
    mem_wr_en      = 1'b0;
    #20 rst_n = 1'b1;
    #20;

    check("BUSY após reset", {31'h0, busy}, 32'h0);
    check("DONE após reset", {31'h0, done}, 32'h0);

    for (int c = 0; c < NUM_CASES; c++) begin
      run_case(c);
      $display("caso %2d concluído: %s", c, case_name[c]);
    end

    run_invalid("NUM_BLOCKS = 0",      3'b000, 32'd0);
    run_invalid("NUM_BLOCKS = 257",    3'b001, 32'd257);
    run_invalid("NUM_BLOCKS = 0x1000", 3'b101, 32'h1000);
    run_invalid("MODE = 110",          3'b110, 32'd1);
    run_invalid("MODE = 111",          3'b111, 32'd1);
    run_invalid("MODE = PCBC (v1.0)",  3'b010, 32'd1);
    run_invalid("MODE = CFB (v1.0)",   3'b011, 32'd1);
    run_invalid("MODE = OFB (v1.0)",   3'b100, 32'd1);

    // uma operação válida depois do ERROR limpa o ERROR
    run_case(0);
    check("ERROR limpo por um START válido", {31'h0, error}, 32'h0);

    $display("==========================================================");
    if (errors == 0)
      $display("PASS: %0d verificações, 0 erros", checks);
    else
      $display("FAIL: %0d verificações, %0d erros", checks, errors);
    $display("==========================================================");
    $finish;
  end

endmodule
