#!/usr/bin/env python3
"""Static audit for the phase-two unified 1900 economy configuration."""

from __future__ import annotations

import json
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTEGRATION_PATH = ROOT / "data/alpha/economy_integration_1900.json"
COVERAGE_PATH = ROOT / "data/alpha/historical_economy_coverage_1900.json"
COMMODITY_PATH = ROOT / "data/alpha/commodity_market_1900.json"
WORLD_PATH = ROOT / "data/alpha/world.json"
ECONOMY_PATH = ROOT / "data/alpha/economy.json"


def load(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    assert isinstance(value, dict), f"{path} root must be an object"
    return value


def unique(records: list[dict], field: str, label: str) -> set[str]:
    values = [str(record.get(field, "")) for record in records]
    assert all(values), f"{label} contains empty {field}"
    assert len(values) == len(set(values)), f"{label} contains duplicate {field}"
    return set(values)


def main() -> None:
    integration = load(INTEGRATION_PATH)
    coverage = load(COVERAGE_PATH)
    commodity = load(COMMODITY_PATH)
    world = load(WORLD_PATH)
    economy = load(ECONOMY_PATH)

    assert integration.get("schema_id") == "alpha_economy_integration_1900_v1"
    assert coverage.get("schema_id") == "historical_economy_coverage_1900_v1"
    assert integration.get("calibration_year") == 1900
    assert coverage.get("calibration_year") == 1900

    strata = integration.get("household_strata", [])
    assert len(strata) >= 3
    assert sum(int(item.get("population_bp", 0)) for item in strata) == 10_000
    assert sum(int(item.get("budget_share_bp", 0)) for item in strata) == 10_000
    assert all(int(item.get("opening_cash_per_person_centimes", -1)) >= 0 for item in strata)

    world_regions = unique(world.get("region_profiles", []), "region_id", "world regions")
    regions = integration.get("regions", [])
    region_ids = unique(regions, "region_id", "integration regions")
    assert len(region_ids) == 8, region_ids
    assert region_ids == world_regions, (region_ids, world_regions)
    assert all(str(record.get("market_id", "")) for record in regions)
    assert all(str(record.get("household_id", "")) for record in regions)
    assert all(int(record.get("market_opening_cash_centimes", -1)) >= 0 for record in regions)

    countries = integration.get("countries", [])
    country_ids = unique(countries, "country_id", "integration countries")
    assert len(country_ids) == 2
    for country in countries:
        assert str(country.get("treasury_id", ""))
        assert str(country.get("central_bank_id", ""))
        assert str(country.get("currency_id", ""))
        assert float(country.get("gold_reserve_grams", 0)) > 0
        assert int(country.get("parity_centimes_per_gram", 0)) > 0
        assert int(country.get("opening_exchange_rate_bp", 0)) > 0

    region_country = {str(r["region_id"]): str(r["country_id"]) for r in regions}
    assert set(region_country.values()) <= country_ids

    edges = integration.get("transport_edges", [])
    edge_ids = unique(edges, "edge_id", "transport edges")
    assert len(edge_ids) == 9
    graph: dict[str, set[str]] = defaultdict(set)
    for edge in edges:
        source = str(edge.get("from_region_id", ""))
        target = str(edge.get("to_region_id", ""))
        assert source in region_ids and target in region_ids and source != target
        assert int(edge.get("duration_hours", 0)) > 0
        assert float(edge.get("capacity_units_per_day", 0)) > 0
        assert int(edge.get("cost_centimes_per_unit", -1)) >= 0
        assert 0 <= int(edge.get("risk_bp", -1)) <= 10_000
        assert str(edge.get("carrier_id", ""))
        graph[source].add(target)
        if bool(edge.get("bidirectional", False)):
            graph[target].add(source)
    visited: set[str] = set()
    queue = deque([next(iter(region_ids))])
    while queue:
        node = queue.popleft()
        if node in visited:
            continue
        visited.add(node)
        queue.extend(graph[node] - visited)
    assert visited == region_ids, f"transport graph disconnected: {region_ids - visited}"

    relations = integration.get("trade_relations", [])
    relation_keys = {
        (str(item.get("exporter_country_id", "")), str(item.get("importer_country_id", "")))
        for item in relations
    }
    assert len(relations) == 2 and len(relation_keys) == 2
    for exporter, importer in relation_keys:
        assert exporter in country_ids and importer in country_ids and exporter != importer
    for relation in relations:
        assert int(relation.get("tariff_bp", -1)) >= 0
        assert float(relation.get("daily_quota_units", 0)) > 0
        assert isinstance(relation.get("embargo"), bool)

    enterprise_ids = unique(economy.get("enterprises", []), "organization_id", "enterprises")
    site_ids = unique(commodity.get("production_sites", []), "site_id", "production sites")
    assignments = integration.get("enterprise_assignment", {}).get("region_enterprises", {})
    assigned_enterprises: set[str] = set()
    for region_id in region_ids:
        candidates = assignments.get(region_id, [])
        assert candidates, f"no enterprise candidates for {region_id}"
        assert set(candidates) <= enterprise_ids
        assigned_enterprises.update(candidates)
    assert assigned_enterprises
    assert len(site_ids) == 49

    procurement = integration.get("government_procurement", [])
    assert procurement
    commodity_ids = unique(commodity.get("commodities", []), "commodity_id", "commodities")
    for rule in procurement:
        assert str(rule.get("country_id", "")) in country_ids
        assert str(rule.get("commodity_id", "")) in commodity_ids
        assert float(rule.get("target_units", 0)) > 0
        assert float(rule.get("daily_purchase_limit_units", 0)) > 0

    coverage_policy = coverage.get("policy", {})
    assert coverage_policy.get("numeric_defaults_forbidden") is True
    assert coverage_policy.get("unverified_records_must_not_enter_formal_simulation") is True
    statuses = set(coverage_policy.get("allowed_statuses", []))
    dimensions = set(coverage.get("dimensions", []))
    coverage_countries = coverage.get("countries", [])
    coverage_ids = unique(coverage_countries, "entity_id", "historical coverage")
    assert len(coverage_ids) >= 15
    forbidden_numeric_fields = {
        "population",
        "agricultural_output",
        "mineral_output",
        "industrial_capacity",
        "railway_capacity",
        "trade_value",
        "price_index",
        "wage_index",
    }
    for record in coverage_countries:
        assert str(record.get("status", "")) in statuses
        verified = set(record.get("verified_dimensions", []))
        missing = set(record.get("missing_dimensions", []))
        assert verified <= dimensions and missing <= dimensions
        assert verified.isdisjoint(missing)
        assert verified | missing == dimensions
        if str(record.get("status")) != "verified":
            assert forbidden_numeric_fields.isdisjoint(record), (
                record.get("entity_id"), forbidden_numeric_fields & set(record)
            )

    adapter = integration.get("historical_world_adapter", {})
    assert adapter.get("forbid_generated_numeric_defaults") is True
    assert str(adapter.get("coverage_registry_path", "")).endswith(
        "historical_economy_coverage_1900.json"
    )

    print(
        "Unified economy audit passed: "
        f"{len(region_ids)} regions, {len(edge_ids)} sparse routes, "
        f"{len(site_ids)} production sites, {len(commodity_ids)} commodities, "
        f"{len(coverage_ids)} source-gated historical states."
    )


if __name__ == "__main__":
    main()
