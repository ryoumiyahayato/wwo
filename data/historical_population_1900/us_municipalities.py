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
