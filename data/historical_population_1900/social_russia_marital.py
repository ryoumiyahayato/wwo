"""Read census marital status as an all-age marginal in Russian opening pools."""

import csv
from pathlib import Path


MARRIAGE_TABLE = Path(__file__).resolve().parent / "collections" / "russia_marital_1897" / "marital_status.csv"
STATUS_LABELS = {
    "single": "Never married",
    "married": "Married",
    "widowed": "Widowed",
    "divorced": "Divorced",
}


def russian_marital_status(pools, provinces, distribution):
    with MARRIAGE_TABLE.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            province = provinces[row["unit_id"]]
            pool_id = province.get("wwo_id") or province["unit_id"]
            if pool_id not in pools:
                continue
            sex_counts = {
                sex: {status: int(row[f"{status}_{sex}"]) for status in (*STATUS_LABELS, "unknown")}
                for sex in ("male", "female")
            }
            if {sex: sum(counts.values()) for sex, counts in sex_counts.items()} != province["sex"]:
                raise ValueError(f"{pool_id}: marital status does not match the provincial census population by sex")
            counts = {
                label: sum(counts[status] for counts in sex_counts.values())
                for status, label in STATUS_LABELS.items()
            }
            yield pool_id, "marital_status", distribution(
                pools[pool_id]["population_value"], classification="russia_1897_reported_marital_status",
                source=row["source_id"], date="1897-02-09", observed_unit=province["unit_id"],
                scope=province["name"], locator=row["locator"], total=province["population_value"],
                observed_counts=counts, unknown=sum(counts["unknown"] for counts in sex_counts.values()),
                definition=("Marital status reported in the 1897 census for all persons present, including children "
                            "and persons of unknown age. The source's unreported status is unassigned."),
            )
