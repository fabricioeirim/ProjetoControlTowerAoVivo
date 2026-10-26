#!/usr/bin/env python3
"""Gera o dashboard AI/BI do portfólio: resources/dashboard-portfolio.lvdash.json.

As queries da gold usam o nome PURO da tabela: o recurso do bundle preenche o
catálogo e o schema (dataset_catalog / dataset_schema). Fornecedor não tem gold:
lê lakehouse_vertice.silver.entregas_fornecedor pelo nome completo.

Uso:
  python scripts/gerar_dashboard.py                         # grava o JSON
  python scripts/gerar_dashboard.py --sql-teste <arquivo>   # grava as queries (com o
      prefixo lakehouse_vertice.gold.) e a contagem de linhas de cada uma, para rodar
      com scripts/run_sql.py antes do deploy
"""
import json, pathlib, re, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "dashboard-portfolio.lvdash.json"
TABELAS_GOLD = ["projeto_situacao_atual", "fato_projeto_semana", "utilizacao_pessoa_semana", "status_estruturado"]

# cores da situação (as mesmas em todo gráfico)
CORES_SITUACAO = [
    {"value": "crítico", "color": "#FF5F46"},
    {"value": "atenção", "color": "#F6C344"},
    {"value": "ok",      "color": "#22C2F4"},
]
BRL = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
       "decimalPlaces": {"type": "max", "places": 2}}
RAZAO = {"type": "number", "decimalPlaces": {"type": "exact", "places": 2}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}


# ============================================================
# Datasets: (nome, título, SQL)
# ============================================================
DATASETS = [
    ("ds_kpis", "KPIs da carteira em andamento", """
SELECT
  SUM(valor_contrato)                                  AS carteira,
  SUM(ev) / SUM(pv)                                    AS spi,
  SUM(ev) / SUM(ac)                                    AS cpi,
  SUM(estouro_previsto)                                AS estouro_previsto,
  count_if(situacao IN ('atenção', 'crítico'))         AS em_risco,
  count_if(situacao = 'crítico')                       AS criticos,
  count_if(melancia)                                   AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
"""),
    ("ds_projetos", "Projetos em andamento", """
SELECT
  projeto,
  cliente,
  situacao,
  spi,
  cpi,
  estouro_previsto,
  margem_projetada,
  atraso_projetado_dias,
  farol_do_gerente,
  farol_calculado,
  CASE WHEN melancia THEN 'sim' ELSE '' END          AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY CASE situacao WHEN 'crítico' THEN 1 WHEN 'atenção' THEN 2 ELSE 3 END, spi
"""),
    ("ds_estouro", "Estouro previsto por projeto", """
SELECT projeto, situacao, estouro_previsto
FROM projeto_situacao_atual
WHERE status = 'em_andamento' AND estouro_previsto > 0
ORDER BY estouro_previsto DESC
"""),
    ("ds_tendencia", "SPI e CPI semanais da carteira", """
SELECT
  semana,
  SUM(ev) / SUM(pv)  AS spi,
  SUM(ev) / SUM(ac)  AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana
"""),
    ("ds_top_parados", "Top 15 pessoas por custo da hora parada", """
SELECT
  concat(nome, ' (', papel, ')')                  AS pessoa,
  SUM(custo_ocioso)                               AS custo_ocioso,
  SUM(horas_apontadas) / SUM(horas_disponiveis)   AS utilizacao
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY nome, papel
ORDER BY custo_ocioso DESC
LIMIT 15
"""),
    ("ds_utilizacao", "Utilização por pessoa e projeto", """
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  projeto_id,
  SUM(horas_disponiveis)                          AS horas_disponiveis,
  SUM(horas_apontadas)                            AS horas_apontadas,
  SUM(horas_ociosas)                              AS horas_ociosas,
  SUM(horas_apontadas) / SUM(horas_disponiveis)   AS utilizacao,
  SUM(custo_ocioso)                               AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY utilizacao, custo_ocioso DESC
"""),
    ("ds_causas", "Causas de bloqueio por projeto", """
SELECT projeto_id, causa_bloqueio, count(*) AS semanas
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
"""),
    ("ds_fornecedores", "Entregas por fornecedor", """
SELECT
  fornecedor,
  count(DISTINCT fornecedor_como_veio)                                       AS grafias_no_cadastro,
  count(*)                                                                    AS entregas,
  SUM(CASE WHEN NOT em_aberto THEN prazo_real_dias END)
    / SUM(CASE WHEN NOT em_aberto THEN prazo_prometido_dias END)              AS prazo_real_sobre_prometido,
  count_if(NOT em_aberto AND dias_de_atraso_na_entrega <= 0)
    / count_if(NOT em_aberto)                                                 AS pct_no_prazo,
  count_if(em_atraso)                                                         AS em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY prazo_real_sobre_prometido DESC
"""),
    ("ds_atrasadas", "Entregas em atraso hoje", """
SELECT
  fornecedor,
  fornecedor_como_veio,
  projeto_id,
  item,
  data_pedido,
  data_prometida,
  datediff(DATE'2026-10-16', data_prometida)   AS dias_em_atraso,
  valor
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_em_atraso DESC
"""),
]


# ============================================================
# Widgets
# ============================================================
def campo(nome):
    return {"name": nome, "expression": f"`{nome}`"}


def query(dataset, campos):
    return [{"name": "main_query",
             "query": {"datasetName": dataset, "fields": [campo(c) for c in campos], "disaggregated": True}}]


def texto(nome, linhas, x, y, w, h):
    return {"widget": {"name": nome, "multilineTextboxSpec": {"lines": linhas}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def counter(nome, titulo, campo_valor, fmt, x, y, w=3, h=3, descricao=None):
    valor = {"fieldName": campo_valor, "displayName": titulo}
    if fmt:
        valor["format"] = fmt
    frame = {"showTitle": True, "title": titulo}
    if descricao:
        frame.update({"showDescription": True, "description": descricao})
    return {"widget": {"name": nome, "queries": query("ds_kpis", [campo_valor]),
                       "spec": {"version": 2, "widgetType": "counter",
                                "encodings": {"value": valor}, "frame": frame}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def tabela(nome, titulo, dataset, colunas, x, y, w, h):
    """colunas: lista de (campo, título, formato ou None)"""
    cols = []
    for c, t, f in colunas:
        col = {"fieldName": c, "displayName": t}
        if f:
            col["format"] = f
        cols.append(col)
    return {"widget": {"name": nome, "queries": query(dataset, [c for c, _, _ in colunas]),
                       "spec": {"version": 2, "widgetType": "table", "encodings": {"columns": cols},
                                "frame": {"showTitle": True, "title": titulo}}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def grafico(nome, titulo, tipo, dataset, campos, encodings, x, y, w, h, descricao=None, extra=None):
    frame = {"showTitle": True, "title": titulo}
    if descricao:
        frame.update({"showDescription": True, "description": descricao})
    spec = {"version": 3, "widgetType": tipo, "encodings": encodings, "frame": frame}
    if extra:
        spec.update(extra)
    return {"widget": {"name": nome, "queries": query(dataset, campos), "spec": spec},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def cor_situacao():
    return {"fieldName": "situacao", "displayName": "Situação",
            "scale": {"type": "categorical", "mappings": CORES_SITUACAO}}


def linha_referencia(eixo, valor, rotulo):
    return {"type": f"{'horizontal' if eixo == 'y' else 'vertical'}-line",
            "encodings": {eixo: {"dataValue": str(valor), "dataType": "DOUBLE"},
                          "label": {"value": rotulo}, "color": {"value": "#FF5F46"}}}


# ---------- Página 1: Portfólio ----------
portfolio = [
    texto("titulo_portfolio",
          ["## Quais projetos estão atrasados, de quais clientes, e quanto esse atraso vai custar?\n", "\n",
           "Carteira em andamento em 16/10/2026. SPI ou CPI < 0,9 = atenção, < 0,8 = crítico."], 0, 0, 12, 2),
    counter("kpi_carteira", "Carteira em andamento", "carteira", BRL, 0, 2),
    counter("kpi_spi", "SPI da carteira", "spi", RAZAO, 3, 2, descricao="Σ EV ÷ Σ PV (< 1 é atraso)"),
    counter("kpi_cpi", "CPI da carteira", "cpi", RAZAO, 6, 2, descricao="Σ EV ÷ Σ AC (< 1 é estouro)"),
    counter("kpi_estouro", "Estouro previsto", "estouro_previsto", BRL, 9, 2, descricao="Σ (EAC − orçamento), só positivos"),
    counter("kpi_risco", "Projetos em risco", "em_risco", None, 0, 5, w=4, descricao="atenção + crítico"),
    counter("kpi_criticos", "Projetos críticos", "criticos", None, 4, 5, w=4, descricao="SPI ou CPI < 0,8"),
    counter("kpi_melancias", "Melancias 🍉", "melancias", None, 8, 5, w=4, descricao="farol do gerente verde e SPI < 0,9"),
    grafico("barra_estouro", "Estouro previsto por projeto", "bar", "ds_estouro",
            ["projeto", "situacao", "estouro_previsto"],
            {"x": {"fieldName": "estouro_previsto", "displayName": "Estouro previsto",
                   "scale": {"type": "quantitative"}, "format": BRL},
             "y": {"fieldName": "projeto", "displayName": "Projeto",
                   "scale": {"type": "categorical"}},
             "color": cor_situacao()},
            0, 8, 6, 7),
    grafico("dispersao_spi_cpi", "SPI × CPI (um ponto por projeto)", "scatter", "ds_projetos",
            ["spi", "cpi", "situacao", "projeto"],
            {"x": {"fieldName": "spi", "displayName": "SPI", "scale": {"type": "quantitative"}},
             "y": {"fieldName": "cpi", "displayName": "CPI", "scale": {"type": "quantitative"}},
             "color": cor_situacao(),
             "extra": [{"fieldName": "projeto", "displayName": "Projeto"}]},
            6, 8, 6, 7,
            extra={"annotations": [linha_referencia("x", 0.9, "SPI 0,9"), linha_referencia("y", 0.9, "CPI 0,9")]}),
    grafico("linha_tendencia", "SPI e CPI semanais da carteira", "line", "ds_tendencia",
            ["semana", "spi", "cpi"],
            {"x": {"fieldName": "semana", "displayName": "Semana", "scale": {"type": "temporal"}},
             "y": {"scale": {"type": "quantitative"},
                   "fields": [{"fieldName": "spi", "displayName": "SPI"},
                              {"fieldName": "cpi", "displayName": "CPI"}]}},
            0, 15, 12, 6, descricao="Σ EV ÷ Σ PV e Σ EV ÷ Σ AC de todos os projetos, por sexta",
            extra={"annotations": [linha_referencia("y", 0.9, "atenção (0,9)")]}),
    tabela("tabela_projetos", "Projetos em andamento: o farol do gerente × o farol pelo número", "ds_projetos",
           [("projeto", "Projeto", None), ("cliente", "Cliente", None), ("situacao", "Situação", None),
            ("spi", "SPI", RAZAO), ("cpi", "CPI", RAZAO), ("estouro_previsto", "Estouro previsto", BRL),
            ("margem_projetada", "Margem projetada", PCT), ("atraso_projetado_dias", "Atraso projetado (dias)", None),
            ("farol_do_gerente", "Farol do gerente", None), ("farol_calculado", "Farol pelo número", None),
            ("melancia", "Melancia", None)],
           0, 21, 12, 9),
]

# ---------- Página 2: Pessoas ----------
pessoas = [
    texto("titulo_pessoas",
          ["## Tenho gente parada enquanto outro projeto pede gente?\n", "\n",
           "Timesheet das últimas 12 semanas (sextas depois de 24/07/2026) e as causas declaradas no status dos últimos 90 dias."],
          0, 0, 12, 2),
    grafico("barra_parados", "Top 15 pessoas por custo da hora parada", "bar", "ds_top_parados",
            ["pessoa", "custo_ocioso", "utilizacao"],
            {"x": {"fieldName": "custo_ocioso", "displayName": "Custo da hora parada",
                   "scale": {"type": "quantitative"}, "format": BRL},
             "y": {"fieldName": "pessoa", "displayName": "Pessoa",
                   "scale": {"type": "categorical"}}},
            0, 2, 5, 8),
    grafico("barra_causas", "Causas de bloqueio por projeto (últimos 90 dias)", "bar", "ds_causas",
            ["projeto_id", "causa_bloqueio", "semanas"],
            {"x": {"fieldName": "projeto_id", "displayName": "Projeto", "scale": {"type": "categorical"}},
             "y": {"fieldName": "semanas", "displayName": "Semanas com o bloqueio", "scale": {"type": "quantitative"}},
             "color": {"fieldName": "causa_bloqueio", "displayName": "Causa", "scale": {"type": "categorical"}}},
            5, 2, 7, 8),
    tabela("tabela_utilizacao", "Utilização por pessoa e projeto (da mais parada à mais ocupada)", "ds_utilizacao",
           [("colaborador_id", "ID", None), ("nome", "Pessoa", None), ("papel", "Papel", None),
            ("senioridade", "Senioridade", None), ("projeto_id", "Projeto", None),
            ("horas_disponiveis", "Horas disponíveis", None), ("horas_apontadas", "Horas apontadas", None),
            ("horas_ociosas", "Horas paradas", None), ("utilizacao", "Utilização", PCT),
            ("custo_ocioso", "Custo parado", BRL)],
           0, 10, 12, 9),
]

# ---------- Página 3: Fornecedores ----------
fornecedores = [
    texto("titulo_fornecedores",
          ["## O que vai dar errado no próximo mês?\n", "\n",
           "As entregas das consultorias: prometido × entregue e o que já está vencido em 16/10/2026."],
          0, 0, 12, 2),
    tabela("tabela_fornecedores", "Entregas por fornecedor", "ds_fornecedores",
           [("fornecedor", "Fornecedor", None), ("grafias_no_cadastro", "Grafias no cadastro", None),
            ("entregas", "Entregas", None), ("prazo_real_sobre_prometido", "Prazo real ÷ prometido", RAZAO),
            ("pct_no_prazo", "% no prazo", PCT), ("em_atraso_hoje", "Em atraso hoje", None)],
           0, 2, 12, 5),
    tabela("tabela_atrasadas", "Entregas em atraso hoje", "ds_atrasadas",
           [("fornecedor", "Fornecedor", None), ("fornecedor_como_veio", "Como veio no cadastro", None),
            ("projeto_id", "Projeto", None), ("item", "Item", None), ("data_pedido", "Pedido", None),
            ("data_prometida", "Prometida para", None), ("dias_em_atraso", "Dias em atraso", None),
            ("valor", "Valor", BRL)],
           0, 7, 12, 6),
]


def pagina(nome, titulo, layout):
    return {"name": nome, "displayName": titulo, "pageType": "PAGE_TYPE_CANVAS",
            "layoutVersion": "GRID_V1", "layout": layout}


def linhas_sql(sql):
    """queryLines: cada linha termina em \\n (são concatenadas sem separador)."""
    return [l + "\n" for l in sql.strip().splitlines()]


DASHBOARD = {
    "datasets": [{"name": n, "displayName": t, "queryLines": linhas_sql(s)} for n, t, s in DATASETS],
    "pages": [
        pagina("portfolio", "Portfólio", portfolio),
        pagina("pessoas", "Pessoas", pessoas),
        pagina("fornecedores", "Fornecedores", fornecedores),
    ],
    "uiSettings": {
        "theme": {
            # cores da Jornada: azul #0059DB, ciano #22C2F4, fundo #14141A no escuro
            "canvasBackgroundColor": {"light": "#F4F6FA", "dark": "#14141A"},
            "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1D1D25"},
            "widgetBorderColor":     {"light": "#FFFFFF", "dark": "#1D1D25"},
            "fontColor":             {"light": "#14141A", "dark": "#F2F4F8"},
            "selectionColor":        {"light": "#0059DB", "dark": "#22C2F4"},
            "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF5F46",
                                    "#8B5CF6", "#2ECC9A", "#FF9F43", "#9AA5B1"],
            "widgetHeaderAlignment": "LEFT",
        }
    },
}


def sql_de_teste():
    """As mesmas queries, com a gold pelo nome completo: a contagem de linhas de cada
    dataset e, para os KPIs, os próprios valores."""
    padrao = re.compile(r"\b(FROM|JOIN)\s+(" + "|".join(TABELAS_GOLD) + r")\b")
    partes = []
    for nome, _, sql in DATASETS:
        completo = padrao.sub(r"\1 lakehouse_vertice.gold.\2", sql.strip())
        partes.append(f"-- {nome}\nSELECT '{nome}' AS dataset, count(*) AS linhas FROM (\n{completo}\n) q;\n")
        if nome == "ds_kpis":
            partes.append(f"-- {nome} (valores)\n{completo};\n")
    return "\n".join(partes)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--sql-teste":
        pathlib.Path(sys.argv[2]).write_text(sql_de_teste(), encoding="utf-8")
        print("queries de teste em", sys.argv[2])
    else:
        SAIDA.write_text(json.dumps(DASHBOARD, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        n_widgets = sum(len(p["layout"]) for p in DASHBOARD["pages"])
        print(f"ok: {SAIDA.relative_to(RAIZ)} ({len(DASHBOARD['datasets'])} datasets, "
              f"{len(DASHBOARD['pages'])} páginas, {n_widgets} widgets)")
