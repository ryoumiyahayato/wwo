extends SceneTree
## Bounded domain integration, using the existing FormalTestCase/WorldBootstrap/
## FormalPersistence entries. No export, external evidence runner or player save.

const Opening = preload("res://scripts/content/economy_network_development.gd")
const DAYS: int = 24
var test := FormalTestCase.new()

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var saved_index := arguments.find("--saved-file")
	if saved_index >= 0:
		_read_saved_file.call_deferred(arguments[saved_index + 1] if saved_index + 1 < arguments.size() else "")
	elif arguments.has("--read-contract-only"):
		_read_contract_only.call_deferred()
	else:
		_run.call_deferred()

func _cash_total(world: WorldState) -> int:
	var total: int = 0
	for account: Dictionary in world.ledger_state.snapshot()["accounts"]: total += int(account["balance"])
	return total

func _physical_valid(economy: EconomyR1Slice) -> bool:
	var formed: Dictionary = Opening.stock()
	var accounted: Dictionary = Opening.stock()
	for source: Dictionary in economy._lots.sources.values(): formed[source["good"]] = int(formed[source["good"]]) + int(source["quantity"])
	for portion: Dictionary in economy._lots.portions.values(): accounted[portion["good"]] = int(accounted[portion["good"]]) + int(portion["remaining"]) + int(portion["consumed"]) + int(portion["lost"])
	if formed != accounted: return false
	for site: String in economy._site_ids():
		for good: String in economy._goods:
			if int(economy._stocks[site][good]) < 0: return false
	return true

func _production_totals_valid(economy: EconomyR1Slice) -> bool:
	for site: String in economy._site_ids():
		var made: Dictionary = Opening.stock()
		var used: Dictionary = Opening.stock()
		for source: Dictionary in economy._lots.sources.values():
			if not str(source["id"]).begins_with("production:") or not str(source["id"]).contains(":" + site + ":"): continue
			made[source["good"]] = int(made[source["good"]]) + int(source["quantity"])
			# This scenario has one saleable output per activity, so each consumed
			# input receipt is counted exactly once, never across unlike units.
			for input: Dictionary in source["inputs"]:
				var good: String = economy._lots.sources[input["source_id"]]["good"]
				used[good] = int(used[good]) + int(input["quantity"])
		if made != economy._physical_totals[site]["produced"] or used != economy._physical_totals[site]["used"]: return false
	return true

func _delivered(economy: EconomyR1Slice, multileg: bool = false, cross_border: bool = false) -> Dictionary:
	var result: Dictionary = Opening.stock()
	for order: Dictionary in economy._orders.values():
		if multileg and order["route_legs"].size() < 2: continue
		if cross_border:
			var crosses: bool = false
			for leg: Dictionary in order["route_legs"]:
				if leg["edge_id"] == Opening.CHANNEL_EDGE: crosses = true
			if not crosses: continue
		result[order["good"]] = int(result[order["good"]]) + int(order["delivered"])
	return result

func _has_quantity(goods: Dictionary) -> bool:
	for good: String in goods:
		if int(goods[good]) > 0: return true
	return false

func _produced(economy: EconomyR1Slice, site: String, good: String) -> int:
	return int(economy._physical_totals[site]["produced"][good])

func _unmet(economy: EconomyR1Slice) -> int:
	var total: int = 0
	for actor: String in economy._actor_ids():
		for category: Dictionary in economy._totals[actor]["categories"].values(): total += int(category["unmet"])
	return total

func _order_read_sample(economy: EconomyR1Slice, orders: Array) -> Dictionary:
	var remote: int = 0
	var hidden: bool = true
	var canonical: bool = true
	for order: Dictionary in orders:
		hidden = hidden and order["unresolved_loss_quantity"] == null
		var received_unresolved: int = 0
		for loss: Dictionary in order["cargo_fulfilment"].get("losses", []):
			if loss["status"] == "ADOPTED": received_unresolved += maxi(0, int(loss["quantity"]) - int(loss["resolved"]))
		canonical = canonical and order["known_unresolved_loss_quantity"] == received_unresolved
		for cargo: Dictionary in order["shipments"]:
			if cargo.get("stage") != "TRANSIT" and economy._at_place(Opening.PLAYER, str(cargo.get("place_id", ""))): continue
			remote += 1
			hidden = hidden and cargo["physical_quantity"] == null and cargo["unresolved_loss_quantity"] == null and cargo["collectable_quantity"] == null
	return {"remote": remote, "hidden": hidden, "canonical": canonical}

func _remote_read_sample(economy: EconomyR1Slice) -> Dictionary:
	var own: Dictionary = economy.economy_read_view(Opening.PLAYER, "firm:network:grain", "site:network:grain")
	var result := _order_read_sample(economy, own.get("orders_latest8", []))
	var complete: bool = true
	var counts: Dictionary = {}
	# Grain supplies the seller path; the separately authorized mill supplies a
	# real buyer path. An empty sales/orders list cannot pass as a tested read.
	for firm: String in ["firm:network:grain", "firm:network:mill1"]:
		var managed: Dictionary = economy.managed_firm(Opening.PLAYER, firm)
		var queried: Dictionary = LivelihoodAction.query_firm(economy._world, Opening.PLAYER, firm)
		for kind: String in ["orders", "sales_orders"]:
			var direct := _order_read_sample(economy, managed.get(kind, []))
			var external := _order_read_sample(economy, queried.get(kind, []))
			result["hidden"] = result["hidden"] and direct["hidden"] and external["hidden"]
			result["canonical"] = result["canonical"] and direct["canonical"] and external["canonical"]
			if (firm == "firm:network:grain" and kind == "sales_orders") or (firm == "firm:network:mill1" and kind == "orders"):
				complete = complete and int(direct["remote"]) > 0 and int(external["remote"]) > 0
				counts[firm + ":" + kind] = {"managed": direct["remote"], "query_firm": external["remote"]}
	result["complete"] = complete
	result["remote_by_projection"] = counts
	return result

## Short functional branch: one normal fixture, at most three days, then reads
## only. It does not save and does not repeat the 24-day two-case integration.
func _read_contract_only() -> void:
	var built := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, false, Opening.request())
	test.expect(built.success and built.world.economy_r1 != null, "Bounded read fixture uses the actual host opening: " + built.error)
	if not built.success or built.world.economy_r1 == null:
		test.finish(self, "Economic network read contract")
		return
	var exercised: bool = false
	for index: int in 3:
		var step: Dictionary = built.simulation_step.advance_minutes(1440)
		test.expect(step.get("success", true), "Read fixture advances one bounded day")
		var before := built.persistence.snapshot()
		var sample := _remote_read_sample(built.world.economy_r1)
		test.expect(built.persistence.snapshot() == before, "Read-contract, managed_firm and query_firm do not write any world state")
		if int(sample["remote"]) == 0: continue
		exercised = true
		test.expect(sample["complete"], "Real remote buyer and seller orders are covered by both managed_firm and query_firm")
		test.expect(sample["hidden"] and sample["canonical"], "All external buy/sell views keep remote/transit quantities null and use only received loss facts")
		test.expect(LivelihoodAction.query_firm(built.world, Opening.PLAYER, "firm:network:mill2").is_empty(), "An unappointed company is still private through the old query entry")
		print("NETWORK_READ_SAMPLE ", JSON.stringify({"minute": built.world.game_clock.total_minutes(), "sample": sample}))
		break
	test.expect(exercised, "At most three days exercised actual nonempty remote cargo")
	test.finish(self, "Economic network read contract")

## Cold file inspection uses only the existing exact decoder/restore candidate.
## No opening scenario is built here, no file is written and no time is advanced.
func _read_saved_file(path: String) -> void:
	test.expect(not path.is_empty() and path.is_absolute_path(), "Cold-read mode requires the actual absolute GUI save path")
	if path.is_empty() or not path.is_absolute_path():
		test.finish(self, "Economic network saved-file cold read")
		return
	var persistence := FormalPersistence.new()
	var loaded := persistence._read_snapshot_file(path)
	test.expect(loaded.success, "Original save decoder reads the supplied file: " + loaded.error_code + " " + loaded.message)
	if not loaded.success:
		test.finish(self, "Economic network saved-file cold read")
		return
	var restored := persistence.restore_candidate(loaded.snapshot)
	test.expect(restored.success and restored.world.economy_r1 != null, "Original persistence restores the supplied native world: " + restored.error)
	if not restored.success or restored.world.economy_r1 == null:
		test.finish(self, "Economic network saved-file cold read")
		return
	var actual := restored.persistence.snapshot()
	for field: String in ["total_minutes", "minute_remainder", "player", "persons", "ledger", "economy_native", "spatial", "population", "organization"]:
		test.expect(actual.get(field) == loaded.snapshot.get(field), "Cold restore preserves the saved authoritative field: " + field)
	test.expect(actual == loaded.snapshot, "Cold restore matches the exact source snapshot without fingerprint calculation")
	var economy := restored.world.economy_r1
	test.equal(economy.config["case_id"], Opening.CASE_ID, "The supplied GUI save is the explicit economic network scenario")
	test.expect(_physical_valid(economy) and _production_totals_valid(economy), "Saved lots and per-good production/input receipts remain physically consistent")
	_print_saved_summary(restored.world, path)
	_print_cross_border_trace(economy)
	# Keep the check separate from the candidate decoder's own validation: these
	# diagnostic reads must not advance time, settle, allocate cash or write state.
	test.expect(restored.persistence.snapshot() == actual, "Cold summary and trace leave the entire restored world unchanged")
	test.finish(self, "Economic network saved-file cold read")

func _print_saved_summary(world: WorldState, source_path: String) -> void:
	var economy := world.economy_r1
	var ledger := world.ledger_state.snapshot()
	var cash: Dictionary = {}
	var reserved: Dictionary = {}
	for account: Dictionary in ledger["accounts"]:
		var currency: String = account["denomination"]
		cash[currency] = int(cash.get(currency, 0)) + int(account["balance"])
		reserved[currency] = int(reserved.get(currency, 0)) + world.ledger_state.reserved_balance(account["account_id"])
	var formed := Opening.stock()
	var retained := Opening.stock()
	var consumed := Opening.stock()
	var lost := Opening.stock()
	for source: Dictionary in economy._lots.sources.values(): formed[source["good"]] = int(formed[source["good"]]) + int(source["quantity"])
	for portion: Dictionary in economy._lots.portions.values():
		var good: String = portion["good"]
		retained[good] = int(retained[good]) + int(portion["remaining"])
		consumed[good] = int(consumed[good]) + int(portion["consumed"])
		lost[good] = int(lost[good]) + int(portion["lost"])
	print("NETWORK_SAVED_FILE ", JSON.stringify({"source_path": source_path, "source": "ORIGINAL_FORMAL_PERSISTENCE_DECODER_AND_RESTORE_CANDIDATE_READ_ONLY", "clock": world.game_clock.snapshot(), "player": world.player_state.snapshot(), "player_place": world.person_overlay.current_place(world.player_state.player_id()), "case_id": economy.config["case_id"], "instances": {"world": world.get_instance_id(), "clock": world.game_clock.get_instance_id(), "ledger": world.ledger_state.get_instance_id(), "native_economy": economy.get_instance_id(), "stock_lots": economy._lots.get_instance_id()}, "counts": {"firms": economy._firm_ids().size(), "sites": economy._site_ids().size(), "actors": economy._actor_ids().size(), "accounts": ledger["accounts"].size(), "transactions": ledger["transactions"].size(), "sources": economy._lots.sources.size(), "portions": economy._lots.portions.size(), "orders": economy._orders.size(), "live_shipments": economy._shipments.size(), "delivery_receipts": economy._delivery_receipts.size(), "shared_entries": economy._shared.entries.size()}, "cash_by_denomination": cash, "reserved_by_denomination": reserved, "goods_units": economy._good_units(), "formed_by_good": formed, "retained_by_good": retained, "consumed_by_good": consumed, "lost_by_good": lost}))

## One existing delivered cross-border order, not an inferred flow or new report
## store. IDs and records below come from formal lots, receipts, Spatial and Ledger.
func _print_cross_border_trace(economy: EconomyR1Slice) -> bool:
	var selected: Dictionary = {}
	var latest: int = -1
	for receipt: Dictionary in economy._delivery_receipts.values():
		var order: Dictionary = economy._orders[receipt["order_id"]]
		var crosses: bool = false
		for leg: Dictionary in order["route_legs"]:
			if leg["edge_id"] == Opening.CHANNEL_EDGE: crosses = true
		if crosses and int(receipt["delivered_minute"]) >= latest:
			selected = order
			latest = int(receipt["delivered_minute"])
	if selected.is_empty():
		print("NETWORK_ORDER_TRACE UNAVAILABLE_NO_ACTUAL_CROSS_BORDER_DELIVERY minute=", economy._world.game_clock.total_minutes())
		return false
	var receipts: Array[Dictionary] = []
	var receipt_ids: Dictionary = {}
	var shipment_ids: Dictionary = {}
	for receipt: Dictionary in economy._delivery_receipts.values():
		if receipt["order_id"] != selected["id"]: continue
		receipts.append(receipt.duplicate(true))
		receipt_ids[receipt["id"]] = true
		shipment_ids[receipt.get("shipment_id", receipt["id"])] = true
	var portions: Dictionary = {}
	var sources: Dictionary = {}
	for portion: Dictionary in economy._lots.portions.values():
		if not receipt_ids.has(portion["acquisition_id"]): continue
		var current := portion
		while not current.is_empty() and not portions.has(current["id"]):
			portions[current["id"]] = current.duplicate(true)
			sources[current["source_id"]] = economy._lots.sources[current["source_id"]].duplicate(true)
			current = economy._lots.portions.get(current["parent_portion_id"], {})
	var legs: Array[Dictionary] = []
	var edges := economy._all_routes()
	for leg: Dictionary in selected["route_legs"]:
		var edge: Dictionary = edges[leg["edge_id"]]
		legs.append({"locked_leg": leg.duplicate(true), "edge_reference": {"id": edge["id"], "from_place_id": edge["from_place_id"], "to_place_id": edge["to_place_id"], "basis": edge["basis"], "source_link_id": edge.get("source_link_id", ""), "source_permission_id": edge.get("source_permission_id", ""), "capacity_and_delay_basis": "DEVELOPMENT_CONFIGURATION"}})
	var adoptions: Array[Dictionary] = []
	for entry: Dictionary in economy._shared.entries.values():
		if shipment_ids.has(entry["shipment_id"]): adoptions.append({"carrier_entry": entry.duplicate(true), "spatial_adoption": economy._world.spatial_world.capacity_adoption(entry["adoption_id"])})
	var node_uses: Array[Dictionary] = []
	for use: Dictionary in economy._shared.node_uses.values():
		if shipment_ids.has(use["shipment_id"]): node_uses.append(use.duplicate(true))
	var payments: Array[Dictionary] = []
	for transaction: Dictionary in economy._world.ledger_state.transactions():
		if transaction["reference_id"] == selected["id"]: payments.append(transaction)
	print("NETWORK_ORDER_TRACE ", JSON.stringify({"source": "ACTUAL_FORMAL_ORDER_LOT_LINEAGE_DELIVERY_SPATIAL_ADOPTION_AND_LEDGER_NOT_A_MACRO_FLOW", "observed_minute": economy._world.game_clock.total_minutes(), "order_id": selected["id"], "buyer": selected["buyer"], "buyer_site": selected["buyer_site"], "seller": selected["seller"], "seller_site": selected["seller_site"], "good": selected["good"], "unit": economy._good_units()[selected["good"]], "contract_quantity": selected["quantity"], "delivered_quantity": selected["delivered"], "pending_quantity": selected["pending"], "transit_quantity": selected["transit"], "price_minor_per_unit": selected["price"], "denomination": selected["denomination"], "sources": sources, "portion_lineage_history_not_additive_stock": portions, "route_id": selected["route_id"], "route_legs": legs, "shipment_ids": shipment_ids.keys(), "delivery_receipts": receipts, "shared_adoptions": adoptions, "node_uses": node_uses, "ledger_transactions_with_order_reference": payments}))
	return true

func _run() -> void:
	var configuration := Opening.template()
	test.expect(EconomySliceConfig.valid(configuration), "Explicit 20-company configuration satisfies the real contract")
	if not EconomySliceConfig.valid(configuration):
		test.finish(self, "Economic node network integration")
		return
	test.equal(configuration["firms"].size(), 20, "Twenty firms excludes the carrier and worker cohorts")
	test.equal(configuration["development_organizations"].size(), 20, "Twenty explicit formal commercial identity bindings")
	var malformed := configuration.duplicate(true)
	malformed["firms"][4]["sites"][0]["activities"][0]["process"]["gross_outputs"]["flour"] = 0
	test.expect(not EconomySliceConfig.valid(malformed), "Invalid gross/net/reject production contract is rejected")
	var built := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, false, Opening.request())
	test.expect(built.success and built.world.economy_r1 != null, "Host regional selection installs the actual native economy: " + built.error + built.world.native_economy_error)
	if not built.success or built.world.economy_r1 == null:
		test.finish(self, "Economic node network integration")
		return
	var economy := built.world.economy_r1
	var initial := built.persistence.snapshot()
	var broken := FormalPersistence.new().restore_candidate(initial)
	test.expect(broken.success and broken.world.economy_r1 != null, "Closed-network case restores the identical initial formal world: " + broken.error)
	if not broken.success or broken.world.economy_r1 == null:
		test.finish(self, "Economic node network integration")
		return
	var interrupted := broken.world.economy_r1
	test.equal(interrupted.snapshot(), economy.snapshot(), "Normal and interrupted cases start with identical contracts, inventory and orders")
	test.equal(broken.world.ledger_state.snapshot(), built.world.ledger_state.snapshot(), "Normal and interrupted cases start with identical cash")
	var accounts: Dictionary = {}
	var organizations: Dictionary = {}
	for firm: String in economy._firm_ids():
		var account: String = economy._account(firm)
		var organization: String = economy._spec["firms"][firm]["host_organization_id"]
		test.expect(not accounts.has(account) and built.world.ledger_state.account(account)["owner_id"] == firm, "Independent formal company account: " + firm)
		test.expect(not organizations.has(organization) and built.world.organization_state.is_organization_active(organization), "Active distinct formal commercial organization: " + firm)
		accounts[account] = true
		organizations[organization] = true
	test.equal(built.world.population_state.unit_for_place("place:port_london"), "british_isles_1900", "London port uses the bounded host population crosswalk")
	test.equal(economy._account(Opening.PLAYER), FormalPersonalEconomyState.personal_account_id(Opening.PLAYER), "Player retains the original personal account, not a development duplicate")
	var before_read := economy.snapshot()
	test.expect(economy.economy_read_view(Opening.PLAYER, "firm:network:mill2", "site:network:mill2").is_empty(), "Public directory and routes never grant another company's private accounts")
	test.expect(not economy.economy_read_view(Opening.PLAYER, "firm:network:mill1", "site:network:mill1").is_empty(), "Real opening appointment permits the player's managed mill, not all twenty companies")
	test.equal(economy.snapshot(), before_read, "Read projection does not change authoritative state")
	for sample: EconomyR1Slice in [economy, interrupted]:
		var denial: Dictionary = sample.submit(Opening.PLAYER, {"action_id": "network_test:unauthorized_purchase", "minute": 0, "kind": "buy", "payload": {"firm": "firm:network:mill2"}})
		test.expect(not denial.get("accepted", false) and denial.get("reason") == "NOT_PROCUREMENT_MANAGER", "Published identity cannot authorize spending another firm's cash")
	var closure: Dictionary = interrupted.submit_internal(Opening.NETWORK_OPERATOR, interrupted._auto_command(Opening.NETWORK_OPERATOR, "set_edge_capacity", {"edge_id": Opening.CLOSURE_EDGE, "capacity": 0}, "network_integration_closure"))
	test.expect(closure.get("accepted", false), "Existing authorized command closes the development city/port access edge, not Spatial-owned capacity")
	var total_cash := _cash_total(built.world)
	var physical_ok: bool = true
	var cash_ok: bool = true
	var steps_ok: bool = true
	var normal_advance_us: int = 0
	var broken_advance_us: int = 0
	var maximum_advance_us: int = 0
	var remote_read_checked: bool = false
	for index: int in DAYS:
		var start: int = Time.get_ticks_usec()
		var normal_step: Dictionary = built.simulation_step.advance_minutes(1440)
		var duration: int = Time.get_ticks_usec() - start
		normal_advance_us += duration
		maximum_advance_us = maxi(maximum_advance_us, duration)
		start = Time.get_ticks_usec()
		var broken_step: Dictionary = broken.simulation_step.advance_minutes(1440)
		duration = Time.get_ticks_usec() - start
		broken_advance_us += duration
		maximum_advance_us = maxi(maximum_advance_us, duration)
		steps_ok = steps_ok and bool(normal_step.get("success", true)) and bool(broken_step.get("success", true))
		physical_ok = physical_ok and _physical_valid(economy) and _physical_valid(interrupted)
		cash_ok = cash_ok and _cash_total(built.world) == total_cash and _cash_total(broken.world) == total_cash
		if not remote_read_checked:
			var unchanged := economy.snapshot()
			var sample := _remote_read_sample(economy)
			if int(sample["remote"]) > 0:
				test.expect(sample["hidden"] and sample["canonical"], "Actual remote cargo remains unknown in read-contract, managed_firm and query_firm buy/sell views")
				test.expect(sample["complete"], "Managed and external query buy/sell paths both contain real remote cargo: " + JSON.stringify(sample["remote_by_projection"]))
				test.equal(economy.snapshot(), unchanged, "Read-contract and existing map-facing buy/sell projections have no authoritative writes")
				remote_read_checked = true
		if not steps_ok: break
	test.expect(remote_read_checked, "The bounded run exercises an actual remote-cargo read, not an empty projection")
	test.expect(steps_ok, "Both existing simulation steps complete the bounded 24-day comparison")
	test.expect(physical_ok, "All original lot sources equal retained, consumed and lost portions; stocks remain nonnegative")
	test.expect(cash_ok, "Both cases conserve all formal cash without top-ups")
	for job: String in ["job:network:handling:le_havre_port", "job:network:handling:london_port"]:
		test.equal(economy._job_postings[job], economy._initial_job_postings()[job], "Fixed paid port posting stays unchanged by a production toggle or transient cargo demand: " + job)
		test.equal(interrupted._job_postings[job], interrupted._initial_job_postings()[job], "Disconnected port keeps its bounded fixed paid posting: " + job)
	for name: String in ["grain", "fiber", "coal", "ore"]:
		var good := "iron_ore" if name == "ore" else name
		test.equal(_produced(economy, "site:network:" + name, good), 0, "Unavailable natural-resource process creates no free material: " + name)
	test.expect(_produced(economy, "site:network:mill1", "flour") > 0 and _produced(economy, "site:network:bakery1", "bread") > 0, "Domestic autonomous firms purchase inputs and execute the processing chain")
	test.expect(_produced(economy, "site:network:mill2", "flour") > 0 and _produced(economy, "site:network:bakery2", "bread") > 0, "Actual cross-border material delivery supports overseas NPC production")
	test.expect(_has_quantity(_delivered(economy)) and _has_quantity(_delivered(economy, true)) and _has_quantity(_delivered(economy, false, true)), "Local, multi-leg and Channel orders physically deliver, with quantities kept by good")
	test.expect(_production_totals_valid(economy) and _production_totals_valid(interrupted), "Per-good physical production/input totals match the actual production lot receipts")
	var shared_channel: bool = false
	var actual_handling_hours: int = 0
	for entry: Dictionary in economy._shared.entries.values():
		if entry["edge_id"] == Opening.CHANNEL_EDGE: shared_channel = true
		actual_handling_hours += int(entry["handling_hours"])
	test.expect(shared_channel and actual_handling_hours > 0 and not economy._shared.node_uses.is_empty(), "Channel cargo actually adopts Spatial capacity, finite vessel payload, paid handling work and node occupancy")
	var local_delivery: bool = false
	var city_delivery: bool = false
	var paid_wages: int = 0
	var consumed_bread: int = 0
	for order: Dictionary in economy._orders.values():
		if int(order["delivered"]) <= 0: continue
		if economy._place(order["seller_site"]) == economy._place(order["buyer_site"] if not str(order["buyer_site"]).is_empty() else order["buyer"]): local_delivery = true
		for leg: Dictionary in order["route_legs"]:
			if leg["edge_id"] in ["edge:network:lyon:paris", "edge:network:paris:lyon"]: city_delivery = true
	for wage: Dictionary in economy._wages.values(): paid_wages += int(wage["amount"]) - int(wage["remaining"])
	for actor: String in economy._actor_ids():
		for category: Dictionary in economy._totals[actor]["categories"].values(): consumed_bread += int(category["used_items"].get("bread", 0))
	test.expect(local_delivery and city_delivery and paid_wages > 0 and consumed_bread > 0, "The running NPC network includes local/city trade, paid wages and real bread consumption")
	test.equal(_delivered(interrupted, false, true), Opening.stock(), "Closed port access cannot be bypassed by an invented route")
	test.equal(_produced(interrupted, "site:network:mill2", "flour"), 0, "Overseas mill cannot produce without blocked finite grain")
	test.expect(_produced(interrupted, "site:network:bakery1", "bread") > 0 and _unmet(interrupted) > 0, "Domestic firms continue while disconnected consumers retain actual unmet needs")
	print("NETWORK_SUMMARY days=", DAYS, " firms=", economy._firm_ids().size(), " delivered_by_good=", _delivered(economy), " multileg_by_good=", _delivered(economy, true), " cross_border_by_good=", _delivered(economy, false, true), " blocked_cross_border_by_good=", _delivered(interrupted, false, true), " bread_consumed_development_pieces=", consumed_bread, " wages_paid_minor_units=", paid_wages)
	print("NETWORK_TIMING normal_advance_us=", normal_advance_us, " broken_advance_us=", broken_advance_us, " max_daily_advance_us=", maximum_advance_us, " scope=advance_minutes_only_excluding_bootstrap_checks_and_restore")
	test.expect(_print_cross_border_trace(economy), "Print one existing cross-border order with original lot lineage, actual receipts, Spatial adoption and Ledger payments")
	# Formal save/restore is exact; no user save file is read or written.
	var saved := built.persistence.snapshot()
	var restored := FormalPersistence.new().restore_candidate(saved)
	test.expect(restored.success and restored.world.economy_r1 != null, "Existing formal persistence restores orders, lots, process history and accounts: " + restored.error)
	if restored.success and restored.world.economy_r1 != null:
		test.equal(restored.persistence.snapshot()["economy_native"], saved["economy_native"], "Native production contracts, orders, inventory and logistics survive exact restore")
		test.equal(restored.world.ledger_state.snapshot(), built.world.ledger_state.snapshot(), "Formal company and personal balances survive exact restore")
		var left: Dictionary = built.simulation_step.advance_minutes(1440)
		var right: Dictionary = restored.simulation_step.advance_minutes(1440)
		test.expect(bool(left.get("success", true)) and bool(right.get("success", true)), "Original and restored worlds both advance once")
		test.equal(restored.world.economy_r1.snapshot(), economy.snapshot(), "Restored NPC production, orders and logistics resume without duplication")
		test.equal(restored.world.ledger_state.snapshot(), built.world.ledger_state.snapshot(), "Restored settlement resumes without cash duplication")
	var broken_save := broken.persistence.snapshot()
	var broken_restore := FormalPersistence.new().restore_candidate(broken_save)
	test.expect(broken_restore.success and broken_restore.world.economy_r1 != null, "Interrupted transport and shortages also survive formal restore: " + broken_restore.error)
	if broken_restore.success and broken_restore.world.economy_r1 != null:
		test.equal(broken_restore.world.economy_r1.snapshot(), interrupted.snapshot(), "Interrupted orders, edge closure and cargo remain exact after restore")
	test.finish(self, "Economic node network integration")
