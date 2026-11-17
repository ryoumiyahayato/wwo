extends RefCounted
## Candidate adopted, native verification pending. Finite same-site one-active-recipe minimum batch.
## All choices are conditional on original future labor, material and transport.
## No atomic synthetic order, bank, reservation or production is created here.

static func protected_quantity(e: RefCounted, site: String, good: String) -> int:
	var q: int = e._service_market.materials_needed(site, good) + e._internal_request_pressure(site, good) + e._capital.goods_needed(site, good)
	for c: Dictionary in e._supply.records.values():
		if c["supplier_site"] == site and c["good"] == good and int(c["ended_minute"]) < 0:
			q += maxi(0, int(c["quantity"]) - int(c["allocated"]))
	return q

static func choices(e: RefCounted, site: String, good: String, date: int, quantity: int) -> Array:
	var firm: String = e._owner(site)
	var currency: String = e._sale_currency(firm)
	var result: Array = []
	for o: Dictionary in e._input_offers(site, good, date, quantity, e._input_need(site, good)):
		if o["denomination"] != currency or o["observed_arrival_day"] == null or int(o["observed_arrival_day"]) > date or int(o["transport_quantity"]) < quantity or e._input_offer_batch_size(o) < quantity: continue
		if e._purchase_limit(firm, good, currency, int(o["price"])) < int(o["price"]): continue
		var row: Dictionary = o.duplicate(true)
		row["kind"] = "SALE"; row["source_site"] = o["seller_site"]; row["unit_cash"] = int(o["price"]) + int(o["freight_per_unit"])
		result.append(row)
	for source: String in e._spec["firms"][firm]["sites"]:
		if source == site or not e._site_reports.has(source) or e._reported_surplus(source, good) < quantity: continue
		for path: Dictionary in e._paths_for(firm, e._place(source), e._place(site), e.day):
			var legs: Array = e._locked_legs(path, currency)
			var row := {"route_legs": legs}
			var eta: Variant = e._input_offer_arrival(row)
			if eta == null or int(eta) > date or e._route_available(path) < quantity or e._input_offer_batch_size(row) < quantity: continue
			row.merge({"kind": "INTERNAL", "good": good, "source_site": source, "seller_site": source, "seller": firm, "route_id": path["id"], "denomination": currency, "price": 0, "freight_per_unit": e._freight(legs), "unit_cash": e._freight(legs), "observed_arrival_day": eta, "transport_quantity": mini(e._reported_surplus(source, good), e._route_available(path))})
			result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["unit_cash"] != b["unit_cash"]: return int(a["unit_cash"]) < int(b["unit_cash"])
		if a["observed_arrival_day"] != b["observed_arrival_day"]: return int(a["observed_arrival_day"]) < int(b["observed_arrival_day"])
		return str(a["source_site"]) + str(a["route_id"]) < str(b["source_site"]) + str(b["route_id"]))
	return result

static func labor(e: RefCounted, site: String, hours: int) -> Dictionary:
	var available: int = 0
	var max_rate: int = 0
	var currency: String = e._sale_currency(e._owner(site))
	for actor: String in e._contracts:
		for c: Dictionary in e._contract_rows(e._contracts[actor]):
			var job: Dictionary = e._labor_market.contract_job(c)
			if job["site_id"] != site or job["employer"] != e._owner(site) or not e._at_place(actor, job["place"]): continue
			if c.get("denomination", currency) != currency: continue
			available += int(job["hours"]) * e._workable_workers(actor, c)
			max_rate = maxi(max_rate, int(job["wage_per_hour"]))
	return {"available_hours": available, "required_hours": hours, "new_work_cash_bound": hours * max_rate, "possible": available >= hours, "basis": "CURRENT_ACCEPTED_PRESENT_WORKERS_NOT_VACANT_POSTINGS_NOT_GUARANTEED_FUTURE_WORK"}

static func joint_ready(e: RefCounted, site: String, selections: Dictionary) -> Dictionary:
	var firm: String = e._owner(site)
	var currency: String = e._sale_currency(firm)
	var cash: int = 0
	var edges: Dictionary = {}; var nodes: Dictionary = {}; var budgets: Dictionary = {}
	for good: String in selections:
		var selected: Dictionary = selections[good]
		var q: int = int(selected["selected_quantity"])
		cash += q * int(selected["unit_cash"])
		var parts: Array[Dictionary] = e._budget_plan(firm, currency, good, selected["route_legs"], q, selected["kind"] == "SALE", int(selected["price"]))
		if not e._budget_ready(parts): return {"ok": false, "reason": "ORIGINAL_COMPONENT_BUDGET", "cash": cash}
		for p: Dictionary in parts:
			if not p.has("rule_id"): continue
			var id: String = p["rule_id"]
			budgets[id] = int(budgets.get(id, 0)) + int(p["amount"])
			if int(e._budgets._used.get(id, 0)) + int(budgets[id]) > int(e._budgets.rule(id)["limit"]): return {"ok": false, "reason": "ORIGINAL_SHARED_BUDGET_WINDOW", "cash": cash}
		var first: String = selected["route_legs"][0]["edge_id"]
		var internal: bool = selected["kind"] == "INTERNAL"
		var target: String = e._all_routes()[first]["carrier"] if internal else selected["seller"]
		var place: String = e._place(selected["source_site"]) if internal else e._place(site)
		var category: String = "freight:" + first if internal else "goods:" + good
		var permission: Dictionary = e._procurement_permission(firm, firm, {}, true, parts, target, place, category, q * int(selected["unit_cash"]))
		if not permission["ok"]: return {"ok": false, "reason": "ORIGINAL_PROCUREMENT_AUTHORITY", "cash": cash}
		var origin: String = e._all_routes()[first]["from_place_id"]
		edges[first] = int(edges.get(first, 0)) + q
		nodes[origin] = int(nodes.get(origin, 0)) + q
		if int(edges[first]) > maxi(0, int(e._edge(first)["capacity"]) - int(e._edge(first)["input_used"])) or int(nodes[origin]) > e._node_capacity(origin): return {"ok": false, "reason": "SHARED_FIRST_DISPATCH_CAPACITY", "cash": cash}
	return {"ok": true, "cash": cash, "shared_budget_amounts": budgets, "first_edge_quantities": edges, "first_node_quantities": nodes}

static func position(e: RefCounted, site: String) -> Dictionary:
	var out := {"applicable": false, "supported": true, "reason": "NO_MULTI_MATERIAL_FUTURE_BATCH", "selected": {}, "basis": "FINITE_MINIMUM_COMPLETE_BATCH_NOT_GLOBAL_OPTIMUM"}
	var active: Array = []
	var plans: Dictionary = e._plans.get(site, {}).get("activities", {})
	for id: String in e._production_order(site):
		if not plans.has(id) or not e._site_state[site]["activities"][id]["enabled"]: continue
		var future: int = 0
		for row: Dictionary in plans[id]["schedule"]:
			if int(row["day"]) > int(e.day): future += int(row["quantity"])
		if future > 0: active.append(id)
	if active.is_empty(): return out
	if active.size() != 1:
		out.merge({"supported": false, "reason": "MULTI_ACTIVITY_SHARED_MATERIAL_NETWORK_RETAINS_ORIGINAL_RULE"}, true); return out
	var activity: Dictionary = e._activity(site, active[0])
	var materials: Array = []
	for good: String in e._goods:
		if int(activity["materials"][good]) > 0: materials.append(good)
	if materials.size() < 2: return out
	var firm: String = e._owner(site)
	if not e._input_need(site, materials[0]).get("npc_timing_adoption", false): return out
	out.merge({"applicable": true, "activity_id": active[0], "materials": materials, "reason": "WAIT_COMPLETE_FIRST_FEASIBLE_FUTURE_BATCH"}, true)
	var labor_view: Dictionary = labor(e, site, int(activity["hours"]))
	out["labor"] = labor_view
	if not labor_view["possible"]: out["reason"] = "NO_CURRENT_ACCEPTED_WORK_CAPACITY"; return out
	var cash_view: Dictionary = e._procurement_cash_position(firm, e._sale_currency(firm))
	out["cash_position"] = cash_view
	for scheduled: Dictionary in plans[active[0]]["schedule"]:
		var date: int = int(scheduled["day"])
		if date <= int(e.day) or int(scheduled["quantity"]) <= 0: continue
		if e._capital.capacity(site, date * 1440, active[0]) < int(activity["capacity_units"]): continue
		var selected: Dictionary = {}; var any_missing: bool = false; var unavailable: bool = false
		for good: String in materials:
			var need: Dictionary = e._input_need(site, good)
			var covered: int = 0
			for req: Dictionary in need["timing_projection"]["requirements"]:
				if req["purpose"] == "PLANNED_PRODUCTION" and int(req["day"]) == date: covered += int(req["possible_covered"])
			var missing: int = maxi(0, int(activity["materials"][good]) - covered)
			if missing <= 0: continue
			any_missing = true
			var known: Array = choices(e, site, good, date, missing)
			if known.is_empty(): unavailable = true; break
			selected[good] = known[0].duplicate(true); selected[good]["selected_quantity"] = missing
		if not any_missing: continue
		if unavailable: continue
		var joint: Dictionary = joint_ready(e, site, selected)
		var total: int = int(joint.get("cash", 0)) + int(labor_view["new_work_cash_bound"])
		if not joint["ok"] or total > int(cash_view["spendable"]): out["reason"] = joint.get("reason", "COMPLETE_BATCH_CASH_AND_NEW_WORK_BOUND"); continue
		out.merge({"selected": selected, "need_by_day": date, "joint": joint, "conditional_new_work_cash": labor_view["new_work_cash_bound"], "reason": "ONE_OBTAINABLE_COMPLETE_BATCH_BEFORE_EXCESS_FIRST_INPUT"}, true)
		# Keep normal larger replenishment where the whole currently selected
		# input window fits original cash/authority/budgets and current sources.
		var full: Dictionary = {}
		var full_known: bool = true
		var future_batches: int = 0
		for entry: Dictionary in plans[active[0]]["schedule"]:
			if int(entry["day"]) > int(e.day): future_batches += int(entry["quantity"])
		for good: String in materials:
			var future_quantity: int = int(e._input_need(site, good)["timing_projection"]["uncovered_future_quantity"])
			if future_quantity <= 0: continue
			var options: Array = choices(e, site, good, date, future_quantity)
			if options.is_empty(): full_known = false; break
			full[good] = options[0].duplicate(true); full[good]["selected_quantity"] = future_quantity
		if full_known and not full.is_empty():
			var all_ready: Dictionary = joint_ready(e, site, full)
			if all_ready["ok"] and int(all_ready["cash"]) + future_batches * int(labor_view["new_work_cash_bound"]) <= int(cash_view["spendable"]): out["applicable"] = false; out["reason"] = "FULL_CURRENT_INPUT_WINDOW_FITS_RETAIN_ORIGINAL_RULE"
		return out
	return out
