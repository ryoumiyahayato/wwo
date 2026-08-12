#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

PATH = Path("scripts/vnext/economy/market_economy.gd")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    text = PATH.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "var _trade_quota_remaining: Dictionary = {}\nvar _last_day_index: int = -1",
        "var _trade_quota_remaining: Dictionary = {}\nvar _in_transit_units_by_destination: Dictionary = {}\nvar _last_day_index: int = -1",
        "derived in-transit index member",
    )

    text = replace_once(
        text,
        "\tshipments = candidate_shipments\n\thistory = candidate_history",
        "\tshipments = candidate_shipments\n\t_rebuild_in_transit_units_index()\n\thistory = candidate_history",
        "restore candidate cache rebuild",
    )

    text = replace_once(
        text,
        "\t\tshipments = original_shipments\n\t\thistory = original_history",
        "\t\tshipments = original_shipments\n\t\t_rebuild_in_transit_units_index()\n\t\thistory = original_history",
        "restore rollback cache rebuild",
    )

    text = replace_once(
        text,
        "\t_trade_quota_remaining.clear()\n\t_last_day_index = -1",
        "\t_trade_quota_remaining.clear()\n\t_in_transit_units_by_destination.clear()\n\t_last_day_index = -1",
        "clear derived cache",
    )

    text = replace_once(
        text,
        "\t_deliver_shipments(day_index)\n\t_apply_spoilage()",
        "\t_deliver_shipments(day_index)\n\t_rebuild_in_transit_units_index()\n\t_apply_spoilage()",
        "post-delivery cache rebuild",
    )

    text = replace_once(
        text,
        "\t_schedule_shipments(day_index)\n\t_update_prices()",
        "\t_schedule_shipments(day_index)\n\t_rebuild_in_transit_units_index()\n\t_update_prices()",
        "post-dispatch cache rebuild",
    )

    text = replace_once(
        text,
        '''func _in_transit_units_for(destination_id: String, commodity_id: String) -> float:\n\tvar total: float = 0.0\n\tfor shipment: Dictionary in shipments:\n\t\tif (\n\t\t\tstr(shipment.get("destination_market_id", "")) == destination_id\n\t\t\tand str(shipment.get("commodity_id", "")) == commodity_id\n\t\t\tand str(shipment.get("status", "")) == "in_transit"\n\t\t):\n\t\t\ttotal += maxf(0.0, float(shipment.get("units", 0.0)))\n\treturn total\n''',
        '''func _rebuild_in_transit_units_index() -> void:\n\t_in_transit_units_by_destination.clear()\n\tfor shipment: Dictionary in shipments:\n\t\tif str(shipment.get("status", "")) != "in_transit":\n\t\t\tcontinue\n\t\tvar destination_id: String = str(shipment.get("destination_market_id", ""))\n\t\tvar commodity_id: String = str(shipment.get("commodity_id", ""))\n\t\tvar units: float = maxf(0.0, float(shipment.get("units", 0.0)))\n\t\tif destination_id.is_empty() or commodity_id.is_empty() or units <= 0.000001:\n\t\t\tcontinue\n\t\tvar commodity_totals: Dictionary = (\n\t\t\t_in_transit_units_by_destination.get(destination_id, {}) as Dictionary\n\t\t)\n\t\tcommodity_totals[commodity_id] = (\n\t\t\tfloat(commodity_totals.get(commodity_id, 0.0)) + units\n\t\t)\n\t\t_in_transit_units_by_destination[destination_id] = commodity_totals\n\n\nfunc _in_transit_units_for(destination_id: String, commodity_id: String) -> float:\n\tvar commodity_totals: Dictionary = (\n\t\t_in_transit_units_by_destination.get(destination_id, {}) as Dictionary\n\t)\n\treturn maxf(0.0, float(commodity_totals.get(commodity_id, 0.0)))\n''',
        "replace repeated shipment scan with derived index",
    )

    text = replace_once(
        text,
        '''\t\t\tvar demand: float = maxf(0.001, float(commodity_state.get("demand_units", 0.0)))\n\t\t\tvar target_days: float = float(commodity.get("target_stock_days", 10)) * float(''',
        '''\t\t\tvar demand_units: float = maxf(0.0, float(commodity_state.get("demand_units", 0.0)))\n\t\t\tvar demand: float = maxf(0.001, demand_units)\n\t\t\tvar same_day_supply: float = maxf(0.0, float(commodity_state.get("supply_units", 0.0)))\n\t\t\tvar same_day_balance_pressure_bp: int = 0\n\t\t\tif demand_units > 0.0001 or same_day_supply > 0.0001:\n\t\t\t\tvar balance_denominator: float = maxf(0.001, demand_units + same_day_supply)\n\t\t\t\tsame_day_balance_pressure_bp = clampi(\n\t\t\t\t\tint(round((demand_units - same_day_supply) / balance_denominator * 8000.0)),\n\t\t\t\t\t-3000,\n\t\t\t\t\t3000\n\t\t\t\t)\n\t\t\tvar target_days: float = float(commodity.get("target_stock_days", 10)) * float(''',
        "same-day balance pressure inputs",
    )

    text = replace_once(
        text,
        '''\t\t\tvar target_multiplier_bp: int = (\n\t\t\t\tBASIS_POINTS + stock_pressure_bp + shortage_pressure_bp + price_shock_bp\n\t\t\t)''',
        '''\t\t\tvar target_multiplier_bp: int = (\n\t\t\t\tBASIS_POINTS\n\t\t\t\t+ stock_pressure_bp\n\t\t\t\t+ shortage_pressure_bp\n\t\t\t\t+ same_day_balance_pressure_bp\n\t\t\t\t+ price_shock_bp\n\t\t\t)''',
        "same-day balance pressure target",
    )

    text = replace_once(
        text,
        '''\t\tvar output_surplus: bool = true\n\t\tfor output: Dictionary in _dictionary_array(recipe.get("outputs", [])):\n\t\t\tvar commodity_id: String = str(output.get("commodity_id", ""))\n\t\t\tvar units: float = float(output.get("units", 0.0))\n\t\t\tvar commodity_state: Dictionary = commodity_snapshot(region_id, commodity_id)''',
        '''\t\tvar output_surplus: bool = true\n\t\tvar region_commodities: Dictionary = (\n\t\t\t(region_states[region_id] as Dictionary).get("commodities", {}) as Dictionary\n\t\t)\n\t\tfor output: Dictionary in _dictionary_array(recipe.get("outputs", [])):\n\t\t\tvar commodity_id: String = str(output.get("commodity_id", ""))\n\t\t\tvar units: float = float(output.get("units", 0.0))\n\t\t\tvar commodity_state: Dictionary = region_commodities.get(commodity_id, {}) as Dictionary''',
        "site target direct output state read",
    )

    text = replace_once(
        text,
        '''\t\tfor input: Dictionary in _dictionary_array(recipe.get("inputs", [])):\n\t\t\tvar commodity_id: String = str(input.get("commodity_id", ""))\n\t\t\tinput_cost_per_batch += float(input.get("units", 0.0)) * float(\n\t\t\t\tcommodity_snapshot(region_id, commodity_id).get("price_centimes", 0)\n\t\t\t)''',
        '''\t\tfor input: Dictionary in _dictionary_array(recipe.get("inputs", [])):\n\t\t\tvar commodity_id: String = str(input.get("commodity_id", ""))\n\t\t\tvar commodity_state: Dictionary = region_commodities.get(commodity_id, {}) as Dictionary\n\t\t\tinput_cost_per_batch += float(input.get("units", 0.0)) * float(\n\t\t\t\tcommodity_state.get("price_centimes", 0)\n\t\t\t)''',
        "site target direct input state read",
    )

    required = [
        "var _in_transit_units_by_destination: Dictionary = {}",
        "func _rebuild_in_transit_units_index() -> void:",
        "+ same_day_balance_pressure_bp",
        "var region_commodities: Dictionary = (",
    ]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"missing postcondition: {needle}")

    PATH.write_text(text, encoding="utf-8")
    print("PR59 market fix applied successfully")


if __name__ == "__main__":
    main()
