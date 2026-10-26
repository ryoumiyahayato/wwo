extends RefCounted
## Optional contract on existing activities. No stock, money, clock or executor.
## Cycle means an eligible daily batch boundary; there is no hidden WIP storage.
const FORMAT: String = "production_process_v1"

static func valid(activity: Dictionary) -> bool:
	if not activity.has("process"): return true
	var p: Variant = activity["process"]
	if not p is Dictionary or not FormalLedgerState.exact_fields(p, ["format", "technology_id", "batch_unit", "source", "gross_outputs", "rejects", "first_day", "cycle_days", "max_batches_per_cycle", "lifetime_batch_limit", "constraints"]): return false
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
	return true

static func reason(activity: Dictionary, day: int, completed: int) -> String:
	if not activity.has("process"): return "LEGACY_UNSPECIFIED"
	var process: Dictionary = activity["process"]
	if not process["constraints"].is_empty(): return "UNAVAILABLE_" + str(process["constraints"][0]["kind"])
	if completed >= int(process["lifetime_batch_limit"]): return "BATCH_QUOTA_EXHAUSTED"
	if day < int(process["first_day"]) or (day - int(process["first_day"])) % int(process["cycle_days"]) != 0: return "OUTSIDE_PROCESS_CYCLE"
	return "ELIGIBLE"

static func limit(activity: Dictionary, day: int, completed: int) -> int:
	if not activity.has("process"): return FormalLedgerState.MAX_AMOUNT
	if reason(activity, day, completed) != "ELIGIBLE": return 0
	return mini(int(activity["process"]["max_batches_per_cycle"]), int(activity["process"]["lifetime_batch_limit"]) - completed)

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
				for good: String in goods:
					var id: String = "production:" + str(date) + ":" + site + ":" + str(activity["id"]) + ":" + good
					var original: Dictionary = e._lots.sources.get(id, {})
					if original.is_empty() or original["formed_minute"] != source["formed_minute"] or original["quantity"] != batches * int(activity["outputs"][good]): return false
				completed += batches
			if completed != int(e._site_state[site]["activities"][activity["id"]]["batches"]): return false
	return true
