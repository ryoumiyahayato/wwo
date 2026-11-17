class_name EconomyR1Slice
extends RefCounted
const SupplyContracts = preload("res://scripts/world/economy_supply_contracts.gd")
const CargoFulfilment = preload("res://scripts/world/economy_cargo_fulfilment.gd")
const LocalQuotations = preload("res://scripts/world/economy_local_quotations.gd")
const CapitalTransport = preload("res://scripts/world/economy_capital_transport.gd")
const SharedTransport = preload("res://scripts/world/economy_shared_transport.gd")
const StockLots = preload("res://scripts/world/economy_stock_lots.gd")
const Budget = preload("res://scripts/world/economy_procurement_budget.gd")
const Cohorts = preload("res://scripts/world/economy_cohort_rules.gd")
var _household_choice_observations: Dictionary={} # Transient developer observation, not formal economic state.
const HouseholdChoice=preload("res://scripts/world/economy_household_choice.gd")
const HouseholdTiming = preload("res://scripts/world/economy_household_timing.gd")
const PersonalArrangementTiming = preload("res://scripts/world/economy_personal_arrangement_timing.gd")
const ProcurementCash = preload("res://scripts/world/economy_procurement_cash.gd")
const ProductionBundle = preload("res://scripts/world/economy_production_bundle.gd")
const NewInputContribution = preload("res://scripts/world/economy_new_input_contribution.gd")
const OperatingInventory = preload("res://scripts/world/economy_operating_inventory.gd")

const CommodityMapping = preload("res://scripts/world/formal_commodity_mapping.gd")
## Authoritative native business implementation for the formal project.
## The independent worktree retains its previous research cases.
## Native economy boundary for the injected world. Clock, identities and money are injected
## host owners. Local feedback uses only received requests and own real deliveries.

signal safe_boundary

const SCHEMA_ID: String = "economy_native_slice_r1_v1"
const R2_SCHEMA_ID: String = "economy_native_slice_r2_v1"
const FARM: String = "firm:r1_farm"
const BAKER: String = "firm:r1_baker"
const BEANER: String = "firm:r1_beaner"
const COHORT: String = "cohort:country_fra:r1"
const JOB_FARM: String = "job:r1_farm"
const JOB_BAKER: String = "job:r1_baker"
const PLACE: String = "place:paris"
const COOPERATION_RECORD_LIMIT: int = 8
const COOPERATION_WINDOW_DAYS: int = 30
const N3_STEP_PERCENT: int = 2
const CONFIG_FIELDS: Array[String] = ["case_id", "background_members", "opening_cash", "firm_cash", "wage_per_hour", "wage_delay", "delivery_delay", "route_capacity", "job_delay", "supplier_delay", "second_job_delay", "bread_price", "beans_price", "grain_price", "grain_stock", "bread_stock", "beans_stock", "production_enabled", "player_choice", "stock_horizon"]
const Credit = preload("res://scripts/world/economy_bilateral_credit.gd")
const Exchange = preload("res://scripts/world/economy_currency_exchange.gd")
const Assets = preload("res://scripts/world/economy_asset_market.gd")
const Capital = preload("res://scripts/world/economy_capital_formation.gd")
const Liquidity = preload("res://scripts/world/economy_liquidity_rules.gd")
const CostAllocation = preload("res://scripts/world/economy_cost_allocation.gd")
const WindDown = preload("res://scripts/world/economy_wind_down.gd")
const LaborMarket = preload("res://scripts/world/economy_labor_market.gd")
const Commercial = preload("res://scripts/world/economy_commercial_information.gd")
const Retail = preload("res://scripts/world/economy_retail_rules.gd")
const Leases = preload("res://scripts/world/economy_lease_market.gd")
const Services = preload("res://scripts/world/economy_service_market.gd")

var error: String = ""
var processing: bool = false
var config: Dictionary = {}
# Configuration is an intention. Host composition publishes responsibility only
# after accounts, physical state and population reservations have succeeded.
var _management: Dictionary = {}
var _scope_requests: Dictionary = {}
var _subject_activation: Dictionary = {}
var _property_handovers: Dictionary = {}
var _pending_scope_requests: Array[String] = []
var _enterprise_changes: Dictionary = {}
var _employment_ends: Dictionary = {}
var _pending_enterprise_changes: Array[String] = []
var _pending_employment_ends: Array[String] = []
var day: int = 0
var next_order: int = 1
var next_shipment: int = 1
var phase: String = "READY"
var _world_ref: WeakRef
var _world: WorldState:
	get:
		return _world_ref.get_ref() as WorldState if _world_ref != null else null
	set(value):
		_world_ref = weakref(value) if value != null else null
var _actors: Dictionary = {}
var _cargo_fulfilment: CargoFulfilment = CargoFulfilment.new()
var _moving_shipments: Dictionary = {} # Derived active physical process IDs.
var _shared: SharedTransport = SharedTransport.new()
var _capital_transport := CapitalTransport.new()
var _local_quotes := LocalQuotations.new()
var _lots: StockLots = StockLots.new()
var _budgets: Budget = Budget.new()
var _legacy_stock_boundary: Dictionary = {}
var _stocks: Dictionary:
	get: return _lots.projection()
var _contracts: Dictionary = {}
var _supply: RefCounted = SupplyContracts.new()
var _work_queue: Dictionary = {}
var _work_records: Dictionary = {}
## Optional developer observation of one procurement boundary; not saved or adopted.
var _procurement_diagnostics_enabled: bool = false
var _dated_input_procurement_enabled: bool = false # Explicit candidate Runtime policy; not saved economic authority.
var _procurement_observations: Array[Dictionary] = []
var _wages: Dictionary = {}
var _open_wages: Array[String] = []
var _orders: Dictionary = {}
var _pending_orders: Array[String] = []
var _active_orders: Array[String] = []
var _shipments: Dictionary = {}
var _delivery_receipts: Dictionary = {}
var _messages: Array[Dictionary] = []
var _receipts: Dictionary = {}
var _commands: Dictionary = {}
var _needs: Dictionary = {}
var _totals: Dictionary = {}
var _relations: Dictionary = {}
var _plans: Dictionary = {}
var _firm_state: Dictionary = {}
var _goods: Array[String] = []
var _services: Dictionary = {}
var _site_state: Dictionary = {}
var _site_reports: Dictionary = {}
var _quote_state: Dictionary = {}
var _job_postings: Dictionary = {}
var _search_state: Dictionary = {}
var _request_window: Dictionary = {}
var _labor: Dictionary = {}
var _capital_work_ids: Array[String] = []
var _physical_totals: Dictionary = {}
var _spec: Dictionary = {}
var _firm_knowledge: Dictionary = {}
var _transport: Dictionary = {}
var _orders_by_buyer: Dictionary = {}
var _active_sales_by_key: Dictionary = {} # Derived seller-site/good access; not persisted.
var _recent_buy_commands: Dictionary = {} # Original IDs only, bounded diagnostic access.
var _active_by_buyer: Dictionary = {}
var _pending_by_key: Dictionary = {}
var _wages_by_worker: Dictionary = {}
var _future_wages: Dictionary = {}
var _matured_wages: Array[String] = []
# Derived access paths. No snapshot fields, money or physical stock authority.
var _route_rows: Dictionary = {}
var _paths_by_endpoints: Dictionary = {}
var _directory_by_candidate: Dictionary = {}
var _directory_by_good: Dictionary = {}
var _node_capacities: Dictionary = {}
var _configuration_queries_ready: bool = false
var _deliveries_by_order: Dictionary = {}
var _shipments_by_order: Dictionary = {}
var _shipments_by_destination_good: Dictionary = {}
var _order_days: Dictionary = {}
var _delivery_days: Dictionary = {}
var _pending_ids_by_key: Dictionary = {}
var _incoming_by_key: Dictionary = {}
var _collected_by_shipment: Dictionary = {}
var _wage_days: Dictionary = {}
var _open_wages_by_employer: Dictionary = {}
var _repayment_days: Dictionary = {}
var _employment_observations: Dictionary = {}
var _accepted_travel_count: int = 0
var _cohort_search_day: Dictionary = {}
var _decision_counts: Dictionary = {}
var _regional_work: Dictionary = {}
var _regional_trade: Dictionary = {}
var _income_by_actor: Dictionary = {}
var _credit: Credit = Credit.new()
var _exchange: Exchange = Exchange.new()
var _assets: Assets = Assets.new()
var _capital: Capital = Capital.new()
var _costs: CostAllocation = CostAllocation.new()
var _service_market: Services = Services.new()
var _leases: Leases = Leases.new()
var _retail: Retail = Retail.new()
var _commercial: Commercial = Commercial.new()
var _labor_market: LaborMarket = LaborMarket.new()
var _wind_down: WindDown = WindDown.new()


func bind(world: WorldState, settings: Dictionary, admission_minutes: Dictionary = {}) -> bool:
	if not _actors.is_empty() or not _stocks.is_empty():
		return _fail("Live native scope is pinned to its saved configuration; responsibility handover is required before rebinding")
	if world == null or not valid_config(settings):
		return _fail("Invalid R1 world or configuration")
	_world = world
	_capital.bind(self)
	_local_quotes.bind(self)
	_supply.bind(self)
	config = EconomySliceConfig.canonical(settings)
	_costs.bind(self)
	_lots.costs = _costs
	_service_market.bind(self)
	_retail.bind(self)
	_commercial.bind(self)
	_labor_market.bind(self)
	_wind_down.bind(self)
	_leases.bind(self)
	_invalidate_configuration_queries()
	_subject_activation = admission_minutes.duplicate(true)
	_spec = EconomySliceConfig.normalize(config, world.person_overlay.person_ids())
	_invalidate_configuration_queries()
	_goods.assign(_spec["good_ids"])
	_lots.configure(_goods, _actor_ids_from_spec())
	_budgets.configure(config.get("procurement_budgets", []))
	_cargo_fulfilment.bind(self)
	if not _leases.validate_host(): return _fail(_leases.error)
	for rule: Dictionary in _budgets.rules:
		var valid_subject: bool = _spec["firms"].has(rule["subject"])
		for firm: String in _firm_ids():
			if str(_spec["firms"][firm].get("host_organization_id", "")) == rule["subject"]:
				valid_subject = true
				_budgets.subject_aliases[firm] = rule["subject"]
		for carrier: Dictionary in config.get("carriers",[]):
			if carrier["id"]==rule["subject"]: valid_subject=true
			if carrier.get("host_organization_id","")==rule["subject"]:
				valid_subject=true
				_budgets.subject_aliases[carrier["id"]]=rule["subject"]
		if not valid_subject: return _fail("Budget has no stable enterprise/organization subject")
		if rule["basis"] != "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY":
			var grant := _world.organization_state.authority_grant(rule["root_authority"])
			if grant.is_empty() or grant.get("operation") != "economy.procure": return _fail("Budget requires an actual economy.procure root authorization")
			var organization := _cargo_fulfilment._host_organization(rule["subject"])
			if organization.is_empty(): organization=rule["subject"]
			if grant.get("represented_entity") != organization: return _fail("Budget root belongs to another organization")

	if not _validate_financial_composition(): return false
	_capital_transport.bind(self)
	if not _shared.bind(self): return _fail(_shared.error if not _shared.error.is_empty() else "Shared transport lacks explicit host link, carrier work site, node facilities or windows")
	_services = _spec["consumption"]
	_management = {"scope_id": str(config.get("management_scope", {}).get("id", config["case_id"])), "status": "PREPARED", "activation_minute": 0}
	if not EconomySliceConfig.credit_parties_valid(config, _spec["actors"], _spec["firms"]):
		return _fail("Credit policy must belong to an existing automatic lender")
	_credit.bind(world.ledger_state)
	_exchange.bind(world.ledger_state, config)
	_assets.bind(world.ledger_state, config, self)
	for row: Dictionary in _spec["actors"].values():
		if not world.spatial_catalog.has_place(str(row.get("place_id", PLACE))):
			return _fail("Unknown actor place: " + str(row["id"]) + "/" + str(row.get("place_id", PLACE)))
		if (row["kind"] == "cohort" and world.population_state.unit_for_place(str(row.get("place_id", PLACE))).is_empty()) or (row["kind"] == "named" and world.population_state.unit_for_person(row["id"]).is_empty()):
			return _fail("Actor place has no admitted host population unit: " + str(row["id"]))
	if not _population_bindings_valid():
		return false
	if uses_host_accounts() and not world.population_state.matches_place_population_bindings(config.get("place_population_bindings", [])): return _fail("Economic configuration differs from current place population bindings")
	if not CommodityMapping.bindings_valid(config.get("commodity_mappings", []), world.economy_state, config): return _fail("Commodity mapping differs from admitted units or source")
	for permit: Dictionary in config.get("residence_permissions", []):
		if not world.person_overlay.has_person(permit["person_id"]) or world.population_state.unit(permit["source_unit_id"]).is_empty() or world.population_state.unit(permit["destination_unit_id"]).is_empty(): return _fail("Residence permission lacks host identities")
		for place: String in permit["place_ids"]:
			if world.population_state.unit_for_place(place) != permit["destination_unit_id"]: return _fail("Residence permit destination differs from its population unit")
	for row: Dictionary in _spec["firms"].values():
		if not world.spatial_catalog.has_place(row["place_id"]):
			return _fail("Unknown firm place: " + str(row["id"]) + "/" + str(row["place_id"]))
	for site: Dictionary in _spec["sites"].values():
		if not world.spatial_catalog.has_place(site["place_id"]):
			return _fail("Unknown operating site place: " + str(site["id"]) + "/" + str(site["place_id"]))
	for row: Dictionary in config.get("carriers", []):
		if not world.spatial_catalog.has_place(row["place_id"]):
			return _fail("Unknown carrier place")
	for route: Dictionary in _all_routes().values():
		if not world.spatial_catalog.has_place(route["from_place_id"]) or not world.spatial_catalog.has_place(route["to_place_id"]):
			return _fail("Unknown transport endpoint")
		if route.get("basis", "SYNTHETIC") == "HOST_LINK":
			var link := world.spatial_catalog.get_link(route["source_link_id"])
			var forward: bool = link.get("from_place_id") == route["from_place_id"] and link.get("to_place_id") == route["to_place_id"]
			var reverse: bool = link.get("to_place_id") == route["from_place_id"] and link.get("from_place_id") == route["to_place_id"]
			if link.is_empty() or (not forward and not reverse):
				return _fail("Transport edge differs from its admitted host map link")
	for node: Dictionary in config.get("transport_nodes", []):
		if not world.spatial_catalog.has_place(node["place_id"]):
			return _fail("Unknown transfer node")
	return true


static func valid_config(value: Dictionary) -> bool:
	if EconomySliceConfig.is_multi(value):
		return EconomySliceConfig.valid(value)
	var fields: Array[String] = CONFIG_FIELDS.duplicate()
	if value.has("credit_offers"):
		fields.append("credit_offers")
	if not FormalLedgerState.exact_fields(value, fields) or not EconomySliceConfig.valid_credit_offers(value) or not value["case_id"] is String or value["case_id"].is_empty() or not value["production_enabled"] is bool or value["player_choice"] not in ["fixed", "substitute"]:
		return false
	for key: String in CONFIG_FIELDS:
		if key in ["case_id", "production_enabled", "player_choice"]:
			continue
		if not FormalLedgerState.valid_amount(value[key]) or int(value[key]) > 1000000:
			return false
	for key: String in ["background_members", "delivery_delay", "route_capacity", "bread_price", "beans_price", "grain_price", "stock_horizon"]:
		if int(value[key]) < 1:
			return false
	return true


func initialize() -> bool:
	if not _actors.is_empty() or _world.game_clock.total_minutes() != 0:
		return _fail("Repeated or late R1 initialization")
	if not _host_firm_bindings_valid() or not _personal_storage_bindings_valid():
		return false
	var ids := _world.person_overlay.person_ids()
	var expected_named: Array[String] = []
	for actor: String in _sorted_ids(_spec["actors"]):
		var row := _spec["actors"][actor] as Dictionary
		if row["kind"] == "named":
			expected_named.append(actor)
		elif int(row["population_start"]) + int(row["members"]) > int(_world.population_state.unit(_population_unit(actor)).get("remaining_background_population", 0)):
			return _fail("Background allocation exceeds host population")
	for person_id: String in expected_named:
		if not ids.has(person_id):
			return _fail("Configured person must already exist in the host overlay")
	var budget := _opening_budget()
	if not (_world.ledger_state.add_native_genesis(budget) if uses_host_accounts() else _world.ledger_state.configure(budget)):
		return _fail(_world.ledger_state.error)
	for denomination: String in _foreign_budgets():
		if not _world.ledger_state.configure_currency(denomination, int(_foreign_budgets()[denomination])):
			return _fail(_world.ledger_state.error)
	for person_id: String in expected_named:
		var person := _world.person_overlay.person(person_id)
		var place := str(_spec["actors"][person_id].get("place_id", PLACE))
		if str(person.get("current_place_id", "")) != place or str(person.get("population_territory_id", "")) != _world.population_state.unit_for_person(person_id):
			return _fail("Actor place differs from the host population identity")
	var initialization_ids: Array[String] = []
	if is_multi():
		initialization_ids = _sorted_ids(_spec["actors"])
	else:
		initialization_ids.assign(ids)
		initialization_ids.append(COHORT)
	for actor: String in initialization_ids:
		var row := _spec["actors"][actor] as Dictionary
		if not _add_actor(actor, int(row["members"]), str(row["control"]), str(row["account_id"])):
			return false
	for firm_id: String in _firm_ids():
		var account_id := _account(firm_id)
		if not _world.ledger_state.open_account(account_id, firm_id, "r1_firm"):
			return _fail(_world.ledger_state.error)
		var cash := int(_spec["firms"][firm_id]["cash"])
		if cash > 0 and not _world.ledger_state.transfer("r1:opening:" + firm_id, FormalLedgerState.SOURCE_ACCOUNT, account_id, cash, 0, "employer_reserve", firm_id):
			return _fail(_world.ledger_state.error)
	for site: String in _site_ids():
		_opening_stock(site, _spec["sites"][site]["stock"])
		_physical_totals[site] = {"produced": _zero_goods(), "used": _zero_goods()}
		_firm_knowledge[site] = [] if is_multi() else _spec["sites"][site]["suppliers"].duplicate()
	if not _initialize_currency_accounts():
		return false
	_assets.initialize()
	for actor: String in _actor_ids():
		for info: Dictionary in _spec["information"]:
			if info["actor"] == actor:
				_schedule_message(actor, info["kind"], info["candidate"], int(info["delivery_day"]))
	if is_multi():
		for info: Dictionary in _spec["information"]:
			if _spec["firms"].has(info["actor"]) or _spec["sites"].has(info["actor"]):
				_schedule_message(info["actor"], info["kind"], info["candidate"], int(info["delivery_day"]))
	_initialize_transport()
	_initialize_operations()
	_deliver_messages()
	_local_quotes.initialize()
	for person: String in personal_accounts():
		for good: String in _goods:
			if int(_stocks[person][good]) > 0:
				_world.personal_economy_state.record_native_source(person, _personal_opening_source(person, good), "native_opening")
	_management["status"] = "READY" if uses_host_accounts() else "ACTIVE"
	return true if uses_host_accounts() else _post_initial_credit_offers()


func _add_actor(actor: String, members: int, control: String, account_id: String) -> bool:
	var role := "r1_cohort" if _spec["actors"][actor]["kind"] == "cohort" else "personal_cash"
	if uses_host_accounts() and role == "personal_cash":
		var existing := _world.ledger_state.account(account_id)
		if existing.get("owner_id") != actor or existing.get("role") != role or int(_spec["actors"][actor]["cash"]) != 0:
			return _fail("Native person must reuse the existing formal cash account without another endowment")
	elif not _world.ledger_state.open_account(account_id, actor, role):
		return _fail(_world.ledger_state.error)
	var amount := int(_spec["actors"][actor]["cash"])
	if amount > 0 and not _world.ledger_state.transfer("r1:opening:" + actor, FormalLedgerState.SOURCE_ACCOUNT, account_id, amount, 0, "opening_cash", actor):
		return _fail(_world.ledger_state.error)
	_actors[actor] = {"members": members, "control": control, "account_id": account_id, "known_jobs": [], "known_suppliers": []}
	_opening_stock(actor, _spec["actors"][actor]["stock"])
	_physical_totals[actor] = {"produced": _zero_goods(), "used": _zero_goods()}
	_totals[actor] = {"categories": _initial_need_totals(actor), "work_hours": 0, "income": 0}
	return true


func _actor_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _actors:
		if subject_exit_minute(id) < 0: ids.append(id)
	ids.sort()
	return ids


func _account(actor: String, denomination: String = FormalLedgerState.DENOMINATION) -> String:
	actor = _owner(actor)
	if denomination != FormalLedgerState.DENOMINATION:
		return _world.ledger_state.owner_account(actor, denomination)
	if _spec["actors"].has(actor):
		return str(_spec["actors"][actor]["account_id"])
	if _spec["firms"].has(actor):
		return str(_spec["firms"][actor]["account_id"])
	for row: Dictionary in config.get("carriers", []):
		if row["id"] == actor:
			return str(row["account_id"])
	return ""

func _place(actor: String) -> String:
	if _spec["sites"].has(actor):
		return str(_spec["sites"][actor]["place_id"])
	if _spec["firms"].has(actor):
		return str(_spec["firms"][actor]["place_id"])
	if _spec["actors"].has(actor):
		return str(_world.person_overlay.person(actor).get("current_place_id", "")) if _spec["actors"][actor]["kind"] == "named" else str(_spec["actors"][actor].get("place_id", PLACE))
	return ""

func _foreign_budgets() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in config.get("currency_accounts", []):
		result[row["denomination"]] = int(result.get(row["denomination"], 0)) + int(row["cash"])
	return result

func _initialize_currency_accounts() -> bool:
	for row: Dictionary in config.get("carriers", []):
		if not _world.ledger_state.open_account(row["account_id"], row["id"], "r1_carrier"):
			return _fail(_world.ledger_state.error)
		if int(row["cash"]) > 0 and not _world.ledger_state.transfer("r1:opening:" + str(row["id"]), FormalLedgerState.SOURCE_ACCOUNT, row["account_id"], int(row["cash"]), 0, "employer_reserve", row["id"]):
			return _fail(_world.ledger_state.error)
	for row: Dictionary in config.get("currency_accounts", []):
		var owner := str(row["owner"])
		var role := "r1_firm" if _spec["firms"].has(owner) else "personal_cash" if _spec["actors"].has(owner) and _spec["actors"][owner]["kind"] == "named" else "r1_cohort" if _spec["actors"].has(owner) else "r1_carrier"
		if not _world.ledger_state.open_account(row["account_id"], owner, role, row["denomination"]):
			return _fail(_world.ledger_state.error)
		if int(row["cash"]) > 0 and not _world.ledger_state.transfer("r1:opening_currency:" + str(row["account_id"]), FormalLedgerState.currency_source(row["denomination"]), row["account_id"], int(row["cash"]), 0, "opening_cash", owner):
			return _fail(_world.ledger_state.error)
	return true

func is_multi() -> bool:
	return EconomySliceConfig.is_multi(config)

func _firm_ids() -> Array[String]:
	if is_multi():
		return _sorted_ids(_spec["firms"])
	var ids: Array[String] = [FARM, BAKER, BEANER]
	return ids

func _opening_budget() -> int:
	var total: int = 0
	for row: Dictionary in _spec["actors"].values():
		total += int(row["cash"])
	for row: Dictionary in _spec["firms"].values():
		total += int(row["cash"])
	for row: Dictionary in config.get("carriers", []):
		total += int(row["cash"])
	return total

func _delivery_delay() -> int:
	return int(_spec["route"]["delay"])

func _price(seller: String, good: String) -> int:
	seller = _inventory_key(seller)
	if not _local_quotes.rule(seller,good).is_empty():
		var published := _local_quotes.current(seller,good)
		if not published.is_empty(): return int(published["price"])
	return int(_quote_state.get(seller + "|" + good, {}).get("price", _spec["sites"][seller]["prices"].get(good, 0)))

func _invalidate_configuration_queries() -> void:
	_configuration_queries_ready = false
	_capital.invalidate_configuration()
	_route_rows.clear()
	_paths_by_endpoints.clear()
	_directory_by_candidate.clear()
	_directory_by_good.clear()
	_node_capacities.clear()

func _ensure_configuration_queries() -> void:
	if _configuration_queries_ready: return
	var local := _spec["route"] as Dictionary
	_route_rows[local["id"]] = {"id": local["id"], "from_place_id": local["place_id"], "to_place_id": local["place_id"], "capacity": local["capacity"], "delay": local["delay"], "carrier": "", "freight_per_unit": 0, "known_to": [], "basis": "SYNTHETIC"}
	for row: Dictionary in config.get("routes", []):
		_route_rows[row["id"]] = row.duplicate(true)
		_route_rows[row["id"]]["basis"] = row.get("basis", "SYNTHETIC")
	for row: Dictionary in _route_rows.values():
		var key := str(row["from_place_id"]) + "|" + str(row["to_place_id"])
		if not _paths_by_endpoints.has(key): _paths_by_endpoints[key] = []
		_paths_by_endpoints[key].append({"id": row["id"], "from_place_id": row["from_place_id"], "to_place_id": row["to_place_id"], "edge_ids": [row["id"]], "known_to": row["known_to"], "known_day": 0})
	for row: Dictionary in config.get("transport_paths", []):
		var ids := row["edge_ids"] as Array
		var origin := str(_route_rows[ids[0]]["from_place_id"])
		var destination := str(_route_rows[ids.back()]["to_place_id"])
		var key := origin + "|" + destination
		if not _paths_by_endpoints.has(key): _paths_by_endpoints[key] = []
		_paths_by_endpoints[key].append({"id": row["id"], "from_place_id": origin, "to_place_id": destination, "edge_ids": ids.duplicate(), "known_to": row["known_to"], "known_day": row["known_day"]})
	for entry: Dictionary in config.get("supplier_directory", []):
		var candidate := _directory_candidate(entry)
		if not _directory_by_candidate.has(candidate): _directory_by_candidate[candidate] = []
		_directory_by_candidate[candidate].append(entry)
		if not _directory_by_good.has(entry["good"]): _directory_by_good[entry["good"]] = []
		_directory_by_good[entry["good"]].append(entry)
	for node: Dictionary in config.get("transport_nodes", []): _node_capacities[node["place_id"]] = node["capacity"]
	_configuration_queries_ready = true

## Internal read-only configuration view. Live capacity is owned by _transport.
func _all_routes() -> Dictionary:
	_ensure_configuration_queries()
	return _route_rows

func _cargo_edge_valid(edge: Dictionary) -> bool:
	if edge.get("basis", "SYNTHETIC") != "HOST_LINK": return true
	var link := _world.spatial_catalog.get_link(edge["source_link_id"])
	if link.is_empty(): return false
	var origin := str(link.get("from_place_id", VNextSpatialCatalog.map_id_to_place_id(str(link.get("from_map_id", "")))))
	var destination := str(link.get("to_place_id", VNextSpatialCatalog.map_id_to_place_id(str(link.get("to_map_id", "")))))
	return (origin == edge["from_place_id"] and destination == edge["to_place_id"]) or (destination == edge["from_place_id"] and origin == edge["to_place_id"])

func _route_for(buyer: String, seller: String, path_id: String = "", buyer_site: String = "", seller_site: String = "") -> Dictionary:
	var origin := _place(_inventory_key(seller, seller_site))
	var destination := _place(_inventory_key(buyer, buyer_site))
	for path: Dictionary in _paths_for(_owner(buyer), origin, destination, day):
		if path_id.is_empty() or path["id"] == path_id:
			return path
	return {}


func _paths_for(buyer: String, origin: String, destination: String, known_day: int) -> Array[Dictionary]:
	_ensure_configuration_queries()
	var result: Array[Dictionary] = []
	for row: Dictionary in _paths_by_endpoints.get(origin + "|" + destination, []):
		if row["id"] != _spec["route"]["id"] and (not row["known_to"].has(buyer) or known_day < int(row["known_day"])): continue
		var valid: bool = true
		for edge_id: String in row["edge_ids"]:
			if not _cargo_edge_valid(_route_rows[edge_id]): valid = false; break
		if valid: result.append({"id": row["id"], "from_place_id": origin, "to_place_id": destination, "edge_ids": row["edge_ids"].duplicate()})
	return result

func _initialize_transport() -> void:
	_transport = {"edges": {}, "nodes": {}}
	for row: Dictionary in _all_routes().values():
		_transport["edges"][row["id"]] = {"period": day, "input_used": 0, "dispatched": 0, "holds": {}, "capacity": row["capacity"], "capacity_action": ""}
	for row: Dictionary in config.get("transport_nodes", []):
		_transport["nodes"][row["place_id"]] = {"dispatched": 0}

func _locked_legs(path: Dictionary, denomination: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var edges := _all_routes()
	for id: String in path["edge_ids"]:
		var edge := edges[id] as Dictionary
		result.append({"edge_id": id, "delay": edge["delay"], "freight_per_unit": edge["freight_per_unit"], "carrier_account": _account(str(edge["carrier"]), denomination) if int(edge["freight_per_unit"]) > 0 else ""})
	return result

func _freight(legs: Array) -> int:
	var total: int = 0
	for leg: Dictionary in legs:
		total += int(leg["freight_per_unit"])
	return total

func _travel_days(legs: Array) -> int:
	var total: int = 0
	for leg: Dictionary in legs:
		total += int(leg["delay"])
	return total

func _node_capacity(place: String) -> int:
	_ensure_configuration_queries()
	return int(_node_capacities.get(place, FormalLedgerState.MAX_AMOUNT))

func _node_available(place: String) -> int:
	return maxi(0, _node_capacity(place) - int(_transport["nodes"].get(place, {}).get("dispatched", 0)))

func _batch_limit(legs: Array) -> int:
	var amount := FormalLedgerState.MAX_AMOUNT
	var edges := _all_routes()
	for leg: Dictionary in legs:
		var edge := edges[leg["edge_id"]] as Dictionary
		if not _cargo_edge_valid(edge): return 0
		amount = mini(amount, mini(FormalLedgerState.MAX_AMOUNT if _shared.bindings.has(leg["edge_id"]) else int(edge["capacity"]), _node_capacity(edge["from_place_id"])))
	return amount

func _set_edge_capacity(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if _shared.bindings.has(payload.get("edge_id")): return _result(false, "CAPACITY_OWNED_BY_HOST_SPATIAL")
	if not FormalLedgerState.exact_fields(payload, ["edge_id", "capacity"]) or not payload["edge_id"] is String or not FormalLedgerState.valid_amount(payload["capacity"]) or not _all_routes().has(payload["edge_id"]):
		return _result(false, "INVALID_EDGE_CAPACITY")
	var edge := _all_routes()[payload["edge_id"]] as Dictionary
	if edge.get("capacity_manager", "") != actor:
		return _result(false, "NOT_TRANSPORT_CAPACITY_MANAGER")
	if int(payload["capacity"]) > int(edge["capacity"]):
		return _result(false, "EDGE_CAPACITY_LIMIT")
	# Closure affects entry only. Cargo already on an edge completes its locked
	# travel time; it is never returned, repriced, or teleported to another edge.
	_edge(payload["edge_id"])["capacity"] = payload["capacity"]
	_edge(payload["edge_id"])["capacity_action"] = action_id
	return {"accepted": true, "reason": "ACCEPTED", "edge_id": payload["edge_id"], "capacity": payload["capacity"]}


func _edge(id: String) -> Dictionary:
	return _transport["edges"][id]


func _route_available(path: Dictionary) -> int:
	for id: String in path["edge_ids"]:
		if _shared.alias_requires_binding(id): return 0
		if not _shared.bindings.has(id) and int(_edge(id)["capacity"]) == 0:
			return 0
	for id: String in path["edge_ids"]:
		if not _cargo_edge_valid(_all_routes()[id]): return 0
	if _shared.bindings.has(path["edge_ids"][0]): return FormalLedgerState.MAX_AMOUNT # Future promise is not physical hourly entry.
	var first := _edge(path["edge_ids"][0])
	return maxi(0, int(first["capacity"]) - int(first["input_used"]))


func _sale_currency(seller: String) -> String:
	return str(_spec["firms"][_owner(seller)].get("denomination", FormalLedgerState.DENOMINATION))

func advance_time() -> bool:
	_assets.advance_time(_world.game_clock.total_minutes())
	_supply.refresh()
	# Midnight is processed once by settle_day after daily counters change.
	if not processing and _world.game_clock.current_day() == day:
		return _advance_shipments(true) and _dispatch_transport(true) and _capital_transport.advance()
	return true

func exchange_input(actor: String, quote_id: String, target: int) -> Dictionary:
	if not _actors.has(actor) or _actors[actor]["control"] != "player":
		return {}
	return _exchange.required_source(actor, quote_id, target, _world.game_clock.total_minutes())


func _schedule_message(actor: String, kind: String, candidate: String, delivery_day: int, observed_day: int = 0) -> void:
	_messages.append({"id": "message:" + actor + ":" + kind + ":" + candidate, "actor": actor, "kind": kind, "candidate": candidate, "observed_day": observed_day, "delivery_day": delivery_day})


func _deliver_messages() -> void:
	var pending: Array[Dictionary] = []
	for message: Dictionary in _messages:
		if int(message["delivery_day"]) > day:
			pending.append(message)
			continue
		if message["kind"] == "job_posting" and _receipts.has(message["id"]) and int(_receipts[message["id"]].get("version", 0)) >= int(message["version"]): continue
		if message["kind"] == "directory":
			_deliver_directory(message)
			continue
		if message["kind"] in ["equity_report","equity_issue","share_distribution"]:
			_receipts[message["id"]]=message.duplicate(true)
			continue
		if message["kind"] in ["goods_quote","supply_opportunity"]:
			_receipts[message["id"]]=message.duplicate(true)
			continue
		if message["kind"]=="capital_offer":
			_capital.adopt_quote(message)
			_receipts[message["id"]]=message.duplicate(true)
			continue
		var key := "known_jobs" if message["kind"] in ["job", "job_posting"] else "known_suppliers"
		if message["kind"] == "site_report":
			_site_reports[message["candidate"]] = message.duplicate(true)
			continue
		if message.get("source")=="commercial":
			_commercial.adopted_message(message)
			if message["kind"]=="service_offer":
				_receipts[message["id"]]=message.duplicate(true)
				continue
		var known: Array = _actors[message["actor"]][key] if _actors.has(message["actor"]) else _firm_knowledge[_inventory_key(message["actor"])]
		if not known.has(message["candidate"]):
			known.append(message["candidate"])
			known.sort()
		if message.get("source")=="labor_market": _labor_market.adopted_message(message)
		_receipts[message["id"]] = message.duplicate(true)
	_messages = pending

func _search_policy(site: String) -> Dictionary:
	site = _inventory_key(site)
	var fallback: Dictionary = {}
	for row: Dictionary in config.get("supplier_search", []):
		if row["firm"] != _owner(site):
			continue
		if row.get("site_id", "") == site:
			return row
		if not row.has("site_id"):
			fallback = row
	return fallback


func _candidate_key(value: String) -> String:
	var fields := _candidate(value)
	return str(fields["seller"]) + "|" + str(fields["good"]) + "|" + str(fields["site"])

func _directory_entry_visible(firm: String, entry: Dictionary, scope: String, at_day: int, policy: Dictionary) -> bool:
	if policy.is_empty() or scope not in ["LOCAL", "REGIONAL", "WIDE"] or (scope == "WIDE" and not policy["allow_wide"]): return false
	if not entry["known_to"].has(firm) and not entry["known_to"].has(_owner(firm)) or int(entry["available_day"]) > at_day: return false
	if policy.get("scope_basis", "CONFIGURED") == "HOST_SPACE":
		var own_place := _place(firm)
		var seller_place := _place(str(entry.get("site_id", _primary_site(entry["seller"]))))
		var own_region := str(_world.spatial_catalog.get_place(own_place).get("parent_region_id", ""))
		var seller_region := str(_world.spatial_catalog.get_place(seller_place).get("parent_region_id", ""))
		return scope == "WIDE" or seller_place == own_place or (scope == "REGIONAL" and not own_region.is_empty() and own_region == seller_region)
	var zones: Array = policy["local_zones"] if scope == "LOCAL" else policy["regional_zones"]
	return scope == "WIDE" or zones.has(entry["zone"])

func _directory_entry(firm: String, candidate: String, scope: String, at_day: int) -> Dictionary:
	_ensure_configuration_queries()
	firm = _inventory_key(firm)
	var policy := _search_policy(firm)
	for entry: Dictionary in _directory_by_candidate.get(candidate, []):
		if _directory_entry_visible(firm, entry, scope, at_day, policy): return entry
	return {}

func _discover_suppliers(firm: String, good: String, need: Dictionary) -> void:
	var policy := _search_policy(firm)
	if policy.is_empty() or (int(need["quantity"]) <= 0 and need["conditional_shortfall_day"] == null):
		return
	var id := "directory:" + firm + ":" + good
	for message: Dictionary in _messages:
		if message["id"] == id:
			return
	var key := firm + "|" + good
	var state := _search_state.get(key, {"next_scope": 0, "last_completed_day": -1}) as Dictionary
	if int(state["last_completed_day"]) >= 0 and day - int(state["last_completed_day"]) < int(policy["cooldown_days"]):
		return
	var scopes: Array[String] = ["LOCAL", "REGIONAL"]
	if policy["allow_wide"]: scopes.append("WIDE")
	var scope := scopes[int(state["next_scope"])]
	_search_state[key] = state
	_messages.append({"id": id, "actor": firm, "kind": "directory", "candidate": good, "observed_day": day, "delivery_day": day + int(policy["delay_days"][scope]), "scope": scope})

func _deliver_directory(message: Dictionary) -> void:
	var firm := _inventory_key(str(message["actor"]))
	var good := str(message["candidate"])
	var policy := _search_policy(firm)
	var known := _firm_knowledge[firm] as Array
	var count: int = 0
	for candidate: String in known:
		if candidate.split("|")[1] == good:
			count += 1
	var limit := mini(int(policy["result_limit"]), maxi(0, int(policy["max_known"]) - count))
	var candidates: Array[Dictionary] = []
	var pending: Dictionary = {}
	for notice: Dictionary in _messages:
		if _inventory_key(notice["actor"]) == firm and notice["kind"] == "supplier": pending[_candidate_key(notice["candidate"])] = true
	_ensure_configuration_queries()
	for entry: Dictionary in _directory_by_good.get(good, []):
		var candidate := _directory_candidate(entry)
		if _supplier_known(known, candidate) or not _directory_entry_visible(firm, entry, message["scope"], day, policy):
			continue
		if pending.has(candidate): continue
		var paths := _paths_for(_owner(firm), _place(str(entry.get("site_id", _primary_site(entry["seller"])))), _place(firm), day)
		var lead: int = -1
		for path: Dictionary in paths:
			var value := _travel_days(_locked_legs(path, _sale_currency(entry["seller"])))
			lead = value if lead < 0 else mini(lead, value)
		if lead >= 0:
			candidates.append({"candidate": candidate, "lead": lead})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["lead"]) < int(b["lead"]) if a["lead"] != b["lead"] else str(a["candidate"]) < str(b["candidate"]))
	for index: int in mini(limit, candidates.size()):
		var candidate := str(candidates[index]["candidate"])
		known.append(candidate)
		var id := "message:" + firm + ":supplier:" + candidate
		_receipts[id] = {"id": id, "actor": firm, "kind": "supplier", "candidate": candidate, "observed_day": message["observed_day"], "delivery_day": message["delivery_day"], "source": "directory", "scope": message["scope"]}
	known.sort()
	var state := _search_state[firm + "|" + good] as Dictionary
	state["last_completed_day"] = day
	state["next_scope"] = (int(state["next_scope"]) + 1) % (3 if policy["allow_wide"] else 2)


## External callers are checked at the host action boundary before this method.
func submit(actor: String, command: Dictionary) -> Dictionary:
	if processing:
		return _result(false, "BUSY")
	if not _actors.has(actor) or _actors[actor]["control"] != "player":
		return _result(false, "UNAUTHORIZED_ACTOR")
	var person := _world.person_overlay.person(actor)
	if not _world.spatial_catalog.has_place(str(person.get("current_place_id", ""))) or str(person.get("population_territory_id", "")) != _world.population_state.unit_for_person(actor):
		return _result(false, "OUTSIDE_R1_SCOPE")
	return _accept(actor, command)

func submit_internal(actor: String, command: Dictionary) -> Dictionary:
	# The caller names an existing automatic owner. No current-player substitution.
	if processing or (not _spec["firms"].has(actor) and (not _actors.has(actor) or _actors[actor]["control"] != "automatic")) or not str(command.get("action_id", "")).begins_with("auto:" + actor + ":"):
		return _result(false, "UNAUTHORIZED_INTERNAL_ACTOR")
	return _accept(actor, command, true)


func _accept(actor: String, command: Dictionary, internal: bool = false) -> Dictionary:
	if (not _actors.has(actor) and not _spec["firms"].has(actor)) or (internal and _actors.has(actor) and _actors[actor]["control"] != "automatic") or (not internal and (not _actors.has(actor) or _actors[actor]["control"] != "player")):
		return _result(false, "UNAUTHORIZED_SOURCE")
	if not FormalLedgerState.exact_fields(command, ["action_id", "minute", "kind", "payload"]) or not command["action_id"] is String or command["action_id"].is_empty() or typeof(command["minute"]) != TYPE_INT or not command["kind"] is String or not command["payload"] is Dictionary:
		return _result(false, "MALFORMED_COMMAND")
	var action_id := str(command["action_id"])
	if _world.personal_economy_state._livelihood_changes.has(action_id): return _result(false, "DOMAIN_ACTION_ID_CONFLICT")
	if _world.military_state.active_actions.has(action_id) or (_world.person_overlay.has_travel_action(action_id) and not _commands.has(action_id)):
		return _result(false, "DOMAIN_ACTION_ID_CONFLICT")
	var envelope := {"actor": actor, "command": command.duplicate(true)}
	if _commands.has(action_id):
		var prior := _commands[action_id] as Dictionary
		if prior["envelope"] != envelope:
			return _result(false, "ACTION_ID_CONFLICT")
		return (prior["result"] as Dictionary).duplicate(true)
	if _spec["firms"].has(actor) and firm_finished(actor) and command["kind"] not in ["repay_loan", "cancel_share_order", "cancel", "request_firm_management", "accept_firm_management", "request_scope_exit", "retry_scope_exit"]: return _result(false, "ENTERPRISE_FINISHED_FUTURE_BUSINESS")
	if _actors.has(actor) and _spec["actors"][actor]["kind"] == "named" and not personal_authorized(actor) and command["kind"] not in ["request_residence", "reenter_scope", "retry_scope_exit"]:
		return _result(false, "OUTSIDE_ACTIVE_HOST_PERSON_SCOPE")
	if int(command["minute"]) != _world.game_clock.total_minutes():
		return _result(false, "STALE_TIME")
	if not advance_time(): return _result(false, error)
	var payload := command["payload"] as Dictionary
	var result: Dictionary
	var restriction:=_wind_down.restriction(actor,command["kind"],payload)
	if not restriction.is_empty(): return _result(false,restriction)
	match command["kind"]:
		"publish_supply_opportunity", "accept_supply_contract", "submit_supply_batch", "terminate_supply_contract": result=_supply.request(actor,command["kind"],payload,action_id)
		"post_goods_quote": result=_local_quotes.request(actor,payload,action_id)
		"post_managed_goods_quote": result=_local_quotes.request_managed(actor,payload,action_id)
		"set_managed_goods_sales": result=_local_quotes.request_sales_control(actor,payload,action_id)
		"commission_capital_transport", "dispatch_capital_transport": result=_capital_transport.request(actor,command["kind"],payload,action_id)
		"dismantle_capital", "offer_capital_asset", "withdraw_capital_offer", "accept_capital_offer", "deliver_capital_asset", "cancel_capital_trade", "reinstall_capital": result=_capital.move_request(actor,command["kind"],payload,action_id)
		"pay_enterprise_debt": result=_wind_down.request(actor,payload,action_id)
		"set_job_offer", "propose_employment_terms", "accept_employment_terms": result=_labor_market.request(actor,command["kind"],payload,action_id)
		"publish_notice", "withdraw_announcement", "set_publicity_policy": result=_commercial.request(actor,command["kind"],payload,action_id)
		"request_lease", "handover_lease", "end_lease", "return_lease", "pay_lease", "set_lease_offer": result = _leases.request(actor,command["kind"],payload,action_id)
		"request_service", "withdraw_service_goods", "cancel_service", "pause_service", "set_service_offer", "reschedule_service": result = _service_market.request(actor,command["kind"],payload,action_id)
		"finance_firm": result = _firm_finance_action(actor,payload,action_id)
		"finance_investment": result = _capital_finance_action(actor, payload, action_id)
		"invest", "investment_status", "capital_status", "maintain_capital": result = _capital.request(actor, payload, action_id, command["kind"])
		"travel": result = _travel_action(actor, payload, action_id, internal)
		"request_residence": result = _world.population_state.request_residence(_world, actor, payload, action_id, self if internal else null)
		"report_cargo_loss", "confirm_cargo_loss", "notify_cargo_loss", "propose_cargo_disposition", "confirm_cargo_disposition", "execute_cargo_disposition": result = _cargo_fulfilment.request(actor, command["kind"], payload, action_id)
		"collect": result = _collect_action(actor, payload, action_id)
		"store_goods", "withdraw_goods": result = _personal_custody_action(actor, payload, action_id, command["kind"])
		"send_personal_goods": result = _personal_freight_action(actor, payload, action_id)
		"expand_scope": result = _request_scope_expansion(actor, payload, action_id)
		"expand_configured_scope": result = _request_configured_expansion(actor, payload, action_id)
		"request_scope_exit": result = _request_scope_exit(actor, payload, action_id)
		"reenter_scope": result = _request_scope_reentry(actor, payload, action_id)
		"retry_scope_exit": result = _retry_scope_exit(actor, payload)
		"apply": result = _apply(actor, payload,action_id)
		"leave_job": result = _request_employment_end(actor, payload, action_id)
		"request_firm_management", "accept_firm_management": result = _management_change_action(actor, payload, action_id, command["kind"])
		"close_site", "finish_firm", "wind_down_firm": result = _request_operating_change(actor, payload, action_id, command["kind"])
		"work": result = _queue_work(actor, payload, action_id)
		"buy": result = _buy(actor, payload, action_id, internal)
		"transfer_goods": result = _transfer_goods(actor, payload, action_id, internal)
		"consume": result = _consume_action(actor, payload)
		"cancel": result = _cancel(actor, payload, action_id)
		"set_edge_capacity": result = _set_edge_capacity(actor, payload, action_id)
		"set_activity_enabled": result = _firm_business_action(actor, str(command["kind"]), payload)
		"set_firm_operating", "set_site_status": result = _request_operating_change(actor, payload, action_id, command["kind"])
		"offer_credit", "accept_credit", "repay_loan", "impair_loan", "forgive_loan":
			result = _credit_action(actor, command, internal)
		"exchange_currency": result = _exchange.accept(actor, payload, int(command["minute"]), action_id)
		"review_corporate_finance": result=_assets.corporate.review(actor,payload,int(command["minute"]))
		"declare_share_distribution": result=_assets.distribution.declare(actor,payload,int(command["minute"]),action_id)
		"settle_share_distribution": result=_assets.distribution.settle(actor,payload,int(command["minute"]),action_id)
		"publish_share_issue": result=_assets.primary.publish(actor,payload,int(command["minute"]),action_id)
		"subscribe_share_issue": result=_assets.primary.subscribe(actor,payload,int(command["minute"]),action_id)
		"cancel_share_issue": result=_assets.primary.cancel(actor,payload,int(command["minute"]),action_id)
		"settle_share_issue": result=_assets.primary.settle(actor,payload,int(command["minute"]),action_id)
		"bid_shares": result=_assets.call_market.bid(actor,payload,int(command["minute"]),action_id)
		"settle_share_bid": result=_assets.call_market.settle(actor,payload,int(command["minute"]),action_id)
		"publish_equity_report": result=_assets.call_market.publish(actor,payload,int(command["minute"]),action_id)
		"sell_shares": result = _assets.sell(actor, payload, int(command["minute"]), action_id)
		"accept_share_order": result = _assets.accept(actor, payload, int(command["minute"]), action_id)
		"cancel_share_order": result = _assets.cancel(actor, payload, int(command["minute"]), action_id)
		"pay_dividend": result = _assets.dividend(actor, payload, int(command["minute"]), action_id)
		_: result = _result(false, "UNKNOWN_ACTION")
	_commands[action_id] = {"envelope": envelope, "result": result.duplicate(true)}
	if _costs.enabled and command["kind"] in ["report_cargo_loss", "confirm_cargo_loss", "notify_cargo_loss", "propose_cargo_disposition", "confirm_cargo_disposition", "execute_cargo_disposition"]: _costs._scores_cache.clear()
	_index_command_access(_commands[action_id])
	if is_multi():
		_commands[action_id]["source"] = "firm" if not _actors.has(actor) else "automatic" if internal else "player"
	if result.get("accepted",false) and command["kind"]=="execute_cargo_disposition": _costs._scores_cache.clear()
	if result.get("accepted", false) and command["kind"] in ["buy", "submit_supply_batch", "transfer_goods", "send_personal_goods", "execute_cargo_disposition", "collect", "report_cargo_loss", "confirm_cargo_loss"] and not processing:
		if not _advance_shipments(true) or not _dispatch_transport(true): result["process_followup_error"] = error
	return result


func _post_initial_credit_offers() -> bool:
	# Explicit, finite NPC lending policy. It posts terms, never a loan or payment.
	# Candidate restore does not call initialize(), so it never reposts these terms.
	var policies: Array = config.get("credit_offers", [])
	for index: int in policies.size():
		var payload := (policies[index] as Dictionary).duplicate(true)
		var lender := str(payload["lender"])
		payload.erase("lender")
		var command := {"action_id": "auto:" + lender + ":credit_offer:" + str(index), "minute": _world.game_clock.total_minutes(), "kind": "offer_credit", "payload": payload}
		var result := _accept(lender, command, true)
		if not result["accepted"]:
			return _fail("Configured credit offer failed: " + str(result["reason"]))
	return true


func _credit_action(actor: String, command: Dictionary, internal: bool) -> Dictionary:
	if _spec["firms"].has(actor):
		var permission := _firm_credit_permission(actor,actor,command["kind"],command["payload"],internal)
		if not permission.get("ok",false): return _result(false,permission["reason"])
		var result := _execute_credit(actor,command,internal)
		if result.get("accepted",false): result["financial_authorization"]=permission
		return result
	return _execute_credit(actor,command,internal)

func _execute_credit(actor: String, command: Dictionary, internal: bool) -> Dictionary:
	var payload := command["payload"] as Dictionary
	var minute := int(command["minute"])
	var action_id := str(command["action_id"])
	match command["kind"]:
		"offer_credit":
			if not Credit.valid_terms(payload):
				return _result(false, "INVALID_CREDIT_TERMS")
			if internal and not _configured_credit_offer(actor, command):
				return _result(false, "NO_LENDING_POLICY")
			var borrower := str(payload["borrower"])
			if not borrower.is_empty() and (not _spec["firms"].has(borrower) and (not _actors.has(borrower) or _actors[borrower]["control"] == "dormant")):
				return _result(false, "UNKNOWN_CREDIT_BORROWER")
			return _credit.offer(actor, _account(actor, payload["denomination"]), payload, minute, action_id)
		"accept_credit":
			return _credit.accept(actor, _account(actor, _credit.offer_currency(str(payload.get("offer_id", "")))), payload, _known_credit_lenders(actor), _contracts.has(actor), minute, action_id)
		"repay_loan":
			return _credit.repay(actor, payload, minute, action_id)
		"impair_loan", "forgive_loan":
			return _credit.adjust(actor, payload, command["kind"] == "forgive_loan")
	return _result(false, "UNKNOWN_ACTION")


func _configured_credit_offer(lender: String, command: Dictionary) -> bool:
	var prefix := "auto:" + lender + ":credit_offer:"
	var action_id := str(command["action_id"])
	if not action_id.begins_with(prefix) or command["minute"] != 0:
		return false
	var suffix := action_id.trim_prefix(prefix)
	if not suffix.is_valid_int():
		return false
	var index := int(suffix)
	var policies: Array = config.get("credit_offers", [])
	if index < 0 or index >= policies.size() or suffix != str(index):
		return false
	var terms := (policies[index] as Dictionary).duplicate(true)
	if terms["lender"] != lender:
		return false
	terms.erase("lender")
	return command["payload"] == terms


func _known_credit_lenders(actor: String) -> Array[String]:
	var known := _credit.known_lenders(actor)
	if _actors.has(actor):
		for id: String in _actors[actor]["known_jobs"]:
			var lender := str(_job(id)["employer"])
			if not known.has(lender):
				known.append(lender)
	var suppliers: Array = _known_suppliers(actor)
	for supplier: String in suppliers:
		var lender := str(supplier.split("|")[0])
		if not known.has(lender):
			known.append(lender)
	known.sort()
	return known


func _job(id: String) -> Dictionary:
	var job := (_spec["jobs"].get(id, {}) as Dictionary).duplicate(true)
	if not job.is_empty():
		job["denomination"] = job.get("denomination", FormalLedgerState.DENOMINATION)
		job["positions"] = _job_postings.get(id, {}).get("positions", job["positions"])
	if _labor_market.controls(id):
		var q:=_labor_market.current(id)
		job["wage_per_hour"]=q["wage_per_hour"]
	if not is_multi():
		job.erase("wage_delay")
	return job

func _wage_delay(job: String) -> int:
	return int(_spec["jobs"][job]["wage_delay"])


func _cohort_profile(actor: String) -> Dictionary:
	return Cohorts.profile(_spec["actors"].get(actor, {}))

func _contract_rows(container: Dictionary) -> Array[Dictionary]:
	return Cohorts.contracts(container)

func _all_contract_rows(contracts: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for actor: String in _sorted_ids(contracts): rows.append_array(_contract_rows(contracts[actor]))
	return rows

func _contract_for(actor: String, job: String) -> Dictionary:
	return Cohorts.contract(_contracts.get(actor, {}), job)

func _work_rows(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var container := _work_queue.get(actor, {}) as Dictionary
	if container.has("allocations"):
		for job: String in _sorted_ids(container["allocations"]):
			var row := (container["allocations"][job] as Dictionary).duplicate()
			row["job"] = job
			result.append(row)
	elif not container.is_empty():
		var row := container.duplicate()
		row["job"] = _contracts[actor]["job"]
		result.append(row)
	return result

func _work_id(date: int, actor: String, job: String) -> String:
	return "work:"+str(date)+":"+actor+(":"+job if not _cohort_profile(actor).is_empty() else "")

func _valid_employment_container(value: Variant, actor: String, known: Array, commands: Dictionary, at_minute: int=-1) -> bool:
	if not value is Dictionary or not _spec["actors"].has(actor): return false
	var profile := _cohort_profile(actor)
	var pooled: bool = not profile.is_empty()
	if pooled and (not FormalLedgerState.exact_fields(value, ["allocations"]) or not value["allocations"] is Dictionary or value["allocations"].is_empty() or value["allocations"].size() > int(profile["max_jobs"])): return false
	if not pooled and not EconomySliceConfig._fields(value, ["job", "workers", "denomination"], ["terms","employment_action_id"]): return false
	var spans: Array[Vector2i] = []
	var fields: Array[String] = ["job", "workers", "denomination"]
	if pooled: fields.append("labor_start")
	for contract: Dictionary in _contract_rows(value):
		var actual_fields:=fields.duplicate()
		if contract.has("terms") or contract.has("employment_action_id"): actual_fields.append_array(["terms","employment_action_id"])
		if not FormalLedgerState.exact_fields(contract, actual_fields) or not contract["job"] is String or not _spec["jobs"].has(contract["job"]) or not known.has(contract["job"]) or not FormalLedgerState.valid_amount(contract["workers"]) or int(contract["workers"]) < 1: return false
		var job := _labor_market.contract_job(contract)
		if int(contract["workers"]) > Cohorts.labor_members(_spec["actors"][actor]) or int(_spec["actors"][actor]["skill"]) < int(job["skill"]) or contract["denomination"] != job["denomination"] or _account(actor, str(contract["denomination"])).is_empty(): return false
		if not contract.has("terms") and _labor_market.controls(contract["job"]) and _labor_market.ready and _labor_market.pinned_source_exists(actor,contract["job"],commands,_world.game_clock.total_minutes() if at_minute<0 else at_minute): return false
		if contract.has("terms"):
			if not _labor_market.controls(contract["job"]) or not contract["terms"] is Dictionary or not contract["employment_action_id"] is String: return false
			if _labor_market.ready and not _labor_market.valid_contract(contract,actor,commands,_world.game_clock.total_minutes() if at_minute<0 else at_minute): return false
		if pooled:
			if value["allocations"].get(contract["job"]) != contract or not Cohorts.allows_job(_spec["actors"][actor], contract["job"]) or not FormalLedgerState.valid_amount(contract["labor_start"]): return false
			var span := Vector2i(int(contract["labor_start"]), int(contract["labor_start"])+int(contract["workers"]))
			if span.y > int(profile["labor_members"]): return false
			for previous: Vector2i in spans:
				if span.x < previous.y and previous.x < span.y: return false
			spans.append(span)
			var formed: bool = contract.has("terms")
			for action: Dictionary in ([] if formed else commands.values()):
				var command := action.get("envelope", {}).get("command", {}) as Dictionary
				var outcome := action.get("result", {}) as Dictionary
				if action.get("envelope", {}).get("actor") == actor and command.get("kind") == "apply" and command.get("payload", {}).get("job_id") == contract["job"] and outcome.get("accepted") == true and outcome.get("workers") == contract["workers"] and outcome.get("labor_start") == contract["labor_start"]: formed = true
			if not formed: return false
	return true

func _valid_work_queue(value: Dictionary, actor: String) -> bool:
	if not value["contracts"].has(actor) or not value["work_queue"][actor] is Dictionary: return false
	var queue := value["work_queue"][actor] as Dictionary
	var pooled: bool = not _cohort_profile(actor).is_empty()
	var jobs: Dictionary = {}
	if pooled:
		if not FormalLedgerState.exact_fields(queue, ["allocations"]) or not queue["allocations"] is Dictionary or queue["allocations"].is_empty(): return false
		jobs = queue["allocations"]
	else: jobs[value["contracts"][actor]["job"]] = queue
	for id: String in jobs:
		var work: Variant = jobs[id]
		var contract := Cohorts.contract(value["contracts"][actor], id)
		if contract.is_empty() or not work is Dictionary or not FormalLedgerState.exact_fields(work, ["action_id", "day", "hours"]) or typeof(work["day"]) != TYPE_INT or int(work["day"]) != int(value["day"])+1 or not FormalLedgerState.valid_amount(work["hours"]) or int(work["hours"]) <= 0 or int(work["hours"]) > int(_labor_market.contract_job(contract)["hours"])*int(contract["workers"]) or not _accepted_command(value, actor, work["action_id"], "work"): return false
		var command := value["commands"][work["action_id"]]["envelope"]["command"] as Dictionary
		if _service_market._resident.work_conflict(actor,id,int(work["day"]),contract): return false
		if command["payload"].get("hours") != work["hours"] or (pooled and command["payload"].get("job_id") != id): return false
		if uses_host_accounts() and (int(command["minute"])/1440 != int(value["day"]) or int(work["hours"]) > ((int(work["day"])*1440-int(command["minute"]))/60)*int(contract["workers"])): return false
	return true

func _apply(actor: String, payload: Dictionary, action_id: String="") -> Dictionary:
	if _legacy_wage_still_active(actor): return _result(false, "LEGACY_WAGE_TERMINATION_REQUIRED")
	var optional: Array[String] = ["job_quote_id"]
	if not _cohort_profile(actor).is_empty(): optional.append("workers")
	if not EconomySliceConfig._fields(payload, ["job_id"], optional) or not payload["job_id"] is String or not (_actors[actor]["known_jobs"] as Array).has(payload["job_id"]):
		return _result(false, "UNKNOWN_JOB")
	var profile := _cohort_profile(actor)
	if _contracts.has(actor) and profile.is_empty(): return _result(false, "ALREADY_EMPLOYED")
	if _employment_end_pending(actor): return _result(false, "EMPLOYMENT_END_PENDING")
	if not Cohorts.allows_job(_spec["actors"][actor], payload["job_id"]): return _result(false, "OUTSIDE_COHORT_OCCUPATION")
	if not profile.is_empty() and (not _contract_for(actor, payload["job_id"]).is_empty() or _contract_rows(_contracts.get(actor, {})).size() >= int(profile["max_jobs"])): return _result(false, "COHORT_ALLOCATION_LIMIT")
	var job := _job(payload["job_id"])
	if _firm_winding_down(job["employer"]) or not _site_accepting(job["site_id"]):
		return _result(false, "FIRM_STOPPED_NEW_BUSINESS")
	var dynamic:=_labor_market.controls(job["id"]);var accepted_quote: Dictionary={}
	if dynamic:
		var result:=_labor_market.applicable(actor,job["id"],str(payload.get("job_quote_id","")))
		if not result["accepted"]: return result
		accepted_quote=result["quote"]
	elif payload.has("job_quote_id"): return _result(false,"FIXED_JOB_HAS_NO_DYNAMIC_QUOTE")
	if not dynamic and manages_person(actor) and _at_place(actor, job["place"]): _observe_local_posting(actor, job["id"])
	if not dynamic and int(_job_postings[job["id"]]["version"]) > 0 and int(_receipts.get("posting:" + actor + ":" + str(job["id"]), {}).get("version", 0)) != int(_job_postings[job["id"]]["version"]):
		return _result(false, "STALE_JOB_NOTICE")
	if (_spec["actors"][actor]["kind"] != "named" and _place(actor) != job["place"]) or _account(actor, job["denomination"]).is_empty() or _account(job["employer"], job["denomination"]).is_empty():
		return _result(false, "JOB_PLACE_OR_CURRENCY_ACCOUNT")
	if int(_spec["actors"][actor]["skill"]) < int(job["skill"]):
		return _result(false, "UNQUALIFIED")
	var occupied: int = 0
	for record: Dictionary in _all_contract_rows(_contracts):
		if record["job"] == job["id"]:
			occupied += int(record["workers"])
	var span := Vector2i(0, int(_actors[actor]["members"])) if profile.is_empty() else Cohorts.free_span(_spec["actors"][actor], _contracts.get(actor, {}))
	var requested := span.y
	if payload.has("workers"):
		if not FormalLedgerState.valid_amount(payload["workers"]) or int(payload["workers"]) < 1: return _result(false, "INVALID_WORKER_COUNT")
		requested = mini(requested, int(payload["workers"]))
	var workers := mini(requested, int(job["positions"]) - occupied)
	if workers <= 0:
		return _result(false, "NO_VACANCY")
	var contract := {"job": job["id"], "workers": workers, "denomination": job["denomination"]}
	if dynamic and not _labor_market.affordable(job["id"],job["wage_per_hour"],workers): return _result(false,"EMPLOYER_CURRENT_PAYROLL_CASH_PRESSURE")
	if dynamic: _labor_market.lock_contract(contract,action_id,accepted_quote)
	if profile.is_empty(): _contracts[actor] = contract
	else:
		contract["labor_start"] = span.x
		if not _contracts.has(actor): _contracts[actor] = {"allocations": {}}
		_contracts[actor]["allocations"][job["id"]] = contract
	var result:={"accepted": true, "reason": "ACCEPTED", "workers": workers, "labor_start": span.x}
	if dynamic: result["employment"]=contract.duplicate(true)
	return result


func _queue_work(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if _legacy_wage_still_active(actor): return _result(false, "LEGACY_WAGE_TERMINATION_REQUIRED")
	var fields: Array[String] = ["hours"]
	if not _cohort_profile(actor).is_empty(): fields.append("job_id")
	if not FormalLedgerState.exact_fields(payload, fields) or typeof(payload["hours"]) != TYPE_INT or not _contracts.has(actor):
		return _result(false, "NO_CONTRACT_OR_INVALID_HOURS")
	var hours := int(payload["hours"])
	var contract := _contract_for(actor, str(payload.get("job_id", _contracts[actor].get("job", ""))))
	if contract.is_empty(): return _result(false, "NO_ALLOCATED_JOB")
	var work_workers:=_workable_workers(actor,contract)
	if work_workers<1: return _result(false,"EMPLOYMENT_END_PENDING")
	if _service_market._resident.work_conflict(actor,contract["job"],day+1): return _result(false,"RESIDENT_SERVICE_MEMBER_INTERVAL_ALREADY_BOOKED")
	if not _site_operating(_job(contract["job"])["site_id"]):
		return _result(false, "WORK_SITE_STOPPED")
	if manages_person(actor) and _world.person_travel != null and _world.person_travel.active(actor):
		return _result(false, "PERSON_JOURNEY_NOT_COMPLETED")
	if not _at_place(actor, _job(contract["job"])["place"]):
		return _result(false, "OUTSIDE_JOB_PLACE")
	if hours <= 0 or hours > int(_labor_market.contract_job(contract)["hours"]) * work_workers:
		return _result(false, "LABOR_LIMIT")
	var wage := int(_labor_market.contract_job(contract)["wage_per_hour"])
	if wage > 0 and hours > FormalLedgerState.MAX_AMOUNT / wage:
		return _result(false, "WAGE_AMOUNT_BOUNDS")
	if uses_host_accounts() and hours > (((day + 1) * 1440 - _world.game_clock.total_minutes()) / 60) * int(contract["workers"]):
		return _result(false, "INSUFFICIENT_WORK_TIME_BEFORE_BOUNDARY")
	var work := {"action_id": action_id, "day": day + 1, "hours": hours}
	if _cohort_profile(actor).is_empty():
		if _work_queue.has(actor): return _result(false, "WORK_PERIOD_ALREADY_CLAIMED")
		_work_queue[actor] = work
	else:
		if not _work_queue.has(actor): _work_queue[actor] = {"allocations": {}}
		if _work_queue[actor]["allocations"].has(contract["job"]): return _result(false, "WORK_PERIOD_ALREADY_CLAIMED")
		_work_queue[actor]["allocations"][contract["job"]] = work
	return _result(true, "ACCEPTED")


func _committed(seller: String, good: String) -> int:
	var quantity := 0
	for id: String in _lots._by_location.get("SITE|"+_inventory_key(seller)+"#"+good, {}):
		var p := _lots.portions[id] as Dictionary
		if p["good"] == good and not str(p["reserved_for"]).is_empty(): quantity += int(p["remaining"])
	return quantity


func _exposure(subject: String, good: String) -> int:
	subject = _inventory_key(subject)
	return int(_stocks[subject][good]) + int(_incoming_by_key.get(subject + "|" + good, 0))


func _offer(actor: String, seller: String, good: String, path_id: String = "", seller_site: String = "", buyer_site: String = "", known_path: Dictionary = {}) -> Dictionary:
	if _spec["firms"].has(actor):
		buyer_site = _inventory_key(actor, buyer_site)
	seller_site = _inventory_key(seller, seller_site)
	buyer_site = _inventory_key(actor, buyer_site) if _spec["firms"].has(actor) else ""
	if path_id == "onsite:"+seller_site: return _onsite_offer(actor,seller,seller_site,good)
	var price := _price(seller_site, good)
	var denomination := _sale_currency(seller)
	var path := _route_for(actor, seller, path_id, buyer_site, seller_site) if known_path.is_empty() else known_path
	var stock := maxi(0, int(_stocks[seller_site][good]) - _committed(seller_site, good))
	var legs: Array[Dictionary] = []
	if not path.is_empty(): legs.assign(_locked_legs(path, denomination))
	var freight := _freight(legs)
	var limit := mini(stock, _route_available(path)) if not path.is_empty() and _site_selling(seller_site) else 0
	for leg: Dictionary in legs:
		if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == _account(actor, denomination)):
			limit = 0
	var available := maxi(0, _world.ledger_state.available_balance(_account(actor, denomination)))
	var quantity := mini(limit, available / (price + freight))
	return _local_quotes.offer(_inventory_key(actor,buyer_site), {"quote_id": _quote_id(_world.game_clock.total_minutes(), actor, seller, good, str(path.get("id", "")), seller_site, buyer_site), "minute": _world.game_clock.total_minutes(), "seller": seller, "seller_site": seller_site, "buyer_site": buyer_site, "good": good, "price": price, "denomination": denomination, "quantity": quantity, "transport_quantity": limit, "freight_per_unit": freight, "route_id": path.get("id", ""), "route_legs": legs, "from_place_id": _place(seller_site), "to_place_id": _place(buyer_site if not buyer_site.is_empty() else actor), "earliest_arrival_day": day + 1 + _travel_days(legs), "eta_guaranteed": false, "reason": "FIRM_STOPPED_NEW_BUSINESS" if not _site_selling(seller_site) else "NO_KNOWN_PATH" if path.is_empty() else "NO_UNCOMMITTED_STOCK" if stock==0 else "TRANSPORT_LIMIT_OR_CLOSED" if limit==0 else "INSUFFICIENT_AVAILABLE_CASH" if quantity==0 else "OFFER", "transport_basis": _path_basis(path)})


func _onsite_offer(actor: String, seller: String, site: String, good: String) -> Dictionary:
	var why:=_retail.reason(actor,site,good)
	var price:=_price(site,good);var currency:=_sale_currency(seller)
	var stock:=maxi(0,int(_stocks[site][good])-_committed(site,good))
	var limit:=mini(stock,_retail.limit(site)) if why=="OFFER" else 0
	var quantity:=mini(limit,maxi(0,_world.ledger_state.available_balance(_account(actor,currency)))/maxi(1,price))
	return _local_quotes.offer(actor, {"quote_id":_quote_id(_world.game_clock.total_minutes(),actor,seller,good,"onsite:"+site,site,""),"minute":_world.game_clock.total_minutes(),"seller":seller,"seller_site":site,"buyer_site":"","good":good,"price":price,"denomination":currency,"quantity":quantity,"transport_quantity":limit,"freight_per_unit":0,"route_id":"onsite:"+site,"route_legs":[],"from_place_id":_place(site),"to_place_id":_place(actor),"earliest_arrival_day":day,"eta_guaranteed":true,"reason":why if why!="OFFER" else "NO_UNCOMMITTED_STOCK" if stock==0 else "INSUFFICIENT_AVAILABLE_CASH" if quantity==0 else "OFFER","transport_basis":[],"fulfilment":"ONSITE_REAL_STOCK_HANDOVER"})


func _offers(actor: String, buyer_site: String = "", only_good: String = "") -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var observer := _inventory_key(actor, buyer_site)
	var known: Array = _actors[actor]["known_suppliers"] if _actors.has(actor) else _firm_knowledge.get(observer, [])
	var seen: Dictionary = {}
	for key: String in known:
		var candidate := _candidate(key)
		if not only_good.is_empty() and candidate["good"] != only_good: continue
		if seen.has(candidate["site"] + "|" + candidate["good"]):
			continue
		seen[candidate["site"] + "|" + candidate["good"]] = true
		if _actors.has(actor) and _retail.has_site(candidate["site"]):
			offers.append(_onsite_offer(actor,candidate["seller"],candidate["site"],candidate["good"]))
			if _at_place(actor,_place(candidate["site"])): continue
		var paths := _paths_for(actor, _place(candidate["site"]), _place(observer), day)
		if paths.is_empty():
			offers.append(_offer(actor, candidate["seller"], candidate["good"], "", candidate["site"], buyer_site))
		for path: Dictionary in paths:
			offers.append(_offer(actor, candidate["seller"], candidate["good"], path["id"], candidate["site"], buyer_site, path))
	return offers


func _buy(actor: String, payload: Dictionary, action_id: String, internal: bool = false) -> Dictionary:
	var submitting_actor := actor
	var authority: Dictionary = {}
	if payload.has("firm"):
		if not payload["firm"] is String or not _spec["firms"].has(payload["firm"]): return _result(false, "UNKNOWN_PROCUREMENT_ENTERPRISE")
		actor = str(payload["firm"])
		if payload.has("authorization_context"):
			if not payload["authorization_context"] is Dictionary: return _result(false, "INVALID_PROCUREMENT_AUTHORITY")

		elif not _manager(submitting_actor, actor): return _result(false, "NOT_PROCUREMENT_MANAGER")
	if _spec["firms"].has(actor) and _firm_winding_down(actor): return _result(false, "WIND_DOWN_STOPS_NEW_PROCUREMENT")
	if manages_person(actor) and not _at_place(actor, _place(actor)): return _result(false, "PERSON_IN_TRANSIT")
	if not EconomySliceConfig._fields(payload, ["quote_id", "seller", "good", "quantity"], ["denomination", "max_price", "path_id", "need_by_day", "seller_site", "buyer_site", "need_category", "purpose", "firm", "authorization_context"]) or not FormalLedgerState.valid_amount(payload["quantity"]) or int(payload["quantity"]) <= 0 or int(payload["quantity"]) > 1000000:
		return _result(false, "INVALID_PURCHASE")
	for key: String in ["quote_id", "seller", "good", "path_id", "seller_site", "buyer_site", "need_category", "purpose"]:
		if not payload.has(key):
			continue
		if not payload[key] is String:
			return _result(false, "INVALID_PURCHASE")
	var seller := str(payload["seller"])
	var good := str(payload["good"])
	var seller_site := _inventory_key(seller, str(payload.get("seller_site", "")))
	var buyer_site := _inventory_key(actor, str(payload.get("buyer_site", ""))) if _spec["firms"].has(actor) else ""
	if seller == actor or (_actors.has(actor) and not str(payload.get("buyer_site", "")).is_empty()) or not _spec["sites"].has(seller_site) or _owner(seller_site) != seller or (not buyer_site.is_empty() and (not _spec["sites"].has(buyer_site) or _owner(buyer_site) != actor)):
		return _result(false, "INVALID_ORDER_SITE")
	var known: Array = _actors[actor]["known_suppliers"] if _actors.has(actor) else _firm_knowledge[buyer_site]
	if not known.has(seller + "|" + good + "|" + seller_site) and not (seller_site == _primary_site(seller) and known.has(seller + "|" + good)):
		return _result(false, "UNKNOWN_SUPPLIER")
	if not _site_selling(seller_site) or (not buyer_site.is_empty() and not _site_accepting(buyer_site)):
		return _result(false, "FIRM_STOPPED_NEW_BUSINESS")
	if _local_quotes.sales_paused(seller_site,good): return _result(false,"GOODS_NEW_SALES_PAUSED")
	var purpose := str(payload.get("purpose", "NEED"))
	if purpose not in ["NEED", "HOLDING"] or (purpose == "HOLDING" and not _actors.has(actor)):
		return _result(false, "INVALID_PURCHASE_PURPOSE")
	var category := str(payload.get("need_category", "food")) if _actors.has(actor) and purpose == "NEED" else ""
	if _actors.has(actor) and purpose == "NEED" and _service(good, category) <= 0:
		return _result(false, "GOOD_HAS_NO_HOUSEHOLD_USE")
	if _actors.has(actor) and _retail.has_site(seller_site) and _at_place(actor,_place(seller_site)) and payload.get("path_id", "")!="onsite:"+seller_site: return _result(false,"LOCAL_STOREFRONT_REQUIRES_ONSITE_HANDOVER")
	var offer := _offer(actor, seller, good, str(payload.get("path_id", "")), seller_site, buyer_site)
	var quotation_reason := _local_quotes.reason(_inventory_key(actor,buyer_site),seller_site,good)
	if not quotation_reason.is_empty():
		if submitting_actor==actor or _manager(submitting_actor,actor): _observe_request(_inventory_key(actor,buyer_site),seller_site,good,int(payload["quantity"]),"",0,0,0,day,action_id,_request_rejection(int(payload["quantity"]),"information"))
		return _result(false,quotation_reason)
	if payload["quote_id"] != offer["quote_id"]:
		if submitting_actor==actor or _manager(submitting_actor,actor): _observe_request(_inventory_key(actor,buyer_site),seller_site,good,int(payload["quantity"]),"",0,0,0,day,action_id,_request_rejection(int(payload["quantity"]),"information"))
		return _result(false, "EXPIRED_QUOTE")
	if (offer["denomination"] != FormalLedgerState.DENOMINATION or offer["route_id"] != _spec["route"]["id"]) and (not payload.has("denomination") or not payload.has("max_price")):
		return _result(false, "EXPLICIT_CURRENCY_AND_LIMIT_REQUIRED")
	if payload.get("denomination", FormalLedgerState.DENOMINATION) != offer["denomination"] or not FormalLedgerState.valid_amount(payload.get("max_price", offer["price"])):
		return _result(false, "PURCHASE_CURRENCY_OR_PRICE_LIMIT")
	var need_by := int(payload.get("need_by_day", day + int(_operations_policy(seller_site)["planning_horizon"])))
	if payload.has("need_by_day") and (not FormalLedgerState.valid_amount(payload["need_by_day"]) or need_by < day or need_by > day + 30):
		return _result(false, "INVALID_NEED_DATE")
	var authority_payload := payload.duplicate(true)
	authority_payload["max_price"] = offer["price"] # Actual quoted money, not a payload limit or zero default.
	var permission := _procurement_permission(submitting_actor, actor, authority_payload, internal, _budget_plan(actor, offer["denomination"], good, offer["route_legs"], payload["quantity"], true, offer["price"]), seller, _place(buyer_site), "goods:"+good, int(FormalLedgerState.ratio(int(offer["price"])+int(offer["freight_per_unit"]), payload["quantity"], 1).get("quotient", -1)))
	if not permission["ok"]:
		if submitting_actor==actor or _manager(submitting_actor,actor): _observe_request(_inventory_key(actor,buyer_site),seller_site,good,int(payload["quantity"]),"",0,0,0,need_by,action_id,_request_rejection(int(payload["quantity"]),"authorization"))
		return _result(false, permission["reason"])
	authority = permission["authorization"]
	if int(payload.get("max_price", offer["price"])) < int(offer["price"]):
		_observe_request(_inventory_key(actor, buyer_site), seller_site, good, int(payload["quantity"]), "", 0, 0, int(payload["quantity"]), need_by, action_id)
		var refused := _result(false,"PURCHASE_PRICE_LIMIT")
		if not authority.is_empty(): refused["authorization"]=authority
		return refused
	var result := _admit(actor, seller, good, int(payload["quantity"]), action_id, str(payload.get("path_id", "")), need_by, seller_site, buyer_site, category)
	if not authority.is_empty(): result["authorization"] = authority
	return result


func _admit(buyer: String, seller: String, good: String, requested: int, action_id: String, path_id: String = "", need_by: int = -1, seller_site: String = "", buyer_site: String = "", category: String = "", supply_id: String = "") -> Dictionary:
	seller_site = _inventory_key(seller, seller_site)
	if supply_id.is_empty() and _local_quotes.sales_paused(seller_site,good): return _result(false,"GOODS_NEW_SALES_PAUSED")
	var price: int = _price(seller_site, good) if supply_id.is_empty() else _supply.locked_price(supply_id)
	var denomination := _sale_currency(seller)
	var onsite: bool=path_id=="onsite:"+seller_site
	if onsite and _retail.reason(buyer,seller_site,good)!="OFFER": return _result(false,_retail.reason(buyer,seller_site,good))
	var route := {"id":path_id,"from_place_id":_place(seller_site),"to_place_id":_place(buyer),"edge_ids":[]} if onsite else _route_for(buyer, seller, path_id, buyer_site, seller_site)
	if route.is_empty():
		return _result(false, "NO_KNOWN_ROUTE")
	var legs := _locked_legs(route, denomination)
	if not _shared.path_conditions(legs, good): return _result(false, "UNCONFIGURED_SHARED_WEIGHT_OR_SERVICE_WINDOW")
	var freight := _freight(legs)
	var unit_cost := price + freight
	var buyer_account := _account(buyer, denomination)
	var seller_account := _account(seller, denomination)
	if buyer_account.is_empty() or seller_account.is_empty():
		return _result(false, "PURCHASE_CURRENCY_ACCOUNT")
	for leg: Dictionary in legs:
		if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == buyer_account):
			return _result(false, "FREIGHT_CURRENCY_ACCOUNT")
	if requested <= 0 or requested > 1000000 or requested > FormalLedgerState.MAX_AMOUNT / unit_cost or next_order >= FormalLedgerState.MAX_AMOUNT:
		return _result(false, "QUANTITY_BOUNDS")
	var limit := maxi(0, int(_stocks[seller_site][good]) - _committed(seller_site, good))
	var eligible := requested
	if _actors.has(buyer) and not category.is_empty():
		var need_offer := _offer(buyer,seller,good,path_id,seller_site,buyer_site)
		# Eligibility is a need boundary, not a repetition of physical admission.
		# Preserve requested as the hypothetical cap so an empty supplier can
		# still receive a genuine stock-shortage observation.
		need_offer["transport_quantity"] = requested
		eligible = int(HouseholdTiming.candidate_need(self,buyer,category,need_offer,requested)["quantity"])
	var headroom := maxi(0, FormalLedgerState.MAX_AMOUNT - _exposure(_inventory_key(buyer, buyer_site), good))
	headroom=mini(headroom,_retail.headroom(_inventory_key(buyer,buyer_site),good))
	var logistics := _retail.limit(seller_site) if onsite else _route_available(route)
	var physical := mini(headroom, mini(eligible, mini(limit, logistics)))
	var funded_cash: int=_world.ledger_state.available_balance(buyer_account) if supply_id.is_empty() else _supply.remaining_money(supply_id)
	var amount := mini(physical, int(funded_cash / unit_cost))
	var limits := _request_limits(eligible, limit, logistics, headroom, maxi(0, int(funded_cash / unit_cost)))
	var date := need_by if need_by >= 0 else day + int(_operations_policy(seller_site)["planning_horizon"])
	if amount <= 0:
		if supply_id.is_empty(): _observe_request(_inventory_key(buyer, buyer_site), seller_site, good, eligible, "", int(limits["refused"]["seller_stock"]), int(limits["refused"]["cash"]), 0, date, action_id, limits)
		return _result(false, "NO_STOCK" if limit == 0 else "INSUFFICIENT_CASH_OR_CAPACITY_OR_NEED")
	var custody:="CARRIED"
	if onsite and manages_person(buyer) and not _can_carry_extra(buyer,good,amount):
		if _personal_storage_site(_place(seller_site),good).is_empty(): return _result(false,"COLLECTION_REQUIRES_STORAGE_OR_SMALLER_QUANTITY")
		custody="STORED"
	if onsite and next_shipment>=FormalLedgerState.MAX_AMOUNT: return _result(false,"RECEIPT_ID_LIMIT")
	var id := "order:" + str(next_order)
	var components := _budget_plan(buyer, denomination, good, legs, amount, true, price)
	if not _budget_ready(components):
		if supply_id.is_empty(): _observe_request(_inventory_key(buyer,buyer_site),seller_site,good,eligible,"",0,0,0,date,action_id,_request_rejection(eligible,"budget"))
		return _result(false, "CUMULATIVE_BUDGET_OR_WINDOW")
	if _lots.selection("SITE|"+seller_site, good, amount).is_empty(): return _result(false, "UNCOMMITTED_SOURCE_PORTIONS_UNAVAILABLE")
	# Prepare all fallible adoption/payment checks before reserving an onsite sale.
	if onsite:
		var preview:={"id":id,"kind":"SALE","buyer":buyer,"seller":seller,"good":good,"quantity":amount,"price":price,"denomination":denomination,"buyer_account":buyer_account,"seller_account":seller_account,"seller_site":seller_site,"buyer_site":"","route_id":path_id,"route_legs":[],"from_place_id":_place(seller_site),"to_place_id":_place(buyer),"accepted_minute":_world.game_clock.total_minutes(),"accepted_day":day,"delivered":0,"pending":0,"transit":amount,"cancelled":0,"need_category":category,"action_id":action_id}
		var receipt_id:="shipment:"+str(next_shipment)
		if not _world.ledger_state.payment_ready("delivery:"+receipt_id,_delivery_legs(receipt_id,preview,amount),_world.game_clock.total_minutes()): return _result(false,"ONSITE_PAYMENT_NOT_ADOPTABLE")
		if manages_person(buyer):
			var source:=_personal_order_source(preview)
			source.merge({"source_id":receipt_id,"shipment_id":receipt_id,"quantity":amount,"amount":amount*price,"transaction_ids":["r1:goods:"+receipt_id],"effective_minute":_world.game_clock.total_minutes(),"custody_mode":custody,"custody_place_id":_place(seller_site)},true)
			if _world.personal_economy_state.prepare_native_source(buyer,source,"native_delivery").is_empty(): return _result(false,"INVALID_PERSONAL_DELIVERY_ADOPTION")
	var funded: bool=_world.ledger_state.reserve(id,buyer_account,amount*unit_cost) if supply_id.is_empty() else _world.ledger_state.split_reservation("supply_split:"+id,supply_id,id,buyer_account,amount*unit_cost)
	if not funded:
		return _result(false, "INSUFFICIENT_CASH")
	var budget_committed := _budgets.commit(id, components)
	assert(budget_committed)
	var portions_reserved := _lots.reserve(id, "SITE|"+seller_site, good, amount, _world.game_clock.total_minutes())
	assert(portions_reserved)
	next_order += 1
	_orders[id] = {"id": id, "kind": "SALE", "seller_site": seller_site, "buyer_site": buyer_site, "need_category": category if _actors.has(buyer) else "", "buyer": buyer, "seller": seller, "good": good, "quantity": amount, "pending": amount, "transit": 0, "delivered": 0, "cancelled": 0, "price": price, "action_id": action_id, "accepted_day": day, "accepted_minute": _world.game_clock.total_minutes()}
	if not supply_id.is_empty(): _orders[id]["supply_contract_id"]=supply_id
	_orders[id].merge({"denomination": denomination, "buyer_account": buyer_account, "seller_account": seller_account, "route_id": route["id"], "from_place_id": route["from_place_id"], "to_place_id": route["to_place_id"], "route_legs": legs})
	if onsite:
		_orders[id]["pending"]=0;_orders[id]["transit"]=amount
		_active_orders.append(id);_index_order(id)
		var receipt_bundle:={"id":"shipment:"+str(next_shipment),"order_id":id,"quantity":amount,"departures":[]}
		next_shipment+=1
		var delivered:=_deliver_shipment(receipt_bundle,_orders[id],"",-1,custody)
		assert(delivered) # Prepared original Ledger, PersonalEconomy and StockLots adoption.
		_observe_request(buyer,seller_site,good,eligible,id,int(limits["refused"]["seller_stock"]),int(limits["refused"]["cash"]),0,date,action_id,limits)
		return {"accepted":true,"reason":"ONSITE_DELIVERED","order_id":id,"quantity":amount,"price":price,"denomination":denomination,"route_id":path_id,"seller_site":seller_site,"buyer_site":""}
	_pending_orders.append(id)
	_active_orders.append(id)
	_index_order(id)
	var edge := _edge(legs[0]["edge_id"])
	edge["input_used"] = int(edge["input_used"]) + amount
	edge["holds"][id] = {"period": day, "quantity": amount}
	if supply_id.is_empty(): _observe_request(_inventory_key(buyer, buyer_site), seller_site, good, eligible, id, int(limits["refused"]["seller_stock"]), int(limits["refused"]["cash"]), 0, date, action_id, limits)
	return {"accepted": true, "reason": "ACCEPTED", "order_id": id, "quantity": amount, "price": price, "denomination": denomination, "route_id": route["id"], "seller_site": seller_site, "buyer_site": buyer_site}


## Caps are request-sized quantities, never a public copy of private balances.
## Refusals are an exclusive decomposition: receiver, logistics, purchasing
## power, then seller supply. All binding dimensions remain in caps.
func _request_limits(quantity: int, stock: int, logistics: int, headroom: int, cash: int) -> Dictionary:
	var caps := {"buyer_capacity": mini(quantity,maxi(0,headroom)), "logistics": mini(quantity,maxi(0,logistics)), "cash": mini(quantity,maxi(0,cash)), "seller_stock": mini(quantity,maxi(0,stock))}
	var refused := {"buyer_capacity":0,"logistics":0,"cash":0,"seller_stock":0,"price":0,"authorization":0,"budget":0,"information":0}
	var remaining := quantity
	for cause: String in ["buyer_capacity","logistics","cash","seller_stock"]:
		var next := mini(remaining,int(caps[cause]))
		refused[cause] = remaining-next
		remaining = next
	return {"basis":"REQUEST_LIMITS_V1_EXCLUSIVE_QUANTITIES","caps":caps,"refused":refused,"accepted_quantity":remaining,"unmet_quantity":quantity-remaining}

func _request_rejection(quantity: int, cause: String) -> Dictionary:
	var result := _request_limits(quantity,quantity,quantity,quantity,quantity)
	result["caps"] = {}
	result["refused"][cause] = quantity
	result["accepted_quantity"] = 0
	result["unmet_quantity"] = quantity
	return result

func _request_supply_pressure(row: Dictionary) -> int:
	# Old mixed physical history remains observable but cannot be reclassified
	# as proven stock shortage. Fresh classified enquiries replace it normally.
	return int(row.get("limit_observation",{}).get("refused",{}).get("seller_stock",0))

func _request_pressure_records(site: String, good: String) -> Array[Dictionary]:
	var latest: Dictionary = {}
	var legacy: Array[Dictionary] = []
	for row: Dictionary in _request_window.get(site+"|"+good,[]):
		if not row.has("buyer"):
			legacy.append(row);continue
		latest[str(row["buyer"])+"|"+str(row["need_by_day"])] = row
	for row: Dictionary in latest.values(): legacy.append(row)
	return legacy

func _request_price_information(row: Dictionary) -> bool:
	return not str(row.get("order_id","")).is_empty() or _request_supply_pressure(row)>0 or int(row.get("cash_refused",0))+int(row.get("price_refused",0))>0


func _observe_request(buyer: String, seller: String, good: String, quantity: int, order_id: String, physical: int, cash: int, price: int, need_by: int, action_id: String, limits: Dictionary = {}) -> void:
	if quantity <= 0: return
	var key := seller + "|" + good
	var records: Array = _request_window.get(key, [])
	for index: int in range(records.size() - 1, -1, -1):
		var prior := records[index] as Dictionary
		if prior.get("buyer", "") != buyer: continue
		# Same unresolved need/time is one enquiry, including a successful retry.
		# Independent accepted orders and distinct actual need boundaries survive.
		if prior.get("action_id", "") == action_id or (int(prior.get("need_by_day",-1)) == need_by and str(prior.get("order_id", "")).is_empty()) or not prior.has("limit_observation"):
			records.remove_at(index)
	var row := {"day":day,"buyer":buyer,"quantity":quantity,"order_id":order_id,"action_id":action_id,"physical_unmet":physical,"cash_refused":cash,"price_refused":price,"need_by_day":need_by}
	if limits.is_empty(): limits = _request_rejection(quantity,"price") if price>0 else _request_limits(quantity,quantity-physical,quantity,quantity,quantity-cash)
	row["limit_observation"] = limits.duplicate(true)
	_request_window[key] = records + [row]


func _valid_request_limits(row: Dictionary, orders: Dictionary, response: Dictionary) -> bool:
	var o: Variant = row["limit_observation"]
	if not o is Dictionary or not FormalLedgerState.exact_fields(o,["basis","caps","refused","accepted_quantity","unmet_quantity"]) or o["basis"]!="REQUEST_LIMITS_V1_EXCLUSIVE_QUANTITIES" or not o["caps"] is Dictionary or not o["refused"] is Dictionary: return false
	if not FormalLedgerState.exact_fields(o["refused"],["buyer_capacity","logistics","cash","seller_stock","price","authorization","budget","information"]): return false
	var total := 0
	for v: Variant in o["refused"].values():
		if not FormalLedgerState.valid_amount(v): return false
		total += int(v)
	if not FormalLedgerState.valid_amount(o["accepted_quantity"]) or not FormalLedgerState.valid_amount(o["unmet_quantity"]) or total!=o["unmet_quantity"] or total+int(o["accepted_quantity"])!=row["quantity"]: return false
	if row["physical_unmet"]!=o["refused"]["seller_stock"] or row["cash_refused"]!=o["refused"]["cash"] or row["price_refused"]!=o["refused"]["price"]: return false
	if not o["caps"].is_empty():
		if not FormalLedgerState.exact_fields(o["caps"],["buyer_capacity","logistics","cash","seller_stock"]): return false
		for v: Variant in o["caps"].values():
			if not FormalLedgerState.valid_amount(v) or v>row["quantity"]: return false
		if _request_limits(row["quantity"],o["caps"]["seller_stock"],o["caps"]["logistics"],o["caps"]["buyer_capacity"],o["caps"]["cash"])!=o: return false
	else:
		var reason: String = str(response.get("reason",""))
		var causes := {"price":["PURCHASE_PRICE_LIMIT"],"budget":["CUMULATIVE_BUDGET_OR_WINDOW"],"authorization":["NOT_AN_ENTERPRISE_PROCUREMENT_CONTEXT","PROCUREMENT_REQUIRES_MULTIPLE_ROOT_AUTHORITIES","PROCUREMENT_AMOUNT_BOUNDS","INVALID_PROCUREMENT_AUTHORITY","NO_AUTHORIZED_PROCUREMENT_REPRESENTATIVE","NO_PROCUREMENT_AUTHORITY"],"information":["EXPIRED_QUOTE","QUOTE_INFORMATION_NOT_RECEIVED","NO_VALID_QUOTATION","NO_KNOWN_CURRENT_QUOTE","UNKNOWN_GOODS_QUOTATION","GOODS_QUOTATION_NOT_RECEIVED","GOODS_QUOTATION_EXPIRED","GOODS_QUOTE_NOT_RECEIVED","GOODS_QUOTE_EXPIRED","GOODS_QUOTE_SUPERSEDED"]}
		var cause := ""
		for field: String in o["refused"]:
			if int(o["refused"][field])==0: continue
			if not cause.is_empty() or not causes.has(field) or int(o["refused"][field])!=int(row["quantity"]): return false
			cause=field
		if cause.is_empty() or reason not in causes[cause]: return false
	var id: String = row["order_id"]
	if id.is_empty() and response.get("accepted",false): return false
	if not id.is_empty() and (not response.get("accepted",false) or response.get("order_id")!=id): return false
	if not o["caps"].is_empty() and response.get("reason")=="NO_STOCK" and int(o["caps"]["seller_stock"])!=0: return false
	return int(o["accepted_quantity"])==int(orders[id]["quantity"]) if not id.is_empty() and orders.has(id) else int(o["accepted_quantity"])==0


func _cancel(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["order_id"]) or not payload["order_id"] is String or not _orders.has(payload["order_id"]):
		return _result(false, "UNKNOWN_ORDER")
	var id := str(payload["order_id"])
	var order := _orders[id] as Dictionary
	if order.has("supply_contract_id"): return _result(false,"SUPPLY_BATCH_REQUIRES_ORIGINAL_FULFILMENT")
	if order["buyer"] != actor and not (_spec["firms"].has(order["buyer"]) and _manager(actor, order["buyer"])):
		return _result(false, "NOT_ORDER_OWNER")
	var amount := int(order["pending"])
	if _cargo_fulfilment.unresolved(id) > 0: return _result(false, "LOSS_REQUIRES_CONFIRMED_DISPOSITION")
	if amount <= 0:
		return _result(false, "NO_PENDING_QUANTITY")
	var custody: Dictionary = {}
	if order["kind"] == "PERSONAL_FREIGHT":
		custody = _custody_fact(actor, order["good"], amount, "FREIGHT|" + id, "STORED|" + str(order["from_place_id"]), action_id, "freight_cancel")
		custody["allocations"] = _personal_allocations_for_portions(actor, order["good"], _lots.selection("PERSON|"+actor+"|FREIGHT|"+id, order["good"], amount), "FREIGHT|"+id)
		if not _world.personal_economy_state.native_custody_ready(custody): return _result(false, "INVALID_CUSTODY_SOURCE")
	var prepared := _world.personal_economy_state.prepare_native_custody(custody) if not custody.is_empty() else {}
	var source_rows := _physical_person_rows(actor, order["good"], custody.get("allocations", [])) if order["kind"] == "PERSONAL_FREIGHT" else _lots.reserved_selection(id, mini(amount, _lots.reserved_quantity(id)))
	if (not source_rows.is_empty() and not _lots.ready(source_rows)) or (source_rows.is_empty() and order["kind"] == "PERSONAL_FREIGHT") or (not custody.is_empty() and prepared.is_empty()) or not _budgets.change_ready(id, order["delivered"], int(order["cancelled"])+amount, order["quantity"]): return _result(false, "INVALID_CANCELLATION_ADOPTION")
	if int(order["price"]) + _freight(order["route_legs"]) > 0 and not _world.ledger_state.release(id, amount * (int(order["price"]) + _freight(order["route_legs"]))):
		return _result(false, "RESERVATION_ERROR")
	if not custody.is_empty():
		_world.personal_economy_state.adopt_native_change(prepared)
		_lots.move(source_rows, "PERSON|"+actor+"|STORED|"+str(order["from_place_id"]), order["from_place_id"], _world.game_clock.total_minutes(), "", "", "", order["source_custody_site"])
	else:
		var q := mini(amount, _lots.reserved_quantity(id))
		if q > 0:
			var released := _lots.release(id, q, _world.game_clock.total_minutes())
			assert(released)
	var settled := _budgets.settle("cancel:"+action_id, id, order["delivered"], int(order["cancelled"])+amount, order["quantity"])
	assert(settled)
	_change_order_observation(order, -amount)
	if order["kind"] != "PERSONAL_FREIGHT": _change_incoming(order, -amount)
	order["pending"] = 0
	order["cancelled"] = int(order["cancelled"]) + amount
	var key := str(order["seller_site"]) + "|" + str(order["good"])
	_pending_by_key[key] = int(_pending_by_key.get(key, 0)) - amount
	_pending_orders.erase(id)
	_pending_ids_by_key.get(key, {}).erase(id)
	if int(order["transit"]) == 0:
		_active_orders.erase(id)
		_active_by_buyer[order["buyer"]].erase(id)
		_active_sales_by_key.get(key,{}).erase(id)
	var edge := _edge(order["route_legs"][0]["edge_id"])
	if int(order["accepted_day"]) == day:
		edge["input_used"] = int(edge["input_used"]) - amount
	edge["holds"].erase(id)
	return {"accepted": true, "reason": "ACCEPTED", "custody_fact": custody} if not custody.is_empty() else _result(true, "ACCEPTED")


func settle_day(settle_personal_arrangements: bool = true) -> bool:
	if processing or _world.game_clock.current_day() != day + 1:
		return _fail("R1 boundary must follow exactly one host day")
	processing = true
	day += 1
	advance_time()
	_begin_market_day()
	for edge: Dictionary in _transport["edges"].values():
		edge["period"] = day
		edge["input_used"] = 0
		edge["dispatched"] = 0
	for node: Dictionary in _transport["nodes"].values():
		node["dispatched"] = 0
	phase = "MESSAGES"
	_commercial.advance_day()
	_deliver_messages()
	_local_quotes.announce_known()
	phase = "ARRIVALS"
	if not _advance_shipments():
		processing = false
		return false
	if not _pay_wages():
		processing = false
		return false
	phase = "OPERATIONS"
	_decision_counts = {"day": day, "production_sites": 0, "resting_sites": 0, "household_searches": 0, "job_searches": 0, "cashless_households": 0, "covered_households": 0}
	_prune_windows()
	if not _npc_liquidity():
		processing=false
		return false
	_plan_firms()
	_update_job_postings()
	phase = "LABOR"
	_labor.clear()
	_capital_work_ids.clear()
	if not uses_host_accounts(): _auto_work()
	for actor: String in _sorted_ids(_work_queue):
		for work: Dictionary in _work_rows(actor):
			var contract := _contract_for(actor, work["job"])
			var job := _labor_market.contract_job(contract)
			if not _at_place(actor, job["place"]) or not _site_operating(job["site_id"],_production_minute()):
				# A future work booking does not permit labor from another host place.
				_commands[work["action_id"]]["result"].merge({"completed": false, "settlement_reason": "OUTSIDE_JOB_PLACE_OR_TRAVELLING" if not _at_place(actor, job["place"]) else "WORK_SITE_STOPPED", "work_day": day})
				continue
			var id := _work_id(day, actor, job["id"])
			var hours := int(work["hours"])
			var amount := hours * int(job["wage_per_hour"])
			_capital_work_ids.append(id)
			_work_records[id] = {"actor": actor, "job": job["id"], "hours": hours, "day": day, "action_id": work["action_id"]}
			if contract.has("employment_action_id"): _work_records[id]["employment_action_id"]=contract["employment_action_id"]
			_index_employment_work(_work_records[id])
			_labor[job["site_id"]] = int(_labor.get(job["site_id"], 0)) + hours
			_totals[actor]["work_hours"] = int(_totals[actor]["work_hours"]) + hours
			_wages[id] = {"id": id, "worker": actor, "employer": job["employer"], "hours": hours, "amount": amount, "remaining": amount, "work_day": day, "due_day": day + int(job.get("wage_delay",_wage_delay(job["id"]))), "paid": 0}
			_wages[id]["denomination"] = contract["denomination"]
			_costs.observe_work(id)
			if amount > 0:
				_open_wages.append(id)
				_index_wage(id)
			else: _index_wage_history(_wages[id])
	_work_queue.clear()
	if not _pay_wages():
		processing = false
		return false
	phase = "CREDIT"
	_credit.advance_day(day)
	_npc_repay_debts()
	_wind_down.npc_decisions()
	phase = "CAPITAL_CONSTRUCTION"
	_capital.build()
	_service_market.build(_capital._last_build_work)
	var shared_work:=_capital._last_build_work.duplicate()
	for id: String in _service_market._last_work: shared_work[id]=int(shared_work.get(id,0))+int(_service_market._last_work[id])
	_retail.prepare_labor(shared_work)
	for id: String in _retail.last_work: shared_work[id]=int(shared_work.get(id,0))+int(_retail.last_work[id])
	_shared.prepare_labor(shared_work)
	phase = "PRODUCTION"
	_produce()
	phase = "PROCUREMENT"
	_leases.advance_day()
	_leases.npc_decisions("BEFORE_OPTIONAL_SERVICES_AND_GOODS")
	_service_market._resident.npc_decisions()
	_supply.npc_decisions()
	_auto_purchase()
	_leases.npc_decisions("AFTER_GOODS")
	_procure_inputs()
	_procure_capital()
	phase = "DISPATCH"
	if not _dispatch_transport():
		processing = false
		return false
	if not _capital_transport.advance():
		processing=false
		return _fail("Capital freight payment failed")
	phase = "CONSUMPTION"
	if not _consume():
		processing = false
		return false
	if settle_personal_arrangements: _world.personal_economy_state.settle_due_consumption()
	_close_price_windows()
	phase = "READY"
	_publish_site_reports()
	_npc_invest()
	_capital.npc_build()
	_capital.npc_resale()
	_local_quotes.npc_decisions()
	_service_market.npc_decisions()
	_commercial.npc_decisions()
	_npc_labor_response()
	_labor_market.worker_decisions()
	_labor_market.npc_decisions()
	if not uses_host_accounts(): _capital.boundary()
	if uses_host_accounts() and _labor_market._rules.is_empty(): _auto_work()
	if _assets.call_market.enabled():
		_assets.primary.npc_decisions()
		_assets.call_market.npc_decisions()
		phase="EQUITY_CLEARING"
		_assets.primary.clear_day()
		_assets.call_market.clear_day()
		_assets.distribution.clear_day()
		phase="READY"
	_assets.corporate.npc_decisions()
	_prune_windows()
	_supply.refresh()
	processing = false
	safe_boundary.emit()
	return true


func _auto_command(actor: String, kind: String, payload: Dictionary, candidate: String = "") -> Dictionary:
	return {"action_id": "auto:" + actor + ":" + str(day) + ":" + kind + ":" + candidate, "minute": _world.game_clock.total_minutes(), "kind": kind, "payload": payload}


func _advance_shipments(timed_only: bool = false) -> bool:
	var ids := _sorted_ids(_moving_shipments)
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("shipment:")) < int(b.trim_prefix("shipment:")))
	var edges := _all_routes()
	for id: String in ids:
		var shipment := _shipments[id] as Dictionary
		var order := _orders[shipment["order_id"]] as Dictionary
		if shipment["stage"] == "AWAITING_RECIPIENT":
			continue
		if int(shipment["quantity"]) <= 0: _moving_shipments.erase(id); continue
		var now: int = _world.game_clock.total_minutes()
		if shipment["stage"] == "LOADING":
			if int(shipment["loading_end_minute"]) > now: continue
			shipment["stage"] = "TRANSIT"
		var at_node: bool = shipment["stage"] in ["WAITING_UNLOAD","UNLOADING"]
		if timed_only and not shipment.has("arrival_minute") and not at_node: continue
		if at_node:
			if not _shared.arrive(shipment,order): continue
		elif shipment["stage"] != "TRANSIT" or (int(shipment["arrival_minute"]) > now if shipment.has("arrival_minute") else int(shipment["leg_arrival_day"]) > day): continue
		var leg := order["route_legs"][int(shipment["leg_index"])] as Dictionary
		if not at_node:
			shipment["place_id"] = edges[leg["edge_id"]]["to_place_id"]
			var physical := _lots.selection("CARGO|"+id, order["good"], _lots.quantity_at("CARGO|"+id, order["good"]))
			if _lots.quantity_at("CARGO|"+id, order["good"]) > 0 and _lots.move(physical, "CARGO|"+id, shipment["place_id"], _world.game_clock.total_minutes()).is_empty(): return _fail("Arrival lacks its actual cargo portions")
			if not _shared.arrive(shipment,order):
				if shipment["stage"] != "UNLOADING": shipment["stage"] = "WAITING_UNLOAD"
				continue
		if int(shipment["leg_index"]) + 1 == order["route_legs"].size():
			if _lots.quantity_at("CARGO|"+id, order["good"]) < int(shipment["quantity"]):
				shipment["stage"] = "AWAITING_RECIPIENT"
				shipment["ready_day"] = shipment["leg_arrival_day"]
				continue # Quantity lost is still unresolved contract responsibility.

			if order["kind"] == "PERSONAL_FREIGHT" or not _recipient_at_destination(order):
				shipment["stage"] = "AWAITING_RECIPIENT"
				shipment["ready_day"] = shipment["leg_arrival_day"]
				continue
			var custody := "CARRIED"
			if manages_person(order["buyer"]) and not _can_carry_extra(order["buyer"], order["good"], int(shipment["quantity"])):
				if _personal_storage_site(order["to_place_id"], order["good"]).is_empty():
					shipment["stage"] = "AWAITING_RECIPIENT"
					shipment["ready_day"] = shipment["leg_arrival_day"]
					continue
				custody = "STORED"
			if not _deliver_shipment(shipment, order, "", -1, custody): return false
		else:
			shipment["leg_index"] = int(shipment["leg_index"]) + 1
			shipment["ready_day"] = shipment["leg_arrival_day"]
			shipment["leg_arrival_day"] = -1
			shipment.erase("arrival_minute")
			shipment.erase("loading_end_minute")
			shipment.erase("unloading_end_minute")
			shipment["stage"] = "WAITING"
	return true

func _recipient_at_destination(order: Dictionary) -> bool:
	var buyer := str(order["buyer"])
	return not uses_host_accounts() or not _spec["actors"].has(buyer) or _spec["actors"][buyer]["kind"] != "named" or _at_place(buyer, order["to_place_id"])

## Locked per-unit contracts have integral cumulative shares. No repricing or
## fixed-fee transport term is introduced by splitting a physical receipt.
func _collection_payment(order: Dictionary, quantity: int, unit_amount: int) -> int:
	var before := int(order["delivered"])
	return (before + quantity) * unit_amount - before * unit_amount

func _delivery_legs(id: String, order: Dictionary, quantity: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if order["kind"] == "SALE":
		result.append({"transaction_id": "r1:goods:" + id, "from_account_id": order["buyer_account"], "to_account_id": order["seller_account"], "amount": _collection_payment(order, quantity, int(order["price"])), "kind": "goods", "reference_id": order["id"]})
	var legs := order["route_legs"] as Array
	for index: int in legs.size():
		var leg := legs[index] as Dictionary
		if int(leg["freight_per_unit"]) <= 0:
			continue
		var tx := "r1:freight:" + id + (":" + str(index) if legs.size() > 1 else "")
		result.append({"transaction_id": tx, "from_account_id": order["buyer_account"], "to_account_id": leg["carrier_account"], "amount": _collection_payment(order, quantity, int(leg["freight_per_unit"])), "kind": "freight", "reference_id": order["id"]})
	return result

func _deliver_shipment(shipment: Dictionary, order: Dictionary, collection_action_id: String = "", requested: int = -1, custody_mode: String = "CARRIED") -> bool:
	var shipment_id := str(shipment["id"])
	var quantity := int(shipment["quantity"]) if requested < 0 else requested
	if quantity <= 0 or quantity > int(shipment["quantity"]): return _fail("INVALID_COLLECTION_QUANTITY")
	var already := int(_collected_by_shipment.get(shipment_id, 0))
	var id := shipment_id if already == 0 and quantity == int(shipment["quantity"]) else shipment_id + ":part:" + str(already + quantity)
	var receipt := {"id": id, "order_id": order["id"], "quantity": quantity, "departures": shipment["departures"].duplicate(), "delivered_day": day, "delivered_minute": _world.game_clock.total_minutes()}
	if shipment.has("departure_quantities"): receipt["departure_quantities"] = shipment["departure_quantities"].duplicate()
	if shipment.has("replacement_disposition_ids"): receipt["replacement_disposition_ids"] = shipment["replacement_disposition_ids"].duplicate()
	if id != shipment_id: receipt["shipment_id"] = shipment_id
	if not collection_action_id.is_empty(): receipt["collection_action_id"] = collection_action_id
	var personal: bool = manages_person(order["buyer"])
	var freight: bool = order["kind"] == "PERSONAL_FREIGHT"
	if personal:
		if custody_mode == "STORED" and _personal_storage_site(order["to_place_id"], order["good"]).is_empty(): return _fail("NO_CONFIGURED_PERSONAL_CUSTODY")
		if custody_mode == "CARRIED" and not _can_carry_extra(order["buyer"], order["good"], quantity): return _fail("COLLECTION_REQUIRES_STORAGE_OR_SMALLER_QUANTITY")
		receipt.merge({"custody_mode": custody_mode, "custody_place_id": order["to_place_id"]})
		if freight:
			var fact := _custody_fact(order["buyer"], order["good"], quantity, "FREIGHT|" + str(order["id"]), "CARRIED" if custody_mode == "CARRIED" else "STORED|" + str(order["to_place_id"]), id, "freight_collect")
			fact["allocations"] = _personal_allocations_for_portions(order["buyer"], order["good"], _lots.selection("CARGO|"+shipment_id, order["good"], quantity), "FREIGHT|"+str(order["id"]))
			if not _world.personal_economy_state.native_custody_ready(fact): return _fail("NO_ORIGINAL_PERSONAL_FREIGHT_LOTS")
			receipt["custody_fact"] = fact
	var legs := _delivery_legs(id, order, quantity)
	var releases := {str(order["id"]): quantity * (int(order["price"]) + _freight(order["route_legs"]))}
	var physical := _lots.reserved_selection(order["id"],quantity) if Retail.onsite(order) else _lots.selection("CARGO|"+shipment_id, order["good"], quantity)
	if not _lots.ready(physical): return _fail("DELIVERY_SOURCE_PORTIONS_UNAVAILABLE")
	var cost_ranges := _costs.ranges(physical)
	if not _budgets.change_ready(order["id"], int(order["delivered"])+quantity, int(order["cancelled"]), int(order["quantity"])): return _fail("INVALID_BUDGET_FULFILMENT")
	var prepared_personal: Dictionary = {}
	if personal:
		if freight:
			prepared_personal = _world.personal_economy_state.prepare_native_custody(receipt["custody_fact"])
		else:
			var source := _personal_order_source(order)
			var transaction_ids: Array[String] = []
			for payment: Dictionary in legs: transaction_ids.append(payment["transaction_id"])
			source.merge({"source_id": id, "shipment_id": receipt.get("shipment_id", id), "quantity": quantity, "amount": quantity*(int(order["price"])+_freight(order["route_legs"])), "transaction_ids": transaction_ids, "effective_minute": _world.game_clock.total_minutes(), "custody_mode": custody_mode, "custody_place_id": order["to_place_id"]}, true)
			prepared_personal = _world.personal_economy_state.prepare_native_source(order["buyer"], source, "native_delivery")
		if prepared_personal.is_empty(): return _fail("INVALID_PERSONAL_DELIVERY_ADOPTION")

	if not legs.is_empty() and not _world.ledger_state.batch_payment("delivery:" + id, legs, _world.game_clock.total_minutes(), releases): return _fail(_world.ledger_state.error)
	# All fallible checks precede payment. No external action runs between these
	# prepared adoptions; no successful receipt exists before physical adoption.
	if personal: _world.personal_economy_state.adopt_native_change(prepared_personal)
	var location := "PERSON|"+str(order["buyer"])+"|"+("CARRIED" if custody_mode == "CARRIED" else "STORED|"+str(order["to_place_id"])) if personal else "ACTOR|"+str(order["buyer"]) if _actors.has(order["buyer"]) else "SITE|"+_destination(order)
	var custodian: String = order["buyer"] if personal and custody_mode == "CARRIED" else _personal_storage_site(order["to_place_id"], order["good"]) if personal else _destination(order)
	var moved := _lots.move(physical, location, order["to_place_id"], _world.game_clock.total_minutes(), order["buyer"], "" if freight else id, "", custodian)
	assert(not moved.is_empty())
	if not Retail.onsite(order): _shared.release_storage(shipment_id,order["good"],quantity,"delivery:"+id)
	var budget_settled := _budgets.settle("delivery:"+id, order["id"], int(order["delivered"])+quantity, int(order["cancelled"]), int(order["quantity"]))
	assert(budget_settled)
	if not freight: _change_incoming(order, -quantity)
	order["transit"] = int(order["transit"]) - quantity
	order["delivered"] = int(order["delivered"]) + quantity
	if int(order["pending"]) + int(order["transit"]) == 0:
		_active_orders.erase(str(order["id"]))
		_active_by_buyer[order["buyer"]].erase(str(order["id"]))
		_active_sales_by_key.get(str(order["seller_site"])+"|"+str(order["good"]),{}).erase(order["id"])
	if order["kind"] == "SALE":
		var relation_key := _destination(order) + "|" + str(order["seller_site"]) + "|" + str(order["good"])
		var recent: Array = _relations.get(relation_key, [])
		recent.append(id)
		if recent.size() > COOPERATION_RECORD_LIMIT: recent.pop_front()
		_relations[relation_key] = recent
	shipment["quantity"] = int(shipment["quantity"]) - quantity
	if shipment["quantity"] == 0:
		_shipments_by_order.get(order["id"], {}).erase(shipment_id)
		if _shipments_by_order.get(order["id"], {}).is_empty(): _shipments_by_order.erase(order["id"])
		var cargo_key := _destination(order) + "|" + str(order["good"])
		_shipments_by_destination_good.get(cargo_key, {}).erase(shipment_id)
		if _shipments_by_destination_good.get(cargo_key, {}).is_empty(): _shipments_by_destination_good.erase(cargo_key)
		_moving_shipments.erase(shipment_id)
		# Preserve entry history of a damaged batch after all surviving goods are acquired.
		if _cargo_fulfilment.cargo_loss(shipment_id) > 0: shipment["stage"] = "LOSS_RECORD"
		else: _shipments.erase(shipment_id)
	_delivery_receipts[id] = receipt
	_index_delivery(receipt)
	_retail.adopted(receipt,order)
	_costs.delivery(id, order, cost_ranges, moved)
	return true

func _dispatch_transport(shared_only: bool = false) -> bool:
	var queue: Array[Dictionary] = []
	for shipment_id: String in _moving_shipments:
		var shipment := _shipments[shipment_id] as Dictionary
		if shipment["stage"] == "WAITING" and int(shipment["ready_day"]) <= day:
			queue.append({"id": shipment["id"], "shipment": true, "ready_day": shipment["ready_day"], "order_id": shipment["order_id"]})
	for id: String in _pending_orders:
		var order := _orders[id] as Dictionary
		var ready := _earliest_dispatch(order)
		if ready <= day:
			queue.append({"id": id, "shipment": false, "ready_day": ready, "order_id": id})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ready_day"] != b["ready_day"]:
			return int(a["ready_day"]) < int(b["ready_day"])
		var first := int(str(a["order_id"]).trim_prefix("order:"))
		var second := int(str(b["order_id"]).trim_prefix("order:"))
		if first != second:
			return first < second
		var first_shipment := int(str(a["id"]).trim_prefix("shipment:")) if a["shipment"] else 0
		var second_shipment := int(str(b["id"]).trim_prefix("shipment:")) if b["shipment"] else 0
		return first_shipment < second_shipment)
	var edges := _all_routes()
	for item: Dictionary in queue:
		var order := _orders[item["order_id"]] as Dictionary
		if item["shipment"]:
			var shipment := _shipments[item["id"]] as Dictionary
			var leg := order["route_legs"][int(shipment["leg_index"])] as Dictionary
			if _shared.alias_requires_binding(leg["edge_id"]) or not _cargo_edge_valid(edges[leg["edge_id"]]): continue
			if shared_only and not _shared.bindings.has(leg["edge_id"]): continue
			var edge := _edge(leg["edge_id"])
			var place := str(edges[leg["edge_id"]]["from_place_id"])
			var free := mini(_shared.quantity(leg["edge_id"], order["good"], FormalLedgerState.MAX_AMOUNT) if _shared.bindings.has(leg["edge_id"]) else maxi(0, int(edge["capacity"])-int(edge["dispatched"])), _node_available(place))
			if int(shipment["quantity"]) <= free and _shared.enter(shipment["id"], shipment["leg_index"], leg["edge_id"], order["good"], shipment["quantity"]):
				_enter_transport_leg(shipment, order)
			continue
		var leg := order["route_legs"][0] as Dictionary
		if _shared.alias_requires_binding(leg["edge_id"]): continue
		if shared_only and not _shared.bindings.has(leg["edge_id"]): continue
		var edge := _edge(leg["edge_id"])
		var place := str(edges[leg["edge_id"]]["from_place_id"])
		# Reuse one partial first dispatch per order/day. Intermediate batches
		# stay intact, rather than expanding one order into an unbounded queue.
		if int(order["pending"]) > 0:
			var free := mini(_shared.quantity(leg["edge_id"], order["good"], FormalLedgerState.MAX_AMOUNT) if _shared.bindings.has(leg["edge_id"]) else maxi(0, int(edge["capacity"])-int(edge["dispatched"])), _node_available(place))
			var physical_pending: int = _lots.quantity_at("PERSON|"+str(order["buyer"])+"|FREIGHT|"+str(order["id"]), order["good"]) if order["kind"] == "PERSONAL_FREIGHT" else _lots.reserved_quantity(order["id"])
			var quantity := mini(mini(int(order["pending"]), physical_pending), mini(free, _batch_limit(order["route_legs"])))
			if quantity <= 0:
				continue
			if next_shipment >= FormalLedgerState.MAX_AMOUNT:
				return _fail("Shipment ID limit")
			var id := "shipment:" + str(next_shipment)
			var shipment := {"id": id, "order_id": order["id"], "quantity": quantity, "stage": "WAITING", "leg_index": 0, "place_id": order["from_place_id"], "ready_day": item["ready_day"], "leg_arrival_day": -1, "departures": [], "departure_quantities": []}
			var source_rows := _lots.reserved_selection(order["id"], quantity) if order["kind"] != "PERSONAL_FREIGHT" else _lots.selection("PERSON|"+str(order["buyer"])+"|FREIGHT|"+str(order["id"]), order["good"], quantity)
			if not _lots.ready(source_rows): return _fail("Dispatch lacks its full physical source bundle")
			var replacements := _cargo_fulfilment.replacement_references(order["id"], source_rows, _lots.portions)
			if not replacements.is_empty(): shipment["replacement_disposition_ids"] = replacements
			if not _shared.enter(id, 0, leg["edge_id"], order["good"], quantity): continue

			if order["kind"] != "PERSONAL_FREIGHT":
				var adopted := _lots.move(_lots.reserved_selection(order["id"], quantity), "CARGO|"+str(shipment["id"]), shipment["place_id"], _world.game_clock.total_minutes())
				if adopted.is_empty(): return _fail("Dispatch lacks its actual committed batch portions")
			else:
				var rows := _lots.selection("PERSON|"+str(order["buyer"])+"|FREIGHT|"+str(order["id"]), order["good"], quantity)
				if _lots.move(rows, "CARGO|"+str(shipment["id"]), shipment["place_id"], _world.game_clock.total_minutes()).is_empty(): return _fail("Personal dispatch lacks its actual locked batch portions")
			order["pending"] = int(order["pending"]) - quantity
			order["transit"] = int(order["transit"]) + quantity
			var key := str(order["seller_site"]) + "|" + str(order["good"])
			_pending_by_key[key] = int(_pending_by_key.get(key, 0)) - quantity
			_shipments[id] = shipment
			_index_shipment(shipment)
			next_shipment += 1
			_enter_transport_leg(shipment, order)
		if int(order["pending"]) == 0:
			_pending_orders.erase(str(order["id"]))
			_pending_ids_by_key.get(str(order["seller_site"]) + "|" + str(order["good"]), {}).erase(str(order["id"]))
			edge["holds"].erase(order["id"])
		else:
			edge["holds"][order["id"]]["quantity"] = order["pending"]
	return true

func _enter_transport_leg(shipment: Dictionary, order: Dictionary) -> void:
	var leg := order["route_legs"][int(shipment["leg_index"])] as Dictionary
	var custody := str(_all_routes()[leg["edge_id"]]["carrier"])
	var rows := _lots.selection("CARGO|"+str(shipment["id"]), order["good"], shipment["quantity"])
	var adopted := _lots.move(rows, "CARGO|"+str(shipment["id"]), shipment["place_id"], _world.game_clock.total_minutes(), "", "", "", custody)
	assert(not adopted.is_empty())

	var edge := _edge(leg["edge_id"])
	edge["dispatched"] = int(edge["dispatched"]) + int(shipment["quantity"])
	if _transport["nodes"].has(shipment["place_id"]):
		var node := _transport["nodes"][shipment["place_id"]] as Dictionary
		node["dispatched"] = int(node["dispatched"]) + int(shipment["quantity"])
	shipment["stage"] = "TRANSIT"
	if not shipment.has("departure_quantities"):
		shipment["departure_quantities"] = []
		for prior: int in shipment["departures"]: shipment["departure_quantities"].append(int(shipment["quantity"])+int(_collected_by_shipment.get(shipment["id"], 0)))
	shipment["departures"].append(day)
	shipment["departure_quantities"].append(shipment["quantity"])
	shipment["leg_arrival_day"] = day + int(leg["delay"])
	var entry := _shared.entries.get("economy_entry:"+str(shipment["id"])+":"+str(shipment["leg_index"]), {}) as Dictionary
	if entry.has("arrival_minute"):
		shipment["loading_end_minute"] = entry["loading_end_minute"]
		shipment["arrival_minute"] = entry["arrival_minute"]
		shipment["leg_arrival_day"] = int(entry["arrival_minute"])/1440
		if int(entry["loading_end_minute"]) > _world.game_clock.total_minutes(): shipment["stage"] = "LOADING"


func _auto_work(people: Array[String] = [], decision: String = "") -> void:
	var subjects: Array[String] = people if not people.is_empty() else _actor_ids()
	for actor: String in subjects:
		if _assets.corporate.enabled() and actor==_assets.corporate.config["controller"] and _assets.corporate.managed(_world.game_clock.total_minutes()): continue # Explicit management role, no automatic factory job.
		if _actors[actor]["control"] != "automatic" or (_employment_end_pending(actor) and _cohort_profile(actor).is_empty()) or _legacy_wage_still_active(actor): continue
		if not _cohort_profile(actor).is_empty():
			_auto_cohort_work(actor)
			continue
		if _work_queue.has(actor): continue
		if manages_person(actor) and _world.person_travel != null:
			if _world.person_travel.active(actor): continue
			observe_person_place(actor)
			_collect_ready_cargo(actor)
		if not _contracts.has(actor):
			for job_id: String in _labor_market.ordered_jobs(actor,_actors[actor]["known_jobs"]):
				var job := _known_job(actor, job_id)
				if not _npc_job_payable(actor,job_id): continue
				if not _at_place(actor, job["place"]) and (not manages_person(actor) or not _npc_job_travel_possible(actor, job)): continue
				var candidate := job_id+(":"+decision if not decision.is_empty() else "")
				if _accept(actor, _auto_command(actor, "apply", _labor_market.apply_payload(actor,job_id), candidate), true)["accepted"]: break
		if not _contracts.has(actor): continue
		var job := _labor_market.contract_job(_contracts[actor])
		if not _site_operating(job["site_id"]): continue
		if manages_person(actor) and not _at_place(actor, job["place"]):
			if _npc_job_travel_possible(actor, job):
				_accept(actor, _auto_command(actor, "travel", {"destination_place_id": job["place"]}, decision), true)
			continue
		var hours := int(job["hours"])*int(_contracts[actor]["workers"])
		if uses_host_accounts():
			hours = mini(hours, (((day+1)*1440-_world.game_clock.total_minutes())/60)*int(_contracts[actor]["workers"]))
		if hours > 0 and _accept(actor, _auto_command(actor, "work", {"hours": hours}, decision), true)["accepted"]:
			if not uses_host_accounts(): _work_queue[actor]["day"] = day


func _auto_cohort_work(actor: String) -> void:
	var profile := _cohort_profile(actor)
	var free := Cohorts.free_span(_spec["actors"][actor], _contracts.get(actor, {}))
	var search_day := int(_cohort_search_day.get(actor, -30))
	var due: bool = day-search_day >= int(profile["job_search_days"])
	for job: String in _actors[actor]["known_jobs"]:
		var notice := _receipts.get("posting:"+actor+":"+job, _receipts.get("message:"+actor+":job:"+job, {})) as Dictionary
		if _labor_market.controls(job): notice=_labor_market.latest_notice(actor,job)
		if int(notice.get("delivery_day", -1)) > search_day: due = true
	if free.y > 0 and due and not _employment_end_pending(actor) and _contract_rows(_contracts.get(actor, {})).size() < int(profile["max_jobs"]):
		_cohort_search_day[actor] = day
		_decision_counts["job_searches"] = int(_decision_counts.get("job_searches", 0))+1
		for id: String in _labor_market.ordered_jobs(actor,_actors[actor]["known_jobs"]):
			if not Cohorts.allows_job(_spec["actors"][actor], id) or not _contract_for(actor, id).is_empty(): continue
			var job := _known_job(actor, id)
			if not _npc_job_payable(actor,id): continue
			if not _at_place(actor, job["place"]): continue
			_accept(actor, _auto_command(actor, "apply", _labor_market.apply_payload(actor,id), id), true)
			if Cohorts.free_span(_spec["actors"][actor], _contracts.get(actor, {})).y == 0: break
	for contract: Dictionary in _contract_rows(_contracts.get(actor, {})):
		var job := _labor_market.contract_job(contract)
		if not _site_operating(job["site_id"]) or not _at_place(actor, job["place"]): continue
		if _work_queue.get(actor, {}).get("allocations", {}).has(job["id"]): continue
		var work_workers:=_workable_workers(actor,contract)
		var hours := int(job["hours"])*work_workers
		if uses_host_accounts(): hours = mini(hours, (((day+1)*1440-_world.game_clock.total_minutes())/60)*work_workers)
		if hours > 0 and _accept(actor, _auto_command(actor, "work", {"job_id": job["id"], "hours": hours}, job["id"]), true)["accepted"]:
			if not uses_host_accounts(): _work_queue[actor]["allocations"][job["id"]]["day"] = day

func _pay_wages() -> bool:
	if _future_wages.has(day):
		for id: String in _future_wages[day]:
			_matured_wages.append(id)
		_future_wages.erase(day)
		_matured_wages.sort_custom(_wage_less)
	for id: String in _matured_wages.duplicate():
		var claim := _wages[id] as Dictionary
		if _wind_down.controls(claim["employer"]) and _firm_winding_down(claim["employer"]): continue
		var amount := mini(int(claim["remaining"]), _world.ledger_state.available_balance(_account(str(claim["employer"]), claim["denomination"])))
		if amount>0 and not _pay_wage_claim(id,amount): return false
	return true

func _pay_wage_claim(id: String, amount: int) -> bool:
	var claim:=_wages.get(id,{}) as Dictionary
	if claim.is_empty() or amount<1 or amount>claim["remaining"] or claim["due_day"]>day: return false
	var currency:=str(claim["denomination"])
	var transaction_id := "r1:wage:"+id+":"+str(claim["paid"])
	if not _world.ledger_state.transfer(transaction_id,_account(claim["employer"],currency),_account(claim["worker"],currency),amount,_world.game_clock.total_minutes(),"wage",id): return _fail(_world.ledger_state.error)
	claim["remaining"]=int(claim["remaining"])-amount;claim["paid"]=int(claim["paid"])+amount
	_observe_wage_payment(claim,amount)
	if currency==FormalLedgerState.DENOMINATION: _totals[claim["worker"]]["income"]=int(_totals[claim["worker"]]["income"])+amount
	if claim["remaining"]==0:
		_open_wages.erase(id);_open_wages_by_employer.get(claim["employer"],{}).erase(id);_matured_wages.erase(id);_wages_by_worker[claim["worker"]].erase(id)
	return true


func _finance_policy(actor: String) -> Dictionary:
	for row: Dictionary in config.get("npc_finance", []):
		if row["actor"] == actor:
			return row
	return {}

func _npc_submit(actor: String, kind: String, payload: Dictionary, candidate: String, decision: Dictionary) -> Dictionary:
	var command := _auto_command(actor, kind, payload, "finance:" + candidate)
	var id := str(command["action_id"])
	if _commands.has(id):
		return _accept(actor, command, true)
	var result := _accept(actor, command, true)
	if _commands.has(id):
		# Normal explanatory action history, not another financial balance/queue.
		_commands[id]["result"]["decision"] = decision.duplicate(true)
		result = (_commands[id]["result"] as Dictionary).duplicate(true)
	return result

func _npc_job_travel_possible(person: String, job: Dictionary) -> bool:
	if job.get("denomination", FormalLedgerState.DENOMINATION) != FormalLedgerState.DENOMINATION: return false
	if _world.person_travel == null or not _world.person_travel.npc_allowed(person) or _work_queue.has(person): return false
	var policy: Dictionary = _world.person_travel.npc_policy(person)
	var offer: Dictionary = _world.person_travel.quote(person, job["place"])
	if offer.is_empty() or int(offer["minutes"]) > int(policy["max_minutes"]) or int(offer["fare"]) > int(policy["max_fee"]): return false
	var cash := _world.ledger_state.available_balance(_account(person))
	# Only known current wages and real travel costs; no future income credited.
	return cash >= int(offer["fare"]) and int(job["wage_per_hour"])*int(job["hours"]) > int(offer["fare"])

func _npc_cash_floor(policy: Dictionary, currency: String) -> int:
	var floor_value := int(policy.get("cash_floors", {}).get(currency, 0))
	return maxi(floor_value,_liquidity_cash_floor(policy.get("actor",""),currency))

func _liquidity_cash_floor(firm: String, currency: String) -> int:
	var terms := Liquidity.policy(config,firm)
	if terms.is_empty() or terms["currency"]!=currency: return 0
	return maxi(int(terms["cash_floor"]),_mature_wage_position(firm,currency)["amount"] if terms["protect_due_wages"] else 0)

func _npc_financed_today(actor: String, currency: String, exchange: bool) -> int:
	var total: int = 0
	for receipt: Dictionary in _world.ledger_state.own_transactions(actor, day * 1440, (day + 1) * 1440):
		if receipt["denomination"] != currency:
			continue
		if exchange and receipt["kind"] in ["fx_principal", "fx_fee"] and receipt["from_account_id"] == _account(actor, currency):
			total = mini(FormalLedgerState.MAX_AMOUNT, total + int(receipt["amount"]))
		elif not exchange and receipt["kind"] == "loan_issue" and receipt["to_account_id"] == _account(actor, currency):
			total = mini(FormalLedgerState.MAX_AMOUNT, total + int(receipt["amount"]))
	return total

func _npc_repay_debts() -> void:
	var subjects := _actor_ids()
	subjects.append_array(_firm_ids())
	for actor: String in subjects:
		if _wind_down.controls(actor) and _firm_winding_down(actor): continue
		var policy := _finance_policy(actor)
		if policy.is_empty() or not policy["repay_due"]:
			continue
		var loans: Array = _credit.visible(actor, _known_credit_lenders(actor), _world.game_clock.total_minutes(), true)["loans"]
		loans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["due_day"]) < int(b["due_day"]) if a["due_day"] != b["due_day"] else int(str(a["id"]).trim_prefix("loan:")) < int(str(b["id"]).trim_prefix("loan:")))
		for loan: Dictionary in loans:
			if loan["borrower"] != actor or int(loan["remaining"]) <= 0 or int(loan["due_day"]) > day:
				continue
			var free := maxi(0, _world.ledger_state.available_balance(loan["borrower_account"]) - _npc_cash_floor(policy, loan["denomination"]))
			var amount := mini(int(loan["remaining"]), free)
			if amount > 0:
				_npc_submit(actor, "repay_loan", {"loan_id": loan["id"], "amount": amount}, loan["id"], {"purpose": "DUE_DEBT", "denomination": loan["denomination"], "cash_floor": _npc_cash_floor(policy, loan["denomination"]), "due_day": loan["due_day"]})

func _procurement_cash_position(firm: String, currency: String) -> Dictionary:
	return ProcurementCash.position(self, firm, currency)

func _procurement_cash_limit(firm: String, currency: String, unit_cost: int, wanted: int) -> int:
	if unit_cost <= 0: return wanted
	return mini(wanted, int(_procurement_cash_position(firm, currency)["spendable"]) / unit_cost)

func _fund_procurement(actor: String, offer: Dictionary, requested: int) -> int:
	if _spec["firms"].has(actor):
		# With no existing finance policy, executable cash quantity must precede
		# budget/authority checks. Never ask an appropriation to fund gross stock.
		if _finance_policy(actor).is_empty():
			requested = _procurement_cash_limit(actor, offer["denomination"], int(offer["price"]) + int(offer["freight_per_unit"]), requested)
		if requested <= 0: return 0
		var components := _budget_plan(actor, offer["denomination"], offer["good"], offer["route_legs"], requested, true, int(offer["price"]))
		if not _budget_ready(components): return 0
		var cost := int(FormalLedgerState.ratio(int(offer["price"])+int(offer["freight_per_unit"]), requested, 1).get("quotient", -1))
		if not _procurement_permission(actor, actor, {}, true, components, offer["seller"], _place(offer.get("buyer_site", "")), "goods:"+str(offer["good"]), cost)["ok"]: return 0
	var policy := _finance_policy(actor)
	if policy.is_empty():
		return requested
	var quantity := mini(requested, int(offer["transport_quantity"]))
	if quantity <= 0:
		return requested
	var currency := str(offer["denomination"])
	var unit_cost := int(offer["price"]) + int(offer["freight_per_unit"])
	var target_account := _account(actor, currency)
	if target_account.is_empty():
		return requested
	var context := {"purpose": "PROCUREMENT", "seller": offer["seller"], "seller_site": offer["seller_site"], "buyer_site": offer["buyer_site"], "need_category": offer.get("need_category", ""), "good": offer["good"], "path_id": offer["route_id"], "quantity": quantity, "denomination": currency}
	var candidate := str(offer["seller"]) + "|" + str(offer["good"]) + "|" + str(offer["route_id"]) + "|" + str(offer.get("buyer_site", "")) + "|" + str(offer.get("seller_site", "")) + "|" + str(offer.get("need_category", ""))
	if policy["allow_exchange"] and _world.ledger_state.available_balance(target_account) < quantity * unit_cost:
		_npc_exchange_procurement(actor, offer, quantity, unit_cost, policy, candidate, context)
	if _world.ledger_state.available_balance(target_account) < quantity * unit_cost:
		_npc_borrow_procurement(actor, offer, quantity, unit_cost, policy, candidate, context)
	return quantity

func _npc_exchange_procurement(actor: String, offer: Dictionary, quantity: int, unit_cost: int, policy: Dictionary, candidate: String, context: Dictionary) -> void:
	var currency := str(offer["denomination"])
	var held := maxi(0, _world.ledger_state.available_balance(_account(actor, currency)))
	var quotes: Array = _exchange.known_offers(actor, _world.game_clock.total_minutes(), false)
	quotes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for quote: Dictionary in quotes:
		if quote["target_currency"] != currency or not policy["fx_limits"].has(quote["source_currency"]):
			continue
		var source := str(quote["source_currency"])
		var daily := maxi(0, int(policy["fx_limits"][source]) - _npc_financed_today(actor, source, true))
		var free := maxi(0, _world.ledger_state.available_balance(_account(actor, source)) - _npc_cash_floor(policy, source))
		var budget := mini(daily, free)
		var lo: int = mini(quantity, held / unit_cost)
		var hi: int = quantity
		while lo < hi:
			var mid: int = lo + (hi - lo + 1) / 2
			var required := _exchange.required_source(actor, quote["id"], maxi(0, mid * unit_cost - held), _world.game_clock.total_minutes())
			if required["accepted"] and required["executable"] and int(required["source_cost"]) <= budget:
				lo = mid
			else:
				hi = mid - 1
		var shortfall := maxi(0, lo * unit_cost - held)
		if shortfall == 0:
			continue
		var required := _exchange.required_source(actor, quote["id"], shortfall, _world.game_clock.total_minutes())
		if not required["accepted"] or not required["executable"] or int(required["source_cost"]) > budget:
			continue
		var natural := FormalLedgerState.ratio(shortfall, int(quote["rate_denominator"]), int(quote["rate_numerator"]))
		if natural.is_empty() or int(required["source_amount"]) != int(natural["quotient"]) + (1 if int(natural["remainder"]) > 0 else 0):
			continue
		var decision := context.duplicate(true)
		decision.merge({"funded_quantity": lo, "target_shortfall": shortfall, "source_currency": source, "source_cash_floor": _npc_cash_floor(policy, source)})
		_npc_submit(actor, "exchange_currency", {"quote_id": quote["id"], "source_amount": required["source_amount"], "min_target": shortfall}, candidate + "|" + str(quote["id"]), decision)
		# One finite quote per procurement decision. If goods later fail, the
		# independently acquired target currency remains in the same Ledger account.
		return

func _npc_borrow_procurement(actor: String, offer: Dictionary, quantity: int, unit_cost: int, policy: Dictionary, candidate: String, context: Dictionary) -> void:
	var currency := str(offer["denomination"])
	_borrow_for_shortfall(actor,currency,maxi(0,quantity*unit_cost-_world.ledger_state.available_balance(_account(actor,currency))),policy,candidate,context,unit_cost)

func _borrow_for_shortfall(actor: String, currency: String, shortfall: int, policy: Dictionary, candidate: String, context: Dictionary, unit_cost: int=1) -> void:
	if not policy["borrow_limits"].has(currency):
		return
	var view := _credit.visible(actor, _known_credit_lenders(actor), _world.game_clock.total_minutes(), true)
	# Autonomous borrowing permits one open loan. No new debt finances repayment,
	# nor replaces cash used for a repayment earlier in this same day.
	for loan: Dictionary in view["loans"]:
		if loan["borrower"] == actor and int(loan["remaining"]) > 0:
			return
	if _repayment_days.get(actor) == day: return
	var limits := policy["borrow_limits"][currency] as Dictionary
	var daily := maxi(0, int(limits["daily_principal"]) - _npc_financed_today(actor, currency, false))
	var held := maxi(0,_world.ledger_state.available_balance(_account(actor,currency)))
	var quotes := view["offers"] as Array
	quotes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(str(a["id"]).trim_prefix("credit_offer:")) < int(str(b["id"]).trim_prefix("credit_offer:")))
	for quote: Dictionary in quotes:
		if quote["lender"] == actor or quote["denomination"] != currency or int(quote["interest"]) > int(limits["max_interest"]) or (quote["requires_job"] and not _contracts.has(actor)):
			continue
		var cap := mini(daily, mini(int(quote["available_quantity"]), maxi(0, int(limits["max_debt"]) - int(quote["interest"]))))
		var amount := mini(shortfall,maxi(0,((held+cap)/unit_cost)*unit_cost-held))
		if amount <= 0:
			continue
		var decision := context.duplicate(true)
		decision.merge({"cash_shortfall": amount, "fixed_interest": quote["interest"]})
		_npc_submit(actor, "accept_credit", {"offer_id": quote["id"], "amount": amount}, candidate + "|" + str(quote["id"]), decision)
		return


func _operations_policy(site: String) -> Dictionary:
	site = _inventory_key(site)
	var owner := _owner(site)
	var fallback: Dictionary = {}
	for row: Dictionary in config.get("firm_operations", []):
		if row["firm"] != owner:
			continue
		if row.get("site_id", "") == site:
			return row
		if not row.has("site_id"):
			fallback = row
	if not fallback.is_empty():
		return fallback
	return {"firm": owner, "planning_horizon": mini(30, int(config["stock_horizon"])), "buffer_days": 2, "demand_window": 3, "manage_jobs": _spec["firms"][owner].has("manager") or not _configured_legacy_recipe(owner)}


func _update_job_postings() -> void:
	var hired_by_site: Dictionary = {}
	var jobs_by_site: Dictionary = {}
	for contract: Dictionary in _all_contract_rows(_contracts):
		var job := _spec["jobs"][contract["job"]] as Dictionary
		if not hired_by_site.has(job["site_id"]): hired_by_site[job["site_id"]] = {}
		hired_by_site[job["site_id"]][job["id"]] = int(hired_by_site[job["site_id"]].get(job["id"], 0)) + int(contract["workers"])
	for id: String in _sorted_ids(_spec["jobs"]):
		var site := str(_spec["jobs"][id]["site_id"])
		if not jobs_by_site.has(site): jobs_by_site[site] = []
		jobs_by_site[site].append(id)
	for firm: String in _site_ids():
		var active := _site_producing(firm)
		var has_activity: bool = _spec["sites"][firm]["activities"].is_empty()
		for activity: Dictionary in _spec["sites"][firm]["activities"]:
			has_activity = has_activity or _site_state[firm]["activities"][activity["id"]]["enabled"]
		active = active and has_activity
		var managed: bool = _operations_policy(firm)["manage_jobs"]
		# Fixed clerical/shop jobs at a non-production site remain real vacancies.
		# A production toggle cannot close them or mutate the fixed job template.
		if not managed and _spec["sites"][firm]["activities"].is_empty():active=_site_operating(firm)
		active = active or (_site_operating(firm) and (_capital.labor_needed(firm) > 0 or _shared.labor_needed(firm) > 0 or _service_market.labor_needed(firm)>0 or _retail.labor_needed(firm)>0) and not _firm_winding_down(_owner(firm)))
		var wanted := int(_allocate_production(firm, FormalLedgerState.MAX_AMOUNT)["labor_used"])+_capital.labor_needed(firm)+_shared.labor_needed(firm)+_service_market.labor_needed(firm)+_retail.labor_needed(firm)
		var occupied := hired_by_site.get(firm, {}) as Dictionary
		for job_id: String in occupied:
			wanted = maxi(0, wanted - int(occupied[job_id]) * int(_spec["jobs"][job_id]["hours"]))
		for id: String in jobs_by_site.get(firm, []):
			if _labor_market.controls(id): continue
			var job := _spec["jobs"][id] as Dictionary
			var hired := int(occupied.get(id, 0))
			var new_slots: int = mini(maxi(0, int(job["positions"]) - hired), (wanted + int(job["hours"]) - 1) / int(job["hours"]))
			wanted = maxi(0, wanted - new_slots * int(job["hours"]))
			var posting := _job_postings[id] as Dictionary
			var total := hired + new_slots if managed and active else int(job["positions"]) if active else hired
			if int(posting["positions"]) == total:
				continue
			posting["positions"] = total
			posting["version"] = int(posting["version"]) + 1
			posting["published_day"] = day
			for info: Dictionary in _spec["information"]:
				if info["kind"] != "job" or info["candidate"] != id:
					continue
				var notice_id := "posting:" + str(info["actor"]) + ":" + id
				for index: int in range(_messages.size() - 1, -1, -1):
					if _messages[index]["id"] == notice_id:
						_messages.remove_at(index)
				_messages.append({"id": notice_id, "actor": info["actor"], "kind": "job_posting", "candidate": id, "observed_day": day, "delivery_day": maxi(day + int(job.get("notice_delay", 1)), int(info["delivery_day"])), "version": posting["version"], "positions": total})

func _known_job(actor: String, id: String) -> Dictionary:
	if _labor_market.controls(id): return _labor_market.known_job(actor,id)
	var job := _job(id)
	if _operations_policy(job["site_id"])["manage_jobs"] or int(_job_postings[id]["version"]) > 0:
		var notice := _receipts.get("posting:" + actor + ":" + id, {}) as Dictionary
		job["positions"] = notice.get("positions", 0)
		job["posting_version"] = notice.get("version", 0)
		job["observed_day"] = notice.get("observed_day", 0)
	return job

func _price_policy(site: String, good: String) -> Dictionary:
	site = _inventory_key(site)
	for row: Dictionary in config.get("price_policies", []):
		if row["firm"] == _owner(site) and row.get("site_id", _primary_site(row["firm"])) == site and row["good"] == good:
			return row
	return {}


func _purchase_limit(actor: String, good: String, currency: String, offered: int) -> int:
	for row: Dictionary in config.get("purchase_limits", []):
		if row["actor"] == actor and row["good"] == good and row["denomination"] == currency:
			return int(row["max_price"])
	return offered

func _initialize_operations() -> void:
	_quote_state = _initial_quote_state(day)
	_job_postings = _initial_job_postings()
	_search_state.clear()
	_firm_state = _initial_firm_state()
	_site_state = _initial_site_state()
	_publish_site_reports()

func _initial_quote_state(at_day: int) -> Dictionary:
	var result: Dictionary = {}
	for site: String in _site_ids():
		for good: String in _spec["sites"][site]["prices"]:
			var row := _price_policy(site, good)
			if row.get("mode", "N2") == "N3":
				result[site + "|" + good] = {"price": _spec["sites"][site]["prices"][good], "next_price": -1, "effective_day": -1, "window_start": at_day + 1, "last_reason": "INITIAL", "updated_day": 0}
	return result


func _initial_job_postings() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _spec["jobs"]:
		var job := _spec["jobs"][id] as Dictionary
		result[id] = _labor_market.posting(id) if _labor_market.controls(id) else {"positions": 0 if _operations_policy(job["site_id"])["manage_jobs"] else job["positions"], "version": 0, "published_day": 0}
	return result

func _received_pressure(firm: String, good: String) -> int:
	var total: int = 0
	var window := int(_operations_policy(firm)["demand_window"])
	for row: Dictionary in _request_pressure_records(firm,good):
		if int(row["day"]) < day - window + 1 or int(row.get("need_by_day", day)) < day:
			continue
		# Legacy received aggregates expire normally; new attempts retain only
		# this buyer's latest unresolved physical request, not repeated gross flow.
		total += _request_supply_pressure(row)
	return total

func _observed_daily_orders(firm: String, good: String) -> int:
	var window := int(_operations_policy(firm)["demand_window"])
	var total: int = 0
	var dates := mini(window, day + 1)
	var observed := _order_days.get(firm + "|" + good, {}) as Dictionary
	for date: int in range(maxi(0, day - window + 1), day + 1): total += int(observed.get(date, 0))
	return (total + dates - 1) / dates

func _site_has_production_decision(site: String) -> bool:
	if not config["production_enabled"] or not _site_producing(site,_production_minute()): return false
	for activity: Dictionary in _spec["sites"][site]["activities"]:
		if _site_state[site]["activities"][activity["id"]]["enabled"] and _capital.capacity(site, _production_minute(), activity["id"]) >= int(activity["capacity_units"]): return true
	return false

func _resting_plan(site: String) -> Dictionary:
	var activities: Dictionary = {}
	var horizon := int(_operations_policy(site)["planning_horizon"])
	for id: String in _spec["sites"][site]["activity_order"]:
		var schedule: Array[Dictionary] = []
		for offset: int in horizon: schedule.append({"day": day+offset, "quantity": 0})
		activities[id] = {"desired": 0, "schedule": schedule, "actual": 0}
	return {"day": day, "activities": activities, "labor_hours": 0}

func _plan_firms() -> void:
	for firm: String in _site_ids():
		if not _site_has_production_decision(firm):
			_plans[firm] = _resting_plan(firm)
			_decision_counts["resting_sites"] = int(_decision_counts.get("resting_sites", 0))+1
			continue
		_decision_counts["production_sites"] = int(_decision_counts.get("production_sites", 0))+1
		var row := _spec["sites"][firm] as Dictionary
		var horizon := int(_operations_policy(firm)["planning_horizon"])
		var demand := _zero_goods()
		var urgent := _zero_goods()
		var input_demands := _zero_goods()
		var input_cover := _zero_goods()
		for good: String in _goods:
			urgent[good] = _committed(firm, good) + _received_pressure(firm, good) + _internal_request_pressure(firm, good) + _capital.goods_needed(firm, good)+_service_market.materials_needed(firm,good)
			var gross := int(row["targets"][good]) + int(urgent[good]) + _observed_daily_orders(firm, good) * horizon
			demand[good] = maxi(0, gross - _exposure(firm, good))
			input_cover[good] = maxi(0, _exposure(firm, good) - gross)
		var candidates: Dictionary = {}
		var order := _planning_activity_order(firm, urgent)
		# Downstream intentions propagate only inside this owner's recipes. One
		# batch's joint outputs cover demands once, including competing recipes.
		for id: String in order:
			var activity := _activity(firm, id)
			var wanted: int = 0
			var priority: int = 0
			for good: String in activity["outputs"]:
				var yield_amount := int(activity["outputs"][good])
				wanted = maxi(wanted, (int(demand[good]) + yield_amount - 1) / yield_amount)
				priority += int(urgent[good])
			var runnable: bool = config["production_enabled"] and _site_producing(firm,_production_minute()) and _site_state[firm]["activities"][id]["enabled"] and _capital.capacity(firm, _production_minute(), id) >= int(activity["capacity_units"])
			var desired := wanted if runnable else 0
			if desired > 0 and bool(_production_new_input_contribution(firm, id)["decline_optional_batch"]): desired = 0
			candidates[id] = {"desired": desired, "schedule": [], "actual": 0, "priority": priority}
			for good: String in activity["outputs"]:
				demand[good] = maxi(0, int(demand[good]) - desired * int(activity["outputs"][good]))
			for good: String in _goods:
				var bounded_batches := mini(desired, _capital.capacity(firm, _production_minute(), id) * horizon / int(activity["capacity_units"]))
				var needed := bounded_batches * int(activity["materials"][good])
				if needed > 0:
					# Existing own stock and accepted inbound orders are counted once
					# per good, not once per downstream production line.
					var prior := int(input_demands[good])
					input_demands[good] = prior + needed
					demand[good] = int(demand[good]) + maxi(0, prior + needed - int(input_cover[good])) - maxi(0, prior - int(input_cover[good]))
					urgent[good] = int(urgent[good]) + priority
		var ranked: Array[String] = []
		ranked.assign(_production_order(firm))
		var stable_order:=ranked.duplicate()
		ranked.sort_custom(func(a: String, b: String) -> bool: return int(candidates[a]["priority"]) > int(candidates[b]["priority"]) if candidates[a]["priority"] != candidates[b]["priority"] else stable_order.find(a) < stable_order.find(b))
		var remaining: Dictionary = {}
		for id: String in candidates:
			remaining[id] = candidates[id]["desired"]
		for offset: int in horizon:
			var pools := _capital.pools(firm, _production_minute())
			for id: String in ranked:
				var cost := int(_activity(firm, id)["capacity_units"])
				var wanted: int = (int(remaining[id]) + horizon - offset - 1) / (horizon - offset)
				var quantity := mini(wanted, Capital.pool_available(pools, id) / cost)
				candidates[id]["schedule"].append({"day": day + offset, "quantity": quantity})
				Capital.use_pool(pools, id, quantity * cost)
				remaining[id] = int(remaining[id]) - quantity
		for entry: Dictionary in candidates.values():
			entry.erase("priority")
		_plans[firm] = {"day": day, "activities": candidates, "labor_hours": 0}

func _allocate_production(firm: String, available_hours: int, at_minute: int = -1, investment: Dictionary = {}) -> Dictionary:
	var stock := (_stocks.get(firm, {}) as Dictionary).duplicate(true)
	var allocations: Dictionary = {}
	var hours := available_hours
	var pools := _capital.pools(firm, _production_minute())
	if int(investment.get("capacity",0))>0: pools.push_front({"id":"unadopted_estimate","capacity":investment["capacity"],"activities":investment["activities"].duplicate()})
	var initial_capacity := Capital.pool_available(pools)
	var used_remaining := _zero_goods()
	var produced_remaining := _zero_goods()
	for good: String in _goods:
		used_remaining[good] = FormalLedgerState.MAX_AMOUNT - int(_physical_totals[firm]["used"][good])
		produced_remaining[good] = FormalLedgerState.MAX_AMOUNT - int(_physical_totals[firm]["produced"][good])
	var plans := _plans.get(firm, {}).get("activities", {}) as Dictionary
	for id: String in _production_order(firm):
		var activity := _activity(firm, id)
		var quantity: int = 0
		if plans.has(id) and config["production_enabled"] and _site_producing(firm,at_minute) and _site_state[firm]["activities"][id]["enabled"]:
			var wanted: int=plans[id]["schedule"][0]["quantity"]
			if not investment.is_empty(): wanted=(int(plans[id]["desired"])+int(_operations_policy(firm)["planning_horizon"])-1)/int(_operations_policy(firm)["planning_horizon"])
			quantity = mini(wanted, mini(hours / int(activity["hours"]), Capital.pool_available(pools, id) / int(activity["capacity_units"])))
			quantity = _material_batches(firm, activity, stock, quantity)
			# Stock and cumulative business quantities stay in ledger integer bounds.
			quantity = mini(quantity, FormalLedgerState.MAX_AMOUNT - int(_site_state[firm]["activities"][id]["batches"]))
			for good: String in _goods:
				var used := int(activity["materials"][good])
				var produced := int(activity["outputs"].get(good, 0))
				if used > 0:
					quantity = mini(quantity, int(used_remaining[good]) / used)
				if produced > 0:
					quantity = mini(quantity, mini((FormalLedgerState.MAX_AMOUNT - int(stock[good])) / produced, int(produced_remaining[good]) / produced))
		allocations[id] = quantity
		hours -= quantity * int(activity["hours"])
		Capital.use_pool(pools, id, quantity * int(activity["capacity_units"]))
		for good: String in _goods:
			var used := quantity * int(activity["materials"][good])
			var produced := quantity * int(activity["outputs"].get(good, 0))
			stock[good] = int(stock[good]) - used + produced
			used_remaining[good] = int(used_remaining[good]) - used
			produced_remaining[good] = int(produced_remaining[good]) - produced
	return {"batches": allocations, "stock": stock, "labor_used": available_hours - hours, "capacity_used": initial_capacity - Capital.pool_available(pools)}

func _production_order(site: String) -> Array[String]:
	var original: Array[String]=[]
	original.assign(_spec["sites"][site]["activity_order"])
	var ranked:=_costs.rank(site,original)
	if ranked==original: return original
	for id: String in original:
		for other: String in original:
			if id==other: continue
			for good: String in _activity(site,other)["outputs"]:
				if int(_activity(site,id)["materials"].get(good,0))>0: return original
	var tie_order:=ranked.duplicate()
	# Existing accepted obligations retain priority over optional margin ranking.
	var urgent: Dictionary={}
	for id: String in original:
		urgent[id]=0
		for good: String in _activity(site,id)["outputs"]:
			urgent[id]+=int(_pending_by_key.get(site+"|"+good,0))
	ranked.sort_custom(func(a: String,b: String) -> bool: return urgent[a]>urgent[b] if urgent[a]!=urgent[b] else tie_order.find(a)<tie_order.find(b))
	return ranked


func _input_good(firm: String, good: String) -> bool:
	if _service_market.materials_needed(firm,good)>0: return true
	for contract: Dictionary in _supply.records.values():
		if contract["supplier_site"]==firm and contract["good"]==good and int(contract["ended_minute"])<0 and int(contract["quantity"])>int(contract["allocated"]): return true
	if _spec["sites"][firm]["activities"].is_empty():
		return true
	for activity: Dictionary in _spec["sites"][firm]["activities"]:
		if _site_state[firm]["activities"][activity["id"]]["enabled"] and int(activity["materials"][good]) > 0:
			return true
	return false


func _known_lead(firm: String, good: String) -> int:
	var shortest: int = -1
	for candidate: String in _firm_knowledge[firm]:
		var parts := _candidate(candidate)
		if parts["good"] != good:
			continue
		for path: Dictionary in _paths_for(_owner(firm), _place(parts["site"]), _place(firm), day):
			var lead := _travel_days(_locked_legs(path, _sale_currency(parts["seller"])))
			shortest = lead if shortest < 0 else mini(shortest, lead)
	return shortest

## Read-only finite projection. Legacy quantity remains the total-stock-position
## field. Adoption uses regular_quantity and the candidate-specific time benefit.
func _npc_timing_adoption(firm: String) -> bool:
	var manager: String=firm_manager_at(firm,_world.game_clock.total_minutes())
	if manager==firm or _assets.corporate.can_plan(firm):return true
	# An appointed automatic manager is still an NPC. The former equality-only
	# check sent it back to total-quantity subtraction despite dated shortages.
	if not _actors.has(manager) or _actors[manager].get("control")!="automatic":return false
	return not _declared_named(manager) or personal_authorized(manager)

func _input_need(firm: String, good: String) -> Dictionary:
	var row := _spec["sites"][firm] as Dictionary
	var policy := _operations_policy(firm)
	var plan := _plans.get(firm, {}) as Dictionary
	var plans := plan.get("activities", {}) as Dictionary
	var requirements: Array[Dictionary] = []
	var future: Array[Dictionary] = []
	var gross := 0
	var future_gross := 0
	var rate := 0
	var missed := 0
	var production_closed := phase in ["PROCUREMENT", "DISPATCH", "CONSUMPTION", "READY", "EQUITY_CLEARING"]
	for offset: int in int(policy["planning_horizon"]):
		var quantity := 0
		var full := 0
		var boundary := int(plan.get("day", day)) + offset
		for id: String in plans:
			if not _site_producing(firm) or not _site_state[firm]["activities"][id]["enabled"]: continue
			var coefficient := int(_activity(firm, id)["materials"][good])
			var entry := plans[id]["schedule"][offset] as Dictionary
			boundary = int(entry["day"])
			var batches := int(entry["quantity"])
			full += batches * coefficient
			if offset == 0: batches = maxi(0, batches - int(plans[id]["actual"]))
			quantity += batches * coefficient
		var closed := boundary < day or (boundary == day and production_closed)
		var requirement := {"day": boundary, "boundary_minute": boundary * 1440, "stage": "PRODUCTION_AFTER_ARRIVALS", "quantity": quantity, "purpose": "PLANNED_PRODUCTION", "recoverable": not closed}
		requirements.append(requirement)
		gross += quantity
		rate = maxi(rate, full)
		if closed: missed += quantity
		elif quantity > 0:
			future.append(requirement.duplicate())
			future_gross += quantity
	# Accepted unallocated supplier obligations are not optional resale buffers.
	# Already allocated child orders reserve physical lots, excluded in free_stock.
	var obligations := 0
	var unrecoverable_contracts: Array = []
	for contract: Dictionary in _supply.records.values():
		if contract["supplier_site"] != firm or contract["good"] != good or int(contract["ended_minute"]) >= 0: continue
		var unallocated := maxi(0, int(contract["quantity"]) - int(contract["allocated"]))
		if unallocated <= 0: continue
		var route := _route_for(contract["buyer"], contract["supplier"], contract["route_id"], contract["buyer_site"], contract["supplier_site"])
		var travel := _travel_days(_locked_legs(route, _sale_currency(contract["supplier"]))) if not route.is_empty() else 0
		# Supplier submission is an ordinary free-action: reserve one dispatch
		# boundary after physical receipt. Never roll an expired promise forward.
		var due := int(contract["deadline"]) / 1440 - travel - 1
		if route.is_empty() or due <= day:
			unrecoverable_contracts.append({"contract_id": contract["id"], "quantity": unallocated, "source_need_day": due if not route.is_empty() else null, "deadline": contract["deadline"], "reason": "MISSED_SOURCE_BOUNDARY_OR_UNKNOWN_ROUTE"})
			continue
		obligations += unallocated
		future.append({"day": due, "boundary_minute": int(contract["deadline"]) - (travel + 1) * 1440, "stage": "SUPPLIER_STOCK_BEFORE_SUBMISSION", "quantity": unallocated, "purpose": "ACCEPTED_SUPPLY_OBLIGATION", "contract_id": contract["id"], "contract_deadline": contract["deadline"], "recoverable": true})
	var lead := _known_lead(firm, good)
	var coverage_days := mini(30, maxi(0, lead) + int(policy["buffer_days"]))
	var inventory_adaptation: Dictionary=OperatingInventory.observe(self,firm,good)
	var buffer_target: int=int(inventory_adaptation.get("optional_buffer_target",row["targets"][good]))
	var base := buffer_target + (_internal_request_pressure(firm, good) if row["activities"].is_empty() else 0)
	var target := maxi(base, maxi(gross, rate * coverage_days))
	var regular_target := maxi(base, maxi(future_gross + obligations, rate * coverage_days))
	if not _input_good(firm, good):
		target = 0
		regular_target = obligations
	var service := _service_market.materials_needed(firm, good)
	target = maxi(target, service)
	regular_target = maxi(regular_target, service)
	if _retail.has_site(firm):
		target = _retail.target(firm, good)
		regular_target = target
	var free_stock := maxi(0, int(_stocks[firm][good]) - _committed(firm, good))
	var incoming := maxi(0, _exposure(firm, good) - int(_stocks[firm][good]))
	var observation := _input_incoming_observation(firm, good, day + int(policy["planning_horizon"]))
	var projection := _project_input_timing(future, free_stock, observation["batches"])
	var need_by := int(projection["first_uncovered_day"]) if projection["first_uncovered_day"] != null else day + int(policy["planning_horizon"])
	# Reclassify this same detached batch list; never rebuild or mutate stock.
	observation = _classify_input_batches(observation, need_by)
	var parent_incoming := int(observation["unallocated_contract"])
	var regular := maxi(0, regular_target - free_stock - incoming - parent_incoming)
	var dated: Dictionary = {}
	var confirmed: Dictionary = {}
	for cargo_id: String in _shipments_by_destination_good.get(firm + "|" + good, {}):
		var cargo := _shipments[cargo_id] as Dictionary
		var order := _orders[cargo["order_id"]] as Dictionary
		if cargo["stage"] == "TRANSIT" and int(cargo["leg_index"]) + 1 == order["route_legs"].size():
			var date := int(cargo["leg_arrival_day"])
			confirmed[date] = int(confirmed.get(date, 0)) + int(cargo["quantity"])
	for batch: Dictionary in observation["batches"]:
		if batch["earliest_arrival_day"] != null:
			var arrival := int(batch["earliest_arrival_day"])
			dated[arrival] = int(dated.get(arrival, 0)) + int(batch["quantity"])
	projection.merge({"missed_production_quantity": missed, "missed_is_not_backlog": true, "retained_unrecoverable_contracts": unrecoverable_contracts, "service_materials_undated": service, "optional_buffer_target": base, "regular_target": regular_target, "unknown_responsibility_hold": observation["unknown_arrival"], "adoption_basis": "FINITE_USEFUL_FUTURE_BOUNDARIES_NO_ETA_GUARANTEE"})
	return {"inventory_adaptation":inventory_adaptation,"good": good, "quantity": maxi(0, target - free_stock - incoming), "npc_timing_adoption": _npc_timing_adoption(_owner(firm)), "regular_quantity": regular, "target": target, "on_hand": free_stock, "incoming": incoming, "accepted_responsibility": incoming + parent_incoming, "known_lead_days": lead if lead >= 0 else null, "need_by_day": need_by, "conditional_shortfall_day": projection["first_uncovered_day"], "requirements": requirements, "confirmed_arrivals": confirmed, "projected_arrivals": dated, "coverage_horizon_days": coverage_days, "incoming_observation": observation, "timing_projection": projection, "coverage_basis": "LEGACY_TOTAL_QUANTITY_PLUS_FINITE_TIME_PROJECTION"}


func _project_input_timing(requirements: Array, stock: int, batches: Array) -> Dictionary:
	var needs := requirements.duplicate(true)
	needs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["boundary_minute"]) < int(b["boundary_minute"]) if a["boundary_minute"] != b["boundary_minute"] else str(a["purpose"]) < str(b["purpose"]))
	var arrivals := batches.duplicate(true)
	arrivals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("observed_arrival_day", 2147483647)) < int(b.get("observed_arrival_day", 2147483647)) if a.get("observed_arrival_day") != null and b.get("observed_arrival_day") != null else a.get("observed_arrival_day") != null)
	var balance := stock
	var used: Dictionary = {}
	var uncovered := 0
	var first: Variant = null
	for need: Dictionary in needs:
		for index: int in arrivals.size():
			var batch := arrivals[index] as Dictionary
			if used.has(index) or batch.get("observed_arrival_day") == null: continue
			if int(batch["observed_arrival_day"]) * 1440 <= int(need["boundary_minute"]):
				balance += int(batch["quantity"])
				used[index] = true
		var covered := mini(balance, int(need["quantity"]))
		balance -= covered
		need["possible_covered"] = covered
		need["uncovered"] = int(need["quantity"]) - covered
		need["eta_guaranteed"] = false
		uncovered += int(need["uncovered"])
		if int(need["uncovered"]) > 0 and first == null: first = need["day"]
	return {"requirements": needs, "uncovered_future_quantity": uncovered, "first_uncovered_day": first, "physical_available": stock, "projected_unused": balance, "projection_only": true}


## A prospective candidate can cover only still-recoverable boundaries. Unknown
## existing responsibility is retained as a conservative risk hold, never erased.
func _input_candidate_need(need: Dictionary, arrival: Variant, capacity: int, batch_size: int = 1000000) -> Dictionary:
	# Human-managed firms retain their existing target-based autonomy. A new
	# projection or accepted supplier contract alone does not authorize spending.
	var timing_allowed: bool = need.get("npc_timing_adoption", true)
	var regular := int(need.get("regular_quantity", need.get("quantity", 0))) if timing_allowed else int(need.get("quantity", 0))
	var result := {"quantity": mini(capacity, regular), "regular_quantity": mini(capacity, regular), "timing_quantity": 0, "need_by_day": need["need_by_day"], "arrival_day": arrival, "reason": "REGULAR_STOCK_POSITION"}
	if not timing_allowed or not need.has("timing_projection") or arrival == null or capacity <= 0: return result
	var projection := need["timing_projection"] as Dictionary
	var batches: Array = need["incoming_observation"]["batches"].duplicate(true)
	if batch_size <= 0: return result
	var remaining := capacity
	for offset: int in mini(31, projection["requirements"].size() + 1):
		if remaining <= 0: break
		var quantity := mini(remaining, batch_size)
		batches.append({"quantity": quantity, "observed_arrival_day": int(arrival) + offset})
		remaining -= quantity
	var improved := _project_input_timing(projection["requirements"], int(need["on_hand"]), batches)
	var benefit := maxi(0, int(projection["uncovered_future_quantity"]) - int(improved["uncovered_future_quantity"]) - int(projection["unknown_responsibility_hold"]))
	for index: int in projection["requirements"].size():
		if int(projection["requirements"][index]["uncovered"]) > int(improved["requirements"][index]["uncovered"]):
			result["need_by_day"] = projection["requirements"][index]["day"]
			break
	result["timing_quantity"] = mini(capacity, benefit)
	result["quantity"] = mini(capacity, maxi(regular, benefit))
	if benefit > 0: result["reason"] = "USEFUL_FUTURE_BOUNDARY_WITH_FINITE_EXTRA_STOCK_RISK"
	elif regular == 0: result["reason"] = "WAIT_EXISTING_RESPONSIBILITY_OR_NO_USEFUL_ARRIVAL"
	return result


## Buy urgent dated uses before a cheaper feasible source becomes useful. This
## only limits the current order; an alternative is never booked as an arrival.
## Every accepted order changes the original projection before the next choice.
func _dated_input_applicable(site: String, good: String, need: Dictionary) -> bool:
	return _dated_input_procurement_enabled and need.get("npc_timing_adoption",false) and int(need["timing_projection"]["uncovered_future_quantity"])>0 and _service_market.materials_needed(site,good)==0 and _internal_request_pressure(site,good)==0 and _capital.goods_needed(site,good)==0


func _input_dated_choice(site: String, good: String, need: Dictionary, offer: Dictionary, candidates: Array) -> Dictionary:
	var choice: Dictionary=_input_candidate_need(need,offer["observed_arrival_day"],int(offer["transport_quantity"]),_input_offer_batch_size(offer))
	if not _dated_input_applicable(site,good,need):return choice # Ordinary buffers and undated uses retain their existing policy.
	var projection: Dictionary=need["timing_projection"]
	var capacity: int=mini(int(choice["quantity"]),int(choice["timing_quantity"]))
	if capacity<=0:return choice # Late stock may still serve later plans; do not abolish the existing reserve policy.
	var batches: Array=need["incoming_observation"]["batches"].duplicate(true)
	var remaining: int=capacity
	var batch: int=_input_offer_batch_size(offer)
	for offset: int in mini(31,projection["requirements"].size()+1):
		if remaining<=0 or batch<=0:break
		var amount: int=mini(remaining,batch)
		batches.append({"quantity":amount,"observed_arrival_day":int(offer["observed_arrival_day"])+offset})
		remaining-=amount
	var improved: Dictionary=_project_input_timing(projection["requirements"],int(need["on_hand"]),batches)
	var admissions: Array[Dictionary]=_managed_offer_rows(_owner(site),_owner(site),site,candidates,1,0,candidates.size())
	var quantity: int=0
	var deferred: Dictionary={}
	var before: Dictionary={};var after: Dictionary={};var seen: Dictionary={}
	for requirement: Dictionary in projection["requirements"]:before[requirement["boundary_minute"]]=int(before.get(requirement["boundary_minute"],0))+int(requirement["uncovered"])
	for requirement: Dictionary in improved["requirements"]:after[requirement["boundary_minute"]]=int(after.get(requirement["boundary_minute"],0))+int(requirement["uncovered"])
	for requirement: Dictionary in projection["requirements"]:
		var boundary: int=int(requirement["boundary_minute"])
		if seen.has(boundary):continue
		seen[boundary]=true
		var benefit: int=maxi(0,int(before[boundary])-int(after.get(boundary,0)))
		if benefit<=0:continue
		for other: Dictionary in admissions:
			if other["denomination"]!=offer["denomination"] or not other["can_order"] or other["observed_arrival_day"]==null or _input_offer_batch_size(other)<=0:continue
			if int(other["comparison"]["currently_acceptable_quantity"])<=0 or _procurement_cash_limit(_owner(site),other["denomination"],int(other["price"])+int(other["freight_per_unit"]),1)<=0:continue
			if int(other["price"])+int(other["freight_per_unit"])>=int(offer["price"])+int(offer["freight_per_unit"]):continue
			if int(other["observed_arrival_day"])*1440>int(requirement["boundary_minute"]):continue
			deferred={"from_day":requirement["day"],"purpose":requirement["purpose"],"seller_site":other["seller_site"],"route_id":other["route_id"],"landed_unit_cost":int(other["price"])+int(other["freight_per_unit"]),"observed_arrival_day":other["observed_arrival_day"],"not_an_accepted_arrival":true}
			break
		if not deferred.is_empty():break
		quantity+=benefit
	if deferred.is_empty():return choice # No executable cheaper alternative: keep the original stock/backup choice.
	choice["unsliced_quantity"]=choice["quantity"]
	choice["quantity"]=mini(capacity,quantity)
	choice["dated_limit"]=choice["quantity"]
	choice["deferred_alternative"]=deferred
	choice["reason"]="DATED_USES_BEFORE_CHEAPER_EXECUTABLE_ARRIVAL"
	return choice


func _classify_input_batches(observation: Dictionary, need_by: int) -> Dictionary:
	observation["earliest_by_need"] = 0
	observation["known_late"] = 0
	observation["unknown_arrival"] = 0
	for batch: Dictionary in observation["batches"]:
		var eta: Variant = batch["earliest_arrival_day"]
		if eta == null: observation["unknown_arrival"] += int(batch["quantity"])
		elif int(eta) > need_by: observation["known_late"] += int(batch["quantity"])
		else: observation["earliest_by_need"] += int(batch["quantity"])
	return observation


func _input_incoming_observation(site: String, good: String, need_by: int) -> Dictionary:
	var result := {"accepted_pending": 0, "in_transit": 0, "unallocated_contract": 0, "earliest_by_need": 0, "known_late": 0, "unknown_arrival": 0, "orders": [], "batches": [], "basis": "ORIGINAL_RESPONSIBILITY_ONCE_BATCH_LOWER_BOUND_NOT_GUARANTEE"}
	for id: String in _active_by_buyer.get(_owner(site), []):
		var order := _orders[id] as Dictionary
		if _destination(order) != site or order["good"] != good or order["kind"] == "PERSONAL_FREIGHT": continue
		if _actors.has(site) and (order["kind"]!="SALE" or (manages_person(site) and order["to_place_id"]!=_place(site))): continue
		var pending := int(order["pending"])
		var transit := int(order["transit"])
		if pending + transit <= 0: continue
		var delay := int(_cooperation_view(site, str(order["seller_site"]), good)["average_delay_days"])
		result["accepted_pending"] += pending
		result["in_transit"] += transit
		result["orders"].append({"order_id": id, "pending": pending, "transit": transit, "supply_contract_id": order.get("supply_contract_id", "")})
		for cargo_id: String in _shipments_by_order.get(id, {}):
			var cargo := _shipment_view(_shipments[cargo_id], order)
			var physical := int(cargo["physical_quantity"])
			var eta: Variant = cargo.get("earliest_arrival_day")
			if eta != null and cargo.has("arrival_minute"):
				# A noon arrival cannot cover the earlier midnight production.
				eta = maxi(int(eta), (int(cargo["arrival_minute"]) + 1439) / 1440)
			if cargo["stage"] in ["TRANSIT", "LOADING"]:
				var current_leg := order["route_legs"][int(cargo["leg_index"])] as Dictionary
				if _shared.bindings.get(current_leg["edge_id"], {}).has("node_resources"):
					eta = null # Arrival is not unloading completion or free stock.
			if physical > 0: result["batches"].append({"order_id": id, "shipment_id": cargo_id, "quantity": physical, "stage": cargo["stage"], "earliest_arrival_day": eta, "observed_arrival_day": int(eta) + delay if eta != null else null, "eta_guaranteed": false})
			var lost := int(cargo["quantity"]) - physical
			if lost > 0: result["batches"].append({"order_id": id, "shipment_id": cargo_id, "quantity": lost, "stage": "UNRESOLVED_PHYSICAL_LOSS", "earliest_arrival_day": null, "observed_arrival_day": null, "eta_guaranteed": false})
		if pending > 0:
			var physical_pending := mini(pending, _lots.reserved_quantity(id))
			if physical_pending < pending:
				result["batches"].append({"order_id": id, "shipment_id": "", "quantity": pending - physical_pending, "stage": "PENDING_SOURCE_LOSS_OR_REPLACEMENT_REQUIRED", "earliest_arrival_day": null, "observed_arrival_day": null, "eta_guaranteed": false})
			pending = physical_pending
			var legs := order["route_legs"] as Array
			var batch_limit := _batch_limit(legs)
			for leg: Dictionary in legs:
				if _shared.bindings.has(leg["edge_id"]) or not _cargo_edge_valid(_all_routes()[leg["edge_id"]]): batch_limit = 0
				else: batch_limit = mini(batch_limit, int(_edge(leg["edge_id"])["capacity"]))
			var dispatch := maxi(_next_dispatch_boundary(), _earliest_dispatch(order))
			var bound := (int(config["stock_horizon"]) if _actors.has(site) else int(_operations_policy(site)["planning_horizon"])) + 1
			for index: int in bound:
				if pending <= 0 or batch_limit <= 0: break
				var quantity := mini(pending, batch_limit)
				var eta := dispatch + index + _travel_days(legs)
				result["batches"].append({"order_id": id, "shipment_id": "", "pending_batch": index, "quantity": quantity, "stage": "ACCEPTED_PENDING", "earliest_arrival_day": eta, "observed_arrival_day": eta + delay, "eta_guaranteed": false})
				pending -= quantity
			if pending > 0: result["batches"].append({"order_id": id, "shipment_id": "", "quantity": pending, "stage": "PENDING_UNKNOWN_OR_BEYOND_FINITE_WINDOW", "earliest_arrival_day": null, "observed_arrival_day": null, "eta_guaranteed": false})
	for contract: Dictionary in _supply.records.values():
		if contract["buyer_site"] != site or contract["good"] != good or int(contract["ended_minute"]) >= 0: continue
		var unallocated := maxi(0, int(contract["quantity"]) - int(contract["allocated"]))
		if unallocated <= 0: continue
		result["unallocated_contract"] += unallocated
		result["batches"].append({"order_id": "", "supply_contract_id": contract["id"], "quantity": unallocated, "stage": "ACCEPTED_UNALLOCATED_CONTRACT", "contract_deadline": contract["deadline"], "earliest_arrival_day": null, "observed_arrival_day": null, "eta_guaranteed": false})
	return _classify_input_batches(result, need_by)


func _next_dispatch_boundary() -> int:
	return day if processing and phase in ["MESSAGES", "ARRIVALS", "OPERATIONS", "LABOR", "CREDIT", "CAPITAL_CONSTRUCTION", "PRODUCTION", "PROCUREMENT"] and _world.game_clock.total_minutes() % 1440 == 0 else day + 1


func _input_offer_batch_size(offer: Dictionary) -> int:
	var legs := offer.get("route_legs", []) as Array
	if legs.is_empty(): return 0
	var amount := _batch_limit(legs)
	for leg: Dictionary in legs:
		if _shared.bindings.has(leg["edge_id"]): return 0
		amount = mini(amount, int(_edge(leg["edge_id"])["capacity"]))
	# Accepted first-edge holds precede a new order. Bound its first useful batch;
	# future queues can delay it further and are never presented as guarantees.
	var first := _edge(legs[0]["edge_id"])
	var daily := mini(int(first["capacity"]), _node_capacity(_all_routes()[legs[0]["edge_id"]]["from_place_id"]))
	if daily <= 0: return 0
	var ahead := 0
	for held: Dictionary in first["holds"].values(): ahead += int(held["quantity"])
	return mini(amount, daily - ahead % daily)


func _input_offer_arrival(offer: Dictionary) -> Variant:
	var legs := offer.get("route_legs", []) as Array
	if legs.is_empty(): return null
	for leg: Dictionary in legs:
		if _shared.bindings.has(leg["edge_id"]) or not _cargo_edge_valid(_all_routes()[leg["edge_id"]]) or int(_edge(leg["edge_id"])["capacity"]) <= 0: return null
	var first := _edge(legs[0]["edge_id"])
	var daily := mini(int(first["capacity"]), _node_capacity(_all_routes()[legs[0]["edge_id"]]["from_place_id"]))
	if daily <= 0: return null
	var ahead := 0
	for held: Dictionary in first["holds"].values(): ahead += int(held["quantity"])
	return _next_dispatch_boundary() + ahead / daily + _travel_days(legs)


func _begin_market_day() -> void:
	for state: Dictionary in _quote_state.values():
		if int(state["effective_day"]) == day:
			state["price"] = state["next_price"]
			state["updated_day"] = day
			state["next_price"] = -1
			state["effective_day"] = -1

func _close_price_windows() -> void:
	for key: String in _quote_state:
		var parts := key.split("|")
		var policy := _price_policy(parts[0], parts[1])
		var state := _quote_state[key] as Dictionary
		var start := int(state["window_start"])
		if day - start + 1 < int(policy["window_days"]):
			continue
		var shipped: int = 0
		var information: int = 0
		var deliveries := _delivery_days.get(key, {}) as Dictionary
		for date: int in range(start, day + 1):
			var observed := deliveries.get(date, {}) as Dictionary
			shipped += int(observed.get("quantity", 0))
			information += int(observed.get("count", 0))
		var physical: int = 0
		var refused: int = 0
		for record: Dictionary in _request_pressure_records(parts[0],parts[1]):
			if int(record["day"]) < start or not _request_price_information(record):
				continue
			information += 1
			if int(record.get("need_by_day", day)) >= day:
				physical += _request_supply_pressure(record)
				refused += int(record.get("cash_refused", 0)) + int(record.get("price_refused", 0))
		var free := maxi(0, int(_stocks[parts[0]][parts[1]]) - _committed(parts[0], parts[1]))
		var current := int(state["price"])
		var tick := int(policy["tick"])
		# Exactly Lab N3: round its 2% adjustment down to whole price ticks.
		# A coarse tick may yield zero; no artificial minimum increase is added.
		var step: int = (current * N3_STEP_PERCENT / 100 / tick) * tick
		var direction: int = 0
		var reason: String = "HOLD"
		if information == 0:
			reason = "NO_NEW_INFORMATION"
		elif free >= 2 * maxi(shipped, 1):
			direction = -1
			reason = "IDLE_STOCK"
		elif refused > 0 and free > 0:
			direction = -1
			reason = "ECONOMIC_REFUSAL"
		elif physical > 0 and shipped > 0 and free < shipped:
			direction = 1
			reason = "OBSERVED_PHYSICAL_PRESSURE"
		state["next_price"] = clampi(current + direction * step, int(policy["minimum"]), int(policy["maximum"]))
		state["effective_day"] = day + 1
		state["window_start"] = day + 1
		state["last_reason"] = reason

func _produce() -> void:
	for firm: String in _site_ids():
		if not _plans.has(firm):
			continue
		var hours := int(_labor.get(firm, 0))
		_capital.observe_acquisition(firm,hours)
		var scheduled: bool = false
		for row: Dictionary in _plans[firm]["activities"].values():
			if int(row["schedule"][0]["quantity"]) > 0: scheduled = true
		if not scheduled:
			_plans[firm]["labor_hours"] = hours+_capital.allocated_hours(firm, day)+_shared.allocated_hours(firm, day)+_service_market.allocated_hours(firm,day)+_retail.allocated_hours(firm,day)
			continue
		var allocation := _allocate_production(firm, hours, _production_minute())
		_plans[firm]["labor_hours"] = hours+_capital.allocated_hours(firm, day)+_shared.allocated_hours(firm, day)+_service_market.allocated_hours(firm,day)+_retail.allocated_hours(firm,day)
		for id: String in _production_order(firm):
			var activity := _activity(firm, id)
			var quantity := int(allocation["batches"][id])
			var inputs: Array[Dictionary] = []
			for good: String in _goods:
				var required := quantity*int(activity["materials"][good])
				if required > 0:
					var rows := _lots.selection("SITE|"+firm, good, required)
					assert(not rows.is_empty())
					inputs.append_array(rows)
			var cost_production := _costs.production(firm, id, quantity, inputs)
			if not inputs.is_empty():
				var consumed := _lots.consume(inputs, _world.game_clock.total_minutes())
				assert(consumed)
			for good: String in activity["outputs"]:
				var output := quantity*int(activity["outputs"][good])
				if output > 0:
					var created := _lots.create("production:"+str(day)+":"+firm+":"+id+":"+good, good, _good_units()[good], output, _owner(firm), "SITE|"+firm, _place(firm), _world.game_clock.total_minutes(), "ACTUAL_RECIPE_INPUTS_AND_LABOR", inputs)
					assert(created)
					_costs.output(cost_production, "production:"+str(day)+":"+firm+":"+id+":"+good)
			_plans[firm]["activities"][id]["actual"] = quantity
			_site_state[firm]["activities"][id]["batches"] = int(_site_state[firm]["activities"][id]["batches"]) + quantity
			for good: String in _goods:
				_physical_totals[firm]["used"][good] = int(_physical_totals[firm]["used"][good]) + quantity * int(activity["materials"][good])
				_physical_totals[firm]["produced"][good] = int(_physical_totals[firm]["produced"][good]) + quantity * int(activity["outputs"].get(good, 0))
		# Only this owner writes this stock point. Intermediate products from an
		# earlier activity become inputs only after their actual execution above.
		assert(_stocks[firm] == allocation["stock"])


func _household_has_budget(actor: String) -> bool:
	for account: Dictionary in _world.ledger_state.own_accounts(actor):
		if _world.ledger_state.available_balance(account["account_id"]) > 0: return true
	# Explicit finance policies can try their existing bounded funding actions.
	return not _finance_policy(actor).is_empty()

func _household_offer_less(actor: String, a: Dictionary, b: Dictionary, category: String) -> bool:
	if _retail.prefers(actor,a)!=_retail.prefers(actor,b): return _retail.prefers(actor,a)
	var preference: Array = _cohort_profile(actor).get("goods_preference", {}).get(category, [])
	if not preference.is_empty():
		var first := preference.find(a["good"])
		var second := preference.find(b["good"])
		first = first if first >= 0 else preference.size()
		second = second if second >= 0 else preference.size()
		if first != second: return first < second
	return _offer_less_for(a, b, category)

func _auto_purchase() -> void:
	for actor: String in _actor_ids():
		if _actors[actor]["control"] != "automatic":
			continue
		if not _household_has_budget(actor):
			_decision_counts["cashless_households"] = int(_decision_counts.get("cashless_households", 0))+1
			continue
		if config.has("household_choice") and not HouseholdTiming._has_personal_flow_schedule(self,actor):
			HouseholdChoice.execute(self,actor)
			continue
		var position := _household_position(actor, true)
		var searched: bool = false
		for category: String in _actor_categories(actor):
			if position[category].get("procurement_authority") == "NATIVE_PERSONAL_ARRANGEMENT": continue
			var shortage := int(position[category]["uncovered"])
			if shortage <= 0: continue
			searched = true
			_decision_counts["household_searches"] = int(_decision_counts.get("household_searches", 0))+1
			var offers := _offers(actor)
			var sent_stock_enquiry: bool=false
			offers = offers.filter(func(offer: Dictionary) -> bool: return typeof(offer.get("price"))==TYPE_INT)
			_annotate_costs(actor, offers, int(position[category]["uncovered"]), category)
			offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _household_offer_less(actor, a, b, category))
			for offer: Dictionary in offers:
				var good := str(offer["good"])
				var unit := _service(good, category)
				if unit == 0:
					continue
				var needed := int(position[category]["uncovered"])
				# Each flow item is consumed whole; unused service cannot move to
				# tomorrow. The common projection chooses minimum useful items.
				var requested := mini(1000000, needed)
				if requested <= 0: break
				var choice := HouseholdTiming.candidate_need(self,actor,category,offer,requested)
				requested = int(choice["quantity"])
				var stock_enquiry: bool=false
				# A genuine funded purchase attempt can reveal stock shortage to
				# its known seller. It carries no guarantee of sale or supply.
				if requested<=0 and config.get("household_purchase_enquiries",false) and not sent_stock_enquiry and offer.get("reason")=="NO_UNCOMMITTED_STOCK" and _local_quotes.reason(actor,offer.seller_site,good).is_empty():
					var path: Dictionary=_route_for(actor,offer.seller,offer.route_id,"",offer.seller_site)
					var unit_cost: int=int(offer.price)+int(offer.freight_per_unit)
					if not path.is_empty() and _route_available(path)>0 and _world.ledger_state.available_balance(_account(actor,offer.denomination))>=unit_cost:
						var enquiry: Dictionary=offer.duplicate(true);enquiry.transport_quantity=1
						choice=HouseholdTiming.candidate_need(self,actor,category,enquiry,1)
						requested=int(choice.quantity)
						if requested>0:sent_stock_enquiry=true;stock_enquiry=true
				if requested <= 0: continue
				var limit := _purchase_limit(actor, good, offer["denomination"], int(offer["price"]))
				if limit >= int(offer["price"]):
					offer["need_category"] = category
					requested = _fund_procurement(actor, offer, requested)
					if requested <= 0: continue
				offer = _offer(actor, offer["seller"], good, offer["route_id"], offer["seller_site"])
				var payload := {"quote_id": offer["quote_id"], "seller": offer["seller"], "seller_site": offer["seller_site"], "good": good, "quantity": requested, "denomination": offer["denomination"], "max_price": limit, "path_id": offer["route_id"], "need_category": category, "need_by_day": clampi(int(choice["need_by_day"]),day,day+30)}
				var command: Dictionary=_auto_command(actor, "buy", payload, category + "|" + str(offer["seller_site"]) + "|" + good + "|" + str(offer["route_id"]))
				var attempted: Dictionary=_accept(actor,command,true)
				if stock_enquiry and _commands.has(command.action_id):
					_commands[command.action_id].result["decision"]={"policy":"FUNDED_KNOWN_SUPPLIER_STOCK_ENQUIRY","quantity_cap":1,"basis":"ORIGINAL_BUY_ADMISSION_NOT_A_GUARANTEED_ORDER_OR_WALLET_DISCLOSURE"}
				if attempted["accepted"]:
					position = _household_position(actor, true)


## One real source-currency account anchors this decision. Foreign prices are
## comparable only through a known, currently funded directed quote. The amount
## includes locked goods + freight, finite quote limits, fee and actual quantity.
## This is a read-only estimate: selecting an offer never executes an exchange.
		if not searched: _decision_counts["covered_households"] = int(_decision_counts.get("covered_households", 0))+1


func _comparison_cost(actor: String, offer: Dictionary, quantity: int, quotes: Array[Dictionary]) -> Dictionary:
	var anchor := str(_world.ledger_state.account(_account(actor)).get("denomination", ""))
	var currency := str(offer["denomination"])
	var result := {"basis": "INCOMPARABLE_DETERMINISTIC_FALLBACK", "currency": anchor, "cost": 0, "quantity": quantity, "quote_id": "", "executable": false}
	if typeof(offer.get("price"))!=TYPE_INT:
		result.merge({"basis":"UNKNOWN_QUOTED_PRICE","cost":null,"reason":offer.get("reason","GOODS_QUOTE_NOT_RECEIVED")},true)
		return result
	var unit := int(offer["price"]) + int(offer["freight_per_unit"])
	if quantity <= 0 or unit <= 0 or quantity > int(offer["transport_quantity"]) or quantity > FormalLedgerState.MAX_AMOUNT / unit: return result
	var amount := quantity * unit
	var policy := _finance_policy(actor)
	var account := _account(actor, currency)
	if account.is_empty() or _world.ledger_state.account(account).get("denomination") != currency: return result
	if currency == anchor:
		if _world.ledger_state.available_balance(account) - _npc_cash_floor(policy, currency) >= amount:
			result.merge({"basis": "OWN_CURRENCY_PAYABLE_COST", "cost": amount, "executable": true}, true)
		return result
	for quote: Dictionary in quotes:
		if quote["source_currency"] != anchor or quote["target_currency"] != currency or quote["dealer"] == actor: continue
		var required := _exchange.required_source(actor, quote["id"], amount, _world.game_clock.total_minutes())
		if not required["accepted"] or not required["executable"]: continue
		var cost := int(required["source_cost"])
		if _world.ledger_state.available_balance(_account(actor, anchor)) - _npc_cash_floor(policy, anchor) < cost: continue
		if not policy.is_empty():
			if not policy["allow_exchange"] or not policy["fx_limits"].has(anchor) or int(policy["fx_limits"][anchor]) - _npc_financed_today(actor, anchor, true) < cost: continue
		if not result["executable"] or cost < int(result["cost"]) or (cost == int(result["cost"]) and str(quote["id"]) < str(result["quote_id"])):
			result.merge({"basis": "KNOWN_EXECUTABLE_FX_FULL_QUANTITY_COST", "cost": cost, "quote_id": quote["id"], "executable": true}, true)
	return result

func _annotate_costs(actor: String, offers: Array[Dictionary], quantity: int, category: String = "") -> void:
	var currencies: Dictionary = {}
	for offer: Dictionary in offers: currencies[offer["denomination"]] = true
	var quotes := _exchange.known_offers(actor, _world.game_clock.total_minutes(), false)
	for offer: Dictionary in offers:
		var units := quantity
		if not category.is_empty():
			var service := _service(offer["good"], category)
			units = (quantity + service - 1) / service if service > 0 else 0
		offer["compare_across_currencies"] = currencies.size() > 1
		offer["cost_comparison"] = _comparison_cost(actor, offer, units, quotes)

func _comparison_less(a: Dictionary, b: Dictionary) -> bool:
	var first := a.get("cost_comparison", {}) as Dictionary
	var second := b.get("cost_comparison", {}) as Dictionary
	if first.get("executable", false) != second.get("executable", false): return first.get("executable", false)
	if first.get("executable", false) and first.get("currency") == second.get("currency") and first["cost"] != second["cost"]: return int(first["cost"]) < int(second["cost"])
	# Incomparable currencies retain an explicit stable fallback, never a claim
	# of cheapest landed cost. Stable identity breaks economically equal ties.
	return str(a["denomination"]) < str(b["denomination"]) if a["denomination"] != b["denomination"] else str(a["seller_site"]) + "|" + str(a["good"]) + "|" + str(a["route_id"]) < str(b["seller_site"]) + "|" + str(b["good"]) + "|" + str(b["route_id"])

func _offer_less_for(a: Dictionary, b: Dictionary, category: String) -> bool:
	var first_unit := _service(a["good"], category)
	var second_unit := _service(b["good"], category)
	if (first_unit > 0) != (second_unit > 0):
		return first_unit > 0
	if a.get("compare_across_currencies", false) and (a.get("cost_comparison", {}).get("executable", false) or b.get("cost_comparison", {}).get("executable", false) or a["denomination"] != b["denomination"]):
		return _comparison_less(a, b)
	var first := (int(a["price"]) + int(a["freight_per_unit"])) * second_unit
	var second := (int(b["price"]) + int(b["freight_per_unit"])) * first_unit
	return first < second if first != second else str(a["seller_site"]) + str(a["good"]) + str(a["route_id"]) < str(b["seller_site"]) + str(b["good"]) + str(b["route_id"])


func _cooperation_view(buyer: String, seller: String, good: String) -> Dictionary:
	var records: Array[Dictionary] = []
	var late: int = 0
	var quantity: int = 0
	var latest: int = -1
	for id: String in _relations.get(buyer + "|" + seller + "|" + good, []):
		var receipt := _delivery_receipts[id] as Dictionary
		if int(receipt["delivered_day"]) < day - COOPERATION_WINDOW_DAYS + 1:
			continue
		var order := _orders[receipt["order_id"]] as Dictionary
		var baseline := _earliest_dispatch(order) + _travel_days(order["route_legs"])
		var delay := maxi(0, int(receipt["delivered_day"]) - baseline)
		late += delay
		quantity += int(receipt["quantity"])
		latest = maxi(latest, int(receipt["delivered_day"]))
		records.append({"shipment_id": id, "order_id": order["id"], "quantity": receipt["quantity"], "delivered_day": receipt["delivered_day"], "baseline_arrival_day": baseline, "delay_days": delay})
	return {"deliveries": records, "received_quantity": quantity, "average_delay_days": (late + records.size() - 1) / records.size() if not records.is_empty() else 0, "latest_day": latest}

## Optional branch resale inventory needs a usable own selling price. This is
## a known landed-cost check, not an origin/buyer ban or a profit guarantee.
## Production, services, internal requests and accepted supply obligations
## retain their own purpose and cannot be silently abandoned by this filter.
func _resale_replenishment_observation(site: String, good: String, offer: Dictionary, requested: int = -1, need: Dictionary = {}) -> Dictionary:
	if need.is_empty(): need = _input_need(site, good)
	var production := 0
	var obligations := 0
	var ids: Array = []
	for r: Dictionary in need.get("timing_projection",{}).get("requirements",[]):
		if r["purpose"]=="PLANNED_PRODUCTION": production += int(r["quantity"])
		elif r["purpose"]=="ACCEPTED_SUPPLY_OBLIGATION":
			obligations += int(r["quantity"])
			ids.append(r["contract_id"])
	var service := _service_market.materials_needed(site, good)
	var internal := _internal_request_pressure(site, good)
	var capital := _capital.goods_needed(site, good)
	var target := production + obligations + service + internal + capital
	var protected_need := need.duplicate(true)
	protected_need["regular_quantity"] = maxi(0,target-int(need["on_hand"])-int(need.get("accepted_responsibility",need["incoming"])))
	protected_need["quantity"] = protected_need["regular_quantity"]
	var arrival: Variant = _input_offer_arrival(offer)
	var capacity := mini(1000000,maxi(0,int(offer.get("transport_quantity",1000000))))
	var batch := _input_offer_batch_size(offer)
	if requested<0: requested = int(_input_candidate_need(need,arrival,capacity,batch)["quantity"])
	requested = mini(capacity,maxi(0,requested))
	var protected := mini(requested,int(_input_candidate_need(protected_need,arrival,capacity,batch)["quantity"]))
	var optional := maxi(0,requested-protected)
	var original_optional: int=optional
	var market_time_response: Dictionary=OperatingInventory.arrival_response(self,site,good,offer.get("observed_arrival_day",arrival),need,batch)
	if not market_time_response.is_empty():optional=mini(optional,int(market_time_response.new_optional_quantity_limit))
	var turnover: Dictionary={}
	if offer.get("price") is int and offer.get("freight_per_unit") is int and offer.get("denomination")==_sale_currency(_owner(site)):
		turnover=OperatingInventory.turnover_response(self,site,good,offer,need,batch)
		if not turnover.is_empty():optional=mini(original_optional,int(turnover.optional_quantity_limit))
	var result := {"applicable":optional>0,"eligible":protected>0,"purpose":"PER_GOOD_QUANTITY_PURPOSES","reason":"NO_OPTIONAL_RESALE_REQUEST","own_price":null,"landed_unit_cost":null,"same_currency":false,"supply_contract_ids":ids,"protected_quantity":protected,"optional_quantity":optional,"quantity_limit":protected,"optional_eligible":false,"purpose_quantities":{"planned_recipe_input":production,"accepted_supply":obligations,"service_material":service,"internal_request":internal,"capital_material":capital}}
	if not turnover.is_empty():
		result["turnover_response"]=turnover
		if optional<=0 and original_optional>0:result.reason=turnover.reason
	if not market_time_response.is_empty():
		result["market_time_response"]=market_time_response
		if optional<=0 and requested>protected and turnover.is_empty():result.reason=market_time_response.reason
	if optional<=0: return result
	var row := _spec["sites"][site] as Dictionary
	if not _site_selling(site) or _local_quotes.sales_paused(site,good):
		result["reason"]="OWN_NEW_SALES_PAUSED_NO_OPTIONAL_BUFFER"
	elif not row["prices"].has(good):
		result["reason"]="NO_VALID_OWN_RESALE_PRICE"
	else:
		var own_price := _price(site,good)
		result["own_price"]=own_price
		var quotation := _local_quotes.current(site,good)
		if not _local_quotes.rule(site,good).is_empty() and (quotation.is_empty() or _world.game_clock.total_minutes()>=int(quotation["expires_day"])*1440):
			result["reason"]="NO_VALID_OWN_RESALE_PRICE"
		elif typeof(offer.get("price"))!=TYPE_INT or typeof(offer.get("freight_per_unit"))!=TYPE_INT:
			result["reason"]="UNKNOWN_LANDED_RESALE_COST"
		elif offer.get("denomination")!=_sale_currency(_owner(site)):
			result["reason"]="INCOMPARABLE_CURRENCY_NO_OPTIONAL_RESALE"
		else:
			result["same_currency"]=true
			var landed := int(offer["price"])+int(offer["freight_per_unit"])
			result["landed_unit_cost"]=landed
			result["optional_eligible"]=landed<=own_price and own_price>0
			result["reason"]="KNOWN_RESALE_PRICE_COVERS_GOODS_AND_FREIGHT" if result["optional_eligible"] else "LANDED_COST_EXCEEDS_OPTIONAL_RESALE_PRICE"
	if result["optional_eligible"]:
		var adaptation: Dictionary=need.get("inventory_adaptation",{})
		if not adaptation.is_empty():
			var spendable: int=int(_procurement_cash_position(_owner(site),offer["denomination"])["spendable"])
			var unit_cost: int=int(result["landed_unit_cost"])
			var budget: int=maxi(0,spendable-protected*unit_cost)*int(adaptation.cash_share_percent)/100
			var company_window: Dictionary=OperatingInventory.cash_window(self,_owner(site),offer.denomination)
			if not company_window.is_empty():
				budget=mini(budget,int(company_window.remaining))
				result["company_cash_window"]=company_window
			optional=mini(optional,budget/unit_cost) if unit_cost>0 else optional
			result["inventory_adaptation"]=adaptation.duplicate(true)
			result["optional_cash_budget"]=budget
			if optional==0:result["reason"]="OPTIONAL_BUFFER_CASH_SHARE_WAIT_DUE_CLAIMS_PROTECTED"
		result["quantity_limit"] += optional
	result["eligible"] = int(result["quantity_limit"])>0
	return result


func _input_offers(firm: String, good: String, need_by: int, requested: int = 1, timing_need: Dictionary = {}, purpose: String = "OPERATING_INPUT") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offer: Dictionary in _offers(_owner(firm), firm, good):
		if offer["good"] != good or typeof(offer.get("price"))!=TYPE_INT:
			continue # Unknown quoted prices are not executable input candidates.
		var resale := {"eligible":true,"quantity_limit":requested,"purpose":"UNADOPTED_CAPITAL_MATERIAL_SOURCE"} if purpose=="CAPITAL_FEASIBILITY" else _resale_replenishment_observation(firm, good, offer, requested, timing_need)
		if not resale["eligible"]: continue
		offer["replenishment_purpose"] = resale
		var relation := _cooperation_view(firm, offer["seller_site"], good)
		var lower: Variant = _input_offer_arrival(offer) if not timing_need.is_empty() else offer["earliest_arrival_day"]
		offer["observed_arrival_day"] = int(lower) + int(relation["average_delay_days"]) if lower != null else null
		offer["late_for_need"] = lower == null or int(offer["observed_arrival_day"]) > need_by
		if not timing_need.is_empty():
			offer["timing_decision"] = _input_candidate_need(timing_need, offer["observed_arrival_day"], mini(int(offer["transport_quantity"]),int(resale["quantity_limit"])), _input_offer_batch_size(offer))
			if int(offer["timing_decision"]["quantity"]) <= 0: continue
		offer["recent_cooperation_day"] = relation["latest_day"]
		result.append(offer)
	_annotate_costs(_owner(firm), result, maxi(1, requested))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (int(a["transport_quantity"]) > 0) != (int(b["transport_quantity"]) > 0):
			return int(a["transport_quantity"]) > 0
		if a["late_for_need"] != b["late_for_need"]:
			return not a["late_for_need"]
		var across: bool = a.get("compare_across_currencies", false)
		var first_cost := a["cost_comparison"] as Dictionary
		var second_cost := b["cost_comparison"] as Dictionary
		if across and first_cost["executable"] != second_cost["executable"]: return first_cost["executable"]
		if across and not first_cost["executable"] and a["denomination"] != b["denomination"]: return _comparison_less(a, b)
		# Untouched capital callers retain their original arrival-first ordering.
		if timing_need.is_empty() and a["observed_arrival_day"] != b["observed_arrival_day"]:
			return int(a["observed_arrival_day"]) < int(b["observed_arrival_day"])
		# Among useful input offers, prefer cost within the relevant boundary.
		if across and first_cost["executable"] and first_cost["cost"] != second_cost["cost"]: return int(first_cost["cost"]) < int(second_cost["cost"])
		var first := int(a["price"]) + int(a["freight_per_unit"])
		var second := int(b["price"]) + int(b["freight_per_unit"])
		if a["denomination"] == b["denomination"] and first != second:
			return first < second
		if a["observed_arrival_day"] != b["observed_arrival_day"]:
			if a["observed_arrival_day"] == null: return false
			if b["observed_arrival_day"] == null: return true
			return int(a["observed_arrival_day"]) < int(b["observed_arrival_day"])
		if a["quantity"] != b["quantity"]:
			return int(a["quantity"]) > int(b["quantity"])
		if a["recent_cooperation_day"] != b["recent_cooperation_day"]:
			return int(a["recent_cooperation_day"]) > int(b["recent_cooperation_day"])
		return str(a["seller_site"]) + str(a["route_id"]) < str(b["seller_site"]) + str(b["route_id"]))
	return result

func _production_new_input_contribution(site: String, activity_id: String) -> Dictionary:
	return NewInputContribution.observe(self, site, activity_id)

func _production_bundle_position(site: String) -> Dictionary:
	return ProductionBundle.position(self, site)

func _production_bundle_limit(site: String, good: String, wanted: int, source: String, path: String, internal: bool = false) -> int:
	var group: Dictionary = _production_bundle_position(site)
	if not group["applicable"]: return wanted
	# An input's separate accepted contract/service/capital purpose is not
	# erased when optional multi-material production must wait.
	var protected: int = mini(wanted, ProductionBundle.protected_quantity(self, site, good))
	var selected: Dictionary = group["selected"].get(good, {})
	if selected.is_empty() or selected["source_site"] != source or selected["route_id"] != path or (selected["kind"] == "INTERNAL") != internal: return protected
	return mini(wanted, maxi(protected, int(selected["selected_quantity"])))

## Ephemeral ordering only. The original accounts, permissions, budget,
## transfer and buy actions remain the sole spending authority. Keep each firm's
## world-turn slots, changing only the non-tied intentions within that firm.
func _procurement_intents() -> Array[Dictionary]:
	var original: Array[Dictionary] = []
	var by_firm: Dictionary = {}
	for site: String in _site_ids():
		if not _site_accepting(site) or _firm_winding_down(_owner(site)): continue
		var firm: String = _owner(site)
		for good: String in _goods:
			if not _input_good(site, good): continue
			var need: Dictionary = _input_need(site, good)
			var priority: int = 3
			var purpose: String = "OPTIONAL_RESALE_OR_BUFFER"
			var due: int = int(need["need_by_day"])
			for requirement: Dictionary in need["timing_projection"]["requirements"]:
				if int(requirement["quantity"]) <= 0: continue
				if requirement["purpose"] == "ACCEPTED_SUPPLY_OBLIGATION":
					priority = 0
					purpose = "ACCEPTED_SUPPLY_RESPONSIBILITY"
				elif requirement["purpose"] == "PLANNED_PRODUCTION" and priority > 1:
					priority = 1
					purpose = "FUTURE_RECIPE_INPUT"
			if _service_market.materials_needed(site, good) > 0 or _internal_request_pressure(site, good) > 0 or _capital.goods_needed(site, good) > 0:
				priority = 0
				purpose = "EXISTING_OPERATING_RESPONSIBILITY"
			var intent := {"firm": firm, "site": site, "good": good, "priority": priority, "purpose": purpose, "need_by_day": due, "basis": "SAME_COMPANY_FINITE_INTENT_ORDER_V1"}
			original.append(intent)
			if not by_firm.has(firm): by_firm[firm] = []
			by_firm[firm].append(intent)
	for firm: String in by_firm:
		var capital_adoption: bool=config.get("operating_inventory",{}).get("turnover_adaptation",false)
		if config.get("operating_inventory",{}).get("company_cash_window",false) or capital_adoption:
			var count: int=by_firm[firm].size()
			for index: int in count:
				var intent: Dictionary=by_firm[firm][index]
				var policy: Dictionary=OperatingInventory.observe(self,intent.site,intent.good)
				var exposure: int=maxi(1,_exposure(intent.site,intent.good))
				intent["own_sales_per_exposure"]=int(policy.get("own_delivered_sales",0))*100/exposure
				intent["rotating_tie"]=(index+day)%maxi(1,count)
				intent["opportunity_score"]=0.0;intent["comparison_currency"]=""
				if capital_adoption and int(intent.priority)==3:
					var decision_need: Dictionary=_input_need(intent.site,intent.good)
					for offer: Dictionary in _offers(firm,intent.site,intent.good):
						if not offer.price is int or not offer.get("freight_per_unit") is int or offer.denomination!=_sale_currency(firm) or int(offer.quantity)<=0:continue
						var comparison: Dictionary=OperatingInventory.turnover_response(self,intent.site,intent.good,offer,decision_need,_input_offer_batch_size(offer))
						if comparison.is_empty() or int(comparison.optional_quantity_limit)<=0:continue
						if float(comparison.opportunity_score)>float(intent.opportunity_score):intent.opportunity_score=comparison.opportunity_score;intent.comparison_currency=comparison.currency
		by_firm[firm].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["priority"] != b["priority"]: return int(a["priority"]) < int(b["priority"])
			if capital_adoption and int(a.priority)==3:
				if (float(a.opportunity_score)>0)!=(float(b.opportunity_score)>0):return float(a.opportunity_score)>0
				if a.comparison_currency==b.comparison_currency and not str(a.comparison_currency).is_empty() and not is_equal_approx(float(a.opportunity_score),float(b.opportunity_score)):return float(a.opportunity_score)>float(b.opportunity_score)
				return int(a.rotating_tie)<int(b.rotating_tie)
			if a["need_by_day"] != b["need_by_day"]: return int(a["need_by_day"]) < int(b["need_by_day"])
			if config.get("operating_inventory",{}).get("company_cash_window",false) and int(a.priority)==3:
				if a.own_sales_per_exposure!=b.own_sales_per_exposure:return int(a.own_sales_per_exposure)>int(b.own_sales_per_exposure)
				return int(a.rotating_tie)<int(b.rotating_tie)
			return str(a["site"]) + "|" + str(a["good"]) < str(b["site"]) + "|" + str(b["good"]))
	var result: Array[Dictionary] = []
	var cursor: Dictionary = {}
	for slot: Dictionary in original:
		var firm: String = slot["firm"]
		var index: int = int(cursor.get(firm, 0))
		result.append(by_firm[firm][index])
		cursor[firm] = index + 1
	return result

func _procure_inputs() -> void:
	_procurement_observations.clear()
	if not config["production_enabled"]:
		return
	for intent: Dictionary in _procurement_intents():
		var site: String = intent["site"]
		var good: String = intent["good"]
		var firm: String = intent["firm"]
		var need := _input_need(site, good)
		_coordinate_transfer(site, good, need)
		need = _input_need(site, good)
		if config.get("operating_inventory",{}).has("enquiry_response"):
			for known: Dictionary in _offers(firm,site,good):
				if not known.price is int:continue
				var response: Dictionary=_resale_replenishment_observation(site,good,known,maxi(1,int(need.regular_quantity)),need)
				if response.has("market_time_response") or response.has("turnover_response"):_procurement_observations.append({"kind":"MARKET_TIME_RESPONSE" if response.has("market_time_response") else "CAPITAL_RESPONSE","minute":_world.game_clock.total_minutes(),"site":site,"good":good,"supplier_site":known.seller_site,"response":response.duplicate(true)})
		var candidates: Array[Dictionary]=_input_offers(site, good, int(need["need_by_day"]), maxi(int(need["regular_quantity"]), int(need["timing_projection"]["uncovered_future_quantity"])), need)
		if _procurement_diagnostics_enabled:
			var known_offers: Array[Dictionary]=_offers(firm,site,good)
			_procurement_observations.append({"kind":"INTENT","minute":_world.game_clock.total_minutes(),"intent":intent.duplicate(true),"need":need.duplicate(true),"ranked":candidates.duplicate(true),"known_one_unit_admission":_managed_offer_rows(firm,firm,site,known_offers,1,0,known_offers.size()),"actual_plan":_plans.get(site,{}).duplicate(true)})
		var dated: bool=_dated_input_applicable(site,good,need)
		var tried: Dictionary={}
		var attempts: int=0
		var attempt_limit: int=maxi(1,candidates.size()*(need["timing_projection"]["requirements"].size()+1))
		while not candidates.is_empty():
			var offer: Dictionary=candidates.pop_front()
			need = _input_need(site, good)
			var key: String=str(offer["seller_site"])+"|"+str(offer["route_id"])+"|"+str(need["need_by_day"])
			if dated and (tried.has(key) or attempts>=attempt_limit):continue
			tried[key]=true;attempts+=1
			var choice: Dictionary=_input_dated_choice(site,good,need,offer,[offer]+candidates) if dated else _input_candidate_need(need, offer["observed_arrival_day"], int(offer["transport_quantity"]), _input_offer_batch_size(offer))
			var wanted := mini(1000000, int(choice["quantity"]))
			wanted = mini(wanted,int(_resale_replenishment_observation(site,good,offer,wanted,need)["quantity_limit"]))
			wanted = _production_bundle_limit(site, good, wanted, offer["seller_site"], offer["route_id"])
			if wanted <= 0: continue
			var limit := _purchase_limit(firm, good, offer["denomination"], int(offer["price"]))
			wanted=_retail.procurement_limit(site,good,offer,wanted)
			if wanted<=0: continue
			if limit >= int(offer["price"]):
				wanted = _fund_procurement(firm, offer, wanted)
				wanted = _procurement_cash_limit(firm, offer["denomination"], int(offer["price"]) + int(offer["freight_per_unit"]), wanted)
			wanted=_retail.procurement_limit(site,good,offer,wanted)
			if wanted<=0: continue
			offer = _offer(firm, offer["seller"], good, offer["route_id"], offer["seller_site"], site)
			var payload := {"quote_id": offer["quote_id"], "seller": offer["seller"], "seller_site": offer["seller_site"], "buyer_site": site, "good": good, "quantity": wanted, "denomination": offer["denomination"], "max_price": limit, "path_id": offer["route_id"], "need_by_day": clampi(int(choice["need_by_day"]), day, day + 30)}
			var observation: Dictionary={}
			if _procurement_diagnostics_enabled:
				var alternatives: Array[Dictionary]=_offers(firm,site,good)
				observation={"kind":"ATTEMPT","minute":_world.game_clock.total_minutes(),"intent":intent.duplicate(true),"need":need.duplicate(true),"choice":choice.duplicate(true),"offer":offer.duplicate(true),"payload":payload.duplicate(true),"available_cash":_world.ledger_state.available_balance(_account(firm,offer["denomination"])),"alternatives_at_quantity":_managed_offer_rows(firm,firm,site,alternatives,wanted,0,alternatives.size())}
			var inventory_decision: Dictionary=_resale_replenishment_observation(site,good,offer,wanted,need) if not need.get("inventory_adaptation",{}).is_empty() else {}
			var accepted: Dictionary=_accept(firm, _auto_command(firm, "buy", payload, site + "|" + str(offer["seller_site"]) + "|" + good + "|" + str(offer["route_id"])+("|dated:"+str(attempts) if dated else "")), true)
			if accepted.get("accepted",false) and not need.get("inventory_adaptation",{}).is_empty():
				var adopted: Dictionary=_commands[_orders[accepted.order_id].action_id].result
				adopted["decision"]={"purpose":"OWN_SALES_AND_OPTIONAL_INVENTORY","inventory_adaptation":need.inventory_adaptation.duplicate(true),"replenishment":inventory_decision}
				if inventory_decision.has("company_cash_window"):
					adopted.decision["company_cash_window"]=inventory_decision.company_cash_window.duplicate(true)
					adopted.decision["intent"]=intent.duplicate(true)
			if _procurement_diagnostics_enabled:observation["result"]=accepted.duplicate(true);_procurement_observations.append(observation)
			if dated and accepted.get("accepted",false):
				tried.clear() # A prior deferral is reconsidered after real capacity/cash changes.
				need=_input_need(site,good)
				candidates=_input_offers(site,good,int(need["need_by_day"]),maxi(int(need["regular_quantity"]),int(need["timing_projection"]["uncovered_future_quantity"])),need)
		_discover_suppliers(site, good, _input_need(site, good))


func _need_total(actor: String, category: String, elapsed: int) -> int:
	return Cohorts.required_total(_spec["actors"][actor], category, _spec["categories"][category]["mode"], elapsed)

func _need_on_day(actor: String, category: String, date: int) -> int:
	var elapsed := maxi(1, _managed_days(actor, date))
	return _need_total(actor, category, elapsed)-_need_total(actor, category, elapsed-1)

func _daily_need(actor: String, category: String = "food") -> int:
	return _need_on_day(actor, category, day)

func _actor_categories(actor: String) -> Array[String]:
	return Cohorts.category_order(_spec["actors"][actor], _category_order())


func _consume() -> bool:
	for actor: String in _actor_ids():
		var remaining_items := personal_inventory(actor) if manages_person(actor) else (_stocks[actor] as Dictionary).duplicate(true)
		var categories: Dictionary = {}
		for category: String in _actor_categories(actor):
			var required := _daily_need(actor, category)
			var service_satisfied:=mini(required,_service_market._resident.food_units(actor,day)) if category=="food" else 0
			var remaining := required-service_satisfied
			var used := _zero_goods()
			var flow: bool = _spec["categories"][category]["mode"] == "flow"
			for good: String in (_consumption_goods(category, actor) if required > 0 else []):
				if flow and manages_person(actor) and _world.personal_economy_state.schedules_category(actor, category):
					continue
				var unit := _service(good, category)
				var amount := mini(int(remaining_items[good]), (remaining + unit - 1) / unit)
				remaining_items[good] = int(remaining_items[good]) - amount
				used[good] = amount
				remaining -= mini(remaining, amount * unit)
				if flow and amount > 0:
					var physical := _consumption_rows(actor, good, amount)
					if not _lots.ready(physical): return _fail("Consumption lacks actual accessible batch portions")
					if manages_person(actor) and not _world.personal_economy_state.record_native_consumption(actor, good, amount, category, "needs"):
						return _fail(_world.personal_economy_state.error)
					var consumed := _lots.consume(physical, _world.game_clock.total_minutes())
					assert(consumed)
					_physical_totals[actor]["used"][good] = int(_physical_totals[actor]["used"][good]) + amount
					_totals[actor]["categories"][category]["used_items"][good] = int(_totals[actor]["categories"][category]["used_items"][good]) + amount
			categories[category] = {"required": required, "satisfied": required - remaining, "unmet": remaining, "used_items": used}
			if service_satisfied>0:
				categories[category]["service_satisfied"]=service_satisfied
				_totals[actor]["categories"][category]["service_satisfied"]=int(_totals[actor]["categories"][category].get("service_satisfied",0))+service_satisfied
			for field: String in ["required", "satisfied", "unmet"]:
				_totals[actor]["categories"][category][field] = int(_totals[actor]["categories"][category][field]) + int(categories[category][field])
		_needs[actor] = {"day": day, "categories": categories}
	return true


func _prune_windows() -> void:
	_prune_observation_indexes()
	for key: String in _request_window:
		var parts := key.split("|")
		var window := _request_retention_window(parts[0])
		var pricing := _price_policy(parts[0], parts[1])
		if not pricing.is_empty():
			window = maxi(window, int(pricing["window_days"]))
		var recent: Array = []
		for record: Dictionary in _request_window[key]:
			if int(record["day"]) >= day - window + 1:
				recent.append(record)
		_request_window[key] = recent


func visible(actor: String) -> Dictionary:
	if _declared_named(actor) and subject_exit_minute(actor) >= 0:
		var retained := _world.personal_economy_state.person_economy(actor)
		retained.merge({"known_jobs": [], "orders": [], "need_today": {}, "managed_firms": [], "scope_changes": scope_change_view(actor), "native_exit_minute": subject_exit_minute(actor), "can_reenter": true, "management_incoming": incoming_management_view(actor)})
		return retained
	if not _actors.has(actor) or _actors[actor]["control"] != "player":
		return {}
	var result := _visible_subject(actor)
	result["cargo_fulfilment"] = _cargo_fulfilment.visible(actor)
	result["resident_services"] = _service_market._resident.personal_view(actor)
	result["leases"] = _leases.view(actor,actor)
	result["commercial_information"]=_commercial.visible(actor)
	result["labor_market"]=_labor_market.worker_view(actor)
	return result

## Native automatic-owner query; the external person query retains its current
## player/alive boundary. This view exposes only the named owner's responsibilities.
func commercial_information(actor: String) -> Array[Dictionary]:
	return _commercial.visible(actor) if _actors.has(actor) and _actors[actor]["control"]=="player" and personal_authorized(actor) else []

func visible_internal(actor: String) -> Dictionary:
	if not _spec["firms"].has(actor) and (not _actors.has(actor) or _actors[actor]["control"] != "automatic"):
		return {}
	return _visible_subject(actor)

func _waiting_reason(leg: Dictionary, quantity: int, ready_day: int, good: String = "") -> String:
	if _shared.alias_requires_binding(leg["edge_id"]): return "SHARED_RESOURCE_REQUIRES_EXPLICIT_BINDING"
	if not _cargo_edge_valid(_all_routes()[leg["edge_id"]]): return "HOST_CONNECTION_UNAVAILABLE"
	if ready_day > day:
		return "NOT_READY"
	var edge := _edge(leg["edge_id"])
	if _shared.bindings.has(leg["edge_id"]):
		if not _shared.window_open(_shared.bindings[leg["edge_id"]], _world.game_clock.total_minutes()): return "WAITING_EXPLICIT_HOST_ENTRY_WINDOW"
		if _shared.quantity(leg["edge_id"], good, quantity) < quantity: return "SHARED_LINK_VEHICLE_OR_HANDLING_LIMIT"
	elif int(edge["capacity"]) == 0:
		return "EDGE_CLOSED"
	elif int(edge["capacity"]) - int(edge["dispatched"]) < quantity:
		return "EDGE_CAPACITY"
	var place := str(_all_routes()[leg["edge_id"]]["from_place_id"])
	if _node_available(place) < quantity:
		return "NODE_CAPACITY"
	return "QUEUED_NEXT_DISPATCH"

func _shipment_view(shipment: Dictionary, order: Dictionary) -> Dictionary:
	var result := shipment.duplicate(true)
	result["physical_quantity"] = _lots.quantity_at("CARGO|"+str(shipment["id"]), order["good"])
	result["unresolved_loss_quantity"] = int(shipment["quantity"])-int(result["physical_quantity"])
	result["collectable_quantity"] = result["physical_quantity"] if shipment["stage"] == "AWAITING_RECIPIENT" else 0
	var legs := order["route_legs"] as Array
	var index := int(shipment["leg_index"])
	if shipment["stage"] in ["WAITING_UNLOAD","UNLOADING"]:
		result["waiting_reason"] = _shared.arrival_wait_reason(shipment,order)
		result["node_resources"] = _shared.shipment_node_view(shipment["id"])
		result["earliest_arrival_day"] = null
		result["eta_guaranteed"] = false
		return result
	if shipment["stage"] == "AWAITING_RECIPIENT":
		var completed: Array[String] = []
		for leg: Dictionary in legs: completed.append(leg["edge_id"])
		result.merge({"leg_count": legs.size(), "completed_edge_ids": completed, "from_place_id": order["to_place_id"], "to_place_id": order["to_place_id"], "current_edge_id": "", "next_edge_id": "", "waiting_reason": "EXPLICIT_OWNER_COLLECTION_REQUIRED", "eta_guaranteed": false, "eta_may_change": true, "eta_basis": "WAITING_FOR_RECIPIENT", "earliest_arrival_day": null, "arrival_blocked_reason": "EXPLICIT_OWNER_COLLECTION_REQUIRED"})
		return result
	var current := legs[index] as Dictionary
	var edge := _all_routes()[current["edge_id"]] as Dictionary
	var completed: Array[String] = []
	for position: int in index:
		completed.append(legs[position]["edge_id"])
	result.merge({"leg_count": legs.size(), "completed_edge_ids": completed, "from_place_id": edge["from_place_id"], "to_place_id": edge["to_place_id"], "current_edge_id": current["edge_id"] if shipment["stage"] in ["TRANSIT", "LOADING"] else "", "next_edge_id": current["edge_id"] if shipment["stage"] == "WAITING" else (legs[index + 1]["edge_id"] if index + 1 < legs.size() else ""), "waiting_reason": _waiting_reason(current, int(shipment["quantity"]), int(shipment["ready_day"]), order["good"]) if shipment["stage"] == "WAITING" else "", "eta_guaranteed": false, "eta_may_change": true, "eta_basis": "EARLIEST_WITHOUT_FUTURE_QUEUE_DELAY"})
	# A lower bound uses actual entered-leg arrival and current remaining capacity.
	# Waiting for an unknown reopening has no promised arrival date.
	var estimate := int(shipment["leg_arrival_day"]) if shipment["stage"] in ["TRANSIT", "LOADING"] else maxi(day + 1, int(shipment["ready_day"]))
	if shipment.has("arrival_minute") and shipment["stage"] in ["TRANSIT", "LOADING"]:
		estimate = maxi(estimate, (int(shipment["arrival_minute"]) + 1439) / 1440)
	var first := index + 1 if shipment["stage"] in ["TRANSIT", "LOADING"] else index
	var blocked: String = ""
	for position: int in range(first, legs.size()):
		var leg := legs[position] as Dictionary
		if not _cargo_edge_valid(_all_routes()[leg["edge_id"]]):
			blocked = "HOST_CONNECTION_UNAVAILABLE"
			estimate = -1
			break
		if _shared.bindings.has(leg["edge_id"]):
			blocked = "FUTURE_HOST_ENTRY_ALLOCATION_REQUIRED"
			estimate = -1
			break
		if int(_edge(leg["edge_id"])["capacity"]) < int(shipment["quantity"]):
			blocked = "EDGE_CLOSED" if int(_edge(leg["edge_id"])["capacity"]) == 0 else "BATCH_EXCEEDS_ACTIVE_CAPACITY"
			estimate = -1
			break
		estimate += int(leg["delay"])
	if _shared.bindings.get(current["edge_id"], {}).has("node_resources"):
		estimate = -1
		blocked = "UNLOADING_COMPLETION_NOT_YET_ALLOCATED"
		result["node_resources"] = _shared.shipment_node_view(shipment["id"])
	result["earliest_arrival_day"] = estimate if estimate >= 0 else null
	result["arrival_blocked_reason"] = blocked
	return result

func _order_view(order: Dictionary) -> Dictionary:
	var result := order.duplicate(true)
	var legs := order["route_legs"] as Array
	var freight := _freight(legs)
	var unsettled := int(order["pending"]) + int(order["transit"])
	result.merge({"freight_per_unit": freight, "locked_goods_amount": int(order["quantity"]) * int(order["price"]), "locked_freight_amount": int(order["quantity"]) * freight, "unsettled_goods_amount": unsettled * int(order["price"]), "unsettled_freight_amount": unsettled * freight, "reserved_amount": unsettled * (int(order["price"]) + freight), "paid_goods_amount": int(order["delivered"]) * int(order["price"]), "paid_freight_amount": int(order["delivered"]) * freight, "eta_guaranteed": false, "eta_may_change": unsettled > 0})
	var shipments: Array[Dictionary] = []
	var waiting: int = 0
	var awaiting_recipient: int = 0
	var estimate: int = -1
	var unknown: bool = false
	var ids := _sorted_ids(_shipments_by_order.get(order["id"], {}))
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("shipment:")) < int(b.trim_prefix("shipment:")))
	for id: String in ids:
		if _shipments[id]["order_id"] != order["id"]:
			continue
		var cargo := _shipment_view(_shipments[id], order)
		shipments.append(cargo)
		if cargo["stage"] == "WAITING":
			waiting += int(cargo["quantity"])
		elif cargo["stage"] == "AWAITING_RECIPIENT": awaiting_recipient += int(cargo["quantity"])
		if cargo["earliest_arrival_day"] == null:
			unknown = true
		else:
			estimate = maxi(estimate, int(cargo["earliest_arrival_day"]))
	result["shipments"] = shipments
	result["waiting_quantity"] = waiting
	result["pending_waiting_reason"] = _waiting_reason(legs[0], 1, _earliest_dispatch(order), order["good"]) if int(order["pending"]) > 0 else ""
	if int(order["pending"]) > 0:
		var batch := _batch_limit(legs)
		var shared := false
		for leg: Dictionary in legs:
			if _shared.bindings.has(leg["edge_id"]): shared = true
			else: batch = mini(batch, int(_edge(leg["edge_id"])["capacity"]))
		if batch == 0 or shared:
			unknown = true
		else:
			var dispatch_days: int = (int(order["pending"]) + batch - 1) / batch
			estimate = maxi(estimate, maxi(day + 1, _earliest_dispatch(order)) + dispatch_days - 1 + _travel_days(legs))
	var deliveries: Array[Dictionary] = []
	for receipt_id: String in _deliveries_by_order.get(order["id"], []):
		var receipt := _delivery_receipts[receipt_id] as Dictionary
		deliveries.append(receipt.duplicate(true))
		if unsettled == 0: estimate = maxi(estimate, int(receipt["delivered_day"]))
	deliveries.sort_custom(_receipt_less)
	result["deliveries"] = deliveries
	result["awaiting_recipient_quantity"] = awaiting_recipient
	var collectable := 0
	var lost := _cargo_fulfilment.unresolved(order["id"])
	for shipment_id: String in _shipments_by_order.get(order["id"], {}):
		var physical := _lots.quantity_at("CARGO|"+shipment_id, order["good"])
		lost += int(_shipments[shipment_id]["quantity"])-physical
		if _shipments[shipment_id]["stage"] == "AWAITING_RECIPIENT": collectable += physical
	result["collectable_quantity"] = collectable
	result["unresolved_loss_quantity"] = lost
	result["can_collect"] = collectable > 0 and manages_person(order["buyer"]) and _recipient_at_destination(order)
	result["can_collect_to_storage"] = result["can_collect"] and not _personal_storage_site(order["to_place_id"], order["good"]).is_empty()
	result["custody_place_id"] = order["to_place_id"] if awaiting_recipient > 0 else ""
	result["travel_quote"] = _world.person_travel.quote(order["buyer"], order["to_place_id"]) if manages_person(order["buyer"]) and _world.person_travel != null else {}
	result["stage"] = "AWAITING_RECIPIENT" if awaiting_recipient > 0 else "WAITING_TRANSFER" if waiting > 0 else "TRANSIT" if int(order["transit"]) > 0 else "PENDING_DISPATCH" if int(order["pending"]) > 0 else "DELIVERED" if int(order["delivered"]) > 0 else "CANCELLED"
	result["earliest_arrival_day"] = estimate if not unknown and estimate >= 0 else null
	return result

func _related_npc_actions(actor: String, loans: Array, payments: Array[Dictionary]) -> Array[Dictionary]:
	var own: Dictionary = {}
	for loan: Dictionary in loans:
		own[loan["id"]] = true
	var result: Array[Dictionary] = []
	for id: String in _commands:
		var entry := _commands[id] as Dictionary
		var subject := str(entry["envelope"]["actor"])
		var command := entry["envelope"]["command"] as Dictionary
		var actual := entry["result"] as Dictionary
		if subject == actor or not actual.has("decision"):
			continue
		if command["kind"] == "exchange_currency":
			var related: Array[Dictionary] = []
			for payment: Dictionary in payments:
				if payment["reference_id"] == actual.get("deal_id") and payment["kind"] in ["fx_principal", "fx_target", "fx_fee"]:
					related.append(payment.duplicate(true))
			if not related.is_empty():
				result.append({"action_id": id, "actor": subject, "minute": command["minute"], "kind": command["kind"], "result": {"accepted": actual["accepted"], "reason": actual["reason"], "deal_id": actual["deal_id"], "own_payments": related}})
			continue
		if command["kind"] not in ["accept_credit", "repay_loan"] or not own.has(actual.get("loan_id")):
			continue
		var response: Dictionary = {}
		for field: String in ["accepted", "reason", "loan_id", "amount", "interest_paid", "principal_paid"]:
			if actual.has(field):
				response[field] = actual[field]
		result.append({"action_id": id, "actor": subject, "minute": command["minute"], "kind": command["kind"], "result": response})
	return result

func _firm_finance_view(firm: String) -> Dictionary:
	var window := int(_operations_policy(firm)["demand_window"])
	var result := {"window_start_day": maxi(0, day - window + 1), "sales_received": {}, "inputs_paid": {}, "freight_paid": {}, "wages_paid": {}, "wages_incurred": {}, "wages_unpaid": {}, "fx_fees_paid": {}, "cargo_refunds_received": {}, "cargo_refunds_paid": {}, "cargo_damages_received": {}, "cargo_damages_paid": {}, "cargo_extra_freight_paid": {}, "loan_principal_received": {}, "debt_payments": {}, "account_cash": {}, "classification_basis": "CASH_FLOWS_AND_OPEN_RESPONSIBILITIES_NOT_PROFIT", "procurement_budget": _budget_view(firm)}
	for payment: Dictionary in _world.ledger_state.own_transactions(firm, int(result["window_start_day"]) * 1440):
		var currency := str(payment["denomination"])
		var own_account := _account(firm, currency)
		var field: String = ""
		if payment["kind"]=="loan_repayment":
			var command_id := str(payment["transaction_id"]).trim_prefix("r1:loan_repayment:")
			var recorded := _commands.get(command_id,{}).get("result",{}) as Dictionary
			if FormalLedgerState.valid_amount(recorded.get("interest_paid")) and FormalLedgerState.valid_amount(recorded.get("principal_paid")) and int(recorded["interest_paid"])+int(recorded["principal_paid"])==int(payment["amount"]):
				for part: String in ["interest","principal"]:
					var category := "debt_"+part+"_paid" if payment["from_account_id"]==own_account else "loan_"+part+"_recovered"
					if not result.has(category): result[category]={}
					result[category][currency]=int(result[category].get(currency,0))+int(recorded[part+"_paid"])
		if payment["kind"] == "loan_issue" and payment["to_account_id"] == own_account:
			field = "loan_principal_received"
		elif payment["kind"]=="dividend":
			field="shareholder_distribution_received" if payment["to_account_id"]==own_account else "shareholder_distribution_paid"
		elif payment["kind"]=="equity_issue":
			field="primary_equity_received" if payment["to_account_id"]==own_account else "primary_subscriptions_paid"
		elif payment["kind"]=="loan_repayment" and payment["to_account_id"]==own_account:
			field="loan_repayments_received"
		elif payment["kind"]=="freight" and payment["from_account_id"]==own_account and payment["to_account_id"]==own_account:
			field="internal_freight_transfers"
		elif payment["kind"]=="capital_equipment":
			field="equipment_disposal_received" if payment["to_account_id"]==own_account else "capital_asset_paid"
		elif payment["kind"] == "goods":
			field = "sales_received" if payment["to_account_id"] == own_account else "inputs_paid"
		elif payment["kind"] == "lease_rent":
			field = "rent_received" if payment["to_account_id"] == own_account else "rent_paid"
		elif payment["kind"] == "service_fee":
			var publication: bool=_service_market.contracts.get(payment.get("reference_id",""),{}).get("kind")=="ANNOUNCEMENT"
			field = ("publication_fees_received" if payment["to_account_id"] == own_account else "advertising_paid") if publication else ("service_fees_received" if payment["to_account_id"] == own_account else "service_fees_paid")
		elif payment["kind"] in ["cargo_refund", "cargo_damages"]:
			field = ("cargo_refunds_" if payment["kind"] == "cargo_refund" else "cargo_damages_") + ("received" if payment["to_account_id"] == own_account else "paid")
		elif payment["kind"]=="freight" and payment["to_account_id"]==own_account:
			field="freight_received"
		elif payment["from_account_id"] == own_account:
			match payment["kind"]:
				"cargo_extra_freight": field = "cargo_extra_freight_paid"
				"freight": field = "freight_paid"
				"wage": field = "wages_paid"
				"fx_fee": field = "fx_fees_paid"
				"loan_repayment": field = "debt_payments"
		if not field.is_empty():
			if not result.has(field): result[field]={}
			result[field][currency] = int(result[field].get(currency, 0)) + int(payment["amount"])
	var incurred := _wage_days.get(firm, {}) as Dictionary
	for date: int in range(int(result["window_start_day"]), day + 1):
		for currency: String in incurred.get(date, {}):
			result["wages_incurred"][currency] = int(result["wages_incurred"].get(currency, 0)) + int(incurred[date][currency])
	for wage_id: String in _open_wages_by_employer.get(firm, {}):
		var claim := _wages[wage_id] as Dictionary
		if claim["employer"] != firm: continue
		var currency := str(claim["denomination"])
		result["wages_unpaid"][currency] = int(result["wages_unpaid"].get(currency, 0)) + int(claim["remaining"])
	for account: Dictionary in _world.ledger_state.own_accounts(firm):
		result["account_cash"][account["denomination"]] = {"balance": account["balance"], "reserved": _world.ledger_state.reserved_balance(account["account_id"]), "available": _world.ledger_state.available_balance(account["account_id"])}
	result["matured_wages"]={}
	for currency: String in result["account_cash"]: result["matured_wages"][currency]=_mature_wage_position(firm,currency)
	result["credit_responsibilities"]=_credit.visible(firm,_known_credit_lenders(firm),_world.game_clock.total_minutes(),true)
	result["liquidity_policy"]=Liquidity.policy(config,firm).duplicate(true)
	result["goods_purchases_paid"]=result["inputs_paid"].duplicate(true)
	result["direct_costs"] = _costs.view(firm, window)
	result["procurement_cash"]={}
	for currency: String in result["account_cash"]:
		var position: Dictionary=_procurement_cash_position(firm,currency)
		var summary: Dictionary={}
		# This authorized money summary must not publish the internal query's
		# unconfirmed cargo-loss references or physical status to a player.
		for field: String in ["basis","firm","currency","balance","reserved","available","due_unreserved","original_policy_floor","protected","spendable","scope"]:summary[field]=position[field]
		result["procurement_cash"][currency]=summary
	result["lease_obligations"] = _leases.finance_view(firm,window)
	return result

func _site_operating_view(firm: String) -> Dictionary:
	var plan := (_plans.get(firm, {}) as Dictionary).duplicate(true)
	var activities: Array[Dictionary] = []
	var scheduled_hours: int = 0
	var actual_hours: int = 0
	var used := _zero_goods()
	for id: String in _spec["sites"][firm]["activity_order"]:
		var activity := _activity(firm, id).duplicate(true)
		activity["state"] = _site_state[firm]["activities"][id].duplicate(true)
		var local := (plan.get("activities", {}).get(id, {}) as Dictionary).duplicate(true)
		if not local.is_empty():
			var batches := int(local["schedule"][0]["quantity"])
			scheduled_hours += batches * int(activity["hours"])
			actual_hours += int(local["actual"]) * int(activity["hours"])
			local["unproduced_today"] = batches - int(local["actual"])
			var scheduled: int = 0
			for entry: Dictionary in local["schedule"]:
				scheduled += int(entry["quantity"])
			local["unplanned_batches"] = maxi(0, int(local["desired"]) - scheduled)
			local["planned_outputs_today"] = {}
			local["actual_outputs_today"] = {}
			for good: String in activity["outputs"]:
				local["planned_outputs_today"][good] = batches * int(activity["outputs"][good])
				local["actual_outputs_today"][good] = int(local["actual"]) * int(activity["outputs"][good])
			for good: String in _goods:
				used[good] = int(used[good]) + int(local["actual"]) * int(activity["materials"][good])
		activity["plan"] = local
		var conditions: Array[String]=[]
		if not _site_operating(firm): conditions.append("SITE_NOT_OPERATING")
		if not _leases.site_allowed(firm): conditions.append("NO_CURRENT_LEASE_USE_RIGHT")
		elif not _site_producing(firm): conditions.append("PRODUCTION_PAUSED")
		if not _site_state[firm]["activities"][id]["enabled"]: conditions.append("ACTIVITY_DISABLED")
		if _capital.capacity(firm,_world.game_clock.total_minutes(),id)<activity["capacity_units"]: conditions.append("NO_COMPATIBLE_EQUIPMENT")
		for good: String in _goods:
			if int(activity["materials"][good])>capital_free_goods(firm,good): conditions.append("MATERIAL_SHORTAGE:"+good)
		activity["next_batch_constraints"]=conditions
		activities.append(activity)
	if not plan.is_empty():
		plan.merge({"scheduled_hours": scheduled_hours, "used_hours": actual_hours, "labor_shortfall_hours": maxi(0, scheduled_hours - int(plan["labor_hours"])), "materials_used": used})
	var needs: Array[Dictionary] = []
	for good: String in _goods:
		if _input_good(firm, good):
			needs.append(_input_need(firm, good))
	var jobs: Array[Dictionary] = []
	for id: String in _sorted_ids(_spec["jobs"]):
		if _spec["jobs"][id]["site_id"] == firm:
			var row := _job(id)
			row["posting"] = (_job_postings[id] as Dictionary).duplicate(true)
			jobs.append(row)
	var prices: Dictionary = {}
	for good: String in _spec["sites"][firm]["prices"]:
		var policy := _price_policy(firm, good)
		prices[good] = {"price": _price(firm, good), "denomination": _sale_currency(firm), "mode": policy.get("mode", "N2"), "policy": policy.duplicate(true), "state": (_quote_state.get(firm + "|" + good, {}) as Dictionary).duplicate(true)}
		prices[good]["listing"] = _managed_listing_view(firm, good)
	var cooperation: Dictionary = {}
	for candidate: String in _firm_knowledge[firm]:
		var parts := candidate.split("|")
		cooperation[candidate] = _cooperation_view(firm, _candidate(candidate)["site"], parts[1])
	var received: Dictionary = {}
	for good: String in _spec["sites"][firm]["prices"]:
		var records: Array[Dictionary] = []
		for record: Dictionary in _request_window.get(firm + "|" + good, []):
			var row := record.duplicate(true)
			if row.has("limit_observation"): row["limit_observation"]["caps"].erase("cash")
			if not str(row.get("order_id", "")).is_empty():
				var order := _orders[row["order_id"]] as Dictionary
				row["fulfillment"] = {"order_id": order["id"], "accepted": order["quantity"], "pending": order["pending"], "transit": order["transit"], "delivered": order["delivered"], "cancelled": order["cancelled"]}
			records.append(row)
		received[good] = records
	var product_needs: Dictionary = {}
	for good: String in _spec["sites"][firm]["prices"]:
		var committed := _committed(firm, good)
		var pressure := _received_pressure(firm, good)
		var internal := _internal_request_pressure(firm, good)
		var rate := _observed_daily_orders(firm, good)
		var target := int(_spec["sites"][firm]["targets"][good])
		product_needs[good] = {"inventory_adaptation": OperatingInventory.observe(self,firm,good), "inventory_target": target, "pending_sales": committed, "received_physical_requests": pressure, "delivered_internal_need": internal, "observed_daily_orders": rate, "net_needed": maxi(0, target + committed + pressure + internal + rate * int(_operations_policy(firm)["planning_horizon"]) - _exposure(firm, good))}
	var searches: Dictionary = {}
	var pending: Array[Dictionary] = []
	for good: String in _goods:
		if _search_state.has(firm + "|" + good):
			searches[good] = (_search_state[firm + "|" + good] as Dictionary).duplicate(true)
	for message: Dictionary in _messages:
		if message["actor"] == firm and message["kind"] == "directory":
			pending.append(message.duplicate(true))
	var free := _zero_goods()
	var committed := _zero_goods()
	var incoming := _zero_goods()
	var stock_costs: Dictionary={}
	for good: String in _goods:
		committed[good] = _committed(firm, good)
		free[good] = maxi(0, int(_stocks[firm][good]) - int(committed[good]))
		incoming[good] = _exposure(firm, good) - int(_stocks[firm][good])
		if int(free[good])>0:stock_costs[good]=OperatingInventory.stock_cash(self,firm,good)
	return {"stock_costs":stock_costs,"firm_id": _owner(firm), "site_id": firm, "roles": _spec["sites"][firm]["roles"].duplicate(), "inventory": _stocks[firm].duplicate(true), "free_inventory": free, "committed_inventory": committed, "incoming": incoming, "known_suppliers": _firm_knowledge[firm].duplicate(), "supplier_introductions": _supplier_introduction_view(firm), "offers": _offers(_owner(firm), firm), "delivered_report": (_site_reports.get(firm, {}) as Dictionary).duplicate(true), "host_organization_id": _spec["firms"][_owner(firm)].get("host_organization_id", ""), "manager": firm_manager_at(_owner(firm), _world.game_clock.total_minutes()), "management_basis": _firm_management_basis(_owner(firm)), "operating": _site_operating(firm), "lease_use_allowed": _leases.site_allowed(firm), "site_status": _site_state[firm].duplicate(true), "stock_place_id": _place(firm), "population_unit_id": _world.population_state.unit_for_place(_place(firm)), "shared_capacity": site_capacity(firm), "base_capacity": _spec["sites"][firm]["capacity"], "capacity_pools": _capital.pools(firm, _world.game_clock.total_minutes()), "capacity_basis": "CONFIGURED_BASE_PLUS_ACTUAL_INSTALLED_CAPITAL", "activities": activities, "product_needs": product_needs, "plan": plan, "input_needs": needs, "job_postings": jobs, "quotations": prices, "cooperation": cooperation, "received_requests": received, "finances": _firm_finance_view(_owner(firm)), "supplier_search": searches, "pending_directory_results": pending}

## Only this desk's already adopted introductions. Reuse direct receipt keys
## and Commercial's recipient index; never scan all world firms or inboxes.
func _supplier_introduction_view(site: String) -> Array[Dictionary]:
	var known: Array=_firm_knowledge.get(site,[])
	var first: Dictionary={}
	for candidate: String in known:
		var receipt: Dictionary=_receipts.get("message:"+site+":supplier:"+candidate,{})
		if not receipt.is_empty():first[candidate]=receipt
	for id: String in _commercial._received.get(site,[]):
		var receipt: Dictionary=_receipts[id]
		if receipt.get("kind")!="supplier" or receipt.candidate not in known:continue
		if not first.has(receipt.candidate) or int(receipt.delivery_day)<int(first[receipt.candidate].delivery_day):first[receipt.candidate]=receipt
	var result: Array[Dictionary]=[]
	for candidate: String in known:
		var source: Dictionary=first.get(candidate,{})
		var parsed: Dictionary=_candidate(candidate)
		result.append({"buyer_site":site,"seller":parsed.seller,"seller_site":parsed.site,"good":parsed.good,"from_place_id":_place(parsed.site),"to_place_id":_place(site),"knowledge_source":source.get("source","opening") if not source.is_empty() else "UNKNOWN_RETAINED_INTRODUCTION","received_day":source.get("delivery_day",null),"observed_day":source.get("observed_day",null),"message_id":source.get("id",""),"announcement_id":source.get("announcement_id","")})
	return result

func _visible_subject(actor: String) -> Dictionary:
	var payments := _world.ledger_state.own_transactions(actor)
	var jobs: Array[Dictionary] = []
	for id: String in _actors.get(actor, {}).get("known_jobs", []):
		var known := _known_job(actor, id)
		known["at_workplace"] = _at_place(actor, str(known.get("place", "")))
		known["travel_quote"] = _world.person_travel.quote(actor, known["place"]) if _world.person_travel != null else {}
		jobs.append(known)
	var orders: Array[Dictionary] = []
	var own_ids: Array = _orders_by_buyer.get(actor, []).duplicate()
	own_ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("order:")) < int(b.trim_prefix("order:")))
	for id: String in own_ids:
		var row := _order_view(_orders[id])
		var known := _cargo_fulfilment.visible(actor, id)
		row["cargo_fulfilment"] = known
		if int(row.get("unresolved_loss_quantity", 0)) > 0 and known["losses"].is_empty():
			row["unresolved_loss_quantity"] = null
			row["physical_tracking"] = "AWAITING_CONFIRMED_LOSS_NOTICE"
			for cargo: Dictionary in row["shipments"]:
				if not _at_place(actor, str(cargo.get("place_id", ""))):
					cargo["physical_quantity"] = null
					cargo["unresolved_loss_quantity"] = null
		orders.append(row)
	var outstanding: int = 0
	var matured: int = 0
	var wages_by_currency: Dictionary = {}
	var income_by_currency: Dictionary = {}
	for claim: Dictionary in _wages.values():
		if claim["worker"] == actor:
			income_by_currency[claim["denomination"]] = int(income_by_currency.get(claim["denomination"], 0)) + int(claim["paid"])
	for id: String in _wages_by_worker.get(actor, []):
		var claim := _wages[id] as Dictionary
		if claim["worker"] == actor:
			var currency := str(claim["denomination"])
			if not wages_by_currency.has(currency):
				wages_by_currency[currency] = {"outstanding": 0, "matured_unpaid": 0}
			wages_by_currency[currency]["outstanding"] = int(wages_by_currency[currency]["outstanding"]) + int(claim["remaining"])
			if int(claim["due_day"]) <= day:
				wages_by_currency[currency]["matured_unpaid"] = int(wages_by_currency[currency]["matured_unpaid"]) + int(claim["remaining"])
			if currency == FormalLedgerState.DENOMINATION:
				outstanding += int(claim["remaining"])
				if int(claim["due_day"]) <= day:
					matured += int(claim["remaining"])
	var credit_view := _credit.visible(actor, _known_credit_lenders(actor), _world.game_clock.total_minutes())
	var credit_actions: Array[Dictionary] = []
	var financial_actions: Array[Dictionary] = []
	for id: String in _commands:
		var entry := _commands[id] as Dictionary
		var command := entry["envelope"]["command"] as Dictionary
		if entry["envelope"]["actor"] == actor and command["kind"] in Credit.ACTIONS:
			credit_actions.append({"action_id": id, "minute": command["minute"], "kind": command["kind"], "payload": command["payload"].duplicate(true), "result": entry["result"].duplicate(true)})
		if entry["envelope"]["actor"] == actor and (command["kind"] in Exchange.ACTIONS or command["kind"] in Assets.ACTIONS):
			financial_actions.append({"action_id": id, "minute": command["minute"], "kind": command["kind"], "payload": command["payload"].duplicate(true), "result": entry["result"].duplicate(true)})
	credit_view["actions"] = credit_actions
	var result := {"current_place_id": _place(actor), "activity_population_unit_id": _world.population_state.unit_for_place(_place(actor)), "resident_population_unit_id": _population_unit(actor) if _actors.has(actor) else "", "population_unit_id": _population_unit(actor) if _actors.has(actor) else _world.population_state.unit_for_place(_place(actor)), "management_scope_id": _management.get("scope_id", ""), "person_id": actor, "subject_id": actor, "minute": _world.game_clock.total_minutes(), "day": day, "known_jobs": jobs, "offers": _offers(actor), "employment": (_contracts.get(actor, {}) as Dictionary).duplicate(true), "cash": _world.ledger_state.balance(_account(actor)), "reserved": _world.ledger_state.reserved_balance(_account(actor)), "accounts": _world.ledger_state.own_accounts(actor), "transactions": payments, "inventory": _inventory_view(actor), "orders": orders, "wage_outstanding": outstanding, "wage_matured_unpaid": matured, "wages_by_currency": wages_by_currency, "income_by_currency": income_by_currency, "need_today": (_needs.get(actor, {}) as Dictionary).duplicate(true) if _needs.get(actor, {}).get("day") == day else {}, "totals": (_totals.get(actor, {}) as Dictionary).duplicate(true), "credit": credit_view, "currency_exchange": _exchange.visible(actor, _world.game_clock.total_minutes()), "assets": _assets.visible(actor, _world.game_clock.total_minutes()), "financial_actions": financial_actions}

	result["managed_firms"] = []
	for firm: String in _firm_ids():
		if _manager(actor, firm):
			result["managed_firms"].append({"firm_id": firm, "place_id": _place(firm), "operating": _firm_operating(firm), "host_organization_id": _spec["firms"][firm].get("host_organization_id", ""), "lifecycle": enterprise_lifecycle_view(actor, firm)})
	result["travel"] = _world.person_overlay.travel_view(actor) if _actors.has(actor) and _spec["actors"][actor]["kind"] == "named" else {}
	result["scope_changes"] = scope_change_view(actor)
	result["management_incoming"] = incoming_management_view(actor)
	result["goods"] = _goods.duplicate()
	result["services_per_item"] = _services.duplicate(true)
	result["need_categories"] = _spec["categories"].duplicate(true)
	if _actors.has(actor):
		result["purchase_needs"] = _household_position(actor, true)
	result["known_suppliers"] = _known_suppliers(actor).duplicate()
	result["related_npc_financial_actions"] = _related_npc_actions(actor, credit_view["loans"], payments)
	if _spec["firms"].has(actor):
		var sales: Array[Dictionary] = []
		for number: int in range(1, next_order):
			var order := _orders["order:" + str(number)] as Dictionary
			if order["seller"] == actor and order["kind"] == "SALE":
				sales.append(_order_view(order))
		result["sales_orders"] = sales
		result["operations"] = []
		for site: String in _spec["firms"][actor]["sites"]:
			result["operations"].append(_site_operating_view(site))
	return result


func snapshot() -> Dictionary:
	var result := {"schema_id": R2_SCHEMA_ID if is_multi() else SCHEMA_ID, "config": config.duplicate(true), "day": day, "next_order": next_order, "next_shipment": next_shipment, "phase": phase, "actors": _actors.duplicate(true), "stock": _stocks.duplicate(true), "contracts": _contracts.duplicate(true), "work_queue": _work_queue.duplicate(true), "work_records": _work_records.duplicate(true), "wages": _wages.duplicate(true), "orders": _orders.duplicate(true), "shipments": _shipments.duplicate(true), "delivery_receipts": _delivery_receipts.duplicate(true), "transport": _transport.duplicate(true), "messages": _messages.duplicate(true), "receipts": _receipts.duplicate(true), "commands": _commands.duplicate(true), "needs": _needs.duplicate(true), "totals": _totals.duplicate(true), "relations": _relations.duplicate(true), "plans": _plans.duplicate(true), "site_state": _site_state.duplicate(true), "site_reports": _site_reports.duplicate(true), "firm_state": _firm_state.duplicate(true), "quote_state": _quote_state.duplicate(true), "job_postings": _job_postings.duplicate(true), "search_state": _search_state.duplicate(true), "request_window": _request_window.duplicate(true), "physical_totals": _physical_totals.duplicate(true)}
	if is_multi():
		result["firm_knowledge"] = _firm_knowledge.duplicate(true)
	if uses_host_accounts(): result["management"] = _management.duplicate(true)
	if uses_host_accounts():
		result["scope_requests"] = _scope_requests.duplicate(true)
		result["subject_activation"] = _subject_activation.duplicate(true)
		result["property_handovers"] = _property_handovers.duplicate(true)
	result["credit"] = _credit.snapshot()
	result["currency_exchange"] = _exchange.snapshot()
	result["assets"] = _assets.snapshot()
	if not _enterprise_changes.is_empty(): result["enterprise_changes"] = _enterprise_changes.duplicate(true)
	if not _employment_ends.is_empty(): result["employment_ends"] = _employment_ends.duplicate(true)
	if not _capital.projects.is_empty() or not _capital.changes.is_empty(): result["capital_formation"] = _capital.snapshot()
	result["cargo_fulfilment"] = _cargo_fulfilment.snapshot()
	result["shared_transport"] = _shared.snapshot()
	if not _capital_transport.tasks.is_empty(): result["capital_transport"]=_capital_transport.tasks.duplicate(true)
	result["stock_lots"] = _lots.snapshot()
	result["procurement_budget"] = _budgets.snapshot()
	if _costs.enabled: result["cost_allocation"] = _costs.snapshot()
	if config.has("service_market"): result["service_market"] = _service_market.snapshot()
	if config.has("lease_market"): result["lease_market"] = _leases.snapshot()
	if config.has("retail_sites"): result["retail"]=_retail.snapshot()
	if config.has("commercial_information"): result["commercial_information"]=_commercial.snapshot()
	if config.has("labor_market"): result["labor_market"]=_labor_market.snapshot()
	if config.has("local_quotation_experiment"): result["local_quotations"] = _local_quotes.snapshot()
	if config.has("supply_contracts"): result["supply_contracts"]=_supply.snapshot()
	return result

func restore(value: Dictionary) -> bool:
	value = value.duplicate(true)
	_labor_market.ready=false
	if not _local_quotes.restore(value.get("local_quotations"),value): return _fail(_local_quotes.error)
	if not _restore_business_lifecycles(value): return false
	if not _labor_market.restore(value.get("labor_market"),value): return _fail(_labor_market.error)
	if not _supply.restore(value.get("supply_contracts"),value): return _fail(_supply.error)
	if not _capital_transport.restore_shape(value): return _fail(_capital_transport.error)
	if not _capital.restore(value.get("capital_formation"), value): return _fail(_capital.error)
	if uses_host_accounts():
		if not value.has("scope_requests"): value["scope_requests"] = {}
		if not value.has("subject_activation"): value["subject_activation"] = {}
		if not value.has("property_handovers"): value["property_handovers"] = {}
		if not value["property_handovers"] is Dictionary: return _fail("Invalid property handover journal")
		_property_handovers = value["property_handovers"].duplicate(true)
		if not value["scope_requests"] is Dictionary or not value["subject_activation"] is Dictionary: return _fail("Invalid runtime native responsibility state")
		_subject_activation = value["subject_activation"].duplicate(true)
		_scope_requests = value["scope_requests"].duplicate(true)
		if not _valid_scope_lifecycle(value.get("commands", {})) or not _valid_property_handovers(value.get("commands", {})): return false
	if not _upgrade_legacy_contracts(value) or not _upgrade_transport(value) or not _upgrade_site_layout(value) or not _upgrade_operations(value):
		return false
	if uses_host_accounts() and value.has("management"):
		if value["management"] != {"scope_id": _management["scope_id"], "status": "ACTIVE", "activation_minute": 0}:
			return _fail("Native management lifecycle differs from its saved host responsibility")
	if not _cargo_fulfilment.restore(value.get("cargo_fulfilment"), value): return _fail("Invalid loss, consent, replacement or cargo payment references")
	if not _leases.restore(value.get("lease_market"),value): return _fail(_leases.error)
	if not _commercial.restore(value.get("commercial_information"),value): return _fail(_commercial.error)
	if not _service_market.restore(value.get("service_market"),value): return _fail(_service_market.error)
	if not _shared.restore(value.get("shared_transport"), value): return _fail("Invalid shared entries, handling labor or vehicle references")
	if not _capital_transport.validate(value): return _fail(_capital_transport.error)
	if not _retail.restore(value.get("retail"),value): return _fail(_retail.error)
	if not _assets.primary.prepare(value.get("assets",{}).get("primary")): return _fail(_assets.primary.error)
	if not _assets.distribution.prepare(value.get("assets",{}).get("distributions")): return _fail(_assets.distribution.error)
	if not _assets.call_market.prepare(value.get("assets",{}).get("call_market")): return _fail(_assets.call_market.error)
	if not _validate_saved(value):
		return false
	if not _wind_down.validate(value): return _fail(_wind_down.error)
	if not _valid_financial_history(value): return _fail("Invalid enterprise financial authorization history")
	var restored_credit := Credit.new()
	restored_credit.bind(_world.ledger_state)
	if not restored_credit.restore(value.get("credit"), value["commands"], _credit_subject_accounts(value["actors"]), _credit_information_dates(value), _world.game_clock.total_minutes()):
		return _fail(restored_credit.error)
	var restored_exchange := Exchange.new()
	restored_exchange.bind(_world.ledger_state, config)
	if not restored_exchange.restore(value.get("currency_exchange"), value["commands"], _world.game_clock.total_minutes()):
		return _fail(restored_exchange.error)
	var restored_assets := Assets.new()
	restored_assets.bind(_world.ledger_state, config, self)
	if not restored_assets.restore(value.get("assets"), value["commands"], _world.game_clock.total_minutes(), value):
		return _fail(restored_assets.error)
	if not _valid_financial_batches(value):
		return false
	_credit = restored_credit
	_exchange = restored_exchange
	_assets = restored_assets
	day = int(value["day"])
	next_order = int(value["next_order"])
	next_shipment = int(value["next_shipment"])
	phase = str(value["phase"])
	_actors = value["actors"].duplicate(true)
	if value.has("stock_lots"):
		var restored_lots := StockLots.new()
		restored_lots.configure(_goods, _actor_ids_from_spec())
		if not restored_lots.restore(value["stock_lots"], value["stock"], _good_units(), _physical_owners(), _world.spatial_catalog.place_ids(), _world.game_clock.total_minutes()): return _fail("Invalid native batch portions or projection")
		_lots = restored_lots
	else:
		_legacy_stock_boundary = value["stock"].duplicate(true)
		for subject: String in value["stock"]:
			if not uses_host_accounts() or not _declared_named(subject): _opening_stock(subject, value["stock"][subject], true)
		for cargo: Dictionary in value["shipments"].values():
			var o := value["orders"][cargo["order_id"]] as Dictionary
			if o["kind"] != "PERSONAL_FREIGHT": _lots.create("legacy_cargo:"+str(cargo["id"]), o["good"], _good_units()[o["good"]], cargo["quantity"], o["seller"], "CARGO|"+str(cargo["id"]), cargo["place_id"], -1, "LEGACY_QUANTITY_BOUNDARY_AGE_COST_UNKNOWN")
		for o: Dictionary in value["orders"].values():
			if int(o["pending"]) > 0 and o["kind"] != "PERSONAL_FREIGHT" and not _lots.reserve(o["id"], "SITE|"+str(o["seller_site"]), o["good"], o["pending"], _world.game_clock.total_minutes()): return _fail("Legacy stock cannot support its sales commitments")
	var extra_contracts:=_cargo_fulfilment.fee_contracts()
	extra_contracts.merge(_service_market.budget_contracts())
	extra_contracts.merge(_leases.budget_contracts())
	extra_contracts.merge(_capital.resale_budget_contracts())
	extra_contracts.merge(_capital_transport.budget_contracts())
	if not _budgets.restore(value.get("procurement_budget"), value["orders"], _world.ledger_state, extra_contracts): return _fail("Invalid procurement commitment/spending journal")
	_contracts = value["contracts"].duplicate(true)
	_work_queue = value["work_queue"].duplicate(true)
	_work_records = value["work_records"].duplicate(true)
	_wages = value["wages"].duplicate(true)
	_orders = value["orders"].duplicate(true)
	_shipments = value["shipments"].duplicate(true)
	_messages.assign(value["messages"].duplicate(true))
	_receipts = value["receipts"].duplicate(true)
	_commands = value["commands"].duplicate(true)
	_needs = value["needs"].duplicate(true)
	_totals = value["totals"].duplicate(true)
	_relations = value["relations"].duplicate(true)
	_plans = value["plans"].duplicate(true)
	_firm_state = value["firm_state"].duplicate(true)
	_site_state = value["site_state"].duplicate(true)
	_site_reports = value["site_reports"].duplicate(true)
	_quote_state = value["quote_state"].duplicate(true)
	_job_postings = value["job_postings"].duplicate(true)
	_search_state = value["search_state"].duplicate(true)
	_request_window = value["request_window"].duplicate(true)
	_physical_totals = value["physical_totals"].duplicate(true)
	_firm_knowledge = value["firm_knowledge"].duplicate(true) if is_multi() else {}
	_transport = value["transport"].duplicate(true)
	_delivery_receipts = value["delivery_receipts"].duplicate(true)
	_costs = CostAllocation.new()
	_costs.bind(self)
	if not _costs.restore(value.get("cost_allocation")): return _fail("Invalid native cost provenance or allocation references")
	_lots.costs = _costs
	if not is_multi():
		for firm: String in _firm_ids():
			_firm_knowledge[_primary_site(firm)] = _spec["sites"][_primary_site(firm)]["suppliers"].duplicate()
	_open_wages.clear()
	_orders_by_buyer.clear()
	_active_sales_by_key.clear()
	_recent_buy_commands.clear()
	_active_by_buyer.clear()
	_pending_by_key.clear()
	_wages_by_worker.clear()
	_future_wages.clear()
	_matured_wages.clear()
	_moving_shipments.clear()
	_shipments_by_order.clear()
	_shipments_by_destination_good.clear()
	for shipment: Dictionary in _shipments.values(): _index_shipment(shipment)
	_deliveries_by_order.clear()
	_order_days.clear()
	_delivery_days.clear()
	_pending_ids_by_key.clear()
	_incoming_by_key.clear()
	_collected_by_shipment.clear()
	_wage_days.clear()
	_open_wages_by_employer.clear()
	_repayment_days.clear()
	_employment_observations.clear()
	_cohort_search_day.clear()
	_regional_work.clear()
	_regional_trade.clear()
	_income_by_actor.clear()
	_decision_counts.clear()
	_accepted_travel_count = 0
	for entry: Dictionary in _commands.values(): _index_command_access(entry)
	for work: Dictionary in _work_records.values(): _index_employment_work(work)
	var wage_ids := _sorted_ids(_wages)
	wage_ids.sort_custom(_wage_less)
	for id: String in wage_ids:
		_observe_wage_payment(_wages[id], int(_wages[id]["paid"]))
		if int(_wages[id]["remaining"]) > 0:
			_open_wages.append(id)
			_index_wage(id)
		else: _index_wage_history(_wages[id])
	# Preserve original numeric creation order, not lexical order (10 before 2).
	_pending_orders.clear()
	_active_orders.clear()
	for number: int in range(1, next_order):
		var id := "order:" + str(number)
		_index_order(id)
		if int(_orders[id]["pending"]) > 0:
			_pending_orders.append(id)
		if int(_orders[id]["pending"]) + int(_orders[id]["transit"]) > 0:
			_active_orders.append(id)
	for receipt: Dictionary in _delivery_receipts.values(): _index_delivery(receipt)
	_prune_observation_indexes()
	_matured_wages.sort_custom(_wage_less)
	_management["status"] = "ACTIVE"
	_local_quotes.saved_receipts = {}
	error = ""
	return true

func _upgrade_operations(value: Dictionary) -> bool:
	for key: String in ["plans", "relations", "delivery_receipts", "physical_totals"]:
		if not value.get(key) is Dictionary:
			return _fail("Missing operating state")
	if not FormalLedgerState.valid_amount(value.get("day")):
		return _fail("Invalid operating date")
	var present: int = 0
	for key: String in ["quote_state", "job_postings", "search_state"]:
		if value.has(key):
			present += 1
	if present not in [0, 3]:
		return _fail("Incomplete operating state")
	if present == 0:
		if not _initial_quote_state(0).is_empty() or not config.get("supplier_search", []).is_empty() or not config.get("firm_operations", []).is_empty():
			return _fail("Missing established local price, hiring or supplier state")
		for firm: String in _firm_ids():
			if not _configured_legacy_recipe(firm):
				return _fail("Current facilities require their saved operating state")
		value["quote_state"] = _initial_quote_state(int(value["day"]))
		value["job_postings"] = _initial_job_postings()
		value["search_state"] = {}
	for site: Variant in value["plans"]:
		var plan: Variant = value["plans"][site]
		if not plan is Dictionary or not _spec["sites"].has(site):
			return _fail("Unknown site plan")
		if plan.has("activities"):
			continue
		if _spec["sites"][site]["activities"].size() != 1:
			return _fail("A legacy plan requires its single original activity")
		var activity := _spec["sites"][site]["activities"][0] as Dictionary
		if not plan.has("schedule"):
			if not FormalLedgerState.exact_fields(plan, ["day", "good", "desired", "actual", "labor_hours", "grain_used"]) or not FormalLedgerState.valid_amount(plan["desired"]) or not FormalLedgerState.valid_amount(plan["actual"]) or plan["grain_used"] != int(plan["actual"]) * int(activity["materials"].get("grain", 0)):
				return _fail("Legacy plan lost material responsibility")
			var schedule: Array[Dictionary] = []
			for offset: int in int(_operations_policy(site)["planning_horizon"]):
				schedule.append({"day": int(plan["day"]) + offset, "quantity": mini(int(_spec["sites"][site]["capacity"]), int(plan["desired"])) if offset == 0 else 0})
			plan["schedule"] = schedule
			plan.erase("grain_used")
		if not FormalLedgerState.exact_fields(plan, ["day", "good", "desired", "schedule", "actual", "labor_hours"]) or not activity["outputs"].has(plan["good"]):
			return _fail("Unknown legacy production plan")
		value["plans"][site] = {"day": plan["day"], "activities": {activity["id"]: {"desired": plan["desired"], "schedule": plan["schedule"], "actual": plan["actual"]}}, "labor_hours": plan["labor_hours"]}
	if int(value["day"]) > 0:
		for site: String in _site_ids():
			if int(_subject_activation.get(site, 0)) == int(value["day"])*1440: continue
			if not value["plans"].has(site) and _spec["sites"][site]["activities"].is_empty():
				if _configured_multi_sites(_owner(site)) or not _configured_legacy_recipe(_owner(site)):
					return _fail("Missing current site execution plan")
				var hours: int = 0
				for work: Variant in value["work_records"].values():
					if not work is Dictionary or not _spec["jobs"].has(work.get("job")) or not FormalLedgerState.valid_amount(work.get("hours")):
						return _fail("Invalid legacy work record")
					if work.get("day") == value["day"] and _spec["jobs"][work["job"]]["site_id"] == site:
						hours += int(work["hours"])
				value["plans"][site] = {"day": value["day"], "activities": {}, "labor_hours": hours}
	return true


func _delivery_relations(receipts: Dictionary, orders: Dictionary, dates: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var ids := _sorted_ids(receipts)
	ids.sort_custom(func(a: String, b: String) -> bool: return _receipt_less(receipts[a], receipts[b]))
	for id: String in ids:
		var receipt := receipts[id] as Dictionary
		var order := orders[receipt["order_id"]] as Dictionary
		if order["kind"] != "SALE":
			continue
		var key := _destination(order) + "|" + str(order["seller_site"]) + "|" + str(order["good"])
		if not result.has(key):
			result[key] = []
		result[key].append(id)
		if result[key].size() > COOPERATION_RECORD_LIMIT:
			result[key].pop_front()
		dates[key] = receipt["delivered_day"]
	return result

func _valid_locked_price(order: Dictionary) -> bool:
	if order.has("supply_contract_id"): return _supply.valid_order(order)
	if not _local_quotes.valid_sale_boundary(order): return false
	if not _local_quotes.rule(order["seller_site"],order["good"]).is_empty(): return _local_quotes.valid_locked_price(order)
	var policy := _price_policy(order["seller_site"], order["good"])
	if policy.is_empty() or policy["mode"] == "N2":
		return int(order["price"]) == int(_spec["sites"][order["seller_site"]]["prices"].get(order["good"], 0))
	return int(order["price"]) >= int(policy["minimum"]) and int(order["price"]) <= int(policy["maximum"]) and int(order["price"]) % int(policy["tick"]) == 0

func _valid_publication_price(site: String,good: String,price: int,minute: int) -> bool:
	# An announcement observes a seller's price. It has no buyer or order cursor.
	if not _local_quotes.rule(site,good).is_empty():
		var quote: Dictionary=_local_quotes.current(site,good,minute)
		return not quote.is_empty() and int(quote.price)==price
	var policy: Dictionary=_price_policy(site,good)
	if policy.is_empty() or policy.mode=="N2":return price==int(_spec.sites[site].prices.get(good,0))
	# Older N3 notices have no adopted observation. A zero initial tick-step
	# proves the price cannot ever change. Bounds alone prove no past price.
	var initial: int=int(_spec.sites[site].prices.get(good,0))
	var step: int=(initial*N3_STEP_PERCENT/100/int(policy.tick))*int(policy.tick)
	return step==0 and price==initial

func _upgrade_legacy_contracts(value: Dictionary) -> bool:
	# Legacy amounts have exactly the original default currency, regardless of
	# the actor's location. Unknown or partially added fields remain load errors.
	for key: String in ["contracts", "wages", "orders", "shipments"]:
		if not value.get(key) is Dictionary:
			return _fail("Missing saved contract container")
	for row: Variant in value["contracts"].values():
		if row is Dictionary and not row.has("denomination") and FormalLedgerState.exact_fields(row, ["job", "workers"]):
			row["denomination"] = FormalLedgerState.DENOMINATION
	for row: Variant in value["wages"].values():
		if row is Dictionary and not row.has("denomination") and FormalLedgerState.exact_fields(row, ["id", "worker", "employer", "hours", "amount", "remaining", "work_day", "due_day", "paid"]):
			row["denomination"] = FormalLedgerState.DENOMINATION
	for row: Variant in value["orders"].values():
		if row is Dictionary and not row.has("denomination") and FormalLedgerState.exact_fields(row, ["id", "buyer", "seller", "good", "quantity", "pending", "transit", "delivered", "cancelled", "price", "action_id", "accepted_day", "accepted_minute"]):
			if (not _spec["actors"].has(row["buyer"]) and not _spec["firms"].has(row["buyer"])) or not _spec["firms"].has(row["seller"]):
				return _fail("Legacy order party is unknown")
			row.merge({"denomination": FormalLedgerState.DENOMINATION, "buyer_account": _account(row["buyer"]), "seller_account": _account(row["seller"]), "carrier_account": "", "route_id": "edge:r2_paris_local", "from_place_id": PLACE, "to_place_id": PLACE, "delivery_delay": _delivery_delay(), "carrier": "", "freight_per_unit": 0})
	for row: Variant in value["shipments"].values():
		if row is Dictionary and not row.has("route_id") and FormalLedgerState.exact_fields(row, ["id", "order_id", "quantity", "dispatch_day", "arrival_day", "place_id"]):
			row.merge({"route_id": "edge:r2_paris_local", "destination_place_id": PLACE})
	return true


func _credit_subject_accounts(actors: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for actor: String in actors:
		result[actor] = actors[actor]["account_id"]
	for firm: String in _spec["firms"]:
		result[firm] = _account(firm)
	return result

func _upgrade_transport(value: Dictionary) -> bool:
	if not FormalLedgerState.valid_amount(value.get("day")):
		return _fail("Invalid saved transport day")
	if value.has("delivery_receipts"):
		return true
	for row: Variant in value["orders"].values():
		if not row is Dictionary:
			return _fail("Invalid saved order")
		if not row.has("route_legs"):
			if not FormalLedgerState.exact_fields(row, ["id", "buyer", "seller", "good", "quantity", "pending", "transit", "delivered", "cancelled", "price", "action_id", "accepted_day", "accepted_minute", "denomination", "buyer_account", "seller_account", "carrier_account", "route_id", "from_place_id", "to_place_id", "delivery_delay", "carrier", "freight_per_unit"]):
				return _fail("Unknown legacy direct transport contract")
			var edge: Dictionary = _all_routes().get(row["route_id"], {})
			if edge.is_empty() or row["carrier"] != edge["carrier"]:
				return _fail("Unknown legacy carrier or edge")
			row["route_legs"] = [{"edge_id": row["route_id"], "delay": row["delivery_delay"], "freight_per_unit": row["freight_per_unit"], "carrier_account": row["carrier_account"]}]
			for field: String in ["delivery_delay", "freight_per_unit", "carrier", "carrier_account"]:
				row.erase(field)
		if not FormalLedgerState.exact_fields(row, ["id", "buyer", "seller", "good", "quantity", "pending", "transit", "delivered", "cancelled", "price", "action_id", "accepted_day", "accepted_minute", "denomination", "buyer_account", "seller_account", "route_id", "from_place_id", "to_place_id", "route_legs"]) or (not _spec["actors"].has(row["buyer"]) and not _spec["firms"].has(row["buyer"])) or not _spec["firms"].has(row["seller"]) or not row["route_legs"] is Array or row["route_legs"].size() != 1:
			return _fail("Invalid legacy direct order responsibility")
		for field: String in ["accepted_day", "accepted_minute", "quantity", "pending", "transit", "delivered", "cancelled", "price"]:
			if not FormalLedgerState.valid_amount(row[field]):
				return _fail("Invalid legacy order amount or date")
		var route_order := row.duplicate(true) as Dictionary
		route_order.merge({"kind": "SALE", "seller_site": _primary_site(row["seller"]), "buyer_site": _primary_site(row["buyer"]) if _spec["firms"].has(row["buyer"]) else "", "need_category": "food" if _spec["actors"].has(row["buyer"]) else ""})
		if not _valid_order_route(route_order):
			return false
	for row: Variant in value["shipments"].values():
		if not row is Dictionary or row.has("stage"):
			return _fail("Legacy cargo requires its direct transport fields")
		if not FormalLedgerState.exact_fields(row, ["id", "order_id", "quantity", "dispatch_day", "arrival_day", "place_id", "destination_place_id", "route_id"]) or not value["orders"].has(row["order_id"]):
			return _fail("Unknown legacy shipment")
		var order := value["orders"][row["order_id"]] as Dictionary
		if row["route_id"] != order["route_id"] or row["destination_place_id"] != order["to_place_id"] or not FormalLedgerState.valid_amount(row["quantity"]) or not FormalLedgerState.valid_amount(row["dispatch_day"]) or not FormalLedgerState.valid_amount(row["arrival_day"]):
			return _fail("Legacy shipment path or dates differ from its contract")
		row.merge({"stage": "TRANSIT", "leg_index": 0, "ready_day": _earliest_dispatch(order), "leg_arrival_day": row["arrival_day"], "departures": [row["dispatch_day"]]})
		for field: String in ["dispatch_day", "arrival_day", "destination_place_id", "route_id"]:
			row.erase(field)
	# Earlier direct saves recorded final delivery only in the actual cash receipt.
	# Recover its one physical leg without launching cargo or executing payment.
	var delivered: Dictionary = {}
	for payment: Dictionary in _world.ledger_state.transactions():
		if payment["kind"] != "goods":
			continue
		var id := str(payment["transaction_id"]).trim_prefix("r1:goods:")
		var order: Variant = value["orders"].get(payment["reference_id"])
		if not order is Dictionary or not FormalLedgerState.valid_amount(order.get("price")) or int(order["price"]) <= 0 or int(payment["amount"]) % int(order["price"]) != 0 or delivered.has(id) or value["shipments"].has(id):
			return _fail("Legacy delivery does not identify unique physical cargo")
		var arrived: int = int(payment["effective_minute"]) / 1440
		delivered[id] = {"id": id, "order_id": order["id"], "quantity": int(payment["amount"]) / int(order["price"]), "departures": [arrived - _travel_days(order["route_legs"])], "delivered_day": arrived}
	value["delivery_receipts"] = delivered
	var edges: Dictionary = {}
	for row: Dictionary in _all_routes().values():
		edges[row["id"]] = {"period": value["day"], "input_used": 0, "dispatched": 0, "holds": {}, "capacity": row["capacity"], "capacity_action": ""}
	for order: Dictionary in value["orders"].values():
		var edge := edges[order["route_legs"][0]["edge_id"]] as Dictionary
		if int(order["accepted_day"]) == int(value["day"]):
			edge["input_used"] = int(edge["input_used"]) + int(order["quantity"]) - int(order["cancelled"])
		if int(order["pending"]) > 0:
			edge["holds"][order["id"]] = {"period": order["accepted_day"], "quantity": order["pending"]}
	var physical: Array = value["shipments"].values()
	physical.append_array(delivered.values())
	var counted: Dictionary = {}
	for cargo: Dictionary in physical:
		var order := value["orders"][cargo["order_id"]] as Dictionary
		if cargo.has("departure_quantities") and counted.has(_cargo_origin_id(cargo)): continue
		if cargo.has("departure_quantities"): counted[_cargo_origin_id(cargo)] = true
		for index: int in cargo["departures"].size():
			if cargo["departures"][index] == value["day"]:
				var edge := edges[order["route_legs"][index]["edge_id"]] as Dictionary
				edge["dispatched"] = int(edge["dispatched"]) + int(cargo["quantity"])
	var inputs: int = 0
	var old_edges: Dictionary = {}
	if is_multi():
		if not value.get("transport") is Dictionary:
			return _fail("Missing legacy shared transport")
		var old := value["transport"] as Dictionary
		if config.has("routes") and FormalLedgerState.exact_fields(old, ["edges"]) and old["edges"] is Dictionary:
			old_edges = old["edges"]
		elif not config.has("routes"):
			old_edges["edge:r2_paris_local"] = old
		if old_edges.size() != edges.size():
			return _fail("Unknown legacy transport container")
	for id: String in edges:
		var edge := edges[id] as Dictionary
		inputs += int(edge["input_used"])
		if is_multi():
			var old: Variant = old_edges.get(id)
			if not old is Dictionary or not FormalLedgerState.exact_fields(old, ["edge_id", "period", "input_used", "dispatch_day", "dispatched", "holds"]) or old["edge_id"] != id or old["period"] != value["day"] or old["dispatch_day"] != value["day"] or old["input_used"] != edge["input_used"] or old["dispatched"] != edge["dispatched"] or old["holds"] != edge["holds"]:
				return _fail("Legacy edge responsibilities conflict")
	if not FormalLedgerState.valid_amount(value.get("capacity_used")) or int(value["capacity_used"]) != inputs:
		return _fail("Legacy transport input responsibility conflict")
	value.erase("capacity_used")
	var nodes: Dictionary = {}
	for row: Dictionary in config.get("transport_nodes", []):
		nodes[row["place_id"]] = {"dispatched": 0}
	value["transport"] = {"edges": edges, "nodes": nodes}
	return true


func _credit_information_dates(value: Dictionary) -> Dictionary:
	# Existing delivered business messages prove when a public lender was known.
	var result: Dictionary = {}
	for receipt: Dictionary in value["receipts"].values():
		if receipt["kind"]=="capital_offer": continue
		var actor := _owner(str(receipt["actor"]))
		var lender := str(_job(receipt["candidate"])["employer"]) if receipt["kind"] in ["job", "job_posting"] else str(str(receipt["candidate"]).split("|")[0])
		if not result.has(actor):
			result[actor] = {}
		var minute := int(receipt.get("observed_minute", int(receipt["delivery_day"])*1440))
		result[actor][lender] = mini(int(result[actor].get(lender, minute)), minute)
	return result

func _index_order(id: String) -> void:
	var order := _orders[id] as Dictionary
	_observe_order_acceptance(order)
	var buyer := str(order["buyer"])
	if not _orders_by_buyer.has(buyer):
		_orders_by_buyer[buyer] = []
		_active_by_buyer[buyer] = []
	_orders_by_buyer[buyer].append(id)
	if int(order["pending"]) + int(order["transit"]) > 0:
		_active_by_buyer[buyer].append(id)
	var key := str(order["seller_site"]) + "|" + str(order["good"])
	if order["kind"]=="SALE" and int(order["pending"])+int(order["transit"])>0:
		if not _active_sales_by_key.has(key):_active_sales_by_key[key]={}
		_active_sales_by_key[key][id]=true
	_pending_by_key[key] = int(_pending_by_key.get(key, 0)) + int(order["pending"])
	if int(order["pending"]) > 0:
		if not _pending_ids_by_key.has(key): _pending_ids_by_key[key] = {}
		_pending_ids_by_key[key][id] = true
	_change_order_observation(order, int(order["quantity"]) - int(order["cancelled"]))
	if order["kind"] != "PERSONAL_FREIGHT": _change_incoming(order, int(order["pending"]) + int(order["transit"]))

func _observation_start(site: String, good: String) -> int:
	var window := _request_retention_window(site)
	window = maxi(window, int(_price_policy(site, good).get("window_days", 0)))
	return maxi(0, day - window + 1)

func _change_order_observation(order: Dictionary, quantity: int) -> void:
	if order["kind"] != "SALE" or int(order["accepted_day"]) < _observation_start(order["seller_site"], order["good"]): return
	var key := str(order["seller_site"]) + "|" + str(order["good"])
	if not _order_days.has(key): _order_days[key] = {}
	var date := int(order["accepted_day"])
	_order_days[key][date] = int(_order_days[key].get(date, 0)) + quantity

func _change_incoming(order: Dictionary, quantity: int) -> void:
	var key := _destination(order) + "|" + str(order["good"])
	_incoming_by_key[key] = int(_incoming_by_key.get(key, 0)) + quantity
	if _incoming_by_key[key] == 0: _incoming_by_key.erase(key)

func _index_shipment(shipment: Dictionary) -> void:
	if int(shipment["quantity"]) <= 0: return
	_moving_shipments[shipment["id"]] = true
	var order := _orders[shipment["order_id"]] as Dictionary
	var order_id := str(order["id"])
	var key := _destination(order) + "|" + str(order["good"])
	if not _shipments_by_order.has(order_id): _shipments_by_order[order_id] = {}
	if not _shipments_by_destination_good.has(key): _shipments_by_destination_good[key] = {}
	_shipments_by_order[order_id][shipment["id"]] = true
	_shipments_by_destination_good[key][shipment["id"]] = true

func _index_delivery(receipt: Dictionary) -> void:
	_observe_delivery_revenue(receipt)
	var order_id := str(receipt["order_id"])
	if not _deliveries_by_order.has(order_id): _deliveries_by_order[order_id] = []
	_deliveries_by_order[order_id].append(receipt["id"])
	var shipment_id := str(receipt.get("shipment_id", receipt["id"]))
	if _shipments.has(shipment_id): _collected_by_shipment[shipment_id] = int(_collected_by_shipment.get(shipment_id, 0)) + int(receipt["quantity"])
	else: _collected_by_shipment.erase(shipment_id)
	var order := _orders[receipt["order_id"]] as Dictionary
	if order["kind"] != "SALE" or int(receipt["delivered_day"]) < _observation_start(order["seller_site"], order["good"]): return
	var key := str(order["seller_site"]) + "|" + str(order["good"])
	if not _delivery_days.has(key): _delivery_days[key] = {}
	var date := int(receipt["delivered_day"])
	if not _delivery_days[key].has(date): _delivery_days[key][date] = {"quantity": 0, "count": 0}
	var value := _delivery_days[key][date] as Dictionary
	value["quantity"] = int(value["quantity"]) + int(receipt["quantity"])
	value["count"] = int(value["count"]) + 1

func _index_command_access(entry: Dictionary) -> void:
	var candidate := entry["envelope"]["command"] as Dictionary
	if candidate["kind"]=="buy":
		var observer: String=entry.envelope.actor
		if not _recent_buy_commands.has(observer):_recent_buy_commands[observer]=[]
		_recent_buy_commands[observer].append(candidate.action_id)
		_recent_buy_commands[observer].sort_custom(func(a: String,b: String):
			var first: int=int(_commands[a].envelope.command.minute);var second: int=int(_commands[b].envelope.command.minute)
			return first<second if first!=second else a<b)
		if _recent_buy_commands[observer].size()>64:_recent_buy_commands[observer].pop_front()
	if candidate["kind"] == "apply":
		var owner := str(entry["envelope"]["actor"])
		_cohort_search_day[owner] = maxi(int(_cohort_search_day.get(owner, -30)), int(candidate["minute"])/1440)
	if not entry["result"]["accepted"]: return
	var envelope := entry["envelope"] as Dictionary
	var command := envelope["command"] as Dictionary
	var actor := str(envelope["actor"])
	if command["kind"] == "repay_loan":
		_repayment_days[actor] = maxi(int(_repayment_days.get(actor, -1)), int(command["minute"]) / 1440)
	elif command["kind"] == "apply":
		var key := actor + "|" + str(command["payload"]["job_id"])
		var minute := int(command["minute"])
		if minute >= int(_employment_observations.get(key, {}).get("accepted_minute", -1)):
			_employment_observations[key] = {"accepted_minute": minute, "worked_hours": 0}
	elif command["kind"] == "travel": _accepted_travel_count += 1

func _work_observation_row(worker: String, employer: String, job: String) -> Dictionary:
	var region := _region_for(str(_job(job)["place"]))
	var key := region+"|"+worker+"|"+employer
	if not _regional_work.has(key): _regional_work[key] = {"region": region, "worker": worker, "employer": employer, "hours": 0, "paid": {}}
	return _regional_work[key]

func _observe_wage_payment(claim: Dictionary, amount: int) -> void:
	if amount <= 0: return
	var worker := str(claim["worker"])
	var currency := str(claim["denomination"])
	var row := _work_observation_row(worker, claim["employer"], _work_records[claim["id"]]["job"])
	row["paid"][currency] = int(row["paid"].get(currency, 0))+amount
	if not _income_by_actor.has(worker): _income_by_actor[worker] = {}
	_income_by_actor[worker][currency] = int(_income_by_actor[worker].get(currency, 0))+amount

func _trade_observation_row(region: String, buyer: String, seller: String) -> Dictionary:
	var key := region+"|"+buyer+"|"+seller
	if not _regional_trade.has(key): _regional_trade[key] = {"region": region, "buyer": buyer, "seller": seller, "accepted": 0, "revenue": {}}
	return _regional_trade[key]

func _observe_order_acceptance(order: Dictionary) -> void:
	var row := _trade_observation_row(_region_for(order["to_place_id"]), order["buyer"], order["seller"])
	row["accepted"] += 1

func _observe_delivery_revenue(receipt: Dictionary) -> void:
	var order := _orders[receipt["order_id"]] as Dictionary
	if order["kind"] != "SALE": return
	var row := _trade_observation_row(_region_for(_place(order["seller_site"])), order["buyer"], order["seller"])
	var currency := str(order["denomination"])
	row["revenue"][currency] = int(row["revenue"].get(currency, 0))+int(receipt["quantity"])*int(order["price"])

func _index_employment_work(work: Dictionary) -> void:
	var summary := _work_observation_row(work["actor"], _job(work["job"])["employer"], work["job"])
	summary["hours"] += int(work["hours"])
	var key := str(work["actor"]) + "|" + str(work["job"])
	var observed := _employment_observations.get(key, {}) as Dictionary
	if not observed.is_empty() and int(work["day"]) * 1440 > int(observed["accepted_minute"]): observed["worked_hours"] = int(observed["worked_hours"]) + int(work["hours"])

func _index_wage_history(claim: Dictionary) -> void:
	var date := int(claim["work_day"])
	if date < day - 29: return
	var employer := str(claim["employer"])
	if not _wage_days.has(employer): _wage_days[employer] = {}
	if not _wage_days[employer].has(date): _wage_days[employer][date] = {}
	var currency := str(claim["denomination"])
	_wage_days[employer][date][currency] = int(_wage_days[employer][date].get(currency, 0)) + int(claim["amount"])

func _prune_observation_indexes() -> void:
	for index: Dictionary in [_order_days, _delivery_days]:
		for key: String in index.keys():
			var parts := key.split("|")
			var start := _observation_start(parts[0], parts[1])
			for date: int in index[key].keys():
				if date < start: index[key].erase(date)
			if index[key].is_empty(): index.erase(key)
	for employer: String in _wage_days:
		for date: int in _wage_days[employer].keys():
			if date < day - 29: _wage_days[employer].erase(date)

func _index_wage(id: String) -> void:
	_index_wage_history(_wages[id])
	var claim := _wages[id] as Dictionary
	if not _open_wages_by_employer.has(claim["employer"]): _open_wages_by_employer[claim["employer"]] = {}
	_open_wages_by_employer[claim["employer"]][id] = true
	var worker := str(claim["worker"])
	if not _wages_by_worker.has(worker):
		_wages_by_worker[worker] = []
	_wages_by_worker[worker].append(id)
	var due := int(claim["due_day"])
	if due <= day:
		_matured_wages.append(id)
	else:
		if not _future_wages.has(due):
			_future_wages[due] = []
		_future_wages[due].append(id)

func _wage_less(a: String, b: String) -> bool:
	if _wages[a]["work_day"] != _wages[b]["work_day"]: return int(_wages[a]["work_day"]) < int(_wages[b]["work_day"])
	if _wages[a]["worker"] != _wages[b]["worker"]: return str(_wages[a]["worker"]) < str(_wages[b]["worker"])
	return str(_work_records[a]["job"]) < str(_work_records[b]["job"])


func _validate_saved(value: Dictionary) -> bool:
	if not _host_firm_bindings_valid():
		return false
	var fields: Array[String] = []
	fields.assign(snapshot().keys())
	for key: String in ["credit", "currency_exchange", "assets", "management", "stock_lots", "procurement_budget", "shared_transport", "cargo_fulfilment", "cost_allocation", "service_market", "lease_market", "retail", "commercial_information", "labor_market", "capital_transport", "supply_contracts"]:
		if not value.has(key):
			fields.erase(key)
	# Older saves carry the research event cursor; accept it without runtime state.
	if value.has("sequence"):
		if not FormalLedgerState.valid_amount(value["sequence"]):
			return _fail("Invalid legacy R1 event cursor")
		fields.append("sequence")
	if not FormalLedgerState.exact_fields(value, fields) or value.get("schema_id") != (R2_SCHEMA_ID if is_multi() else SCHEMA_ID) or value.get("config") != config or value.get("phase") != "READY":
		return _fail("R1 save version, configuration or safe phase mismatch")
	for key: String in ["day", "next_order", "next_shipment"]:
		if not FormalLedgerState.valid_amount(value[key]):
			return _fail("Invalid R1 cursor")
	if int(value["day"]) != _world.game_clock.current_day() or int(value["next_order"]) < 1 or int(value["next_shipment"]) < 1:
		return _fail("R1 clock, ID or capacity conflict")
	for key: String in fields:
		if key in ["schema_id", "config", "day", "sequence", "next_order", "next_shipment", "phase"]:
			continue
		if key == "messages":
			if not value[key] is Array:
				return _fail("Invalid R1 messages")
		elif not value[key] is Dictionary:
			return _fail("Invalid R1 state container")
	var actors := value["actors"] as Dictionary
	var stock := value["stock"] as Dictionary
	if is_multi():
		for id: String in EconomySliceConfig.named_ids(config):
			if not _world.person_overlay.has_person(id):
				return _fail("Economic person is missing from the host overlay")
		if not _population_bindings_valid():
			return false
		for actor: String in _spec["actors"]:
			var row := _spec["actors"][actor] as Dictionary
			if row["control"] == "player" and _world.player_state.player_id() != actor:
				return _fail("Runtime control switching is unsupported")
			if row["kind"] == "cohort" and int(row["population_start"]) + int(row["members"]) > int(_world.population_state.unit(_population_unit(actor))["remaining_background_population"]):
				return _fail("Cohort no longer fits host background responsibility")
	var expected_actors := _sorted_ids(_spec["actors"])
	if actors.size() != expected_actors.size() or stock.size() != actors.size() + _spec["sites"].size() or value["totals"].size() != actors.size():
		return _fail("Missing R1 subject")
	for actor: String in expected_actors:
		if not actors.has(actor) or not actors[actor] is Dictionary or not stock.has(actor) or not value["totals"].has(actor):
			return _fail("Invalid R1 actor reference")
		var record := actors[actor] as Dictionary
		var specification := _spec["actors"][actor] as Dictionary
		if specification["kind"] == "named":
			var person := _world.person_overlay.person(actor)
			if not bool(person.get("alive", false)) or not _world.spatial_catalog.has_place(str(person.get("current_place_id", ""))) or person.get("population_territory_id") != _world.population_state.unit_for_person(actor):
				return _fail("R1 actor lacks an admitted current host place/population identity")
		var account_id := str(specification["account_id"])
		var members := int(specification["members"])
		if not FormalLedgerState.exact_fields(record, ["members", "control", "account_id", "known_jobs", "known_suppliers"]) or record["account_id"] != account_id or record["members"] != members or typeof(record["members"]) != TYPE_INT or record["control"] != specification["control"] or not record["known_jobs"] is Array or not record["known_suppliers"] is Array or _world.ledger_state.account(account_id).get("owner_id") != actor or _world.ledger_state.account(account_id).get("role") != ("personal_cash" if specification["kind"] == "named" else "r1_cohort"):
			return _fail("R1 population/account/control mismatch")
		if not _valid_need_totals(value["totals"][actor], actor, _managed_days(actor, int(value["day"]))):
			return _fail("Invalid household category totals")

	for actor: Variant in stock:
		if not actor is String or not stock[actor] is Dictionary or not FormalLedgerState.exact_fields(stock[actor], _goods) or (not actors.has(actor) and not _spec["sites"].has(actor)):
			return _fail("Invalid R1 inventory subject or goods")
		for amount: Variant in stock[actor].values():
			if not FormalLedgerState.valid_amount(amount):
				return _fail("Negative or invalid R1 inventory")
	var received: Dictionary = {}
	for id: Variant in value["receipts"]:
		var message: Variant = value["receipts"][id]
		if not message is Dictionary or not _valid_message(message, actors) or message["kind"] == "site_report" or message["id"] != id or int(message["delivery_day"]) > int(value["day"]):
			return _fail("Invalid or future received message")
		if message["kind"] in ["job", "supplier"] and not message.has("source"):
			received[id] = true
	var pending_messages: Dictionary = {}
	for message: Variant in value["messages"]:
		if not message is Dictionary or not _valid_message(message, actors) or int(message["observed_day"]) > int(value["day"]) or int(message["delivery_day"]) <= int(value["day"]) or (received.has(message["id"]) and message["kind"] != "job_posting") or pending_messages.has(message["id"]) or (message["kind"] == "site_report" and int(message["order_cursor"]) > int(value["next_order"])):
			return _fail("Duplicate or invalid pending message")
		pending_messages[message["id"]] = true
	for info: Dictionary in _spec["information"]:
		var id := "message:" + str(info["actor"]) + ":" + str(info["kind"]) + ":" + str(info["candidate"])
		if not received.has(id) and not pending_messages.has(id):
			return _fail("Addressed initial information was lost")
	for actor: String in expected_actors:
		for field: String in ["known_jobs", "known_suppliers"]:
			var known: Array = []
			for message: Dictionary in value["receipts"].values():
				if message["actor"] == actor and ((field == "known_jobs" and message["kind"] in ["job", "job_posting"]) or (field == "known_suppliers" and message["kind"] == "supplier")) and not known.has(message["candidate"]):
					known.append(message["candidate"])
			known.sort()
			if known != actors[actor][field]:
				return _fail("R1 knowledge has no received provenance")
	if is_multi():
		if value["firm_knowledge"].size() != _spec["sites"].size():
			return _fail("Missing site knowledge")
		for site: String in _site_ids():
			var known: Array = []
			for message: Dictionary in value["receipts"].values():
				if _inventory_key(message["actor"]) == site and message["kind"] == "supplier" and not known.has(message["candidate"]):
					known.append(message["candidate"])
			known.sort()
			if known != value["firm_knowledge"].get(site):
				return _fail("Site information has no received provenance")

	for actor: Variant in value["contracts"]:
		if not actors.has(actor) or not _valid_employment_container(value["contracts"][actor], actor, actors[actor]["known_jobs"], value["commands"]): return _fail("Invalid R1 employment, worker allocation or qualification")
	for job_id: String in _sorted_ids(_spec["jobs"]):
		var occupied: int = 0
		for contract: Dictionary in _all_contract_rows(value["contracts"]):
			if contract["job"] == job_id:
				occupied += int(contract["workers"])
		if occupied > int(value["job_postings"].get(job_id, {}).get("positions", -1)):
			return _fail("R1 vacancy oversubscribed")
	for id: Variant in value["commands"]:
		var entry: Variant = value["commands"][id]
		var command_fields: Array[String] = ["envelope", "result"]
		if is_multi():
			command_fields.append("source")
		if not id is String or _world.military_state.active_actions.has(id) or not entry is Dictionary or not FormalLedgerState.exact_fields(entry, command_fields) or not entry["envelope"] is Dictionary or not FormalLedgerState.exact_fields(entry["envelope"], ["actor", "command"]) or not entry["result"] is Dictionary or (not actors.has(entry["envelope"].get("actor")) and not _spec["firms"].has(entry["envelope"].get("actor"))) or not entry["envelope"].get("command") is Dictionary:
			return _fail("Invalid R1 command archive")
		var command := entry["envelope"]["command"] as Dictionary
		if not FormalLedgerState.exact_fields(command, ["action_id", "minute", "kind", "payload"]) or command["action_id"] != id or typeof(command["minute"]) != TYPE_INT or int(command["minute"]) < 0 or int(command["minute"]) > _world.game_clock.total_minutes() or not command["kind"] is String or not command["payload"] is Dictionary or not entry["result"].get("accepted") is bool:
			return _fail("Invalid R1 idempotency record")
		if command["kind"] in ["store_goods", "withdraw_goods"] and entry["result"]["accepted"]:
			var payload := command["payload"] as Dictionary
			var owner := str(entry["envelope"]["actor"])
			if not _declared_named(owner) or not FormalLedgerState.exact_fields(payload, ["good", "quantity", "place_id"]) or payload["good"] not in _goods or not payload["place_id"] is String or not FormalLedgerState.valid_amount(payload["quantity"]) or int(payload["quantity"]) <= 0 or _personal_storage_site(payload["place_id"], payload["good"]).is_empty(): return _fail("Saved custody action lacks a permitted site")
			var store: bool = command["kind"] == "store_goods"
			var key := "STORED|" + str(payload["place_id"])
			if not _valid_custody_fact(entry["result"].get("custody_fact"), owner, payload["good"], payload["quantity"], "CARRIED" if store else key, key if store else "CARRIED", id, command["kind"], command["minute"]) or entry["result"]["custody_fact"]["activity_place_id"] != payload["place_id"]: return _fail("Saved custody action loses original lots")
		if command["kind"] == "cancel" and entry["result"]["accepted"] and entry["result"].has("custody_fact"):
			var order: Dictionary = value["orders"].get(command["payload"].get("order_id"), {})
			if order.is_empty() or order["kind"] != "PERSONAL_FREIGHT" or entry["envelope"]["actor"] != order["buyer"] or not _valid_custody_fact(entry["result"]["custody_fact"], order["buyer"], order["good"], order["cancelled"], "FREIGHT|" + str(order["id"]), "STORED|" + str(order["from_place_id"]), id, "freight_cancel", command["minute"]): return _fail("Cancelled freight loses its original source custody")
		if int(command["minute"]) < int(_subject_activation.get(entry["envelope"]["actor"], 0)): return _fail("Action precedes its subject admission")
		if not _command_within_management_interval(entry): return _fail("Economic command follows the end of its native responsibility")
		if not is_multi() and not actors.has(entry["envelope"]["actor"]) and command["kind"] not in ["buy", "transfer_goods", "set_activity_enabled", "set_site_status", "set_firm_operating"] and command["kind"] not in Credit.ACTIONS and command["kind"] not in Exchange.ACTIONS and command["kind"] not in Assets.ACTIONS:
			return _fail("Unsupported R1 firm action record")
		if not is_multi() and _spec["firms"].has(entry["envelope"]["actor"]) and command["kind"] == "buy" and not str(id).begins_with("auto:" + str(entry["envelope"]["actor"]) + ":"):
			return _fail("Firm purchase lost its internal action source")
		if command["kind"] in Credit.ACTIONS or command["kind"] in Exchange.ACTIONS or command["kind"] in Assets.ACTIONS:
			var actor := str(entry["envelope"]["actor"])
			var control := str(actors[actor]["control"]) if actors.has(actor) else "automatic"
			var delegated: bool=_delegated_firm_credit(value,entry)
			if not entry["result"].get("reason") is String or control == "dormant" or (control == "player" and actor != _world.player_state.player_id()) or (control != "player" and not str(id).begins_with("auto:" + actor + ":") and not delegated):
				return _fail("Financial action authority conflict")
			if command["kind"] == "offer_credit" and control != "player" and entry["result"]["accepted"] and not _configured_credit_offer(actor, command) and not delegated:
				return _fail("Saved lending terms differ from the lender's policy")
		if is_multi():
			var actor := str(entry["envelope"]["actor"])
			var source := "firm" if _spec["firms"].has(actor) else str(actors[actor]["control"])
			if entry["source"] != source or source == "dormant" or (source != "player" and not str(id).begins_with("auto:" + actor + ":") and not _delegated_firm_credit(value,entry)) or (source == "player" and actor != _world.player_state.player_id()):
				return _fail("Command authority provenance conflict")
	for actor: Variant in value["work_queue"]:
		if not _valid_work_queue(value, actor): return _fail("Invalid pending aggregate or named labor interval")
	var expected_reservations: Dictionary = {}
	var orders := value["orders"] as Dictionary
	if orders.size() != int(value["next_order"]) - 1:
		return _fail("R1 duplicate/missing order IDs")
	for number: int in range(1, int(value["next_order"])):
		var id := "order:" + str(number)
		if not orders.get(id) is Dictionary:
			return _fail("Missing R1 order ID")
		var order := orders[id] as Dictionary
		if not EconomySliceConfig._fields(order, ["id", "kind", "buyer", "seller", "buyer_site", "seller_site", "need_category", "good", "quantity", "pending", "transit", "delivered", "cancelled", "price", "action_id", "accepted_day", "accepted_minute", "denomination", "buyer_account", "seller_account", "route_id", "from_place_id", "to_place_id", "route_legs"], ["custody_fact", "source_custody_site", "destination_custody_site", "supply_contract_id"]) or order["id"] != id or not order["buyer_site"] is String or not order["seller_site"] is String or not stock.has(_destination(order)) or (not _spec["firms"].has(order["seller"]) and order["kind"] != "PERSONAL_FREIGHT") or order["good"] not in _goods:
			return _fail("Order site or goods references are invalid")
		for key: String in ["quantity", "pending", "transit", "delivered", "cancelled", "price", "accepted_day", "accepted_minute"]:
			if not FormalLedgerState.valid_amount(order[key]):
				return _fail("Invalid order amount")
		if int(order["quantity"]) <= 0 or int(order["accepted_day"]) > int(value["day"]) or int(order["accepted_minute"]) > _world.game_clock.total_minutes() or int(order["quantity"]) != int(order["pending"]) + int(order["transit"]) + int(order["delivered"]) + int(order["cancelled"]) or not _valid_order_route(order) or not _valid_order_action(value, order):
			return _fail("Order responsibility, route or accepted action conflict")

		if int(order["accepted_minute"]) < maxi(int(_subject_activation.get(order["buyer"], 0)), maxi(int(_subject_activation.get(order["seller"], 0)), int(_subject_activation.get(order["seller_site"], 0)))): return _fail("Order precedes its operating ownership")
		var amount := (int(order["pending"]) + int(order["transit"])) * (int(order["price"]) + _freight(order["route_legs"]))
		if amount > 0:
			var account_id := str(order["buyer_account"])
			expected_reservations[id] = {"account_id": account_id, "amount": amount}
	expected_reservations.merge(_supply.cash_reservations())
	expected_reservations.merge(_service_market.cash_reservations())
	expected_reservations.merge(_leases.cash_reservations())
	expected_reservations.merge(_capital.resale_cash_reservations())
	expected_reservations.merge(_capital_transport.reservations())
	if config.has("equity_call_market"): expected_reservations.merge(_assets.call_market.reservations())
	if config.has("equity_primary"): expected_reservations.merge(_assets.primary.reservations())
	if config.has("equity_distribution"): expected_reservations.merge(_assets.distribution.reservations())
	if _world.ledger_state.snapshot()["r1_reservations"] != expected_reservations:
		return _fail("R1 order reservations differ from host Ledger")
	if not _validate_cargo_records(value, orders):
		return false
	var claim_hours: Dictionary = {}
	var claim_income: Dictionary = {}
	for id: Variant in value["wages"]:
		var claim: Variant = value["wages"][id]
		var work: Variant = value["work_records"].get(id)
		var historical := _employment_for_work(value, work) if work is Dictionary else {}
		if not id is String or not claim is Dictionary or not work is Dictionary or not FormalLedgerState.exact_fields(claim, ["id", "worker", "employer", "hours", "amount", "remaining", "work_day", "due_day", "paid", "denomination"]) or not EconomySliceConfig._fields(work, ["actor", "job", "hours", "day", "action_id"],["employment_action_id"]) or claim["id"] != id or not actors.has(claim["worker"]) or work["actor"] != claim["worker"] or _job(str(work["job"])).get("employer") != claim["employer"] or claim["denomination"] != _job(str(work["job"])).get("denomination"):
			return _fail("R1 wage has no real work or subject")
		for key: String in ["hours", "amount", "remaining", "work_day", "due_day", "paid"]:
			if not FormalLedgerState.valid_amount(claim[key]):
				return _fail("Invalid R1 wage quantity")
		if id != _work_id(int(claim["work_day"]), str(claim["worker"]), str(work["job"])) or int(claim["work_day"]) < 1 or int(claim["work_day"]) > int(value["day"]) or work["day"] != claim["work_day"] or work["hours"] != claim["hours"] or historical.is_empty() or historical.get("job") != work["job"] or int(claim["hours"]) <= 0 or int(claim["hours"]) > int(_labor_market.contract_job(historical)["hours"]) * int(historical["workers"]) or int(claim["amount"]) != int(claim["hours"]) * int(_labor_market.contract_job(historical)["wage_per_hour"]) or int(claim["paid"]) + int(claim["remaining"]) != int(claim["amount"]) or int(claim["due_day"]) != int(claim["work_day"]) + int(_labor_market.contract_job(historical).get("wage_delay",_wage_delay(work["job"]))):
			return _fail("R1 work/wage quantity or date conflict")
		if not _accepted_command(value, work["actor"], work["action_id"], "work"):
			return _fail("R1 wage work lacks accepted action")
		var work_command := value["commands"][work["action_id"]]["envelope"]["command"] as Dictionary
		if uses_host_accounts() and (int(work_command["minute"]) >= int(work["day"]) * 1440 or int(claim["hours"]) > ((int(work["day"]) * 1440 - int(work_command["minute"])) / 60) * int(historical["workers"])):
			return _fail("Saved actual work exceeds its elapsed formal time")
		if int(work_command["minute"]) < maxi(int(_subject_activation.get(work["actor"], 0)), int(_subject_activation.get(_job(work["job"])["site_id"], 0))): return _fail("Labor precedes its operating ownership")
		var work_payload := work_command["payload"] as Dictionary
		if typeof(work_payload.get("hours")) != TYPE_INT or work_payload["hours"] != claim["hours"] or (not _cohort_profile(work["actor"]).is_empty() and work_payload.get("job_id") != work["job"]):
			return _fail("R1 accepted labor differs from actual work")
		claim_hours[claim["worker"]] = int(claim_hours.get(claim["worker"], 0)) + int(claim["hours"])
		if claim["denomination"] == FormalLedgerState.DENOMINATION:
			claim_income[claim["worker"]] = int(claim_income.get(claim["worker"], 0)) + int(claim["paid"])
	if value["work_records"].size() != value["wages"].size():
		return _fail("Unpaired R1 work and wage")
	var paid: Dictionary = {}
	var delivered_money: Dictionary = {}
	var freight_money: Dictionary = {}
	var expected_freight: Dictionary = {}
	for cargo: Dictionary in value["delivery_receipts"].values():
		var order := orders[cargo["order_id"]] as Dictionary
		for leg: Dictionary in _delivery_legs(cargo["id"], order, int(cargo["quantity"])):
			if leg["kind"] == "freight":
				var expected := leg.duplicate(true)
				expected.merge({"denomination": order["denomination"], "effective_minute": _delivery_minute(cargo), "basis": "GENERATED_SIMULATION_ASSUMPTION"})
				expected_freight[leg["transaction_id"]] = expected
	for transaction: Dictionary in _world.ledger_state.transactions():
		if transaction["kind"] == "wage":
			var id := str(transaction["reference_id"])
			if uses_host_accounts() and not id.begins_with("work:"):
				continue
			if not value["wages"].has(id):
				return _fail("Unworked or legacy wage payment")
			var claim := value["wages"][id] as Dictionary
			var worker_account := _account(str(claim["worker"]), str(claim["denomination"]))
			if transaction["denomination"] != claim["denomination"] or transaction["from_account_id"] != _account(str(claim["employer"]), str(claim["denomination"])) or transaction["to_account_id"] != worker_account or int(transaction["effective_minute"]) < int(claim["due_day"]) * 1440 or int(transaction["effective_minute"]) > _world.game_clock.total_minutes():
				return _fail("Invalid wage payment attribution or maturity")
			paid[id] = int(paid.get(id, 0)) + int(transaction["amount"])
		elif transaction["kind"] == "goods":
			var id := str(transaction["reference_id"])
			if not orders.has(id) or int(transaction["effective_minute"]) > _world.game_clock.total_minutes():
				return _fail("Unexplained goods payment")
			var order := orders[id] as Dictionary
			if transaction["denomination"] != order["denomination"] or transaction["from_account_id"] != order["buyer_account"] or transaction["to_account_id"] != order["seller_account"] or not _valid_delivery_payment(transaction, order, value["delivery_receipts"]):
				return _fail("Invalid goods payment parties")
			delivered_money[id] = int(delivered_money.get(id, 0)) + int(transaction["amount"])
		elif transaction["kind"] == "freight":
			if str(transaction["transaction_id"]).begins_with("capital_freight_payment:"):
				if not _capital_transport.valid_payment(transaction["transaction_id"]): return _fail("Invalid equipment freight commitment")
				continue
			var id := str(transaction["reference_id"])
			if not orders.has(id) or not expected_freight.has(transaction["transaction_id"]) or expected_freight[transaction["transaction_id"]] != transaction:
				return _fail("Freight lacks its completed segment commitment")
			freight_money[id] = int(freight_money.get(id, 0)) + int(transaction["amount"])
	for id: String in value["wages"]:
		if int(value["wages"][id]["paid"]) != int(paid.get(id, 0)):
			return _fail("R1 paid wage differs from Ledger")
	for id: String in orders:
		if int(orders[id]["delivered"]) * int(orders[id]["price"]) != int(delivered_money.get(id, 0)):
			return _fail("R1 delivered goods differ from Ledger")
		if int(orders[id]["delivered"]) * _freight(orders[id]["route_legs"]) != int(freight_money.get(id, 0)):
			return _fail("Delivered freight differs from Ledger")
	for actor: String in expected_actors:
		if int(value["totals"][actor]["work_hours"]) != int(claim_hours.get(actor, 0)) or int(value["totals"][actor]["income"]) != int(claim_income.get(actor, 0)):
			return _fail("R1 cumulative labor/income conflict")
	return _validate_continuation(value, actors, stock, orders)

func _validate_continuation(value: Dictionary, actors: Dictionary, stock: Dictionary, orders: Dictionary) -> bool:
	if not _validate_firm_state(value):
		return false
	var physical := value["physical_totals"] as Dictionary
	if physical.size() != stock.size():
		return _fail("Missing physical conservation totals")
	var employer_hours: Dictionary = {}
	for work: Dictionary in value["work_records"].values():
		var employer := str(_job(str(work["job"]))["site_id"])
		employer_hours[employer] = int(employer_hours.get(employer, 0)) + int(work["hours"])
	for actor: String in stock:
		var flows: Variant = physical.get(actor)
		if not flows is Dictionary or not FormalLedgerState.exact_fields(flows, ["produced", "used"]):
			return _fail("Invalid physical totals")
		for field: String in ["produced", "used"]:
			if not flows[field] is Dictionary or not FormalLedgerState.exact_fields(flows[field], _goods):
				return _fail("Invalid physical goods totals")
			for amount: Variant in flows[field].values():
				if not FormalLedgerState.valid_amount(amount):
					return _fail("Invalid physical quantity")
		for good: String in _goods:
			var opening := int(_spec["actors"][actor]["stock"][good]) if actors.has(actor) else int(_spec["sites"][actor]["stock"][good])
			var expected := opening + int(flows["produced"][good]) - int(flows["used"][good])
			expected += _service_market.stock_delta(actor,good)
			for p: Dictionary in value.get("stock_lots", {}).get("portions", {}).values():
				if p["good"] == good and (p["location"] == "SITE|"+actor or p["location"] == "ACTOR|"+actor or (_declared_named(actor) and p["owner"] == actor)): expected -= int(p["lost"])

			for fact: Dictionary in _property_handovers.values():
				if fact["person_id"] == actor and fact["good"] == good: expected += int(fact["quantity"])
			for order: Dictionary in orders.values():
				if order["good"] != good or order["kind"] == "PERSONAL_FREIGHT":
					continue
				if _destination(order) == actor:
					expected += int(order["delivered"])
				if order["seller_site"] == actor:
					expected -= int(order["transit"]) + int(order["delivered"])
					for loss: Dictionary in _cargo_fulfilment.losses.values():
						if loss["status"] == "ADOPTED" and loss["order_id"] == order["id"] and not str(loss["shipment_id"]).is_empty(): expected -= int(loss["quantity"])
			if expected != int(stock[actor][good]):
				return _fail("R1 inventory does not match actual physical flows")
		if actors.has(actor):
			if not _valid_household_flows(value, actor, flows):
				return false
		else:
			var produced := _zero_goods()
			var used := _zero_goods()
			var hours: int = 0
			var capacity: int = 0
			for activity: Dictionary in _spec["sites"][actor]["activities"]:
				var batches := int(value["site_state"][actor]["activities"][activity["id"]]["batches"])
				hours += batches * int(activity["hours"])
				capacity += batches * int(activity["capacity_units"])
				for good: String in _goods:
					produced[good] = int(produced[good]) + batches * int(activity["outputs"].get(good, 0))
					used[good] = int(used[good]) + batches * int(activity["materials"][good])
			for good: String in _goods: used[good] = int(used[good]) + _capital.invested_goods(actor, good)+_service_market.consumed_goods(actor,good,value.get("stock_lots",{}).get("portions",{}))
			if produced != flows["produced"] or used != flows["used"]:
				return _fail("Physical flows differ from actual activity batch executions")
			if hours+_capital.allocated_hours(actor)+_shared.allocated_hours(actor)+_service_market.allocated_hours(actor)+_retail.allocated_hours(actor) > int(employer_hours.get(actor, 0)) or capacity > _capital.cumulative_capacity(actor, int(value["day"])) or (not config["production_enabled"] and capacity > 0):
				return _fail("Activities exceed shared actual labor or equipment")
	for key: Variant in value["request_window"]:
		var parts := str(key).split("|")
		if not key is String or parts.size() != 2 or not _spec["sites"].has(parts[0]) or not _spec["sites"][parts[0]]["prices"].has(parts[1]) or not value["request_window"][key] is Array:
			return _fail("Invalid received customer request container")
		var window := _request_retention_window(parts[0])
		var policy := _price_policy(parts[0], parts[1])
		if not policy.is_empty():
			window = maxi(window, int(policy["window_days"]))
		var buyers: Dictionary = {}
		for row: Variant in value["request_window"][key]:
			if not row is Dictionary or not FormalLedgerState.valid_amount(row.get("day")) or int(row["day"]) < maxi(0, int(value["day"]) - window + 1) or int(row["day"]) > int(value["day"]) or not FormalLedgerState.valid_amount(row.get("quantity")) or int(row["quantity"]) <= 0 or int(row["quantity"]) > 1000000:
				return _fail("Invalid received customer request amount or date")
			if FormalLedgerState.exact_fields(row, ["day", "quantity"]):
				continue
			if not EconomySliceConfig._fields(row, ["day", "buyer", "quantity", "order_id", "action_id", "physical_unmet", "cash_refused", "price_refused", "need_by_day"], ["limit_observation"]) or not stock.has(row["buyer"]) or not row["order_id"] is String or not row["action_id"] is String or not value["commands"].has(row["action_id"]):
				return _fail("Request lacks its actual buyer or command")
			for field: String in ["physical_unmet", "cash_refused", "price_refused", "need_by_day"]:
				if not FormalLedgerState.valid_amount(row[field]):
					return _fail("Invalid request response or need date")
			if int(row["need_by_day"]) < int(row["day"]) or int(row["need_by_day"]) > int(row["day"]) + 30 or int(row["physical_unmet"]) + int(row["cash_refused"]) + int(row["price_refused"]) > int(row["quantity"]):
				return _fail("Request responses exceed received quantity")
			var entry := value["commands"][row["action_id"]] as Dictionary
			var command := entry["envelope"]["command"] as Dictionary
			if not _valid_procurement_actor(entry, _owner(row["buyer"])) or command["kind"] != "buy" or command["payload"].get("seller") != _owner(parts[0]) or _inventory_key(str(command["payload"].get("seller", "")), str(command["payload"].get("seller_site", ""))) != parts[0] or _inventory_key(str(command["payload"].get("firm", entry["envelope"]["actor"])), str(command["payload"].get("buyer_site", ""))) != row["buyer"] or command["payload"].get("good") != parts[1] or int(command["minute"]) / 1440 != int(row["day"]) or not FormalLedgerState.valid_amount(command["payload"].get("quantity")) or int(row["quantity"]) > int(command["payload"]["quantity"]):
				return _fail("Request differs from its received purchase command")
			if not row["order_id"].is_empty() and (not orders.has(row["order_id"]) or orders[row["order_id"]]["action_id"] != row["action_id"]):
				return _fail("Request fulfillment has no accepted order")
			var request_key: String = str(row["buyer"])+"|"+(str(row["order_id"]) if not str(row["order_id"]).is_empty() else str(row["need_by_day"])) if row.has("limit_observation") else str(row["buyer"])
			if buyers.has(request_key) or (row.has("limit_observation") and not _valid_request_limits(row, orders, entry["result"])): return _fail("Invalid classified request limits or duplicate need")
			buyers[request_key] = true
	var account_specs := _configured_accounts()
	var expected_accounts: int = account_specs.size() + 1 + _foreign_budgets().size()
	var expected_budget := _opening_budget()
	if (not uses_host_accounts() and (_world.ledger_state.account_ids().size() != expected_accounts or _world.ledger_state.snapshot()["scenario_budget"] != expected_budget)) or _world.ledger_state.snapshot().get("currency_budgets", {}) != _foreign_budgets():
		return _fail("R1 account/endowment responsibility conflict")
	var initial_transfers: Dictionary = {}
	for account_id: String in account_specs:
		var row := account_specs[account_id] as Dictionary
		var actual := _world.ledger_state.account(account_id)
		if actual.get("owner_id") != row["actor"] or actual.get("role") != row["role"] or actual.get("denomination") != row["denomination"]:
			return _fail("Configured currency account ownership conflict")
		if int(row["amount"]) > 0:
			initial_transfers[row["transaction_id"]] = row
	var shipment_ids: Dictionary = {}
	for id: String in value["shipments"]:
		shipment_ids[id] = true
	for transaction: Dictionary in _world.ledger_state.transactions():
		if transaction["kind"] in ["opening_cash", "employer_reserve"]:
			var id := str(transaction["transaction_id"])
			if uses_host_accounts() and not id.begins_with("r1:"):
				continue
			if not initial_transfers.has(id):
				return _fail("R1 duplicate or unexplained initial funds")
			var expected := initial_transfers[id] as Dictionary
			if transaction["from_account_id"] != FormalLedgerState.currency_source(expected["denomination"]) or transaction["to_account_id"] != expected["account_id"] or transaction["amount"] != expected["amount"] or transaction["denomination"] != expected["denomination"] or transaction["reference_id"] != expected["actor"] or transaction["effective_minute"] != 0:
				return _fail("R1 opening responsibility differs from Ledger")
			initial_transfers.erase(id)
	for id: String in value["delivery_receipts"]:
		var cargo := value["delivery_receipts"][id] as Dictionary
		if id == _cargo_origin_id(cargo) and shipment_ids.has(id) and int(value["shipments"].get(id, {}).get("quantity", 1)) > 0: return _fail("Cargo is both in transit and delivered")
		shipment_ids[_cargo_origin_id(cargo)] = true
		if not _valid_arrival_payment(cargo, orders[cargo["order_id"]]):
			return false

	if not initial_transfers.is_empty() or shipment_ids.size() != int(value["next_shipment"]) - 1:
		return _fail("R1 missing opening transfers or shipment IDs")
	for number: int in range(1, int(value["next_shipment"])):
		if not shipment_ids.has("shipment:" + str(number)):
			return _fail("R1 shipment sequence conflict")
	var relation_dates: Dictionary = {}
	var relations := _delivery_relations(value["delivery_receipts"], orders, relation_dates)
	var legacy_relations: bool = false
	for row: Variant in value["relations"].values():
		if typeof(row) == TYPE_INT:
			legacy_relations = true
	if legacy_relations:
		if value["relations"] != relation_dates:
			return _fail("Legacy cooperation dates differ from actual delivery")
		value["relations"] = relations
	elif value["relations"] != relations:
		return _fail("Recent cooperation references differ from actual delivered cargo")
	var expected_needs: int = 0
	for actor: String in actors:
		if _last_managed_need_day(actor, int(value["day"])) >= 0: expected_needs += 1
	if value["needs"].size() != expected_needs:
		return _fail("R1 current needs are missing")
	for actor: Variant in value["needs"]:
		if not actors.has(actor) or not _valid_current_need(value, actor):
			return _fail("Invalid current household category state")

	if not _validate_transport(value):
		return false
	return _validate_operations(value)


func _configured_accounts() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _spec["actors"]:
		var row := _spec["actors"][id] as Dictionary
		result[row["account_id"]] = {"actor": id, "account_id": row["account_id"], "amount": row["cash"], "denomination": FormalLedgerState.DENOMINATION, "role": "personal_cash" if row["kind"] == "named" else "r1_cohort", "transaction_id": "r1:opening:" + id}
	for id: String in _spec["firms"]:
		var row := _spec["firms"][id] as Dictionary
		result[row["account_id"]] = {"actor": id, "account_id": row["account_id"], "amount": row["cash"], "denomination": FormalLedgerState.DENOMINATION, "role": "r1_firm", "transaction_id": "r1:opening:" + id}
	for row: Dictionary in config.get("carriers", []):
		result[row["account_id"]] = {"actor": row["id"], "account_id": row["account_id"], "amount": row["cash"], "denomination": FormalLedgerState.DENOMINATION, "role": "r1_carrier", "transaction_id": "r1:opening:" + str(row["id"])}
	for row: Dictionary in config.get("currency_accounts", []):
		var owner := str(row["owner"])
		result[row["account_id"]] = {"actor": owner, "account_id": row["account_id"], "amount": row["cash"], "denomination": row["denomination"], "role": result[_account(owner)]["role"], "transaction_id": "r1:opening_currency:" + str(row["account_id"])}
	return result

func _valid_order_route(order: Dictionary) -> bool:
	if Retail.onsite(order):
		return _retail.has_site(order["seller_site"]) and order["kind"]=="SALE" and order["route_id"]=="onsite:"+str(order["seller_site"]) and _spec["actors"].has(order["buyer"]) and order["buyer_site"]=="" and order["seller"]==_owner(order["seller_site"]) and order["route_legs"]==[] and order["pending"]==0 and order["transit"]==0 and order["cancelled"]==0 and order["delivered"]==order["quantity"] and order["from_place_id"]==_place(order["seller_site"]) and order["to_place_id"]==order["from_place_id"] and order["denomination"]==_sale_currency(order["seller"]) and order["price"]>0 and _valid_locked_price(order) and order["buyer_account"]==_account(order["buyer"],order["denomination"]) and order["seller_account"]==_account(order["seller"],order["denomination"]) and not order.has("custody_fact")
	if order["kind"] == "PERSONAL_FREIGHT": return _valid_personal_freight_order(order)
	if order.has("custody_fact") or order.has("source_custody_site") or order.has("destination_custody_site"): return _fail("Sale cannot reinterpret a personal custody contract")
	var transfer: bool = order["kind"] == "TRANSFER"
	if order["kind"] not in ["SALE", "TRANSFER"] or not _spec["sites"].has(order["seller_site"]) or _owner(order["seller_site"]) != order["seller"] or not FormalLedgerState.currency_id(order["denomination"]) or not order["route_id"] is String or not order["route_legs"] is Array or order["route_legs"].is_empty():
		return _fail("Unknown order kind, stock point, currency or path")
	if _spec["firms"].has(order["buyer"]):
		if not _spec["sites"].has(order["buyer_site"]) or _owner(order["buyer_site"]) != order["buyer"] or order["need_category"] != "":
			return _fail("Firm order lacks its destination stock point")
	elif not _spec["actors"].has(order["buyer"]) or order["buyer_site"] != "" or not order["need_category"] is String or (not str(order["need_category"]).is_empty() and _service(order["good"], order["need_category"]) <= 0):
		return _fail("Household order lacks its actual usable need category")
	if transfer:
		if order["buyer"] != order["seller"] or order["buyer_site"] == order["seller_site"] or order["price"] != 0:
			return _fail("Internal movement cannot create sale income")
	elif order["buyer"] == order["seller"] or order["denomination"] != _sale_currency(order["seller"]) or int(order["price"]) <= 0 or not _valid_locked_price(order):
		return _fail("External sale currency or locked price conflict")
	var chosen: Dictionary = {}
	for path: Dictionary in _paths_for(order["buyer"], str(order["from_place_id"]), str(order["to_place_id"]), int(order["accepted_day"])):
		if path["id"] == order["route_id"]:
			chosen = path
	# A named buyer can later move. Its original host destination stays locked.
	var destination_valid: bool = _world.spatial_catalog.has_place(str(order["to_place_id"])) if order["buyer_site"] == "" else order["to_place_id"] == _place(order["buyer_site"])
	if chosen.is_empty() or order["from_place_id"] != _place(order["seller_site"]) or not destination_valid or order["route_legs"] != _locked_legs(chosen, order["denomination"]):
		return _fail("Order differs from its known locked site path and freight")
	if order["buyer_account"] != _account(order["buyer"], order["denomination"]) or order["seller_account"] != _account(order["seller"], order["denomination"]) or str(order["buyer_account"]).is_empty() or str(order["seller_account"]).is_empty() or (order["buyer_account"] == order["seller_account"]) != transfer:
		return _fail("Order currency account ownership conflict")
	for leg: Dictionary in order["route_legs"]:
		if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == order["buyer_account"]):
			return _fail("Locked freight recipient is unavailable")
	var unit := int(order["price"]) + _freight(order["route_legs"])
	if unit > FormalLedgerState.MAX_AMOUNT or (unit > 0 and int(order["quantity"]) > FormalLedgerState.MAX_AMOUNT / unit):
		return _fail("Order payment exceeds amount bounds")
	return true


func _valid_delivery_payment(payment: Dictionary, order: Dictionary, receipts: Dictionary) -> bool:
	var id := str(payment["transaction_id"]).trim_prefix("r1:goods:")
	var receipt: Dictionary = receipts.get(id, {})
	return order["kind"] == "SALE" and not receipt.is_empty() and receipt["order_id"] == order["id"] and int(payment["effective_minute"]) == _delivery_minute(receipt) and _valid_arrival_payment(receipt, order)


func _earliest_dispatch(order: Dictionary) -> int:
	if Retail.onsite(order): return int(order["accepted_day"])
	var buyer := str(order["buyer"])
	var automatic: bool = _spec["firms"].has(buyer) or (_spec["actors"].has(buyer) and _spec["actors"][buyer]["control"] == "automatic")
	if _shared.bindings.get(order["route_legs"][0]["edge_id"], {}).has("window_minutes"): return int(order["accepted_day"])
	return int(order["accepted_day"]) + (0 if automatic and int(order["accepted_minute"]) % 1440 == 0 else 1)

func _cargo_origin_id(cargo: Dictionary) -> String:
	return str(cargo.get("shipment_id", cargo["id"]))

func _receipt_less(a: Dictionary, b: Dictionary) -> bool:
	if _delivery_minute(a) != _delivery_minute(b): return _delivery_minute(a) < _delivery_minute(b)
	var first := int(_cargo_origin_id(a).trim_prefix("shipment:"))
	var second := int(_cargo_origin_id(b).trim_prefix("shipment:"))
	if first != second: return first < second
	return int(str(a["id"]).get_slice(":part:", 1)) < int(str(b["id"]).get_slice(":part:", 1))

func _validate_cargo_records(value: Dictionary, orders: Dictionary) -> bool:
	var cargo_losses: Dictionary = {}
	for portion: Variant in value.get("stock_lots", {}).get("portions", {}).values():
		if not portion is Dictionary or not portion.get("location") is String or not FormalLedgerState.valid_amount(portion.get("lost")): return _fail("Invalid physical cargo loss reference")
		if portion["location"].begins_with("CARGO|"):
			var cargo_id := str(portion["location"]).trim_prefix("CARGO|")
			cargo_losses[cargo_id] = int(cargo_losses.get(cargo_id, 0))+int(portion["lost"])
	var transit: Dictionary = {}
	var delivered: Dictionary = {}
	var batches: Dictionary = {}
	var edges := _all_routes()
	for collection: String in ["shipments", "delivery_receipts"]:
		for id: Variant in value[collection]:
			var raw: Variant = value[collection][id]
			if not id is String or not raw is Dictionary: return _fail("Invalid cargo container")
			var cargo := raw as Dictionary
			if not cargo.get("id") is String: return _fail("Invalid cargo identity")
			var receipt: bool = collection == "delivery_receipts"
			var fields: Array[String] = []
			fields.assign(["id", "order_id", "quantity", "departures", "delivered_day"] if receipt else ["id", "order_id", "quantity", "stage", "leg_index", "place_id", "ready_day", "leg_arrival_day", "departures"])
			var optional: Array[String] = []
			optional.assign(["departure_quantities", "loading_end_minute", "arrival_minute", "unloading_end_minute", "replacement_disposition_ids"])
			if receipt: optional.append_array(["delivered_minute", "collection_action_id", "shipment_id", "custody_mode", "custody_place_id", "custody_fact"])
			var base := _cargo_origin_id(cargo)
			if not EconomySliceConfig._fields(cargo, fields, optional) or cargo["id"] != id or base != "shipment:" + str(int(base.trim_prefix("shipment:"))) or int(base.trim_prefix("shipment:")) <= 0 or int(base.trim_prefix("shipment:")) >= int(value["next_shipment"]) or not orders.has(cargo["order_id"]) or not FormalLedgerState.valid_amount(cargo["quantity"]) or (int(cargo["quantity"]) <= 0 and (receipt or _cargo_fulfilment.cargo_loss(base) <= 0)) or not cargo["departures"] is Array or (cargo["departures"].is_empty() and not (receipt and Retail.onsite(orders[cargo["order_id"]]))): return _fail("Invalid physical cargo identity or quantity")
			if id != base and (not receipt or (not cargo.has("collection_action_id") and _cargo_fulfilment.cargo_loss(base) <= 0) or id != base + ":part:" + str(int(str(id).get_slice(":part:", 1))) or int(str(id).get_slice(":part:", 1)) <= 0): return _fail("Invalid partial physical receipt")
			var order := orders[cargo["order_id"]] as Dictionary
			if cargo.has("replacement_disposition_ids"):
				if not cargo["replacement_disposition_ids"] is Array: return _fail("Invalid replacement attempt reference")
				for replacement_id: Variant in cargo["replacement_disposition_ids"]:
					var replacement: Variant = _cargo_fulfilment.dispositions.get(replacement_id)
					if not replacement is Dictionary or replacement["status"] != "EXECUTED" or replacement["terms"]["mode"] != "REPLACE" or _cargo_fulfilment.losses[replacement["loss_id"]]["order_id"] != order["id"]: return _fail("Replacement attempt loses its original contract")
			if Retail.onsite(order):
				if not receipt or id!=base or value["shipments"].has(base) or delivered.has(order["id"]) or cargo["departures"]!=[] or cargo.get("delivered_minute")!=order["accepted_minute"] or cargo["delivered_day"]!=order["accepted_day"] or cargo["quantity"]!=order["quantity"] or cargo.has("collection_action_id") or cargo.has("replacement_disposition_ids") or cargo.has("shipment_id"): return _fail("Invalid onsite handover receipt")
				if _declared_named(order["buyer"]) and (cargo.get("custody_mode") not in ["CARRIED","STORED"] or cargo.get("custody_place_id")!=order["to_place_id"]): return _fail("Onsite personal custody missing")
				delivered[order["id"]]=cargo["quantity"]
				continue
			var legs := order["route_legs"] as Array
			if not batches.has(base): batches[base] = {"base": base, "order_id": order["id"], "departures": cargo["departures"], "quantity": 0, "receipts": []}
			var batch := batches[base] as Dictionary
			if batch["order_id"] != order["id"] or batch["departures"] != cargo["departures"]: return _fail("Partial receipt changes its original physical shipment")
			batch["quantity"] = int(batch["quantity"]) + int(cargo["quantity"])
			if batch["quantity"] > _batch_limit(legs) or batch["quantity"] > int(order["quantity"]) or cargo["departures"].size() > legs.size(): return _fail("Physical batch cannot fit its original route")
			var ready := _earliest_dispatch(order)
			var ready_minute := ready*1440
			for index: int in cargo["departures"].size():
				var departed: Variant = cargo["departures"][index]
				if not FormalLedgerState.valid_amount(departed) or int(departed) < ready or int(departed) > int(value["day"]): return _fail("Cargo enters a segment before physical arrival")
				var entry := _shared.entries.get("economy_entry:"+base+":"+str(index), {}) as Dictionary
				if entry.has("arrival_minute"):
					if int(entry["minute"]) < ready_minute: return _fail("Timed entry precedes actual prior arrival")
					ready_minute = maxi(int(entry["arrival_minute"]),_shared.node_completion_minute(base,index))
					ready = int(entry["arrival_minute"])/1440
				else:
					ready = int(departed) + int(legs[index]["delay"])
					ready_minute = ready*1440
			if receipt:
				if _delivery_minute(cargo) < ready_minute: return _fail("Collection precedes actual timed arrival")
				if cargo.has("delivered_minute") and (not FormalLedgerState.valid_amount(cargo["delivered_minute"]) or int(cargo["delivered_minute"]) / 1440 != int(cargo["delivered_day"]) or int(cargo["delivered_minute"]) > _world.game_clock.total_minutes()): return _fail("Invalid actual collection time")
				if cargo.has("collection_action_id"):
					var entry: Dictionary = value["commands"].get(cargo["collection_action_id"], {})
					if entry.is_empty() or not entry["result"].get("accepted", false) or entry["envelope"]["actor"] != order["buyer"] or entry["envelope"]["command"]["kind"] != "collect" or entry["envelope"]["command"]["payload"].get("shipment_id") != base or entry["envelope"]["command"]["minute"] != _delivery_minute(cargo) or entry["result"].get("quantity") != cargo["quantity"]: return _fail("Collection lacks its recipient action")
					if entry["envelope"]["command"]["payload"].has("quantity") and entry["envelope"]["command"]["payload"]["quantity"] != cargo["quantity"]: return _fail("Partial receipt differs from requested quantity")
				if (id == base and value["shipments"].has(base) and int(value["shipments"][base]["quantity"]) > 0) or cargo["departures"].size() != legs.size() or not FormalLedgerState.valid_amount(cargo["delivered_day"]) or int(cargo["delivered_day"]) < ready or int(cargo["delivered_day"]) > int(value["day"]) or (int(cargo["delivered_day"]) != ready and not _declared_named(order["buyer"]) and not _shared.has_node_arrival(base, legs.size()-1)): return _fail("Delivery lacks final physical arrival")
				if cargo.has("custody_mode"):
					if not _declared_named(order["buyer"]) or cargo["custody_mode"] not in ["CARRIED", "STORED"] or cargo.get("custody_place_id") != order["to_place_id"] or (cargo["custody_mode"] == "STORED" and _personal_storage_site(order["to_place_id"], order["good"]).is_empty()): return _fail("Invalid acquisition custody")
				if order["kind"] == "PERSONAL_FREIGHT":
					if not cargo.has("custody_fact") or not _valid_custody_fact(cargo["custody_fact"], order["buyer"], order["good"], cargo["quantity"], "FREIGHT|" + str(order["id"]), "CARRIED" if cargo.get("custody_mode") == "CARRIED" else "STORED|" + str(order["to_place_id"]), id, "freight_collect", _delivery_minute(cargo)): return _fail("Personal freight loses original property custody")
				elif cargo.has("custody_fact"): return _fail("Goods purchase cannot reuse already owned freight lots")
				batch["receipts"].append(cargo)
				delivered[order["id"]] = int(delivered.get(order["id"], 0)) + int(cargo["quantity"])
			else:
				if int(cargo["quantity"]) == 0:
					if cargo.get("stage") != "LOSS_RECORD" or _cargo_fulfilment.cargo_loss(base) <= 0: return _fail("Empty shipment has no adopted loss")
					continue
				if cargo.get("stage") == "AWAITING_RECIPIENT":
					if (not _declared_named(order["buyer"]) and int(cargo_losses.get(base, 0)) <= 0) or cargo.get("leg_index") != legs.size()-1 or cargo["departures"].size() != legs.size() or cargo.get("place_id") != order["to_place_id"] or cargo.get("ready_day") != ready or cargo.get("leg_arrival_day") != ready or ready > int(value["day"]) or ready_minute > _world.game_clock.total_minutes(): return _fail("Awaiting cargo lacks its custody destination")
				else:
					if cargo.get("stage") not in ["TRANSIT", "WAITING", "LOADING", "WAITING_UNLOAD", "UNLOADING"] or not FormalLedgerState.valid_amount(cargo.get("leg_index")) or int(cargo["leg_index"]) >= legs.size() or not FormalLedgerState.valid_amount(cargo.get("ready_day")) or typeof(cargo.get("leg_arrival_day")) != TYPE_INT: return _fail("Invalid cargo segment cursor")
					var index := int(cargo["leg_index"])
					var expected_count := index + 1 if cargo["stage"] in ["TRANSIT", "LOADING", "WAITING_UNLOAD", "UNLOADING"] else index
					var expected_ready := _earliest_dispatch(order) if index == 0 else int(cargo["departures"][index - 1]) + int(legs[index - 1]["delay"])
					var prior_entry := _shared.entries.get("economy_entry:"+base+":"+str(index-1), {}) as Dictionary
					if prior_entry.has("arrival_minute"): expected_ready = int(prior_entry["arrival_minute"])/1440
					if cargo["departures"].size() != expected_count or cargo["place_id"] != edges[legs[index]["edge_id"]]["to_place_id" if cargo["stage"] in ["WAITING_UNLOAD","UNLOADING"] else "from_place_id"] or int(cargo["ready_day"]) != expected_ready: return _fail("Cargo cursor lacks actual entered segments")
					if cargo["stage"] in ["WAITING_UNLOAD","UNLOADING"]:
						var entered := _shared.entries.get("economy_entry:"+base+":"+str(index), {}) as Dictionary
						if not _shared.bindings.get(legs[index]["edge_id"],{}).has("node_resources") or entered.get("arrival_minute",FormalLedgerState.MAX_AMOUNT) > _world.game_clock.total_minutes() or cargo.get("arrival_minute") != entered.get("arrival_minute"): return _fail("Node wait lacks actual entered cargo")
						if cargo["stage"] == "UNLOADING" and (not FormalLedgerState.valid_amount(cargo.get("unloading_end_minute")) or cargo["unloading_end_minute"] <= _world.game_clock.total_minutes()): return _fail("Invalid actual unloading cursor")
					if cargo["stage"] in ["TRANSIT", "LOADING"]:
						var entered := _shared.entries.get("economy_entry:"+base+":"+str(index), {}) as Dictionary
						if entered.has("arrival_minute"):
							if cargo.get("arrival_minute") != entered["arrival_minute"] or cargo.get("loading_end_minute") != entered["loading_end_minute"] or int(entered["arrival_minute"]) <= _world.game_clock.total_minutes() or (cargo["stage"] == "LOADING") != (int(entered["loading_end_minute"]) > _world.game_clock.total_minutes()): return _fail("Timed cargo entry lifecycle mismatch")
						elif cargo.has("arrival_minute") or cargo.has("loading_end_minute"): return _fail("Timed cargo lacks its actual entry")
						if int(cargo["leg_arrival_day"]) != ready or (ready <= int(value["day"]) and not entered.has("arrival_minute")): return _fail("Cargo timing conflict")
					elif cargo["stage"]=="WAITING" and (index == 0 or int(cargo["leg_arrival_day"]) != -1 or ready > int(value["day"]) or ready_minute > _world.game_clock.total_minutes()): return _fail("Waiting cargo has not reached its node")
				transit[order["id"]] = int(transit.get(order["id"], 0)) + int(cargo["quantity"])
	for batch: Dictionary in batches.values():
		var base := str(batch["base"])
		var rows: Array = batch["receipts"].duplicate()
		if value["shipments"].has(base): rows.append(value["shipments"][base])
		var original := int(batch["quantity"])+_cargo_fulfilment.cargo_loss(base)
		for cargo: Dictionary in rows:
			if not cargo.has("departure_quantities"): continue
			for i: int in cargo["departures"].size():
				var expected := original
				for loss_id: String in _cargo_fulfilment._losses_by_shipment.get(base, []):
					var loss := _cargo_fulfilment.losses[loss_id] as Dictionary
					if loss["status"] == "ADOPTED" and (int(loss["leg_index"]) < i or (int(loss["leg_index"]) == i and loss["stage"] == "WAITING")): expected -= int(loss["quantity"])
				if cargo["departure_quantities"][i] != expected: return _fail("Segment throughput differs from its physical loss timeline")
		batch["receipts"].sort_custom(_receipt_less)
		var cumulative: int = 0
		for receipt: Dictionary in batch["receipts"]:
			cumulative += int(receipt["quantity"])
			if receipt.has("shipment_id") and int(str(receipt["id"]).get_slice(":part:", 1)) != cumulative: return _fail("Partial receipt duplicates or loses original batch quantity")
	for id: String in orders:
		if int(orders[id]["transit"]) != int(transit.get(id, 0)) or int(orders[id]["delivered"]) != int(delivered.get(id, 0)): return _fail("Order physical responsibility differs from cargo")
	return true

func _valid_financial_batches(value: Dictionary) -> bool:
	for id: String in _world.ledger_state.snapshot().get("payment_batches", {}):
		if id.begins_with("delivery:shipment:"):
			if not value["delivery_receipts"].has(id.trim_prefix("delivery:")) or _delivery_legs(id.trim_prefix("delivery:"), value["orders"][value["delivery_receipts"][id.trim_prefix("delivery:")]["order_id"]], int(value["delivery_receipts"][id.trim_prefix("delivery:")]["quantity"])).is_empty():
				return _fail("Orphan arrival payment batch")
		elif uses_host_accounts() and id.begins_with("travel:"):
			var action := id.trim_prefix("travel:")
			var entry: Dictionary = value["commands"].get(action, {})
			if entry.is_empty() or entry["envelope"]["command"]["kind"] != "travel" or not entry["result"].get("accepted", false) or entry["result"].get("journey", {}).get("id") != action: return _fail("Passenger payment has no accepted host action")
			# Fare routes, payees and quantities are checked by FormalPersonTravel
			# later in the same candidate restore, against this exact Ledger.
		elif id.begins_with("cargo:"):
			if not _cargo_fulfilment.valid_payment_batch(id): return _fail("Orphan cargo disposition payment")
		elif id.begins_with("lease_payment:"):
			if not _leases.valid_payment_batch(id): return _fail("Orphan lease payment")
		elif id.begins_with("capital_freight_payment:"):
			if not _capital_transport.valid_payment(id): return _fail("Orphan equipment freight payment")
		elif id.begins_with("capital_payment:"):
			if not _capital.valid_resale_payment(id): return _fail("Orphan equipment delivery payment")
		elif id.begins_with("service_payment:"):
			if not _service_market.valid_payment_batch(id): return _fail("Orphan service payment")
		elif id.begins_with("fx:fx_deal:"):
			if not value.get("currency_exchange", {}).get("deals", {}).has(id.trim_prefix("fx:")):
				return _fail("Orphan FX payment batch")
		elif id.begins_with("asset_trade:"):
			if not value.get("assets", {}).get("trades", {}).has(id):
				return _fail("Orphan share payment batch")
		elif id.begins_with("primary_settlement:"):
			if not value.get("assets",{}).get("primary",{}).get("settlements",{}).has(id): return _fail("Orphan primary payment batch")
		elif id.begins_with("share_distribution_batch:"):
			var found: bool=false
			for plan: Dictionary in value.get("assets",{}).get("distributions",{}).get("plans",{}).values():
				if plan["status"]=="PAID" and plan["payment_batch"]==id: found=true
			if not found: return _fail("Orphan shareholder distribution batch")
		elif id.begins_with("dividend:"):
			if not value.get("assets", {}).get("dividends", {}).has(id):
				return _fail("Orphan dividend payment batch")
		else:
			return _fail("Unknown economic payment batch")
	return true


func _valid_message(message: Dictionary, actors: Dictionary) -> bool:
	if not message.get("id") is String or not message.get("actor") is String or not message.get("candidate") is String or not FormalLedgerState.valid_amount(message.get("observed_day")) or not FormalLedgerState.valid_amount(message.get("delivery_day")) or int(message["delivery_day"]) < int(message["observed_day"]) or (not actors.has(message["actor"]) and not _spec["firms"].has(message["actor"]) and not _spec["sites"].has(message["actor"])):
		return false
	if message.get("kind")=="equity_report": return _assets.call_market.message_valid(message)
	if message.get("kind")=="equity_issue": return _assets.primary.message_valid(message)
	if message.get("kind")=="share_distribution": return _assets.distribution.message_valid(message)
	if message.get("kind")=="supply_opportunity": return _supply.valid_message(message)
	if message.get("kind")=="goods_quote": return _local_quotes.valid_message(message)
	if message.get("kind")=="capital_offer": return _capital.quote_message_valid(message)
	if message.get("source")=="commercial": return _commercial.message_valid(message)
	if message.get("source")=="labor_market": return _labor_market.valid_message(message)
	var actor := str(message["actor"])
	var candidate := str(message["candidate"])
	var fields: Array[String] = ["id", "actor", "kind", "candidate", "observed_day", "delivery_day"]
	if message.get("kind") == "site_report":
		return _valid_site_report(message)
	if message.get("kind") == "directory":
		fields.append("scope")
		var policy := _search_policy(actor)
		return FormalLedgerState.exact_fields(message, fields) and not policy.is_empty() and candidate in _goods and message["scope"] in ["LOCAL", "REGIONAL", "WIDE"] and (message["scope"] != "WIDE" or policy["allow_wide"]) and message["id"] == "directory:" + actor + ":" + candidate and int(message["delivery_day"]) == int(message["observed_day"]) + int(policy["delay_days"][message["scope"]])
	if message.get("source") == "directory":
		fields.append_array(["source", "scope"])
		var policy := _search_policy(actor)
		return FormalLedgerState.exact_fields(message, fields) and message["kind"] == "supplier" and not policy.is_empty() and message["scope"] in ["LOCAL", "REGIONAL", "WIDE"] and not _directory_entry(actor, candidate, message["scope"], int(message["delivery_day"])).is_empty() and message["id"] == "message:" + actor + ":supplier:" + candidate and int(message["delivery_day"]) == int(message["observed_day"]) + int(policy["delay_days"][message["scope"]])
	if message.get("kind") == "job_posting":
		fields.append_array(["version", "positions"])
		var local: bool = message.get("source") == "local_notice"
		if local: fields.append_array(["source", "place_id", "observed_minute"])
		if not FormalLedgerState.exact_fields(message, fields) or not actors.has(actor) or not _spec["jobs"].has(candidate) or not FormalLedgerState.valid_amount(message["version"]) or int(message["version"]) <= 0 or not FormalLedgerState.valid_amount(message["positions"]):
			return false
		var job := _spec["jobs"][candidate] as Dictionary
		if int(message["positions"]) > int(job["positions"]) or message["id"] != "posting:" + actor + ":" + candidate:
			return false
		if local:
			return _spec["actors"][actor]["kind"] == "named" and message["place_id"] == job["place"] and FormalLedgerState.valid_amount(message["observed_minute"]) and int(message["observed_minute"]) <= _world.game_clock.total_minutes() and int(message["observed_minute"])/1440 == int(message["delivery_day"])
		for info: Dictionary in _spec["information"]:
			if info["actor"] == actor and info["kind"] == "job" and info["candidate"] == candidate:
				return int(message["delivery_day"]) == maxi(int(message["observed_day"]) + int(job.get("notice_delay", 1)), int(info["delivery_day"]))
		return false
	if not FormalLedgerState.exact_fields(message, fields) or message.get("kind") not in ["job", "supplier"] :
		return false
	for info: Dictionary in _spec["information"]:
		if info["actor"] == actor and info["kind"] == message["kind"] and info["candidate"] == candidate:
			return message["id"] == "message:" + actor + ":" + str(message["kind"]) + ":" + candidate and int(message["delivery_day"]) == int(info["delivery_day"]) and int(message["observed_day"]) == int(info.get("observed_day", 0))
	return false

func _validate_operations(value: Dictionary) -> bool:
	var quotes := value["quote_state"] as Dictionary
	var initial := _initial_quote_state(int(value["day"]))
	if quotes.size() != initial.size():
		return _fail("Missing or unknown local quotation state")
	for key: String in initial:
		var state: Variant = quotes.get(key)
		var parts := key.split("|")
		var policy := _price_policy(parts[0], parts[1])
		if not state is Dictionary or not FormalLedgerState.exact_fields(state, ["price", "next_price", "effective_day", "window_start", "last_reason", "updated_day"]) or not FormalLedgerState.valid_amount(state["price"]) or not FormalLedgerState.valid_amount(state["window_start"]) or not FormalLedgerState.valid_amount(state["updated_day"]) or typeof(state["next_price"]) != TYPE_INT or typeof(state["effective_day"]) != TYPE_INT or state["last_reason"] not in ["INITIAL", "HOLD", "NO_NEW_INFORMATION", "IDLE_STOCK", "ECONOMIC_REFUSAL", "OBSERVED_PHYSICAL_PRESSURE"]:
			return _fail("Invalid local quotation window")
		if int(state["price"]) < int(policy["minimum"]) or int(state["price"]) > int(policy["maximum"]) or int(state["price"]) % int(policy["tick"]) != 0 or int(state["updated_day"]) > int(value["day"]) or int(state["window_start"]) > int(value["day"]) + 1:
			return _fail("Quotation exceeds its configured bounds or date")
		if int(state["next_price"]) == -1:
			if int(state["effective_day"]) != -1:
				return _fail("Quotation lacks its scheduled next price")
		else:
			var step: int = (int(state["price"]) * N3_STEP_PERCENT / 100 / int(policy["tick"])) * int(policy["tick"])
			if int(state["effective_day"]) != int(value["day"]) + 1 or state["window_start"] != state["effective_day"] or int(state["next_price"]) < int(policy["minimum"]) or int(state["next_price"]) > int(policy["maximum"]) or int(state["next_price"]) % int(policy["tick"]) != 0 or absi(int(state["next_price"]) - int(state["price"])) > step:
				return _fail("Next quotation exceeds its bounded adjustment")
	var postings := value["job_postings"] as Dictionary
	if postings.size() != _spec["jobs"].size():
		return _fail("Missing configured job posting")
	for id: String in _spec["jobs"]:
		var state: Variant = postings.get(id)
		if not state is Dictionary or not FormalLedgerState.exact_fields(state, ["positions", "version", "published_day"]):
			return _fail("Invalid job posting state")
		for amount: Variant in state.values():
			if not FormalLedgerState.valid_amount(amount):
				return _fail("Invalid job posting count or date")
		if _labor_market.controls(id):
			if state!=_labor_market.posting(id): return _fail("Dynamic job posting differs from effective quotation")
			continue
		var job := _spec["jobs"][id] as Dictionary
		var occupied: int = 0
		for contract: Dictionary in _all_contract_rows(value["contracts"]):
			if contract["job"] == id:
				occupied += int(contract["workers"])
		if int(state["positions"]) < occupied or int(state["positions"]) > int(job["positions"]) or int(state["published_day"]) > int(value["day"]):
			return _fail("Posting lost existing employment or exceeds its template")
		var operated: bool = false
		for entry: Dictionary in _operating_history(value["commands"]):
			var command := entry["envelope"]["command"] as Dictionary
			if command["kind"] in ["set_activity_enabled", "set_site_status", "set_firm_operating", "close_site", "finish_firm", "wind_down_firm"] and entry["result"]["accepted"] and command["payload"].get("firm") == job["employer"]:
				operated = true
		if not _operations_policy(job["site_id"])["manage_jobs"] and not operated and state != _initial_job_postings()[id]:
			return _fail("Fixed job template was changed without an operating action")
	for message: Dictionary in value["messages"]:
		if message["kind"] == "job_posting" and message.get("source")!="labor_market" and (message["version"] != postings[message["candidate"]]["version"] or message["positions"] != postings[message["candidate"]]["positions"] or message["observed_day"] != postings[message["candidate"]]["published_day"]):
			return _fail("Pending posting differs from its published version")
	for message: Dictionary in value["receipts"].values():
		if message["kind"] == "job_posting" and int(message["version"]) > int(postings[message["candidate"]]["version"]):
			return _fail("Received posting refers to a future version")
	for site: String in _site_ids():
		var search := _search_policy(site)
		if search.is_empty():
			continue
		for good: String in _goods:
			var known: Dictionary = {}
			var initial_known: Dictionary = {}
			for candidate: String in value.get("firm_knowledge", {}).get(site, _spec["sites"][site]["suppliers"]):
				var supplier := _candidate(candidate)
				if supplier["good"] == good:
					known[supplier["site"]] = true
			for candidate: String in _spec["sites"][site]["suppliers"]:
				var supplier := _candidate(candidate)
				if supplier["good"] == good:
					initial_known[supplier["site"]] = true
			if known.size() > maxi(initial_known.size(), int(search["max_known"])):
				return _fail("Site supplier knowledge exceeds its finite policy")

	for key: Variant in value["search_state"]:
		var parts := str(key).split("|")
		var state: Variant = value["search_state"][key]
		var policy := _search_policy(parts[0]) if parts.size() == 2 else {}
		if not key is String or parts.size() != 2 or parts[1] not in _goods or policy.is_empty() or not state is Dictionary or not FormalLedgerState.exact_fields(state, ["next_scope", "last_completed_day"]) or not FormalLedgerState.valid_amount(state["next_scope"]) or int(state["next_scope"]) >= (3 if policy["allow_wide"] else 2) or typeof(state["last_completed_day"]) != TYPE_INT or int(state["last_completed_day"]) < -1 or int(state["last_completed_day"]) > int(value["day"]):
			return _fail("Invalid finite supplier search cursor")
	for message: Dictionary in value["messages"]:
		if message["kind"] == "directory":
			var key := str(message["actor"]) + "|" + str(message["candidate"])
			var scopes: Array[String] = []
			scopes.assign(["LOCAL", "REGIONAL", "WIDE"] if _search_policy(message["actor"])["allow_wide"] else ["LOCAL", "REGIONAL"])
			if not value["search_state"].has(key) or scopes[int(value["search_state"][key]["next_scope"])] != message["scope"]:
				return _fail("Pending directory result lost its local search cursor")
	var expected_plans: int = 0
	for site: String in _site_ids():
		if int(value["day"])*1440 > int(_subject_activation.get(site, 0)): expected_plans += 1
	if value["plans"].size() != expected_plans:
		return _fail("Missing or unknown firm plan")
	for firm: String in value["plans"]:
		if not _spec["sites"].has(firm):
			return _fail("Unknown planned enterprise")
		var plan: Variant = value["plans"][firm]
		var expected: Array[String] = []
		expected.assign(_spec["sites"][firm]["activity_order"])
		if not plan is Dictionary or not FormalLedgerState.exact_fields(plan, ["day", "activities", "labor_hours"]) or plan["day"] != value["day"] or not plan["activities"] is Dictionary or not FormalLedgerState.exact_fields(plan["activities"], expected) or not FormalLedgerState.valid_amount(plan["labor_hours"]):
			return _fail("Invalid local multi-activity plan")
		var horizon := int(_operations_policy(firm)["planning_horizon"])
		var capacities: Array[int] = []
		capacities.resize(horizon)
		capacities.fill(0)
		var hours: int = 0
		var worked: int = 0
		for work: Dictionary in value["work_records"].values():
			if work["day"] == value["day"] and _spec["jobs"][work["job"]]["site_id"] == firm:
				worked += int(work["hours"])
		if int(plan["labor_hours"]) != worked:
			return _fail("Plan labor differs from actual completed work")
		for id: String in expected:
			var local: Variant = plan["activities"][id]
			var activity := _activity(firm, id)
			if not local is Dictionary or not FormalLedgerState.exact_fields(local, ["desired", "schedule", "actual"]) or not FormalLedgerState.valid_amount(local["desired"]) or not FormalLedgerState.valid_amount(local["actual"]) or not local["schedule"] is Array or local["schedule"].size() != horizon:
				return _fail("Invalid activity intention or actual production")
			var total: int = 0
			for index: int in horizon:
				var entry: Variant = local["schedule"][index]
				if not entry is Dictionary or not FormalLedgerState.exact_fields(entry, ["day", "quantity"]) or entry["day"] != int(value["day"]) + index or not FormalLedgerState.valid_amount(entry["quantity"]) or int(entry["quantity"]) > _capital.capacity(firm, int(value["day"])*1440-1, id) / int(activity["capacity_units"]):
					return _fail("Invalid dated activity schedule")
				total += int(entry["quantity"])
				capacities[index] += int(entry["quantity"]) * int(activity["capacity_units"])
			if total > int(local["desired"]) or int(local["actual"]) > int(local["schedule"][0]["quantity"]) or int(local["actual"]) > int(value["site_state"][firm]["activities"][id]["batches"]) or (not config["production_enabled"] and total > 0):
				return _fail("Actual activity exceeds its scheduled intention")
			hours += int(local["actual"]) * int(activity["hours"])
		if hours+_capital.allocated_hours(firm, int(value["day"]))+_shared.allocated_hours(firm, int(value["day"]))+_service_market.allocated_hours(firm,int(value["day"]))+_retail.allocated_hours(firm,int(value["day"])) > worked:
			return _fail("Production activities reused the same labor hours")
		for capacity: int in capacities:
			if capacity > _capital.capacity(firm, int(value["day"])*1440-1):
				return _fail("Production activities duplicated shared capacity")
	return true


func _validate_transport(value: Dictionary) -> bool:
	var transport := value["transport"] as Dictionary
	var routes := _all_routes()
	if not FormalLedgerState.exact_fields(transport, ["edges", "nodes"]) or not transport["edges"] is Dictionary or not transport["nodes"] is Dictionary or transport["edges"].size() != routes.size() or transport["nodes"].size() != config.get("transport_nodes", []).size():
		return _fail("Missing shared physical edges or nodes")
	var capacities: Dictionary = {}
	for id: String in routes:
		capacities[id] = {"capacity": routes[id]["capacity"], "action_id": ""}
	for id: String in value["commands"]:
		var entry := value["commands"][id] as Dictionary
		var command := entry["envelope"]["command"] as Dictionary
		if command["kind"] != "set_edge_capacity" or not entry["result"]["accepted"]:
			continue
		var payload := command["payload"] as Dictionary
		if not FormalLedgerState.exact_fields(payload, ["edge_id", "capacity"]) or not payload["edge_id"] is String or not routes.has(payload["edge_id"]) or not FormalLedgerState.valid_amount(payload["capacity"]) or int(payload["capacity"]) > int(routes[payload["edge_id"]]["capacity"]) or routes[payload["edge_id"]].get("capacity_manager", "") != entry["envelope"]["actor"] or entry["result"].get("edge_id") != payload["edge_id"] or entry["result"].get("capacity") != payload["capacity"]:
			return _fail("Edge capacity change lacks configured authority")
		capacities[payload["edge_id"]] = {"capacity": payload["capacity"], "action_id": id}
	var entered: Dictionary = {}
	var nodes: Dictionary = {}
	var physical: Array = value["shipments"].values()
	physical.append_array(value["delivery_receipts"].values())
	var counted: Dictionary = {}
	for cargo: Dictionary in physical:
		var order := value["orders"][cargo["order_id"]] as Dictionary
		if cargo.has("departure_quantities") and counted.has(_cargo_origin_id(cargo)): continue
		if cargo.has("departure_quantities"): counted[_cargo_origin_id(cargo)] = true
		for index: int in cargo["departures"].size():
			if cargo["departures"][index] != value["day"]:
				continue
			var id := str(order["route_legs"][index]["edge_id"])
			var quantity: int = cargo["departure_quantities"][index] if cargo.has("departure_quantities") else cargo["quantity"]
			entered[id] = int(entered.get(id, 0)) + quantity
			var place := str(routes[id]["from_place_id"])
			nodes[place] = int(nodes.get(place, 0)) + quantity
	for id: String in routes:
		var edge: Variant = transport["edges"].get(id)
		if not edge is Dictionary or not FormalLedgerState.exact_fields(edge, ["period", "input_used", "dispatched", "holds", "capacity", "capacity_action"]) or not FormalLedgerState.valid_amount(edge["period"]) or edge["period"] != value["day"] or not edge["holds"] is Dictionary or not FormalLedgerState.valid_amount(edge["input_used"]) or not FormalLedgerState.valid_amount(edge["dispatched"]) or not FormalLedgerState.valid_amount(edge["capacity"]) or (not _shared.bindings.has(id) and (int(edge["input_used"]) > int(routes[id]["capacity"]) or int(edge["dispatched"]) > int(routes[id]["capacity"]))) or edge["capacity"] != capacities[id]["capacity"] or edge["capacity_action"] != capacities[id]["action_id"]:
			return _fail("Shared edge capacity or cursor conflict")
		var holds: Dictionary = {}
		var accepted: int = 0
		for order: Dictionary in value["orders"].values():
			if Retail.onsite(order) or order["route_legs"][0]["edge_id"] != id:
				continue
			if int(order["accepted_day"]) == int(value["day"]):
				accepted += int(order["quantity"]) - int(order["cancelled"])
			if int(order["pending"]) > 0:
				holds[order["id"]] = {"period": order["accepted_day"], "quantity": order["pending"]}
		if edge["holds"] != holds or int(edge["input_used"]) != accepted or int(edge["dispatched"]) != int(entered.get(id, 0)):
			return _fail("Shared edge responsibilities differ from actual segment entries")
	for row: Dictionary in config.get("transport_nodes", []):
		var node: Variant = transport["nodes"].get(row["place_id"])
		if not node is Dictionary or not FormalLedgerState.exact_fields(node, ["dispatched"]) or not FormalLedgerState.valid_amount(node["dispatched"]) or int(node["dispatched"]) != int(nodes.get(row["place_id"], 0)) or int(node["dispatched"]) > int(row["capacity"]):
			return _fail("Shared transfer-node capacity conflict")
	return true


func _accepted_command(value: Dictionary, actor: String, id: String, kind: String) -> bool:
	var entry: Variant = value["commands"].get(id)
	return entry is Dictionary and entry.get("envelope") is Dictionary and entry.get("result") is Dictionary and entry["envelope"].get("actor") == actor and entry["envelope"].get("command") is Dictionary and entry["envelope"]["command"].get("kind") == kind and bool(entry["result"].get("accepted", false))


func _sorted_ids(value: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(value.keys())
	ids.sort()
	return ids


func _result(accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "reason": reason}


func _fail(message: String) -> bool:
	error = message
	return false


func _zero_goods() -> Dictionary:
	return EconomySliceConfig.zero_stock(_goods)

func _consumption_goods(category: String, actor: String = "") -> Array[String]:
	var result: Array[String] = []
	for good: String in _goods:
		if _service(good, category) > 0:
			result.append(good)
	result.sort_custom(func(a: String, b: String) -> bool: return _service(a, category) > _service(b, category) if _service(a, category) != _service(b, category) else a < b)
	var preferred: Array = _cohort_profile(actor).get("goods_preference", {}).get(category, [])
	if not preferred.is_empty():
		var ordered: Array[String] = []
		for good: String in preferred:
			if good in result: ordered.append(good)
		for good: String in result:
			if good not in ordered: ordered.append(good)
		return ordered
	return result


func _population_unit(actor: String) -> String:
	return _world.population_state.unit_for_person(actor) if _spec["actors"][actor]["kind"] == "named" else _world.population_state.unit_for_place(str(_spec["actors"][actor].get("place_id", PLACE)))

func _population_bindings_valid() -> bool:
	var spans: Dictionary = {}
	for id: String in _spec["actors"]:
		var actor := _spec["actors"][id] as Dictionary
		var unit := _population_unit(id)
		var admission_minute: Variant = _subject_activation.get(id, _world.game_clock.total_minutes() if _management.get("status") == "ACTIVE" and not _actors.has(id) else 0)
		if not FormalLedgerState.valid_amount(admission_minute): return _fail("Invalid population admission time")
		var binding_unit := _world.population_state.residence_unit_at(id, int(admission_minute)) if actor["kind"] == "named" else unit
		if actor.has("population_unit_id") and actor["population_unit_id"] != binding_unit:
			return _fail("Actor initial population binding differs from its actual admission residence")
		if actor["kind"] != "cohort":
			continue
		var span := Vector2i(int(actor["population_start"]), int(actor["population_start"]) + int(actor["members"]))
		if span.y > int(_world.population_state.unit(unit).get("remaining_background_population", 0)):
			return _fail("Cohort exceeds the unmaterialized population of its host unit")
		for other: Vector2i in spans.get(unit, []):
			if span.x < other.y and other.x < span.y:
				return _fail("Cohorts overlap within their host population unit")
		if not spans.has(unit):
			spans[unit] = []
		spans[unit].append(span)
	return true

func _path_basis(path: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var edges := _all_routes()
	for id: String in path.get("edge_ids", []):
		result.append({"edge_id": id, "basis": edges[id].get("basis", "SYNTHETIC"), "source_link_id": edges[id].get("source_link_id", ""), "capacity_and_delay_basis": "DEVELOPMENT_CONFIGURATION"})
	return result

func _activity(firm: String, id: String) -> Dictionary:
	for row: Dictionary in _spec["sites"][_inventory_key(firm)]["activities"]:
		if row["id"] == id:
			return row
	return {}

func _configured_legacy_recipe(firm: String) -> bool:
	if not is_multi():
		return true
	for row: Dictionary in config["firms"]:
		if row["id"] == firm:
			return row.has("recipe")
	return false

func _initial_firm_state() -> Dictionary:
	var result: Dictionary = {}
	for firm: String in _firm_ids():
		result[firm] = {"operating": true}
	return result


func _firm_operating(firm: String) -> bool:
	if firm_finished(firm) or not bool(_firm_state.get(firm, {}).get("operating", true)):
		return false
	var association := str(_spec["firms"][firm].get("host_organization_id", ""))
	return association.is_empty() or _world.organization_state.is_organization_active(association)

## Manager authority is explicit configuration. Share holdings never grant it.
## A new activity enables an admitted recipe against existing shared equipment;
## it does not mint equipment, goods, cash, shares, or a second account.
func _firm_business_action(actor: String, kind: String, payload: Dictionary) -> Dictionary:
	var fields: Array[String] = []
	fields.assign(["firm", "operating"] if kind == "set_firm_operating" else ["firm", "site_id", "enabled", "production_enabled", "accepting_business"] if kind == "set_site_status" else ["firm", "activity_id", "enabled"])
	var optional: Array[String] = []
	optional.assign(["site_id"] if kind == "set_activity_enabled" else [])
	if not EconomySliceConfig._fields(payload, fields, optional) or not payload["firm"] is String or not _spec["firms"].has(payload["firm"]) or not _manager(actor, payload["firm"]):
		return _result(false, "NOT_FIRM_MANAGER_OR_INVALID_ACTION")
	var firm := str(payload["firm"])
	if kind == "set_firm_operating":
		if not payload["operating"] is bool:
			return _result(false, "INVALID_FIRM_STATUS")
		var association := str(_spec["firms"][firm].get("host_organization_id", ""))
		if payload["operating"] and not association.is_empty() and not _world.organization_state.is_organization_active(association):
			return _result(false, "HOST_ORGANIZATION_INACTIVE")
		_firm_state[firm]["operating"] = payload["operating"]
	else:
		var site := str(payload.get("site_id", _primary_site(firm)))
		if site_closed(site): return _result(false, "SITE_ALREADY_CLOSED")
		if not _spec["sites"].has(site) or _owner(site) != firm:
			return _result(false, "NOT_OWN_SITE")
		if kind == "set_site_status":
			for flag: String in ["enabled", "production_enabled", "accepting_business"]:
				if not payload[flag] is bool:
					return _result(false, "INVALID_SITE_STATUS")
			for flag: String in ["enabled", "production_enabled", "accepting_business"]:
				_site_state[site][flag] = payload[flag]
		else:
			if not payload["enabled"] is bool or not payload["activity_id"] is String or not _site_state[site]["activities"].has(payload["activity_id"]):
				return _result(false, "UNKNOWN_ACTIVITY")
			if payload["enabled"] and (not _site_operating(site) or _capital.capacity(site, _world.game_clock.total_minutes(), payload["activity_id"]) < int(_activity(site, payload["activity_id"])["capacity_units"])):
				return _result(false, "NO_EXISTING_SITE_CAPACITY")
			_site_state[site]["activities"][payload["activity_id"]]["enabled"] = payload["enabled"]
	_update_job_postings()
	var result := payload.duplicate(true)
	result.merge({"accepted": true, "reason": "ACCEPTED"})
	return result


func business_view(actor: String, firm: String, site: String, quantity_value: int=1, offset: int=0, limit: int=1) -> Dictionary:
	if not _spec["firms"].has(firm) or not _manager(actor,firm): return {}
	if site.is_empty(): site=_primary_site(firm)
	if not _spec["sites"].has(site) or _owner(site)!=firm or quantity_value<1 or quantity_value>1000000 or offset<0 or limit<1 or limit>16: return {}
	var candidates := _offers(firm,site)
	var rows: Array[Dictionary]=_managed_offer_rows(actor,firm,site,candidates,quantity_value,offset,limit)
	return {"firm_id":firm,"site_id":site,"minute":_world.game_clock.total_minutes(),"finance":_firm_finance_view(firm),"financial_actions":_business_credit_actions(actor,firm,quantity_value),"retail":_retail.view(site),"commercial_information":_commercial.business_view(actor,firm,site),"labor_market":_labor_market.business_view(actor,firm,site),"wind_down":_wind_down.view(actor,firm,quantity_value),"capital_resale":_capital.resale_business(actor,firm),"services":_service_market.business_view(actor,firm,site,quantity_value),"leases":_leases.view(actor,firm,site),"site":_site_operating_view(site),"offers":rows,"offer_total":candidates.size(),"offer_offset":offset,"sites":_spec["firms"][firm]["sites"].duplicate(),"orders":_active_by_buyer.get(firm,{}).size(),"identity_basis":_business_identity_basis(firm)}

## Callers validate the manager, own site and fixed query bounds first.
## Reuse the exact purchase/permission checks without unrelated business panels.
func _managed_offer_rows(actor: String, firm: String, site: String, candidates: Array, quantity_value: int, offset: int, limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for i: int in range(offset,mini(offset+limit,candidates.size())):
		var offer := candidates[i].duplicate(true) as Dictionary
		if not FormalLedgerState.valid_amount(offer.get("price")) or not FormalLedgerState.valid_amount(offer.get("freight_per_unit")):
			offer["can_order"]=false;offer["order_reason"]=offer.get("reason","UNKNOWN_QUOTATION");offer["request"]={}
			offer["comparison"]=_managed_purchase_comparison(actor,firm,site,offer,quantity_value)
			rows.append(offer);continue
		var payload := {"firm":firm,"buyer_site":site,"seller":offer["seller"],"seller_site":offer["seller_site"],"good":offer["good"],"quantity":quantity_value,"quote_id":offer["quote_id"],"path_id":offer["route_id"],"max_price":offer["price"],"denomination":offer["denomination"]}
		var components := _budget_plan(firm,offer["denomination"],offer["good"],offer["route_legs"],quantity_value,true,offer["price"])
		var roots: Array[String]=[]
		for component: Dictionary in components:
			if not component.has("rule_id"): continue
			var rule := _budgets.rule(component["rule_id"])
			if rule["basis"]!="EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY" and rule["root_authority"] not in roots: roots.append(rule["root_authority"])
		var cost := FormalLedgerState.ratio(int(offer["price"])+int(offer["freight_per_unit"]),quantity_value,1)
		if not cost.is_empty() and roots.size()==1:
			var context := _cargo_fulfilment._available_context(actor,firm,{"operation":"economy.procure","target":offer["seller"],"place":_place(site),"category":"goods:"+str(offer["good"]),"amount":cost.get("quotient",-1)},roots[0])
			if not context.is_empty(): payload["authorization_context"]=context
		var permission := _procurement_permission(actor,firm,payload,false,components,offer["seller"],_place(site),"goods:"+str(offer["good"]),cost.get("quotient",-1))
		offer["can_order"]=offer["reason"]=="OFFER" and offer["quantity"]>=quantity_value and _site_accepting(site) and not _firm_winding_down(firm) and _budget_ready(components) and permission["ok"]
		offer["order_reason"]="FIRM_STOPPED_NEW_PROCUREMENT" if not _site_accepting(site) or _firm_winding_down(firm) else "CUMULATIVE_BUDGET_OR_WINDOW" if not _budget_ready(components) else permission.get("reason","") if not permission["ok"] else offer["reason"] if offer["reason"]!="OFFER" else "QUANTITY_EXCEEDS_CURRENT_OFFER" if offer["quantity"]<quantity_value else offer["reason"]
		offer["request"]=payload
		offer["comparison"]=_managed_purchase_comparison(actor,firm,site,offer,quantity_value)
		rows.append(offer)
	return rows

## Own posted terms only. An active listing is not an accepted buyer commitment.
func _managed_listing_view(site: String, good: String) -> Dictionary:
	var minute: int = _world.game_clock.total_minutes()
	var configured: bool = _spec["sites"][site]["prices"].has(good) and _price(site, good) > 0
	var quote: Dictionary = _local_quotes.current(site, good)
	var future: Array[Dictionary] = []
	for row: Dictionary in _local_quotes.quotes.values():
		if row["site"] != site or row["good"] != good or int(row["effective_day"])*1440 <= minute: continue
		future.append({"quote_id":row["id"],"price":row["price"],"effective_minute":int(row["effective_day"])*1440,"expires_minute":int(row["expires_day"])*1440})
	var policy_state: Dictionary = _quote_state.get(site+"|"+good, {})
	if quote.is_empty() and int(policy_state.get("next_price", -1)) > 0 and int(policy_state.get("effective_day", -1))*1440 > minute:
		future.append({"quote_id":"","price":policy_state["next_price"],"effective_minute":int(policy_state["effective_day"])*1440,"expires_minute":null})
	future.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a["effective_minute"]) < int(b["effective_minute"]))
	var expired: bool = not quote.is_empty() and minute >= int(quote["expires_day"])*1440
	var paused: bool = _local_quotes.sales_paused(site,good)
	var control: Dictionary = _local_quotes.sales_controls.get(site+"|"+good,{})
	var active: bool = configured and _site_selling(site) and not expired and not paused
	var reserved_ids: Array[String] = []
	for id: String in _lots._by_location.get("SITE|"+site+"#"+good, {}):
		var reservation: String = str(_lots.portions[id].get("reserved_for", ""))
		if not reservation.is_empty() and reservation not in reserved_ids: reserved_ids.append(reservation)
	reserved_ids.sort()
	var reserved: int = _committed(site, good)
	return {"active":active,"price":_price(site,good) if configured else null,"denomination":_sale_currency(_owner(site)),"quote_id":quote.get("id", ""),"effective_minute":int(quote["effective_day"])*1440 if not quote.is_empty() else null,"expires_minute":int(quote["expires_day"])*1440 if not quote.is_empty() else null,"future_quotes":future,"reserved_quantity":reserved,"reserved_order_ids":reserved_ids,"free_quantity":maxi(0,int(_stocks[site].get(good,0))-reserved),"stock_quantity":int(_stocks[site].get(good,0)),"reason":"NO_LISTING" if not configured else "GOODS_NEW_SALES_PAUSED" if paused else "FIRM_STOPPED_NEW_BUSINESS" if not _site_selling(site) else "GOODS_QUOTE_EXPIRED" if expired else "LISTED","automatic_sale_possible":active,"price_change_next_day":not _local_quotes.rule(site,good).is_empty(),"price_changes_per_day":1 if not _local_quotes.rule(site,good).is_empty() else null,"pause_scope":"SITE_GOOD_NEW_SALES_ONLY","existing_orders_continue":true,"existing_supply_contracts_continue":true,"individual_delisting_supported":not _local_quotes.rule(site,good).is_empty(),"sales_control_supported":not _local_quotes.rule(site,good).is_empty(),"sales_paused":paused,"sales_control_effective_minute":control.get("effective_minute",null),"sales_control_sequence":control.get("adoption_sequence",null),"sales_control_quote_id":control.get("quote_id",""),"basis":"OWN_ORIGINAL_QUOTATIONS_NOT_GUARANTEED_SALES"}

func _managed_locked_sales(actor: String, firm: String, site: String, good: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contract: Dictionary in _supply.views(actor):
		if contract.get("supplier") != firm or contract.get("supplier_site") != site or contract.get("good") != good or not contract.has("accept_action"): continue
		if contract.get("status") not in ["ACCEPTED", "PARTIAL", "OVERDUE"]: continue
		# Original acceptance requires a known zero-freight local route. This is
		# a term of this contract only, not a promise to buy every new stock lot.
		result.append({"id":contract["id"],"kind":"SUPPLY_CONTRACT","contract_id":contract["id"],"order_id":"","order_ids":contract.get("batches",[]).duplicate(),"buyer":contract["buyer"],"buyer_site":contract["buyer_site"],"price":contract["price"],"denomination":_sale_currency(firm),"remaining":contract.get("remaining",0),"unallocated":contract.get("unallocated",0),"deadline":contract["deadline"],"status":contract["status"],"onward_delivery":{"known":true,"amount":0,"freight_per_unit":0,"payer":"BUYER","basis":"ACCEPTED_SUPPLY_REQUIRES_ZERO_FREIGHT_LOCAL_ROUTE"}})
	for order: Dictionary in _orders.values():
		if order["kind"] != "SALE" or order["seller"] != firm or order["seller_site"] != site or order["good"] != good or order.has("supply_contract_id"): continue
		var remaining: int = int(order["pending"])+int(order["transit"])
		if remaining <= 0: continue
		result.append({"id":order["id"],"kind":"SALE_ORDER","contract_id":"","order_id":order["id"],"order_ids":[order["id"]],"buyer":order["buyer"],"buyer_site":order["buyer_site"],"price":order["price"],"denomination":order["denomination"],"remaining":remaining,"unallocated":0,"deadline":null,"status":"PENDING_DELIVERY","onward_delivery":{"known":true,"amount":0,"freight_per_unit":_freight(order["route_legs"]),"firm_amount":0,"buyer_commitment":FormalLedgerState.ratio(_freight(order["route_legs"]),remaining,1).get("quotient",null),"denomination":order["denomination"],"payer":"BUYER","basis":"ORIGINAL_SALE_ORDER_AMOUNT_IS_MANAGED_FIRM_COST_BUYER_PAYS_FREIGHT"}})
	return result

## One received source/path, never minimum price times unrelated supply.
## No reservations, observations, orders, lots or Ledger writes occur here.
func _managed_purchase_comparison(actor: String, firm: String, site: String, offer: Dictionary, requested: int) -> Dictionary:
	var good: String = str(offer["good"])
	var currency: String = str(offer["denomination"])
	var listing: Dictionary = _managed_listing_view(site, good)
	var locked: Array[Dictionary] = _managed_locked_sales(actor, firm, site, good)
	var quantity: int = mini(requested, maxi(0,int(offer.get("quantity",0))))
	quantity = mini(quantity, maxi(0,FormalLedgerState.MAX_AMOUNT-_exposure(site,good)))
	quantity = mini(quantity, _retail.headroom(site,good))
	var known: bool = FormalLedgerState.valid_amount(offer.get("price")) and FormalLedgerState.valid_amount(offer.get("freight_per_unit")) and not str(offer.get("route_id","")).is_empty()
	var why: String = str(offer.get("order_reason",offer.get("reason","UNKNOWN_QUOTATION")))
	var request: Dictionary = offer.get("request",{}).duplicate(true)
	if not known or offer.get("reason") != "OFFER" or not _site_accepting(site) or _firm_winding_down(firm): quantity = 0
	if quantity > 0:
		var legs: Array = offer.get("route_legs",[])
		var components: Array[Dictionary] = _budget_plan(firm,currency,good,legs,quantity,true,int(offer["price"]))
		request["quantity"] = quantity
		var cost: Dictionary = FormalLedgerState.ratio(int(offer["price"])+int(offer["freight_per_unit"]),quantity,1)
		var roots: Array[String] = []
		for component: Dictionary in components:
			if not component.has("rule_id"): continue
			var rule: Dictionary = _budgets.rule(component["rule_id"])
			if rule["basis"] != "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY" and rule["root_authority"] not in roots: roots.append(str(rule["root_authority"]))
		if not cost.is_empty() and roots.size() == 1:
			var context: Dictionary = _cargo_fulfilment._available_context(actor,firm,{"operation":"economy.procure","target":offer["seller"],"place":_place(site),"category":"goods:"+good,"amount":cost["quotient"]},roots[0])
			if not context.is_empty(): request["authorization_context"] = context
		var permission: Dictionary = _procurement_permission(actor,firm,request,false,components,str(offer["seller"]),_place(site),"goods:"+good,int(cost.get("quotient",-1)))
		if _account(firm,currency).is_empty() or _account(str(offer["seller"]),currency).is_empty(): quantity=0;why="PURCHASE_CURRENCY_ACCOUNT"
		elif not _shared.path_conditions(legs,good): quantity=0;why="UNCONFIGURED_SHARED_WEIGHT_OR_SERVICE_WINDOW"
		elif not _budget_ready(components): quantity=0;why="CUMULATIVE_BUDGET_OR_WINDOW"
		elif not permission.get("ok",false): quantity=0;why=str(permission.get("reason","NO_PROCUREMENT_AUTHORITY"))
		elif cost.is_empty() or next_order >= FormalLedgerState.MAX_AMOUNT: quantity=0;why="QUANTITY_BOUNDS"
		elif _lots.selection("SITE|"+str(offer["seller_site"]),good,quantity).is_empty(): quantity=0;why="UNCOMMITTED_SOURCE_PORTIONS_UNAVAILABLE"
		else: why="PARTIAL_CURRENT_OFFER" if quantity < requested else "OFFER"
	var goods: Variant = null
	var freight: Variant = null
	var total: Variant = null
	if known:
		goods = FormalLedgerState.ratio(int(offer["price"]),quantity,1).get("quotient",null)
		freight = FormalLedgerState.ratio(int(offer["freight_per_unit"]),quantity,1).get("quotient",null)
		total = FormalLedgerState.ratio(int(offer["price"])+int(offer["freight_per_unit"]),quantity,1).get("quotient",null)
	var scenario: Dictionary = {"known":false,"sales_amount":null,"known_cash_difference":null,"quantity":quantity,"basis":"CURRENT_LISTING_IF_SOLD_NOT_FORECAST_EXCLUDES_UNKNOWN_ONWARD_COSTS"}
	if quantity > 0 and total != null and listing["active"] and listing["denomination"] == currency:
		var sales_amount: Variant = FormalLedgerState.ratio(int(listing["price"]),quantity,1).get("quotient",null)
		if sales_amount != null: scenario.merge({"known":true,"sales_amount":sales_amount,"known_cash_difference":int(sales_amount)-int(total)},true)
	return {"requested_quantity":requested,"acceptable_quantity":quantity,"currently_acceptable_quantity":quantity,"source_available_quantity":offer.get("quantity",0),"goods_commitment":goods,"inbound_freight_commitment":freight,"freight_commitment":freight,"maximum_cash_commitment":total,"total_commitment":total,"commitment_quantity":quantity,"denomination":currency,"destination_site":site,"supplier_price":offer.get("price",null),"supplier_quote_id":offer.get("published_quote_id",offer.get("quote_id","")),"supplier_site":offer["seller_site"],"route_id":offer.get("route_id",""),"inbound_freight_per_unit":offer.get("freight_per_unit",null),"own_listing":listing,"sale_listing":listing.duplicate(true),"locked_sales_contracts":locked,"locked_sales":locked.duplicate(true),"onward_delivery":{"known":false,"amount":null,"payer":"UNKNOWN_UNTIL_BUYER_AND_ORDER_EXIST","basis":"NO_SALE_OR_LOT_ALLOCATION_FOR_THIS_NEW_PURCHASE"},"scenario":scenario,"order_reason":why,"acceptable_request":request if quantity > 0 else {},"basis":"READ_ONLY_CURRENT_SINGLE_SOURCE_NOT_GUARANTEED_FUTURE_RECEIPTS"}

## Same received offers and ordering used by _procure_inputs. No discovery,
## reservations or commands occur here. Other firms' need/cash/stock are omitted.
func managed_network_contacts(actor: String, firm: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _spec["firms"].has(firm) or not _manager(actor,firm): return result
	for site: String in _spec["firms"][firm]["sites"]:
		var ranks: Dictionary = {}
		var needs: Dictionary = {}
		var executable: Dictionary = {}
		var candidates: Array=_offers(firm,site)
		for row: Dictionary in _managed_offer_rows(actor,firm,site,candidates,1,0,candidates.size()):executable[str(row.quote_id)]=row
		for offer: Dictionary in candidates:
			var good: String = offer["good"]
			if not needs.has(good):
				needs[good] = _input_need(site,good)
				if int(needs[good]["regular_quantity"])>0 or int(needs[good]["timing_projection"]["uncovered_future_quantity"])>0:
					var ranked: Array[Dictionary] = _input_offers(site,good,int(needs[good]["need_by_day"]),maxi(int(needs[good]["regular_quantity"]),int(needs[good]["timing_projection"]["uncovered_future_quantity"])),needs[good])
					for index: int in ranked.size():
						ranks[str(ranked[index]["quote_id"])] = index+1
			var request_quantity: int=int(needs[good]["quantity"])
			if needs[good]["npc_timing_adoption"]:request_quantity=maxi(int(needs[good]["regular_quantity"]),maxi(0,int(needs[good]["timing_projection"]["uncovered_future_quantity"])-int(needs[good]["timing_projection"]["unknown_responsibility_hold"])))
			var executable_offer: Dictionary=executable.get(str(offer.quote_id),{})
			var comparison: Dictionary=executable_offer.get("comparison",{})
			var row: Dictionary = {"buyer_site":site,"need_quantity":request_quantity,"legacy_stock_position_need":needs[good]["quantity"],"known_late_quantity":needs[good]["incoming_observation"]["known_late"],"unknown_arrival_quantity":needs[good]["incoming_observation"]["unknown_arrival"],"can_order_one":executable_offer.get("can_order",false),"order_reason":executable_offer.get("order_reason","UNKNOWN"),"autonomous_rank":ranks.get(str(offer["quote_id"]),null),"basis":"RECEIVED_OFFERS_ORIGINAL_PROCUREMENT_ORDER_NOT_FUTURE_ORDER"}
			row["landed_unit_cost"]=int(offer.price)+int(offer.freight_per_unit) if typeof(offer.get("price"))==TYPE_INT and typeof(offer.get("freight_per_unit"))==TYPE_INT else null
			row["can_order_one"]=bool(row.can_order_one) and int(comparison.get("acceptable_quantity",0))>=1
			if not row.can_order_one:row["order_reason"]=comparison.get("order_reason",row.order_reason)
			var experience: Dictionary=_cooperation_view(site,offer.seller_site,good)
			var lower: Variant=_input_offer_arrival(offer)
			row["observed_arrival_day"]=int(lower)+int(experience.average_delay_days) if lower!=null else null
			row["average_delay_days"]=experience.average_delay_days
			row["delivery_samples"]=experience.deliveries.size()
			for key: String in ["quote_id","published_quote_id","quote_expires_minute","seller","seller_site","good","price","denomination","quantity","transport_quantity","freight_per_unit","route_id","from_place_id","to_place_id","earliest_arrival_day","eta_guaranteed","reason","minute"]:
				if offer.has(key): row[key] = offer[key]
			result.append(row)
	return result

func _business_identity_basis(firm: String) -> String:
	for row: Dictionary in config.get("development_organizations",[]):
		if row["firm_id"]==firm: return "EXPLICIT_DEVELOPMENT_COMMERCIAL_ORGANIZATION"
	return "HOST_COMMERCIAL_ORGANIZATION" if not str(_spec["firms"][firm].get("host_organization_id","")).is_empty() else "DEVELOPMENT_ENTERPRISE"

func managed_firm(actor: String, firm: String) -> Dictionary:
	if not _actors.has(actor) or _actors[actor]["control"] != "player" or not _spec["firms"].has(firm) or not _manager(actor, firm):
		return {}
	var result := _visible_subject(firm)
	result["cargo_fulfilment"] = _cargo_fulfilment.visible(actor)
	result["resident_services"] = _service_market._resident.personal_view(actor)
	result["leases"] = _leases.view(actor,firm,_primary_site(firm))
	var employees: Array[Dictionary] = []
	for worker: String in _contracts:
		for contract: Dictionary in _contract_rows(_contracts[worker]):
			var job := _labor_market.contract_job(contract)
			if job["employer"] == firm:
				employees.append({"worker_id": worker, "job_id": job["id"], "site_id": job["site_id"], "work_place_id": job["place"], "workers": contract["workers"], "booked_work": _work_queue.get(worker, {}).get("allocations", {}).get(job["id"], {}).duplicate(true) if not _cohort_profile(worker).is_empty() else _work_queue.get(worker, {}).duplicate(true)})
	result["employees"] = employees
	result["transport_facilities"] = {}
	for site: String in _spec["firms"][firm]["sites"]: result["transport_facilities"][site] = _shared.site_resource_view(site)
	result["physical_batches"] = {}
	for site: String in _spec["firms"][firm]["sites"]: result["physical_batches"][site] = owned_batch_rows(actor, site)
	result["lifecycle"] = enterprise_lifecycle_view(actor, firm)
	return result


func _validate_firm_state(value: Dictionary) -> bool:
	var states := value["firm_state"] as Dictionary
	var sites := value["site_state"] as Dictionary
	var expected := _initial_firm_state()
	var expected_sites := _initial_site_state()
	if states.size() != expected.size() or sites.size() != expected_sites.size():
		return _fail("Missing firm or site operating responsibility")
	for firm: String in expected:
		var state: Variant = states.get(firm)
		if not state is Dictionary or not FormalLedgerState.exact_fields(state, ["operating"]) or not state["operating"] is bool:
			return _fail("Invalid firm operating state")
	for site: String in expected_sites:
		var state: Variant = sites.get(site)
		var ids: Array[String] = []
		ids.assign(expected_sites[site]["activities"].keys())
		if not state is Dictionary or not FormalLedgerState.exact_fields(state, ["enabled", "production_enabled", "accepting_business", "activities"]) or not state["activities"] is Dictionary or not FormalLedgerState.exact_fields(state["activities"], ids):
			return _fail("Invalid site activity state")
		for flag: String in ["enabled", "production_enabled", "accepting_business"]:
			if not state[flag] is bool:
				return _fail("Invalid site operating flag")
		for id: String in ids:
			var activity: Variant = state["activities"][id]
			if not activity is Dictionary or not FormalLedgerState.exact_fields(activity, ["enabled", "batches"]) or not activity["enabled"] is bool or not FormalLedgerState.valid_amount(activity["batches"]):
				return _fail("Invalid activity execution responsibility")
	# Restore flags from accepted management actions, without running them again.
	for entry: Dictionary in _operating_history(value["commands"]):
		var command := entry["envelope"]["command"] as Dictionary
		var kind := str(command["kind"])
		if kind not in ["set_activity_enabled", "set_site_status", "set_firm_operating", "close_site", "finish_firm", "wind_down_firm"] or not entry["result"]["accepted"]:
			continue
		var payload := command["payload"] as Dictionary
		var fields: Array[String] = []
		fields.assign(["firm", "operating"] if kind == "set_firm_operating" else ["firm", "site_id", "enabled", "production_enabled", "accepting_business"] if kind == "set_site_status" else ["firm", "site_id"] if kind == "close_site" else ["firm"] if kind in ["finish_firm", "wind_down_firm"] else ["firm", "activity_id", "enabled"])
		var optional: Array[String] = []
		optional.assign(["site_id"] if kind == "set_activity_enabled" else [])
		if not EconomySliceConfig._fields(payload, fields, optional) or not payload["firm"] is String or not expected.has(payload["firm"]) or not _manager_at(entry["envelope"]["actor"], payload["firm"], command["minute"]):
			return _fail("Operating command lacks explicit manager authority")
		var firm := str(payload["firm"])
		for key: String in payload:
			if entry["result"].get(key) != payload[key]:
				return _fail("Operating result differs from accepted action")
		if kind == "wind_down_firm":
			if not _wind_down.controls(firm): expected[firm]["operating"] = true
			continue
		if kind == "finish_firm":
			expected[firm]["operating"] = false
			continue
		if kind == "set_firm_operating":
			if not payload["operating"] is bool:
				return _fail("Invalid firm operating flag")
			expected[firm]["operating"] = payload["operating"]
			continue
		var site := str(payload.get("site_id", _primary_site(firm)))
		if not expected_sites.has(site) or _owner(site) != firm:
			return _fail("Management action changed another firm's site")
		if kind == "close_site":
			for flag: String in ["enabled", "production_enabled", "accepting_business"]: expected_sites[site][flag] = false
		elif kind == "set_site_status":
			for flag: String in ["enabled", "production_enabled", "accepting_business"]:
				if not payload[flag] is bool:
					return _fail("Invalid site status command")
				expected_sites[site][flag] = payload[flag]
		else:
			if not payload["enabled"] is bool or not payload["activity_id"] is String or not expected_sites[site]["activities"].has(payload["activity_id"]):
				return _fail("Unknown managed site activity")
			if payload["enabled"] and (not expected[firm]["operating"] or not expected_sites[site]["enabled"] or _capital.capacity(site, int(command["minute"]), payload["activity_id"]) < int(_activity(site, payload["activity_id"])["capacity_units"])):
				return _fail("Activity enabled without existing site equipment")
			expected_sites[site]["activities"][payload["activity_id"]]["enabled"] = payload["enabled"]
	for firm: String in expected:
		if states[firm] != expected[firm]:
			return _fail("Firm status lost its manager action")
	for site: String in expected_sites:
		for flag: String in ["enabled", "production_enabled", "accepting_business"]:
			if sites[site][flag] != expected_sites[site][flag]:
				return _fail("Site status lost its manager action")
		for id: String in expected_sites[site]["activities"]:
			if sites[site]["activities"][id]["enabled"] != expected_sites[site]["activities"][id]["enabled"]:
				return _fail("Activity status lost its manager action")
	for site: Variant in value["site_reports"]:
		var report: Variant = value["site_reports"][site]
		if not report is Dictionary or not _valid_site_report(report) or report["candidate"] != site or int(report["delivery_day"]) > int(value["day"]) or int(report["order_cursor"]) > int(value["next_order"]):
			return _fail("Invalid delivered internal site information")
	return true


func _host_firm_bindings_valid() -> bool:
	var associations: Dictionary = {}
	for carrier: Dictionary in config.get("carriers",[]):
		if not carrier.has("host_organization_id"): continue
		if not _world.organization_state.has_organization(carrier["host_organization_id"]) or _world.organization_state.organization_kind(carrier["host_organization_id"]) not in ["company","corporation","enterprise"]: return _fail("Carrier financial association requires an existing commercial organization")
	for firm: String in _firm_ids():
		var row := _spec["firms"][firm] as Dictionary
		if not row.has("host_organization_id"):
			continue
		var id := str(row["host_organization_id"])
		if associations.has(id) or not _world.organization_state.has_organization(id) or _world.organization_state.organization_kind(id) not in ["company", "corporation", "enterprise"] or (not _world.organization_state.primary_place_id(id).is_empty() and _world.organization_state.primary_place_id(id) != row["place_id"]):
			return _fail("Firm binding requires an existing commercial organization with its declared headquarters: " + firm + "/" + id)
		associations[id] = firm
	return true


func _material_batches(firm: String, activity: Dictionary, stock: Dictionary, wanted: int) -> int:
	var quantity := wanted
	for good: String in _goods:
		var coefficient := int(activity["materials"][good])
		if coefficient > 0:
			quantity = mini(quantity, maxi(0, int(stock[good]) - _committed(firm, good)) / coefficient)
	return quantity

func _planning_activity_order(firm: String, urgent: Dictionary) -> Array[String]:
	var depths: Dictionary = {}
	var deadline: Dictionary = {}
	var pressure: Dictionary = {}
	var feasible: Dictionary = {}
	var order: Array[String] = []
	order.assign(_spec["sites"][firm]["activity_order"])
	for id: String in order:
		var activity := _activity(firm, id)
		depths[id] = 0
		for prior: String in depths:
			if prior == id:
				continue
			for good: String in _activity(firm, prior)["outputs"]:
				if int(activity["materials"][good]) > 0:
					depths[id] = maxi(int(depths[id]), int(depths[prior]) + 1)
		deadline[id] = day + int(_operations_policy(firm)["planning_horizon"])
		pressure[id] = 0
		for good: String in activity["outputs"]:
			pressure[id] = int(pressure[id]) + int(urgent[good])
			for order_id: String in _pending_ids_by_key.get(firm + "|" + good, {}):
				var customer_order := _orders[order_id] as Dictionary
				var payload := _commands.get(customer_order["action_id"], {}).get("envelope", {}).get("command", {}).get("payload", {}) as Dictionary
				var due := int(payload.get("need_by_day", _earliest_dispatch(customer_order) + _travel_days(customer_order["route_legs"])))
				deadline[id] = mini(int(deadline[id]), maxi(day, due))
			for request: Dictionary in _request_pressure_records(firm,good):
				if _request_supply_pressure(request) > 0 and int(request.get("need_by_day", -1)) >= day:
					deadline[id] = mini(int(deadline[id]), int(request["need_by_day"]))
		feasible[id] = _material_batches(firm, activity, _stocks[firm], _capital.capacity(firm, _production_minute(), id) / int(activity["capacity_units"]))
	# Descending local dependency depth lets downstream demands reach their own
	# upstream activities. Within a layer, current requests and actual ingredients
	# decide which alternative recipe receives the still uncovered product demand.
	order.sort_custom(func(a: String, b: String) -> bool:
		if depths[a] != depths[b]:
			return int(depths[a]) > int(depths[b])
		if deadline[a] != deadline[b]:
			return int(deadline[a]) < int(deadline[b])
		if pressure[a] != pressure[b]:
			return int(pressure[a]) > int(pressure[b])
		if (int(feasible[a]) > 0) != (int(feasible[b]) > 0):
			return int(feasible[a]) > 0
		return a < b)
	return order


func _site_ids() -> Array[String]:
	return _sorted_ids(_spec["sites"])

func _owner(subject: String) -> String:
	return str(_spec["sites"][subject]["firm_id"]) if _spec.get("sites", {}).has(subject) else subject

func _primary_site(firm: String) -> String:
	return str(_spec["firms"].get(firm, {}).get("primary_site", ""))

func _inventory_key(subject: String, site: String = "") -> String:
	return site if not site.is_empty() else _primary_site(subject) if _spec["firms"].has(subject) else subject

func _destination(order: Dictionary) -> String:
	return str(order["buyer_site"]) if not str(order["buyer_site"]).is_empty() else str(order["buyer"])

func _candidate(key: String) -> Dictionary:
	var parts := key.split("|")
	return {"seller": parts[0], "good": parts[1], "site": parts[2] if parts.size() == 3 else _primary_site(parts[0])}

func _directory_candidate(entry: Dictionary) -> String:
	return str(entry["seller"]) + "|" + str(entry["good"]) + "|" + str(entry.get("site_id", _primary_site(entry["seller"])))

func _known_suppliers(subject: String) -> Array:
	if _actors.has(subject):
		return _actors[subject]["known_suppliers"]
	if _spec["sites"].has(subject):
		return _firm_knowledge.get(subject, [])
	var result: Array = []
	for site: String in _spec["firms"].get(subject, {}).get("sites", []):
		for candidate: String in _firm_knowledge.get(site, []):
			if not result.has(candidate):
				result.append(candidate)
	return result

func _manager(actor: String, firm: String) -> bool:
	return _manager_at(actor, firm, _world.game_clock.total_minutes())

func _site_operating(site: String, at_minute: int = -1) -> bool:
	return not site_closed(site) and _firm_operating(_owner(site)) and bool(_site_state.get(site, {}).get("enabled", false)) and _leases.site_allowed(site,at_minute)

func _site_accepting(site: String) -> bool:
	return _site_operating(site) and bool(_site_state[site]["accepting_business"])

func _site_selling(site: String) -> bool:
	return _site_accepting(site) and _wind_down.selling(site)

func _site_producing(site: String, at_minute: int = -1) -> bool:
	return not _firm_winding_down(_owner(site)) and _site_operating(site,at_minute) and bool(_site_state[site]["production_enabled"])

func _initial_site_state() -> Dictionary:
	var result: Dictionary = {}
	for site: String in _site_ids():
		var row := _spec["sites"][site] as Dictionary
		var state := {"enabled": row["enabled"], "production_enabled": row["production_enabled"], "accepting_business": row["accepting_business"], "activities": {}}
		for activity: Dictionary in row["activities"]:
			state["activities"][activity["id"]] = {"enabled": activity["enabled"], "batches": 0}
		result[site] = state
	return result

func _inventory_view(subject: String) -> Dictionary:
	if not _spec["firms"].has(subject):
		return (_stocks.get(subject, {}) as Dictionary).duplicate(true)
	var total := _zero_goods()
	for site: String in _spec["firms"][subject]["sites"]:
		for good: String in _goods:
			total[good] = int(total[good]) + int(_stocks[site][good])
	return total

func _quote_id(minute: int, buyer: String, seller: String, good: String, route: String, source: String, destination: String) -> String:
	return "quote:" + str(minute) + ":" + buyer + ":" + seller + ":" + good + ":" + route + ":" + source + ":" + destination

func _publish_site_reports() -> void:
	for site: String in _site_ids():
		var inventory := _zero_goods()
		for good: String in _goods:
			inventory[good] = maxi(0, int(_stocks[site][good]) - _committed(site, good))
		var local_needs: Dictionary = {}
		for good: String in _goods: local_needs[good] = _input_need(site, good)
		var surplus := _zero_goods()
		for good: String in _goods:
			var retained := maxi(int(_spec["sites"][site]["targets"][good]), int(local_needs[good]["target"]))
			surplus[good] = maxi(0, int(inventory[good]) - retained)
		var needs: Dictionary = {}
		for good: String in _goods:
			var need := local_needs[good] as Dictionary
			needs[good] = {"quantity": maxi(maxi(int(need["regular_quantity"]), maxi(0, int(need["timing_projection"]["uncovered_future_quantity"]) - int(need["timing_projection"]["unknown_responsibility_hold"]))), _capital.goods_needed(site, good)-maxi(0, _exposure(site, good)-_committed(site, good))) if _site_accepting(site) else 0, "need_by_day": need["need_by_day"]}
		var report := {"id": "site_report:" + site + ":" + str(day), "actor": _owner(site), "kind": "site_report", "candidate": site, "observed_day": day, "delivery_day": day + int(_spec["sites"][site]["coordination_delay"]), "inventory": inventory, "surplus": surplus, "needs": needs, "order_cursor": next_order, "producing": _site_producing(site), "labor_hours": int(_plans.get(site, {}).get("labor_hours", 0))}
		if int(report["delivery_day"]) == day:
			_site_reports[site] = report
		else:
			_messages.append(report)


func _category_order() -> Array[String]:
	var result: Array[String] = []
	result.assign(_spec["categories"].keys())
	result.sort_custom(func(a: String, b: String) -> bool: return int(_spec["categories"][a]["priority"]) < int(_spec["categories"][b]["priority"]) if _spec["categories"][a]["priority"] != _spec["categories"][b]["priority"] else a < b)
	return result

func _service(good: String, category: String) -> int:
	return int(_services.get(good, {}).get(category, 0)) if _spec["categories"].has(category) else 0

func _initial_need_totals(actor: String) -> Dictionary:
	var result: Dictionary = {}
	for category: String in _category_order():
		result[category] = {"required": 0, "satisfied": 0, "unmet": 0, "used_items": _zero_goods()}
	return result

## A temporary use allocation prevents one multi-use item covering every need.
## Durable targets use one held service target; flow targets use the stock horizon.
func _household_position(actor: String, incoming: bool) -> Dictionary:
	if incoming: return HouseholdTiming.position(self,actor)
	var items := personal_inventory(actor) if manages_person(actor) else (_stocks[actor] as Dictionary).duplicate(true)
	if incoming:
		for id: String in _active_by_buyer.get(actor, []):
			var order := _orders[id] as Dictionary
			if order["kind"] == "SALE" and order["need_category"] == "" and (not manages_person(actor) or order["to_place_id"] == _place(actor)):
				items[order["good"]] = int(items[order["good"]]) + int(order["pending"]) + int(order["transit"])
	var result: Dictionary = {}
	for category: String in _actor_categories(actor):
		var target := _daily_need(actor, category)
		if incoming and _spec["categories"][category]["mode"] == "flow":
			var elapsed := maxi(1, _managed_days(actor, day))
			target = _need_total(actor, category, elapsed+int(config["stock_horizon"])-1)-_need_total(actor, category, elapsed-1)
		var covered: int = mini(target,_service_market._resident.planning_cover(actor)) if incoming and category=="food" else 0
		if incoming:
			for id: String in _active_by_buyer.get(actor, []):
				var order := _orders[id] as Dictionary
				if order["kind"] == "SALE" and order["need_category"] == category and (not manages_person(actor) or order["to_place_id"] == _place(actor)):
					covered = mini(target, covered + (int(order["pending"]) + int(order["transit"])) * _service(order["good"], category))
		for good: String in _consumption_goods(category, actor):
			var unit := _service(good, category)
			var amount := mini(int(items[good]), (maxi(0, target - covered) + unit - 1) / unit)
			items[good] = int(items[good]) - amount
			covered = mini(target, covered + amount * unit)
		result[category] = {"target": target, "covered": covered, "uncovered": target - covered, "mode": _spec["categories"][category]["mode"]}
	return result

## Internal movement shares orders, reservations, segment entry and final arrival.
## No goods-payment leg is created between two sites owned by the same firm.
func _transfer_goods(actor: String, payload: Dictionary, action_id: String, internal: bool = false) -> Dictionary:
	if not EconomySliceConfig._fields(payload, ["firm", "from_site", "to_site", "good", "quantity", "path_id", "denomination", "max_freight"], ["authorization_context"]) or not payload["firm"] is String or not _spec["firms"].has(payload["firm"]) or not _manager(actor, payload["firm"]):
		return _result(false, "INVALID_TRANSFER_AUTHORITY")
	var firm := str(payload["firm"])
	for field: String in ["from_site", "to_site"]:
		if not payload[field] is String or not _spec["sites"].has(payload[field]) or _owner(payload[field]) != firm:
			return _result(false, "NOT_OWN_SITE")
	if firm_finished(firm) or site_closed(payload["from_site"]) or site_closed(payload["to_site"]): return _result(false, "CLOSED_SITE_CANNOT_ACCEPT_NEW_TRANSFER")
	if payload["from_site"] == payload["to_site"] or payload["good"] not in _goods or not payload["path_id"] is String or not FormalLedgerState.valid_amount(payload["quantity"]) or int(payload["quantity"]) < 1 or int(payload["quantity"]) > 1000000 or not FormalLedgerState.valid_amount(payload["max_freight"]) or not FormalLedgerState.currency_id(payload["denomination"]):
		return _result(false, "INVALID_TRANSFER")
	var path := _route_for(firm, firm, payload["path_id"], payload["to_site"], payload["from_site"])
	if path.is_empty():
		return _result(false, "NO_KNOWN_ROUTE")
	var legs := _locked_legs(path, payload["denomination"])
	if not _shared.path_conditions(legs, payload["good"]): return _result(false, "UNCONFIGURED_SHARED_WEIGHT_OR_SERVICE_WINDOW")
	var freight := _freight(legs)
	var account := _account(firm, payload["denomination"])
	if account.is_empty() or freight > int(payload["max_freight"]):
		return _result(false, "TRANSFER_CURRENCY_OR_FREIGHT_LIMIT")
	for leg: Dictionary in legs:
		if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == account):
			return _result(false, "FREIGHT_CURRENCY_ACCOUNT")
	var available := maxi(0, int(_stocks[payload["from_site"]][payload["good"]]) - _committed(payload["from_site"], payload["good"]))
	var headroom := maxi(0, FormalLedgerState.MAX_AMOUNT - _exposure(payload["to_site"], payload["good"]))
	headroom=mini(headroom,_retail.headroom(payload["to_site"],payload["good"]))
	var quantity := mini(headroom, mini(int(payload["quantity"]), mini(available, _route_available(path))))
	if freight > 0:
		quantity = mini(quantity, mini(FormalLedgerState.MAX_AMOUNT / freight, _world.ledger_state.available_balance(account) / freight))
	if quantity <= 0 or next_order >= FormalLedgerState.MAX_AMOUNT:
		return _result(false, "NO_TRANSFER_STOCK_CASH_OR_CAPACITY")
	var id := "order:" + str(next_order)
	var components := _budget_plan(firm, payload["denomination"], payload["good"], legs, quantity, false)
	if not _budget_ready(components): return _result(false, "CUMULATIVE_FREIGHT_BUDGET_OR_WINDOW")
	var permission := _procurement_permission(actor, firm, payload, internal, components, _all_routes()[legs[0]["edge_id"]]["carrier"], _place(payload["from_site"]), "freight:"+str(legs[0]["edge_id"]), quantity*freight)
	if not permission["ok"]: return _result(false, permission["reason"])
	if _lots.selection("SITE|"+str(payload["from_site"]), payload["good"], quantity).is_empty(): return _result(false, "UNCOMMITTED_SOURCE_PORTIONS_UNAVAILABLE")
	if freight > 0 and not _world.ledger_state.reserve(id, account, quantity * freight):
		return _result(false, "INSUFFICIENT_TRANSFER_CASH")
	var budget_committed := _budgets.commit(id, components)
	assert(budget_committed)
	var portions_reserved := _lots.reserve(id, "SITE|"+str(payload["from_site"]), payload["good"], quantity, _world.game_clock.total_minutes())
	assert(portions_reserved)
	next_order += 1
	_orders[id] = {"id": id, "kind": "TRANSFER", "buyer": firm, "seller": firm, "buyer_site": payload["to_site"], "seller_site": payload["from_site"], "need_category": "", "good": payload["good"], "quantity": quantity, "pending": quantity, "transit": 0, "delivered": 0, "cancelled": 0, "price": 0, "action_id": action_id, "accepted_day": day, "accepted_minute": _world.game_clock.total_minutes(), "denomination": payload["denomination"], "buyer_account": account, "seller_account": account, "route_id": path["id"], "from_place_id": path["from_place_id"], "to_place_id": path["to_place_id"], "route_legs": legs}
	_pending_orders.append(id)
	_active_orders.append(id)
	_index_order(id)
	var edge := _edge(legs[0]["edge_id"])
	edge["input_used"] = int(edge["input_used"]) + quantity
	edge["holds"][id] = {"period": day, "quantity": quantity}
	var result := {"accepted": true, "reason": "ACCEPTED", "order_id": id, "quantity": quantity, "seller_site": payload["from_site"], "buyer_site": payload["to_site"]}
	if not permission["authorization"].is_empty(): result["authorization"] = permission["authorization"]
	return result

func _coordinate_transfer(destination: String, good: String, need: Dictionary, capital_project_id: String = "") -> void:
	if int(need.get("regular_quantity", need["quantity"])) <= 0 and int(need.get("timing_projection", {}).get("uncovered_future_quantity", 0)) <= 0:
		return
	var firm := _owner(destination)
	var currency := _sale_currency(firm)
	var candidates: Array[Dictionary] = []
	for source: String in _spec["firms"][firm]["sites"]:
		if source == destination or not _site_reports.has(source):
			continue
		var surplus := _reported_surplus(source, good)
		if surplus <= 0:
			continue
		for path: Dictionary in _paths_for(firm, _place(source), _place(destination), day):
			var legs := _locked_legs(path, currency)
			var lower: Variant = _input_offer_arrival({"route_legs": legs})
			if lower == null and capital_project_id.is_empty(): continue
			var arrival := int(lower) if lower != null else day + 1 + _travel_days(legs)
			var freight := _freight(legs)
			var candidate_need := _input_candidate_need(need, lower, surplus, _input_offer_batch_size({"route_legs": legs})) if capital_project_id.is_empty() else {"quantity": need["quantity"]}
			if int(candidate_need["quantity"]) <= 0: continue
			var preferable: bool = true
			for external: Dictionary in _input_offers(destination, good, int(need["need_by_day"]), int(candidate_need["quantity"]), need if capital_project_id.is_empty() else {}):
				if int(external["transport_quantity"]) <= 0 or external["observed_arrival_day"] == null:
					continue
				if (arrival > int(need["need_by_day"]) and not external["late_for_need"]) or (external["denomination"] == currency and int(external["observed_arrival_day"]) <= arrival and int(external["price"]) + int(external["freight_per_unit"]) <= freight):
					preferable = false
			if preferable:
				candidates.append({"source": source, "quantity": surplus, "path": path["id"], "arrival": arrival, "freight": freight, "batch_size": _input_offer_batch_size({"route_legs": legs})})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["arrival"]) < int(b["arrival"]) if a["arrival"] != b["arrival"] else int(a["freight"]) < int(b["freight"]) if a["freight"] != b["freight"] else str(a["source"]) < str(b["source"]))
	for candidate: Dictionary in candidates:
		var needed := int(_input_candidate_need(_input_need(destination, good), candidate["arrival"], int(candidate["quantity"]), int(candidate["batch_size"]))["quantity"]) if capital_project_id.is_empty() else maxi(0, _capital.goods_needed(destination, good)-maxi(0, _exposure(destination, good)-_committed(destination, good)))
		var wanted := mini(1000000, mini(_reported_surplus(candidate["source"], good), needed))
		if capital_project_id.is_empty():
			var internal_offer := {"price":0,"freight_per_unit":candidate["freight"],"denomination":currency,"transport_quantity":wanted,"route_legs":_locked_legs(_route_for(firm,firm,candidate["path"],destination,candidate["source"]),currency)}
			wanted = mini(wanted,int(_resale_replenishment_observation(destination,good,internal_offer,wanted)["quantity_limit"]))
			wanted = _production_bundle_limit(destination, good, wanted, candidate["source"], candidate["path"], true)
		if not capital_project_id.is_empty() and int(candidate["freight"]) > 0:
			var p := _capital.projects[capital_project_id] as Dictionary
			var money := maxi(0, int(p["budget"])-_capital.committed_cost(p)-_capital.remaining_labor_budget(p))
			money = mini(money, maxi(0, _world.ledger_state.available_balance(_account(firm, currency))-_capital_cash_protected(firm, _capital.template(p["template_id"]))))
			wanted = mini(wanted, money/int(candidate["freight"]))
		wanted = _procurement_cash_limit(firm, currency, int(candidate["freight"]), wanted)
		if wanted <= 0:
			continue
		var payload := {"firm": firm, "from_site": candidate["source"], "to_site": destination, "good": good, "quantity": wanted, "path_id": candidate["path"], "denomination": currency, "max_freight": candidate["freight"]}
		# Autonomous coordination is the firm's native operating action. A named
		# manager's separate player authority is never replaced or impersonated.
		var command := _auto_command(firm, "transfer_goods", payload, (capital_project_id+"|" if not capital_project_id.is_empty() else "")+str(candidate["source"]) + "|" + destination + "|" + good + "|" + str(candidate["path"]))
		var result := _accept(firm, command, true)
		if not capital_project_id.is_empty() and result.get("accepted", false) and result.has("order_id") and not _capital.projects[capital_project_id]["orders"].has(result["order_id"]): _capital.projects[capital_project_id]["orders"].append(result["order_id"])


## Upgrade only the representation of the old single stock point. Quantities,
## cash receipts, locked routes and every outstanding responsibility stay intact.
func _upgrade_site_layout(value: Dictionary) -> bool:
	for field: String in ["stock", "physical_totals", "plans", "orders", "totals", "needs"]:
		if not value.get(field) is Dictionary:
			return _fail("Missing site or living state")
	if not value.has("site_state"):
		if value.has("site_reports"):
			return _fail("Incomplete site state")
		if not value.get("firm_state", _initial_firm_state()) is Dictionary:
			return _fail("Invalid saved firm state")
		var firms := value.get("firm_state", _initial_firm_state()) as Dictionary
		var states := _initial_site_state()
		for firm: String in _firm_ids():
			if _spec["firms"][firm]["sites"].size() != 1 or (is_multi() and _configured_multi_sites(firm)):
				return _fail("Multi-site save lost its actual operating units")
			var site := _primary_site(firm)
			if not value["stock"].get(firm) is Dictionary or not value["physical_totals"].get(firm) is Dictionary or not firms.get(firm) is Dictionary:
				return _fail("Legacy stock point is missing")
			value["stock"][site] = value["stock"][firm]
			value["stock"].erase(firm)
			value["physical_totals"][site] = value["physical_totals"][firm]
			value["physical_totals"].erase(firm)
			if firms.get(firm, {}).has("activities"):
				states[site]["activities"] = firms[firm]["activities"]
				firms[firm].erase("activities")
			else:
				for id: String in states[site]["activities"]:
					var activity := _activity(site, id)
					if activity["outputs"].size() != 1 or int(activity["outputs"].values()[0]) != 1 or not value["physical_totals"][site].get("produced") is Dictionary:
						return _fail("Legacy activity executions cannot be inferred")
					states[site]["activities"][id]["batches"] = value["physical_totals"][site]["produced"].get(activity["outputs"].keys()[0])
			if value["plans"].has(firm):
				value["plans"][site] = value["plans"][firm]
				value["plans"].erase(firm)
			if value.get("firm_knowledge", {}).has(firm):
				value["firm_knowledge"][site] = value["firm_knowledge"][firm]
				value["firm_knowledge"].erase(firm)
		value["firm_state"] = firms
		value["site_state"] = states
		value["site_reports"] = {}
		for field: String in ["quote_state", "search_state", "request_window", "relations"]:
			if not value.get(field, {}) is Dictionary:
				return _fail("Invalid legacy site metadata")
			var converted: Dictionary = {}
			for key: Variant in value.get(field, {}):
				if not key is String:
					return _fail("Invalid site metadata key")
				var parts := str(key).split("|")
				if field == "relations" and parts.size() == 3:
					parts[0] = _inventory_key(parts[0])
					parts[1] = _inventory_key(parts[1])
				elif parts.size() == 2:
					parts[0] = _inventory_key(parts[0])
				else:
					return _fail("Invalid legacy site relation")
				converted["|".join(parts)] = value[field][key]
			if value.has(field):
				value[field] = converted
		for rows: Variant in value.get("request_window", {}).values():
			if not rows is Array:
				return _fail("Invalid received requests")
			for row: Variant in rows:
				if row is Dictionary and row.has("buyer"):
					row["buyer"] = _inventory_key(row["buyer"])
	for order: Variant in value["orders"].values():
		if not order is Dictionary:
			return _fail("Invalid site order")
		if not order.has("kind"):
			if not _spec["firms"].has(order.get("seller")) or (not _spec["firms"].has(order.get("buyer")) and not _spec["actors"].has(order.get("buyer"))):
				return _fail("Unknown legacy order owner")
			order.merge({"kind": "SALE", "seller_site": _primary_site(order["seller"]), "buyer_site": _primary_site(order["buyer"]) if _spec["firms"].has(order["buyer"]) else "", "need_category": "food" if _spec["actors"].has(order["buyer"]) else ""})
	for actor: String in value["totals"]:
		var total: Variant = value["totals"][actor]
		if not total is Dictionary:
			return _fail("Invalid living totals")
		if not total.has("categories"):
			if not value["physical_totals"].get(actor) is Dictionary or not value["physical_totals"][actor].get("used") is Dictionary or not FormalLedgerState.exact_fields(total, ["required", "consumed", "unmet", "work_hours", "income"]) or _spec["categories"].size() != 1 or _spec["categories"].get("food", {}).get("mode") != "flow":
				return _fail("Legacy food totals require their original need category")
			value["totals"][actor] = {"categories": {"food": {"required": total["required"], "satisfied": total["consumed"], "unmet": total["unmet"], "used_items": value["physical_totals"][actor]["used"].duplicate(true)}}, "work_hours": total["work_hours"], "income": total["income"]}
	for actor: String in value["needs"]:
		var need: Variant = value["needs"][actor]
		if not need is Dictionary:
			return _fail("Invalid living need")
		if not need.has("categories"):
			if not FormalLedgerState.exact_fields(need, ["day", "required", "consumed", "unmet"]):
				return _fail("Unknown legacy need")
			# Old food saves have actual service totals but no per-good daily use.
			# Preserve that absence rather than inventing historical allocations.
			value["needs"][actor] = {"day": need["day"], "categories": {"food": {"required": need["required"], "satisfied": need["consumed"], "unmet": need["unmet"], "used_items": null}}}
	return true

func _configured_multi_sites(firm: String) -> bool:
	for row: Dictionary in config.get("firms", []):
		if row["id"] == firm:
			return row.has("sites")
	return false

func _valid_order_action(value: Dictionary, order: Dictionary) -> bool:
	if order.has("supply_contract_id"):return _supply.valid_order_action(value,order)
	var legacy: bool = not is_multi() and _spec["firms"].has(order["buyer"]) and str(order["action_id"]).begins_with("plan:") and order["kind"] == "SALE"
	if legacy:
		return true
	var entry: Variant = value["commands"].get(order["action_id"])
	if not entry is Dictionary or not entry["result"].get("accepted", false):
		return false
	var command := entry["envelope"]["command"] as Dictionary
	var payload := command["payload"] as Dictionary
	if command["minute"] != order["accepted_minute"] or int(order["accepted_day"]) != int(order["accepted_minute"]) / 1440 or entry["result"].get("order_id") != order["id"] or entry["result"].get("quantity") != order["quantity"] or not FormalLedgerState.valid_amount(payload.get("quantity")) or int(payload["quantity"]) < int(order["quantity"]) or payload.get("good") != order["good"]:
		return false
	if order["kind"] == "PERSONAL_FREIGHT":
		if command["kind"] != "send_personal_goods" or entry["envelope"]["actor"] != order["buyer"] or not FormalLedgerState.exact_fields(payload, ["good", "quantity", "from_place_id", "to_place_id", "path_id", "denomination", "max_freight"]): return false
		return payload["quantity"] == order["quantity"] and payload["from_place_id"] == order["from_place_id"] and payload["to_place_id"] == order["to_place_id"] and payload["path_id"] == order["route_id"] and payload["denomination"] == order["denomination"] and FormalLedgerState.valid_amount(payload["max_freight"]) and int(payload["max_freight"]) >= _freight(order["route_legs"])
	if order["kind"] == "TRANSFER":
		return command["kind"] == "transfer_goods" and EconomySliceConfig._fields(payload, ["firm", "from_site", "to_site", "good", "quantity", "path_id", "denomination", "max_freight"], ["authorization_context"]) and payload["firm"] == order["buyer"] and _valid_procurement_actor(entry, order["buyer"], order) and payload["from_site"] == order["seller_site"] and payload["to_site"] == order["buyer_site"] and payload["path_id"] == order["route_id"] and payload["denomination"] == order["denomination"] and FormalLedgerState.valid_amount(payload["max_freight"]) and int(payload["max_freight"]) >= _freight(order["route_legs"])
	if (order["need_category"] == "" and _spec["actors"].has(order["buyer"]) and payload.get("purpose") != "HOLDING") or command["kind"] != "buy" or not _valid_procurement_actor(entry, order["buyer"], order) or payload.get("seller") != order["seller"] or _inventory_key(order["seller"], str(payload.get("seller_site", ""))) != order["seller_site"] or str(payload.get("buyer_site", _primary_site(order["buyer"]) if _spec["firms"].has(order["buyer"]) else "")) != order["buyer_site"] or payload.get("need_category", "food" if _spec["actors"].has(order["buyer"]) and payload.get("purpose", "NEED") == "NEED" else "") != order["need_category"]:
		return false
	var policy := _price_policy(order["seller_site"], order["good"])
	if (entry["result"].has("price") and entry["result"]["price"] != order["price"]) or (not policy.is_empty() and policy["mode"] == "N3" and entry["result"].get("price") != order["price"]):
		return false
	if (payload.has("path_id") and payload["path_id"] != order["route_id"]) or payload.get("denomination", FormalLedgerState.DENOMINATION) != order["denomination"] or not FormalLedgerState.valid_amount(payload.get("max_price", order["price"])) or int(payload.get("max_price", order["price"])) < int(order["price"]):
		return false
	var quoted := _quote_id(int(order["accepted_minute"]), order["buyer"], order["seller"], order["good"], order["route_id"], order["seller_site"], order["buyer_site"])
	if not _local_quotes.rule(order["seller_site"],order["good"]).is_empty():
		var received := _local_quotes.known(_inventory_key(order["buyer"],order["buyer_site"]),order["seller_site"],order["good"],int(order["accepted_minute"]))
		return not received.is_empty() and payload.get("quote_id")==quoted+"|"+str(received["id"])
	if payload.get("quote_id") == quoted:
		return true
	if payload.has("seller_site") or payload.has("buyer_site") or order["seller_site"] != _primary_site(order["seller"]) or (_spec["firms"].has(order["buyer"]) and order["buyer_site"] != _primary_site(order["buyer"])):
		return false
	var old := "quote:" + str(order["accepted_minute"]) + ":" + str(order["buyer"]) + ":" + str(order["seller"]) + ":" + str(order["good"])
	return payload.get("quote_id") == old + ":" + str(order["route_id"]) or (order["denomination"] == FormalLedgerState.DENOMINATION and order["route_id"] == "edge:r2_paris_local" and payload.get("quote_id") == old)

func _valid_arrival_payment(receipt: Dictionary, order: Dictionary) -> bool:
	var minute := _delivery_minute(receipt)
	var ids: Array[String] = []
	for leg: Dictionary in _delivery_legs(receipt["id"], order, int(receipt["quantity"])):
		var expected := leg.duplicate(true)
		expected.merge({"denomination": order["denomination"], "effective_minute": minute, "basis": "GENERATED_SIMULATION_ASSUMPTION"})
		if _world.ledger_state.transaction(leg["transaction_id"]) != expected:
			return _fail("Arrival goods or freight payment differs from physical delivery")
		ids.append(leg["transaction_id"])
	var batch := _world.ledger_state.payment_batch("delivery:" + str(receipt["id"]))
	if ids.is_empty():
		return order["kind"] in ["TRANSFER", "PERSONAL_FREIGHT"] and batch.is_empty()
	if batch.is_empty():
		return order["kind"] == "SALE" and order["route_legs"].size() == 1 and _freight(order["route_legs"]) == 0
	return batch == {"transactions": ids, "releases": {str(order["id"]): int(receipt["quantity"]) * (int(order["price"]) + _freight(order["route_legs"]))}, "minute": minute}

func _valid_site_report(report: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(report, ["id", "actor", "kind", "candidate", "observed_day", "delivery_day", "inventory", "surplus", "needs", "order_cursor", "producing", "labor_hours"]) or report["kind"] != "site_report" or not _spec["sites"].has(report["candidate"]) or report["actor"] != _owner(report["candidate"]) or not FormalLedgerState.valid_amount(report["observed_day"]) or not FormalLedgerState.valid_amount(report["delivery_day"]) or report["id"] != "site_report:" + str(report["candidate"]) + ":" + str(report["observed_day"]) or int(report["delivery_day"]) != int(report["observed_day"]) + int(_spec["sites"][report["candidate"]]["coordination_delay"]):
		return false
	if not report["producing"] is bool or not FormalLedgerState.valid_amount(report["labor_hours"]) or not FormalLedgerState.valid_amount(report["order_cursor"]) or int(report["order_cursor"]) < 1 or not report["needs"] is Dictionary or not FormalLedgerState.exact_fields(report["needs"], _goods):
		return false
	for good: String in _goods:
		var need: Variant = report["needs"][good]
		if not need is Dictionary or not FormalLedgerState.exact_fields(need, ["quantity", "need_by_day"]) or not FormalLedgerState.valid_amount(need["quantity"]) or not FormalLedgerState.valid_amount(need["need_by_day"]) or int(need["need_by_day"]) < int(report["observed_day"]) or int(need["need_by_day"]) > int(report["observed_day"]) + 30:
			return false
	for field: String in ["inventory", "surplus"]:
		if not report[field] is Dictionary or not FormalLedgerState.exact_fields(report[field], _goods):
			return false
		for amount: Variant in report[field].values():
			if not FormalLedgerState.valid_amount(amount):
				return false
	for good: String in _goods:
		if int(report["surplus"][good]) > int(report["inventory"][good]):
			return false
	return true

func _valid_need_totals(totals: Variant, actor: String, elapsed: int) -> bool:
	if not totals is Dictionary or not FormalLedgerState.exact_fields(totals, ["categories", "work_hours", "income"]) or not FormalLedgerState.valid_amount(totals["work_hours"]) or not FormalLedgerState.valid_amount(totals["income"]) or not totals["categories"] is Dictionary or not FormalLedgerState.exact_fields(totals["categories"], _category_order()):
		return false
	for category: String in _category_order():
		var row: Variant = totals["categories"][category]
		if not _valid_need_row(row, category, false) or int(row["required"]) != _need_total(actor, category, elapsed):
			return false
	return true

func _valid_need_row(row: Variant, category: String, legacy: bool) -> bool:
	if not row is Dictionary or not EconomySliceConfig._fields(row, ["required", "satisfied", "unmet", "used_items"],["service_satisfied"]):
		return false
	for field: String in ["required", "satisfied", "unmet"]:
		if not FormalLedgerState.valid_amount(row[field]):
			return false
	if not FormalLedgerState.valid_amount(row.get("service_satisfied",0)) or int(row.get("service_satisfied",0))>int(row["satisfied"]) or (category!="food" and row.get("service_satisfied",0)!=0): return false
	if int(row["satisfied"]) + int(row["unmet"]) != int(row["required"]):
		return false
	if row["used_items"] == null:
		return legacy and category == "food" and _category_order() == ["food"] and _spec["categories"][category]["mode"] == "flow"
	if not row["used_items"] is Dictionary or not FormalLedgerState.exact_fields(row["used_items"], _goods):
		return false
	for good: String in _goods:
		if not FormalLedgerState.valid_amount(row["used_items"][good]) or (int(row["used_items"][good]) > 0 and _service(good, category) <= 0):
			return false
	return true

func _valid_household_flows(value: Dictionary, actor: String, flows: Dictionary) -> bool:
	var used := _zero_goods()
	for category: String in _category_order():
		var row := value["totals"][actor]["categories"][category] as Dictionary
		if _spec["categories"][category]["mode"] == "durable":
			if row["used_items"] != _zero_goods():
				return _fail("Durable holdings cannot create physical consumption")
			continue
		var service: int = 0
		var largest: int = 1
		for good: String in _goods:
			used[good] = int(used[good]) + int(row["used_items"][good])
			service += int(row["used_items"][good]) * _service(good, category)
			largest = maxi(largest, _service(good, category))
		var resident:=int(row.get("service_satisfied",0))
		if resident!=(_service_market._resident.food_total(actor,int(value["day"])) if category=="food" else 0): return _fail("Resident food satisfaction lacks actual service receipt")
		if int(row["satisfied"])-resident > service or service - (int(row["satisfied"])-resident) > int(value["day"]) * (largest - 1):
			return _fail("Flow need lacks actual usable item consumption")
	return flows["produced"] == _zero_goods() and used == flows["used"]

func _valid_current_need(value: Dictionary, actor: String) -> bool:
	var need: Variant = value["needs"][actor]
	var need_day := _last_managed_need_day(actor, int(value["day"]))
	if not need is Dictionary or not FormalLedgerState.exact_fields(need, ["day", "categories"]) or need["day"] != need_day or not need["categories"] is Dictionary or not FormalLedgerState.exact_fields(need["categories"], _category_order()):
		return false
	var held := _zero_goods()
	for category: String in _category_order():
		var row: Variant = need["categories"][category]
		if not _valid_need_row(row, category, true) or int(row["required"]) != _need_on_day(actor, category, need_day):
			return false
		if row["used_items"] == null:
			continue
		var service: int = 0
		for good: String in _goods:
			service += int(row["used_items"][good]) * _service(good, category)
			if _spec["categories"][category]["mode"] == "durable":
				held[good] = int(held[good]) + int(row["used_items"][good])
			elif int(row["used_items"][good]) > int(value["totals"][actor]["categories"][category]["used_items"][good]):
				return false
		var resident:=mini(int(row["required"]),_service_market._resident.food_units(actor,need_day)) if category=="food" else 0
		if row.get("service_satisfied",0)!=resident: return false
		if int(row["satisfied"]) != mini(int(row["required"]), service+resident):
			return false
	for good: String in _goods:
		if int(held[good]) > int(value["stock"][actor][good]):
			return false
	return true

func _supplier_known(known: Array, candidate: String) -> bool:
	for key: String in known:
		if _candidate(key) == _candidate(candidate):
			return true
	return false

func _reported_surplus(site: String, good: String) -> int:
	var report := _site_reports.get(site, {}) as Dictionary
	if report.is_empty():
		return 0
	var quantity := int(report["surplus"][good])
	for number: int in range(int(report["order_cursor"]), next_order):
		var order := _orders["order:" + str(number)] as Dictionary
		if order["seller_site"] == site and order["good"] == good:
			quantity -= int(order["quantity"]) - int(order["cancelled"])
	return maxi(0, quantity)

func _reported_gap(site: String, good: String) -> int:
	var report := _site_reports.get(site, {}) as Dictionary
	if report.is_empty():
		return 0
	var quantity := int(report["needs"][good]["quantity"])
	for number: int in range(int(report["order_cursor"]), next_order):
		var order := _orders["order:" + str(number)] as Dictionary
		if _destination(order) == site and order["good"] == good:
			quantity -= int(order["quantity"]) - int(order["cancelled"])
	return maxi(0, quantity)

## Allocate a delivered internal need to one known own facility. This is a local
## intention; only later admission reserves goods, money and transport capacity.
func _internal_request_pressure(source: String, good: String) -> int:
	var firm := _owner(source)
	var total: int = 0
	for destination: String in _spec["firms"][firm]["sites"]:
		if destination == source or not _site_reports.has(destination) or _reported_gap(destination, good) <= 0:
			continue
		var candidates: Array[Dictionary] = []
		for site: String in _spec["firms"][firm]["sites"]:
			if site == destination or not _site_reports.has(site):
				continue
			var row := _spec["sites"][site] as Dictionary
			var produces: bool = false
			var feasible: bool = false
			for activity: Dictionary in row["activities"]:
				if activity["outputs"].has(good):
					produces = true
					var workable: bool = int(_site_reports[site]["labor_hours"]) >= int(activity["hours"]) and _capital.capacity(site, _world.game_clock.total_minutes(), activity["id"]) >= int(activity["capacity_units"])
					for material: String in _goods:
						workable = workable and int(_site_reports[site]["inventory"][material]) >= int(activity["materials"][material])
					feasible = feasible or workable
			if (not produces or not _site_reports[site]["producing"]) and _reported_surplus(site, good) <= 0:
				continue
			for path: Dictionary in _paths_for(firm, _place(site), _place(destination), day):
				var legs := _locked_legs(path, _sale_currency(firm))
				candidates.append({"site": site, "surplus": _reported_surplus(site, good), "feasible": feasible, "lead": _travel_days(legs), "freight": _freight(legs)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if (int(a["surplus"]) > 0) != (int(b["surplus"]) > 0):
				return int(a["surplus"]) > 0
			if a["feasible"] != b["feasible"]:
				return bool(a["feasible"])
			if a["lead"] != b["lead"]:
				return int(a["lead"]) < int(b["lead"])
			if a["freight"] != b["freight"]:
				return int(a["freight"]) < int(b["freight"])
			return str(a["site"]) < str(b["site"]))
		if not candidates.is_empty() and candidates[0]["site"] == source:
			total += _reported_gap(destination, good)
	return total


func manages_person(person: String) -> bool:
	return subject_exit_minute(person) < 0 and (not uses_host_accounts() or _management.get("status") == "ACTIVE") and _actors.has(person) and _stocks.has(person) and _spec["actors"].has(person) and _spec["actors"][person]["kind"] == "named" and _spec["actors"][person]["control"] != "dormant"

## Account references can be bound before initialization; manages_person decides ownership.
func personal_accounts() -> Dictionary:
	var result: Dictionary = {}
	for person: String in _spec["actors"]:
		if _spec["actors"][person]["kind"] == "named" and _spec["actors"][person]["control"] != "dormant":
			result[person] = _spec["actors"][person]["account_id"]
	return result

func managed_background_population(unit_id: String) -> int:
	var count: int = 0
	for actor: String in _spec["actors"]:
		if (not uses_host_accounts() or _management.get("status") == "ACTIVE") and _actors.has(actor) and _stocks.has(actor) and _spec["actors"][actor]["kind"] == "cohort" and _spec["actors"][actor]["control"] != "dormant" and _population_unit(actor) == unit_id:
			count += int(_spec["actors"][actor]["members"])
	return count

func personal_authorized(person: String) -> bool:
	return manages_person(person) and _world.person_overlay.is_alive(person) and (not uses_host_accounts() or (_world.spatial_catalog.has_place(_place(person)) and not _world.population_state.unit_for_person(person).is_empty())) and (_spec["actors"][person]["control"] == "automatic" or person == _world.player_state.player_id())

func personal_owned_inventory(person: String) -> Dictionary:
	return (_legacy_stock_boundary.get(person, _stocks.get(person, {})) as Dictionary).duplicate(true) if _declared_named(person) else {}

func personal_accessible_stock(person: String, carried_only: bool = false) -> Dictionary:
	var result := _zero_goods()
	if not _declared_named(person): return result
	var place := _place(person)
	var present := _at_place(person, place)
	for good: String in _goods:
		result[good] = _lots.quantity_at("PERSON|"+person+"|CARRIED", good)
		if present and not carried_only: result[good] += _lots.quantity_at("PERSON|"+person+"|STORED|"+place, good)
	return result

func personal_inventory(person: String) -> Dictionary:
	return personal_accessible_stock(person) if manages_person(person) else _zero_goods()

func personal_economy(person: String) -> Dictionary:
	if not manages_person(person):
		return {}
	var contract := (_contracts.get(person, {}) as Dictionary).duplicate(true)
	var employer: Dictionary = {}
	if not contract.is_empty():
		var job := _labor_market.contract_job(contract)
		contract.merge({"wage_per_hour": job["wage_per_hour"], "site_id": job["site_id"], "payer_account_id": _account(job["employer"], job["denomination"]), "work_hours_limit": int(job["hours"]) * int(contract["workers"]), "work_place_id": job["place"], "at_workplace": _at_place(person, job["place"])})
		var available_hours := mini(int(contract["work_hours_limit"]), (((day+1)*1440-_world.game_clock.total_minutes())/60)*int(contract["workers"]))
		var travelling: bool = _world.person_travel != null and _world.person_travel.active(person)
		contract["work_hours_available"] = available_hours if not travelling else 0
		contract["can_work_now"] = not travelling and bool(contract["at_workplace"]) and available_hours > 0 and not _work_queue.has(person) and _site_operating(job["site_id"])
		employer = {"employer_id": job["employer"], "label": job["employer"], "site_id": job["site_id"]}
	var unpaid: Dictionary = {}
	for id: String in _wages_by_worker.get(person, []):
		var claim := _wages[id] as Dictionary
		if int(claim["due_day"]) <= day:
			unpaid[claim["denomination"]] = int(unpaid.get(claim["denomination"], 0)) + int(claim["remaining"])
	return {"management_scope_id": _management.get("scope_id", ""), "current_place_id": _place(person), "activity_population_unit_id": _world.population_state.unit_for_place(_place(person)), "resident_population_unit_id": _population_unit(person), "population_unit_id": _population_unit(person), "account_id": _account(person), "cash": _world.ledger_state.balance(_account(person)), "reserved": _world.ledger_state.reserved_balance(_account(person)), "denomination": FormalLedgerState.DENOMINATION, "accounts": _world.ledger_state.own_accounts(person), "employment": contract, "employer": employer, "wage_unpaid": not unpaid.is_empty(), "matured_wages": unpaid, "native": true, "available": _world.ledger_state.available_balance(_account(person)), "need_today": _needs.get(person, {}).duplicate(true) if _needs.get(person, {}).get("day") == day else {}, "work_booking": _work_queue.get(person, {}).duplicate(true), "owned_inventory": personal_owned_inventory(person), "usable_inventory": personal_inventory(person), "custody": _world.personal_economy_state.native_custody_rows(person), "physical_batches": owned_batch_rows(person, person)}

func personal_used(person: String, good: String) -> int:
	return int(_physical_totals.get(person, {}).get("used", {}).get(good, 0))

func personal_commodity(commodity: String) -> Dictionary:
	if not commodity.begins_with("native:") or commodity.trim_prefix("native:") not in _goods:
		return {}
	var good := commodity.trim_prefix("native:")
	var category: String = ""
	for id: String in _category_order():
		if _service(good, id) > 0:
			category = id
			break
	var result := {"commodity_id": commodity, "good": good, "name_zh": good, "unit_id": "native_unit:" + good, "unit_name_zh": "配置单位", "quantity_scale": 1, "sale_supported": true, "consumable": false, "daily_supported": not category.is_empty(), "need_category": category, "mode": _spec["categories"].get(category, {}).get("mode", ""), "services": _services.get(good, {}).duplicate(true)}
	for id: String in _category_order():
		if _service(good, id) > 0 and _spec["categories"][id]["mode"] == "flow":
			result["consumable"] = true
	for row: Dictionary in config.get("goods", []):
		if row["id"] == good:
			result["unit_id"] = row.get("unit_id", result["unit_id"])
			result["unit_name_zh"] = row.get("unit_name_zh", result["unit_name_zh"])
	return result

func personal_market_rows(person: String, limit: int, offset: int) -> Array[Dictionary]:
	var by_site: Dictionary = {}
	for offer: Dictionary in _offers(person):
		var key := str(offer["good"]) + "|" + str(offer["seller_site"])
		var unit_cost := int(offer["price"]) + int(offer["freight_per_unit"])
		if by_site.has(key) and (int(by_site[key]["inventory"])>0 or int(offer["quantity"])<=0) and int(by_site[key]["unit_cost"]) <= unit_cost: continue
		var row := personal_commodity("native:" + str(offer["good"]))
		row.merge({"price": offer["price"], "inventory": offer["quantity"], "seller_site": offer["seller_site"], "denomination": offer["denomination"], "unit_cost": unit_cost, "sale_basis": "KNOWN_ONSITE_STORE" if Retail.onsite(offer) else "KNOWN_NATIVE_SITE", "fulfilment":offer.get("fulfilment","TRANSPORT_CONTRACT"),"reason":offer["reason"]})
		by_site[key] = row
	var ids := by_site.keys()
	ids.sort()
	var result: Array[Dictionary] = []
	for index: int in range(maxi(0, offset), mini(ids.size(), maxi(0, offset) + maxi(0, limit))):
		result.append(by_site[ids[index]])
	return result

## Read-only native-arrangement query. Manual personal_purchase_quote/HOLDING
## remains unchanged. The caller still executes the original purchase command.
func personal_arrangement_position(person: String) -> Dictionary:
	return PersonalArrangementTiming.position(self, person)

func personal_arrangement_purchase_quote(person: String, commodity: String) -> Dictionary:
	var ctx: Dictionary = PersonalArrangementTiming.context(self, person)
	if not ctx.get("supported", false):
		ctx["success"] = false
		return ctx
	var plan: Dictionary = _world.personal_economy_state._arrangements.get(person, {}).get(commodity, {})
	if plan.is_empty() or not plan.get("auto_buy_missing", false) or plan.get("mode") != "flow":
		return {"success": false, "supported": true, "quantity": 0, "reason": "PERSONAL_ARRANGEMENT_NO_FLOW_AUTO_BUY_AUTHORITY"}
	var item := personal_commodity(commodity)
	var offers: Array[Dictionary] = []
	for offer: Dictionary in _offers(person, "", item["good"]):
		if typeof(offer.get("price")) != TYPE_INT or int(offer.get("quantity", 0)) <= 0: continue
		if offer["route_legs"].is_empty() and not Retail.onsite(offer): continue
		offers.append(offer)
	# Preserve existing personal price/currency order among useful offers; no
	# new wallet, borrowing, consumption budget or price policy is introduced.
	_annotate_costs(person, offers, int(plan["quantity"]))
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("compare_across_currencies", false) and (a.get("cost_comparison", {}).get("executable", false) or b.get("cost_comparison", {}).get("executable", false) or a["denomination"] != b["denomination"]): return _comparison_less(a, b)
		var first := int(a["price"]) + int(a["freight_per_unit"])
		var second := int(b["price"]) + int(b["freight_per_unit"])
		return first < second if first != second else str(a["seller_site"]) + str(a["route_id"]) < str(b["seller_site"]) + str(b["route_id"]))
	var reason := "NO_AVAILABLE_OR_FUNDED_PERSONAL_ARRANGEMENT_OFFER"
	for offer: Dictionary in offers:
		var timing: Dictionary = PersonalArrangementTiming.candidate_need(self, person, commodity, offer, ctx)
		reason = str(timing.get("reason", reason))
		var quantity: int = int(timing.get("quantity", 0))
		if quantity <= 0: continue
		var quote: Dictionary = offer.duplicate(true)
		quote.merge(item, true)
		quote.merge({"success": true, "unit_price": offer["price"], "quantity": quantity, "offered_quantity": offer["quantity"], "amount": quantity * (int(offer["price"]) + int(offer["freight_per_unit"])), "purpose": "HOLDING", "stock_scope": "NATIVE_SITE", "buyer_account_id": _account(person, offer["denomination"])}, true)
		return {"success": true, "supported": true, "quantity": quantity, "quote": quote, "timing": timing, "reason": timing["reason"]}
	return {"success": false, "supported": true, "quantity": 0, "reason": reason}


func personal_purchase_quote(person: String, market: String, commodity: String, quantity: int) -> Dictionary:
	if not _at_place(person, _place(person)): return {"success": false, "error": "人物正在旅行，不能在上一节点办理新购买。", "quantity_scale": 1}
	var item := personal_commodity(commodity)
	if not personal_authorized(person) or item.is_empty() or quantity <= 0 or quantity > 1000000:
		return {"success": false, "error": "人物、原生商品单位或数量无效。", "quantity_scale": 1}
	var offers: Array[Dictionary] = []
	for offer: Dictionary in _offers(person, "", item["good"]):
		if offer["good"] == item["good"] and (not market.begins_with("site:") or offer["seller_site"] == market) and (not offer["route_legs"].is_empty() or Retail.onsite(offer)):
			offers.append(offer)
	_annotate_costs(person, offers, quantity)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (int(a["quantity"])>0)!=(int(b["quantity"])>0): return int(a["quantity"])>0
		if a.get("compare_across_currencies", false) and (a.get("cost_comparison", {}).get("executable", false) or b.get("cost_comparison", {}).get("executable", false) or a["denomination"] != b["denomination"]): return _comparison_less(a, b)
		var first := int(a["price"]) + int(a["freight_per_unit"])
		var second := int(b["price"]) + int(b["freight_per_unit"])
		return first < second if first != second else str(a["seller_site"]) + str(a["route_id"]) < str(b["seller_site"]) + str(b["route_id"]))
	if offers.is_empty():
		return {"success": false, "error": "没有已知的合法卖方及运输路径。", "quantity_scale": 1}
	var offer := offers[0].duplicate(true)
	var offered_quantity := int(offer["quantity"])
	if offered_quantity<=0: return {"success":false,"error":offer["reason"],"quantity_scale":1}
	var unit := int(offer["price"]) + int(offer["freight_per_unit"])
	if quantity > FormalLedgerState.MAX_AMOUNT / unit:
		return {"success": false, "error": "成交金额超过整数范围。", "quantity_scale": 1}
	offer.merge(item, true)
	offer.merge({"success": true, "unit_price": offer["price"], "quantity": quantity, "offered_quantity": offered_quantity, "amount": mini(quantity, offered_quantity) * unit, "purpose": "HOLDING", "stock_scope": "NATIVE_SITE", "buyer_account_id": _account(person, offer["denomination"])}, true)
	return offer

func personal_purchase(person: String, quote: Dictionary, quantity: int, id: String) -> Dictionary:
	if not personal_authorized(person) or quote.get("quantity_scale") != 1 or quote.get("quantity") != quantity or not quote.get("commodity_id") is String or not quote.get("seller_site") is String:
		return {"success": false, "error": "报价单位、人物或数量不一致。"}
	var payload := {"quote_id": quote.get("quote_id", ""), "seller": quote.get("seller", ""), "seller_site": quote["seller_site"], "good": str(quote["commodity_id"]).trim_prefix("native:"), "quantity": quantity, "denomination": quote.get("denomination", ""), "max_price": quote.get("unit_price", 0), "path_id": quote.get("route_id", ""), "purpose": "HOLDING", "need_category": ""}
	var automatic: bool = _spec["actors"][person]["control"] == "automatic"
	var command := _auto_command(person, "buy", payload, id) if automatic else {"action_id": id, "minute": _world.game_clock.total_minutes(), "kind": "buy", "payload": payload}
	var result := _accept(person, command, automatic)
	if not result["accepted"]:
		return {"success": false, "error": result["reason"]}
	return {"success": true, "source": _personal_order_source(_orders[result["order_id"]]), "message": "现场交付完成。物品已取得，之后按原消费安排使用。" if Retail.onsite(_orders[result["order_id"]]) else "订单已接受。资金已预留，物品在实际交付后取得。"}

func personal_incoming(person: String, commodity: String) -> int:
	var quantity: int = 0
	for id: String in _active_by_buyer.get(person, []):
		var order := _orders[id] as Dictionary
		if order["kind"] == "SALE" and order["good"] == commodity.trim_prefix("native:"):
			quantity += int(order["pending"]) + int(order["transit"])
	return quantity

func _personal_order_source(order: Dictionary) -> Dictionary:
	var result := personal_commodity("native:" + str(order["good"]))
	result.merge({"source_id": order["id"], "order_id": order["id"], "seller_id": order["seller"], "seller_site": order["seller_site"], "buyer_account_id": order["buyer_account"], "seller_account_id": order["seller_account"], "quantity": order["quantity"], "unit_price": order["price"], "freight_per_unit": _freight(order["route_legs"]), "denomination": order["denomination"], "amount": _order_view(order)["locked_goods_amount"] + _order_view(order)["locked_freight_amount"], "effective_minute": order["accepted_minute"]})
	return result

func _personal_delivery_source(receipt: Dictionary) -> Dictionary:
	var order := _orders[receipt["order_id"]] as Dictionary
	var result := _personal_order_source(order)
	var money: int = 0
	var payments: Array[String] = []
	for leg: Dictionary in _delivery_legs(receipt["id"], order, int(receipt["quantity"])):
		var payment := _world.ledger_state.transaction(leg["transaction_id"])
		money += int(payment["amount"])
		payments.append(payment["transaction_id"])
	result.merge({"source_id": receipt["id"], "shipment_id": receipt.get("shipment_id", receipt["id"]), "quantity": receipt["quantity"], "amount": money, "transaction_ids": payments, "effective_minute": _delivery_minute(receipt)}, true)
	if receipt.has("custody_mode"): result.merge({"custody_mode": receipt["custody_mode"], "custody_place_id": receipt["custody_place_id"]})
	return result

func _personal_opening_source(person: String, good: String) -> Dictionary:
	var result := personal_commodity("native:" + good)
	result.merge({"source_id": "native_opening:" + person + ":" + good, "quantity": _spec["actors"][person]["stock"][good], "effective_minute": 0, "amount": 0, "basis": "DEVELOPMENT_CONFIGURATION"})
	return result

func personal_balance_source(person: String, good: String) -> Dictionary:
	var result := personal_commodity("native:" + good)
	result.merge({"source_id": "native_balance:" + person + ":" + good + ":" + str(_world.game_clock.total_minutes()), "quantity": _stocks[person][good], "effective_minute": _world.game_clock.total_minutes(), "amount": 0, "previous_used": personal_used(person, good), "basis": "PRE_EXISTING_NATIVE_BALANCE_SOURCE_UNRECORDED"})
	return result

func valid_personal_source(person: String, record: Dictionary) -> bool:
	if not _declared_named(person) or personal_commodity(str(record.get("commodity_id", ""))).is_empty():
		return false
	var source: Dictionary = {}
	var good := str(record["commodity_id"]).trim_prefix("native:")
	if record["kind"] == "native_opening":
		source = _personal_opening_source(person, good)
	elif record["kind"] == "native_balance":
		if not FormalLedgerState.valid_amount(record.get("previous_used")) or int(record["previous_used"]) > personal_used(person, good):
			return false
		var actual := int(_spec["actors"][person]["stock"][good])
		for receipt: Dictionary in _delivery_receipts.values():
			var order := _orders[receipt["order_id"]] as Dictionary
			if order["buyer"] == person and order["good"] == good and _delivery_minute(receipt) <= int(record["effective_minute"]):
				actual += int(receipt["quantity"])
		if record.get("source_id") != "native_balance:" + person + ":" + good + ":" + str(record["effective_minute"]) or record.get("basis") != "PRE_EXISTING_NATIVE_BALANCE_SOURCE_UNRECORDED" or int(record["quantity"]) != actual - int(record["previous_used"]) or record.get("amount") != 0:
			return false
		for key: String in personal_commodity(str(record["commodity_id"])):
			if record.get(key) != personal_commodity(str(record["commodity_id"]))[key]:
				return false
		return true
	elif record["kind"] == "native_handover":
		var fact := property_handover(str(record.get("source_id", "")))
		if fact.is_empty() or fact["person_id"] != person: return false
		source = _handover_native_source(fact)
	elif record["kind"] == "native_order":
		var order: Dictionary = _orders.get(record.get("source_id"), {})
		if order.is_empty() or order["buyer"] != person:
			return false
		source = _personal_order_source(order)
	elif record["kind"] == "native_delivery":
		var receipt: Dictionary = _delivery_receipts.get(record.get("source_id"), {})
		if receipt.is_empty() or _orders[receipt["order_id"]]["buyer"] != person:
			return false
		source = _personal_delivery_source(receipt)
	else:
		return false
	for key: String in source:
		if record.get(key) != source[key]:
			return false
	return true

func valid_personal_use(record: Dictionary) -> bool:
	var item := personal_commodity(str(record.get("commodity_id", "")))
	return not item.is_empty() and record.get("need_category") is String and _service(item["good"], record["need_category"]) > 0 and _spec["categories"][record["need_category"]]["mode"] == "flow"

func personal_consumption_quote(person: String, commodity: String, quantity: int) -> Dictionary:
	var item := personal_commodity(commodity)
	if _needs.get(person, {}).get("day", -1) != day: return {"success": false, "error": "本次接管后的需要尚未到期。"}
	if not personal_authorized(person) or item.is_empty() or not item["consumable"] or quantity <= 0:
		return {"success": false, "error": "没有合法流量消费用途；耐用品保留持有。"}
	var available := int(personal_inventory(person).get(item["good"], 0))
	for category: String in _category_order():
		if _spec["categories"][category]["mode"] == "durable":
			var held: Variant = _needs.get(person, {}).get("categories", {}).get(category, {}).get("used_items", {})
			if held is Dictionary:
				available -= int(held.get(item["good"], 0))
	if quantity > available or _world.personal_economy_state.native_allocations(person, item["good"], quantity).is_empty():
		return {"success": false, "error": "持有不足，或物品本期已分配给耐用品用途。"}
	for category: String in _category_order():
		var unit := _service(item["good"], category)
		var current := _needs.get(person, {}).get("categories", {}).get(category, {}) as Dictionary
		if unit > 0 and _spec["categories"][category]["mode"] == "flow" and quantity <= (int(current.get("unmet", 0)) + unit - 1) / unit:
			return {"success": true, "need_category": category, "quantity_scale": 1}
	return {"success": false, "error": "本期没有对应的未满足需要。"}


func personal_consume(person: String, commodity: String, quantity: int, source: String, id: String) -> Dictionary:
	var quote := personal_consumption_quote(person, commodity, quantity)
	if not quote.get("success", false):
		return quote
	var payload := {"commodity_id": commodity, "quantity": quantity, "need_category": quote["need_category"], "source": source}
	var automatic: bool = _spec["actors"][person]["control"] == "automatic"
	var command := _auto_command(person, "consume", payload, id) if automatic else {"action_id": id, "minute": _world.game_clock.total_minutes(), "kind": "consume", "payload": payload}
	var result := _accept(person, command, automatic)
	return {"success": result["accepted"], "error": result["reason"], "message": "已按实际批次消费，并计入当前需要。"}

func _consume_action(person: String, payload: Dictionary) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["commodity_id", "quantity", "need_category", "source"]) or not payload["commodity_id"] is String or not FormalLedgerState.valid_amount(payload["quantity"]) or not payload["source"] is String:
		return _result(false, "INVALID_CONSUMPTION")
	var quote := personal_consumption_quote(person, payload["commodity_id"], int(payload["quantity"]))
	if not quote.get("success", false) or quote["need_category"] != payload["need_category"]:
		return _result(false, "NO_OWNED_USABLE_ITEMS_OR_CURRENT_NEED")
	var good := str(payload["commodity_id"]).trim_prefix("native:")
	var category := str(payload["need_category"])
	var quantity := int(payload["quantity"])
	if quantity > FormalLedgerState.MAX_AMOUNT - int(_physical_totals[person]["used"][good]) or quantity > FormalLedgerState.MAX_AMOUNT - int(_totals[person]["categories"][category]["used_items"][good]):
		return _result(false, "CONSUMPTION_INTEGER_BOUNDS")
	var physical := _consumption_rows(person, good, quantity)
	if not _lots.ready(physical): return _result(false, "NO_ACCESSIBLE_PHYSICAL_SOURCE")
	if not _world.personal_economy_state.record_native_consumption(person, good, quantity, category, payload["source"]):
		return _result(false, "NO_SOURCE_LOTS")
	var consumed := _lots.consume(physical, _world.game_clock.total_minutes())
	assert(consumed)
	_physical_totals[person]["used"][good] = int(_physical_totals[person]["used"][good]) + quantity
	var need := _needs[person]["categories"][category] as Dictionary
	var satisfied := mini(int(need["unmet"]), quantity * _service(good, category))
	need["satisfied"] = int(need["satisfied"]) + satisfied
	need["unmet"] = int(need["unmet"]) - satisfied
	if need["used_items"] is Dictionary:
		need["used_items"][good] = int(need["used_items"][good]) + quantity
	var total := _totals[person]["categories"][category] as Dictionary
	total["satisfied"] = int(total["satisfied"]) + satisfied
	total["unmet"] = int(total["unmet"]) - satisfied
	total["used_items"][good] = int(total["used_items"][good]) + quantity
	return _result(true, "ACCEPTED")

func uses_host_accounts() -> bool:
	return bool(config.get("host_personal_accounts", false))

## Validate host identity and account references before any opening mutations.
func validate_formal_composition() -> bool:
	if not _personal_storage_bindings_valid(): return false
	if not uses_host_accounts() or not _host_firm_bindings_valid():
		return _fail("Formal native composition requires explicit host account ownership")
	for id: String in _spec["actors"]:
		var actor := _spec["actors"][id] as Dictionary
		if actor["kind"] != "named":
			continue
		var person := _world.person_overlay.person(id)
		if person.is_empty() or not _world.person_overlay.is_alive(id) or person.get("current_place_id") != actor.get("place_id", PLACE):
			return _fail("Configured named person is absent or outside its admitted place: " + id)
		if actor["control"] == "player" and id != _world.player_state.player_id():
			return _fail("Configured player is not the current formal player: " + id)
		var admission := _world.personal_economy_state.native_admission_reason(id)
		if not admission.is_empty(): return _fail(id+":"+admission)
		if int(actor["cash"]) != 0 or _world.ledger_state.account(actor["account_id"]).get("owner_id") != id:
			return _fail("Named person must use its existing formal account: " + id)
	# Ownership must include a reachable, explicitly supplied household business
	# relation. Empty information cannot silently remove the old living path.
	for id: String in _spec["actors"]:
		var actor := _spec["actors"][id] as Dictionary
		if actor["control"] == "dormant": continue
		for category: String in actor["needs"]:
			if int(actor["needs"][category]) == 0: continue
			var related: bool = false
			for info: Dictionary in _spec["information"]:
				if info["actor"] != id or info["kind"] != "supplier": continue
				var supplier := _candidate(info["candidate"])
				if _service(supplier["good"], category) > 0 and not _paths_for(id, _place(supplier["site"]), _place(id), int(info["delivery_day"])).is_empty():
					related = true
					break
			if not related:
				return _fail("Missing admitted household supplier relation: " + id + "/" + category)
	for account_id: String in _configured_accounts():
		var row := _configured_accounts()[account_id] as Dictionary
		if row["role"] != "personal_cash" and not _world.ledger_state.account(account_id).is_empty():
			return _fail("Configured native account already belongs to a host responsibility: " + account_id)
	return true

func host_account_specs() -> Dictionary:
	return _configured_accounts()

func background_responsibilities() -> Dictionary:
	var result: Dictionary = {}
	for actor: String in _actors:
		if _spec["actors"][actor]["kind"] == "cohort":
			var unit := _population_unit(actor)
			result[unit] = int(result.get(unit, 0)) + int(_actors[actor]["members"])
	return result

func owns_transaction(receipt: Dictionary) -> bool:
	if receipt.get("kind")=="capital_equipment": return _capital.valid_resale_payment(str(receipt.get("transaction_id","")))
	if receipt.get("kind")=="lease_rent": return _leases.valid_payment_batch(str(receipt.get("transaction_id","")))
	if receipt.get("kind")=="service_fee": return _service_market.valid_payment_batch(str(receipt.get("transaction_id","")))
	return str(receipt.get("transaction_id", "")).begins_with("r1:") or receipt.get("kind") in ["person_travel", "cargo_refund", "cargo_damages", "cargo_extra_freight", "goods", "freight", "loan_issue", "loan_repayment", "fx_principal", "fx_target", "fx_fee", "asset_trade", "dividend", "equity_issue"] or (receipt.get("kind") == "wage" and str(receipt.get("reference_id", "")).begins_with("work:"))

func next_person_action_id() -> String:
	return "formal_native:" + str(_world.game_clock.total_minutes()) + ":" + str(_commands.size() + _world.person_overlay.travel_action_count() + _scope_requests.size() + 1)

func _at_place(actor: String, place: String) -> bool:
	if _spec["actors"].has(actor) and _spec["actors"][actor]["kind"] == "named" and _world.person_travel != null:
		return _world.person_travel.is_present(actor, place)
	return _place(actor) == place

func _travel_action(actor: String, payload: Dictionary, action_id: String, internal: bool) -> Dictionary:
	if not manages_person(actor) or _world.person_travel == null or not FormalLedgerState.exact_fields(payload, ["destination_place_id"]) or not payload["destination_place_id"] is String: return _result(false, "INVALID_PERSON_TRAVEL")
	if _work_queue.has(actor): return _result(false, "WORK_INTERVAL_ALREADY_BOOKED")
	return _world.person_travel.start(actor, payload["destination_place_id"], action_id, internal)

## Explicit development custody at an existing operating site. Its owner never
## receives these goods into commercial stock and cannot sell personal property.
func _personal_storage_site(place: String, good: String) -> String:
	for row: Dictionary in config.get("personal_storage", []):
		if _spec["sites"].has(row["site_id"]) and _place(row["site_id"]) == place and row["goods"].has(good): return row["site_id"]
	return ""

func _can_carry_extra(person: String, good: String, quantity: int) -> bool:
	return not uses_host_accounts() or (_world.person_travel != null and _world.person_travel.can_carry_extra(person, good, quantity))

func _custody_fact(person: String, good: String, quantity: int, from_key: String, to_key: String, source: String, operation: String) -> Dictionary:
	return {"person_id": person, "commodity_id": "native:" + good, "quantity": quantity, "from_key": from_key, "to_key": to_key, "source_id": source, "operation": operation, "effective_minute": _world.game_clock.total_minutes(), "activity_place_id": _place(person), "allocations": _world.personal_economy_state.native_custody_allocations(person, good, quantity, from_key)}

func _personal_custody_action(actor: String, payload: Dictionary, id: String, kind: String) -> Dictionary:
	if not manages_person(actor) or not FormalLedgerState.exact_fields(payload, ["good", "quantity", "place_id"]) or payload["good"] not in _goods or not payload["place_id"] is String or not FormalLedgerState.valid_amount(payload["quantity"]) or int(payload["quantity"]) <= 0: return _result(false, "INVALID_PERSONAL_CUSTODY")
	if not _at_place(actor, payload["place_id"]): return _result(false, "OWNER_NOT_AT_CUSTODY_PLACE")
	var site := _personal_storage_site(payload["place_id"], payload["good"])
	if site.is_empty(): return _result(false, "NO_CONFIGURED_PERSONAL_CUSTODY")
	var store: bool = kind == "store_goods"
	if store and not _site_accepting(site): return _result(false, "CUSTODY_SITE_STOPPED_NEW_BUSINESS")
	if not store and not _can_carry_extra(actor, payload["good"], int(payload["quantity"])): return _result(false, "ITEMS_REQUIRE_SEPARATE_FREIGHT")
	var key := "STORED|" + str(payload["place_id"])
	var fact := _custody_fact(actor, payload["good"], int(payload["quantity"]), "CARRIED" if store else key, key if store else "CARRIED", id, kind)
	if fact["allocations"].is_empty(): return _result(false, "NO_OWNED_QUANTITY_AT_SOURCE")
	var prepared := _world.personal_economy_state.prepare_native_custody(fact)
	var rows := _physical_person_rows(actor, payload["good"], fact["allocations"])
	if prepared.is_empty() or not _lots.ready(rows): return _result(false, "INVALID_CUSTODY_SOURCE")
	_world.personal_economy_state.adopt_native_change(prepared)
	_lots.move(rows, "PERSON|"+actor+"|"+str(fact["to_key"]), _place(actor), _world.game_clock.total_minutes(), "", "", "", actor if fact["to_key"] == "CARRIED" else site)
	return {"accepted": true, "reason": "STORED" if store else "WITHDRAWN", "quantity": fact["quantity"], "site_id": site, "custody_fact": fact}

func _known_custody_place(person: String, place: String) -> bool:
	if _at_place(person, place): return true
	for candidate: String in _actors[person]["known_suppliers"]:
		var fields := candidate.split("|")
		var site := fields[2] if fields.size() == 3 else _primary_site(fields[0])
		if _spec["sites"].has(site) and _place(site) == place: return true
	for row: Dictionary in _world.personal_economy_state.native_custody_rows(person):
		if row["state"] == "STORED" and row["place_id"] == place: return true
	return false

func personal_freight_options(person: String, good: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not personal_authorized(person) or good not in _goods or not _at_place(person, _place(person)): return result
	var origin := _place(person)
	if _personal_storage_site(origin, good).is_empty(): return result
	var destinations: Dictionary = {}
	for row: Dictionary in config.get("personal_storage", []):
		var destination := _place(row["site_id"])
		if destination == origin or destinations.has(destination) or not row["goods"].has(good) or not _known_custody_place(person, destination): continue
		destinations[destination] = true
		for path: Dictionary in _paths_for(person, origin, destination, day):
			var currency := str(_world.ledger_state.account(_account(person)).get("denomination", FormalLedgerState.DENOMINATION))
			var legs := _locked_legs(path, currency)
			var valid: bool = true
			for leg: Dictionary in legs:
				if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == _account(person, currency)): valid = false
			if valid: result.append({"path_id": path["id"], "from_place_id": origin, "to_place_id": destination, "denomination": currency, "freight_per_unit": _freight(legs), "quantity_limit": _route_available(path), "travel_days": _travel_days(legs), "source_site_id": _personal_storage_site(origin, good), "destination_site_id": row["site_id"]})
	return result

func _personal_freight_action(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if not manages_person(actor) or not FormalLedgerState.exact_fields(payload, ["good", "quantity", "from_place_id", "to_place_id", "path_id", "denomination", "max_freight"]) or payload["good"] not in _goods or not FormalLedgerState.valid_amount(payload["quantity"]) or int(payload["quantity"]) <= 0 or int(payload["quantity"]) > 1000000 or not FormalLedgerState.valid_amount(payload["max_freight"]) or not FormalLedgerState.currency_id(payload["denomination"]): return _result(false, "INVALID_PERSONAL_FREIGHT")
	for field: String in ["from_place_id", "to_place_id", "path_id"]:
		if not payload[field] is String: return _result(false, "INVALID_PERSONAL_FREIGHT")
	if not _at_place(actor, payload["from_place_id"]) or payload["from_place_id"] == payload["to_place_id"]: return _result(false, "OWNER_NOT_AT_FREIGHT_ORIGIN")
	var source := _personal_storage_site(payload["from_place_id"], payload["good"])
	var destination := _personal_storage_site(payload["to_place_id"], payload["good"])
	if source.is_empty() or destination.is_empty() or not _site_accepting(source) or not _site_accepting(destination) or not _known_custody_place(actor, payload["to_place_id"]): return _result(false, "NO_KNOWN_PERMITTED_CUSTODY")
	var path: Dictionary = {}
	for candidate: Dictionary in _paths_for(actor, payload["from_place_id"], payload["to_place_id"], day):
		if candidate["id"] == payload["path_id"]: path = candidate
	if path.is_empty(): return _result(false, "NO_KNOWN_ROUTE")
	var legs := _locked_legs(path, payload["denomination"])
	if not _shared.path_conditions(legs, payload["good"]): return _result(false, "UNCONFIGURED_SHARED_WEIGHT_OR_SERVICE_WINDOW")
	var freight := _freight(legs)
	var account := _account(actor, payload["denomination"])
	if account.is_empty() or freight > int(payload["max_freight"]): return _result(false, "FREIGHT_CURRENCY_OR_LIMIT")
	for leg: Dictionary in legs:
		if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == account): return _result(false, "FREIGHT_CURRENCY_ACCOUNT")
	var quantity := int(payload["quantity"])
	if quantity > _route_available(path) or next_order >= FormalLedgerState.MAX_AMOUNT or (freight > 0 and quantity > FormalLedgerState.MAX_AMOUNT / freight): return _result(false, "FREIGHT_CAPACITY_OR_AMOUNT_BOUNDS")
	var id := "order:" + str(next_order)
	var fact := _custody_fact(actor, payload["good"], quantity, "STORED|" + str(payload["from_place_id"]), "FREIGHT|" + id, id, "freight_lock")
	if not _world.personal_economy_state.native_custody_ready(fact): return _result(false, "NO_OWNED_STORED_SOURCE_LOTS")
	var prepared := _world.personal_economy_state.prepare_native_custody(fact)
	var source_rows := _physical_person_rows(actor, payload["good"], fact["allocations"])
	if prepared.is_empty() or not _lots.ready(source_rows): return _result(false, "INVALID_CUSTODY_SOURCE")
	if freight > 0 and not _world.ledger_state.reserve(id, account, quantity * freight): return _result(false, "INSUFFICIENT_FREIGHT_CASH")
	_world.personal_economy_state.adopt_native_change(prepared)
	_lots.move(source_rows, "PERSON|"+actor+"|FREIGHT|"+id, payload["from_place_id"], _world.game_clock.total_minutes(), "", "", "", source)
	next_order += 1
	_orders[id] = {"id": id, "kind": "PERSONAL_FREIGHT", "buyer": actor, "seller": actor, "buyer_site": "", "seller_site": actor, "need_category": "", "good": payload["good"], "quantity": quantity, "pending": quantity, "transit": 0, "delivered": 0, "cancelled": 0, "price": 0, "action_id": action_id, "accepted_day": day, "accepted_minute": _world.game_clock.total_minutes(), "denomination": payload["denomination"], "buyer_account": account, "seller_account": account, "route_id": path["id"], "from_place_id": path["from_place_id"], "to_place_id": path["to_place_id"], "route_legs": legs, "custody_fact": fact, "source_custody_site": source, "destination_custody_site": destination}
	_pending_orders.append(id)
	_active_orders.append(id)
	_index_order(id)
	var edge := _edge(legs[0]["edge_id"])
	edge["input_used"] = int(edge["input_used"]) + quantity
	edge["holds"][id] = {"period": day, "quantity": quantity}
	return {"accepted": true, "reason": "PERSONAL_FREIGHT_ACCEPTED", "order_id": id, "quantity": quantity, "freight_per_unit": freight, "denomination": payload["denomination"]}

func _valid_custody_fact(fact: Variant, person: String, good: String, quantity: int, from_key: String, to_key: String, source: String, operation: String, minute: int) -> bool:
	if not fact is Dictionary or not FormalLedgerState.exact_fields(fact, ["person_id", "commodity_id", "quantity", "from_key", "to_key", "source_id", "operation", "effective_minute", "activity_place_id", "allocations"]) or fact["person_id"] != person or fact["commodity_id"] != "native:" + good or fact["quantity"] != quantity or fact["from_key"] != from_key or fact["to_key"] != to_key or fact["source_id"] != source or fact["operation"] != operation or fact["effective_minute"] != minute or not _world.spatial_catalog.has_place(str(fact["activity_place_id"])) or not fact["allocations"] is Array or fact["allocations"].is_empty(): return false
	var amount: int = 0
	for allocation: Variant in fact["allocations"]:
		if not allocation is Dictionary or not FormalLedgerState.exact_fields(allocation, ["purchase_record_id", "quantity", "custody_key"]) or not allocation["purchase_record_id"] is String or allocation["custody_key"] != from_key or not FormalLedgerState.valid_amount(allocation["quantity"]) or int(allocation["quantity"]) == 0: return false
		amount += int(allocation["quantity"])
	return amount == quantity

func _declared_named(person: String) -> bool:
	return _spec["actors"].has(person) and _spec["actors"][person]["kind"] == "named" and _spec["actors"][person]["control"] != "dormant"

func _valid_personal_freight_order(order: Dictionary) -> bool:
	var person := str(order["buyer"])
	if not _declared_named(person) or order["seller"] != person or order["seller_site"] != person or order["buyer_site"] != "" or order["price"] != 0 or order["need_category"] != "" or order["from_place_id"] == order["to_place_id"] or not FormalLedgerState.currency_id(order["denomination"]) or not order["route_legs"] is Array or order["route_legs"].is_empty(): return _fail("Invalid personal freight ownership")
	if order.get("source_custody_site", "").is_empty() or order.get("destination_custody_site", "").is_empty() or order["source_custody_site"] != _personal_storage_site(order["from_place_id"], order["good"]) or order["destination_custody_site"] != _personal_storage_site(order["to_place_id"], order["good"]): return _fail("Personal freight lacks explicit custody permissions")
	var path: Dictionary = {}
	for candidate: Dictionary in _paths_for(person, order["from_place_id"], order["to_place_id"], int(order["accepted_day"])):
		if candidate["id"] == order["route_id"]: path = candidate
	if path.is_empty() or order["route_legs"] != _locked_legs(path, order["denomination"]) or order["buyer_account"] != _account(person, order["denomination"]) or order["buyer_account"] != order["seller_account"] or str(order["buyer_account"]).is_empty(): return _fail("Personal freight changes its known path or account")
	for leg: Dictionary in order["route_legs"]:
		if int(leg["freight_per_unit"]) > 0 and (str(leg["carrier_account"]).is_empty() or leg["carrier_account"] == order["buyer_account"]): return _fail("Personal freight lacks its carrier account")
	var unit := _freight(order["route_legs"])
	if unit > 0 and int(order["quantity"]) > FormalLedgerState.MAX_AMOUNT / unit: return _fail("Personal freight amount bounds")
	if not _valid_custody_fact(order.get("custody_fact"), person, order["good"], order["quantity"], "STORED|" + str(order["from_place_id"]), "FREIGHT|" + str(order["id"]), order["id"], "freight_lock", order["accepted_minute"]) or order["custody_fact"]["activity_place_id"] != order["from_place_id"]: return _fail("Personal freight lacks original lot reservation")
	return true

func personal_custody_source(source: String, operation: String) -> Dictionary:
	if operation == "freight_lock":
		return _orders[source]["custody_fact"].duplicate(true) if _orders.has(source) and _orders[source]["kind"] == "PERSONAL_FREIGHT" else {}
	if operation == "freight_collect": return _delivery_receipts.get(source, {}).get("custody_fact", {}).duplicate(true)
	if operation == "freight_replace":
		var disposition := _cargo_fulfilment.dispositions.get(source, {}) as Dictionary
		return disposition.get("custody_fact", {}).duplicate(true) if disposition.get("status") == "EXECUTED" and disposition.get("terms", {}).get("mode") == "REPLACE" else {}
	if operation not in ["store_goods", "withdraw_goods", "freight_cancel"]: return {}
	return _commands.get(source, {}).get("result", {}).get("custody_fact", {}).duplicate(true)

func valid_personal_custody_key(person: String, key: String, good: String = "") -> bool:
	if key == "CARRIED": return true
	var fields := key.split("|", true, 1)
	if fields.size() != 2: return false
	if fields[0] == "STORED": return _world.spatial_catalog.has_place(fields[1]) and (good.is_empty() or not _personal_storage_site(fields[1], good).is_empty())
	if fields[0] == "FREIGHT": return _orders.has(fields[1]) and _orders[fields[1]]["kind"] == "PERSONAL_FREIGHT" and _orders[fields[1]]["buyer"] == person
	return false

func valid_personal_freight_lots(person: String, lots: Dictionary) -> bool:
	var committed: Dictionary = {}
	for good: String in lots:
		for lot: Dictionary in lots[good]:
			for key: String in lot.get("positions", {}):
				if key.begins_with("FREIGHT|"):
					var id := key.trim_prefix("FREIGHT|")
					if not _orders.has(id) or _orders[id]["kind"] != "PERSONAL_FREIGHT" or _orders[id]["buyer"] != person or _orders[id]["good"] != good: return false
					committed[id] = int(committed.get(id, 0)) + int(lot["positions"][key])
	for order: Dictionary in _orders.values():
		if order["kind"] == "PERSONAL_FREIGHT" and order["buyer"] == person and int(committed.get(order["id"], 0)) != int(order["pending"]) + int(order["transit"]) - _cargo_fulfilment.unresolved(order["id"]): return false
	return true

func personal_freight_custody(person: String, id: String) -> Dictionary:
	var order: Dictionary = _orders.get(id, {})
	if order.is_empty() or order["kind"] != "PERSONAL_FREIGHT" or order["buyer"] != person: return {}
	var view := _order_view(order)
	return {"order_id": id, "origin_place_id": order["from_place_id"], "destination_place_id": order["to_place_id"], "stage": view["stage"], "pending_quantity": order["pending"], "transit_quantity": int(order["transit"])-int(view["awaiting_recipient_quantity"]), "awaiting_quantity": view["awaiting_recipient_quantity"], "reserved_amount": view["reserved_amount"], "shipments": view["shipments"]}

func _collect_action(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if not manages_person(actor) or not EconomySliceConfig._fields(payload, ["shipment_id"], ["quantity", "custody_mode"]) or not payload["shipment_id"] is String: return _result(false, "INVALID_COLLECTION")
	var id := str(payload["shipment_id"])
	if not _shipments.has(id): return _result(false, "NO_UNCOLLECTED_BATCH")
	var cargo := _shipments[id] as Dictionary
	var order := _orders[cargo["order_id"]] as Dictionary
	if order["buyer"] != actor or cargo["stage"] != "AWAITING_RECIPIENT" or not _recipient_at_destination(order): return _result(false, "RECIPIENT_NOT_AT_CUSTODY_PLACE")
	var quantity: Variant = payload.get("quantity", cargo["quantity"])
	if not FormalLedgerState.valid_amount(quantity) or int(quantity) <= 0 or int(quantity) > int(cargo["quantity"]): return _result(false, "INVALID_COLLECTION_QUANTITY")
	var mode: Variant = payload.get("custody_mode", "STORED" if order["kind"] == "PERSONAL_FREIGHT" or not _can_carry_extra(actor, order["good"], int(quantity)) else "CARRIED")
	if mode not in ["CARRIED", "STORED"]: return _result(false, "INVALID_COLLECTION_CUSTODY")
	if not _deliver_shipment(cargo, order, action_id, int(quantity), mode): return _result(false, error)
	return {"accepted": true, "reason": "COLLECTED", "shipment_id": id, "quantity": int(quantity), "remaining_quantity": int(cargo["quantity"]), "place_id": order["to_place_id"], "custody_mode": mode, "paid_amount": int(quantity) * (int(order["price"]) + _freight(order["route_legs"]))}

## Only WorldBootstrap calls this after successful host composition. Runtime
## scope edits have no implicit exit path: orders, wages, cargo and contracts
## retain their saved owners even if a launch selection changes later.
func activate_formal_scope() -> bool:
	if not uses_host_accounts() or _management.get("status") != "READY" or _world.game_clock.total_minutes() != 0:
		return _fail("Native scope is not ready for new-world activation")
	for id: String in _spec["actors"]:
		if not _actors.has(id) or not _stocks.has(id): return _fail("Unprepared native actor: " + id)
	for id: String in _site_ids():
		if not _stocks.has(id) or not _site_state.has(id): return _fail("Unprepared native operating site: " + id)
	_management["status"] = "ACTIVE"
	if not _post_initial_credit_offers():
		_management["status"] = "READY"
		return false
	return true

func management_active() -> bool:
	return _management.get("status") == "ACTIVE"

func _scope_manager(actor: String) -> bool:
	for firm: String in _firm_ids():
		if not firm_finished(firm) and _manager(actor, firm): return true
	return false

## An append-only development request. Existing money, cargo, finance policies
## and contracts are never rebound. It becomes effective after the old day ends.
func _request_scope_expansion(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if not uses_host_accounts() or not is_multi() or not _scope_manager(actor): return _result(false, "NO_NATIVE_SCOPE_MANAGEMENT_AUTHORITY")
	if not EconomySliceConfig._fields(payload, [], ["actors", "firms", "sites", "jobs", "information", "routes", "transport_paths", "transport_nodes", "route_knowledge", "personal_storage"]): return _result(false, "INVALID_SCOPE_EXTENSION")
	var count: int = 0
	for field: String in payload:
		if not payload[field] is Array: return _result(false, "INVALID_SCOPE_EXTENSION_ROWS")
		count += payload[field].size()
	if count == 0 or count > 64 or _scope_requests.size() >= 64: return _result(false, "SCOPE_REQUEST_LIMIT")
	var candidate := _extension_configuration(payload)
	if candidate.has("error"): return _result(false, candidate["error"])
	if not _extension_route_authority(actor, payload): return _result(false, "NO_DECLARED_ROUTE_INFORMATION_SOURCE")
	for permission: Dictionary in payload.get("personal_storage", []):
		var owner: String = ""
		var normalized := EconomySliceConfig.normalize(candidate["configuration"], _world.person_overlay.person_ids())
		for company: String in normalized["firms"]:
			if normalized["firms"][company]["sites"].has(permission["site_id"]): owner = company
		if owner.is_empty() or (not _manager(actor, owner) and (_spec["firms"].has(owner) or normalized["firms"][owner].get("manager", owner) != actor)): return _result(false, "CUSTODY_SITE_OWNER_MANAGEMENT_REQUIRED")
	for site: Dictionary in payload.get("sites", []):
		if not _manager(actor, site["firm_id"]) or firm_finished(site["firm_id"]): return _result(false, "OPEN_SITE_OWNER_MANAGEMENT_REQUIRED")
	_scope_requests[action_id] = {"id": action_id, "actor": actor, "kind": "EXPAND", "payload": payload.duplicate(true), "requested_minute": _world.game_clock.total_minutes(), "boundary_minute": (day+1)*1440, "effective_minute": -1, "status": "QUEUED", "reason": ""}
	_pending_scope_requests.append(action_id)
	return {"accepted": true, "reason": "QUEUED_FOR_ECONOMIC_BOUNDARY", "request_id": action_id, "boundary_minute": (day+1)*1440}

func _extension_configuration(payload: Dictionary) -> Dictionary:
	var candidate := config.duplicate(true)
	for field: String in ["actors", "firms", "jobs", "information", "routes", "transport_paths", "transport_nodes", "personal_storage"]:
		if not payload.has(field): continue
		if not candidate.has(field): candidate[field] = []
		candidate[field].append_array(payload[field].duplicate(true))
	for row: Variant in payload.get("sites", []):
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["firm_id", "site"]) or not row["site"] is Dictionary: return {"error": "INVALID_SITE_EXTENSION"}
		var found: bool = false
		for firm: Dictionary in candidate["firms"]:
			if firm["id"] == row["firm_id"] and firm.has("sites"):
				firm["sites"].append(row["site"].duplicate(true))
				found = true
				break
		if not found: return {"error": "SITE_REQUIRES_EXISTING_MULTISITE_FIRM"}
	for knowledge: Variant in payload.get("route_knowledge", []):
		if not knowledge is Dictionary or not FormalLedgerState.exact_fields(knowledge, ["actor", "route_id"]) or not knowledge["actor"] is String or not knowledge["route_id"] is String: return {"error": "INVALID_ROUTE_KNOWLEDGE"}
		var declared: bool = false
		for subject: Dictionary in candidate["actors"]+candidate["firms"]:
			if subject["id"] == knowledge["actor"]: declared = true
		for firm: Dictionary in candidate["firms"]:
			for site: Dictionary in firm.get("sites", []):
				if site["id"] == knowledge["actor"]: declared = true
		if not declared: return {"error": "ROUTE_INFORMATION_HAS_NO_DECLARED_RECIPIENT"}
		var found: bool = knowledge["route_id"] == candidate["route"]["id"]
		for field: String in ["routes", "transport_paths"]:
			for route: Dictionary in candidate.get(field, []):
				if route["id"] == knowledge["route_id"]:
					if not route["known_to"].has(knowledge["actor"]): route["known_to"].append(knowledge["actor"])
					found = true
		if not found: return {"error": "UNKNOWN_EXTENSION_ROUTE"}
	if not EconomySliceConfig.valid(candidate): return {"error": "INVALID_COMBINED_BUSINESS_CONFIGURATION"}
	return {"configuration": EconomySliceConfig.canonical(candidate)}

func _extension_reason(candidate: Dictionary) -> String:
	var spec := EconomySliceConfig.normalize(candidate, _world.person_overlay.person_ids())
	for id: String in spec["actors"]:
		if _spec["actors"].has(id): continue
		var row := spec["actors"][id] as Dictionary
		if int(row["cash"]) != 0 or row["stock"] != _zero_goods(): return "RUNTIME_ADMISSION_CANNOT_CREATE_CASH_OR_STOCK"
		if row["kind"] == "named":
			var reason := _world.personal_economy_state.native_admission_reason(id, true)
			var property := _world.personal_economy_state.owned_handover_plan(id, candidate.get("commodity_mappings", []))
			if reason.is_empty() and not property.get("success", false): reason = property["reason"]
			if not reason.is_empty(): return id+":"+reason
			if row["place_id"] != _world.person_overlay.current_place(id) or row["account_id"] != FormalPersonalEconomyState.personal_account_id(id): return "HOST_PERSON_PLACE_OR_ACCOUNT_DIFFERS"
			if row["control"] == "player" and id != _world.player_state.player_id(): return "CURRENT_PLAYER_SCOPE_DIFFERS"
			var account := _world.ledger_state.account(row["account_id"])
			if not account.is_empty() and (account.get("owner_id") != id or account.get("role") != "personal_cash" or account.get("denomination") != FormalLedgerState.DENOMINATION): return "HOST_PERSON_ACCOUNT_HAS_DIFFERENT_OWNER"
		elif not _world.ledger_state.account(row["account_id"]).is_empty(): return "COHORT_ACCOUNT_HAS_EXISTING_RESPONSIBILITY"
	for id: String in spec["firms"]:
		if _spec["firms"].has(id): continue
		var row := spec["firms"][id] as Dictionary
		if int(row["cash"]) != 0 or not row.has("host_organization_id"): return "NEW_FIRM_REQUIRES_HOST_ORGANIZATION_AND_NO_ENDOWMENT"
		if not _world.ledger_state.account(row["account_id"]).is_empty(): return "EXISTING_FIRM_ACCOUNT_HAS_NO_CONTRACT_HANDOVER"
	for id: String in spec["sites"]:
		if _spec["sites"].has(id): continue
		if spec["sites"][id]["stock"] != _zero_goods(): return "NEW_SITE_CANNOT_CLAIM_MACRO_OR_INITIAL_STOCK"
		if not _world.spatial_catalog.has_place(spec["sites"][id]["place_id"]): return "SITE_HAS_NO_HOST_PLACE"
	for route: Dictionary in candidate.get("routes", []):
		if route["basis"] != "HOST_LINK": continue
		var link := _world.spatial_catalog.get_link(route.get("source_link_id", ""))
		var a := VNextSpatialCatalog.map_id_to_place_id(str(link.get("from_map_id", "")))
		var b := VNextSpatialCatalog.map_id_to_place_id(str(link.get("to_map_id", "")))
		if link.is_empty() or not ((route["from_place_id"] == a and route["to_place_id"] == b) or (route["from_place_id"] == b and route["to_place_id"] == a)): return "CARGO_EXTENSION_HAS_NO_MATCHING_HOST_CONNECTION"
	var old_spec := _spec
	var old_configuration := config
	_spec = spec
	_invalidate_configuration_queries()
	config = candidate
	_invalidate_configuration_queries()
	var valid := _population_bindings_valid() and _host_firm_bindings_valid() and _personal_storage_bindings_valid()
	var reason := error if not valid else ""
	if valid:
		for id: String in spec["actors"]:
			if old_spec["actors"].has(id): continue
			var row := spec["actors"][id] as Dictionary
			if row["kind"] == "named":
				var property := _world.personal_economy_state.owned_handover_plan(id, candidate.get("commodity_mappings", []))
				for fact: Dictionary in property.get("facts", []):
					if (_personal_storage_site(row["place_id"], fact["good"]).is_empty() or not _site_accepting(_personal_storage_site(row["place_id"], fact["good"]))): reason = "MAPPED_PERSONAL_PROPERTY_REQUIRES_LOCAL_LEGAL_CUSTODY"
			if row["control"] == "dormant":
				reason = "DORMANT_SUBJECT_CANNOT_ASSUME_LIVING_RESPONSIBILITY"
				break
			for category: String in row["needs"]:
				if int(row["needs"][category]) == 0: continue
				var related: bool = false
				for info: Dictionary in spec["information"]:
					if info["actor"] != id or info["kind"] != "supplier": continue
					var supplier := _candidate(info["candidate"])
					if _service(supplier["good"], category) > 0 and not _paths_for(id, _place(supplier["site"]), row["place_id"], int(info["delivery_day"])).is_empty(): related = true
				if not related: reason = id+":NO_ADMITTED_HOUSEHOLD_SUPPLIER_FOR_"+category
	_spec = old_spec
	_invalidate_configuration_queries()
	config = old_configuration
	_invalidate_configuration_queries()
	return reason

func apply_scope_boundary() -> void:
	if not uses_host_accounts() or processing or _world.game_clock.total_minutes() != day*1440: return
	_apply_business_boundary()
	_labor_market.boundary()
	if not _labor_market._rules.is_empty(): _auto_work()
	_capital.boundary()
	for id: String in _pending_scope_requests.duplicate():
		var request := _scope_requests[id] as Dictionary
		if request["kind"] == "EXIT" and request["status"] in ["QUEUED", "DEFERRED"] and int(request["boundary_minute"]) <= _world.game_clock.total_minutes():
			var reason := _scope_exit_reason(request["payload"]["subject_id"])
			if reason.is_empty():
				request["status"] = "APPLIED"
				request["reason"] = "LEGACY_RESIDENT_CONSUMPTION_FORMAL_ACCOUNT_AND_HISTORY_RETAINED"
				request["effective_minute"] = _world.game_clock.total_minutes()
			else:
				request["status"] = "DEFERRED"
				request["reason"] = reason
				request["boundary_minute"] = (day+1)*1440
			_pending_scope_requests.erase(id)
			continue
		if request["kind"] == "REENTER" and int(request["boundary_minute"]) <= _world.game_clock.total_minutes():
			var reason := _reentry_reason(request["actor"])
			if reason.is_empty(): _commit_reentry(request)
			else:
				request["status"] = "DEFERRED"
				request["reason"] = reason
				request["boundary_minute"] = (day+1)*1440
			continue
		if request["kind"] != "EXPAND" or request["status"] not in ["QUEUED", "DEFERRED"] or int(request["boundary_minute"]) > _world.game_clock.total_minutes(): continue
		var combined := _extension_configuration(request["payload"])
		var reason := str(combined.get("error", ""))
		if reason.is_empty(): reason = _extension_reason(combined["configuration"])
		if not reason.is_empty():
			request["status"] = "DEFERRED"
			request["reason"] = reason
			request["boundary_minute"] = (day+1)*1440
			continue
		if not _install_extension(combined["configuration"], request):
			request["status"] = "DEFERRED"
			request["reason"] = error
			request["boundary_minute"] = (day+1)*1440

func _install_extension(candidate: Dictionary, request: Dictionary) -> bool:
	for info: Dictionary in candidate["information"]:
		if not _spec["information"].has(info):
			info["delivery_day"] = maxi(day+1, int(info["delivery_day"]))
			info["observed_day"] = day
	var spec := EconomySliceConfig.normalize(candidate, _world.person_overlay.person_ids())
	var old_config := config
	var old_spec := _spec
	var old_actors := _actors
	var property_plans: Array[Dictionary] = []
	for id: String in spec["actors"]:
		if not old_spec["actors"].has(id) and spec["actors"][id]["kind"] == "named":
			var plan := _world.personal_economy_state.owned_handover_plan(id, candidate.get("commodity_mappings", []))
			if not plan.get("success", false): return _fail(plan.get("reason", "Property preparation failed"))
			property_plans.append_array(plan["facts"])
	var ledger_before := _world.ledger_state.snapshot()
	# Prepare all real accounts before publishing any future economic ownership.
	for id: String in spec["actors"]:
		if _actors.has(id): continue
		var row := spec["actors"][id] as Dictionary
		var account := _world.ledger_state.account(row["account_id"])
		if account.is_empty() and not _world.ledger_state.open_account(row["account_id"], id, "personal_cash" if row["kind"] == "named" else "r1_cohort"):
			_world.ledger_state.restore(ledger_before)
			return _fail("Runtime actor account preparation failed")
	for id: String in spec["firms"]:
		if old_spec["firms"].has(id): continue
		if not _world.ledger_state.open_account(spec["firms"][id]["account_id"], id, "r1_firm"):
			_world.ledger_state.restore(ledger_before)
			return _fail("Runtime enterprise account preparation failed")
	config = candidate
	_invalidate_configuration_queries()
	_spec = spec
	_invalidate_configuration_queries()
	_actors = _actors.duplicate(true)
	for id: String in spec["actors"]:
		if not _actors.has(id): _actors[id] = {"members": spec["actors"][id]["members"]}
	var background: Dictionary = {}
	for id: String in spec["actors"]:
		if spec["actors"][id]["kind"] == "cohort":
			var unit := _population_unit(id)
			background[unit] = int(background.get(unit, 0))+int(spec["actors"][id]["members"])
	if not _world.population_state.bind_native_background(background, self, true):
		config = old_config
		_invalidate_configuration_queries()
		_spec = old_spec
		_invalidate_configuration_queries()
		_actors = old_actors
		_world.ledger_state.restore(ledger_before)
		return _fail("Runtime population responsibility could not be published")
	var now := _world.game_clock.total_minutes()
	for id: String in spec["actors"]:
		if old_spec["actors"].has(id): continue
		var row := spec["actors"][id] as Dictionary
		_actors[id] = {"members": row["members"], "control": row["control"], "account_id": row["account_id"], "known_jobs": [], "known_suppliers": []}
		_lots.configure(_goods, _actor_ids_from_spec())
		_lots.ensure_subject(id)
		_physical_totals[id] = {"produced": _zero_goods(), "used": _zero_goods()}
		_totals[id] = {"categories": _initial_need_totals(id), "work_hours": 0, "income": 0}
		_subject_activation[id] = now
		if row["kind"] == "named": _world.personal_economy_state.admit_runtime_account(id, row["account_id"], now)
	for fact: Dictionary in property_plans:
		_commit_property_handover(fact, request["id"], now)
	for id: String in spec["sites"]:
		if _stocks.has(id): continue
		_lots.configure(_goods, _actor_ids_from_spec())
		_lots.ensure_subject(id)
		_physical_totals[id] = {"produced": _zero_goods(), "used": _zero_goods()}
		_firm_knowledge[id] = []
		_site_state[id] = _initial_site_state()[id]
		_subject_activation[id] = now
	for id: String in spec["firms"]:
		if not _firm_state.has(id):
			_firm_state[id] = _initial_firm_state()[id]
			_subject_activation[id] = now
	for id: String in _initial_job_postings():
		if not _job_postings.has(id): _job_postings[id] = _initial_job_postings()[id]
	for key: String in _initial_quote_state(day):
		if not _quote_state.has(key): _quote_state[key] = _initial_quote_state(day)[key]
	for edge: Dictionary in _all_routes().values():
		if not _transport["edges"].has(edge["id"]): _transport["edges"][edge["id"]] = {"period": day, "input_used": 0, "dispatched": 0, "holds": {}, "capacity": edge["capacity"], "capacity_action": ""}
	for node: Dictionary in config.get("transport_nodes", []):
		if not _transport["nodes"].has(node["place_id"]): _transport["nodes"][node["place_id"]] = {"dispatched": 0}
	for info: Dictionary in spec["information"]:
		if old_spec["information"].has(info): continue
		var info_id := "message:"+str(info["actor"])+":"+str(info["kind"])+":"+str(info["candidate"])
		_messages.append({"id": info_id, "actor": info["actor"], "kind": info["kind"], "candidate": info["candidate"], "observed_day": day, "delivery_day": maxi(day+1, int(info["delivery_day"]))})
		if info["kind"] == "job":
			var posting := _job_postings[info["candidate"]] as Dictionary
			if int(posting["version"]) > 0:
				_messages.append({"id": "posting:"+str(info["actor"])+":"+str(info["candidate"]), "actor": info["actor"], "kind": "job_posting", "candidate": info["candidate"], "observed_day": posting["published_day"], "delivery_day": maxi(int(info["delivery_day"]), int(posting["published_day"])+int(_job(info["candidate"]).get("notice_delay", 1))), "version": posting["version"], "positions": posting["positions"]})
	request["status"] = "APPLIED"
	request["effective_minute"] = now
	request["reason"] = "FUTURE_BUSINESS_WITH_OWNED_PROPERTY_HANDOVER" if not property_plans.is_empty() else "FUTURE_BUSINESS_ONLY_NO_ASSET_REISSUE"
	_pending_scope_requests.erase(request["id"])
	for subject: Dictionary in request["payload"].get("actors", []):
		if subject["kind"] == "named": _world.personal_economy_state.commit_native_arrangements(subject["id"], request["id"], now)
	if not config.has("person_travel"): _world.person_travel.configure_notices(EconomyDevelopmentConfig.formal_arrival_notices(config))
	for id: String in spec["actors"]:
		if manages_person(id): observe_person_place(id)
	_auto_work([], "admission:"+str(request["id"]))
	error = ""
	return true

func _request_scope_exit(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if _scope_requests.size() >= 64: return _result(false, "SCOPE_REQUEST_LIMIT")
	if not FormalLedgerState.exact_fields(payload, ["subject_id"]) or not payload["subject_id"] is String: return _result(false, "NO_SCOPE_EXIT_AUTHORITY")
	var subject := str(payload["subject_id"])
	if not (subject == actor and manages_person(subject)) and not _scope_manager(actor): return _result(false, "NO_SCOPE_EXIT_AUTHORITY")
	if not _actors.has(subject) and not _spec["firms"].has(subject) and not _spec["sites"].has(subject): return _result(false, "UNKNOWN_MANAGED_SUBJECT")
	if (_spec["firms"].has(subject) or _spec["sites"].has(subject)) and not _manager(actor, _owner(subject)): return _result(false, "SUBJECT_OWNER_MANAGEMENT_REQUIRED")
	if manages_person(subject) and subject != actor: return _result(false, "PERSONAL_OWNER_MUST_REQUEST_EXIT")
	if subject_exit_minute(subject) >= 0: return _result(false, "SUBJECT_ALREADY_EXITED")
	for request: Dictionary in _scope_requests.values():
		if request["kind"] == "EXIT" and request["payload"].get("subject_id") == subject and request["status"] != "APPLIED": return _result(false, "EXIT_REQUEST_ALREADY_PENDING")
	var reason := _scope_exit_reason(subject)
	_scope_requests[action_id] = {"id": action_id, "actor": actor, "kind": "EXIT", "payload": payload.duplicate(true), "requested_minute": _world.game_clock.total_minutes(), "boundary_minute": (day+1)*1440, "effective_minute": -1, "status": "QUEUED", "reason": reason}
	_pending_scope_requests.append(action_id)
	return {"accepted": true, "reason": "EXIT_DEFERRED" if not reason.is_empty() else "EXIT_QUEUED", "responsibility_reason": reason, "boundary_minute": (day+1)*1440}


func _valid_scope_lifecycle(commands: Dictionary) -> bool:
	var claimed_activation: Dictionary = {}
	var personal_events: Dictionary = {}
	for subject: Variant in _subject_activation:
		var minute: Variant = _subject_activation[subject]
		if not subject is String or (not _spec["actors"].has(subject) and not _spec["firms"].has(subject) and not _spec["sites"].has(subject)) or not FormalLedgerState.valid_amount(minute) or int(minute) < 1440 or int(minute)%1440 != 0 or int(minute) > _world.game_clock.total_minutes(): return _fail("Invalid subject activation boundary")
	for id: Variant in _scope_requests:
		var row: Variant = _scope_requests[id]
		if not id is String or not row is Dictionary or not FormalLedgerState.exact_fields(row, ["id", "actor", "kind", "payload", "requested_minute", "boundary_minute", "effective_minute", "status", "reason"]) or row["id"] != id or not row["payload"] is Dictionary or row["kind"] not in ["EXPAND", "EXIT", "REENTER"] or row["status"] not in ["QUEUED", "DEFERRED", "APPLIED"] or not FormalLedgerState.valid_amount(row["requested_minute"]) or int(row["requested_minute"]) > _world.game_clock.total_minutes() or not FormalLedgerState.valid_amount(row["boundary_minute"]) or int(row["boundary_minute"])%1440 != 0: return _fail("Invalid saved scope request")
		if not row["actor"] is String or (not _scope_manager_at(row["actor"], int(row["requested_minute"])) and not (row["kind"] in ["EXIT", "REENTER"] and row["payload"].get("subject_id") == row["actor"] and _declared_named(row["actor"]))) or not row["reason"] is String or typeof(row["effective_minute"]) != TYPE_INT: return _fail("Scope request has no declared manager or outcome")
		if row["kind"] == "EXPAND":
			if not EconomySliceConfig._fields(row["payload"], [], ["actors", "firms", "sites", "jobs", "information", "routes", "transport_paths", "transport_nodes", "route_knowledge", "personal_storage"]): return _fail("Unknown saved extension field")
			for field: String in row["payload"]:
				if not row["payload"][field] is Array: return _fail("Saved extension rows are not arrays")
				for item: Variant in row["payload"][field]:
					if not item is Dictionary: return _fail("Invalid saved extension row")
		var entry := commands.get(id, {}) as Dictionary
		if entry.is_empty() or entry.get("envelope", {}).get("actor") != row["actor"] or entry.get("envelope", {}).get("command", {}).get("minute") != row["requested_minute"] or entry.get("result", {}).get("accepted") != true: return _fail("Scope request has no accepted formal action")
		var command := entry["envelope"]["command"] as Dictionary
		if row["kind"] in ["EXIT", "REENTER"]:
			if command["kind"] != ("request_scope_exit" if row["kind"] == "EXIT" else "reenter_scope") or command["payload"] != row["payload"]: return _fail("Exit differs from its retained authority")
		elif command["kind"] == "expand_scope":
			if command["payload"] != row["payload"]: return _fail("Extension differs from its declared business")
		elif command["kind"] == "expand_configured_scope":
			var declared: bool = false
			for option: Dictionary in config.get("runtime_expansions", []):
				if command["payload"] == {"extension_id": option["id"]} and option["extension"] == row["payload"]: declared = true
			if not declared: return _fail("Extension has no saved configuration source")
		else: return _fail("Scope request action is unrelated")
		if row["status"] == "APPLIED" and row["kind"] == "EXIT":
			var subject: Variant = row["payload"].get("subject_id")
			if not subject is String or not _declared_named(subject) or subject != row["actor"] or row["reason"] != "LEGACY_RESIDENT_CONSUMPTION_FORMAL_ACCOUNT_AND_HISTORY_RETAINED" or row["effective_minute"] != row["boundary_minute"] or int(row["effective_minute"]) <= int(row["requested_minute"]) or int(row["effective_minute"]) > _world.game_clock.total_minutes(): return _fail("Invalid completed personal scope exit")
			if not personal_events.has(subject): personal_events[subject] = []
			personal_events[subject].append(row)
		elif row["status"] == "APPLIED" and row["kind"] == "REENTER":
			var subject: Variant = row["payload"].get("subject_id")
			if not subject is String or not _declared_named(subject) or subject != row["actor"] or row["payload"] != {"subject_id": subject} or row["reason"] != "REACTIVATED_SAME_PERSON_ACCOUNT_AND_HISTORY" or row["effective_minute"] != row["boundary_minute"] or int(row["effective_minute"]) <= int(row["requested_minute"]) or int(row["effective_minute"]) > _world.game_clock.total_minutes(): return _fail("Invalid personal reentry")
			if not personal_events.has(subject): personal_events[subject] = []
			personal_events[subject].append(row)
		elif row["status"] == "APPLIED":
			for field: String in ["actors", "firms"]:
				for subject: Dictionary in row["payload"].get(field, []):
					if not _spec[field].has(subject["id"]) or claimed_activation.has(subject["id"]): return _fail("Admitted subject is absent or repeated")
					claimed_activation[subject["id"]] = row["effective_minute"]
					if field == "firms":
						for site: Dictionary in subject.get("sites", []): claimed_activation[site["id"]] = row["effective_minute"]
			for item: Dictionary in row["payload"].get("sites", []):
				var subject := str(item["site"]["id"])
				if not _spec["sites"].has(subject) or claimed_activation.has(subject): return _fail("Admitted site is absent or repeated")
				claimed_activation[subject] = row["effective_minute"]
			if row["kind"] != "EXPAND" or int(row["effective_minute"])%1440 != 0 or int(row["effective_minute"]) <= int(row["requested_minute"]) or int(row["effective_minute"]) > _world.game_clock.total_minutes(): return _fail("Scope activation precedes its legal boundary")
		elif row["effective_minute"] != -1 or (int(row["boundary_minute"]) <= _world.game_clock.total_minutes() and not (row["kind"] == "EXIT" and row["status"] == "DEFERRED")): return _fail("Pending scope responsibility has no future boundary")
	if claimed_activation != _subject_activation: return _fail("Subject activation lacks its real admission request")
	for subject: String in personal_events:
		personal_events[subject].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
		var active: bool = true
		var boundary: int = int(_subject_activation.get(subject, 0))
		for row: Dictionary in personal_events[subject]:
			if int(row["requested_minute"]) < boundary or int(row["effective_minute"]) <= boundary or (row["kind"] == "EXIT") != active: return _fail("Overlapping or repeated personal management interval")
			active = not active
			boundary = int(row["effective_minute"])
	_pending_scope_requests.clear()
	for id: String in _scope_requests:
		var row := _scope_requests[id] as Dictionary
		if row["status"] == "QUEUED" or (row["status"] == "DEFERRED" and row["kind"] != "EXIT"): _pending_scope_requests.append(id)
	return true

func scope_change_view(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in _scope_requests.values():
		if row["actor"] != actor: continue
		result.append({"id": row["id"], "kind": row["kind"], "status": row["status"], "reason": row["reason"], "boundary_minute": row["boundary_minute"], "effective_minute": row["effective_minute"], "subject_id": row["payload"].get("subject_id", ""), "responsibilities": scope_subject_responsibilities(row["payload"]["subject_id"]) if row["kind"] == "EXIT" and _can_observe_scope_subject(actor, row["payload"]["subject_id"]) else {}})
	return result

func scope_options(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _scope_manager(actor): return result
	for row: Dictionary in config.get("runtime_expansions", []):
		var used: bool = false
		for request: Dictionary in _scope_requests.values():
			if request["kind"] == "EXPAND" and request["payload"] == row.get("extension", {}): used = true
		if not used: result.append({"id": row["id"], "label": row["label"]})
	return result

func _request_configured_expansion(actor: String, payload: Dictionary, action_id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["extension_id"]) or not payload["extension_id"] is String: return _result(false, "INVALID_CONFIGURED_SCOPE_REQUEST")
	for row: Dictionary in config.get("runtime_expansions", []):
		if row["id"] == payload["extension_id"]: return _request_scope_expansion(actor, row["extension"], action_id)
	return _result(false, "UNKNOWN_CONFIGURED_EXTENSION")

func management_view() -> Dictionary:
	var people: Array[Dictionary] = []
	var cohorts: Array[Dictionary] = []
	var firms: Array[Dictionary] = []
	var sites: Array[Dictionary] = []
	var places: Dictionary = {}
	var background: int = 0
	for id: String in _actor_ids():
		var actor := _spec["actors"][id] as Dictionary
		if actor["control"] == "dormant": continue
		places[_place(id)] = true
		var row := {"id": id, "place_id": _place(id), "activity_population_unit_id": _world.population_state.unit_for_place(_place(id)), "resident_population_unit_id": _population_unit(id), "population_unit_id": _population_unit(id), "members": actor["members"], "activation_minute": _subject_activation.get(id, 0), "lifecycle": person_management_view(id) if actor["kind"] == "named" else {}, "identity_basis": "HOST_NAMED_PERSON" if actor["kind"] == "named" else "HOST_ANONYMOUS_POPULATION_RANGE"}
		if actor["kind"] == "named": people.append(row)
		else:
			row["population_start"] = actor["population_start"]
			var profile := _cohort_profile(id)
			row["cohort_profile"] = {}
			for field: String in ["stratum_id", "label", "occupation", "basis"]:
				if profile.has(field): row["cohort_profile"][field] = profile[field]
			row["labor_members"] = Cohorts.labor_members(actor)
			cohorts.append(row)
			background += int(actor["members"])
	for firm: String in _firm_ids():
		var organization := str(_spec["firms"][firm].get("host_organization_id", ""))
		firms.append({"id": firm, "host_organization_id": organization, "identity_basis": _business_identity_basis(firm), "business_basis": "DEVELOPMENT_CONFIGURATION", "manager": firm_manager_at(firm, _world.game_clock.total_minutes()), "operating": _firm_operating(firm), "winding_down": _firm_winding_down(firm), "finished": firm_finished(firm)})
	for id: String in _site_ids():
		places[_place(id)] = true
		sites.append({"id": id, "firm_id": _owner(id), "place_id": _place(id), "space_basis": "HOST_CATALOG", "facility_basis": _spec["sites"][id]["basis"], "population_unit_id": _world.population_state.unit_for_place(_place(id)), "activation_minute": _subject_activation.get(id, 0), "roles": _spec["sites"][id]["roles"].duplicate(), "operating": _site_operating(id), "closed": site_closed(id), "base_capacity": _spec["sites"][id]["capacity"], "effective_capacity": site_capacity(id), "installed_capital_assets": _capital.installed_assets(id).size()})
	return {"scope_id": _management.get("scope_id", ""), "status": _management.get("status", "PREPARED"), "activation_minute": _management.get("activation_minute", 0), "named_people": people, "cohorts": cohorts, "background_population": background, "population": people.size()+background, "firms": firms, "sites": sites, "place_ids": _sorted_ids(places), "identity_basis": "HOST_WORLD", "business_basis": "DEVELOPMENT_CONFIGURATION", "scope_changes": "BOUNDARY_ADMISSION_EXIT_AND_SAME_PERSON_REENTRY", "inventory_authority": "NATIVE_OPERATING_SITES", "cash_authority": "FORMAL_LEDGER", "remaining_scope": "LEGACY_MACRO_AND_PERSONAL"}

func _region_for(place: String) -> String:
	var row := _world.spatial_catalog.get_place(place)
	var region := str(row.get("parent_region_id", ""))
	return region if not region.is_empty() else _world.population_state.unit_for_place(place)

func _empty_region(id: String) -> Dictionary:
	return {"region_id": id, "named_people": 0, "background_population": 0, "travelling_named_people": 0, "sites": 0, "labor_hours": 0, "produced": _zero_goods(), "site_inventory": _zero_goods(), "free_sale_stock": _zero_goods(), "committed": _zero_goods(), "household_stock": _zero_goods(), "consumed": _zero_goods(), "current_unmet": {}, "wages_by_currency": {}, "labor_population": 0, "employed_people": 0, "unemployed_people": 0, "cohort_strata": {}, "need_results": {}, "cohort_need_history": {}, "accepted_orders": 0, "in_transit": _zero_goods(), "revenue_by_currency": {}, "credit_by_currency": {}}

## Detached observation of authoritative facts. No projection can sell goods,
## pay money or advance time. Publication of regional aggregates is explicit;
## otherwise metrics cover only the observer and their managed enterprises.
## Public aggregate strata do not disclose private cash, holdings, quotes or
## future plans. Bounded pages refer to the same population/contract/need facts.
func cohort_observation(observer: String, limit: int = 16, offset: int = 0) -> Dictionary:
	if observer != _world.player_state.player_id() or not _world.person_overlay.is_alive(observer): return {}
	var public_totals: bool = config.get("management_scope", {}).get("statistics_visibility", "OWNER_ONLY") == "PUBLIC_AGGREGATES"
	if not public_totals: return {"rows": [], "total": 0, "offset": 0, "limit": 0, "visibility": "NO_PUBLIC_COHORT_STATISTICS"}
	var ids: Array[String] = []
	for actor: String in _actor_ids():
		if _spec["actors"][actor]["kind"] == "cohort": ids.append(actor)
	var rows: Array[Dictionary] = []
	limit = clampi(limit, 1, 32)
	offset = maxi(0, offset)
	for index: int in range(mini(ids.size(), offset), mini(ids.size(), offset+limit)):
		var actor := ids[index]
		var profile := _cohort_profile(actor)
		var workers := Cohorts.labor_members(_spec["actors"][actor])
		var employed := Cohorts.employed(_contracts.get(actor, {}))
		var current := _needs.get(actor, {}).get("categories", {}) as Dictionary
		var today: Dictionary = {}
		for category: String in current:
			today[category] = {"required": current[category]["required"], "satisfied": current[category]["satisfied"], "unmet": current[category]["unmet"]}
		var mature: Dictionary = {}
		for id: String in _wages_by_worker.get(actor, []):
			var claim := _wages[id] as Dictionary
			if int(claim["due_day"]) <= day: mature[claim["denomination"]] = int(mature.get(claim["denomination"], 0))+int(claim["remaining"])
		var cumulative: Dictionary = {}
		for category: String in _totals[actor]["categories"]:
			cumulative[category] = {}
			for field: String in ["required", "satisfied", "unmet"]: cumulative[category][field] = _totals[actor]["categories"][category][field]
		rows.append({"id": actor, "place_id": _place(actor), "population_unit_id": _population_unit(actor), "population_start": _spec["actors"][actor]["population_start"], "members": _actors[actor]["members"], "label": profile.get("label", "旧同质 cohort"), "occupation": profile.get("occupation", "LEGACY_UNSPECIFIED"), "basis": profile.get("basis", "LEGACY_CONFIGURATION"), "labor_members": workers, "employed": employed, "unemployed": workers-employed, "employment_basis": "ACTIVE_CONTRACT_WORKER_SHARES", "household_basis": "AGGREGATE_GROUP_BUDGET_NO_MEMBER_WELFARE_INFERENCE", "paid_wages_by_currency": _income_by_actor.get(actor, {}).duplicate(true), "matured_unpaid_by_currency": mature, "need_day": _needs.get(actor, {}).get("day", -1), "needs": today, "cumulative_needs": cumulative, "service_targets": _service_market._resident.need_view(actor), "housing_use": _leases.housing_view(actor), "work_hours": _totals[actor]["work_hours"]})
	return {"rows": rows, "total": ids.size(), "offset": offset, "limit": limit, "visibility": "PUBLIC_COHORT_AGGREGATES"}

func regional_observation(observer: String) -> Dictionary:
	if _management.get("status") != "ACTIVE" or observer != _world.player_state.player_id() or not _world.person_overlay.is_alive(observer): return {}
	var public_totals: bool = config.get("management_scope", {}).get("statistics_visibility", "OWNER_ONLY") == "PUBLIC_AGGREGATES"
	var allowed: Dictionary = {observer: true}
	for firm: String in _firm_ids():
		if _manager(observer, firm): allowed[firm] = true
	var regions: Dictionary = {}
	var resident_counts: Dictionary = {}
	var unlocated_consumption: Dictionary = {}
	for actor: String in _actor_ids():
		if _actors[actor]["control"] == "dormant" or (not public_totals and not allowed.has(actor)): continue
		var region := _region_for(_place(actor))
		if not regions.has(region): regions[region] = _empty_region(region)
		var row := regions[region] as Dictionary
		var named: bool = _spec["actors"][actor]["kind"] == "named"
		resident_counts[_population_unit(actor)] = int(resident_counts.get(_population_unit(actor), 0)) + int(_actors[actor]["members"])
		if named:
			if _at_place(actor, _place(actor)): row["named_people"] += 1
			else: row["travelling_named_people"] = int(row.get("travelling_named_people", 0)) + 1
			for property: Dictionary in _world.personal_economy_state.native_custody_rows(actor):
				if property["state"] == "FREIGHT": continue # Same quantities appear as cargo below.
				var property_region := _region_for(property["place_id"])
				if not regions.has(property_region): regions[property_region] = _empty_region(property_region)
				regions[property_region]["household_stock"][property["good"]] += int(property["quantity"])
			var places := _world.personal_economy_state.native_consumption_places(actor)
			for place: String in places:
				if place == "UNRECORDED_ACTIVITY_PLACE":
					for good: String in places[place]: unlocated_consumption[good] = int(unlocated_consumption.get(good, 0)) + int(places[place][good])
					continue
				var consumption_region := _region_for(place)
				if not regions.has(consumption_region): regions[consumption_region] = _empty_region(consumption_region)
				for good: String in places[place]: regions[consumption_region]["consumed"][good] += int(places[place][good])
		else:
			row["background_population"] += int(_actors[actor]["members"])
			var employed := Cohorts.employed(_contracts.get(actor, {}))
			var workers := Cohorts.labor_members(_spec["actors"][actor])
			row["labor_population"] += workers
			row["employed_people"] += employed
			row["unemployed_people"] += workers-employed
			var profile := _cohort_profile(actor)
			var label := str(profile.get("label", "旧同质 cohort"))
			if not row["cohort_strata"].has(label): row["cohort_strata"][label] = {"members": 0, "labor_members": 0, "employed": 0, "unemployed": 0, "cohorts": 0}
			var stratum := row["cohort_strata"][label] as Dictionary
			stratum["members"] += int(_actors[actor]["members"])
			stratum["labor_members"] += workers
			stratum["employed"] += employed
			stratum["unemployed"] += workers-employed
			stratum["cohorts"] += 1
			for good: String in _goods:
				row["household_stock"][good] += int(_stocks[actor][good])
				row["consumed"][good] += int(_physical_totals[actor]["used"][good])
		if not named:
			for category: String in _totals[actor]["categories"]:
				if not row["cohort_need_history"].has(category): row["cohort_need_history"][category] = {"required": 0, "satisfied": 0, "unmet": 0}
				for field: String in ["required", "satisfied", "unmet"]: row["cohort_need_history"][category][field] += int(_totals[actor]["categories"][category][field])
		for category: String in _needs.get(actor, {}).get("categories", {}):
			if not row["need_results"].has(category): row["need_results"][category] = {"required": 0, "satisfied": 0, "unmet": 0}
			for field: String in ["required", "satisfied", "unmet"]: row["need_results"][category][field] += int(_needs[actor]["categories"][category][field])
			row["current_unmet"][category] = int(row["current_unmet"].get(category, 0)) + int(_needs[actor]["categories"][category]["unmet"])
	for site: String in _site_ids():
		if not public_totals and not allowed.has(_owner(site)): continue
		var region := _region_for(_place(site))
		if not regions.has(region): regions[region] = _empty_region(region)
		var row := regions[region] as Dictionary
		row["sites"] += 1
		row["installed_capital_assets"] = int(row.get("installed_capital_assets", 0)) + _capital.installed_assets(site).size()
		row["effective_production_capacity"] = int(row.get("effective_production_capacity", 0)) + site_capacity(site)
		row["construction_hours"] = int(row.get("construction_hours", 0)) + _capital.allocated_hours(site)
		for good: String in _goods:
			row["produced"][good] += int(_physical_totals[site]["produced"][good])
			row["site_inventory"][good] += int(_stocks[site][good])
			if _site_accepting(site) and _spec["sites"][site]["prices"].has(good): row["free_sale_stock"][good] += maxi(0, int(_stocks[site][good]) - _committed(site, good))
			row["committed"][good] += _committed(site, good)
	for fact: Dictionary in _regional_work.values():
		if not public_totals and not allowed.has(fact["worker"]) and not allowed.has(fact["employer"]): continue
		var region := str(fact["region"])
		if not regions.has(region): regions[region] = _empty_region(region)
		regions[region]["labor_hours"] += int(fact["hours"])
		for currency: String in fact["paid"]:
			var wages := regions[region]["wages_by_currency"] as Dictionary
			if not wages.has(currency): wages[currency] = {"paid": 0, "unpaid": 0, "matured_unpaid": 0}
			wages[currency]["paid"] += int(fact["paid"][currency])
	for id: String in _open_wages:
		var claim := _wages[id] as Dictionary
		if not public_totals and not allowed.has(claim["worker"]) and not allowed.has(claim["employer"]): continue
		var region := _region_for(str(_job(_work_records[id]["job"])["place"]))
		if not regions.has(region): regions[region] = _empty_region(region)
		var wages := regions[region]["wages_by_currency"] as Dictionary
		var currency := str(claim["denomination"])
		if not wages.has(currency): wages[currency] = {"paid": 0, "unpaid": 0, "matured_unpaid": 0}
		wages[currency]["unpaid"] += int(claim["remaining"])
		if int(claim["due_day"]) <= day: wages[currency]["matured_unpaid"] += int(claim["remaining"])
	for fact: Dictionary in _regional_trade.values():
		if not public_totals and not allowed.has(fact["buyer"]) and not allowed.has(fact["seller"]): continue
		var region := str(fact["region"])
		if not regions.has(region): regions[region] = _empty_region(region)
		regions[region]["accepted_orders"] += int(fact["accepted"])
		for currency: String in fact["revenue"]:
			var revenue := regions[region]["revenue_by_currency"] as Dictionary
			revenue[currency] = int(revenue.get(currency, 0))+int(fact["revenue"][currency])
	for id: String in _active_orders:
		var order := _orders[id] as Dictionary
		if not public_totals and not allowed.has(order["buyer"]) and not allowed.has(order["seller"]): continue
		var region := _region_for(order["to_place_id"])
		if not regions.has(region): regions[region] = _empty_region(region)
		regions[region]["in_transit"][order["good"]] += int(order["transit"])
		if order["kind"] == "PERSONAL_FREIGHT" and int(order["pending"]) > 0:
			var origin := _region_for(order["from_place_id"])
			if not regions.has(origin): regions[origin] = _empty_region(origin)
			regions[origin]["household_stock"][order["good"]] += int(order["pending"])
	for party: String in _credit._active_loans_by_party:
		if not public_totals and not allowed.has(party): continue
		for id: String in _credit._active_loans_by_party[party]:
			var loan := _credit._loans[id] as Dictionary
			if loan["borrower"] != party: continue
			var region := _region_for(_place(party))
			if not regions.has(region): regions[region] = _empty_region(region)
			var debts := regions[region]["credit_by_currency"] as Dictionary
			var currency := str(loan["denomination"])
			debts[currency] = int(debts.get(currency, 0))+Credit._remaining(loan)
	var rows: Array[Dictionary] = []
	for id: String in _sorted_ids(regions):
		if not _labor_market._rules.is_empty(): regions[id]["labor_market"]=_labor_market.region_summary(id,{} if public_totals else allowed)
		rows.append(regions[id])
	return {"resident_population_by_unit": resident_counts, "unlocated_historical_consumption": unlocated_consumption, "regional_population_basis": "ACTUAL_ACTIVITY_NOT_RESIDENCE", "management": management_view(), "activity_schedule": _decision_counts.duplicate(true) if public_totals else {}, "day": day, "minute": _world.game_clock.total_minutes(), "regions": rows, "coverage": "PUBLISHED_REGION_TOTALS" if public_totals else "OBSERVER_AND_MANAGED_ENTERPRISES", "quantities": "NATIVE_GOOD_UNITS", "money": "BY_DENOMINATION", "macro_comparison": "SEPARATE_UNITS_NO_GDP_SUM"}

func has_economic_action(id: String) -> bool:
	return _commands.has(id) or _scope_requests.has(id)

func person_has_work_booking(person: String) -> bool:
	return _work_queue.has(person)

func person_has_resident_service_booking(person: String) -> bool:
	return _service_market._resident.booked(person)

func automatic_person(person: String) -> bool:
	return manages_person(person) and _actors[person]["control"] == "automatic"

func person_arrived(person: String) -> void:
	if not manages_person(person): return
	observe_person_place(person)
	if automatic_person(person):
		_collect_ready_cargo(person)
		_auto_work([person], "arrival:"+str(_world.person_travel.view(person).get("id", "")))

func _collect_ready_cargo(person: String) -> void:
	var ids: Array[String] = []
	for order_id: String in _active_by_buyer.get(person, []): ids.append_array(_shipments_by_order.get(order_id, {}).keys())
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("shipment:")) < int(b.trim_prefix("shipment:")))
	for id: String in ids:
		var cargo := _shipments[id] as Dictionary
		if cargo["stage"] == "AWAITING_RECIPIENT" and _recipient_at_destination(_orders[cargo["order_id"]]):
			var quantity := _lots.quantity_at("CARGO|"+id, _orders[cargo["order_id"]]["good"])
			if quantity > 0: _accept(person, _auto_command(person, "collect", {"shipment_id": cargo["id"], "quantity": quantity}, cargo["id"]), true)

func observe_person_place(person: String) -> void:
	if not personal_authorized(person) or _world.person_overlay.is_travelling(person): return
	_commercial.contact_local(person)
	if _world.person_travel != null: _world.person_travel.observe_place(person)
	for route: Dictionary in config.get("routes", []):
		if route["from_place_id"] == _place(person) and route["to_place_id"] == _place(person) and not route["known_to"].has(person): route["known_to"].append(person)
	for row: Dictionary in _world.person_overlay.arrival_notices(_place(person)):
		if not valid_arrival_notice(row): continue
		var id := "message:"+person+":"+str(row["kind"])+":"+str(row["candidate"])
		if _receipts.has(id):
			if row["kind"] == "job": _observe_local_posting(person, row["candidate"])
			continue
		var exists: bool = false
		for info: Dictionary in config["information"]:
			if info["actor"] == person and info["kind"] == row["kind"] and info["candidate"] == row["candidate"]: exists = true
		if exists:
			if row["kind"] == "job": _observe_local_posting(person, row["candidate"])
			continue
		var category := "job" if row["kind"] == "job" else str(_candidate(row["candidate"])["good"])
		var known_count: int = 0
		for info: Dictionary in config["information"]:
			if info["actor"] != person: continue
			var key := "job" if info["kind"] == "job" else str(_candidate(info["candidate"])["good"])
			if key == category: known_count += 1
		if known_count >= 16: continue
		var at := _world.game_clock.current_day()
		var info := {"actor": person, "kind": row["kind"], "candidate": row["candidate"], "observed_day": at, "delivery_day": at}
		config["information"].append(info)
		_spec["information"].append(info.duplicate(true))
		_schedule_message(person, row["kind"], row["candidate"], at, at)
		if row["kind"] == "job": _observe_local_posting(person, row["candidate"])
	config = EconomySliceConfig.canonical(config)
	_invalidate_configuration_queries()
	_deliver_messages()

func _delivery_minute(receipt: Dictionary) -> int:
	return int(receipt.get("delivered_minute", int(receipt["delivered_day"])*1440))

## Travel restoration checks the accepted host action without executing it.
func travel_action_matches(id: String, person: String, trip: Dictionary) -> bool:
	var entry := _commands.get(id, {}) as Dictionary
	if entry.is_empty(): return false
	var command := entry["envelope"]["command"] as Dictionary
	return entry["envelope"]["actor"] == person and command["kind"] == "travel" and command["minute"] == trip["departed_minute"] and command["payload"] == {"destination_place_id": trip["destination"]} and entry["result"].get("accepted", false) and entry["result"].get("journey", {}).get("id") == id

func valid_arrival_notice(row: Dictionary) -> bool:
	if row["kind"] == "job": return _spec["jobs"].get(row["candidate"], {}).get("place") == row["place_id"]
	var parts := str(row["candidate"]).split("|")
	if parts.size() not in [2, 3] or not _spec["firms"].has(parts[0]): return false
	var site := str(parts[2]) if parts.size() == 3 else _primary_site(parts[0])
	return _spec["sites"].has(site) and _owner(site) == parts[0] and _place(site) == row["place_id"] and _spec["sites"][site]["prices"].has(parts[1])

func _extension_route_authority(manager: String, payload: Dictionary) -> bool:
	var known := _all_routes().duplicate()
	for route: Dictionary in config.get("transport_paths", []): known[route["id"]] = route
	for route: Dictionary in payload.get("routes", []): known[route["id"]] = route
	for route: Dictionary in payload.get("transport_paths", []): known[route["id"]] = route
	for item: Dictionary in payload.get("route_knowledge", []):
		if item["route_id"] == _spec["route"]["id"]: continue
		if not known.has(item["route_id"]): return false
		var sources: Array = known[item["route_id"]]["known_to"]
		var available: bool = sources.has(manager)
		for source: String in sources:
			if _spec["firms"].has(source) or _spec["sites"].has(source): available = available or _manager(manager, _owner(source))
		if not available: return false
	return true

func has_person_travel_responsibilities() -> bool:
	return _accepted_travel_count > 0

func _observe_local_posting(person: String, job_id: String) -> void:
	var job := _job(job_id)
	if not personal_authorized(person) or not _at_place(person, job["place"]): return
	if _labor_market.controls(job_id): _labor_market.observe_person(person);return
	var posting := _job_postings[job_id] as Dictionary
	var id := "posting:"+person+":"+job_id
	if int(posting["version"]) <= 0 or int(_receipts.get(id, {}).get("version", 0)) >= int(posting["version"]): return
	for index: int in range(_messages.size()-1,-1,-1):
		if _messages[index]["id"] == id: _messages.remove_at(index)
	var now := _world.game_clock.total_minutes()
	_messages.append({"id": id, "actor": person, "kind": "job_posting", "candidate": job_id, "observed_day": posting["published_day"], "delivery_day": now/1440, "version": posting["version"], "positions": posting["positions"], "source": "local_notice", "place_id": job["place"], "observed_minute": now})
	_deliver_messages()

func _personal_storage_bindings_valid() -> bool:
	for row: Dictionary in config.get("personal_storage", []):
		if not _spec["sites"].has(row["site_id"]) or not _world.spatial_catalog.has_place(_place(row["site_id"])): return _fail("Custody permission requires an existing host operating site")
	return true

func personal_custody_quote(person: String, commodity: String, quantity: int) -> Dictionary:
	var good := commodity.trim_prefix("native:")
	if not personal_authorized(person) or not commodity.begins_with("native:") or good not in _goods or quantity <= 0: return {}
	var place := _place(person)
	var site := _personal_storage_site(place, good)
	var present := _at_place(person, place)
	return {"place_id": place, "site_id": site, "quantity": quantity, "can_store": present and not site.is_empty() and _site_accepting(site) and not _world.personal_economy_state.native_custody_allocations(person, good, quantity, "CARRIED").is_empty(), "can_withdraw": present and not site.is_empty() and _can_carry_extra(person, good, quantity) and not _world.personal_economy_state.native_custody_allocations(person, good, quantity, "STORED|" + place).is_empty(), "freight_options": personal_freight_options(person, good)}

func personal_transaction_rows(person: String, limit: int, offset: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _declared_named(person) or not _world.person_overlay.is_alive(person) or (person != _world.player_state.player_id() and _spec["actors"][person]["control"] != "automatic") or limit <= 0: return result
	var payments := _world.ledger_state.own_transactions(person)
	for index: int in range(payments.size()-1-maxi(0,offset),maxi(-1,payments.size()-1-maxi(0,offset)-limit),-1): result.append(payments[index])
	return result


func valid_residence_request(row: Dictionary) -> bool:
	var command := _commands.get(row["action_id"], {}) as Dictionary
	return (command.get("source") == "player" or (command.get("source") == "automatic" and _npc_residence_policy(row["person_id"]).get("permission_id") == row["permission_id"])) and command.get("envelope", {}).get("actor") == row["person_id"] and command.get("envelope", {}).get("command") == {"action_id": row["action_id"], "minute": row["requested_minute"], "kind": "request_residence", "payload": {"destination_unit_id": row["destination_unit_id"], "place_id": row["place_id"]}} and command.get("result", {}).get("accepted") == true


func property_handover(id: String) -> Dictionary:
	return (_property_handovers.get(id, {}) as Dictionary).duplicate(true)

func _handover_native_source(fact: Dictionary) -> Dictionary:
	var source := personal_commodity("native:"+str(fact["good"]))
	source.merge({"source_id": fact["id"], "quantity": fact["quantity"], "effective_minute": fact["effective_minute"], "amount": 0, "basis": "OWNED_LEGACY_PROPERTY_UNIT_HANDOVER", "custody_mode": "STORED", "custody_place_id": fact["place_id"], "legacy_commodity_id": fact["legacy_commodity_id"], "legacy_quantity_milli": fact["legacy_quantity_milli"], "mapping_id": fact["mapping_id"], "legacy_allocations": fact["allocations"].duplicate(true)})
	return source

func _commit_property_handover(prepared: Dictionary, request_id: String, minute: int) -> void:
	var fact := prepared.duplicate(true)
	fact.merge({"id": "handover:"+request_id+":"+str(fact["person_id"])+":"+str(fact["legacy_commodity_id"]), "scope_request_id": request_id, "effective_minute": minute, "place_id": _place(fact["person_id"])})
	_property_handovers[fact["id"]] = fact
	var source_created := _lots.create("handover:"+str(fact["id"]), fact["good"], _good_units()[fact["good"]], fact["quantity"], fact["person_id"], "PERSON|"+str(fact["person_id"])+"|STORED|"+_place(fact["person_id"]), _place(fact["person_id"]), _world.game_clock.total_minutes(), "EXACT_OWNED_COMMODITY_HANDOVER", [], fact["id"])
	assert(source_created)
	_world.personal_economy_state.commit_owned_handover(fact, _handover_native_source(fact))

func _valid_property_handovers(commands: Dictionary) -> bool:
	for id: Variant in _property_handovers:
		var fact: Variant = _property_handovers[id]
		if not id is String or not fact is Dictionary or not FormalLedgerState.exact_fields(fact, ["id", "person_id", "legacy_commodity_id", "legacy_quantity_milli", "good", "quantity", "mapping_id", "allocations", "scope_request_id", "effective_minute", "place_id"]): return _fail("Invalid owned property handover fields")
		var request := _scope_requests.get(fact["scope_request_id"], {}) as Dictionary
		if request.get("kind") not in ["EXPAND", "REENTER"] or request.get("status") != "APPLIED" or fact["id"] != id or id != "handover:"+str(fact["scope_request_id"])+":"+str(fact["person_id"])+":"+str(fact["legacy_commodity_id"]) or not _declared_named(fact["person_id"]) or not valid_plan_admission(fact["person_id"], fact["scope_request_id"], fact["effective_minute"]) or fact["effective_minute"] != request["effective_minute"] or not commands.has(fact["scope_request_id"]) or _personal_storage_site(fact["place_id"], fact["good"]).is_empty(): return _fail("Property handover lacks its accepted admission and legal custody")
		var mapping := CommodityMapping.find(config.get("commodity_mappings", []), fact["legacy_commodity_id"])
		if not FormalLedgerState.valid_amount(fact["legacy_quantity_milli"]) or not FormalLedgerState.valid_amount(fact["quantity"]): return _fail("Invalid handover quantity")
		var converted := CommodityMapping.to_native(mapping, int(fact["legacy_quantity_milli"]))
		if not converted.get("success", false) or converted["quantity"] != fact["quantity"] or mapping["id"] != fact["mapping_id"] or mapping["native_good_id"] != fact["good"] or not mapping["operations"].has("PERSONAL_OWNED_HANDOVER") or not fact["allocations"] is Array or fact["allocations"].is_empty(): return _fail("Property handover loses exact unit crosswalk or sources")
	return true


func _personal_lifecycle(subject: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for row: Dictionary in _scope_requests.values():
		if row["status"] == "APPLIED" and row["kind"] in ["EXIT", "REENTER"] and row["payload"].get("subject_id") == subject: events.append(row)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
	return events

func subject_active_at(subject: String, minute: int) -> bool:
	if minute < int(_subject_activation.get(subject, 0)): return false
	var active: bool = true
	for row: Dictionary in _personal_lifecycle(subject):
		if int(row["effective_minute"]) > minute: break
		active = row["kind"] == "REENTER"
	return active

func subject_exit_minute(subject: String) -> int:
	var result: int = -1
	for row: Dictionary in _personal_lifecycle(subject):
		if int(row["effective_minute"]) > _world.game_clock.total_minutes(): break
		result = int(row["effective_minute"]) if row["kind"] == "EXIT" else -1
	return result

func _managed_days(subject: String, through_day: int) -> int:
	var start: int = int(_subject_activation.get(subject, 0))/1440
	var active: bool = true
	var total: int = 0
	for row: Dictionary in _personal_lifecycle(subject):
		var boundary: int = int(row["effective_minute"])/1440
		if boundary > through_day: break
		if active: total += maxi(0, boundary-start)
		active = row["kind"] == "REENTER"
		start = boundary
	if active: total += maxi(0, through_day-start)
	return total

func _last_managed_need_day(subject: String, through_day: int) -> int:
	var start: int = int(_subject_activation.get(subject, 0))/1440
	var active: bool = true
	var last: int = -1
	for row: Dictionary in _personal_lifecycle(subject):
		var boundary: int = int(row["effective_minute"])/1440
		if boundary > through_day: break
		if active and boundary > start: last = boundary
		active = row["kind"] == "REENTER"
		start = boundary
	if active and through_day > start: last = through_day
	return last

func _request_scope_reentry(actor: String, payload: Dictionary, id: String) -> Dictionary:
	if not uses_host_accounts() or not FormalLedgerState.exact_fields(payload, ["subject_id"]) or payload["subject_id"] != actor or not _declared_named(actor) or subject_exit_minute(actor) < 0: return _result(false, "NO_EXITED_PERSON_REENTRY_AUTHORITY")
	if _scope_requests.size() >= 64: return _result(false, "SCOPE_REQUEST_LIMIT")
	for row: Dictionary in _scope_requests.values():
		if row["kind"] == "REENTER" and row["actor"] == actor and row["status"] != "APPLIED": return _result(false, "REENTRY_ALREADY_PENDING")
	_scope_requests[id] = {"id": id, "actor": actor, "kind": "REENTER", "payload": payload.duplicate(true), "requested_minute": _world.game_clock.total_minutes(), "boundary_minute": (day+1)*1440, "effective_minute": -1, "status": "QUEUED", "reason": ""}
	_pending_scope_requests.append(id)
	return {"accepted": true, "reason": "REENTRY_QUEUED", "boundary_minute": (day+1)*1440}

func _reentry_reason(person: String) -> String:
	if not _declared_named(person) or subject_exit_minute(person) < 0: return "PERSON_NO_LONGER_EXITED"
	var reason := _world.personal_economy_state.native_admission_reason(person, true)
	if not reason.is_empty(): return reason
	var account := _world.ledger_state.account(_account(person))
	if account.get("owner_id") != person or _world.personal_economy_state.account_id_for_person(person) != _account(person): return "PERSONAL_ACCOUNT_AUTHORITY_CHANGED"
	var property := _world.personal_economy_state.owned_handover_plan(person, config.get("commodity_mappings", []))
	if not property.get("success", false): return property["reason"]
	for fact: Dictionary in property["facts"]:
		if _personal_storage_site(_place(person), fact["good"]).is_empty() or not _site_accepting(_personal_storage_site(_place(person), fact["good"])) or int(fact["quantity"]) > FormalLedgerState.MAX_AMOUNT-int(_stocks[person][fact["good"]]): return "PERSONAL_PROPERTY_HAS_NO_LEGAL_LOCAL_RECEIVER"
	return ""

func _commit_reentry(request: Dictionary) -> void:
	var person := str(request["actor"])
	var now := _world.game_clock.total_minutes()
	var property := _world.personal_economy_state.owned_handover_plan(person, config.get("commodity_mappings", []))
	# Preparation succeeded. No actors, accounts, shares, budgets or opening stock are created.
	request["status"] = "APPLIED"
	request["effective_minute"] = now
	request["reason"] = "REACTIVATED_SAME_PERSON_ACCOUNT_AND_HISTORY"
	for fact: Dictionary in property["facts"]: _commit_property_handover(fact, request["id"], now)
	_world.personal_economy_state.commit_native_arrangements(person, request["id"], now)
	_pending_scope_requests.erase(request["id"])
	observe_person_place(person)
	_auto_work([person], "reentry:"+str(request["id"]))

func _retry_scope_exit(actor: String, payload: Dictionary) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["request_id"]) or not payload["request_id"] is String: return _result(false, "INVALID_EXIT_RETRY")
	var row := _scope_requests.get(payload["request_id"], {}) as Dictionary
	if row.get("kind") != "EXIT" or row.get("status") != "DEFERRED" or row["actor"] != actor: return _result(false, "NO_PENDING_OWNER_EXIT")
	row["boundary_minute"] = (day+1)*1440
	row["status"] = "QUEUED"
	_pending_scope_requests.append(payload["request_id"])
	return {"accepted": true, "reason": "EXIT_RETRY_QUEUED", "boundary_minute": (day+1)*1440}

func valid_plan_admission(person: String, request_id: String, minute: int) -> bool:
	var row := _scope_requests.get(request_id, {}) as Dictionary
	if row.get("status") != "APPLIED" or row.get("effective_minute") != minute: return false
	if row.get("kind") == "REENTER": return row.get("actor") == person
	if row.get("kind") == "EXPAND":
		for actor: Dictionary in row["payload"].get("actors", []):
			if actor["id"] == person and actor["kind"] == "named": return true
	return false

## Only a debt/stock/contract-free named person has an existing legacy future
## consumption receiver. Cash and historical sources already live in the host.
func _scope_exit_reason(subject: String, restored_history: bool = false) -> String:
	var lease_reason:=_leases.keeper_reason(subject)
	if not lease_reason.is_empty(): return lease_reason
	var cargo_reason := _cargo_fulfilment.keeper_reason(subject)
	if not cargo_reason.is_empty(): return cargo_reason
	for id: String in _service_market._active:
		if _service_market.contracts[id]["client"]==subject: return "SERVICE_CONTRACT_REMAINS_UNSETTLED"
	if not _declared_named(subject): return "NO_LEGACY_ENTERPRISE_OR_COHORT_CONTRACT_AND_PROPERTY_RECEIVER"
	if _contracts.has(subject) or _work_queue.has(subject): return "EMPLOYMENT_OR_WORK_REMAINS_ACTIVE"
	for order: Dictionary in _orders.values():
		if (order["buyer"] == subject or order["seller"] == subject) and int(order["pending"])+int(order["transit"]) > 0: return "ORDERS_OR_CARGO_REMAIN_UNSETTLED"
	for wage: Dictionary in _wages.values():
		if (wage["worker"] == subject or wage["employer"] == subject) and int(wage["remaining"]) > 0: return "ACTUAL_WAGES_REMAIN_UNPAID"
	for loan: Dictionary in _credit.visible(subject, [], _world.game_clock.total_minutes()).get("loans", []):
		if int(loan["remaining"]) > 0: return "CREDIT_CONTRACT_REMAINS_ACTIVE"
	for offer: Dictionary in _credit.snapshot()["offers"].values():
		if (offer["lender"] == subject or offer["borrower"] == subject) and int(offer["expires_minute"]) >= _world.game_clock.total_minutes(): return "CREDIT_OFFER_REMAINS_ACTIVE"
	for asset: Dictionary in _assets.snapshot()["assets"].values():
		if asset["manager"] == subject: return "SECURITY_MANAGEMENT_REMAINS_ACTIVE"
	var assets := _assets.visible(subject, _world.game_clock.total_minutes())
	for holding: Dictionary in assets.get("holdings", []):
		if int(holding["quantity"]) > 0: return "SHARES_REQUIRE_OWNERSHIP_RECEIVER"
	for order: Dictionary in assets.get("own_orders", []):
		if order.get("status") == "OPEN": return "SECURITY_ORDER_REMAINS_ACTIVE"
	for firm: Dictionary in _spec["firms"].values():
		if firm_manager_at(firm["id"], _world.game_clock.total_minutes()) == subject: return "ENTERPRISE_MANAGEMENT_REMAINS_ACTIVE"
	for amount: int in _stocks.get(subject, {}).values():
		if amount > 0: return "PHYSICAL_STOCK_REQUIRES_LEGAL_RECEIVER"
	for account: Dictionary in _world.ledger_state.own_accounts(subject):
		if _world.ledger_state.reserved_balance(account["account_id"]) > 0: return "FUNDS_HAVE_UNSETTLED_RESERVATIONS"
	if not restored_history:
		if _world.person_travel != null and _world.person_travel.active(subject): return "PERSON_TRAVEL_REMAINS_ACTIVE"
		if not _world.population_state.residence_view(_world, subject)["pending"].is_empty(): return "RESIDENCE_REQUEST_REMAINS_PENDING"
	return _world.personal_economy_state.native_exit_reason(subject, restored_history)

func validate_completed_exits() -> bool:
	for request: Dictionary in _scope_requests.values():
		if request["kind"] == "EXIT" and request["status"] == "APPLIED" and subject_exit_minute(request["payload"]["subject_id"]) == int(request["effective_minute"]) and not _scope_exit_reason(request["payload"]["subject_id"], true).is_empty(): return _fail("Completed exit still lacks a legal responsibility receiver")
	return true

func responsibility_handover_view(observer: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for request: Dictionary in _scope_requests.values():
		if request["actor"] != observer or request["kind"] != "EXIT": continue
		var subject := str(request["payload"]["subject_id"])
		rows.append({"subject_id": subject, "status": request["status"], "reason": request["reason"], "effective_minute": request["effective_minute"], "cash_receiver": "FORMAL_LEDGER_RETAINS_SAME_ACCOUNT", "history_receiver": "FORMAL_PERSONAL_ECONOMY", "future_consumption_receiver": ("NATIVE_REENTERED" if subject_active_at(subject, _world.game_clock.total_minutes()) else "LEGACY_RESIDENT_MACRO") if request["status"] == "APPLIED" else "NATIVE_REMAINS_RESPONSIBLE"})
	return rows


## Detached actual responsibilities, visible through an accepted owner request.
func scope_subject_responsibilities(subject: String) -> Dictionary:
	var inventories: Dictionary = {}
	var production_sites: Array[String] = []
	if _actors.has(subject): inventories[subject] = (_stocks.get(subject, {}) as Dictionary).duplicate(true)
	for site: String in _site_ids():
		if site != subject and _owner(site) != subject: continue
		inventories[site] = (_stocks.get(site, {}) as Dictionary).duplicate(true)
		if _site_producing(site): production_sites.append(site)
	var orders: Array[Dictionary] = []
	for order: Dictionary in _orders.values():
		if int(order["pending"])+int(order["transit"]) == 0: continue
		if order["buyer"] == subject or order["seller"] == subject or order["buyer_site"] == subject or order["seller_site"] == subject: orders.append({"id": order["id"], "pending": order["pending"], "transit": order["transit"], "good": order["good"], "kind": order["kind"]})
	var wages: Dictionary = {}
	for wage: Dictionary in _wages.values():
		if int(wage["remaining"]) > 0 and (wage["worker"] == subject or wage["employer"] == _owner(subject)):
			wages[wage["denomination"]] = int(wages.get(wage["denomination"], 0))+int(wage["remaining"])
	var labor: int = 0
	for worker: String in _contracts:
		for contract: Dictionary in _contract_rows(_contracts[worker]):
			var job := _labor_market.contract_job(contract)
			if worker == subject or job["employer"] == subject or job["site_id"] == subject: labor += 1
	var loans: Array[Dictionary] = []
	for loan: Dictionary in _credit.visible(_owner(subject), [], _world.game_clock.total_minutes()).get("loans", []):
		if int(loan["remaining"]) > 0: loans.append(loan.duplicate(true))
	var assets := _assets.visible(_owner(subject), _world.game_clock.total_minutes())
	return {"cash_owner": "FORMAL_LEDGER", "accounts": _world.ledger_state.own_accounts(_owner(subject)), "inventory": inventories, "open_orders_and_cargo": orders, "unpaid_wages": wages, "labor_contracts": labor, "active_loans": loans, "shares": assets.get("holdings", []), "security_orders": assets.get("own_orders", []), "producing_sites": production_sites, "capital": _capital.view(_owner(subject)) if _spec["firms"].has(_owner(subject)) else {}, "future_receiver": "LEGACY_RESIDENT_MACRO" if _declared_named(subject) else "NO_LEGACY_ENTERPRISE_CONTRACT_RECEIVER"}

func property_handover_view(observer: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for fact: Dictionary in _property_handovers.values():
		if fact["person_id"] != observer and _scope_requests.get(fact["scope_request_id"], {}).get("actor") != observer: continue
		rows.append({"person_id": fact["person_id"], "legacy_commodity_id": fact["legacy_commodity_id"], "legacy_quantity_milli": fact["legacy_quantity_milli"], "good": fact["good"], "quantity": fact["quantity"], "mapping_id": fact["mapping_id"], "place_id": fact["place_id"], "effective_minute": fact["effective_minute"], "inventory_authority": "NATIVE_PERSONAL_PROPERTY_IN_FORMAL_CUSTODY"})
	return rows

func _scope_manager_at(actor: String, minute: int) -> bool:
	for firm: String in _firm_ids():
		if _manager_at(actor, firm, minute): return true
	return false

func _manager_at(actor: String, firm: String, minute: int) -> bool:
	return actor == firm or firm_manager_at(firm, minute) == actor

func firm_manager_at(firm: String, minute: int) -> String:
	var manager := str(_spec["firms"].get(firm, {}).get("manager", firm))
	var changes: Array[Dictionary] = []
	for row: Dictionary in _enterprise_changes.values():
		if row["kind"] == "MANAGER" and row["status"] == "APPLIED" and row["firm"] == firm and int(row["effective_minute"]) <= minute: changes.append(row)
	changes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
	for row: Dictionary in changes: manager = row["payload"]["successor"]
	return manager

func _management_permission(firm: String, outgoing: String, successor: String, historical: bool = false) -> Dictionary:
	for permit: Dictionary in config.get("firm_management_permissions", []):
		if permit["firm"] != firm or permit["from_manager"] != outgoing or permit["to_manager"] != successor: continue
		if not _spec["firms"].has(firm) or (not _declared_named(successor) and successor != firm): continue
		var organization := str(_spec["firms"][firm].get("host_organization_id", ""))
		if organization.is_empty():
			if permit["basis"] == "DEVELOPMENT_MANAGER_SUCCESSION": return permit.duplicate(true)
		elif permit["basis"] == "HOST_APPOINTED_MANAGER_SUCCESSION":
			if historical: return permit.duplicate(true) # The accepted boundary retains the appointment proof.
			if not _world.organization_state.is_organization_active(organization): continue
			for appointment: Dictionary in _world.organization_state.appointments_for_person(successor):
				if appointment["organization_id"] == organization and appointment["position_id"] == permit["position_id"] and _world.organization_state.position(organization, permit["position_id"]).get("capability_ids", []).has(permit["capability_id"]):
					var evidence := permit.duplicate(true)
					evidence["appointment_id"] = appointment["appointment_id"]
					return evidence
	return {}

func _management_change_action(actor: String, payload: Dictionary, id: String, kind: String) -> Dictionary:
	if _enterprise_changes.size() >= 256: return _result(false, "ENTERPRISE_LIFECYCLE_LIMIT")
	if kind == "accept_firm_management":
		if not FormalLedgerState.exact_fields(payload, ["request_id"]): return _result(false, "INVALID_MANAGEMENT_ACCEPTANCE")
		var row := _enterprise_changes.get(payload["request_id"], {}) as Dictionary
		if row.get("kind") != "MANAGER" or row.get("status") != "AWAITING_ACCEPTANCE" or row["payload"]["successor"] != actor: return _result(false, "NOT_DECLARED_SUCCESSOR")
		row["acceptance_id"] = id
		row["status"] = "QUEUED"
		_pending_enterprise_changes.append(payload["request_id"])
		row["boundary_minute"] = (day+1)*1440
		return {"accepted": true, "reason": "MANAGEMENT_ACCEPTED", "request_id": payload["request_id"]}
	if not FormalLedgerState.exact_fields(payload, ["firm", "successor"]) or not payload["firm"] is String or not payload["successor"] is String or not _spec["firms"].has(payload["firm"]): return _result(false, "INVALID_MANAGER_REQUEST")
	var firm := str(payload["firm"])
	if actor != firm_manager_at(firm, _world.game_clock.total_minutes()) or payload["successor"] == actor: return _result(false, "OUTGOING_MANAGER_REQUIRED")
	var permit := _management_permission(firm, actor, payload["successor"])
	if permit.is_empty(): return _result(false, "NO_LAWFUL_SUCCESSOR_PERMISSION")
	for row: Dictionary in _enterprise_changes.values():
		if row["firm"] == firm and row["kind"] == "MANAGER" and row["status"] in ["AWAITING_ACCEPTANCE", "QUEUED"]: return _result(false, "MANAGEMENT_CHANGE_PENDING")
	_enterprise_changes[id] = _new_enterprise_change(actor, "MANAGER", firm, payload, id)
	_enterprise_changes[id]["status"] = "AWAITING_ACCEPTANCE"
	_enterprise_changes[id]["permission"] = permit
	if permit["accept_automatically"] and (payload["successor"] == firm or _spec["actors"].get(payload["successor"], {}).get("control") == "automatic"):
		_accept(payload["successor"], _auto_command(payload["successor"], "accept_firm_management", {"request_id": id}, id), true)
	return {"accepted": true, "reason": "MANAGEMENT_PROPOSED", "request_id": id}

func _new_enterprise_change(actor: String, kind: String, firm: String, payload: Dictionary, id: String) -> Dictionary:
	return {"id": id, "actor": actor, "kind": kind, "firm": firm, "payload": payload.duplicate(true), "requested_minute": _world.game_clock.total_minutes(), "boundary_minute": (day+1)*1440, "effective_minute": -1, "status": "QUEUED", "reason": "", "acceptance_id": "", "permission": {}}

func _request_operating_change(actor: String, payload: Dictionary, id: String, kind: String) -> Dictionary:
	var fields: Array[String] = []
	fields.assign(["firm", "operating"] if kind == "set_firm_operating" else ["firm", "site_id", "enabled", "production_enabled", "accepting_business"] if kind == "set_site_status" else ["firm", "site_id"] if kind == "close_site" else ["firm"])
	if not FormalLedgerState.exact_fields(payload, fields) or not payload["firm"] is String or not _spec["firms"].has(payload["firm"]) or not _manager(actor, payload["firm"]): return _result(false, "NO_FIRM_OPERATING_AUTHORITY")
	var firm := str(payload["firm"])
	if firm_finished(firm): return _result(false, "ENTERPRISE_ALREADY_FINISHED")
	if payload.has("site_id") and (not payload["site_id"] is String or not _spec["sites"].has(payload["site_id"]) or _owner(payload["site_id"]) != firm or site_closed(payload["site_id"])): return _result(false, "NO_OPEN_OWN_SITE")
	for flag: String in ["operating", "enabled", "production_enabled", "accepting_business"]:
		if payload.has(flag) and not payload[flag] is bool: return _result(false, "INVALID_OPERATING_FLAG")
	if _enterprise_changes.size() >= 256: return _result(false, "ENTERPRISE_LIFECYCLE_LIMIT")
	for pending: String in _pending_enterprise_changes:
		var change := _enterprise_changes[pending] as Dictionary
		if change["firm"] == firm and change["kind"] == kind and change["payload"].get("site_id", "") == payload.get("site_id", ""): return _result(false, "OPERATING_CHANGE_ALREADY_PENDING")
	var proof: Dictionary={}
	if _wind_down.controls(firm) and (kind in ["wind_down_firm","close_site","finish_firm"] or (kind=="set_firm_operating" and payload["operating"])):
		proof=_wind_down.permission(actor,firm,"resume" if kind=="set_firm_operating" else "decide")
		if not proof["ok"]: return _result(false,proof["reason"])
	if kind=="wind_down_firm" and _firm_winding_down(firm): return _result(false,"ALREADY_WINDING_DOWN")
	var row := _new_enterprise_change(actor, kind, firm, payload, id)
	if not proof.is_empty(): row["permission"]={"request":proof,"adoption":{}}
	_enterprise_changes[id] = row
	_pending_enterprise_changes.append(id)
	var result := payload.duplicate(true)
	result.merge({"accepted": true, "reason": "OPERATING_CHANGE_QUEUED", "boundary_minute": row["boundary_minute"]})
	return result

func site_closed(site: String) -> bool:
	for row: Dictionary in _enterprise_changes.values():
		if row["kind"] == "close_site" and row["status"] == "APPLIED" and row["payload"].get("site_id") == site: return true
	return false

func firm_finished(firm: String) -> bool:
	for row: Dictionary in _enterprise_changes.values():
		if row["kind"] == "finish_firm" and row["status"] == "APPLIED" and row["firm"] == firm: return true
	return false

func _site_close_reason(site: String, include_lease: bool = true) -> String:
	if not _supply.keeper_reason(site).is_empty():return _supply.keeper_reason(site)
	if include_lease and not _leases.keeper_reason(site).is_empty(): return _leases.keeper_reason(site)
	var service_reason:=_service_market.keeper_reason(site)
	if not service_reason.is_empty(): return service_reason
	var transport_reason:=_shared.site_keeper_reason(site)
	if not transport_reason.is_empty(): return transport_reason
	var capital_reason := _capital.keeper_reason(site)
	if not capital_reason.is_empty(): return capital_reason
	for amount: int in _stocks[site].values():
		if amount > 0: return "SITE_STOCK_REQUIRES_REAL_SALE_OR_TRANSPORT"
	for id: String in _active_orders:
		var order := _orders[id] as Dictionary
		if order["buyer_site"] == site or order["seller_site"] == site or order.get("source_custody_site") == site or order.get("destination_custody_site") == site: return "SITE_ORDER_OR_CARGO_REMAINS_ACTIVE"
	for worker: String in _contracts:
		for contract: Dictionary in _contract_rows(_contracts[worker]):
			if _job(contract["job"])["site_id"] == site: return "SITE_LABOR_CONTRACT_REMAINS_ACTIVE"
	for id: String in _open_wages:
		if _job(_work_records[id]["job"])["site_id"] == site: return "SITE_WAGE_REMAINS_UNPAID"
	for person: String in personal_accounts():
		for row: Dictionary in _world.personal_economy_state.native_custody_rows(person):
			if row.get("place_id") == _place(site) and row.get("state") == "STORED" and _personal_storage_site(_place(site), row["good"]) == site: return "PERSONAL_CUSTODY_REQUIRES_LEGAL_KEEPER"
	return ""

func _firm_finish_reason(firm: String) -> String:
	if not _supply.keeper_reason(firm).is_empty():return _supply.keeper_reason(firm)
	if not _leases.keeper_reason(firm).is_empty(): return _leases.keeper_reason(firm)
	var service_reason:=_service_market.keeper_reason(firm)
	if not service_reason.is_empty(): return service_reason
	var cargo_reason := _cargo_fulfilment.keeper_reason(firm)
	if not cargo_reason.is_empty(): return cargo_reason
	for asset: Dictionary in _capital.assets.values():
		if _capital.asset_state(asset["id"])["owner"] == firm: return "CAPITAL_ASSET_RETAINS_CURRENT_ENTERPRISE_OWNER"
	if _firm_operating(firm) and not _firm_winding_down(firm): return "STOP_NEW_BUSINESS_BEFORE_FINISHING"
	for site: String in _spec["firms"][firm]["sites"]:
		if not site_closed(site): return "OPERATING_SITE_STILL_HAS_KEEPER_RESPONSIBILITY"
	for account: Dictionary in _world.ledger_state.own_accounts(firm):
		if _world.ledger_state.reserved_balance(account["account_id"]) > 0: return "FUNDS_REMAIN_RESERVED"
	for loan: Dictionary in _credit.visible(firm, [], _world.game_clock.total_minutes()).get("loans", []):
		if int(loan["remaining"]) > 0: return "CREDIT_CONTRACT_REMAINS_ACTIVE"
	for offer: Dictionary in _credit.snapshot()["offers"].values():
		if (offer["lender"] == firm or offer["borrower"] == firm) and int(offer["expires_minute"]) >= _world.game_clock.total_minutes(): return "CREDIT_OFFER_REMAINS_ACTIVE"
	for quote: Dictionary in _exchange.snapshot()["offers"].values():
		if quote["dealer"] == firm and int(quote["expires_minute"]) >= _world.game_clock.total_minutes() and int(quote["source_limit"])-int(_exchange._used.get(quote["id"], 0)) >= int(quote["min_source"]): return "FX_DEALER_QUOTE_REQUIRES_KEEPER"
	for asset: Dictionary in _assets.snapshot()["assets"].values():
		if asset["issuer"] == firm or asset["manager"] == firm: return "ISSUED_SHARES_OR_SECURITY_MANAGEMENT_REQUIRES_KEEPER"
	var assets := _assets.visible(firm, _world.game_clock.total_minutes())
	if not assets.get("holdings", []).is_empty(): return "SHARES_REQUIRE_OWNERSHIP_KEEPER"
	for order: Dictionary in assets.get("own_orders", []):
		if order["status"] == "OPEN": return "SECURITY_ORDER_REMAINS_ACTIVE"
	return ""

func _apply_business_boundary() -> void:
	var now := _world.game_clock.total_minutes()
	for id: String in _pending_employment_ends.duplicate():
		var row := _employment_ends[id] as Dictionary
		if row["status"] == "QUEUED" and int(row["boundary_minute"]) <= now:
			if _contracts.get(row["worker"]) == row["contract"] and not _work_queue.has(row["worker"]):
				if row.has("job_id"):
					var c:=_contract_for(row["worker"],row["job_id"])
					if row["workers"]<c["workers"]: c["workers"]=int(c["workers"])-int(row["workers"])
					elif _contracts[row["worker"]].has("allocations"):
						_contracts[row["worker"]]["allocations"].erase(row["job_id"])
						if _contracts[row["worker"]]["allocations"].is_empty(): _contracts.erase(row["worker"])
					else: _contracts.erase(row["worker"])
				else: _contracts.erase(row["worker"])
				_cohort_search_day.erase(row["worker"])
				row["status"] = "APPLIED"
				row["effective_minute"] = now
				_labor_market.record_end(row)
				_pending_employment_ends.erase(id)
	for id: String in _pending_enterprise_changes.duplicate():
		var row := _enterprise_changes[id] as Dictionary
		if row["status"] != "QUEUED" or int(row["boundary_minute"]) > now: continue
		_pending_enterprise_changes.erase(id)
		var reason: String = ""
		if not _manager(row["actor"], row["firm"]) or (row["kind"] == "MANAGER" and firm_manager_at(row["firm"], now) != row["actor"]): reason = "MANAGER_AUTHORITY_CHANGED_BEFORE_BOUNDARY"
		elif row["kind"] == "MANAGER":
			var permit := _management_permission(row["firm"], row["actor"], row["payload"]["successor"])
			if permit.is_empty() or (_declared_named(row["payload"]["successor"]) and not manages_person(row["payload"]["successor"])): reason = "SUCCESSOR_AUTHORITY_NO_LONGER_VALID"
			else: row["permission"] = permit
		elif row["kind"] == "wind_down_firm":
			var organization := str(_spec["firms"][row["firm"]].get("host_organization_id", ""))
			if not organization.is_empty() and not _world.organization_state.is_organization_active(organization): reason = "HOST_ORGANIZATION_INACTIVE"
		elif row["kind"] == "close_site": reason = _site_close_reason(row["payload"]["site_id"])
		elif row["kind"] == "finish_firm": reason = _firm_finish_reason(row["firm"])
		if reason.is_empty() and row["permission"].has("request"):
			var proof:=_wind_down.permission(row["actor"],row["firm"],row["permission"]["request"]["operation"])
			if not proof["ok"]: reason=proof["reason"]
			else: row["permission"]["adoption"]=proof
		if not reason.is_empty():
			row["status"] = "DEFERRED"
			row["reason"] = reason
			continue # Explicit retry/new request, never an automatic daily exit loop.
		if row["kind"] in ["set_firm_operating", "set_site_status"]:
			var result := _firm_business_action(row["actor"], row["kind"], row["payload"])
			if not result["accepted"]:
				row["status"] = "DEFERRED"
				row["reason"] = result["reason"]
				continue
		elif row["kind"] == "close_site":
			for flag: String in ["enabled", "production_enabled", "accepting_business"]: _site_state[row["payload"]["site_id"]][flag] = false
		elif row["kind"] == "finish_firm": _firm_state[row["firm"]]["operating"] = false
		elif row["kind"] == "wind_down_firm" and not _wind_down.controls(row["firm"]): _firm_state[row["firm"]]["operating"] = true
		row["status"] = "APPLIED"
		row["effective_minute"] = now
	_update_job_postings()

func _request_employment_end(actor: String, payload: Dictionary, id: String) -> Dictionary:
	if _employment_ends.size() >= 256: return _result(false, "EMPLOYMENT_HISTORY_LIMIT")
	if not EconomySliceConfig._fields(payload,[],["job_id","workers"]) or not _contracts.has(actor) or _employment_end_pending(actor): return _result(false, "NO_ACTIVE_OWN_EMPLOYMENT")
	if not payload.is_empty():
		var selected:=_contract_for(actor,str(payload.get("job_id","")))
		if selected.is_empty() or not _labor_market.controls(selected["job"]) or not FormalLedgerState.valid_amount(payload.get("workers")) or payload["workers"]<1 or payload["workers"]>selected["workers"]: return _result(false,"INVALID_OWN_LABOR_SHARE_RELEASE")
	_employment_ends[id] = {"worker": actor, "contract": _contracts[actor].duplicate(true), "boundary_minute": (day+1)*1440, "effective_minute": -1, "status": "QUEUED"}
	if not payload.is_empty(): _employment_ends[id].merge(payload)
	_pending_employment_ends.append(id)
	return {"accepted": true, "reason": "EMPLOYMENT_END_QUEUED", "boundary_minute": (day+1)*1440}

func _workable_workers(actor: String,contract: Dictionary) -> int:
	for id: String in _pending_employment_ends:
		var row:=_employment_ends[id] as Dictionary
		if row["worker"]!=actor: continue
		if not row.has("job_id"): return 0
		if row["job_id"]==contract["job"]: return maxi(0,int(contract["workers"])-int(row["workers"]))
	return int(contract["workers"])

func _employment_end_pending(worker: String) -> bool:
	for id: String in _pending_employment_ends:
		if _employment_ends[id]["worker"] == worker: return true
	return false

func _employment_for_work(value: Dictionary, work: Dictionary) -> Dictionary:
	var command := value["commands"].get(work.get("action_id"), {}).get("envelope", {}).get("command", {}) as Dictionary
	if work.has("employment_action_id"): return _labor_market.work_contract(work,command,value["commands"])
	if _labor_market.controls(str(work.get("job",""))) and _labor_market.pinned_source_exists(str(work.get("actor","")),work["job"],value["commands"],int(command.get("minute",-1))): return {}
	for row: Dictionary in _employment_ends.values():
		var contract := Cohorts.contract(row["contract"], str(work.get("job", "")))
		if row.has("job_id") and row["job_id"]!=work.get("job"): continue
		if row["worker"] == work.get("actor") and not contract.is_empty() and row["status"] == "APPLIED" and int(command.get("minute", -1)) < int(row["effective_minute"]) and int(work["day"])*1440 <= int(row["effective_minute"]): return contract
	return Cohorts.contract(value["contracts"].get(work.get("actor"), {}), str(work.get("job", "")))


func _operating_history(commands: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var sequence: int = 0
	for entry: Dictionary in commands.values():
		var id := str(entry["envelope"]["command"]["action_id"])
		var row := _enterprise_changes.get(id, {}) as Dictionary
		if not row.is_empty() and row["status"] != "APPLIED": continue
		var detached := entry.duplicate(true)
		detached["operating_minute"] = row.get("effective_minute", entry["envelope"]["command"]["minute"])
		detached["operating_sequence"] = sequence
		sequence += 1
		entries.append(detached)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["operating_minute"]) < int(b["operating_minute"]) if a["operating_minute"] != b["operating_minute"] else int(a["operating_sequence"]) < int(b["operating_sequence"]))
	return entries

func enterprise_lifecycle_view(actor: String, firm: String) -> Dictionary:
	if not _manager(actor, firm): return {}
	var changes: Array[Dictionary] = []
	for row: Dictionary in _enterprise_changes.values():
		if row["firm"] == firm: changes.append(row.duplicate(true))
	var sites: Array[Dictionary] = []
	for site: String in _spec["firms"][firm]["sites"]: sites.append({"id": site, "place_id": _place(site), "status": "CLOSED" if site_closed(site) else "OPERATING" if _site_operating(site) else "PAUSED", "close_reason": _site_close_reason(site), "production_running": _site_producing(site), "accepting_new_sales": _site_accepting(site), "flags": _site_state[site].duplicate(true), "effective_capacity": site_capacity(site), "base_capacity": _spec["sites"][site]["capacity"]})
	var successors: Array[String] = []
	for permit: Dictionary in config.get("firm_management_permissions", []):
		if permit["firm"] == firm and permit["from_manager"] == firm_manager_at(firm, _world.game_clock.total_minutes()) and not _management_permission(firm, permit["from_manager"], permit["to_manager"]).is_empty(): successors.append(permit["to_manager"])
	return {"manager": firm_manager_at(firm, _world.game_clock.total_minutes()), "status": "FINISHED_NATIVE_IDENTITY_RETAINED" if firm_finished(firm) else "PAUSED" if not _firm_operating(firm) else "WINDING_DOWN" if _firm_winding_down(firm) else "OPERATING", "changes": changes, "sites": sites, "successors": successors, "finish_reason": _firm_finish_reason(firm), "wind_down":_wind_down.view(actor,firm), "responsibilities": scope_subject_responsibilities(firm), "capital": _capital.view(firm)}

func incoming_management_view(person: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in _enterprise_changes.values():
		if row["kind"] == "MANAGER" and row["payload"]["successor"] == person and row["status"] == "AWAITING_ACCEPTANCE": rows.append(row.duplicate(true))
	return rows

func _restore_business_lifecycles(value: Dictionary) -> bool:
	for field: String in ["enterprise_changes", "employment_ends"]:
		if value.has(field) and not value[field] is Dictionary: return _fail("Invalid business lifecycle journal")
	_enterprise_changes = value.get("enterprise_changes", {}).duplicate(true)
	_employment_ends = value.get("employment_ends", {}).duplicate(true)
	var now := _world.game_clock.total_minutes()
	_pending_enterprise_changes.clear()
	_pending_employment_ends.clear()
	var transitions: Dictionary = {}
	for id: Variant in _enterprise_changes:
		var row: Variant = _enterprise_changes[id]
		if not id is String or not row is Dictionary or not FormalLedgerState.exact_fields(row, ["id", "actor", "kind", "firm", "payload", "requested_minute", "boundary_minute", "effective_minute", "status", "reason", "acceptance_id", "permission"]) or row["id"] != id or not row["payload"] is Dictionary or not row["permission"] is Dictionary or not row["reason"] is String or not row["acceptance_id"] is String or not _spec["firms"].has(row["firm"]) or row["status"] not in ["AWAITING_ACCEPTANCE", "QUEUED", "DEFERRED", "APPLIED"]: return _fail("Invalid enterprise lifecycle authority")
		for key: String in ["actor", "kind", "firm"]:
			if not row[key] is String: return _fail("Invalid enterprise identity reference")
		if row["payload"].get("firm") != row["firm"]: return _fail("Enterprise target differs from original action")
		if row["status"] == "QUEUED": _pending_enterprise_changes.append(id)
		var entry := value.get("commands", {}).get(id, {}) as Dictionary
		var command := entry.get("envelope", {}).get("command", {}) as Dictionary
		if entry.get("result", {}).get("accepted") != true or command.get("payload") != row["payload"] or command.get("minute") != row["requested_minute"] or entry.get("envelope", {}).get("actor") != row["actor"] or not FormalLedgerState.valid_amount(row["requested_minute"]) or int(row["requested_minute"]) > now or not FormalLedgerState.valid_amount(row["boundary_minute"]) or int(row["boundary_minute"])%1440 != 0 or int(row["boundary_minute"]) <= int(row["requested_minute"]) or typeof(row["effective_minute"]) != TYPE_INT: return _fail("Enterprise lifecycle lacks accepted timed action")
		if row["status"] == "APPLIED":
			if row["effective_minute"] != row["boundary_minute"] or int(row["effective_minute"]) > now: return _fail("Invalid enterprise application boundary")
		elif row["effective_minute"] != -1 or (row["status"] == "QUEUED" and int(row["boundary_minute"]) <= now): return _fail("Invalid pending enterprise responsibility")
		if row["kind"] == "MANAGER":
			if command.get("kind") != "request_firm_management" or not FormalLedgerState.exact_fields(row["payload"], ["firm", "successor"]) or row["payload"]["firm"] != row["firm"] or _management_permission(row["firm"], row["actor"], row["payload"]["successor"], true).is_empty(): return _fail("Management change has no declared rights source")
			if row["status"] != "AWAITING_ACCEPTANCE":
				var accepted := value["commands"].get(row["acceptance_id"], {}) as Dictionary
				if accepted.get("result", {}).get("accepted") != true or accepted.get("envelope", {}).get("actor") != row["payload"]["successor"] or accepted.get("envelope", {}).get("command", {}).get("kind") != "accept_firm_management" or accepted["envelope"]["command"]["payload"] != {"request_id": id} or accepted["envelope"]["command"]["minute"] < row["requested_minute"] or accepted["envelope"]["command"]["minute"] >= row["boundary_minute"]: return _fail("Management transfer lacks successor consent")
				if row["permission"].get("basis") == "HOST_APPOINTED_MANAGER_SUCCESSION" and row["status"] == "APPLIED" and row["permission"].get("appointment_id", "").is_empty(): return _fail("Host succession loses its actual appointment evidence")
			if row["status"] == "APPLIED":
				if not transitions.has(row["firm"]): transitions[row["firm"]] = []
				transitions[row["firm"]].append(row)
		elif row["kind"] not in ["set_firm_operating", "set_site_status", "close_site", "finish_firm", "wind_down_firm"] or command.get("kind") != row["kind"]: return _fail("Unsupported enterprise lifecycle action")
	for firm: String in transitions:
		transitions[firm].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
		var manager := str(_spec["firms"][firm].get("manager", firm))
		var previous: int = -1
		for row: Dictionary in transitions[firm]:
			if row["actor"] != manager or int(row["requested_minute"]) < previous or int(row["effective_minute"]) <= previous: return _fail("Conflicting enterprise managerial succession")
			manager = row["payload"]["successor"]
			previous = row["effective_minute"]
	for row: Dictionary in _enterprise_changes.values():
		if not _wind_down.controls(row["firm"]) or row["kind"] not in ["wind_down_firm","close_site","finish_firm","set_firm_operating"] or (row["kind"]=="set_firm_operating" and not row["payload"].get("operating",false)): continue
		var op: String="resume" if row["kind"]=="set_firm_operating" else "decide"
		if not FormalLedgerState.exact_fields(row["permission"],["request","adoption"]) or not _wind_down.proof_valid(row["permission"]["request"],row["actor"],row["firm"],op,0,row["requested_minute"]): return _fail("Voluntary closure lacks its separate original authority")
		if row["status"]=="APPLIED" and not _wind_down.proof_valid(row["permission"]["adoption"],row["actor"],row["firm"],op,0,row["effective_minute"]): return _fail("Voluntary closure lacks effective boundary authority")
	for id: Variant in _employment_ends:
		var row: Variant = _employment_ends[id]
		var entry := value.get("commands", {}).get(id, {}) as Dictionary
		if not row is Dictionary or not EconomySliceConfig._fields(row, ["worker", "contract", "boundary_minute", "effective_minute", "status"],["job_id","workers"]) or not row["contract"] is Dictionary or not _spec["actors"].has(row["worker"]) or not _valid_employment_container(row["contract"], row["worker"], value.get("actors", {}).get(row["worker"], {}).get("known_jobs", []), value.get("commands", {}),int(entry.get("envelope",{}).get("command",{}).get("minute",0))) or entry.get("envelope", {}).get("actor") != row["worker"] or entry.get("envelope", {}).get("command", {}).get("kind") != "leave_job" or entry["envelope"]["command"]["payload"] != ({"job_id":row["job_id"],"workers":row.get("workers")} if row.has("job_id") else {}) or entry.get("result", {}).get("accepted") != true or row["status"] not in ["QUEUED", "APPLIED"] or not FormalLedgerState.valid_amount(row["boundary_minute"]) or row["boundary_minute"] != (int(entry["envelope"]["command"]["minute"])/1440+1)*1440: return _fail("Invalid ended employment authority")
		if row.has("job_id"):
			var selected:=Cohorts.contract(row["contract"],row["job_id"])
			if selected.is_empty() or not _labor_market.controls(row["job_id"]) or not FormalLedgerState.valid_amount(row.get("workers")) or row["workers"]<1 or row["workers"]>selected["workers"]: return _fail("Ended worker shares exceed original employment")
		for contract: Dictionary in _contract_rows(row["contract"]):
			var formed: bool = false
			for action: Dictionary in value["commands"].values():
				var command := action["envelope"]["command"] as Dictionary
				if action["envelope"]["actor"] == row["worker"] and command["kind"] == "apply" and action["result"]["accepted"] and command["payload"].get("job_id") == contract["job"] and int(command["minute"]) <= int(entry["envelope"]["command"]["minute"]): formed = true
			if not formed: return _fail("Ended employment has no actual accepted job")
		if row["status"] == "APPLIED":
			if row["effective_minute"] != row["boundary_minute"] or int(row["effective_minute"]) > now: return _fail("Employment ended outside its legal boundary")
		elif row["effective_minute"] != -1 or int(row["boundary_minute"]) <= now: return _fail("Unprocessed employment ending")
		if row["status"] == "QUEUED": _pending_employment_ends.append(id)
	return true


func _npc_residence_policy(person: String) -> Dictionary:
	for row: Dictionary in config.get("npc_residence", []):
		if row["person_id"] == person: return row
	return {}

func npc_residence_authorized(person: String, payload: Dictionary) -> bool:
	var policy := _npc_residence_policy(person)
	if policy.is_empty() or person == _world.player_state.player_id() or not manages_person(person) or _actors[person]["control"] != "automatic" or not _contracts.has(person) or not FormalLedgerState.exact_fields(payload, ["destination_unit_id", "place_id"]): return false
	var place := _place(person)
	var job := _job(_contracts[person]["job"])
	if payload["place_id"] != place or place != job["place"] or not _at_place(person, place) or (_world.person_travel != null and _world.person_travel.active(person)): return false
	var residence := _world.population_state.residence_view(_world, person)
	if not residence["can_request"] or payload["destination_unit_id"] != residence["target_unit_id"]: return false
	var permission: Dictionary = {}
	for row: Dictionary in config.get("residence_permissions", []):
		if row["id"] == policy["permission_id"]: permission = row
	if permission.get("person_id") != person or permission.get("source_unit_id") != _population_unit(person) or permission.get("destination_unit_id") != payload["destination_unit_id"] or not permission.get("place_ids", []).has(place): return false
	var moves: int = 0
	var last: int = -1
	for row: Dictionary in residence["history"]:
		if row["status"] == "APPLIED":
			moves += 1
			last = maxi(last, int(row["effective_minute"]))
	if moves >= int(policy["max_moves"]) or (last >= 0 and _world.game_clock.total_minutes()-last < int(policy["cooldown_days"])*1440): return false
	var observed := _employment_observations.get(person + "|" + str(job["id"]), {}) as Dictionary
	var accepted := int(observed.get("accepted_minute", -1))
	if accepted < 0 or _world.game_clock.total_minutes()-accepted < int(policy["min_employment_days"])*1440: return false
	return int(observed.get("worked_hours", 0)) >= int(policy["min_work_hours"])

func propose_npc_residences() -> void:
	for policy: Dictionary in config.get("npc_residence", []):
		var person := str(policy["person_id"])
		var payload := {"destination_unit_id": _world.population_state.unit_for_place(_place(person)), "place_id": _place(person)}
		if npc_residence_authorized(person, payload): _accept(person, _auto_command(person, "request_residence", payload, policy["permission_id"]), true)


func validate_business_continuity() -> bool:
	for site: String in _site_ids():
		if site_closed(site) and not _site_close_reason(site).is_empty(): return _fail("Closed site still has physical or contractual custody")
	for firm: String in _firm_ids():
		if firm_finished(firm) and not _firm_finish_reason(firm).is_empty(): return _fail("Finished enterprise still lacks a lawful obligation keeper")
	return true


func _legacy_wage_still_active(person: String) -> bool:
	return _declared_named(person) and not _world.personal_economy_state.employment(person).is_empty() and _world.personal_economy_state.legacy_wage_end(person) < 0


func person_management_view(person: String) -> Dictionary:
	if not _declared_named(person): return {"active": false, "future_authority": "LEGACY_RESIDENT_MACRO_AND_FORMAL_PERSONAL"}
	var first: int = int(_subject_activation.get(person, 0))
	var entry := first
	var exit: int = -1
	var intervals: Array[Dictionary] = []
	var start := first
	for row: Dictionary in _personal_lifecycle(person):
		if row["kind"] == "EXIT":
			exit = int(row["effective_minute"])
			intervals.append({"start_minute": start, "end_minute": exit, "request_id": row["id"]})
		else:
			entry = int(row["effective_minute"])
			start = entry
	var active := manages_person(person)
	if active: intervals.append({"start_minute": start, "end_minute": -1, "request_id": ""})
	return {"active": active, "first_admission_minute": first, "last_entry_minute": entry, "last_exit_minute": exit, "active_intervals": intervals, "future_authority": "NATIVE_PERSONAL_NEEDS" if active else "LEGACY_RESIDENT_MACRO_AND_FORMAL_PERSONAL", "settled_native_days": _managed_days(person, day)}


func _command_within_management_interval(entry: Dictionary) -> bool:
	var command := entry["envelope"]["command"] as Dictionary
	var person := str(entry["envelope"]["actor"])
	var minute := int(command["minute"])
	if command["kind"] in ["request_residence", "reenter_scope", "retry_scope_exit"] or subject_active_at(person, minute): return true
	# Automatic settlement completes before the same midnight's scope change.
	# Its financial authority is independently retained by credit/FX/assets and Ledger.
	return minute > 0 and minute%1440 == 0 and entry.get("source") == "automatic" and entry["result"]["accepted"] and command["kind"] in ["repay_loan", "exchange_currency", "cancel_share_order"] and subject_active_at(person, minute-1)


func _firm_winding_down(firm: String) -> bool:
	var winding: bool = false
	var latest: int = -1
	for row: Dictionary in _enterprise_changes.values():
		if row["firm"] != firm or row["status"] != "APPLIED" or row["kind"] not in ["wind_down_firm", "set_firm_operating"]: continue
		if row["kind"] == "set_firm_operating" and not row["payload"]["operating"]: continue
		if int(row["effective_minute"]) >= latest:
			latest = int(row["effective_minute"])
			winding = row["kind"] == "wind_down_firm"
	return winding


func _can_observe_scope_subject(observer: String, subject: String) -> bool:
	if _declared_named(subject): return observer == subject
	if _spec["firms"].has(subject) or _spec["sites"].has(subject): return _manager(observer, _owner(subject))
	return _spec["actors"].has(subject) and _scope_manager(observer)

func _firm_management_basis(firm: String) -> String:
	var basis := "EXPLICIT_DEVELOPMENT_CONFIGURATION"
	var latest: int = -1
	for row: Dictionary in _enterprise_changes.values():
		if row["kind"] == "MANAGER" and row["status"] == "APPLIED" and row["firm"] == firm and int(row["effective_minute"]) > latest:
			latest = int(row["effective_minute"])
			basis = row["permission"]["basis"]
	return basis


func _production_minute() -> int:
	# Production settles the preceding interval. Equipment commissioned at this
	# midnight belongs to the next interval, including after save restoration.
	return maxi(0, day*1440-1)

func capital_free_goods(site: String, good: String) -> int:
	return maxi(0, int(_stocks.get(site, {}).get(good, 0))-_committed(site, good)) if _stocks.has(site) else 0

func capital_take_goods(site: String, materials: Dictionary, project_id: String = "") -> bool:
	if not project_id.is_empty() and not _capital.projects.has(project_id): return false
	for good: String in materials:
		if capital_free_goods(site, good) < int(materials[good]) or int(_physical_totals[site]["used"][good]) > FormalLedgerState.MAX_AMOUNT-int(materials[good]): return false
	var inputs: Array[Dictionary] = []
	for good: String in materials:
		if int(materials[good]) > 0:
			var rows := _lots.selection("SITE|"+site, good, int(materials[good]))
			if rows.is_empty(): return false
			inputs.append_array(rows)
	if not inputs.is_empty() and not _lots.ready(inputs): return false
	if _costs.enabled and not project_id.is_empty(): _costs.capital_inputs(project_id, inputs)
	if not inputs.is_empty() and not _lots.consume(inputs, _world.game_clock.total_minutes()): return false
	if not project_id.is_empty(): _capital.projects[project_id]["material_sources"] = inputs.duplicate(true)
	for good: String in materials:
		_physical_totals[site]["used"][good] = int(_physical_totals[site]["used"][good])+int(materials[good])
	return true

func _procure_capital() -> void:
	for id: String in _capital._active.duplicate():
		var project := _capital.projects[id] as Dictionary
		if _wind_down.controls(project["firm"]) and _firm_winding_down(project["firm"]): continue
		if project["status"] == "PAUSED" or not project["materials"].is_empty(): continue
		var site := str(project["site_id"])
		var firm := str(project["firm"])
		if not _site_accepting(site): continue
		var terms := _capital.terms_for(project)
		for good: String in terms["materials"]:
			var wanted := maxi(0, _capital.goods_needed(site, good)-maxi(0, _exposure(site, good)-_committed(site, good)))
			_coordinate_transfer(site, good, {"quantity": wanted, "need_by_day": day+1}, id)
			wanted = maxi(0, _capital.goods_needed(site, good)-maxi(0, _exposure(site, good)-_committed(site, good)))
			if wanted <= 0: continue
			for offer: Dictionary in _input_offers(site, good, day+1, wanted):
				if offer["denomination"] != terms["denomination"]: continue
				var unit_cost := int(offer["price"])+int(offer["freight_per_unit"])
				if unit_cost <= 0: continue
				var remainder := maxi(0, int(project["budget"])-_capital.committed_cost(project)-_capital.remaining_labor_budget(project))
				_fund_procurement(firm, offer, mini(wanted, remainder/unit_cost))
				var funds := maxi(0, _world.ledger_state.available_balance(_account(firm, terms["denomination"]))-_capital_cash_protected(firm, terms))
				var quantity := mini(wanted, mini(remainder, funds)/unit_cost)
				if quantity <= 0: break
				var payload := {"quote_id": offer["quote_id"], "seller": offer["seller"], "seller_site": offer["seller_site"], "buyer_site": site, "good": good, "quantity": quantity, "denomination": offer["denomination"], "max_price": _purchase_limit(firm, good, offer["denomination"], int(offer["price"])), "path_id": offer["route_id"], "need_by_day": day+1}
				var result := _accept(firm, _auto_command(firm, "buy", payload, id+"|"+str(offer["seller_site"])+"|"+good+"|"+str(offer["route_id"])), true)
				if result.get("accepted", false) and result.has("order_id"):
					if not project["orders"].has(result["order_id"]):
						project["orders"].append(result["order_id"])
					wanted = maxi(0, _capital.goods_needed(site, good)-maxi(0, _exposure(site, good)-_committed(site, good)))
				if wanted == 0: break
			if wanted > 0:
				_discover_suppliers(site, good, {"quantity": wanted, "need_by_day": day+1})

func _npc_invest() -> void:
	for policy: Dictionary in config.get("capital_investment", {}).get("npc_policies", []):
		var terms := _capital.template(policy["template_id"])
		var firm := str(terms["firm"])
		var site := str(terms["site_id"])
		if not _spec["sites"].has(site) or (firm_manager_at(firm, _world.game_clock.total_minutes()) != firm and not _assets.corporate.can_plan(firm)) or not _site_producing(site) or _firm_winding_down(firm): continue
		if _capital.active_count(firm) >= int(terms["max_projects"]): continue
		var liquidity := Liquidity.policy(config,firm)
		if not liquidity.is_empty():
			var available := _world.ledger_state.available_balance(_account(firm,terms["denomination"]))
			if _mature_wage_position(firm,terms["denomination"])["amount"]>0 or (available-_due_credit_amount(firm,terms["denomination"])<int(terms["cash_floor"]) and not _assets.corporate.can_plan(firm)): continue
		var latest := int(_capital._firm_last_project.get(firm, -int(policy["cooldown_days"])*1440))
		if day*1440-latest < int(policy["cooldown_days"])*1440: continue
		var observed_days: Dictionary = {}
		var pressure := 0
		for good: String in _spec["sites"][site]["prices"]:
			for row: Dictionary in _request_window.get(site+"|"+good, []):
				if int(row["day"]) <= day-int(policy["window_days"]): continue
				var accepted_order := _orders.get(str(row.get("order_id", "")), {}) as Dictionary
				var amount := int(accepted_order.get("pending", 0))+int(accepted_order.get("transit", 0))
				# Unfunded requests remain visible as enquiries, not committed revenue.
				if not accepted_order.is_empty(): amount += _delivered_order_quantity(accepted_order["id"], maxi(0, day-int(policy["window_days"])+1))
				if amount > 0:
					observed_days[row["day"]] = true
					pressure += amount
		if _assets.corporate.can_plan(firm):
			# Repeated buyers replace their enquiry rows; the existing accepted-order
			# day index retains the actual multi-day business observation instead.
			observed_days.clear();pressure=0
			for good: String in _spec["sites"][site]["prices"]:
				for date: int in _order_days.get(site+"|"+good,{}):
					if date>day-int(policy["window_days"]) and int(_order_days[site+"|"+good][date])>0:
						observed_days[date]=true;pressure+=int(_order_days[site+"|"+good][date])
		if observed_days.size() < int(policy["window_days"]) or pressure < int(policy["minimum_pressure"]): continue
		var used := 0
		if not _costs.investment_allowed(site): continue
		for activity: Dictionary in _spec["sites"][site]["activities"]:
			used += int(_plans.get(site, {}).get("activities", {}).get(activity["id"], {}).get("actual", 0))*int(activity["capacity_units"])
		if used*100 < _capital.capacity(site, _production_minute())*int(policy["minimum_utilization_percent"]): continue
		var money := _world.ledger_state.available_balance(_account(firm, terms["denomination"]))-_capital_cash_protected(firm, terms)
		if (money < int(terms["budget"]) and not (_assets.corporate.can_plan(firm) and int(_assets.primary.config["max_new_shares"])*int(_assets.primary.config["price"])>=int(terms["budget"]))) or _capital.labor_needed(site) > 0: continue
		var supply_known := true
		for good: String in terms["materials"]:
			if capital_free_goods(site, good) < int(terms["materials"][good]) and _input_offers(site, good, day+30, int(terms["materials"][good]), {}, "CAPITAL_FEASIBILITY").is_empty() and not _assets.corporate.known_own_producer(site,good): supply_known = false
		if not supply_known or _labor.get(site, 0) <= 0: continue
		_accept(firm, _auto_command(firm, "invest", {"template_id": terms["id"], "budget": terms["budget"]}, terms["id"]), true)



func site_capacity(site: String) -> int:
	return _capital.capacity(site, _world.game_clock.total_minutes()) if _site_producing(site) else 0

func _capital_finance_action(actor: String, payload: Dictionary, id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["project_id", "offer_id", "amount"]) or not payload["project_id"] is String or not payload["offer_id"] is String or not FormalLedgerState.valid_amount(payload["amount"]): return _result(false, "INVALID_INVESTMENT_FINANCE")
	var project := _capital.projects.get(payload["project_id"], {}) as Dictionary
	if project.is_empty() or not _manager(actor, project["firm"]) or project["status"] in Capital.TERMINAL: return _result(false, "NOT_ACTIVE_PROJECT_MANAGER")
	if int(payload["amount"]) <= 0 or int(payload["amount"]) > maxi(0, int(project["budget"])-_capital.committed_cost(project)): return _result(false, "FINANCE_EXCEEDS_PROJECT_BUDGET")
	var visible_offers: Array = _credit.visible(project["firm"], _known_credit_lenders(project["firm"]), _world.game_clock.total_minutes())["offers"]
	var legal: bool = false
	for offer: Dictionary in visible_offers:
		if offer["id"] == payload["offer_id"] and offer["denomination"] == _capital.template(project["template_id"])["denomination"]: legal = true
	if not legal: return _result(false, "UNKNOWN_ENTERPRISE_CREDIT_OFFER")
	var result := _firm_finance_action(actor,{"firm":project["firm"],"operation":"accept_credit","terms":{"offer_id":payload["offer_id"],"amount":payload["amount"]}},id)
	result["project_id"] = project["id"]
	return result


func _request_retention_window(site: String) -> int:
	var window := maxi(int(_operations_policy(site)["demand_window"]),maxi(_retail.observation_days(site),_commercial.observation_days(site)))
	if config.get("operating_inventory",{}).has("enquiry_response"):window=maxi(window,31) # Original buy boundary is at most day+30; do not discard an unexpired enquiry.
	if config.get("operating_inventory",{}).get("enabled",false):window=maxi(window,int(config.operating_inventory.window_days))
	for row: Dictionary in config.get("capital_investment", {}).get("npc_policies", []):
		if _capital.template(row["template_id"])["site_id"] == site: window = maxi(window, int(row["window_days"]))
	var acquisition: Dictionary=_capital.autonomous_policy(_owner(site))
	if acquisition.get("site_id")==site: window=maxi(window,int(acquisition["observation_days"]))
	return window


func _capital_cash_protected(firm: String, terms: Dictionary) -> int:
	var currency := str(terms["denomination"])
	var amount := int(terms["cash_floor"])+int(_firm_finance_view(firm)["wages_unpaid"].get(currency, 0))
	for loan: Dictionary in _credit.visible(firm, _known_credit_lenders(firm), _world.game_clock.total_minutes(), true)["loans"]:
		if loan["borrower"] == firm and loan["denomination"] == currency and int(loan["due_day"]) <= day: amount = mini(FormalLedgerState.MAX_AMOUNT, amount+int(loan["remaining"]))
	return mini(FormalLedgerState.MAX_AMOUNT, amount)

func _actor_ids_from_spec() -> Array[String]:
	var result: Array[String] = []
	result.assign(_spec.get("actors", {}).keys())
	return result

func _physical_owners() -> Array[String]:
	var result := _actor_ids_from_spec()
	result.append_array(_firm_ids())
	return result

func _good_units() -> Dictionary:
	var result: Dictionary = {}
	for good: String in _goods: result[good] = "native_unit:"+good
	for row: Dictionary in config.get("goods", []): result[row["id"]] = row.get("unit_id", "native_unit:"+str(row["id"]))
	return result

func _opening_stock(subject: String, balances: Dictionary, legacy: bool = false) -> void:
	_lots.ensure_subject(subject)
	for good: String in _goods:
		var q := int(balances.get(good, 0))
		if q <= 0: continue
		var named := _declared_named(subject)
		var acquisition := "native_opening:"+subject+":"+good if named and not legacy else ""
		var location := "SITE|"+subject if _spec["sites"].has(subject) else "PERSON|"+subject+"|CARRIED" if named else "ACTOR|"+subject
		var created := _lots.create(("legacy_balance:" if legacy else "opening:")+subject+":"+good, good, _good_units()[good], q, _owner(subject), location, _place(subject), -1 if legacy else 0, "LEGACY_QUANTITY_BOUNDARY_AGE_COST_UNKNOWN" if legacy else "EXPLICIT_DEVELOPMENT_STOCK", [], acquisition)
		assert(created)

func _budget_subject(firm: String) -> String:
	var organization := str(_spec["firms"].get(firm, {}).get("host_organization_id", ""))
	for r: Dictionary in _budgets.rules:
		if r["subject"] == organization and not organization.is_empty(): return organization
	return firm

func _budget_plan(firm: String, currency: String, good: String, legs: Array, quantity: int, sale: bool = true, locked_price: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _spec["firms"].has(firm): return result
	var subject := _budget_subject(firm)
	if sale: result.append(_budgets.plan(subject, currency, "goods:"+good, int(FormalLedgerState.ratio(locked_price, quantity, 1).get("quotient", -1)), _world.game_clock.total_minutes()))
	var amounts: Dictionary = {}
	for leg: Dictionary in legs:
		var category := "freight:"+str(leg["edge_id"])
		var cost := int(FormalLedgerState.ratio(leg["freight_per_unit"], quantity, 1).get("quotient", -1))
		if cost < 0 or cost > FormalLedgerState.MAX_AMOUNT-int(amounts.get(category, 0)):
			result.append({"ok": false, "reason": "FREIGHT_BUDGET_AMOUNT_BOUNDS"})
			return result
		amounts[category] = int(amounts.get(category, 0))+cost
	for category: String in amounts: result.append(_budgets.plan(subject, currency, category, amounts[category], _world.game_clock.total_minutes()))
	return result

func _budget_ready(components: Array[Dictionary]) -> bool:
	for p: Dictionary in components:
		if not p.get("ok", false): return false
	return true

func _physical_person_rows(person: String, good: String, allocations: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for allocation: Dictionary in allocations:
		var acquisition := ""
		for lot: Dictionary in _world.personal_economy_state._native_lots.get(person, {}).get(good, []):
			if lot["purchase_record_id"] == allocation["purchase_record_id"]: acquisition = lot["source_id"]
		if acquisition.is_empty(): return []
		var location := "PERSON|"+person+"|"+str(allocation["custody_key"])
		var rows := _lots.selection(location, good, allocation["quantity"], "", acquisition)
		if rows.is_empty(): return []
		result.append_array(rows)
	if not _lots.ready(result): result.clear()
	return result

func _consumption_rows(person: String, good: String, quantity: int) -> Array[Dictionary]:
	if manages_person(person): return _physical_person_rows(person, good, _world.personal_economy_state.native_allocations(person, good, quantity))
	return _lots.selection("ACTOR|"+person, good, quantity)

## Old quantity saves are adopted at a visible boundary, never assigned an age,
## cost or invented previous route. Named partitions come from restored custody.
func finalize_physical_restore() -> bool:
	if not _legacy_stock_boundary.is_empty():
		var freight_left: Dictionary = {}
		for cargo: Dictionary in _shipments.values(): freight_left[cargo["id"]] = cargo["quantity"]
		for person: String in _actor_ids_from_spec():
			if not _declared_named(person): continue
			_lots.ensure_subject(person)
			for good: String in _world.personal_economy_state._native_lots.get(person, {}):
				for lot: Dictionary in _world.personal_economy_state._native_lots[person][good]:
					for custody: String in _world.personal_economy_state._lot_positions(lot):
						var quantity := int(_world.personal_economy_state._lot_positions(lot)[custody])
						if quantity <= 0: continue
						var location := "PERSON|"+person+"|"+custody
						var place := _place(person) if custody == "CARRIED" else custody.trim_prefix("STORED|") if custody.begins_with("STORED|") else str(_orders.get(custody.trim_prefix("FREIGHT|"), {}).get("from_place_id", ""))
						if custody.begins_with("FREIGHT|"):
							var order_id := custody.trim_prefix("FREIGHT|")
							for cargo_id: String in _shipments_by_order.get(order_id, {}):
								var cargo := _shipments[cargo_id] as Dictionary
								var amount := mini(quantity, int(freight_left[cargo_id]))
								if amount > 0:
									if not _lots.create("legacy_person:"+person+":"+good+":"+str(_lots.next_id), good, _good_units()[good], amount, person, "CARGO|"+cargo_id, cargo["place_id"], -1, "LEGACY_QUANTITY_BOUNDARY_AGE_COST_UNKNOWN", [], lot["source_id"]): return false
									quantity -= amount
									freight_left[cargo_id] = int(freight_left[cargo_id])-amount
						if quantity > 0 and not _lots.create("legacy_person:"+person+":"+good+":"+str(_lots.next_id), good, _good_units()[good], quantity, person, location, place, -1, "LEGACY_QUANTITY_BOUNDARY_AGE_COST_UNKNOWN", [], lot["source_id"]): return false
		if _stocks != _legacy_stock_boundary: return _fail("Restored physical partitions differ from old quantity balance")
		_legacy_stock_boundary.clear()
	return _validate_physical_references() and _validate_personal_physical_partitions()

func _validate_physical_references() -> bool:
	var custodians: Dictionary = {}
	for carrier: Dictionary in config.get("carriers", []): custodians[carrier["id"]] = true
	for o: Dictionary in _orders.values():
		if o["kind"] != "PERSONAL_FREIGHT" and int(o["pending"]) > 0:
			var live := _lots.reserved_quantity(o["id"])
			var lost := _lots.lost_at("SITE|"+str(o["seller_site"]), o["good"], o["id"])
			if live+lost+_cargo_fulfilment.unresolved(o["id"])-_cargo_fulfilment.site_loss(o["id"]) != int(o["pending"]): return _fail("Order lacks physical reserved portions or recorded outstanding loss")
			var rows := _lots.reserved_selection(o["id"], live)
			for r: Dictionary in rows:
				var p := _lots.portions[r["portion_id"]] as Dictionary
				if p["good"] != o["good"] or p["owner"] != o["seller"] or p["location"] != "SITE|"+str(o["seller_site"]): return _fail("Reserved portion owner/location mismatch")
	for p: Dictionary in _lots.portions.values():
		if not _actors.has(p["custodian"]) and not _spec["firms"].has(p["custodian"]) and not _spec["sites"].has(p["custodian"]) and not custodians.has(p["custodian"]): return _fail("Physical portion has an unknown custodian")
		if int(p["remaining"]) <= 0: continue
		var loc := str(p["location"])
		if not str(p["reserved_for"]).is_empty():
			if _service_market.contracts.has(p["reserved_for"]):
				var c:=_service_market.contracts[p["reserved_for"]] as Dictionary
				if c["kind"]!="STORAGE" or c["started_minute"]>=0 or c["status"]=="CANCELLED" or loc!="SITE|"+str(c["source_site"]) or p["owner"]!=c["client"] or p["good"]!=c["good"]: return _fail("Service reservation lost actual client stock")
				continue
			var order := _orders.get(p["reserved_for"], {}) as Dictionary
			if order.is_empty() or order["kind"] == "PERSONAL_FREIGHT" or int(order["pending"]) <= 0 or loc != "SITE|"+str(order["seller_site"]) or p["owner"] != order["seller"] or p["good"] != order["good"]: return _fail("Physical reservation has no corresponding unfulfilled order")
		if loc.begins_with("CARGO|"):
			var id := loc.trim_prefix("CARGO|")
			if not _shipments.has(id) or p["good"] != _orders[_shipments[id]["order_id"]]["good"] or p["place_id"] != _shipments[id]["place_id"]: return _fail("Physical cargo has an invalid shipment reference")
			var order := _orders[_shipments[id]["order_id"]] as Dictionary
			if p["owner"] != (order["buyer"] if order["kind"] == "PERSONAL_FREIGHT" else order["seller"]): return _fail("Cargo ownership differs from the original order")
		elif loc.begins_with("SERVICE|"):
			var id:=loc.trim_prefix("SERVICE|")
			var c:=_service_market.contracts.get(id,{}) as Dictionary
			if c.is_empty() or c["kind"]!="STORAGE" or c["started_minute"]<0 or p["owner"]!=c["client"] or p["good"]!=c["good"] or p["custodian"]!=c["provider_site"] or p["place_id"]!=_place(c["provider_site"]): return _fail("Commercial custody has no actual owner/provider contract")
		elif loc.begins_with("SITE|"):
			var id := loc.trim_prefix("SITE|")
			if not _spec["sites"].has(id) or p["owner"] != _owner(id) or p["place_id"] != _place(id): return _fail("Physical site custody has an invalid owner/place")
		elif loc.begins_with("PERSON|"):
			if not _declared_named(p["owner"]) or not loc.begins_with("PERSON|"+str(p["owner"])+"|"): return _fail("Invalid personal portion owner")
			var custody := loc.trim_prefix("PERSON|"+str(p["owner"])+"|")
			if custody.begins_with("STORED|") and p["place_id"] != custody.trim_prefix("STORED|"): return _fail("Personal storage place differs from physical custody")
		elif loc != "ACTOR|"+str(p["owner"]) or not _actors.has(p["owner"]): return _fail("Unknown physical custody")
	for cargo: Dictionary in _shipments.values():
		var good := str(_orders[cargo["order_id"]]["good"])
		if _lots.quantity_at("CARGO|"+str(cargo["id"]), good)+_lots.lost_at("CARGO|"+str(cargo["id"]), good)-_cargo_fulfilment.cargo_loss(cargo["id"]) != int(cargo["quantity"]): return _fail("Shipment physical quantities and unresolved losses are not conserved")
	return true

func _personal_allocations_for_portions(person: String, good: String, rows: Array[Dictionary], custody: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in rows:
		var p := _lots.portions[row["portion_id"]] as Dictionary
		var record_id := ""
		for lot: Dictionary in _world.personal_economy_state._native_lots.get(person, {}).get(good, []):
			if lot["source_id"] == p["acquisition_id"]: record_id = lot["purchase_record_id"]
		if record_id.is_empty(): return []
		result.append({"purchase_record_id": record_id, "quantity": row["quantity"], "custody_key": custody})
	return result

func _procurement_permission(actor: String, firm: String, payload: Dictionary, internal: bool, components: Array[Dictionary], target: String, place: String, category: String, amount: int) -> Dictionary:
	var roots: Dictionary = {}
	for component: Dictionary in components:
		if not component.has("rule_id"): continue
		var rule := _budgets.rule(component["rule_id"])
		if rule["basis"] != "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY": roots[rule["root_authority"]] = true
	if roots.is_empty() and not payload.has("authorization_context"): return {"ok": true, "authorization": {}}
	if not _spec["firms"].has(firm): return {"ok": false, "reason": "NOT_AN_ENTERPRISE_PROCUREMENT_CONTEXT"}
	if roots.size() > 1: return {"ok": false, "reason": "PROCUREMENT_REQUIRES_MULTIPLE_ROOT_AUTHORITIES"}
	if not FormalLedgerState.valid_amount(amount): return {"ok": false, "reason": "PROCUREMENT_AMOUNT_BOUNDS"}
	var context: Variant = payload.get("authorization_context", {})
	if not context is Dictionary: return {"ok": false, "reason": "INVALID_PROCUREMENT_AUTHORITY"}
	if internal and context.is_empty() and not roots.is_empty():
		actor = firm_manager_at(firm, _world.game_clock.total_minutes())
		var organization := str(_spec["firms"][firm].get("host_organization_id", ""))
		if not _world.person_overlay.has_person(actor) or organization.is_empty(): return {"ok": false, "reason": "NO_AUTHORIZED_PROCUREMENT_REPRESENTATIVE"}
		context = OrganizationState.acting_context(actor, organization, organization, roots.keys()[0])
	if context.get("person_id") != actor or context.get("represented_organization_id") != _spec["firms"][firm].get("host_organization_id") or _world.authorization_check == null: return {"ok": false, "reason": "INVALID_PROCUREMENT_AUTHORITY"}
	var proof := _world.authorization_check.resolve_authority(context, "economy.procure", AuthorizationCheck.STAGE_DOMAIN_EXECUTION, target, place, category, float(amount), _world.game_clock.current_hour())
	if proof.get("status") != AuthorizationCheck.ALLOWED or (not roots.is_empty() and not roots.has(proof.get("authority_id"))): return {"ok": false, "reason": "NO_PROCUREMENT_AUTHORITY"}
	proof["procurement_context"] = context.duplicate(true)
	return {"ok": true, "authorization": proof}

func _valid_procurement_actor(entry: Dictionary, buyer: String, order: Dictionary = {}) -> bool:
	var actor := str(entry["envelope"]["actor"])
	var command := entry["envelope"]["command"] as Dictionary
	var roots: Dictionary = {}
	if order.is_empty(): order = _orders.get(entry["result"].get("order_id", ""), {}) as Dictionary
	if not order.is_empty():
		for component: Dictionary in _budgets.order_components(order):
			var rule := _budgets.rule(component["rule_id"])
			if rule["basis"] != "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY": roots[rule["root_authority"]] = true
	if not roots.is_empty() and not entry["result"].has("authorization"): return false
	if actor != buyer and command["payload"].get("firm") != buyer: return false
	if entry["result"].has("authorization"):
		var proof := entry["result"]["authorization"] as Dictionary
		var context := proof.get("procurement_context", command["payload"].get("authorization_context", {})) as Dictionary
		if proof.get("status") != AuthorizationCheck.ALLOWED or not _world.organization_state._authority_grants.has(proof.get("authority_id")) or (not roots.is_empty() and not roots.has(proof.get("authority_id"))): return false
		if context.get("represented_organization_id") != _spec["firms"].get(buyer, {}).get("host_organization_id"): return false
		if context.get("person_id") != (firm_manager_at(buyer, command["minute"]) if actor == buyer else actor): return false
		for id: String in proof.get("basis_chain", []):
			if id != proof["authority_id"] and not _world.organization_state._delegations.has(id): return false
		return true
	return actor == buyer or _manager_at(actor, buyer, command["minute"])

func _budget_view(firm: String) -> Dictionary:
	var result := {"policy": "EXPLICIT_WINDOWS_ONLY", "windows": []}
	for r: Dictionary in _budgets.rules:
		if r["subject"] != _budget_subject(firm): continue
		var row := r.duplicate(true)
		row["committed_and_spent"] = _budgets._used.get(r["id"], 0)
		result["windows"].append(row)
	return result

func _delivered_order_quantity(id: String, first_day: int) -> int:
	var total := 0
	for receipt_id: String in _deliveries_by_order.get(id, []):
		var receipt := _delivery_receipts[receipt_id] as Dictionary
		if int(receipt["delivered_day"]) >= first_day: total += int(receipt["quantity"])
	return total

func next_transport_boundary() -> int:
	return _shared.next_boundary(_world.game_clock.total_minutes())

func dispatch_shared_window() -> bool:
	return _advance_shipments(true) and _dispatch_transport(true) and _capital_transport.advance()

## Quantified process observation only. No default daily/process loss formula,
## no refund, cancelled order, budget release or guessed liability settlement.
func record_physical_loss(actor: String, id: String, rows: Array[Dictionary], basis: String, process: String) -> bool:
	if _cargo_fulfilment.losses.has(id): return _cargo_fulfilment.losses[id]["status"] == "ADOPTED" and _cargo_fulfilment.losses[id]["rows"] == rows and _cargo_fulfilment.losses[id]["basis"] == basis and _cargo_fulfilment.losses[id]["process"] == process and _cargo_fulfilment.losses[id]["parties"].all(func(p: String) -> bool: return _cargo_fulfilment.controls(actor, p))
	if not _lots.ready(rows): return false
	for r: Dictionary in rows:
		var p := _lots.portions[r["portion_id"]] as Dictionary
		if not _cargo_fulfilment.controls(actor, p["owner"]) or not _cargo_fulfilment.controls(actor, p["custodian"]): return false
	var result := _cargo_fulfilment.request(actor, "report_cargo_loss", {"portions": rows, "basis": basis, "process": process}, id)
	return result.get("accepted", false) and _cargo_fulfilment.losses.get(id, {}).get("status") == "ADOPTED"

func _refresh_loss_pending(order: Dictionary) -> void:
	var id := str(order["id"])
	var key := str(order["seller_site"])+"|"+str(order["good"])
	_pending_by_key[key] = int(_pending_by_key.get(key, 0)) + int(order["pending"])-int(_edge(order["route_legs"][0]["edge_id"])["holds"].get(id, {}).get("quantity", 0))
	if id not in _pending_orders: _pending_orders.append(id)
	if not _pending_ids_by_key.has(key): _pending_ids_by_key[key] = {}
	_pending_ids_by_key[key][id] = true
	_edge(order["route_legs"][0]["edge_id"])["holds"][id] = {"period": order["accepted_day"], "quantity": order["pending"]}
	for cargo_id: String in _shipments_by_order.get(id, {}).keys():
		if int(_shipments[cargo_id]["quantity"]) == 0:
			_shipments[cargo_id]["stage"] = "LOSS_RECORD"
			_moving_shipments.erase(cargo_id)
			_shipments_by_order.get(id, {}).erase(cargo_id)
			var destination_key := _destination(order)+"|"+str(order["good"])
			_shipments_by_destination_good.get(destination_key, {}).erase(cargo_id)
			if _shipments_by_destination_good.get(destination_key, {}).is_empty(): _shipments_by_destination_good.erase(destination_key)
	if _shipments_by_order.get(id, {}).is_empty(): _shipments_by_order.erase(id)

func _mature_wage_position(firm: String, currency: String) -> Dictionary:
	var amount := 0
	var oldest := -1
	for id: String in _open_wages_by_employer.get(firm,{}):
		var w := _wages[id] as Dictionary
		if w["denomination"]!=currency or w["due_day"]>day: continue
		amount+=int(w["remaining"])
		if int(w["remaining"])>0 and (oldest<0 or int(w["due_day"])<oldest): oldest=int(w["due_day"])
	return {"amount":amount,"oldest_due_day":oldest,"arrears_days":day-oldest if oldest>=0 else 0}

func _business_credit_actions(actor: String, firm: String, quantity_value: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var view := _credit.visible(firm,_known_credit_lenders(firm),_world.game_clock.total_minutes(),true)
	for offer: Dictionary in view["offers"]:
		if offer["lender"]==firm: continue
		var terms := {"offer_id":offer["id"],"amount":quantity_value}
		var permission := _firm_credit_permission(actor,firm,"accept_credit",terms,false)
		var affordable: bool=quantity_value<=int(offer["available_quantity"])
		result.append({"kind":"BORROW","id":offer["id"],"denomination":offer["denomination"],"amount":quantity_value,"available":offer["available_quantity"],"interest":offer["interest"],"duration_days":offer["duration_days"],"can_execute":permission["ok"] and affordable,"reason":permission.get("reason","OFFER" if affordable else "QUANTITY_EXCEEDS_FUNDED_CREDIT"),"request":{"firm":firm,"operation":"accept_credit","terms":terms}})
	for loan: Dictionary in view["loans"]:
		if loan["borrower"]!=firm: continue
		var terms := {"loan_id":loan["id"],"amount":quantity_value}
		var permission := _firm_credit_permission(actor,firm,"repay_loan",terms,false)
		var affordable: bool=quantity_value<=int(loan["remaining"]) and quantity_value<=_world.ledger_state.available_balance(_account(firm,loan["denomination"]))
		result.append({"kind":"REPAY","id":loan["id"],"denomination":loan["denomination"],"amount":quantity_value,"remaining":loan["remaining"],"due_day":loan["due_day"],"can_execute":permission["ok"] and affordable,"reason":permission.get("reason","OFFER" if affordable else "CASH_OR_REMAINING_DEBT_LIMIT"),"request":{"firm":firm,"operation":"repay_loan","terms":terms}})
	return result

func _due_credit_amount(firm: String, currency: String) -> int:
	var amount := 0
	for loan: Dictionary in _credit.visible(firm,_known_credit_lenders(firm),_world.game_clock.total_minutes(),true)["loans"]:
		if loan["borrower"]==firm and loan["denomination"]==currency and loan["due_day"]<=day: amount+=int(loan["remaining"])
	return amount

func _validate_financial_composition() -> bool:
	for p: Dictionary in config.get("firm_finance_authorities",[]):
		var organization := str(_spec["firms"][p["firm"]].get("host_organization_id",""))
		if organization.is_empty() or not _world.organization_state.has_organization(organization): return _fail("Financial authority has no actual commercial organization")
		if _account(p["firm"],p["currency"]).is_empty(): return _fail("Financial authority currency has no enterprise account")
		if p["controller"]!=p["firm"] and not _world.person_overlay.has_person(p["controller"]): return _fail("Financial controller has no actual person identity")
		if p["basis"]=="HOST_ORGANIZATION_ROOT_AUTHORITY":
			var grant := _world.organization_state.authority_grant(p["root_authority"])
			if grant.is_empty() or grant.get("represented_entity")!=organization or grant.get("operation")!="economy.credit."+str(p["operations"][0]): return _fail("Financial root authority differs from its organization or operation")
	return true

func _firm_credit_permission(actor: String, firm: String, kind: String, payload: Dictionary, internal: bool) -> Dictionary:
	var organization := str(_spec["firms"][firm].get("host_organization_id",""))
	if organization.is_empty() and config.get("firm_finance_authorities",[]).is_empty():
		return {"ok":true,"basis":"LEGACY_UNBOUND_DEVELOPMENT_ENTERPRISE","actor":actor,"firm":firm} if _manager(actor,firm) else {"ok":false,"reason":"NO_ENTERPRISE_FINANCIAL_AUTHORITY"}
	if not organization.is_empty() and not _world.organization_state.is_organization_active(organization): return {"ok":false,"reason":"FINANCIAL_ORGANIZATION_INACTIVE"}
	var raw_amount: Variant=payload.get("principal_limit",payload.get("amount",-1))
	if not FormalLedgerState.valid_amount(raw_amount): return {"ok":false,"reason":"INVALID_FINANCIAL_AMOUNT"}
	var amount := int(raw_amount)
	var currency := str(payload.get("denomination",""))
	var target := str(payload.get("borrower",""))
	if kind=="accept_credit":
		var offer := _credit._offers.get(payload.get("offer_id",""),{}) as Dictionary
		currency=str(offer.get("denomination",""));target=str(offer.get("lender",""))
	elif kind in ["repay_loan","impair_loan","forgive_loan"]:
		var loan := _credit._loans.get(payload.get("loan_id",""),{}) as Dictionary
		currency=str(loan.get("denomination",""));target=str(loan.get("lender","") if kind=="repay_loan" else loan.get("borrower",""))
	if not FormalLedgerState.valid_amount(amount) or amount<1 or not FormalLedgerState.currency_id(currency): return {"ok":false,"reason":"INVALID_FINANCIAL_TERMS"}
	var now := _world.game_clock.total_minutes()
	for p: Dictionary in config.get("firm_finance_authorities",[]):
		if p["firm"]!=firm or p["controller"]!=actor or kind not in p["operations"] or p["currency"]!=currency or amount>int(p["limit"]) or now<int(p["start_minute"]) or now>=int(p["end_minute"]): continue
		if internal and actor!=firm: continue
		if kind=="accept_credit" and p.has("borrow_limits"):
			var limits := p["borrow_limits"] as Dictionary
			var interest := int(_credit._offers.get(payload.get("offer_id",""),{}).get("interest",0))
			var debt := 0
			for loan: Dictionary in _credit.visible(firm,_known_credit_lenders(firm),now,true)["loans"]:
				if loan["borrower"]==firm and loan["denomination"]==currency: debt+=int(loan["remaining"])
			if interest>int(limits["max_interest"]): return {"ok":false,"reason":"CREDIT_INTEREST_ABOVE_AUTHORIZED_LIMIT"}
			if amount>int(limits["daily_principal"])-_npc_financed_today(firm,currency,false): return {"ok":false,"reason":"ENTERPRISE_DAILY_PRINCIPAL_LIMIT"}
			if amount+interest>maxi(0,int(limits["max_debt"])-debt): return {"ok":false,"reason":"ENTERPRISE_OUTSTANDING_DEBT_LIMIT"}
		var proof := {"ok":true,"id":p["id"],"actor":actor,"firm":firm,"operation":kind,"currency":currency,"amount":amount,"minute":now,"basis":p["basis"],"root_authority":p["root_authority"],"organization_id":organization}
		if p.has("borrow_limits"): proof["borrow_limits"]=p["borrow_limits"].duplicate(true)
		if p["basis"]=="HOST_ORGANIZATION_ROOT_AUTHORITY":
			if internal or not _world.person_overlay.has_person(actor): continue
			var scope := {"operation":"economy.credit."+kind,"target":target,"place":_place(_primary_site(firm)),"category":"credit:"+currency,"amount":amount}
			var context := _cargo_fulfilment._available_context(actor,firm,scope,p["root_authority"])
			if context.is_empty(): continue
			var authorization := _world.authorization_check.resolve_authority(context,scope["operation"],AuthorizationCheck.STAGE_DOMAIN_EXECUTION,target,scope["place"],scope["category"],float(amount),_world.game_clock.current_hour(),str(context.get("decision_id","")))
			if authorization.get("status")!=AuthorizationCheck.ALLOWED or authorization.get("authority_id")!=p["root_authority"]: continue
			proof["authorization"]=authorization
		return proof
	return {"ok":false,"reason":"NO_SEPARATE_ENTERPRISE_FINANCIAL_AUTHORITY"}

func _firm_finance_action(actor: String, payload: Dictionary, id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload,["firm","operation","terms"]) or not _spec["firms"].has(payload.get("firm")) or payload.get("operation") not in Liquidity.ACTIONS or not payload.get("terms") is Dictionary: return _result(false,"INVALID_ENTERPRISE_FINANCE")
	var firm := str(payload["firm"])
	var permission := _firm_credit_permission(actor,firm,payload["operation"],payload["terms"],false)
	if not permission["ok"]: return _result(false,permission["reason"])
	var inner := {"action_id":"auto:"+firm+":delegated:"+id+":enterprise_credit","minute":_world.game_clock.total_minutes(),"kind":payload["operation"],"payload":payload["terms"].duplicate(true)}
	if _commands.has(inner["action_id"]): return _result(false,"ENTERPRISE_CREDIT_ACTION_CONFLICT")
	var result := _execute_credit(firm,inner,false)
	result["financial_authorization"]=permission
	result["delegated_by"]=id
	_commands[inner["action_id"]]={"envelope":{"actor":firm,"command":inner},"result":result.duplicate(true),"source":"firm"}
	_index_command_access(_commands[inner["action_id"]])
	return result

func _valid_financial_history(saved: Dictionary) -> bool:
	var commands := saved["commands"] as Dictionary
	for entry: Dictionary in commands.values():
		var command := entry["envelope"]["command"] as Dictionary
		var firm := str(entry["envelope"]["actor"])
		if not _spec["firms"].has(firm) or command["kind"] not in Liquidity.ACTIONS or not entry["result"].get("accepted",false): continue
		if not entry["result"].has("financial_authorization"):
			# A later explicit financial admission cannot rewrite older accepted debt.
			for p: Dictionary in config.get("firm_finance_authorities",[]):
				if p["firm"]==firm and int(command["minute"])>=int(p["start_minute"]): return false
			continue
		if not entry["result"]["financial_authorization"] is Dictionary: return false
		var proof := entry["result"]["financial_authorization"] as Dictionary
		if not FormalLedgerState.valid_amount(proof.get("amount")) and proof.get("basis")!="LEGACY_UNBOUND_DEVELOPMENT_ENTERPRISE": return false
		if proof.get("basis")=="LEGACY_UNBOUND_DEVELOPMENT_ENTERPRISE":
			if not str(_spec["firms"][firm].get("host_organization_id","")).is_empty() or proof.get("firm")!=firm or not _manager_at(proof.get("actor",""),firm,int(command["minute"])): return false
			continue
		var fields: Array[String]=["ok","id","actor","firm","operation","currency","amount","minute","basis","root_authority","organization_id"]
		if proof.has("authorization"): fields.append("authorization")
		if proof.has("borrow_limits"): fields.append("borrow_limits")
		if not FormalLedgerState.exact_fields(proof,fields) or proof.get("ok")!=true or proof.get("firm")!=firm or proof.get("amount")!=command["payload"].get("principal_limit",command["payload"].get("amount")): return false
		var currency := str(command["payload"].get("denomination",""))
		if command["kind"]=="accept_credit": currency=str(saved.get("credit",{}).get("offers",{}).get(command["payload"].get("offer_id"),{}).get("denomination",""))
		elif command["kind"] in ["repay_loan","impair_loan","forgive_loan"]: currency=str(saved.get("credit",{}).get("loans",{}).get(command["payload"].get("loan_id"),{}).get("denomination",""))
		if proof["currency"]!=currency: return false
		if proof["basis"]=="HOST_ORGANIZATION_ROOT_AUTHORITY":
			var grant := _world.organization_state.authority_grant(proof["root_authority"])
			if grant.is_empty() or grant.get("represented_entity")!=proof["organization_id"] or grant.get("operation")!="economy.credit."+str(command["kind"]) or not proof.get("authorization") is Dictionary or proof["authorization"].get("authority_id")!=proof["root_authority"]: return false
		var found := false
		for p: Dictionary in config.get("firm_finance_authorities",[]):
			if p["id"]==proof.get("id") and p["firm"]==firm and p["controller"]==proof.get("actor") and proof.get("operation")==command["kind"] and command["kind"] in p["operations"] and proof.get("currency")==p["currency"] and proof.get("basis")==p["basis"] and proof.get("root_authority")==p["root_authority"] and proof.get("borrow_limits",{})==p.get("borrow_limits",{}) and proof.get("organization_id")==_spec["firms"][firm].get("host_organization_id","") and proof.get("minute")==command["minute"] and int(proof.get("amount",0))>0 and int(proof["amount"])<=int(p["limit"]) and int(command["minute"])>=int(p["start_minute"]) and int(command["minute"])<int(p["end_minute"]): found=true
		if not found: return false
	return true

func _delegated_firm_credit(saved: Dictionary, entry: Dictionary) -> bool:
	var firm := str(entry["envelope"]["actor"])
	var inner := entry["envelope"]["command"] as Dictionary
	if not _spec["firms"].has(firm) or inner["kind"] not in Credit.ACTIONS or not entry["result"].get("delegated_by") is String or not entry["result"].get("financial_authorization") is Dictionary: return false
	var parent_id := str(entry["result"]["delegated_by"])
	if inner["action_id"]!="auto:"+firm+":delegated:"+parent_id+":enterprise_credit": return false
	var raw: Variant=saved["commands"].get(parent_id)
	if not raw is Dictionary or not raw.get("result") is Dictionary or not raw.get("envelope") is Dictionary or not raw["envelope"].get("command") is Dictionary: return false
	var parent := raw as Dictionary
	if not parent["result"].get("accepted",false) or parent["envelope"]["command"].get("minute")!=inner["minute"] or parent["result"].get("financial_authorization")!=entry["result"]["financial_authorization"]: return false
	var outer := parent["envelope"]["command"] as Dictionary
	var source := str(parent["envelope"].get("actor",""))
	if source!=entry["result"]["financial_authorization"].get("actor") or not outer.get("payload") is Dictionary: return false
	if outer["kind"]=="finance_firm": return outer["payload"].get("firm")==firm and outer["payload"].get("operation")==inner["kind"] and outer["payload"].get("terms")==inner["payload"]
	if outer["kind"]=="finance_investment":
		var project := saved.get("capital_formation",{}).get("projects",{}).get(outer["payload"].get("project_id"),{}) as Dictionary
		return project.get("firm")==firm and inner["kind"]=="accept_credit" and inner["payload"]=={"offer_id":outer["payload"].get("offer_id"),"amount":outer["payload"].get("amount")}
	return false

func _npc_liquidity() -> bool:
	for p: Dictionary in config.get("liquidity_policies",[]):
		if _wind_down.controls(p["firm"]) and _firm_winding_down(p["firm"]): continue
		var firm := str(p["firm"])
		if firm_manager_at(firm,_world.game_clock.total_minutes())!=firm or firm_finished(firm): continue
		var wages := _mature_wage_position(firm,p["currency"])
		var policy := _finance_policy(firm)
		if p["finance_due_wages"] and wages["amount"]>0 and not policy.is_empty():
			var before := _world.ledger_state.available_balance(_account(firm,p["currency"]))
			var shortfall := maxi(0,int(wages["amount"])-before)
			_borrow_for_shortfall(firm,p["currency"],shortfall,policy,"mature_wages",{"purpose":"MATURED_WAGES","wage_amount":wages["amount"],"oldest_due_day":wages["oldest_due_day"]})
			if _world.ledger_state.available_balance(_account(firm,p["currency"]))>before and not _pay_wages(): return false
			wages=_mature_wage_position(firm,p["currency"])
		var constrained: bool=wages["amount"]>0 and wages["arrears_days"]>=int(p["pause_after_days"])
		if constrained and p["pause_investment"]:
			for project_site: String in _spec["firms"][firm]["sites"]:
				for project_id: String in _capital._active_by_site.get(project_site,[]):
					var project := _capital.projects[project_id] as Dictionary
					if project["status"]!="PAUSED": _npc_submit(firm,"investment_status",{"project_id":project_id,"status":"PAUSED"},project_id,{"purpose":"PRESERVE_MATURED_WAGE_RESPONSIBILITY"})
		for site: String in _spec["firms"][firm]["sites"]:
			if site_closed(site) or _firm_winding_down(firm): continue
			var state := _site_state[site] as Dictionary
			var recover: bool=not constrained and wages["amount"]==0 and _world.ledger_state.available_balance(_account(firm,p["currency"]))-_due_credit_amount(firm,p["currency"])>=int(p["recover_cash"]) and _own_liquidity_pause(site)
			if (constrained and state["production_enabled"]) or (recover and not state["production_enabled"]):
				_npc_submit(firm,"set_site_status",{"firm":firm,"site_id":site,"enabled":state["enabled"],"production_enabled":recover,"accepting_business":state["accepting_business"]},"liquidity:"+site,{"purpose":"LIQUIDITY_RECOVERY" if recover else "LIQUIDITY_PRODUCTION_PAUSE","wage_amount":wages["amount"],"arrears_days":wages["arrears_days"]})
		var closure_pending:=false
		for change: String in _pending_enterprise_changes:
			if _enterprise_changes[change]["firm"]==firm and _enterprise_changes[change]["kind"]=="wind_down_firm": closure_pending=true;break
		if not closure_pending and p["wind_down_after_days"]>0 and wages["amount"]>0 and wages["arrears_days"]>=int(p["wind_down_after_days"]) and not _firm_winding_down(firm):
			_npc_submit(firm,"wind_down_firm",{"firm":firm},"liquidity:wind_down",{"purpose":"PERSISTENT_UNFUNDED_OBLIGATIONS"})
		elif p["pause_investment"] and not constrained and wages["amount"]==0 and not _firm_winding_down(firm):
			for project_site: String in _spec["firms"][firm]["sites"]:
				for project_id: String in _capital._active_by_site.get(project_site,[]):
					var project := _capital.projects[project_id] as Dictionary
					var terms := _capital.template(project["template_id"])
					var available := _world.ledger_state.available_balance(_account(firm,terms["denomination"]))-_due_credit_amount(firm,terms["denomination"])
					if project["status"]=="PAUSED" and _own_liquidity_project_pause(project_id) and available>=maxi(int(p["recover_cash"]),int(terms["cash_floor"])+_capital.remaining_labor_budget(project)):
						_npc_submit(firm,"investment_status",{"project_id":project_id,"status":"ACTIVE"},project_id,{"purpose":"LIQUIDITY_PROJECT_RECOVERY"})
	return true

func _own_liquidity_pause(site: String) -> bool:
	var latest: Dictionary={}
	for row: Dictionary in _enterprise_changes.values():
		if row["status"]=="APPLIED" and row["payload"].get("site_id")==site and row["kind"]=="set_site_status" and (latest.is_empty() or row["effective_minute"]>latest["effective_minute"]): latest=row
	return not latest.is_empty() and _commands.get(latest["id"],{}).get("result",{}).get("decision",{}).get("purpose")=="LIQUIDITY_PRODUCTION_PAUSE"

func _own_liquidity_project_pause(project_id: String) -> bool:
	var latest: Dictionary={}
	for row: Dictionary in _capital.changes.values():
		if row["status"]=="APPLIED" and row["kind"]=="investment_status" and row["payload"].get("project_id")==project_id and (latest.is_empty() or row["effective_minute"]>latest["effective_minute"]): latest=row
	return not latest.is_empty() and _commands.get(latest["id"],{}).get("result",{}).get("decision",{}).get("purpose")=="PRESERVE_MATURED_WAGE_RESPONSIBILITY"

func _npc_job_payable(actor: String, job: String) -> bool:
	var p := Liquidity.labor_policy(config,actor)
	if p.is_empty(): return true
	for id: String in _wages_by_worker.get(actor,[]):
		var w := _wages[id] as Dictionary
		if _work_records[id]["job"]==job and w["remaining"]>0 and day-int(w["due_day"])>=int(p["arrears_days"]): return false
	return true

func _npc_labor_response() -> void:
	# One explicitly configured group per day. Old wage claims remain with their employer.
	for p: Dictionary in config.get("labor_response_policies",[]):
		var actor := str(p["actor"])
		if not _contracts.has(actor) or _employment_end_pending(actor): continue
		var all_unpaid := true
		for contract: Dictionary in _contract_rows(_contracts[actor]): all_unpaid=all_unpaid and not _npc_job_payable(actor,contract["job"])
		if all_unpaid:
			_npc_submit(actor,"leave_job",{},"wage_arrears",{"purpose":"OWN_MATURED_WAGE_ARREARS","waiting_days":p["arrears_days"]})
			return

func _release_loss_obligation(order: Dictionary, quantity: int, id: String) -> bool:
	if order.has("supply_contract_id") and _supply.records.get(order["supply_contract_id"],{}).get("ended_minute",-1)<0: return _fail("ACTIVE_SUPPLY_REQUIRES_REPLACEMENT_OR_EXPLICIT_CONTRACT_END")
	if quantity > int(order["pending"]) or not _budgets.change_ready(order["id"], order["delivered"], int(order["cancelled"])+quantity, order["quantity"]): return false
	var amount := quantity*(int(order["price"])+_freight(order["route_legs"]))
	if amount > 0 and not _world.ledger_state.release(order["id"], amount): return false
	var settled := _budgets.settle("loss_release:"+id, order["id"], order["delivered"], int(order["cancelled"])+quantity, order["quantity"])
	assert(settled)
	_change_order_observation(order, -quantity)
	if order["kind"] != "PERSONAL_FREIGHT": _change_incoming(order, -quantity)
	order["pending"] -= quantity
	order["cancelled"] += quantity
	var key := str(order["seller_site"])+"|"+str(order["good"])
	_pending_by_key[key] = int(_pending_by_key.get(key, 0))-quantity
	var edge := _edge(order["route_legs"][0]["edge_id"])
	if order["accepted_day"] == day: edge["input_used"] -= quantity
	if int(order["pending"]) == 0:
		_pending_orders.erase(order["id"])
		_pending_ids_by_key.get(key, {}).erase(order["id"])
		edge["holds"].erase(order["id"])
	else: edge["holds"][order["id"]]["quantity"] = order["pending"]
	if int(order["pending"])+int(order["transit"]) == 0:
		_active_orders.erase(order["id"])
		_active_by_buyer.get(order["buyer"], []).erase(order["id"])
		_active_sales_by_key.get(key,{}).erase(order["id"])
	return true

func personal_loss_source(id: String) -> Dictionary:
	return _cargo_fulfilment.losses.get(id, {}).get("personal_fact", {}).duplicate(true)

## Stable physical source/unit query for future consumers, including a future
## military connection. This query grants no transfer or conversion authority.
func owned_batch_rows(actor: String, subject: String, limit: int = 32, offset: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if limit <= 0 or offset < 0: return result
	var owner := _owner(subject)
	if _spec["sites"].has(subject) or _spec["firms"].has(subject):
		if not _manager(actor, owner): return result
	elif subject != actor or not _actors.has(actor): return result
	var ids: Array = _lots._by_owner.get(owner, {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("portion:")) < int(b.trim_prefix("portion:")))
	var skipped := 0
	for id: String in ids:
		var p := _lots.portions[id] as Dictionary
		if _spec["sites"].has(subject) and p["location"] != "SITE|"+subject: continue
		if skipped < offset: skipped += 1; continue
		var row := p.duplicate(true)
		if p["location"] == "PERSON|"+owner+"|CARRIED":
			row["place_id"] = _place(owner)
			row["person_travelling"] = _world.person_travel != null and _world.person_travel.active(owner)
		row["source_basis"] = _lots.sources[p["source_id"]]["basis"]
		row["formed_minute"] = _lots.sources[p["source_id"]]["formed_minute"]
		if _costs.enabled:
			row["cost"] = _costs.cost_of(_costs.ranges([{ "portion_id":id,"source_id":p["source_id"],"quantity":p["remaining"] }]))
		result.append(row)
		if result.size() >= mini(limit, 64): return result
	return result

func _validate_personal_physical_partitions() -> bool:
	var expected: Dictionary = {}
	var actual: Dictionary = {}
	for person: String in _world.personal_economy_state._native_lots:
		if not _declared_named(person): continue
		for good: String in _world.personal_economy_state._native_lots[person]:
			for lot: Dictionary in _world.personal_economy_state._native_lots[person][good]:
				for custody: String in _world.personal_economy_state._lot_positions(lot):
					var key := person+"#"+good+"#"+str(lot["source_id"])+"#"+custody
					expected[key] = int(expected.get(key, 0))+int(_world.personal_economy_state._lot_positions(lot)[custody])
	for person: String in _actor_ids_from_spec():
		if not _declared_named(person): continue
		for id: String in _lots._by_owner.get(person, {}):
			var p := _lots.portions[id] as Dictionary
			var custody := str(p["location"]).trim_prefix("PERSON|"+person+"|")
			if str(p["location"]).begins_with("CARGO|"):
				custody = "FREIGHT|"+str(_shipments[str(p["location"]).trim_prefix("CARGO|")]["order_id"])
			var key := person+"#"+str(p["good"])+"#"+str(p["acquisition_id"])+"#"+custody
			actual[key] = int(actual.get(key, 0))+int(p["remaining"])
	if actual != expected: return _fail("Personal source/custody descriptions differ from actual physical portions")
	var consumed: Dictionary = {}
	for project: Dictionary in _capital.projects.values():
		if not project.has("material_sources"): continue # Old projects retain unrecorded historic input origins.
		if not project["material_sources"] is Array: return _fail("Invalid capital material source portions")
		var materials: Dictionary = {}
		for row: Variant in project["material_sources"]:
			if not row is Dictionary or not _lots.portions.has(row.get("portion_id")) or not FormalLedgerState.valid_amount(row.get("quantity")): return _fail("Missing capital material source portion")
			var p := _lots.portions[row["portion_id"]] as Dictionary
			if p["location"] != "SITE|"+str(project["site_id"]) or p["owner"] != project["firm"] or row.get("source_id") != p["source_id"] or int(p["opened_minute"]) > int(project["material_minute"]): return _fail("Capital material source owner/place/time mismatch")
			consumed[p["id"]] = int(consumed.get(p["id"], 0))+int(row["quantity"])
			if int(consumed[p["id"]]) > int(p["consumed"]): return _fail("Capital reuses a consumed portion")
			materials[p["good"]] = int(materials.get(p["good"], 0))+int(row["quantity"])
		for good: String in project["materials"]:
			if int(project["materials"][good]) != int(materials.get(good, 0)): return _fail("Capital input quantities lost their sources")
	return true

## Called only after native, Spatial and host passenger candidate restoration.
func validate_transport_references() -> bool:
	if not _leases.validate_presence(): return _fail(_leases.error)
	if not _capital.validate_mobility_presence(): return _fail(_capital.error)
	if not _retail.validate_presence(): return _fail(_retail.error)
	if not _commercial.validate_presence(): return _fail(_commercial.error)
	if not _labor_market.validate_presence(): return _fail(_labor_market.error)
	if not _service_market._resident.validate_presence(): return _fail(_service_market._resident.error)
	for id: String in _world.spatial_world._capacity._adoptions:
		if id.begins_with("economy_entry:") and not _shared.entries.has(id): return _fail("Unowned native Spatial entry: "+id)
		if id.begins_with("passenger_entry:") and (_world.person_travel==null or not _world.person_travel._shared_entries.has(id)): return _fail("Unowned passenger Spatial entry: "+id)
	return true

## Stable read-only merchant queries. No advance_time, mutation or other firms' cash.
func supply_business_view(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=_supply.views(actor)
	for c: Dictionary in result:
		# UI receipts use own actual Ledger facts, not delivered quantity times price.
		# Preserve original contract progress calculations for domain decisions.
		if _manager(actor,str(c.get("supplier",""))):
			c["delivered_locked_goods_value"]=c.get("paid",0)
			var actual_paid: int=0
			var payment_ids: Array[String]=[]
			for payment: Dictionary in _world.ledger_state.own_transactions(c["supplier"]):
				if payment["kind"]!="goods" or payment["to_account_id"]!=_account(c["supplier"],payment["denomination"]):continue
				var order: Dictionary=_orders.get(payment["reference_id"],{})
				if order.get("supply_contract_id","")!=c["id"]:continue
				actual_paid+=int(payment["amount"]);payment_ids.append(str(payment["transaction_id"]))
			c["paid"]=actual_paid;c["payment_ids"]=payment_ids;c["paid_basis"]="OWN_ORIGINAL_LEDGER_LINKED_TO_SUPPLY_ORDERS"
		c.merge(supply_dispatch_preview(actor,c["id"]))
		var comparison_quantity: int=clampi(int(c["quantity"])-int(c.get("free_stock",0)),1,1000000)
		var business: Dictionary=business_view(actor,c["supplier"],c["supplier_site"],comparison_quantity,0,16)
		var sources: Array[Dictionary]=[]
		for q: Dictionary in business.get("offers",[]):
			if q.get("good")==c["good"]:sources.append(q.duplicate(true))
		c["known_sources"]=sources
		c["estimate_basis"]="KNOWN_CURRENT_QUOTES_NOT_FUTURE_GUARANTEE"
	return result.duplicate(true)

func supply_dispatch_preview(actor: String,id: String) -> Dictionary:
	var c: Dictionary=_supply.view(actor,id)
	var result: Dictionary={"new_batch_earliest_day":null,"new_batch_eta_basis":"UNKNOWN"}
	if c.is_empty():return result
	var route_id: String=str(c.get("route_id",""))
	for path: Dictionary in _paths_for(c["supplier"],_place(c["supplier_site"]),_place(c["buyer_site"]),day):
		if not route_id.is_empty() and path["id"]!=route_id:continue
		var legs: Array=_locked_legs(path,FormalLedgerState.DENOMINATION)
		if legs.is_empty():continue
		for leg: Dictionary in legs:
			if _shared.bindings.has(leg["edge_id"]):return result
		var preview: Dictionary={"route_id":path["id"],"buyer":c["buyer"],"accepted_minute":_world.game_clock.total_minutes(),"accepted_day":day,"route_legs":legs}
		result["new_batch_earliest_day"]=_earliest_dispatch(preview)+_travel_days(legs)
		result["new_batch_eta_basis"]="FORMAL_DAILY_NO_QUEUE_LOWER_BOUND"
		return result
	return result

func managed_transfer_options(actor: String,firm: String,source_site: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not _manager(actor,firm) or not _spec["sites"].has(source_site) or _owner(source_site)!=firm:return result
	for site: String in _site_ids():
		if site==source_site or _owner(site)!=firm:continue
		for path: Dictionary in _paths_for(firm,_place(source_site),_place(site),day):
			var legs: Array=_locked_legs(path,FormalLedgerState.DENOMINATION)
			result.append({"from_site":source_site,"to_site":site,"from_place":_place(source_site),"to_place":_place(site),"path_id":path["id"],"freight_per_unit":_freight(legs),"denomination":FormalLedgerState.DENOMINATION})
	return result

## Index only the managed firm's original Ledger facts; references never create money.
func _managed_trade_payments(firm: String) -> Dictionary:
	var result: Dictionary = {}
	for payment: Dictionary in _world.ledger_state.own_transactions(firm):
		if payment["kind"] not in ["goods", "freight"]: continue
		var reference: String = str(payment["reference_id"])
		if not result.has(reference): result[reference] = []
		result[reference].append(payment)
	return result

func _managed_receipt_payments(receipt: Dictionary, order: Dictionary, payments: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var id: String = str(receipt["id"])
	var batch: Dictionary = _world.ledger_state.payment_batch("delivery:"+id)
	# The fallback is the original delivery transaction identity, not quantity
	# times price. It also supports older facts without a payment-batch index.
	var ids: Array = batch.get("transactions",[]).duplicate()
	if "r1:goods:"+id not in ids: ids.append("r1:goods:"+id)
	var legs: Array = order.get("route_legs",[])
	for i: int in legs.size():
		var freight_id: String = "r1:freight:"+id+(":"+str(i) if legs.size()>1 else "")
		if freight_id not in ids: ids.append(freight_id)
	for payment: Dictionary in payments.get(str(order["id"]),[]):
		if payment["transaction_id"] not in ids or payment["denomination"] != order["denomination"]: continue
		if payment["from_account_id"] != order["buyer_account"]: continue
		if payment["kind"] == "goods" and payment["to_account_id"] != order["seller_account"]: continue
		result.append(payment.duplicate(true))
	return result

func _managed_order_cash_rows(firm: String, payments: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order: Dictionary in _orders.values():
		if order["buyer"] != firm and order["seller"] != firm: continue
		var paid: Dictionary = {};var freight: Dictionary = {};var received: Dictionary = {};var delta: Dictionary = {}
		var payment_ids: Array[String] = [];var receipt_ids: Array[String] = [];var receipt_rows: Array[Dictionary] = []
		var actual_payments: Array[Dictionary] = []
		for payment: Dictionary in payments.get(str(order["id"]),[]):
			var currency: String = str(payment["denomination"])
			var account: String = _account(firm,currency)
			var amount: int = int(payment["amount"])
			if payment["kind"] == "goods":
				if payment["from_account_id"] == account: paid[currency]=int(paid.get(currency,0))+amount
				if payment["to_account_id"] == account: received[currency]=int(received.get(currency,0))+amount
			elif payment["from_account_id"] == account: freight[currency]=int(freight.get(currency,0))+amount
			payment_ids.append(str(payment["transaction_id"]))
			actual_payments.append(payment.duplicate(true))
		for receipt_id: String in _deliveries_by_order.get(str(order["id"]),[]):
			var receipt: Dictionary = _delivery_receipts[receipt_id]
			var receipt_payments: Array[Dictionary] = _managed_receipt_payments(receipt,order,payments)
			var linked_ids: Array[String] = []
			var goods_linked: bool = false
			for payment: Dictionary in receipt_payments:
				linked_ids.append(str(payment["transaction_id"]))
				if payment["kind"] == "goods": goods_linked = true
			receipt_ids.append(receipt_id)
			receipt_rows.append({"receipt_id":receipt_id,"order_id":order["id"],"quantity":receipt["quantity"],"minute":_delivery_minute(receipt),"payment_ids":linked_ids,"payments":receipt_payments,"payment_status":"GOODS_LEDGER_LINKED" if goods_linked else "DELIVERED_PENDING_VERIFICATION" if order["kind"]=="SALE" else "NO_GOODS_PAYMENT_FOR_INTERNAL_TRANSFER"})
		for currency: String in received.keys()+paid.keys()+freight.keys(): delta[currency]=int(received.get(currency,0))-int(paid.get(currency,0))-int(freight.get(currency,0))
		result.append({"order_id":order["id"],"kind":order["kind"],"role":"TRANSFER" if order["buyer"]==firm and order["seller"]==firm else "PURCHASE" if order["buyer"]==firm else "SALE","good":order["good"],"buyer":order["buyer"],"seller":order["seller"],"buyer_site":order["buyer_site"],"seller_site":order["seller_site"],"quantity":order["quantity"],"delivered":order["delivered"],"pending":order["pending"],"transit":order["transit"],"cancelled":order["cancelled"],"locked_price":order["price"],"denomination":order["denomination"],"accepted_minute":order["accepted_minute"],"supply_contract_id":order.get("supply_contract_id",""),"goods_paid":paid,"freight_paid":freight,"sales_received":received,"received":received.duplicate(true),"known_trade_cash_difference":delta,"payment_ids":payment_ids,"payment_reference_id":order["id"],"payments":actual_payments,"receipt_ids":receipt_ids,"receipt_rows":receipt_rows,"basis":"ORIGINAL_ORDER_REFERENCED_LEDGER_CASH_NOT_LOT_MATCHED_PROFIT"})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a["accepted_minute"])>int(b["accepted_minute"]) if a["accepted_minute"]!=b["accepted_minute"] else str(a["order_id"])<str(b["order_id"]))
	return result

## Amounts from the managed firm's own posted Ledger receipts, never wage claims.
func _managed_nontrade_cash(firm: String) -> Dictionary:
	var result: Dictionary={"wages_paid":{},"advertising_paid":{},"service_fees_paid":{},"other_cash_paid":{}}
	for payment: Dictionary in _world.ledger_state.own_transactions(firm):
		var currency: String=str(payment["denomination"])
		if payment["from_account_id"]!=_account(firm,currency) or payment["kind"] in ["goods","freight"]:continue
		var field: String="other_cash_paid"
		if payment["kind"]=="wage":field="wages_paid"
		elif payment["kind"]=="service_fee":field="advertising_paid" if _service_market.contracts.get(payment.get("reference_id",""),{}).get("kind")=="ANNOUNCEMENT" else "service_fees_paid"
		result[field][currency]=int(result[field].get(currency,0))+int(payment["amount"])
	result["basis"]="LIFETIME_OWN_POSTED_NONTRADE_PAYMENTS_NOT_INCURRED_COST_OR_PROFIT"
	return result

func managed_trade_review(actor: String,firm: String) -> Dictionary:
	if not _manager(actor,firm):return {}
	var purchased: Dictionary={};var held: Dictionary={};var paid: Dictionary={};var freight: Dictionary={};var received: Dictionary={};var delta: Dictionary={}
	var procurement_unsettled: int=0;var sale_unsettled: int=0
	for order: Dictionary in _orders.values():
		if order["kind"]!="SALE":continue
		if order["buyer"]==firm:
			purchased[order["good"]]=int(purchased.get(order["good"],0))+int(order["delivered"])
			procurement_unsettled+=(int(order["pending"])+int(order["transit"]))*int(order["price"])
		if order["seller"]==firm:sale_unsettled+=(int(order["pending"])+int(order["transit"]))*int(order["price"])
	for site: String in _site_ids():
		if _owner(site)!=firm:continue
		for good: String in _goods:held[good]=int(held.get(good,0))+int(_stocks[site][good])
	var payments: Dictionary = _managed_trade_payments(firm)
	for rows: Array in payments.values():
		for payment: Dictionary in rows:
			var currency: String=payment["denomination"];var account: String=_account(firm,currency);var amount: int=int(payment["amount"])
			if payment["kind"]=="goods":
				if payment["to_account_id"]==account:received[currency]=int(received.get(currency,0))+amount
				if payment["from_account_id"]==account:paid[currency]=int(paid.get(currency,0))+amount
			elif payment["kind"]=="freight" and payment["from_account_id"]==account:freight[currency]=int(freight.get(currency,0))+amount
	for currency: String in received.keys()+paid.keys()+freight.keys():delta[currency]=int(received.get(currency,0))-int(paid.get(currency,0))-int(freight.get(currency,0))
	var open: Array[Dictionary]=[]
	for c: Dictionary in _supply.views(actor):
		if c.get("supplier")==firm and c.has("accept_action") and c.get("status") in ["ACCEPTED","PARTIAL"]:open.append({"id":c["id"],"good":c["good"],"remaining":c["remaining"],"deadline":c["deadline"]})
	return {"nontrade_cash":_managed_nontrade_cash(firm),"delivered_purchases":purchased,"current_inventory":held,"goods_paid":paid,"freight_paid":freight,"sales_received":received,"known_trade_cash_difference":delta,"unsettled_goods_purchases":procurement_unsettled,"unsettled_goods_sales":sale_unsettled,"open_supply_contracts":open,"order_rows":_managed_order_cash_rows(firm,payments),"basis":"LIFETIME_ORIGINAL_LEDGER_GOODS_AND_FREIGHT_ONLY_NOT_PROFIT"}

## Authorized projection rebuilt from original receipts and own Ledger facts.
## Full receipt/quote history survives refresh; UI read positions are not authority.
func managed_market_feedback(actor: String, firm: String) -> Dictionary:
	if not _manager(actor,firm):return {}
	var events: Array[Dictionary]=[]
	var payments: Dictionary = _managed_trade_payments(firm)
	var sales: Dictionary={};var seen_quotes: Dictionary={};var spot: int=0;var held: int=0;var active: int=0;var completed: int=0
	var labels: Dictionary={"grain":"粮食","beans":"豆类","fiber":"纤维","oil":"油料","bread":"面包","clothes":"衣物","soap":"肥皂"}
	for receipt: Dictionary in _delivery_receipts.values():
		var order: Dictionary=_orders[receipt["order_id"]]
		if order["kind"]!="SALE" or (order["seller"]!=firm and order["buyer"]!=firm):continue
		var quantity: int=int(receipt["quantity"])
		var good: String=labels.get(order["good"],"商品")
		var linked: Array[Dictionary] = _managed_receipt_payments(receipt,order,payments)
		var goods_ids: Array[String] = [];var payment_ids: Array[String] = []
		var amount: int = 0;var payment_minute: int = _delivery_minute(receipt)
		for payment: Dictionary in linked:
			payment_ids.append(str(payment["transaction_id"]))
			if payment["kind"] != "goods": continue
			goods_ids.append(str(payment["transaction_id"]))
			amount += int(payment["amount"])
			payment_minute = maxi(payment_minute,int(payment["effective_minute"]))
		goods_ids.sort();payment_ids.sort()
		var text: String="采购到仓：%s %d单位；已交付，付款凭据待核对。"%[good,quantity]
		var kind: String="receipt";var priority: int=60
		var event_id: String="receipt:"+str(receipt["id"])
		var status: String="DELIVERED_PENDING_VERIFICATION"
		if not goods_ids.is_empty():
			text="采购到仓：%s %d单位；原账本已付货款%d。"%[good,quantity,amount]
			status="PAID"
		if order["seller"]==firm:
			sales[order["id"]]=true
			if not order.has("supply_contract_id"):spot+=quantity
			var sale_kind: String="合同供货" if order.has("supply_contract_id") else "现货销售"
			text="%s：%s %d单位已交付，收款凭据待核对。"%[sale_kind,good,quantity]
			priority=80
			if not goods_ids.is_empty():
				text="%s：%s %d单位已交付，原账本实收货款%d。"%[sale_kind,good,quantity,amount]
				kind="payment";priority=100;status="RECEIVED"
				event_id="payment:"+"|".join(goods_ids)
		var refs: Array = [str(receipt["id"]),str(order["id"])]
		refs.append_array(payment_ids)
		events.append({"event_id":event_id,"kind":kind,"priority":priority,"text":text,"minute":payment_minute,"refs":refs,"payment_ids":payment_ids,"receipt_id":str(receipt["id"]),"order_id":str(order["id"]),"amount":amount if not goods_ids.is_empty() else null,"denomination":order["denomination"],"payment_status":status,"payments":linked})
	for order: Dictionary in _orders.values():
		if order["buyer"]==firm or order["seller"]==firm:
			if int(order["pending"])+int(order["transit"])>0:active+=1
	for site: String in _site_ids():
		if _owner(site)!=firm:continue
		for good: String in _goods:held+=maxi(0,int(_stocks[site][good])-_committed(site,good))
	# Reconstruct every actually delivered quotation notice, not just the newest
	# currently useful quote. Never read another firm's unreceived quote history.
	for notice: Dictionary in _receipts.values():
		if notice.get("kind") != "goods_quote" or not _local_quotes.quotes.has(notice.get("candidate")): continue
		var observer: String = _inventory_key(str(notice["actor"]))
		if not _spec["sites"].has(observer) or _owner(observer) != firm: continue
		var q: Dictionary = _local_quotes.quotes[notice["candidate"]]
		var received_minute: int = int(notice["delivery_day"])*1440
		if seen_quotes.has(q["id"]):
			var earlier: Dictionary=events[int(seen_quotes[q["id"]])]
			earlier["minute"]=mini(int(earlier["minute"]),received_minute)
			continue
		seen_quotes[q["id"]]=events.size()
		var expired: bool=_world.game_clock.total_minutes()>=int(q["expires_day"])*1440
		var text: String="已收到%s报价%d；第%d天生效，有效至第%d天。"%[labels.get(q["good"],"商品"),int(q["price"]),int(q["effective_day"])+1,int(q["expires_day"])+1]
		if expired:text+="此报价现已过期。"
		events.append({"event_id":"quote:"+str(q["id"]),"kind":"quote","priority":10,"text":text,"minute":received_minute,"refs":[str(q["id"]),str(notice["id"])],"payment_ids":[],"receipt_id":"","order_id":"","amount":null,"denomination":_sale_currency(_owner(str(q["site"]))),"quote_id":q["id"]})
	for c: Dictionary in _supply.views(actor):
		if c.get("supplier")!=firm:continue
		if c.get("status")=="COMPLETED":completed+=1
	# Current buyer need/cash can affect preflight, never erase an old notice.
	for notice: Dictionary in _supply.notices.values():
		var terms: Dictionary=notice["terms"]
		if terms["supplier"]!=firm or not _supply.known_notice(notice["id"]):continue
		events.append({"event_id":"quote:"+str(notice["id"]),"kind":"quote","priority":20,"text":"已收到%s采购公告：%d单位，单价%d，截止第%d天；是否仍可接单需复核。"%[labels.get(terms["good"],"商品"),int(terms["quantity"]),int(notice["price"]),int(terms["deadline"])/1440+1],"minute":_received_market_minute(str(terms["supplier_site"]),"supply_opportunity",str(notice["id"])),"refs":[str(notice["id"])],"payment_ids":[],"receipt_id":"","order_id":"","amount":null,"denomination":_sale_currency(firm)})
	for event: Dictionary in events:event["text"]="第%d天 · "%[int(event["minute"])/1440+1]+str(event["text"])
	events.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a["minute"])>int(b["minute"]) if a["minute"]!=b["minute"] else int(a["priority"])>int(b["priority"]) if a["priority"]!=b["priority"] else str(a["event_id"])<str(b["event_id"]))
	var cash: int=_world.ledger_state.available_balance(_account(firm))
	var goals: Array[Dictionary]=[
		{"title":"完成第一笔实际现货销售","achieved":spot>0,"progress":"已交付%d单位"%spot},
		{"title":"完成一项合法供货合同","achieved":completed>0,"progress":"已完成%d项"%completed},
		{"title":"完成数笔销售并保留库存","achieved":sales.size()>=3 and held>0,"progress":"%d笔交付销售 / %d单位自由库存"%[sales.size(),held]},
		{"title":"承担未完订单时保留可用资金","achieved":active>0 and cash>0,"progress":"%d项未完订单 / 可用%d"%[active,cash]},
		{"title":"在有限开局资源下经营30日","achieved":day>=30,"progress":"已经过%d日；本目标不发资金或物资"%day}]
	return {"events":events,"goals":goals,"history_complete":true,"basis":"OWN_ORIGINAL_LEDGER_DELIVERY_RECEIPTS_AND_RECEIVED_INFORMATION_READ_ONLY"}

func _received_market_minute(observer: String, kind: String, candidate: String) -> int:
	var minute: int=0
	for receipt: Dictionary in _receipts.values():
		if _inventory_key(receipt["actor"])==observer and receipt["kind"]==kind and receipt["candidate"]==candidate:
			minute=maxi(minute,int(receipt["delivery_day"])*1440)
	return minute
