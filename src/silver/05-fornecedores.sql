-- silver.entregas_fornecedor: prometido × entregue das consultorias.
-- Não tem gold: o dashboard lê direto daqui.

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor (
  CONSTRAINT data_prometida_valida EXPECT (data_prometida IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Entregas das consultorias contratadas: fornecedor (nome normalizado), item, valor, data do pedido, data prometida e data de entrega (vazia = em aberto), com prazos em dias e a marca em_atraso (em aberto e já vencida em 16/10/2026).'
AS
WITH base AS (
  SELECT
    entrega_id,
    projeto_id,
    -- sujeira 15: a CodeForge veio de 4 jeitos
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor
    END                                        AS fornecedor,
    fornecedor                                 AS fornecedor_como_veio,
    item,
    CAST(valor AS DECIMAL(14, 2))              AS valor,
    to_date(data_pedido)                       AS data_pedido,
    to_date(data_prometida)                    AS data_prometida,
    to_date(nullif(trim(data_entrega), ''))    AS data_entrega,   -- vazia = em aberto (não é sujeira)
    CAST(prazo_contratado_dias AS INT)         AS prazo_contratado_dias,
    status
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  *,
  datediff(data_prometida, data_pedido)        AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)          AS prazo_real_dias,
  datediff(data_entrega, data_prometida)       AS dias_de_atraso_na_entrega,
  data_entrega IS NULL                         AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16' AS em_atraso
FROM base;
