# Relatório — Semana 02: Desafio SubBytes e ShiftRows

> Entrega: 30/10/2026.
> Referências: [FIPS PUB 197](<../spec/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>) (Figura 7 e Apêndice B) e Block Guide do MiniSoC AES v1.0.0 (seções 1 a 3 e 8).

## 1. O que foi feito

- Reestruturação do repositório para o Block Guide do MiniSoC AES: instruções revisadas (13 semanas), nova figura de arquitetura, `rtl/` organizado conforme a seção 10 do Block Guide e relatórios renomeados para `semana_XX.md`.
- Implementação dos módulos combinacionais `minisoc_aes_sbox`, `minisoc_aes_sub_bytes` e `minisoc_aes_shift_rows`.
- Testbench autoverificável `minisoc_aes_sub_shift_tb`.
- Alvo `make lint` no Makefile.
- Leitura das seções 1 a 3 e 8 do Block Guide (dúvidas na seção 5).

## 2. Implementação

Todos os módulos ficam em `rtl/minisoc_aes/` e são puramente combinacionais.

### 2.1 Convenção do estado

O estado de 128 bits segue a ordem do Block Guide: o byte 0 fica em `[127:120]` e o byte 15 em `[7:0]`, ou seja, o byte `n` ocupa `[127-8n -: 8]`. O byte `n` corresponde a `s[r][c]`, com `r = n mod 4` e `c = n div 4` (FIPS-197, seção 3.4). Assim, cada coluna do estado é uma palavra de 32 bits, e a coluna 0 é `[127:96]`, a mesma Word 0 do Block Guide.

### 2.2 `minisoc_aes_sbox`

| Porta | Direção | Largura |
|---|---|---|
| `i_data` | entrada | 8 |
| `o_data` | saída | 8 |

Implementada como tabela de consulta (`localparam` com as 256 entradas da Figura 7 da FIPS-197) indexada pelo byte de entrada. Na síntese, a tabela vira lógica combinacional. A alternativa, calcular o inverso em GF(2⁸) seguido da transformação afim, ocupa menos área e pode ser avaliada na síntese (semana 8).

### 2.3 `minisoc_aes_sub_bytes`

| Porta | Direção | Largura |
|---|---|---|
| `i_state` | entrada | 128 |
| `o_state` | saída | 128 |

Um laço `generate` (`g_sbox`) instancia 16 S-boxes, uma por byte. O byte `n` de entrada é substituído e sai na mesma posição `n`.

### 2.4 `minisoc_aes_shift_rows`

| Porta | Direção | Largura |
|---|---|---|
| `i_state` | entrada | 128 |
| `o_state` | saída | 128 |

A linha `r` rotaciona `r` posições para a esquerda: `s'[r][c] = s[r][(c + r) mod 4]`. Como é apenas uma reordenação de bytes, o módulo é uma única concatenação, sem lógica. A saída, coluna a coluna, é formada pelos bytes de entrada:

```
coluna 0: 0, 5, 10, 15
coluna 1: 4, 9, 14,  3
coluna 2: 8, 13, 2,  7
coluna 3: 12, 1, 6, 11
```

## 3. Verificação

### 3.1 Testbench

`tb/minisoc_aes_sub_shift_tb.sv` instancia os três módulos e compara as saídas com valores de referência:

| Teste | Vetores | Verificações |
|---|---|---|
| S-box | Todas as 256 entradas, contra a Figura 7 da FIPS-197 | 256 |
| SubBytes | Apêndice B, rodadas 1 a 10: *Start of Round* → *After SubBytes* | 10 |
| ShiftRows | Apêndice B, rodadas 1 a 10: *After SubBytes* → *After ShiftRows* | 10 |

O pedido era testar pelo menos as rodadas 1 e 10. O testbench cobre todas as dez. Os vetores foram gerados por um modelo de referência em Python e conferidos contra a FIPS-197: a rodada 1 confere com os valores do enunciado, e a cifragem completa do Apêndice B resulta no ciphertext oficial `3925841d02dc09fbdc118597196a0b32`.

Ao final, o testbench imprime `PASS` ou `FAIL` com o número de verificações e de erros.

### 3.2 Como executar

No servidor `microeletronica3`, com VCS e Verdi X-2025.06-SP2:

```bash
source /Tools/synopsys-scripts/snps.sh
make run    # compila e simula o testbench
make lint   # lint do RTL (+lint=all), saída em lint.log
make wave   # abre as formas de onda no Verdi
```

### 3.3 Resultados

| Comando | Resultado |
|---|---|
| `make run` | **PASS: 276 verificações, 0 erros** |
| `make lint` | **0 erros e 0 avisos** |

O critério de aceite da semana (testbench executado por um único comando, com PASS em todos os casos, e lint sem erros) foi atendido.

## 4. Problemas encontrados

- **Atraso na especificação:** o Block Guide foi publicado junto com o desafio, o que exigiu reestruturar o repositório (nomes `minisoc_*`, organização de `rtl/`, cronograma de 13 semanas) antes de começar a implementação.
- **Block Guide confidencial:** o documento é marcado como confidencial e o repositório é público. Por isso ele não é versionado (está no `.gitignore`) e é apenas mencionado na documentação.
- **Ambiente da Synopsys:** as ferramentas não estão no `PATH` por padrão no servidor. É preciso carregar o ambiente com `source /Tools/synopsys-scripts/snps.sh` antes de usar o Makefile.

## 5. Dúvidas sobre o Block Guide

<!-- TODO: preencher após a leitura das seções 1 a 3 e 8. -->

## 6. Próximos passos (semana 3, entrega 06/11)

- Documento de microarquitetura: diagrama de blocos interno, microarquitetura do AES, FSM do `minisoc_aes_top`, estratégia de CDC entre `spi_sclk` e `clk` e sequência de reset do domínio do sistema.
- Implementação de MixColumns e AddRoundKey.
- Implementação das transformações inversas: InvSubBytes, InvShiftRows e InvMixColumns.
- Testes unitários com os Apêndices B e C.1 da FIPS-197.
- Apresentação da microarquitetura ao verificador parceiro.
