#!/usr/bin/env python3
"""Convert the reproducible verbose 1900 estimates into runtime compact tables."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALPHA = ROOT / "data" / "alpha"

COUNTRY_FIELDS = [
    "rank", "entity_id", "primary_iso3",
    "population_value", "population_lower", "population_upper", "population_confidence_bp",
    "gdp_pc_value", "gdp_pc_lower", "gdp_pc_upper", "gdp_confidence_bp",
    "urban_value_bp", "urban_lower_bp", "urban_upper_bp", "urban_confidence_bp",
    "agriculture_capacity_index", "industrial_capacity_index", "steel_output_tonnes", "energy_coal_equivalent_tonnes",
    "coal_index", "iron_ore_index", "copper_index", "petroleum_index", "timber_index", "production_confidence_bp",
    "rail_route_km", "rail_lower_km", "rail_upper_km", "waterway_km", "port_capacity_index", "merchant_shipping_index", "infrastructure_confidence_bp",
    "household_budget_template_id", "overall_confidence_bp", "formal_simulation_allowed", "major_ports",
]


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value: dict, compact: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    kwargs = {"ensure_ascii": False}
    if compact:
        kwargs["separators"] = (",", ":")
    else:
        kwargs["indent"] = 2
    path.write_text(json.dumps(value, **kwargs) + "\n", encoding="utf-8")


def compact_country(country: dict) -> list:
    p = country["population"]
    g = country["gdp_per_capita_2011_intl_dollars"]
    u = country["urban_population_share_bp"]
    production = country["production"]
    minerals = production["mineral_capacity_index"]
    infra = country["infrastructure"]
    return [
        country["rank"], country["entity_id"], country["primary_iso3"],
        p["value"], p["lower"], p["upper"], p["confidence_bp"],
        g["value"], g["lower"], g["upper"], g["confidence_bp"],
        u["value"], u["lower"], u["upper"], u["confidence_bp"],
        production["agriculture_capacity_index"], production["industrial_capacity_index"], production["steel_output_tonnes"], production["primary_energy_coal_equivalent_tonnes"],
        minerals["coal"], minerals["iron_ore"], minerals["copper"], minerals["petroleum"], minerals["timber"], production["confidence_bp"],
        infra["rail_route_km"], infra["rail_route_km_lower"], infra["rail_route_km_upper"], infra["navigable_waterway_km"], infra["port_capacity_index"], infra["merchant_shipping_index"], infra["confidence_bp"],
        country["household_budget_template_id"], country["overall_confidence_bp"], country["formal_simulation_allowed"], infra["major_ports"],
    ]


def main() -> None:
    world_path = ALPHA / "historical_world_economy_1900.json"
    transport_path = ALPHA / "historical_transport_network_1900.json"
    world = load(world_path)
    transport = load(transport_path)
    if "countries" not in world or "domestic_networks" not in transport:
        raise SystemExit("Run tools/build_1900_world_economy_estimates.py before compacting")

    country_table = {
        "schema_id": "historical_world_economy_1900_compact_country_table_v1",
        "field_order": COUNTRY_FIELDS,
        "common_methods": {
            "population": "historical_series_or_census_anchor_with_border_crosswalk",
            "gdp": "maddison_anchor_or_regional_analogue",
            "production": "cow_nmc_where_available_else_scale_model_with_resource_overrides",
            "infrastructure": "historical_total_anchor_or_density_model; curated circa-1900 gateways",
        },
        "rows": [compact_country(country) for country in world.pop("countries")],
    }
    world["compact_country_table_path"] = "res://data/alpha/historical_world_economy_1900/countries_compact.json"
    write(ALPHA / "historical_world_economy_1900" / "countries_compact.json", country_table, compact=True)
    write(world_path, world)

    domestic_fields = ["entity_id", "rail_route_km", "rail_lower_km", "rail_upper_km", "waterway_km", "port_capacity_index", "merchant_shipping_index", "network_class", "confidence_bp", "gateway_ports"]
    maritime_fields = ["corridor_id", "origin_port", "destination_port", "origin_entity_id", "destination_entity_id", "duration_days", "capacity_index", "mode", "confidence_bp"]
    river_fields = ["corridor_id", "entity_ids", "hubs", "capacity_index", "seasonality_bp"]
    compact_transport = {
        "schema_id": "historical_transport_network_1900_compact_tables_v1",
        "domestic_field_order": domestic_fields,
        "domestic_rows": [[x["entity_id"], x["rail_route_km"], x["rail_route_km_lower"], x["rail_route_km_upper"], x["navigable_waterway_km"], x["port_capacity_index"], x["merchant_shipping_index"], x["network_class"], x["confidence_bp"], x["gateway_ports"]] for x in transport.pop("domestic_networks")],
        "maritime_field_order": maritime_fields,
        "maritime_rows": [[x["corridor_id"], x["origin_port"], x["destination_port"], x["origin_entity_id"], x["destination_entity_id"], x["typical_duration_days"], x["capacity_index"], x["mode"], x["confidence_bp"]] for x in transport.pop("international_maritime_corridors")],
        "river_field_order": river_fields,
        "river_rows": [[x["corridor_id"], x["entity_ids"], x["hubs"], x["capacity_index"], x["seasonality_bp"]] for x in transport.pop("major_river_corridors")],
    }
    transport["compact_table_path"] = "res://data/alpha/historical_transport_network_1900/transport_compact.json"
    write(ALPHA / "historical_transport_network_1900" / "transport_compact.json", compact_transport, compact=True)
    write(transport_path, transport)


if __name__ == "__main__":
    main()
