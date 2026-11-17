class_name EconomySliceConfig
extends RefCounted
const SupplyContracts = preload("res://scripts/world/economy_supply_contracts.gd")
const LocalQuotations = preload("res://scripts/world/economy_local_quotations.gd")
const CapitalTransport = preload("res://scripts/world/economy_capital_transport.gd")
const SharedTransport = preload("res://scripts/world/economy_shared_transport.gd")
const Liquidity = preload("res://scripts/world/economy_liquidity_rules.gd")
const CostAllocation = preload("res://scripts/world/economy_cost_allocation.gd")
const WindDown = preload("res://scripts/world/economy_wind_down.gd")
const LaborMarket = preload("res://scripts/world/economy_labor_market.gd")
const Commercial = preload("res://scripts/world/economy_commercial_information.gd")
const Retail = preload("res://scripts/world/economy_retail_rules.gd")
const Leases = preload("res://scripts/world/economy_lease_market.gd")
const Services = preload("res://scripts/world/economy_service_market.gd")
const Budget = preload("res://scripts/world/economy_procurement_budget.gd")
const Cohorts = preload("res://scripts/world/economy_cohort_rules.gd")

const Capital = preload("res://scripts/world/economy_capital_formation.gd")
const CommodityMapping = preload("res://scripts/world/formal_commodity_mapping.gd")
## Pure input normalization. There is one execution kernel for R1 and R2.

const GOODS: Array[String] = ["beans", "bread", "grain"]
const ZERO: Dictionary = {"beans": 0, "bread": 0, "grain": 0}
const PLACE: String = "place:paris"
const FIELDS: Array[String] = ["format", "case_id", "actors", "firms", "jobs", "information", "route", "stock_horizon", "production_enabled", "player_choice"]
const Credit = preload("res://scripts/world/economy_bilateral_credit.gd")
const Exchange = preload("res://scripts/world/economy_currency_exchange.gd")
const Assets = preload("res://scripts/world/economy_asset_market.gd")
const OPTIONAL_FIELDS: Array[String] = ["household_choice","household_purchase_enquiries","operating_inventory","credit_offers", "currency_accounts", "carriers", "fx_offers", "routes", "assets", "transport_paths", "transport_nodes", "npc_finance", "firm_operations", "price_policies", "purchase_limits", "supplier_directory", "supplier_search", "goods", "need_categories", "host_personal_accounts", "management_scope", "person_travel", "runtime_expansions", "personal_storage", "residence_permissions", "commodity_mappings", "place_population_bindings", "npc_residence", "firm_management_permissions", "capital_investment", "procurement_budgets", "shared_transport", "transport_facilities", "development_organizations", "liquidity_policies", "labor_response_policies", "firm_finance_authorities", "cost_accounting", "service_market", "lease_market", "retail_sites", "commercial_information", "labor_market", "wind_down", "capital_resale", "capital_transport", "local_quotation_experiment", "equity_call_market", "equity_primary", "equity_distribution", "corporate_decisions", "supply_contracts", "supply_opportunity_policies"]
## Extra accounts declare finite minor-unit endowments, including zero accounts.
## FX offers use target-minor/source-minor rational rates and a fixed source fee.
## Routes are directed shared physical edges, with same-currency freight per unit.
## Optional capacity_manager can submit set_edge_capacity within the base capacity;
## zero closes entry, while already entered cargo completes its locked travel time.
## transport_paths: id, ordered edge_ids (1..8), known_to, known_day. No live reroute.
## transport_nodes: place_id, daily outgoing capacity shared by all attached edges.
## Omitted nodes have no additional throughput limit; they never own cargo stock.
## npc_finance is empty by default. Each explicit automatic actor/firm policy has
## repay_due, allow_exchange and currency-keyed cash_floors / borrow_limits / fx_limits.
## cash_floors protect repayment and FX source spending, without reserving money.
## borrow_limits: daily_principal, max_debt (principal + fixed interest), max_interest.
## Autonomous borrowing permits one open borrower loan and none on a repayment day.
## fx_limits cap daily source principal plus fees. Financing serves current known
## goods/input procurement only; no autonomous lending, investing or dividends.
## Assets declare issuer, manager, finite holders, and public information recipients.

static func valid_development_organizations(settings: Dictionary) -> bool:
	var rows: Variant=settings.get("development_organizations",[])
	if not rows is Array or rows.size()>32: return false
	var firms: Dictionary={}
	for firm: Variant in settings.get("firms",[]):
		if not firm is Dictionary or not firm.get("id") is String: return false
		firms[firm["id"]]=firm
	var used: Dictionary={}
	for row: Variant in rows:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["organization_id","firm_id","basis"]) or not row["organization_id"] is String or not row["organization_id"].begins_with("organization:development_") or not row["firm_id"] is String or not firms.has(row["firm_id"]) or used.has(row["organization_id"]) or used.has(row["firm_id"]) or row["basis"]!="EXPLICIT_DEVELOPMENT_COMMERCIAL_ORGANIZATION" or firms[row["firm_id"]].get("host_organization_id")!=row["organization_id"]: return false
		used[row["organization_id"]]=true
		used[row["firm_id"]]=true
	return rows.is_empty() or settings.get("host_personal_accounts",false)

static func is_multi(value: Dictionary) -> bool:
	return value.get("format") == "R2"

static func valid(value: Dictionary) -> bool:
	if not preload("res://scripts/world/economy_household_choice.gd").valid(value):return false
	if value.has("household_purchase_enquiries") and not value.household_purchase_enquiries is bool:return false
	if not preload("res://scripts/world/economy_operating_inventory.gd").valid(value):return false
	if not SupplyContracts.valid_configuration(value): return false
	if not CapitalTransport.valid_configuration(value): return false
	if not valid_development_organizations(value): return false
	if not Budget.valid_rules(value.get("procurement_budgets", [])) or not SharedTransport.valid_configuration(value.get("shared_transport", [])) or not SharedTransport.valid_facilities(value.get("transport_facilities", [])): return false
	if not Liquidity.valid(value) or not CostAllocation.valid_configuration(value): return false
	if value.has("place_population_bindings") and (not value.get("host_personal_accounts", false) or not FormalWorldPopulationState.valid_place_population_bindings(value["place_population_bindings"])): return false
	if value.has("commodity_mappings") and (not value.get("host_personal_accounts", false) or not CommodityMapping.valid_rows(value["commodity_mappings"])): return false
	if value.has("residence_permissions"):
		if not value.get("host_personal_accounts", false) or not value["residence_permissions"] is Array or value["residence_permissions"].size() > 256: return false
		var permissions: Dictionary = {}
		for row: Variant in value["residence_permissions"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["id", "person_id", "source_unit_id", "destination_unit_id", "place_ids", "basis"]) or not row["place_ids"] is Array or row["place_ids"].is_empty() or row["basis"] != "DEVELOPMENT_RESIDENCE_PERMISSION": return false
			for key: String in ["id", "person_id", "source_unit_id", "destination_unit_id"]:
				if not row[key] is String or row[key].is_empty(): return false
			if permissions.has(row["id"]) or row["source_unit_id"] == row["destination_unit_id"]: return false
			permissions[row["id"]] = true
			var places: Dictionary = {}
			for place: Variant in row["place_ids"]:
				if not place is String or not _place(place) or places.has(place): return false
				places[place] = true
	if value.has("personal_storage"):
		if not value.get("host_personal_accounts", false) or not value["personal_storage"] is Array or value["personal_storage"].size() > 256: return false
		var custody_sites: Dictionary = {}
		for row: Variant in value["personal_storage"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["site_id", "goods", "basis"]) or not row["site_id"] is String or custody_sites.has(row["site_id"]) or not row["goods"] is Array or row["goods"].is_empty() or row["basis"] != "DEVELOPMENT_CUSTODY_PERMISSION": return false
			var goods_seen: Dictionary = {}
			for good: Variant in row["goods"]:
				if not good is String or not good_ids(value).has(good) or goods_seen.has(good): return false
				goods_seen[good] = true
			custody_sites[row["site_id"]] = true
	if value.has("host_personal_accounts") and value["host_personal_accounts"] != true:
		return false
	if value.has("person_travel") and (not value.get("host_personal_accounts", false) or not VNextNamedPersonOverlay.valid_mobility_configuration(value["person_travel"])): return false
	if value.has("runtime_expansions"):
		if not value.get("host_personal_accounts", false) or not value["runtime_expansions"] is Array or value["runtime_expansions"].size() > 16: return false
		var expansion_ids: Dictionary = {}
		for expansion: Variant in value["runtime_expansions"]:
			if not expansion is Dictionary or not FormalLedgerState.exact_fields(expansion, ["id", "label", "extension"]) or not expansion["id"] is String or expansion_ids.has(expansion["id"]) or not expansion["label"] is String or not expansion["extension"] is Dictionary: return false
			expansion_ids[expansion["id"]] = true
	if value.has("management_scope"):
		var scope: Variant = value["management_scope"]
		if not value.get("host_personal_accounts", false) or not scope is Dictionary or not FormalLedgerState.exact_fields(scope, ["id", "identity_basis", "business_basis", "statistics_visibility"]) or not scope["id"] is String or scope["id"].is_empty() or scope["identity_basis"] != "HOST_WORLD" or scope["business_basis"] != "DEVELOPMENT_CONFIGURATION" or scope["statistics_visibility"] not in ["OWNER_ONLY", "PUBLIC_AGGREGATES"]:
			return false
	var fields: Array[String] = FIELDS.duplicate()
	for field: String in OPTIONAL_FIELDS:
		if value.has(field):
			fields.append(field)
	if not FormalLedgerState.exact_fields(value, fields) or not valid_credit_offers(value) or value["format"] != "R2" or not value["case_id"] is String or value["case_id"].is_empty() or not value["production_enabled"] is bool or value["player_choice"] not in ["fixed", "substitute"] or not _number(value["stock_horizon"], 1):
		return false
	for field: String in ["actors", "firms", "jobs", "information"]:
		if not value[field] is Array:
			return false
	var goods := good_ids(value)
	if not _goods_valid(value):
		return false
	var actors: Dictionary = {}
	var firms: Dictionary = {}
	var sites: Dictionary = {}
	var jobs: Dictionary = {}
	var accounts: Dictionary = {FormalLedgerState.SOURCE_ACCOUNT: true}
	var players: int = 0
	var ranges: Array[Dictionary] = []
	for actor: Variant in value["actors"]:
		if not actor is Dictionary or not _fields(actor, ["id", "kind", "control", "members", "account_id", "cash", "stock", "skill", "daily_need", "population_start"], ["place_id", "population_unit_id", "needs", "cohort_profile"]) or not _place(actor.get("place_id", PLACE)):
			return false
		if not actor["id"] is String or actors.has(actor["id"]) or actor["kind"] not in ["named", "cohort"] or actor["control"] not in ["player", "automatic", "dormant"] or not _number(actor["members"], 1) or not _number(actor["cash"]) or not _number(actor["skill"], 1) or not _number(actor["daily_need"]) or not _number(actor["population_start"]) or not _stock(actor["stock"], goods):
			return false
		if actor["kind"] == "named":
			if not str(actor["id"]).begins_with("person:") or actor["members"] != 1 or actor["account_id"] != FormalPersonalEconomyState.personal_account_id(actor["id"]) or actor["population_start"] != 0:
				return false
		else:
			if not str(actor["id"]).begins_with("cohort:") or actor["control"] != "automatic":
				return false
			var span := Vector2i(int(actor["population_start"]), int(actor["population_start"]) + int(actor["members"]))
			for prior: Dictionary in ranges:
				var same_unit: bool = not str(actor.get("population_unit_id", "")).is_empty() and prior["unit"] == actor.get("population_unit_id")
				var same_place: bool = prior["place"] == actor.get("place_id", PLACE)
				if (same_unit or same_place) and span.x < prior["span"].y and prior["span"].x < span.y:
					return false
			ranges.append({"unit": actor.get("population_unit_id", ""), "place": actor.get("place_id", PLACE), "span": span})
		if actor["control"] == "dormant" and (actor["daily_need"] != 0 or actor["cash"] != 0 or actor["stock"] != zero_stock(goods)):
			return false
		if actor.has("population_unit_id") and (not actor["population_unit_id"] is String or actor["population_unit_id"].is_empty()):
			return false
		if not _account(actor["account_id"], accounts):
			return false
		players += 1 if actor["control"] == "player" else 0
		if not _actor_needs_valid(actor, value):
			return false
		actors[actor["id"]] = actor
	if players > 1 or (not value.get("host_personal_accounts", false) and players != 1) or actors.size() > 128:
		return false
	for firm: Variant in value["firms"]:
		if not firm is Dictionary or not _fields(firm, ["id", "place_id", "account_id", "cash"], ["suppliers", "denomination", "recipe", "activities", "manager", "cargo_settlement_controller", "cargo_settlement_basis", "host_organization_id", "stock", "capacity", "targets", "prices", "sites"]):
			return false
		if not firm["id"] is String or not str(firm["id"]).begins_with("firm:") or firms.has(firm["id"]) or not _place(firm["place_id"]) or not _account(firm["account_id"], accounts) or not _number(firm["cash"]) or (firm.has("suppliers") and not firm["suppliers"] is Array):
			return false
		if firm.has("manager") and (not firm["manager"] is String or (firm["manager"] != firm["id"] and (not actors.has(firm["manager"]) or actors[firm["manager"]]["control"] == "dormant"))):
			return false
		if firm.has("host_organization_id") and (not firm["host_organization_id"] is String or not str(firm["host_organization_id"]).begins_with("organization:")):
			return false
		if firm.has("sites"):
			for field: String in ["stock", "capacity", "targets", "prices", "recipe", "activities"]:
				if firm.has(field):
					return false
			if not firm["sites"] is Array or firm["sites"].is_empty() or firm["sites"].size() > 16:
				return false
			for site: Variant in firm["sites"]:
				if not site is Dictionary or not _fields(site, ["id", "place_id", "roles", "stock", "capacity", "targets", "prices", "suppliers", "activities", "enabled", "production_enabled", "accepting_business", "basis", "coordination_delay"], []) or not site["id"] is String or not str(site["id"]).begins_with("site:") or sites.has(site["id"]) or not _site_valid(site, goods):
					return false
				sites[site["id"]] = _normalized_site(site, firm["id"], goods)
		else:
			for field: String in ["stock", "capacity", "targets", "prices", "suppliers"]:
				if not firm.has(field):
					return false
			if not _stock(firm["stock"], goods) or not _stock(firm["targets"], goods) or not _number(firm["capacity"]) or not _prices_valid(firm["prices"], goods) or not _production_valid(firm, goods):
				return false
			var site := _legacy_site(firm, goods)
			if sites.has(site["id"]):
				return false
			sites[site["id"]] = site
		if firm.has("sites"):
			for candidate: Variant in firm.get("suppliers", []):
				if not sites[configured_primary({firm["id"]: firm}, firm["id"])]["suppliers"].has(candidate):
					return false
		if firm.has("cargo_settlement_controller"):
			if firm.get("cargo_settlement_basis") != "EXPLICIT_DEVELOPMENT_CARGO_SETTLEMENT_AUTHORITY" or not firm["cargo_settlement_controller"] is String or firm["cargo_settlement_controller"] not in [firm["id"], firm.get("manager", firm["id"])]: return false
		elif firm.has("cargo_settlement_basis"): return false
		firms[firm["id"]] = firm
	if firms.is_empty() or firms.size() > 32:
		return false
	for job: Variant in value["jobs"]:
		if not job is Dictionary or not _fields(job, ["id", "employer", "positions", "skill", "hours", "place", "wage_per_hour", "wage_delay"], ["denomination", "notice_delay", "site_id"]) or not job["id"] is String or not str(job["id"]).begins_with("job:") or jobs.has(job["id"]) or not firms.has(job["employer"]) or not _place(job["place"]) or not sites.has(job.get("site_id", configured_primary(firms, job["employer"]))) or sites[job.get("site_id", configured_primary(firms, job["employer"]))]["firm_id"] != job["employer"] or job["place"] != sites[job.get("site_id", configured_primary(firms, job["employer"]))]["place_id"]:
			return false
		for key: String in ["positions", "skill", "hours", "wage_per_hour", "wage_delay"]:
			if not _number(job[key], 1 if key in ["skill", "hours"] else 0):
				return false
		if job.has("notice_delay") and (not _number(job["notice_delay"], 1) or int(job["notice_delay"]) > 30):
			return false
		jobs[job["id"]] = job
	var info_ids: Dictionary = {}
	var counts: Dictionary = {}
	for row: Variant in value["information"]:
		if not row is Dictionary or not _fields(row, ["actor", "kind", "candidate", "delivery_day"], ["observed_day"]) or not row["actor"] is String or (not actors.has(row["actor"]) and not firms.has(row["actor"]) and not sites.has(row["actor"])) or row["kind"] not in ["job", "supplier"] or not row["candidate"] is String or not _number(row["delivery_day"]):
			return false
		if actors.has(row["actor"]) and actors[row["actor"]]["control"] == "dormant":
			return false
		var good := "job"
		if row["kind"] == "job":
			if not actors.has(row["actor"]) or not jobs.has(row["candidate"]):
				return false
		else:
			var parts := str(row["candidate"]).split("|")
			if parts.size() not in [2, 3] or not firms.has(parts[0]):
				return false
			var seller_site := str(parts[2]) if parts.size() == 3 else configured_primary(firms, parts[0])
			if not sites.has(seller_site) or sites[seller_site]["firm_id"] != parts[0] or not sites[seller_site]["prices"].has(parts[1]) or parts[0] == row["actor"] or (sites.has(row["actor"]) and sites[row["actor"]]["firm_id"] == parts[0]):
				return false
			good = parts[1]
			if firms.has(row["actor"]) and not sites[configured_primary(firms, row["actor"])]["suppliers"].has(row["candidate"]):
				return false
			if sites.has(row["actor"]) and not sites[row["actor"]]["suppliers"].has(row["candidate"]):
				return false
		if row.has("observed_day") and (not FormalLedgerState.valid_amount(row["observed_day"]) or int(row["observed_day"]) > int(row["delivery_day"])): return false
		var id := str(row["actor"]) + ":" + str(row["kind"]) + ":" + str(row["candidate"])
		if info_ids.has(id):
			return false
		info_ids[id] = true
		var count_key := str(row["actor"]) + "|" + good
		counts[count_key] = int(counts.get(count_key, 0)) + 1
		if int(counts[count_key]) > (16 if value.get("host_personal_accounts", false) else 3):
			return false
	for firm: Dictionary in firms.values():
		var unique: Dictionary = {}
		for candidate: Variant in firm.get("suppliers", []):
			if not candidate is String or unique.has(candidate) or not info_ids.has(str(firm["id"]) + ":supplier:" + candidate):
				return false
			unique[candidate] = true
	for site: Dictionary in sites.values():
		var unique: Dictionary = {}
		for candidate: Variant in site["suppliers"]:
			if not candidate is String or unique.has(candidate) or (not info_ids.has(str(site["id"]) + ":supplier:" + candidate) and not (site["id"] == configured_primary(firms, site["firm_id"]) and info_ids.has(str(site["firm_id"]) + ":supplier:" + candidate))):
				return false
			unique[candidate] = true
	for actor: Dictionary in actors.values():
		if not Cohorts.valid(actor, value, jobs): return false
	var route: Variant = value["route"]
	return route is Dictionary and FormalLedgerState.exact_fields(route, ["id", "place_id", "capacity", "delay", "basis"]) and route["id"] is String and str(route["id"]).begins_with("edge:") and _place(route["place_id"]) and route["basis"] == "SYNTHETIC" and _number(route["capacity"], 1) and _number(route["delay"], 1) and credit_parties_valid(value, actors, firms) and _finance(value, actors, firms, jobs, accounts) and _operations(value, actors, firms) and _lifecycle_configuration(value, actors, firms) and Capital.valid_configuration(value, normalize(value, [])) and Services.valid_configuration(value, normalize(value, [])) and Leases.valid_configuration(value, normalize(value, [])) and Retail.valid_configuration(value, normalize(value, [])) and Commercial.valid_configuration(value, normalize(value, [])) and LaborMarket.valid_configuration(value,normalize(value,[])) and WindDown.valid_configuration(value,normalize(value,[])) and LocalQuotations.valid_configuration(value,normalize(value,[])) and Assets.CallMarket.valid_configuration(value,normalize(value,[])) and Assets.Primary.valid_configuration(value,normalize(value,[])) and Assets.Distribution.valid_configuration(value,normalize(value,[])) and Assets.Corporate.valid_configuration(value,normalize(value,[]))

static func _fields(row: Dictionary, required: Array[String], optional: Array[String]) -> bool:
	var fields := required.duplicate()
	for key: String in optional:
		if row.has(key):
			fields.append(key)
	return FormalLedgerState.exact_fields(row, fields)

static func _place(value: Variant) -> bool:
	return value is String and str(value).begins_with("place:") and str(value).length() > 6

static func _finance(value: Dictionary, actors: Dictionary, firms: Dictionary, jobs: Dictionary, accounts: Dictionary) -> bool:
	for field: String in ["currency_accounts", "carriers", "fx_offers", "routes", "assets", "transport_paths", "transport_nodes", "npc_finance", "firm_operations", "price_policies", "purchase_limits", "supplier_directory", "supplier_search"]:
		if not value.get(field, []) is Array or value.get(field, []).size() > 256:
			return false
	var subjects := actors.duplicate(true)
	subjects.merge(firms)
	var owner_currencies: Dictionary = {}
	for id: String in subjects:
		owner_currencies[id] = {FormalLedgerState.DENOMINATION: subjects[id]["account_id"]}
	for row: Variant in value.get("carriers", []):
		if not row is Dictionary or not _fields(row, ["id", "place_id", "account_id", "cash"], ["custody_controller", "settlement_controller", "cargo_authority_basis", "host_organization_id"]) or not row["id"] is String or not str(row["id"]).begins_with("carrier:") or subjects.has(row["id"]) or not _place(row["place_id"]) or not _number(row["cash"]) or not _account(row["account_id"], accounts):
			return false
		if row.has("custody_controller") or row.has("settlement_controller"):
			if row.get("cargo_authority_basis") != "EXPLICIT_DEVELOPMENT_CARGO_AUTHORITY": return false
			for k: String in ["custody_controller", "settlement_controller"]:
				if row.has(k) and (not row[k] is String or (not actors.has(row[k]) and not firms.has(row[k])) or (actors.has(row[k]) and actors[row[k]]["control"] == "dormant")): return false
		elif row.has("cargo_authority_basis"): return false
		subjects[row["id"]] = row
		owner_currencies[row["id"]] = {FormalLedgerState.DENOMINATION: row["account_id"]}
	var budgets: Dictionary = {}
	for row: Variant in value.get("currency_accounts", []):
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["owner", "account_id", "denomination", "cash"]) or not subjects.has(row["owner"]) or not FormalLedgerState.currency_id(row["denomination"]) or row["denomination"] == FormalLedgerState.DENOMINATION or owner_currencies[row["owner"]].has(row["denomination"]) or not FormalLedgerState.valid_amount(row["cash"]) or not _account(row["account_id"], accounts):
			return false
		if actors.has(row["owner"]) and actors[row["owner"]]["control"] == "dormant" and int(row["cash"]) != 0:
			return false
		var denomination := str(row["denomination"])
		if int(budgets.get(denomination, 0)) > FormalLedgerState.MAX_AMOUNT - int(row["cash"]):
			return false
		budgets[denomination] = int(budgets.get(denomination, 0)) + int(row["cash"])
		owner_currencies[row["owner"]][denomination] = row["account_id"]
	for denomination: String in budgets:
		if accounts.has(FormalLedgerState.currency_source(denomination)):
			return false
	for row: Dictionary in firms.values():
		if not FormalLedgerState.currency_id(row.get("denomination", FormalLedgerState.DENOMINATION)) or not owner_currencies[row["id"]].has(row.get("denomination", FormalLedgerState.DENOMINATION)):
			return false
	for row: Dictionary in jobs.values():
		if not FormalLedgerState.currency_id(row.get("denomination", FormalLedgerState.DENOMINATION)) or not owner_currencies[row["employer"]].has(row.get("denomination", FormalLedgerState.DENOMINATION)):
			return false
	for row: Dictionary in value.get("credit_offers", []):
		if not owner_currencies[row["lender"]].has(row["denomination"]) or (row["borrower"] != "" and not owner_currencies[row["borrower"]].has(row["denomination"])):
			return false
	var ids: Dictionary = {}
	for row: Variant in value.get("fx_offers", []):
		if not row is Dictionary or not Exchange.valid_offer(row) or ids.has(row["id"]) or not subjects.has(row["dealer"]) or not subjects.has(row["fee_recipient"]):
			return false
		if actors.has(row["dealer"]) and actors[row["dealer"]]["control"] != "automatic":
			return false
		for currency: String in [row["source_currency"], row["target_currency"]]:
			if not owner_currencies[row["dealer"]].has(currency):
				return false
		if not owner_currencies[row["fee_recipient"]].has(row["source_currency"]):
			return false
		var traders: Dictionary = {}
		for actor: Variant in row["traders"]:
			if not actor is String or not subjects.has(actor) or traders.has(actor) or actor == row["dealer"] or (int(row["fee"]) > 0 and actor == row["fee_recipient"]) or (actors.has(actor) and actors[actor]["control"] == "dormant") or not owner_currencies[actor].has(row["source_currency"]) or not owner_currencies[actor].has(row["target_currency"]):
				return false
			traders[actor] = true
		ids[row["id"]] = true
	ids = {value["route"]["id"]: true}
	for row: Variant in value.get("routes", []):
		if not row is Dictionary or not _fields(row, ["id", "from_place_id", "to_place_id", "capacity", "delay", "carrier", "freight_per_unit", "known_to"], ["capacity_manager", "basis", "source_link_id"]) or not row["id"] is String or not str(row["id"]).begins_with("edge:") or ids.has(row["id"]) or not _place(row["from_place_id"]) or not _place(row["to_place_id"]) or not _number(row["capacity"], 1) or not _number(row["delay"], 1) or not _number(row["freight_per_unit"]) or not subjects.has(row["carrier"]) or not row["known_to"] is Array:
			return false
		if row.get("basis", "SYNTHETIC") not in ["SYNTHETIC", "HOST_LINK"] or (row.get("basis", "SYNTHETIC") == "HOST_LINK" and (not row.get("source_link_id") is String or str(row["source_link_id"]).is_empty())) or (row.get("basis", "SYNTHETIC") == "SYNTHETIC" and row.has("source_link_id")):
			return false
		if row.has("capacity_manager") and (not firms.has(row["capacity_manager"]) and (not actors.has(row["capacity_manager"]) or actors[row["capacity_manager"]]["control"] == "dormant")):
			return false
		var recipients: Dictionary = {}
		for actor: Variant in row["known_to"]:
			if not actor is String or not subjects.has(actor) or recipients.has(actor) or (actor == row["carrier"] and not firms.has(actor)) or (actors.has(actor) and actors[actor]["control"] == "dormant"):
				return false
			recipients[actor] = true
		ids[row["id"]] = true
	if not _transport_and_policy(value, actors, firms, owner_currencies):
		return false
	ids.clear()
	var share_subjects: Dictionary=subjects.duplicate()
	if value.has("equity_call_market") and value.get("host_personal_accounts",false): share_subjects["HOST_SELECTED_PLAYER"]=true
	for row: Variant in value.get("assets", []):
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, Assets.CONFIG_FIELDS) or not row["id"] is String or not str(row["id"]).begins_with("asset:") or ids.has(row["id"]) or not firms.has(row["issuer"]) or (not firms.has(row["manager"]) and not actors.has(row["manager"])) or (actors.has(row["manager"]) and actors[row["manager"]]["control"] == "dormant") or not FormalLedgerState.valid_amount(row["total_shares"]) or int(row["total_shares"]) <= 0 or not row["holders"] is Dictionary or not row["known_to"] is Array:
			return false
		var total: int = 0
		for holder: Variant in row["holders"]:
			if not holder is String or not share_subjects.has(holder) or (actors.has(holder) and actors[holder]["control"] == "dormant") or not FormalLedgerState.valid_amount(row["holders"][holder]) or total > int(row["total_shares"]) - int(row["holders"][holder]):
				return false
			total += int(row["holders"][holder])
		if total != int(row["total_shares"]):
			return false
		var recipients: Dictionary = {}
		for actor: Variant in row["known_to"]:
			if not actor is String or not share_subjects.has(actor) or recipients.has(actor) or (actors.has(actor) and actors[actor]["control"] == "dormant"):
				return false
			recipients[actor] = true
		ids[row["id"]] = true
	return true

static func _transport_and_policy(value: Dictionary, actors: Dictionary, firms: Dictionary, currencies: Dictionary) -> bool:
	var local := value["route"] as Dictionary
	var edges := {local["id"]: {"from_place_id": local["place_id"], "to_place_id": local["place_id"], "known_to": []}}
	for row: Dictionary in value.get("routes", []):
		edges[row["id"]] = row
	var ids: Dictionary = {}
	for path: Variant in value.get("transport_paths", []):
		if not path is Dictionary or not FormalLedgerState.exact_fields(path, ["id", "edge_ids", "known_to", "known_day"]) or not path["id"] is String or not str(path["id"]).begins_with("path:") or ids.has(path["id"]) or not path["edge_ids"] is Array or path["edge_ids"].is_empty() or path["edge_ids"].size() > 8 or not path["known_to"] is Array or not _number(path["known_day"]):
			return false
		var visited: Dictionary = {}
		var previous: String = ""
		for id: Variant in path["edge_ids"]:
			if not id is String or not edges.has(id) or visited.has(id) or (not previous.is_empty() and edges[id]["from_place_id"] != previous):
				return false
			visited[id] = true
			previous = str(edges[id]["to_place_id"])
		var recipients: Dictionary = {}
		for actor: Variant in path["known_to"]:
			if not actor is String or (not actors.has(actor) and not firms.has(actor)) or recipients.has(actor) or (actors.has(actor) and actors[actor]["control"] == "dormant"):
				return false
			for id: String in path["edge_ids"]:
				if id != str(local["id"]) and not edges[id]["known_to"].has(actor):
					return false
			recipients[actor] = true
		ids[path["id"]] = true
	ids.clear()
	for node: Variant in value.get("transport_nodes", []):
		if not node is Dictionary or not FormalLedgerState.exact_fields(node, ["place_id", "capacity"]) or not _place(node["place_id"]) or not _number(node["capacity"], 1) or ids.has(node["place_id"]):
			return false
		ids[node["place_id"]] = true
	ids.clear()
	for policy: Variant in value.get("npc_finance", []):
		if not policy is Dictionary or not FormalLedgerState.exact_fields(policy, ["actor", "repay_due", "allow_exchange", "cash_floors", "borrow_limits", "fx_limits"]) or not policy["actor"] is String or ids.has(policy["actor"]) or (not firms.has(policy["actor"]) and (not actors.has(policy["actor"]) or actors[policy["actor"]]["control"] != "automatic")) or not policy["repay_due"] is bool or not policy["allow_exchange"] is bool:
			return false
		for field: String in ["cash_floors", "borrow_limits", "fx_limits"]:
			if not policy[field] is Dictionary:
				return false
			for currency: Variant in policy[field]:
				if not FormalLedgerState.currency_id(currency) or not currencies[policy["actor"]].has(currency):
					return false
				if field != "borrow_limits":
					if not FormalLedgerState.valid_amount(policy[field][currency]):
						return false
				else:
					var limit: Variant = policy[field][currency]
					if not limit is Dictionary or not FormalLedgerState.exact_fields(limit, ["daily_principal", "max_debt", "max_interest"]):
						return false
					for amount: Variant in limit.values():
						if not FormalLedgerState.valid_amount(amount):
							return false
		ids[policy["actor"]] = true
	return true

## Optional firm_operations rows: firm, planning_horizon (1..30), buffer_days
## (0..30), demand_window (1..30), manage_jobs. Job positions remain a configured
## ceiling; notice_delay on each template defaults to one host day.
## price_policies: firm, good, mode N2/N3, tick, window_days, minimum, maximum.
## N3 retains Lab's 2% step and quarter/four-times-initial bounds, with next-day effect.
## purchase_limits: actor, good, denomination, max_price; no implicit FX valuation.
## supplier_directory is explicit coarse information, never a stock/cash registry:
## seller, good, zone, known_to, available_day. Search policies name firm, local_zones,
## regional_zones, allow_wide, delay_days {LOCAL, REGIONAL, WIDE}, result_limit,
## Site stock, capacity and activities are explicit development facilities at host
## places. They do not infer factories from population or organization labels.
## site_id on policies addresses one site; omitted operating/search policies apply
## to the owner, while an omitted price site addresses its primary sales site.
## Need categories declare flow consumption or durable holdings and use priority.
## max_known and cooldown_days. Search results arrive through the existing inbox.
static func _operations(value: Dictionary, actors: Dictionary, firms: Dictionary) -> bool:
	var spec := normalize(value, [])
	var sites := spec["sites"] as Dictionary
	var seen: Dictionary = {}
	for row: Variant in value.get("firm_operations", []):
		if not row is Dictionary or not _fields(row, ["firm", "planning_horizon", "buffer_days", "demand_window", "manage_jobs"], ["site_id"]) or not firms.has(row["firm"]) or seen.has(str(row.get("site_id", row["firm"]))) or not row["manage_jobs"] is bool:
			return false
		for key: String in ["planning_horizon", "buffer_days", "demand_window"]:
			if not _number(row[key], 0 if key == "buffer_days" else 1) or int(row[key]) > 30:
				return false
		if row.has("site_id") and (not sites.has(row["site_id"]) or sites[row["site_id"]]["firm_id"] != row["firm"]):
			return false
		seen[str(row.get("site_id", row["firm"]))] = true
	seen.clear()
	for row: Variant in value.get("price_policies", []):
		if not row is Dictionary or not _fields(row, ["firm", "good", "mode", "tick", "window_days", "minimum", "maximum"], ["site_id"]) or not firms.has(row["firm"]) or not sites.has(policy_site(row, firms)) or sites[policy_site(row, firms)]["firm_id"] != row["firm"] or not sites[policy_site(row, firms)]["prices"].has(row["good"]) or row["mode"] not in ["N2", "N3"]:
			return false
		var key := policy_site(row, firms) + "|" + str(row["good"])
		if seen.has(key) or not _number(row["tick"], 1) or not _number(row["window_days"], 1) or int(row["window_days"]) > 30 or not FormalLedgerState.valid_amount(row["minimum"]) or not FormalLedgerState.valid_amount(row["maximum"]):
			return false
		var initial := int(sites[policy_site(row, firms)]["prices"][row["good"]])
		var tick := int(row["tick"])
		var lower: int = (initial + 4 * tick - 1) / (4 * tick) * tick
		if initial % tick != 0 or int(row["minimum"]) < lower or int(row["minimum"]) > initial or int(row["maximum"]) < initial or int(row["maximum"]) > 4 * initial or int(row["minimum"]) % tick != 0 or int(row["maximum"]) % tick != 0:
			return false
		seen[key] = true
	seen.clear()
	for row: Variant in value.get("purchase_limits", []):
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["actor", "good", "denomination", "max_price"]) or (not actors.has(row["actor"]) and not firms.has(row["actor"])) or row["good"] not in good_ids(value) or not FormalLedgerState.currency_id(row["denomination"]) or not FormalLedgerState.valid_amount(row["max_price"]):
			return false
		var key := str(row["actor"]) + "|" + str(row["good"]) + "|" + str(row["denomination"])
		if seen.has(key):
			return false
		seen[key] = true
	seen.clear()
	for row: Variant in value.get("supplier_directory", []):
		if not row is Dictionary or not _fields(row, ["seller", "good", "zone", "known_to", "available_day"], ["site_id"]) or not firms.has(row["seller"]) or not sites.has(row.get("site_id", configured_primary(firms, row["seller"]))) or sites[row.get("site_id", configured_primary(firms, row["seller"]))]["firm_id"] != row["seller"] or not sites[row.get("site_id", configured_primary(firms, row["seller"]))]["prices"].has(row["good"]) or not row["zone"] is String or row["zone"].is_empty() or not row["known_to"] is Array or not _number(row["available_day"]):
			return false
		var key := str(row.get("site_id", configured_primary(firms, row["seller"]))) + "|" + str(row["good"])
		if seen.has(key):
			return false
		var recipients: Dictionary = {}
		for firm: Variant in row["known_to"]:
			if not firm is String or (not firms.has(firm) and not sites.has(firm)) or firm == row["seller"] or (sites.has(firm) and sites[firm]["firm_id"] == row["seller"]) or recipients.has(firm):
				return false
			recipients[firm] = true
		seen[key] = true
	seen.clear()
	for row: Variant in value.get("supplier_search", []):
		if not row is Dictionary or not _fields(row, ["firm", "local_zones", "regional_zones", "allow_wide", "delay_days", "result_limit", "max_known", "cooldown_days"], ["scope_basis", "site_id"]) or not firms.has(row["firm"]) or seen.has(str(row.get("site_id", row["firm"]))) or not row["allow_wide"] is bool or row.get("scope_basis", "CONFIGURED") not in ["CONFIGURED", "HOST_SPACE"] or not row["delay_days"] is Dictionary or not FormalLedgerState.exact_fields(row["delay_days"], ["LOCAL", "REGIONAL", "WIDE"]):
			return false
		for key: String in ["local_zones", "regional_zones"]:
			if not row[key] is Array or row[key].size() > 16:
				return false
			var zones: Dictionary = {}
			for zone: Variant in row[key]:
				if not zone is String or zone.is_empty() or zones.has(zone):
					return false
				zones[zone] = true
		for delay: Variant in row["delay_days"].values():
			if not _number(delay, 1) or int(delay) > 30:
				return false
		if not _number(row["result_limit"], 1) or int(row["result_limit"]) > 8 or not _number(row["max_known"], 1) or int(row["max_known"]) > 32 or not _number(row["cooldown_days"], 1) or int(row["cooldown_days"]) > 365:
			return false
		if row.has("site_id") and (not sites.has(row["site_id"]) or sites[row["site_id"]]["firm_id"] != row["firm"]):
			return false
		seen[str(row.get("site_id", row["firm"]))] = true
	return true

static func valid_credit_offers(settings: Dictionary) -> bool:
	if not settings.has("credit_offers"):
		return true
	if not settings["credit_offers"] is Array:
		return false
	var fields: Array[String] = Credit.TERM_FIELDS.duplicate()
	fields.append("lender")
	for raw: Variant in settings["credit_offers"]:
		if not raw is Dictionary or not FormalLedgerState.exact_fields(raw, fields) or not raw["lender"] is String or raw["lender"].is_empty():
			return false
		var terms := (raw as Dictionary).duplicate(true)
		terms.erase("lender")
		if not Credit.valid_terms(terms) or (not is_multi(settings) and terms["denomination"] != FormalLedgerState.DENOMINATION):
			return false
	return true

static func credit_parties_valid(settings: Dictionary, actors: Dictionary, firms: Dictionary) -> bool:
	for policy: Dictionary in settings.get("credit_offers", []):
		var lender := str(policy["lender"])
		var borrower := str(policy["borrower"])
		if not firms.has(lender) and (not actors.has(lender) or actors[lender]["control"] != "automatic"):
			return false
		if borrower == lender or (not borrower.is_empty() and not firms.has(borrower) and (not actors.has(borrower) or actors[borrower]["control"] == "dormant")):
			return false
	return true

static func _number(value: Variant, minimum: int = 0) -> bool:
	return FormalLedgerState.valid_amount(value) and int(value) >= minimum and int(value) <= 1000000

static func _stock(value: Variant, goods: Array[String] = GOODS) -> bool:
	if not value is Dictionary or not FormalLedgerState.exact_fields(value, goods):
		return false
	for amount: Variant in value.values():
		if not _number(amount):
			return false
	return true

static func _account(value: Variant, accounts: Dictionary) -> bool:
	if not value is String or not str(value).begins_with("account:") or str(value).length() <= 8 or accounts.has(value):
		return false
	accounts[value] = true
	return true

static func named_ids(settings: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if is_multi(settings):
		for actor: Dictionary in settings["actors"]:
			if actor["kind"] == "named":
				result.append(actor["id"])
	result.sort()
	return result

static func canonical(settings: Dictionary) -> Dictionary:
	var result := settings.duplicate(true)
	if not is_multi(result):
		return result
	for key: String in ["actors", "firms", "jobs"]:
		result[key].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	result["information"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["actor"]) + str(a["kind"]) + str(a["candidate"]) < str(b["actor"]) + str(b["kind"]) + str(b["candidate"]))
	return result

static func normalize(settings: Dictionary, persons: Array[String]) -> Dictionary:
	if is_multi(settings):
		var result := settings.duplicate(true)
		for key: String in ["actors", "firms", "jobs"]:
			var mapped: Dictionary = {}
			for row: Dictionary in result[key]:
				mapped[row["id"]] = row
			result[key] = mapped
		result["information"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["actor"]) + str(a["kind"]) + str(a["candidate"]) < str(b["actor"]) + str(b["kind"]) + str(b["candidate"]))
		return _normalize_production(result)
	var result := {"actors": {}, "firms": {}, "jobs": {}, "information": [], "route": {"capacity": settings["route_capacity"], "delay": settings["delivery_delay"]}}
	for id: String in persons:
		result["actors"][id] = {"id": id, "kind": "named", "control": "player", "members": 1, "account_id": FormalPersonalEconomyState.personal_account_id(id), "cash": settings["opening_cash"], "stock": ZERO.duplicate(), "skill": 1, "daily_need": 2, "population_start": 0}
	var cohort := EconomyR1Slice.COHORT
	result["actors"][cohort] = {"id": cohort, "kind": "cohort", "control": "automatic", "members": settings["background_members"], "account_id": "account:r1_background", "cash": int(settings["background_members"]) * int(settings["opening_cash"]), "stock": ZERO.duplicate(), "skill": 1, "daily_need": 2, "population_start": 0}
	for id: String in [EconomyR1Slice.FARM, EconomyR1Slice.BAKER, EconomyR1Slice.BEANER]:
		var stock := ZERO.duplicate()
		var recipe: Dictionary = {}
		var targets := ZERO.duplicate()
		var prices: Dictionary = {}
		var supplies: Array[String] = []
		if id == EconomyR1Slice.FARM:
			stock["grain"] = settings["grain_stock"]
			recipe = {"good": "grain", "materials": ZERO.duplicate(), "hours": 1}
			targets["grain"] = 12
			prices["grain"] = settings["grain_price"]
		elif id == EconomyR1Slice.BAKER:
			stock["bread"] = settings["bread_stock"]
			stock["grain"] = 16
			recipe = {"good": "bread", "materials": {"beans": 0, "bread": 0, "grain": 2}, "hours": 1}
			targets["bread"] = 8
			targets["grain"] = 12
			prices["bread"] = settings["bread_price"]
			supplies = [EconomyR1Slice.FARM + "|grain"]
		else:
			stock["beans"] = settings["beans_stock"]
			prices["beans"] = settings["beans_price"]
		result["firms"][id] = {"id": id, "account_id": "account:" + id.trim_prefix("firm:"), "place_id": PLACE, "cash": settings["firm_cash"], "stock": stock, "recipe": recipe, "capacity": 8, "targets": targets, "prices": prices, "suppliers": supplies}
	for id: String in [EconomyR1Slice.JOB_FARM, EconomyR1Slice.JOB_BAKER]:
		result["jobs"][id] = {"id": id, "employer": EconomyR1Slice.FARM if id == EconomyR1Slice.JOB_FARM else EconomyR1Slice.BAKER, "positions": settings["background_members"] if id == EconomyR1Slice.JOB_FARM else persons.size(), "skill": 1, "hours": 2, "place": PLACE, "wage_per_hour": settings["wage_per_hour"], "wage_delay": settings["wage_delay"]}
	for actor: String in result["actors"]:
		if actor == cohort:
			result["information"].append({"actor": actor, "kind": "job", "candidate": EconomyR1Slice.JOB_FARM, "delivery_day": 0})
			for supplier: String in [EconomyR1Slice.BEANER + "|beans", EconomyR1Slice.BAKER + "|bread"]:
				result["information"].append({"actor": actor, "kind": "supplier", "candidate": supplier, "delivery_day": 0})
		else:
			for job: String in [EconomyR1Slice.JOB_BAKER, EconomyR1Slice.JOB_FARM]:
				result["information"].append({"actor": actor, "kind": "job", "candidate": job, "delivery_day": settings["job_delay"] if job == EconomyR1Slice.JOB_BAKER else settings["second_job_delay"]})
			for supplier: String in [EconomyR1Slice.BAKER + "|bread", EconomyR1Slice.BEANER + "|beans"]:
				result["information"].append({"actor": actor, "kind": "supplier", "candidate": supplier, "delivery_day": settings["supplier_delay"]})
	result["route"].merge({"id": "edge:r2_paris_local", "place_id": PLACE, "basis": "SYNTHETIC"})
	return _normalize_production(result)


## Goods supply configured need categories. Empty needs mark industrial inputs.
## Quantities are developer parameters, not calibrated historical consumption.
static func good_ids(settings: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	if not settings.has("goods"):
		return GOODS.duplicate()
	if not settings["goods"] is Array:
		return ids
	for row: Variant in settings["goods"]:
		if row is Dictionary and row.get("id") is String:
			ids.append(row["id"])
	ids.sort()
	return ids

static func consumption(settings: Dictionary) -> Dictionary:
	if not settings.has("goods"):
		return {"beans": {"food": 2}, "bread": {"food": 1}}
	var result: Dictionary = {}
	for row: Dictionary in settings["goods"]:
		if not row["needs"].is_empty():
			result[row["id"]] = row["needs"].duplicate(true)
	return result


static func zero_stock(goods: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for good: String in goods:
		result[good] = 0
	return result

static func _goods_valid(settings: Dictionary) -> bool:
	if not _categories_valid(settings):
		return false
	if not settings.has("goods"):
		return categories(settings).has("food")
	if not settings["goods"] is Array or settings["goods"].is_empty() or settings["goods"].size() > 64:
		return false
	var seen: Dictionary = {}
	for row: Variant in settings["goods"]:
		if not row is Dictionary or not _fields(row, ["id", "needs"], ["unit_id", "unit_name_zh", "capital_uses", "unit_weight", "daily_loss"]) or not row["id"] is String or row["id"].is_empty() or "|" in row["id"] or ":" in row["id"] or seen.has(row["id"]) or not row["needs"] is Dictionary:
			return false
		for physical: String in ["unit_weight", "daily_loss"]:
			if row.has(physical):
				var m: Variant = row[physical]
				if not m is Dictionary or not FormalLedgerState.exact_fields(m, ["numerator", "denominator", "unit", "basis"]) or not _number(m["numerator"]) or not _number(m["denominator"], 1) or not m["unit"] is String or m["unit"].is_empty() or not m["basis"] is String or m["basis"].is_empty(): return false
		for field: String in ["unit_id", "unit_name_zh"]:
			if row.has(field) and (not row[field] is String or row[field].is_empty()):
				return false
		if row.has("capital_uses"):
			if not row["capital_uses"] is Array or row["capital_uses"].is_empty(): return false
			var uses: Dictionary = {}
			for use: Variant in row["capital_uses"]:
				if not use is String or use not in ["CONSTRUCTION_MATERIAL", "INSTALLABLE_EQUIPMENT", "INSTALLATION_INPUT", "MAINTENANCE_INPUT"] or uses.has(use): return false
				uses[use] = true
		for need: Variant in row["needs"]:
			if not categories(settings).has(need) or not _number(row["needs"][need], 1):
				return false
		seen[row["id"]] = true
	return true

## One stock point per operating site. Its shared capacity is equipment already
## declared by development content. Enabling another activity does not add it.
## Activity fields: id, place_id, outputs, materials, hours, capacity_units,
## enabled, basis. Outputs are sparse positive batch yields; materials are dense.
static func _production_valid(firm: Dictionary, goods: Array[String]) -> bool:
	if firm.has("recipe") == firm.has("activities"):
		return false
	if firm.has("recipe"):
		if not firm["recipe"] is Dictionary:
			return false
		var recipe := firm["recipe"] as Dictionary
		return recipe.is_empty() or (FormalLedgerState.exact_fields(recipe, ["good", "materials", "hours"]) and recipe["good"] in goods and _stock(recipe["materials"], goods) and int(recipe["materials"][recipe["good"]]) == 0 and _number(recipe["hours"], 1) and firm["prices"].has(recipe["good"]))
	if not firm["activities"] is Array or firm["activities"].size() > 32:
		return false
	var ids: Dictionary = {}
	for activity: Variant in firm["activities"]:
		if not activity is Dictionary or not FormalLedgerState.exact_fields(activity, ["id", "place_id", "outputs", "materials", "hours", "capacity_units", "enabled", "basis"]) or not activity["id"] is String or not str(activity["id"]).begins_with("activity:") or ids.has(activity["id"]) or activity["place_id"] != firm["place_id"] or not activity["enabled"] is bool or activity["basis"] != "DEVELOPMENT_CONFIGURATION" or not _number(activity["hours"], 1) or not _number(activity["capacity_units"], 1) or not _stock(activity["materials"], goods) or not activity["outputs"] is Dictionary or activity["outputs"].is_empty():
			return false
		for good: Variant in activity["outputs"]:
			if good not in goods or not _number(activity["outputs"][good], 1) or int(activity["materials"][good]) != 0:
				return false
		ids[activity["id"]] = true
	return activity_order(firm["activities"]).size() == firm["activities"].size()

## Bounded local dependency order, not a world production graph. Cycles require
## a separate scheduling policy and are rejected rather than instant self-funding.
static func activity_order(activities: Array) -> Array[String]:
	var result: Array[String] = []
	var remaining: Dictionary = {}
	for row: Dictionary in activities:
		remaining[row["id"]] = row
	while not remaining.is_empty():
		var ready: Array[String] = []
		for id: String in remaining:
			var depends: bool = false
			for other: String in remaining:
				if other == id:
					continue
				for good: String in remaining[other]["outputs"]:
					if int(remaining[id]["materials"].get(good, 0)) > 0:
						depends = true
			if not depends:
				ready.append(id)
		if ready.is_empty():
			return []
		ready.sort()
		for id: String in ready:
			result.append(id)
			remaining.erase(id)
	return result

static func _normalize_production(spec: Dictionary) -> Dictionary:
	spec["good_ids"] = good_ids(spec)
	spec["consumption"] = consumption(spec)
	spec["categories"] = categories(spec)
	var sites: Dictionary = {}
	for row: Dictionary in spec["actors"].values():
		row["needs"] = actor_needs(row)
	for row: Dictionary in spec["firms"].values():
		if row.has("sites") and row["sites"] is Array and (row["sites"].is_empty() or row["sites"][0] is String):
			for id: String in row["sites"]:
				sites[id] = spec["sites"][id]
			continue
		var ids: Array[String] = []
		if row.has("sites"):
			for site: Dictionary in row["sites"]:
				var normalized := _normalized_site(site, row["id"], spec["good_ids"])
				sites[site["id"]] = normalized
				ids.append(site["id"])
		else:
			var site := _legacy_site(row, spec["good_ids"])
			sites[site["id"]] = site
			ids.append(site["id"])
		row["sites"] = ids
		row["primary_site"] = ids[0]
		for key: String in ["stock", "capacity", "targets", "prices", "recipe", "activities", "activity_order", "suppliers"]:
			row.erase(key)
	spec["sites"] = sites
	for job: Dictionary in spec["jobs"].values():
		job["site_id"] = job.get("site_id", spec["firms"][job["employer"]]["primary_site"])
	return spec


static func saved_spec(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("firms") is Dictionary or not value.get("actors") is Dictionary or not value.get("jobs") is Dictionary or not value.get("route") is Dictionary or not _goods_valid(value):
		return {}
	for row: Variant in value["firms"].values():
		if not row is Dictionary or not row.get("id") is String or not _place(row.get("place_id")):
			return {}
		if not row.has("sites") and (not row.get("prices") is Dictionary or not _production_valid(row, good_ids(value))):
			return {}
	for actor: Variant in value["actors"].values():
		if not actor is Dictionary or not actor.has("daily_need") or not actor.has("control") or not _actor_needs_valid(actor, value):
			return {}
	for firm: Dictionary in value["firms"].values():
		if not firm.has("sites"):
			continue
		if not firm["sites"] is Array or firm["sites"].is_empty() or not value.get("sites") is Dictionary or firm.get("primary_site") != firm["sites"][0]:
			return {}
		for id: Variant in firm["sites"]:
			var site: Variant = value["sites"].get(id)
			if not id is String or not site is Dictionary or site.get("id") != id or site.get("firm_id") != firm["id"] or not _site_valid(site, good_ids(value)):
				return {}
	for job: Variant in value["jobs"].values():
		if not job is Dictionary or not value["firms"].has(job.get("employer")):
			return {}
	var spec := value.duplicate(true) as Dictionary
	if not is_multi(spec):
		for key: String in ["id", "place_id", "basis"]:
			if not spec["route"].has(key):
				spec["route"][key] = {"id": "edge:r2_paris_local", "place_id": PLACE, "basis": "SYNTHETIC"}[key]
	return _normalize_production(spec)



static func primary_site_id(firm: String) -> String:
	return "site:" + firm.trim_prefix("firm:") + ":primary"

static func configured_primary(firms: Dictionary, firm: String) -> String:
	var row := firms.get(firm, {}) as Dictionary
	if row.has("primary_site"):
		return str(row["primary_site"])
	if row.get("sites") is Array and not row["sites"].is_empty():
		return str(row["sites"][0]["id"]) if row["sites"][0] is Dictionary else str(row["sites"][0])
	return primary_site_id(firm)

static func policy_site(row: Dictionary, firms: Dictionary = {}) -> String:
	return str(row.get("site_id", configured_primary(firms, str(row["firm"]))))

static func _prices_valid(prices: Variant, goods: Array[String]) -> bool:
	if not prices is Dictionary:
		return false
	for good: Variant in prices:
		if good not in goods or not _number(prices[good], 1):
			return false
	return true

static func _site_valid(site: Dictionary, goods: Array[String]) -> bool:
	if not _place(site["place_id"]) or not site["roles"] is Array or site["roles"].is_empty() or not _stock(site["stock"], goods) or not _stock(site["targets"], goods) or not _prices_valid(site["prices"], goods) or not _number(site["capacity"]) or not _number(site["coordination_delay"]) or int(site["coordination_delay"]) > 30 or not site["suppliers"] is Array or not site["activities"] is Array or site["basis"] != "DEVELOPMENT_CONFIGURATION":
		return false
	for flag: String in ["enabled", "production_enabled", "accepting_business"]:
		if not site[flag] is bool:
			return false
	var seen: Dictionary = {}
	for role: Variant in site["roles"]:
		if role not in ["production", "storage", "sales"] or seen.has(role):
			return false
		seen[role] = true
	if (not site["roles"].has("production") and (int(site["capacity"]) > 0 or not site["activities"].is_empty())) or (not site["roles"].has("sales") and not site["prices"].is_empty()):
		return false
	return _production_valid(site, goods)

static func _normalized_site(site: Dictionary, firm: String, goods: Array[String]) -> Dictionary:
	var result := site.duplicate(true)
	result["firm_id"] = firm
	if result.has("recipe"):
		result["activities"] = []
		var recipe := result["recipe"] as Dictionary
		if not recipe.is_empty():
			result["activities"].append({"id": "activity:" + firm.trim_prefix("firm:") + ":primary", "place_id": result["place_id"], "outputs": {recipe["good"]: 1}, "materials": recipe["materials"].duplicate(true), "hours": recipe["hours"], "capacity_units": 1, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION"})
		result.erase("recipe")
	result["activity_order"] = activity_order(result["activities"])
	return result

static func _legacy_site(firm: Dictionary, goods: Array[String]) -> Dictionary:
	var site := {"id": primary_site_id(firm["id"]), "place_id": firm["place_id"], "stock": firm["stock"].duplicate(true), "capacity": firm["capacity"], "targets": firm["targets"].duplicate(true), "prices": firm["prices"].duplicate(true), "suppliers": firm["suppliers"].duplicate(), "roles": ["production", "storage", "sales"], "enabled": true, "production_enabled": true, "accepting_business": true, "basis": "DEVELOPMENT_CONFIGURATION", "coordination_delay": 0}
	if firm.has("recipe"):
		site["recipe"] = firm["recipe"].duplicate(true)
	else:
		site["activities"] = firm["activities"].duplicate(true)
	return _normalized_site(site, firm["id"], goods)

static func categories(settings: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in settings.get("need_categories", [{"id": "food", "mode": "flow", "priority": 0}]):
		result[row["id"]] = row.duplicate(true)
	return result

static func _categories_valid(settings: Dictionary) -> bool:
	if not settings.get("need_categories", []) is Array or settings.get("need_categories", []).size() > 16:
		return false
	var seen: Dictionary = {}
	for row: Variant in settings.get("need_categories", [{"id": "food", "mode": "flow", "priority": 0}]):
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["id", "mode", "priority"]) or not row["id"] is String or row["id"].is_empty() or row["mode"] not in ["flow", "durable"] or not _number(row["priority"]) or seen.has(row["id"]):
			return false
		seen[row["id"]] = true
	return not seen.is_empty()

static func actor_needs(actor: Dictionary) -> Dictionary:
	return (actor["needs"] as Dictionary).duplicate(true) if actor.has("needs") else {"food": actor["daily_need"]}

static func _actor_needs_valid(actor: Dictionary, settings: Dictionary) -> bool:
	if actor.has("needs") and not actor["needs"] is Dictionary:
		return false
	var needs := actor_needs(actor)
	for category: Variant in needs:
		if not categories(settings).has(category) or not _number(needs[category]) or (actor["control"] == "dormant" and int(needs[category]) > 0):
			return false
	return int(needs.get("food", 0)) == int(actor["daily_need"])


static func _lifecycle_configuration(value: Dictionary, actors: Dictionary, firms: Dictionary) -> bool:
	for field: String in ["npc_residence", "firm_management_permissions"]:
		if not value.get(field, []) is Array or value.get(field, []).size() > 64 or (value.has(field) and not value.get("host_personal_accounts", false)): return false
	var people: Dictionary = {}
	for row: Variant in value.get("npc_residence", []):
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["person_id", "permission_id", "min_employment_days", "min_work_hours", "cooldown_days", "max_moves", "basis"]) or not row["person_id"] is String or not actors.has(row["person_id"]) or actors[row["person_id"]]["kind"] != "named" or actors[row["person_id"]]["control"] != "automatic" or people.has(row["person_id"]) or row["basis"] != "EXPLICIT_DEVELOPMENT_NPC_RESIDENCE_POLICY": return false
		for key: String in ["min_employment_days", "min_work_hours", "cooldown_days", "max_moves"]:
			if not _number(row[key], 1) or int(row[key]) > 10000: return false
		var permitted: bool = false
		for permit: Dictionary in value.get("residence_permissions", []):
			if permit["person_id"] == row["person_id"] and permit["id"] == row["permission_id"]: permitted = true
		if not permitted: return false
		people[row["person_id"]] = true
	var pairs: Dictionary = {}
	for row: Variant in value.get("firm_management_permissions", []):
		if not row is Dictionary or not _fields(row, ["firm", "from_manager", "to_manager", "basis", "accept_automatically"], ["position_id", "capability_id"]) or not row["firm"] is String or not firms.has(row["firm"]) or not row["from_manager"] is String or not row["to_manager"] is String or row["from_manager"] == row["to_manager"] or not row["accept_automatically"] is bool or row["basis"] not in ["DEVELOPMENT_MANAGER_SUCCESSION", "HOST_APPOINTED_MANAGER_SUCCESSION"]: return false
		for key: String in ["from_manager", "to_manager"]:
			if row[key] != row["firm"] and (not actors.has(row[key]) or actors[row[key]]["kind"] != "named" or actors[row[key]]["control"] == "dormant"): return false
		var associated: bool = not str(firms[row["firm"]].get("host_organization_id", "")).is_empty()
		if associated != (row["basis"] == "HOST_APPOINTED_MANAGER_SUCCESSION"): return false
		if associated and (not row.get("position_id") is String or row["position_id"].is_empty() or not row.get("capability_id") is String or row["capability_id"].is_empty()): return false
		var pair := str(row["firm"])+"|"+str(row["from_manager"])+"|"+str(row["to_manager"])
		if pairs.has(pair): return false
		pairs[pair] = true
	return true
