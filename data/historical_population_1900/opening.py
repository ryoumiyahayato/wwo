"""Select disjoint inputs for the existing population authority. Evidence stays immutable."""
import csv
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATE = "1900-01-01"

def sourced_people(group):
    return group["population_value"] - group.get("legacy_unlocated_balance", 0)

def qing_interior(observations):
    path = HERE / "collections/eastern/qing_interior_crosswalk.tsv"
    by_id = {r["unit_id"]: r for r in observations
             if r["source_id"] == "cao_qing_provincial_reconstruction" and r["date"] == DATE}
    with path.open(encoding="utf8") as f:
        links = list(csv.DictReader(f, delimiter="\t"))
    leaves = []
    for link in links:
        row = by_id[link["unit_id"]]
        leaves.append(dict(unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
            source_id=row["source_id"], locator=row["locator"], source_observation=row["record_id"],
            source_quality=row["quality"], source_unit_ids=[row["unit_id"]], endpoint_values=row["endpoint_values"],
            wwo_admin_label=link["wwo_admin_label"], chgis_id=link["chgis_territory"], chgis_url=link["gazetteer"],
            geography_valid_years=[int(link["valid_from_year"]), int(link["valid_to_year"])],
            scope=link["study_scope"], place_ids=[]))
    legacy = json.loads((HERE.parent/"alpha/historical_world_economy_1900/countries_compact.json").read_text(encoding="utf8"))
    controls = (dict(zip(legacy["field_order"], data)) for data in legacy["rows"])
    control = next(r["population_value"] for r in controls if r["entity_id"] == "qing_empire")
    example = by_id[links[0]["unit_id"]]
    return dict(unit_id="qing_empire", date=DATE, population_value=control, source_id=example["source_id"],
        method=example["method"] + ". Nominal July endpoints for the two source years. Fraction " + example["fraction"],
        locator="Ni Yuping reproducing Cao, Table 1.1, p. 17 (PDF p. 31), rows 6 and 9.",
        partition_source=path.relative_to(HERE).as_posix(), endpoint_dates=example["source_dates"],
        interpolation_reference_dates=example["interpolation_reference_dates"], units=leaves,
        scope="Partial reconstruction for the two interior provinces. The total and the rest of the empire retain the legacy basis.",
        legacy_control_source="data/alpha/historical_world_economy_1900/countries_compact.json: qing_empire population_value",
        legacy_unlocated_balance=control-sum(leaf["population_value"] for leaf in leaves),
        uncertainty_kind="Model sensitivity scenarios in collections/eastern/qing_reconciliation.json. No calibrated interval.")


def groups(observations):
    study = {r["unit_id"]: r for r in observations if r["kind"] == "territory" and r["date"] == DATE and r["source_id"].startswith("ft_world_")}
    endpoints = {(r["unit_id"], r["date"]): r["population_value"] for r in observations if r["source_id"].startswith("ft_world_")}
    selected = defaultdict(list)
    with (HERE / "opening_series.tsv").open(encoding="utf8") as f:
        for decision in csv.DictReader(f, delimiter="\t"):
            row = study[decision["research_id"]]
            selected[decision["root_id"]].append((row, decision["scope"]))
    result = {}
    for root, pairs in selected.items():
        leaves = []
        for row, scope in pairs:
            leaves.append(dict(unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
                        population_lower=row["population_lower"], population_upper=row["population_upper"],
                        endpoint_values=[endpoints[(row["unit_id"], d)] for d in row["source_dates"]],
                        scope=scope, locator=row["locator"] + "; " + row["method_locator"], source_quality=row["quality"]))
        for leaf in leaves:
            if leaf["unit_id"] == "ft_russia_empire_ussr":
                leaf["place_ids"] = ["place:st_petersburg", "place:moscow"]
        first = pairs[0][0]
        bounds = {}
        for key in ("population_lower", "population_upper"):
            values = [leaf[key] for leaf in leaves]
            bounds[key] = sum(values) if all(value is not None for value in values) else None
        group = dict(unit_id=root, date=DATE, source_id=first["source_id"], population_value=sum(x["population_value"] for x in leaves),
                     method=first["method"]+"; elapsed fraction "+first["fraction"], locator=" / ".join(x["locator"] for x in leaves),
                     endpoint_dates=first["source_dates"], country_endpoint_values=[sum(x["endpoint_values"][i] for x in leaves) for i in (0, 1)],
                     scope=" / ".join(x["scope"] for x in leaves), research_unit_ids=[x["unit_id"] for x in leaves],
                     **bounds,
                     uncertainty_kind=first["uncertainty_kind"] if all(v is not None for v in bounds.values()) else "No sensitivity interval is available for this version of the study series.", units=leaves if len(leaves)>1 else [])
        result[root] = group
    files = sorted(HERE.glob("collections/*/*_opening.json"))
    territorial_roots = set()
    for path in files:
        group = json.loads(path.read_text(encoding="utf8"))
        root = group["unit_id"]
        if root in territorial_roots:
            raise ValueError(f"two production partitions for {root}")
        territorial_roots.add(root)
        group["partition_source"] = path.relative_to(HERE).as_posix()
        group.setdefault("date", DATE)
        if root in result:
            group["alternative_research_value"] = result[root]["population_value"]
        result[root] = group
    if "qing_empire" in result:
        raise ValueError("duplicate Qing population control")
    result["qing_empire"] = qing_interior(observations)
    ids = set()
    for root, group in result.items():
        group.setdefault("population_lower",None)
        group.setdefault("population_upper",None)
        group.setdefault("uncertainty_kind","Enumeration coverage and interpolation error have no quantified interval.")
        children = group["units"]
        for child in children:
            child.setdefault("population_lower",None)
            child.setdefault("population_upper",None)
        if children and sum(x["population_value"] for x in children) != sourced_people(group):
            raise ValueError(f"non-closing opening partition {root}")
        for key in [root]+[x["unit_id"] for x in children]:
            if key in ids:
                raise ValueError(f"duplicate population unit {key}")
            ids.add(key)
    return [result[key] for key in sorted(result)]
