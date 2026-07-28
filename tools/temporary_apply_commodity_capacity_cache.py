from pathlib import Path

path = Path("scripts/alpha/alpha_commodity_market_service.gd")
text = path.read_text(encoding="utf-8")
if "func _build_capacity_indexes()" in text:
    raise SystemExit(0)

replacements = [
    (
        "var _region_ids: Array[String] = []\nvar _processed_keys: Dictionary = {}",
        "var _region_ids: Array[String] = []\n"
        "var _production_site_ids: Array[String] = []\n"
        "var _industrial_input_capacity: Dictionary = {}\n"
        "var _output_capacity: Dictionary = {}\n"
        "var _processed_keys: Dictionary = {}",
    ),
    (
        "\t_region_ids.clear()\n\t_processed_keys.clear()",
        "\t_region_ids.clear()\n"
        "\t_production_site_ids.clear()\n"
        "\t_industrial_input_capacity.clear()\n"
        "\t_output_capacity.clear()\n"
        "\t_processed_keys.clear()",
    ),
    (
        "\t\tproduction_sites[site_id] = site\n\t_initialize_international_market(document)",
        "\t\tproduction_sites[site_id] = site\n"
        "\t\t_production_site_ids.append(site_id)\n"
        "\t_production_site_ids.sort()\n"
        "\t_build_capacity_indexes()\n"
        "\t_initialize_international_market(document)",
    ),
    (
        "func _run_production(total_hour: int) -> void:\n"
        "\tvar site_ids: Array[String] = []\n"
        "\tfor raw_id: Variant in production_sites:\n"
        "\t\tsite_ids.append(str(raw_id))\n"
        "\tsite_ids.sort()\n"
        "\tfor site_id: String in site_ids:",
        "func _run_production(total_hour: int) -> void:\n"
        "\tfor site_id: String in _production_site_ids:",
    ),
]
for before, after in replacements:
    if before not in text:
        raise SystemExit(f"required optimization anchor missing: {before[:48]!r}")
    text = text.replace(before, after, 1)

old_scan = '''func _daily_industrial_input_need(region_id: String, commodity_id: String) -> float:
\tvar total: float = 0.0
\tfor raw_site: Variant in production_sites.values():
\t\tvar site: Dictionary = raw_site as Dictionary
\t\tif str(site.get("region_id", "")) != region_id:
\t\t\tcontinue
\t\tvar recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
\t\tfor raw_input: Variant in recipe.get("inputs", []) as Array:
\t\t\tvar input: Dictionary = raw_input as Dictionary
\t\t\tif str(input.get("commodity_id", "")) == commodity_id:
\t\t\t\ttotal += float(input.get("units", 0.0)) * float(site.get("capacity_batches_per_day", 0.0))
\treturn total


func _daily_output_capacity(region_id: String, commodity_id: String) -> float:
\tvar total: float = 0.0
\tfor raw_site: Variant in production_sites.values():
\t\tvar site: Dictionary = raw_site as Dictionary
\t\tif str(site.get("region_id", "")) != region_id:
\t\t\tcontinue
\t\tvar recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
\t\tfor raw_output: Variant in recipe.get("outputs", []) as Array:
\t\t\tvar output: Dictionary = raw_output as Dictionary
\t\t\tif str(output.get("commodity_id", "")) == commodity_id:
\t\t\t\ttotal += float(output.get("units", 0.0)) * float(site.get("capacity_batches_per_day", 0.0))
\treturn total
'''
new_index = '''func _build_capacity_indexes() -> void:
\tfor region_id: String in _region_ids:
\t\t_industrial_input_capacity[region_id] = {}
\t\t_output_capacity[region_id] = {}
\tfor site_id: String in _production_site_ids:
\t\tvar site: Dictionary = production_sites[site_id] as Dictionary
\t\tvar region_id: String = str(site.get("region_id", ""))
\t\tvar recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
\t\tvar capacity: float = float(site.get("capacity_batches_per_day", 0.0))
\t\tvar inputs: Dictionary = _industrial_input_capacity.get(region_id, {}) as Dictionary
\t\tfor raw_input: Variant in recipe.get("inputs", []) as Array:
\t\t\tvar input: Dictionary = raw_input as Dictionary
\t\t\tvar commodity_id: String = str(input.get("commodity_id", ""))
\t\t\tinputs[commodity_id] = float(inputs.get(commodity_id, 0.0)) + float(input.get("units", 0.0)) * capacity
\t\t_industrial_input_capacity[region_id] = inputs
\t\tvar outputs: Dictionary = _output_capacity.get(region_id, {}) as Dictionary
\t\tfor raw_output: Variant in recipe.get("outputs", []) as Array:
\t\t\tvar output: Dictionary = raw_output as Dictionary
\t\t\tvar commodity_id: String = str(output.get("commodity_id", ""))
\t\t\toutputs[commodity_id] = float(outputs.get(commodity_id, 0.0)) + float(output.get("units", 0.0)) * capacity
\t\t_output_capacity[region_id] = outputs


func _daily_industrial_input_need(region_id: String, commodity_id: String) -> float:
\treturn float(
\t\t(_industrial_input_capacity.get(region_id, {}) as Dictionary).get(
\t\t\tcommodity_id, 0.0
\t\t)
\t)


func _daily_output_capacity(region_id: String, commodity_id: String) -> float:
\treturn float(
\t\t(_output_capacity.get(region_id, {}) as Dictionary).get(commodity_id, 0.0)
\t)
'''
if old_scan not in text:
    raise SystemExit("production capacity scan block missing")
text = text.replace(old_scan, new_index, 1)
path.write_text(text, encoding="utf-8")
