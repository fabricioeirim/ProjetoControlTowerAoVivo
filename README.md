# Projeto Control Tower ao Vivo

<p align="center">
  <img src="https://img.shields.io/badge/Databricks-Lakehouse-ff7f50?style=for-the-badge&logo=databricks" alt="Databricks" />
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python" alt="Python 3.12" />
  <img src="https://img.shields.io/badge/Analytics-Executive-Dashboard-0A84FF?style=for-the-badge" alt="Analytics" />
  <img src="https://img.shields.io/badge/AI-Status-Classification-6A5ACD?style=for-the-badge" alt="AI" />
</p>

Um case de engenharia de dados, analytics e governança operacional para monitoramento de portfólio de projetos em tempo real.

## Visão geral

Este projeto simula um cenário real de gestão de projetos em empresas de consultoria, tecnologia e serviços, onde os dados estão espalhados em múltiplas ferramentas: Excel, ClickUp, Microsoft Project e outros sistemas de registro operacional.

A proposta foi construir uma solução de data platform para transformar esse cenário caótico em uma visão executiva do portfólio, permitindo responder perguntas críticas da liderança:

- Quais projetos estão atrasados?
- De quais clientes?
- Qual é o impacto financeiro desse atraso?
- Existe sobreposição de alocação de pessoas?
- O que pode dar errado no próximo mês?

## Problema de negócio

A grande maioria das empresas não consegue acompanhar com clareza o status real dos seus projetos porque os dados ficam fragmentados em planilhas, listas de tarefas e sistemas de gestão.

Sem uma visão integrada:
- o acompanhamento fica manual e inconsistente,
- o risco operacional cresce,
- a margem do projeto se reduz,
- e a tomada de decisão acontece sem dados confiáveis.

## Solução

O Projeto Control Tower ao Vivo foi pensado para consolidar esses dados em uma arquitetura moderna de dados, com foco em integração, limpeza, modelagem e analytics.

A solução inclui:
- ingestão de dados multifuente,
- padronização e qualidade de dados,
- modelagem em camadas bronze, silver e gold,
- cálculo de KPIs de desempenho e risco,
- IA para classificação de status e extração de contexto,
- dashboard analítico para monitoramento executivo.

## Arquitetura

A arquitetura foi organizada em camadas:

- Bronze: dados brutos e origem
- Silver: limpeza, padronização e integração
- Gold: modelo analítico pronto para consumo
- IA: classificação e extração de contexto operacional
- Dashboard: visualização dos principais indicadores

## Stack

- Databricks
- Unity Catalog / Lakehouse
- Spark SQL
- Python
- Delta Lake
- Pipelines declarativas
- Jobs e Bundles do Databricks
- IA nativa do Databricks

## KPIs e indicadores

O projeto calcula e acompanha indicadores como:

- SPI
- CPI
- EAC
- Estouro previsto
- Margem projetada
- Atraso projetado
- Farol de risco por projeto
- Melancia (projeto verde em risco)

## Objetivo

Transformar dados operacionais dispersos em inteligência executiva, com foco em:

- previsibilidade,
- governança,
- desempenho,
- e tomada de decisão baseada em evidência.

## Estrutura do projeto

```text
.
├── .databricks/
├── fixtures/
├── resources/
├── scripts/
├── src/
├── tests/
├── .gitignore
├── AGENTS.md
├── CLAUDE.md
├── databricks.yml
├── pyproject.toml
├── README.md
├── script.py
├── script.txt
└── .vscode/
```

## Como executar

### 1. Criar ambiente virtual

```bash
python -m venv .venv
source .venv/bin/activate
```

No Windows:

```powershell
.venv\Scripts\activate
```

### 2. Instalar dependências

```bash
pip install -r requirements.txt
```

ou com uv:

```bash
uv sync --dev
```

### 3. Deploy do bundle no Databricks

```bash
databricks configure
databricks bundle deploy --target dev
```

## Status

Em desenvolvimento, com foco em entrega de um case realista de engenharia de dados aplicado ao contexto de gestão de portfólio e tomada de decisão.

## Autor

Fabricio Eirim

## Conecte-se

- GitHub: https://github.com/fabricioeirim
- LinkedIn: https://www.linkedin.com/in/fabricioeirim

---

Se quiser mostrar esse projeto em um portfólio, essa estrutura funciona muito bem para comunicação técnica e estratégica.