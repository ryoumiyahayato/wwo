extends RefCounted
## Ephemeral projection of the original person's plans, stock and responsibilities.
## No stored demand, inventory, timer, money, authority or substitute execution.
## Future ordinary day routes use their real midnight transport boundaries;
## entered final timed legs retain their exact arrival minute, never day-ceil.

static func _unsupported(reason: String, detail: Dictionary = {}) -> Dictionary:
	return {"supported": false, "reason": reason, "detail": detail, "events": [], "categories": {}, "quantity": 0}

static func context(e: RefCounted, person: String) -> Dictionary:
	var p: RefCounted = e._world.personal_economy_state
	var now: int = e._world.game_clock.total_minutes()
	if not e.personal_authorized(person) or not e._at_place(person, e._place(person)):
		return _unsupported("PERSONAL_ARRANGEMENT_OWNER_UNAVAILABLE")
	var horizon: int = clampi(int(e.config["stock_horizon"]), 1, 30)
	if now > 9223372036854732607: return _unsupported("PERSONAL_ARRANGEMENT_TIME_RANGE_LIMIT")
	var end: int = now + horizon * 1440
	var events: Array = []
	var goods: Dictionary = {}
	var categories: Dictionary = {}
	var plans: Dictionary = p._arrangements.get(person, {})
	for commodity: String in plans:
		if not commodity.begins_with("native:"):
			return _unsupported("MIXED_LEGACY_NATIVE_ARRANGEMENTS_REQUIRE_HANDOVER_PROJECTION", {"commodity": commodity})
		var plan: Dictionary = plans[commodity]
		if plan.get("mode") != "flow": continue # Original durable holding authority stays separate.
		var item: Dictionary = e.personal_commodity(commodity)
		var category: String = str(plan.get("need_category", ""))
		if item.is_empty() or item.get("mode") != "flow" or item.get("need_category") != category or int(plan.get("period_minutes", 0)) != 1440:
			return _unsupported("PERSONAL_ARRANGEMENT_PLAN_SHAPE_UNSUPPORTED", {"commodity": commodity})
		var positive_uses: int = 0
		for use: String in item["services"]:
			if int(item["services"][use]) > 0: positive_uses += 1
		# A multi-use item could also be claimed by midnight durable/other flow
		# consumption. Do not duplicate it in a second independent projection.
		if positive_uses != 1:
			return _unsupported("PERSONAL_ARRANGEMENT_MULTI_USE_REQUIRES_JOINT_CONSUMPTION_PROJECTION", {"commodity": commodity})
		var due: int = int(plan["next_due_minute"])
		if due <= now: return _unsupported("PERSONAL_ARRANGEMENT_CURRENT_DUE_NOT_SETTLED", {"commodity": commodity, "due_minute": due})
		var unit: int = e._service(item["good"], category)
		if unit <= 0 or int(plan["quantity"]) <= 0: return _unsupported("PERSONAL_ARRANGEMENT_INVALID_UNIT_OR_QUANTITY")
		goods[item["good"]] = commodity
		categories[category] = true
		while due <= end:
			if not e.subject_active_at(person, due): return _unsupported("PERSONAL_ARRANGEMENT_SCOPE_ENDS_BEFORE_DUE")
			events.append({"commodity": commodity, "good": item["good"], "category": category, "minute": due, "day": due / 1440, "quantity": int(plan["quantity"]), "unit": unit})
			due += 1440
	if events.is_empty(): return _unsupported("NO_FUTURE_NATIVE_FLOW_ARRANGEMENT_IN_WINDOW")
	if events.size() > 512: return _unsupported("PERSONAL_ARRANGEMENT_FINITE_WINDOW_LIMIT")
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["minute"]) < int(b["minute"]) if a["minute"] != b["minute"] else str(a["commodity"]) < str(b["commodity"]))
	var needs: Dictionary = {}
	var nominal_remaining: Dictionary = {}
	for event: Dictionary in events:
		var key: String = str(event["day"]) + "|" + str(event["category"])
		if not needs.has(key):
			var date: int = event["day"]
			var category: String = event["category"]
			var required: int = e._need_on_day(person, category, date)
			if date == e.day and e._needs.get(person, {}).get("day", -1) == date:
				required = int(e._needs[person]["categories"][category]["unmet"])
			elif category == "food": required -= mini(required, e._service_market._resident.food_units(person, date))
			needs[key] = {"day": date, "category": category, "quantity": required}
			nominal_remaining[key] = required
		var available_need: int = int(nominal_remaining[key])
		# Original personal_consume rejects the entire offered item quantity if
		# it exceeds ceil(current unmet / service). Never silently resize a plan.
		if int(event["quantity"]) > (available_need + int(event["unit"]) - 1) / int(event["unit"]):
			return _unsupported("PERSONAL_ARRANGEMENTS_EXCEED_SHARED_DAILY_NEED", {"commodity": event["commodity"], "due_minute": event["minute"], "remaining_service": available_need})
		nominal_remaining[key] = maxi(0, available_need - int(event["quantity"]) * int(event["unit"]))
	var physical: Dictionary = e.personal_inventory(person)
	var batches: Array = []
	for good: String in goods:
		var incoming: Dictionary = e._input_incoming_observation(person, good, end / 1440)
		for source: Dictionary in incoming["batches"]:
			var order: Dictionary = e._orders.get(source.get("order_id", ""), {})
			if order.is_empty() or order["kind"] != "SALE" or order["to_place_id"] != e._place(person): continue
			var minute: Variant = int(source["observed_arrival_day"]) * 1440 if source.get("observed_arrival_day") != null else null
			var cargo: Dictionary = e._shipments.get(source.get("shipment_id", ""), {})
			if not cargo.is_empty() and source["stage"] not in ["UNRESOLVED_PHYSICAL_LOSS", "PENDING_SOURCE_LOSS_OR_REPLACEMENT_REQUIRED"]:
				var last: bool = int(cargo["leg_index"]) + 1 == order["route_legs"].size()
				var edge_id: String = order["route_legs"][int(cargo["leg_index"])]["edge_id"]
				if last and cargo["stage"] in ["TRANSIT", "LOADING"] and not e._shared.bindings.get(edge_id, {}).has("node_resources"):
					# Entered final leg timing is an original locked responsibility,
					# not a retrospective day-rounded estimate or new promise.
					minute = int(cargo["arrival_minute"]) if cargo.has("arrival_minute") else int(cargo["leg_arrival_day"]) * 1440
			batches.append({"good": good, "quantity": int(source["quantity"]), "available_minute": minute, "order_id": source["order_id"], "shipment_id": source.get("shipment_id", ""), "stage": source["stage"]})
	var holds: Dictionary = {}
	for id: String in e._service_market._active:
		var contract: Dictionary = e._service_market.contracts[id]
		if contract["kind"] != "DINING" or contract["client"] != person or contract["status"] not in ["ACCEPTED", "WAITING"]: continue
		var terms: Dictionary = e._service_market._offers[contract["offer_id"]]["resident_terms"]
		var remaining: int = maxi(0, int(contract["quantity"]) - int(contract["resident"]["fulfilled"]))
		holds["food"] = int(holds.get("food", 0)) + remaining * int(terms["units_per_service"])
	return {"supported": true, "reason": "EXACT_FUTURE_NATIVE_ARRANGEMENT_MINUTES", "person": person, "now": now, "end": end, "events": events, "goods": goods, "categories": categories, "needs": needs, "physical": physical, "batches": batches, "service_holds": holds}

static func project(ctx: Dictionary, risk_hold: bool, extra: Array = []) -> Dictionary:
	if not ctx.get("supported", false): return ctx
	var pool: Dictionary = ctx["physical"].duplicate()
	var batches: Array = ctx["batches"].duplicate(true)
	batches.append_array(extra)
	var added: Dictionary = {}
	var needs: Dictionary = ctx["needs"].duplicate(true)
	var holds: Dictionary = ctx["service_holds"].duplicate() if risk_hold else {}
	var rows: Dictionary = {}
	for category: String in ctx["categories"]:
		rows[category] = {"target": 0, "covered": 0, "uncovered": 0, "mode": "flow", "requirements": [], "timing_adoption": true, "procurement_authority": "NATIVE_PERSONAL_ARRANGEMENT", "coverage_basis": "ORIGINAL_NEXT_DUE_MINUTES_SHARED_DAILY_NEED_AND_GOODS", "eta_guaranteed": false}
	for event: Dictionary in ctx["events"]:
		for index: int in batches.size():
			if added.has(index): continue
			var batch: Dictionary = batches[index]
			var eta: Variant = batch["available_minute"]
			if (eta == null and risk_hold) or (eta != null and int(eta) <= int(event["minute"])):
				pool[batch["good"]] = int(pool.get(batch["good"], 0)) + int(batch["quantity"])
				added[index] = true
		var key: String = str(event["day"]) + "|" + str(event["category"])
		var need: Dictionary = needs[key]
		var quantity: int = mini(int(event["quantity"]), int(pool.get(event["good"], 0)))
		# Same shared category boundary as personal_consumption_quote. No flow
		# item remainder becomes a service credit carried into another day.
		if quantity > (int(need["quantity"]) + int(event["unit"]) - 1) / int(event["unit"]): quantity = 0
		var served: int = mini(int(need["quantity"]), quantity * int(event["unit"]))
		pool[event["good"]] = int(pool.get(event["good"], 0)) - quantity
		need["quantity"] = int(need["quantity"]) - served
		rows[event["category"]]["requirements"].append({"boundary_minute": event["minute"], "commodity": event["commodity"], "requested_goods": event["quantity"], "possible_used_goods": quantity, "possible_service": served, "remaining_day_service": need["quantity"], "eta_guaranteed": false})
	for key: String in needs:
		var category: String = needs[key]["category"]
		rows[category]["target"] += int(ctx["needs"][key]["quantity"])
		var held: int = mini(int(needs[key]["quantity"]), int(holds.get(category, 0)))
		holds[category] = int(holds.get(category, 0)) - held
		rows[category]["uncovered"] += int(needs[key]["quantity"]) - held
	for category: String in rows: rows[category]["covered"] = int(rows[category]["target"]) - int(rows[category]["uncovered"])
	return {"supported": true, "categories": rows}

static func candidate_batches(e: RefCounted, person: String, offer: Dictionary, quantity: int) -> Array:
	if quantity <= 0: return []
	var onsite: bool = str(offer.get("route_id", "")).begins_with("onsite:")
	if onsite: return [{"good": offer["good"], "quantity": quantity, "available_minute": e._world.game_clock.total_minutes()}]
	var arrival: Variant = e._input_offer_arrival(offer)
	var size: int = e._input_offer_batch_size(offer)
	if arrival == null or size <= 0: return []
	var preview := {"buyer": person, "route_id": offer["route_id"], "route_legs": offer["route_legs"], "accepted_day": e.day, "accepted_minute": e._world.game_clock.total_minutes()}
	var day: int = maxi(int(arrival), maxi(e._next_dispatch_boundary(), e._earliest_dispatch(preview)) + e._travel_days(offer["route_legs"]))
	var result: Array = []
	for offset: int in range(31):
		if quantity <= 0: break
		var amount: int = mini(quantity, size)
		result.append({"good": offer["good"], "quantity": amount, "available_minute": (day + offset) * 1440})
		quantity -= amount
	return result

static func candidate_need(e: RefCounted, person: String, commodity: String, offer: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty(): ctx = context(e, person)
	if not ctx.get("supported", false): return ctx
	var plan: Dictionary = e._world.personal_economy_state._arrangements.get(person, {}).get(commodity, {})
	var result := {"supported": true, "quantity": 0, "reason": "WAIT_EXISTING_RESPONSIBILITY_OR_NO_USEFUL_ARRIVAL", "eta_guaranteed": false}
	if plan.is_empty() or not plan.get("auto_buy_missing", false) or plan.get("mode") != "flow":
		result["reason"] = "PERSONAL_ARRANGEMENT_NO_FLOW_AUTO_BUY_AUTHORITY"
		return result
	var good: String = commodity.trim_prefix("native:")
	if offer.get("good") != good: return result
	var requested: int = 0
	for event: Dictionary in ctx["events"]:
		if event["good"] == good: requested += int(event["quantity"])
	var cap: int = mini(1000000, mini(requested, mini(maxi(0, int(offer.get("quantity", 0))), maxi(0, int(offer.get("transport_quantity", 0))))))
	if cap <= 0:
		result["reason"] = "NO_AVAILABLE_OR_FUNDED_PERSONAL_ARRANGEMENT_OFFER"
		return result
	var category: String = plan["need_category"]
	var base: Dictionary = project(ctx, true)["categories"][category]
	var extra: Array = candidate_batches(e, person, offer, cap)
	if extra.is_empty():
		result["reason"] = "PERSONAL_ARRANGEMENT_CANDIDATE_ARRIVAL_UNKNOWN"
		return result
	var full: Dictionary = project(ctx, true, extra)["categories"][category]
	var benefit: int = maxi(0, int(base["uncovered"]) - int(full["uncovered"]))
	if benefit <= 0: return result
	var low: int = 1
	var high: int = cap
	while low < high:
		var middle: int = (low + high) / 2
		var test: Dictionary = project(ctx, true, candidate_batches(e, person, offer, middle))["categories"][category]
		if int(base["uncovered"]) - int(test["uncovered"]) >= benefit: high = middle
		else: low = middle + 1
	result.merge({"quantity": low, "reason": "USEFUL_EXACT_FUTURE_ARRANGEMENT_BOUNDARY", "service_improvement": benefit, "arrival_batches": candidate_batches(e, person, offer, low), "requirements_before": base["requirements"], "requirements_after": project(ctx, true, candidate_batches(e, person, offer, low))["categories"][category]["requirements"]}, true)
	return result

static func position(e: RefCounted, person: String) -> Dictionary:
	var ctx: Dictionary = context(e, person)
	if not ctx.get("supported", false): return ctx
	var timed: Dictionary = project(ctx, false)
	var held: Dictionary = project(ctx, true)
	for category: String in timed["categories"]:
		timed["categories"][category]["unknown_responsibility_hold"] = maxi(0, int(timed["categories"][category]["uncovered"]) - int(held["categories"][category]["uncovered"]))
	return timed
