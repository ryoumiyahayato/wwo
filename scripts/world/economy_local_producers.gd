class_name EconomyLocalProducers
extends RefCounted
## A bounded household recipe over the original actor, labor pool and StockLots.
## Rules/queries only: no wallets, inventory, orders, transport or saved counters.
const BASIS: String = "EXPLICIT_DEVELOPMENT_FINITE_HOUSEHOLD_PROCESSING"
const SOURCE_BASIS: String = "ACTUAL_HOUSEHOLD_INPUTS_AND_LOCAL_LABOR"
const PREFIX: String = "local_production:"
const DAILY_PERSON_HOURS: int = 8 # Explicit development workday, not a historical estimate.
var _ref: WeakRef
var error: String = ""

func bind(e: RefCounted) -> void:
	_ref = weakref(e)

func economy() -> RefCounted:
	return _ref.get_ref()

static func valid(settings: Dictionary, spec: Dictionary) -> bool:
	var rows: Variant = settings.get("local_producers", [])
	if not rows is Array or rows.size() > 8: return false
	var seen: Dictionary = {}
	for row: Variant in rows:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["actor", "input_good", "input_per_batch", "output_good", "output_per_batch", "hours_per_batch", "max_batches_per_day", "lifetime_batch_limit", "price", "basis"]): return false
		if not row["actor"] is String or seen.has(row["actor"]) or not spec.get("actors", {}).has(row["actor"]): return false
		var actor: Dictionary = spec["actors"][row["actor"]]
		if actor.get("kind") != "cohort" or actor.get("control") != "automatic" or row["basis"] != BASIS or row["input_good"] != "grain" or row["output_good"] != "flour": return false
		if "grain" not in spec.get("good_ids", []) or "flour" not in spec.get("good_ids", []): return false
		for key: String in ["input_per_batch", "output_per_batch", "hours_per_batch", "max_batches_per_day", "lifetime_batch_limit", "price"]:
			if not FormalLedgerState.valid_amount(row[key]) or int(row[key]) < 1 or int(row[key]) > 1000000: return false
		# Only this declared small hand-milling recipe, not a general factory API.
		if row["input_per_batch"] != 3 or row["output_per_batch"] != 2 or row["hours_per_batch"] != 2 or int(row["max_batches_per_day"]) > 8: return false
		if int(row["lifetime_batch_limit"]) > int(actor.get("stock", {}).get("grain", 0)) / 3 or EconomyCohortRules.labor_members(actor) < 1: return false
		seen[row["actor"]] = true
	return true

static func sale_valid(settings: Dictionary, seller: String, good: String, stock_point: String) -> bool:
	if stock_point != seller or seller.is_empty() or good != "flour": return false
	var rows: Variant = settings.get("local_producers", [])
	if not rows is Array: return false
	for row: Variant in rows:
		if not row is Dictionary: return false
		if row.get("actor") == seller and row.get("output_good") == good and row.get("basis") == BASIS: return true
	return false

func rule(actor: String) -> Dictionary:
	for row: Dictionary in economy().config.get("local_producers", []):
		if row["actor"] == actor: return row
	return {}

func has_actor(actor: String) -> bool:
	return not rule(actor).is_empty()

func sells(seller: String, good: String, stock_point: String) -> bool:
	return sale_valid(economy().config, seller, good, stock_point)

func location(subject: String) -> String:
	return "ACTOR|" + subject if has_actor(subject) else "SITE|" + subject

func _source_id(actor: String, date: int) -> String:
	return PREFIX + str(date) + ":" + actor + ":flour"

func flow_totals(actor: String, raw_lots: Dictionary) -> Dictionary:
	var result: Dictionary = {"produced": economy()._zero_goods(), "used": economy()._zero_goods(), "hours": 0, "batches": 0}
	var r: Dictionary = rule(actor)
	if r.is_empty(): return result
	if not raw_lots.get("sources", {}) is Dictionary: return {}
	for source: Variant in raw_lots.get("sources", {}).values():
		if not source is Dictionary or not source.get("id") is String: return {}
		var id: String = source["id"]
		if not id.begins_with(PREFIX) or not id.ends_with(":" + actor + ":flour"): continue
		if not FormalLedgerState.valid_amount(source.get("quantity")) or int(source["quantity"]) < 1 or int(source["quantity"]) % int(r["output_per_batch"]) != 0: return {}
		var batches: int = int(source["quantity"]) / int(r["output_per_batch"])
		result["produced"][r["output_good"]] += batches * int(r["output_per_batch"])
		result["used"][r["input_good"]] += batches * int(r["input_per_batch"])
		result["hours"] += batches * int(r["hours_per_batch"])
		result["batches"] += batches
	return result

func _paid_hours(actor: String, date: int, records: Dictionary) -> int:
	var hours: int = 0
	for work: Dictionary in records.values():
		if work["actor"] == actor and int(work["day"]) == date: hours += int(work["hours"])
	return hours

func _resident_members(actor: String, date: int, services: Dictionary) -> int:
	# Existing resident-service bookings occupy the same people, conservatively
	# for that workday. Do not turn a fulfilled service into free production time.
	var spans: Array[Vector2i] = []
	for contract: Dictionary in services.values():
		if contract.get("client") != actor or not contract.has("resident"): continue
		for booking: Dictionary in contract["resident"]["bookings"]:
			if int(booking["scheduled_minute"]) == date * 1440:
				spans.append(Vector2i(int(booking["member_start"]), int(booking["member_start"]) + int(booking["quantity"])))
	spans.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var end: int = 0
	var count: int = 0
	for span: Vector2i in spans:
		count += maxi(0, span.y - maxi(end, span.x))
		end = maxi(end, span.y)
	return count

func labor_budget(actor: String, date: int, records: Dictionary, services: Dictionary) -> int:
	var e: RefCounted = economy()
	var members: int = EconomyCohortRules.labor_members(e._spec["actors"][actor])
	var since: int = maxi((date - 1) * 1440, int(e._subject_activation.get(actor, 0)))
	var elapsed_hours: int = mini(DAILY_PERSON_HOURS, maxi(0, date * 1440 - since) / 60)
	return maxi(0, maxi(0, members - _resident_members(actor, date, services)) * elapsed_hours - _paid_hours(actor, date, records))

func produce() -> void:
	var e: RefCounted = economy()
	if not e.config["production_enabled"] or e.day < 1: return
	for r: Dictionary in e.config.get("local_producers", []):
		var actor: String = r["actor"]
		if not e.subject_active_at(actor, e._production_minute()) or not e._actors.has(actor): continue
		# This original cumulative receipt total is strictly checked on restore.
		# An exhausted finite recipe need not rescan world work/source history.
		if int(e._physical_totals[actor]["produced"][r["output_good"]]) >= int(r["lifetime_batch_limit"]) * int(r["output_per_batch"]): continue
		var source_id: String = _source_id(actor, e.day)
		if e._lots.sources.has(source_id): continue
		var history: Dictionary = flow_totals(actor, {"sources": e._lots.sources})
		assert(not history.is_empty())
		e._labor[actor] = labor_budget(actor, e.day, e._work_records, e._service_market.contracts)
		var batches: int = mini(int(r["max_batches_per_day"]), int(r["lifetime_batch_limit"]) - int(history["batches"]))
		batches = mini(batches, int(e._labor[actor]) / int(r["hours_per_batch"]))
		batches = mini(batches, maxi(0, int(e._stocks[actor][r["input_good"]]) - e._committed(actor, r["input_good"])) / int(r["input_per_batch"]))
		batches = mini(batches, (FormalLedgerState.MAX_AMOUNT - int(e._physical_totals[actor]["used"][r["input_good"]])) / int(r["input_per_batch"]))
		batches = mini(batches, (FormalLedgerState.MAX_AMOUNT - int(e._physical_totals[actor]["produced"][r["output_good"]])) / int(r["output_per_batch"]))
		batches = mini(batches, (FormalLedgerState.MAX_AMOUNT - e._exposure(actor, r["output_good"])) / int(r["output_per_batch"]))
		if batches < 1: continue
		var inputs: Array[Dictionary] = e._lots.selection("ACTOR|" + actor, r["input_good"], batches * int(r["input_per_batch"]))
		if inputs.is_empty(): continue
		var consumed: bool = e._lots.consume(inputs, e._world.game_clock.total_minutes())
		assert(consumed)
		var created: bool = e._lots.create(source_id, r["output_good"], e._good_units()[r["output_good"]], batches * int(r["output_per_batch"]), actor, "ACTOR|" + actor, e._place(actor), e._world.game_clock.total_minutes(), SOURCE_BASIS, inputs)
		assert(created)
		e._labor[actor] -= batches * int(r["hours_per_batch"])
		e._physical_totals[actor]["used"][r["input_good"]] += batches * int(r["input_per_batch"])
		e._physical_totals[actor]["produced"][r["output_good"]] += batches * int(r["output_per_batch"])

func history_valid() -> bool:
	var e: RefCounted = economy()
	var consumed_inputs: Dictionary = {}
	for source: Dictionary in e._lots.sources.values():
		if not str(source["id"]).begins_with(PREFIX): continue
		var actor: String = ""
		for row: Dictionary in e.config.get("local_producers", []):
			if str(source["id"]).ends_with(":" + str(row["actor"]) + ":flour"): actor = row["actor"]
		var r: Dictionary = rule(actor)
		if r.is_empty() or not e.config["production_enabled"]: return false
		var minute: int = int(source["formed_minute"])
		var date: int = minute / 1440
		var batches: int = int(source["quantity"]) / int(r["output_per_batch"])
		if date < 1 or minute % 1440 != 0 or source["id"] != _source_id(actor, date) or source["basis"] != SOURCE_BASIS or source["good"] != r["output_good"] or source["unit"] != e._good_units()[r["output_good"]] or batches < 1 or batches > int(r["max_batches_per_day"]) or int(source["quantity"]) != batches * int(r["output_per_batch"]) or not e.subject_active_at(actor, maxi(0, minute - 1)): return false
		if batches * int(r["hours_per_batch"]) > labor_budget(actor, date, e._work_records, e._service_market.contracts): return false
		var inputs: int = 0
		for ref: Dictionary in source["inputs"]:
			var p: Dictionary = e._lots.portions.get(ref.get("portion_id"), {})
			if p.is_empty() or p["owner"] != actor or p["good"] != r["input_good"] or p["source_id"] != ref["source_id"] or p["location"] != "ACTOR|" + actor or p["place_id"] != e._place(actor) or int(p["opened_minute"]) > minute or int(ref["quantity"]) < 1: return false
			inputs += int(ref["quantity"])
			consumed_inputs[p["id"]] = int(consumed_inputs.get(p["id"], 0)) + int(ref["quantity"])
		if inputs != batches * int(r["input_per_batch"]): return false
		var roots: int = 0
		for p: Dictionary in e._lots.portions.values():
			if p["source_id"] != source["id"] or not str(p["parent_portion_id"]).is_empty(): continue
			if p["owner"] != actor or p["location"] != "ACTOR|" + actor or p["place_id"] != e._place(actor) or p["opened_minute"] != minute: return false
			roots += int(p["quantity"])
		if roots != int(source["quantity"]): return false
	for id: String in consumed_inputs:
		if consumed_inputs[id] > int(e._lots.portions[id]["consumed"]): return false
	for row: Dictionary in e.config.get("local_producers", []):
		var actor: String = row["actor"]
		var flows: Dictionary = flow_totals(actor, {"sources": e._lots.sources})
		if flows.is_empty() or int(flows["batches"]) > int(row["lifetime_batch_limit"]): return false
		for good: String in e._goods:
			var consumed: int = 0
			for p: Dictionary in e._lots.portions.values():
				if p["owner"] == actor and p["good"] == good: consumed += int(p["consumed"])
			if consumed != int(e._physical_totals[actor]["used"][good]): return false
	return true

func view(actor: String) -> Dictionary:
	var r: Dictionary = rule(actor)
	if r.is_empty(): return {}
	var e: RefCounted = economy()
	var flows: Dictionary = flow_totals(actor, {"sources": e._lots.sources})
	var revenues: Dictionary = {}
	for receipt: Dictionary in e._delivery_receipts.values():
		var order: Dictionary = e._orders[receipt["order_id"]]
		if order["kind"] != "SALE" or order["seller"] != actor: continue
		var currency: String = order["denomination"]
		revenues[currency] = int(revenues.get(currency, 0)) + int(receipt["quantity"]) * int(order["price"])
	var result: Dictionary = r.duplicate(true)
	result.merge({"batches": flows["batches"], "self_work_hours": flows["hours"], "remaining_batches": maxi(0, int(r["lifetime_batch_limit"]) - int(flows["batches"])), "input_on_hand": e._lots.quantity_at("ACTOR|" + actor, r["input_good"]), "output_on_hand": e._lots.quantity_at("ACTOR|" + actor, r["output_good"]), "output_owned_including_cargo": e._stocks[actor][r["output_good"]], "sales_revenue_by_currency": revenues, "labor_basis": "DECLARED_COHORT_8H_WORKDAY_LESS_ACTUAL_WAGE_WORK_AND_RESIDENT_BOOKINGS", "income_basis": "ORIGINAL_DELIVERED_SALE_LEDGER_RECEIPTS_NOT_PROFIT", "regeneration": "NONE_FINITE_OPENING_GRAIN_PROCESSING_ONLY"})
	return result
