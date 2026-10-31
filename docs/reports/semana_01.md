# Relatório de Estudo — Semana 01: AES (FIPS-197) e SPI

> Referências:
> - [FIPS PUB 197, *Advanced Encryption Standard (AES)*, NIST, 2001](<../spec/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>). Essa versão foi substituída pela **FIPS 197-upd1 (2023)**, que tem apenas mudanças editoriais. O algoritmo é o mesmo.
> - [P. Dhaker, *Introduction to SPI Interface*, Analog Dialogue, Analog Devices, 2018](https://www.analog.com/en/resources/analog-dialogue/articles/introduction-to-spi-interface.html).

## Parte I — AES (FIPS-197)

### 1. Visão geral

O AES é uma **cifra de bloco simétrica**: a mesma chave cifra e decifra. Ele é baseado no algoritmo Rijndael e opera sempre sobre **blocos de 128 bits**, com chaves de **128, 192 ou 256 bits**. Uma implementação precisa suportar pelo menos um desses tamanhos de chave.

| Variante | Nk (palavras de chave) | Nb (palavras do bloco) | Nr (rodadas) |
|----------|:---:|:---:|:---:|
| AES-128  | 4 | 4 | 10 |
| AES-192  | 6 | 4 | 12 |
| AES-256  | 8 | 4 | 14 |

Uma "palavra" tem 32 bits (4 bytes).

### 2. O State

Internamente, o bloco de 16 bytes é organizado em uma matriz 4×4 chamada **State**, preenchida **coluna a coluna**:

```
in0  in4  in8  in12        s[r,c] = in[r + 4c]
in1  in5  in9  in13
in2  in6  in10 in14
in3  in7  in11 in15
```

Cada coluna também pode ser vista como uma palavra de 32 bits (w0..w3). Na saída, o State é copiado de volta para o vetor `out` na mesma ordem.

### 3. Fundamentos matemáticos: GF(2⁸)

Cada byte é tratado como um elemento do corpo finito GF(2⁸), representado como um polinômio de grau < 8.

- **Soma:** é um XOR bit a bit. Subtração é a mesma coisa que soma.
- **Multiplicação:** é a multiplicação de polinômios módulo o polinômio irredutível m(x) = x⁸ + x⁴ + x³ + x + 1 (`{01}{1b}`).
- **xtime():** multiplicar por `{02}` equivale a um deslocamento à esquerda seguido de XOR com `{1b}` se o bit 7 era 1. Multiplicações por outras constantes se constroem com xtime e XORs. Em hardware, isso é apenas lógica combinacional simples.
- **Inverso multiplicativo:** todo byte diferente de zero tem um inverso. Por convenção, `{00}` é mapeado para si mesmo.

As colunas também são tratadas como polinômios de 4 termos com coeficientes em GF(2⁸), multiplicados módulo x⁴ + 1. É essa operação que define o MixColumns.

### 4. Cifração (Cipher)

```
State = in
AddRoundKey(State, k[0])
para round = 1 .. Nr-1:
    SubBytes(State)
    ShiftRows(State)
    MixColumns(State)
    AddRoundKey(State, k[round])
SubBytes(State)
ShiftRows(State)
AddRoundKey(State, k[Nr])        // última rodada sem MixColumns
out = State
```

#### 4.1 SubBytes

Substituição **não linear** de cada byte pela **S-box**. A S-box é construída em dois passos:

1. Calcular o inverso multiplicativo do byte em GF(2⁸).
2. Aplicar uma transformação afim sobre GF(2), com a constante `{63}`.

Na prática, a S-box é uma tabela fixa de 256 entradas (Fig. 7 da norma). Exemplo: S(`{53}`) = `{ed}`.

#### 4.2 ShiftRows

Rotação cíclica das linhas do State para a esquerda:

| Linha | Deslocamento |
|---|---|
| 0 | 0 |
| 1 | 1 |
| 2 | 2 |
| 3 | 3 |

Em hardware isso é **apenas fiação**, sem nenhuma lógica.

#### 4.3 MixColumns

Cada coluna é multiplicada pela matriz fixa:

```
| 02 03 01 01 |
| 01 02 03 01 |
| 01 01 02 03 |
| 03 01 01 02 |
```

Por exemplo, s'₀ = 2·s₀ ⊕ 3·s₁ ⊕ s₂ ⊕ s₃. Isso dá **difusão**: cada byte de saída depende dos quatro bytes da coluna.

#### 4.4 AddRoundKey

XOR do State com a chave de rodada, que tem 128 bits (4 palavras do key schedule). Ela é a sua própria inversa.

### 5. Expansão de chave (Key Expansion)

A partir da chave original, a expansão gera **Nb·(Nr+1)** palavras: 44 para AES-128, 52 para AES-192 e 60 para AES-256. Em resumo:

- As primeiras **Nk** palavras são a própria chave.
- Cada nova palavra é `w[i] = w[i-Nk] ⊕ temp`, onde `temp = w[i-1]`.
- Se `i mod Nk = 0`, então `temp = SubWord(RotWord(temp)) ⊕ Rcon[i/Nk]`.
- Só no AES-256: se `i mod Nk = 4`, então `temp = SubWord(temp)`.

As funções auxiliares são:

- **RotWord:** `[a0,a1,a2,a3] → [a1,a2,a3,a0]`.
- **SubWord:** aplica a S-box em cada um dos 4 bytes.
- **Rcon[i]:** `[xⁱ⁻¹, 00, 00, 00]`, ou seja, `01, 02, 04, 08, 10, 20, 40, 80, 1b, 36, ...`.

Para implementação em hardware, a expansão pode ser feita **on-the-fly**, calculando uma chave por rodada, ou **pré-calculada**, armazenando todas. Na cifração, on-the-fly economiza área. Na decifração, as chaves são usadas na ordem inversa.

### 6. Decifração

#### 6.1 Inverse Cipher

A decifração aplica as transformações inversas, em ordem reversa e com as chaves da última para a primeira:

- **InvShiftRows:** rotação das linhas para a direita.
- **InvSubBytes:** usa a S-box inversa (Fig. 14).
- **InvMixColumns:** usa a matriz com os coeficientes `0e 0b 0d 09`, mais cara em hardware que a da cifração.
- **AddRoundKey:** é igual à da cifração.

#### 6.2 Equivalent Inverse Cipher

Duas propriedades permitem reordenar as etapas da decifração:

1. SubBytes e ShiftRows comutam.
2. InvMixColumns é linear.

Com isso, a decifração passa a ter **a mesma sequência de etapas da cifração**, com cada etapa trocada pela sua inversa. O custo é aplicar InvMixColumns nas chaves das rodadas 1 a Nr-1. Isso é útil para compartilhar estrutura de controle entre cifração e decifração.

### 7. Vetores de teste

O Apêndice C da norma traz os valores intermediários de cada etapa de cada rodada, para as três variantes. Eles são ideais para testes unitários das transformações. Exemplo do AES-128 (C.1):

```
PLAINTEXT : 00112233445566778899aabbccddeeff
KEY       : 000102030405060708090a0b0c0d0e0f
CIPHERTEXT: 69c4e0d86a7b0430d8cdb78070b4c55a
```

O Apêndice A traz a expansão de chave passo a passo. O Apêndice B traz um exemplo completo da cifração com o State a cada etapa.

### 8. Observações para implementação em hardware

- Uma rodada completa (SubBytes → ShiftRows → MixColumns → AddRoundKey) é **combinacional** e pode ser feita em um ciclo por rodada. Para AES-128 isso dá 10 rodadas mais a AddRoundKey inicial, cerca de 11 ciclos.
- A **S-box** domina a área: são 16 no datapath e mais 4 na expansão de chave. Ela pode ser implementada como LUT ou em campo composto, que é menor.
- ShiftRows é apenas fiação. MixColumns e AddRoundKey são XORs com xtime.
- Suportar **decifração** adiciona a S-box inversa e InvMixColumns, além de exigir a geração das chaves na ordem inversa.

## Parte II — Interface SPI

O artigo usa os termos *main* e *subnode* no lugar dos antigos *master* e *slave*. Este relatório segue essa nomenclatura.

### 9. Visão geral

O SPI (*Serial Peripheral Interface*) é uma interface serial **síncrona** e **full duplex**, muito usada entre microcontroladores e periféricos como sensores, ADCs, DACs, registradores de deslocamento e SRAM.

- **Síncrona:** os dados são sincronizados com a borda (de subida ou de descida) de um clock gerado pelo main.
- **Full duplex:** main e subnode transmitem ao mesmo tempo.
- Existe em versões de 3 e de 4 fios. O artigo e este relatório tratam da versão de **4 fios**, a mais comum.
- Há **um único main** no barramento e **um ou mais subnodes**.
- Suporta frequências de clock bem maiores que o I²C. O limite vem do datasheet de cada dispositivo.

### 10. Sinais

| Sinal | Nome | Direção | Função |
|---|---|---|---|
| SCLK | Serial Clock | main → subnode | Clock gerado pelo main. Sincroniza todos os dados. |
| CS | Chip Select | main → subnode | Seleciona o subnode. Normalmente **ativo em nível baixo**. |
| MOSI | Main Out, Subnode In | main → subnode | Dados do main para o subnode (também chamado SDI no subnode). |
| MISO | Main In, Subnode Out | subnode → main | Dados do subnode para o main (também chamado SDO no subnode). |

Com CS em nível alto, o subnode fica desconectado do barramento. Cada subnode precisa do seu próprio CS (ver seção 13).

### 11. Transmissão de dados

1. O main seleciona o subnode colocando **CS em 0** e começa a gerar o clock.
2. A cada ciclo de SCLK, os dois lados **deslocam** (*shift*) um bit para fora e **amostram** (*sample*) um bit de entrada. Main envia por MOSI e recebe por MISO ao mesmo tempo.
3. Uma borda do clock é usada para deslocar e a outra para amostrar. Quais bordas fazem o quê depende do modo SPI.
4. O main encerra a transação colocando CS de volta em 1.

O número de bits por transação não é fixado pelo SPI. Ele é definido pelo datasheet de cada dispositivo.

Na prática, os dois lados funcionam como **registradores de deslocamento ligados em anel**: a cada bit que o main envia, ele recebe um bit do subnode.

### 12. Polaridade e fase do clock (CPOL / CPHA)

- **CPOL** define o nível do clock no estado ocioso (*idle*). O idle é o período em que CS está em 1, incluindo as transições de CS no início e no fim da transmissão.
- **CPHA** define a fase, ou seja, qual borda é usada para amostrar e qual é usada para deslocar os dados.

O main deve configurar CPOL e CPHA de acordo com o que o subnode exige. As combinações dão os quatro modos:

| Modo | CPOL | CPHA | Clock em idle | Amostra na borda | Desloca na borda |
|:---:|:---:|:---:|---|---|---|
| 0 | 0 | 0 | Baixo | Subida | Descida |
| 1 | 0 | 1 | Baixo | Descida | Subida |
| 2 | 1 | 0 | Alto | Descida | Subida |
| 3 | 1 | 1 | Alto | Subida | Descida |

Uma regra fácil de lembrar: com **CPHA = 0**, a amostragem acontece na **primeira** borda do clock depois que CS desce. Por isso o primeiro bit já precisa estar na linha antes do primeiro pulso. Com **CPHA = 1**, a primeira borda desloca e a amostragem acontece na **segunda**.

As Figuras 2 a 5 do artigo mostram o diagrama de tempo de cada modo. Elas são só ilustrativas: os tempos reais (setup, hold, frequência máxima) vêm sempre do datasheet do dispositivo.

### 13. Vários subnodes

#### 13.1 Modo regular (CS independente)

- O main tem **um CS para cada subnode**. SCLK, MOSI e MISO são compartilhados.
- Só **um CS pode estar ativo por vez**. Se dois subnodes forem selecionados juntos, os dois dirigem a linha MISO e os dados se corrompem.
- O número de pinos do main cresce com o número de subnodes. Uma saída é gerar os CS com um mux ou decodificador.

#### 13.2 Daisy-chain

- **Um único CS** é compartilhado por todos os subnodes, e todos recebem o mesmo SCLK.
- O MOSI do main vai para o primeiro subnode. A saída de dados de cada subnode alimenta a entrada do próximo, e a do último volta para o MISO do main.
- Os dados atravessam a cadeia: com palavras de 8 bits, o 3º subnode só recebe seus dados depois de **24 pulsos de clock**, contra 8 no modo regular. O número de ciclos cresce com a posição na cadeia.
- Nem todo dispositivo SPI suporta daisy-chain. É preciso conferir no datasheet.

#### 13.3 Exemplo do artigo: chaves analógicas com SPI

O artigo compara formas de controlar quatro chaves quádruplas SPST (ADG1412 / ADGS1412), totalizando 16 sinais de controle:

| Abordagem | GPIOs do main |
|---|:---:|
| Controle paralelo direto (ADG1412) | 16 |
| Chaves com SPI (ADGS1412), modo regular | 7 (SCLK, MOSI, MISO + 4 CS) |
| Chaves com SPI em daisy-chain | 4, independente do número de chaves |

Uma alternativa intermediária é usar um conversor serial-paralelo controlado por SPI, mas isso adiciona um componente à lista de materiais.
