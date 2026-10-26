extends RefCounted
## Projection only. The host authenticates actor; supplied IDs grant no rights.
const FORMAT: String = "economy_read_v1"
const Process = preload("res://scripts/world/economy_production_process.gd")

## Shared external projection for personal, managed-firm and read-contract views.
## actor is the actual observer, never the enterprise's configured place.
static func order_view(e: RefCounted, actor: String, order: Dictionary) -> Dictionary:
	var row: Dictionary = e._order_view(order)
	var known: Dictionary = e._cargo_fulfilment.visible(actor, order["id"])
	row["cargo_fulfilment"] = known
	# Redaction must not depend on whether an unseen loss actually exists.
	# One received notice never unlocks subsequent remote physical outcomes.
	row["unresolved_loss_quantity"] = null
	row["physical_tracking"] = "LOCAL_OBSERVATION_AND_RECEIVED_LOSS_RECORDS_ONLY"
	var known_unresolved: int = 0
	for loss: Dictionary in known.get("losses", []):
		if loss["status"] == "ADOPTED": known_unresolved += maxi(0, int(loss["quantity"]) - int(loss["resolved"]))
	row["known_unresolved_loss_quantity"] = known_unresolved
	if actor != order["buyer"]: row.erase("travel_quote")
	if not e._at_place(actor, str(row["to_place_id"])):
		row["collectable_quantity"] = null
		row["can_collect"] = false
		row["can_collect_to_storage"] = false
	for cargo: Dictionary in row["shipments"]:
		if cargo.get("stage") == "TRANSIT" or not e._at_place(actor, str(cargo.get("place_id", ""))):
			cargo["physical_quantity"] = null
			cargo["unresolved_loss_quantity"] = null
			cargo["collectable_quantity"] = null
			cargo["physical_tracking"] = "AWAITING_LOCAL_OBSERVATION_OR_SPECIFIC_NOTICE"
	return row

static func own(e: RefCounted, actor: String, firm: String, site: String) -> Dictionary:
	if not e._spec.firms.has(firm) or not e._manager(actor, firm) or not e._spec.sites.has(site) or e._owner(site) != firm: return {}
	var now: int = e._world.game_clock.total_minutes()
	var activities: Array[Dictionary] = []
	for activity: Dictionary in e._spec.sites[site].activities:
		var state: Dictionary = e._site_state[site].activities[activity.id]
		var plan: Dictionary = e._plans.get(site, {}).get("activities", {}).get(activity.id, {})
		var actual: int = int(plan.get("actual", 0))
		var inputs: Dictionary = {}
		var outputs: Dictionary = {}
		var rejects: Dictionary = {}
		for good: String in activity.materials: inputs[good] = actual * int(activity.materials[good])
		for good: String in activity.outputs:
			outputs[good] = actual * int(activity.outputs[good])
			rejects[good] = actual * int(activity.get("process", {}).get("rejects", {}).get(good, 0))
		var reason: String = Process.reason(activity, e.day, int(state.batches))
		var planned: int = int(plan.get("schedule", [{"quantity": 0}])[0].quantity)
		var capacity: int = e._capital.capacity(site, e._production_minute(), activity.id)
		var constraints: Array[String] = []
		if reason not in ["ELIGIBLE", "LEGACY_UNSPECIFIED"]: constraints.append(reason)
		if planned > actual:
			if int(e._labor.get(site, 0)) < planned * int(activity.hours): constraints.append("LABOR_HOURS_BOUND")
			if capacity < planned * int(activity.capacity_units): constraints.append("CAPACITY_BOUND")
			# End-of-day stock is an observation, not reconstructed start stock.
			for good: String in activity.materials:
				if int(activity.materials[good]) > 0 and int(e._stocks[site][good]) < int(activity.materials[good]): constraints.append("CURRENT_MATERIAL_SHORTAGE:" + good)
		activities.append({"id": activity.id, "recipe": activity.duplicate(true), "process_status": reason, "planned_batches": planned, "actual_batches": actual, "cumulative_batches": state.batches, "actual_inputs": inputs, "actual_outputs": outputs, "declared_non_saleable_rejects": rejects, "allocated_person_hours": actual * int(activity.hours), "capacity_available_units": capacity, "capacity_used_units": actual * int(activity.capacity_units), "capacity_utilization": float(actual * int(activity.capacity_units)) / capacity if capacity > 0 else null, "observed_constraints": constraints})
	var orders: Array[Dictionary] = []
	var prices: Array[Dictionary] = []
	var decisions: Array[Dictionary] = []
	var wages: Array[Dictionary] = []
	for order: Dictionary in e._orders.values():
		if order.buyer != firm and order.seller != firm: continue
		orders.append(order_view(e, actor, order))
		if orders.size() > 8: orders.pop_front()
	for receipt: Dictionary in e._delivery_receipts.values():
		var order: Dictionary = e._orders[receipt.order_id]
		if order.buyer != firm and order.seller != firm: continue
		prices.append({"order_id": order.id, "receipt_id": receipt.id, "good": order.good, "price": order.price, "quantity": receipt.quantity, "denomination": order.denomination, "delivered_minute": receipt.delivered_minute})
		if prices.size() > 8: prices.pop_front()
	for command: Dictionary in e._commands.values():
		var who: String = str(command.get("envelope", {}).get("actor", {}).get("id", "")) if command.get("envelope", {}).get("actor") is Dictionary else str(command.get("envelope", {}).get("actor", ""))
		if who != firm: continue
		decisions.append({"action_id": command.get("envelope", {}).get("command", {}).get("action_id", ""), "result": command.result.duplicate(true)})
		if decisions.size() > 8: decisions.pop_front()
	for wage: Dictionary in e._wages.values():
		if wage.employer != firm: continue
		wages.append(wage.duplicate(true))
		if wages.size() > 8: wages.pop_front()
	var quotes: Array[Dictionary] = []
	for good: String in e._spec.sites[site].prices:
		quotes.append({"site_id": site, "good": good, "price": e._price(site, good), "denomination": e._sale_currency(firm), "policy": e._price_policy(site, good).duplicate(true), "state": e._quote_state.get(site + "|" + good, {}).duplicate(true), "published_quote": e._local_quotes.current(site, good).duplicate(true), "basis": "OWN_POSTED_TERMS_NOT_ACCEPTED_TRADE"})
	var inventory_status: Dictionary = {}
	for good: String in e._goods:
		var reserved: int = e._committed(site, good)
		var incoming_transit: int = 0
		var outgoing_transit: int = 0
		var delivered_in: int = 0
		var delivered_out: int = 0
		for order: Dictionary in e._orders.values():
			if order.good != good: continue
			if order.buyer == firm and order.buyer_site == site:
				incoming_transit += int(order.transit)
				delivered_in += int(order.delivered)
			if order.seller == firm and order.seller_site == site:
				outgoing_transit += int(order.transit)
				delivered_out += int(order.delivered)
		inventory_status[good] = {"at_site_quantity": e._stocks[site][good], "reserved_at_site_quantity": reserved, "unreserved_at_site_quantity": maxi(0, int(e._stocks[site][good]) - reserved), "incoming_accepted_quantity": e._incoming_by_key.get(site + "|" + good, 0), "incoming_order_transit_quantity": incoming_transit, "outgoing_order_transit_quantity": outgoing_transit, "cumulative_delivered_in": delivered_in, "cumulative_delivered_out": delivered_out, "basis": "FORMAL_LOTS_RESERVATIONS_AND_CONTRACT_STATUS_NOT_UNCONFIRMED_REMOTE_CARGO_PHYSICS"}
	var payments: Array = e._world.ledger_state.own_transactions(firm)
	if payments.size() > 8: payments = payments.slice(payments.size() - 8)
	return {"format": FORMAT, "minute": now, "day": e.day, "observer": actor, "visibility": "AUTHORIZED_CURRENT_MANAGER_OWN_BUSINESS", "firm_id": firm, "site_id": site, "place_id": e._place(site), "configuration_source": {"case_id": e.config.case_id, "identity_basis": e._business_identity_basis(firm), "recipe_source": "EconomySliceConfig normalized activities; process.source or LEGACY_UNSPECIFIED"}, "units": {"goods": e._good_units().duplicate(true), "labor": "person_hour", "time": "host_game_minute", "currency": "denomination-tagged integer minor units", "capacity": "capacity_unit_per_eligible_day"}, "activities": activities, "physical_totals": e._physical_totals[site].duplicate(true), "inventory": e._inventory_view(site).duplicate(true), "inventory_status": inventory_status, "finance": e._firm_finance_view(firm).duplicate(true), "wage_claims_latest8": wages, "seller_quotes": quotes, "actual_trade_prices_latest8": prices, "orders_latest8": orders, "payments_latest8": payments, "npc_results_latest8": decisions, "truncation": "Latest 8 records per history; aggregates retain source windows", "excluded_internal_state": ["OTHER_FIRMS_PRIVATE_STOCK_CASH_PLANS", "UNRECEIVED_SUPPLIER_INFORMATION", "MACRO_ESTIMATED_FLOW_AND_PRICE", "UNCONFIRMED_CARGO_OUTCOME"]}
