#!/usr/bin/env python3
"""Static audit for the population-linked 1900 commodity market configuration."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "data/alpha/commodity_market_1900.json"
REQUIRED_TRADE_CLASSES = {
    "global_bulk", "international_specialty", "regional_mass",
    "local_perishable", "local_service", "luxury",
}
REQUIRED_COMMODITIES = {
    "wheat", "rice", "bread", "meat", "milk", "sugar", "tea", "coffee",
    "coal", "coke", "iron_ore", "steel", "copper", "crude_petroleum",
    "kerosene", "timber", "raw_cotton", "wool", "natural_rubber",
    "industrial_chemicals", "cotton_cloth", "clothing", "soap", "paper",
    "cement", "machinery", "railway_equipment", "small_arms", "ammunition",
    "fine_clothing", "perfume_cosmetics", "jewelry_watches",
}
REQUIRED_RECIPE_OUTPUTS = {
    "bread", "steel", "machinery", "small_arms", "ammunition",
    "clothing", "soap", "paper", "cement", "electricity_service",
}


def fail(message: str) -> None:
    raise SystemExit(f"1900 commodity audit failed: {message}")


def main() -> None:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    if data.get("schema_id") != "alpha_commodity_market_1900_v1":
        fail("schema_id")
    commodities = data.get("commodities", [])
    recipes = data.get("recipes", [])
    sites = data.get("production_sites", [])
    regions = data.get("region_overrides", {})
    if not 60 <= len(commodities) <= 120:
        fail(f"commodity count {len(commodities)}")
    if len(recipes) < 30 or len(sites) < 40 or len(regions) != 8:
        fail("recipe, site or region coverage")
    ids: set[str] = set()
    trade_classes: set[str] = set()
    luxury = 0
    household = 0
    for item in commodities:
        cid = item.get("commodity_id", "")
        if not cid or cid in ids:
            fail(f"duplicate commodity {cid}")
        ids.add(cid)
        trade_class = item.get("trade_class", "")
        trade_classes.add(trade_class)
        if int(item.get("base_price_centimes", 0)) <= 0:
            fail(f"invalid price {cid}")
        if float(item.get("unit_mass_kg", -1)) < 0:
            fail(f"invalid mass {cid}")
        if not item.get("historical_note"):
            fail(f"missing historical note {cid}")
        if item.get("category") == "luxury":
            luxury += 1
        if float(item.get("base_daily_units_per_million", 0)) > 0:
            household += 1
    missing = REQUIRED_COMMODITIES - ids
    if missing:
        fail(f"missing required commodities {sorted(missing)}")
    if not REQUIRED_TRADE_CLASSES <= trade_classes:
        fail(f"missing trade classes {sorted(REQUIRED_TRADE_CLASSES - trade_classes)}")
    if luxury < 6 or household < 20:
        fail("luxury or population-consumption coverage")
    recipe_ids: set[str] = set()
    outputs: set[str] = set()
    for recipe in recipes:
        rid = recipe.get("recipe_id", "")
        if not rid or rid in recipe_ids:
            fail(f"duplicate recipe {rid}")
        recipe_ids.add(rid)
        for field in ("inputs", "outputs"):
            for flow in recipe.get(field, []):
                cid = flow.get("commodity_id", "")
                if cid not in ids or float(flow.get("units", 0)) <= 0:
                    fail(f"invalid recipe flow {rid}/{field}/{cid}")
                if field == "outputs":
                    outputs.add(cid)
    if not REQUIRED_RECIPE_OUTPUTS <= outputs:
        fail(f"missing recipe outputs {sorted(REQUIRED_RECIPE_OUTPUTS - outputs)}")
    site_ids: set[str] = set()
    for site in sites:
        sid = site.get("site_id", "")
        if not sid or sid in site_ids:
            fail(f"duplicate site {sid}")
        site_ids.add(sid)
        if site.get("recipe_id") not in recipe_ids or site.get("region_id") not in regions:
            fail(f"invalid site reference {sid}")
        if float(site.get("capacity_batches_per_day", 0)) <= 0 or int(site.get("workers_capacity", 0)) <= 0:
            fail(f"invalid site capacity {sid}")
    policies = data.get("policies", {})
    for flag in (
        "regional_balance_before_international", "negative_inventory_forbidden",
        "modern_brand_skus_collapsed", "local_perishables_not_internationally_cleared",
    ):
        if policies.get(flag) is not True:
            fail(f"policy {flag}")
    if len(data.get("source_groups", [])) < 4:
        fail("source groups")
    print(json.dumps({
        "success": True,
        "commodity_count": len(commodities),
        "household_consumables": household,
        "luxury_count": luxury,
        "recipe_count": len(recipes),
        "production_site_count": len(sites),
        "region_count": len(regions),
        "trade_classes": sorted(trade_classes),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
