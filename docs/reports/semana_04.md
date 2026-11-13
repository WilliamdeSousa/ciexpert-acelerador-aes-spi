# Relatório — Semana 04: Expansão de chave e datapath AES-128

> Entrega: 13/11/2026.
> Referências: [FIPS PUB 197](<../spec/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>) (seções 5.1 a 5.3, Apêndices A.1, B e C.1) e [documento de microarquitetura](../architecture/microarquitetura.md) (seções 5.1 e 5.2).

## 1. O que foi feito

- Implementação de `minisoc_aes_key_exp`: expansão da chave AES-128 com as 11 round keys pré-calculadas (#15).
- Implementação de `minisoc_aes_dp`: datapath iterativo de um bloco, com cifra e cifra inversa e interface `start/done` (#16).
- Testbench autoverificável `minisoc_aes_dp_tb`, com `key_exp` e `dp` integrados (#17).

## 2. Implementação

### 2.1 `minisoc_aes_key_exp`

| Porta | Dir. | Largura | Descrição |
|---|---|---|---|
| `i_clk`, `i_rst_n` | I | 1 | clock e reset assíncrono ativo em nível baixo |
| `i_start` | I | 1 | captura `i_key` e inicia a expansão |
| `i_key` | I | 128 | chave |
| `i_round` | I | 4 | índice da round key lida (0 a 10) |
| `o_round_key` | O | 128 | round key `i_round` |
| `o_ready` | O | 1 | as 11 round keys estão disponíveis |

No `start`, a chave é copiada para `rk[0]`. A cada ciclo, a próxima round key é calculada a partir da última (FIPS-197, seção 5.2):

```
temp     = SubWord(RotWord(w3)) ^ {Rcon[i], 24'h0}
w0'      = w0 ^ temp
w1'      = w1 ^ w0'
w2'      = w2 ^ w1'
w3'      = w3 ^ w2'
```

O cálculo usa 4 S-boxes (SubWord) e uma cadeia de XOR. A round key mais recente fica num registrador à parte (`last_q`), o que evita um mux de 11 entradas na realimentação. As 11 chaves ficam em registradores sem reset, por serem dados que sempre são escritos antes de serem lidos. Só os registradores de controle têm reset.

**Latência:** 10 ciclos após o `start`, uma vez por operação.

**Justificativa da expansão pré-calculada:**

| | Pré-calculada (escolhida) | On-the-fly |
|---|---|---|
| Registradores | 11 × 128 = 1408 flip-flops | 128 flip-flops |
| Decriptação | lê as chaves de 10 para 0 sem custo extra | precisa expandir até `rk[10]` antes de começar e derivar as chaves em ordem inversa (lógica adicional) |
| Vários blocos | a expansão é feita uma vez e serve a todos os blocos da operação | as chaves são recalculadas a cada bloco |

A expansão pré-calculada é mais simples e não penaliza a decriptação nem os modos com vários blocos. O custo em área será medido na síntese (semana 8), onde a alternativa on-the-fly pode ser reavaliada.

### 2.2 `minisoc_aes_dp`

| Porta | Dir. | Largura | Descrição |
|---|---|---|---|
| `i_clk`, `i_rst_n` | I | 1 | clock e reset assíncrono ativo em nível baixo |
| `i_start` | I | 1 | inicia o processamento de `i_block` |
| `i_decrypt` | I | 1 | 0 = cifra, 1 = cifra inversa |
| `i_block` | I | 128 | bloco de entrada |
| `o_round` | O | 4 | índice da round key necessária |
| `i_round_key` | I | 128 | round key vinda do `key_exp` |
| `o_block` | O | 128 | bloco de saída |
| `o_done` | O | 1 | pulso de 1 ciclo: `o_block` válido |

- **Rodada 0:** no `start`, o registrador de estado recebe `i_block ^ rk`, com `rk[0]` na cifra e `rk[10]` na decifra.
- **Rodadas 1 a 10:** uma por ciclo. Os dois caminhos são combinacionais e existem lado a lado, e um mux controlado por `decrypt` escolhe qual resultado volta ao registrador de estado:
  - direto: SubBytes → ShiftRows → MixColumns → AddRoundKey;
  - inverso: InvShiftRows → InvSubBytes → AddRoundKey → InvMixColumns.
- Na rodada 10, MixColumns e InvMixColumns são ignorados.
- **Round key:** `o_round` vale `r` na cifra e `10 - r` na decifra. Fora de uma operação, aponta para a chave da rodada 0 (`0` ou `10`, conforme `i_decrypt`), para que o AddRoundKey inicial já esteja pronto no ciclo do `start`.
- **Latência:** 11 ciclos, da borda que captura o `start` até a borda que levanta o `o_done`.

O `dp` reaproveita, sem alterações, os módulos de rodada das semanas 2 e 3.

## 3. Verificação

### 3.1 Testbench

`tb/minisoc_aes_dp_tb.sv` liga `key_exp` e `dp` como no `minisoc_aes_top`: o `dp` escolhe a round key por `o_round`. Para cada vetor, o testbench:

1. expande a chave e compara as 11 round keys com a referência;
2. cifra `pt` e compara com `ct`;
3. decifra `ct` com as mesmas round keys e compara com `pt`;
4. confere a latência de 11 ciclos nas duas operações.

| Vetores | Origem |
|---|---|
| Apêndice B | `key = 2b7e1516…`, `pt = 3243f6a8…`, `ct = 3925841d…` (round keys do Apêndice A.1) |
| Apêndice C.1 | `key = 00010203…`, `pt = 00112233…`, `ct = 69c4e0d8…` |
| 8 aleatórios | chave e bloco aleatórios, com os valores esperados gerados pelo modelo de referência em Python |

São 15 verificações por vetor (11 round keys, 2 blocos e 2 latências), num total de 150.

### 3.2 Como executar

No servidor `microeletronica3`:

```bash
source /Tools/synopsys-scripts/snps.sh
make run                               # testbench da semana 4 (padrão)
make run TOP=minisoc_aes_round_tb      # semana 3
make run TOP=minisoc_aes_sub_shift_tb  # semana 2
make lint
```

### 3.3 Resultados

| Comando | Resultado |
|---|---|
| `make run` | **PASS: 150 verificações, 0 erros** |
| `make run TOP=minisoc_aes_round_tb` | **PASS: 592 verificações, 0 erros** |
| `make run TOP=minisoc_aes_sub_shift_tb` | **PASS: 276 verificações, 0 erros** |
| `make lint` | **0 erros e 0 avisos** |

O critério de aceite da semana (cifragem e decriptação conferem com os vetores de referência; lint sem erros) foi atendido.

## 4. Problemas encontrados

- **Índice da Rcon:** a primeira versão indexava uma tabela por `idx - 1`, que daria um índice fora da tabela com `idx = 0`. A tabela foi trocada por uma função com `case`, com valor padrão `00`.
- **Round key da rodada 0:** como o AddRoundKey inicial acontece no ciclo do `start`, o `dp` precisa indicar a round key certa antes de começar. A solução foi o `o_round` apontar para a chave da rodada 0, segundo `i_decrypt`, enquanto o datapath está ocioso.

## 5. Próximos passos (semana 5, entrega 20/11)

- `minisoc_spi`: SPI Mode 0, frame de 40 bits, banco de registradores e sincronização por toggle (#19).
- `minisoc_pll_mock`: divisores /1, /2, /4 e /8 e `locked` após um número pseudoaleatório de ciclos (#20).
- Testbench dirigido de escrita e leitura de todos os registradores e de travamento do PLL (#21).
- Relatório da semana 5, com o relatório de lint e a justificativa dos avisos (#22).
