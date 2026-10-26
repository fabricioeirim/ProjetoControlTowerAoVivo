import json
import pathlib
import re

candidatos = [
    pathlib.Path("resources/ingestao.job.yml"),
    pathlib.Path("resources/ingestão.job.yml"),
    pathlib.Path("resources\\ingestao.job.yml"),
    pathlib.Path("resources\\ingestão.job.yml"),
]
arquivo = next((p for p in candidatos if p.exists()), None)
if arquivo is None:
    raise FileNotFoundError(
        "não achei o job do bundle em resources/ingestao.job.yml ou resources/ingestão.job.yml. "
        "Rode dentro da pasta do bundle e depois do generate."
    )

yml = arquivo.read_text(encoding="utf-8")
chaves = {
    "s3_access_key_id": "AWS_ACCESS_KEY_ID",
    "s3_secret_access_key": "AWS_SECRET_ACCESS_KEY",
}
valores = {}
for var, param in chaves.items():
    match = re.search(rf"{re.escape(param)}:\s*(.+)", yml)
    if match is None:
        raise ValueError(f"não encontrei a chave {param} dentro de {arquivo}")

    valores[var] = match.group(1).strip().strip("\"'")
    yml = re.sub(rf"{re.escape(param)}:\s*.+", f"{param}: ${{var.{var}}}", yml, count=1)

prefixo = "variables:\n" + "".join(
    f"  {v}:\n    description: chave do data lake (o valor fica fora do Git)\n" for v in chaves
) + "\n"
yml = prefixo + yml
arquivo.write_text(yml, encoding="utf-8")

pasta = pathlib.Path(".databricks/bundle/dev")
pasta.mkdir(parents=True, exist_ok=True)
arquivo_override = pasta / "variable-overrides.json"
arquivo_override.write_text(json.dumps(valores, ensure_ascii=False, indent=2), encoding="utf-8")
print("ok: as chaves saíram do YAML e foram para", arquivo_override)