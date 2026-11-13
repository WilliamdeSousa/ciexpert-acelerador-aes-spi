// ==========================================================
// Testbench autoverificável: expansão de chave e datapath AES-128
// ==========================================================
// minisoc_aes_key_exp e minisoc_aes_dp ligados como no
// minisoc_aes_top: o dp escolhe a round key por o_round.
// Para cada vetor:
//   - round keys 0 a 10 comparadas com o modelo de referência
//     (Apêndice A.1 para a chave do Apêndice B);
//   - cifragem pt -> ct e decriptação ct -> pt;
//   - latência de 11 ciclos do start ao done.
// Vetores: FIPS-197 Apêndices B e C.1 e 8 vetores aleatórios.
`timescale 1ns/1ps

module minisoc_aes_dp_tb;

  localparam int LATENCY = 11;

  // ========================================================
  // Clock, reset e DUTs
  // ========================================================
  logic         clk = 1'b0;
  logic         rst_n;
  logic         kexp_start, kexp_ready;
  logic [127:0] key;
  logic         dp_start, dp_decrypt, dp_done;
  logic [127:0] dp_block_in, dp_block_out;
  logic [3:0]   dp_round, tb_round, kexp_round;
  logic [127:0] round_key;
  logic         tb_owns_round;  // 1: o testbench lê as round keys diretamente

  always #1 clk = ~clk;

  assign kexp_round = tb_owns_round ? tb_round : dp_round;

  minisoc_aes_key_exp u_key_exp (
    .i_clk       (clk),
    .i_rst_n     (rst_n),
    .i_start     (kexp_start),
    .i_key       (key),
    .i_round     (kexp_round),
    .o_round_key (round_key),
    .o_ready     (kexp_ready)
  );

  minisoc_aes_dp u_dp (
    .i_clk       (clk),
    .i_rst_n     (rst_n),
    .i_start     (dp_start),
    .i_decrypt   (dp_decrypt),
    .i_block     (dp_block_in),
    .o_round     (dp_round),
    .i_round_key (round_key),
    .o_block     (dp_block_out),
    .o_done      (dp_done)
  );

  // ========================================================
  // Vetores de referência
  // ========================================================
  // Vetores: 0 = Apêndice B, 1 = Apêndice C.1, 2 a 9 = aleatórios (modelo em Python, semente 2026)
  localparam int NUM_VEC = 10;

  localparam string NAME [NUM_VEC] = '{
    "Apêndice B",
    "Apêndice C.1",
    "aleatório 0",
    "aleatório 1",
    "aleatório 2",
    "aleatório 3",
    "aleatório 4",
    "aleatório 5",
    "aleatório 6",
    "aleatório 7"
  };

  localparam logic [127:0] KEY [NUM_VEC] = '{
    128'h2b7e151628aed2a6abf7158809cf4f3c,
    128'h000102030405060708090a0b0c0d0e0f,
    128'hf38b2ffc80a4df5a51c9bc701e7ea419,
    128'he512148239292d22e255accb1a466884,
    128'hd7a7a3cc8c3d5f169293de8fc88b2875,
    128'h70eb9a0a96263ae6c5e818fac0433cbd,
    128'h1919e93ad11745ad498893101c593af5,
    128'h5071950eadec6f117d836e77af67d461,
    128'h5b4c8012ede7bd0cffb88309fadb8908,
    128'hb91dddd91389b372a341738c837a7935
  };

  localparam logic [127:0] PT [NUM_VEC] = '{
    128'h3243f6a8885a308d313198a2e0370734,
    128'h00112233445566778899aabbccddeeff,
    128'hf3f49249dc28ff90a5aec7978306d03b,
    128'h6bad6be28e7aa6e99f19950499dd251d,
    128'h7dabe929c4a334bfc6cd75e9bb049a79,
    128'h14aa4e719d3c7dec00a61f933d6c51e3,
    128'he4163207d094499602f0ee99731c9452,
    128'h59001ac9406329bc65b00a2d35d14880,
    128'hbef7e268ffe976ab60581ccace1d62e0,
    128'h89be9c1c8eb5140f16f4488157241955
  };

  localparam logic [127:0] CT [NUM_VEC] = '{
    128'h3925841d02dc09fbdc118597196a0b32,
    128'h69c4e0d86a7b0430d8cdb78070b4c55a,
    128'h53f18f623547a3077b7df2c1653f4a5b,
    128'ha74693d19d41209a81ac81d23f28fde3,
    128'h53f4f835af884f59b610062f3e0c0909,
    128'hc9446383ee2c4ee1f6c6ce5b67e2d344,
    128'h3e470edf353b1a690a1d8d4df7a328ae,
    128'haca4df1fa7605dd89f9db378fe77e9b9,
    128'h18404f5bbc8921aa0cd4e82ba2dfd190,
    128'h3190f4d5dc4d5685f51293db74c5f84a
  };

  // Round keys 0 a 10 de cada chave (a do Apêndice B é a do Apêndice A.1)
  localparam logic [127:0] RK [NUM_VEC][11] = '{
    '{
      128'h2b7e151628aed2a6abf7158809cf4f3c,
      128'ha0fafe1788542cb123a339392a6c7605,
      128'hf2c295f27a96b9435935807a7359f67f,
      128'h3d80477d4716fe3e1e237e446d7a883b,
      128'hef44a541a8525b7fb671253bdb0bad00,
      128'hd4d1c6f87c839d87caf2b8bc11f915bc,
      128'h6d88a37a110b3efddbf98641ca0093fd,
      128'h4e54f70e5f5fc9f384a64fb24ea6dc4f,
      128'head27321b58dbad2312bf5607f8d292f,
      128'hac7766f319fadc2128d12941575c006e,
      128'hd014f9a8c9ee2589e13f0cc8b6630ca6
    },
    '{
      128'h000102030405060708090a0b0c0d0e0f,
      128'hd6aa74fdd2af72fadaa678f1d6ab76fe,
      128'hb692cf0b643dbdf1be9bc5006830b3fe,
      128'hb6ff744ed2c2c9bf6c590cbf0469bf41,
      128'h47f7f7bc95353e03f96c32bcfd058dfd,
      128'h3caaa3e8a99f9deb50f3af57adf622aa,
      128'h5e390f7df7a69296a7553dc10aa31f6b,
      128'h14f9701ae35fe28c440adf4d4ea9c026,
      128'h47438735a41c65b9e016baf4aebf7ad2,
      128'h549932d1f08557681093ed9cbe2c974e,
      128'h13111d7fe3944a17f307a78b4d2b30c5
    },
    '{
      128'hf38b2ffc80a4df5a51c9bc701e7ea419,
      128'h01c2fb8e816624d4d0af98a4ced13cbd,
      128'h3d298105bc4fa5d16ce03d75a23101c8,
      128'hfe55693f421accee2efaf19b8ccbf053,
      128'he9d9845babc348b58539b92e09f2497d,
      128'h70e27b5adb2133ef5e188ac157eac3bc,
      128'hd7cc1e010ced2dee52f5a72f051f6493,
      128'h578fc26a5b62ef84099748ab0c882c38,
      128'h13fec594489c2a10410b62bb4d834e83,
      128'he4d12977ac4d0367ed4661dca0c52f5f,
      128'h74c4e697d889e5f035cf842c950aab73
    },
    '{
      128'he512148239292d22e255accb1a466884,
      128'hbe574b20877e6602652bcac97f6da24d,
      128'h806da8f20713cef0623804391d55a674,
      128'h78493a567f5af4a61d62f09f003756eb,
      128'heaf8d33595a2279388c0d70c88f781e7,
      128'h92f447f1075660628f96b76e07613689,
      128'h5df1e0345aa78056d5313738d25001b1,
      128'h4e8d2881142aa8d7c11b9fef134b9e5e,
      128'h7d8670fc69acd82ba8b747c4bbfcd99a,
      128'hd6b3c816bf1f103d17a857f9ac548e63,
      128'hc0aa33877fb523ba681d7443c449fa20
    },
    '{
      128'hd7a7a3cc8c3d5f169293de8fc88b2875,
      128'heb933e2467ae6132f53dbfbd3db697c8,
      128'ha71bd603c0b5b7313588088c083e9f44,
      128'h11c0cd33d1757a02e4fd728eecc3edca,
      128'h3795b9fde6e0c3ff021db171eede5cbb,
      128'h3adf53d5dc3f902ade22215b30fc7de0,
      128'haa20b2d1761f22fba83d03a098c17e40,
      128'h92d3bb97e4cc996c4cf19accd430e48c,
      128'h16badfdff27646b3be87dc7f6ab738f3,
      128'ha4bdd2dd56cb946ee84c481182fb70e2,
      128'h9dec4acecb27dea0236b96b1a190e653
    },
    '{
      128'h70eb9a0a96263ae6c5e818fac0433cbd,
      128'h6b00e0b0fd26da5638cec2acf88dfe11,
      128'h34bb62f1c99db8a7f1537a0b09de841a,
      128'h2de4c0f0e4797857152a025c1cf48646,
      128'h9aa09a6c7ed9e23b6bf3e06777076621,
      128'h4f936799314a85a25ab965c52dbe03e4,
      128'hc1e80e41f0a28be3aa1bee2687a5edc2,
      128'h87bd2b56771fa0b5dd044e935aa1a351,
      128'h35b7fae842a85a5d9fac14cec50db79f,
      128'hf91e214ebbb67b13241a6fdde117d842,
      128'h3f7f0db684c976a5a0d3197841c4c13a
    },
    '{
      128'h1919e93ad11745ad498893101c593af5,
      128'hd3990fa6028e4a0b4b06d91b575fe3ee,
      128'h1e8827fd1c066df65700b4ed005f5703,
      128'hd5d35c9ec9d531689ed585859e8ad286,
      128'ha36618956ab329fdf466ac786aec7efe,
      128'h7d95a39717268a6ae340261289ac58ec,
      128'hccff6d30dbd9e75a3899c148b13599a4,
      128'h1a1124f8c1c8c3a2f95102ea48649b4e,
      128'hd9050baa18cdc808e19ccae2a9f851ac,
      128'h83d49a799b1952717a859893d37dc93f,
      128'h4a09ef1fd110bd6eab9525fd78e8ecc2
    },
    '{
      128'h5071950eadec6f117d836e77af67d461,
      128'hd4397a7779d5156604567b11ab31af70,
      128'h11402b1568953e736cc34562c7f2ea12,
      128'h9cc7e2d3f452dca0989199c25f6373d0,
      128'h6f48921c9b1a4ebc038bd77e5ce8a4ae,
      128'he40176567f1b38ea7c90ef9420784b3a,
      128'h78b2f6e107a9ce0b7b39219f5b416aa5,
      128'hbbb0f0d8bc193ed3c7201f4c9c6175e9,
      128'hd42dee066834d0d5af14cf993375ba70,
      128'h52d9bfc53aed6f1095f9a089a68c1af9,
      128'h007b26e13a9649f1af6fe97809e3f381
    },
    '{
      128'h5b4c8012ede7bd0cffb88309fadb8908,
      128'he3ebb03f0e0c0d33f1b48e3a0b6f0732,
      128'h492e931447229e27b696101dbdf9172f,
      128'hd4de866e93fc1849256a085498931f7b,
      128'h001ea72893e2bf61b688b7352e1ba84e,
      128'hbfdc88192c3e37789ab6804db4ad2803,
      128'h0ae8f39426d6c4ecbc6044a108cd6ca2,
      128'hf7b8c9a4d16e0d486d0e49e965c3254b,
      128'h59877ae988e977a1e5e73e4880241b03,
      128'h74280124fcc17685192648cd990253ce,
      128'h35c58acac904fc4fd022b4824920e74c
    },
    '{
      128'hb91dddd91389b372a341738c837a7935,
      128'h62ab4b357122f847d2638bcb5119f2fe,
      128'hb422f0e4c50008a317638368467a7196,
      128'h6a8160beaf81681db8e2eb75fe989ae3,
      128'h243971058bb81918335af26dcdc2688e,
      128'h117c68b89ac471a0a99e83cd645ceb43,
      128'h7b9572fbe151035b48cf80962c936bd5,
      128'he7ea718a06bb72d14e74f24762e79992,
      128'hf3043e20f5bf4cf1bbcbbeb6d92c2724,
      128'h99c808156c7744e4d7bcfa520e90dd76,
      128'hcf0930bea37e745a74c28e087a52537e
    }
  };

  // ========================================================
  // Verificação
  // ========================================================
  int checks = 0;
  int errors = 0;

  task automatic check(string what, int v, logic [127:0] got, logic [127:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("[FAIL] %s (%s): obtido %032h, esperado %032h", what, NAME[v], got, exp);
    end
  endtask

  task automatic expand_key(int v);
    key = KEY[v];
    @(negedge clk) kexp_start = 1'b1;
    @(negedge clk) kexp_start = 1'b0;
    while (!kexp_ready) @(negedge clk);
  endtask

  // Dispara o dp e conta os ciclos, da borda que captura o start até a que levanta o done
  task automatic run_block(int v, logic decrypt, logic [127:0] block_in, logic [127:0] exp);
    int cycles;
    dp_decrypt  = decrypt;
    dp_block_in = block_in;
    @(negedge clk) dp_start = 1'b1;
    @(posedge clk) cycles = 1;
    @(negedge clk) dp_start = 1'b0;
    while (!dp_done) begin
      @(posedge clk);
      cycles++;
      #0.1;
    end
    check(decrypt ? "decriptação" : "cifragem", v, dp_block_out, exp);
    checks++;
    if (cycles != LATENCY) begin
      errors++;
      $display("[FAIL] latência (%s): %0d ciclos, esperado %0d", NAME[v], cycles, LATENCY);
    end
  endtask

  initial begin
    $fsdbDumpfile("minisoc_aes_dp_tb.fsdb");
    $fsdbDumpvars(0, minisoc_aes_dp_tb);
  end

  initial begin
    rst_n         = 1'b0;
    kexp_start    = 1'b0;
    dp_start      = 1'b0;
    dp_decrypt    = 1'b0;
    dp_block_in   = '0;
    key           = '0;
    tb_round      = '0;
    tb_owns_round = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    for (int v = 0; v < NUM_VEC; v++) begin
      expand_key(v);

      // round keys
      tb_owns_round = 1'b1;
      for (int r = 0; r <= 10; r++) begin
        tb_round = r[3:0];
        #0.1;
        check($sformatf("round key %0d", r), v, round_key, RK[v][r]);
      end
      tb_owns_round = 1'b0;

      // cifragem e decriptação com as mesmas round keys
      run_block(v, 1'b0, PT[v], CT[v]);
      run_block(v, 1'b1, CT[v], PT[v]);
    end

    $display("==========================================================");
    if (errors == 0)
      $display("PASS: %0d verificações, 0 erros", checks);
    else
      $display("FAIL: %0d verificações, %0d erros", checks, errors);
    $display("==========================================================");
    $finish;
  end

endmodule
