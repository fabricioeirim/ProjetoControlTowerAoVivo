-- Testes de qualidade da Torre (sql_task, depois do medalhão).
-- Cada teste devolve 'ok' ou derruba a tarefa com raise_error dizendo o que falhou.


-- 1. os 60 projetos têm cronograma na silver.tarefas
SELECT '01 projetos com cronograma' AS teste,
       CASE WHEN n = 60 THEN 'ok'
            ELSE raise_error(concat('teste 1: só ', n, ' de 60 projetos têm tarefas na silver.tarefas')) END AS resultado
FROM (SELECT count(DISTINCT projeto_id) AS n FROM lakehouse_vertice.silver.tarefas);


-- 2. cada projeto veio de UMA ferramenta, a do cadastro do PMO
SELECT '02 uma ferramenta por projeto' AS teste,
       CASE WHEN n = 0 THEN 'ok'
            ELSE raise_error(concat('teste 2: ', n, ' projeto(s) com tarefas de outra ferramenta ou de mais de uma')) END AS resultado
FROM (
  SELECT count(*) AS n
  FROM (
    SELECT t.projeto_id
    FROM lakehouse_vertice.silver.tarefas t
    JOIN lakehouse_vertice.silver.projetos p USING (projeto_id)
    GROUP BY t.projeto_id
    HAVING count(DISTINCT t.ferramenta) > 1 OR max(t.ferramenta <> p.ferramenta)
  )
);


-- 3. as horas do Excel na silver = a soma das linhas de TOTAL das planilhas
SELECT '03 horas do Excel = TOTAL' AS teste,
       CASE WHEN n_diferentes = 0 AND n_planilhas = 20 THEN 'ok'
            ELSE raise_error(concat('teste 3: ', n_diferentes, ' planilha(s) com horas diferentes do TOTAL (de ', n_planilhas, ')')) END AS resultado
FROM (
  SELECT count(*) AS n_planilhas,
         count_if(abs(total.horas - silver.horas) >= 0.01) AS n_diferentes
  FROM (SELECT regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0) AS projeto_id,
               CAST(replace(horas_previstas, 'h', '') AS DOUBLE) AS horas
        FROM lakehouse_vertice.bronze.excel_tarefas
        WHERE tarefa = 'TOTAL') total
  JOIN (SELECT projeto_id, sum(horas) AS horas
        FROM lakehouse_vertice.silver.tarefas
        WHERE ferramenta = 'excel'
        GROUP BY projeto_id) silver
    USING (projeto_id)
);


-- 4. uma linha por pessoa na silver
SELECT '04 uma linha por pessoa' AS teste,
       CASE WHEN linhas = pessoas THEN 'ok'
            ELSE raise_error(concat('teste 4: ', linhas, ' linhas para ', pessoas, ' pessoas em silver.colaboradores')) END AS resultado
FROM (SELECT count(*) AS linhas, count(DISTINCT colaborador_id) AS pessoas
      FROM lakehouse_vertice.silver.colaboradores);


-- 5. a CodeForge virou um fornecedor só
SELECT '05 CodeForge é um fornecedor só' AS teste,
       CASE WHEN n = 1 THEN 'ok'
            ELSE raise_error(concat('teste 5: a CodeForge aparece com ', n, ' grafias em silver.entregas_fornecedor')) END AS resultado
FROM (SELECT count(DISTINCT fornecedor) AS n
      FROM lakehouse_vertice.silver.entregas_fornecedor
      WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%');


-- 6. a limpeza não mudou o custo total (bronze com replace = silver)
SELECT '06 custo total preservado' AS teste,
       CASE WHEN bronze = silver THEN 'ok'
            ELSE raise_error(concat('teste 6: custo na bronze ', bronze, ' x na silver ', silver)) END AS resultado
FROM (SELECT (SELECT sum(CAST(replace(valor, ',', '.') AS DECIMAL(14, 2))) FROM lakehouse_vertice.bronze.custos) AS bronze,
             (SELECT sum(valor) FROM lakehouse_vertice.silver.custos) AS silver);


-- 7. os 60 projetos têm fotografia de hoje
SELECT '07 fotografia dos 60 projetos' AS teste,
       CASE WHEN n = 60 THEN 'ok'
            ELSE raise_error(concat('teste 7: ', n, ' linhas em gold.projeto_situacao_atual (esperado 60)')) END AS resultado
FROM (SELECT count(*) AS n FROM lakehouse_vertice.gold.projeto_situacao_atual);


-- 8. todo projeto em andamento tem SPI e CPI
SELECT '08 SPI e CPI dos em andamento' AS teste,
       CASE WHEN n = 0 THEN 'ok'
            ELSE raise_error(concat('teste 8: ', n, ' projeto(s) em andamento sem SPI ou CPI')) END AS resultado
FROM (SELECT count(*) AS n
      FROM lakehouse_vertice.gold.projeto_situacao_atual
      WHERE status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL));


-- 9. o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%, na carteira)
SELECT '09 EV do status = EV das ferramentas' AS teste,
       CASE WHEN abs(ev_status - ev_ferramentas) / ev_ferramentas < 0.01 THEN 'ok'
            ELSE raise_error(concat('teste 9: EV pelo status ', ev_status, ' x pelas ferramentas ', ev_ferramentas)) END AS resultado
FROM (SELECT (SELECT sum(ev) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') AS ev_status,
             (SELECT sum(ev) FROM lakehouse_vertice.gold.projeto_situacao_atual) AS ev_ferramentas);


-- 10. AC de hoje no fato = soma dos lançamentos até hoje
SELECT '10 AC de hoje = lançamentos' AS teste,
       CASE WHEN abs(ac_fato - ac_custos) < 0.01 THEN 'ok'
            ELSE raise_error(concat('teste 10: AC no fato ', ac_fato, ' x lançamentos até hoje ', ac_custos)) END AS resultado
FROM (SELECT (SELECT sum(ac) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') AS ac_fato,
             (SELECT sum(valor) FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16') AS ac_custos);
