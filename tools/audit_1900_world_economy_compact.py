#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALPHA = ROOT / "data" / "alpha"
PROFILES = ROOT / "data" / "world_map" / "historical" / "major_state_profiles_1900.json"
POLITICAL_UNITS = ROOT / "data" / "world_map" / "historical" / "political_units_1900.json"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


def rows_to_dicts(document: dict, prefix: str) -> list[dict]:
    fields = document[f"{prefix}_field_order"]
    return [dict(zip(fields, row, strict=True)) for row in document[f"{prefix}_rows"]]


def main() -> None:
    world = load(ALPHA / "historical_world_economy_1900.json")
    countries_table = load(ALPHA / "historical_world_economy_1900" / "countries_compact.json")
    budgets = load(ALPHA / "historical_household_budgets_1900.json")
    transport = load(ALPHA / "historical_transport_network_1900.json")
    transport_table = load(ALPHA / "historical_transport_network_1900" / "transport_compact.json")
    profiles = load(PROFILES)
    political_units = load(POLITICAL_UNITS)

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
    assert len(countries) == 50
    expected = {str(x["entity_id"]) for x in profiles["profiles"]}
    assert {str(x["entity_id"]) for x in countries} == expected
    assert sorted(int(x["rank"]) for x in countries) == list(range(1, 51))

    unit_ids = {str(x["id"]) for x in political_units["units"]}
    missing_map_crosswalk = sorted(expected - unit_ids)
    assert int(political_units["unit_count"]) == len(unit_ids) == 151

    templates = {str(x["template_id"]): x for x in budgets["templates"]}
    assert len(templates) >= 6
    for template in templates.values():
        assert sum(int(value) for value in template["shares_bp"].values()) == 10000
        assert 0 < int(template["confidence_bp"]) <= 10000

    population_total = 0
    formal_count = 0
    bounded_fields = (
        ("population", "population_confidence_bp"),
        ("gdp_pc", "gdp_confidence_bp"),
    )
    for country in countries:
        for prefix, confidence_field in bounded_fields:
            assert float(country[f"{prefix}_lower"]) <= float(country[f"{prefix}_value"]) <= float(country[f"{prefix}_upper"])
            assert 0 < int(country[confidence_field]) <= 10000
        assert int(country["urban_lower_bp"]) <= int(country["urban_value_bp"]) <= int(country["urban_upper_bp"])
        assert 0 < int(country["urban_confidence_bp"]) <= 10000
        assert int(country["rail_lower_km"]) <= int(country["rail_route_km"]) <= int(country["rail_upper_km"])
        assert 0 <= int(country["port_capacity_index"]) <= 100
        assert 0 <= int(country["merchant_shipping_index"]) <= 100
        assert isinstance(country["major_ports"], list) and country["major_ports"]
        assert str(country["household_budget_template_id"]) in templates
        confidence = int(country["overall_confidence_bp"])
        assert bool(country["formal_simulation_allowed"]) == (confidence >= threshold)
        population_total += int(country["population_value"])
        formal_count += int(bool(country["formal_simulation_allowed"]))

    summary = world["coverage_summary"]
    residual_population = sum(int(x["population_estimate"]) for x in world["world_residual_aggregates"])
    assert population_total == int(summary["formal_entity_population"])
    assert residual_population == int(summary["residual_population"])
    assert population_total + residual_population == int(summary["estimated_world_population"])
    assert 1_550_000_000 <= int(summary["estimated_world_population"]) <= 1_750_000_000
    assert formal_count >= 25

    domestic = rows_to_dicts(transport_table, "domestic")
    maritime = rows_to_dicts(transport_table, "maritime")
    rivers = rows_to_dicts(transport_table, "river")
    assert len(domestic) == 50
    assert {str(x["entity_id"]) for x in domestic} == expected
    assert len(maritime) >= 30
    assert len(rivers) >= 12
    for route in maritime:
        assert str(route["origin_entity_id"]) in expected
        assert str(route["destination_entity_id"]) in expected
        assert int(route["duration_days"]) > 0
        assert 0 < int(route["capacity_index"]) <= 100
        assert 0 < int(route["confidence_bp"]) <= 10000

    source_ids = {str(x["source_id"]) for x in world["source_manifest"]}
    assert {"maddison_2023", "cow_nmc_v7", "cepii_tradhist", "bls_1901_family_budget"} <= source_ids
    print({
        "countries": len(countries),
        "formal_allowed": formal_count,
        "world_political_units": len(unit_ids),
        "major_polities_missing_direct_map_id": missing_map_crosswalk,
        "estimated_world_population": summary["estimated_world_population"],
        "sea_corridors": len(maritime),
        "river_corridors": len(rivers),
        "budget_templates": len(templates),
    })


if __name__ == "__main__":
    main()
