"""Build comparable prefectural population observations for Shaanxi and Gansu."""
import csv
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = "lu_qing_shaangan_prefecture_reconstruction"
MERGERS = {
    "佛坪调整组": ("xian_hanzhong", "西安府及汉中府（含佛坪厅）"),
    "兰州西宁平凉宁夏调整组": (
        "lanzhou_xining_pingliang_ningxia", "兰州、西宁、平凉、宁夏诸府（含固原州、化平川厅）"
    ),
}

with (HERE / "lu_shaangan_table_2.csv").open(encoding="utf-8", newline="") as stream:
    raw = list(csv.DictReader(stream))
scopes = defaultdict(list)
for row in raw:
    slug, name = MERGERS.get(row["modernized_scope_group"],
                             (row["prefecture_slug"], row["admin_1900_name"]))
    scopes[(row["parent_unit_id"], slug, name)].append(row)

observations = []
for (parent, slug, name), rows in sorted(scopes.items()):
    names = "、".join(row["source_name"] for row in rows)
    pages = ", ".join(sorted({row["printed_page"] for row in rows}))
    unit = f"{parent}_{slug}"
    definition = (
        "Population reconstruction on comparable 1820 statistical areas named for jurisdictions existing in 1900. "
        "The two groups affected by known cross-prefecture transfers are combined. "
        "Other differences from 1900 boundaries have no quantified interval."
    )
    for year, column in (("1880", "population_1880"), ("1910", "population_1910_revised")):
        observations.append(dict(
            unit_id=unit, name=name, parent_id=parent, kind="admin", administrative_level=2,
            population_value=sum(int(row[column]) for row in rows), date=year, source_id=SOURCE,
            locator=f"Table 2, pp. {pages}, {names}, {year} reconstruction column",
            definition=definition, method="published_historical_demographic_reconstruction",
            quality="rounded_reconstruction", mapping_status="historical_statistical_area_without_1900_polygon",
            region="Asia",
        ))

(HERE / "observations.jsonl").write_text(
    "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in observations),
    encoding="utf-8",
)
