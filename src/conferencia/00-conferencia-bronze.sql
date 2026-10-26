-- Conferência da bronze: a ingestão trouxe tudo?
-- Uma linha por tabela, com a contagem esperada (seed 42) e a obtida.
-- Se alguma divergir, raise_error() derruba a tarefa e o job para aqui,
-- antes de a silver ler uma bronze pela metade.
-- (bronze.feriados fica de fora: cresce a cada execução.)

WITH esperado AS (
  SELECT * FROM VALUES
    ('projetos',               60),
    ('status_semanal',       3911),
    ('excel_tarefas',        1663),
    ('clickup_tarefas',      2119),
    ('msproject_tarefas',    1260),
    ('colaboradores',         523),
    ('apontamentos',        30883),
    ('custos',              23640),
    ('entregas_fornecedor',   640)
  AS t(tabela, esperado)
),

obtido AS (
            SELECT 'projetos'            AS tabela, COUNT(*) AS obtido FROM lakehouse_vertice.bronze.projetos
  UNION ALL SELECT 'status_semanal',      COUNT(*) FROM lakehouse_vertice.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas',       COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas',     COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas',   COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores',       COUNT(*) FROM lakehouse_vertice.bronze.colaboradores
  UNION ALL SELECT 'apontamentos',        COUNT(*) FROM lakehouse_vertice.bronze.apontamentos
  UNION ALL SELECT 'custos',              COUNT(*) FROM lakehouse_vertice.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor', COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor
)

SELECT e.tabela,
       e.esperado,
       o.obtido,
       CASE WHEN o.obtido = e.esperado THEN 'ok'
            ELSE raise_error(concat(
                   'bronze.', e.tabela, ': esperado ', e.esperado, ' linhas, obtido ', o.obtido,
                   '. Olhe a saída da tarefa ingestao_data_lake do job vertice_farol.'))
       END AS situacao
FROM esperado e
JOIN obtido o USING (tabela)
ORDER BY e.tabela
