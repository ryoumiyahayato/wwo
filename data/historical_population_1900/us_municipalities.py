"""Subtract selected 1900 legal municipalities from same-date U.S. controls."""

from collections import defaultdict


DATE = "1900-06-01"
VOLUME = "us_twelfth_census_vol1"
GIBSON = "us_census_gibson_urban"
DISTRICT = "us_district_of_columbia"


def citation(row):
    fields = ("population_value", "source_id", "locator", "definition", "record_id")
    return {field: row[field] for field in fields if field in row}


def us_residuals(rows):
    same_date = [row for row in rows if row["date"] == DATE]
    controls = {
        row["unit_id"]: row for row in same_date
        if row["kind"] == "admin" and row["source_id"] == VOLUME
        and row["parent_id"] == "united_states_1900"
        and (row["unit_id"].startswith("us_state_") or row["unit_id"] == DISTRICT)
    }
    cities = {}
    for row in same_date:
        # The Honolulu footnote is outside the ranked continental U.S. series.
        if (row["kind"] == "city" and row["source_id"] == GIBSON
                and row["locator"].startswith("Table 13, rank ")):
            cities[row["unit_id"]] = dict(citation(row), unit_id=row["unit_id"],
                                         name=row["name"], parent_id=row["parent_id"])

    for row in same_date:
        if (row["kind"] != "city" or row["source_id"] != VOLUME
                or ", Table XXII, rank " not in row["locator"]):
            continue
        unit_id = row["unit_id"]
        if unit_id not in cities:
            cities[unit_id] = dict(citation(row), unit_id=unit_id,
                                   name=row["name"], parent_id=row["parent_id"])
            continue
        selected = cities[unit_id]
        alternate = citation(row)
        alternate["parent_id"] = row["parent_id"]
        alternate["status"] = (
            "boundary_conflict" if selected["parent_id"] != row["parent_id"]
            else "population_discrepancy" if selected["population_value"] != row["population_value"]
            else "same_municipality"
        )
        selected.setdefault("other_observations", []).append(alternate)

    members = defaultdict(list)
    for city in cities.values():
        if city["parent_id"] not in controls:
            raise ValueError(f'{city["unit_id"]}: no same-date state or district control')
        members[city["parent_id"]].append(city)

    # The four mainland territories have separate controls and no selected cities.
    # Alaska and Hawaii have their own enumerations.
    result = []
    for unit_id, parent in sorted(controls.items()):
        selected = sorted(members[unit_id], key=lambda city: (-city["population_value"], city["unit_id"]))
        inside = sum(city["population_value"] for city in selected)
        difference = parent["population_value"] - inside
        result.append(dict(
            parent_id=unit_id, date=DATE, source_id=VOLUME,
            parent_value=parent["population_value"], parent_locator=parent["locator"],
            city_ids=[city["unit_id"] for city in selected], cities=selected,
            identified_city_population=inside, remainder=difference if difference >= 0 else None,
            arithmetic_difference=difference,
            municipality_scope="Gibson Table 13 ranked places and documented Volume I Table XXII municipalities",
            meaning="Residents outside the selected municipalities. Includes other municipalities and rural areas.",
            status="conflict_quarantined" if difference < 0 else (
                "disjoint_subtraction" if selected else "no_listed_municipalities"
            ),
        ))
    return result


def opening_municipalities(group, rows, map_city_ids, ports_by_city):
    """Keep state totals and debit same-day, disjoint municipalities from them."""
    by_state = {entry["parent_id"]: entry for entry in us_residuals(rows)}
    leaves = []
    aggregates = []
    # Only place IDs with the same municipal scope are bound. Washington DC as
    # reported by Gibson used the district boundary, and stays in that account.
    blocked = {"washington"}
    for state in group["units"]:
        state_id = state["unit_id"]
        result = by_state.get(state_id)
        if not result or not result["cities"] or result["remainder"] is None or state_id == DISTRICT:
            leaves.append(state)
            continue
        state_count = state["population_value"]
        cities = result["cities"] if state_count > result["identified_city_population"] else []
        if not cities:
            leaves.append(state)
            continue
        city_places = set()
        for city in cities:
            key = city["unit_id"].removeprefix(state_id.replace("us_state_", "us_city_") + "_")
            places = ["place:" + key, *ports_by_city.get(key, [])] if key in map_city_ids - blocked else []
            city_places.update(places)
            leaves.append(dict(
                unit_id=city["unit_id"], name="New York City" if key == "new_york" else city["name"],
                population_value=city["population_value"], date=DATE, source_id=city["source_id"],
                locator=city["locator"], scope=city["definition"], place_ids=places,
                coextensive_place=bool(places), urban_municipality=True, statistical_parent=state_id,
                method="Use the June 1900 incorporated-place enumeration as the January opening proxy, debited from the existing state balance.",
                uncertainty_kind="Opening-date offset is unquantified; municipal boundaries follow the census.",
            ))
        leaves.append(dict(
            unit_id=state_id + "_outside_selected_cities", name=state["name"] + " outside selected cities",
            population_value=state_count - sum(city["population_value"] for city in cities),
            place_ids=[place for place in state.get("place_ids", []) if place not in city_places],
            statistical_parent=state_id,
            method="State opening balance less the non-overlapping 1900 municipal census proxy amounts.",
        ))
        aggregates.append(dict(
            unit_id=state_id, name=state["name"], population_value=state_count,
            date=group["date"], source_id=group["source_id"], locator=group["locator"],
            method="Preserve the former state opening total as the sum of its city and residual accounts.",
            uncertainty_kind=group["uncertainty_kind"],
        ))
    return dict(group, units=leaves, statistical_aggregates=aggregates)


def write_opening_v44():
    import gzip
    import json
    from pathlib import Path

    here = Path(__file__).resolve().parent
    data = here.parent
    def read(path):
        return json.loads((data / path).read_text(encoding="utf-8"))

    baseline = read("historical_population_1900/opening_v43.json")
    us, = (row for row in baseline["groups"] if row["unit_id"] == "united_states_1900")
    with gzip.open(here / "population_1900.jsonl.gz", "rt", encoding="utf-8") as file:
        rows = [json.loads(line) for line in file]
    cities = {row["id"] for row in read("world_map/cities.json")["cities"]
              if row["parent_country_id"] == "united_states"}
    for key, _, _, _, kind, start, end, polity in read(
        "alpha/historical_transport_network_1900/map_identities.json"
    )["places"]:
        if kind == "place" and polity == "united_states_1900" and start <= "1900-01-01" < end:
            cities.add(key.removeprefix("place:"))
    ports = defaultdict(list)
    for port in read("world_map/ports.json")["ports"]:
        if port["parent_country_id"] == "united_states":
            ports[port["city_id"]].append("place:" + port["id"])
    group = opening_municipalities(us, rows, cities, ports)
    manifest = dict(
        version=44, inherits=43,
        exact_inherited_places={"place:paris": "administrative_region:france_arrondissement_751"},
        groups=[group],
    )
    (here / "opening_v44.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    write_opening_v44()
