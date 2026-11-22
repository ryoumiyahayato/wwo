"""Rebuild the single research release, catalogue, accounts and Rust input offline."""
import csv
import gzip
import json
from collections import Counter, defaultdict

from pathlib import Path
from geography import catalogue, legacy_audit
from opening import geographic_partitions, groups, sourced_people
from social import opening_social
from structure import age_sex_panels, dimensions, opening_structure
from structural_coverage import structural_coverage
from reconciliation import comparisons, asian_estimates, world_accounts
from cities import city_index
from us_municipalities import us_residuals

HERE = Path(__file__).resolve().parent
COL = HERE / "collections"
DATE = "1900-01-01"
OPENING_VERSION = 27

def json_file(name, value):
    (HERE/name).write_text(json.dumps(value, indent=2, ensure_ascii=False)+"\n", encoding="utf8", newline="\n")

def records(name, rows):
    # No timestamp or platform-specific filename in the portable compressed records.
    with (HERE/name).open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as out:
        for row in rows:
            out.write((json.dumps(row, ensure_ascii=False, separators=(",",":"))+"\n").encode())

def bucket(n):
    if n is None or n < 50000:
        return None
    if n < 100000:
        return "50k–<100k"
    if n < 200000:
        return "100k–<200k"
    if n < 500000:
        return "200k–<500k"
    return "500k+"

def opening_age_coverage(selection, legacy, structure_opening, comparison_rows):
    parents = {u["unit_id"]: g["unit_id"] for g in selection
               for u in [*g["units"], *g.get("statistical_aggregates", [])]}
    controls = {g["unit_id"]: g["population_value"] for g in selection}
    controls.update({r["unit_id"]: r["population_value"] for r in legacy if r["status"]=="legacy_only"})
    supported = defaultdict(int)
    age_unknown = defaultdict(int)
    for group in structure_opening["groups"]:
        unit = group["unit_id"]
        root = parents.get(unit, unit)
        total = group["opening_total"]
        observed = group["observed_total"]
        cells = []
        for band in group["bands"]:
            for field, sex in (("female", "f"), ("male", "m")):
                if band[field]:
                    count, remainder = divmod(total * band[field], observed)
                    cells.append((-remainder, f"{band['id']}:{sex}", count, band["age_min"] is None))
        remaining = total - sum(cell[2] for cell in cells)
        age_unknown[root] += sum(count + (rank < remaining)
                                 for rank, (_, _, count, unknown) in enumerate(sorted(cells)) if unknown)
        supported[root] += total
    regions = {key: row["research_regions"][0] for row in comparison_rows if len(row["research_regions"])==1
               for key in row["opening_root_ids"]}
    totals_by_region = defaultdict(Counter)
    world = Counter()
    roots = []
    for key, count in sorted(controls.items()):
        coverage = dict(opening_control=count, in_model_pools=supported[key], outside_model_pools=count-supported[key],
                        modeled_age_and_sex=supported[key]-age_unknown[key], modeled_sex_age_unknown=age_unknown[key])
        region = regions.get(key)
        totals = totals_by_region[region or "no_reviewed_research_region"]
        totals.update(coverage)
        world.update(coverage)
        roots.append(dict(opening_unit_id=key, research_region=region, **coverage))
    return dict(note="Opening controls before named-resident deductions. Source-age-unknown cells remain unknown after integer apportionment. Dated census populations are separate. Unknown research regions do not inherit a continent from political control.",
                opening_roots=roots, by_research_region=dict(totals_by_region), world=dict(world))


def opening_count_basis(selection, legacy, world_reference):
    counts = dict(direct_enumeration_on_opening_date=0, published_historical_estimates=0,
                  date_models_from_territorial_returns=0, retained_legacy_estimates=0)
    accounts = []
    for group in selection:
        source = group["source_id"]
        if source == "nl_cbs_census_1899_age_marital":
            basis = "direct_enumeration_on_opening_date"
        elif source.startswith("ft_world_") or source in {
            "cao_qing_provincial_reconstruction", "natal_statistical_yearbook_1909_macdonald",
            "cape_colony_1899_imperial_conference", "zanzibar_statesmans_year_book_1899",
            "se_scb_population_tab5890", "pe_inei_historical_population_1900",
        }:
            basis = "published_historical_estimates"
        else:
            basis = "date_models_from_territorial_returns"
        sourced = group.get("research_unlocated_balance", sourced_people(group))
        retained = group.get("legacy_unlocated_balance", 0)
        counts[basis] += sourced
        counts["retained_legacy_estimates"] += retained
        accounts.append(dict(unit_id=group["unit_id"], source_id=source,
                             sourced_people=sourced, sourced_basis=basis, retained_legacy_people=retained))
        if "research_unlocated_balance" in group:
            for leaf in group["units"]:
                leaf_basis = (basis if basis == "direct_enumeration_on_opening_date"
                              else "date_models_from_territorial_returns")
                counts[leaf_basis] += leaf["population_value"]
                accounts.append(dict(unit_id=leaf["unit_id"], source_id=leaf["source_id"],
                                     sourced_people=leaf["population_value"], sourced_basis=leaf_basis,
                                     retained_legacy_people=0, parent_id=group["unit_id"]))
    for row in legacy:
        if row["status"] == "legacy_only":
            retained = row["population_value"]
            counts["retained_legacy_estimates"] += retained
            accounts.append(dict(unit_id=row["unit_id"], source_id=None,
                                 sourced_people=0, sourced_basis=None, retained_legacy_people=retained))
    return dict(
        counts={key: dict(people=count, pct_of_research_reference=round(100*count/world_reference, 3))
                for key, count in counts.items()},
        scopes=sorted(accounts, key=lambda row: row["unit_id"]),
        note="Published historical estimates include the normalized date of a research or contemporary estimate. Territorial models use census or official statistical returns at other dates. The Dutch count enumerates usual residents at the opening midnight. The difference between authorities is not an observed count of missing residents.",
    )

def residuals(rows):
    # Restrict subtraction to reviewed sets of disjoint municipalities and a
    # same-date parent. Other city populations remain views of their parent.
    controls = {(r["source_id"],r["unit_id"],r["date"]):r for r in rows if r["kind"]=="admin"}
    members = defaultdict(list)
    for r in rows:
        if r["kind"]!="city" or r["source_id"] not in {"swiss_federal_census_comparison_1911","russia_first_census"}:
            continue
        key=(r["source_id"],r["parent_id"],r["date"])
        if key in controls:
            if r["source_id"]=="russia_first_census" and "_r" not in r["parent_id"]:
                continue   # At this level other cities belong to intermediate districts.
            members[key].append(r)
    result=[]
    for key, cities in sorted(members.items()):
        parent=controls[key]
        inside=sum(r["population_value"] for r in cities)
        difference=parent["population_value"]-inside
        result.append(dict(parent_id=key[1],date=key[2],source_id=key[0],parent_value=parent["population_value"],
            parent_locator=parent["locator"],city_ids=[r["unit_id"] for r in cities],identified_city_population=inside,
            remainder=difference if difference>=0 else None,arithmetic_difference=difference,
            meaning="Residents outside the listed cities; may include other towns and rural settlements.",
            status="disjoint_subtraction" if difference>=0 else "conflict_quarantined"))
    return sorted(result + us_residuals(rows), key=lambda r: (r["source_id"], r["parent_id"], r["date"]))


def england_wales_habitations():
    path = COL / "england_wales_habitations" / "habitations.json"
    census = json.loads(path.read_text(encoding="utf8"))
    district_returns = census["districts"].values()
    all_rooms = census["by_rooms_in_tenement"]
    crowded_rooms = census["by_rooms_in_overcrowded_tenement"]
    if (sum(row["population"] for row in district_returns) != census["total_population"]
        or sum(row["overcrowded_tenements_1_to_4_rooms"] for row in district_returns) != census["overcrowded_tenements_1_to_4_rooms"]
        or sum(row["occupants_of_these_tenements"] for row in district_returns) != census["occupants_of_these_tenements"]
        or sum(row["tenements"] for row in all_rooms.values()) != census["separate_occupations"]
        or sum(row["occupants"] for row in all_rooms.values()) != census["total_population"]
        or sum(row["tenements"] for row in crowded_rooms.values()) != census["overcrowded_tenements_1_to_4_rooms"]
        or sum(row["occupants"] for row in crowded_rooms.values()) != census["occupants_of_these_tenements"]
        or any(count > all_rooms[rooms][unit]
               for rooms, metrics in crowded_rooms.items() for unit, count in metrics.items())):
        raise ValueError("England and Wales housing census breakdowns do not close")
    metadata = {key: census.pop(key) for key in ("unit_id", "date", "source_id")}
    return dict(**metadata, dimension="housing_and_urban_rural", category="published census observation",
        locator="General Report, sections II.1 and II.4 population controls; section III, pp. 39–41, tenements and overcrowding.",
        definition="Census-night population within the statutory urban and rural districts then in force, excluding the islands in the British seas. The report counts separate occupations. The overcrowding measure covers only one- to four-room tenements with more than two occupants per room. It supplies neither floor area nor a complete count of overcrowding in all dwellings.",
        values=census)


def main():
    observations=[]
    manifest={}
    city_keys={}
    with (COL/"cities_europe"/"city_equivalences.csv").open(encoding="utf8") as f:
        for row in csv.DictReader(f):
            city_keys[row["member_unit_id"]]=row["city_key"]
    for f in sorted([*COL.glob("*/sources.json"), *COL.glob("age_sex/*_sources.json")]):
        for s in json.loads(f.read_text(encoding="utf8")):
            if s["id"] in manifest and manifest[s["id"]]["url"]!=s["url"]:
                raise ValueError("source ID collision: "+s["id"])
            manifest.setdefault(s["id"],s|{"collection":f.parent.name})
    regional_counts={}
    for f in sorted(COL.glob("*/observations.jsonl")):
        n=0
        for line in f.read_text(encoding="utf8").splitlines():
            r=json.loads(line)
            if r["source_id"] not in manifest or not r["locator"]:
                raise ValueError((f,r["unit_id"],r["source_id"]))
            n+=1
            r["record_id"]=f"{f.parent.name}:{n}"
            r["population_lower"]=r.pop("lower",r.get("population_lower"))
            r["population_upper"]=r.pop("upper",r.get("population_upper"))
            r.setdefault("parent_id",None)
            r.setdefault("wwo_id",None)
            r.setdefault("valid_from",None)
            r.setdefault("valid_to",None)
            if r["kind"]=="city":
                r["city_key"]=city_keys.get(r["unit_id"],r["unit_id"])
                r["band"]=bucket(r["population_value"])
                r["accounting_role"]="contained_city_or_unresolved_extent_never_add"
            else:
                r["accounting_role"]="source_observation_never_sum_across_sources_dates_or_levels"
            observations.append(r)
        regional_counts[f.parent.name]=n
    derived=asian_estimates(observations)
    for n,row in enumerate(derived,1):
        row.update(record_id=f"asian_interpolation:{n}",valid_from=None,valid_to=None,wwo_id=None,
                   accounting_role="alternative_reconstruction_nonadditive")
    observations.extend(derived)
    regional_counts["asian_interpolation"]=len(derived)
    selection=groups(observations, version=OPENING_VERSION)
    calcutta=next(u for g in selection for u in g["units"] if u["unit_id"]=="raj_bengal_calcutta")
    calcutta["place_evidence"]={"place:kolkata": {
        "locator": "Census of India 1901, Vol. VI-A, Table II, p. 6, Presidency Division, Calcutta row",
        "url": "https://archive.org/details/in.ernet.dli.2015.55931",
        "scope": "Calcutta as its own census account. The game place locates that account without a boundary polygon.",
    }}
    geography,dates=catalogue(observations,selection)
    for r in observations:
        # The observation date and the validity window of a WWO geography are separate.
        if r.get("wwo_id") in dates:
            r["map_reference_from"],r["map_reference_to"]=dates[r["wwo_id"]]
    study=[r for r in observations if r["source_id"].startswith("ft_world_") and r["date"]==DATE and r["kind"]=="territory"]
    controls={r["date"]:r["population_value"] for r in observations if r["unit_id"]=="ft_region_world"}
    target=controls[DATE]
    legacy=legacy_audit(study,selection)
    replaced=sum(r["role"]=="economic_statistical_unit" and r["opening_replacement"] is not None for r in legacy)
    partial=[g for g in selection if "legacy_unlocated_balance" in g]
    full=[g for g in selection if "legacy_unlocated_balance" not in g]
    total=sum(sourced_people(g) for g in selection)
    legacy_only=sum(r["population_value"] for r in legacy if r["status"]=="legacy_only")
    legacy_only += sum(g["legacy_unlocated_balance"] for g in partial)
    parts=[g for g in selection if g["units"]]
    areas=[r for r in geography if r["catalogue"]=="political_unit" and r["active"]]
    admin=[r for r in geography if r["catalogue"]=="administrative_identity"]
    cities=[r for r in observations if r["kind"]=="city"]
    city_panels=defaultdict(Counter)
    for r in cities:
        if r["band"]:
            city_panels[(r["source_id"],r["date"])][r["band"]]+=1
    rem=residuals(observations)
    located_partitions=[unit for group in parts for unit in geographic_partitions(group)]
    unlocated_partitions=[unit for group in parts for unit in group["units"] if unit.get("geographically_unlocated")]
    summary=dict(reference_date=DATE,release_status="PARTIAL",research_observations_by_collection=regional_counts,
        cited_sources=len(manifest),world_midyear=controls["1900-07-01"],world_jan1_interpolated=target,
        research_component_sum_jan1=sum(r["population_value"] for r in study),
        production_roots=len(full),partially_located_legacy_roots=len(partial),
        documented_people_under_legacy_controls=sum(sourced_people(g) for g in partial),
        replaced_legacy_roots=replaced,new_roots=len(full)-replaced,
        production_people=total,production_people_pct_world_estimate=round(100*total/target,3),
        population_outside_evidence_opening_estimate=target-total,legacy_only_people=legacy_only,
        authoritative_total_for_new_game=total+legacy_only,
        roots_with_partitions=len(parts),disjoint_leaves=len(located_partitions),
        people_in_partitions=sum(unit["population_value"] for unit in located_partitions),
        unlocated_balances_under_research_controls=[dict(unit_id=g["unit_id"], people=g["research_unlocated_balance"])
            for g in selection if "research_unlocated_balance" in g] + [dict(unit_id=unit["unit_id"], people=unit["population_value"])
            for unit in unlocated_partitions],
        partitions_with_explicit_places=sum(bool(u.get("place_ids")) for g in parts for u in g["units"]),
        people_in_partitions_with_explicit_places=sum(u["population_value"] for g in parts for u in g["units"] if u.get("place_ids")),
        political_catalogue_at_opening=len(areas),political_catalogue_with_research_candidate=sum(bool(r["study_candidates"]) for r in areas),
        political_catalogue_members_of_production_groups=sum(bool(r["opening_ids"]) for r in areas),
        dated_admin_catalogues={file:dict(units=len(sub),with_linked_observation=sum(bool(r["historical_observation_ids"]) for r in sub),
           with_opening_partition=sum(bool(r["opening_ids"]) for r in sub)) for file in sorted({r["file"] for r in admin})
           if (sub:=[r for r in admin if r["file"]==file])},
        city_observation_count=len(cities),city_keys_after_reviewed_matches=len({r["city_key"] for r in cities}),
        nonadditive_city_panels=[dict(source_id=k,date=d,bands=dict(v)) for (k,d),v in sorted(city_panels.items())],
        dated_city_remainders=len(rem),source_panels_are_nonadditive=True)
    summary["political_catalogue_with_any_statistical_candidate"]=sum(bool(r["study_candidates"] or r["historical_observation_ids"]) for r in areas)
    summary["source_statistical_units"]=sum(r["catalogue"]=="source_statistical_unit" for r in geography)
    summary["opening_by_source_type"]={}
    for label,subset in [("territorial_returns",[g for g in full if "partition_source" in g]),
                         ("historical_world_reconstruction",[g for g in full if "partition_source" not in g])]:
        summary["opening_by_source_type"][label]={"roots":len(subset),"people":sum(g["population_value"] for g in subset)}
    summary["opening_by_source_type"]["documented_subdivisions_of_legacy_control"]={"roots":len(partial),"people":sum(sourced_people(g) for g in partial)}
    city_catalog=city_index(observations,bucket)
    summary["city_index_representative_bands"]=dict(Counter(r["tier"] for r in city_catalog if r["tier"]))
    summary["city_index_unresolved"]=sum(r["representative_record"] is None for r in city_catalog)
    records("cities_1900.jsonl.gz",city_catalog)
    structural=dimensions(observations)
    structural.append(england_wales_habitations())
    structure_opening=opening_structure(selection, observations, version=OPENING_VERSION)
    social_opening=opening_social(selection, observations, version=OPENING_VERSION)
    social_coverage=Counter()
    for region in social_opening["regions"]:
        for dimension, allocation in region["marginal_distributions"].items():
            if any(source not in manifest for source in allocation["source_ids"]):
                raise ValueError((region["unit_id"], dimension, allocation["source_ids"]))
            social_coverage[dimension] += region["opening_total"] - allocation["unknown"]
    summary["opening_social_coverage"] = {
        dimension: dict(assigned_people=known, unknown_people=total+legacy_only-known)
        for dimension, known in sorted(social_coverage.items())
    }
    summary["structural_observations_by_source"]=dict(Counter(r["source_id"] for r in structural))
    summary["structure_opening_pool_controls"]=sum(g["opening_total"] for g in structure_opening["groups"])
    summary["structure_opening_pool_count"]=len(structure_opening["groups"])
    summary["structure_opening_residents_outside_modeled_pools"]=total+legacy_only-summary["structure_opening_pool_controls"]
    summary["structure_opening_scopes"]=[
        {key: group[key] for key in ("unit_id", "opening_total", "observed_unit_id", "observed_total", "observed_date")}
        for group in structure_opening["groups"]
    ]
    summary["structure_broad_observations"]=[
        dict(panel_id=panel["id"], unit_id=panel["observed_unit_id"], date=panel["observed_date"],
             population=next(row["both"] for row in rows if row["role"]=="total"),
             age_not_stated=sum(row["both"] for row in rows if row["role"]=="band" and row["age_min"] is None)
                 if panel.get("age_not_stated_separately", True) else None,
             combined_open_age_and_unreported=sum(row["both"] for row in rows if row["role"]=="mixed_age_band") or None)
        for panel,rows in age_sex_panels() if panel["broad_observation"]
    ]
    summary["structure_unknown_policy"]="Original counts stay at their observed scope and date. Compatible opening pools use model allocations. Other pools retain unknown age and sex."
    audit=comparisons(observations)
    summary["dated_parent_controls"]=len(audit)
    summary["dated_parent_controls_arithmetic_closure"]=sum(r["children_minus_parent"]==0 for r in audit)
    ledger=world_accounts(study, selection, legacy, target)
    summary["research_regions"]=ledger["research_regions"]
    summary["opening_age_sex_by_scope"]=opening_age_coverage(selection, legacy, structure_opening, ledger["opening_comparisons"])
    summary["opening_count_basis"]=opening_count_basis(selection, legacy, target)
    json_file("structure_coverage_1900.json", structural_coverage(observations, structural, geography, selection, legacy=legacy))
    json_file("world_accounts.json",ledger)
    records("demography_1900.jsonl.gz",structural)
    records("parent_reconciliation.jsonl.gz",audit)
    json_file(f"opening_v{OPENING_VERSION}.json", dict(version=OPENING_VERSION, groups=selection))
    json_file(f"opening_structure_v{OPENING_VERSION}.json", structure_opening)
    json_file(f"opening_social_v{OPENING_VERSION}.json", social_opening)
    json_file("sources.json",list(manifest.values()))
    json_file("summary.json",summary)
    json_file("legacy_audit.json",legacy)
    records("population_1900.jsonl.gz",observations)
    records("geography_1900.jsonl.gz",geography)
    records("city_remainders.jsonl.gz",rem)

if __name__=="__main__":
    import argparse
    import subprocess
    import sys

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from-sources", action="store_true", help="First regenerate regional data from the archived source files.")
    if parser.parse_args().from_sources:
        for script in sorted(COL.glob("*/build.py")):
            subprocess.run([sys.executable, str(script)], cwd=script.parent, check=True)
    main()
