"""Social census counts at Indian princely state boundaries."""

import csv
import json
from collections import defaultdict
from pathlib import Path

from opening import MADRAS_STATES_AGE_SOURCE


COLLECTIONS = Path(__file__).resolve().parent / "collections"
GWALIOR = "raj_gwalior_state"
REMAINDER = "raj_central_india_ex_gwalior"
PARENT = "raj_central_india_agency"
TRAVANCORE = "raj_travancore_state"
COCHIN = "raj_cochin_state"
MADRAS_STATES = "raj_madras_states"
OTHER_MADRAS_STATES = "raj_madras_states_ex_cochin_travancore"


def travancore_language(pools, distribution):
    if TRAVANCORE not in pools:
        return
    path = COLLECTIONS / "india_princely_1901" / "travancore_language_1901.json"
    row = json.loads(path.read_text(encoding="utf8"))
    pool = pools[TRAVANCORE]
    if pool["endpoint_values"][-1] != row["total"] or pool["source_dates"][-1] != row["date"]:
        raise ValueError("Travancore language and population census scopes differ")
    yield TRAVANCORE, "language", distribution(
        pool["population_value"], classification="india_1901_ordinarily_used_language",
        source="india_travancore_1901_language", date=row["date"], observed_unit=TRAVANCORE,
        scope=pool["name"], locator="Table X, Part IV, printed pp. 144–145, Travancore State and continuation",
        total=row["total"], observed_counts=row["counts"], unknown=row["unknown"],
        definition="Ordinarily used language reported to the census. Cultural identity is not inferred.",
    )


def madras_states_religion(pools, distribution, table_definition):
    if TRAVANCORE not in pools:
        return
    path = COLLECTIONS / "india_princely_1901" / "religion_1901.json"
    census = json.loads(path.read_text(encoding="utf8"))
    dimension, classification, _, labels, definition = table_definition
    if tuple(census["columns"]) != labels:
        raise ValueError("The Madras States religion table has unexpected columns")
    date = census["date"]
    rows = census["rows"]
    parent = rows[MADRAS_STATES]
    states = [rows[unit_id] for unit_id in (TRAVANCORE, COCHIN)]
    for row in [parent, *states]:
        if sum(row["counts"]) + row["unknown"] != row["total"]:
            raise ValueError("The original Madras States religion table does not close")
    remainder = {"total": parent["total"] - sum(row["total"] for row in states),
                 "unknown": parent["unknown"] - sum(row["unknown"] for row in states),
                 "counts": [total - travancore - cochin for total, travancore, cochin in
                            zip(parent["counts"], *(row["counts"] for row in states), strict=True)]}
    allocations = dict(zip((TRAVANCORE, COCHIN), states, strict=True))
    if OTHER_MADRAS_STATES in pools:
        allocations[OTHER_MADRAS_STATES] = remainder
    for unit_id, row in allocations.items():
        pool = pools[unit_id]
        if (pool["statistical_parent"] != MADRAS_STATES or pool["endpoint_values"][-1] != row["total"]
                or pool["source_dates"][-1] != date):
            raise ValueError(f"{unit_id}: religion and population census scopes differ")
        locator = "Indian Empire Table 12, printed p. 107"
        if unit_id == OTHER_MADRAS_STATES:
            locator += "; Madras States less Travancore State and Cochin State"
        yield unit_id, dimension, distribution(
            pool["population_value"], classification=classification, source="india_madras_states_1901_religion",
            date=date, observed_unit=unit_id, scope=pool["name"], locator=locator,
            total=row["total"], observed_counts=dict(zip(labels, row["counts"], strict=True)),
            unknown=row["unknown"], definition=definition,
        )
    if OTHER_MADRAS_STATES not in pools:
        yield from madras_remaining_states_religion(pools, distribution, classification, remainder)


def madras_remaining_states_religion(pools, distribution, classification, aggregate):
    path = COLLECTIONS / "india_remaining_princely_demography" / "madras_states_religion_1901.csv"
    by_state = defaultdict(list)
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            by_state[row["area"]].append(row)
    labels = {"Hindu": "Hindus", "Musalman": "Muhammadans", "Christian": "Christians"}
    if len(by_state) != 3 or sum(int(row["persons"]) for rows in by_state.values() for row in rows) != aggregate["total"]:
        raise ValueError("The three Madras State religion returns do not match the remainder control")
    for state, rows in by_state.items():
        unit_id = f"raj_madras_{state}"
        pool = pools[unit_id]
        counts = {labels[row["religion"]]: int(row["persons"]) for row in rows if row["religion"] != "Others"}
        unknown = sum(int(row["persons"]) for row in rows if row["religion"] == "Others")
        dates = {row["date"] for row in rows}
        pages = {row["printed_page"] for row in rows}
        date, = dates
        page, = pages
        if date != pool["source_dates"][-1]:
            raise ValueError(f"{unit_id}: religion and population census dates differ")
        yield unit_id, "religion", distribution(
            pool["population_value"], classification=classification, source=MADRAS_STATES_AGE_SOURCE,
            date=date, observed_unit=unit_id, scope=pool["name"], locator=f"Vol. XV-A, Table VII, p. {page}",
            total=pool["endpoint_values"][-1], observed_counts=counts, unknown=unknown,
            definition="Census All Religions control and named religious returns. The residual Others group has "
                       "no individually reported religions and remains unassigned.",
        )


def india_princely_residence(pools, distribution):
    if GWALIOR not in pools:
        return

    archive = COLLECTIONS / "india_princely_1901" / "residence_1901.json"
    state_row = json.loads(archive.read_text(encoding="utf8"))
    archive = COLLECTIONS / "india_social_1901" / "census.json"
    parent_rows = json.loads(archive.read_text(encoding="utf8"))["1"]
    parent_row = next(row for row in parent_rows if row["unit_id"] == PARENT)

    total = state_row["enumerated_residents"]
    urban = state_row["urban"]
    rural = total - urban
    parent_urban, parent_rural = parent_row["counts"]
    remainder = parent_row["total"] - total
    census_date = state_row["date"]
    if (state_row["unit_id"] != GWALIOR or urban != state_row["urban_male"] + state_row["urban_female"]
            or parent_row["unknown"] != 0 or parent_urban + parent_rural != parent_row["total"]
            or pools[GWALIOR]["endpoint_values"][-1] != total or pools[REMAINDER]["endpoint_values"][-1] != remainder):
        raise ValueError("Gwalior residence counts differ from their 1901 population controls")

    for unit_id, observed_total, counts in (
        (GWALIOR, total, (urban, rural)),
        (REMAINDER, remainder, (parent_urban - urban, parent_rural - rural)),
    ):
        pool = pools[unit_id]
        if pool["statistical_parent"] != PARENT or pool["source_dates"][-1] != census_date:
            raise ValueError(f"{unit_id}: residence and population census scopes differ")
        locator = state_row["locator"]
        if unit_id == REMAINDER:
            parent_locator = ", ".join(map(str, parent_row["sheet_rows"]))
            locator += f" Deduct from Central India Agency, Statistical Abstract No. 39, Table 1, workbook row {parent_locator}."
        marginal = distribution(
            pool["population_value"], classification="india_1901_census_towns_and_rural", source=state_row["source_id"],
            date=census_date, observed_unit=unit_id, scope=pool["name"], locator=locator,
            total=observed_total, observed_counts=dict(zip(("Urban", "Rural"), counts, strict=True)), unknown=0,
            definition="The census assigns residents to towns and rural areas using its contemporary definitions.",
        )
        if unit_id == REMAINDER:
            marginal["source_ids"].append("india_statistical_abstract_1905")
        yield unit_id, "residence", marginal
