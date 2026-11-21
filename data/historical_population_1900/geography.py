"""Reconcile statistical scopes with dated WWO catalogues without spatial allocations."""
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE.parent
MAP = DATA / "world_map" / "historical"
DATE = "1900-01-01"

def read(path):
    return json.loads(path.read_text(encoding="utf8"))

def aliases():
    return {r["economy_entity_id"]:r["polity_ids"] for r in read(MAP / "major_economy_polity_crosswalk_1900.json")["records"]}

def link_dated_identities(rows):
    britain = read(MAP / "britain_historic_counties_identity.json")["units"]
    index = {(u["unit_type"], u["historical_name"].casefold()): u for u in britain}
    for r in rows:
        if r["unit_id"] == "somaliland_protectorate":
            r.update(wwo_id="cshapes_gw_521", mapping_status="protectorate_identity_only_no_census_boundary")
            continue
        name = r["name"].casefold()
        if r["source_id"] == "england_wales_summary_tables_1901" and r["parent_id"] in {"uk_ancient_area_england","uk_ancient_area_wales"}:
            # These are ancient counties, including the county shares of London.
            variants = {"devonshire":"devon","dorsetshire":"dorset","somersetshire":"somerset","rutlandshire":"rutland",
                        "carnarvonshire":"caernarvonshire","glamorganshire":"glamorgan"}
            unit = index.get(("historic_county_reference", variants.get(name,name)))
        elif r["source_id"] == "ireland_general_census_1911" and r["unit_id"].startswith("irish_county_"):
            borough = r["unit_id"].startswith("irish_county_borough_")
            unit = index.get(("irish_county_borough" if borough else "irish_administrative_county",
                              name.removesuffix(" county borough" if borough else " county")))
            if unit is None and name in {"king's county","queen's county"}:
                unit = index.get(("irish_administrative_county",name))
        else:
            continue
        if unit:
            r.update(wwo_id=unit["id"],mapping_status="dated_statistical_identity_boundary_not_certified")

def catalogue(rows, groups):
    link_dated_identities(rows)
    local = defaultdict(set)
    polity_studies = defaultdict(list)
    group_at = defaultdict(list)
    dates = {}
    for group in groups:
        for link in aliases().get(group["unit_id"], [group["unit_id"]]):
            group_at[link].append(group["unit_id"])
        for leaf in group["units"]:
            group_at[leaf["unit_id"]].append(leaf["unit_id"])
    for r in rows:
        if r.get("wwo_id"):
            local[r["wwo_id"].removeprefix("state:")].add(r["unit_id"])
        elif r["kind"] != "city":
            local[r["unit_id"]].add(r["unit_id"])
        if r["date"]==DATE and r["kind"]=="territory":
            for p in r.get("candidate_polity_ids", []):
                polity_studies[p].append(r["unit_id"])
    out=[]
    for p in read(MAP/"political_units_1900.json")["units"]:
        key=p["id"]
        active=p["valid_from"]<=DATE<=p["valid_to"]
        out.append(dict(catalogue="political_unit",id=key,name=p["source_name"],controller=p["controller_id"] or None,
            valid_from=p["valid_from"],valid_to=p["valid_to"],active=active,study_candidates=polity_studies[key],
            historical_observation_ids=sorted(local[key]),opening_ids=group_at[key],
            status=("catalogue_version_after_opening" if not active else "opening_group_or_collective_member" if group_at[key]
                    else "candidate_statistics_only" if polity_studies[key] or local[key] else "population_identity_unresolved")))
    for f in sorted(MAP.glob("*identity*.json")):
        for u in read(f)["units"]:
            key=u["id"]
            dates[key]=(u.get("valid_from"),u.get("valid_to"))
            out.append(dict(catalogue="administrative_identity",file=f.name,id=key,name=u.get("historical_name"),kind=u.get("unit_type"),
                polity=u.get("polity_id"),parent=u.get("parent_region_id"),valid_from=u.get("valid_from"),valid_to=u.get("valid_to"),
                geometry_status=u.get("boundary_reference_status"),historical_observation_ids=sorted(local[key]),opening_ids=group_at[key],
                status="opening_partition" if group_at[key] else "dated_population_evidence" if local[key] else "population_unknown"))
    for p in read(MAP/"historical_admin1_1900.json")["countries"]:
        for i,name in enumerate(p["units"],1):
            out.append(dict(catalogue="historical_admin1_label",id=f"{p['entity_id']}:label:{i}",name=name,polity=p["entity_id"],
                 geometry_status=p["geometry_status"],status="name_reference_only",source=p["source_basis"]))
    for u in read(MAP/"island_political_references_1900.json")["annotations"]:
        out.append(dict(catalogue="physical_island_reference",id=u["id"],name=u["name"],parent=u["political_source_id"] or None,
            valid_from=u.get("valid_from"),valid_to=u.get("valid_to"),study_candidates=polity_studies[u["political_source_id"]],
            status="political_reference_only_population_for_physical_outline_unknown",source=u["source_reference"]))
    for file, keys in [("historical_authorities_1900.json",["assignments"]),("arabia_authority_coverage_1900.json",["assignments","map_display_records","unresolved_regions"])]:
        for field in keys:
            for u in read(MAP/file)[field]:
                out.append(dict(catalogue="arabian_authority_or_display",file=file,id=u.get("id",f"unresolved:{u.get('component_index')}"),
                     name=u.get("name_zh"),kind=field,status="no_population_geometry_allocation"))
    for p in read(DATA/"world_map"/"cities.json")["cities"]:
        key="place:"+p["id"]
        out.append(dict(catalogue="prototype_place",id=key,name=p["name"],prototype_parent=p["parent_country_id"],
                     historical_observation_ids=sorted(local[key]),status="place_identity" if local[key] else "no_linked_city_observation"))
    # Source-only statistical territories remain searchable when no dated WWO polygon exists.
    identities=defaultdict(list)
    for r in rows:
        if r["kind"] in {"country","territory","admin"} and not r["source_id"].startswith("ft_world_"):
            identities[r["unit_id"]].append(r)
    opening_ids={g["unit_id"] for g in groups} | {u["unit_id"] for g in groups for u in g["units"]}
    for key, observed in sorted(identities.items()):
        out.append(dict(catalogue="source_statistical_unit",id=key,name=observed[0]["name"],
            source_ids=sorted({r["source_id"] for r in observed}),observation_dates=sorted({r["date"] for r in observed}),
            parent_ids=sorted({r["parent_id"] for r in observed if r["parent_id"]}),
            wwo_identity_links=sorted({r["wwo_id"] for r in observed if r.get("wwo_id")}),
            status="opening_unit" if key in opening_ids else "dated_evidence_only",
            observation_ids=[r["record_id"] for r in observed]))
    blockers={
        "ft_china":"Alternative Qing household, Customs and reconstructed province totals differ. Taiwan, concessions, frontier populations and retrospective province boundaries require explicit remapping.",
        "ft_mongolia":"Outside the Cao provincial return but inside the Qing political unit. Outer Mongolia and Tannu Uriankhai require a separate population and boundary reconciliation.",
        "ft_india":"Census enumeration expanded in the Burma and frontier areas. The imperial return also includes Aden outside the WWO India boundary. See eastern/reconciliation.json.",
        "ft_egypt":"Nomad corrections and western oases in the WWO footprint do not have an established census allocation. See eastern/reconciliation.json.",
        "ft_formosa_taiwan":"The Governor-General registers separately list island residents and foreigners. The garrison and Orchid Island lack a comparable complete return.",
        "ft_south_africa":"The 1904 post-war population includes personnel and territory transfers. A single retrospective Union total cannot replace four separate opening polities.",
        "ft_german_east_africa":"Separate Rwanda/Burundi series and the Tanganyika series share one political map identifier.",
        "ft_rwanda_and_burundi":"German East Africa includes this study unit; a separate Rwanda/Burundi opening boundary is unavailable.",
        "ft_austria_hungary":"The historical research total includes the administered provinces of Bosnia and Herzegovina, which also have separate WWO political identities.",
        "ft_denmark":"The study discusses Greenland and Faroese series jointly with Denmark. Their share and coverage cannot be inferred from the Denmark column.",
        "ft_melanesia":"Regional group spans several colonial administrations and smaller islands outside those WWO polygons.",
        "ft_micronesia":"Regional group includes Guam and other archipelagos; no mutually exclusive per-island opening allocation.",
        "ft_polynesia":"Archipelago-level allocation and islands outside the map catalogue require separate controls."
    }
    for r in rows:
        if r["date"]==DATE and r.get("source_id","").startswith("ft_world_") and r["kind"]=="territory":
            links=sorted({g for key in r["candidate_polity_ids"] for g in group_at[key]})
            why=blockers.get(r["unit_id"]) or r.get("scope_note") or (
                 "No matching political unit in the opening catalogue." if not r["candidate_polity_ids"] else
                 "A candidate political identity is known. Its source coverage and excluded territories have not been verified for the opening.")
            if links:
                why="Matched to opening scopes listed here; the source value is retained as a comparator. Opening totals and any finer divisions use their cited sources."

            out.append(dict(catalogue="research_territory",id=r["unit_id"],name=r["name"],region=r["region"],
                population_value=r["population_value"],population_lower=r["population_lower"],population_upper=r["population_upper"],
                quality=r["quality"],source_id=r["source_id"],locator=r["locator"],candidate_polity_ids=r["candidate_polity_ids"],
                scope_note=r["scope_note"],status=r["mapping_status"],opening_candidates=links,
                opening_disposition="comparison_with_opening_scopes" if links else "research_only",accounting_note=why))
    for key,note in [
        ("antarctica","Contemporaneous expedition parties and temporary bases require dated personnel records; no permanent household census adopted."),
        ("liechtenstein","Official 1891/1901 returns for all 11 municipalities and 1900 mean of 7,520 are in the Liechtenstein collection. No separate WWO or study unit; inclusion in adjacent research totals unresolved."),
        ("san_marino","No separate study column; inclusion in Italy has not been confirmed."),
        ("channel_islands_and_isle_of_man","UK excludes the islands. The crown_islands collection gives Jersey’s 12 parishes and island controls for Jersey, Guernsey and the Isle of Man. Independent opening scopes and geometry remain unresolved."),
        ("svalbard","Seasonal/industrial settlement needs dated evidence; no allocation from Norway."),
        ("greenland_remote_districts","Danish western colonial returns and east coast enumerations have different coverage. Other Inuit settlements cannot be inferred."),
        ("pacific_small_islands","Study aggregates Micronesia, Polynesia and Melanesia. Disaggregation and enumeration of outer islands remain open."),
        ("mobile_and_unenumerated","Nomadic, Indigenous, maritime and other populations omitted by historic enumerators remain unknown unless explicitly estimated.")]:
        out.append(dict(catalogue="named_coverage_gap",id=key,status="unresolved",note=note))
    return out, dates

def legacy_audit(study, groups):
    raw=read(DATA/"alpha"/"historical_world_economy_1900"/"countries_compact.json")
    manifest=read(DATA/"alpha"/"historical_world_economy_1900.json")
    g={x["unit_id"]:x for x in groups}
    out=[]
    for data in raw["rows"]:
        old=dict(zip(raw["field_order"],data))
        key=old["entity_id"]
        links=aliases().get(key,[key])
        refs=[r for r in study if set(links).intersection(r["candidate_polity_ids"])]
        root=g.get(key)
        out.append(dict(unit_id=key,role="economic_statistical_unit",candidate_polities=links,
             population_value=old["population_value"],population_lower=old["population_lower"],population_upper=old["population_upper"],
             source_year_or_day=None,original_table=None,per_unit_citation=None,legacy_method=raw["common_methods"].get("population",raw["common_methods"].get("population_method")),
             published_confidence_bp=old["population_confidence_bp"],research_candidates=[r["unit_id"] for r in refs],
             opening_replacement=root["population_value"] if root else None,
             replacement_minus_legacy=root["population_value"]-old["population_value"] if root else None,
             status="replaced_for_new_games" if root else "legacy_only",
             comparison="Arithmetic change in authoritative opening; old census date and territorial inclusions are undocumented."))
    residual_names={"residual:dutch_east_indies":["ft_dutch_east_indies_indonesia"],"residual:philippines":["ft_philippines"],
                    "residual:french_indochina":["ft_french_indochina"]}
    for x in manifest["world_residual_aggregates"]:
        key=x["aggregate_id"]
        out.append(dict(unit_id=key,role="excluded_economic_residual",population_value=x["population_estimate"],
                     controller=x["controller_entity_id"] or None,published_confidence_bp=x["confidence_bp"],source_year_or_day=None,
                     original_table=None,per_unit_citation=None,research_candidates=residual_names.get(key,[]),
                     status="not_a_population_partition",comparison="No exclusive list of component territories in legacy source; never allocate by controller."))
    return out
