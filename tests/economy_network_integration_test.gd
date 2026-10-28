extends SceneTree
## Bounded domain integration, using the existing FormalTestCase/WorldBootstrap/
## FormalPersistence entries. No export, external evidence runner or player save.

const Opening = preload("res://scripts/content/economy_network_development.gd")
const DAYS: int = 24
const REGIONAL_DAYS: int = 36
var test := FormalTestCase.new()
var _lyon_shared_case: bool = false
var _rail_link: String = Opening.REGIONAL_RAIL_LINK
var _rail_edges: Array[String] = Opening.REGIONAL_RAIL_EDGES.duplicate()

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var saved_index := arguments.find("--saved-file")
	var compare_index := arguments.find("--compare-saved")
	if compare_index >= 0 and (saved_index < 0 or compare_index + 1 >= arguments.size()):
		test.expect(false, "--compare-saved requires --saved-file and an absolute baseline save path")
		test.finish(self, "Economic network saved-file cold read")
		return
	if saved_index >= 0:
		var compare_path: String = arguments[compare_index + 1] if compare_index >= 0 else ""
		_read_saved_file.call_deferred(arguments[saved_index + 1] if saved_index + 1 < arguments.size() else "", compare_path)
	elif arguments.has("--regional-case"):
		if arguments.has("--lyon-shared"):
			_lyon_shared_case = true
			_rail_link = Opening.REGIONAL_LYON_RAIL_LINK
			_rail_edges = Opening.REGIONAL_LYON_RAIL_EDGES.duplicate()
		_run_regional.call_deferred()
	elif arguments.has("--directory-history-only"):
		_directory_history_only.call_deferred()
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
	for owner: String in economy._stocks:
		for good: String in economy._goods:
			if int(economy._stocks[owner][good]) < 0: return false
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
		# Installation/maintenance consume real goods at their material stage,
		# including projects later cancelled or still waiting for paid work.
		for project: Dictionary in economy._capital.projects.values():
			if project["site_id"] != site: continue
			for input: Dictionary in project.get("material_sources", []):
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

func _planning_delay_projection_exact(economy: EconomyR1Slice) -> bool:
	var paths: Array[Dictionary] = [{"edge_ids": []}]
	for id: String in economy._all_routes(): paths.append({"edge_ids": [id]})
	for path: Dictionary in economy.config.get("transport_paths", []): paths.append(path)
	for order: Dictionary in economy._orders.values():
		var path: Dictionary = {"edge_ids": []}
		for leg: Dictionary in order["route_legs"]: path["edge_ids"].append(leg["edge_id"])
		paths.append(path)
	for path: Dictionary in paths:
		var expected: int = economy._travel_days(economy._locked_legs(path, FormalLedgerState.DENOMINATION))
		if economy._path_travel_days(path) != expected: return false
	return true


## Short functional branch: one normal fixture, at most three days, then reads
## only. It does not save and does not repeat the 24-day two-case integration.
func _map_presentation_boundary(built: WorldBuildResult) -> void:
	var before := built.persistence.snapshot()
	var economy := built.world.economy_r1
	var subject: String = ""
	for row: Dictionary in economy.map_subjects(built.world.player_state.player_id()):
		if economy._spec["firms"].has(row["id"]):
			subject = row["id"]
			break
	test.expect(not subject.is_empty(), "Presentation read uses a real currently authorized company")
	if subject.is_empty(): return
	var site := economy._primary_site(subject)
	var place := economy._place(site)
	var overview := FormalEconomicMapObservation.overview(built.world, "", place, subject)
	test.expect(overview["read_scope"]["kind"] == "HUB_IDENTITIES_ONLY" and overview["node_network"].is_empty() and overview["firm"].is_empty() and overview["production_details"].is_empty(), "Closed map reads hub identities, not private business or production")
	var page := FormalEconomicMapObservation.details(built.world, "", subject, 0, "", place, site)
	test.expect(page["read_scope"]["kind"] == "AUTHORIZED_ORDER_PAGE" and page["read_scope"]["site_id"] == site and page["read_scope"]["page_limit"] == 32, "Open map describes its original authorized site and bounded page")
	# UI-only detached DTO fixtures test aggregation/unknowns, not economic facts.
	var now: int = 8 * 1440
	var delivery := {"id":"ui:receipt", "delivered_minute":now - 7 * 1440, "quantity":2}
	var cargo := {"id":"ui:shipment", "stage":"TRANSIT", "physical_quantity":null}
	var order := {"id":"ui:order", "good":"grain", "from_place_id":"place:paris", "to_place_id":"place:rouen", "pending":1, "transit":1, "shipments":[cargo, cargo.duplicate(true)], "deliveries":[delivery, delivery.duplicate(true), {"id":"ui:future", "delivered_minute":now + 1, "quantity":9}, {"id":"ui:old", "delivered_minute":now - 7 * 1440 - 1, "quantity":9}]}
	page["minute"] = now; page["date"] = {}; page["read_scope"]["observed_minute"] = now
	page["firm"]["orders"] = [order, order]; page["firm"]["sales_orders"] = [order.duplicate(true)]
	page["market_network"] = {"nodes":{}, "edges":{"ui:order":{"order_id":"ui:order", "good":"grain", "from_node":"place:paris", "to_node":"place:rouen", "status":"TRANSIT", "pending_responsibility":1, "transit_responsibility":1}}, "cargo":{"ui:shipment":{"cargo_id":"ui:shipment", "order_id":"ui:order", "good":"grain", "stage":"TRANSIT", "physical_quantity":null}}}
	var view := FormalEconomyMapView.new()
	root.add_child(view)
	view.set_details_open(true)
	var emissions: Array = []
	view.links_changed.connect(func(rows: Array[Dictionary]) -> void: emissions.append(rows.duplicate(true)))
	view.present(page, built.world.spatial_catalog, true)
	test.expect(emissions.size() == 1, "One presentation update publishes links only once")
	test.expect(view._order_index.size() == 1 and view._receipt_facts.size() == 1 and view._receipt_facts[0]["quantity"] == 2, "Repeated buyer/seller orders and receipt IDs count once; exact seven-day boundary stays and future/old rows do not")
	var links_valid: bool = true
	for link: Dictionary in emissions[0]:
		links_valid = links_valid and (not link.get("animate", false) or link["kind"] == "receipt") and link["kind"] != "cargo"
		if link["kind"] == "contract": links_valid = links_valid and not link.has("quantity")
	test.expect(links_valid and emissions[0].size() <= 48 and view._freight_summary().contains("另1条分段记录的实物量/当前位置未知"), "Unknown TRANSIT stays unknown and unlocated; only actual receipt facts animate, contracts have no fake zero quantity")
	# Detached UI-only control: no seven-day expiry or future receipt crosses
	# this one-minute step. Exercise the original renderer setter off-tree,
	# without _ready, viewports, drawing, a second scene or world advancement.
	var stable_page: Dictionary = page.duplicate(true)
	for bucket: String in ["orders", "sales_orders"]:
		for row: Dictionary in stable_page["firm"][bucket]:
			row["deliveries"] = [{"id":"ui:stable", "delivered_minute":now - 1440, "quantity":2}]
	view.present(stable_page, built.world.spatial_catalog, true)
	var stable_links: Array[Dictionary] = emissions.back().duplicate(true)
	var renderer := GlobeRenderer.new()
	renderer.spatial_world = built.world.spatial_world
	renderer.set_topic_links(stable_links)
	test.expect(not renderer._topic_paths.is_empty(), "The real renderer builds spherical paths for the detached authorized-page fixture")
	if not renderer._topic_paths.is_empty():
		var path_id: String = str(renderer._topic_paths.keys()[0])
		var geometry: Dictionary = renderer._topic_paths[path_id]
		stable_page["minute"] = now + 1; stable_page["read_scope"]["observed_minute"] = now + 1
		view.present(stable_page, built.world.spatial_catalog, true)
		var next_links: Array[Dictionary] = emissions.back().duplicate(true)
		renderer.set_topic_links(next_links)
		renderer.set_topic_world_minute(now + 1)
		test.expect(stable_links == next_links and is_same(geometry, renderer._topic_paths[path_id]) and renderer._topic_flow.get("world_minute") == now + 1, "A pure observation-minute refresh reuses the same geometry objects while the real receipt animation minute still advances")
		var legacy_links: Array[Dictionary] = stable_links.duplicate(true)
		for row: Dictionary in legacy_links:
			if not row.get("animate", false): row["observed_minute"] = now
		renderer.set_topic_links(legacy_links)
		var old_geometry: Dictionary = renderer._topic_paths[path_id]
		var samples: int = 0
		for path: Dictionary in renderer._topic_paths.values(): samples += path["units"].size()
		var next_legacy_links: Array[Dictionary] = legacy_links.duplicate(true)
		for row: Dictionary in next_legacy_links:
			if not row.get("animate", false): row["observed_minute"] = now + 1
		renderer.set_topic_links(next_legacy_links)
		test.expect(not is_same(old_geometry, renderer._topic_paths[path_id]), "The previous timestamp-only link shape actually rebuilds geometry in the same unchanged renderer")
		print("MAP_GEOMETRY_MINUTE_CONTROL ", JSON.stringify({"paths":renderer._topic_paths.size(), "old_timestamp_refresh_spherical_samples":samples, "new_minute_only_spherical_samples":0, "scope":"DETACHED_UI_DATA_REAL_RENDERER_SETTER_NO_WINDOW_OR_FPS_MEASUREMENT"}))
	renderer.free()
	for index: int in 257:
		order["deliveries"].append({"id":"ui:cap:" + str(index), "delivered_minute":now - 10, "quantity":1})
	view.present(page, built.world.spatial_catalog, true)
	test.expect(view._receipt_truncated and view._receipt_source_count == 258 and view._receipt_facts.size() == 256 and view._freight_summary().contains("收据已截断"), "Receipt budget retains the latest 256 unique facts and states its actual truncation")
	view.set_details_open(false)
	overview["world_id"] = int(page["world_id"]) + 1; overview["observer"] = "ui:other-observer"
	view.present(overview, built.world.spatial_catalog, true)
	test.expect(view.public_network.is_empty() and view.network.is_empty() and view._order_index.is_empty() and view._receipt_facts.is_empty() and view._details.text.is_empty(), "Changing source world or observer clears both public/private old page data and text: " + JSON.stringify({"public_empty":view.public_network.is_empty(), "private_empty":view.network.is_empty(), "orders_empty":view._order_index.is_empty(), "receipts_empty":view._receipt_facts.is_empty(), "text_length":view._details.text.length()}))
	view.free()
	test.expect(built.persistence.snapshot() == before, "Map observations and all presentation fixture operations leave the complete real world and clock unchanged")


## One original regional opening, twelve real days and one continuation day.
## Only the declared Shared entry schedule is shortened; no clock or receipt is
## manufactured to make the household discoverable before its original delay.
func _directory_history_only() -> void:
	var request := Opening.regional_request()
	for binding: Dictionary in request["configuration"]["shared_transport"]:
		var entries: Array[int] = []
		for minute: int in binding["entry_minutes"]:
			if minute < 9 * 1440: entries.append(minute)
		binding["entry_minutes"] = entries
	test.expect(EconomySliceConfig.valid(request["configuration"]), "Shortened original entry windows retain the real regional configuration contract")
	var built := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, request)
	test.expect(built.success and built.world.economy_r1 != null, "Historical directory fixture uses the original formal regional opening: " + built.error)
	if not built.success or built.world.economy_r1 == null:
		test.finish(self, "Economic network historical directory")
		return
	var economy := built.world.economy_r1
	var buyer_site: String = "site:network:bakery1"
	var buyer: String = economy._owner(buyer_site)
	var family: String = Opening.REGIONAL_FAMILY
	var candidate: String = family + "|flour|" + family
	var receipt_id: String = "message:" + buyer_site + ":supplier:" + candidate
	var receipt: Dictionary = {}
	var past_path: String = ""
	var steps_ok: bool = true
	var conserved: bool = true
	var cash: int = _cash_total(built.world)
	for index: int in 12:
		var step: Dictionary = built.simulation_step.advance_minutes(1440)
		steps_ok = steps_ok and bool(step.get("success", true))
		conserved = conserved and _physical_valid(economy) and _cash_total(built.world) == cash
		if not steps_ok: break
		if index == 7:
			receipt = economy._receipts.get(receipt_id, {}).duplicate(true)
			test.expect(receipt.get("source") == "directory" and receipt.get("scope") == "REGIONAL" and int(receipt.get("delivery_day", -1)) > 0 and int(receipt.get("delivery_day", 9)) < 9, "The household is genuinely learned through its original delayed REGIONAL inbox before the last window")
			for known_offer: Dictionary in economy._offers(buyer, buyer_site, "flour"):
				if known_offer["seller"] == family and not str(known_offer["route_id"]).is_empty():
					past_path = str(known_offer["route_id"])
					break
			test.expect(not past_path.is_empty(), "The received household has a real known goods corridor while entry windows remain")
			var before_expiry := built.persistence.snapshot()
			var early_restore := FormalPersistence.new().restore_candidate(before_expiry)
			test.expect(early_restore.success, "The actual day-eight world cold-restores before window expiry: " + early_restore.error)
			if early_restore.success: test.expect(early_restore.persistence.snapshot() == before_expiry, "The pre-expiry complete formal snapshot is exact")
	test.expect(steps_ok and built.world.game_clock.total_minutes() == 12 * 1440, "The original SimulationStep reaches day twelve without editing GameClock")
	test.expect(conserved, "Each of twelve actual daily boundaries conserves original goods and formal cash")
	if not steps_ok or receipt.get("source") != "directory" or receipt.get("scope") != "REGIONAL" or past_path.is_empty():
		test.finish(self, "Economic network historical directory")
		return
	var origin: String = economy._place(family)
	var destination: String = economy._place(buyer_site)
	test.expect(economy._supplier_known(economy._known_suppliers(buyer_site), candidate), "Expiry does not erase the household identity already received by the city")
	test.expect(economy._paths_for(buyer, origin, destination, economy.day, "flour").is_empty(), "A current flour path has no remaining configured Shared entry window")
	var offer := economy._offer(buyer, family, "flour", past_path, family, buyer_site)
	test.expect(int(offer["quantity"]) == 0 and int(offer["transport_quantity"]) == 0, "An old corridor identity cannot become a fresh executable offer after expiry")
	var payload := {"quote_id": offer["quote_id"], "seller": family, "seller_site": family, "buyer_site": buyer_site, "good": "flour", "quantity": 1, "denomination": offer["denomination"], "max_price": offer["price"], "path_id": past_path, "need_by_day": economy.day + 1}
	var refused := economy.submit_internal(buyer, economy._auto_command(buyer, "buy", payload, "historical_directory_expired_window"))
	test.expect(not refused.get("accepted", false) and refused.get("reason") in ["NO_KNOWN_ROUTE", "UNCONFIGURED_SHARED_WEIGHT_OR_SERVICE_WINDOW"], "The ordinary current buy rejects the expired corridor, not merely an unaffordable or unknown supplier: " + str(refused))
	var checkpoint := built.persistence.snapshot()
	# Warm the current negative result first. A historical lookup must neither
	# reuse it nor replace it with a formerly usable path under the same key.
	economy._paths_for(buyer, origin, destination, economy.day, "flour")
	var current_cache: Dictionary = economy._node_network._path_cache.duplicate(true)
	var current_epoch: int = economy._node_network._cache_until
	test.expect(economy._valid_message(receipt, economy._actors), "A real directory receipt remains valid at its own delivery day after the final Shared window")
	test.expect(economy._node_network._path_cache == current_cache and economy._node_network._cache_until == current_epoch, "Historical validation does not read through, replace or reset the current path cache epoch")
	test.expect(economy._paths_for(buyer, origin, destination, economy.day, "flour").is_empty(), "Current paths remain unavailable after validating historical knowledge")
	# Exercise Node search itself, not only the direct legacy Rouen/Paris row.
	var derived_destination: String = "place:lyon"
	test.expect(economy._node_network.paths(economy, buyer, origin, derived_destination, "flour").is_empty(), "Current derived Rouen/Lyon flour search warms a negative result after entry expiry")
	var derived_cache: Dictionary = economy._node_network._path_cache.duplicate(true)
	var derived_epoch: int = economy._node_network._cache_until
	var historical_paths: Array[Dictionary] = economy._node_network.paths(economy, buyer, origin, derived_destination, "flour", 7 * 1440)
	var multileg_via_paris: bool = false
	var route_rows: Dictionary = economy._all_routes()
	for historical_path: Dictionary in historical_paths:
		if historical_path["edge_ids"].size() < 2: continue
		for edge: String in historical_path["edge_ids"]:
			if route_rows[edge]["to_place_id"] == "place:paris": multileg_via_paris = true
	test.expect(multileg_via_paris, "An explicit day-seven Node query recovers a real multileg Rouen/Paris/Lyon goods corridor despite today's cached negative result")
	test.expect(economy._node_network.paths(economy, buyer, origin, derived_destination, "flour", 10 * 1440).is_empty(), "An as-of query after the last entry cannot reuse a path that existed on day seven")
	test.expect(economy._node_network._path_cache == derived_cache and economy._node_network._cache_until == derived_epoch, "Positive and negative historical multileg searches leave the current path cache and epoch unchanged")
	test.expect(economy._node_network.paths(economy, buyer, origin, derived_destination, "flour").is_empty(), "The current derived multileg query stays unavailable after historical searches")
	test.expect(built.persistence.snapshot() == checkpoint, "Historical validation and current path reads change no field of the complete formal world")
	for change: String in ["date", "audience"]:
		var altered := checkpoint.duplicate(true)
		var forged: Dictionary = receipt.duplicate(true)
		if change == "date":
			forged["delivery_day"] = 10
			forged["observed_day"] = 10 - int(economy._search_policy(buyer_site)["delay_days"][receipt["scope"]])
		else:
			forged["actor"] = "site:network:mill1"
			forged["id"] = "message:" + str(forged["actor"]) + ":supplier:" + candidate
		test.expect(not economy._valid_message(forged, economy._actors), "Original directory legality rejects a forged " + change + " despite a well-formed identity and delay")
		altered["economy_native"]["receipts"].erase(receipt_id)
		altered["economy_native"]["receipts"][forged["id"]] = forged
		var invalid := FormalPersistence.new().restore_candidate(altered)
		test.expect(not invalid.success, "Strict cold restore rejects the forged directory " + change)
	var wrong_good: Dictionary = receipt.duplicate(true)
	wrong_good["candidate"] = family + "|steel|" + family
	wrong_good["id"] = "message:" + buyer_site + ":supplier:" + str(wrong_good["candidate"])
	test.expect(not economy._valid_message(wrong_good, economy._actors), "Historical knowledge retains the actually announced commodity instead of bypassing good validation")
	var restored := FormalPersistence.new().restore_candidate(checkpoint)
	test.expect(restored.success, "The actual post-window world cold-restores its legal old directory receipt: " + restored.error)
	if not restored.success:
		test.finish(self, "Economic network historical directory")
		return
	test.expect(restored.persistence.snapshot() == checkpoint, "Cold restore after expiry preserves every formal snapshot field without a new schema")
	var original_next: Dictionary = built.simulation_step.advance_minutes(1440)
	var restored_next: Dictionary = restored.simulation_step.advance_minutes(1440)
	test.expect(original_next.get("success", true) and restored_next.get("success", true), "Both original and cold-restored worlds advance the same thirteenth day")
	test.expect(restored.persistence.snapshot() == built.persistence.snapshot(), "The complete continued world is exact with no duplicate knowledge, cargo, goods or payments")
	test.finish(self, "Economic network historical directory")


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
		if index == 0:
			var economy := built.world.economy_r1
			test.expect(_planning_delay_projection_exact(economy), "Planning delay matches original locked legs for empty, single-edge, configured and accepted paths")
			var places: Array[String] = ["place:paris"]
			var hubs := economy.market_hub_view(Opening.PLAYER, places)
			test.expect(not hubs.is_empty() and not hubs.get("hubs", []).is_empty() and hubs.get("inventory_authority_created", true) == false, "The real player's typed-place hub view is nonempty and creates no inventory authority")
			var identity_only: bool = true
			for hub: Dictionary in hubs.get("hubs", []): identity_only = identity_only and not hub.has("cash") and not hub.has("inventory")
			test.expect(identity_only, "Every public city hub omits private cash and inventory")
			test.expect(economy.market_hub_view("firm:network:mill1", places).is_empty(), "A firm ID cannot impersonate the player to read city hubs")
			var mapped := economy.economy_map_view(Opening.PLAYER, "firm:network:mill1", "site:network:mill1", 0, 999)
			test.expect(not mapped.is_empty() and mapped.get("page_size") == 32 and int(mapped.get("scanned", 257)) <= 256 and int(mapped.get("scanned", -1)) >= 0, "Authorized map reads clamp an oversized request to 32 rows and examine at most 256 IDs")
			var selected: Dictionary = mapped.get("firm", {})
			var operations: Array = selected.get("operations", [])
			test.expect(selected.get("inventory_basis") == "SELECTED_OWN_SITE" and selected.get("site_id") == "site:network:mill1" and operations.size() == 1 and operations[0].get("site_id") == "site:network:mill1", "Map inventory and the sole operation refer only to the selected authorized site")
			test.expect(economy.economy_map_view(Opening.PLAYER, "firm:network:mill2", "site:network:mill2").is_empty(), "An unappointed company has no map business read")
			test.expect(economy.economy_map_view(Opening.PLAYER, "firm:network:mill1", "site:network:mill2").is_empty(), "A map read cannot attach another company's site to an authorized company")
			test.expect(economy.economy_map_view("firm:network:mill1", "firm:network:mill1", "site:network:mill1").is_empty(), "A forged observer cannot read the player's managed company through the map API")
			var production := economy.economy_production_view(Opening.PLAYER, "firm:network:mill1", "site:network:mill1")
			test.expect(not production.is_empty() and production.get("firm_id") == "firm:network:mill1" and production.get("site_id") == "site:network:mill1", "Opt-in production detail returns the selected authorized business")
			var unappointed_production := economy.economy_production_view(Opening.PLAYER, "firm:network:mill2", "site:network:mill2")
			var wrong_site_production := economy.economy_production_view(Opening.PLAYER, "firm:network:mill1", "site:network:mill2")
			var forged_production := economy.economy_production_view("firm:network:mill1", "firm:network:mill1", "site:network:mill1")
			test.expect(unappointed_production.is_empty() and wrong_site_production.is_empty() and forged_production.is_empty(), "Production detail rejects an unappointed company, a wrong site and a forged observer")
		test.expect(built.persistence.snapshot() == before, "Legacy cargo/business reads and new hub, paged-map and production reads leave the complete authoritative world snapshot unchanged")
		if int(sample["remote"]) == 0: continue
		exercised = true
		test.expect(sample["complete"], "Real remote buyer and seller orders are covered by both managed_firm and query_firm")
		test.expect(sample["hidden"] and sample["canonical"], "All external buy/sell views keep remote/transit quantities null and use only received loss facts")
		test.expect(LivelihoodAction.query_firm(built.world, Opening.PLAYER, "firm:network:mill2").is_empty(), "An unappointed company is still private through the old query entry")
		print("NETWORK_READ_SAMPLE ", JSON.stringify({"minute": built.world.game_clock.total_minutes(), "sample": sample}))
		break
	test.expect(exercised, "At most three days exercised actual nonempty remote cargo")
	_map_presentation_boundary(built)
	test.finish(self, "Economic network read contract")

## Cold file inspection uses only the existing exact decoder/restore candidate.
## No opening scenario is built here, no file is written and no time is advanced.
func _read_saved_file(path: String, compare_path: String = "") -> void:
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
	test.expect(economy.config["case_id"] in [Opening.CASE_ID, Opening.REGIONAL_CASE_ID], "The supplied GUI save is an explicit original or regional economic scenario")
	test.expect(_physical_valid(economy) and _production_totals_valid(economy), "Saved lots and per-good production/input receipts remain physically consistent")
	_print_saved_summary(restored.world, path)
	_print_cross_border_trace(economy)
	if not compare_path.is_empty(): _compare_saved_snapshot(persistence, actual, path, compare_path)
	# Keep the check separate from the candidate decoder's own validation: these
	# diagnostic reads must not advance time, settle, allocate cash or write state.
	test.expect(restored.persistence.snapshot() == actual, "Cold summary and trace leave the entire restored world unchanged")
	test.finish(self, "Economic network saved-file cold read")

func _compare_saved_snapshot(persistence: FormalPersistence, current: Dictionary, current_path: String, baseline_path: String) -> void:
	test.expect(baseline_path.is_absolute_path(), "Save comparison requires the explicitly supplied absolute baseline path")
	if not baseline_path.is_absolute_path(): return
	var baseline := persistence._read_snapshot_file(baseline_path)
	test.expect(baseline.success, "Original decoder reads only the requested baseline save: " + baseline.error_code + " " + baseline.message)
	if not baseline.success: return
	var same_clock: bool = current.get("total_minutes") == baseline.snapshot.get("total_minutes") and current.get("minute_remainder") == baseline.snapshot.get("minute_remainder")
	var same_native: bool = current.get("economy_native") == baseline.snapshot.get("economy_native")
	var same_ledger: bool = current.get("ledger") == baseline.snapshot.get("ledger")
	test.expect(same_clock, "Current cold-restored and baseline decoded clocks are exactly equal")
	test.expect(same_native, "Native economy dictionaries are exact: no duplicated orders, lots, wages or production")
	test.expect(same_ledger, "Ledger dictionaries are exact: no duplicated payment or reservation")
	print("NETWORK_SAVED_COMPARE ", JSON.stringify({"source": "ORIGINAL_DECODED_SNAPSHOTS_AND_CURRENT_RESTORE_DICTIONARY_EQUALITY_NO_HASHES_NO_WRITES", "current_path": current_path, "baseline_path": baseline_path, "exact": {"clock": same_clock, "economy_native": same_native, "ledger": same_ledger, "all_requested": same_clock and same_native and same_ledger}, "current": _saved_dedup_summary(current), "baseline": _saved_dedup_summary(baseline.snapshot)}))

func _saved_dedup_summary(state: Dictionary) -> Dictionary:
	var native: Dictionary = state.get("economy_native", {})
	var sources: Dictionary = native.get("stock_lots", {}).get("sources", {})
	var unique_transactions: Dictionary = {}
	var transaction_rows: Array = state.get("ledger", {}).get("transactions", [])
	for transaction: Dictionary in transaction_rows: unique_transactions[transaction["transaction_id"]] = true
	var production_sources: Dictionary = {}
	var produced := Opening.stock()
	for source: Dictionary in sources.values():
		if not str(source["id"]).begins_with("production:") and not str(source["id"]).begins_with("local_production:"): continue
		production_sources[source["id"]] = true
		produced[source["good"]] = int(produced[source["good"]]) + int(source["quantity"])
	return {"clock": {"total_minutes": state.get("total_minutes"), "minute_remainder": state.get("minute_remainder")}, "orders_unique_ids": native.get("orders", {}).size(), "sources_unique_ids": sources.size(), "transactions_rows": transaction_rows.size(), "transactions_unique_ids": unique_transactions.size(), "wages_unique_ids": native.get("wages", {}).size(), "production_sources_unique_ids": production_sources.size(), "produced_by_good_from_unique_source_receipts": produced}

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

func _regional_history(economy: EconomyR1Slice) -> Dictionary:
	return {"minute": economy._world.game_clock.total_minutes(), "orders": economy._orders.size(), "sources": economy._lots.sources.size(), "portions": economy._lots.portions.size(), "wages": economy._wages.size(), "delivery_receipts": economy._delivery_receipts.size(), "shared_entries": economy._shared.entries.size(), "transactions": economy._world.ledger_state.transactions().size(), "route_queries": economy.query_metrics(), "rail_infrastructure": _regional_rail_state(economy), "scope": "ACTUAL_RUNTIME_RECORD_COUNTS_AND_DERIVED_QUERY_METRICS_NOT_ENCODED_SAVE_BYTES"}

func _source_has_mined_input(economy: EconomyR1Slice, source_id: String, site: String) -> bool:
	var pending: Array[String] = [source_id]
	var seen: Dictionary = {}
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if seen.has(id): continue
		seen[id] = true
		var source: Dictionary = economy._lots.sources.get(id, {})
		if str(source.get("id", "")).begins_with("production:") and str(source["id"]).contains(":" + site + ":"): return true
		for input: Dictionary in source.get("inputs", []): pending.append(input["source_id"])
	return false

func _regional_market_feedback(economy: EconomyR1Slice) -> Dictionary:
	var candidate: String = Opening.REGIONAL_FAMILY + "|flour|" + Opening.REGIONAL_FAMILY
	var received: Dictionary = {}
	for receipt: Dictionary in economy._receipts.values():
		if receipt.get("source") == "directory" and receipt.get("candidate") == candidate:
			received[receipt["actor"]] = {"observed_day":receipt["observed_day"], "delivery_day":receipt["delivery_day"], "scope":receipt["scope"]}
	var orders: Array[Dictionary] = []
	var after_knowledge: bool = true
	for order: Dictionary in economy._orders.values():
		if order["seller"] != Opening.REGIONAL_FAMILY or order["buyer_site"] not in ["site:network:bakery1", "site:regional:station:paris"]: continue
		var receipt: Dictionary = received.get(order["buyer_site"], {})
		after_knowledge = after_knowledge and not receipt.is_empty() and int(order["accepted_day"]) >= int(receipt.get("delivery_day", FormalLedgerState.MAX_AMOUNT))
		orders.append({"id":order["id"], "buyer_site":order["buyer_site"], "accepted_day":order["accepted_day"], "quantity":order["quantity"], "delivered":order["delivered"], "price":order["price"]})
	var bread: int = 0
	for source: Dictionary in economy._lots.sources.values():
		if source["good"] != "bread" or not str(source["id"]).contains(":site:network:bakery1:"): continue
		var pending: Array[String] = [source["id"]]
		var seen: Dictionary = {}
		var family_input: bool = false
		while not pending.is_empty():
			var id: String = pending.pop_back()
			if seen.has(id): continue
			seen[id] = true
			if id.begins_with("local_production:") and id.ends_with(":" + Opening.REGIONAL_FAMILY + ":flour"):
				family_input = true
				break
			for input: Dictionary in economy._lots.sources.get(id, {}).get("inputs", []): pending.append(input["source_id"])
		if family_input: bread += int(source["quantity"])
	return {"market_place_id":economy._place(Opening.REGIONAL_FAMILY), "received_announcements":received, "orders":orders, "all_orders_after_knowledge":after_knowledge, "bread_with_household_flour_input":bread, "remaining_family_flour":economy._stocks[Opening.REGIONAL_FAMILY]["flour"], "scope":"ORIGINAL_DELAYED_DIRECTORY_ORDER_LEDGER_AND_SOURCE_LINEAGE_NOT_HUB_STOCK"}


func _regional_metrics(economy: EconomyR1Slice) -> Dictionary:
	var family_output: int = 0
	var family_input: int = 0
	var family_sources: int = 0
	for source: Dictionary in economy._lots.sources.values():
		if not str(source["id"]).begins_with("local_production:") or not str(source["id"]).ends_with(":" + Opening.REGIONAL_FAMILY + ":flour"): continue
		family_sources += 1
		family_output += int(source["quantity"])
		for input: Dictionary in source["inputs"]: family_input += int(input["quantity"])
	var family_delivered: int = 0
	var family_payments: int = 0
	for order: Dictionary in economy._orders.values():
		if order["seller"] != Opening.REGIONAL_FAMILY: continue
		family_delivered += int(order["delivered"])
		for payment: Dictionary in economy._world.ledger_state.own_transactions(Opening.REGIONAL_FAMILY):
			if payment["reference_id"] == order["id"] and payment["kind"] == "goods": family_payments += int(payment["amount"])
	var installations: int = 0
	var repairs: int = 0
	var repair_tools: int = 0
	var complete_chain: bool = false
	var pending_repairs: Array[Dictionary] = []
	for project: Dictionary in economy._capital.projects.values():
		if project["kind"] == "INSTALL" and project["status"] == "COMPLETED": installations += 1
		if project["kind"] != "MAINTENANCE": continue
		if project["status"] == "COMPLETED": repairs += 1
		else: pending_repairs.append({"id": project["id"], "status": project["status"], "reason": project["reason"]})
		for input: Dictionary in project.get("material_sources", []):
			var source: Dictionary = economy._lots.sources[input["source_id"]]
			if source["good"] != "tools": continue
			repair_tools += int(input["quantity"])
			if _source_has_mined_input(economy, source["id"], "site:network:coal") and _source_has_mined_input(economy, source["id"], "site:network:ore"): complete_chain = true
	var funded_residents: int = 0
	var paid: int = 0
	for claim: Dictionary in economy._wages.values(): paid += int(claim["amount"]) - int(claim["remaining"])
	for actor: String in economy._actor_ids():
		if actor == Opening.REGIONAL_FAMILY or economy._spec["actors"][actor]["kind"] != "cohort": continue
		var account: String = economy._account(actor)
		var wage_in: int = 0
		var other_in: int = 0
		var food_out: int = 0
		for payment: Dictionary in economy._world.ledger_state.own_transactions(actor):
			if payment["to_account_id"] == account:
				if payment["kind"] == "wage": wage_in += int(payment["amount"])
				else: other_in += int(payment["amount"])
			var order: Dictionary = economy._orders.get(payment["reference_id"], {})
			if payment["from_account_id"] == account and payment["kind"] == "goods" and order.get("good") == "bread": food_out += int(payment["amount"])
		if wage_in > 0 and other_in == 0 and food_out > 0 and int(economy._physical_totals[actor]["used"]["bread"]) > 0: funded_residents += 1
	return {"family_sources": family_sources, "family_grain_used": family_input, "family_flour_produced": family_output, "family_flour_delivered": family_delivered, "family_goods_payments": family_payments, "installations_completed": installations, "maintenance_completed": repairs, "tools_consumed_in_maintenance": repair_tools, "mined_coal_ore_to_steel_to_tools_to_maintenance": complete_chain, "pending_maintenance": pending_repairs, "coal_extracted_kg": _produced(economy, "site:network:coal", "coal"), "ore_extracted_kg": _produced(economy, "site:network:ore", "iron_ore"), "wages_paid_minor": paid, "zero_opening_cash_wage_funded_food_consumers": funded_residents, "unmet_need_units": _unmet(economy), "delivered_by_good": _delivered(economy), "multileg_delivered_by_good": _delivered(economy, true), "history": _regional_history(economy)}

func _print_public_control_leaves(expected: Dictionary, actual: Dictionary, label: String) -> void:
	# Selected original public control/topology leaves only. Never normalize or
	# rewrite either saved world, and never print provenance fingerprints.
	var leaves: Array[Dictionary] = []
	var before: Dictionary = expected["territory"]["controllers"]
	var after: Dictionary = actual["territory"]["controllers"]
	var ids: Array = before.keys()
	for id: Variant in after:
		if not ids.has(id): ids.append(id)
	for id: Variant in ids:
		if before.has(id) == after.has(id) and before.get(id) == after.get(id): continue
		leaves.append({"path": "territory.controllers." + str(id), "before_present": before.has(id), "after_present": after.has(id), "before": before.get(id), "after": after.get(id), "before_type": typeof(before.get(id)), "after_type": typeof(after.get(id))})
		if leaves.size() >= 4: break
	var old_land: Dictionary = expected["spatial"]["land"]
	var new_land: Dictionary = actual["spatial"]["land"]
	if old_land["revision"] != new_land["revision"]: leaves.append({"path": "spatial.land.revision", "before": old_land["revision"], "after": new_land["revision"]})
	if old_land["active"].size() != new_land["active"].size(): leaves.append({"path": "spatial.land.active.size", "before": old_land["active"].size(), "after": new_land["active"].size()})
	var old_parents: Dictionary = {}
	var new_parents: Dictionary = {}
	for row: Dictionary in old_land["active"]: old_parents[row["territory_unit_id"]] = row["parent_id"]
	for row: Dictionary in new_land["active"]: new_parents[row["territory_unit_id"]] = row["parent_id"]
	ids = old_parents.keys()
	for id: Variant in new_parents:
		if not ids.has(id): ids.append(id)
	for id: Variant in ids:
		if leaves.size() >= 8: break
		if old_parents.has(id) == new_parents.has(id) and old_parents.get(id) == new_parents.get(id): continue
		leaves.append({"path": "spatial.land.active[" + str(id) + "].parent_id", "before_present": old_parents.has(id), "after_present": new_parents.has(id), "before": old_parents.get(id), "after": new_parents.get(id), "before_type": typeof(old_parents.get(id)), "after_type": typeof(new_parents.get(id))})
	if not leaves.is_empty(): print("REGIONAL_PUBLIC_CONTROL_LEAVES ", label, " ", JSON.stringify(leaves))

func _lyon_shared_metrics(economy: EconomyR1Slice) -> Dictionary:
	var entered := Opening.stock()
	var delivered := Opening.stock()
	var entries: int = 0
	var spatial_facts_match: bool = true
	var shipment_orders: Dictionary = {}
	for cargo: Dictionary in economy._shipments.values(): shipment_orders[cargo["id"]] = cargo["order_id"]
	for receipt: Dictionary in economy._delivery_receipts.values(): shipment_orders[receipt.get("shipment_id", receipt["id"])] = receipt["order_id"]
	for entry: Dictionary in economy._shared.entries.values():
		if entry["edge_id"] not in Opening.REGIONAL_LYON_RAIL_EDGES: continue
		entries += 1
		var order: Dictionary = economy._orders.get(shipment_orders.get(entry["shipment_id"], ""), {})
		if not order.is_empty(): entered[order["good"]] = int(entered[order["good"]]) + int(entry["quantity"])
		var fact := economy._world.spatial_world.capacity_adoption(entry["adoption_id"])
		spatial_facts_match = spatial_facts_match and not fact.is_empty() and fact["link_id"] == Opening.REGIONAL_LYON_RAIL_LINK and fact["source_id"] == entry["shipment_id"]
	var grain_order: Dictionary = {}
	for order: Dictionary in economy._orders.values():
		var uses_link: bool = false
		for leg: Dictionary in order["route_legs"]:
			if leg["edge_id"] in Opening.REGIONAL_LYON_RAIL_EDGES: uses_link = true
		if not uses_link: continue
		delivered[order["good"]] = int(delivered[order["good"]]) + int(order["delivered"])
		if grain_order.is_empty() and order["good"] == "grain" and order["buyer"] == "firm:network:mill1" and int(order["delivered"]) > 0: grain_order = order
	var goods_paid: int = 0
	var freight_paid: int = 0
	if not grain_order.is_empty():
		for payment: Dictionary in economy._world.ledger_state.own_transactions(grain_order["buyer"]):
			if payment["reference_id"] != grain_order["id"]: continue
			if payment["kind"] == "goods": goods_paid += int(payment["amount"])
			if payment["kind"] == "freight": freight_paid += int(payment["amount"])
	var worker: String = "cohort:regional:station:lyon"
	var wages_paid: int = 0
	for payment: Dictionary in economy._world.ledger_state.own_transactions(worker):
		if payment["kind"] == "wage" and payment["to_account_id"] == economy._account(worker): wages_paid += int(payment["amount"])
	return {"entries": entries, "entered_by_good": entered, "delivered_using_link_by_good": delivered, "spatial_facts_match": spatial_facts_match, "lyon_handling_hours_allocated": economy._shared.allocated_hours("site:regional:station:lyon"), "lyon_zero_cash_worker_wages_paid": wages_paid, "lyon_worker_bread_consumed": economy._physical_totals[worker]["used"]["bread"], "lyon_seller_grain_remaining": economy._stocks["site:network:grain"]["grain"], "paris_mill_grain_consumed": economy._physical_totals["site:network:mill1"]["used"]["grain"], "example_order": {"id": grain_order.get("id", ""), "buyer": grain_order.get("buyer", ""), "seller": grain_order.get("seller", ""), "accepted_day": grain_order.get("accepted_day", -1), "quantity": grain_order.get("quantity", 0), "delivered": grain_order.get("delivered", 0), "goods_paid": goods_paid, "freight_paid": freight_paid}}

func _regional_rail_state(economy: EconomyR1Slice) -> Dictionary:
	var row := economy._world.spatial_world.infrastructure_state(_rail_link)
	return {"status": row.get("status"), "nominal_capacity": row.get("nominal_capacity"), "condition": row.get("condition"), "effective_capacity": row.get("effective_capacity"), "remaining_capacity": row.get("remaining_capacity")}

func _regional_rail_waiting(economy: EconomyR1Slice) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in economy._moving_shipments:
		var cargo: Dictionary = economy._shipments[id]
		if cargo["stage"] != "WAITING": continue
		var order: Dictionary = economy._orders[cargo["order_id"]]
		var leg: Dictionary = order["route_legs"][cargo["leg_index"]]
		if leg["edge_id"] not in _rail_edges: continue
		result.append({"shipment": id, "good": order["good"], "quantity": cargo["quantity"], "leg_index": cargo["leg_index"], "reason": economy._waiting_reason(leg, cargo["quantity"], cargo["ready_day"], order["good"])})
		if result.size() >= 4: break
	for id: String in economy._pending_orders:
		if result.size() >= 4: break
		var order: Dictionary = economy._orders[id]
		var leg: Dictionary = order["route_legs"][0]
		if leg["edge_id"] not in _rail_edges: continue
		result.append({"order": id, "good": order["good"], "pending": order["pending"], "reason": economy._waiting_reason(leg, 1, economy._earliest_dispatch(order), order["good"])})
	return result

func _print_initial_authority_difference(expected: Dictionary, actual: Dictionary, label: String) -> void:
	for field: String in ["total_minutes", "minute_remainder", "economy_native", "ledger", "population"]:
		test.expect(actual.get(field) == expected.get(field), label + " initial authority remains exact: " + field)
	var differences: Array[Dictionary] = []
	for field: String in expected:
		if expected[field] == actual.get(field): continue
		var row: Dictionary = {"field": field, "expected_type": typeof(expected[field]), "actual_type": typeof(actual.get(field))}
		if expected[field] is Dictionary and actual.get(field) is Dictionary:
			var children: Array[Dictionary] = []
			for key: Variant in expected[field]:
				if expected[field][key] == actual[field].get(key): continue
				var child: Dictionary = {"field": key}
				if typeof(expected[field][key]) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
					child["expected"] = expected[field][key]
					child["actual"] = actual[field].get(key)
				children.append(child)
				if children.size() >= 8: break
			row["different_children_first_8"] = children
		else:
			row["expected"] = expected[field]
			row["actual"] = actual.get(field)
		differences.append(row)
	if not differences.is_empty():
		print("REGIONAL_INITIAL_RESTORE_DIFFERENCES ", label, " ", JSON.stringify(differences))
		if label == "tools_shortage": _print_public_control_leaves(expected, actual, label)

func _advance_regional_rail(world: WorldBuildResult, minutes: int, control: Dictionary) -> Dictionary:
	var economy := world.world.economy_r1
	var target: int = world.world.game_clock.total_minutes() + minutes
	while world.world.game_clock.total_minutes() < target:
		if control["closed"]: return world.simulation_step.advance_minutes(target - world.world.game_clock.total_minutes())
		if control["failed"]: return {"success": true, "intervention_failed": true}
		var now: int = world.world.game_clock.total_minutes()
		var boundary: int = mini(target, (world.world.game_clock.current_day() + 1) * 1440)
		var next_event: int = economy.next_transport_boundary()
		if next_event > now: boundary = mini(boundary, next_event)
		var step: Dictionary = world.simulation_step.advance_minutes(boundary - now)
		if not step.get("success", true): return step
		for entry: Dictionary in economy._shared.entries.values():
			if entry["edge_id"] not in _rail_edges: continue
			var cargo: Dictionary = economy._shipments.get(entry["shipment_id"], {})
			if cargo.is_empty() or economy._orders[cargo["order_id"]]["route_legs"].size() < 2: continue
			if cargo["leg_index"] == entry["leg_index"] and cargo["stage"] == "TRANSIT":
				control["adopted"] = entry.duplicate(true)
				control["fact"] = world.world.spatial_world.capacity_adoption(entry["adoption_id"])
				for prior: Dictionary in economy._shared.entries.values():
					if prior["edge_id"] in _rail_edges: control["entry_ids"][prior["adoption_id"]] = true
				control["closed"] = world.world.spatial_world.set_infrastructure_status(_rail_link, VNextInfrastructureLinkState.STATUS_INTERRUPTED)
				control["failed"] = not control["closed"]
				test.expect(control["closed"], "Spatial interrupts the real rail immediately after actual loading ends and the admitted multileg cargo enters TRANSIT")
				print("REGIONAL_RAIL_INTERRUPTION ", JSON.stringify({"minute": world.world.game_clock.total_minutes(), "cargo_stage": cargo["stage"], "already_adopted_entry": control["adopted"], "spatial_fact": control["fact"], "entry_count_at_closure": control["entry_ids"].size(), "infrastructure_after": _regional_rail_state(economy)}))
				break
			if cargo["leg_index"] > entry["leg_index"] or (cargo["leg_index"] == entry["leg_index"] and cargo["stage"] in ["WAITING_UNLOAD", "UNLOADING", "AWAITING_RECIPIENT"]):
				control["failed"] = true
				test.expect(false, "Rail control missed an already-progressed real multileg adoption; stop this branch immediately rather than claim an intervention")
				return {"success": true, "intervention_failed": true}
		if not control["closed"] and world.world.game_clock.total_minutes() >= 7 * 1440:
			control["failed"] = true
			test.expect(false, "No actual multileg rail TRANSIT was intercepted in the bounded opening week; do not silently run an unchanged 36-day control")
			return {"success": true, "intervention_failed": true}
	return {"success": true}

func _print_regional_family_market(economy: EconomyR1Slice) -> void:
	var buyers: Array[Dictionary] = []
	var family_key := Opening.REGIONAL_FAMILY + "|flour|" + Opening.REGIONAL_FAMILY
	for site: String in ["site:network:bakery1", "site:regional:station:paris"]:
		var need := economy._input_need(site, "flour")
		var offers: Array[Dictionary] = []
		var rank: int = 0
		for offer: Dictionary in economy._input_offers(site, "flour", need["need_by_day"], maxi(1, int(need["quantity"]))):
			rank += 1
			if rank > 2 and offer["seller"] != Opening.REGIONAL_FAMILY: continue
			offers.append({"rank": rank, "seller": offer["seller"], "quantity": offer["quantity"], "transport_quantity": offer["transport_quantity"], "reason": offer["reason"], "price": offer["price"], "freight_per_unit": offer["freight_per_unit"], "route_legs": offer["route_legs"], "arrival_day": offer["earliest_arrival_day"]})
		buyers.append({"site": site, "family_known": economy._firm_knowledge[site].has(family_key), "buyer_account": economy._account(economy._owner(site)), "available_cash": economy._world.ledger_state.available_balance(economy._account(economy._owner(site))), "input_need": need, "ranked_legal_offers_first_2_and_family": offers})
	var orders: Array[Dictionary] = []
	for order: Dictionary in economy._orders.values():
		if order["seller"] == Opening.REGIONAL_FAMILY and orders.size() < 8: orders.append({"id": order["id"], "buyer_site": order["buyer_site"], "quantity": order["quantity"], "pending": order["pending"], "transit": order["transit"], "delivered": order["delivered"]})
	var commands: Array[Dictionary] = []
	for row: Dictionary in economy._commands.values():
		var command: Dictionary = row["envelope"]["command"]
		if command["kind"] == "buy" and command["payload"].get("seller") == Opening.REGIONAL_FAMILY and commands.size() < 8: commands.append({"id": command["action_id"], "minute": command["minute"], "actor": row["envelope"]["actor"], "payload": command["payload"], "result": row["result"]})
	var shipments: Array[Dictionary] = []
	for cargo: Dictionary in economy._shipments.values():
		var order: Dictionary = economy._orders[cargo["order_id"]]
		if order["seller"] != Opening.REGIONAL_FAMILY: continue
		var view := economy._shipment_view(cargo, order)
		shipments.append({"id": cargo["id"], "order_id": order["id"], "stage": view["stage"], "leg_index": view["leg_index"], "quantity": view["quantity"], "physical_quantity": view["physical_quantity"], "place_id": view["place_id"], "arrival_minute": view.get("arrival_minute"), "unloading_end_minute": view.get("unloading_end_minute"), "waiting_reason": view.get("waiting_reason"), "arrival_blocked_reason": view.get("arrival_blocked_reason")})
		if shipments.size() >= 8: break
	var handling_rows: Array[Dictionary] = []
	var resources: Array[Dictionary] = []
	var now: int = economy._world.game_clock.total_minutes()
	for edge_id: String in Opening.REGIONAL_RAIL_EDGES:
		var binding: Dictionary = economy._shared.bindings[edge_id]
		for operation: String in ["ORIGIN", "ARRIVAL"]:
			var key := str(economy.day) + "|" + edge_id
			var site: String = binding["handling_site"]
			if operation == "ARRIVAL":
				key += "|arrival"
				site = economy._shared.facilities[binding["node_resources"]["destination_handling"]]["site_id"]
			var handling: Dictionary = economy._shared.handling.get(key, {})
			var work_sources: Array[Dictionary] = []
			for work_id: String in economy._capital_work_ids:
				var work: Dictionary = economy._work_records[work_id]
				if economy._spec["jobs"][work["job"]]["site_id"] != site: continue
				var claim: Dictionary = economy._wages.get(work_id, {})
				var payments: Array[Dictionary] = []
				for payment: Dictionary in economy._world.ledger_state.own_transactions(work["actor"]):
					if payment["kind"] == "wage" and payment["reference_id"] == work_id and payments.size() < 4: payments.append({"transaction_id": payment["transaction_id"], "minute": payment["effective_minute"], "amount": payment["amount"]})
				work_sources.append({"work_id": work_id, "actor": work["actor"], "job": work["job"], "work_day": work["day"], "recorded_hours": work["hours"], "wage_amount": claim.get("amount"), "wage_paid": claim.get("paid"), "wage_remaining": claim.get("remaining"), "wage_due_day": claim.get("due_day"), "actual_wage_transactions_first_4": payments})
				if work_sources.size() >= 4: break
			var needed: int = economy._shared.labor_needed_arrival(edge_id) if operation == "ARRIVAL" else economy._shared._needed_hours(edge_id)
			handling_rows.append({"day": economy.day, "edge_id": edge_id, "operation": operation, "site": site, "record_present": economy._shared.handling.has(key), "hours": handling.get("hours"), "used": handling.get("used"), "work": handling.get("work"), "needed_hours_now": needed, "native_remaining_site_labor": economy._labor.get(site), "actual_site_work_and_wage_sources_first_4": work_sources})
		var nodes: Dictionary = {}
		for role: String in ["origin_handling", "origin_berth", "destination_handling", "destination_berth", "destination_storage"]:
			var facility: String = binding["node_resources"][role]
			nodes[role] = {"facility_id": facility, "capacity": economy._shared._node_capacity(facility, now), "used": economy._shared._node_used(facility, now), "available": economy._shared._node_available(facility, now)}
		resources.append({"edge_id": edge_id, "window_open": economy._shared.window_open(binding, now), "weight_unit": binding["weight_unit"], "vehicle_id": binding["vehicle_id"], "vehicle_payload": binding["vehicle_payload"], "vehicle_available": economy._shared._vehicle_available(binding, now), "actual_link_remaining_capacity": economy._world.spatial_world.remaining_capacity(binding["source_link_id"]), "flour_quantity_limit_for_one_unit_now": economy._shared.quantity(edge_id, "flour", 1), "node_resources": nodes})
	print("REGIONAL_FAMILY_MARKET ", JSON.stringify({"minute": now, "buyers": buyers, "family_orders_first_8": orders, "family_buy_commands_first_8": commands, "no_submitted_family_buy_commands": commands.is_empty(), "printed_family_shipment_rows": shipments.size()}))
	for row: Dictionary in shipments: print("REGIONAL_FAMILY_SHIPMENT ", JSON.stringify({"minute": now, "shipment": row}))
	for row: Dictionary in handling_rows: print("REGIONAL_RAIL_HANDLING ", JSON.stringify({"minute": now, "handling": row}))
	for row: Dictionary in resources: print("REGIONAL_RAIL_RESOURCES ", JSON.stringify({"minute": now, "resources": row}))

func _print_regional_pending_maintenance(economy: EconomyR1Slice) -> void:
	var pending: Array[Dictionary] = []
	for project: Dictionary in economy._capital.projects.values():
		if project["status"] == "COMPLETED": continue
		var resources: Dictionary = {}
		var terms := economy._capital.terms_for(project)
		for good: String in terms["materials"]:
			resources[good] = {"required": terms["materials"][good], "on_hand": economy._stocks[project["site_id"]][good], "free": economy.capital_free_goods(project["site_id"], good), "exposure": economy._exposure(project["site_id"], good), "offers": economy._input_offers(project["site_id"], good, economy.day + 1, 1).slice(0, 2)}
		var commands: Array[Dictionary] = []
		for row: Dictionary in economy._commands.values():
			var command: Dictionary = row["envelope"]["command"]
			if command["kind"] == "buy" and command["payload"].get("buyer_site") == project["site_id"] and command["payload"].get("good") in ["steel", "tools"]: commands.append({"minute": command["minute"], "payload": command["payload"], "result": row["result"]})
		pending.append({"id": project["id"], "kind": project["kind"], "site": project["site_id"], "status": project["status"], "reason": project["reason"], "budget": project["budget"], "orders": project["orders"], "material_sources": project.get("material_sources", []), "resources": resources, "recent_material_buy_commands_last_4": commands.slice(maxi(0, commands.size() - 4))})
	print("REGIONAL_PENDING_CAPITAL ", JSON.stringify({"minute": economy._world.game_clock.total_minutes(), "projects": pending}))

func _regional_config_failure_names(configuration: Dictionary) -> void:
	# Only on a failed existing validation. Reuse its original subvalidators;
	# do not start a world, add a validation platform or relax admission rules.
	var actors: Dictionary = {}
	var firms: Dictionary = {}
	var accounts: Dictionary = {FormalLedgerState.SOURCE_ACCOUNT: true}
	for actor: Dictionary in configuration["actors"]:
		actors[actor["id"]] = actor
		accounts[actor["account_id"]] = true
	for firm: Dictionary in configuration["firms"]:
		firms[firm["id"]] = firm
		accounts[firm["account_id"]] = true
	var jobs: Dictionary = {}
	for job: Dictionary in configuration["jobs"]: jobs[job["id"]] = job
	var spec := EconomySliceConfig.normalize(configuration, [])
	var checks: Dictionary = {"finance_routes": EconomySliceConfig._finance(configuration, actors, firms, jobs, accounts), "operations_supplier_search": EconomySliceConfig._operations(configuration, actors, firms), "capital_investment": EconomySliceConfig.Capital.valid_configuration(configuration, spec), "production_process": EconomySliceConfig.Process.valid_configuration(configuration, spec), "local_producers": EconomySliceConfig.LocalProducers.valid(configuration, spec), "shared_transport": EconomySliceConfig.SharedTransport.valid_configuration(configuration.get("shared_transport", [])), "transport_facilities": EconomySliceConfig.SharedTransport.valid_facilities(configuration.get("transport_facilities", []))}
	var failures: Array[String] = []
	for name: String in checks:
		if not checks[name]: failures.append(name)
	if failures.is_empty(): failures.append("BASE_R2_IDENTITIES_SITES_JOBS_INFORMATION_OR_OTHER_ORIGINAL_OPTIONAL_CONTRACT")
	print("REGIONAL_CONFIGURATION_FAILED ", JSON.stringify(failures))

func _run_regional() -> void:
	var configuration := Opening.regional_template(_lyon_shared_case)
	var valid: bool = EconomySliceConfig.valid(configuration)
	test.expect(valid, "Regional case uses native producers, capital permissions and existing Shared transport schema")
	if not valid:
		_regional_config_failure_names(configuration)
		test.finish(self, "Regional economic industry integration")
		return
	test.equal(configuration["firms"].size(), 20, "The actual household is not a twenty-first company")
	test.equal(Opening.template()["case_id"], Opening.CASE_ID, "The old case entry is unchanged")
	# Use the actual formal opening's historical land initialization. Skipping it
	# made restore legitimately add land splits/controllers absent from the seed.
	var normal := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, Opening.regional_request([], _lyon_shared_case))
	test.expect(normal.success and normal.world.economy_r1 != null, "Host opening builds the opt-in regional case: " + normal.error)
	if not normal.success or normal.world.economy_r1 == null:
		test.finish(self, "Regional economic industry integration")
		return
	var initial := normal.persistence.snapshot()
	var initial_sample_minute: int = int(initial["total_minutes"])
	var initial_document_bytes: int = JSON.stringify(FormalWorldPersistenceDocument.encode(initial)).to_utf8_buffer().size()
	var initial_native_bytes: int = var_to_bytes(initial["economy_native"]).size()
	var tools := FormalPersistence.new().restore_candidate(initial)
	var rail := FormalPersistence.new().restore_candidate(initial)
	test.expect(tools.success and rail.success, "Normal, upstream-tools shortage and rail interruption use the identical original formal snapshot")
	if not tools.success or not rail.success:
		test.finish(self, "Regional economic industry integration")
		return
	var tools_initial := tools.persistence.snapshot()
	var rail_initial := rail.persistence.snapshot()
	test.expect(tools_initial == initial and rail_initial == initial, "Initial cash, lots, population, responsibilities and clock are exact before the single intervention")
	_print_initial_authority_difference(initial, tools_initial, "tools_shortage")
	_print_initial_authority_difference(initial, rail_initial, "rail_interrupted")
	var economy := normal.world.economy_r1
	var shortage := tools.world.economy_r1
	var interrupted := rail.world.economy_r1
	if _lyon_shared_case:
		var lyon_binding: Dictionary = economy._shared.bindings[Opening.REGIONAL_LYON_RAIL_EDGES[0]]
		var rouen_binding: Dictionary = economy._shared.bindings[Opening.REGIONAL_RAIL_EDGES[0]]
		test.expect(lyon_binding["node_resources"]["origin_handling"] == rouen_binding["node_resources"]["origin_handling"] and lyon_binding["vehicle_id"] != rouen_binding["vehicle_id"] and lyon_binding["vehicle_id"] == economy._shared.bindings[Opening.REGIONAL_LYON_RAIL_EDGES[1]]["vehicle_id"], "Two finite bidirectional trains share one actual Paris handling facility, not per-service cloned station capacity")
		test.expect(economy._spec["actors"]["cohort:regional:station:lyon"]["cash"] == 0 and economy._spec["sites"]["site:regional:station:lyon"]["stock"] == Opening.stock(), "The added Lyon handling site and host worker introduce no money, sale goods or phantom production")
	var family_candidate: String = Opening.REGIONAL_FAMILY + "|flour|" + Opening.REGIONAL_FAMILY
	test.expect(not economy._supplier_known(economy._known_suppliers("site:network:bakery1"), family_candidate) and not economy._supplier_known(economy._known_suppliers("site:regional:station:paris"), family_candidate), "City buyers start without a secretly prefilled household supplier")
	test.expect(economy._directory_entry("site:network:bakery1", family_candidate, "REGIONAL", 0).is_empty() and economy._directory_entry("site:network:mill1", family_candidate, "WIDE", 1).is_empty(), "Unpublished or unaddressed city announcements do not grant supplier knowledge")
	test.expect(not economy._spec["firms"].has(Opening.REGIONAL_FAMILY) and economy._spec["actors"][Opening.REGIONAL_FAMILY]["members"] == 2, "Rouen processing belongs to two real anonymous residents, not a renamed corporation")
	test.equal(normal.world.population_state.unit_for_place("place:rouen"), "country_fra", "Rouen is an admitted host place in the existing French population authority")
	test.equal(normal.world.ledger_state.account(economy._account(Opening.REGIONAL_FAMILY))["owner_id"], Opening.REGIONAL_FAMILY, "The household retains its own canonical account")
	test.expect(LivelihoodAction.query(normal.world, Opening.PLAYER).get("known_suppliers", []).has(Opening.REGIONAL_FAMILY + "|flour|" + Opening.REGIONAL_FAMILY), "The Paris person actually received the household sale identity through original supplier information")
	test.expect(LivelihoodAction.query_firm(normal.world, Opening.PLAYER, Opening.REGIONAL_FAMILY).is_empty(), "A received sale notice grants no household management, cash or stock access")
	# A tools-supply shock, not an assumption that NPCs cannot discover the
	# other tool producer over the real network. Both original plants use their
	# own legal operating action; no existing tool lot or reservation is removed.
	for suffix: String in ["1", "2"]:
		var owner := "firm:network:tools" + suffix
		var close: Dictionary = shortage.submit_internal(owner, shortage._auto_command(owner, "set_site_status", {"firm": owner, "site_id": "site:network:tools" + suffix, "enabled": true, "production_enabled": false, "accepting_business": false}, "regional_upstream_tools_shortage"))
		test.expect(close.get("accepted", false), "Existing self-manager action stops new upstream tools at plant " + suffix + "; no inventory is edited")
	var cash := _cash_total(normal.world)
	var steps_ok: bool = true
	var physical_ok: bool = true
	var cash_ok: bool = true
	var rail_control: Dictionary = {"closed": false, "failed": false, "adopted": {}, "fact": {}, "entry_ids": {}}
	var closed_rail: bool = false
	var adopted: Dictionary = {}
	var adopted_fact: Dictionary = {}
	var entry_ids_at_closure: Dictionary = {}
	var entered_cargo_progressed: bool = false
	var retained_adoption: bool = true
	var closure_maintained: bool = true
	var day_times: Dictionary = {"normal": [], "tools_shortage": [], "rail_interrupted": []}
	var worlds: Array[WorldBuildResult] = [normal, tools, rail]
	var labels: Array[String] = ["normal", "tools_shortage", "rail_interrupted"]
	var resumed: WorldBuildResult
	# One extra day only, from the same minute-zero snapshot. Cache policy and
	# counters belong to the derived helper, never to persistent economic state.
	var uncached := FormalPersistence.new().restore_candidate(initial)
	test.expect(uncached.success, "A single cache-off control restores the identical minute-zero formal snapshot: " + uncached.error)
	if not uncached.success:
		test.finish(self, "Regional economic industry integration")
		return
	var uncached_authority := uncached.persistence.snapshot()
	test.expect(uncached_authority == initial, "The cache control also preserves the entire original minute-zero snapshot before its policy switch")
	uncached.world.economy_r1._node_network.cache_enabled = false
	test.expect(uncached.persistence.snapshot() == uncached_authority, "The sole derived cache switch changes no field of its exact pre-switch saved authority")
	var cached_before := economy.query_metrics()
	var uncached_before := uncached.world.economy_r1.query_metrics()
	# All opening equality/restore checks are complete. Retain only scalar byte
	# counts, not minute-zero snapshot copies, throughout the multi-day loop.
	initial = {}
	tools_initial = {}
	rail_initial = {}
	uncached_authority = {}
	for index: int in REGIONAL_DAYS:
		var timings: Dictionary = {}
		for branch: int in worlds.size():
			if branch == 2 and rail_control["failed"]:
				timings[labels[branch]] = null
				day_times[labels[branch]].append(null)
				continue
			var start: int = Time.get_ticks_usec()
			var step: Dictionary
			if branch == 2: step = _advance_regional_rail(worlds[branch], 1440, rail_control)
			else: step = worlds[branch].simulation_step.advance_minutes(1440)
			var elapsed: int = Time.get_ticks_usec() - start
			timings[labels[branch]] = elapsed
			day_times[labels[branch]].append(elapsed)
			steps_ok = steps_ok and bool(step.get("success", true))
			physical_ok = physical_ok and _physical_valid(worlds[branch].world.economy_r1)
			cash_ok = cash_ok and _cash_total(worlds[branch].world) == cash
		if index == 0:
			var uncached_start: int = Time.get_ticks_usec()
			var uncached_step: Dictionary = uncached.simulation_step.advance_minutes(1440)
			var uncached_elapsed: int = Time.get_ticks_usec() - uncached_start
			test.expect(uncached_step.get("success", true), "The cache-off control executes only the same first 1440 minutes")
			var clock_exact: bool = uncached.world.game_clock.snapshot() == normal.world.game_clock.snapshot()
			var native_exact: bool = uncached.world.economy_r1.snapshot() == economy.snapshot()
			var ledger_exact: bool = uncached.world.ledger_state.snapshot() == normal.world.ledger_state.snapshot()
			test.expect(clock_exact and native_exact and ledger_exact, "Cache on/off has exactly the same first-day clock, native orders/transport/production and Ledger money")
			var cached_after := economy.query_metrics()
			var uncached_after := uncached.world.economy_r1.query_metrics()
			var cached_counts: Dictionary = {}
			var uncached_counts: Dictionary = {}
			for counter: String in ["queries", "searches", "hits"]:
				cached_counts[counter] = int(cached_after[counter]) - int(cached_before[counter])
				uncached_counts[counter] = int(uncached_after[counter]) - int(uncached_before[counter])
			print("REGIONAL_CACHE_CONTROL ", JSON.stringify({"minutes": 1440, "extra_control_days": 1, "exact": {"clock": clock_exact, "economy_native": native_exact, "ledger": ledger_exact}, "cache_on_day1_counts": cached_counts, "cache_off_day1_counts": uncached_counts, "cache_on_advance_us": timings["normal"], "cache_off_advance_us": uncached_elapsed, "scope": "ONE_FIRST_DAY_ONLY_DERIVED_CACHE_POLICY_NOT_EXCLUSIVE_PERFORMANCE"}))
			uncached = null
		closed_rail = rail_control["closed"]
		if closed_rail:
			var link_state := _regional_rail_state(interrupted)
			var still_closed: bool = link_state["status"] == VNextInfrastructureLinkState.STATUS_INTERRUPTED and link_state["effective_capacity"] == 0.0
			if closure_maintained and not still_closed:
				test.expect(false, "Spatial rail interruption must persist with zero effective capacity after every subsequent native advance")
				print("REGIONAL_RAIL_UNEXPECTED_STATE ", JSON.stringify({"minute": rail.world.game_clock.total_minutes(), "link": link_state}))
			closure_maintained = closure_maintained and still_closed
			adopted = rail_control["adopted"]
			adopted_fact = rail_control["fact"]
			entry_ids_at_closure = rail_control["entry_ids"]
			retained_adoption = retained_adoption and interrupted._shared.entries.get(adopted["adoption_id"]) == adopted and rail.world.spatial_world.capacity_adoption(adopted["adoption_id"]) == adopted_fact
			var cargo: Dictionary = interrupted._shipments.get(adopted["shipment_id"], {})
			if not cargo.is_empty() and int(cargo["leg_index"]) > int(adopted["leg_index"]): entered_cargo_progressed = true
			for receipt: Dictionary in interrupted._delivery_receipts.values():
				if receipt.get("shipment_id", receipt["id"]) == adopted["shipment_id"]: entered_cargo_progressed = true
		print("REGIONAL_DAY ", JSON.stringify({"day": index + 1, "advance_minutes_1440_us": timings, "normal_records": _regional_history(economy), "tools_shortage_records": _regional_history(shortage), "rail_interrupted_records": _regional_history(interrupted)}))
		if index < 4 or index == REGIONAL_DAYS - 1: _print_regional_family_market(economy)
		if index == 1 and _lyon_shared_case:
			var witnessed: bool = true
			var investment_responded: bool = true
			for pair: Array in [["site:network:coal", "coal"], ["site:network:ore", "iron_ore"]]:
				var fresh_unlinked: bool = false
				var committed: int = 0
				var installed_project: bool = false
				for row: Dictionary in economy._request_window.get(str(pair[0]) + "|" + str(pair[1]), []):
					if row["buyer"] == "site:network:steel2" and int(row["day"]) == 2 and str(row["order_id"]).is_empty(): fresh_unlinked = true
				for order: Dictionary in economy._orders.values():
					if order["kind"] == "SALE" and order["seller_site"] == pair[0] and order["buyer_site"] == "site:network:steel2" and order["good"] == pair[1]: committed += int(order["pending"]) + int(order["transit"])
				for project: Dictionary in economy._capital.projects.values():
					if project["site_id"] == pair[0] and project["kind"] == "INSTALL": installed_project = true
				witnessed = witnessed and fresh_unlinked and committed > 0
				investment_responded = investment_responded and installed_project
			test.expect(witnessed, "The original day-two world has newer unlinked enquiries and older genuinely funded coal/ore obligations, not synthetic demand")
			test.expect(investment_responded, "A newer enquiry cannot erase an eligible self-manager's actual unfulfilled SALE evidence for original capital investment")
		if index + 1 in [9, 10, 12, REGIONAL_DAYS]: _print_regional_pending_maintenance(economy)
		if index == REGIONAL_DAYS - 2:
			var checkpoint := normal.persistence.snapshot()
			resumed = FormalPersistence.new().restore_candidate(checkpoint)
			test.expect(resumed.success, "Day-35 cold restore retains finite deposits, household lots, capital maintenance and responsibilities: " + resumed.error)
			if resumed.success: test.expect(resumed.persistence.snapshot() == checkpoint, "Day-35 formal restore is exact without duplicating history")
		elif index == REGIONAL_DAYS - 1 and resumed != null and resumed.success:
			var next: Dictionary = resumed.simulation_step.advance_minutes(1440)
			test.expect(next.get("success", true), "Cold-restored world advances the same final day, never an extra hidden day")
			test.expect(resumed.world.economy_r1.snapshot() == economy.snapshot() and resumed.world.ledger_state.snapshot() == normal.world.ledger_state.snapshot(), "Repeated final-day execution in the restored world is deterministic with no duplicate extraction, goods, wages or payments")
		if not steps_ok: break
	test.expect(steps_ok and normal.world.game_clock.total_minutes() == REGIONAL_DAYS * 1440 and tools.world.game_clock.total_minutes() == REGIONAL_DAYS * 1440, "Normal and tools-shortage branches finish all 36 days through successful original simulation steps")
	test.expect(not rail_control["failed"] and rail.world.game_clock.total_minutes() == REGIONAL_DAYS * 1440, "The rail branch finishes 36 days only with an actual successful intervention, not an unchanged or abandoned control")
	test.expect(physical_ok and cash_ok, "Every daily boundary conserves per-good source/portions and formal cash in all branches")
	for world: WorldBuildResult in worlds: test.expect(_production_totals_valid(world.world.economy_r1), "Production plus actual installation/maintenance input receipts match per-good site totals")
	for world: WorldBuildResult in worlds:
		test.expect(_planning_delay_projection_exact(world.world.economy_r1), "Planning delay remains exact after 36 days, including original closed-link and shortage paths")
	var market_feedback := _regional_market_feedback(economy)
	test.expect(not market_feedback["received_announcements"].is_empty() and not market_feedback["orders"].is_empty() and market_feedback["all_orders_after_knowledge"], "City market discovery actually precedes household sale contracts through the delayed original inbox")
	test.expect(int(market_feedback["bread_with_household_flour_input"]) > 0, "A city bakery actually consumes the discovered household flour in later bread production")
	print("REGIONAL_CITY_MARKET ", JSON.stringify(market_feedback))
	var actual := _regional_metrics(economy)
	var lacking := _regional_metrics(shortage)
	var delayed := _regional_metrics(interrupted)
	var lyon_normal: Dictionary = {}
	if _lyon_shared_case:
		lyon_normal = _lyon_shared_metrics(economy)
		var lyon_blocked := _lyon_shared_metrics(interrupted)
		test.expect(int(lyon_normal["entries"]) > 0 and lyon_normal["spatial_facts_match"] and int(lyon_normal["lyon_handling_hours_allocated"]) > 0, "The formerly daily-business Lyon rail really adopts original Spatial capacity and earned station work")
		var grain: Dictionary = lyon_normal["example_order"]
		test.expect(int(grain["delivered"]) > 0 and int(grain["goods_paid"]) == int(grain["delivered"]) and int(grain["freight_paid"]) > 0 and int(lyon_normal["lyon_seller_grain_remaining"]) < 160 and int(lyon_normal["paris_mill_grain_consumed"]) > 0, "Actual Lyon grain reaches the Paris mill, reduces the original seller stock, pays goods plus freight and is later consumed")
		test.expect(int(lyon_normal["lyon_zero_cash_worker_wages_paid"]) > 0, "The added handling member starts with no cash and receives the existing carrier's real wages")
		print("REGIONAL_LYON_SHARED_OUTCOME ", JSON.stringify({"interrupted_link": _rail_link, "normal": lyon_normal, "interrupted": lyon_blocked}))
	test.expect(int(actual["family_sources"]) > 0 and int(actual["family_sources"]) <= 8 and actual["family_grain_used"] == int(actual["family_sources"]) * 3 and actual["family_flour_produced"] == int(actual["family_sources"]) * 2, "Finite household flour is backed by its original grain portions and bounded self-work, not regeneration")
	test.expect(int(actual["family_flour_delivered"]) > 0 and actual["family_goods_payments"] == int(actual["family_flour_delivered"]) * 3, "A city buyer actually receives household flour and pays the household's original account")
	if _lyon_shared_case:
		# This is a different declared-capacity input, not the old positive-throughput
		# baseline. A physically missing maintenance tool must not become a repair.
		var mined_steel: bool = false
		for source: Dictionary in economy._lots.sources.values():
			if source["good"] == "steel" and _source_has_mined_input(economy, source["id"], "site:network:coal") and _source_has_mined_input(economy, source["id"], "site:network:ore"): mined_steel = true
		test.expect(int(actual["installations_completed"]) >= 2 and mined_steel and _produced(economy, "site:network:tools1", "tools") > 0 and int(lyon_normal["delivered_using_link_by_good"]["steel"]) > 0 and int(lyon_normal["delivered_using_link_by_good"]["tools"]) > 0, "The new finite mainline has actual installation, mined inputs in steel, manufactured tools and real steel/tool deliveries")
		var waiting_sites: Dictionary = {}
		for project: Dictionary in economy._capital.projects.values():
			var site: String = project["site_id"]
			if project["kind"] == "MAINTENANCE" and project["status"] == "WAITING_RESOURCES" and project["reason"] == "CAPITAL_GOODS_NOT_AT_SITE" and site in ["site:network:coal", "site:network:ore"] and int(economy._stocks[site]["tools"]) == 0 and economy._exposure(site, "tools") == 0: waiting_sites[site] = true
		test.expect(waiting_sites.size() == 2 and int(actual["maintenance_completed"]) == 0 and int(actual["tools_consumed_in_maintenance"]) == 0, "Under the declared shared-capacity shortage both mine repairs really wait for absent tools, with no invented material consumption or completed maintenance")
	else:
		test.expect(int(actual["installations_completed"]) >= 2 and int(actual["maintenance_completed"]) > 0 and actual["mined_coal_ore_to_steel_to_tools_to_maintenance"], "Actual finite coal/ore inputs reach steel, tools and later equipment maintenance through original source lineage")
	test.expect(int(actual["coal_extracted_kg"]) <= 48 and int(actual["ore_extracted_kg"]) <= 72, "In-ground finite estimates cannot become unlimited saleable stock")
	if _lyon_shared_case:
		test.expect(_produced(economy, "site:network:tools1", "tools") > _produced(shortage, "site:network:tools1", "tools") and int(actual["coal_extracted_kg"]) > int(lacking["coal_extracted_kg"]) and int(actual["ore_extracted_kg"]) > int(lacking["ore_extracted_kg"]), "The sole upstream-tools intervention changes actual manufacture and extraction under the same constrained transport, not an asserted successful repair")
	else:
		test.expect(int(actual["coal_extracted_kg"]) > int(lacking["coal_extracted_kg"]) and int(actual["ore_extracted_kg"]) > int(lacking["ore_extracted_kg"]) and int(lacking["maintenance_completed"]) == 0, "Stopping upstream new tools causes real maintenance failure and lower subsequent mine capacity/output")
	test.expect(int(actual["zero_opening_cash_wage_funded_food_consumers"]) > 0, "Residents with no opening cash actually buy and consume bread using paid wages rather than UI allocations")
	test.expect(closed_rail and retained_adoption and entered_cargo_progressed, "An adopted multileg cargo keeps its original capacity fact and progresses beyond the interrupted rail leg")
	var no_new_entries: bool = closed_rail
	var unexpected_entries: Array[Dictionary] = []
	for entry: Dictionary in interrupted._shared.entries.values():
		if entry["edge_id"] in _rail_edges and not entry_ids_at_closure.has(entry["adoption_id"]):
			no_new_entries = false
			if unexpected_entries.size() < 8: unexpected_entries.append(entry)
	var delivery_changed: bool = actual["multileg_delivered_by_good"] != delayed["multileg_delivered_by_good"]
	test.expect(closed_rail and closure_maintained, "Real Spatial rail status remains interrupted with zero effective capacity after native advances")
	test.expect(no_new_entries, "Closed real rail admits no later Shared cargo adoption")
	test.expect(delivery_changed, "The actual multileg delivery outcome changes without a synthetic bypass")
	print("REGIONAL_RAIL_OUTCOME ", JSON.stringify({"closure_maintained": closure_maintained, "no_new_adoptions": no_new_entries, "unexpected_adoptions_first_8": unexpected_entries, "normal_infrastructure": _regional_rail_state(economy), "interrupted_infrastructure": _regional_rail_state(interrupted), "normal_multileg_delivered_by_good": actual["multileg_delivered_by_good"], "interrupted_multileg_delivered_by_good": delayed["multileg_delivered_by_good"], "normal_waiting_on_rail_first_4": _regional_rail_waiting(economy), "interrupted_waiting_on_rail_first_4": _regional_rail_waiting(interrupted)}))
	for world: WorldBuildResult in [tools, rail]:
		var snapshot := world.persistence.snapshot()
		var restored := FormalPersistence.new().restore_candidate(snapshot)
		test.expect(restored.success, "The actual shortage/interrupted branch cold-restores with its original obligations: " + restored.error)
		if restored.success: test.expect(restored.persistence.snapshot() == snapshot, "Cold restore does not duplicate failed requests, capital stages, shipments or payments")
	print("REGIONAL_SUMMARY ", JSON.stringify({"configuration_variant": "LYON_SHARED_FINITE_CAPACITY" if _lyon_shared_case else "ORIGINAL_LYON_LEGACY_CAPACITY", "days": REGIONAL_DAYS, "normal": actual, "tools_shortage": lacking, "rail_interrupted": delayed, "advance_us_by_day": day_times, "timing_scope": "ADVANCE_MINUTES_ONLY_NOT_EXCLUSIVE_GUI_OR_RENDER_PERFORMANCE", "actual_adopted_rail_fact_retained": closed_rail and retained_adoption, "rail_intervention_failed": rail_control["failed"]}))
	var final_save := normal.persistence.snapshot()
	var final_document_bytes: int = JSON.stringify(FormalWorldPersistenceDocument.encode(final_save)).to_utf8_buffer().size()
	var final_native_bytes: int = var_to_bytes(final_save["economy_native"]).size()
	print("REGIONAL_SAVE_GROWTH ", JSON.stringify({"start_minute": initial_sample_minute, "end_minute": final_save["total_minutes"], "exact_document_json_utf8_bytes": {"start": initial_document_bytes, "end": final_document_bytes, "growth": final_document_bytes - initial_document_bytes}, "economy_native_variant_bytes": {"start": initial_native_bytes, "end": final_native_bytes, "growth": final_native_bytes - initial_native_bytes}, "encoding": FormalWorldPersistenceDocument.FORMAT_ID, "scope": "TWO_IN_MEMORY_ORIGINAL_CODEC_SAMPLES_NOT_ACTUAL_DISK_FILE_SIZE", "exact_document_metadata_included": true, "excluded": ["SAVE_TO_USER_UI_SUMMARY", "ATOMIC_TEMPORARY_FILE"]}))
	final_save = {}
	_print_cross_border_trace(economy)
	test.finish(self, "Regional economic industry integration")

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
