"""Rebuild observations.jsonl from the published population cells below."""

import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
SOURCES = {s["id"]: s for s in json.loads((OUT / "sources.json").read_text(encoding="utf-8"))}
ROOT = "cabo_verde_archipelago"
GOVERNMENT = "cabo_verde_secretaria_1901"
ISLANDS = [
    # Table 3, island, 1895, 1900. S. Thiago is Santiago.
    ("santiago", "Santiago", 60767, 64943),
    ("fogo", "Fogo", 20009, 17620),
    ("brava", "Brava", 9842, 9223),
    ("maio", "Maio", 1813, 1916),
    ("santo_antao", "Santo Antão", 23735, 29888),
    ("sao_vicente", "São Vicente", 6211, 8780),
    ("sao_nicolau", "São Nicolau", 12003, 11958),
    ("sal", "Sal", 550, 483),
    ("boa_vista", "Boa Vista", 3776, 2613),
]


def observation(source_id, year, value, unit=ROOT, name="Cabo Verde"):
    source = SOURCES[source_id]
    is_archipelago = unit == ROOT
    row = {
        "unit_id": unit, "name": name, "parent_id": None if is_archipelago else ROOT,
        "kind": "territory" if is_archipelago else "admin", "region": "Africa",
        "date": str(year), "population_value": value, "population_lower": None,
        "population_upper": None, "source_id": source_id, "locator": source["locator"],
        "definition": source["definition"], "method": source["method"],
        "mapping_status": "historical_identity_link" if is_archipelago else "historical_unit_unlinked",
        "quality": "published_historical_series",
    }
    if is_archipelago:
        row["wwo_id"] = "cshapes_gw_402"
    return row


rows = []
for island, name, earlier, later in ISLANDS:
    for year, value in [(1895, earlier), (1900, later)]:
        rows.append(observation(GOVERNMENT, year, value, "cabo_verde_" + island, name))
for year, value in [(1895, 138706), (1900, 147424)]:
    rows.append(observation(GOVERNMENT, year, value))
for year, value in [(1895, 138796), (1899, 144382), (1900, 147424), (1912, 143929)]:
    rows.append(observation("cabo_verde_medina_2009", year, value))
rows.append(observation("cabo_verde_ine_1900_2010", 1900, 143929))

(OUT / "observations.jsonl").write_text(
    "".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows),
    encoding="utf-8",
)
