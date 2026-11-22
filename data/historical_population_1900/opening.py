"""Select disjoint inputs for the existing population authority. Evidence stays immutable."""
import csv
import json
from collections import defaultdict
from datetime import date
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATE = "1900-01-01"
ENGLAND_WALES_OCCUPATION_REMAINDER = "uk_england_wales_except_anglesey"
EGYPT_COMPARABLE_PROVINCES = "egypt_census_1907_comparable_provinces"
EGYPT_FAIYUM_SOURCES = {"egypt_faiyum_census_1897", "egypt_faiyum_census_1907"}
ITALIAN_CIVIL_STATUS_SCOPE = "it_1901_civil_status_scope"
SPANISH_CIVIL_STATUS_SCOPE = "es_1900_civil_status_scope"
AGRA_DISTRICT_SOURCE = "india_agra_census_1901_districts"
AGRA_DISTRICT_BALANCE = "raj_agra_unlocated_table_ii_a"
BENGAL_DISTRICT_SOURCE = "india_bengal_census_1901_districts"
BENGAL_DISCREPANCY = "raj_bengal_unlocated_comparison"
BOMBAY_DISTRICT_SOURCE = "india_bombay_census_1901_districts"
MADRAS_STATES_REMAINDER = "raj_madras_states_ex_cochin_travancore"
MADRAS_STATES_AGE_SOURCE = "india_madras_1901_princely_age_and_religion"

def sourced_people(group):
    return group["population_value"] - group.get("legacy_unlocated_balance", 0)

def located_people(group):
    return sourced_people(group) - group.get("research_unlocated_balance", 0)


def geographic_partitions(group):
    return [unit for unit in group["units"] if not unit.get("geographically_unlocated")]


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


def opening_fraction(dates):
    first, last = map(date.fromisoformat, dates)
    return Fraction((date.fromisoformat(DATE) - first).days, (last - first).days)


def interpolate_partition(rows, parent, dates, *, normalize=False):
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
    fraction = opening_fraction(dates)
    observed = {unit: [series[d] for d in dates] for unit, series in partition.items()}
    values = {unit: [row["population_value"] for row in rows] for unit, rows in observed.items()}
    quotas = {unit: a + (b - a) * fraction for unit, (a, b) in values.items()}
    method = f"Linear daily interpolation, elapsed fraction {fraction}."
    if normalize:
        scaling = Fraction(parent["population_value"], sum(quotas.values()))
        quotas = {unit: quota * scaling for unit, quota in quotas.items()}
        method += " Normalize interpolated regional shares to the independent national opening control."
    allocations = apportion(quotas, parent["population_value"])
    return [dict(
        unit_id=unit, name=rows[0]["name"], population_value=allocations[unit],
        subdivision_of=parent["unit_id"], source_id=rows[0]["source_id"], source_unit_ids=[unit],
        source_dates=dates, source_observations=[row["record_id"] for row in rows],
        endpoint_values=values[unit], locator=rows[0]["locator"], scope=rows[0]["definition"],
        method=f"{method} Integer people use largest remainders within {parent['name']}.",
        uncertainty_kind="Enumeration coverage and interpolation error have no quantified interval.",
        place_ids=[],
    ) for unit, rows in observed.items()]


FR_ARRONDISSEMENT_PLACES = {
    "place:marseille": "133",
    "place:port_marseille": "133",
    "place:brest": "291",
    "place:port_brest": "291",
    "place:toulouse": "313",
    "place:bordeaux": "332",
    "place:port_bordeaux": "332",
    "place:nantes": "442",
    # Calais belonged to the Boulogne-sur-Mer arrondissement.
    "place:calais": "623",
    "place:port_calais": "623",
    "place:lyon": "691",
    "place:paris": "751",
    "place:le_havre": "762",
    "place:port_le_havre": "762",
    "place:rouen": "763",
}


def add_french_arrondissements(group, observations):
    dates = group["endpoint_dates"]
    prefix = "administrative_region:france_arrondissement_"
    references = defaultdict(dict)
    endpoints = defaultdict(list)
    for row in observations:
        if row["source_id"] != group["source_id"] or row.get("administrative_level") != 2:
            continue
        department, unit = row["parent_id"], row["unit_id"]
        if row.get("wwo_id") != unit or not unit.startswith(prefix):
            continue
        if row["date"] in dates:
            endpoints[department].append(row)
        elif row["date"] == DATE and row["method"] == "linear_daily_interpolation_within_department":
            if unit in references[department] or row["control_unit_id"] != department:
                raise ValueError(f"Invalid opening arrondissement reference {unit}")
            references[department][unit] = row

    units = []
    aggregates = []
    for department in group["units"]:
        parent = department["unit_id"]
        if parent not in references:
            units.append(department)
            continue

        children = interpolate_partition(endpoints[parent], department, dates)
        expected = references.pop(parent)
        if {child["unit_id"] for child in children} != expected.keys():
            raise ValueError(f"Arrondissement endpoint coverage differs from opening references for {parent}")

        by_id = {child["unit_id"]: child for child in children}
        for place in department["place_ids"]:
            target = FR_ARRONDISSEMENT_PLACES.get(place)
            if target is None or (prefix + target) not in by_id:
                raise ValueError(f"Missing arrondissement residence binding for {place} in {parent}")
            by_id[prefix + target]["place_ids"].append(place)

        for child in children:
            evidence = expected[child["unit_id"]]
            if (child["population_value"] != evidence["population_value"]
                    or department["population_value"] != evidence["control_population_value"]):
                raise ValueError(f"Arrondissement opening differs from the archived reconstruction for {child['unit_id']}")
            child.update(
                statistical_parent=parent,
                date=DATE,
                locator=evidence["locator"],
                reconstruction_observation=evidence["record_id"],
                uncertainty_kind=evidence["quality_note"],
            )
        aggregates.append(dict(
            unit_id=parent, name=department["name"], population_value=department["population_value"],
            source_id=group["source_id"], locator=department["locator"],
            method="Sum of reconciled arrondissement opening estimates within the interpolated département control.",
            date=DATE, scope=next(iter(expected.values()))["definition"],
            population_lower=None, population_upper=None,
            uncertainty_kind="Enumeration coverage and interpolation error have no quantified interval.",
            endpoint_dates=dates, endpoint_values=department["endpoint_values"],
        ))
        units.extend(children)

    if references:
        raise ValueError(f"Arrondissement references have no département control: {sorted(references)}")
    group["units"] = units
    group["statistical_aggregates"] = aggregates
    group["method"] += (
        "; reconciled arrondissement leaves replace the département pool wherever the census partition closes."
    )


def add_british_county_partitions(group, observations, *, version):
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
    if version >= 27:
        for county in counties:
            county["statistical_parent"] = county["subdivision_of"]
        group.setdefault("statistical_aggregates", []).extend(
            control | dict(
                date=DATE, source_id=group["source_id"], endpoint_dates=dates,
                method="Sum of the disjoint historical county and borough opening balances.",
                uncertainty_kind="Within-constituent population change and census coverage are unquantified.",
            )
            for control in controls.values()
        )
    group["subdivision_sources"] = ["collections/scotland_civil_counties/observations.jsonl",
                                    "collections/britain/observations.jsonl"]
    group["method"] += (" Scottish civil counties use both census endpoints. The Irish administrative "
                        "counties and county boroughs use their 1901 shares within the interpolated provinces.")
    group["source_ids"] = [*group["source_ids"], "scotland_civil_counties_census_1901", source]


def add_england_wales_statistical_scope(group, observations):
    unit_id = "uk_england_wales"
    population_source = "uk_general_census_report_1901"
    county_source = "england_wales_summary_tables_1901"
    dates = group["endpoint_dates"]
    controls = {
        row["date"]: row for row in observations
        if row["unit_id"] == unit_id and row["source_id"] == population_source
        and row["date"] in dates
    }
    counties = [unit for unit in group["units"] if unit.get("source_id") == county_source]
    endpoints = [controls[census_date]["population_value"] for census_date in dates]
    if not counties or any(unit.get("statistical_parent") for unit in counties):
        raise ValueError("Invalid statistical members for England and Wales")
    county_totals = [sum(unit["endpoint_values"][i] for unit in counties) for i in range(len(dates))]
    if county_totals != endpoints:
        raise ValueError("England and Wales county returns do not close to the census division")
    anglesey = next(unit for unit in counties if unit["unit_id"] == "administrative_region:gb_historic_anglesey")
    rest = [unit for unit in counties if unit is not anglesey]
    for unit in rest:
        unit["statistical_parent"] = ENGLAND_WALES_OCCUPATION_REMAINDER
    group.setdefault("statistical_aggregates", []).append(dict(
        unit_id=ENGLAND_WALES_OCCUPATION_REMAINDER, name="England and Wales except Anglesey",
        population_value=sum(unit["population_value"] for unit in rest),
        source_id=population_source, locator=controls[dates[-1]]["locator"],
        method="Sum of the mutually exclusive opening balances of the ancient-county groups excluding Anglesey.",
        date=DATE, scope=controls[dates[-1]]["definition"] + " Excludes Anglesey, a separately assigned ancient county.",
        endpoint_dates=dates, endpoint_values=[total - local for total, local in zip(endpoints, anglesey["endpoint_values"])],
        population_lower=None, population_upper=None,
        uncertainty_kind="Census coverage and the opening date interpolation have no quantified interval.",
    ))


def add_mauritius_districts(group, observations):
    islands = {row["unit_id"]: row for row in group["units"]}
    island = islands["mu_main_island"]
    rodrigues = islands["mu_rodrigues"]
    dates = ["1891-04-06", "1901-04-01"]
    sources = ["mauritius_census_1891", "mauritius_census_1911_district_comparison"]
    returns = [row for row in observations if row["source_id"] in sources]
    district_returns = [row for row in returns if row["parent_id"] == island["unit_id"]]
    fraction = opening_fraction(dates)
    island_first, island_last = island["endpoint_values"]
    island["population_value"] = round(island_first + (island_last - island_first) * fraction)
    districts = interpolate_partition(district_returns, island, dates)
    for district in districts:
        district["source_ids"] = sources
    rodrigues_returns = {row["date"]: row for row in returns if row["unit_id"] == rodrigues["unit_id"]}
    rodrigues_first, rodrigues_last = (rodrigues_returns[day]["population_value"] for day in dates)
    method = (f"Linear daily interpolation over elapsed fraction {fraction} between the original census "
              "enumeration dates. Each island rounded to a whole person.")
    rodrigues.update(
        population_value=round(rodrigues_first + (rodrigues_last - rodrigues_first) * fraction),
        endpoint_values=[rodrigues_first, rodrigues_last], source_id=sources[0], source_ids=sources, source_dates=dates,
        source_observations=[rodrigues_returns[day]["record_id"] for day in dates],
        locator="1891 census, paragraph 50; 1911 census, section II, Rodrigues row for 1901.",
        method=method, scope=rodrigues_returns[dates[0]]["definition"],
    )
    island_locator = "1891 census, paragraph 1; 1911 census, Statistical Abstracts, Table I."
    group["units"] = districts + [rodrigues]
    group["subdivision_control"] = dict(island, source_ids=sources, source_dates=dates, locator=island_locator)
    group["subdivision_source"] = "collections/mauritius_districts/observations.jsonl"
    group["source_id"] = sources[0]
    group["source_ids"] = sources
    group["endpoint_dates"] = dates
    group["country_endpoint_values"] = [island_first + rodrigues_first, island_last + rodrigues_last]
    group["population_value"] = island["population_value"] + rodrigues["population_value"]
    group["locator"] = island_locator + " Rodrigues is reported separately in paragraph 50 and section II."
    group["method"] = method + " Districts use largest remainders to match the opening count of the main island."
    group["scope"] = ("Mauritius and its nearby census islets, plus Rodrigues. The district totals exclude "
                      "barracks, shipping and other separately reported dependencies.")


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


def add_russian_districts(group, observations):
    continuity_path = HERE / "collections/russia_1900_districts/continuity.json"
    districts = json.loads(continuity_path.read_text(encoding="utf8"))
    source = "russia_first_census"
    census = {row["unit_id"]: row for row in observations if row["source_id"] == source}
    units = []
    aggregates = []
    for province in group["units"]:
        parent = province["unit_id"]
        observed = next(iter(province.get("source_unit_ids", ())), None)
        if observed not in districts:
            units.append(province)
            continue
        boundary = districts.pop(observed)
        if province["place_ids"]:
            raise ValueError(f"District split requires explicit placement for {parent}")
        control = census[observed]
        children = allocate_census_shares(
            observations, source_id=source, observed_date=control["date"], observed_root=control,
            control_source=province["source_id"], control_value=province["population_value"], places={},
            scope="Full uezd census areas, including the cities enumerated within each uezd.",
            uncertainty="District identities are attested in 1900. Within-province shares are from 1897. "
                        "The effects of differential growth, migration and local boundary changes are unquantified.",
        )
        if len(children) != boundary["district_count"] or any(child["unit_id"] == child["source_unit_ids"][0] for child in children):
            raise ValueError(f"District census identity coverage differs for {parent}")
        for sex in ("male", "female"):
            if sum(census[child["source_unit_ids"][0]]["sex"][sex] for child in children) != control["sex"][sex]:
                raise ValueError(f"District census sex totals differ for {parent}")
        for child in children:
            child.update(statistical_parent=parent, date=DATE, district_boundary_source=boundary["source_id"],
                         locator=f"{child['locator']}; 1900 identity: {boundary['locator']}")
        aggregates.append(province | dict(date=DATE, method=(province["method"] + " Sum the resulting uezd opening balances.")))
        units.extend(children)
    if districts:
        raise ValueError(f"Unmatched opening controls for Russian districts: {sorted(districts)}")
    group["units"] = units
    group["statistical_aggregates"] = aggregates



def add_hungarian_crown_counties(group, observations):
    dates = dict(zip(group["census_date_labels"], group["endpoint_dates"]))
    counties_by_parent = defaultdict(list)
    for row in observations:
        if row["source_id"] == "ah_hungarian_counties_1900":
            counties_by_parent[row["parent_id"]].append(row | dict(date=dates[row["date"]]))

    units = []
    aggregates = []
    for parent in group["units"]:
        parent_id = parent["unit_id"]
        if parent_id not in counties_by_parent:
            units.append(parent)
            continue
        if parent["place_ids"]:
            raise ValueError(f"County split requires explicit places for {parent_id}")

        children = interpolate_partition(counties_by_parent.pop(parent_id), parent, group["endpoint_dates"])
        for county in children:
            county.update(statistical_parent=parent_id, date=DATE)
        units.extend(children)
        aggregates.append(parent | dict(
            date=DATE, endpoint_dates=group["endpoint_dates"],
            method="Sum the non-overlapping historical county and municipal opening balances.",
            scope=children[0]["scope"],
        ))

    if counties_by_parent or not aggregates:
        raise ValueError(f"Unmatched or missing Hungarian county opening controls: {sorted(counties_by_parent)}")
    group["units"] = units
    group["statistical_aggregates"] = aggregates


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


def taiwan_opening(study, observations, endpoints):
    root = "taiwan_under_japan"
    source = "tw_governor_general_1900"
    date_of_return = "1899-12-31"
    rows = {row["unit_id"]: row for row in observations
            if row["source_id"] == source and row["date"] == date_of_return}
    official = rows["tw_register_total"]
    foreign = rows["tw_foreign_taiwan"]
    places = [row for row in rows.values() if row["parent_id"] == official["unit_id"] and row["kind"] == "admin"]
    registered = sum(row["population_value"] for row in places)
    if len(places) != 6 or registered != official["population_value"]:
        raise ValueError("Taiwan's six official administrations do not close to the register")
    total = study["population_value"]
    balance = total - registered
    if balance < foreign["population_value"]:
        raise ValueError("Taiwan's opening balance cannot accommodate the separate foreign register")
    method = "Carry the separate December 31 register count straight to the midnight opening."
    return dict(
        unit_id=root, date=DATE, source_id=study["source_id"], population_value=total,
        population_lower=study["population_lower"], population_upper=study["population_upper"],
        research_unlocated_balance=balance, research_unit_ids=[study["unit_id"]],
        source_observations=[study["record_id"], official["record_id"], foreign["record_id"]],
        locator=study["locator"] + "; " + study["method_locator"] + "; Taiwan registers, Tables XVII and XL",
        endpoint_dates=study["source_dates"],
        country_endpoint_values=[endpoints[(study["unit_id"], date)] for date in study["source_dates"]],
        method=study["method"] + ". Six administrative balances use the contemporary register; other residents remain unlocated.",
        scope="Taiwan and Penghu under Japanese administration. Separate from the Japanese home islands and the Qing control.",
        uncertainty_kind=study["uncertainty_kind"] + ". The unlocated balance includes "
                         f"{foreign['population_value']:,} separately registered foreign residents without a same-date locality split. "
                         "The remaining difference is between independent sources. The administrative register excludes troops and unsurveyed places.",
        partition_source="collections/japan_taiwan/observations.jsonl",
        units=[dict(
            unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
            source_id=source, date=date_of_return, source_dates=[date_of_return],
            source_observations=[row["record_id"], official["record_id"]], source_unit_ids=[row["unit_id"]],
            locator=row["locator"], scope=row["definition"], method=method, place_ids=[],
            uncertainty_kind="No margin of error is published for the people covered by the register.",
        ) for row in places],
    )


def netherlands_opening(previous, observations):
    source = "nl_cbs_census_1899_age_marital"
    national_id = "nl1899_nl1000"
    returns = [row for row in observations if row["source_id"] == source and row["date"] == DATE]
    national = next(row for row in returns if row["unit_id"] == national_id)
    provinces = [row for row in returns if row["parent_id"] == national_id and row["kind"] == "admin"]
    balance = national["population_value"] - sum(row["population_value"] for row in provinces)
    if len(provinces) != 11 or balance != 158:
        raise ValueError("The Dutch provinces and unassigned residents must match the national census")
    method = "Use the published usual-residence census at the midnight opening, without extrapolation."
    places = {"nl1899_pv2700": ["place:amsterdam"]}
    return dict(
        unit_id=previous["unit_id"], date=DATE, source_id=source,
        population_value=national["population_value"], locator=national["locator"],
        method=method, scope=national["definition"],
        uncertainty_kind="Census coverage error has no published interval. The 158 residents outside municipal totals have no opening provincial allocation.",
        research_unit_ids=previous["research_unit_ids"], alternative_research_value=previous["population_value"],
        research_unlocated_balance=balance, source_observations=[national["record_id"]],
        partition_source="collections/netherlands_census_1899/observations.jsonl",
        units=[dict(
            unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
            locator=row["locator"], source_id=source, method=method, scope=row["definition"],
            source_dates=[DATE], source_observations=[row["record_id"]], place_ids=places.get(row["unit_id"], []),
        ) for row in provinces],
    )


def add_nordic_population_controls(group, observations):
    sources = {
        "ft_sweden": ("se_scb_population_tab5890", "1899-12-31"),
        "ft_norway": ("no_ssb_population_10211", DATE),
    }
    counts = {row["unit_id"]: row for row in observations
              if sources.get(row["unit_id"]) == (row["source_id"], row["date"])}
    leaves = []
    for previous in group["units"]:
        row = counts[previous["unit_id"]]
        leaves.append(dict(
            unit_id=row["unit_id"], name=row["name"], population_value=row["population_value"],
            date=DATE, source_id=row["source_id"], source_dates=[row["date"]],
            locator=row["locator"], scope=row["definition"], source_observations=[row["record_id"]],
            method="Use the published opening-time resident stock. No date interpolation is applied.",
        ))
    group.pop("endpoint_dates")
    group.pop("country_endpoint_values")
    group.update(
        alternative_research_value=group["population_value"],
        population_value=sum(row["population_value"] for row in leaves), units=leaves,
        source_id=sources["ft_sweden"][0], locator=" / ".join(row["locator"] for row in leaves),
        method="Sum Sweden's year-end 1899 registered population and Norway's reconstructed population at January 1, 1900.",
        scope="Sweden and Norway, separately tabulated within their political union.",
        population_lower=None, population_upper=None,
        uncertainty_kind="Registry coverage and Norway's reconstruction error have no quantified interval.",
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


def add_india_princely_states(group, observations):
    dates = group["endpoint_dates"]
    source = "india_census_1901_comparable_princely_states"
    parents = {
        "raj_central_india_agency": "raj_comparable_row_16",
        "raj_madras_states": "raj_comparable_row_20",
    }
    endpoints = defaultdict(list)
    for row in observations:
        if row["source_id"] == source:
            endpoints[row["parent_id"]].append(row)

    units = []
    aggregates = []
    for parent in group["units"]:
        parent_id = parent["unit_id"]
        if parent_id not in parents:
            units.append(parent)
            continue
        children = interpolate_partition(endpoints[parents[parent_id]], parent, dates)
        for child in children:
            child.update(
                statistical_parent=parent_id,
                date=DATE,
                uncertainty_kind="Enumeration coverage, the effects of famine and migration, and interpolation error have no quantified interval.",
            )
        aggregates.append(parent | dict(
            source_id=group["source_id"], endpoint_dates=dates, date=DATE,
            method="Sum of the mutually exclusive state and remainder opening estimates, reconciled to the interpolated agency control.",
            population_lower=None, population_upper=None,
            uncertainty_kind="Enumeration coverage, the effects of famine and migration, and interpolation error have no quantified interval.",
        ))
        units.extend(children)

    group["units"] = sorted(units, key=lambda row: row["unit_id"])
    group["statistical_aggregates"] = aggregates


def add_remaining_madras_states(group, observations):
    parent = next(unit for unit in group["units"] if unit["unit_id"] == MADRAS_STATES_REMAINDER)
    rows = [row for row in observations if row["parent_id"] == MADRAS_STATES_REMAINDER]
    children = interpolate_partition(rows, parent, group["endpoint_dates"])
    for child in children:
        child.update(statistical_parent="raj_madras_states", date=DATE,
                     source_ids=["india_madras_1941_princely_sex_comparison", MADRAS_STATES_AGE_SOURCE])
    group["units"] = sorted([unit for unit in group["units"] if unit is not parent] + children,
                            key=lambda row: row["unit_id"])


def add_italian_regions(group, observations):
    source = "it_1901_census_v5_age_and_marital"
    root = group["unit_id"]
    dates = ["1882-01-01", "1901-02-10"]
    rows = [row for row in observations if row["source_id"] == source and row["date"] in dates]
    totals = {row["date"]: row["population_value"] for row in rows if row["unit_id"] == root}
    parent = group | dict(endpoint_values=[totals[day] for day in dates], name="Kingdom of Italy")
    leaves = interpolate_partition([row for row in rows if row["parent_id"] == root], parent, dates, normalize=True)
    places = {"it_1901_lazio": ["place:rome"], "it_1901_lombardia": ["place:milan"],
              "it_1901_piemonte": ["place:turin"]}
    uncertainty = ("The 1882 count is published on the 1901 comparison geography. The long interval, "
                   "regional migration and the independent national control have no quantified regional error interval.")
    for leaf in leaves:
        leaf.update(statistical_parent=ITALIAN_CIVIL_STATUS_SCOPE, date=DATE,
                    place_ids=places.get(leaf["unit_id"], []), uncertainty_kind=uncertainty)
    group["units"] = sorted(leaves, key=lambda row: row["unit_id"])
    group["statistical_aggregates"] = [dict(
        unit_id=ITALIAN_CIVIL_STATUS_SCOPE, name="Kingdom of Italy (census civil status scope)",
        population_value=group["population_value"], date=DATE, source_id=source,
        locator="Vol. V, Table IV p. 24 and civil status pp. LXIV–LXV",
        method="Sum of the 17 disjoint census compartments at the January 1900 opening.",
        scope="Kingdom-wide census civil status; no separate compartment marriage counts are assigned.",
        uncertainty_kind=uncertainty,
    )]


def add_spanish_provinces(group, observations):
    sources = {"es_census_1897_provincial_population", "es_census_1900_provincial_population"}
    root = group["unit_id"]
    dates = ["1897-12-31", "1900-12-31"]
    rows = [row for row in observations if row["source_id"] in sources]
    totals = {row["date"]: row["population_value"] for row in rows if row["unit_id"] == root}
    parent = group | dict(endpoint_values=[totals[day] for day in dates], name="Kingdom of Spain")
    leaves = interpolate_partition([row for row in rows if row["parent_id"] == root], parent, dates, normalize=True)
    civil_sources = HERE / "collections/spain_census_1900/provincial_age_sources_1900.csv"
    with civil_sources.open(encoding="utf8", newline="") as stream:
        separately_reported = {row["panel"] for row in csv.DictReader(stream)}
    uncertainty = ("Provincial change within the census interval and the rescaling to the national "
                   "opening estimate have no quantified regional error interval.")
    for leaf in leaves:
        leaf.update(date=DATE, uncertainty_kind=uncertainty)
        if leaf["unit_id"] not in separately_reported:
            leaf["statistical_parent"] = SPANISH_CIVIL_STATUS_SCOPE
        leaf["locator"] = f"{leaf['locator']}; 1900 census, Vol. I, p. 323"
    group["units"] = sorted(leaves, key=lambda row: row["unit_id"])
    group["statistical_aggregates"] = [dict(
        unit_id=SPANISH_CIVIL_STATUS_SCOPE, name="Spain (remaining census civil status scope)",
        population_value=sum(leaf["population_value"] for leaf in leaves if "statistical_parent" in leaf),
        date=DATE, source_id="es_census_1900_age_marital",
        locator="Vol. III, pp. 64–65, 292–293 and 296–297",
        method="Sum of the provinces outside the independently assigned provincial civil status tables.",
        scope="Mainland and adjacent islands, excluding the nine provinces independently assigned civil status.",
        uncertainty_kind=uncertainty,
    )]


def add_indian_local_areas(group, observations, *, version):
    sources = {
        "raj_united_provinces_states": {"india_up_states_census_1901_table_2"},
        "raj_mysore_state": {"india_mysore_census_1901_report", "india_mysore_census_1901_talukwar_table_2"},
    }
    if version >= 24:
        sources["raj_agra_oudh"] = {
            "india_census_1901_comparable_area", "india_oudh_census_1901_districts",
        }
    rows = defaultdict(list)
    for observation in observations:
        parent_id = observation["parent_id"]
        if observation["source_id"] in sources.get(parent_id, ()) and observation["unit_id"] != "raj_mysore_western_division":
            rows[parent_id].append(observation)
    units = []
    dates = group["endpoint_dates"]
    uncertainty = "Enumeration coverage, famine, migration and interpolation error have no quantified interval."
    for parent in group["units"]:
        parent_id = parent["unit_id"]
        if parent_id not in sources:
            units.append(parent)
            continue
        children = interpolate_partition(rows[parent_id], parent, dates)
        for child in children:
            child.update(statistical_parent=parent_id, date=DATE, uncertainty_kind=uncertainty)
            if child["unit_id"] == "raj_oudh_lucknow":
                child["place_ids"] = ["place:lucknow"]
        units.extend(children)
        group["statistical_aggregates"].append(parent | dict(
            source_id=group["source_id"], date=DATE, endpoint_dates=dates,
            method="Sum of the disjoint local returns reconciled to the existing comparable-area opening control.",
            uncertainty_kind=uncertainty,
        ))
    group["units"] = sorted(units, key=lambda row: row["unit_id"])


def add_agra_districts(group, observations):
    parent = next(unit for unit in group["units"] if unit["unit_id"] == "raj_agra_remainder")
    rows = [row for row in observations if row["source_id"] == AGRA_DISTRICT_SOURCE
            or row["unit_id"] == AGRA_DISTRICT_BALANCE]
    dates = group["endpoint_dates"]
    places = {row["unit_id"]: row["place_ids"] for row in rows if row.get("place_ids")}
    children = interpolate_partition(rows, parent, dates)
    for child in children:
        child.update(statistical_parent="raj_agra_oudh", date=DATE, place_ids=places.get(child["unit_id"], []),
                     uncertainty_kind="The comparable district series uses March 1901 boundaries. January 1900 "
                                      "boundary changes, famine, migration and enumeration error have no quantified interval.")
        if child["unit_id"] == AGRA_DISTRICT_BALANCE:
            child["geographically_unlocated"] = True
    group["units"] = sorted([unit for unit in group["units"] if unit is not parent] + children,
                            key=lambda row: row["unit_id"])


def add_bengal_districts(group, observations):
    parent_id = "raj_bengal_province"
    parent = next(unit for unit in group["units"] if unit["unit_id"] == parent_id)
    dates = group["endpoint_dates"]
    rows = [row for row in observations if row["source_id"] == BENGAL_DISTRICT_SOURCE and row["parent_id"] == parent_id]
    endpoints = [71_346_961, 74_744_866]
    discrepancy = 26
    if (len(rows) != 96 or [value + discrepancy for value in endpoints] != parent["endpoint_values"]):
        raise ValueError("Bengal province and district census controls differ")
    province = parent | dict(
        population_value=parent["population_value"] - discrepancy,
        endpoint_values=endpoints, endpoint_dates=dates, date=DATE,
        source_id=BENGAL_DISTRICT_SOURCE, locator="Vol. VI-A, Table II, pp. 5–6, British Territory",
        method="Sum of the disjoint districts and city on March 1901 boundaries; the comparison discrepancy remains separate.",
        uncertainty_kind="Within-district movement and enumeration or interpolation errors have no quantified interval.",
    )
    children = interpolate_partition(rows, province, dates)
    places = {row["unit_id"]: row["place_ids"] for row in rows if row.get("place_ids")}
    for child in children:
        child.update(statistical_parent=parent_id, date=DATE, place_ids=places.get(child["unit_id"], []),
                     uncertainty_kind="January 1900 is estimated on March 1901 district jurisdiction. "
                                      "Other boundary, migration and enumeration changes are unquantified.")
    balance = dict(
        unit_id=BENGAL_DISCREPANCY, name="Bengal census comparison discrepancy",
        population_value=discrepancy, endpoint_values=[discrepancy, discrepancy], source_dates=dates,
        source_id=group["source_id"], source_ids=[group["source_id"], BENGAL_DISTRICT_SOURCE],
        locator="Vol. I-A, Table II-A, p. 10 and Bengal Vol. VI-A, Table II, pp. 5–6",
        scope="Net difference after transfers between Bengal, Agra and Assam in the comparable returns.",
        date=DATE, geographically_unlocated=True, place_ids=[],
        method="Retain the difference in the existing India opening control outside all provincial and local census profiles.",
        uncertainty_kind="This net accounting discrepancy has no independently identified inhabitants or age and sex distribution.",
    )
    group["units"] = sorted([unit for unit in group["units"] if unit is not parent] + children + [balance],
                            key=lambda row: row["unit_id"])
    group["statistical_aggregates"].append(province)


def add_bombay_districts(group, observations):
    presidency_id = "raj_bombay_presidency"
    states_id = "raj_bombay_states"
    parents = {unit["unit_id"]: unit for unit in group["units"] if unit["unit_id"] in (presidency_id, states_id)}
    dates = group["endpoint_dates"]
    collection = HERE / "collections" / "india_bombay_districts_1901"
    with (collection / "bombay_endpoint_sex_controls.csv").open(encoding="utf8", newline="") as source:
        controls = {(row["unit_id"], row["date"]): row for row in csv.DictReader(source)}
    changes = {}
    for unit_id, parent in parents.items():
        rows = [controls[(unit_id, when)] for when in dates]
        endpoints = [int(row["persons"]) for row in rows]
        changes[unit_id] = [new - old for new, old in zip(endpoints, parent["endpoint_values"], strict=True)]
        delta, repeated = changes[unit_id]
        if delta != repeated:
            raise ValueError(f"{unit_id}: Bombay scope difference varies across census endpoints")
        parent.update(
            endpoint_values=endpoints, source_dates=dates, date=DATE,
            population_value=parent["population_value"] + delta,
            source_id=BOMBAY_DISTRICT_SOURCE, locator="; ".join(row["locator"] for row in rows),
            scope=rows[-1]["scope"],
            method="Interpolate the 1891 and 1901 census counts on the common March 1901 jurisdiction.",
            uncertainty_kind="Enumeration and interpolation error, including the effects of famine and migration, are unquantified.",
        )
    if sum(changes[unit_id][0] for unit_id in (presidency_id, states_id)):
        raise ValueError("British Bombay and Bombay States scope changes do not cancel")
    districts = [row for row in observations if row["source_id"] == BOMBAY_DISTRICT_SOURCE
                 and row["parent_id"] == presidency_id]
    if len(districts) != 48:
        raise ValueError("Bombay Presidency requires two census counts in each of 24 districts")
    presidency = parents[presidency_id]
    children = interpolate_partition(districts, presidency, dates)
    places = {row["unit_id"]: row["place_ids"] for row in districts if row.get("place_ids")}
    for child in children:
        child.update(statistical_parent=presidency_id, date=DATE, place_ids=places.get(child["unit_id"], []),
                     uncertainty_kind=presidency["uncertainty_kind"])
    group["statistical_aggregates"].append(presidency)
    group["units"] = sorted([unit for unit in group["units"] if unit is not presidency] + children,
                            key=lambda row: row["unit_id"])


def portuguese_opening(previous, observations):
    root = previous["unit_id"]
    dates = ["1890-12-01", "1900-12-01"]
    sources = {"pt_census_1890", "pt_census_1900"}
    controls = {row["date"]: row for row in observations if row["unit_id"] == root and row["source_id"] in sources}
    early, late = [controls[day] for day in dates]
    endpoints = [early["population_value"], late["population_value"]]
    fraction = opening_fraction(dates)
    total = round(endpoints[0] * (1 - fraction) + endpoints[1] * fraction)
    districts = [row for row in observations if row["parent_id"] == root and row["source_id"] in sources]
    if len(districts) != 42:
        raise ValueError("Portuguese census must contain 21 districts at each census date")
    parent = dict(unit_id=root, name=late["name"], population_value=total, endpoint_values=endpoints)
    leaves = interpolate_partition(districts, parent, dates)
    for leaf in leaves:
        leaf["locator"] = f"{leaf['locator']}; {late['locator']}"
        leaf["uncertainty_kind"] = ("Districts are paired by historical identity. Lower-level boundary transfers, "
                                    "enumeration coverage and interpolation error have no quantified interval.")
    return dict(unit_id=root, date=DATE, population_value=total, source_id=late["source_id"],
                source_observations=[row["record_id"] for row in (early, late)], locator=f"{early['locator']}; {late['locator']}",
                method=f"Linearly interpolate the two official population-present census totals, elapsed fraction {fraction}.",
                scope=late["definition"], endpoint_dates=dates, country_endpoint_values=endpoints,
                alternative_research_value=previous["population_value"], research_unit_ids=previous["research_unit_ids"],
                partition_source="collections/portugal_census_1900/observations.jsonl", units=leaves)


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


def egypt_opening(observations, version):
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
    if version >= 20:
        provinces = defaultdict(dict)
        for row in observations:
            if row["source_id"] == EGYPT_COMPARABLE_PROVINCES:
                provinces[row["unit_id"]][row["date"]] = row
        for unit, endpoints in sorted(provinces.items()):
            before, after = [endpoints[day] for day in dates]
            initial, final = [row["population_value"] for row in (before, after)]
            leaves.append(dict(
                unit_id=unit, name=before["name"], population_value=round(initial + (final - initial) * fraction),
                source_unit_ids=[unit], source_id=before["source_id"], source_quality=before["quality"],
                source_observations=[before["record_id"], after["record_id"]],
                endpoint_values=[initial, final], source_dates=dates,
                locator=before["locator"] + " / " + after["locator"],
                scope=before["definition"],
                uncertainty_kind="Enumeration coverage and interpolation error have no quantified interval. "
                                 "The comparison table includes some estimated nomadic populations. "
                                 "Boundary changes below the provincial level are unresolved.",
            ))
    control = legacy_population_control(root)
    opening = dict(
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
    if version >= 20:
        opening.update(
            locator="Tanada, Tables 2 and 4; Census of Egypt, 1907, Table 5, printed pp. 29–32.",
            method=f"Linear daily interpolation of two town returns and comparable provincial totals, "
                   f"elapsed fraction {fraction}.",
            scope="Cairo, Alexandria and six provinces are disjoint subdivisions of the retained Egypt control. "
                  "The balance has no geographic allocation. Census and map extents differ for western "
                  "oases and the southern frontier.",
            uncertainty_kind="The national control retains its inherited source basis. The interpolated "
                             "local estimates have no statistical interval.",
        )
    if version >= 25:
        parent = next(leaf for leaf in leaves if leaf["unit_id"] == "egy_mudiriya_faiyum")
        local = [row for row in observations if row["source_id"] in EGYPT_FAIYUM_SOURCES]
        districts = interpolate_partition(local, parent, dates)
        for district in districts:
            district.update(statistical_parent=parent["unit_id"], date=DATE,
                            locator=f"{district['locator']}; 1907 census, Table 5 p. 32")
        opening["units"] = [leaf for leaf in leaves if leaf is not parent] + districts
        opening["statistical_aggregates"] = [parent | dict(
            date=DATE, method="Sum of the Itsa, Faiyum and Sinuris districts on their comparable census extent.",
        )]
    return opening


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


def belgium_opening(previous, observations):
    source = "belgium_census_provinces_1890_1900"
    national_id = "be_census_kingdom"
    dates = ["1890-12-31", "1900-12-31"]
    provinces = (
        "antwerp", "brabant", "west_flanders", "east_flanders", "hainaut",
        "liege", "limburg", "luxembourg", "namur",
    )
    labels = {f"be_census_{province}": f"{previous['unit_id']}:label:{index}"
              for index, province in enumerate(provinces, 1)}
    places = {
        "be_census_antwerp": ["place:antwerp"],
        "be_census_brabant": ["place:brussels"],
        "be_census_west_flanders": ["place:kortrijk"],
        "be_census_east_flanders": ["place:ghent"],
        "be_census_hainaut": ["place:tournai"],
    }
    rows = [row for row in observations if row["source_id"] == source and row["date"] in dates]
    national = sorted((row for row in rows if row["unit_id"] == national_id), key=lambda row: row["date"])
    if [row["date"] for row in national] != dates:
        raise ValueError("Missing or duplicate census control for Belgium")
    endpoints = [row["population_value"] for row in national]
    fraction = opening_fraction(dates)
    population = round(endpoints[0] + (endpoints[1] - endpoints[0]) * fraction)
    province_rows = [row for row in rows if row["parent_id"] == national_id and row["kind"] == "admin"]
    if {row["unit_id"] for row in province_rows} != labels.keys():
        raise ValueError("The Belgian census must cover all nine historical provinces")
    leaves = interpolate_partition(province_rows, dict(
        unit_id=previous["unit_id"], name="Belgium", population_value=population, endpoint_values=endpoints,
    ), dates)
    for leaf in leaves:
        leaf["wwo_admin_label"] = labels[leaf["unit_id"]]
        leaf["place_ids"] = places.get(leaf["unit_id"], [])
    return dict(
        unit_id=previous["unit_id"], date=DATE, source_id=source,
        population_value=population, endpoint_dates=dates, country_endpoint_values=endpoints,
        source_observations=[row["record_id"] for row in national],
        locator=" / ".join(row["locator"] for row in national),
        method=f"Linear daily interpolation of the two census totals, elapsed fraction {fraction}. Round once.",
        scope=("Usual residents of the historical nine-province Kingdom of Belgium, including people temporarily absent. "
               "Luxembourg here refers to the Belgian province. The Grand Duchy and Congo Free State are separate."),
        research_unit_ids=previous["research_unit_ids"], alternative_research_value=previous["population_value"],
        partition_source="collections/belgium_provinces_1900/observations.jsonl", units=leaves,
    )


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
    if version >= 11:
        coastal_and_frontier = path.with_name("qing_interior_v11_crosswalk.tsv")
        with coastal_and_frontier.open(encoding="utf8") as f:
            links.extend(csv.DictReader(f, delimiter="	"))
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
    if version >= 11:
        group["v11_territorial_source"] = coastal_and_frontier.relative_to(HERE).as_posix()
    if version >= 19:
        add_shaangan_prefectures(group, observations)
    return group


def add_shaangan_prefectures(group, observations):
    source = "lu_qing_shaangan_prefecture_reconstruction"
    dates = group["interpolation_reference_dates"]
    year_to_anchor = dict(zip(group["endpoint_dates"], dates, strict=True))
    prefectures = defaultdict(list)
    for row in observations:
        if row["source_id"] == source:
            prefectures[row["parent_id"]].append(row | dict(date=year_to_anchor[row["date"]]))
    units, aggregates = [], []
    for parent in group["units"]:
        parent_id = parent["unit_id"]
        if parent_id not in prefectures:
            units.append(parent)
            continue
        if parent["place_ids"]:
            raise ValueError(f"Assign the existing places to prefectures before splitting {parent_id}")
        children = interpolate_partition(prefectures.pop(parent_id), parent, dates)
        for child in children:
            child.update(
                statistical_parent=parent_id, date=DATE,
                source_dates=group["endpoint_dates"], interpolation_reference_dates=dates,
                method=child["method"] + " The two anchor dates are conventional July midpoints of source years.",
                uncertainty_kind=("The source estimates are rounded to thousands. Local boundary differences and "
                                  "interpolation errors have no calibrated interval."),
            )
        units.extend(children)
        aggregates.append(parent | dict(
            date=DATE, endpoint_dates=group["endpoint_dates"],
            interpolation_reference_dates=dates,
            method="Sum the non-overlapping historical prefectural statistical areas using the provincial controls.",
        ))
    if prefectures or {parent["unit_id"] for parent in aggregates} != {"qing_hist_shaanxi", "qing_hist_gansu"}:
        raise ValueError("The prefectural data must close to both existing Shaanxi and Gansu controls")
    group.update(units=units, statistical_aggregates=aggregates)


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
        for group in (egypt_opening(observations, version), natal_and_zululand(observations)):
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
        add_british_county_partitions(result["british_isles_1900"], observations, version=version)
        add_russian_provinces(result["russian_empire"], observations)
        add_japanese_prefectures(result["empire_of_japan"], observations)
        add_india_comparable_areas(result["cshapes_gw_750"], observations)
    if version >= 11:
        add_mauritius_districts(result["cshapes_gw_590"], observations)
    if version >= 12:
        root = "kingdom_of_netherlands"
        result[root] = netherlands_opening(result[root], observations)
    if version >= 13:
        add_french_arrondissements(result["country_fra"], observations)
        add_nordic_population_controls(result["sweden_norway_union"], observations)
        root = "kingdom_of_belgium"
        result[root] = belgium_opening(result[root], observations)
    if version >= 14:
        add_india_princely_states(result["cshapes_gw_750"], observations)
    if version >= 15:
        add_russian_districts(result["russian_empire"], observations)
    if version >= 17:
        add_england_wales_statistical_scope(result["british_isles_1900"], observations)
    if version >= 18:
        add_hungarian_crown_counties(result["austria_hungary"], observations)
    if version >= 21:
        taiwan = taiwan_opening(study["ft_formosa_taiwan"], observations, endpoints)
        if taiwan["unit_id"] in result:
            raise ValueError("Duplicate Taiwan opening control")
        result[taiwan["unit_id"]] = taiwan
    if version >= 22:
        add_italian_regions(result["kingdom_of_italy"], observations)
        add_indian_local_areas(result["cshapes_gw_750"], observations, version=version)
    if version >= 25:
        add_spanish_provinces(result["kingdom_of_spain"], observations)
    if version >= 26:
        add_agra_districts(result["cshapes_gw_750"], observations)
        result["kingdom_of_portugal"] = portuguese_opening(result["kingdom_of_portugal"], observations)
        peru, = (row for row in observations if row["source_id"] == "pe_inei_historical_population_1900")
        result["peru_1900"] = dict(
            unit_id="peru_1900", date=DATE, population_value=peru["population_value"],
            source_id=peru["source_id"], source_quality=peru["quality"], source_observations=[peru["record_id"]],
            source_dates=[peru["date"]], locator=peru["locator"], scope=peru["definition"],
            partition_source="collections/peru_1900_reconstruction/observations.jsonl",
            method="Use the published annual historical estimate as the opening proxy.",
            uncertainty_kind="The reference day, population basis, frontier treatment, estimation method and error interval are unpublished.",
            units=[],
        )
    if version >= 27:
        add_remaining_madras_states(result["cshapes_gw_750"], observations)
        add_bengal_districts(result["cshapes_gw_750"], observations)
    if version >= 28:
        india = result["cshapes_gw_750"]
        add_bombay_districts(india, observations)
        for unit in india["units"]:
            if unit["unit_id"] in {"raj_bengal_calcutta", "raj_bombay_bombay_city"}:
                unit["coextensive_place"] = True
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
