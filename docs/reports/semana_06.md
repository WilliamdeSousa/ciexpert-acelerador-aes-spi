# Relatório — Semana 06: AES engine e memória compartilhada

> Entrega: 27/11/2026.
> Referências: Block Guide do MiniSoC AES v1.0.0 (seções 7, 8 e 11), [FIPS PUB 197](<../spec/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>), NIST SP 800-38A e [documento de microarquitetura](../architecture/microarquitetura.md) (seções 5.3, 5.4 e 6).

## 1. O que foi feito

- Implementação de `minisoc_memory`: 1024 × 32, single-port síncrona, sem reset, com ownership por MEM_SEL_AES e mux de clock sem glitch.
- Implementação de `minisoc_aes_top`: sincronização do START, captura da configuração, FSM de leitura, processamento e escrita in-place, status BUSY, DONE, ERROR e BLOCKS_DONE.
- Modos ECB, CBC e CTR, em cifragem e decriptação.
- Detecção de configuração inválida (NUM_BLOCKS fora de 1..256 e MODE reservado), com ERROR e encerramento sem processamento.
- Modelo de referência em Python (`scripts/aes_ref.py`), gerador de vetores (`scripts/gen_aes_top_vectors.py`) e testbench de bloco `minisoc_aes_top_tb`.

## 2. Implementação

### 2.1 `minisoc_memory`

| Porta | Dir. | Largura | Descrição |
|---|---|---|---|
| `i_rst_n` | I | 1 | reset do mux de clock (o conteúdo não tem reset) |
| `i_mem_sel_aes` | I | 1 | MEM_SEL_AES: 0 = MEMORY DATA, 1 = AES |
| `i_mem_clk`, `i_mem_addr`, `i_mem_data`, `i_mem_wr_en` | I | 1, 10, 32, 1 | interface MEMORY DATA |
| `i_sys_clk`, `i_aes_addr`, `i_aes_data`, `i_aes_wr_en` | I | 1, 10, 32, 1 | porto do AES |
| `o_rdata` | O | 32 | dado lido, ligado ao mesmo tempo a `mem_o_data` e ao AES |

- **Semântica:** com `wr_en = 1`, escreve na borda; com `wr_en = 0`, lê, e o dado aparece em `o_rdata` depois da borda (1 ciclo de latência).
- **Mux de clock sem glitch:** cada lado tem 2 flip-flops. O primeiro, na borda de subida do próprio clock, sincroniza a seleção, mas só se o outro lado já estiver desligado. O segundo, na borda de descida, libera o enable com o clock em 0. O clock da memória é `(sys_clk & aes_en) | (mem_clk & ext_en)`. Assim, os dois enables nunca ficam em 1 juntos, e cada um só muda com o seu clock em nível baixo.
- **Mux do porto:** endereço, dado e write-enable seguem o enable do clock (`aes_en`), e não diretamente o MEM_SEL_AES. Dessa forma, os sinais de dados trocam junto com o clock.

### 2.2 `minisoc_aes_top`

| Grupo | Porta | Dir. | Largura | Descrição |
|---|---|---|---|---|
| Clock | `i_clk`, `i_rst_n` | I | 1 | `sys_clk` e reset do domínio do sistema |
| Configuração | `i_start_toggle` | I | 1 | toggle de START vindo do `minisoc_spi` |
| Configuração | `i_cfg_key`, `i_cfg_iv` | I | 128 | KEY e IV |
| Configuração | `i_cfg_counter` | I | 64 | COUNTER |
| Configuração | `i_cfg_num_blocks` | I | 32 | NUM_BLOCKS |
| Configuração | `i_cfg_mode`, `i_cfg_decrypt` | I | 3, 1 | MODE e DECRYPT |
| Status | `o_busy`, `o_done`, `o_error` | O | 1 | BUSY, DONE (sticky) e ERROR |
| Status | `o_blocks_done_gray` | O | 9 | BLOCKS_DONE em código Gray |
| Memória | `o_mem_addr`, `o_mem_data`, `o_mem_wr_en` | O | 10, 32, 1 | porto do AES na memória |
| Memória | `i_mem_rdata` | I | 32 | dado lido |

**FSM** (detalhes na seção 5.4 da microarquitetura):

```
IDLE → CHECK → KEY → READ → CIPHER → WAIT → WRITE → (READ | IDLE)
          └→ IDLE com ERROR e DONE (configuração inválida)
```

- **START:** o toggle passa por 2 flip-flops e um detector de mudança. Nos 3 primeiros ciclos após o reset, a cadeia se carrega com o valor atual do toggle e mudanças são ignoradas, para que um toggle já em 1 antes do reset do `sys_clk` não gere um START falso. O START só é aceito em IDLE.
- **Configuração:** capturada na borda em que o START é aceito. Ela atravessa do `clk` para o `sys_clk` sem sincronizador, porque é estável por regra de programação: é escrita antes do START (Block Guide, seção 9).
- **Validação (CHECK):** `1 ≤ NUM_BLOCKS ≤ 256`, comparando os 32 bits, e MODE ∈ {ECB, CBC, CTR}. Senão, ERROR = 1, DONE = 1, BUSY = 0 e nenhum acesso à memória.
- **Endereços:** o bloco `i` ocupa as palavras `4i` a `4i+3`, com a Word 0 em `[127:96]` (Block Guide, seção 7.1). O resultado é escrito no mesmo lugar (REQ-AES-02).
- **Modos:**

| Modo | Entrada do `dp` | Sentido do `dp` | Resultado | Atualização |
|---|---|---|---|---|
| ECB | `in` | DECRYPT | `dp` | — |
| CBC cifra | `in ^ chain` | cifra | `dp` | `chain = out` |
| CBC decifra | `in` | decifra | `dp ^ chain` | `chain = in` |
| CTR | `IV ^ {64'b0, ctr}` | sempre cifra | `in ^ dp` | `ctr = ctr + 1` (64 bits, com volta) |

- **Status:** BLOCKS_DONE é mantido em binário e também num registrador em Gray, atualizado na mesma borda. O valor em Gray sai direto de um flip-flop, sem lógica combinacional, e muda 1 bit por incremento, o que é seguro para o sincronizador de 2 FF do `minisoc_spi`.
- **Latência:** 21 ciclos de `sys_clk` por bloco (5 de leitura, 1 de início, 11 do `dp` e 4 de escrita), mais 12 por operação (CHECK e expansão de chave). Com 256 blocos, são cerca de 5390 ciclos.

## 3. Verificação

### 3.1 Modelo de referência

`scripts/aes_ref.py` implementa o AES-128 e os seis modos do Block Guide, na mesma convenção de bytes do RTL. O autoteste (`python3 scripts/aes_ref.py`) confere o modelo contra:

- FIPS-197, Apêndices B e C.1 (cifra, decifra e a última round key do A.1);
- NIST SP 800-38A, F.1.1 (ECB) e F.2.1 (CBC, cifra e decifra);
- CTR com o contador de 64 bits dando a volta.

`scripts/gen_aes_top_vectors.py` (semente fixa 2026) gera 18 casos: ECB, CBC e CTR × cifra e decifra × 1, 2 e 256 blocos. Cada caso tem chave, IV, contador e uma imagem de memória de 1024 palavras aleatórios. No CTR com 256 blocos, o contador começa em `2^64 - 3` e dá a volta. Os arquivos ficam em `tb/vectors/`.

### 3.2 Testbench

`tb/minisoc_aes_top_tb.sv` liga `minisoc_aes_top` e `minisoc_memory`, com `sys_clk` de 1 GHz e `mem_clk` de 200 MHz. Para cada caso:

1. escreve as 1024 palavras pela interface MEMORY DATA, com MEM_SEL_AES = 0;
2. passa a memória ao AES, aplica a configuração e inverte o toggle de START;
3. confere que BUSY sobe e que o DONE da operação anterior é limpo;
4. espera DONE e confere BUSY = 0, ERROR = 0, BLOCKS_DONE = NUM_BLOCKS e DONE sticky;
5. devolve a memória e compara as 1024 palavras com o modelo. As palavras fora da região processada devem estar intactas.

Depois, 8 configurações inválidas: NUM_BLOCKS = 0, 257 e `0x1000`; MODE = 110 e 111; e PCBC, CFB e OFB, rejeitados na v1.0. Em todas, ERROR = 1, DONE = 1, BUSY = 0, BLOCKS_DONE = 0 e a memória intacta. Por fim, uma operação válida confere que o ERROR é limpo.

### 3.3 Como executar

No servidor `microeletronica3`:

```bash
source /Tools/synopsys-scripts/snps.sh
python3 scripts/aes_ref.py              # autoteste do modelo
python3 scripts/gen_aes_top_vectors.py  # regera tb/vectors (já versionados)
make run                                # testbench da semana 6 (padrão)
make run TOP=minisoc_spi_pll_tb         # semana 5
make lint
```

### 3.4 Resultados

| Comando | Resultado |
|---|---|
| `python3 scripts/aes_ref.py` | **autoteste OK** |
| `make run` | **PASS: 19669 verificações, 0 erros** |
| `make run TOP=minisoc_spi_pll_tb` | **PASS: 116 verificações, 0 erros** |
| `make run TOP=minisoc_aes_dp_tb` | **PASS: 150 verificações, 0 erros** |
| `make run TOP=minisoc_aes_round_tb` | **PASS: 592 verificações, 0 erros** |
| `make run TOP=minisoc_aes_sub_shift_tb` | **PASS: 276 verificações, 0 erros** |
| `make lint` | **0 erros e 0 avisos** ([log](lint/semana_06_lint.log)) |

Com `+lint=all`, sem as exceções do Makefile, o único aviso continua sendo o `Lint-[NS]` do `default: ;` do `minisoc_spi`, justificado no relatório da semana 5.

O critério de aceite foi atendido: ECB, CBC e CTR conferem com o modelo de referência nos dois sentidos, ERROR é sinalizado nas configurações inválidas e o lint não tem erros.

## 4. Limitações conhecidas da v1.0

- **PCBC, CFB e OFB:** não implementados. São rejeitados com ERROR, como uma configuração inválida, até a semana 10. O modelo de referência já os implementa. **A comunicar ao verificador parceiro.**
- **START durante uma operação:** é ignorado, e não enfileirado.
- **Troca de MEM_SEL_AES:** o mux de clock é seguro, mas a regra do Block Guide continua valendo: trocar só com o AES ocioso e sem acesso externo em andamento.

## 5. Problemas encontrados

- **BLOCKS_DONE atrasado em relação ao DONE:** na primeira versão, o registrador em Gray era calculado a partir do contador binário um ciclo depois, e o testbench leu BLOCKS_DONE = N − 1 com DONE = 1. Agora os dois são atualizados na mesma borda.
- **START falso após o reset:** se o toggle de START já estiver em 1 quando o domínio do sistema sai do reset, a cadeia de sincronização veria uma mudança 0 → 1. Isso foi resolvido com um período de aquecimento de 3 ciclos.

## 6. Próximos passos (semana 7, entrega 04/12)

- `minisoc_top`: conexão de `minisoc_spi`, `minisoc_pll_mock`, `minisoc_aes_top` e `minisoc_memory`, com as interfaces de topo do Block Guide.
- Sequência de reset do domínio do sistema (lock + 16 ciclos) e sincronizadores de reset.
- Teste de ponta a ponta com os 14 passos do modelo de programação.
- Análise de CDC e tag `rtl-v1.0`.
