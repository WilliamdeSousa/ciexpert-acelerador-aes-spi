# ciexpert-acelerador-aes-spi

Acelerador AES com interface SPI e baixo consumo. Este projeto faz parte do Hands-on da Trilha de RTL Design da Residência em Microeletrônica CI Expert.

O sistema de topo tem um datapath AES ([FIPS-197](<docs/reports/semana01/FIPS 197, Advanced Encryption Standard (AES) - nist.fips.197.pdf>)), é configurado e controlado por uma interface SPI, recebe e devolve dados por uma interface de memória e conta com blocos de reset e de geração de clock. O projeto vai do RTL à síntese, passando por verificação formal de equivalência (Formality) e técnicas de baixo consumo descritas em UPF, ao longo de 15 semanas.

![Architecture Diagram](docs/architecture/rsc/architecture.png)

*Figura 1 – Arquitetura-base do sistema de topo.*

As instruções completas do instrutor (objetivos, cronograma, entregáveis e critérios de aceite) estão em [docs/architecture/instrucoes.md](docs/architecture/instrucoes.md).

## Estrutura do repositório

```
.
├── README.md
├── Makefile             # fluxo de simulação, síntese e formal
├── docs/
│   ├── spec/            # especificação funcional (fornecida)
│   ├── architecture/    # arquitetura e arquitetura de energia
│   └── reports/         # relatórios semanais
├── rtl/                 # código RTL
├── models/              # modelos simples do PLL e da memória
├── tb/                  # testbenches
├── formal/              # scripts e relatórios do Formality
├── syn/                 # SDC, scripts e relatórios de síntese
├── upf/                 # arquivos UPF e relatórios
└── scripts/             # automação do fluxo
```

## Uso

Requer as ferramentas da Synopsys (VCS, Verdi, Design Compiler e Formality).

| Comando | Ação |
|---|---|
| `make run` | Compila e simula o testbench |
| `make wave` | Abre as formas de onda no Verdi |
| `make synth` | Executa a síntese lógica no Design Compiler |
| `make formality` | Executa a verificação de equivalência RTL × netlist |
| `make clean` | Remove os arquivos gerados |

## Relatórios semanais

| Semana | Tema |
|---|---|
| [01](docs/reports/semana01/README.md) | Estudo do AES (FIPS-197) e do SPI |
