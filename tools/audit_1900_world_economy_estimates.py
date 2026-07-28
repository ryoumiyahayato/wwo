#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALPHA = ROOT / "data" / "alpha"
PROFILES = ROOT / "data" / "world_map" / "historical" / "major_state_profiles_1900.json"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


def main() -> None:
    world = load(ALPHA / "historical_world_economy_1900.json")
    budgets = load(ALPHA / "historical_household_budgets_1900.json")
    transport = load(ALPHA / "historical_transport_network_1900.json")
    profiles = load(PROFILES)

    assert world["schema_id"] == "historical_world_economy_1900_estimates_v1"
    assert budgets["schema_id"] == "historical_household_budgets_1900_v1"
    assert transport["schema_id"] == "historical_transport_network_1900_estimates_v1"
    assert world["policy"]["estimated_values_allowed"] is True
    assert world["policy"]["all_estimates_require_bounds"] is True
    assert world["policy"]["silent_numeric_defaults_forbidden"] is True
    threshold = int(world["policy"]["minimum_formal_confidence_bp"])
    assert 4000 <= threshold <= 7000

    expected = {str(x["entity_id"]) for x in profiles["profiles"]}
    records = world["countries"]
    assert len(records) == 50
    ids = {str(x["entity_id"]) for x in records}
    assert ids == expected
    assert sorted(int(x["rank"]) for x in records) == list(range(1, 51))

    templates = {str(x["template_id"]) for x in budgets["templates"]}
    assert len(templates) >= 6
    for template in budgets["templates"]:
        assert sum(int(v) for v in template["shares_bp"].values()) == 10000
        assert 0 < int(template["confidence_bp"]) <= 10000

    total_formal_population = 0
    allowed = 0
    for country in records:
        population = country["population"]
        gdp = country["gdp_per_capita_2011_intl_dollars"]
        urban = country["urban_population_share_bp"]
        infrastructure = country["infrastructure"]
        production = country["production"]
        for bounded in (population, gdp, urban):
            assert float(bounded["lower"]) <= float(bounded["value"]) <= float(bounded["upper"])
            assert 0 < int(bounded["confidence_bp"]) <= 10000
        assert int(population["value"]) > 0
        assert int(gdp["value"]) > 0
        assert 0 <= int(urban["value"]) <= 10000
        assert int(infrastructure["rail_route_km_lower"]) <= int(infrastructure["rail_route_km"]) <= int(infrastructure["rail_route_km_upper"])
        assert int(infrastructure["navigable_waterway_km"]) >= 0
        assert 0 <= int(infrastructure["port_capacity_index"]) <= 100
        assert isinstance(infrastructure["major_ports"], list) and infrastructure["major_ports"]
        assert int(production["steel_output_tonnes"]) >= 0
        assert int(production["primary_energy_coal_equivalent_tonnes"]) >= 0
        assert str(country["household_budget_template_id"]) in templates
        confidence = int(country["overall_confidence_bp"])
        assert bool(country["formal_simulation_allowed"]) == (confidence >= threshold)
        allowed += int(bool(country["formal_simulation_allowed"]))
        total_formal_population += int(population["value"])

    summary = world["coverage_summary"]
    residual_population = sum(int(x["population_estimate"]) for x in world["world_residual_aggregates"])
    assert int(summary["formal_entity_population"]) == total_formal_population
    assert int(summary["residual_population"]) == residual_population
    assert 1_550_000_000 <= int(summary["estimated_world_population"]) <= 1_750_000_000
    assert allowed >= 25

    domestic = transport["domestic_networks"]
    assert len(domestic) == 50
    assert {str(x["entity_id"]) for x in domestic} == expected
    assert len(transport["international_maritime_corridors"]) >= 30
    assert len(transport["major_river_corridors"]) >= 12
    for route in transport["international_maritime_corridors"]:
        assert str(route["origin_entity_id"]) in ids
        assert str(route["destination_entity_id"]) in ids
        assert int(route["typical_duration_days"]) > 0
        assert 0 < int(route["capacity_index"]) <= 100

    source_ids = {str(x["source_id"]) for x in world["source_manifest"]}
    assert {"maddison_2023", "cow_nmc_v7", "cepii_tradhist", "bls_1901_family_budget"} <= source_ids
    print({
        "countries": len(records),
        "formal_allowed": allowed,
        "world_population": summary["estimated_world_population"],
        "sea_corridors": len(transport["international_maritime_corridors"]),
        "river_corridors": len(transport["major_river_corridors"]),
        "budget_templates": len(budgets["templates"]),
    })


if __name__ == "__main__":
    main()
