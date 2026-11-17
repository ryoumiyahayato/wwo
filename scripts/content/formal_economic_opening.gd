class_name FormalEconomicOpening
extends RefCounted
## One bounded ordinary opening. It uses host persons/accounts and the native
## execution kernel. Saved worlds bind their saved config without genesis.
const SINGLE_PATH := "res://data/formal/paris_workshop_opening_r1.json"
const MATERIAL_RENEWAL_CASE := "FORMAL_PARIS_FINITE_MATERIAL_RENEWAL_R1"
const SECOND_WORKER_CASE := "FORMAL_PARIS_TWO_WORKERS_OPENING_R1"
const PATH := "res://data/formal/paris_employment_opening_r1.json"
const FranceMarketGoods = preload("res://scripts/content/france_market_goods.gd")

static func for_source(source_id: String) -> Dictionary:
	if "--formal-single-employer-opening" in OS.get_cmdline_user_args(): return single_employer(source_id)
	if source_id != "country_fra": return {}
	if "--formal-material-renewal-opening" in OS.get_cmdline_user_args(): return material_renewal(source_id)
	if "--formal-second-worker-opening" in OS.get_cmdline_user_args(): return second_worker(source_id)
	var result := _load(PATH)
	# Explicit initial conditions for the finite comparison. Never changes a running world.
	if "--formal-employment-opportunity" in OS.get_cmdline_user_args():
		for row: Dictionary in result.get("information", []):
			if row["actor"] == "person:formal_generated_country_fra_0002" and row["kind"] == "job" and row["candidate"] == "job:opening_paris_bakery": row["delivery_day"] = 4
	if "--formal-employment-arrears" in OS.get_cmdline_user_args():
		result["firms"][1]["cash"] = 16
		result["opening_organizations"][1]["notice"] = str(result["opening_organizations"][1]["notice"]).replace("初始现金600", "初始现金16（隔离欠薪对照）")
	if not OS.get_cmdline_user_args().has("--formal-employment-arrears") and not OS.get_cmdline_user_args().has("--formal-employment-opportunity"):
		_add_resident_markets(result)
		_add_market_goods(result)
		_add_milling_chain(result)
	return result

static func _add_milling_chain(result: Dictionary) -> void:
	const WORKSHOP := "firm:opening_paris_workshop"
	const FARM := "cohort:opening:rouen_farm"
	const HOUSEHOLDS := "cohort:opening:paris_households"
	const MILL_JOB := "job:opening_paris_mill"
	var site: Dictionary = result["firms"][0]["sites"][0]
	var site_id: String = site["id"]
	var bakery: Dictionary = site["activities"][0]
	var grain: Dictionary = bakery["materials"].duplicate()
	grain["grain"] = 4
	bakery["materials"]["grain"] = 0
	bakery["materials"]["flour"] = 1
	site["activities"].append({
		"id":"activity:opening_paris_milling","place_id":"place:paris",
		"outputs":{"flour":3},"materials":grain,"hours":1,"capacity_units":1,
		"enabled":true,"basis":"GENERATED_OPENING_CONFIGURATION",
	})
	# Two milling batches of opening stock at the workshop. The remainder stays
	# with the upstream supplier at genesis. Total opening grain stays constant.
	var retained_at_origin: int = int(site["stock"]["grain"])-8
	site["stock"]["grain"] = 8
	for actor: Dictionary in result["actors"]:
		if actor["id"] == FARM: actor["stock"]["grain"] += retained_at_origin
		elif actor["id"] == HOUSEHOLDS: actor["cohort_profile"]["job_ids"].append(MILL_JOB)
	var upstream := FARM+"|grain|"+FARM
	site["suppliers"].append(upstream)
	result["routes"][0]["known_to"].append(WORKSHOP)
	result["information"].append_array([
		{"actor":site_id,"kind":"supplier","candidate":upstream,"delivery_day":0},
		{"actor":HOUSEHOLDS,"kind":"job","candidate":MILL_JOB,"delivery_day":0},
		{"actor":HOUSEHOLDS,"kind":"supplier","candidate":WORKSHOP+"|bread|"+site_id,"delivery_day":0},
	])
	result["jobs"].append({"id":MILL_JOB,"employer":WORKSHOP,"site_id":site_id,"place":"place:paris",
		"positions":1,"skill":1,"hours":3,"wage_per_hour":3,"wage_delay":1,"notice_delay":1})
	# Selling uses its own share of paid work. At most two production batches
	# can use the original equipment in the remaining workshop hours.
	result["retail_sites"][0]["job_ids"].append(MILL_JOB)
	site["targets"]["flour"] = 3
	result["opening_organizations"][0]["notice"] += " 本普通法国新局另配磨粉工时及磨粉批次。工坊以1千克面粉烘焙2份面包。"

static func _add_market_goods(result: Dictionary) -> void:
	var definitions := FranceMarketGoods.definitions()
	result["goods"].append_array(definitions)
	# R2 stores configured quantities densely. Zero entries create no StockLots.
	var zeros: Dictionary = {}
	for good: Dictionary in definitions:
		zeros[good["id"]] = 0
	for actor: Dictionary in result["actors"]:
		actor["stock"].merge(zeros)
	for firm: Dictionary in result["firms"]:
		for site: Dictionary in firm["sites"]:
			site["stock"].merge(zeros)
			site["targets"].merge(zeros)
			for activity: Dictionary in site["activities"]:
				activity["materials"].merge(zeros)

## Regional opening allocations in kg of grain and 500g dry staple units.
## These represented population shares and January carryover
## stocks are declared assumptions. StockLots and Ledger admit them at genesis.
static func _add_resident_markets(result: Dictionary) -> void:
	const FARM: String = "cohort:opening:rouen_farm"
	const PARIS: String = "cohort:opening:paris_households"
	const LYON: String = "cohort:opening:lyon_households"
	const CARRIER: String = "carrier:opening_french_rail"
	const CARRIER_ACCOUNT: String = "account:opening_french_rail"
	const ROUEN_PARIS: String = "edge:opening:rouen:paris"
	const PARIS_LYON: String = "edge:opening:paris:lyon"
	result["goods"] = [
		{"id":"beans", "needs":{"food":2}, "unit_id":"development_kg", "unit_name_zh":"千克"},
		{"id":"grain", "needs":{"food":2}, "unit_id":"development_kg", "unit_name_zh":"千克"},
		{"id":"bread", "needs":{"food":1}, "unit_id":"development_portion", "unit_name_zh":"份"},
	]
	result["stock_horizon"] = 6
	result["unified_market"] = {"period_days":3, "request_days":14, "eta_permille":50,
		"damping_permille":500, "deadband_permille":100, "maximum_price":1000000}
	for actor: Dictionary in result["actors"]:
		actor["stock"]["bread"] = 4
	var population_start: int = 100
	for group: Dictionary in [
		{"id":PARIS, "place":"place:paris", "members":5000, "grain":10000, "cash":150000, "label":"巴黎居民家庭"},
		{"id":LYON, "place":"place:lyon", "members":3000, "grain":6000, "cash":90000, "label":"里昂居民家庭"},
		{"id":FARM, "place":"place:rouen", "members":2000, "grain":550000, "cash":60000, "label":"鲁昂自营农户"},
	]:
		var farm: bool = group["id"] == FARM
		var people: int = group["members"]
		result["actors"].append({
			"id":group["id"], "kind":"cohort", "control":"automatic", "members":people,
			"account_id":"account:"+str(group["id"]), "cash":group["cash"],
			"stock":{"beans":0, "bread":0, "grain":group["grain"]}, "skill":1, "daily_need":1,
			"population_start":population_start, "place_id":group["place"], "population_unit_id":"country_fra",
			"cohort_profile":{"stratum_id":"self_employed" if farm else "resident_household",
				"label":group["label"], "occupation":"grain" if farm else "unallocated",
				"labor_members":people if farm else people/2, "max_jobs":1, "job_ids":[],
				"job_search_days":7, "basis":"EXPLICIT_DEVELOPMENT_COHORT_STRATUM",
				"need_rates":{"food":{"numerator":1, "denominator":1}}},
		})
		population_start += people
	var source := _load("res://data/land/economic_resources_france_pilot.json")
	var crop: Dictionary = source["resources"][0].duplicate(true)
	crop.merge({"land_units":10000, "land_unit_m2":1000, "seed_per_unit":20,
		"yield_per_unit":150, "food_reserve":253000}, true)
	result["resource_producers"] = [{"actor":FARM, "good":"grain", "price":3, "resource":crop, "seasonal_reserve":true}]
	result["carriers"] = [{"id":CARRIER, "place_id":"place:paris", "account_id":CARRIER_ACCOUNT, "cash":0}]
	var player: String = WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
	result["person_travel"]["carry_limits"]["native:grain"] = 20
	result["routes"] = [
		{"id":ROUEN_PARIS, "from_place_id":"place:rouen", "to_place_id":"place:paris",
			"capacity":10000, "delay":1, "carrier":CARRIER, "freight_per_unit":1,
			"known_to":[PARIS, LYON, player], "basis":"HOST_LINK", "source_link_id":"rail_paris_rouen"},
		{"id":PARIS_LYON, "from_place_id":"place:paris", "to_place_id":"place:lyon",
			"capacity":5000, "delay":2, "carrier":CARRIER, "freight_per_unit":1,
			"known_to":[LYON, player], "basis":"HOST_LINK", "source_link_id":"rail_paris_lyon"},
	]
	result["transport_paths"] = [{"id":"path:opening:rouen:lyon", "edge_ids":[ROUEN_PARIS, PARIS_LYON],
		"known_to":[LYON, player], "known_day":0}]
	for buyer: String in [PARIS, LYON, player]:
		result["information"].append({"actor":buyer, "kind":"supplier",
			"candidate":FARM+"|grain|"+FARM, "delivery_day":0})
	for passage: Dictionary in [
		{"from":"paris", "to":"rouen", "link":"rail_paris_rouen", "minutes":240},
		{"from":"paris", "to":"lyon", "link":"rail_paris_lyon", "minutes":720},
	]:
		for reverse: bool in [false, true]:
			var origin: String = passage["to"] if reverse else passage["from"]
			var destination: String = passage["from"] if reverse else passage["to"]
			result["person_travel"]["passages"].append({"id":"passage:opening:"+origin+":"+destination,
				"source_link_id":passage["link"], "from_place_id":"place:"+origin, "to_place_id":"place:"+destination,
				"minutes":passage["minutes"], "fee":2, "payee_account_id":CARRIER_ACCOUNT,
				"known_to":[player], "basis":"EXPLICIT_DEVELOPMENT_PERSON_PASSAGE"})

## Explicit candidate only. Copy the original resident's needs, notices and arrears
## policy; firms, vacancies, recipes, cash and material mandates remain identical.
static func second_worker(source_id: String) -> Dictionary:
	if source_id != "country_fra": return {}
	var result := _load(PATH)
	result["case_id"] = SECOND_WORKER_CASE
	result["management_scope"]["id"] = "scope:formal_paris_two_workers_opening_r1"
	var original := "person:formal_generated_country_fra_0002"
	var person := "person:formal_generated_country_fra_0003"
	var resident: Dictionary = result["opening_residents"][0].duplicate(true)
	resident["person_id"] = person
	resident["claim_id"] = "formal_population_claim:country_fra:0003"
	result["opening_residents"].append(resident)
	var actor: Dictionary = result["actors"][1].duplicate(true)
	actor["id"] = person
	actor["account_id"] = FormalPersonalEconomyState.personal_account_id(person)
	result["actors"].append(actor)
	for notice: Dictionary in result["information"].duplicate(true):
		if notice["actor"] != original: continue
		notice["actor"] = person
		result["information"].append(notice)
	var response: Dictionary = result["labor_response_policies"][0].duplicate(true)
	response["actor"] = person
	result["labor_response_policies"].append(response)
	return result

## Two standing organization resolutions, declared only in this new candidate.
## Executors may adopt these fixed terms once; ordinary procurement grants no
## authority to invent terms, repeat a resolution or appoint an employee issuer.
static func material_renewal(source_id: String) -> Dictionary:
	var result := second_worker(source_id)
	if result.is_empty(): return result
	result["case_id"] = MATERIAL_RENEWAL_CASE
	result["management_scope"]["id"] = "scope:formal_paris_finite_material_renewal_r1"
	result["material_renewals"] = []
	for opening: Dictionary in result["opening_organizations"]:
		var trade: Dictionary = opening["material_trade"]
		result["material_renewals"].append({"id": "material_mandate:" + opening["firm_id"].trim_prefix("firm:") + ":renewal_1", "issuer": opening["organization_id"], "firm": opening["firm_id"], "operation": trade["operation"], "counterparty": trade["counterparty"], "good": "grain", "min_price": 1, "max_price": 1, "quantity_limit": 4, "stock_floor": trade["stock_floor"], "valid_from": 32 * 1440, "valid_until": 36 * 1440, "basis": "GENERATED_OPENING_ONE_TIME_ORGANIZATION_RESOLUTION"})
		opening["notice"] += " 本显式候选另含本组织一次性续期决议：首批8粮耗尽后，由原企业主体执行，第32日生效、第36日截止，限原交易对手及粮食、单价1、第二批累计最多4粮；可撤销后续受理，不抹去已受理责任。雇员无签发权，不能再次续期；不增加粮源。"
	return result

static func single_employer(source_id: String) -> Dictionary:
	return _load(SINGLE_PATH) if source_id == "country_fra" else {}

static func _load(path: String) -> Dictionary:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _integers(document) if document is Dictionary else {"case_id":"INVALID_OPENING"}

static func _integers(value: Variant) -> Variant:
	# JSON numbers cross an integer-only domain boundary. Invalid fractional
	# or out-of-range values remain invalid; do not round them into authority.
	if value is float and is_finite(value) and value==floor(value) and absf(value)<=float(FormalLedgerState.MAX_AMOUNT): return int(value)
	if value is Dictionary:
		for key:Variant in value:value[key]=_integers(value[key])
	elif value is Array:
		for index:int in value.size():value[index]=_integers(value[index])
	return value
