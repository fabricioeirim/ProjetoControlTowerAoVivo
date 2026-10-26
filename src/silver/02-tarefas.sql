-- silver.tarefas: AS TRÊS FERRAMENTAS VIRAM UMA.
-- Cada ferramenta ganha uma visão temporária com AS MESMAS colunas:
--   projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
--   inicio_baseline, fim_baseline, inicio_real, fim_real,
--   pct_como_veio, horas, status_na_ferramenta
-- e no fim um UNION ALL junta tudo numa tabela só.


-- ============================================================
-- 1. Excel (20 planilhas, tudo texto)
-- ============================================================
CREATE TEMPORARY VIEW tarefas_excel AS
SELECT
  -- de-para: codigo_ferramenta = nome do arquivo. Se não casar (código vazio,
  -- ou o arquivo chegou sem acento), o PRJ-xxx está no nome do arquivo.
  coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
  'excel'                                  AS ferramenta,
  CAST(e.id AS STRING)                     AS id_na_ferramenta,
  e.fase,
  e.tarefa,
  e.responsavel,

  -- sujeira 4: data em texto (dd/MM/yyyy) ou número de série do Excel (dias desde 30/12/1899)
  CASE WHEN e.inicio_previsto LIKE '%/%' THEN to_date(e.inicio_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(e.inicio_previsto AS DOUBLE) AS INT)) END AS inicio_baseline,
  CASE WHEN e.termino_previsto LIKE '%/%' THEN to_date(e.termino_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(e.termino_previsto AS DOUBLE) AS INT)) END AS fim_baseline,
  CASE WHEN e.inicio_real LIKE '%/%' THEN to_date(e.inicio_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(e.inicio_real AS DOUBLE) AS INT)) END AS inicio_real,
  CASE WHEN e.termino_real LIKE '%/%' THEN to_date(e.termino_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(e.termino_real AS DOUBLE) AS INT)) END AS fim_real,

  -- sujeira 5: '45%' e '10,5%' (percentual) ou 0.45 (fração, × 100)
  CASE WHEN contains(e.pct_concluido, '%')
       THEN CAST(replace(replace(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(e.pct_concluido AS DOUBLE) * 100
  END AS pct_como_veio,

  -- sujeira 7: horas em '40h'
  CAST(replace(e.horas_previstas, 'h', '') AS DOUBLE) AS horas,

  CAST(NULL AS STRING) AS status_na_ferramenta
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN projetos p
  ON p.ferramenta = 'excel' AND p.codigo_ferramenta = e.arquivo
-- sujeira 6: a linha de TOTAL do fim da planilha não é tarefa
WHERE coalesce(e.tarefa, '') <> 'TOTAL';


-- ============================================================
-- 2. ClickUp (25 listas, JSON da API)
-- ============================================================
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  -- de-para: codigo_ferramenta = list_id; se o código faltar, casa pelo nome da lista
  coalesce(p_codigo.projeto_id, p_nome.projeto_id) AS projeto_id,
  'clickup'                                AS ferramenta,
  c.id                                     AS id_na_ferramenta,
  filter(c.custom_fields, f -> f.name = 'Fase')[0].value AS fase,
  c.name                                   AS tarefa,
  c.assignees[0].username                  AS responsavel,

  -- sujeira 8: datas em milissegundos; baseline e % dentro de custom_fields
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))) AS inicio_baseline,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT)))    AS fim_baseline,
  to_date(timestamp_millis(CAST(c.start_date AS BIGINT))) AS inicio_real,
  to_date(timestamp_millis(CAST(c.date_done  AS BIGINT))) AS fim_real,
  CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE) AS pct_como_veio,

  c.time_estimate / 3600000.0              AS horas,   -- ms → horas

  -- sujeira 9: o status escrito de 12 jeitos vira 3
  CASE
    WHEN lower(c.status.status) IN ('done', 'closed', 'concluído')    THEN 'concluida'
    WHEN lower(c.status.status) IN ('to do', 'a fazer', 'backlog')    THEN 'a_fazer'
    WHEN lower(c.status.status) IN ('in progress', 'doing', 'em andamento', 'review') THEN 'em_andamento'
  END AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos p_codigo
  ON p_codigo.ferramenta = 'clickup' AND p_codigo.codigo_ferramenta = c.list_id
LEFT JOIN projetos p_nome
  ON p_nome.ferramenta = 'clickup' AND p_nome.codigo_ferramenta IS NULL AND p_nome.nome_projeto = c.list_name;


-- ============================================================
-- 3. MS Project (15 XML)
-- ============================================================
-- Primeiro a janela, em TODAS as linhas: a fase é a tarefa-resumo de nível 1
-- mais recente antes da tarefa (as fases são justamente as linhas Summary = 1).
CREATE TEMPORARY VIEW msproject_com_fase AS
SELECT
  m.*,
  last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
    OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase   -- sujeira 11
FROM lakehouse_vertice.bronze.msproject_tarefas m;

CREATE TEMPORARY VIEW tarefas_msproject AS
SELECT
  p.projeto_id,                            -- de-para: codigo_ferramenta = arquivo
  'msproject'                              AS ferramenta,
  CAST(m.UID AS STRING)                    AS id_na_ferramenta,
  m.fase,
  m.Name                                   AS tarefa,
  CAST(NULL AS STRING)                     AS responsavel,
  to_date(m.Baseline.Start)                AS inicio_baseline,
  to_date(m.Baseline.Finish)               AS fim_baseline,
  to_date(m.ActualStart)                   AS inicio_real,
  to_date(m.ActualFinish)                  AS fim_real,
  CAST(m.PercentComplete AS DOUBLE)        AS pct_como_veio,
  CAST(regexp_extract(m.Work, 'PT([0-9]+)H', 1) AS DOUBLE) AS horas,   -- sujeira 12: 'PT40H0M0S'
  CAST(NULL AS STRING)                     AS status_na_ferramenta
FROM msproject_com_fase m
LEFT JOIN projetos p
  ON p.ferramenta = 'msproject' AND p.codigo_ferramenta = m.arquivo
-- sujeira 10: as tarefas-resumo somam as horas de baixo; contá-las dobraria as horas
WHERE m.Summary = 0;


-- ============================================================
-- 4. As três numa tabela só
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto EXPECT (projeto_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100) ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas EXPECT (horas > 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Todas as tarefas dos cronogramas num modelo só: as 20 planilhas Excel, as 25 listas do ClickUp e os 15 projetos do MS Project. Uma linha por tarefa (sem linhas de TOTAL nem tarefas-resumo), com baseline, datas reais, % concluído de hoje (16/10/2026) e horas previstas.'
AS
WITH todas AS (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  pct_como_veio,
  least(pct_como_veio, 100)  AS pct_concluido,           -- sujeira 5: 11 vieram acima de 100
  pct_como_veio > 100        AS pct_veio_acima_de_100,
  horas,
  status_na_ferramenta
FROM todas;
