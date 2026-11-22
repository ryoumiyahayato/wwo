"""Archive Cao's two comparable Jiangxi prefectural returns."""
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = "cao_qing_jiangxi_prefecture_reconstruction"

with (HERE / "cao_jiangxi_table_12_13.csv").open(encoding="utf8", newline="") as stream:
    rows = list(csv.DictReader(stream))

with (HERE / "observations.jsonl").open("w", encoding="utf8", newline="\n") as stream:
    for year in ("1865", "1910"):
        for row in rows:
            level = 1 if row["role"] == "control" else 2
            observation = dict(
                source_id=SOURCE, unit_id=row["unit_id"], parent_id=row["parent_unit_id"],
                name=row["name"], date=year, kind="admin", administrative_level=level,
                population_value=int(row[f"population_{year}"]), region="Asia",
                locator=f"Cao, vol. 5, p. 535, Table 12–13; {year}, {row['name']}; Huang and Yang, p. 124, Table 1",
                definition=f"Published Jiangxi population reconstruction for {row['en_name']}.",
                method="published_historical_demographic_reconstruction", quality="rounded_reconstruction",
                chgis_id=row["chgis_id"], mapping_status="historical_statistical_area",
            )
            stream.write(json.dumps(observation, ensure_ascii=False, separators=(",", ":")) + "\n")
