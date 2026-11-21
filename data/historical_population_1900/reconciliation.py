"""Parent controls and source conflicts. Dated observations are never balances."""
from collections import Counter, defaultdict
from datetime import date
from fractions import Fraction

from geography import DATE, opening_scope_links, research_scope_note
from opening import sourced_people


def world_accounts(study, selection, legacy, target):
    """Trace the published research total and the separate opening authority."""
    rows = {r["unit_id"]: r for r in study}
    roots = {g["unit_id"]: g for g in selection}
    legacy_economies = {r["unit_id"]: r for r in legacy if r["role"] == "economic_statistical_unit"}
    changes = [r for r in legacy_economies.values() if r["replacement_minus_legacy"] is not None]
    added = [g for g in selection if g["unit_id"] not in legacy_economies]
    untouched = [r for r in legacy_economies.values() if r["status"] == "legacy_only"]
    residuals = [r for r in legacy if r["role"] == "excluded_economic_residual"]
    legacy_total = sum(r["population_value"] for r in legacy_economies.values())
    replacement_delta = sum(r["replacement_minus_legacy"] for r in changes)
    additions_total = sum(g["population_value"] for g in added)
    authoritative = legacy_total + replacement_delta + additions_total
    documented = sum(sourced_people(g) for g in selection)
    untouched_total = sum(r["population_value"] for r in untouched)
    unlocated_total = sum(g.get("legacy_unlocated_balance", 0) for g in selection)

    reviewed = []
    for link in opening_scope_links(selection, study):
        selected = [roots[key] for key in link["opening_root_ids"]]
        research = [rows[key] for key in link["research_unit_ids"]]
        regions = sorted({r["region"] for r in research})
        opening_people = sum(sourced_people(g) for g in selected)
        research_people = sum(r["population_value"] for r in research) if research else None
        reviewed.append(dict(**link, research_regions=regions, research_people=research_people,
            documented_opening_people=opening_people,
            opening_people_including_retained_balances=sum(g["population_value"] for g in selected),
            research_minus_documented=research_people-opening_people if research else None))
    linked = {key: entry for entry in reviewed for key in entry["research_unit_ids"]}

    register = []
    for row in study:
        key = row["unit_id"]
        comparison = linked.get(key)
        register.append(dict(unit_id=key, name=row["name"], region=row["region"], population_value=row["population_value"],
            population_lower=row["population_lower"], population_upper=row["population_upper"], quality=row["quality"],
            source_id=row["source_id"], locator=row["locator"], method_locator=row.get("method_locator"),
            candidate_polity_ids=row["candidate_polity_ids"],
            comparison_id=comparison["comparison_id"] if comparison else None,
            opening_disposition=comparison["scope_relation"] if comparison else "research_only",
            note=comparison["note"] if comparison else research_scope_note(row)))

    by_region = defaultdict(list)
    for row in register:
        by_region[row["region"]].append(row)
    research_regions = {}
    for region, entries in sorted(by_region.items()):
        comparisons = [entry for entry in reviewed if entry["research_regions"] == [region]]
        production_roots = sorted(key for entry in comparisons for key in entry["opening_root_ids"])
        production_people = sum(sourced_people(roots[key]) for key in production_roots)
        regional_total = sum(row["population_value"] for row in entries)
        research_only = [r for r in entries if r["opening_disposition"] == "research_only"]
        research_regions[region] = dict(statistical_units=len(entries), opening_research_estimate=regional_total,
            units_with_polity_candidates=sum(bool(r["candidate_polity_ids"]) for r in entries),
            people_without_polity_candidate=sum(r["population_value"] for r in entries if not r["candidate_polity_ids"]),
            grades=dict(Counter(r["quality"] for r in entries)), production_root_ids=production_roots,
            production_people=production_people, production_pct_of_regional_research_estimate=round(100*production_people/regional_total, 3),
            people_with_opening_subdivision=sum(sourced_people(roots[key]) for key in production_roots if roots[key]["units"]),
            research_only_units=len(research_only), research_only_people=sum(r["population_value"] for r in research_only))

    component_total = sum(r["population_value"] for r in study)
    research_only_total = sum(r["population_value"] for r in register if r["opening_disposition"] == "research_only")
    compared_differences = defaultdict(int)
    for entry in reviewed:
        if entry["research_minus_documented"] is not None:
            compared_differences[entry["scope_relation"]] += entry["research_minus_documented"]
    unlinked_opening = sum(entry["documented_opening_people"] for entry in reviewed if not entry["research_unit_ids"])
    signed_changes = dict(published_minus_component_sum=target-component_total,
        research_only_component_people=research_only_total, comparisons_by_scope=dict(compared_differences),
        opening_without_benchmark_link=-unlinked_opening, untouched_legacy_controls=-untouched_total,
        unlocated_balances_under_retained_controls=-unlocated_total)
    return dict(reference_date=DATE,
        accounting_note="Research is a benchmark at published statistical extents. Opening is an independent authority with retained legacy accounts. Differences involving unmatched extents, dates or sources are arithmetic and cannot locate people.",
        research_regions=research_regions, research_units=register, opening_comparisons=reviewed,
        opening_comparisons_without_single_region=[entry["comparison_id"] for entry in reviewed if len(entry["research_regions"]) != 1],
        legacy_to_opening=dict(legacy_economic_accounts=len(legacy_economies), legacy_economic_population=legacy_total,
            changes_to_existing_accounts=[dict(unit_id=r["unit_id"], people=r["replacement_minus_legacy"])
                for r in changes if r["status"] == "replaced_for_new_games"],
            net_replacements=replacement_delta,
            added_opening_accounts=[dict(unit_id=g["unit_id"], people=g["population_value"]) for g in added],
            net_additions=additions_total, authoritative_opening_population=authoritative,
            excluded_economic_residuals=[dict(unit_id=r["unit_id"], people=r["population_value"]) for r in residuals],
            excluded_residual_sum_nonexclusive=sum(r["population_value"] for r in residuals)),
        research_to_opening=dict(published_research_estimate=target, research_component_sum=component_total,
            documented_opening_population=documented, untouched_legacy_population=untouched_total,
            retained_unlocated_population=unlocated_total, authoritative_opening_population=authoritative,
            published_minus_documented_opening=target-documented, signed_components_of_difference=signed_changes,
            published_minus_authoritative_opening=target-authoritative))

_DANISH_TOWN_DISTRICTS = {
    "dk_faroe", "dk_island_south", "dk_island_west", "dk_island_northeast",
    "dk_st_croix", "dk_st_thomas", "dk_st_jan",
}
_ADDITIONAL_COMPONENTS = {
    ("ph_census_1903_vol2", "ph_archipelago_census_1903"): {"ph_1903_manila_city"},
    ("british_empire_census_1901", "basutoland"): {"basutoland_gaols", "basutoland_hospitals"},
    ("british_empire_census_1901", "lagos_colony_protectorate"): {"lagos_island_harbour", "ebute_metta"},
    ("cao_qing_provincial_reconstruction", "qing_cao_total"): {
        "qing_hist_mongolia", "qing_hist_qinghai", "qing_hist_tibet",
    },
}
_SCOPE_NOTES = {
    ("ph_census_1903_vol2", "ph_archipelago_census_1903"):
        "Volume II General Table 1 has 50 reporting areas, including Manila city as a peer of the provinces and districts.",
    ("ca_census_1901_vol1_table1", "dominion_of_canada"):
        "Final electoral geography, Table I. Québec and the Unorganized Territories are separate rows. The combined opening comparator overlaps both and is excluded.",
    ("ca_yearbook_2012_table241", "dominion_of_canada"):
        "Only the Manitoba and Ontario comparison rows are available from this source in this collection.",
    ("british_empire_census_1901", "basutoland"):
        "Table 3 reports gaols and hospitals separately from the districts. Their totals are included without geographic allocation.",
    ("british_empire_census_1901", "lagos_colony_protectorate"):
        "Table 1 combines the April 1 enumeration of Lagos Island and Harbour and Ebute Metta with the year-only district estimates.",
    ("dk_yearbook_1903_dependencies", "dk_greenland_se"):
        "Table C.1 gives a control for South and East Greenland together. Footnote 1 supplies only the East Greenland component.",
    ("nz_official_yearbook_1900", "nz_colony"):
        "The district estimates cover non-Māori population. The colony control also includes 39,854 Māori carried forward from the 1896 census, without a district allocation here.",
    ("egypt_historical_census_primary_tables", "egy_census_territory"):
        "The appendix subtotal covers the listed rural provinces. Table 4 principal-town counts cannot replace whole governorates. See the census territory control for coverage.",
    ("egypt_historical_census_primary_tables", "egy_mudiriya_gharbiya"):
        "The published Gharbiya control and the individual markaz figures are retained as transcribed in the appendix.",
    ("india_statistical_abstract_1905", "raj_central_india_agency"):
        "Table 2 names Gwalior as a component of Central India Agency. It is the only state-level component available here.",
    ("india_statistical_abstract_1905", "raj_madras_states"):
        "Table 2 gives Cochin and Travancore individually. The rest of the Madras States population remains in the reported control.",
}


def _component_date(row):
    source, parent, unit = row["source_id"], row["parent_id"], row["unit_id"]
    scope = (source, parent)
    if source == "ca_census_1901_vol1_table1" and unit == "ca_quebec_and_unorganized_territories":
        return None
    if row["kind"] in {"admin", "territory", "country"}:
        return row["date"]
    if unit in _ADDITIONAL_COMPONENTS.get(scope, ()):
        # The Lagos year-only control combines two precise censuses with estimated districts.
        if parent == "lagos_colony_protectorate" and row["date"] == "1901-04-01":
            return "1901"
        return row["date"]
    if row["kind"] == "city" and (
        (source == "ireland_general_census_1911" and unit.startswith("irish_county_borough_"))
        or (source == "dk_yearbook_1903_dependencies" and parent in _DANISH_TOWN_DISTRICTS)
    ):
        return row["date"]
    return None


def _interpretation(parent, difference, counted):
    source, unit = parent["source_id"], parent["unit_id"]
    if difference is None:
        return "Alternative values for the same child or unknown count."
    if counted is not None:
        remainder = parent["population_value"] + difference - counted["population_value"]
        return (
            f"Gold Coast Table 1 adds a published omission allowance of {counted['published_omission_allowance']:,} "
            f"to its counted control of {counted['population_value']:,}. The district subtotal minus the "
            f"counted control is {remainder:,}. The allowance has no common district allocation."
        )
    if note := _SCOPE_NOTES.get((source, unit)):
        return note
    if source == "ireland_general_census_1911" and unit.startswith("irish_province_"):
        return "Tables 48 and 48A report county boroughs separately from the administrative counties."
    if source == "dk_yearbook_1903_dependencies" and unit in _DANISH_TOWN_DISTRICTS:
        return "Table C lists the towns and the surrounding rural districts as separate components."
    if source == "cao_qing_provincial_reconstruction":
        if difference == 0:
            return "Cao Table 1.1 reports 25 areas, including Inner Mongolia, Qinghai and Tibet."
        if parent["date"] == "1900-01-01":
            return "All 25 reporting areas are included. The 1900 component estimates and their control were rounded independently."
    if difference == 0:
        return "Arithmetic closure only. See the original enumeration definitions."
    if source == "insee_sgf_censuses":
        return "The department or national control and its components come from separate DBF cells. Estimates retain the endpoint differences and are rounded independently."
    if source == "jp_cabinet_1909_resident_prefectures":
        return "The Cabinet Statistics Bureau published both the resident total and prefectural values to hundreds."
    if source == "india_statistical_abstract_1905" and parent["date"] == "1900-01-01":
        if unit in {"raj_total_british_territory", "raj_total_native_states"}:
            return "The 1901 control includes Baluchistan. Table 2 has no corresponding 1891 Baluchistan figures for the territorial or agency components."
        return "The components and their control were interpolated and rounded independently."
    if source == "de_jahrbuch_1902_census" and parent["method"] == "linear_daily_interpolation":
        return "The components and their control were interpolated and rounded independently."
    return "The available components leave a scope or source difference. The control and individual observations are retained."


def comparisons(rows):
    children=defaultdict(list)
    counted_controls={}
    for r in rows:
        if not r["parent_id"]:
            continue
        if component_date := _component_date(r):
            children[(r["source_id"],component_date,r["parent_id"])].append(r)
        if r["source_id"] == "british_empire_census_1901" and r["unit_id"] == "gold_coast_enumerated":
            counted_controls[(r["source_id"],r["date"],r["parent_id"])]=r
    out=[]
    for p in rows:
        if p["kind"]=="city" or p["source_id"].startswith("ft_world_"):
            continue
        key=(p["source_id"],p["date"],p["unit_id"])
        entries=children.get(key)
        if not entries:
            continue
        unique=len({c["unit_id"] for c in entries})==len(entries)
        subtotal=sum(c["population_value"] for c in entries) if unique and all(c["population_value"] is not None for c in entries) else None
        diff=subtotal-p["population_value"] if subtotal is not None and p["population_value"] is not None else None
        out.append(dict(parent_id=p["unit_id"],date=p["date"],source_id=p["source_id"],locator=p["locator"],reported=p["population_value"],
                observed_children=[c["record_id"] for c in entries],subtotal=subtotal,children_minus_parent=diff,
                interpretation=_interpretation(p,diff,counted_controls.get(key))))
    return out

def asian_estimates(rows):
    # Research-only. Annual Cao dates are represented by a nominal July midpoint.
    # Table 2 for India includes portions retrospectively tabulated under later names.
    grouped=defaultdict(list)
    for r in rows:
        if r["source_id"]=="cao_qing_provincial_reconstruction" or (
                r["source_id"]=="india_statistical_abstract_1905" and r["kind"]!="city" and r["locator"].startswith("Table 2,")
                and r["date"] in {"1891","1901-03-01"}):
            grouped[r["unit_id"]].append(r)
    output=[]
    for key,block in grouped.items():
        if len(block)!=2:continue
        a,b=sorted(block,key=lambda r:r["date"])
        annual=a["source_id"]=="cao_qing_provincial_reconstruction"
        dates=[(r["date"]+"-07-01" if annual else "1891-02-26") if len(r["date"])==4 else r["date"] for r in (a,b)]
        left,right=map(date.fromisoformat,dates)
        f=Fraction((date(1900,1,1)-left).days,(right-left).days)
        if not 0<f<1:continue
        value=round(a["population_value"]+(b["population_value"]-a["population_value"])*f)
        note=("Nominal midyear for year-only endpoints. Source uses retrospective regional names. Cao includes Taiwan within Fujian and excludes Outer Mongolia (Federico–Tena Appendix I, p. 73 nn. 54–55)." if annual else
            "Interpolation of printed columns on the table's reporting geography. Indian Empire includes Aden. Burma enumeration expanded; missing fringe populations and famine timing make this unsuitable as a complete boundary-consistent census.")
        output.append(dict(unit_id=key,name=a["name"],parent_id=a["parent_id"],kind=a["kind"],population_value=value,
            population_lower=None,population_upper=None,date="1900-01-01",source_id=a["source_id"],
            locator=a["locator"]+" / "+b["locator"],source_dates=[a["date"],b["date"]],endpoint_values=[a["population_value"],b["population_value"]],
            interpolation_reference_dates=dates, date_basis="nominal midyear" if annual else "Census of India, General Report 1891, ch. I, opening paragraph; reference night, remote areas differed",
            date_source=None if annual else "https://censusindia.gov.in/nada/index.php/catalog/28412/",fraction=str(f),definition=note,method="linear interpolation of two source totals, rounded once; model error unquantified",
            mapping_status="research_only_original_statistical_scope",quality="derived_estimate_unquantified",region="Asia"))
    return output
