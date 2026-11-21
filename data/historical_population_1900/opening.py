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


def apportion(values, total):
    """Round individual exact quotas to a fixed, independently selected control."""
    quotas = {key: int(value) for key, value in values.items()}
    extra = total - sum(quotas.values())
    if not 0 <= extra <= len(quotas):
        raise ValueError(f"Cannot reconcile exact quotas to {total}")
    order = sorted(values, key=lambda key: (quotas[key] - values[key], key))
    for key in order[:extra]:
        quotas[key] += 1
    return quotas


def allocate_census_shares(observations, *, source_id, observed_date, observed_root, control_source,
                           control_value, scope, uncertainty, places, kinds=("admin",)):
    rows = [row for row in observations if row["source_id"] == source_id and row["date"] == observed_date
            and row["parent_id"] == observed_root["unit_id"] and row["kind"] in kinds]
    denominator = observed_root["population_value"]
    if len({row["unit_id"] for row in rows}) != len(rows) or sum(row["population_value"] for row in rows) != denominator:
        raise ValueError(f"Non-closing source partition for {observed_root['unit_id']}")
    weights = {row["unit_id"]: Fraction(control_value * row["population_value"], denominator) for row in rows}
    allocated = apportion(weights, control_value)
    method = (f"Allocate the selected opening control of {control_value:,} by the shares in the published "
              f"{observed_date} statistical control of {denominator:,}. Integer people use largest remainders.")
    return [dict(
        unit_id=row.get("wwo_id") or row["unit_id"], name=row["name"], population_value=allocated[row["unit_id"]],
        source_id=source_id, control_source_id=control_source, source_unit_ids=[row["unit_id"]],
        source_dates=[observed_date], source_observations=[row["record_id"], observed_root["record_id"]],
        observed_value=row["population_value"], observed_control_value=denominator, locator=row["locator"],
        method=method, scope=scope, uncertainty_kind=uncertainty, place_ids=places.get(row["unit_id"], []),
    ) for row in rows]


def interpolate_partition(rows, parent, dates):
    partition = defaultdict(dict)
    for row in rows:
        if row["date"] in dates:
            series = partition[row["unit_id"]]
            if row["date"] in series:
                raise ValueError(f"Duplicate endpoint for {row['unit_id']} on {row['date']}")
            series[row["date"]] = row
    for census_date, control in zip(dates, parent["endpoint_values"]):
        if sum(series[census_date]["population_value"] for series in partition.values()) != control:
            raise ValueError(f"Non-closing source partition for {parent['unit_id']} on {census_date}")
    first, last = map(date.fromisoformat, dates)
    fraction = Fraction((date.fromisoformat(DATE) - first).days, (last - first).days)
    observed = {unit: [series[d] for d in dates] for unit, series in partition.items()}
    values = {unit: [row["population_value"] for row in rows] for unit, rows in observed.items()}
    allocations = apportion(
        {unit: a + (b - a) * fraction for unit, (a, b) in values.items()},
        parent["population_value"],
    )
    return [dict(
        unit_id=unit, name=rows[0]["name"], population_value=allocations[unit],
        subdivision_of=parent["unit_id"], source_id=rows[0]["source_id"], source_unit_ids=[unit],
        source_dates=dates, source_observations=[row["record_id"] for row in rows],
        endpoint_values=values[unit], locator=rows[0]["locator"], scope=rows[0]["definition"],
        method=f"Linear daily interpolation, elapsed fraction {fraction}. Integer people use largest remainders within {parent['name']}.",
        uncertainty_kind="Enumeration coverage and interpolation error have no quantified interval.",
        place_ids=[],
    ) for unit, rows in observed.items()]


def add_british_county_partitions(group, observations):
    scotland_id = "administrative_region:uk_constituent_scotland"
    ireland_id = "administrative_region:uk_constituent_ireland"
    controls = {row["unit_id"]: row for row in group["units"] if row["unit_id"] in (scotland_id, ireland_id)}
    dates = group["endpoint_dates"]
    county_returns = [r for r in observations if r["source_id"] == "scotland_civil_counties_census_1901"
                      and r["parent_id"] == "uk_scotland"]
    counties = interpolate_partition(county_returns, controls[scotland_id], dates)
    source = "ireland_general_census_1911"
    province_returns = [r for r in observations if r["source_id"] == source and r["parent_id"] == "uk_ireland"]
    province_estimates = interpolate_partition(province_returns, controls[ireland_id], dates)
    province_observations = {row["record_id"]: row for row in province_returns}
    for province in province_estimates:
        count = province_observations[province["source_observations"][-1]]
        children = allocate_census_shares(
            observations, source_id=source, observed_date=dates[-1], observed_root=count,
            control_source=source, control_value=province["population_value"], places={},
            scope=("Administrative counties and separately counted county boroughs in the 1911 report's "
                   "1901 comparison geography. The two Tipperary ridings form one reporting unit."),
            uncertainty=("No quantitative county interval. The 1901 proportions are used at the opening "
                         "date within the same interpolated census province. Earlier changes in county "
                         "and borough shares and differences from the opening-date boundaries are unquantified."),
            kinds=("admin", "city"),
        )
        for child in children:
            child.update(
                subdivision_of=ireland_id, share_source_unit_id=province["unit_id"],
                province_endpoint_values=province["endpoint_values"],
                province_source_observations=province["source_observations"],
            )
            child["method"] = province["method"] + " " + child["method"]
        counties.extend(children)
    group["units"] = [row for row in group["units"] if row["unit_id"] not in controls] + counties
    group["subdivision_controls"] = list(controls.values())
    group["subdivision_sources"] = ["collections/scotland_civil_counties/observations.jsonl",
                                    "collections/britain/observations.jsonl"]
    group["method"] += (" Scottish civil counties use both census endpoints. The Irish administrative "
                        "counties and county boroughs use their 1901 shares within the interpolated provinces.")
    group["source_ids"] = [*group["source_ids"], "scotland_civil_counties_census_1901", source]


def add_australian_colonies(group, observations):
    source = "abs_historical_population_2021"
    dates = ["1899-12-31", "1900-12-31"]
    returns = [r for r in observations if r["source_id"] == source and r["date"] in dates]
    controls = {r["date"]: r for r in returns if r["unit_id"] == "abs_australia"}
    initial, final = (controls[d]["population_value"] for d in dates)
    span = (date.fromisoformat(dates[1]) - date.fromisoformat(dates[0])).days
    count = round(initial + Fraction(final - initial, span))
    basis = dict(unit_id=group["unit_id"], name="the six Australian colonies",
                 population_value=count, endpoint_values=[initial, final])
    units = interpolate_partition([r for r in returns if r["kind"] == "territory"], basis, dates)
    for unit in units:
        if unit["unit_id"] == "abs_south_australia":
            unit["scope"] += " Includes the Northern Territory."
        if unit["unit_id"] == "abs_new_south_wales":
            unit["scope"] += " Includes the territory of the later Australian Capital Territory."
    group["units"] = units
    group["subdivision_source"] = "collections/eastern/observations.jsonl"
    group["subdivision_control"] = dict(
        source_id=source, source_dates=dates, population_value=count, endpoint_values=[initial, final],
        source_observations=[controls[d]["record_id"] for d in dates],
        geography_reference="https://www.abs.gov.au/methodologies/historical-population-methodology/2021",
    )
    group["research_unlocated_balance"] = group["population_value"] - count
    group["scope"] += (" The ABS-counted population is separated by colony. The arithmetic balance between the "
                       "two historical series remains geographically unallocated. It cannot identify the size "
                       "or distribution of Aboriginal and Torres Strait Islander populations.")


def add_russian_provinces(group, observations):
    core, finland = group["units"]
    if core["unit_id"] != "ft_russia_empire_ussr" or finland["unit_id"] != "ft_finland":
        raise ValueError("Unexpected Russian research controls")
    census = next(row for row in observations if row["unit_id"] == "ru_census_1897_ex_finland")
    group["subdivision_source"] = "collections/russia/observations.jsonl"
    group["subdivision_control"] = core
    group["units"] = allocate_census_shares(
        observations, source_id="russia_first_census", observed_date=census["date"], observed_root=census,
        control_source=group["source_id"], control_value=core["population_value"],
        scope=("Persons allocated to the provincial and oblast reporting scopes of the 1897 de facto census. "
               "Finland is a separate opening unit. The protectorates of Khiva and Bukhara are outside these shares."),
        uncertainty=("No quantitative opening provincial interval. The shares assume common proportional growth "
                     "between census and opening. Differential growth, migration and boundary changes are unquantified."),
        places={"ru1897_24": ["place:moscow"], "ru1897_37": ["place:st_petersburg"]},
    ) + [finland]


def add_japanese_prefectures(group, observations):
    source_id = "jp_cabinet_1909_resident_prefectures"
    prior_night = "1899-12-31"
    register = next(row for row in observations if row["source_id"] == source_id and row["date"] == prior_night
                    and row["unit_id"] == "japan_proper_otsu")
    group["subdivision_source"] = "collections/japan_taiwan/observations.jsonl"
    group["units"] = allocate_census_shares(
        observations, source_id=source_id, observed_date=prior_night, observed_root=register,
        control_source=group["source_id"], control_value=group["population_value"],
        scope=("The home-island opening total is split across the 47 contemporary prefectural reporting scopes. "
               "Weights represent estimated residents in the Japanese register (乙種). Taiwan is excluded."),
        uncertainty=("No quantitative prefectural interval. The published register rounds to hundreds and excludes "
                     "foreigners outside the register. Relative shares are applied to the distinct opening control. "
                     "There is no separate foreign resident allocation."),
        places={"jp_otsu_pref_tokyo": ["place:tokyo"], "jp_otsu_pref_kanagawa": ["place:yokohama"]},
    )


def add_india_comparable_areas(group, observations):
    areas = {
        2: ("raj_andaman_nicobar_comparable", "Andaman and Nicobar Islands", "The comparable return excludes Indigenous islanders first enumerated in 1901."),
        3: ("raj_assam_comparable", "Assam", "Manipur and the newly enumerated part of the Lushai Hills are outside this comparable return."),
        7: ("raj_burma_comparable", "Burma", "Shan States, Chin Hills and other newly enumerated fringe areas are outside this comparable return."),
        11: ("raj_punjab_comparable", "Punjab and Northwest frontier", "The table combines Punjab with the later North-West Frontier Province on a shared 1891 enumeration extent. Newly enumerated tracts and the separately tabulated Punjab States are excluded."),
    }
    source = group["source_id"]
    returns = {row["unit_id"]: row for row in observations if row["source_id"] == source and row["date"] == DATE}
    added = []
    for n, (unit, name, scope) in areas.items():
        row = returns[f"raj_comparable_row_{n:02}"]
        added.append(dict(
            unit_id=unit, name=name + " (common census area)", source_unit_ids=[row["unit_id"]],
            population_value=row["population_value"], endpoint_values=row["endpoint_values"],
            source_dates=row["source_dates"], source_observations=[row["record_id"]], locator=row["locator"],
            scope=scope, uncertainty_kind="No quantified interval. The boundary and timing of omitted enumeration remain unknown.",
            place_ids=[],
        ))
    group["units"].extend(added)
    group["units"].sort(key=lambda row: row["unit_id"])
    group["legacy_unlocated_balance"] -= sum(row["population_value"] for row in added)
    balance = group["balance_basis"]
    held_out = [row for row in balance["comparable_rows_left_out"] if row["source_unit_id"] not in {
        leaf["source_unit_ids"][0] for leaf in added
    }]
    balance.update(
        comparable_area_minus_admitted=balance["comparable_area_excluding_aden"] - located_people(group),
        comparable_rows_left_out=held_out,
        comparable_rows_left_out_total=sum(row["population_value"] for row in held_out),
    )


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


def zanzibar_protectorate(observations, version):
    returns = [r for r in observations if r["unit_id"] == "zanzibar_protectorate"]
    estimate = next(row for row in returns if row["source_id"] == "zanzibar_statesmans_year_book_1899")
    group = dict(
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
    if version >= 10:
        islands = estimate["breakdowns"]["reported_island_estimates"]
        group["units"] = [
            dict(unit_id="zanzibar_" + key, name=name, population_value=islands[key],
                 source_id=estimate["source_id"], source_unit_ids=[estimate["unit_id"]],
                 source_dates=[estimate["date"]], source_observations=[estimate["record_id"]],
                 locator=estimate["locator"], method=group["method"],
                 scope=f"{name} and its administratively dependent islets.",
                 uncertainty_kind="Reference date, foreign-resident treatment and estimation error are unquantified.",
                 place_ids=[])
            for key, name in (("unguja", "Unguja"), ("pemba", "Pemba"))
        ]
        group["uncertainty_kind"] = "No statistical interval. Later census and earlier estimates have different dates."
    return group


def bosnia_herzegovina(observations):
    unit = "statistical_area:bosnia_herzegovina_1900"
    before = next(row for row in observations if row["unit_id"] == unit and row["date"] == "1895-04-22"
                  and row["source_id"] == "bosnia_herzegovina_demography_2024")
    after = next(row for row in observations if row["unit_id"] == unit and row["date"] == "1910-10-10"
                 and row["source_id"] == "bosnia_herzegovina_admin_population_1910")
    start, end = (date.fromisoformat(row["date"]) for row in (before, after))
    fraction = Fraction((date.fromisoformat(DATE) - start).days, (end - start).days)
    initial, final = (row["population_value"] for row in (before, after))
    return dict(
        unit_id=unit, date=DATE, population_value=round(initial + (final - initial) * fraction),
        source_id=after["source_id"], source_observations=[before["record_id"], after["record_id"]],
        locator=before["locator"] + " / " + after["locator"],
        endpoint_dates=[before["date"], after["date"]], country_endpoint_values=[initial, final],
        partition_source="collections/bosnia_herzegovina_population/observations.jsonl",
        method=f"Linear daily interpolation between civilian present-population census controls, elapsed fraction {fraction}.",
        scope="Common province total for occupied Bosnia and Herzegovina. The censuses exclude active military from this civilian series. Novi Pazar is outside the civil administration. The map displays two units; no separate population is assigned to either one.",
        uncertainty_kind="No statistical interval. Reported province area changes from 51,246 to 51,200 square kilometres. Enumeration and temporal model error are unquantified. No district or map-boundary equivalence is assumed.",
        collective_scope=dict(name="波斯尼亚和黑塞哥维那占领区合计", polity_ids=["cshapes_gw_3461", "cshapes_gw_3462"]),
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
    if version >= 7:
        revised = path.with_name("qing_interior_v7_crosswalk.tsv")
        by_unit = {link["unit_id"]: link for link in links}
        with revised.open(encoding="utf8") as f:
            by_unit.update((link["unit_id"], link) for link in csv.DictReader(f, delimiter="\t"))
        links = list(by_unit.values())
    if version >= 8:
        expanded = path.with_name("qing_interior_v8_crosswalk.tsv")
        with expanded.open(encoding="utf8") as f:
            links.extend(csv.DictReader(f, delimiter="\t"))
    if version >= 10:
        additions = path.with_name("qing_interior_v10_crosswalk.tsv")
        with additions.open(encoding="utf8") as f:
            links.extend(csv.DictReader(f, delimiter="\t"))
    leaves = []
    for link in links:
        row = by_id[link["unit_id"]]
        leaf = dict(unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
            source_id=row["source_id"], locator=row["locator"], source_observation=row["record_id"],
            source_quality=row["quality"], source_unit_ids=[row["unit_id"]], endpoint_values=row["endpoint_values"],
            wwo_admin_label=link["wwo_admin_label"], chgis_id=link["chgis_territory"], chgis_url=link["gazetteer"],
            geography_valid_years=[int(link["valid_from_year"]), int(link["valid_to_year"])],
            scope=link["study_scope"], place_ids=[])
        if deduction := link.get("deduct_source_unit"):
            by_date = {o["date"]: o for o in observations if o["unit_id"] == deduction}
            subtract = [by_date[when] for when in row["source_dates"]]
            first, last = (total - part["population_value"]
                           for total, part in zip(row["endpoint_values"], subtract, strict=True))
            leaf.update(name="Fujian excluding Cao's Taiwan component",
                endpoint_values=[first, last], population_value=round(first + (last-first)*Fraction(row["fraction"])),
                deductions=[dict(source_id=o["source_id"], record_id=o["record_id"], date=o["date"],
                    population_value=o["population_value"], locator=o["locator"]) for o in subtract],
                method="Subtract Cao's Taiwan component at both endpoints before daily interpolation. Round once.")
        if version >= 10:
            leaf["uncertainty_kind"] = "No calibrated interval. See the source reconstruction and scope note."
        leaves.append(leaf)
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
    if version >= 7:
        group["revised_partition_source"] = revised.relative_to(HERE).as_posix()
    if version >= 8:
        group["expanded_partition_source"] = expanded.relative_to(HERE).as_posix()
    if version >= 10:
        group["additional_territorial_source"] = additions.relative_to(HERE).as_posix()
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
    if version >= 6:
        series_files.append("opening_series_v6.tsv")
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
        zanzibar = zanzibar_protectorate(observations, version)
        if zanzibar["unit_id"] in result:
            raise ValueError("duplicate Zanzibar population control")
        result[zanzibar["unit_id"]] = zanzibar
    if version >= 6:
        bosnia = bosnia_herzegovina(observations)
        result[bosnia["unit_id"]] = bosnia
    if version >= 10:
        add_australian_colonies(result["australia_colonies_1900"], observations)
        add_british_county_partitions(result["british_isles_1900"], observations)
        add_russian_provinces(result["russian_empire"], observations)
        add_japanese_prefectures(result["empire_of_japan"], observations)
        add_india_comparable_areas(result["cshapes_gw_750"], observations)
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
