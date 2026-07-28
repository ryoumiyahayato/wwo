#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALPHA = ROOT / "data" / "alpha"
HISTORICAL = ROOT / "data" / "world_map" / "historical"
PROFILES = HISTORICAL / "major_state_profiles_1900.json"
POLITICAL_UNITS = HISTORICAL / "political_units_1900.json"
CROSSWALK = HISTORICAL / "major_economy_polity_crosswalk_1900.json"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


def rows_to_dicts(document: dict, prefix: str) -> list[dict]:
    fields = document[f"{prefix}_field_order"]
    return [dict(zip(fields, row, strict=True)) for row in document[f"{prefix}_rows"]]


def audit_crosswalk(expected: set[str], unit_ids: set[str], document: dict) -> set[str]:
    assert document["schema_id"] == "major_economy_polity_crosswalk_1900_v1"
    policy = document["policy"]
    assert policy["economy_count_is_not_world_polity_count"] is True
    assert policy["one_economy_may_cover_multiple_map_units"] is True
    records = document["records"]
    economy_ids: set[str] = set()
    covered_ids: set[str] = set()
    for record in records:
        economy_id = str(record["economy_entity_id"])
        polity_ids = [str(value) for value in record["polity_ids"]]
        assert economy_id in expected and economy_id not in economy_ids
        assert polity_ids and all(value in unit_ids for value in polity_ids)
        assert not covered_ids.intersection(polity_ids)
        economy_ids.add(economy_id)
        covered_ids.update(polity_ids)
    assert expected - unit_ids == economy_ids
    assert economy_ids == {"australia_colonies_1900", "kingdom_of_luxembourg"}
    assert len(covered_ids) == 7
    return covered_ids


def main() -> None:
    world = load(ALPHA / "historical_world_economy_1900.json")
    countries_table = load(ALPHA / "historical_world_economy_1900" / "countries_compact.json")
    budgets = load(ALPHA / "historical_household_budgets_1900.json")
    transport = load(ALPHA / "historical_transport_network_1900.json")
    transport_table = load(ALPHA / "historical_transport_network_1900" / "transport_compact.json")
    profiles = load(PROFILES)
    political_units = load(POLITICAL_UNITS)
    crosswalk = load(CROSSWALK)

    assert world["schema_id"] == "historical_world_economy_1900_estimates_v1"
    assert countries_table["schema_id"] == "historical_world_economy_1900_compact_country_table_v1"
    assert budgets["schema_id"] == "historical_household_budgets_1900_v1"
    assert transport["schema_id"] == "historical_transport_network_1900_estimates_v1"
    assert transport_table["schema_id"] == "historical_transport_network_1900_compact_tables_v1"
    assert world["policy"]["all_estimates_require_bounds"] is True
    assert world["policy"]["silent_numeric_defaults_forbidden"] is True
    threshold = int(world["policy"]["minimum_formal_confidence_bp"])
    assert threshold == 4500

    fields = countries_table["field_order"]
    countries = [dict(zip(fields, row, strict=True)) for row in countries_table["rows"]]
    expected = {str(value["entity_id"]) for value in profiles["profiles"]}
    assert len(countries) == len(expected) == 50
    assert {str(value["entity_id"]) for value in countries} == expected
    assert sorted(int(value["rank"]) for value in countries) == list(range(1, 51))

    unit_ids = {str(value["id"]) for value in political_units["units"]}
    assert int(political_units["unit_count"]) == len(unit_ids) == 151
    crosswalk_polity_ids = audit_crosswalk(expected, unit_ids, crosswalk)
    direct_ids = expected.intersection(unit_ids)
    detailed_polity_ids = direct_ids.union(crosswalk_polity_ids)
    assert len(direct_ids) == 48
    assert len(detailed_polity_ids) == 55
    assert len(unit_ids - detailed_polity_ids) == 96

    templates = {str(value["template_id"]): value for value in budgets["templates"]}
    assert len(templates) >= 6
    for template in templates.values():
        assert sum(int(value) for value in template["shares_bp"].values()) == 10000
        assert 0 < int(template["confidence_bp"]) <= 10000

    population_total = 0
    formal_count = 0
    for country in countries:
        for prefix, confidence_field in (
            ("population", "population_confidence_bp"),
            ("gdp_pc", "gdp_confidence_bp"),
        ):
            assert float(country[f"{prefix}_lower"]) <= float(country[f"{prefix}_value"]) <= float(country[f"{prefix}_upper"])
            assert 0 < int(country[confidence_field]) <= 10000
        assert int(country["urban_lower_bp"]) <= int(country["urban_value_bp"]) <= int(country["urban_upper_bp"])
        assert int(country["rail_lower_km"]) <= int(country["rail_route_km"]) <= int(country["rail_upper_km"])
        assert str(country["household_budget_template_id"]) in templates
        confidence = int(country["overall_confidence_bp"])
        assert bool(country["formal_simulation_allowed"]) == (confidence >= threshold)
        population_total += int(country["population_value"])
        formal_count += int(bool(country["formal_simulation_allowed"]))

    summary = world["coverage_summary"]
    residual_population = sum(int(value["population_estimate"]) for value in world["world_residual_aggregates"])
    assert population_total == int(summary["formal_entity_population"])
    assert residual_population == int(summary["residual_population"])
    assert population_total + residual_population == int(summary["estimated_world_population"])
    assert 1_550_000_000 <= int(summary["estimated_world_population"]) <= 1_750_000_000
    assert formal_count >= 25

    domestic = rows_to_dicts(transport_table, "domestic")
    maritime = rows_to_dicts(transport_table, "maritime")
    rivers = rows_to_dicts(transport_table, "river")
    assert len(domestic) == 50
    assert {str(value["entity_id"]) for value in domestic} == expected
    assert len(maritime) >= 30 and len(rivers) >= 12
    for route in maritime:
        assert str(route["origin_entity_id"]) in expected
        assert str(route["destination_entity_id"]) in expected
        assert int(route["duration_days"]) > 0

    source_ids = {str(value["source_id"]) for value in world["source_manifest"]}
    assert {"maddison_2023", "cow_nmc_v7", "cepii_tradhist", "bls_1901_family_budget"} <= source_ids
    print({
        "major_economies": len(expected),
        "world_political_units": len(unit_ids),
        "detailed_polity_units": len(detailed_polity_ids),
        "background_polity_units": len(unit_ids - detailed_polity_ids),
        "crosswalk_economies": sorted(expected - unit_ids),
        "estimated_world_population": summary["estimated_world_population"],
        "sea_corridors": len(maritime),
        "river_corridors": len(rivers),
    })


if __name__ == "__main__":
    main()
