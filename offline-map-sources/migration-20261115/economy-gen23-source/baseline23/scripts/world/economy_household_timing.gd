extends RefCounted
## Read-only projections over original household lots, orders and requirements.
## Nothing here creates inventory, money, authority, schedules or a second ledger.
## Known ETA is a lower bound. Unknown responsibility is a finite spending hold,
## never reported as actual inventory or guaranteed timely consumption.

static func first_day(e: RefCounted) -> int:
	# Daily consumption follows procurement and dispatch. READY at midnight is
	# already after consumption; day zero is the opening, not an unpaid meal.
	var open_today: bool = e.processing and e.phase in ["MESSAGES", "ARRIVALS", "OPERATIONS", "LABOR", "CREDIT", "CAPITAL_CONSTRUCTION", "PRODUCTION", "PROCUREMENT", "DISPATCH"] and int(e._world.game_clock.total_minutes()) % 1440 == 0
	return maxi(1, int(e.day) if open_today else int(e.day) + 1)

static func _has_personal_flow_schedule(e: RefCounted, actor: String) -> bool:
	if not e.manages_person(actor): return false
	for category: String in e._actor_categories(actor):
		if e._spec["categories"][category]["mode"] == "flow" and e._world.personal_economy_state.schedules_category(actor, category): return true
	return false

static func _legacy_position(e: RefCounted, actor: String) -> Dictionary:
	# Legacy projection is retained only for unarranged categories when a person
	# has separate native flow plans. It never authorizes scheduled-category buys.
	var items: Dictionary = e.personal_inventory(actor) if e.manages_person(actor) else e._stocks[actor].duplicate(true)
	for id: String in e._active_by_buyer.get(actor, []):
		var order: Dictionary = e._orders[id]
		if order["kind"] == "SALE" and order["need_category"] == "" and (not e.manages_person(actor) or order["to_place_id"] == e._place(actor)):
			items[order["good"]] = int(items[order["good"]]) + int(order["pending"]) + int(order["transit"])
	var result: Dictionary = {}
	for category: String in e._actor_categories(actor):
		var target: int = e._daily_need(actor, category)
		if e._spec["categories"][category]["mode"] == "flow":
			var elapsed: int = maxi(1, e._managed_days(actor, e.day))
			target = e._need_total(actor, category, elapsed + int(e.config["stock_horizon"]) - 1) - e._need_total(actor, category, elapsed - 1)
		var covered: int = mini(target, e._service_market._resident.planning_cover(actor)) if category == "food" else 0
		for id: String in e._active_by_buyer.get(actor, []):
			var order: Dictionary = e._orders[id]
			if order["kind"] == "SALE" and order["need_category"] == category and (not e.manages_person(actor) or order["to_place_id"] == e._place(actor)):
				covered = mini(target, covered + (int(order["pending"]) + int(order["transit"])) * e._service(order["good"], category))
		for good: String in e._consumption_goods(category, actor):
			var unit: int = e._service(good, category)
			var quantity: int = mini(int(items[good]), (maxi(0, target - covered) + unit - 1) / unit)
			items[good] = int(items[good]) - quantity
			covered = mini(target, covered + quantity * unit)
		result[category] = {"target": target, "covered": covered, "uncovered": target - covered, "mode": e._spec["categories"][category]["mode"], "timing_adoption": false, "coverage_basis": "UNARRANGED_CATEGORIES_RETAIN_LEGACY_WHILE_NATIVE_PLANS_OWN_MINUTES"}
	return result

static func _context(e: RefCounted, actor: String) -> Dictionary:
	var start: int = first_day(e)
	var horizon: int = clampi(int(e.config["stock_horizon"]), 1, 30)
	var context := {"actor": actor, "start": start, "horizon": horizon, "physical": e.personal_inventory(actor) if e.manages_person(actor) else e._stocks[actor].duplicate(true), "batches": [], "service_holds": []}
	for good: String in e._goods:
		if int(e._incoming_by_key.get(actor + "|" + good, 0)) <= 0: continue
		var incoming: Dictionary = e._input_incoming_observation(actor, good, start + horizon - 1)
		for original: Dictionary in incoming["batches"]:
			var order: Dictionary = e._orders.get(original.get("order_id", ""), {})
			if order.is_empty() or order["kind"] != "SALE" or (e.manages_person(actor) and order["to_place_id"] != e._place(actor)): continue
			var batch: Dictionary = original.duplicate(true)
			batch["good"] = good
			batch["category"] = str(order.get("need_category", ""))
			context["batches"].append(batch)
	# Pending dining does not establish actual food. Retain a finite uncertainty
	# hold once per original unfinished contract, using its actual service units.
	var market: RefCounted = e._service_market
	for id: String in market._active:
		var contract: Dictionary = market.contracts[id]
		if contract["kind"] != "DINING" or contract["client"] != actor or contract["status"] not in ["ACCEPTED", "WAITING"]: continue
		var terms: Dictionary = market._offers[contract["offer_id"]]["resident_terms"]
		var quantity: int = maxi(0, int(contract["quantity"]) - int(contract["resident"]["fulfilled"]))
		if quantity > 0: context["service_holds"].append({"contract_id": id, "category": "food", "units": quantity * int(terms["units_per_service"])})
	return context

static func _project(e: RefCounted, context: Dictionary, mode: String, extra: Array = []) -> Dictionary:
	var actor: String = context["actor"]
	var categories: Array = e._actor_categories(actor)
	var rows: Dictionary = {}
	for category: String in categories:
		rows[category] = {"target": 0, "covered": 0, "uncovered": 0, "objective_uncovered": 0, "mode": e._spec["categories"][category]["mode"], "requirements": [], "first_uncovered_day": null}
	var pool: Array = []
	for good: String in context["physical"]:
		if int(context["physical"][good]) > 0: pool.append({"good": good, "quantity": int(context["physical"][good]), "category": ""})
	var batches: Array = context["batches"].duplicate(true)
	batches.append_array(extra)
	var added: Dictionary = {}
	var holds: Dictionary = {}
	if mode in ["RISK_HOLD", "ALL_RESPONSIBILITIES"]:
		for hold: Dictionary in context["service_holds"]: holds[hold["category"]] = int(holds.get(hold["category"], 0)) + int(hold["units"])
	for date: int in range(int(context["start"]), int(context["start"]) + int(context["horizon"])):
		for index: int in batches.size():
			if added.has(index): continue
			var batch: Dictionary = batches[index]
			var eta: Variant = batch.get("observed_arrival_day")
			var ready: bool = mode == "ALL_RESPONSIBILITIES" or (eta == null and mode == "RISK_HOLD") or (eta != null and int(eta) <= date)
			if ready:
				pool.append({"good": batch["good"], "quantity": int(batch["quantity"]), "category": batch.get("category", "")})
				added[index] = true
		# Durable use blocks a physical item from another category in this same
		# boundary but does not destroy it. Flow use removes whole actual items;
		# spare service within one item is not banked as fictional future food.
		var durable_used: Dictionary = {}
		for category: String in categories:
			var row: Dictionary = rows[category]
			var required: int = e._need_on_day(actor, category, date) if e.subject_active_at(actor, date * 1440) else 0
			var remaining: int = required
			if category == "food": remaining -= mini(remaining, e._service_market._resident.food_units(actor, date))
			var hold_used: int = mini(remaining, int(holds.get(category, 0)))
			remaining -= hold_used
			holds[category] = int(holds.get(category, 0)) - hold_used
			var flow: bool = row["mode"] == "flow"
			for good: String in e._consumption_goods(category, actor):
				var unit: int = e._service(good, category)
				# An assigned future order serves its purpose first. Unassigned
				# physical stock/HOLDING orders remain one shared pool, never one
				# full copy per category.
				for assigned: bool in [true, false]:
					for index: int in pool.size():
						var item: Dictionary = pool[index]
						if item["good"] != good or (item["category"] == category) != assigned or item["category"] not in ["", category]: continue
						var available: int = maxi(0, int(item["quantity"]) - int(durable_used.get(index, 0)))
						var quantity: int = mini(available, (remaining + unit - 1) / unit)
						if quantity <= 0: continue
						remaining -= mini(remaining, quantity * unit)
						if flow: item["quantity"] = int(item["quantity"]) - quantity
						else: durable_used[index] = int(durable_used.get(index, 0)) + quantity
			row["target"] = int(row["target"]) + required if flow else maxi(int(row["target"]), required)
			row["uncovered"] = int(row["uncovered"]) + remaining if flow else maxi(int(row["uncovered"]), remaining)
			row["objective_uncovered"] = int(row["objective_uncovered"]) + remaining
			if remaining > 0 and row["first_uncovered_day"] == null: row["first_uncovered_day"] = date
			row["requirements"].append({"day": date, "boundary_minute": date * 1440, "stage": "CONSUMPTION_AFTER_PROCUREMENT_AND_DISPATCH", "required": required, "possible_covered": required - remaining, "uncovered": remaining, "recoverable": true, "eta_guaranteed": false})
	for category: String in categories: rows[category]["covered"] = int(rows[category]["target"]) - int(rows[category]["uncovered"])
	return rows

static func position(e: RefCounted, actor: String) -> Dictionary:
	if _has_personal_flow_schedule(e, actor):
		var result: Dictionary = _legacy_position(e, actor)
		var arranged: Dictionary = e.personal_arrangement_position(actor)
		for category: String in result:
			if not e._world.personal_economy_state.schedules_category(actor, category) or e._spec["categories"][category]["mode"] != "flow": continue
			if arranged.get("supported", false) and arranged["categories"].has(category): result[category] = arranged["categories"][category]
			else:
				result[category]["timing_adoption"] = false
				result[category]["coverage_basis"] = arranged.get("reason", "PERSONAL_ARRANGEMENT_TIMING_UNSUPPORTED")
			result[category]["procurement_authority"] = "NATIVE_PERSONAL_ARRANGEMENT"
		return result
	var context: Dictionary = _context(e, actor)
	var timed: Dictionary = _project(e, context, "TIMED")
	var regular: Dictionary = _project(e, context, "ALL_RESPONSIBILITIES")
	var held: Dictionary = _project(e, context, "RISK_HOLD")
	for category: String in timed:
		var row: Dictionary = timed[category]
		row["regular_uncovered"] = regular[category]["uncovered"]
		row["unknown_responsibility_hold"] = maxi(0, int(row["objective_uncovered"]) - int(held[category]["objective_uncovered"]))
		row["timing_adoption"] = true
		row["first_need_day"] = context["start"]
		row["coverage_basis"] = "DATED_ORIGINAL_RESPONSIBILITIES_CONDITIONAL_ETA_AND_FINITE_UNKNOWN_HOLD"
		row["missed_today_is_not_backlog"] = int(context["start"]) > int(e.day)
	return timed

static func _candidate_batches(e: RefCounted, actor: String, category: String, offer: Dictionary, quantity: int) -> Array:
	var result: Array = []
	var onsite: bool = str(offer.get("route_id", "")).begins_with("onsite:")
	var arrival: Variant = int(e.day) if onsite else e._input_offer_arrival(offer)
	var batch_size: int = quantity if onsite else e._input_offer_batch_size(offer)
	if not onsite and arrival != null:
		var preview := {"buyer": actor, "route_id": offer["route_id"], "route_legs": offer["route_legs"], "accepted_day": e.day, "accepted_minute": e._world.game_clock.total_minutes()}
		arrival = maxi(int(arrival), maxi(e._next_dispatch_boundary(), e._earliest_dispatch(preview)) + e._travel_days(offer["route_legs"]))
	if arrival == null or batch_size <= 0: return result
	var remaining: int = quantity
	for offset: int in range(31):
		if remaining <= 0: break
		var amount: int = mini(remaining, batch_size)
		result.append({"good": offer["good"], "category": category, "quantity": amount, "observed_arrival_day": int(arrival) + offset})
		remaining -= amount
	return result

static func candidate_need(e: RefCounted, actor: String, category: String, offer: Dictionary, requested: int) -> Dictionary:
	var unit: int = e._service(str(offer.get("good", "")), category)
	var cap: int = mini(maxi(0, requested), maxi(0, int(offer.get("transport_quantity", 0))))
	var result := {"quantity": 0, "regular_quantity": 0, "timing_quantity": 0, "need_by_day": first_day(e), "reason": "WAIT_EXISTING_RESPONSIBILITY_OR_NO_USEFUL_ARRIVAL", "eta_guaranteed": false}
	if unit <= 0 or cap <= 0: return result
	if _has_personal_flow_schedule(e, actor):
		if e._world.personal_economy_state.schedules_category(actor, category) and e._spec["categories"][category]["mode"] == "flow":
			result["reason"] = "NATIVE_PERSONAL_ARRANGEMENT_REQUIRES_ITS_OWN_DUE_AND_AUTO_BUY_AUTHORITY"
			return result
		var legacy: Dictionary = _legacy_position(e, actor)[category]
		result["quantity"] = mini(cap, (int(legacy["uncovered"]) + unit - 1) / unit)
		result["regular_quantity"] = result["quantity"]
		result["reason"] = "UNARRANGED_CATEGORIES_RETAIN_LEGACY_WHILE_NATIVE_PLANS_OWN_MINUTES"
		return result
	var context: Dictionary = _context(e, actor)
	var regular: Dictionary = _project(e, context, "ALL_RESPONSIBILITIES")[category]
	# Routine stock needs must use the same whole-item consumption projection.
	# Ceil(sum(service_need) / unit) would incorrectly carry unused bean service
	# from one day to the next. ALL_RESPONSIBILITIES retains every old liability.
	var regular_extra: Array = [{"good": offer["good"], "category": category, "quantity": cap, "observed_arrival_day": context["start"]}]
	var regular_full: Dictionary = _project(e, context, "ALL_RESPONSIBILITIES", regular_extra)[category]
	var regular_benefit: int = maxi(0, int(regular["objective_uncovered"]) - int(regular_full["objective_uncovered"]))
	var regular_items: int = 0
	if regular_benefit > 0:
		var regular_low: int = 1
		var regular_high: int = cap
		while regular_low < regular_high:
			var middle: int = (regular_low + regular_high) / 2
			regular_extra[0]["quantity"] = middle
			var test: Dictionary = _project(e, context, "ALL_RESPONSIBILITIES", regular_extra)[category]
			if int(regular["objective_uncovered"]) - int(test["objective_uncovered"]) >= regular_benefit: regular_high = middle
			else: regular_low = middle + 1
		regular_items = regular_low
	var base: Dictionary = _project(e, context, "RISK_HOLD")[category]
	var extra: Array = _candidate_batches(e, actor, category, offer, cap)
	var improved: Dictionary = _project(e, context, "RISK_HOLD", extra)[category]
	var benefit: int = maxi(0, int(base["objective_uncovered"]) - int(improved["objective_uncovered"]))
	var timing_items: int = 0
	if benefit > 0:
		# Read-only binary search finds the minimum whole items that achieve this
		# candidate's maximal improvement. One durable can serve several days;
		# one bean cannot keep its unused food service after actual flow use.
		var low: int = 1
		var high: int = cap
		while low < high:
			var middle: int = (low + high) / 2
			var test: Dictionary = _project(e, context, "RISK_HOLD", _candidate_batches(e, actor, category, offer, middle))[category]
			if int(base["objective_uncovered"]) - int(test["objective_uncovered"]) >= benefit: high = middle
			else: low = middle + 1
		timing_items = low
		for index: int in base["requirements"].size():
			if int(improved["requirements"][index]["uncovered"]) < int(base["requirements"][index]["uncovered"]):
				result["need_by_day"] = base["requirements"][index]["day"]
				break
	result["regular_quantity"] = regular_items
	result["timing_quantity"] = timing_items
	result["quantity"] = mini(cap, maxi(regular_items, timing_items))
	result["reason"] = "USEFUL_UNCONSUMED_BOUNDARY" if timing_items > 0 else "REGULAR_UNCOVERED_STOCK_POSITION" if regular_items > 0 else result["reason"]
	return result
