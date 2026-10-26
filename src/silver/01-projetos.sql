-- silver.projetos: o cadastro do PMO.
-- É o de-para da integração: diz em qual ferramenta cada projeto é controlado
-- e qual o código dele lá dentro (arquivo do Excel, lista do ClickUp, XML do Project).

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida EXPECT (data_inicio IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos da Vértice (um por linha): cliente, segmento, tipo, valor do contrato, orçamento de custo, datas baseline, gerente e a ferramenta onde o cronograma vive (excel, clickup ou msproject), com o código do projeto nessa ferramenta.'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,

  -- sujeira 2: a ferramenta veio escrita de 8 jeitos ('Planilha', 'Clickup', 'Project'...)
  CASE
    WHEN lower(ferramenta) LIKE '%click%'                                   THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
    WHEN lower(ferramenta) LIKE '%project%'                                 THEN 'msproject'
  END AS ferramenta,
  ferramenta AS ferramenta_como_veio,

  -- sujeira 3: código vazio vira NULL (a silver.tarefas acha o projeto por outro caminho)
  nullif(trim(codigo_ferramenta), '') AS codigo_ferramenta,

  CAST(valor_contrato  AS DECIMAL(14, 2)) AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(14, 2)) AS orcamento_custo,

  -- sujeira 1: data_inicio em yyyy-MM-dd ou dd/MM/yyyy
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'),
           try_to_date(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
  to_date(data_fim_baseline)                       AS data_fim_baseline,

  status,
  gerente_projeto
FROM lakehouse_vertice.bronze.projetos;
