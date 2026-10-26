-- silver.status_semanal e silver.custos

-- O status de toda sexta: é dele que vem o HISTÓRICO do avanço
-- (as ferramentas só guardam o % de hoje).
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal de cada projeto (toda sexta): % concluído informado pelo gerente, farol do gerente (verde, amarelo, vermelho) e o texto livre com entregas e bloqueios. status_vazio marca textos sem conteúdo (vazio, N/A, ver ata da reunião), que ficam na tabela.'
AS
SELECT
  projeto_id,
  to_date(data_status)               AS data_status,
  gerente,
  lower(trim(farol))                 AS farol,          -- sujeira 17: 'Verde', 'VERDE'
  CAST(pct_concluido AS INT)         AS pct_concluido,
  texto_status,
  -- sujeira 18: status sem conteúdo NÃO é descartado, só sinalizado
  trim(coalesce(texto_status, '')) IN ('', 'N/A', 'ver ata da reunião') AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;


-- Lançamentos de custo real. O teste: a soma tem que dar R$ 193,35 mi, igual à bronze.
CREATE OR REFRESH MATERIALIZED VIEW custos (
  CONSTRAINT valor_legivel EXPECT (valor IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Lançamentos de custo real por projeto (pessoal, consultoria, cloud, licenças, despesas), com a data, a sexta da semana e o valor líquido em R$. Estornos ficam como valor negativo, marcados em estorno.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(data)                                   AS data,
  to_date(date_add(date_trunc('WEEK', data), 4))  AS semana,   -- sexta da semana
  categoria,
  descricao,
  -- sujeira 13: '12345,67'. replace ANTES do CAST: try_cast jogaria R$ 5,4 mi fora em silêncio
  CAST(replace(valor, ',', '.') AS DECIMAL(14, 2)) AS valor,
  -- sujeira 14: estorno fica (custo é líquido), só marcado
  CAST(replace(valor, ',', '.') AS DECIMAL(14, 2)) < 0 AS estorno,
  centro_custo
FROM lakehouse_vertice.bronze.custos;
