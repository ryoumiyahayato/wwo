class_name EconomyLocalProducers
extends RefCounted
## Shared household/resource rules over the original actor, labor and StockLots.
## Only land/crop timing and seed references are saved here. No cash or goods copy.
const BASIS: String = "EXPLICIT_DEVELOPMENT_FINITE_HOUSEHOLD_PROCESSING"
const SOURCE_BASIS: String = "ACTUAL_HOUSEHOLD_INPUTS_AND_LOCAL_LABOR"
const PREFIX: String = "local_production:"
const DAILY_PERSON_HOURS: int = 8 # Explicit development workday, not a historical estimate.
var _ref: WeakRef
var error: String = ""
var crop_cycles: Dictionary = {} # Land/time and consumed seed references; never goods or cash.
var _active_crops: Dictionary = {} # Derived actor -> growing year IDs, rebuilt on restore.
var _extracted: Dictionary = {} # Derived by geographic resource ID from original source receipts.

func bind(e: RefCounted) -> void:
	_ref = weakref(e)

func economy() -> RefCounted:
	return _ref.get_ref()

static func valid(settings: Dictionary, spec: Dictionary) -> bool:
	if not _resources_valid(settings, spec): return false
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
	for row: Dictionary in settings.get("resource_producers", []):
		if row["actor"] == seller and row["good"] == good and stock_point == seller: return true
	if stock_point != seller or seller.is_empty() or good != "flour": return false
	var rows: Variant = settings.get("local_producers", [])
	if not rows is Array: return false
	for row: Variant in rows:
		if not row is Dictionary: return false
		if row.get("actor") == seller and row.get("output_good") == good and row.get("basis") == BASIS: return true
	return false

func rule(actor: String) -> Dictionary:
	for row: Dictionary in economy().config.get("resource_producers", []):
		if row["actor"] == actor: return row
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
	if r.has("resource"):
		for source: Dictionary in raw_lots.get("sources", {}).values():
			if _resource_owner(source["id"]) == actor:
				result["produced"][r["good"]] += int(source["quantity"])
		for cycle: Dictionary in crop_cycles.get(actor, {}).values():
			result["used"][r["good"]] += int(cycle["units"]) * int(r["resource"].get("seed_per_unit", 0))
		return result
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

static func _resource_owner(id: String) -> String:
	return id.substr(9, id.rfind(":") - 9) if id.begins_with("resource:") else ""

func _paid_hours(actor: String, date: int, records: Dictionary) -> int:
	var hours: int = 0
	var e: RefCounted = economy()
	if e._cohort_profile(actor).is_empty(): return int(records.get(e._work_id(date, actor, ""), {}).get("hours", 0))
	for job: String in e._spec["jobs"]:
		hours += int(records.get(e._work_id(date, actor, job), {}).get("hours", 0))
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
	_produce_resources()
	for r: Dictionary in e.config.get("local_producers", []):
		var actor: String = r["actor"]
		if not e.subject_active_at(actor, e._production_minute()) or not e._actors.has(actor): continue
		# This original cumulative receipt total is strictly checked on restore.
		# An exhausted finite recipe need not rescan world work/source history.
		if int(e._physical_totals[actor]["produced"][r["output_good"]]) >= int(r["lifetime_batch_limit"]) * int(r["output_per_batch"]): continue
		var source_id: String = _source_id(actor, e.day)
		if e._lots.sources.has(source_id): continue
		var completed: int = int(e._physical_totals[actor]["produced"][r["output_good"]]) / int(r["output_per_batch"])
		e._labor[actor] = labor_budget(actor, e.day, e._work_records, e._service_market.contracts)
		var batches: int = mini(int(r["max_batches_per_day"]), int(r["lifetime_batch_limit"]) - completed)
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
	if not _resource_history_valid(): return false
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
	if r.has("resource"): return resource_view(actor)
	var e: RefCounted = economy()
	var flows: Dictionary = flow_totals(actor, {"sources": e._lots.sources})
	var revenues: Dictionary = {}
	for receipt: Dictionary in e._delivery_receipts.values():
		var order: Dictionary = e._orders[receipt["order_id"]]
		if order["kind"] != "SALE" or order["seller"] != actor: continue
		var currency: String = order["denomination"]
		revenues[currency] = int(revenues.get(currency, 0)) + e._receipt_goods_amount(receipt, order)
	var result: Dictionary = r.duplicate(true)
	result.merge({"batches": flows["batches"], "self_work_hours": flows["hours"], "remaining_batches": maxi(0, int(r["lifetime_batch_limit"]) - int(flows["batches"])), "input_on_hand": e._lots.quantity_at("ACTOR|" + actor, r["input_good"]), "output_on_hand": e._lots.quantity_at("ACTOR|" + actor, r["output_good"]), "output_owned_including_cargo": e._stocks[actor][r["output_good"]], "sales_revenue_by_currency": revenues, "labor_basis": "DECLARED_COHORT_8H_WORKDAY_LESS_ACTUAL_WAGE_WORK_AND_RESIDENT_BOOKINGS", "income_basis": "ORIGINAL_DELIVERED_SALE_LEDGER_RECEIPTS_NOT_PROFIT", "regeneration": "NONE_FINITE_OPENING_GRAIN_PROCESSING_ONLY"})
	return result

static func _resources_valid(settings: Dictionary, spec: Dictionary) -> bool:
	var seen: Dictionary = {}
	var resource_ids: Dictionary = {}
	var resource_goods: Dictionary = {}
	for row: Variant in settings.get("resource_producers", []):
		if not row is Dictionary or not EconomySliceConfig._fields(row, ["actor", "good", "price", "resource"], ["land_use_units", "from_day", "until_day", "stock_cover_days", "seasonal_reserve", "self_use"]): return false
		for flag: String in ["seasonal_reserve", "self_use"]:
			if row.has(flag) and not row[flag] is bool: return false
		if row.has("stock_cover_days") and (not EconomySliceConfig._number(row["stock_cover_days"], 1) or int(row["stock_cover_days"]) > 30): return false
		if seen.has(row["actor"]) or not spec["actors"].has(row["actor"]) or spec["actors"][row["actor"]]["kind"] != "cohort" or row["good"] not in spec["good_ids"] or not row["resource"] is Dictionary: return false
		var r: Dictionary = row["resource"]
		if row.has("seasonal_reserve") and r.get("kind") != "crop": return false
		if row.has("self_use") and r.get("kind") != "mineral": return false
		if not r.get("id") is String: return false
		if resource_ids.has(r["id"]) and resource_ids[r["id"]] != r: return false
		if resource_goods.has(r["id"]) and resource_goods[r["id"]] != row["good"]: return false
		resource_ids[r["id"]] = r
		resource_goods[r["id"]] = row["good"]
		if r.get("kind") not in ["crop", "mineral"] or r.get("place_id") != spec["actors"][row["actor"]].get("place_id") or r.get("quantity_basis") != "EXPLICIT_DEVELOPMENT_ASSUMPTION" or r.get("geographic_unit_id", "").is_empty() or r.get("source_url", "").is_empty(): return false
		for key: String in ["price"]:
			if not FormalLedgerState.valid_amount(row[key]) or int(row[key]) < 1: return false
		var numeric: Array = ["land_units", "seed_per_unit", "yield_per_unit", "sow_hours", "harvest_hours", "grow_days", "suitability_permille", "fertility_permille", "climate_permille", "technology_permille"] if r["kind"] == "crop" else ["geological_quantity", "discovered_quantity", "units_per_day", "hours_per_unit", "equipment_period", "maintenance_hours", "economic_cost"]
		for key: String in numeric:
			if not FormalLedgerState.valid_amount(r.get(key)) or int(r[key]) < 1 or int(r[key]) > 1000000: return false
		if r["kind"] == "mineral" and int(r["discovered_quantity"]) > int(r["geological_quantity"]): return false
		var discovered_total: int = int(r.get("discovered_quantity", 0))
		var discovery_day: int = -1
		for event: Variant in r.get("discovery", []):
			if not event is Dictionary or not FormalLedgerState.exact_fields(event, ["day", "quantity"]) or not FormalLedgerState.valid_amount(event["day"]) or not FormalLedgerState.valid_amount(event["quantity"]) or int(event["day"]) <= discovery_day: return false
			discovered_total += int(event["quantity"])
			discovery_day = int(event["day"])
		if r["kind"] == "mineral" and discovered_total > int(r["geological_quantity"]): return false
		if r["kind"] == "crop" and (int(r.get("sow_month", 0)) < 1 or int(r["sow_month"]) > 12 or int(r.get("sow_date", 0)) < 1 or int(r["sow_date"]) > 28): return false
		if row.has("land_use_units") and (r["kind"] != "crop" or not FormalLedgerState.valid_amount(row["land_use_units"]) or int(row["land_use_units"]) > int(r["land_units"])): return false
		if not FormalLedgerState.valid_amount(row.get("from_day", 0)) or not FormalLedgerState.valid_amount(row.get("until_day", 1000000)) or int(row.get("from_day", 0)) >= int(row.get("until_day", 1000000)): return false
		seen[row["actor"]] = true
	return true

func resource_keep(actor: String, good: String) -> int:
	var row: Dictionary = rule(actor)
	if row.get("good") != good or not row.has("resource"): return 0
	var e: RefCounted = economy()
	var r: Dictionary = row["resource"]
	var seed: int = int(row.get("land_use_units", r.get("land_units", 0))) * int(r.get("seed_per_unit", 0))
	var household: int = 0
	for category: String in e._actor_categories(actor):
		var unit: int = e._service(good, category)
		if unit > 0: household += (e._daily_need(actor, category) * int(e.config["stock_horizon"]) + unit - 1) / unit
	return seed + maxi(int(r.get("food_reserve", 0)), household)

func sale_available(site: String, good: String) -> int:
	var e: RefCounted = economy()
	return maxi(0, e._lots.quantity_at(location(site), good) - e._committed(site, good) - resource_keep(site, good))

## Cumulative actual uses grouped by physical source. Annual uses are differences
## of observations at year boundaries, not a replay or a second stock authority.
func agricultural_observation(actor: String) -> Dictionary:
	var e: RefCounted = economy()
	var cfg: Dictionary = rule(actor)
	if cfg.get("resource", {}).get("kind") != "crop": return {}
	var good: String = cfg["good"]
	var rows: Dictionary = {}
	var seed: Dictionary = {}
	var processing: Dictionary = {}
	for cycle: Dictionary in crop_cycles.get(actor, {}).values():
		for ref: Dictionary in cycle["inputs"]:
			seed[ref["source_id"]] = int(seed.get(ref["source_id"], 0)) + int(ref["quantity"])
	var outputs: Dictionary = {}
	for id: String in e._lots._owner_history.get(actor, []):
		var p: Dictionary = e._lots.portions[id]
		outputs[p["source_id"]] = true
	for id: String in outputs:
		for ref: Dictionary in e._lots.sources[id]["inputs"]:
			var p: Dictionary = e._lots.portions[ref["portion_id"]]
			# Crop inputs are already seed. Only an actual different output is processing.
			if p["owner"] == actor and p["good"] == good and e._lots.sources[id]["good"] != good:
				processing[ref["source_id"]] = int(processing.get(ref["source_id"], 0)) + int(ref["quantity"])
	for id: String in e._lots._owner_history.get(actor, []):
		var p: Dictionary = e._lots.portions[id]
		if p["good"] != good: continue
		var source: Dictionary = e._lots.sources[p["source_id"]]
		var production: bool = str(source["id"]).begins_with("resource:" + actor + ":")
		var row: Dictionary = rows.get_or_add(source["id"], {"source_id": source["id"], "origin": "HARVEST" if production else "OPENING" if str(source["id"]).begins_with("opening:") else "EXTERNAL", "formed_minute": source["formed_minute"], "opening": 0, "harvest": 0, "external_in": 0, "seed": 0, "household": 0, "processing": 0, "sold": 0, "other_out": 0, "loss": 0, "held": 0})
		var parent: Dictionary = e._lots.portions.get(p["parent_portion_id"], {})
		if parent.is_empty(): row["harvest" if production else "opening" if row["origin"] == "OPENING" else "external_in"] += int(p["quantity"])
		elif parent["owner"] != actor: row["external_in"] += int(p["quantity"])
		row["household"] += int(p["consumed"])
		row["loss"] += int(p["lost"])
		row["held"] += int(p["remaining"])
	var receipts: Dictionary = {}
	for id: String in e._lots._owner_outgoing.get(actor, []):
		var p: Dictionary = e._lots.portions[id]
		if p["good"] != good: continue
		var receipt: Dictionary = e._delivery_receipts.get(p["acquisition_id"], {})
		var order: Dictionary = e._orders.get(receipt.get("order_id", ""), {})
		var sale: bool = order.get("kind") == "SALE" and order.get("seller") == actor
		rows[p["source_id"]]["sold" if sale else "other_out"] += int(p["quantity"])
		if sale: receipts[p["acquisition_id"]] = true
	var total: Dictionary = {"opening": 0, "harvest": 0, "external_in": 0, "seed": 0, "household": 0, "processing": 0, "sold": 0, "other_out": 0, "loss": 0, "held": 0}
	for id: String in rows:
		var row: Dictionary = rows[id]
		row["seed"] = int(seed.get(id, 0)); row["processing"] = int(processing.get(id, 0))
		row["household"] -= int(row["seed"]) + int(row["processing"])
		row["balance_error"] = int(row["opening"]) + int(row["harvest"]) + int(row["external_in"]) - int(row["seed"]) - int(row["household"]) - int(row["processing"]) - int(row["sold"]) - int(row["other_out"]) - int(row["loss"]) - int(row["held"])
		row["commercialization"] = {"numerator": row["sold"], "denominator": row["harvest"]} if row["origin"] == "HARVEST" else null
		row["self_consumption"] = {"numerator": row["household"], "denominator": row["harvest"]} if row["origin"] == "HARVEST" else null
		for key: String in total: total[key] += int(row[key])
	var money: int = 0
	for id: String in receipts:
		var receipt: Dictionary = e._delivery_receipts[id]
		money += e._receipt_goods_amount(receipt, e._orders[receipt["order_id"]])
	var seed_plan: int = int(cfg.get("land_use_units", cfg["resource"]["land_units"])) * int(cfg["resource"]["seed_per_unit"])
	var rate: int = e._local_quotes.market_rate(actor, good) if e._local_quotes.market_enabled() else int(cfg["price"]) * 1000
	var values: Dictionary = {"basis": "CURRENT_ASK_NOT_CONFIRMED_MARKET_VALUE", "minor_per_unit_milli": rate, "divisor": 1000, "no_ledger_credit": true}
	for use: String in ["harvest", "household", "held"]: values[use] = FormalLedgerState.ratio(rate, int(total[use]), 1000)
	return {"actor": actor, "good": good, "unit": e._good_units()[good], "as_of_day": e.day, "scope": "CUMULATIVE_ACTUAL_SOURCE_USES", "totals": total, "sources": rows, "committed_undelivered": e._committed(actor, good), "planned_retention": resource_keep(actor, good), "planned_seed": seed_plan, "planned_household": resource_keep(actor, good) - seed_plan, "sale_available": sale_available(actor, good), "cash_goods_income": money, "denomination": e._sale_currency(actor), "food_service": e._totals[actor]["categories"]["food"].duplicate(true), "unmodeled": {"livestock_feed": null, "in_kind_rent_tax_wages_barter": null, "spoilage": null, "nutrition": null}, "loss_scope": "RECORDED_RULE_EVENTS_ONLY", "reference_valuation": values}

static func agricultural_period(opening: Dictionary, closing: Dictionary) -> Dictionary:
	if opening.is_empty() or closing.is_empty() or opening["actor"] != closing["actor"] or opening["good"] != closing["good"] or opening["denomination"] != closing["denomination"] or int(opening["as_of_day"]) >= int(closing["as_of_day"]): return {}
	var flow: Dictionary = {}
	for key: String in closing["totals"]: flow[key] = int(closing["totals"][key]) - int(opening["totals"][key])
	flow["opening"] = opening["totals"]["held"]; flow["held"] = closing["totals"]["held"]
	var fresh_sales: int = 0; var fresh_food: int = 0
	for source: Dictionary in closing["sources"].values():
		if source["origin"] == "HARVEST" and int(source["formed_minute"]) > int(opening["as_of_day"]) * 1440:
			fresh_sales += int(source["sold"]); fresh_food += int(source["household"])
	var need: int = int(closing["food_service"]["required"]) - int(opening["food_service"]["required"])
	var satisfied: int = int(closing["food_service"]["satisfied"]) - int(opening["food_service"]["satisfied"])
	return {"from_day_exclusive": opening["as_of_day"], "to_day_inclusive": closing["as_of_day"], "flows": flow, "new_harvest_sold": fresh_sales, "new_harvest_household": fresh_food, "commercialization": {"numerator": fresh_sales, "denominator": flow["harvest"]}, "new_harvest_consumption": {"numerator": fresh_food, "denominator": flow["harvest"]}, "food_service": {"required": need, "satisfied": satisfied}, "cash_goods_income": int(closing["cash_goods_income"]) - int(opening["cash_goods_income"]), "balance_error": int(flow["opening"]) + int(flow["harvest"]) + int(flow["external_in"]) - int(flow["seed"]) - int(flow["household"]) - int(flow["processing"]) - int(flow["sold"]) - int(flow["other_out"]) - int(flow["loss"]) - int(flow["held"])}

func _resource_output(row: Dictionary, quantity: int, suffix: String, inputs: Array[Dictionary]) -> void:
	if quantity <= 0: return
	var e: RefCounted = economy()
	var actor: String = row["actor"]
	var id: String = "resource:" + actor + ":" + suffix
	if e._lots.sources.has(id): return
	var made: bool = e._lots.create(id, row["good"], e._good_units()[row["good"]], quantity, actor, "ACTOR|" + actor, e._place(actor), e._world.game_clock.total_minutes(), "GEOGRAPHIC_RESOURCE_AND_ACTUAL_LOCAL_WORK|" + str(row["resource"]["id"]), inputs)
	assert(made)
	e._physical_totals[actor]["produced"][row["good"]] += quantity
	if row["resource"]["kind"] == "mineral": _extracted[row["resource"]["id"]] = int(_extracted.get(row["resource"]["id"], 0)) + quantity

func rebuild_resource_index() -> void:
	_active_crops.clear(); _extracted.clear()
	for actor: String in crop_cycles:
		for year: String in crop_cycles[actor]:
			if int(crop_cycles[actor][year]["harvest_day"]) < 0:
				if not _active_crops.has(actor): _active_crops[actor] = []
				_active_crops[actor].append(year)
	for source: Dictionary in economy()._lots.sources.values():
		if not str(source["id"]).begins_with("resource:"): continue
		var id: String = str(source["basis"]).get_slice("|", 1)
		if id.is_empty():
			for row: Dictionary in economy().config.get("resource_producers", []):
				if _resource_owner(source["id"]) == row["actor"]: id = row["resource"]["id"]; break
		_extracted[id] = int(_extracted.get(id, 0)) + int(source["quantity"])

func discovered(row: Dictionary, date: int) -> int:
	var r: Dictionary = row["resource"]
	var quantity: int = int(r["discovered_quantity"])
	for event: Dictionary in r.get("discovery", []):
		if date >= int(event["day"]): quantity += int(event["quantity"])
	return mini(quantity, int(r["geological_quantity"]))

func self_use_target(row: Dictionary, date: int) -> int:
	if not row.get("self_use", false): return 0
	var e: RefCounted = economy()
	var target: int = 0
	for category: String in e._actor_categories(row["actor"]):
		var unit: int = e._service(row["good"], category)
		if unit > 0:
			var need: int = e._need_on_day(row["actor"], category, date)
			target += (need * int(e.config["stock_horizon"]) + unit - 1) / unit
	return target

func sowing_decision(row: Dictionary, units: int, hours: int) -> Dictionary:
	var e: RefCounted = economy()
	var actor: String = row["actor"]
	var r: Dictionary = row["resource"]
	var stock: int = maxi(0, e._lots.quantity_at("ACTOR|" + actor, row["good"]) - e._committed(actor, row["good"]))
	var food_unit: int = e._service(row["good"], "food")
	var reserve: int = 0
	if food_unit > 0:
		reserve = (e._daily_need(actor, "food") * int(r["grow_days"]) + food_unit - 1) / food_unit
	# Current unaccepted quotes are opportunities, not secured food for 180 days.
	# Do not spend the same cash on seed credit or assume future wage/sale income.
	var external: int = 0
	for offer: Dictionary in e._offers(actor):
		if offer["good"] == row["good"] and int(offer["earliest_arrival_day"]) < e.day + int(r["grow_days"]):
			external = maxi(external, int(offer["quantity"]))
	var expected: int = crop_output(r, units, "EXPECTED_NORMAL_WEATHER")
	var selected: int = mini(units, stock / int(r["seed_per_unit"]))
	var reproduction: int = 0
	if row.get("seasonal_reserve", false):
		# Avoid financing today's reserve by eliminating next year's own food.
		# Compare annual household food with expected output NET of its own seed.
		# This is a normal-weather plan, never a guaranteed harvest or income.
		var year: int = int(e._world.game_clock.current_date()["year"])
		var year_days: int = (GameCalendar.to_total_hour({"year": year + 1, "month": 1, "day": 1, "hour": 0}) - GameCalendar.to_total_hour({"year": year, "month": 1, "day": 1, "hour": 0})) / 24
		var annual_food: int = (e._need_total(actor, "food", year_days) + maxi(1, food_unit) - 1) / maxi(1, food_unit)
		var net: int = expected - units * int(r["seed_per_unit"])
		if net > 0: reproduction = mini(selected, (annual_food * units + net - 1) / net)
		selected = mini(selected, maxi(reproduction, maxi(0, stock - reserve) / int(r["seed_per_unit"])))
		# Both sowing and eventual harvest must fit this household's labor pool.
		selected = mini(selected, hours / int(r["harvest_hours"]))
		if crop_output(r, selected, "EXPECTED_NORMAL_WEATHER") <= selected * int(r["seed_per_unit"]): selected = 0
	return {"stock": stock, "preharvest_food": reserve, "known_affordable_external": external, "secured_external": 0, "land_labor_limit": units, "expected_full_output": expected, "annual_food_seed_units": reproduction, "selected_units": selected, "seed": selected * int(r["seed_per_unit"]), "sow_hours": selected * int(r["sow_hours"]), "harvest_hours": selected * int(r["harvest_hours"]), "basis": "FINITE_FOOD_RESERVE_AND_NEXT_CROP_NET_FOOD_UNCONTRACTED_QUOTES_NOT_GUARANTEED"}

func mineral_available(row: Dictionary, date: int, extracted: int, price: int) -> int:
	var r: Dictionary = row["resource"]
	if price < int(r["economic_cost"]) or date % int(r["equipment_period"]) == 0: return 0
	return maxi(0, mini(int(r["geological_quantity"]), discovered(row, date)) - extracted)

static func crop_output(r: Dictionary, units: int, year: String) -> int:
	var quantity: float = float(units * int(r["yield_per_unit"]))
	for factor: String in ["suitability_permille", "fertility_permille", "climate_permille", "technology_permille"]: quantity *= float(r[factor]) / 1000.0
	return int(floor(quantity * float(r.get("weather_by_year_permille", {}).get(year, 1000)) / 1000.0))

func _produce_resources() -> void:
	var e: RefCounted = economy()
	var date: Dictionary = e._world.game_clock.current_date()
	var occupied: Dictionary = {}
	for actor: String in _active_crops:
		var id: String = rule(actor)["resource"]["id"]
		for year: String in _active_crops[actor]: occupied[id] = int(occupied.get(id, 0)) + int(crop_cycles[actor][year]["units"])
	for row: Dictionary in e.config.get("resource_producers", []):
		var actor: String = row["actor"]
		if not e.subject_active_at(actor, e._production_minute()): continue
		var r: Dictionary = row["resource"]
		var hours: int = labor_budget(actor, e.day, e._work_records, e._service_market.contracts)
		var permitted: bool = e.day >= int(row.get("from_day", 0)) and e.day < int(row.get("until_day", 1000000))
		if r["kind"] == "mineral":
			if not permitted: continue
			if e.day % int(r["equipment_period"]) == 0:
				e._labor[actor] = maxi(0, hours - int(r["maintenance_hours"]))
				continue # Scheme B: scheduled availability and local maintenance time; no repair goods.
			var market_remaining: int = mineral_available(row, e.day, int(_extracted.get(r["id"], 0)), e._local_quotes.market_rate(actor, row["good"]) / 1000 if e._local_quotes.market_enabled() else int(row["price"]))
			# Unused qualified household labor may meet bounded own fuel needs.
			# The opportunity-cost quote gate still controls commercial supply.
			var self_shortfall: int = maxi(0, self_use_target(row, e.day) - e._lots.quantity_at("ACTOR|" + actor, row["good"], true))
			var remaining: int = maxi(market_remaining, mini(self_shortfall, maxi(0, discovered(row, e.day) - int(_extracted.get(r["id"], 0)))))
			var quantity: int = mini(remaining, mini(int(r["units_per_day"]), hours / int(r["hours_per_unit"])))
			if row.has("stock_cover_days") and market_remaining > 0:
				var cover: int = e._costs.recent_sales(actor, row["good"], 30) * int(row["stock_cover_days"]) / mini(30, e.day + 1)
				var target: int = maxi(quantity, cover) + e._committed(actor, row["good"]) + self_use_target(row, e.day)
				quantity = mini(quantity, maxi(0, target - int(e._stocks[actor][row["good"]])))
			if market_remaining == 0: quantity = mini(quantity, self_shortfall)
			_resource_output(row, quantity, str(e.day), [])
			e._labor[actor] = hours - quantity * int(r["hours_per_unit"])
			continue
		if not crop_cycles.has(actor): crop_cycles[actor] = {}
		var key: String = str(date["year"])
		var cycle: Dictionary = crop_cycles[actor].get(key, {})
		if permitted and cycle.is_empty() and date["month"] == r["sow_month"] and date["day"] == r["sow_date"]:
			var units: int = mini(mini(int(row.get("land_use_units", r["land_units"])), maxi(0, int(r["land_units"]) - int(occupied.get(r["id"], 0)))), hours / int(r["sow_hours"]))
			units = int(sowing_decision(row, units, hours)["selected_units"])
			if units > 0:
				var inputs: Array[Dictionary] = e._lots.selection("ACTOR|" + actor, row["good"], units * int(r["seed_per_unit"]))
				if not inputs.is_empty() and e._lots.consume(inputs, e._world.game_clock.total_minutes()):
					e._physical_totals[actor]["used"][row["good"]] += units * int(r["seed_per_unit"])
					cycle = {"sown_day": e.day, "due_day": e.day + int(r["grow_days"]), "units": units, "inputs": inputs, "harvest_day": -1, "quantity": 0}
					crop_cycles[actor][key] = cycle
					if not _active_crops.has(actor): _active_crops[actor] = []
					_active_crops[actor].append(key)
					occupied[r["id"]] = int(occupied.get(r["id"], 0)) + units
					hours -= units * int(r["sow_hours"])
		for year: String in _active_crops.get(actor, []).duplicate():
			cycle = crop_cycles[actor][year]
			if e.day < int(cycle["due_day"]) or hours < int(cycle["units"]) * int(r["harvest_hours"]): continue
			cycle["quantity"] = crop_output(r, int(cycle["units"]), year)
			cycle["harvest_day"] = e.day
			var seed_inputs: Array[Dictionary] = []
			seed_inputs.assign(cycle["inputs"])
			_resource_output(row, int(cycle["quantity"]), year, seed_inputs)
			_active_crops[actor].erase(year)
			occupied[r["id"]] -= int(cycle["units"])
			if hours > 0: hours -= int(cycle["units"]) * int(r["harvest_hours"])
		e._labor[actor] = hours

func resource_view(actor: String) -> Dictionary:
	var e: RefCounted = economy()
	var row: Dictionary = rule(actor)
	var r: Dictionary = row["resource"]
	var made: int = int(e._physical_totals[actor]["produced"][row["good"]])
	var result: Dictionary = {"actor": actor, "resource_id": r["id"], "good": row["good"], "geographic_unit_id": r["geographic_unit_id"], "source_url": r["source_url"], "quantity_basis": r["quantity_basis"], "produced": made, "sale_available": sale_available(actor, row["good"]), "retained": resource_keep(actor, row["good"]), "self_employed_output_owner": actor}
	if r["kind"] == "crop": result["cycles"] = crop_cycles.get(actor, {}).duplicate(true)
	else:
		result["discovered_remaining"] = maxi(0, discovered(row, e.day) - int(_extracted.get(r["id"], 0)))
		result["economic_remaining"] = mineral_available(row, e.day, int(_extracted.get(r["id"], 0)), e._local_quotes.market_rate(actor, row["good"]) / 1000 if e._local_quotes.market_enabled() else int(row["price"]))
		if e.day < int(row.get("from_day", 0)) or e.day >= int(row.get("until_day", 1000000)): result["economic_remaining"] = 0
		result["self_use_target"] = self_use_target(row, e.day)
		result["self_use_shortfall"] = maxi(0, self_use_target(row, e.day) - e._lots.quantity_at("ACTOR|" + actor, row["good"], true))
		result["undiscovered"] = "UNKNOWN_TO_MARKET" # Never expose precise hidden geological potential here.
	return result

func _resource_history_valid() -> bool:
	var e: RefCounted = economy()
	var mineral_sources: Dictionary = {}
	var land_events: Dictionary = {}
	var resources: Dictionary = {}
	var work: Dictionary = {}
	for row: Dictionary in e.config.get("resource_producers", []):
		var actor: String = row["actor"]
		var r: Dictionary = row["resource"]
		resources[r["id"]] = row
		var extracted: int = 0
		var sources: Array[Dictionary] = []
		for source: Dictionary in e._lots.sources.values():
			if _resource_owner(source["id"]) == actor: sources.append(source)
		sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["formed_minute"]) < int(b["formed_minute"]))
		for source: Dictionary in sources:
			if source["good"] != row["good"] or source["basis"] not in ["GEOGRAPHIC_RESOURCE_AND_ACTUAL_LOCAL_WORK", "GEOGRAPHIC_RESOURCE_AND_ACTUAL_LOCAL_WORK|" + str(r["id"])] or int(source["formed_minute"]) > e._world.game_clock.total_minutes(): return false
			if r["kind"] == "crop" and not crop_cycles.get(actor, {}).has(str(source["id"]).get_slice(":", str(source["id"]).get_slice_count(":") - 1)): return false
			if r["kind"] == "mineral":
				if not mineral_sources.has(r["id"]): mineral_sources[r["id"]] = []
				mineral_sources[r["id"]].append(source)
				var date: int = int(source["formed_minute"]) / 1440
				if date < int(row.get("from_day", 0)) or date >= int(row.get("until_day", 1000000)): return false
				var price: int = e._local_quotes.market_rate(actor, row["good"], date) / 1000 if e._local_quotes.market_enabled() else int(row["price"])
				if source["id"] != "resource:" + actor + ":" + str(date) or int(source["formed_minute"]) % 1440 != 0 or int(source["quantity"]) > mini(int(r["units_per_day"]), maxi(mineral_available(row, date, extracted, price), mini(self_use_target(row, date), maxi(0, discovered(row, date) - extracted)))) or int(source["quantity"]) * int(r["hours_per_unit"]) > labor_budget(actor, date, e._work_records, e._service_market.contracts): return false
			extracted += int(source["quantity"])
			if r["kind"] == "mineral" and extracted > discovered(row, int(source["formed_minute"]) / 1440): return false
		if r["kind"] == "mineral" and extracted > int(r["geological_quantity"]): return false
		for key: String in crop_cycles.get(actor, {}):
			var c: Dictionary = crop_cycles[actor][key]
			if int(c["units"]) < 1 or int(c["units"]) > int(row.get("land_use_units", r["land_units"])) or int(c["due_day"]) != int(c["sown_day"]) + int(r["grow_days"]): return false
			var sow_day: int = GameCalendar.to_total_hour({"year": key.to_int(), "month": r["sow_month"], "day": r["sow_date"], "hour": 0}) / 24
			if sow_day < int(row.get("from_day", 0)) or sow_day >= int(row.get("until_day", 1000000)): return false
			if int(c["sown_day"]) != sow_day or int(c["sown_day"]) > e.day or int(c["units"]) * int(r["sow_hours"]) > labor_budget(actor, sow_day, e._work_records, e._service_market.contracts): return false
			if not land_events.has(r["id"]): land_events[r["id"]] = []
			land_events[r["id"]].append(Vector2i(sow_day, int(c["units"])))
			work[actor + "|" + str(sow_day)] = int(work.get(actor + "|" + str(sow_day), 0)) + int(c["units"]) * int(r["sow_hours"])
			if int(c["harvest_day"]) >= 0 and (int(c["quantity"]) != crop_output(r, int(c["units"]), key) or int(c["units"]) * int(r["harvest_hours"]) > labor_budget(actor, int(c["harvest_day"]), e._work_records, e._service_market.contracts)): return false
			if int(c["harvest_day"]) >= 0:
				land_events[r["id"]].append(Vector2i(int(c["harvest_day"]), -int(c["units"])))
				var work_key: String = actor + "|" + str(c["harvest_day"])
				work[work_key] = int(work.get(work_key, 0)) + int(c["units"]) * int(r["harvest_hours"])
			var seeds: int = 0
			for input: Dictionary in c["inputs"]:
				var p: Dictionary = e._lots.portions.get(input["portion_id"], {})
				if p.is_empty() or p["owner"] != actor or p["good"] != row["good"] or int(p["consumed"]) < int(input["quantity"]): return false
				seeds += int(input["quantity"])
			if seeds != int(c["units"]) * int(r["seed_per_unit"]): return false
			var output: Dictionary = e._lots.sources.get("resource:" + actor + ":" + key, {})
			if int(c["harvest_day"]) < 0:
				if not output.is_empty() or int(c["quantity"]) != 0: return false
			elif int(c["quantity"]) == 0:
				if not output.is_empty() or int(c["harvest_day"]) < int(c["due_day"]): return false
			elif int(c["harvest_day"]) < int(c["due_day"]) or int(output.get("quantity", -1)) != int(c["quantity"]) or int(output.get("formed_minute", -1)) != int(c["harvest_day"]) * 1440: return false
	for id: String in mineral_sources:
		mineral_sources[id].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["formed_minute"]) < int(b["formed_minute"]))
		var used: int = 0
		for source: Dictionary in mineral_sources[id]:
			used += int(source["quantity"])
			if used > discovered(resources[id], int(source["formed_minute"]) / 1440): return false
	for id: String in land_events:
		land_events[id].sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.x != b.x else a.y < b.y)
		var used: int = 0
		for event: Vector2i in land_events[id]:
			used += event.y
			if used < 0 or used > int(resources[id]["resource"]["land_units"]): return false
	for key: String in work:
		var parts := key.split("|")
		if int(work[key]) > labor_budget(parts[0], parts[1].to_int(), e._work_records, e._service_market.contracts): return false
	return true
