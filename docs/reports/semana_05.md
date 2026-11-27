# Relatório — Semana 05: SPI front-end e PLL mock

> Entrega: 20/11/2026.
> Referências: Block Guide do MiniSoC AES v1.0.0 (seções 4.1, 5, 6 e 9) e [documento de microarquitetura](../architecture/microarquitetura.md) (seções 4 e 7).

## 1. O que foi feito

- Implementação de `minisoc_spi`: recepção SPI Mode 0 de 40 bits, sincronização do frame por toggle e banco de registradores no domínio `clk` (#19).
- Implementação de `minisoc_pll_mock`: divisores /1, /2, /4 e /8 e `locked` após um número pseudoaleatório de ciclos (#20).
- Testbench dirigido `minisoc_spi_pll_tb`, com o SPI e o PLL ligados como no `minisoc_top`, e relatório de lint versionado (#21).

## 2. Implementação

### 2.1 `minisoc_spi`

| Grupo | Porta | Dir. | Largura | Descrição |
|---|---|---|---|---|
| Controle | `i_clk`, `i_rst_n` | I | 1 | clock always-on (2 GHz) e reset ativo em nível baixo |
| SPI | `i_spi_sclk`, `i_spi_cs_n`, `i_spi_mosi` | I | 1 | interface SPI (Mode 0, MSB-first) |
| SPI | `o_spi_miso` | O | 1 | dado de leitura |
| Configuração | `o_cfg_key`, `o_cfg_iv` | O | 128 | KEY0–KEY3 e IV0–IV3 concatenados (KEY0 em `[127:96]`) |
| Configuração | `o_cfg_counter` | O | 64 | `{COUNTER_HI, COUNTER_LO}` |
| Configuração | `o_cfg_num_blocks` | O | 32 | NUM_BLOCKS, com os 32 bits escritos |
| Configuração | `o_cfg_mode`, `o_cfg_decrypt` | O | 3, 1 | campos MODE e DECRYPT de AES_CONTROL |
| Configuração | `o_start_toggle` | O | 1 | inverte a cada escrita de START = 1 |
| Status | `i_aes_busy`, `i_aes_done`, `i_aes_error` | I | 1 | status do AES (domínio `sys_clk`) |
| Status | `i_aes_blocks_done_gray` | I | 9 | BLOCKS_DONE em código Gray (domínio `sys_clk`) |
| Sistema | `o_mem_sel_aes`, `o_pll_enable`, `o_pll_div_sel` | O | 1, 1, 2 | campos de SYSTEM_CONTROL |
| Sistema | `i_pll_locked` | I | 1 | PLL_LOCKED |

**Recepção (domínio `spi_sclk`):**

- O MOSI é amostrado na borda de subida e entra num registrador de deslocamento.
- Um contador de bits é zerado de forma assíncrona enquanto `spi_cs_n = 1`.
- No 40º bit, o frame completo é copiado para `frame_q` e um bit de toggle é invertido. `frame_q` só muda no fim do próximo frame, ou seja, pelo menos 40 bordas de `spi_sclk` depois.

**CDC do frame (`spi_sclk` → `clk`):**

- O toggle passa por 2 flip-flops e um terceiro detecta a mudança, gerando um pulso de 1 ciclo de `clk`.
- Nesse pulso, o banco de registradores lê os campos de `frame_q` diretamente. Eles estão estáveis: o pulso chega cerca de 3 ciclos de `clk` (1,5 ns) depois do fim do frame, e o próximo frame leva pelo menos 1,6 µs.
- Assim, só 1 bit cruza o domínio por sincronizador, e não os 40 bits do frame.

**Banco de registradores (domínio `clk`):**

| Addr | Registro | Acesso | Implementação |
|---|---|---|---|
| 0x00–0x03 | KEY0–KEY3 | R/W | 32 bits |
| 0x04–0x07 | IV0–IV3 | R/W | 32 bits |
| 0x08, 0x09 | COUNTER_HI, COUNTER_LO | R/W | 32 bits |
| 0x0A | NUM_BLOCKS | R/W | 32 bits, sem saturação, para que o AES detecte valores fora de 1..256 |
| 0x0B | AES_CONTROL | R/W | MODE `[4:2]` e DECRYPT `[1]`; START `[0]` inverte o toggle e é lido como 0 |
| 0x0C | AES_STATUS | R | `{BLOCKS_DONE[11:3], ERROR, DONE, BUSY}`, vindos dos sincronizadores |
| 0x0D | VERSION | R | parâmetro `VERSION`, padrão `0x0001_0000` (v1.0.0) |
| 0x0E | SYSTEM_CONTROL | R/W | PLL_DIV_SEL `[3:2]`, PLL_ENABLE `[1]`, MEM_SEL_AES `[0]` |
| 0x0F | SYSTEM_STATUS | R | PLL_LOCKED `[0]` |
| 0x3F | NOP | — | escrita ignorada, leitura em 0 |

- Escritas em registradores R, no NOP ou em endereços livres são ignoradas. Endereços livres são lidos como 0, assim como os bits reservados.
- **START (write-one-pulse):** não é guardado. Cada escrita com o bit 0 em 1 inverte `o_start_toggle`, que o `minisoc_aes_top` vai sincronizar no `sys_clk` (semana 6).

**Leitura em duas transações:**

1. O READ request (`RWb = 1`) guarda o valor do registrador `ADDR` em `rdata_q`.
2. Na transação seguinte, endereçada ao NOP, a resposta ocupa a posição do campo DATA. Os bits 39 a 32 saem em 0 e os bits 31 a 0 trazem `rdata_q`, MSB primeiro, com o MISO atualizado na borda de descida.

O bit enviado é escolhido pelo contador de bits (`tx_word[39 - bit_cnt]`). Como o primeiro bit é 0, ele já está correto na descida de `spi_cs_n`, antes de qualquer borda de `spi_sclk`. `rdata_q` só muda ao fim de um READ request, então fica estável durante toda a transação de retorno.

**CDC do status (`sys_clk` e PLL → `clk`):**

- BUSY, DONE, ERROR e PLL_LOCKED são níveis de 1 bit e passam por 2 flip-flops.
- BLOCKS_DONE chega em código Gray. Como só 1 bit muda por incremento, cada bit pode passar por 2 flip-flops sem misturar valores. Depois é convertido para binário (`b[i] = g[8] ^ ... ^ g[i]`).

### 2.2 `minisoc_pll_mock`

| Porta | Dir. | Largura | Descrição |
|---|---|---|---|
| `i_clk`, `i_rst_n` | I | 1 | referência de 2 GHz e reset |
| `i_enable` | I | 1 | PLL_ENABLE |
| `i_div_sel` | I | 2 | PLL_DIV_SEL: 00 = /1, 01 = /2, 10 = /4, 11 = /8 |
| `o_sys_clk` | O | 1 | clock de sistema, em 0 enquanto não travado |
| `o_locked` | O | 1 | PLL_LOCKED (domínio `clk`) |

- **Tempo de lock:** um LFSR de 16 bits roda o tempo todo. Enquanto o PLL está desabilitado, o contador de aquisição é recarregado com `LOCK_MIN + lfsr[LOCK_BITS-1:0]` (64 a 319 ciclos, com os parâmetros padrão). Habilitado, ele conta até 0 e levanta `locked`.
- **Divisores:** um contador de 3 bits gera /2, /4 e /8 pelos bits 0, 1 e 2. Ele fica parado em 0 até o lock, então os clocks divididos começam em nível baixo e não geram pulso curto.
- **/1:** é o próprio `clk`, passado por um AND com um enable atualizado na borda de descida. Assim o enable só muda com `clk` em 0, e o AND não gera glitch.
- **Divisor fixo durante a operação:** `PLL_DIV_SEL` só é aceito antes do lock. Ele pode ser escrito junto com `PLL_ENABLE` (passo 8 do modelo de programação), e uma mudança com o PLL travado só vale depois de desabilitar e habilitar de novo.

## 3. Verificação

### 3.1 Testbench

`tb/minisoc_spi_pll_tb.sv` liga `minisoc_spi` e `minisoc_pll_mock` pelos sinais PLL_ENABLE, PLL_DIV_SEL e PLL_LOCKED. Um mestre SPI Mode 0 de 40 bits a 25 MHz faz as transações. O `clk` é de 2 GHz.

| Teste | O que confere |
|---|---|
| Registradores R/W | escrita de valores aleatórios em 0x00–0x0A, leitura de volta e saídas `o_cfg_*`; campos e bits reservados de AES_CONTROL e SYSTEM_CONTROL |
| Registradores R | escrita em AES_STATUS, VERSION e SYSTEM_STATUS sem alterar o valor lido |
| NOP e endereços livres | escrita sem efeito nos registradores; leitura em 0 |
| AES_STATUS | BUSY, DONE e ERROR aleatórios e BLOCKS_DONE = 0, 1, 4, 255 e 256, enviados em Gray |
| START | uma escrita com START = 1 inverte o toggle uma vez; escrita sem START não inverte; START lido como 0 |
| Retorno da leitura | bits 39 a 32 da transação de retorno em 0 |
| PLL nos 4 divisores | `locked = 0` e `sys_clk` parado com o PLL desabilitado; PLL_DIV_SEL e PLL_ENABLE na mesma escrita; leitura de SYSTEM_STATUS até PLL_LOCKED = 1; período do `sys_clk` (0,5, 1, 2 e 4 ns) |
| Monitor | nenhuma borda de `sys_clk` com `locked = 0` durante toda a simulação |

### 3.2 Como executar

No servidor `microeletronica3`:

```bash
source /Tools/synopsys-scripts/snps.sh
make run                               # testbench da semana 5 (padrão)
make run TOP=minisoc_aes_dp_tb         # semana 4
make run TOP=minisoc_aes_round_tb      # semana 3
make run TOP=minisoc_aes_sub_shift_tb  # semana 2
make lint
```

### 3.3 Resultados

| Comando | Resultado |
|---|---|
| `make run` | **PASS: 116 verificações, 0 erros** |
| `make run TOP=minisoc_aes_dp_tb` | **PASS: 150 verificações, 0 erros** |
| `make run TOP=minisoc_aes_round_tb` | **PASS: 592 verificações, 0 erros** |
| `make run TOP=minisoc_aes_sub_shift_tb` | **PASS: 276 verificações, 0 erros** |
| `make lint` | **0 erros e 0 avisos** |

O PLL travou após 141, 100, 133 e 174 ciclos de `clk` (/1, /2, /4 e /8).

### 3.4 Relatório de lint

O log está em [lint/semana_05_lint.log](lint/semana_05_lint.log). O alvo `make lint` usa `+lint=all,noWMIA-L,noNS`. Para justificar as exceções, o lint foi executado também com `+lint=all`, sem nenhuma delas:

| Aviso | Onde | Justificativa |
|---|---|---|
| `Lint-[NS]` Null statement | `minisoc_spi.sv`, `default: ;` do decodificador de escrita | Intencional: escritas em registradores R, no NOP e em endereços livres não fazem nada. O `default` vazio deixa isso explícito e evita latch, porque o bloco é sequencial. |
| `Lint-[WMIA-L]` | — | Não dispara no RTL atual. A exceção vem da configuração inicial do Makefile. |

## 4. Decisões e ambiguidades do Block Guide

- **Posição da resposta no MISO:** o Block Guide diz que a segunda transação "desloca o valor lido", sem dizer em quais bits. Adotou-se o alinhamento com o campo DATA (bits 31 a 0), com os bits 39 a 32 em 0. A seção 4 da microarquitetura foi atualizada. **Ponto a confirmar com o verificador parceiro.**
- **Valor de VERSION:** não especificado. Adotado `0x0001_0000` (v1.0.0), como parâmetro.
- **NUM_BLOCKS:** os 32 bits são guardados e lidos de volta. Assim, um valor como `0x1000` chega ao AES e é rejeitado com ERROR, em vez de virar 0 por truncamento.
- **Divisor do PLL:** mudanças de PLL_DIV_SEL com o PLL travado são ignoradas até um novo enable. Isso evita trocar a frequência do `sys_clk` no meio de uma operação.

## 5. Problemas encontrados

- **Borda extra do `sys_clk` ao desabilitar o PLL:** o testbench detectou uma borda de subida do `sys_clk` com `locked = 0` nos divisores /4 e /8. O contador do divisor olhava o `locked` registrado e ainda incrementava uma vez no ciclo em que o enable caía. A correção foi zerar o contador também quando `i_enable = 0`.
- **Glitch no /1:** um AND direto de `clk` com `locked` geraria um pulso curto, porque `locked` muda logo depois da borda de subida, com `clk` em 1. Por isso o enable do /1 é registrado na borda de descida.

## 6. Próximos passos (semana 6, entrega 27/11)

- `minisoc_memory`: 1024 × 32, single-port síncrona, sem reset, com ownership por MEM_SEL_AES e mux de clock sem glitch.
- `minisoc_aes_top`: FSM da microarquitetura, captura da configuração no START, sincronização do toggle de START e status (BUSY, DONE, ERROR e BLOCKS_DONE em Gray).
- Modos ECB, CBC e CTR nos dois sentidos, com modelo de referência em Python e testbench com 1, 2 e 256 blocos.
