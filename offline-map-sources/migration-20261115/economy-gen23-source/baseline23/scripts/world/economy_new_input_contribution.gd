extends RefCounted
## dot candidate. A finite avoidable-new-cash check, never historical cost
## accounting, net profit, guaranteed sale proceeds or a joint-output valuation.
static func observe(e: RefCounted, site: String, id: String) -> Dictionary:
	var result := {"applicable": false, "decline_optional_batch": false, "reason": "UNKNOWN_OR_PROTECTED_RETAIN_ORIGINAL_PLAN", "known_new_material_cash_lower_bound": null, "quoted_output_receipt_not_guaranteed": null, "historical_material_cost": null, "other_costs": null, "basis": "FINITE_AVOIDABLE_NEW_INPUT_CASH_NOT_NET_PROFIT", "sources": []}
	var activity: Dictionary = e._activity(site, id)
	if activity.is_empty() or activity["outputs"].size() != 1:
		result["reason"] = "JOINT_OUTPUT_ALLOCATION_UNKNOWN_RETAIN_ORIGINAL_PLAN"; return result
	var output: String = activity["outputs"].keys()[0]
	var firm: String = e._owner(site)
	if e.firm_manager_at(firm, e._world.game_clock.total_minutes()) != firm and not e._assets.corporate.can_plan(firm):
		result["reason"] = "ORIGINAL_MANAGER_AUTHORITY_RETAINS_PRODUCTION_PLAN"; return result
	var currency: String = e._sale_currency(firm)
	if e._committed(site, output) > 0 or e._internal_request_pressure(site, output) > 0 or e._capital.goods_needed(site, output) > 0 or e._service_market.materials_needed(site, output) > 0:
		result["reason"] = "ORIGINAL_ACCEPTED_OR_OPERATING_OUTPUT_RESPONSIBILITY"; return result
	for c: Dictionary in e._supply.records.values():
		if c["supplier_site"] == site and c["good"] == output and int(c["ended_minute"]) < 0 and int(c["quantity"]) > int(c["allocated"]):
			result["reason"] = "ORIGINAL_UNALLOCATED_PARENT_SUPPLY_RESPONSIBILITY"; return result
	for own: String in e._spec["firms"][firm]["sites"]:
		for other: Dictionary in e._spec["sites"][own]["activities"]:
			if int(other["materials"].get(output, 0)) > 0:
				result["reason"] = "OWN_DOWNSTREAM_RECIPE_RETAINS_ORIGINAL_TOPOLOGY"; return result
	if not e._site_selling(site) or e._local_quotes.sales_paused(site, output) or not e._spec["sites"][site]["prices"].has(output):
		result["reason"] = "NO_USABLE_OUTPUT_QUOTE"; return result
	var quotation: Dictionary = e._local_quotes.current(site, output)
	if not e._local_quotes.rule(site, output).is_empty() and (quotation.is_empty() or e._world.game_clock.total_minutes() >= int(quotation["expires_day"]) * 1440):
		result["reason"] = "NO_USABLE_OUTPUT_QUOTE"; return result
	var receipt: int = e._price(site, output) * int(activity["outputs"][output])
	if receipt <= 0: return result
	var lower: int = 0
	var material_count: int = 0
	var last_day: int = int(e.day) + int(e._operations_policy(site)["planning_horizon"]) - 1
	for good: String in e._goods:
		var coefficient: int = int(activity["materials"][good])
		if coefficient <= 0: continue
		material_count += 1
		if e._exposure(site, good) > 0:
			result["reason"] = "EXISTING_MATERIAL_OR_ACCEPTED_INPUT_IS_NOT_NEW_AVOIDABLE_PURCHASE"; return result
		for own: String in e._spec["firms"][firm]["sites"]:
			if own != site and e._site_reports.has(own) and e._reported_surplus(own, good) > 0:
				result["reason"] = "OWN_TRANSFER_ALTERNATIVE_HAS_UNKNOWN_ORIGINAL_COST"; return result
		var chosen: Dictionary = {}
		for offer: Dictionary in e._offers(firm, site, good):
			if offer["good"] != good or typeof(offer.get("price")) != TYPE_INT or typeof(offer.get("freight_per_unit")) != TYPE_INT or int(offer["transport_quantity"]) < coefficient: continue
			var eta: Variant = e._input_offer_arrival(offer)
			if eta == null or int(eta) > last_day or e._input_offer_batch_size(offer) < coefficient: continue
			if offer["denomination"] != currency:
				result["reason"] = "KNOWN_ALTERNATIVE_CURRENCY_NOT_SILENTLY_CONVERTED"; return result
			if e._purchase_limit(firm, good, currency, int(offer["price"])) < int(offer["price"]): continue
			var cash: int = coefficient * (int(offer["price"]) + int(offer["freight_per_unit"]))
			if chosen.is_empty() or cash < int(chosen["cash"]): chosen = {"good": good, "quantity": coefficient, "cash": cash, "currency": currency, "supplier_site": offer["seller_site"], "quote_id": offer["quote_id"], "route_id": offer["route_id"], "unit_price": offer["price"], "unit_freight": offer["freight_per_unit"], "arrival_lower_bound_day": eta, "eta_guaranteed": false}
		if chosen.is_empty():
			result["reason"] = "NO_COMPLETE_KNOWN_NEW_INPUT_CASH_BOUND"; return result
		lower += int(chosen["cash"])
		result["sources"].append(chosen)
	if material_count == 0: return result
	result.merge({"applicable": true, "decline_optional_batch": lower > receipt, "known_new_material_cash_lower_bound": lower, "quoted_output_receipt_not_guaranteed": receipt, "reason": "NEW_MATERIAL_CASH_ALONE_EXCEEDS_CURRENT_OUTPUT_QUOTE" if lower > receipt else "KNOWN_CASH_LOWER_BOUND_DOES_NOT_ESTABLISH_A_LOSS", "wages_and_other_costs": "UNKNOWN_OR_SEPARATELY_SOURCED_NOT_ZERO"}, true)
	return result
