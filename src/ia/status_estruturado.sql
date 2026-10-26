-- gold.status_estruturado: o texto livre do status semanal vira coluna.
-- sql_task do job vertice_farol (depois do medalhão, em paralelo com os testes).
--
-- Três métodos, do mais barato ao mais caro:
--   regra         status vazio ou "sem bloqueios": não precisa ler nada
--   ia            status com bloqueio dos últimos 90 dias: ai_classify + ai_extract (~5 s por texto)
--   palavra_chave status com bloqueio mais antigos: RLIKE no texto
-- A tabela ACUMULA: o MERGE só insere o que ainda não foi classificado,
-- então a IA nunca é refeita para um status que já passou por ela.


-- a. a tabela (criada uma vez, nunca recriada)
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id       STRING    COMMENT 'Projeto (PRJ-xxx) do status',
  data_status      DATE      COMMENT 'Sexta-feira do status semanal',
  farol            STRING    COMMENT 'Farol publicado pelo gerente: verde, amarelo ou vermelho',
  causa_bloqueio   STRING    COMMENT 'Causa do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado (status vazio) ou outro',
  bloqueio         STRING    COMMENT 'O bloqueio em uma frase, extraído pela IA (só no método ia)',
  quem_destrava    STRING    COMMENT 'Quem precisa agir para destravar, extraído pela IA (só no método ia, quando o texto diz)',
  dias_impacto     DOUBLE    COMMENT 'Dias de impacto no cronograma declarados no texto (1 semana = 7)',
  metodo           STRING    COMMENT 'Como a causa foi obtida: regra, ia ou palavra_chave',
  texto_status     STRING    COMMENT 'O texto livre original do status',
  _classificado_em TIMESTAMP COMMENT 'Quando a linha foi classificada (carimbo da execução)'
)
COMMENT 'Status semanais estruturados: causa do bloqueio, o bloqueio, quem destrava e os dias de impacto declarados. IA (ai_classify + ai_extract) só nos status com bloqueio dos últimos 90 dias. Uma linha por projeto e sexta.';


-- b. só os status novos, cada um pelo seu método
MERGE INTO lakehouse_vertice.gold.status_estruturado AS destino
USING (
  WITH

  novos AS (
    SELECT s.*
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status
  ),

  com_metodo AS (
    SELECT
      *,
      CASE
        WHEN status_vazio
          OR lower(texto_status) LIKE '%bloqueios: nenhum%'
          OR lower(texto_status) LIKE '%sem bloqueios%'
          OR lower(texto_status) LIKE '%nada relevante%'  THEN 'regra'
        WHEN data_status >= DATE'2026-07-18'              THEN 'ia'
        ELSE 'palavra_chave'
      END AS metodo,
      -- impacto declarado no texto: 'impacto estimado de 10 dias' ou 'impacto estimado: 1 semana'
      coalesce(
        CAST(nullif(regexp_extract(lower(texto_status), 'impacto estimado de ([0-9]+) dias', 1), '') AS DOUBLE),
        CAST(nullif(regexp_extract(lower(texto_status), 'impacto estimado: ([0-9]+) semana', 1), '') AS DOUBLE) * 7
      ) AS dias_pela_regex
    FROM novos
  ),

  -- a IA roda SÓ aqui, e só nas linhas do método ia (~160)
  chamadas_ia AS (
    SELECT
      *,
      ai_classify(
        texto_status,
        '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
        map('version', '2.0')
      ) AS classificacao,
      ai_extract(
        texto_status,
        '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"dias de atraso no cronograma, 1 semana = 7"}}',
        map('version', '2.0')
      ) AS extracao
    FROM com_metodo
    WHERE metodo = 'ia'
  ),

  via_ia AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      classificacao:response[0]::STRING                        AS causa_bloqueio,
      extracao:response:bloqueio::STRING                       AS bloqueio,
      extracao:response:quem_destrava::STRING                  AS quem_destrava,
      coalesce(extracao:response:dias_impacto::DOUBLE, dias_pela_regex) AS dias_impacto,
      metodo,
      texto_status
    FROM chamadas_ia
  ),

  sem_ia AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      CASE
        WHEN status_vazio      THEN 'nao_reportado'
        WHEN metodo = 'regra'  THEN 'sem_bloqueio'
        WHEN lower(texto_status) RLIKE 'freeze|congelamento|janela de deploy'                THEN 'change_freeze'
        WHEN lower(texto_status) RLIKE 'sre|infraestrutura|ambiente de homologação'          THEN 'falta_sre'
        WHEN lower(texto_status) RLIKE 'forge|consultoria|fornecedor'                         THEN 'dependencia_fornecedor'
        WHEN lower(texto_status) RLIKE 'saída de|rotatividade|onboarding'                     THEN 'rotatividade'
        WHEN lower(texto_status) RLIKE 'escopo|change request|regra de negócio'               THEN 'mudanca_escopo'
        WHEN lower(texto_status) RLIKE 'bugs|regressão|refazendo'                             THEN 'bug_retrabalho'
        WHEN lower(texto_status) RLIKE 'aprovação do cliente|homologação do cliente'          THEN 'aprovacao_cliente'
        ELSE 'outro'
      END                      AS causa_bloqueio,
      CAST(NULL AS STRING)     AS bloqueio,
      CAST(NULL AS STRING)     AS quem_destrava,
      CASE WHEN metodo = 'palavra_chave' THEN dias_pela_regex END AS dias_impacto,
      metodo,
      texto_status
    FROM com_metodo
    WHERE metodo <> 'ia'
  )

  SELECT *, current_timestamp() AS _classificado_em FROM via_ia
  UNION ALL
  SELECT *, current_timestamp() AS _classificado_em FROM sem_ia
) AS origem
ON  destino.projeto_id  = origem.projeto_id
AND destino.data_status = origem.data_status
WHEN NOT MATCHED THEN INSERT *;


-- c. leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, count(*) AS status
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, status DESC;
