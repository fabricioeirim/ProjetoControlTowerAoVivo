-- gold.projeto_situacao_atual e gold.utilizacao_pessoa_semana


-- A fotografia de hoje (16/10/2026): uma linha por projeto, com o cadastro
-- e os KPIs calculados sobre as tarefas das ferramentas (o % de hoje).
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual (
  CONSTRAINT tem_projeto EXPECT (projeto_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Situação de cada um dos 60 projetos em 16/10/2026: cadastro (cliente, segmento, tipo, ferramenta, gerente, contrato, orçamento, prazo) e KPIs das tarefas de hoje: PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem projetada, atraso e término projetados, situação (crítico < 0,8, atenção < 0,9), farol do gerente, farol calculado e melancia (farol verde com SPI < 0,9).'
AS
WITH

-- PV e EV de hoje, pelas tarefas (pesadas pelas horas)
tarefas_hoje AS (
  SELECT
    projeto_id,
    horas,
    pct_concluido,
    greatest(0, least(1, coalesce(
      try_divide(datediff(DATE'2026-10-16', inicio_baseline), datediff(fim_baseline, inicio_baseline)),
      CASE WHEN DATE'2026-10-16' >= fim_baseline THEN 1 ELSE 0 END
    ))) AS fracao_decorrida
  FROM tarefas
),
avanco AS (
  SELECT
    projeto_id,
    try_divide(sum(horas * fracao_decorrida), sum(horas))     AS fracao_planejada,
    try_divide(sum(horas * pct_concluido / 100), sum(horas))  AS fracao_agregada
  FROM tarefas_hoje
  GROUP BY projeto_id
),

-- AC: tudo o que foi gasto até hoje
custo_real AS (
  SELECT projeto_id, sum(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),

-- o farol do último status publicado até hoje
ultimo_status AS (
  SELECT projeto_id, farol AS farol_do_gerente
  FROM (
    SELECT
      projeto_id,
      farol,
      row_number() OVER (PARTITION BY projeto_id ORDER BY data_status DESC) AS ordem
    FROM status_semanal
    WHERE data_status <= DATE'2026-10-16'
  )
  WHERE ordem = 1
),

kpis AS (
  SELECT
    p.*,
    datediff(p.data_fim_baseline, p.data_inicio)           AS duracao_baseline_dias,
    p.orcamento_custo * a.fracao_planejada                 AS pv,
    p.orcamento_custo * a.fracao_agregada                  AS ev,
    coalesce(c.ac, 0)                                      AS ac,
    round(try_divide(a.fracao_agregada, a.fracao_planejada), 4)                         AS spi,
    round(try_divide(p.orcamento_custo * a.fracao_agregada, coalesce(c.ac, 0)), 4)      AS cpi,
    s.farol_do_gerente
  FROM projetos p
  LEFT JOIN avanco        a ON a.projeto_id = p.projeto_id
  LEFT JOIN custo_real    c ON c.projeto_id = p.projeto_id
  LEFT JOIN ultimo_status s ON s.projeto_id = p.projeto_id
),

projecoes AS (
  SELECT
    *,
    try_divide(orcamento_custo, cpi)                       AS eac,
    try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias AS atraso_dias
  FROM kpis
)

SELECT
  concat(projeto_id, ' · ', nome_projeto)                  AS projeto,
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento_custo                                          AS orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,

  CAST(pv AS DECIMAL(14, 2))                               AS pv,
  CAST(ev AS DECIMAL(14, 2))                               AS ev,
  CAST(ac AS DECIMAL(14, 2))                               AS ac,
  spi,
  cpi,
  CAST(eac AS DECIMAL(14, 2))                              AS eac,
  CAST(greatest(eac - orcamento_custo, 0) AS DECIMAL(14, 2)) AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4) AS margem_projetada,
  CAST(round(atraso_dias) AS INT)                          AS atraso_projetado_dias,
  date_add(data_inicio, CAST(round(duracao_baseline_dias + atraso_dias) AS INT)) AS termino_projetado,

  CASE
    WHEN status <> 'em_andamento'     THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8       THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9       THEN 'atenção'
    ELSE 'ok'
  END                                                      AS situacao,

  farol_do_gerente,
  -- regra do manual da Vértice
  CASE
    WHEN spi >= 0.95 THEN 'verde'
    WHEN spi >= 0.90 THEN 'amarelo'
    ELSE 'vermelho'
  END                                                      AS farol_calculado,
  -- verde por fora, vermelho por dentro
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM projecoes;


-- Uso do timesheet por pessoa, projeto e semana:
-- "tenho gente parada enquanto outro projeto pede gente?"
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Uma linha por pessoa, projeto e semana (sexta): nome, papel, senioridade, horas disponíveis, apontadas e ociosas, utilização (apontadas ÷ disponíveis), custo ocioso (horas ociosas × custo/hora) e o SPI do projeto naquela semana.'
AS
SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  a.horas_disponiveis - a.horas_apontadas                            AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)       AS utilizacao,
  CAST((a.horas_disponiveis - a.horas_apontadas) * c.custo_hora AS DECIMAL(14, 2)) AS custo_ocioso,
  f.spi                                                              AS spi_do_projeto
FROM apontamentos a
LEFT JOIN colaboradores c
  ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id AND f.semana = a.semana;
