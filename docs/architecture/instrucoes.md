# Instruções do projeto: Acelerador AES com interface SPI e baixo consumo

> Instruções fornecidas pelo instrutor (versão revisada em 27/10/2026).

## Visão geral

O *[Advanced Encryption Standard](<../spec/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>)*, ou AES, é um padrão de criptografia simétrica amplamente utilizado para proteger dados. Neste projeto, os alunos da trilha RTL desenvolverão um sistema de topo com datapath AES, a mesma arquitetura (*AES Top-Level System*) adotada no projeto integrador da trilha de Design Verification. O sistema é configurado e controlado por uma [interface SPI](https://www.analog.com/en/resources/analog-dialogue/articles/introduction-to-spi-interface.html), recebe e devolve dados por uma interface de dados com memória e conta com blocos de reset e de geração de clock.

![Arquitetura do MiniSoC AES](rsc/architecture.png)

*Figura 1 – Arquitetura-base do sistema de topo, a mesma utilizada pela trilha de Design Verification.*

O projeto percorre o fluxo típico de desenvolvimento de um IP digital: do RTL à primeira síntese, passando pela verificação formal de equivalência e pela aplicação de técnicas de baixo consumo, com a intenção de potência descrita em UPF. Ao final, cada aluno terá um IP sintetizável, com equivalência formal entre RTL e netlist comprovada, verificado em simulação por um aluno da trilha de verificação e preparado para operar em diferentes modos de energia.

O projeto terá duração de **13 semanas**, com **um entregável por semana**; o encerramento é em 29/01/2027 e recesso de fim de ano entre 21/12/2026 e 03/01/2027.

> **Escopo deste documento:** descrever como o projeto será executado (etapas, cronograma, entregáveis e critérios de aceite). A especificação funcional é o Block Guide do MiniSoC AES (v1.0.0), fornecido pelo instrutor. Interfaces de topo, nomes de módulos e arquivos, mapa de registradores, protocolo SPI e modelo de programação devem seguir o Block Guide; divergências e ambiguidades são registradas como issues e levadas ao instrutor.
> 

Especificação de referência: Block Guide – MiniSoC AES (v1.0.0), o mesmo documento utilizado pela trilha de Design Verification.

> O Block Guide é um documento confidencial e por isso não é versionado neste repositório. Ele está disponível na página do hands-on no Notion.

---

## Objetivos de aprendizagem

Ao concluir o projeto, o aluno deverá ser capaz de:

- transformar uma especificação em arquitetura, microarquitetura e RTL sintetizável;
- integrar um sistema de topo com reset, geração de clock, configuração por SPI, datapath e memória;
- integrar blocos com domínios de clock distintos, tratando a sincronização entre eles;
- preparar restrições de timing e executar uma síntese lógica, interpretando os relatórios de área, timing e potência;
- utilizar verificação formal de equivalência entre RTL e netlist com o Formality;
- descrever a intenção de potência de um projeto com UPF;
- aplicar e avaliar técnicas de baixo consumo, como clock gating, power gating, isolamento de operandos e retenção de estado;
- documentar e apresentar tecnicamente as decisões de projeto.

---

## Organização

A organização seguirá o fluxo **cliente/instrutor → alunos**.

- **Instrutor:** define o escopo, a especificação funcional e os critérios de aceite; fornece as ferramentas e o PDK; acompanha as entregas semanais; conduz as defesas e revisões técnicas.
- **Alunos:** cada aluno prepara o seu ambiente inicial (repositório e scripts), gerencia o seu backlog, desenvolve o seu próprio IP, executa as atividades de projeto, registra as decisões e produz os entregáveis.
- **Verificador parceiro:** cada aluno da trilha RTL terá o seu IP verificado por um aluno da trilha de verificação (ver seção *Interação com a trilha de verificação*).

### Ritmo semanal

| Momento | Atividade |
| --- | --- |
| Início da semana | Planejamento: atualização do backlog pelo aluno e definição das tarefas da semana |
| Meio da semana | Ponto de acompanhamento com o instrutor (bloqueios e dúvidas) |
| Fim da semana | Entrega do artefato da semana no repositório e revisão com o instrutor com sabatina oral a respeito do que foi feito |

### Regras gerais para os entregáveis

- Todo entregável deve estar no repositório Git do aluno, em uma *tag* ou *branch* identificada pela semana (ex.: `w06-rtl-v1.0`).
- Todo entregável deve vir acompanhado de um relatório curto (`docs/reports/semana_XX.md`) com o que foi feito, os resultados obtidos, os problemas encontrados e os próximos passos.
- Relatórios de ferramentas (lint, síntese, formal, UPF) devem ser versionados junto com os scripts que os geraram.
- Uma entrega só é considerada concluída quando atende ao critério de aceite da semana.
- Defeitos reportados pelo verificador parceiro são registrados como *issues* no repositório e tratados no backlog do aluno.

---

## Fases do projeto

> Cronograma revisado em 27/10/2026. O projeto foi replanejado para terminar em 29/01/2027: são 13 semanas de entrega, com recesso de fim de ano entre 21/12/2026 e 03/01/2027. A Semana 1 está concluída. As demais semanas seguem o Block Guide do MiniSoC AES (v1.0.0), que passa a ser a especificação funcional do projeto.
> 

| Fase | Semanas | Período | Foco |
| --- | --- | --- | --- |
| 1. Kick-off e ambiente | 1 | concluída | Estudo, repositório e fluxo mínimo |
| 2. Desenvolvimento do RTL | 2–7 | 30/10 a 04/12 | Datapath AES, SPI, PLL mock, AES engine, memória e integração (RTL v1.0) |
| 3. Síntese inicial | 8 | 11/12 | SDC, síntese e baseline de área, timing e potência |
| 4. Verificação formal de equivalência | 9 | 18/12 | Equivalência RTL × netlist com o Formality |
| Recesso | — | 21/12 a 03/01 | Sem entregas |
| 5. Fechamento funcional | 10 | 08/01 | Modos restantes, correções e RTL v1.1 |
| 6. Intenção de potência e baixo consumo | 11–12 | 15/01 a 22/01 | Arquitetura de energia, UPF, power gating e clock gating (RTL v2.0) |
| 7. Síntese low power e encerramento | 13 | 29/01 | Comparação com o baseline e apresentação final |

---

## Cronograma semanal

As entregas acontecem sempre na sexta-feira indicada em cada semana. Todas as referências a seções (por exemplo, "seção 6") remetem ao Block Guide do MiniSoC AES.

### Semana 1 — Kick-off, estudo e ambiente (concluída)

Atividades

- Apresentação do projeto e da especificação funcional.
- Estudo do algoritmo AES (FIPS-197) e do protocolo SPI (modos de operação, polaridade e fase de clock).
- Preparação do ambiente inicial pelo aluno: repositório, scripts de execução e configuração das ferramentas fornecidas (simulador, lint).
- Criação do backlog inicial do projeto.

Entregável: repositório estruturado, backlog inicial, ambiente executando um exemplo mínimo (compilação, lint e simulação) e relatório de estudo sobre AES e SPI.

Critério de aceite: o repositório pode ser clonado em um ambiente limpo e o fluxo mínimo executado com um único comando.

---

### Semana 2 — Desafio: SubBytes e ShiftRows (entrega 30/10)

Desafio curto para retomar o ritmo. As duas transformações são combinacionais, independentes do restante do sistema e serão reaproveitadas no datapath (minisoc_aes_dp) a partir da Semana 3.

Atividades

- Implementar minisoc_aes_sbox: entrada de 8 bits, saída de 8 bits, puramente combinacional (tabela de 256 entradas da FIPS-197, Figura 7, ou cálculo pela inversa em GF(2^8) seguida da transformação afim).
- Implementar minisoc_aes_sub_bytes: estado de 128 bits, com 16 instâncias da S-box.
- Implementar minisoc_aes_shift_rows: estado de 128 bits, apenas reordenação de fios.
- Convenção do estado: o byte 0 fica em [127:120] e o byte 15 em [7:0], na mesma ordem do Block Guide (a Word 0 de um bloco é [127:96]). O byte n corresponde a s[r][c], com r = n mod 4 e c = n div 4 (FIPS-197, seção 3.4).
- Testbench autoverificável: (a) S-box nas 256 entradas, comparada com uma tabela de referência; (b) SubBytes e ShiftRows aplicados aos estados do exemplo de cifragem da FIPS-197 (Apêndice B), conferindo "Start of Round" → "After SubBytes" → "After ShiftRows" pelo menos nas rodadas 1 e 10.
- Leitura das seções 1 a 3 e 8 do Block Guide, registrando dúvidas e ambiguidades.

Vetores de referência (FIPS-197, Apêndice B, rodada 1):

```
start of round  : 193de3bea0f4e22b9ac68d2ae9f84808
after SubBytes  : d42711aee0bf98f1b8b45de51e415230
after ShiftRows : d4bf5d30e0b452aeb84111f11e2798e5

sbox(8'h00) = 8'h63
sbox(8'h53) = 8'hed
```

Entregável: RTL de minisoc_aes_sbox, minisoc_aes_sub_bytes e minisoc_aes_shift_rows, testbench autoverificável e relatório curto (docs/reports/semana_02.md) com o resultado dos testes e a lista de dúvidas sobre o Block Guide.

Critério de aceite: testbench executado por um único comando, com PASS nas 256 entradas da S-box e nos vetores do Apêndice B; lint sem erros.

Opcional: InvSubBytes e InvShiftRows, testadas como inversas (InvSubBytes(SubBytes(x)) = x).

---

### Semana 3 — Microarquitetura e transformações de rodada (entrega 06/11)

Atividades

- Documento de microarquitetura curto. O Block Guide já fixa as interfaces de topo, os módulos e arquivos, o mapa de registradores e o protocolo SPI; o aluno define como implementá-los: diagrama de blocos interno, microarquitetura do AES (por exemplo, iterativa com uma rodada por ciclo, ou outra alternativa justificada), FSM do minisoc_aes_top, estratégia de CDC entre spi_sclk e clk (sincronização por toggle, seção 5.3) e sequência de reset do domínio do sistema (seção 4.2).
- Implementação de MixColumns e AddRoundKey.
- Implementação das transformações inversas: InvSubBytes, InvShiftRows e InvMixColumns (necessárias à decriptação nos modos ECB, CBC e PCBC).
- Testes unitários com os valores intermediários da FIPS-197: Apêndice B (cifragem) e Apêndice C.1 (cifragem inversa).
- Apresentação da microarquitetura ao verificador parceiro.

Entregável: documento de microarquitetura v1.0 (docs/architecture/), RTL de todas as transformações de rodada (diretas e inversas) e testes unitários.

Critério de aceite: microarquitetura aprovada pelo instrutor na defesa curta; transformações conferem com os valores de referência; lint sem erros.

---

### Semana 4 — Expansão de chave e datapath AES-128 (entrega 13/11)

Atividades

- Implementação de minisoc_aes_key_exp: expansão da chave AES-128 (11 round keys), pré-computada ou on-the-fly, com a escolha justificada (impacto em área e na decriptação, que consome as round keys em ordem inversa).
- Implementação de minisoc_aes_dp: cifra e cifra inversa de um bloco de 128 bits, com a interface de controle definida na microarquitetura (por exemplo, start/done).
- Testbench com os vetores da FIPS-197, nos dois sentidos.

Vetores de referência:

```
Apêndice C.1
  key : 000102030405060708090a0b0c0d0e0f
  pt  : 00112233445566778899aabbccddeeff
  ct  : 69c4e0d86a7b0430d8cdb78070b4c55a

Apêndice B
  key : 2b7e151628aed2a6abf7158809cf4f3c
  pt  : 3243f6a8885a308d313198a2e0370734
  ct  : 3925841d02dc09fbdc118597196a0b32
```

Entregável: RTL de minisoc_aes_key_exp e minisoc_aes_dp e testbench com os vetores do padrão.

Critério de aceite: cifragem e decriptação conferem com os vetores de referência; lint sem erros.

---

### Semana 5 — SPI front-end e PLL mock (entrega 20/11)

Atividades

- Implementação de minisoc_spi (seção 5): SPI Mode 0 (MOSI amostrado na borda de subida e MISO atualizado na borda de descida de spi_sclk), MSB-first, frame de 40 bits (RWb, ADDR[5:0], RSV, DATA[31:0]). Escrita em uma transação; leitura em duas, em que a primeira seleciona o endereço e a segunda desloca o valor lido (endereço NOP 0x3F na fase de retorno).
- Recepção serial no domínio de spi_sclk e banco de registradores no domínio always-on clk, com o evento de frame completo transportado por sincronização de toggle.
- Banco de registradores conforme a seção 6: KEY0–KEY3, IV0–IV3, COUNTER_HI/COUNTER_LO, NUM_BLOCKS, AES_CONTROL (START write-one-pulse), AES_STATUS, VERSION, SYSTEM_CONTROL e SYSTEM_STATUS.
- Implementação de minisoc_pll_mock (seção 4.1): referência de 2 GHz, enable e PLL_DIV_SEL (/1, /2, /4, /8); locked em 0 e clock de sistema bloqueado enquanto desabilitado; locked após um número pseudoaleatório de ciclos de clk depois do enable. É um modelo de integração, não uma macro de implementação.
- Testbench dirigido: escrita e leitura de todos os registradores via SPI e habilitação do PLL até PLL_LOCKED = 1 (passos 8 e 9 do modelo de programação, seção 9).

Entregável: RTL de minisoc_spi e minisoc_pll_mock, testbench e relatório de lint.

Critério de aceite: todos os registradores R/W escritos e lidos via SPI; registradores R não alterados por escrita; PLL travando nos quatro divisores; lint sem erros e com avisos justificados.

---

### Semana 6 — AES engine e memória compartilhada (entrega 27/11)

Atividades

- Implementação de minisoc_memory (seção 7): 1024 × 32 bits, single-port síncrona, sem reset, com ownership definido por MEM_SEL_AES (endereço, dado, write-enable e clock vêm da interface MEMORY DATA ou do AES engine).
- Implementação de minisoc_aes_top (seção 8): no START válido, captura KEY, IV, COUNTER, MODE, DECRYPT e NUM_BLOCKS; para cada bloco, lê quatro palavras, processa o bloco e o escreve in-place; atualiza BUSY, DONE (sticky até um novo START aceito), ERROR e BLOCKS_DONE.
- Modos ECB, CBC e CTR, em cifragem e decriptação. Os modos PCBC, CFB e OFB ficam para a Semana 10; na v1.0 eles constam como limitação conhecida no relatório e são comunicados ao verificador parceiro.
- Detecção de configuração inválida (NUM_BLOCKS fora de 1..256 ou MODE reservado), com ERROR e encerramento sem processamento.
- Testbench de bloco com a memória: operações com 1, 2 e 256 blocos em cada modo implementado, comparadas com um modelo de referência em software (por exemplo, um script em Python que gera os vetores esperados).

Entregável: RTL de minisoc_memory e minisoc_aes_top, testbench de bloco e vetores gerados pelo modelo de referência.

Critério de aceite: ECB, CBC e CTR conferem com o modelo de referência nos dois sentidos; ERROR sinalizado nas configurações inválidas; lint sem erros.

---

### Semana 7 — Integração do top-level e RTL v1.0 (entrega 04/12)

Atividades

- Implementação de minisoc_top: conexão dos quatro blocos e exposição exata das interfaces de topo CLK, RESET, SPI e MEMORY DATA (seção 3), com os mesmos nomes de sinais.
- Sequência de reset: domínio do sistema mantido em reset até o clock ser liberado pelo PLL e transcorrerem ciclos suficientes (seção 4.2).
- Teste de ponta a ponta seguindo os 14 passos do modelo de programação (seção 9).
- Análise de CDC: spi_sclk × clk, clk × sys_clk (comando e status) e mem_clk × sys_clk na troca de ownership da memória.
- Correção dos problemas encontrados.
- Entrega do RTL v1.0 ao verificador parceiro.

Entregável: top-level integrado, teste de ponta a ponta, relatórios de lint e CDC e tag rtl-v1.0.

Critério de aceite: fluxo completo (memória → configuração → PLL → START → DONE → leitura do resultado) funcionando em simulação; interfaces de topo idênticas às do Block Guide; nenhuma violação de CDC sem justificativa. O RTL v1.0 passa a ser o baseline das fases seguintes.

---

### Semana 8 — Síntese inicial (entrega 11/12)

Atividades

- Escrita das restrições de timing (SDC): clk, sys_clk (gerado pelo PLL), spi_sclk e mem_clk, com os grupos assíncronos declarados; entradas, saídas e caminhos de sincronização. As frequências-alvo são definidas pelo instrutor.
- Tratamento de minisoc_pll_mock e minisoc_memory como caixas-pretas ou macros, conforme orientação do instrutor.
- Síntese lógica do RTL v1.0 com a biblioteca de células do PDK fornecido.
- Análise dos relatórios de área, timing e potência e identificação de caminhos críticos e de construções não sintetizáveis ou ineficientes.

Entregável: scripts de síntese, arquivo SDC, netlist e relatório de baseline (área, timing e potência estimada).

Critério de aceite: síntese sem erros, sem latches não intencionais e com timing atendido nas frequências-alvo, ou com o plano de correção documentado.

---

### Semana 9 — Verificação formal de equivalência (entrega 18/12)

Atividades

- Preparação do fluxo no Formality: RTL (referência), netlist sintetizada (implementação), bibliotecas do PDK e arquivo de guidance (SVF) gerado pela síntese.
- Tratamento do PLL mock e da memória como caixas-pretas, de forma consistente com a síntese.
- Execução das etapas de match e verify e depuração dos pontos não casados, não verificados ou não equivalentes.
- Exercício de diagnóstico: inserção intencional de uma alteração no RTL ou na netlist para observar como o Formality aponta a diferença.

Entregável: scripts do Formality e relatório de equivalência entre o RTL v1.0 e a netlist do baseline, com o registro das não equivalências e de suas causas.

Critério de aceite: fluxo executável por script; equivalência confirmada, sem pontos não casados ou não verificados sem justificativa.

---

> Recesso de fim de ano: 21/12/2026 a 03/01/2027, sem entregas. O verificador parceiro segue com o RTL v1.0; issues abertas no período são tratadas na Semana 10.
> 

---

### Semana 10 — Fechamento funcional e RTL v1.1 (entrega 08/01)

Atividades

- Implementação dos modos PCBC, CFB e OFB, completando os seis modos da seção 8.2.
- Correção dos defeitos reportados pelo verificador parceiro até o momento.
- Nova síntese e nova verificação de equivalência sobre o RTL corrigido.
- Entrega do RTL v1.1 ao verificador parceiro.

Entregável: tag rtl-v1.1, testes dos seis modos, netlist atualizada e relatório de equivalência.

Critério de aceite: os seis modos conferem com o modelo de referência; issues do verificador classificadas e tratadas; equivalência entre o RTL v1.1 e a sua netlist confirmada.

---

### Semana 11 — Arquitetura de energia e UPF (entrega 15/01)

Atividades

- Análise do perfil de atividade: quais blocos ficam ociosos e em quais situações (por exemplo, o AES engine fora de uma operação ou com o PLL desabilitado).
- Definição dos modos de operação (por exemplo, ativo, ocioso e desligado), dos domínios de potência e da tabela de estados de potência, identificando os blocos sempre ligados (por exemplo, SPI, banco de registradores e PLL).
- Definição das estratégias de isolamento e retenção e da sequência de desligamento e religamento.
- Escrita do UPF: domínios, redes de alimentação, chaves de potência, isolamento e retenção.
- Verificação estática do UPF e simulação power-aware de um desligamento e religamento do domínio do AES.

Entregável: documento curto de arquitetura de energia (domínios, modos, tabela de estados e sequências), arquivo UPF, relatório de verificação estática e relatório de simulação power-aware, apresentados em uma defesa curta.

Critério de aceite: arquitetura de energia aprovada pelo instrutor; UPF sem erros na verificação estática; simulação mostrando corrupção dos sinais do domínio desligado e isolamento correto.

---

### Semana 12 — Técnicas de baixo consumo e RTL v2.0 (entrega 22/01)

Atividades

- Controlador de energia e sequência de power gating (isolar, salvar, desligar, religar, restaurar, liberar), integrado ao banco de registradores.
- Clock gating: identificação de oportunidades arquiteturais (por exemplo, sys_clk do AES engine quando ocioso) e uso de células ICG.
- Outras técnicas, conforme a arquitetura aprovada (isolamento de operandos, redução de atividade de chaveamento).
- Atualização do testbench para exercitar as transições entre modos de energia.
- Entrega do RTL v2.0 ao verificador parceiro para regressão.

Entregável: tag rtl-v2.0 (low power), testes atualizados, relatório de simulação power-aware e relatório descrevendo cada técnica aplicada e onde ela foi aplicada.

Critério de aceite: funcionalidade da v1.1 preservada; transições entre modos de energia funcionando em simulação power-aware, com isolamento e retenção corretos.

---

### Semana 13 — Síntese low power e encerramento (entrega 29/01)

Atividades

- Síntese do RTL v2.0 com o UPF, incluindo a inserção automática de clock gating.
- Comparação com o baseline da Semana 8: área, timing e potência, por modo de operação.
- Verificação de equivalência no Formality entre o RTL v2.0 e a netlist low power, considerando o UPF e o clock gating inserido.
- Consolidação da documentação, dos defeitos reportados pelo verificador parceiro e do repositório.
- Apresentação final.

Entregável: relatório comparativo baseline × low power, relatório de equivalência, release final no repositório e apresentação final.

Critério de aceite: síntese com UPF sem erros; ganhos e custos quantificados e justificados; projeto reproduzível a partir do repositório (simulação, síntese, formal e UPF executáveis pelos scripts); apresentação realizada. O artigo técnico, quando houver, pode ser concluído após o encerramento.

---

## Resumo dos entregáveis

| Semana | Data | Entregável | Marco |
| --- | --- | --- | --- |
| 1 | concluída | Ambiente configurado + backlog inicial + relatório de estudo | Kick-off |
| 2 | 30/10 | SubBytes, ShiftRows e S-box + testbench | Desafio de retomada |
| 3 | 06/11 | Microarquitetura v1.0 + transformações de rodada (diretas e inversas) | Defesa curta; apresentação ao verificador parceiro |
| 4 | 13/11 | Expansão de chave + datapath AES-128 |  |
| 5 | 20/11 | SPI front-end + banco de registradores + PLL mock |  |
| 6 | 27/11 | AES engine (ECB, CBC, CTR) + memória compartilhada |  |
| 7 | 04/12 | Top-level integrado + teste de ponta a ponta + CDC | RTL v1.0; entrega ao verificador parceiro |
| 8 | 11/12 | Síntese inicial + relatório de baseline | Baseline |
| 9 | 18/12 | Scripts e relatório de equivalência (Formality) |  |
| — | 21/12 a 03/01 | Recesso |  |
| 10 | 08/01 | Modos PCBC, CFB e OFB + correções + nova equivalência | RTL v1.1; entrega ao verificador parceiro |
| 11 | 15/01 | Arquitetura de energia + UPF + simulação power-aware | Defesa da arquitetura de energia |
| 12 | 22/01 | Power gating + clock gating | RTL v2.0; entrega ao verificador parceiro |
| 13 | 29/01 | Síntese low power + comparação + equivalência + release final | Apresentação final |

---

## Estrutura sugerida do repositório

A organização de rtl/ segue a seção 10 do Block Guide.

```
.
├── README.md
├── docs/
│   ├── spec/            # Block Guide MiniSoC AES (fornecido)
│   ├── architecture/    # microarquitetura e arquitetura de energia
│   └── reports/         # relatórios semanais
├── rtl/
│   ├── minisoc_aes/     # minisoc_aes_top, minisoc_aes_dp, minisoc_aes_key_exp e submódulos
│   ├── minisoc_mem/     # minisoc_memory
│   ├── minisoc_pll/     # minisoc_pll_mock (modelo de integração)
│   ├── minisoc_spi/     # minisoc_spi
│   └── minisoc_top.sv
├── tb/                  # testbenches e modelo de referência
├── formal/              # scripts e relatórios do Formality
├── syn/                 # SDC, scripts e relatórios de síntese
├── upf/                 # arquivos UPF e relatórios
└── scripts/             # automação do fluxo
```

---

## Entregas finais

Ao final do projeto, cada aluno deverá apresentar:

- documento de microarquitetura e documento de arquitetura de energia;
- código RTL (v1.0, v1.1 e v2.0 identificados por tags);
- testbenches, vetores de teste e modelo de referência;
- restrições de timing e scripts de síntese;
- relatórios de síntese (baseline e low power);
- scripts e relatórios de verificação de equivalência;
- arquivo UPF e relatórios de verificação power-aware;
- relatório comparativo das técnicas de baixo consumo;
- histórico dos defeitos reportados pelo verificador parceiro e das correções;
- repositório Git organizado e reproduzível;
- apresentação final;
- artigo preparado para submissão (caso possível).

---

## Interação com a trilha de verificação

Cada aluno da trilha RTL formará uma dupla com um aluno da trilha de Design Verification. O verificador parceiro será responsável por verificar em simulação o IP desenvolvido pelo aluno de RTL, enquanto o aluno de RTL mantém a responsabilidade pelo projeto, pela síntese, pela verificação de equivalência e pelas técnicas de baixo consumo.

As duas trilhas trabalham sobre a mesma especificação, o Block Guide do MiniSoC AES. Na trilha de verificação, cada aluno constrói VIPs para as quatro interfaces de topo (CLK, RESET, SPI e MEMORY DATA), um modelo de referência para o AES e um ambiente que verifica o fluxo fim a fim.

A verificação acontece em duas etapas:

1. RTL de referência. Para não depender do andamento desta trilha, a trilha de verificação desenvolve o seu ambiente sobre o RTL de referência do MiniSoC AES, fornecido pelo instrutor de verificação.
2. RTL do aluno parceiro. Em um segundo momento, o ambiente passa a ser executado sobre o RTL desenvolvido pelo aluno de RTL, para encontrar defeitos tanto no RTL quanto no próprio ambiente de verificação.

Para que o ambiente construído na primeira etapa possa ser reaproveitado na segunda, o top-level desta trilha deve ser idêntico ao do Block Guide: nomes dos sinais, protocolo SPI, mapa de registradores e temporizações.

O mesmo vale para minisoc_pll_mock e minisoc_memory. Cada aluno de RTL escreve as suas versões para os testes iniciais, para não depender da trilha de verificação. Na segunda etapa, elas podem ser substituídas pelas da trilha de verificação, que têm a mesma interface. Diferenças de comportamento entre os dois modelos são registradas como issues, pois indicam defeito no RTL, defeito em um dos modelos ou ambiguidade da especificação.

A interação seguirá quatro pontos de contato:

| Semana | Data | Ponto de contato | O que é compartilhado |
| --- | --- | --- | --- |
| 3 | 06/11 | Apresentação da microarquitetura | Documento de microarquitetura, para alinhar decisões e dúvidas sobre o Block Guide |
| 7 | 04/12 | Primeira entrega do IP | Tag rtl-v1.0 (modos ECB, CBC e CTR), a partir da qual o ambiente passa a ser executado sobre o RTL do aluno parceiro |
| 10 | 08/01 | Segunda entrega do IP | Tag rtl-v1.1, com os seis modos e as correções das issues abertas |
| 12 | 22/01 | Entrega low power | Tag rtl-v2.0, com os modos de energia, para regressão |

Regras da interação:

- O verificador parceiro acessa o IP pela tag entregue, e não pelo estado corrente do repositório.
- Os defeitos encontrados são registrados como issues no repositório do aluno de RTL, com descrição, cenário de reprodução e evidência (log ou forma de onda).
- O aluno de RTL analisa cada issue e a classifica como defeito do RTL, defeito do ambiente de verificação ou ambiguidade da especificação; ambiguidades são levadas ao instrutor.
- As correções são entregues em novas tags e comunicadas ao verificador parceiro.
- O escopo de verificação da trilha de verificação é funcional e não inclui os modos de energia. A regressão sobre a v2.0 confirma que a funcionalidade não foi alterada; os modos de energia são verificados pelo próprio aluno de RTL (simulação power-aware).
- A apresentação final de cada aluno deve incluir o resultado da verificação feita pelo verificador parceiro.
