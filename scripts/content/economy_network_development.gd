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
const REGIONAL_CASE_ID: String = "FORMAL_ECONOMIC_REGIONAL_INDUSTRY_DEVELOPMENT"
const REGIONAL_FAMILY: String = "cohort:regional:rouen_miller"
const REGIONAL_RAIL_LINK: String = "rail_paris_rouen"
const REGIONAL_PAYLOAD_UNIT: String = "development_transport_payload_unit"
const REGIONAL_RAIL_EDGES: Array[String] = ["edge:network:paris:rouen", "edge:network:rouen:paris"]
const REGIONAL_LYON_RAIL_LINK: String = "rail_paris_lyon"
const REGIONAL_LYON_RAIL_EDGES: Array[String] = ["edge:network:paris:lyon", "edge:network:lyon:paris"]

static func request(person_ids: Array[String] = []) -> Dictionary:
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": template()}

static func stock(values: Dictionary = {}) -> Dictionary:
	var result := EconomySliceConfig.zero_stock(GOODS)
	result.merge(values, true)
	return result

## Small resource/market selection in the SAME WorldBootstrap. No alternate runtime.
static func resource_request(households_only: bool = false) -> Dictionary:
	var base: Dictionary = template()
	var result: Dictionary = {}
	for key: String in ["format", "host_personal_accounts", "management_scope", "goods", "need_categories", "route", "carriers", "production_enabled", "player_choice", "stock_horizon", "cost_accounting"]: result[key] = base[key].duplicate(true) if base[key] is Array or base[key] is Dictionary else base[key]
	result["case_id"] = "FORMAL_RESOURCE_MARKET_PILOT"
	result["management_scope"]["id"] = "scope:formal_resource_market_pilot"
	var selected: Array[String] = ["firm:network:grain", "firm:network:mill1", "firm:network:bakery1"]
	for key: String in ["actors", "firms", "jobs", "information", "development_organizations", "firm_operations", "routes", "transport_nodes"]: result[key] = []
	for row: Dictionary in base["firms"]:
		if row["id"] not in selected: continue
		row["sites"][0]["suppliers"] = []
		row["manager"] = row["id"]
		if row["id"] == "firm:network:mill1":
			row["manager"] = PLAYER
			row["cash"] = 600 # Finite pilot working capital, never an automatic solvency guarantee.
			row["sites"][0]["activities"][0]["materials"]["coal"] = 1 # Explicit steam-milling recipe assumption.
		for activity: Dictionary in row["sites"][0]["activities"]: activity["hours"] = 1
		if row["id"] == "firm:network:grain":
			row["sites"][0]["activities"] = []
			row["sites"][0]["capacity"] = 0
			row["sites"][0]["stock"] = stock({"grain": 24})
			row["sites"][0]["prices"]["grain"] = 5
		result["firms"].append(row)
	for key: String in ["jobs", "development_organizations", "firm_operations"]:
		for row: Dictionary in base[key]:
			if row.get("employer", row.get("firm_id", row.get("firm", ""))) in selected:
				if key == "firm_operations": row["manage_jobs"] = true
				if key == "jobs": row["hours"] = 1
				result[key].append(row)
	for row: Dictionary in base["actors"]:
		if row["id"] in [PLAYER, "cohort:network:mill1", "cohort:network:bakery1"]:
			row["daily_need"] = 1
			row["needs"] = {"food": 1, "clothing": 0, "household": 0}
			if row["kind"] == "cohort": row["cohort_profile"] = {"stratum_id": "wage_workers", "label": "加工雇员", "occupation": "processing", "labor_members": 1, "max_jobs": 1, "job_ids": ["job:network:" + str(row["id"]).trim_prefix("cohort:network:")], "job_search_days": 7, "basis": "EXPLICIT_DEVELOPMENT_COHORT_STRATUM", "need_rates": {"food": {"numerator": 1, "denominator": 10}}}
			result["actors"].append(row)
	for row: Dictionary in base["transport_nodes"]:
		if row["place_id"] in ["place:paris", "place:rouen", "place:lyon"]: result["transport_nodes"].append(row)
	var receivers: Array[String] = [PLAYER, "firm:network:grain", "firm:network:mill1", "firm:network:bakery1", "cohort:resource:farm", "cohort:resource:mine", "cohort:network:mill1", "cohort:network:bakery1"]
	for row: Dictionary in base["routes"]:
		if row["from_place_id"] in ["place:paris", "place:rouen", "place:lyon"] and row["to_place_id"] in ["place:paris", "place:rouen", "place:lyon"]:
			row["known_to"] = receivers.duplicate()
			row["capacity_manager"] = NETWORK_OPERATOR
			result["routes"].append(row)
	var data: Dictionary = FormalEconomicOpening._integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/land/economic_resources_france_pilot.json")))
	result["resource_producers"] = []
	for index: int in data["resources"].size():
		var r: Dictionary = data["resources"][index]
		var actor: String = "cohort:resource:farm" if index == 0 else "cohort:resource:mine"
		var good: String = "grain" if index == 0 else "coal"
		result["actors"].append({"id": actor, "kind": "cohort", "control": "automatic", "members": 2, "account_id": "account:" + actor, "cash": 60, "stock": stock({"grain": 32} if index == 0 else {}), "skill": 1, "daily_need": 1, "needs": {"food": 1, "clothing": 0, "household": 0}, "population_start": 100 + index * 2, "place_id": r["place_id"], "population_unit_id": "country_fra", "cohort_profile": {"stratum_id": "self_employed", "label": "资源生产家庭", "occupation": good, "labor_members": 2, "max_jobs": 1, "job_ids": [], "job_search_days": 7, "basis": "EXPLICIT_DEVELOPMENT_COHORT_STRATUM", "need_rates": {"food": {"numerator": 1, "denominator": 50}}}})
		result["resource_producers"].append({"actor": actor, "good": good, "price": 3 if index == 0 else 2, "resource": r})
	for good: Dictionary in result["goods"]:
		if good["id"] == "grain": good["needs"] = {"food": 1}
	# All notices remain original delayed supplier messages; no global supplier scan.
	for observer: String in receivers:
		var receiver: String = "site:network:" + observer.trim_prefix("firm:network:") if observer.begins_with("firm:network:") else observer
		for pair: Array in [["cohort:resource:farm", "grain", "cohort:resource:farm"], ["cohort:resource:mine", "coal", "cohort:resource:mine"], ["firm:network:grain", "grain", "site:network:grain"], ["firm:network:mill1", "flour", "site:network:mill1"], ["firm:network:bakery1", "bread", "site:network:bakery1"]]:
			if observer != pair[0]:
				var candidate: String = "|".join(pair)
				result["information"].append({"actor": receiver, "kind": "supplier", "candidate": candidate, "delivery_day": 0})
				for firm: Dictionary in result["firms"]:
					if firm["id"] == observer: firm["sites"][0]["suppliers"].append(candidate)
	for row: Dictionary in result["jobs"]:
		result["information"].append({"actor": "cohort:network:" + str(row["id"]).trim_prefix("job:network:"), "kind": "job", "candidate": row["id"], "delivery_day": 0})
	result["unified_market"] = {"period_days": 7, "request_days": 14, "eta_permille": 50, "damping_permille": 500, "deadband_permille": 100, "maximum_price": 1000000}
	if households_only:
		for key: String in ["firms", "jobs", "development_organizations", "firm_operations"]: result[key] = []
		var ids: Array = [PLAYER, "cohort:resource:farm", "cohort:resource:mine"]
		result["actors"] = result["actors"].filter(func(row: Dictionary) -> bool: return row["id"] in ids)
		result["information"] = result["information"].filter(func(row: Dictionary) -> bool: return row["actor"] in ids and row["kind"] == "supplier" and str(row["candidate"]).get_slice("|", 0) in ids)
		for row: Dictionary in result["routes"]:
			row["known_to"] = ids.duplicate()
			row.erase("capacity_manager")
	return {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": true, "configuration": result}

## Opt-in quantities for CPU scale comparisons. No historical calibration or
## runtime grant. The original resource_request and its opening remain intact.
static func resource_scale_request(scale: int, scenario: String = "balanced") -> Dictionary:
	var request: Dictionary = resource_request()
	var cfg: Dictionary = request["configuration"]
	var supply: int = 2 if scenario == "surplus" else 1
	var population: int = 10 if scenario == "shortage" else 1
	var cursor: int = 100
	for actor: Dictionary in cfg["actors"]:
		if actor["kind"] != "cohort": continue
		var households: int = 1 if actor["id"] == "cohort:resource:farm" else population
		actor["members"] *= scale * households
		actor["population_start"] = cursor
		cursor += int(actor["members"])
		actor["cash"] *= scale * households
		actor["cohort_profile"]["labor_members"] *= scale
		for good: String in actor["stock"]: actor["stock"][good] *= scale
		if actor["id"] == "cohort:resource:farm": actor["stock"]["grain"] += 20 * scale * (supply - 1)
	for row: Dictionary in cfg["resource_producers"]:
		var resource: Dictionary = row["resource"]
		if resource["kind"] == "crop":
			resource["land_units"] *= scale * supply
			resource["food_reserve"] *= scale
		else:
			for key: String in ["geological_quantity", "discovered_quantity", "units_per_day"]: resource[key] *= scale
			for event: Dictionary in resource["discovery"]: event["quantity"] *= scale
	for firm: Dictionary in cfg["firms"]:
		firm["cash"] *= scale
		for site: Dictionary in firm["sites"]:
			site["capacity"] *= scale
			for good: String in site["stock"]: site["stock"][good] *= scale
			for good: String in site["targets"]: site["targets"][good] *= scale
			# The control merchant only liquidates opening grain (target zero).
			# This explicit revolving-stock target permits funded resale, not supply.
			if firm["id"] == "firm:network:grain": site["targets"]["grain"] = 4 * scale
			for activity: Dictionary in site["activities"]:
				activity["process"]["max_batches_per_cycle"] *= scale
				activity["process"]["lifetime_batch_limit"] *= scale
	for job: Dictionary in cfg["jobs"]: job["positions"] *= scale
	var transport: int = maxi(1, scale / 100) if scenario == "bottleneck" else scale
	cfg["route"]["capacity"] *= transport
	for edge: Dictionary in cfg["routes"]: edge["capacity"] *= transport
	for node: Dictionary in cfg["transport_nodes"]: node["capacity"] *= transport
	return request

## Proportion/household experiment in the same Formal world. Old scale controls
## remain unchanged. Basket and operating assumptions are in the resource book.
static func resource_cycle_request(scale: int = 100, scenario: String = "normal") -> Dictionary:
	var request: Dictionary = resource_scale_request(scale)
	var cfg: Dictionary = request["configuration"]
	for category: Dictionary in cfg["need_categories"]:
		if category["id"] != "food": category["priority"] += 1
	cfg["need_categories"].append({"id": "fuel", "mode": "flow", "priority": 1})
	for good: Dictionary in cfg["goods"]:
		if good["id"] in ["grain", "flour"]: good["needs"] = {"food": 1000}
		if good["id"] == "bread": good["needs"] = {"food": 500}
		if good["id"] == "coal": good["needs"] = {"fuel": 25}
	var cursor: int = 100
	for actor: Dictionary in cfg["actors"]:
		actor["needs"] = {"food": 500, "fuel": 10, "clothing": 0, "household": 0}
		actor["daily_need"] = 500
		if actor["kind"] != "cohort": continue
		var farm: bool = actor["id"] == "cohort:resource:farm"
		var mine: bool = actor["id"] == "cohort:resource:mine"
		if mine: actor["needs"]["food"] = 600; actor["daily_need"] = 600
		actor["members"] = scale / (5 if farm else 10 if mine else 20)
		actor["population_start"] = cursor; cursor += int(actor["members"])
		actor["cash"] = int(actor["members"]) * (30 if farm or mine else 60)
		var profile: Dictionary = actor["cohort_profile"]
		profile["labor_members"] = actor["members"]
		profile["need_rates"] = {"food": {"numerator": 600 if mine else 500, "denominator": 1}, "fuel": {"numerator": 10, "denominator": 1}}
		profile["category_priority"] = ["food", "fuel"]
		if not farm and not mine: profile["goods_preference"] = {"food": ["bread", "flour", "grain"]}
	for row: Dictionary in cfg["resource_producers"]:
		var r: Dictionary = row["resource"]
		if r["kind"] == "crop":
			# Re-group the same area/seed/yield into 0.1ha capacity units. Work
			# rates are declared developer estimates, not measured 1900 labor.
			r["land_units"] /= 10; r["land_unit_m2"] *= 10
			r["seed_per_unit"] *= 10; r["yield_per_unit"] *= 10
			if scenario == "supply": r["weather_by_year_permille"]["1901"] = 500
		else:
			row["price"] = 4
			row["stock_cover_days"] = 7 if scenario == "adjusted" else 14
	for firm: Dictionary in cfg["firms"]:
		firm["cash"] /= 20
		firm["manager"] = firm["id"]
		for site: Dictionary in firm["sites"]:
			for good: String in site["targets"]: site["targets"][good] /= 10
			for activity: Dictionary in site["activities"]:
				if firm["id"] == "firm:network:mill1":
					activity["materials"]["grain"] = 5; activity["outputs"]["flour"] = 4
					activity["process"]["gross_outputs"]["flour"] = 5
				else:
					activity["materials"]["flour"] = 5; activity["materials"]["coal"] = 1
					activity["outputs"]["bread"] = 10; activity["hours"] = 2
					activity["process"]["gross_outputs"]["bread"] = 10
	for job: Dictionary in cfg["jobs"]:
		job["positions"] = scale / 20; job["wage_per_hour"] = 8
	for policy: Dictionary in cfg["firm_operations"]:
		if policy["firm"] == "firm:network:grain":
			policy["sales_cover_days"] = 7 if scenario == "adjusted" else 14
			policy["resale_margin_permille"] = 100 if scenario == "adjusted" else 0
		elif scenario == "adjusted": policy["demand_shifts"] = true
	cfg["labor_response_policies"] = []
	for actor: Dictionary in cfg["actors"]:
		if actor["id"].begins_with("cohort:network:"): cfg["labor_response_policies"].append({"actor": actor["id"], "arrears_days": 7, "basis": "EXPLICIT_DEVELOPMENT_LABOR_RESPONSE"})
	return request

## Explicit new opening, never an asset conversion or a reinterpretation of saves.
## Paris references applied to this finite France slice; regional prices, opening
## wealth and eight-hour normalization remain declared development assumptions.
static func resource_franc_request(reserve: bool = false) -> Dictionary:
	var request: Dictionary = resource_cycle_request(100, "normal")
	var cfg: Dictionary = request["configuration"]
	cfg["case_id"] = "FORMAL_FRANCE_1900_CENTIME_REFERENCE"
	cfg["settlement_currency"] = FormalLedgerState.FRANC_1900
	cfg["currency_accounts"] = []
	for key: String in ["actors", "firms", "carriers"]:
		for subject: Dictionary in cfg.get(key, []):
			cfg["currency_accounts"].append({"owner": subject["id"], "account_id": "account:franc1900:" + str(subject["id"]), "denomination": FormalLedgerState.FRANC_1900, "cash": int(subject["cash"]) * 20})
			subject["cash"] = 0
	for firm: Dictionary in cfg["firms"]:
		firm["denomination"] = FormalLedgerState.FRANC_1900
		for site: Dictionary in firm["sites"]:
			for good: String in site["prices"]:
				site["prices"][good] = {"grain": 19, "flour": 37, "bread": 22, "coal": 6}.get(good, int(site["prices"][good]) * 20)
	for job: Dictionary in cfg["jobs"]:
		job["denomination"] = FormalLedgerState.FRANC_1900
		job["wage_per_hour"] = 45 # 3.60 Fr / normalized 8h; not guaranteed daily work.
	for row: Dictionary in cfg["resource_producers"]:
		row["price"] = 19 if row["good"] == "grain" else 6
		if row["resource"]["kind"] == "crop":
			if reserve: row["seasonal_reserve"] = true
		else:
			# 466c/day / 8h * original 2h/kg = 116.5c/kg, rounded up.
			row["resource"]["economic_cost"] = 117
	# One centime per original route unit is an explicit freight assumption.
	return request

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
	# Two actual local vacancies are public knowledge, not a job or management grant.
	for job: Dictionary in result["jobs"]:
		if job["place"] == "place:paris" and job["id"] in ["job:network:bakery1", "job:network:tools1"]:
			result["information"].append({"actor": PLAYER, "kind": "job", "candidate": job["id"], "delivery_day": 0})
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

## Separate opt-in regional case. The original template/request and saved native
## configurations above are never rewritten or upgraded by selecting this case.
static func regional_request(person_ids: Array[String] = [], lyon_shared: bool = true, numeric_rouen: bool = true) -> Dictionary:
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": regional_template(lyon_shared,numeric_rouen)}

static func add_warehouse_pilot(result: Dictionary) -> void:
	# One explicit lease pool per existing handling site. Grain/flour and bread
	# occupy the same declared payload units as freight.
	var market := {"facilities":[],"offers":[],"authorities":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_SERVICE_MARKET"}
	result["service_market"] = market
	var nodes: Array[Dictionary] = [
		{"key":"paris","site":"site:regional:station:paris","provider":"firm:network:wholesale1","job":"job:regional:station:paris",
			"clients":["firm:network:mill1","firm:network:bakery1"],"shared":"facility:regional:site:regional:station:paris:STORAGE_OCCUPANCY",
			"unit":REGIONAL_PAYLOAD_UNIT,"capacity":8,"price":2,"bread":[75,165],"grain":[4,12]},
		{"key":"london","site":"site:network:wholesale2","provider":"firm:network:wholesale2","job":"job:network:handling:london_port",
			"clients":["firm:network:mill2"],"shared":"facility:network:site:network:wholesale2:STORAGE_OCCUPANCY",
			"unit":REGIONAL_PAYLOAD_UNIT,"capacity":16,"price":1,"bread":[115,210],"grain":[8,22]},
	]
	for node: Dictionary in nodes:
		var facility := "facility:warehouse:"+str(node["key"])
		var offer := "service_offer:warehouse:"+str(node["key"])
		var provider: String = node["provider"]
		var currency := FormalLedgerState.DENOMINATION
		var spoilage: Dictionary = {}
		for good: String in ["grain","flour","bread"]:
			var rates: Array = node["bread"] if good=="bread" else node["grain"]
			spoilage[good] = {"staffed":rates[0],"unstaffed":rates[1]}
		market["facilities"].append({"id":facility,"provider":provider,"site_id":node["site"],"kind":"STORAGE",
			"capacity":node["capacity"],"unit":node["unit"],"good_units":{"grain":1,"flour":1,"bread":1},"shared_storage_id":node["shared"],
			"basis":"EXPLICIT_DEVELOPMENT_SERVICE_FACILITY","spoilage":spoilage})
		var known: Array = node["clients"].duplicate()
		if node["key"]=="london": known.append("firm:network:mill1") # Published terms, not remote deposit authority.
		market["offers"].append({"id":offer,"facility_id":facility,"kind":"STORAGE","denomination":currency,"price":node["price"],
			"valid_from":0,"valid_until":60*1440,"known_to":known,"notice_minute":0,"job_ids":[node["job"]],"hours_per_day":2,
			"cancel_rule":"UNSTARTED_REPAIR_OR_STORAGE_RETURN","basis":"EXPLICIT_DEVELOPMENT_SERVICE_OFFER",
			"storage_terms":{"period_minutes":1440,"max_periods":30,"intake_hours":1,"supervision_hours":1,"charge_rule":"CUMULATIVE_UNIT_MINUTES_FLOOR"}})
		for firm: String in [provider]+node["clients"]:
			var operations: Array[String] = ["supply" if firm==provider else "purchase","control"]
			market["authorities"].append({"id":"service_authority:warehouse:"+firm,"firm":firm,"controller":PLAYER if firm=="firm:network:mill1" else firm,
				"operations":operations,"denomination":currency,"limit":480,"start_minute":0,"end_minute":60*1440,
				"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_SERVICE_AUTHORITY"})

static func regional_template(lyon_shared: bool = true, numeric_rouen: bool = false) -> Dictionary:
	var result := template()
	result["case_id"] = REGIONAL_CASE_ID
	result["management_scope"]["id"] = "scope:economic_regional_industry_development"
	# One declared payload estimate works on both admitted rail and sea bindings.
	# It is not historical tonnage, nor a conversion of the unlike goods units.
	for good: Dictionary in result["goods"]:
		good["unit_weight"]["unit"] = REGIONAL_PAYLOAD_UNIT
		if good["id"] == "tools": good["capital_uses"] = ["INSTALLABLE_EQUIPMENT", "MAINTENANCE_INPUT"]
		if good["id"] == "steel": good["capital_uses"] = ["INSTALLATION_INPUT", "MAINTENANCE_INPUT"]
	for binding: Dictionary in result["shared_transport"]: binding["weight_unit"] = REGIONAL_PAYLOAD_UNIT
	for facility: Dictionary in result["transport_facilities"]: facility["unit"] = REGIONAL_PAYLOAD_UNIT
	var population_start: int = 0
	for actor: Dictionary in result["actors"]:
		if actor["kind"] != "cohort": continue
		# Resident wage/spending causality is visible without opening cash gifts.
		actor["cash"] = 0
		if actor.get("population_unit_id") == "country_fra": population_start = maxi(population_start, int(actor["population_start"]) + int(actor["members"]))
	result["capital_investment"] = {"templates": [], "npc_policies": [], "maintenance_policies": []}
	for mine: Dictionary in [{"name": "coal", "good": "coal", "opening": 8, "batch": 4, "reserve": 48}, {"name": "ore", "good": "iron_ore", "opening": 12, "batch": 6, "reserve": 72}]:
		_install_regional_mine(result, mine, population_start)
		population_start += 1
	# Existing French metal/tool production has spare paid labor. Installed mine
	# capacity, real inputs and process quotas remain independent limitations.
	for job: Dictionary in result["jobs"]:
		if job["id"] in ["job:network:steel1", "job:network:tools1"]: job["hours"] = 8
	for firm: Dictionary in result["firms"]:
		if firm["id"] not in ["firm:network:steel1", "firm:network:tools1"]: continue
		for site: Dictionary in firm["sites"]:
			for activity: Dictionary in site["activities"]: activity["process"]["max_batches_per_cycle"] = 4
	_install_regional_rail(result, population_start, lyon_shared)
	if numeric_rouen:
		for binding: Dictionary in result["shared_transport"]:
			if binding["source_link_id"] == REGIONAL_RAIL_LINK: binding["capacity_model"] = "WINDOW_THROUGHPUT"
	population_start += 3 if lyon_shared else 2
	_install_regional_family(result, population_start)
	_install_regional_search(result)
	# Explicit finite information, not knowledge of other firms' private books.
	for actor: Dictionary in result["actors"]:
		if actor["kind"] == "named" and actor["place_id"] == "place:paris":
			# The local household announced a sale to this person. Identity and
			# quotation knowledge confer no control over household cash or stock.
			result["information"].append({"actor": actor["id"], "kind": "supplier", "candidate": REGIONAL_FAMILY + "|flour|" + REGIONAL_FAMILY, "delivery_day": 0})
		var is_new: bool = str(actor["id"]).begins_with("cohort:regional:")
		if not is_new and actor["place_id"] != "place:paris": continue
		for supplier: String in ["firm:network:bakery1|bread|site:network:bakery1", "firm:network:wholesale1|bread|site:regional:station:paris", "firm:network:tailor1|clothes|site:network:tailor1", "firm:network:tools1|tools|site:network:tools1"]:
			var already: bool = false
			for notice: Dictionary in result["information"]:
				if notice["actor"] == actor["id"] and notice["kind"] == "supplier" and notice["candidate"] == supplier: already = true
			if not already: result["information"].append({"actor": actor["id"], "kind": "supplier", "candidate": supplier, "delivery_day": 0})
		if not is_new: continue
		for edge: Dictionary in result["routes"]:
			var local: bool = edge["from_place_id"] == actor["place_id"] and edge["to_place_id"] == actor["place_id"]
			var supply: bool = actor["place_id"] == "place:lyon" and edge.get("source_link_id") == "rail_paris_lyon"
			supply = supply or (actor["place_id"] == "place:rouen" and edge.get("source_link_id") == REGIONAL_RAIL_LINK)
			if (local or supply) and not actor["id"] in edge["known_to"]: edge["known_to"].append(actor["id"])
	return result

static func _install_regional_search(result: Dictionary) -> void:
	result["supplier_search"] = []
	result["supplier_directory"] = []
	var recipients: Array[String] = []
	for firm: Dictionary in result["firms"]: recipients.append(firm["id"])
	for firm: Dictionary in result["firms"]:
		var receivers := recipients.duplicate()
		receivers.erase(firm["id"])
		for site: Dictionary in firm["sites"]:
			if not site["suppliers"].is_empty():
				result["supplier_search"].append({"firm": firm["id"], "site_id": site["id"], "local_zones": [], "regional_zones": [], "scope_basis": "NETWORK_ACCESS", "regional_max_days": 4, "allow_wide": true, "delay_days": {"LOCAL": 1, "REGIONAL": 2, "WIDE": 3}, "result_limit": 2, "max_known": 8, "cooldown_days": 3})
			for good: String in site["prices"]:
				# Explicit published commercial notices. NETWORK_ACCESS uses the
				# receiving site's known goods paths, not this required legacy tag.
				result["supplier_directory"].append({"seller": firm["id"], "site_id": site["id"], "good": good, "zone": "published_admitted_network", "known_to": receivers.duplicate(), "available_day": 1})
	# A real Rouen household publishes to two admitted city stock points. The
	# original search delay and known goods corridors govern when they learn it.
	result["supplier_directory"].append({"seller": REGIONAL_FAMILY, "site_id": REGIONAL_FAMILY, "good": "flour", "zone": "published_admitted_network", "known_to": ["site:network:bakery1", "site:regional:station:paris"], "available_day": 1})

static func _regional_worker(result: Dictionary, name: String, firm: String, site: String, place: String, population_start: int) -> void:
	var actor := "cohort:regional:" + name
	var job := "job:regional:" + name
	result["actors"].append({"id": actor, "kind": "cohort", "control": "automatic", "members": 1, "account_id": "account:regional:" + name, "cash": 0, "stock": stock(), "skill": 1, "daily_need": 1, "needs": {"food": 1, "clothing": 1, "household": 1}, "population_start": population_start, "place_id": place, "population_unit_id": "country_fra"})
	result["jobs"].append({"id": job, "employer": firm, "site_id": site, "positions": 1, "skill": 1, "hours": 8, "place": place, "wage_per_hour": 1, "wage_delay": 1})
	result["information"].append({"actor": actor, "kind": "job", "candidate": job, "delivery_day": 0})

static func _install_regional_mine(result: Dictionary, mine: Dictionary, population_start: int) -> void:
	var name: String = mine["name"]
	var owner := "firm:network:" + name
	var site_id := "site:network:" + name
	var activity_id := "activity:network:" + name
	var template_id := "capital_template:regional:" + name
	for firm: Dictionary in result["firms"]:
		if firm["id"] != owner: continue
		firm["manager"] = owner
		var site: Dictionary = firm["sites"][0]
		# Small explicit opening lots break the coal/steel/tool startup cycle.
		# They are not extraction receipts and are never silently replenished.
		site["stock"] = stock({str(mine["good"]): mine["opening"], "tools": 1, "steel": 1})
		site["capacity"] = 0
		site["targets"] = stock({str(mine["good"]): int(mine["batch"]) * 2})
		var activity: Dictionary = site["activities"][0]
		activity["outputs"] = {str(mine["good"]): mine["batch"]}
		activity["materials"] = stock()
		activity["process"] = _process(activity["outputs"], {}, "")
		activity["process"]["max_batches_per_cycle"] = 4
		activity["process"]["lifetime_batch_limit"] = 12
		activity["process"]["finite_extraction"] = {"format": "finite_mineral_extraction_v1", "id": "deposit:regional:" + name, "good": mine["good"], "place_id": site["place_id"], "unit": "development_kg", "reserve_quantity": mine["reserve"], "quantity_per_batch": mine["batch"], "capital_template_id": template_id, "basis": "EXPLICIT_DEVELOPMENT_FINITE_MINERAL_RESERVE", "source": "Explicit finite in-ground development estimate; no historical mine, title or measured geological reserve is inferred"}
		for supplier: String in ["firm:network:tools1|tools|site:network:tools1", "firm:network:steel1|steel|site:network:steel1"]:
			site["suppliers"].append(supplier)
			result["information"].append({"actor": site_id, "kind": "supplier", "candidate": supplier, "delivery_day": 0})
	result["capital_investment"]["templates"].append({"id": template_id, "firm": owner, "site_id": site_id, "kind": "INSTALL", "asset_type": "development_mine_equipment", "capacity": 2, "activities": [activity_id], "materials": {"tools": 1, "steel": 1}, "hours": 2, "hours_per_day": 2, "duration_minutes": 1440, "max_projects": 1, "budget": 40, "cash_floor": 20, "denomination": FormalLedgerState.DENOMINATION, "basis": "DEVELOPMENT_CAPITAL_PERMISSION", "service_days": 5, "maintenance": {"materials": {"tools": 1, "steel": 1}, "hours": 2, "hours_per_day": 2, "duration_minutes": 1440}})
	result["capital_investment"]["npc_policies"].append({"template_id": template_id, "window_days": 1, "minimum_pressure": 1, "minimum_utilization_percent": 0, "cooldown_days": 365})
	result["capital_investment"]["maintenance_policies"].append({"template_id": template_id, "basis": "EXPLICIT_DEVELOPMENT_SCHEDULED_MAINTENANCE"})
	_regional_worker(result, "mine:" + name, owner, site_id, "place:lyon", population_start)

static func _install_regional_family(result: Dictionary, population_start: int) -> void:
	result["actors"].append({"id": REGIONAL_FAMILY, "kind": "cohort", "control": "automatic", "members": 2, "account_id": "account:regional:rouen_miller", "cash": 24, "stock": stock({"grain": 24}), "skill": 1, "daily_need": 1, "needs": {"food": 1, "clothing": 1, "household": 1}, "population_start": population_start, "place_id": "place:rouen", "population_unit_id": "country_fra"})
	result["local_producers"] = [{"actor": REGIONAL_FAMILY, "input_good": "grain", "input_per_batch": 3, "output_good": "flour", "output_per_batch": 2, "hours_per_batch": 2, "max_batches_per_day": 1, "lifetime_batch_limit": 8, "price": 3, "basis": "EXPLICIT_DEVELOPMENT_FINITE_HOUSEHOLD_PROCESSING"}]

static func _install_regional_rail(result: Dictionary, population_start: int, lyon_shared: bool) -> void:
	var owner := "firm:network:wholesale1"
	var paris := "site:regional:station:paris"
	var rouen := "site:regional:station:rouen"
	var lyon := "site:regional:station:lyon"
	# false preserves the original regional input for its existing regression;
	# normal gameplay uses true. Neither option upgrades a saved configuration.
	var stations: Array = [[paris, "place:paris"], [rouen, "place:rouen"]]
	if lyon_shared: stations.append([lyon, "place:lyon"])
	for firm: Dictionary in result["firms"]:
		if firm["id"] != owner: continue
		for pair: Array in stations:
			var shop: bool = pair[0] == paris
			var suppliers: Array[String] = []
			if shop: suppliers.append("firm:network:bakery1|bread|site:network:bakery1")
			firm["sites"].append({"id": pair[0], "place_id": pair[1], "roles": ["storage", "sales"] if shop else ["storage"], "stock": stock(), "capacity": 0, "targets": stock({"flour": 4, "bread": 4}) if shop else stock(), "prices": {"flour": 5, "bread": 5} if shop else {}, "activities": [], "suppliers": suppliers, "enabled": true, "production_enabled": false, "accepting_business": true, "basis": "DEVELOPMENT_CONFIGURATION", "coordination_delay": 0})
			for supplier: String in suppliers: result["information"].append({"actor": pair[0], "kind": "supplier", "candidate": supplier, "delivery_day": 0})
	_regional_worker(result, "station:paris", owner, paris, "place:paris", population_start)
	_regional_worker(result, "station:rouen", owner, rouen, "place:rouen", population_start + 1)
	if lyon_shared: _regional_worker(result, "station:lyon", owner, lyon, "place:lyon", population_start + 2)
	var handling_starts: Array[int] = []
	for day: int in range(0, 61):
		for hour: int in [0, 4, 12, 16]: handling_starts.append(day * 1440 + hour * 60)
	# Both rail services use this ONE Paris facility and the same earned work.
	# The Lyon site has no opening goods, money or production. Its worker is an
	# admitted host population member paid from the existing carrier account.
	for pair: Array in stations:
		var site: String = pair[0]
		for kind: String in ["HANDLING_THROUGHPUT", "BERTH_OCCUPANCY", "STORAGE_OCCUPANCY"]:
			var windows: Array[Dictionary] = []
			if kind == "HANDLING_THROUGHPUT":
				for start: int in handling_starts: windows.append({"start_minute": start, "end_minute": start + 60, "capacity": 4})
			else: windows.append({"start_minute": 0, "end_minute": 90 * 1440, "capacity": 8 if kind == "STORAGE_OCCUPANCY" else 4})
			# BERTH is the original finite standing/working-space mechanism here,
			# explicitly a station platform; it does not turn this rail into a port.
			result["transport_facilities"].append({"id": "facility:regional:" + site + ":" + kind, "site_id": site, "kind": kind, "unit": REGIONAL_PAYLOAD_UNIT, "windows": windows, "basis": "EXPLICIT_DEVELOPMENT_TRANSPORT_FACILITY"})
	for edge: Dictionary in result["routes"]:
		var link: String = str(edge.get("source_link_id", ""))
		if link != REGIONAL_RAIL_LINK and (not lyon_shared or link != REGIONAL_LYON_RAIL_LINK): continue
		edge["carrier"] = owner
		var mainline: bool = link == REGIONAL_LYON_RAIL_LINK
		var other := lyon if mainline else rouen
		var forward: bool = edge["from_place_id"] == "place:paris"
		var origin := paris if forward else other
		var destination := other if forward else paris
		var entries: Array[int] = []
		for day: int in range(0, 61): entries.append(day * 1440 + (0 if forward else 720))
		var resources: Dictionary = {"unloading_minutes": 60, "unloading_hours_per_unit": 1}
		for key: String in ["origin_handling", "origin_berth", "destination_handling", "destination_berth", "destination_storage"]:
			var site := origin if key.begins_with("origin") else destination
			var kind := "HANDLING_THROUGHPUT" if key.ends_with("handling") else "BERTH_OCCUPANCY" if key.ends_with("berth") else "STORAGE_OCCUPANCY"
			resources[key] = "facility:regional:" + site + ":" + kind
		var vehicle: String = "vehicle:regional:finite_lyon_train" if mainline else "vehicle:regional:finite_train"
		result["shared_transport"].append({"edge_id": edge["id"], "source_link_id": link, "entry_minutes": entries, "weight_unit": REGIONAL_PAYLOAD_UNIT, "vehicle_id": vehicle, "vehicle_payload": 4, "handling_site": origin, "handling_hours_per_unit": 1, "basis": "EXPLICIT_DEVELOPMENT_SHARED_RAIL_CAPACITY", "window_minutes": 60, "loading_minutes": 60, "travel_minutes": 180, "vehicle_hold_minutes": 300, "node_resources": resources, "legacy_node_limit_basis": "EXPLICIT_DAILY_BUSINESS_QUANTITY_LIMIT"})

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
