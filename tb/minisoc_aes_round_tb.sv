// ==========================================================
// Testbench autoverificável: transformações de rodada do AES
// ==========================================================
// Vetores de referência da FIPS-197:
//   - S-box e S-box inversa: Figura 7, nas 256 entradas;
//   - SubBytes, ShiftRows, MixColumns e AddRoundKey: Apêndice B
//     (exemplo de cifragem), rodadas 0 a 10;
//   - InvShiftRows, InvSubBytes, InvMixColumns e AddRoundKey:
//     Apêndice C.1 (cifragem inversa do AES-128), rodadas 0 a 10.
// Convenção do estado: byte 0 em [127:120] e byte 15 em [7:0].
`timescale 1ns/1ps

module minisoc_aes_round_tb;

  // ========================================================
  // Sinais e DUTs
  // ========================================================
  logic [7:0]   sbox_in,      sbox_out;
  logic [7:0]   inv_sbox_in,  inv_sbox_out;
  logic [127:0] sub_in,       sub_out;
  logic [127:0] inv_sub_in,   inv_sub_out;
  logic [127:0] shift_in,     shift_out;
  logic [127:0] inv_shift_in, inv_shift_out;
  logic [127:0] mix_in,       mix_out;
  logic [127:0] inv_mix_in,   inv_mix_out;
  logic [127:0] ark_in,       ark_key,      ark_out;

  minisoc_aes_sbox u_sbox (
    .i_data (sbox_in),
    .o_data (sbox_out)
  );

  minisoc_aes_inv_sbox u_inv_sbox (
    .i_data (inv_sbox_in),
    .o_data (inv_sbox_out)
  );

  minisoc_aes_sub_bytes u_sub_bytes (
    .i_state (sub_in),
    .o_state (sub_out)
  );

  minisoc_aes_inv_sub_bytes u_inv_sub_bytes (
    .i_state (inv_sub_in),
    .o_state (inv_sub_out)
  );

  minisoc_aes_shift_rows u_shift_rows (
    .i_state (shift_in),
    .o_state (shift_out)
  );

  minisoc_aes_inv_shift_rows u_inv_shift_rows (
    .i_state (inv_shift_in),
    .o_state (inv_shift_out)
  );

  minisoc_aes_mix_columns u_mix_columns (
    .i_state (mix_in),
    .o_state (mix_out)
  );

  minisoc_aes_inv_mix_columns u_inv_mix_columns (
    .i_state (inv_mix_in),
    .o_state (inv_mix_out)
  );

  minisoc_aes_add_round_key u_add_round_key (
    .i_state     (ark_in),
    .i_round_key (ark_key),
    .o_state     (ark_out)
  );

  // ========================================================
  // Vetores de referência
  // ========================================================
  // S-box (FIPS-197, Figura 7): SBOX_REF[x] = S(x)
  localparam logic [7:0] SBOX_REF [256] = '{
    8'h63, 8'h7c, 8'h77, 8'h7b, 8'hf2, 8'h6b, 8'h6f, 8'hc5, 8'h30, 8'h01, 8'h67, 8'h2b, 8'hfe, 8'hd7, 8'hab, 8'h76,
    8'hca, 8'h82, 8'hc9, 8'h7d, 8'hfa, 8'h59, 8'h47, 8'hf0, 8'had, 8'hd4, 8'ha2, 8'haf, 8'h9c, 8'ha4, 8'h72, 8'hc0,
    8'hb7, 8'hfd, 8'h93, 8'h26, 8'h36, 8'h3f, 8'hf7, 8'hcc, 8'h34, 8'ha5, 8'he5, 8'hf1, 8'h71, 8'hd8, 8'h31, 8'h15,
    8'h04, 8'hc7, 8'h23, 8'hc3, 8'h18, 8'h96, 8'h05, 8'h9a, 8'h07, 8'h12, 8'h80, 8'he2, 8'heb, 8'h27, 8'hb2, 8'h75,
    8'h09, 8'h83, 8'h2c, 8'h1a, 8'h1b, 8'h6e, 8'h5a, 8'ha0, 8'h52, 8'h3b, 8'hd6, 8'hb3, 8'h29, 8'he3, 8'h2f, 8'h84,
    8'h53, 8'hd1, 8'h00, 8'hed, 8'h20, 8'hfc, 8'hb1, 8'h5b, 8'h6a, 8'hcb, 8'hbe, 8'h39, 8'h4a, 8'h4c, 8'h58, 8'hcf,
    8'hd0, 8'hef, 8'haa, 8'hfb, 8'h43, 8'h4d, 8'h33, 8'h85, 8'h45, 8'hf9, 8'h02, 8'h7f, 8'h50, 8'h3c, 8'h9f, 8'ha8,
    8'h51, 8'ha3, 8'h40, 8'h8f, 8'h92, 8'h9d, 8'h38, 8'hf5, 8'hbc, 8'hb6, 8'hda, 8'h21, 8'h10, 8'hff, 8'hf3, 8'hd2,
    8'hcd, 8'h0c, 8'h13, 8'hec, 8'h5f, 8'h97, 8'h44, 8'h17, 8'hc4, 8'ha7, 8'h7e, 8'h3d, 8'h64, 8'h5d, 8'h19, 8'h73,
    8'h60, 8'h81, 8'h4f, 8'hdc, 8'h22, 8'h2a, 8'h90, 8'h88, 8'h46, 8'hee, 8'hb8, 8'h14, 8'hde, 8'h5e, 8'h0b, 8'hdb,
    8'he0, 8'h32, 8'h3a, 8'h0a, 8'h49, 8'h06, 8'h24, 8'h5c, 8'hc2, 8'hd3, 8'hac, 8'h62, 8'h91, 8'h95, 8'he4, 8'h79,
    8'he7, 8'hc8, 8'h37, 8'h6d, 8'h8d, 8'hd5, 8'h4e, 8'ha9, 8'h6c, 8'h56, 8'hf4, 8'hea, 8'h65, 8'h7a, 8'hae, 8'h08,
    8'hba, 8'h78, 8'h25, 8'h2e, 8'h1c, 8'ha6, 8'hb4, 8'hc6, 8'he8, 8'hdd, 8'h74, 8'h1f, 8'h4b, 8'hbd, 8'h8b, 8'h8a,
    8'h70, 8'h3e, 8'hb5, 8'h66, 8'h48, 8'h03, 8'hf6, 8'h0e, 8'h61, 8'h35, 8'h57, 8'hb9, 8'h86, 8'hc1, 8'h1d, 8'h9e,
    8'he1, 8'hf8, 8'h98, 8'h11, 8'h69, 8'hd9, 8'h8e, 8'h94, 8'h9b, 8'h1e, 8'h87, 8'he9, 8'hce, 8'h55, 8'h28, 8'hdf,
    8'h8c, 8'ha1, 8'h89, 8'h0d, 8'hbf, 8'he6, 8'h42, 8'h68, 8'h41, 8'h99, 8'h2d, 8'h0f, 8'hb0, 8'h54, 8'hbb, 8'h16
  };

  // Apêndice B: cifragem
  localparam logic [127:0] B_INPUT  = 128'h3243f6a8885a308d313198a2e0370734;
  localparam logic [127:0] B_OUTPUT = 128'h3925841d02dc09fbdc118597196a0b32;

  // round keys 0 a 10 (índice = rodada)
  localparam logic [127:0] B_K_SCH [11] = '{
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
  };

  // Start of Round, rodadas 1 a 10 (índice 0 = rodada 1)
  localparam logic [127:0] B_START [10] = '{
    128'h193de3bea0f4e22b9ac68d2ae9f84808,
    128'ha49c7ff2689f352b6b5bea43026a5049,
    128'haa8f5f0361dde3ef82d24ad26832469a,
    128'h486c4eee671d9d0d4de3b138d65f58e7,
    128'he0927fe8c86363c0d9b1355085b8be01,
    128'hf1006f55c1924cef7cc88b325db5d50c,
    128'h260e2e173d41b77de86472a9fdd28b25,
    128'h5a4142b11949dc1fa3e019657a8c040c,
    128'hea835cf00445332d655d98ad8596b0c5,
    128'heb40f21e592e38848ba113e71bc342d2
  };

  // After SubBytes, rodadas 1 a 10
  localparam logic [127:0] B_S_BOX [10] = '{
    128'hd42711aee0bf98f1b8b45de51e415230,
    128'h49ded28945db96f17f39871a7702533b,
    128'hac73cf7befc111df13b5d6b545235ab8,
    128'h52502f2885a45ed7e311c807f6cf6a94,
    128'he14fd29be8fbfbba35c89653976cae7c,
    128'ha163a8fc784f29df10e83d234cd503fe,
    128'hf7ab31f02783a9ff9b4340d354b53d3f,
    128'hbe832cc8d43b86c00ae1d44dda64f2fe,
    128'h87ec4a8cf26ec3d84d4c46959790e7a6,
    128'he9098972cb31075f3d327d94af2e2cb5
  };

  // After ShiftRows, rodadas 1 a 10
  localparam logic [127:0] B_S_ROW [10] = '{
    128'hd4bf5d30e0b452aeb84111f11e2798e5,
    128'h49db873b453953897f02d2f177de961a,
    128'hacc1d6b8efb55a7b1323cfdf457311b5,
    128'h52a4c89485116a28e3cf2fd7f6505e07,
    128'he1fb967ce8c8ae9b356cd2ba974ffb53,
    128'ha14f3dfe78e803fc10d5a8df4c632923,
    128'hf783403f27433df09bb531ff54aba9d3,
    128'hbe3bd4fed4e1f2c80a642cc0da83864d,
    128'h876e46a6f24ce78c4d904ad897ecc395,
    128'he9317db5cb322c723d2e895faf090794
  };

  // After MixColumns, rodadas 1 a 9 (a rodada 10 não tem MixColumns)
  localparam logic [127:0] B_M_COL [9] = '{
    128'h046681e5e0cb199a48f8d37a2806264c,
    128'h584dcaf11b4b5aacdbe7caa81b6bb0e5,
    128'h75ec0993200b633353c0cf7cbb25d0dc,
    128'h0fd6daa9603138bf6fc0106b5eb31301,
    128'h25d1a9adbd11d168b63a338e4c4cc0b0,
    128'h4b868d6d2c4a8980339df4e837d218d8,
    128'h1415b5bf461615ec274656d7342ad843,
    128'h00512fd1b1c889ff54766dcdfa1b99ea,
    128'h473794ed40d4e4a5a3703aa64c9f42bc
  };

  // Apêndice C.1: cifragem inversa (AES-128)
  localparam logic [127:0] C_INPUT  = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
  localparam logic [127:0] C_OUTPUT = 128'h00112233445566778899aabbccddeeff;

  // ik_sch das rodadas 0 a 10 (round keys em ordem inversa)
  localparam logic [127:0] C_IK_SCH [11] = '{
    128'h13111d7fe3944a17f307a78b4d2b30c5,
    128'h549932d1f08557681093ed9cbe2c974e,
    128'h47438735a41c65b9e016baf4aebf7ad2,
    128'h14f9701ae35fe28c440adf4d4ea9c026,
    128'h5e390f7df7a69296a7553dc10aa31f6b,
    128'h3caaa3e8a99f9deb50f3af57adf622aa,
    128'h47f7f7bc95353e03f96c32bcfd058dfd,
    128'hb6ff744ed2c2c9bf6c590cbf0469bf41,
    128'hb692cf0b643dbdf1be9bc5006830b3fe,
    128'hd6aa74fdd2af72fadaa678f1d6ab76fe,
    128'h000102030405060708090a0b0c0d0e0f
  };

  // istart, rodadas 1 a 10 (índice 0 = rodada 1)
  localparam logic [127:0] C_ISTART [10] = '{
    128'h7ad5fda789ef4e272bca100b3d9ff59f,
    128'h54d990a16ba09ab596bbf40ea111702f,
    128'h3e1c22c0b6fcbf768da85067f6170495,
    128'hb458124c68b68a014b99f82e5f15554c,
    128'he8dab6901477d4653ff7f5e2e747dd4f,
    128'h36339d50f9b539269f2c092dc4406d23,
    128'h2d6d7ef03f33e334093602dd5bfb12c7,
    128'h3bd92268fc74fb735767cbe0c0590e2d,
    128'ha7be1a6997ad739bd8c9ca451f618b61,
    128'h6353e08c0960e104cd70b751bacad0e7
  };

  // is_row (After InvShiftRows), rodadas 1 a 10
  localparam logic [127:0] C_IS_ROW [10] = '{
    128'h7a9f102789d5f50b2beffd9f3dca4ea7,
    128'h5411f4b56bd9700e96a0902fa1bb9aa1,
    128'h3e175076b61c04678dfc2295f6a8bfc0,
    128'hb415f8016858552e4bb6124c5f998a4c,
    128'he847f56514dadde23f77b64fe7f7d490,
    128'h36400926f9336d2d9fb59d23c42c3950,
    128'h2dfb02343f6d12dd09337ec75b36e3f0,
    128'h3b59cb73fcd90ee05774222dc067fb68,
    128'ha761ca9b97be8b45d8ad1a611fc97369,
    128'h63cab7040953d051cd60e0e7ba70e18c
  };

  // is_box (After InvSubBytes), rodadas 1 a 10
  localparam logic [127:0] C_IS_BOX [10] = '{
    128'hbd6e7c3df2b5779e0b61216e8b10b689,
    128'hfde3bad205e5d0d73547964ef1fe37f1,
    128'hd1876c0f79c4300ab45594add66ff41f,
    128'hc62fe109f75eedc3cc79395d84f9cf5d,
    128'hc81677bc9b7ac93b25027992b0261996,
    128'h247240236966b3fa6ed2753288425b6c,
    128'hfa636a2825b339c940668a3157244d17,
    128'h4915598f55e5d7a0daca94fa1f0a63f7,
    128'h89d810e8855ace682d1843d8cb128fe4,
    128'h00102030405060708090a0b0c0d0e0f0
  };

  // ik_add (After AddRoundKey), rodadas 1 a 10
  localparam logic [127:0] C_IK_ADD [10] = '{
    128'he9f74eec023020f61bf2ccf2353c21c7,
    128'hbaa03de7a1f9b56ed5512cba5f414d23,
    128'hc57e1c159a9bd286f05f4be098c63439,
    128'h9816ee7400f87f556b2c049c8e5ad036,
    128'hf4bcd45432e554d075f1d6c51dd03b3c,
    128'h6385b79ffc538df997be478e7547d691,
    128'h4c9c1e66f771f0762c3f868e534df256,
    128'hff87968431d86a51645151fa773ad009,
    128'h5f72641557f5bc92f7be3b291db9f91a,
    128'h00112233445566778899aabbccddeeff
  };

  // ========================================================
  // Verificação
  // ========================================================
  int checks = 0;
  int errors = 0;

  task automatic check_state(string name, int round, logic [127:0] got, logic [127:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("[FAIL] %s rodada %0d: obtido %032h, esperado %032h", name, round, got, exp);
    end
  endtask

  task automatic check_add_round_key(string name, int round, logic [127:0] state, logic [127:0] key,
                                     logic [127:0] exp);
    ark_in  = state;
    ark_key = key;
    #1;
    check_state(name, round, ark_out, exp);
  endtask

  initial begin
    $fsdbDumpfile("minisoc_aes_round_tb.fsdb");
    $fsdbDumpvars(0, minisoc_aes_round_tb);
  end

  initial begin
    // S-box e S-box inversa nas 256 entradas
    for (int i = 0; i < 256; i++) begin
      sbox_in     = i[7:0];
      inv_sbox_in = SBOX_REF[i];
      #1;
      checks += 2;
      if (sbox_out !== SBOX_REF[i]) begin
        errors++;
        $display("[FAIL] sbox(%02h): obtido %02h, esperado %02h", i[7:0], sbox_out, SBOX_REF[i]);
      end
      if (inv_sbox_out !== i[7:0]) begin
        errors++;
        $display("[FAIL] inv_sbox(%02h): obtido %02h, esperado %02h", SBOX_REF[i], inv_sbox_out, i[7:0]);
      end
    end

    // Cifragem (Apêndice B)
    check_add_round_key("AddRoundKey", 0, B_INPUT, B_K_SCH[0], B_START[0]);
    for (int r = 0; r < 10; r++) begin
      sub_in   = B_START[r];
      shift_in = B_S_BOX[r];
      #1;
      check_state("SubBytes",  r + 1, sub_out,   B_S_BOX[r]);
      check_state("ShiftRows", r + 1, shift_out, B_S_ROW[r]);
      if (r < 9) begin
        mix_in = B_S_ROW[r];
        #1;
        check_state("MixColumns", r + 1, mix_out, B_M_COL[r]);
        check_add_round_key("AddRoundKey", r + 1, B_M_COL[r], B_K_SCH[r + 1], B_START[r + 1]);
      end else begin
        check_add_round_key("AddRoundKey", r + 1, B_S_ROW[r], B_K_SCH[r + 1], B_OUTPUT);
      end
    end

    // Cifragem inversa (Apêndice C.1)
    check_add_round_key("Inv AddRoundKey", 0, C_INPUT, C_IK_SCH[0], C_ISTART[0]);
    for (int r = 0; r < 10; r++) begin
      inv_shift_in = C_ISTART[r];
      inv_sub_in   = C_IS_ROW[r];
      #1;
      check_state("InvShiftRows", r + 1, inv_shift_out, C_IS_ROW[r]);
      check_state("InvSubBytes",  r + 1, inv_sub_out,   C_IS_BOX[r]);
      if (r < 9) begin
        check_add_round_key("Inv AddRoundKey", r + 1, C_IS_BOX[r], C_IK_SCH[r + 1], C_IK_ADD[r]);
        inv_mix_in = C_IK_ADD[r];
        #1;
        check_state("InvMixColumns", r + 1, inv_mix_out, C_ISTART[r + 1]);
      end else begin
        check_add_round_key("Inv AddRoundKey", r + 1, C_IS_BOX[r], C_IK_SCH[r + 1], C_OUTPUT);
      end
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
