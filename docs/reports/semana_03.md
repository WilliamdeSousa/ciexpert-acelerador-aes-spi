# Relatório — Semana 03: Microarquitetura e transformações de rodada

> Entrega: 06/11/2026.
> Referências: [FIPS PUB 197](<../spec/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>) (seções 5.1 e 5.3, Apêndices B e C.1) e Block Guide do MiniSoC AES v1.0.0.

## 1. O que foi feito

- Implementação de MixColumns e AddRoundKey.
- Implementação das transformações inversas: S-box inversa, InvSubBytes, InvShiftRows e InvMixColumns.
- Testbench autoverificável `minisoc_aes_round_tb` com os valores intermediários dos Apêndices B e C.1 da FIPS-197.
- Documento de microarquitetura v1.0: [docs/architecture/microarquitetura.md](../architecture/microarquitetura.md).
- Novo fluxo de trabalho no repositório: branch `dev` para o trabalho da semana, com um commit por issue (#10 a #13) e PR semanal de `dev` para `main`.

## 2. Implementação

Todos os módulos ficam em `rtl/minisoc_aes/`, são puramente combinacionais e seguem a convenção de estado da semana 2: o byte 0 fica em `[127:120]` e a coluna `c` ocupa `[127-32c -: 32]`.

| Módulo | Função |
|---|---|
| `minisoc_aes_mix_columns` | Multiplica cada coluna pela matriz `02 03 01 01` em GF(2⁸) |
| `minisoc_aes_add_round_key` | `o_state = i_state ^ i_round_key` |
| `minisoc_aes_inv_sbox` | Tabela inversa (FIPS-197, Figura 14) |
| `minisoc_aes_inv_sub_bytes` | 16 instâncias da S-box inversa |
| `minisoc_aes_inv_shift_rows` | A linha `r` rotaciona `r` posições para a direita |
| `minisoc_aes_inv_mix_columns` | Multiplica cada coluna pela matriz `0e 0b 0d 09` em GF(2⁸) |

### 2.1 MixColumns e InvMixColumns

A multiplicação por 02 em GF(2⁸) é a função `xtime`, que desloca o byte 1 bit à esquerda e, se o bit 7 era 1, faz XOR com `1b` (redução por x⁸ + x⁴ + x³ + x + 1):

```systemverilog
xtime(b) = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00)
```

A multiplicação por 03 é `xtime(b) ^ b`. Na InvMixColumns, os coeficientes são decompostos em potências de 2: por exemplo, `0e = 08 ^ 04 ^ 02`. Assim, as duas transformações usam apenas deslocamentos e XOR, sem multiplicadores. A InvMixColumns tem bem mais lógica que a MixColumns, o que torna a decifra mais cara em área.

### 2.2 AddRoundKey

AddRoundKey é a própria inversa, porque `(s ^ k) ^ k = s`. Por isso o mesmo módulo serve à cifra e à decifra. Na cifra inversa, só muda a ordem das round keys, que são usadas de 10 para 0.

### 2.3 InvShiftRows

`s'[r][(c + r) mod 4] = s[r][c]`. Coluna a coluna, a saída é formada pelos bytes de entrada:

```
coluna 0: 0, 13, 10,  7
coluna 1: 4,  1, 14, 11
coluna 2: 8,  5,  2, 15
coluna 3: 12, 9,  6,  3
```

## 3. Verificação

### 3.1 Testbench

`tb/minisoc_aes_round_tb.sv` instancia todos os módulos de rodada, diretos e inversos, e compara as saídas com os valores de referência:

| Teste | Vetores | Verificações |
|---|---|---|
| S-box e S-box inversa | 256 entradas cada (`inv_sbox(S(x)) = x`) | 512 |
| Cifragem | Apêndice B, rodadas 0 a 10: SubBytes, ShiftRows, MixColumns (rodadas 1 a 9) e AddRoundKey | 40 |
| Cifragem inversa | Apêndice C.1, rodadas 0 a 10: InvShiftRows, InvSubBytes, AddRoundKey e InvMixColumns (rodadas 1 a 9) | 40 |

Os vetores foram gerados por um modelo de referência em Python e conferidos contra a FIPS-197. A cifragem do Apêndice B resulta em `3925841d02dc09fbdc118597196a0b32`, e a cifragem inversa do Apêndice C.1 recupera o plaintext `00112233445566778899aabbccddeeff`. Os valores intermediários conferem com os publicados.

### 3.2 Como executar

No servidor `microeletronica3`:

```bash
source /Tools/synopsys-scripts/snps.sh
make run                              # testbench da semana 3 (padrão)
make run TOP=minisoc_aes_sub_shift_tb # testbench da semana 2
make lint
```

### 3.3 Resultados

| Comando | Resultado |
|---|---|
| `make run` | **PASS: 592 verificações, 0 erros** |
| `make run TOP=minisoc_aes_sub_shift_tb` | **PASS: 276 verificações, 0 erros** |
| `make lint` | **0 erros e 0 avisos** |

## 4. Microarquitetura

O documento completo está em [docs/architecture/microarquitetura.md](../architecture/microarquitetura.md). As principais decisões foram:

| Tema | Decisão |
|---|---|
| Arquitetura do AES | Iterativa, uma rodada por ciclo, com o estado num registrador interno. A memória só é usada no início e no fim de cada bloco. |
| Expansão de chave | 11 round keys calculadas uma vez por operação, logo após o START, e guardadas em registradores |
| Modos de operação | O `minisoc_aes_dp` processa um bloco, e o `minisoc_aes_top` faz o encadeamento (IV, contador, realimentação) |
| Cifra e decifra | Dois caminhos de rodada com um mux controlado por `decrypt` |
| CDC | Toggle para pulsos (frame SPI, START), configuração capturada no START, 2 FF para os bits de status, código Gray para BLOCKS_DONE e mux de clock sem glitch na memória |
| Reset | Um sincronizador por domínio. O domínio do sistema fica em reset até o PLL travar e mais 16 ciclos. |

A latência estimada é de 11 ciclos por bloco no datapath, cerca de 21 ciclos por bloco com os acessos à memória, mais 10 ciclos de expansão de chave por operação.

## 5. Problemas encontrados

- **Ambiguidades do Block Guide:** a especificação não define vários pontos da implementação, como o caminho de leitura da memória para o AES, o endereço base dos blocos e o formato do contador do CTR. Esses pontos foram tratados como decisões de microarquitetura.
- **Área da decifra:** a InvMixColumns e o segundo caminho de rodada aumentam a área. O compartilhamento de lógica entre cifra e decifra ficou para a otimização na síntese.

## 6. Próximos passos (semana 4, entrega 13/11)

- Implementação de `minisoc_aes_key_exp`, com as 11 round keys pré-calculadas.
- Implementação de `minisoc_aes_dp`: cifra e cifra inversa de um bloco, com a interface `start/done` definida na microarquitetura.
- Testbench com os vetores da FIPS-197, nos dois sentidos.
