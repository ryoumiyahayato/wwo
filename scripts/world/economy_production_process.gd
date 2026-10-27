extends RefCounted
## Optional contract on existing activities. No stock, money, clock or executor.
## Cycle means an eligible daily batch boundary; there is no hidden WIP storage.
const FORMAT: String = "production_process_v1"

static func valid(activity: Dictionary) -> bool:
	if not activity.has("process"): return true
	var p: Variant = activity["process"]
	if not p is Dictionary: return false
	var fields: Array[String] = ["format", "technology_id", "batch_unit", "source", "gross_outputs", "rejects", "first_day", "cycle_days", "max_batches_per_cycle", "lifetime_batch_limit", "constraints"]
	if p.has("finite_extraction"): fields.append("finite_extraction")
	if not FormalLedgerState.exact_fields(p, fields): return false
	if p["format"] != FORMAT: return false
	for key: String in ["technology_id", "batch_unit"]:
		if not p[key] is String or p[key].is_empty(): return false
	var source: Variant = p["source"]
	if not source is Dictionary or not FormalLedgerState.exact_fields(source, ["id", "basis", "estimated", "hours_unit", "capacity_unit"]) or not source["estimated"] is bool or source["hours_unit"] != "person_hour" or source["capacity_unit"] != "capacity_unit_per_eligible_day": return false
	for key: String in ["id", "basis"]:
		if not source[key] is String or source[key].is_empty(): return false
	for key: String in ["first_day", "cycle_days", "max_batches_per_cycle", "lifetime_batch_limit"]:
		if not FormalLedgerState.valid_amount(p[key]) or p[key] > 1000000: return false
	if p["first_day"] < 1 or p["cycle_days"] < 1 or p["max_batches_per_cycle"] < 1 or p["lifetime_batch_limit"] < 1: return false
	if not p["gross_outputs"] is Dictionary or not p["rejects"] is Dictionary or p["gross_outputs"].size() != activity["outputs"].size() or p["rejects"].size() != activity["outputs"].size(): return false
	for good: String in activity["outputs"]:
		if not FormalLedgerState.valid_amount(p["gross_outputs"].get(good)) or not FormalLedgerState.valid_amount(p["rejects"].get(good)): return false
		if int(p["gross_outputs"][good]) - int(p["rejects"][good]) != int(activity["outputs"][good]): return false
	if not p["constraints"] is Array or p["constraints"].size() > 16: return false
	for constraint: Variant in p["constraints"]:
		if not constraint is Dictionary or not FormalLedgerState.exact_fields(constraint, ["kind", "availability", "source", "unit"]): return false
		if constraint["kind"] not in ["LAND", "BIOLOGICAL_CYCLE", "MINERAL_DEPOSIT", "ACTIVITY_LABOR_ROLE", "SPECIFIC_EQUIPMENT", "FUEL", "SERVICE_OUTPUT", "MULTIDAY_WIP"] or constraint["availability"] != "UNAVAILABLE": return false
		for key: String in ["source", "unit"]:
			if not constraint[key] is String or constraint[key].is_empty(): return false
	return _finite_extraction_valid(activity)

## This is an explicit finite in-ground development endowment, not saleable
## inventory. Depletion is derived only from original executed batch receipts.
static func _finite_extraction_valid(activity: Dictionary) -> bool:
	var process: Dictionary = activity["process"]
	if not process.has("finite_extraction"): return true
	var resource: Variant = process["finite_extraction"]
	if not resource is Dictionary or not FormalLedgerState.exact_fields(resource, ["format", "id", "good", "place_id", "unit", "reserve_quantity", "quantity_per_batch", "capital_template_id", "basis", "source"]): return false
	if resource["format"] != "finite_mineral_extraction_v1" or resource["basis"] != "EXPLICIT_DEVELOPMENT_FINITE_MINERAL_RESERVE": return false
	for key: String in ["id", "good", "place_id", "unit", "capital_template_id", "source"]:
		if not resource[key] is String or resource[key].is_empty(): return false
	if not str(resource["id"]).begins_with("deposit:") or resource["place_id"] != activity["place_id"] or activity["outputs"].size() != 1 or not activity["outputs"].has(resource["good"]): return false
	for key: String in ["reserve_quantity", "quantity_per_batch"]:
		if not FormalLedgerState.valid_amount(resource[key]) or int(resource[key]) > 1000000: return false
	if int(resource["quantity_per_batch"]) < 1 or resource["quantity_per_batch"] != process["gross_outputs"][resource["good"]]: return false
	for constraint: Dictionary in process["constraints"]:
		if constraint["kind"] == "MINERAL_DEPOSIT": return false
	return true

## No shared reserve is copied into two activity counters. Capital is the existing
## native construction permission, installed with real goods, paid work and time.
static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	var deposits: Dictionary = {}
	var templates: Dictionary = {}
	var investment: Variant = settings.get("capital_investment", {})
	if not investment is Dictionary or not investment.get("templates", []) is Array or not settings.get("goods", []) is Array: return false
	for row: Variant in investment.get("templates", []):
		if not row is Dictionary or not row.get("id") is String: return false
		templates[row["id"]] = row
	var units: Dictionary = {}
	for good: Variant in settings.get("goods", []):
		if not good is Dictionary or not good.get("id") is String: return false
		units[good["id"]] = good.get("unit_id", "")
	for site: Dictionary in spec["sites"].values():
		for activity: Dictionary in site["activities"]:
			var resource: Dictionary = activity.get("process", {}).get("finite_extraction", {})
			if resource.is_empty(): continue
			if deposits.has(resource["id"]) or units.get(resource["good"], "") != resource["unit"] or int(site["capacity"]) != 0: return false
			var capital: Dictionary = templates.get(resource["capital_template_id"], {})
			if capital.is_empty() or capital.get("site_id") != site["id"] or capital.get("firm") != site["firm_id"] or not capital.get("activities") is Array or not capital["activities"].has(activity["id"]) or capital.get("kind") not in ["INSTALL", "NEW_SITE", "EXPAND"]: return false
			deposits[resource["id"]] = true
	return true

static func extraction_view(activity: Dictionary, completed: int) -> Dictionary:
	var resource: Dictionary = activity.get("process", {}).get("finite_extraction", {})
	if resource.is_empty(): return {}
	var extracted: int = completed * int(resource["quantity_per_batch"])
	var result: Dictionary = resource.duplicate(true)
	result["extracted_quantity"] = extracted
	result["remaining_quantity"] = maxi(0, int(resource["reserve_quantity"]) - extracted)
	result["depletion_basis"] = "EXECUTED_BATCHES_VERIFIED_AGAINST_ORIGINAL_PRODUCTION_SOURCES"
	return result

static func reason(activity: Dictionary, day: int, completed: int) -> String:
	if not activity.has("process"): return "LEGACY_UNSPECIFIED"
	var process: Dictionary = activity["process"]
	if not process["constraints"].is_empty(): return "UNAVAILABLE_" + str(process["constraints"][0]["kind"])
	var resource: Dictionary = process.get("finite_extraction", {})
	if not resource.is_empty() and completed >= int(resource["reserve_quantity"]) / int(resource["quantity_per_batch"]): return "MINERAL_RESERVE_EXHAUSTED"
	if completed >= int(process["lifetime_batch_limit"]): return "BATCH_QUOTA_EXHAUSTED"
	if day < int(process["first_day"]) or (day - int(process["first_day"])) % int(process["cycle_days"]) != 0: return "OUTSIDE_PROCESS_CYCLE"
	return "ELIGIBLE"

static func limit(activity: Dictionary, day: int, completed: int) -> int:
	if not activity.has("process"): return FormalLedgerState.MAX_AMOUNT
	if reason(activity, day, completed) != "ELIGIBLE": return 0
	var process: Dictionary = activity["process"]
	var remaining: int = int(process["lifetime_batch_limit"]) - completed
	var resource: Dictionary = process.get("finite_extraction", {})
	if not resource.is_empty(): remaining = mini(remaining, int(resource["reserve_quantity"]) / int(resource["quantity_per_batch"]) - completed)
	return mini(int(process["max_batches_per_cycle"]), remaining)

## Original output source receipts validate history even with monetary cost
## accounting disabled. Never infer historical batches from intentions or plans.
static func history_valid(e: RefCounted) -> bool:
	for site: String in e._site_ids():
		for activity: Dictionary in e._spec["sites"][site]["activities"]:
			if not activity.has("process"): continue
			var goods: Array = activity["outputs"].keys()
			goods.sort()
			var suffix: String = ":" + site + ":" + str(activity["id"]) + ":" + str(goods[0])
			var rows: Array[Dictionary] = []
			for source: Dictionary in e._lots.sources.values():
				if str(source["id"]).begins_with("production:") and str(source["id"]).ends_with(suffix): rows.append(source)
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["formed_minute"]) < int(b["formed_minute"]))
			var completed: int = 0
			for source: Dictionary in rows:
				var date: int = int(source["formed_minute"]) / 1440
				var batches: int = int(source["quantity"]) / int(activity["outputs"][goods[0]])
				if int(source["quantity"]) % int(activity["outputs"][goods[0]]) != 0 or batches < 1 or batches > limit(activity, date, completed): return false
				if activity["process"].has("finite_extraction"):
					var minute: int = maxi(0, date * 1440 - 1)
					if batches * int(activity["capacity_units"]) > e._capital.capacity(site, minute, activity["id"]): return false
				for good: String in goods:
					var id: String = "production:" + str(date) + ":" + site + ":" + str(activity["id"]) + ":" + good
					var original: Dictionary = e._lots.sources.get(id, {})
					if original.is_empty() or original["formed_minute"] != source["formed_minute"] or original["quantity"] != batches * int(activity["outputs"][good]): return false
				completed += batches
			if completed != int(e._site_state[site]["activities"][activity["id"]]["batches"]): return false
	return true
