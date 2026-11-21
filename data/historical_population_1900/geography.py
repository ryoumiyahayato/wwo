"""Reconcile statistical scopes with dated WWO catalogues without spatial allocations."""
import csv
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

def opening_scope_links(groups, study):
    """Join reviewed statistical extents, independently of political map aliases."""
    roots = {group["unit_id"] for group in groups}
    units = {row["unit_id"]: row for row in study}
    used_roots, used_units, comparisons = set(), set(), []
    with (HERE / "opening_geography.tsv").open(encoding="utf8") as source:
        for row in csv.DictReader(source, delimiter="\t"):
            opening_ids = row["opening_roots"].split()
            research_ids = row["research_units"].split()
            if roots.isdisjoint(opening_ids):
                continue
            if (not roots.issuperset(opening_ids) or not units.keys() >= set(research_ids)
                    or not used_roots.isdisjoint(opening_ids) or not used_units.isdisjoint(research_ids)):
                raise ValueError(f"Invalid opening scope comparison: {row['comparison_id']}")
            comparisons.append(dict(comparison_id=row["comparison_id"], opening_root_ids=opening_ids,
                research_unit_ids=research_ids, scope_relation=row["scope_relation"], note=row["note"]))
            used_roots.update(opening_ids)
            used_units.update(research_ids)
    for group in groups:
        root = group["unit_id"]
        if root in used_roots:
            continue
        ids = group.get("research_unit_ids", [])
        if not units.keys() >= set(ids) or not used_units.isdisjoint(ids):
            raise ValueError(f"Invalid opening series link: {root}")
        comparisons.append(dict(comparison_id=root, opening_root_ids=[root], research_unit_ids=ids,
            scope_relation="adopted_research_series" if ids else "opening_without_benchmark_link",
            note=group["scope"]))
        used_units.update(ids)
    return comparisons


_RESEARCH_SCOPE_NOTES = {
    "ft_algeria": "Appendix I uses Maravall-Buckwalter's corrected population, anchored on the 1906 return including the Territories of the South. Their opening-day extent remains unresolved. Metropolitan France excludes Algeria.",
    "ft_morocco": "Appendix I projects backwards from separate French and northern Spanish protectorate counts plus Tangier. Adequacy of the southern frontier coverage for the 1900 Sultanate remains unresolved. Spanish Sahara, Ceuta and Melilla have separate study series.",
    "ft_paraguay": "Appendix I uses the Pérez-Brignoli reconstruction. The contemporary Argentine consular table separately estimates the western Chaco. Boundaries and Indigenous coverage need reconciliation with the legacy geography.",
    "ft_liberia": "The Frankema–Jerven projection uses later national boundaries and population anchors. The 1900 inland scope and the widely varying contemporary estimates are unresolved.",
    "ft_belgium_congo": "The retrospective Congo population uses later enumeration anchors. The Congo Free State's opening boundary and actual geographic coverage require review before replacing the legacy account.",
    "ft_zanzibar_island": "The study interpolates from British estimates and omits the 1901 estimate. The source description does not establish the inclusion of Pemba in the Zanzibar Islands opening control.",
    "ft_china": "Alternative Qing household, Customs and reconstructed province totals differ. Taiwan, concessions, frontier populations and retrospective province boundaries require explicit remapping.",
    "ft_mongolia": "Outer Mongolia and Tannu Uriankhai require independent statistical and boundary reconciliation. The selected Cao provincial returns contain neither.",
    "ft_philippines": "The March 1903 census includes Cagayan de Jolo and Sibutu, named in the November 1900 treaty effective March 1901. Bulletin 1 tables 2 pp. 15, 18 count 2,000 and 280 respectively. Opening-date counts for those islands and dependencies are unresolved.",
    "ft_india": "The imperial census includes Aden. Enumeration expanded in Burma and other frontier areas. See collections/india_comparable for the comparable reporting units and retained balance.",
    "ft_egypt": "Nomad corrections and western oases in the WWO footprint lack a reconciled census allocation. See collections/eastern/reconciliation.json.",
    "ft_formosa_taiwan": "Residents and foreigners are separately registered. The garrison and Orchid Island lack a comparable complete return.",
    "ft_south_africa": "1904 was a postwar census. The 1903 Natal boundary change and other territorial and enumeration changes require separate reconciliation for the four opening polities.",
    "ft_german_east_africa": "The reconstructed Tanganyika and Rwanda/Burundi series share a political map identifier. Their study units have separate values.",
    "ft_rwanda_and_burundi": "This unit and Tanganyika have separate research series. A separate Rwanda/Burundi opening boundary is unavailable.",
    "ft_nigeria": "The reconstruction covers the later Nigeria territory. Lagos and the Northern and Southern protectorates require separate territorial controls; the Lagos return covers Lagos alone.",
    "ft_french_west_africa": "The reconstructed regional control spans several 1900 administrations. Component boundaries and counts need reconciliation before allocation.",
    "ft_ethiopia": "The historical reconstruction covers areas whose political administration and census coverage changed. V5 revises the older estimates using Frankema and Jerven and supplies no opening subdivision.",
    "ft_sudan_anglo_egyptian_sudan": "The V5 revision changes the reconstructed national trajectory. Condominium control, Darfur and retrospective series boundaries require a dated crosswalk.",
    "ft_italian_somaliland": "V5 cites Frankema and Jerven for Somalia. Inclusion of British Somaliland must be established before using it alongside separate protectorate returns.",
    "ft_denmark": "The study discusses Greenland and Faroese series jointly with Denmark. Their individual series and the metropole require separate coverage checks.",
    "ft_melanesia": "The study includes eastern New Guinea here and western New Guinea in Dutch East Indies. Other islands span several colonial administrations and unmapped coastal and interior census scopes.",
    "ft_micronesia": "The regional total includes Guam and other archipelagos. A mutually exclusive island allocation is unavailable.",
    "ft_polynesia": "Archipelago-level allocation and islands outside the map catalogue require separate controls.",
}


def research_scope_note(row):
    return _RESEARCH_SCOPE_NOTES.get(row["unit_id"]) or row.get("scope_note") or (
        "No matching political unit in the opening catalogue." if not row["candidate_polity_ids"] else
        "The political candidates require a review of source coverage and territorial exclusions.")


def link_dated_identities(rows):
    britain = read(MAP / "britain_historic_counties_identity.json")["units"]
    index = {(u["unit_type"], u["historical_name"].casefold()): u for u in britain}
    for r in rows:
        if r["unit_id"] == "somaliland_protectorate":
            r.update(wwo_id="cshapes_gw_521", mapping_status="protectorate_identity_only_no_census_boundary")
            continue
        if r.get("wwo_id"):
            continue
        name = r["name"].casefold()
        if r["source_id"] == "england_wales_summary_tables_1901" and r["parent_id"] in {"uk_ancient_area_england","uk_ancient_area_wales"}:
            # These are ancient counties, including the county shares of London.
            variants = {"devonshire":"devon","dorsetshire":"dorset","somersetshire":"somerset","rutlandshire":"rutland",
                        "carnarvonshire":"caernarvonshire","glamorganshire":"glamorgan"}
            unit = index.get(("historic_county_reference", name)) or index.get(("historic_county_reference", variants.get(name,name)))
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
    shared_openings = defaultdict(set)
    source_openings = defaultdict(set)
    label_openings = {}
    partial_roots = {g["unit_id"] for g in groups if "legacy_unlocated_balance" in g}
    dates = {}
    for group in groups:
        scope = group.get("collective_scope")
        links = scope["polity_ids"] if scope else aliases().get(group["unit_id"], [group["unit_id"]])
        for link in links:
            group_at[link].append(group["unit_id"])
            if scope:
                local[link].add(group["unit_id"])
        for leaf in group["units"]:
            key = leaf["unit_id"]
            group_at[key].append(key)
            if leaf.get("wwo_admin_label"):
                label_openings[leaf["wwo_admin_label"]] = key
            for member in leaf.get("member_region_ids", []):
                if member != key:
                    shared_openings[member].add(key)
            for source_unit in leaf.get("source_unit_ids", []):
                source_openings[source_unit].add(key)
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
            status=("catalogue_version_after_opening" if not active else "legacy_control_with_verified_subdivisions" if key in partial_roots else "opening_group_or_collective_member" if group_at[key]
                    else "candidate_statistics_only" if polity_studies[key] or local[key] else "population_identity_unresolved")))
    for f in sorted(MAP.glob("*identity*.json")):
        for u in read(f)["units"]:
            key=u["id"]
            dates[key]=(u.get("valid_from"),u.get("valid_to"))
            out.append(dict(catalogue="administrative_identity",file=f.name,id=key,name=u.get("historical_name"),kind=u.get("unit_type"),
                polity=u.get("polity_id"),parent=u.get("parent_region_id"),valid_from=u.get("valid_from"),valid_to=u.get("valid_to"),
                geometry_status=u.get("boundary_reference_status"),historical_observation_ids=sorted(local[key]),opening_ids=group_at[key],
                shared_opening_ids=sorted(shared_openings[key]),
                status="opening_partition" if group_at[key] else "member_of_shared_partition" if shared_openings[key] else "dated_population_evidence" if local[key] else "population_unknown"))
    for p in read(MAP/"historical_admin1_1900.json")["countries"]:
        for i,name in enumerate(p["units"],1):
            key = f"{p['entity_id']}:label:{i}"
            out.append(dict(catalogue="historical_admin1_label",id=key,name=name,polity=p["entity_id"],
                 geometry_status=p["geometry_status"],status="linked_statistical_identity_no_polygon" if key in label_openings else "name_reference_only",
                 opening_id=label_openings.get(key),source=p["source_basis"]))
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
        if r["kind"] in {"country","territory","historical_territory","admin"} and not r["source_id"].startswith("ft_world_"):
            identities[r["unit_id"]].append(r)
    opening_ids={g["unit_id"] for g in groups} | {u["unit_id"] for g in groups for u in g["units"]}
    for key, observed in sorted(identities.items()):
        out.append(dict(catalogue="source_statistical_unit",id=key,name=observed[0]["name"],
            source_ids=sorted({r["source_id"] for r in observed}),observation_dates=sorted({r["date"] for r in observed}),
            parent_ids=sorted({r["parent_id"] for r in observed if r["parent_id"]}),
            wwo_identity_links=sorted({r["wwo_id"] for r in observed if r.get("wwo_id")}),
            opening_partition_links=sorted(source_openings[key]),
            status="opening_unit" if key in opening_ids else "linked_to_opening_partition" if source_openings[key] else "dated_evidence_only",
            observation_ids=[r["record_id"] for r in observed]))
    study = [r for r in rows if r["date"] == DATE and r["source_id"].startswith("ft_world_") and r["kind"] == "territory"]
    scope_links = {k: link for link in opening_scope_links(groups, study) for k in link["research_unit_ids"]}
    for r in study:
        link = scope_links.get(r["unit_id"])
        links = link["opening_root_ids"] if link else []
        disposition = "research_only"
        if link:
            disposition = "partially_located_legacy_control" if all(key in partial_roots for key in links) else "comparison_with_opening_scopes"
        out.append(dict(catalogue="research_territory",id=r["unit_id"],name=r["name"],region=r["region"],
            population_value=r["population_value"],population_lower=r["population_lower"],population_upper=r["population_upper"],
            quality=r["quality"],source_id=r["source_id"],locator=r["locator"],candidate_polity_ids=r["candidate_polity_ids"],
            scope_note=r["scope_note"],status=r["mapping_status"],opening_candidates=links,
            comparison_id=link["comparison_id"] if link else None, opening_disposition=disposition,
            accounting_note=link["note"] if link else research_scope_note(r)))
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
        partial=root is not None and "legacy_unlocated_balance" in root
        out.append(dict(unit_id=key,role="economic_statistical_unit",candidate_polities=links,
             population_value=old["population_value"],population_lower=old["population_lower"],population_upper=old["population_upper"],
             source_year_or_day=None,original_table=None,per_unit_citation=None,legacy_method=raw["common_methods"].get("population",raw["common_methods"].get("population_method")),
             published_confidence_bp=old["population_confidence_bp"],research_candidates=[r["unit_id"] for r in refs],
             opening_replacement=root["population_value"] if root and not partial else None,
             legacy_unlocated_balance=root["legacy_unlocated_balance"] if partial else None,
             replacement_minus_legacy=root["population_value"]-old["population_value"] if root else None,
             status="legacy_control_with_verified_subdivisions" if partial else "replaced_for_new_games" if root else "legacy_only",
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
