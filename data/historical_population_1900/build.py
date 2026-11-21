"""Rebuild the single research release, catalogue, accounts and Rust input offline."""
import csv
import gzip
import json
from collections import Counter, defaultdict

from pathlib import Path
from geography import catalogue, legacy_audit
from opening import groups, sourced_people
from structure import dimensions
from reconciliation import comparisons, asian_estimates
from cities import city_index
from us_municipalities import us_residuals

HERE = Path(__file__).resolve().parent
COL = HERE / "collections"
DATE = "1900-01-01"

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

def main():
    observations=[]
    manifest={}
    city_keys={}
    with (COL/"cities_europe"/"city_equivalences.csv").open(encoding="utf8") as f:
        for row in csv.DictReader(f):
            city_keys[row["member_unit_id"]]=row["city_key"]
    for f in sorted(COL.glob("*/sources.json")):
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
    selection=groups(observations)
    geography,dates=catalogue(observations,selection)
    for r in observations:
        # The observation date and the validity window of a WWO geography are separate.
        if r.get("wwo_id") in dates:
            r["map_reference_from"],r["map_reference_to"]=dates[r["wwo_id"]]
    study=[r for r in observations if r["source_id"].startswith("ft_world_") and r["date"]==DATE and r["kind"]=="territory"]
    by_area=defaultdict(list)
    for r in study:
        by_area[r["region"]].append(r)
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
    summary=dict(reference_date=DATE,release_status="PARTIAL",research_observations_by_collection=regional_counts,
        cited_sources=len(manifest),world_midyear=controls["1900-07-01"],world_jan1_interpolated=target,
        research_component_sum_jan1=sum(r["population_value"] for r in study),
        research_regions={k:dict(statistical_units=len(v),opening_research_estimate=sum(r["population_value"] for r in v),
             units_with_polity_candidates=sum(bool(r["candidate_polity_ids"]) for r in v),
             people_without_polity_candidate=sum(r["population_value"] for r in v if not r["candidate_polity_ids"]),
             grades=dict(Counter(r["quality"] for r in v))) for k,v in by_area.items()},
        production_roots=len(full),partially_located_legacy_roots=len(partial),
        documented_people_under_legacy_controls=sum(sourced_people(g) for g in partial),
        replaced_legacy_roots=replaced,new_roots=len(full)-replaced,
        production_people=total,production_people_pct_world_estimate=round(100*total/target,3),
        population_outside_evidence_opening_estimate=target-total,legacy_only_people=legacy_only,
        authoritative_total_for_new_game=total+legacy_only,
        roots_with_partitions=len(parts),disjoint_leaves=sum(len(g["units"]) for g in parts),
        people_in_partitions=sum(sourced_people(g) for g in parts),
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
    summary["structural_observations_by_source"]=dict(Counter(r["source_id"] for r in structural))
    summary["structure_unknown_policy"]="No group fractions assigned outside the original source scope. Household observations embedded in other tables remain in population records."
    audit=comparisons(observations)
    summary["dated_parent_controls"]=len(audit)
    summary["dated_parent_controls_arithmetic_closure"]=sum(r["children_minus_parent"]==0 for r in audit)
    # Coverage uses the paper's partition of the world, which places the entire
    # Russian study entry in Europe. It is not the population within continent polygons.
    from geography import aliases

    for area,metrics in summary["research_regions"].items():
        match={p for r in by_area[area] for p in r["candidate_polity_ids"]}
        assigned=[g for g in selection if set(aliases().get(g["unit_id"],[g["unit_id"]])) & match]
        opening_people=sum(sourced_people(g) for g in assigned)
        metrics.update(production_root_ids=[g["unit_id"] for g in assigned],production_people=opening_people,
                       production_pct_of_regional_research_estimate=round(100*opening_people/metrics["opening_research_estimate"],3),
                       people_with_opening_subdivision=sum(sourced_people(g) for g in assigned if g["units"]))
    records("demography_1900.jsonl.gz",structural)
    records("parent_reconciliation.jsonl.gz",audit)
    json_file("opening.json",dict(version=1,groups=selection))
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
