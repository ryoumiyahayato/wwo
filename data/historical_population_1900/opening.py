"""Select disjoint inputs for the existing population authority. Evidence stays immutable."""
import csv
import json
from collections import defaultdict
from datetime import date
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATE = "1900-01-01"

def sourced_people(group):
    return group["population_value"] - group.get("legacy_unlocated_balance", 0)

def located_people(group):
    return sourced_people(group) - group.get("research_unlocated_balance", 0)


def legacy_population_control(unit_id):
    legacy = json.loads((HERE.parent/"alpha/historical_world_economy_1900/countries_compact.json").read_text(encoding="utf8"))
    controls = (dict(zip(legacy["field_order"], data)) for data in legacy["rows"])
    return next(r["population_value"] for r in controls if r["entity_id"] == unit_id)


def fiji_and_rotuma(observations):
    source = "british_empire_census_1901"
    returns = {r["date"]: r for r in observations if r["source_id"] == source and r["unit_id"] == "fiji_rotuma"}
    before, after = returns["1891"], returns["1901-04-01"]
    first, last = date(1891, 4, 5), date(1901, 3, 31)
    fraction = Fraction((date.fromisoformat(DATE) - first).days, (last - first).days)
    initial, final = before["population_value"], after["population_value"]
    return dict(unit_id="cshapes_gw_950", date=DATE, population_value=round(initial+(final-initial)*fraction),
        source_id=source, locator=after["locator"], endpoint_dates=[first.isoformat(), last.isoformat()],
        country_endpoint_values=[initial, final], source_observations=[before["record_id"], after["record_id"]],
        date_source="https://www.statsfiji.gov.fj/statistics/social-statistics/population-and-demographic-indicators/",
        method=f"Linear interpolation of comparable colony census totals using the Fiji Bureau of Statistics reference nights, elapsed fraction {fraction}.",
        scope="Fiji Islands and Rotuma, after Rotuma joined the colony in 1881. The 1901 return separately tabulates the two components. Their 1900 values are unavailable.",
        partition_source="collections/eastern/observations.jsonl", units=[])


def egypt_two_cities(observations):
    root = "khedivate_of_egypt"
    source = "egypt_historical_census_primary_tables"
    dates = ["1897-06-01", "1907-04-29"]
    start, end = map(date.fromisoformat, dates)
    fraction = Fraction((date.fromisoformat(DATE) - start).days, (end - start).days)
    returns = {(r["unit_id"], r["date"]): r for r in observations if r["source_id"] == source and r["kind"] == "city"}
    leaves = []
    for city, scope in [
        ("cairo", "Cairo town in the separate governorate return. Giza is a separate entry under Giza province."),
        ("alexandria", "Alexandria town in the separate governorate return. Ramleh is separately listed under Buheira."),
    ]:
        unit = "egy_madina_" + city
        before, after = [returns[(unit, d)] for d in dates]
        initial, final = [r["population_value"] for r in (before, after)]
        leaves.append(dict(
            unit_id=unit, name=before["name"], population_value=round(initial+(final-initial)*fraction),
            source_unit_ids=[unit], source_id=source, source_quality=before["quality"],
            source_observations=[before["record_id"], after["record_id"]],
            endpoint_values=[initial, final], locator=before["locator"]+" / "+after["locator"],
            scope=scope, place_ids=["place:"+city],
            uncertainty_kind="No statistical interval. Enumeration coverage, changes to the reported urban extent and interpolation error are unquantified.",
        ))
    control = legacy_population_control(root)
    return dict(
        unit_id=root, date=DATE, population_value=control, source_id=source,
        legacy_control_source="data/alpha/historical_world_economy_1900/countries_compact.json: khedivate_of_egypt population_value",
        legacy_unlocated_balance=control-sum(leaf["population_value"] for leaf in leaves),
        partition_source="collections/eastern/observations.jsonl",
        locator="Tanada, Table 4, Cairo and Alexandria; census dates in Table 2.",
        endpoint_dates=dates, interpolation_reference_dates=dates,
        method=f"Linear daily interpolation of the two separate town returns, elapsed fraction {fraction}.",
        scope="The two towns are disjoint subdivisions of the retained Egypt control. The balance has no geographic allocation. The census and map extents differ for western oases and the southern frontier.",
        uncertainty_kind="The national control retains its inherited source basis. The interpolated town estimates have no statistical interval.",
        units=leaves,
    )


def natal_and_zululand(observations):
    partition = "collections/african_returns/natal_v3_geography.json"
    basis = json.loads((HERE / partition).read_text(encoding="utf8"))
    estimate = next(r for r in observations if r["unit_id"] == "natal_zululand_pre_transfer" and r["date"] == "1900")
    comparison = next(r for r in observations if r["unit_id"] == "natal_zululand" and r["date"] == "1904-04-18"
                      and r["source_id"] == basis["comparison_source_id"])
    districts = basis["transferred_districts"]
    return dict(
        unit_id=estimate["wwo_id"], date=DATE, population_value=estimate["population_value"],
        source_id=estimate["source_id"], source_quality=estimate["quality"], source_observations=[estimate["record_id"]],
        locator=estimate["locator"], source_dates=[estimate["date"]], partition_source=partition,
        method="Use the published annual colonial estimate as a proxy for 1 January 1900. The underlying table supplies a year and no reference day.",
        scope=basis["scope"], geography_note=basis["geography_note"],
        uncertainty_kind="No statistical interval. The estimate's date and method are incompletely documented. Wartime migration and enumeration differences are unquantified.",
        census_comparison=dict(
            source_id=comparison["source_id"], source_observation=comparison["record_id"],
            date=comparison["date"], locator=basis["comparison_locator"],
            published_population=comparison["population_value"], excluded_districts=districts,
            population_on_pre_transfer_definition=comparison["population_value"]-sum(d["population_value"] for d in districts),
            scope=basis["comparison_scope"],
        ),
        units=[],
    )

def cape_colony(observations):
    estimate = next(r for r in observations if r["source_id"] == "cape_colony_1899_imperial_conference")
    alternatives = [r for r in observations if r["unit_id"] == estimate["unit_id"] and r is not estimate]
    return dict(
        unit_id=estimate["wwo_id"], date=DATE, population_value=estimate["population_value"],
        source_id=estimate["source_id"], source_quality=estimate["quality"],
        source_observations=[estimate["record_id"]], source_dates=[estimate["date"]],
        locator=estimate["locator"], partition_source="collections/cape_population/observations.jsonl",
        method="Use the 1899 official annual estimate as the closest published pre-opening proxy. Its reference month and day are unknown.",
        scope=estimate["definition"],
        uncertainty_kind="No statistical interval. Enumeration coverage, the estimate date, and wartime displacement are unquantified. Dated alternatives remain separate.",
        alternative_estimates=[
            {key: row[key] for key in ("source_id", "date", "population_value", "locator", "record_id", "definition")}
            for row in alternatives
        ],
        units=[],
    )


def zanzibar_protectorate(observations):
    returns = [r for r in observations if r["unit_id"] == "zanzibar_protectorate"]
    estimate = next(row for row in returns if row["source_id"] == "zanzibar_statesmans_year_book_1899")
    return dict(
        unit_id=estimate["wwo_id"], date=DATE, population_value=estimate["population_value"],
        source_id=estimate["source_id"], source_quality=estimate["quality"],
        source_observations=[estimate["record_id"]], source_dates=[estimate["date"]],
        locator=estimate["locator"], partition_source="collections/zanzibar_population/observations.jsonl",
        method="Use the two island estimates published in 1899 as the opening proxy. Their reference date and estimation method are not stated.",
        scope=estimate["definition"],
        uncertainty_kind="No statistical interval. Later census and earlier estimates have different dates. No opening island or urban allocation is adopted.",
        alternative_estimates=[
            {key: row[key] for key in ("source_id", "date", "population_value", "locator", "record_id", "definition")}
            for row in returns if row is not estimate
        ],
        units=[],
    )


def add_java_and_madura(group, observations):
    unit = "java_madoera_colonial_population"
    first, last = sorted((r for r in observations if r["unit_id"] == unit), key=lambda r: r["date"])
    start, end = (date.fromisoformat(row["date"]) for row in (first, last))
    fraction = Fraction((date.fromisoformat(DATE) - start).days, (end - start).days)
    opening = round(first["population_value"] + (last["population_value"] - first["population_value"]) * fraction)
    group["subdivision_source"] = "collections/java_madoera/observations.jsonl"
    group["research_unlocated_balance"] = group["population_value"] - opening
    group["scope"] += (" Java and Madura are a distinct civilian statistical subdivision. The research account balance remains "
                       "an arithmetic unlocated pool including any date, coverage or definition differences. It does not establish the total of the Outer Islands.")
    group["units"] = [dict(
        unit_id=unit, name=first["name"], date=DATE, population_value=opening,
        source_id=last["source_id"], source_unit_ids=[unit],
        source_observations=[first["record_id"], last["record_id"]], source_dates=[first["date"], last["date"]],
        endpoint_values=[first["population_value"], last["population_value"]],
        locator=first["locator"]+" / "+last["locator"],
        method=f"Linear daily interpolation of the two civilian administrative totals, elapsed fraction {fraction}.",
        scope=last["definition"],
        uncertainty_kind="The first return is provisional. Private-estate coverage and interpolation error have no quantified interval. No opening polygon or residence point is assigned.",
        place_ids=[],
    )]


def qing_interior(observations, version):
    path = HERE / "collections/eastern/qing_interior_crosswalk.tsv"
    by_id = {r["unit_id"]: r for r in observations
             if r["source_id"] == "cao_qing_provincial_reconstruction" and r["date"] == DATE}
    with path.open(encoding="utf8") as f:
        links = list(csv.DictReader(f, delimiter="\t"))
    if version >= 2:
        additional = path.with_name("qing_interior_v2_crosswalk.tsv")
        with additional.open(encoding="utf8") as f:
            links.extend(csv.DictReader(f, delimiter="\t"))
    leaves = []
    for link in links:
        row = by_id[link["unit_id"]]
        leaves.append(dict(unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
            source_id=row["source_id"], locator=row["locator"], source_observation=row["record_id"],
            source_quality=row["quality"], source_unit_ids=[row["unit_id"]], endpoint_values=row["endpoint_values"],
            wwo_admin_label=link["wwo_admin_label"], chgis_id=link["chgis_territory"], chgis_url=link["gazetteer"],
            geography_valid_years=[int(link["valid_from_year"]), int(link["valid_to_year"])],
            scope=link["study_scope"], place_ids=[]))
    control = legacy_population_control("qing_empire")
    example = by_id[links[0]["unit_id"]]
    group = dict(unit_id="qing_empire", date=DATE, population_value=control, source_id=example["source_id"],
        method=example["method"] + ". Nominal July endpoints for the two source years. Fraction " + example["fraction"],
        locator="Ni Yuping reproducing Cao, Table 1.1, p. 17 (PDF p. 31), rows 6 and 9.",
        partition_source=path.relative_to(HERE).as_posix(), endpoint_dates=example["source_dates"],
        interpolation_reference_dates=example["interpolation_reference_dates"], units=leaves,
        scope="Partial reconstruction for the two interior provinces. The total and the rest of the empire retain the legacy basis.",
        legacy_control_source="data/alpha/historical_world_economy_1900/countries_compact.json: qing_empire population_value",
        legacy_unlocated_balance=control-sum(leaf["population_value"] for leaf in leaves),
        uncertainty_kind="Model sensitivity scenarios in collections/eastern/qing_reconciliation.json. No calibrated interval.")
    if version >= 2:
        group.update(
            locator="Ni Yuping reproducing Cao, Table 1.1, pp. 17–18 (PDF pp. 31–32). See the individual province locators.",
            scope="Disjoint provincial returns within the legacy Qing control. The province links establish historical statistical identities. No separate city, concession or frontier population is added.",
            additional_partition_source=additional.relative_to(HERE).as_posix())
    return group


def groups(observations, version=1):
    study = {r["unit_id"]: r for r in observations if r["kind"] == "territory" and r["date"] == DATE and r["source_id"].startswith("ft_world_")}
    endpoints = {(r["unit_id"], r["date"]): r["population_value"] for r in observations if r["source_id"].startswith("ft_world_")}
    selected = defaultdict(list)
    series_files = ["opening_series.tsv"]
    if version >= 2:
        series_files.append("opening_series_v2.tsv")
    if version >= 5:
        series_files.append("opening_series_v5.tsv")
    for file in series_files:
        with (HERE / file).open(encoding="utf8") as f:
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
    if version >= 2:
        files = [path.with_name("india_opening_v2.json") if path.name == "india_opening.json" else path for path in files]
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
    result["qing_empire"] = qing_interior(observations, version)
    if version >= 2:
        fiji = fiji_and_rotuma(observations)
        result[fiji["unit_id"]] = fiji
    if version >= 3:
        for group in (egypt_two_cities(observations), natal_and_zululand(observations)):
            root = group["unit_id"]
            if root in result:
                raise ValueError(f"two production partitions for {root}")
            result[root] = group
    if version >= 4:
        cape = cape_colony(observations)
        if cape["unit_id"] in result:
            raise ValueError("duplicate Cape population control")
        result[cape["unit_id"]] = cape
        add_java_and_madura(result["cshapes_gw_850"], observations)
    if version >= 5:
        zanzibar = zanzibar_protectorate(observations)
        if zanzibar["unit_id"] in result:
            raise ValueError("duplicate Zanzibar population control")
        result[zanzibar["unit_id"]] = zanzibar
    ids = set()
    for root, group in result.items():
        group.setdefault("population_lower",None)
        group.setdefault("population_upper",None)
        group.setdefault("uncertainty_kind","Enumeration coverage and interpolation error have no quantified interval.")
        children = group["units"]
        for child in children:
            child.setdefault("population_lower",None)
            child.setdefault("population_upper",None)
        if children and sum(x["population_value"] for x in children) != located_people(group):
            raise ValueError(f"non-closing opening partition {root}")
        for key in [root]+[x["unit_id"] for x in children]:
            if key in ids:
                raise ValueError(f"duplicate population unit {key}")
            ids.add(key)
    return [result[key] for key in sorted(result)]
