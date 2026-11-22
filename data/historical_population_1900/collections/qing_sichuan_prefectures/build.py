"""Transcribe the reviewed disjoint Sichuan scopes at both Cao benchmarks."""
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = "cao_qing_sichuan_prefecture_reconstruction"

with (HERE / "sichuan_opening_groups.csv").open(encoding="utf-8", newline="") as stream:
    scopes = list(csv.DictReader(stream))

observations = []
for row in scopes:
    unlocated = row["mapping_status"] == "unlocated"
    definition = (
        "Sichuan balance from the author's six historical western statistical rows with unresolved 1900 boundaries and coverage."
        if unlocated else
        f"Author's comparable historical population reconstruction assigned to the 1900 scope {row['scope_1900']}."
    )
    for year in ("1880", "1910"):
        observations.append(dict(
            unit_id=row["unit_id"], name=row["name"], parent_id=row["parent_unit_id"],
            date=year, kind="admin", administrative_level=2,
            population_value=int(row[f"population_{year}"]), source_id=SOURCE,
            locator=f"Appendix 7, p. 560, {year} column, {row['source_slugs'].replace('|', ', ')}",
            definition=definition, method="published_historical_demographic_reconstruction",
            quality="rounded_reconstruction", mapping_status=row["mapping_status"],
            geographically_unlocated=unlocated, region="Asia",
        ))

(HERE / "observations.jsonl").write_text(
    "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in observations),
    encoding="utf-8",
)
