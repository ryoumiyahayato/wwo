class_name EconomyNetworkDevelopment
extends RefCounted
## France-only, explicitly selected development opening; never ordinary history.
## Twenty separate companies reuse formal organizations, population, accounts,
## StockLots, orders and GameClock. Cohorts and the carrier are not companies.
## Quantities, cash, recipes, wages, prices, freight and time are finite development
## estimates, not historical rates or a claim of long-term commercial viability.

const CASE_ID: String = "FORMAL_ECONOMIC_NODE_NETWORK_DEVELOPMENT"
const GOODS: Array[String] = ["grain", "flour", "bread", "fiber", "cloth", "clothes", "coal", "iron_ore", "steel", "tools"]
const PLAYER: String = WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
const CHANNEL_EDGE: String = "edge:network:port_le_havre:port_london"
const CLOSURE_EDGE: String = "edge:network:le_havre:port_le_havre"
const NETWORK_OPERATOR: String = "firm:network:mill1"
const PLACES: Array[String] = ["paris", "lyon", "marseille", "rouen", "le_havre", "port_le_havre", "port_london", "london"]

static func request(person_ids: Array[String] = []) -> Dictionary:
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": template()}

static func stock(values: Dictionary = {}) -> Dictionary:
	var result := EconomySliceConfig.zero_stock(GOODS)
	result.merge(values, true)
	return result

static func _process(outputs: Dictionary, rejects: Dictionary, unavailable: String) -> Dictionary:
	var gross := outputs.duplicate(true)
	var waste: Dictionary = {}
	for good: String in outputs:
		waste[good] = int(rejects.get(good, 0))
		gross[good] = int(outputs[good]) + int(waste[good])
	return {"format": "production_process_v1", "technology_id": "technology:network:development_processing", "batch_unit": "development_batch", "source": {"id": "economy_network_development:finite_v1", "basis": "EXPLICIT_DEVELOPMENT_ESTIMATE_NOT_HISTORICAL_RATE", "estimated": true, "hours_unit": "person_hour", "capacity_unit": "capacity_unit_per_eligible_day"}, "gross_outputs": gross, "rejects": waste, "first_day": 1, "cycle_days": 1, "max_batches_per_cycle": 2, "lifetime_batch_limit": 64, "constraints": [] if unavailable.is_empty() else [{"kind": unavailable, "availability": "UNAVAILABLE", "source": "No admitted land, biological renewal or mineral extraction executor; opening raw lots are finite", "unit": "unconfigured"}]}

static func _definitions() -> Array:
	# name, real host place, finite opening stock, posted prices, batch outputs,
	# consumed inputs, unavailable natural-resource constraint.
	var rows: Array = [
		["grain", "lyon", {"grain": 160}, {"grain": 1}, {"grain": 1}, {}, "LAND"],
		["fiber", "lyon", {"fiber": 120}, {"fiber": 2}, {"fiber": 1}, {}, "BIOLOGICAL_CYCLE"],
		["coal", "lyon", {"coal": 120}, {"coal": 2}, {"coal": 1}, {}, "MINERAL_DEPOSIT"],
		["ore", "lyon", {"iron_ore": 120}, {"iron_ore": 2}, {"iron_ore": 1}, {}, "MINERAL_DEPOSIT"]]
	for index: int in range(1, 3):
		var suffix := str(index)
		var overseas := index == 2
		rows.append_array([
			["mill" + suffix, "port_london" if overseas else "paris", {}, {"flour": 4}, {"flour": 2}, {"grain": 3}, ""],
			["bakery" + suffix, "london" if overseas else "paris", {}, {"bread": 4}, {"bread": 2}, {"flour": 1}, ""],
			["weave" + suffix, "london" if overseas else "lyon", {}, {"cloth": 5}, {"cloth": 2}, {"fiber": 2}, ""],
			["steel" + suffix, "port_london" if overseas else "lyon", {}, {"steel": 8}, {"steel": 2}, {"coal": 2, "iron_ore": 3}, ""],
			["tools" + suffix, "london" if overseas else "paris", {}, {"tools": 12}, {"tools": 2}, {"steel": 2}, ""],
			["tailor" + suffix, "london" if overseas else "paris", {}, {"clothes": 8}, {"clothes": 2}, {"cloth": 2}, ""],
			["wholesale" + suffix, "port_london" if overseas else "marseille", {}, {"bread": 5, "clothes": 9, "tools": 13}, {}, {}, ""],
			["retail" + suffix, "london" if overseas else "marseille", {}, {"bread": 6, "clothes": 10, "tools": 14}, {}, {}, ""]])
	return rows

static func _supplier_names(name: String) -> Array[String]:
	var suffix := "2" if name.ends_with("2") else "1"
	if name.begins_with("mill"): return ["grain"]
	if name.begins_with("bakery"): return ["mill" + suffix]
	if name.begins_with("weave"): return ["fiber"]
	if name.begins_with("steel"): return ["coal", "ore"]
	if name.begins_with("tools"): return ["steel" + suffix]
	if name.begins_with("tailor"): return ["weave" + suffix]
	if name.begins_with("wholesale"): return ["bakery" + suffix, "tailor" + suffix, "tools" + suffix]
	if name.begins_with("retail"): return ["wholesale" + suffix]
	return []

static func template() -> Dictionary:
	var result: Dictionary = {
		"format": "R2", "case_id": CASE_ID, "host_personal_accounts": true,
		"management_scope": {"id": "scope:economic_node_network_development", "identity_basis": "HOST_WORLD", "business_basis": "DEVELOPMENT_CONFIGURATION", "statistics_visibility": "PUBLIC_AGGREGATES"},
		"actors": [], "firms": [], "jobs": [], "information": [], "goods": [],
		"development_organizations": [], "firm_operations": [], "routes": [], "transport_nodes": [],
		"production_enabled": true, "player_choice": "substitute", "stock_horizon": 2,
		"need_categories": [{"id": "food", "mode": "flow", "priority": 0}, {"id": "clothing", "mode": "durable", "priority": 1}, {"id": "household", "mode": "durable", "priority": 2}],
		"route": {"id": "edge:network:local:paris", "place_id": "place:paris", "capacity": 40, "delay": 1, "basis": "SYNTHETIC"},
		"carriers": [{"id": "carrier:network", "place_id": "place:paris", "account_id": "account:network:carrier", "cash": 0}],
		"cost_accounting": {"freight_treatment": "BUYER_ACQUISITION", "joint_allocations": [], "npc_policies": [], "basis": "EXPLICIT_DEVELOPMENT_COST_POLICY"},
		# No personal unit conversion or runtime free-resource expansion is implied.
		"commodity_mappings": [], "runtime_expansions": [], "firm_management_permissions": [],
		"place_population_bindings": []}
	for place: String in ["london", "port_london"]:
		result["place_population_bindings"].append({"place_id": "place:" + place, "population_unit_id": "british_isles_1900", "source": FormalWorldEconomicEvidenceCatalog.WORLD_MANIFEST_PATH, "basis": "DEVELOPMENT_PLACE_POPULATION_CROSSWALK", "scope_assumption": "LONDON_MAINLAND_PLACES_WITHIN_BRITISH_ISLES_STATISTICAL_SCOPE_ONLY"})
	for good: String in GOODS:
		var bulk := good in ["grain", "flour", "fiber", "coal", "iron_ore", "steel"]
		result["goods"].append({"id": good, "needs": {"food": 1} if good == "bread" else {"clothing": 1} if good in ["cloth", "clothes"] else {"household": 1} if good == "tools" else {}, "unit_id": "development_kg" if bulk else "development_m" if good == "cloth" else "development_piece", "unit_name_zh": "千克（开发口径）" if bulk else "米（开发口径）" if good == "cloth" else "件（开发口径）"})
	# Existing legal France player, with no extra cash or opening property. The
	# regional resolver gives only the first company's real management appointment.
	result["actors"].append({"id": PLAYER, "kind": "named", "control": "player", "members": 1, "account_id": FormalPersonalEconomyState.personal_account_id(PLAYER), "cash": 0, "stock": stock(), "skill": 1, "daily_need": 2, "needs": {"food": 2, "clothing": 1, "household": 1}, "population_start": 0, "place_id": "place:paris", "population_unit_id": "country_fra"})
	var definitions := _definitions()
	var population_starts: Dictionary = {"country_fra": 0, "british_isles_1900": 0}
	for definition: Array in definitions:
		var name: String = definition[0]
		var place := "place:" + str(definition[1])
		var firm := "firm:network:" + name
		var site := "site:network:" + name
		var organization := "organization:development_network_" + name
		var outputs: Dictionary = definition[4]
		var inputs: Dictionary = definition[5]
		var unavailable: String = definition[6]
		var activities: Array = []
		if not outputs.is_empty():
			activities.append({"id": "activity:network:" + name, "place_id": place, "outputs": outputs.duplicate(), "materials": stock(inputs), "hours": 2, "capacity_units": 1, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION", "process": _process(outputs, {"flour": 1} if name.begins_with("mill") else {}, unavailable)})
		var targets: Dictionary = {}
		for good: String in definition[3]: targets[good] = 4 if unavailable.is_empty() else 0
		var suppliers: Array[String] = []
		for other: Array in definitions:
			if str(other[0]) not in _supplier_names(name): continue
			for good: String in other[3]:
				var candidate := "firm:network:" + str(other[0]) + "|" + good + "|site:network:" + str(other[0])
				suppliers.append(candidate)
				result["information"].append({"actor": site, "kind": "supplier", "candidate": candidate, "delivery_day": 0})
		var row: Dictionary = {"id": site, "place_id": place, "roles": ["production", "storage", "sales"] if not activities.is_empty() else ["storage", "sales"], "stock": stock(definition[2]), "capacity": 2 if not activities.is_empty() else 0, "targets": stock(targets), "prices": definition[3].duplicate(), "activities": activities, "suppliers": suppliers, "enabled": true, "production_enabled": true, "accepting_business": true, "basis": "DEVELOPMENT_CONFIGURATION", "coordination_delay": 0}
		var company: Dictionary = {"id": firm, "place_id": place, "account_id": "account:network:" + name, "cash": 360, "host_organization_id": organization, "sites": [row]}
		if name == "mill1": company["manager"] = PLAYER # Actual host appointment, not global financial access.
		result["firms"].append(company)
		result["development_organizations"].append({"organization_id": organization, "firm_id": firm, "basis": "EXPLICIT_DEVELOPMENT_COMMERCIAL_ORGANIZATION"})
		result["firm_operations"].append({"firm": firm, "planning_horizon": 3, "buffer_days": 1, "demand_window": 7, "manage_jobs": false})
		if inputs.is_empty(): continue
		var unit := "british_isles_1900" if str(definition[1]) in ["london", "port_london"] else "country_fra"
		var worker := "cohort:network:" + name
		var job := "job:network:" + name
		result["actors"].append({"id": worker, "kind": "cohort", "control": "automatic", "members": 1, "account_id": "account:worker:" + name, "cash": 60, "stock": stock(), "skill": 1, "daily_need": 1, "needs": {"food": 1, "clothing": 1, "household": 1}, "population_start": int(population_starts[unit]), "place_id": place, "population_unit_id": unit})
		population_starts[unit] = int(population_starts[unit]) + 1
		result["jobs"].append({"id": job, "employer": firm, "site_id": site, "positions": 1, "skill": 1, "hours": 4, "place": place, "wage_per_hour": 1, "wage_delay": 1})
		result["information"].append({"actor": worker, "kind": "job", "candidate": job, "delivery_day": 0})
	_install_channel_transport(result, population_starts)
	# Consumers know actual posted local shops, or an explicit domestic regional
	# supplier where no local retailer exists. No consumer scans the whole world.
	for actor: Dictionary in result["actors"]:
		for definition: Array in definitions:
			var name: String = definition[0]
			var destination: String = actor["place_id"]
			var local: bool = "place:" + str(definition[1]) == destination
			var regional: bool = destination in ["place:lyon", "place:port_le_havre"] and name in ["bakery1", "tailor1", "tools1"]
			var port_shop: bool = destination == "place:port_london" and name == "retail2"
			# The player's bounded published directory lists all twenty businesses;
			# this grants identity/quote knowledge, never another company's accounts.
			if actor["id"] != PLAYER and not local and not regional and not port_shop: continue
			for good: String in definition[3]:
				result["information"].append({"actor": actor["id"], "kind": "supplier", "candidate": "firm:network:" + name + "|" + good + "|site:network:" + name, "delivery_day": 0})
	var firms: Array[String] = []
	for firm: Dictionary in result["firms"]: firms.append(firm["id"])
	var business_known := firms.duplicate()
	business_known.append(PLAYER)
	for place: String in PLACES:
		result["transport_nodes"].append({"place_id": "place:" + place, "capacity": 40})
		if place == "paris": continue
		var local_known := business_known.duplicate()
		for actor: Dictionary in result["actors"]:
			if actor["kind"] == "cohort" and actor["place_id"] == "place:" + place: local_known.append(actor["id"])
		result["routes"].append({"id": "edge:network:local:" + place, "from_place_id": "place:" + place, "to_place_id": "place:" + place, "capacity": 40, "delay": 1, "carrier": "carrier:network", "freight_per_unit": 0, "known_to": local_known, "basis": "SYNTHETIC"})
	# Every nonlocal link is either an actual catalog link or a labelled limited
	# development city/port access permission. No invented historical railway.
	for link: Array in [["paris", "lyon", "rail_paris_lyon"], ["lyon", "marseille", "rail_lyon_marseille"], ["paris", "rouen", "rail_paris_rouen"], ["rouen", "le_havre", "rail_rouen_le_havre"], ["port_le_havre", "port_london", "shipping_channel"], ["le_havre", "port_le_havre", ""], ["port_london", "london", ""]]:
		for reverse: bool in [false, true]:
			var origin: String = link[1] if reverse else link[0]
			var destination: String = link[0] if reverse else link[1]
			var known := business_known.duplicate()
			# Finite announced routes to their actual known consumer suppliers.
			for actor: Dictionary in result["actors"]:
				if actor["kind"] != "cohort": continue
				var lyon_supply: bool = actor["place_id"] == "place:lyon" and str(link[2]) == "rail_paris_lyon"
				var havre_supply: bool = actor["place_id"] == "place:port_le_havre" and (str(link[2]) in ["rail_paris_rouen", "rail_rouen_le_havre"] or (str(link[2]).is_empty() and str(link[0]) == "le_havre"))
				var london_supply: bool = actor["place_id"] == "place:port_london" and str(link[2]).is_empty() and str(link[0]) == "port_london"
				if lyon_supply or havre_supply or london_supply: known.append(actor["id"])
			var edge: Dictionary = {"id": "edge:network:" + origin + ":" + destination, "from_place_id": "place:" + origin, "to_place_id": "place:" + destination, "capacity": 20, "delay": 1, "carrier": "carrier:network", "freight_per_unit": 1, "known_to": known, "capacity_manager": NETWORK_OPERATOR, "basis": "HOST_LINK" if not str(link[2]).is_empty() else "DEVELOPMENT_PERMISSION"}
			if not str(link[2]).is_empty(): edge["source_link_id"] = link[2]
			else: edge["source_permission_id"] = "development_permission:network:" + ("le_havre_port_access" if "le_havre" in [origin, destination] else "london_port_access")
			if str(link[2]) == "shipping_channel": edge["carrier"] = "firm:network:wholesale2" if reverse else "firm:network:wholesale1"
			result["routes"].append(edge)
	_bind_channel_edges(result)
	return result

## Only the Channel leg is adopted into Spatial's actual capacity. Other catalog
## legs retain explicitly limited legacy daily BUSINESS quantities, not physical
## railway capacity. City/port access remains a labelled development permission.
## Existing wholesale firms provide the service; no twenty-first company or free
## worker is created. Their wages and handling consume their original finite cash.
static func _install_channel_transport(result: Dictionary, population_starts: Dictionary) -> void:
	var origin_site := "site:network:wholesale1:le_havre_port"
	for firm: Dictionary in result["firms"]:
		if firm["id"] != "firm:network:wholesale1": continue
		firm["sites"].append({"id": origin_site, "place_id": "place:port_le_havre", "roles": ["storage"], "stock": stock(), "capacity": 0, "targets": stock(), "prices": {}, "activities": [], "suppliers": [], "enabled": true, "production_enabled": false, "accepting_business": true, "basis": "DEVELOPMENT_CONFIGURATION", "coordination_delay": 0})
	for port: Dictionary in [{"name": "le_havre_port", "firm": "firm:network:wholesale1", "site": origin_site, "place": "place:port_le_havre", "unit": "country_fra"}, {"name": "london_port", "firm": "firm:network:wholesale2", "site": "site:network:wholesale2", "place": "place:port_london", "unit": "british_isles_1900"}]:
		var worker := "cohort:network:handling:" + str(port["name"])
		var job := "job:network:handling:" + str(port["name"])
		result["actors"].append({"id": worker, "kind": "cohort", "control": "automatic", "members": 1, "account_id": "account:network:handling:" + str(port["name"]), "cash": 60, "stock": stock(), "skill": 1, "daily_need": 1, "needs": {"food": 1, "clothing": 1, "household": 1}, "population_start": int(population_starts[port["unit"]]), "place_id": port["place"], "population_unit_id": port["unit"]})
		population_starts[port["unit"]] = int(population_starts[port["unit"]]) + 1
		result["jobs"].append({"id": job, "employer": port["firm"], "site_id": port["site"], "positions": 1, "skill": 1, "hours": 8, "place": port["place"], "wage_per_hour": 1, "wage_delay": 1})
		result["information"].append({"actor": worker, "kind": "job", "candidate": job, "delivery_day": 0})
	var starts: Array[int] = []
	for day: int in range(0, 61):
		starts.append(day * 1440)
		starts.append(day * 1440 + 720)
	var unit := "development_channel_payload_unit"
	for good: Dictionary in result["goods"]:
		good["unit_weight"] = {"numerator": 1, "denominator": 1, "unit": unit, "basis": "EXPLICIT_DEVELOPMENT_PAYLOAD_ESTIMATE_NOT_HISTORICAL_MASS"}
	result["transport_facilities"] = []
	result["shared_transport"] = []
	for site: String in [origin_site, "site:network:wholesale2"]:
		for kind: String in ["HANDLING_THROUGHPUT", "BERTH_OCCUPANCY", "STORAGE_OCCUPANCY"]:
			var windows: Array[Dictionary] = []
			if kind == "HANDLING_THROUGHPUT":
				for start: int in starts: windows.append({"start_minute": start, "end_minute": start + 60, "capacity": 8})
			else: windows.append({"start_minute": 0, "end_minute": 90 * 1440, "capacity": 16 if kind == "STORAGE_OCCUPANCY" else 8})
			result["transport_facilities"].append({"id": "facility:network:" + site + ":" + kind, "site_id": site, "kind": kind, "unit": unit, "windows": windows, "basis": "EXPLICIT_DEVELOPMENT_TRANSPORT_FACILITY"})

static func _bind_channel_edges(result: Dictionary) -> void:
	var starts: Array[int] = []
	for day: int in range(0, 61):
		starts.append(day * 1440)
		starts.append(day * 1440 + 720)
	for edge: Dictionary in result["routes"]:
		if edge.get("source_link_id") != "shipping_channel": continue
		var origin := "site:network:wholesale1:le_havre_port" if edge["from_place_id"] == "place:port_le_havre" else "site:network:wholesale2"
		var destination := "site:network:wholesale2" if edge["to_place_id"] == "place:port_london" else "site:network:wholesale1:le_havre_port"
		var resources: Dictionary = {"unloading_minutes": 60, "unloading_hours_per_unit": 1}
		for key: String in ["origin_handling", "origin_berth", "destination_handling", "destination_berth", "destination_storage"]:
			var site := origin if key.begins_with("origin") else destination
			var kind := "HANDLING_THROUGHPUT" if key.ends_with("handling") else "BERTH_OCCUPANCY" if key.ends_with("berth") else "STORAGE_OCCUPANCY"
			resources[key] = "facility:network:" + site + ":" + kind
		result["shared_transport"].append({"edge_id": edge["id"], "source_link_id": "shipping_channel", "entry_minutes": starts.duplicate(), "weight_unit": "development_channel_payload_unit", "vehicle_id": "vehicle:network:finite_channel_ship", "vehicle_payload": 8, "handling_site": origin, "handling_hours_per_unit": 1, "basis": "EXPLICIT_DEVELOPMENT_SHARED_CHANNEL_CAPACITY", "window_minutes": 60, "loading_minutes": 60, "travel_minutes": 660, "vehicle_hold_minutes": 780, "node_resources": resources, "legacy_node_limit_basis": "EXPLICIT_DAILY_BUSINESS_QUANTITY_LIMIT"})
