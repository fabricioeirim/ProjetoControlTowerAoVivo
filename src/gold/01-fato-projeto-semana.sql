-- gold.fato_projeto_semana: a evolução de cada projeto, semana a semana (toda sexta).
-- O histórico do avanço vem do status semanal: as ferramentas só guardam o % de hoje.
-- Regra do pipeline: janela e agregação em CTEs separados.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo EXPECT (pv >= 0) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_o_orcamento EXPECT (ev <= orcamento) ON VIOLATION FAIL UPDATE
)
COMMENT 'Uma linha por projeto e semana (sexta-feira), da semana do início até 16/10/2026: valor planejado (pv), valor agregado (ev, pelo % do status semanal), custo real acumulado (ac), SPI, CPI, EAC, o farol publicado pelo gerente e as horas disponíveis, apontadas e ociosas da semana.'
AS
WITH

-- 1. todas as sextas de cada projeto, da semana do início até hoje
semanas AS (
  SELECT
    projeto_id,
    orcamento_custo AS orcamento,
    explode(sequence(
      date_add(to_date(date_trunc('WEEK', data_inicio)), 4),
      DATE'2026-10-16',
      INTERVAL 1 WEEK
    )) AS semana
  FROM projetos
),

-- 2. PV: quanto do trabalho (em horas) o baseline mandava ter feito até aquela sexta
fracao_por_tarefa AS (
  SELECT
    s.projeto_id,
    s.semana,
    t.horas,
    greatest(0, least(1, coalesce(
      try_divide(datediff(s.semana, t.inicio_baseline), datediff(t.fim_baseline, t.inicio_baseline)),
      CASE WHEN s.semana >= t.fim_baseline THEN 1 ELSE 0 END    -- tarefa de duração zero
    ))) AS fracao_decorrida
  FROM semanas s
  JOIN tarefas t ON t.projeto_id = s.projeto_id
),
pv_semana AS (
  SELECT
    projeto_id,
    semana,
    try_divide(sum(horas * fracao_decorrida), sum(horas)) AS fracao_planejada
  FROM fracao_por_tarefa
  GROUP BY projeto_id, semana
),

-- 3. o status de cada sexta; semana sem status (projeto concluído) repete o último
status_da_semana AS (
  SELECT
    s.projeto_id,
    s.semana,
    last_value(st.pct_concluido, true) OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS pct_concluido,
    last_value(st.farol, true)         OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS farol_do_gerente
  FROM semanas s
  LEFT JOIN status_semanal st
    ON st.projeto_id = s.projeto_id AND st.data_status = s.semana
),

-- 4. AC: todo custo lançado até aquela sexta (acumulado)
ac_semana AS (
  SELECT
    s.projeto_id,
    s.semana,
    coalesce(sum(c.valor), 0) AS ac
  FROM semanas s
  LEFT JOIN custos c
    ON c.projeto_id = s.projeto_id AND c.data <= s.semana
  GROUP BY s.projeto_id, s.semana
),

-- 5. timesheet da semana
horas_semana AS (
  SELECT
    projeto_id,
    semana,
    sum(horas_disponiveis) AS horas_disponiveis,
    sum(horas_apontadas)   AS horas_apontadas
  FROM apontamentos
  GROUP BY projeto_id, semana
),

-- 6. junta tudo
base AS (
  SELECT
    s.projeto_id,
    s.semana,
    s.orcamento,
    s.orcamento * coalesce(pv.fracao_planejada, 0)   AS pv,
    s.orcamento * coalesce(st.pct_concluido, 0) / 100 AS ev,
    ac.ac,
    st.pct_concluido,
    st.farol_do_gerente,
    h.horas_disponiveis,
    h.horas_apontadas
  FROM semanas s
  LEFT JOIN pv_semana        pv ON pv.projeto_id = s.projeto_id AND pv.semana = s.semana
  LEFT JOIN status_da_semana st ON st.projeto_id = s.projeto_id AND st.semana = s.semana
  LEFT JOIN ac_semana        ac ON ac.projeto_id = s.projeto_id AND ac.semana = s.semana
  LEFT JOIN horas_semana     h  ON h.projeto_id  = s.projeto_id AND h.semana  = s.semana
),

kpis AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi
  FROM base
)

SELECT
  projeto_id,
  semana,
  orcamento,
  pct_concluido,
  CAST(pv AS DECIMAL(14, 2))  AS pv,
  CAST(ev AS DECIMAL(14, 2))  AS ev,
  CAST(ac AS DECIMAL(14, 2))  AS ac,
  spi,
  cpi,
  CAST(try_divide(orcamento, cpi) AS DECIMAL(14, 2)) AS eac,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  horas_disponiveis - horas_apontadas AS horas_ociosas
FROM kpis;
