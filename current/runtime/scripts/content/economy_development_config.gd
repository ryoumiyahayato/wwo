class_name EconomyDevelopmentConfig
extends RefCounted
## Explicit opt-in content for the existing WorldBootstrap.build() argument.
## Host places and rail IDs are real catalog references. Firms, facilities,
## recipes, endowments, needs, delays and capacities are development parameters.
## Default world creation never reads or enables this configuration.
## Regional selection accepts any valid R2 configuration in its configuration
## field. Existing commercial organizations are bound explicitly with each
## firm's host_organization_id; identities and opening business data stay separate.

static func multisite() -> Dictionary:
	var goods: Array[String] = ["beans", "bread", "cloth", "clothes", "fiber", "flour", "grain", "oil", "soap"]
	var stock := func(values: Dictionary) -> Dictionary:
		var result := EconomySliceConfig.zero_stock(goods)
		result.merge(values, true)
		return result
	var activity := func(id: String, place: String, outputs: Dictionary, materials: Dictionary) -> Dictionary:
		return {"id": id, "place_id": place, "outputs": outputs, "materials": stock.call(materials), "hours": 1, "capacity_units": 1, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION"}
	var site := func(id: String, place: String, roles: Array, inventory: Dictionary, targets: Dictionary, prices: Dictionary, capacity: int, activities: Array, suppliers: Array) -> Dictionary:
		return {"id": id, "place_id": place, "roles": roles, "stock": stock.call(inventory), "targets": stock.call(targets), "prices": prices, "capacity": capacity, "activities": activities, "suppliers": suppliers, "enabled": true, "production_enabled": true, "accepting_business": true, "basis": "DEVELOPMENT_CONFIGURATION", "coordination_delay": 1}
	var player := WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
	var farm: String = "firm:development_farm"
	var workshop: String = "firm:development_workshop"
	var soap: String = "firm:development_soap"
	var farm_source: String = "site:development_farm:lyon"
	var farm_store: String = "site:development_farm:paris"
	var works: String = "site:development_workshop:paris"
	var shop: String = "site:development_workshop:lyon"
	var soap_works: String = "site:development_soap:paris"
	var workshop_workers: String = "cohort:development:paris_workshop"
	var farm_workers: String = "cohort:development:lyon_farm"
	var soap_workers: String = "cohort:development:paris_soap"
	var farm_suppliers: Array = [farm + "|grain|" + farm_store, farm + "|fiber|" + farm_store]
	var soap_supplier := soap + "|soap|" + soap_works
	var soap_material := farm + "|oil|" + farm_store
	var result := {
		"format": "R2", "case_id": "DEVELOPMENT_MULTI_SITE_LIVING", "stock_horizon": 2,
		"production_enabled": true, "player_choice": "substitute",
		"need_categories": [{"id": "food", "mode": "flow", "priority": 0}, {"id": "clothing", "mode": "durable", "priority": 1}, {"id": "household", "mode": "flow", "priority": 2}],
		"goods": [{"id": "grain", "needs": {}}, {"id": "beans", "needs": {"food": 2}}, {"id": "flour", "needs": {}}, {"id": "bread", "needs": {"food": 1}}, {"id": "fiber", "needs": {}}, {"id": "cloth", "needs": {"clothing": 1, "household": 1}}, {"id": "clothes", "needs": {"clothing": 2}}, {"id": "oil", "needs": {}}, {"id": "soap", "needs": {"household": 2}}],
		"actors": [], "firms": [], "jobs": [], "information": [],
		"route": {"id": "edge:r2_paris_local", "place_id": "place:paris", "capacity": 24, "delay": 1, "basis": "SYNTHETIC"},
		"carriers": [{"id": "carrier:development_rail", "place_id": "place:paris", "account_id": "account:development_rail", "cash": 0}],
		"transport_nodes": [{"place_id": "place:paris", "capacity": 24}, {"place_id": "place:lyon", "capacity": 18}],
		"firm_operations": [{"firm": farm, "planning_horizon": 4, "buffer_days": 1, "demand_window": 3, "manage_jobs": true}, {"firm": workshop, "planning_horizon": 4, "buffer_days": 1, "demand_window": 3, "manage_jobs": true}, {"firm": soap, "planning_horizon": 3, "buffer_days": 1, "demand_window": 3, "manage_jobs": true}],
		"price_policies": [{"firm": workshop, "site_id": shop, "good": "clothes", "mode": "N3", "tick": 1, "window_days": 3, "minimum": 25, "maximum": 400}],
		"supplier_directory": [{"seller": farm, "site_id": farm_source, "good": "fiber", "zone": "lyon", "known_to": [works], "available_day": 1}, {"seller": farm, "site_id": farm_source, "good": "grain", "zone": "lyon", "known_to": [works], "available_day": 1}],
		"supplier_search": [{"firm": workshop, "site_id": works, "local_zones": [], "regional_zones": [], "scope_basis": "HOST_SPACE", "allow_wide": true, "delay_days": {"LOCAL": 1, "REGIONAL": 2, "WIDE": 3}, "result_limit": 2, "max_known": 4, "cooldown_days": 3}]
	}
	result["actors"].append({"id": player, "kind": "named", "control": "player", "members": 1, "account_id": FormalPersonalEconomyState.personal_account_id(player), "cash": 120, "stock": stock.call({"bread": 4}), "skill": 1, "daily_need": 2, "needs": {"food": 2, "clothing": 1, "household": 1}, "population_start": 0, "place_id": "place:paris"})
	for group: Dictionary in [{"id": workshop_workers, "members": 2, "start": 0, "place": "place:paris"}, {"id": farm_workers, "members": 2, "start": 2, "place": "place:lyon"}, {"id": soap_workers, "members": 1, "start": 4, "place": "place:paris"}]:
		result["actors"].append({"id": group["id"], "kind": "cohort", "control": "automatic", "members": group["members"], "account_id": "account:" + str(group["id"]).trim_prefix("cohort:"), "cash": 120, "stock": stock.call({"bread": 4}), "skill": 1, "daily_need": 2, "needs": {"food": 2, "clothing": 1, "household": 1}, "population_start": group["start"], "place_id": group["place"]})
	result["firms"] = [
		{"id": farm, "place_id": "place:paris", "account_id": "account:development_farm", "cash": 180, "sites": [
			site.call(farm_source, "place:lyon", ["production", "storage", "sales"], {"grain": 24, "beans": 12, "fiber": 16, "oil": 8}, {"grain": 8, "beans": 6, "fiber": 6, "oil": 4}, {"grain": 2, "beans": 4, "fiber": 3, "oil": 3}, 8, [activity.call("activity:grain", "place:lyon", {"grain": 2}, {}), activity.call("activity:beans", "place:lyon", {"beans": 2}, {}), activity.call("activity:fiber", "place:lyon", {"fiber": 2}, {}), activity.call("activity:oil", "place:lyon", {"oil": 1}, {})], []),
			site.call(farm_store, "place:paris", ["storage", "sales"], {"grain": 4, "beans": 6, "fiber": 4, "oil": 4}, {"grain": 8, "beans": 8, "fiber": 8, "oil": 4}, {"grain": 3, "beans": 5, "fiber": 4, "oil": 4}, 0, [], [])]},
		{"id": workshop, "place_id": "place:paris", "account_id": "account:development_workshop", "cash": 200, "manager": player, "sites": [
			site.call(works, "place:paris", ["production", "storage", "sales"], {"grain": 6, "fiber": 6, "bread": 4, "cloth": 2, "clothes": 2}, {"flour": 2, "bread": 6, "cloth": 2, "clothes": 3}, {"bread": 7, "cloth": 30, "clothes": 90}, 10, [activity.call("activity:mill", "place:paris", {"flour": 2}, {"grain": 1}), activity.call("activity:bakery", "place:paris", {"bread": 2}, {"flour": 1}), activity.call("activity:weave", "place:paris", {"cloth": 1}, {"fiber": 2}), activity.call("activity:sew", "place:paris", {"clothes": 1}, {"cloth": 1})], farm_suppliers),
			site.call(shop, "place:lyon", ["storage", "sales"], {"bread": 4, "clothes": 1, "cloth": 1}, {"bread": 6, "clothes": 2, "cloth": 2, "soap": 2}, {"bread": 8, "clothes": 100, "cloth": 35, "soap": 9}, 0, [], [soap_supplier])]},
		{"id": soap, "place_id": "place:paris", "account_id": "account:development_soap", "cash": 120, "sites": [site.call(soap_works, "place:paris", ["production", "storage", "sales"], {"oil": 4, "soap": 4}, {"soap": 6}, {"soap": 8}, 4, [activity.call("activity:soap", "place:paris", {"soap": 2}, {"oil": 1})], [soap_material])]}
	]
	for job: Dictionary in [{"id": "job:development_workshop", "employer": workshop, "site_id": works, "positions": 2, "place": "place:paris"}, {"id": "job:development_farm", "employer": farm, "site_id": farm_source, "positions": 2, "place": "place:lyon"}, {"id": "job:development_soap", "employer": soap, "site_id": soap_works, "positions": 1, "place": "place:paris"}]:
		job.merge({"skill": 1, "hours": 2, "wage_per_hour": 3, "wage_delay": 1, "notice_delay": 1})
		result["jobs"].append(job)
	for pair: Array in [[workshop_workers, "job:development_workshop"], [farm_workers, "job:development_farm"], [soap_workers, "job:development_soap"]]:
		result["information"].append({"actor": pair[0], "kind": "job", "candidate": pair[1], "delivery_day": 0})
	for pair: Array in [[works, farm_suppliers[0]], [works, farm_suppliers[1]], [shop, soap_supplier], [soap_works, soap_material]]:
		result["information"].append({"actor": pair[0], "kind": "supplier", "candidate": pair[1], "delivery_day": 0})
	for actor: Dictionary in result["actors"]:
		var local: bool = actor["place_id"] == "place:paris"
		var suppliers: Array = [farm + "|beans|" + (farm_store if local else farm_source), workshop + "|bread|" + (works if local else shop), workshop + "|clothes|" + (works if local else shop), workshop + "|cloth|" + (works if local else shop), soap_supplier if local else workshop + "|soap|" + shop]
		for candidate: String in suppliers:
			result["information"].append({"actor": actor["id"], "kind": "supplier", "candidate": candidate, "delivery_day": 0})
	var known: Array = [farm, workshop, soap, player, workshop_workers, farm_workers, soap_workers]
	result["routes"] = [
		{"id": "edge:development_paris_lyon", "from_place_id": "place:paris", "to_place_id": "place:lyon", "capacity": 12, "delay": 2, "carrier": "carrier:development_rail", "freight_per_unit": 1, "known_to": known.duplicate(), "basis": "HOST_LINK", "source_link_id": "rail_paris_lyon"},
		{"id": "edge:development_lyon_paris", "from_place_id": "place:lyon", "to_place_id": "place:paris", "capacity": 12, "delay": 2, "carrier": "carrier:development_rail", "freight_per_unit": 1, "known_to": known.duplicate(), "basis": "HOST_LINK", "source_link_id": "rail_paris_lyon"},
		{"id": "edge:development_lyon_local", "from_place_id": "place:lyon", "to_place_id": "place:lyon", "capacity": 18, "delay": 1, "carrier": "carrier:development_rail", "freight_per_unit": 0, "known_to": known.duplicate(), "basis": "SYNTHETIC"}
	]
	result["transport_paths"] = [{"id": "path:development_lyon_paris_local", "edge_ids": ["edge:development_lyon_paris", "edge:r2_paris_local"], "known_to": [farm, workshop, soap], "known_day": 0}]
	return result

## Limited formal opt-in. Named cash remains the ordinary formal opening cash.
## The three firms and five sites are development assumptions, not historical factories.
static func formal_limited() -> Dictionary:
	var result := multisite()
	result["host_personal_accounts"] = true
	result["actors"][0]["cash"] = 0
	for job: Dictionary in result["jobs"]:
		if job["id"] == "job:development_workshop": job["positions"] = 3
	result["information"].append({"actor": WorldBootstrap.DEFAULT_FORMAL_PERSON_ID, "kind": "job", "candidate": "job:development_workshop", "delivery_day": 0})
	result["information"].append({"actor": WorldBootstrap.DEFAULT_FORMAL_PERSON_ID, "kind": "job", "candidate": "job:development_farm", "delivery_day": 1})
	_install_capital_configuration(result)
	result["personal_storage"] = _development_personal_storage(result)
	_install_commodity_crosswalk(result)
	_install_lifecycle_configuration(result)
	var reserve := "cohort:development:workshop_reserve"
	var zeros := EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(result))
	result["runtime_expansions"] = result.get("runtime_expansions", []) + [{"id": "extension:development:workshop_reserve", "label": "纳入一名工作坊背景人口；零初始资金和库存", "extension": {"actors": [{"id": reserve, "kind": "cohort", "control": "automatic", "members": 1, "account_id": "account:development:workshop_reserve", "cash": 0, "stock": zeros, "skill": 1, "daily_need": 2, "needs": {"food": 2, "clothing": 1, "household": 1}, "population_start": 5, "place_id": "place:paris"}], "jobs": [{"id": "job:development_workshop:reserve", "employer": "firm:development_workshop", "site_id": "site:development_workshop:paris", "positions": 1, "skill": 1, "hours": 2, "place": "place:paris", "wage_per_hour": 3, "wage_delay": 1, "notice_delay": 1}], "information": [{"actor": reserve, "kind": "job", "candidate": "job:development_workshop:reserve", "delivery_day": 1}, {"actor": reserve, "kind": "supplier", "candidate": "firm:development_workshop|bread|site:development_workshop:paris", "delivery_day": 1}, {"actor": reserve, "kind": "supplier", "candidate": "firm:development_workshop|clothes|site:development_workshop:paris", "delivery_day": 1}, {"actor": reserve, "kind": "supplier", "candidate": "firm:development_soap|soap|site:development_soap:paris", "delivery_day": 1}]}}]
	return result

## Explicit passenger permissions for development worlds, separate from freight.
## Minutes, seats, fares and luggage are assumptions; topology is the host's.
static func formal_passenger_routes(world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var account := "account:regional_development_transport" if not world.ledger_state.account("account:regional_development_transport").is_empty() else "account:development_rail"
	for pair: Dictionary in [{"a": "paris", "b": "lyon", "link": "rail_paris_lyon", "minutes": 720}, {"a": "lyon", "b": "marseille", "link": "rail_lyon_marseille", "minutes": 480}, {"a": "port_le_havre", "b": "port_london", "link": "shipping_channel", "minutes": 960}]:
		if world.spatial_catalog.get_link(pair["link"]).is_empty(): continue
		for reverse: bool in [false, true]:
			var origin := "place:"+str(pair["b"] if reverse else pair["a"])
			var destination := "place:"+str(pair["a"] if reverse else pair["b"])
			result.append({"id": "passenger:"+origin.trim_prefix("place:")+":"+destination.trim_prefix("place:"), "from_place_id": origin, "to_place_id": destination, "source_link_id": pair["link"], "minutes": pair["minutes"], "fare": 2, "payee_account_id": account, "seats": 8, "portable_goods": ["beans", "bread", "soap", "clothes", "cloth"], "carry_units": 20, "known_to": world.person_overlay.person_ids(), "public_notice": true, "basis": "DEVELOPMENT_PASSENGER_PERMISSION"})
	return result

## Local posted information is observed only after physical arrival.
static func _notice_only_supplier(settings: Dictionary, candidate: String) -> bool:
	for policy: Dictionary in settings.get("commercial_information",{}).get("npc_policies",[]):
		if policy["kind"]=="GOODS" and candidate==str(policy["firm"])+"|"+str(policy["item"])+"|"+str(policy["site_id"]): return true
	return false

static func formal_arrival_notices(settings: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job: Dictionary in settings.get("jobs", []):
		result.append({"place_id": job["place"], "kind": "job", "candidate": job["id"]})
	for firm: Dictionary in settings.get("firms", []):
		for site: Dictionary in firm.get("sites", []):
			for good: String in site["prices"]:
				if _notice_only_supplier(settings,str(firm["id"])+"|"+good+"|"+str(site["id"])): continue
				result.append({"place_id": site["place_id"], "kind": "supplier", "candidate": str(firm["id"])+"|"+good+"|"+str(site["id"])})
	return result

## A selection is resolved after host population, identities, accounts and places
## exist. Explicit person IDs never materialize a new person. An empty selection
## chooses only already admitted people at the configured operating places.
static func formal_regional_request(person_ids: Array[String] = []) -> Dictionary:
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": regional_template()}

## Separate opt-in selection; does not restore or change any main-menu entry.
static func player_capital_requested() -> bool:
	return OS.get_cmdline_user_args().has("--formal-player-capital-trade") or OS.get_cmdline_user_args().has("--formal-player-capital-trade=seller")

static func formal_stratified_request(person_ids: Array[String] = []) -> Dictionary:
	if OS.get_cmdline_user_args().has("--formal-economy-feedback"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":economy_feedback_regional_template()}
	if player_capital_requested():
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":player_capital_trade_regional_template("seller" if OS.get_cmdline_user_args().has("--formal-player-capital-trade=seller") else "buyer")}
	if OS.get_cmdline_user_args().has("--formal-npc-capital-recirculation"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":npc_capital_recirculation_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-npc-capital-competition"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":npc_capital_competition_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-npc-capital-trade"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":npc_capital_trade_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-capital-transport"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":capital_transport_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-capital-resale"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":capital_resale_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-enterprise-wind-down"): 
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":wind_down_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-labor-market"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":labor_market_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-commercial-information"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":commercial_information_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-retail-market"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":retail_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-building-leases"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":building_lease_regional_template()}
	if OS.get_cmdline_user_args().has("--formal-leases"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":lease_regional_template(OS.get_cmdline_user_args().has("--formal-liquidity-policy"))}
	if OS.get_cmdline_user_args().has("--formal-resident-services"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":resident_service_regional_template(OS.get_cmdline_user_args().has("--formal-liquidity-policy"))}
	if OS.get_cmdline_user_args().has("--formal-services"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":service_regional_template(OS.get_cmdline_user_args().has("--formal-liquidity-policy"))}
	if OS.get_cmdline_user_args().has("--formal-cost-accounting"):
		return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":cost_regional_template(OS.get_cmdline_user_args().has("--formal-liquidity-policy"))}
	if OS.get_cmdline_user_args().has("--formal-liquidity-policy"): return formal_liquidity_request(person_ids)
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": stratified_regional_template()}

static func formal_liquidity_request(person_ids: Array[String] = []) -> Dictionary:
	return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":liquidity_regional_template()}

static func cost_regional_template(with_liquidity: bool = false) -> Dictionary:
	var result:=liquidity_regional_template() if with_liquidity else stratified_regional_template()
	result["case_id"]="FORMAL_DIRECT_COST_REGIONAL_DEVELOPMENT"
	result["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
	for firm: String in ["firm:regional_food","firm:regional_textile","firm:regional_household"]:
		result["cost_accounting"]["npc_policies"].append({"firm":firm,"window_days":7,"rank_production":true,"block_known_loss_investment":true,"basis":"EXPLICIT_DEVELOPMENT_COST_RESPONSE"})
	return result

## Existing organizations, accounts, goods and workers. No new endowment.
static func service_regional_template(with_liquidity: bool=false) -> Dictionary:
	var result:=cost_regional_template(with_liquidity)
	if not result.has("procurement_budgets"): result["procurement_budgets"]=[]
	result["case_id"]="FORMAL_SERVICE_REGIONAL_DEVELOPMENT"
	var client:="firm:regional_upstream"
	var provider:="firm:regional_textile"
	var site:="site:regional_textile:lyon"
	var currency:=FormalLedgerState.DENOMINATION
	result["service_market"]={"facilities":[{"id":"facility:service:lyon_warehouse","provider":provider,"site_id":site,"kind":"STORAGE","capacity":8,"unit":"development_service_storage_unit","good_units":{"beans":1,"grain":1,"fiber":1,"bread":1},"shared_storage_id":"","basis":"EXPLICIT_DEVELOPMENT_SERVICE_FACILITY"},{"id":"facility:service:lyon_repair","provider":provider,"site_id":site,"kind":"REPAIR","capacity":1,"unit":"development_repair_bay","good_units":{},"shared_storage_id":"","basis":"EXPLICIT_DEVELOPMENT_SERVICE_FACILITY"}],"offers":[],"authorities":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_SERVICE_MARKET"}
	var market:=result["service_market"] as Dictionary
	market["offers"].append({"id":"service_offer:lyon_storage","facility_id":"facility:service:lyon_warehouse","kind":"STORAGE","denomination":currency,"price":1,"valid_from":0,"valid_until":60*1440,"known_to":[client,"firm:regional_food"],"notice_minute":0,"job_ids":["job:regional_textile:lyon","job:regional_textile:lyon:support"],"hours_per_day":2,"cancel_rule":"UNSTARTED_REPAIR_OR_STORAGE_RETURN","basis":"EXPLICIT_DEVELOPMENT_SERVICE_OFFER","storage_terms":{"period_minutes":1440,"max_periods":30,"intake_hours":1,"supervision_hours":1,"charge_rule":"CUMULATIVE_UNIT_MINUTES_FLOOR"}})
	market["offers"].append({"id":"service_offer:lyon_repair","facility_id":"facility:service:lyon_repair","kind":"REPAIR","denomination":currency,"price":18,"valid_from":0,"valid_until":60*1440,"known_to":[client,"firm:regional_food"],"notice_minute":0,"job_ids":["job:regional_textile:lyon","job:regional_textile:lyon:support"],"hours_per_day":1,"cancel_rule":"UNSTARTED_REPAIR_OR_STORAGE_RETURN","basis":"EXPLICIT_DEVELOPMENT_SERVICE_OFFER","repair_terms":{"asset_types":["development_shared_production_equipment"],"mode":"ON_SITE_SAME_HOST_PLACE","material_owner":"PROVIDER"}})
	for pair: Array in [[client,"HOST_SELECTED_PLAYER"],["firm:regional_food","firm:regional_food"],[provider,provider]]:
		market["authorities"].append({"id":"service_authority:"+str(pair[0]),"firm":pair[0],"controller":pair[1],"operations":["supply","control"] if pair[0]==provider else ["purchase","control"],"denomination":currency,"limit":200,"start_minute":0,"end_minute":60*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_SERVICE_AUTHORITY"})
	market["npc_policies"].append({"firm":"firm:regional_food","storage_offer":"service_offer:lyon_storage","source_site":"site:regional_food:lyon","good":"bread","trigger_quantity":3,"store_quantity":1,"periods":1,"repair_offer":"service_offer:lyon_repair","cooldown_days":7,"basis":"EXPLICIT_DEVELOPMENT_SERVICE_DEMAND"})
	# Capital's existing supplier notices already include the provider's tools.
	for kind: String in ["storage","repair"]:
		result["procurement_budgets"].append({"id":"budget:service:"+kind,"subject":"organization:development_regional_upstream","root_authority":"service_authority:"+client,"denomination":currency,"category":"service:"+kind,"start_minute":0,"end_minute":60*1440,"limit":64,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	return result

## Same four firms/eight cohorts, no added opening money, food or workers.
## One-hour daily slots are development service assumptions, not historical data.
static func resident_service_regional_template(with_liquidity: bool=false) -> Dictionary:
	var result:=service_regional_template(with_liquidity)
	result["case_id"]="FORMAL_RESIDENT_SERVICE_REGIONAL_DEVELOPMENT"
	var m:=result["service_market"] as Dictionary
	var provider:="firm:regional_food";var site:="site:regional_food:paris"
	var customers: Array[String]=["HOST_SELECTED_PLAYER","cohort:stratified:paris_nonworkers","cohort:stratified:paris_industrial"]
	# These already-employed support workers also supply production. No extra hours.
	var jobs: Array[String]=["job:regional_food:paris:support"] # Explicit dual service qualification for this development offer.
	for kind: String in ["DINING","HAIRCUT"]:
		var id:="facility:service:paris_"+kind.to_lower()
		m["facilities"].append({"id":id,"provider":provider,"site_id":site,"kind":kind,"capacity":2 if kind=="DINING" else 1,"unit":"development_daily_resident_place","good_units":{},"shared_storage_id":"","basis":"EXPLICIT_DEVELOPMENT_SERVICE_FACILITY"})
		m["offers"].append({"id":"service_offer:paris_"+kind.to_lower(),"facility_id":id,"kind":kind,"denomination":FormalLedgerState.DENOMINATION,"price":3 if kind=="DINING" else 2,"valid_from":0,"valid_until":60*1440,"known_to":customers.duplicate(),"notice_minute":0,"job_ids":jobs.duplicate(),"hours_per_day":2 if kind=="DINING" else 1,"cancel_rule":"UNSTARTED_REPAIR_OR_STORAGE_RETURN","basis":"EXPLICIT_DEVELOPMENT_SERVICE_OFFER","resident_terms":{"materials":{"bread":1} if kind=="DINING" else {},"hours_per_unit":1,"need_id":"food" if kind=="DINING" else "grooming","units_per_service":1,"time_basis":"NEXT_DAY_ON_SITE_NO_WORK_SHARE"}})
	for authority: Dictionary in m["authorities"]:
		if authority["firm"]==provider: authority["operations"]=["purchase","supply","control"]
	m["resident_targets"]=[];m["resident_policies"]=[]
	for customer: String in customers:
		m["resident_targets"].append({"customer":customer,"need_id":"grooming","period_days":7,"start_minute":0,"basis":"EXPLICIT_DEVELOPMENT_RESIDENT_SERVICE_TARGET"})
		if customer=="HOST_SELECTED_PLAYER": continue
		m["resident_policies"].append({"customer":customer,"offer_ids":["service_offer:paris_dining","service_offer:paris_haircut"],"quantity_limit":1,"budget_limit":8 if customer.ends_with("nonworkers") else 16,"budget_window_days":7,"priority":"SERVICE_FIRST_KNOWN_LOCAL_WITHIN_BUDGET","basis":"EXPLICIT_DEVELOPMENT_RESIDENT_SERVICE_DEMAND"})
	return result

## Explicit use rights at existing host places; no building genesis, cash or stock.
static func lease_regional_template(with_liquidity:bool=false)->Dictionary:
	var result:=resident_service_regional_template(with_liquidity)
	result["case_id"]="FORMAL_LEASE_REGIONAL_DEVELOPMENT"
	var currency:=FormalLedgerState.DENOMINATION
	var housing:="lease_object:development:paris_housing"
	var commercial:="lease_object:development:paris_food_premises"
	var residents:Array[String]=["HOST_SELECTED_PLAYER","cohort:stratified:paris_nonworkers","cohort:stratified:paris_industrial"]
	result["lease_market"]={"basis":"EXPLICIT_DEVELOPMENT_LEASE_MARKET","objects":[],"offers":[],"authorities":[],"housing_targets":[],"npc_policies":[]}
	var m:=result["lease_market"] as Dictionary
	for kind:String in ["RESIDENTIAL_SPACE","COMMERCIAL_PREMISES"]:
		var id:=housing if kind=="RESIDENTIAL_SPACE" else commercial
		var owner:="firm:regional_textile" if kind=="RESIDENTIAL_SPACE" else "firm:regional_upstream"
		m["objects"].append({"id":id,"place_id":"place:paris","kind":kind,"lessor":owner,"capacity":3 if kind=="RESIDENTIAL_SPACE" else 1,"unit":"development_person_place" if kind=="RESIDENTIAL_SPACE" else "development_exclusive_premises","rights_source":{"id":"development_use_grant:"+id,"holder":owner,"basis":"EXPLICIT_DEVELOPMENT_INITIAL_USE_RIGHT_GRANT","note":"Limited simulated space grant at an admitted place; no historical building or land ownership is inferred."},"capital_asset_id":"","eligible_sites":[] if kind=="RESIDENTIAL_SPACE" else ["site:regional_food:paris"],"valid_from":0,"valid_until":90*1440,"capacity_basis":"DEDICATED_DEVELOPMENT_SPACE_NO_STORAGE_EQUIVALENCE"})
		m["offers"].append({"id":"lease_offer:development:paris_housing" if kind=="RESIDENTIAL_SPACE" else "lease_offer:development:paris_food_premises","object_id":id,"denomination":currency,"rent_per_unit":3 if kind=="RESIDENTIAL_SPACE" else 5,"period_days":2,"max_days":14,"valid_from":0,"valid_until":60*1440,"known_to":residents.duplicate() if kind=="RESIDENTIAL_SPACE" else ["firm:regional_food"],"notice_minute":0,"payment_rule":"FIRST_PERIOD_SECURED_RENT_AFTER_USE_NO_DEPOSIT","cancel_rule":"TENANT_MAY_END_AT_DAILY_BOUNDARY_RETURN_REQUIRED","due_priority":"AFTER_EXISTING_WAGES_AND_DEBT_BEFORE_NEW_PROCUREMENT","billing_rule":"CUMULATIVE_AVAILABLE_UNIT_MINUTES_FLOOR","housing_rule":"LOCAL_AT_DAILY_BOUNDARY"})
	for a:Array in [["firm:regional_textile","firm:regional_textile",["let"]],["firm:regional_upstream","HOST_SELECTED_PLAYER",["let"]],["firm:regional_food","firm:regional_food",["rent","manage"]]]:
		m["authorities"].append({"id":"lease_authority:"+str(a[0]),"firm":a[0],"controller":a[1],"operations":a[2],"denomination":currency,"limit":80,"start_minute":0,"end_minute":60*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_LEASE_AUTHORITY"})
	for customer:String in residents:m["housing_targets"].append({"customer":customer,"basis":"EXPLICIT_DEVELOPMENT_HOUSING_USE_TARGET","initial_housing":"UNSPECIFIED_NOT_A_HOMELESSNESS_CLASSIFICATION"})
	for tenant:String in ["cohort:stratified:paris_nonworkers","firm:regional_food"]:
		m["npc_policies"].append({"tenant":tenant,"offer_ids":["lease_offer:development:paris_housing" if tenant.begins_with("cohort:") else "lease_offer:development:paris_food_premises"],"quantity":2 if tenant.begins_with("cohort:") else 1,"term_days":6,"max_total":24,"priority":"BEFORE_OPTIONAL_SERVICES_AND_GOODS","auto_handover":true,"auto_return_on_end":false,"no_new_if_overdue":true,"basis":"EXPLICIT_DEVELOPMENT_LEASE_DEMAND"})
	result["procurement_budgets"].append({"id":"budget:development:food_premises","subject":"organization:development_regional_food","root_authority":"lease_authority:firm:regional_food","denomination":currency,"category":"lease:commercial_premises","start_minute":0,"end_minute":60*1440,"limit":20,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	return result

## Explicit 60-day development commercial terms. Existing money/stock is unchanged.
static func liquidity_regional_template() -> Dictionary:
	var result := stratified_regional_template()
	result["case_id"]="FORMAL_LIQUIDITY_REGIONAL_DEVELOPMENT"
	var currency := FormalLedgerState.DENOMINATION
	var upstream := "firm:regional_upstream"
	var food := "firm:regional_food"
	var textile := "firm:regional_textile"
	var household := "firm:regional_household"
	result["firm_finance_authorities"]=[]
	for firm: String in [upstream,food,textile,household]:
		result["firm_finance_authorities"].append({"id":"finance:development:"+firm,"firm":firm,"controller":firm,"operations":["offer_credit","accept_credit","repay_loan"],"currency":currency,"limit":100,"start_minute":0,"end_minute":90*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_FIRM_FINANCE_AUTHORITY"})
	result["firm_finance_authorities"].append({"id":"finance:development:player","firm":upstream,"controller":"HOST_SELECTED_PLAYER","operations":["offer_credit","accept_credit","repay_loan"],"currency":currency,"limit":100,"start_minute":0,"end_minute":90*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_FIRM_FINANCE_AUTHORITY"})
	for authority: Dictionary in result["firm_finance_authorities"]: authority["borrow_limits"]={"daily_principal":80,"max_debt":100,"max_interest":5}
	result["credit_offers"]=[{"lender":upstream,"borrower":textile,"principal_limit":80,"denomination":currency,"interest":3,"duration_days":8,"valid_days":60,"requires_job":false},{"lender":upstream,"borrower":food,"principal_limit":60,"denomination":currency,"interest":2,"duration_days":8,"valid_days":60,"requires_job":false}]
	result["npc_finance"]=[]
	result["liquidity_policies"]=[]
	for firm: String in [food,textile,household]:
		result["npc_finance"].append({"actor":firm,"repay_due":true,"allow_exchange":false,"cash_floors":{currency:5},"borrow_limits":{currency:{"daily_principal":80,"max_debt":100,"max_interest":5}},"fx_limits":{}})
		result["liquidity_policies"].append({"firm":firm,"currency":currency,"cash_floor":5,"protect_due_wages":true,"finance_due_wages":true,"pause_after_days":5,"recover_cash":30,"wind_down_after_days":20,"pause_investment":true,"basis":"EXPLICIT_DEVELOPMENT_LIQUIDITY_POLICY"})
	result["labor_response_policies"]=[{"actor":"cohort:stratified:lyon_skilled","arrears_days":7,"basis":"EXPLICIT_DEVELOPMENT_LABOR_RESPONSE"}]
	result["procurement_budgets"]=[]
	for w: Dictionary in [{"id":"first","a":0,"b":20,"limit":35},{"id":"second","a":20,"b":60,"limit":55}]:
		result["procurement_budgets"].append({"id":"budget:development:food_grain:"+w["id"],"subject":"organization:development_regional_food","root_authority":"development:food_grain_authority","denomination":currency,"category":"goods:grain","start_minute":w["a"]*1440,"end_minute":w["b"]*1440,"limit":w["limit"],"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	# Existing enterprises explicitly perform transport with their existing workers.
	# No new cash account, worker or Spatial connection is created.
	var unit := "development_link_payload_unit"
	for good: Dictionary in result["goods"]: good["unit_weight"]={"numerator":1,"denominator":1,"unit":unit,"basis":"EXPLICIT_DEVELOPMENT_SHARED_LINK_LOAD_ASSUMPTION"}
	var starts: Array[int]=[]
	for date: int in range(0,61):
		starts.append(date*1440);starts.append(date*1440+720)
	result["transport_facilities"]=[]
	for site: String in ["site:regional_upstream:lyon","site:regional_food:paris"]:
		for kind: String in ["HANDLING_THROUGHPUT","BERTH_OCCUPANCY","STORAGE_OCCUPANCY"]:
			var windows: Array[Dictionary]=[]
			if kind=="HANDLING_THROUGHPUT":
				for start: int in starts:
					windows.append({"start_minute":start,"end_minute":start+60,"capacity":8})
			else: windows.append({"start_minute":0,"end_minute":90*1440,"capacity":64 if kind=="STORAGE_OCCUPANCY" else 8})
			result["transport_facilities"].append({"id":"facility:development:"+site+":"+kind,"site_id":site,"kind":kind,"unit":unit,"windows":windows,"basis":"EXPLICIT_DEVELOPMENT_TRANSPORT_FACILITY"})
	result["shared_transport"]=[]
	for route: Dictionary in result["routes"]:
		if route.get("source_link_id")!="rail_paris_lyon": continue
		var origin := "site:regional_food:paris" if route["from_place_id"]=="place:paris" else "site:regional_upstream:lyon"
		var destination := "site:regional_upstream:lyon" if route["to_place_id"]=="place:lyon" else "site:regional_food:paris"
		route["carrier"]=food if route["from_place_id"]=="place:paris" else upstream
		var nodes := {"unloading_minutes":60,"unloading_hours_per_unit":1}
		for k: String in ["origin_handling","origin_berth","destination_handling","destination_berth","destination_storage"]:
			var site := origin if k.begins_with("origin") else destination
			var kind := "HANDLING_THROUGHPUT" if k.ends_with("handling") else "BERTH_OCCUPANCY" if k.ends_with("berth") else "STORAGE_OCCUPANCY"
			nodes[k]="facility:development:"+site+":"+kind
		result["shared_transport"].append({"edge_id":route["id"],"source_link_id":"rail_paris_lyon","entry_minutes":starts.duplicate(),"weight_unit":unit,"vehicle_id":"vehicle:development:"+route["carrier"],"vehicle_payload":8,"handling_site":origin,"handling_hours_per_unit":1,"basis":"EXPLICIT_DEVELOPMENT_SHARED_LINK_LOAD_ASSUMPTION","window_minutes":60,"loading_minutes":60,"travel_minutes":660,"vehicle_hold_minutes":780,"node_resources":nodes,"legacy_node_limit_basis":"EXPLICIT_DAILY_BUSINESS_QUANTITY_LIMIT"})
	return result

## Eight finite strata / 72 background people, using the same firms, goods and
## routes. Counts, occupations, rates and money are development assumptions.
## The original regional total of 260 cash and eight breads is preserved.
static func stratified_regional_template() -> Dictionary:
	var result := regional_template()
	result["case_id"] = "FORMAL_STRATIFIED_REGIONAL_DEVELOPMENT"
	result["management_scope"]["id"] = "scope:stratified_regional_development"
	var old: Dictionary = {}
	var information: Dictionary = {}
	for actor: Dictionary in result["actors"]:
		old[actor["id"]] = actor
		information[actor["id"]] = []
	var retained: Array[Dictionary] = []
	for row: Dictionary in result["information"]:
		if old.has(row["actor"]): information[row["actor"]].append(row)
		else: retained.append(row)
	var groups: Array[Dictionary] = [
		{"source": "cohort:regional:paris_food", "id": "cohort:stratified:paris_industrial", "members": 18, "labor": 12, "cash": 55, "bread": 2, "occupation": "food_work", "label": "食品劳动人口", "food": 2, "household_n": 1, "household_d": 2},
		{"source": "cohort:regional:paris_food", "id": "cohort:stratified:paris_nonworkers", "members": 6, "labor": 0, "cash": 15, "bread": 0, "occupation": "nonworking", "label": "非劳动人口", "food": 1, "household_n": 1, "household_d": 3},
		{"source": "cohort:regional:lyon_upstream", "id": "cohort:stratified:lyon_primary", "members": 16, "labor": 10, "cash": 60, "bread": 2, "occupation": "primary_work", "label": "原料劳动人口", "food": 2, "household_n": 1, "household_d": 3},
		{"source": "cohort:regional:lyon_upstream", "id": "cohort:stratified:lyon_jobseekers", "members": 8, "labor": 8, "cash": 0, "bread": 0, "occupation": "primary_work", "label": "无储蓄求职人口", "food": 2, "household_n": 1, "household_d": 4},
		{"source": "cohort:regional:lyon_textile", "id": "cohort:stratified:lyon_skilled", "members": 8, "labor": 6, "cash": 70, "bread": 2, "occupation": "textile_work", "label": "纺织技能人口", "food": 2, "household_n": 1, "household_d": 1},
		{"source": "cohort:regional:lyon_textile", "id": "cohort:stratified:lyon_lowsavings", "members": 6, "labor": 4, "cash": 10, "bread": 0, "occupation": "textile_work", "label": "低储蓄劳动人口", "food": 2, "household_n": 1, "household_d": 3},
		{"source": "cohort:regional:marseille_household", "id": "cohort:stratified:marseille_industrial", "members": 6, "labor": 4, "cash": 40, "bread": 2, "occupation": "household_work", "label": "日用品劳动人口", "food": 2, "household_n": 1, "household_d": 2},
		{"source": "cohort:regional:marseille_household", "id": "cohort:stratified:marseille_nonworkers", "members": 4, "labor": 0, "cash": 10, "bread": 0, "occupation": "nonworking", "label": "非劳动人口", "food": 1, "household_n": 1, "household_d": 4}]
	var actors: Array[Dictionary] = []
	var replacements: Dictionary = {}
	var next_population_start: int = 0
	# A second real job at the same factory permits disjoint worker allocations.
	# Its finite positions and pay are not copies of the complete old labor pool.
	var extra_jobs: Dictionary = {}
	for job: Dictionary in result["jobs"].duplicate(true):
		var extra := job.duplicate(true)
		extra["id"] = str(job["id"])+":support"
		extra["positions"] = 1
		extra["hours"] = 1
		extra["wage_per_hour"] = 2
		extra["skill"] = 1
		if job["employer"] == "firm:regional_upstream": job["wage_per_hour"] = 2
		if job["employer"] == "firm:regional_textile":
			job["skill"] = 2
			job["wage_per_hour"] = 4
		for original: Dictionary in result["jobs"]:
			if original["id"] == job["id"]:
				original["skill"] = job["skill"]
				original["wage_per_hour"] = job["wage_per_hour"]
		result["jobs"].append(extra)
		extra_jobs[job["id"]] = extra["id"]
	for group: Dictionary in groups:
		var source := old[group["source"]] as Dictionary
		var actor := source.duplicate(true)
		var id := str(group["id"])
		var place := str(source["place_id"])
		actor.merge({"id": id, "members": group["members"], "account_id": "account:"+id.trim_prefix("cohort:"), "cash": group["cash"], "stock": EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(result)), "population_start": next_population_start, "daily_need": group["food"], "needs": {"food": group["food"], "clothing": 1, "household": 1}}, true)
		actor["stock"]["bread"] = group["bread"]
		if group["id"] == "cohort:stratified:lyon_skilled": actor["skill"] = 2
		next_population_start += int(actor["members"])
		var jobs: Array[String] = []
		for notice: Dictionary in information[group["source"]]:
			var row := notice.duplicate(true)
			row["actor"] = id
			if row["kind"] == "job":
				if int(group["labor"]) == 0: continue
				jobs.append(row["candidate"])
				jobs.append(extra_jobs[row["candidate"]])
				var extra := row.duplicate(true)
				extra["candidate"] = extra_jobs[row["candidate"]]
				retained.append(extra)
			retained.append(row)
		actor["cohort_profile"] = {"stratum_id": id, "label": group["label"], "occupation": group["occupation"], "labor_members": group["labor"], "max_jobs": 2, "job_ids": jobs, "job_search_days": 3, "basis": "EXPLICIT_DEVELOPMENT_COHORT_STRATUM", "need_rates": {"household": {"numerator": group["household_n"], "denominator": group["household_d"]}}, "category_priority": ["food", "household", "clothing"], "goods_preference": {"food": ["beans", "bread"] if group["occupation"] == "primary_work" else ["bread", "beans"]}}
		actors.append(actor)
		if not replacements.has(group["source"]): replacements[group["source"]] = []
		replacements[group["source"]].append(id)
	result["actors"] = actors
	result["information"] = retained
	result["development_organizations"]=[]
	for firm: Dictionary in result["firms"]:
		var organization := "organization:development_"+str(firm["id"]).trim_prefix("firm:")
		firm["host_organization_id"]=organization
		result["development_organizations"].append({"organization_id":organization,"firm_id":firm["id"],"basis":"EXPLICIT_DEVELOPMENT_COMMERCIAL_ORGANIZATION"})
	for template: Dictionary in result["capital_investment"]["templates"]:
		if template["kind"]=="EXPAND":
			result["capital_investment"]["npc_policies"].append({"template_id":template["id"],"window_days":3,"minimum_pressure":4,"minimum_utilization_percent":50,"cooldown_days":10})
	for field: String in ["routes", "transport_paths"]:
		for row: Dictionary in result.get(field, []):
			var known: Array = []
			for id: String in row["known_to"]:
				if replacements.has(id): known.append_array(replacements[id])
				else: known.append(id)
			row["known_to"] = known
	return result

static func resolve_regional(world: WorldState, request: Dictionary) -> Dictionary:
	if not FormalLedgerState.exact_fields(request, ["format", "person_ids", "select_people_at_sites", "configuration"]) or not request.get("person_ids") is Array or not request.get("select_people_at_sites") is bool or not request.get("configuration") is Dictionary:
		return {"error": "Invalid regional host selection"}
	var result: Dictionary = request["configuration"].duplicate(true)
	if not EconomySliceConfig.valid(result) or not result.get("host_personal_accounts", false):
		return {"error": "Regional business configuration must be a valid host-account R2 configuration"}
	if request["select_people_at_sites"] and not request["person_ids"].is_empty():
		return {"error": "Automatic host selection cannot also declare an explicit person list"}
	if not result.get("actors") is Array or not result.get("firms") is Array or not result.get("jobs") is Array or not result.get("information") is Array:
		return {"error": "Regional selection requires an R2 business configuration"}
	var places: Dictionary = {}
	for firm: Dictionary in result["firms"]:
		for site: Dictionary in firm.get("sites", []):
			places[site["place_id"]] = true
	var selected: Array[String] = []
	if request["select_people_at_sites"]:
		for person: String in world.person_overlay.person_ids():
			if places.has(str(world.person_overlay.person(person).get("current_place_id", ""))) and world.person_overlay.is_alive(person): selected.append(person)
	else:
		for id: Variant in request["person_ids"]:
			if not id is String or selected.has(id): return {"error": "Invalid or duplicate selected person"}
			selected.append(id)
	selected.sort()
	var corporate_manager: String=""
	if result.has("corporate_decisions"):
		var candidates: Array[String]=world.person_overlay.person_ids()
		candidates.sort()
		for person: String in candidates:
			if person!=world.player_state.player_id() and world.person_overlay.is_alive(person) and not world.personal_economy_state.account_id_for_person(person).is_empty():
				corporate_manager=person;break
		if corporate_manager.is_empty():return {"error":"No admitted living NPC manager with an original personal account"}
		if corporate_manager not in selected:selected.append(corporate_manager);selected.sort()
		result["corporate_decisions"]["controller"]=corporate_manager
	var declared: Dictionary = {}
	for actor: Dictionary in result["actors"]: declared[actor["id"]] = true
	var needs: Dictionary = {}
	for category: String in EconomySliceConfig.categories(result): needs[category] = 2 if category == "food" else 1
	for id: String in selected:
		var person := world.person_overlay.person(id)
		if person.is_empty() or not world.person_overlay.is_alive(id) or world.personal_economy_state.account_id_for_person(id).is_empty():
			return {"error": "Selected person has no admitted host identity/account: " + id}
		if declared.has(id): continue # Preserve the explicit person's needs and knowledge.
		var place := str(person["current_place_id"])
		result["actors"].append({"id": id, "kind": "named", "control": "player" if id == world.player_state.player_id() else "automatic", "members": 1, "account_id": world.personal_economy_state.account_id_for_person(id), "cash": 0, "stock": EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(result)), "skill": 1, "daily_need": int(needs.get("food", 0)), "needs": needs.duplicate(), "population_start": 0, "place_id": place, "population_unit_id": world.population_state.unit_for_person(id)})
		# Initial knowledge is local and explicitly limited, not a national scan
		# performed by the consumer AI. Later knowledge uses normal messages.
		var counts: Dictionary = {}
		for firm: Dictionary in result["firms"]:
			for site: Dictionary in firm.get("sites", []):
				if site["place_id"] != place: continue
				for good: String in site["prices"]:
					if _notice_only_supplier(result,str(firm["id"])+"|"+good+"|"+str(site["id"])): continue
					if int(counts.get(good, 0)) >= 3: continue
					result["information"].append({"actor": id, "kind": "supplier", "candidate": str(firm["id"]) + "|" + good + "|" + str(site["id"]), "delivery_day": 0})
					counts[good] = int(counts.get(good, 0)) + 1
		for job: Dictionary in result["jobs"]:
			if id!=corporate_manager and job["place"] == place: result["information"].append({"actor": id, "kind": "job", "candidate": job["id"], "delivery_day": 0})
	# Same-place delivery edges are local knowledge, not commuting permission.
	for route: Dictionary in result.get("routes", []):
		if route["from_place_id"] != route["to_place_id"]: continue
		for id: String in selected:
			if str(world.person_overlay.person(id)["current_place_id"]) == route["from_place_id"] and not route["known_to"].has(id): route["known_to"].append(id)
	# Local paths are known by same-place delivery. Cross-region routes remain
	# known only to their declared businesses/cohorts; selecting a person adds
	# no national transport knowledge or hidden supplier knowledge.
	# One explicitly selected developer manager can arrange bounded admissions.
	if selected.has(world.player_state.player_id()) and not result["firms"].is_empty():
		result["firms"][0]["manager"] = corporate_manager if not corporate_manager.is_empty() else world.player_state.player_id()
	if result.has("equity_call_market"):
		var player_id: String=world.player_state.player_id()
		for asset: Dictionary in result.get("assets",[]):
			if asset["holders"].has("HOST_SELECTED_PLAYER"):
				asset["holders"][player_id]=asset["holders"]["HOST_SELECTED_PLAYER"]
				asset["holders"].erase("HOST_SELECTED_PLAYER")
			if asset["known_to"].has("HOST_SELECTED_PLAYER"):
				asset["known_to"].erase("HOST_SELECTED_PLAYER");asset["known_to"].append(player_id)
		for mandate: Dictionary in result["equity_call_market"]["participants"]:
			if mandate["actor"]=="HOST_SELECTED_PLAYER": mandate["actor"]=player_id
	for program_key: String in ["equity_primary","equity_distribution"]:
		if not result.has(program_key): continue
		var program: Dictionary=result[program_key]
		if program["controller"]=="HOST_SELECTED_PLAYER": program["controller"]=corporate_manager if not corporate_manager.is_empty() else world.player_state.player_id()
		if program["consenting_holders"].has("HOST_SELECTED_PLAYER"):
			program["consenting_holders"].erase("HOST_SELECTED_PLAYER");program["consenting_holders"].append(world.player_state.player_id())
	if not corporate_manager.is_empty():
		for family: String in ["capital_resale","service_market","lease_market"]:
			for authority: Dictionary in result.get(family,{}).get("authorities",[]):
				if authority["firm"]==result["corporate_decisions"]["issuer"] and authority["controller"]=="HOST_SELECTED_PLAYER":authority["controller"]=corporate_manager
	for authority: Dictionary in result.get("firm_finance_authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
	for authority: Dictionary in result.get("service_market",{}).get("authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
	for offer: Dictionary in result.get("service_market",{}).get("offers",[]):
		var known: Array=offer["known_to"]
		if known.has("HOST_SELECTED_PLAYER"):
			known.erase("HOST_SELECTED_PLAYER")
			if selected.has(world.player_state.player_id()): known.append(world.player_state.player_id())
	for authority: Dictionary in result.get("capital_resale",{}).get("authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
	for authority: Dictionary in result.get("wind_down",{}).get("authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
	for authority: Dictionary in result.get("labor_market",{}).get("authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
	for rule: Dictionary in result.get("labor_market",{}).get("job_rules",[]):
		if rule["recipients"].has("HOST_SELECTED_PLAYER"):
			rule["recipients"].erase("HOST_SELECTED_PLAYER")
			if selected.has(world.player_state.player_id()): rule["recipients"].append(world.player_state.player_id())
	for channel: Dictionary in result.get("commercial_information",{}).get("channels",[]):
		if channel["recipients"].has("HOST_SELECTED_PLAYER"):
			var index: int=channel["recipients"].find("HOST_SELECTED_PLAYER")
			if selected.has(world.player_state.player_id()): channel["recipients"][index]=world.player_state.player_id()
			else: channel["recipients"].remove_at(index)
			channel["recipient_limit"]=mini(int(channel["recipient_limit"]),channel["recipients"].size())
	var resident_targets: Array[Dictionary]=[]
	for target: Dictionary in result.get("service_market",{}).get("resident_targets",[]):
		if target["customer"]=="HOST_SELECTED_PLAYER":
			if not selected.has(world.player_state.player_id()): continue
			target["customer"]=world.player_state.player_id()
		resident_targets.append(target)
	if result.get("service_market",{}).has("resident_targets"): result["service_market"]["resident_targets"]=resident_targets
	for template: Dictionary in result.get("capital_investment",{}).get("templates",[]):
		if not template.has("building"):continue
		var building:=template["building"] as Dictionary
		if building["permit"]["controller"]=="HOST_SELECTED_PLAYER":building["permit"]["controller"]=world.player_state.player_id()
		var known:Array=building["offer"]["known_to"]
		if known.has("HOST_SELECTED_PLAYER"):
			known.erase("HOST_SELECTED_PLAYER")
			if selected.has(world.player_state.player_id()):known.append(world.player_state.player_id())
	for authority: Dictionary in result.get("lease_market",{}).get("authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
	for offer: Dictionary in result.get("lease_market",{}).get("offers",[]):
		if offer["known_to"].has("HOST_SELECTED_PLAYER"):
			offer["known_to"].erase("HOST_SELECTED_PLAYER")
			if selected.has(world.player_state.player_id()): offer["known_to"].append(world.player_state.player_id())
	var housing_targets: Array[Dictionary]=[]
	for target: Dictionary in result.get("lease_market",{}).get("housing_targets",[]):
		if target["customer"]=="HOST_SELECTED_PLAYER":
			if not selected.has(world.player_state.player_id()): continue
			target["customer"]=world.player_state.player_id()
		housing_targets.append(target)
	if result.get("lease_market",{}).has("housing_targets"): result["lease_market"]["housing_targets"]=housing_targets
	if not result.has("personal_storage"): result["personal_storage"] = _development_personal_storage(result)
	if not result.has("commodity_mappings"): _install_commodity_crosswalk(result)
	_install_lifecycle_configuration(result)
	if result["case_id"] == "FORMAL_STRATIFIED_REGIONAL_DEVELOPMENT":
		result["place_population_bindings"] = formal_residence_place_bindings(world)
		result["residence_permissions"] = formal_residence_permissions(world, result)
	if not result.has("runtime_expansions"):
		result["runtime_expansions"] = _regional_runtime_options(world, result)
	elif result["runtime_expansions"].size() == 1 and result["runtime_expansions"][0]["id"] == "expansion:development_capital_annex":
		result["runtime_expansions"].append_array(_regional_runtime_options(world, result))
	return {"configuration": result}

## Four distinct development businesses in three existing map places. Callers
## may replace firms/sites/jobs/cohorts/routes using the ordinary R2 structures.
## No array index participates in an account, actor, firm or facility identity.
static func regional_template() -> Dictionary:
	var goods: Array[String] = ["beans", "bread", "clothes", "fiber", "flour", "grain", "oil", "soap"]
	var stock := func(values: Dictionary) -> Dictionary:
		var row := EconomySliceConfig.zero_stock(goods)
		row.merge(values, true)
		return row
	var activity := func(id: String, place: String, outputs: Dictionary, materials: Dictionary) -> Dictionary:
		return {"id": id, "place_id": place, "outputs": outputs, "materials": stock.call(materials), "hours": 1, "capacity_units": 1, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION"}
	var site := func(id: String, place: String, inventory: Dictionary, targets: Dictionary, prices: Dictionary, capacity: int, activities: Array, suppliers: Array) -> Dictionary:
		return {"id": id, "place_id": place, "roles": ["production", "storage", "sales"] if capacity > 0 else ["storage", "sales"], "stock": stock.call(inventory), "targets": stock.call(targets), "prices": prices, "capacity": capacity, "activities": activities, "suppliers": suppliers, "enabled": true, "production_enabled": true, "accepting_business": true, "basis": "DEVELOPMENT_CONFIGURATION", "coordination_delay": 1}
	var upstream := "firm:regional_upstream"
	var food := "firm:regional_food"
	var textile := "firm:regional_textile"
	var household := "firm:regional_household"
	var farm := "site:regional_upstream:lyon"
	var bakery := "site:regional_food:paris"
	var food_store := "site:regional_food:lyon"
	var weave := "site:regional_textile:lyon"
	var coast_store := "site:regional_textile:marseille"
	var soap := "site:regional_household:marseille"
	var grain := upstream + "|grain|" + farm
	var fiber := upstream + "|fiber|" + farm
	var oil := upstream + "|oil|" + farm
	var result := {
		"format": "R2", "case_id": "FORMAL_REGIONAL_DEVELOPMENT", "host_personal_accounts": true,
		"management_scope": {"id": "scope:regional_development", "identity_basis": "HOST_WORLD", "business_basis": "DEVELOPMENT_CONFIGURATION", "statistics_visibility": "PUBLIC_AGGREGATES"},
		"stock_horizon": 2, "production_enabled": true, "player_choice": "substitute",
		"need_categories": [{"id": "food", "mode": "flow", "priority": 0}, {"id": "clothing", "mode": "durable", "priority": 1}, {"id": "household", "mode": "flow", "priority": 2}],
		"goods": [{"id": "grain", "needs": {}}, {"id": "beans", "needs": {"food": 2}}, {"id": "flour", "needs": {}}, {"id": "bread", "needs": {"food": 1}}, {"id": "fiber", "needs": {}}, {"id": "clothes", "needs": {"clothing": 2}}, {"id": "oil", "needs": {}}, {"id": "soap", "needs": {"household": 2}}],
		"actors": [], "firms": [], "jobs": [], "information": [],
		"route": {"id": "edge:regional_local:paris", "place_id": "place:paris", "capacity": 16, "delay": 1, "basis": "SYNTHETIC"},
		"carriers": [{"id": "carrier:regional_development", "place_id": "place:lyon", "account_id": "account:regional_development_transport", "cash": 0}],
		"transport_nodes": [{"place_id": "place:paris", "capacity": 16}, {"place_id": "place:lyon", "capacity": 18}, {"place_id": "place:marseille", "capacity": 12}],
		"firm_operations": [], "routes": [], "transport_paths": [], "price_policies": [],
		"supplier_directory": [{"seller": food, "site_id": food_store, "good": "bread", "zone": "rhone_valley", "known_to": [coast_store], "available_day": 1}],
		"supplier_search": [{"firm": textile, "site_id": coast_store, "local_zones": [], "regional_zones": [], "scope_basis": "HOST_SPACE", "allow_wide": true, "delay_days": {"LOCAL": 1, "REGIONAL": 2, "WIDE": 3}, "result_limit": 2, "max_known": 4, "cooldown_days": 3}]
	}
	result["firms"] = [
		{"id": upstream, "place_id": "place:lyon", "account_id": "account:regional_upstream", "cash": 220, "sites": [site.call(farm, "place:lyon", {"grain": 18, "beans": 10, "fiber": 12, "oil": 8}, {"grain": 8, "beans": 4, "fiber": 6, "oil": 4}, {"grain": 3, "beans": 5, "fiber": 4, "oil": 4}, 9, [activity.call("activity:regional_grain", "place:lyon", {"grain": 2}, {}), activity.call("activity:regional_beans", "place:lyon", {"beans": 2}, {}), activity.call("activity:regional_fiber", "place:lyon", {"fiber": 2}, {}), activity.call("activity:regional_oil", "place:lyon", {"oil": 1}, {})], [])]},
		{"id": food, "place_id": "place:paris", "account_id": "account:regional_food", "cash": 170, "sites": [site.call(bakery, "place:paris", {"grain": 6, "bread": 6}, {"flour": 3, "bread": 8}, {"bread": 7}, 7, [activity.call("activity:regional_mill", "place:paris", {"flour": 2}, {"grain": 1}), activity.call("activity:regional_bread", "place:paris", {"bread": 2}, {"flour": 1})], [grain]), site.call(food_store, "place:lyon", {"bread": 3}, {"bread": 5, "clothes": 2, "soap": 3}, {"bread": 8, "clothes": 44, "soap": 9}, 0, [], [textile+"|clothes|"+weave, household+"|soap|"+soap])]},
		{"id": textile, "place_id": "place:lyon", "account_id": "account:regional_textile", "cash": 140, "sites": [site.call(weave, "place:lyon", {"fiber": 8, "clothes": 4, "bread": 3}, {"clothes": 5, "bread": 4, "soap": 2}, {"clothes": 40, "bread": 9, "soap": 10}, 5, [activity.call("activity:regional_clothes", "place:lyon", {"clothes": 1}, {"fiber": 2})], [fiber, food+"|bread|"+bakery, household+"|soap|"+soap]), site.call(coast_store, "place:marseille", {"clothes": 2, "bread": 4}, {"clothes": 3, "bread": 5}, {"clothes": 48, "bread": 10}, 0, [], [food+"|bread|"+bakery])]},
		{"id": household, "place_id": "place:marseille", "account_id": "account:regional_household", "cash": 110, "sites": [site.call(soap, "place:marseille", {"oil": 4, "soap": 5}, {"soap": 5}, {"soap": 8}, 4, [activity.call("activity:regional_soap", "place:marseille", {"soap": 2}, {"oil": 1})], [oil])]}
	]
	# A sales branch in Paris supplies all categories locally without duplicating
	# a factory's whole inventory. Its finite stock must be replenished by orders.
	for firm: Dictionary in result["firms"]:
		if firm["id"] == textile: firm["sites"].append(site.call("site:regional_textile:paris", "place:paris", {"clothes": 2, "soap": 2}, {"clothes": 3, "soap": 3}, {"clothes": 45, "soap": 9}, 0, [], [household+"|soap|"+soap]))
	var groups: Array[Dictionary] = [
		{"id": "cohort:regional:paris_food", "place": "place:paris", "start": 0, "members": 2, "cash": 70, "site": bakery, "firm": food},
		{"id": "cohort:regional:lyon_upstream", "place": "place:lyon", "start": 2, "members": 2, "cash": 60, "site": farm, "firm": upstream},
		{"id": "cohort:regional:lyon_textile", "place": "place:lyon", "start": 4, "members": 2, "cash": 80, "site": weave, "firm": textile},
		{"id": "cohort:regional:marseille_household", "place": "place:marseille", "start": 6, "members": 1, "cash": 50, "site": soap, "firm": household}]
	for group: Dictionary in groups:
		var id := str(group["id"])
		result["actors"].append({"id": id, "kind": "cohort", "control": "automatic", "members": group["members"], "account_id": "account:"+id.trim_prefix("cohort:"), "cash": group["cash"], "stock": stock.call({"bread": 2}), "skill": 1, "daily_need": 2, "needs": {"food": 2, "clothing": 1, "household": 1}, "population_start": group["start"], "place_id": group["place"]})
		var job := "job:"+str(group["site"]).trim_prefix("site:")
		result["jobs"].append({"id": job, "employer": group["firm"], "site_id": group["site"], "positions": int(group["members"])+1, "skill": 1, "hours": 2, "place": group["place"], "wage_per_hour": 3, "wage_delay": 1, "notice_delay": 1})
		result["information"].append({"actor": id, "kind": "job", "candidate": job, "delivery_day": 0})
		for firm: Dictionary in result["firms"]:
			for unit: Dictionary in firm["sites"]:
				if unit["place_id"] != group["place"]: continue
				for good: String in unit["prices"]:
					result["information"].append({"actor": id, "kind": "supplier", "candidate": str(firm["id"])+"|"+good+"|"+str(unit["id"]), "delivery_day": 0})
	for firm: Dictionary in result["firms"]:
		result["firm_operations"].append({"firm": firm["id"], "planning_horizon": 4, "buffer_days": 1, "demand_window": 3, "manage_jobs": true})
		for unit: Dictionary in firm["sites"]:
			for supplier: String in unit["suppliers"]:
				result["information"].append({"actor": unit["id"], "kind": "supplier", "candidate": supplier, "delivery_day": 0})
	var known: Array = [upstream, food, textile, household]
	for group: Dictionary in groups: known.append(group["id"])
	for place: String in ["lyon", "marseille"]:
		result["routes"].append({"id": "edge:regional_local:"+place, "from_place_id": "place:"+place, "to_place_id": "place:"+place, "capacity": 18 if place=="lyon" else 12, "delay": 1, "carrier": "carrier:regional_development", "freight_per_unit": 0, "known_to": known.duplicate(), "basis": "SYNTHETIC"})
	for link: Dictionary in [{"a": "paris", "b": "lyon", "source": "rail_paris_lyon", "capacity": 10, "delay": 2}, {"a": "lyon", "b": "marseille", "source": "rail_lyon_marseille", "capacity": 6, "delay": 2}]:
		for pair: Array in [[link["a"],link["b"]],[link["b"],link["a"]]]:
			result["routes"].append({"id": "edge:regional:"+str(pair[0])+":"+str(pair[1]), "from_place_id": "place:"+str(pair[0]), "to_place_id": "place:"+str(pair[1]), "capacity": link["capacity"], "delay": link["delay"], "carrier": "carrier:regional_development", "freight_per_unit": 1, "known_to": known.duplicate(), "basis": "HOST_LINK", "source_link_id": link["source"]})
	result["transport_paths"] = [{"id": "path:regional:paris:marseille", "edge_ids": ["edge:regional:paris:lyon", "edge:regional:lyon:marseille"], "known_to": known.duplicate(), "known_day": 0}, {"id": "path:regional:marseille:paris", "edge_ids": ["edge:regional:marseille:lyon", "edge:regional:lyon:paris"], "known_to": known.duplicate(), "known_day": 0}]
	result["price_policies"] = [{"firm": textile, "site_id": coast_store, "good": "clothes", "mode": "N3", "tick": 1, "window_days": 3, "minimum": 25, "maximum": 120}]
	_install_capital_configuration(result)
	return result

## Bounded choices prepared from existing host places and people. Selecting one
## only queues future responsibility; it creates no opening money or goods.
static func _regional_runtime_options(world: WorldState, settings: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var announcement := _managed_freight_announcement(settings, world.player_state.player_id())
	if not announcement.is_empty(): result.append(announcement)
	var spec := EconomySliceConfig.normalize(settings, world.person_overlay.person_ids())
	var starts: Dictionary = {}
	for actor: Dictionary in spec["actors"].values():
		if actor["kind"] != "cohort": continue
		var unit := world.population_state.unit_for_place(actor["place_id"])
		starts[unit] = maxi(int(starts.get(unit, 0)), int(actor["population_start"])+int(actor["members"]))
	for firm: Dictionary in settings["firms"]:
		if result.size() >= 12: break
		if firm.get("manager", firm["id"]) != world.player_state.player_id(): continue
		var base := (firm["sites"][0] as Dictionary)
		var place := str(base["place_id"])
		var unit := world.population_state.unit_for_place(place)
		var id := "cohort:runtime:"+str(firm["id"]).trim_prefix("firm:")+":"+place.trim_prefix("place:")
		var needs: Dictionary = {}
		for category: String in spec["categories"]: needs[category] = 2 if category == "food" else 1
		var actor := {"id": id, "kind": "cohort", "control": "automatic", "members": 1, "account_id": "account:"+id.trim_prefix("cohort:"), "cash": 0, "stock": EconomySliceConfig.zero_stock(spec["good_ids"]), "skill": 1, "daily_need": int(needs.get("food", 0)), "needs": needs, "population_start": int(starts.get(unit, 0)), "place_id": place, "population_unit_id": unit}
		var extension := _runtime_subject_extension(settings, actor, firm["id"], base["id"])
		if not extension.is_empty() and int(actor["population_start"]) < int(world.population_state.unit(unit).get("remaining_background_population", 0)):
			result.append({"id": "extension:"+id, "label": "纳入当地背景人口："+place+"；零初始资源", "extension": extension})
			starts[unit] = int(actor["population_start"])+1
		# An explicitly declared development operating unit in another existing
		# region. It uses the same company funds and starts with empty inventory.
		var places: Array[String] = []
		for site: Dictionary in spec["sites"].values():
			if site["place_id"] != place and not places.has(site["place_id"]): places.append(site["place_id"])
		places.sort()
		for other: String in places:
			if result.size() >= 12 or not world.spatial_catalog.has_place(other): break
			var site := base.duplicate(true)
			site["id"] = "site:runtime:"+str(firm["id"]).trim_prefix("firm:")+":"+other.trim_prefix("place:")
			site["place_id"] = other
			site["stock"] = EconomySliceConfig.zero_stock(spec["good_ids"])
			site["capacity"] = mini(1, int(base["capacity"]))
			# One explicitly bounded development activity; no copy of all HQ lines.
			var activities: Array[Dictionary] = []
			for activity: Dictionary in base["activities"]:
				if activity["enabled"]:
					activities.append(activity.duplicate(true))
					break
			site["activities"] = activities
			for activity: Dictionary in site["activities"]:
				activity["id"] = "activity:runtime:"+str(firm["id"]).trim_prefix("firm:")+":"+other.trim_prefix("place:")+":"+str(activity["id"]).trim_prefix("activity:")
				activity["place_id"] = other
			var other_unit := world.population_state.unit_for_place(other)
			var worker := actor.duplicate(true)
			worker["id"] = "cohort:runtime:"+str(firm["id"]).trim_prefix("firm:")+":"+other.trim_prefix("place:")
			worker["account_id"] = "account:"+str(worker["id"]).trim_prefix("cohort:")
			worker["place_id"] = other
			worker["population_unit_id"] = other_unit
			worker["population_start"] = int(starts.get(other_unit, 0))
			var added := settings.duplicate(true)
			for company: Dictionary in added["firms"]:
				if company["id"] == firm["id"]: company["sites"].append(site)
			var growth := _runtime_subject_extension(added, worker, firm["id"], site["id"])
			if growth.is_empty() or int(worker["population_start"]) >= int(world.population_state.unit(other_unit).get("remaining_background_population", 0)): continue
			growth["sites"] = [{"firm_id": firm["id"], "site": site}]
			for candidate: String in site["suppliers"]:
				growth["information"].append({"actor": site["id"], "kind": "supplier", "candidate": candidate, "delivery_day": 1})
			result.append({"id": "extension:"+str(site["id"]), "label": "启用开发经营单元："+other+"；零初始资源", "extension": growth})
			starts[other_unit] = int(worker["population_start"])+1
			break
		for person: String in world.person_overlay.person_ids():
			if result.size() >= 12: break
			if spec["actors"].has(person) or world.person_overlay.current_place(person) != place or not world.personal_economy_state.native_admission_reason(person).is_empty(): continue
			var named := actor.duplicate(true)
			named.merge({"id": person, "kind": "named", "account_id": FormalPersonalEconomyState.personal_account_id(person), "population_start": 0}, true)
			var admission := _runtime_subject_extension(settings, named, firm["id"], base["id"])
			if not admission.is_empty(): result.append({"id": "extension:"+person, "label": "纳入已有宿主人物："+person+"；引用原账户", "extension": admission})
	return result

static func _runtime_subject_extension(settings: Dictionary, actor: Dictionary, firm: String, site: String) -> Dictionary:
	var spec := EconomySliceConfig.normalize(settings, [])
	var information: Array[Dictionary] = []
	for category: String in actor["needs"]:
		if int(actor["needs"][category]) <= 0: continue
		var found: bool = false
		for seller: Dictionary in spec["sites"].values():
			if seller["place_id"] != actor["place_id"]: continue
			for good: String in seller["prices"]:
				if int(spec["consumption"].get(good, {}).get(category, 0)) <= 0: continue
				var row := {"actor": actor["id"], "kind": "supplier", "candidate": str(seller["firm_id"])+"|"+good+"|"+str(seller["id"]), "delivery_day": 1}
				if not information.has(row): information.append(row)
				found = true
				break
			if found: break
		if not found: return {}
	var job := {"id": "job:runtime:"+str(actor["id"])+":"+site.trim_prefix("site:"), "employer": firm, "site_id": site, "positions": 1, "skill": 1, "hours": 2, "place": actor["place_id"], "wage_per_hour": 3, "wage_delay": 1, "notice_delay": 1}
	if settings["case_id"] == "FORMAL_STRATIFIED_REGIONAL_DEVELOPMENT" and actor["kind"] == "cohort":
		actor["cohort_profile"] = {"stratum_id": actor["id"], "label": "追加劳动人口", "occupation": "local_development_work", "labor_members": 1, "max_jobs": 1, "job_ids": [job["id"]], "job_search_days": 3, "basis": "EXPLICIT_DEVELOPMENT_COHORT_STRATUM"}
	information.append({"actor": actor["id"], "kind": "job", "candidate": job["id"], "delivery_day": 1})
	var routes: Array[Dictionary] = []
	for edge: Dictionary in settings.get("routes", []):
		if edge["from_place_id"] == actor["place_id"] and edge["to_place_id"] == actor["place_id"]: routes.append({"actor": actor["id"], "route_id": edge["id"]})
	return {"actors": [actor], "jobs": [job], "information": information, "route_knowledge": routes}

## Custody service is development content, not a historical warehouse claim.
## It authorizes co-located personal lots, never commercial stock ownership.
static func _development_personal_storage(settings: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var places: Dictionary = {}
	for firm: Dictionary in settings["firms"]:
		for site: Dictionary in firm.get("sites", []):
			if places.has(site["place_id"]): continue
			places[site["place_id"]] = true
			result.append({"site_id": site["id"], "goods": EconomySliceConfig.good_ids(settings), "basis": "DEVELOPMENT_CUSTODY_PERMISSION"})
	return result


static func _managed_freight_announcement(settings: Dictionary, person: String) -> Dictionary:
	var sources: Array[String] = []
	for firm: Dictionary in settings["firms"]:
		if firm.get("manager", firm["id"]) == person: sources.append(firm["id"])
	var rows: Array[Dictionary] = []
	for field: String in ["routes", "transport_paths"]:
		for route: Dictionary in settings.get(field, []):
			if route["known_to"].has(person): continue
			for source: String in sources:
				if route["known_to"].has(source):
					rows.append({"actor": person, "route_id": route["id"]})
					break
	if rows.is_empty(): return {}
	return {"id": "extension:managed_freight_notice", "label": "获取所管理企业的开发承运路线公告", "extension": {"route_knowledge": rows}}


## Native kg/count semantics are explicit development assumptions, not inferred
## from recipes, names, retail prices or household satisfaction values.
static func _install_commodity_crosswalk(settings: Dictionary) -> void:
	var legacy: Dictionary = {"bread": "bread", "flour": "flour", "beans": "pulses", "grain": "wheat", "oil": "vegetable_oil", "soap": "soap"}
	settings["commodity_mappings"] = []
	for good: Dictionary in settings.get("goods", []):
		if not legacy.has(good["id"]): continue
		good["unit_id"] = "development_kg"
		good["unit_name_zh"] = "千克（开发口径）"
		settings["commodity_mappings"].append({"id": "mapping:development:"+str(legacy[good["id"]])+":"+str(good["id"]), "legacy_commodity_id": legacy[good["id"]], "native_good_id": good["id"], "legacy_unit_name_zh": "吨", "native_unit_id": "development_kg", "native_units_numerator": 1000, "legacy_units_denominator": 1, "scope": "FORMAL_PERSON_OWNED_PROPERTY", "source": FormalWorldEconomicEvidenceCatalog.COMMODITY_PATH, "basis": "EXPLICIT_DEVELOPMENT_UNIT_CROSSWALK", "semantic_assumption": "DEVELOPMENT_GOOD_REPRESENTS_ONE_KG_OF_SELECTED_STATISTICAL_COMMODITY", "operations": ["OBSERVE", "PERSONAL_OWNED_HANDOVER", "FUTURE_FLOW_ARRANGEMENT"] if good["id"] in ["bread", "beans", "soap"] else ["OBSERVE", "PERSONAL_OWNED_HANDOVER"]})

## This permits residence changes only at existing explicitly selected host places.
## It does not configure a passenger connection, immigration law or nationality.
static func formal_residence_permissions(world: WorldState, settings: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var places: Array[String] = ["place:paris", "place:lyon", "place:marseille", "place:port_le_havre", "place:port_london"]
	var by_unit: Dictionary = {}
	for place: String in places:
		var unit := world.population_state.unit_for_place(place)
		if unit.is_empty() or not world.spatial_catalog.has_place(place): continue
		if not by_unit.has(unit): by_unit[unit] = []
		by_unit[unit].append(place)
	for person: String in EconomySliceConfig.named_ids(settings):
		for source: String in by_unit:
			for target: String in by_unit:
				if source == target: continue
				result.append({"id": "residence:development:"+person+":"+source+":"+target, "person_id": person, "source_unit_id": source, "destination_unit_id": target, "place_ids": by_unit[target].duplicate(), "basis": "DEVELOPMENT_RESIDENCE_PERMISSION"})
	return result


## The host labels London as british_empire, whereas population evidence has
## british_isles_1900. This opt-in assumption binds only the two actual London
## places; it makes no claim about the Empire's overseas resident population.
static func formal_residence_place_bindings(world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world.population_state.unit("british_isles_1900").is_empty(): return result
	for place: String in ["place:london", "place:port_london"]:
		if not world.spatial_catalog.has_place(place) or not world.population_state.unit_for_place(place).is_empty(): continue
		result.append({"place_id": place, "population_unit_id": "british_isles_1900", "source": FormalWorldEconomicEvidenceCatalog.WORLD_MANIFEST_PATH, "basis": "DEVELOPMENT_PLACE_POPULATION_CROSSWALK", "scope_assumption": "LONDON_MAINLAND_PLACES_WITHIN_BRITISH_ISLES_STATISTICAL_SCOPE_ONLY"})
	return result


static func _install_lifecycle_configuration(result: Dictionary) -> void:
	# Limited succession to the same development firm's existing automatic operator.
	# No stock, cash, organization office or shares change owner.
	if not result.has("firm_management_permissions"):
		result["firm_management_permissions"] = []
		for firm: Dictionary in result["firms"]:
			var manager := str(firm.get("manager", firm["id"]))
			if manager != firm["id"] and str(firm.get("host_organization_id", "")).is_empty(): result["firm_management_permissions"].append({"firm": firm["id"], "from_manager": manager, "to_manager": firm["id"], "basis": "DEVELOPMENT_MANAGER_SUCCESSION", "accept_automatically": true})
	if not result.has("npc_residence"): result["npc_residence"] = []


## These goods and permits describe the developer network, not historical
## machines, mineral yields, land ownership, prices or industrial statistics.
static func _install_capital_configuration(result: Dictionary) -> void:
	for good: Dictionary in [{"id": "building_material", "capital_uses": ["CONSTRUCTION_MATERIAL"], "unit_id": "development_material_lot", "unit_name_zh": "开发材料批"}, {"id": "production_tool", "capital_uses": ["INSTALLATION_INPUT", "MAINTENANCE_INPUT"], "unit_id": "development_tool_set", "unit_name_zh": "开发工具组"}, {"id": "machine", "capital_uses": ["INSTALLABLE_EQUIPMENT"], "unit_id": "development_machine_set", "unit_name_zh": "开发设备组"}]:
		good["needs"] = {}
		result["goods"].append(good)
	var goods := EconomySliceConfig.good_ids(result)
	for actor: Dictionary in result["actors"]:
		for good: String in goods:
			if not actor["stock"].has(good): actor["stock"][good] = 0
	var sites: Array[Dictionary] = []
	for firm: Dictionary in result["firms"]:
		for site: Dictionary in firm["sites"]:
			for good: String in goods:
				if not site["stock"].has(good): site["stock"][good] = 0
				if not site["targets"].has(good): site["targets"][good] = 0
			for activity: Dictionary in site["activities"]:
				for good: String in goods:
					if not activity["materials"].has(good): activity["materials"][good] = 0
			if site["roles"].has("production"): sites.append({"firm": firm["id"], "site": site})
	if sites.size() < 2: return
	var upstream := sites[0] as Dictionary
	var assembler := sites[1] as Dictionary
	var source := upstream["site"] as Dictionary
	var works := assembler["site"] as Dictionary
	source["activities"].append({"id": "activity:development_building_material", "place_id": source["place_id"], "outputs": {"building_material": 2}, "materials": EconomySliceConfig.zero_stock(goods), "hours": 1, "capacity_units": 1, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION"})
	source["prices"]["building_material"] = 3
	source["targets"]["building_material"] = 6
	for row: Dictionary in [{"id": "production_tool", "inputs": {"building_material": 1}, "price": 8, "target": 2}, {"id": "machine", "inputs": {"building_material": 3, "production_tool": 1}, "price": 24, "target": 1}]:
		var materials := EconomySliceConfig.zero_stock(goods)
		materials.merge(row["inputs"], true)
		works["activities"].append({"id": "activity:development_"+str(row["id"]), "place_id": works["place_id"], "outputs": {row["id"]: 1}, "materials": materials, "hours": 2, "capacity_units": 2, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION"})
		works["prices"][row["id"]] = row["price"]
		works["targets"][row["id"]] = row["target"]
	result["capital_investment"] = {"templates": [], "npc_policies": []}
	for item: Dictionary in sites:
		var site := item["site"] as Dictionary
		var activities: Array[String] = []
		for row: Dictionary in site["activities"]: activities.append(row["id"])
		result["capital_investment"]["templates"].append(_capital_template(item["firm"], site["id"], activities, "EXPAND"))
		_add_capital_suppliers(result, item["firm"], site, upstream, assembler)
	# A new zero-resource workshop at an existing host place. Existing scope
	# preparation admits its stock point and jobs; installation alone supplies capacity.
	var builder := upstream
	for firm: Dictionary in result["firms"]:
		if str(firm.get("manager", firm["id"])) == firm["id"]: continue
		for item: Dictionary in sites:
			if item["firm"] == firm["id"]:
				builder = item
				break
		break
	var owner := str(builder["firm"])
	var site_id := "site:"+owner.trim_prefix("firm:")+":capital_annex"
	var annex := (builder["site"] as Dictionary).duplicate(true)
	annex["id"] = site_id
	annex["stock"] = EconomySliceConfig.zero_stock(goods)
	annex["capacity"] = 0
	annex["targets"] = EconomySliceConfig.zero_stock(goods)
	annex["suppliers"] = []
	_add_capital_suppliers(result, owner, annex, upstream, assembler, false)
	var known: Array = []
	for actor: Dictionary in result["actors"]:
		if actor["place_id"] == annex["place_id"]: known.append(actor["id"])
	var job := {"id": "job:"+site_id.trim_prefix("site:"), "employer": owner, "site_id": site_id, "positions": 2, "skill": 1, "hours": 2, "place": annex["place_id"], "wage_per_hour": 3, "wage_delay": 1, "notice_delay": 1}
	var information: Array = []
	for actor: String in known:
		information.append({"actor": actor, "kind": "job", "candidate": job["id"], "delivery_day": 1})
		for good: String in annex["prices"]: information.append({"actor": actor, "kind": "supplier", "candidate": owner+"|"+good+"|"+site_id, "delivery_day": 1})
	for candidate: String in annex["suppliers"]: information.append({"actor": site_id, "kind": "supplier", "candidate": candidate, "delivery_day": 1})
	if not result.has("runtime_expansions"): result["runtime_expansions"] = []
	result["runtime_expansions"].append({"id": "expansion:development_capital_annex", "label": "准备零产能建设经营地点（开发许可）", "extension": {"sites": [{"firm_id": owner, "site": annex}], "jobs": [job], "information": information}})
	var compatible: Array[String] = []
	for row: Dictionary in annex["activities"]: compatible.append(row["id"])
	result["capital_investment"]["templates"].append(_capital_template(owner, site_id, compatible, "NEW_SITE"))
	var installation := _capital_template(assembler["firm"], works["id"], [str(works["activities"][0]["id"])], "INSTALL")
	installation["id"] += ":equipment_installation"
	installation.merge({"capacity": 2, "materials": {"machine": 1, "production_tool": 1}, "hours": 2, "duration_minutes": 1440, "budget": 80}, true)
	result["capital_investment"]["templates"].append(installation)

static func _capital_template(firm: String, site: String, activities: Array[String], kind: String) -> Dictionary:
	return {"id": "investment:"+site.trim_prefix("site:"), "firm": firm, "site_id": site, "kind": kind, "asset_type": "development_shared_production_equipment", "capacity": 4, "activities": activities, "materials": {"machine": 1, "building_material": 4, "production_tool": 1}, "hours": 6, "hours_per_day": 2, "duration_minutes": 2880, "max_projects": 1, "budget": 160, "cash_floor": 20, "denomination": FormalLedgerState.DENOMINATION, "basis": "DEVELOPMENT_CAPITAL_PERMISSION", "maintenance": {"materials": {"production_tool": 1}, "hours": 2, "hours_per_day": 2, "duration_minutes": 1440}}

static func _add_capital_suppliers(result: Dictionary, firm: String, site: Dictionary, upstream: Dictionary, assembler: Dictionary, publish: bool = true) -> void:
	for row: Dictionary in [{"owner": upstream["firm"], "site": upstream["site"]["id"], "good": "building_material"}, {"owner": assembler["firm"], "site": assembler["site"]["id"], "good": "machine"}, {"owner": assembler["firm"], "site": assembler["site"]["id"], "good": "production_tool"}]:
		if row["owner"] == firm: continue # Same-firm resources use real internal transport.
		var candidate := str(row["owner"])+"|"+str(row["good"])+"|"+str(row["site"])
		if not site["suppliers"].has(candidate): site["suppliers"].append(candidate)
		if publish: result["information"].append({"actor": site["id"], "kind": "supplier", "candidate": candidate, "delivery_day": 0})


## Explicit building permissions and commercial clauses. No new opening goods,
## cash, people or industrial machinery. Buildings consume the existing chain.
static func building_lease_regional_template()->Dictionary:
	var result:=lease_regional_template()
	result["case_id"]="FORMAL_BUILT_LEASE_REGIONAL_DEVELOPMENT"
	var market:=result["lease_market"] as Dictionary;var currency:=FormalLedgerState.DENOMINATION
	# This opt-in scenario chooses a longer original premises contract; no saved
	# contract is rewritten and the ordinary lease template remains unchanged.
	for policy:Dictionary in market["npc_policies"]:
		if policy["tenant"]=="firm:regional_food":policy["term_days"]=14;policy["max_total"]=35
	for budget:Dictionary in result["procurement_budgets"]:
		if budget["id"]=="budget:development:food_premises":budget["limit"]=40
	var site:={"id":"site:regional_upstream:leased_depot","place_id":"place:paris","roles":["storage","sales"],"stock":EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(result)),"targets":EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(result)),"prices":{},"capacity":0,"activities":[],"suppliers":[],"enabled":true,"production_enabled":false,"accepting_business":true,"basis":"DEVELOPMENT_CONFIGURATION","coordination_delay":1}
	result["runtime_expansions"].append({"id":"expansion:development:built_depot","label":"准备建成场地的零资源经营站点","extension":{"sites":[{"firm_id":"firm:regional_upstream","site":site}]}})
	var plans:Array=[
		["paris_home","firm:regional_food","site:regional_food:paris","RESIDENTIAL_BUILD",2,"firm:regional_food",[]],
		["paris_depot","firm:regional_food","site:regional_food:paris","COMMERCIAL_PREMISES_BUILD",1,"firm:regional_food",[site["id"]]],
		["lyon_home","firm:regional_upstream","site:regional_upstream:lyon","RESIDENTIAL_BUILD",2,"HOST_SELECTED_PLAYER",[]]]
	for data:Array in plans:
		var name:String=data[0];var owner:String=data[1];var residential:bool=data[3]=="RESIDENTIAL_BUILD";var place:="place:lyon" if name=="lyon_home" else "place:paris"
		var permit:={"id":"construction_permission:development:"+name,"space_id":"construction_space:development:"+name,"unit":"development_construction_plot_share","holder":owner,"controller":data[5],"place_id":place,"kind":data[3],"slots":1,"valid_from":0,"valid_until":60*1440,"source":"Explicit finite simulated construction use at an admitted place; no cadastral title, building footprint or historical permit inferred.","root_authority":"","basis":"EXPLICIT_DEVELOPMENT_CONSTRUCTION_USE_PERMISSION","slot_rule":"RESERVE_ON_ACCEPTANCE_NO_AUTOMATIC_REUSE"}
		var object:={"id":"lease_object:built:"+name,"place_id":place,"kind":"RESIDENTIAL_SPACE" if residential else "COMMERCIAL_PREMISES","lessor":owner,"capacity":data[4],"unit":"development_person_place" if residential else "development_exclusive_premises","rights_source":{"id":permit["id"],"holder":owner,"basis":"COMPLETED_CAPITAL_PROJECT_REQUIRED","note":permit["source"]},"capital_asset_id":"","eligible_sites":data[6],"valid_from":0,"valid_until":90*1440,"capacity_basis":"CAPITAL_ASSET_CAPACITY_PROJECTION"}
		var known:Array=["HOST_SELECTED_PLAYER","cohort:stratified:paris_industrial","cohort:stratified:paris_nonworkers"] if place=="place:paris" else ["cohort:stratified:lyon_primary","cohort:stratified:lyon_textile"]
		if not residential:known=["firm:regional_upstream"]
		# Use actual cohort IDs from the declared finite population.
		if place=="place:lyon":
			known=[]
			for actor:Dictionary in result["actors"]:
				if actor["place_id"]==place:known.append(actor["id"])
		var quote:={"id":"lease_offer:built:"+name,"object_id":object["id"],"denomination":currency,"rent_per_unit":2 if residential else 4,"period_days":2,"max_days":14,"valid_from":0,"valid_until":60*1440,"known_to":known,"notice_minute":0,"payment_rule":"FIRST_PERIOD_SECURED_RENT_AFTER_USE_NO_DEPOSIT","cancel_rule":"TENANT_MAY_END_AT_DAILY_BOUNDARY_RETURN_REQUIRED","due_priority":"AFTER_EXISTING_WAGES_AND_DEBT_BEFORE_NEW_PROCUREMENT","billing_rule":"CUMULATIVE_AVAILABLE_UNIT_MINUTES_FLOOR","housing_rule":"LOCAL_AT_DAILY_BOUNDARY"}
		var template:={"id":"investment:building:"+name,"firm":owner,"site_id":data[2],"kind":data[3],"asset_type":"development_built_residential_space" if residential else "development_built_commercial_premises","capacity":data[4],"activities":[],"materials":{"building_material":4,"production_tool":1},"hours":4,"hours_per_day":2,"duration_minutes":2880,"max_projects":2,"budget":50,"cash_floor":2,"denomination":currency,"basis":"DEVELOPMENT_CAPITAL_PERMISSION","maintenance":{"materials":{"production_tool":1},"hours":2,"hours_per_day":2,"duration_minutes":1440},"building":{"permit":permit,"object":object,"offer":quote}}
		result["capital_investment"]["templates"].append(template)
	market["authorities"].append({"id":"lease_authority:building_food","firm":"firm:regional_food","controller":"firm:regional_food","operations":["let"],"denomination":currency,"limit":80,"start_minute":0,"end_minute":60*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_LEASE_AUTHORITY"})
	for authority:Dictionary in market["authorities"]:
		if authority["firm"]=="firm:regional_upstream":authority["operations"].append_array(["rent","manage"])
	market["npc_policies"].append({"tenant":"cohort:stratified:paris_industrial","offer_ids":["lease_offer:built:paris_home"],"quantity":2,"term_days":6,"max_total":12,"priority":"BEFORE_OPTIONAL_SERVICES_AND_GOODS","auto_handover":true,"auto_return_on_end":false,"no_new_if_overdue":true,"basis":"EXPLICIT_DEVELOPMENT_LEASE_DEMAND"})
	result["procurement_budgets"].append({"id":"budget:development:built_depot","subject":"organization:development_regional_upstream","root_authority":"lease_authority:firm:regional_upstream","denomination":currency,"category":"lease:commercial_premises","start_minute":0,"end_minute":60*1440,"limit":20,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	market["housing_targets"].append({"customer":"cohort:stratified:lyon_primary","basis":"EXPLICIT_DEVELOPMENT_HOUSING_USE_TARGET","initial_housing":"UNSPECIFIED_NOT_A_HOMELESSNESS_CLASSIFICATION"})
	result["capital_investment"]["building_policies"]=[{"template_id":"investment:building:paris_depot","window_days":7,"minimum_paid_rent":2,"cash_floor":0,"require_no_vacancy":true,"basis":"EXPLICIT_DEVELOPMENT_BUILD_FROM_OWN_PAID_RENT"}]
	return result


## Independent merchant uses the existing upstream organization, cash and
## workforce pool. New site opens empty after ordinary construction and lease.
static func retail_regional_template() -> Dictionary:
	var result:=building_lease_regional_template()
	result["case_id"]="FORMAL_PHYSICAL_RETAIL_REGIONAL_DEVELOPMENT"
	var site_id:="site:regional_upstream:leased_depot"
	var expansions: Array=[]
	for expansion: Dictionary in result["runtime_expansions"]:
		if expansion["id"]!="expansion:development:built_depot": expansions.append(expansion);continue
		var site:=expansion["extension"]["sites"][0]["site"] as Dictionary
		site["prices"]={"bread":8,"soap":12}
		site["targets"]["bread"]=6;site["targets"]["soap"]=2
		site["suppliers"]=["firm:regional_food|bread|site:regional_food:paris","firm:regional_household|soap|site:regional_household:marseille"]
		# Declared empty from startup. Lease gate prevents any use before completion.
		for firm: Dictionary in result["firms"]:
			if firm["id"]=="firm:regional_upstream": firm["sites"].append(site)
		var job:={"id":"job:regional_upstream:store","employer":"firm:regional_upstream","site_id":site_id,"positions":1,"skill":1,"hours":2,"place":"place:paris","wage_per_hour":2,"wage_delay":1,"notice_delay":1}
		result["jobs"].append(job)
		for candidate: String in site["suppliers"]: result["information"].append({"actor":site_id,"kind":"supplier","candidate":candidate,"delivery_day":0})
		for customer: String in ["cohort:stratified:paris_nonworkers","cohort:stratified:paris_industrial"]:
			for good: String in ["bread","soap"]: result["information"].append({"actor":customer,"kind":"supplier","candidate":"firm:regional_upstream|"+good+"|"+site_id,"delivery_day":0})
		result["information"].append({"actor":"cohort:stratified:paris_industrial","kind":"job","candidate":job["id"],"delivery_day":0})
		for actor: Dictionary in result["actors"]:
			if actor["id"]=="cohort:stratified:paris_industrial":
				actor["cohort_profile"]["job_ids"].append(job["id"])
				actor["cohort_profile"]["max_jobs"]=3
	result["runtime_expansions"]=expansions
	result["retail_sites"]=[{"site_id":site_id,"firm_id":"firm:regional_upstream","job_ids":["job:regional_upstream:store"],"stock_units":{"bread":1,"soap":2},"stock_capacity":12,"stock_unit":"development_dedicated_store_stock_unit","hours_per_day":2,"units_per_hour":3,"daily_limit":6,"open_from":0,"open_until":1440,"restock":{"bread":{"target":6,"threshold":3,"batch_limit":4,"max_price":7,"cash_floor":6},"soap":{"target":2,"threshold":1,"batch_limit":2,"max_price":12,"cash_floor":6}},"window_days":7,"onsite_first_for":["cohort:stratified:paris_industrial"],"basis":"EXPLICIT_DEVELOPMENT_STOREFRONT","time_basis":"SETTLED_DAILY_STAFFING_WINDOW"}]
	return result

## Existing textile merchant performs finite local publication work with its
## store worker. Prices, delay and pooled purchasing desks are simulation assumptions.
static func commercial_information_regional_template() -> Dictionary:
	var result:=retail_regional_template()
	result["case_id"]="FORMAL_LOCAL_COMMERCIAL_INFORMATION_DEVELOPMENT"
	# Longer new-world premises term uses the same account and actual rent.
	# Existing saves and the ordinary building/retail templates are not changed.
	for quote: Dictionary in result["lease_market"]["offers"]:
		if quote["id"]=="lease_offer:development:paris_food_premises": quote["max_days"]=20
	for policy: Dictionary in result["lease_market"]["npc_policies"]:
		if policy["tenant"]=="firm:regional_food": policy["term_days"]=20;policy["max_total"]=50
	for budget: Dictionary in result["procurement_budgets"]:
		if budget["id"]=="budget:development:food_premises": budget["limit"]=50

	# A second merchant at an existing legal sales site. No opening resources
	# are added. Bread must be bought and delivered under the original orders.
	var competitor:="site:regional_textile:paris"
	for firm: Dictionary in result["firms"]:
		if firm["id"]!="firm:regional_textile": continue
		for outlet: Dictionary in firm["sites"]:
			if outlet["id"]==competitor:
				outlet["prices"]["bread"]=6 # Explicit loss-leading N2 quote, not a price algorithm.
				outlet["targets"]["bread"]=3
				outlet["suppliers"].append("firm:regional_food|bread|site:regional_food:paris")
	var job:="job:regional_textile:paris_store"
	result["jobs"].append({"id":job,"employer":"firm:regional_textile","site_id":competitor,"positions":1,"skill":1,"hours":1,"place":"place:paris","wage_per_hour":2,"wage_delay":1,"notice_delay":1})
	result["information"].append({"actor":competitor,"kind":"supplier","candidate":"firm:regional_food|bread|site:regional_food:paris","delivery_day":0})
	result["information"].append({"actor":"cohort:stratified:paris_industrial","kind":"job","candidate":job,"delivery_day":0})
	for actor: Dictionary in result["actors"]:
		if actor["id"]=="cohort:stratified:paris_industrial":
			actor["cohort_profile"]["job_ids"].append(job)
			actor["cohort_profile"]["max_jobs"]=4
	var retail: Dictionary=result["retail_sites"][0].duplicate(true)
	retail.merge({"site_id":competitor,"firm_id":"firm:regional_textile","job_ids":[job],"stock_units":{"bread":1,"clothes":2,"soap":2},"stock_capacity":16,"hours_per_day":1,"daily_limit":3,"restock":{"bread":{"target":3,"threshold":2,"batch_limit":3,"max_price":7,"cash_floor":6}}},true)
	result["retail_sites"].append(retail)
	var market:=result["service_market"] as Dictionary
	# Another announced quotation for the existing haircut capacity. It creates
	# no second chair, worker or service result and grants no initial knowledge.
	var announced: Dictionary={}
	for quote: Dictionary in market["offers"]:
		if quote["id"]=="service_offer:paris_haircut": announced=quote.duplicate(true)
	announced["id"]="service_offer:paris_haircut_public";announced["known_to"]=[]
	market["offers"].append(announced)
	for policy: Dictionary in market["resident_policies"]: policy["offer_ids"].append(announced["id"])
	var provider:="firm:regional_textile";var site:=competitor
	var offer:="service_offer:paris_local_publication";var facility:="facility:service:paris_publication"
	var channel:="channel:development:paris_paid"
	market["facilities"].append({"id":facility,"provider":provider,"site_id":site,"kind":"ANNOUNCEMENT","capacity":1,"unit":"development_local_publication_job","good_units":{},"shared_storage_id":"","basis":"EXPLICIT_DEVELOPMENT_SERVICE_FACILITY"})
	market["offers"].append({"id":offer,"facility_id":facility,"kind":"ANNOUNCEMENT","denomination":FormalLedgerState.DENOMINATION,"price":3,"valid_from":0,"valid_until":60*1440,"known_to":["firm:regional_upstream"],"notice_minute":0,"job_ids":[job],"hours_per_day":1,"cancel_rule":"UNSTARTED_REPAIR_OR_STORAGE_RETURN","basis":"EXPLICIT_DEVELOPMENT_SERVICE_OFFER","announcement_terms":{"channel_id":channel,"work_hours":1,"rule":"LOCAL_PUBLICATION_WORK_NO_GUARANTEED_SALE"}})
	result["procurement_budgets"].append({"id":"budget:development:local_publication","subject":"organization:development_regional_upstream","root_authority":"service_authority:firm:regional_upstream","denomination":FormalLedgerState.DENOMINATION,"category":"service:announcement","start_minute":0,"end_minute":60*1440,"limit":6,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	# Original known suppliers are retained. Lyon households can learn the Paris
	# store, but still need an executable route; an announcement grants no travel.
	var recipients: Array[String]=["HOST_SELECTED_PLAYER","cohort:stratified:paris_industrial","cohort:stratified:paris_nonworkers","site:regional_food:paris","cohort:stratified:lyon_jobseekers",competitor]
	result["commercial_information"]={"basis":"EXPLICIT_DEVELOPMENT_COMMERCIAL_INFORMATION","channels":[],"npc_policies":[]}
	for kind: String in ["SITE_BOARD","PAID_LOCAL_PUBLICATION"]:
		result["commercial_information"]["channels"].append({"id":"channel:development:paris_board" if kind=="SITE_BOARD" else channel,"kind":kind,"place_id":"place:paris","service_offer":"" if kind=="SITE_BOARD" else offer,"recipients":recipients.duplicate(),"recipient_limit":3 if kind=="SITE_BOARD" else 4,"delay_days":1 if kind=="SITE_BOARD" else 2,"cooldown_days":4,"window_days":7,"window_limit":2,"basis":"EXPLICIT_DEVELOPMENT_PUBLICATION_CHANNEL","audience_basis":"LOCAL_NAMED_PERSON_OR_POOLED_PURCHASING_DESK_NOT_MEMBER_KNOWLEDGE"})
	result["commercial_information"]["channels"].append({"id":"channel:development:lyon_board","kind":"SITE_BOARD","place_id":"place:lyon","service_offer":"","recipients":["site:regional_upstream:lyon","site:regional_food:lyon","cohort:stratified:lyon_skilled"],"recipient_limit":2,"delay_days":1,"cooldown_days":7,"window_days":7,"window_limit":1,"basis":"EXPLICIT_DEVELOPMENT_PUBLICATION_CHANNEL","audience_basis":"LOCAL_NAMED_PERSON_OR_POOLED_PURCHASING_DESK_NOT_MEMBER_KNOWLEDGE"})
	result["commercial_information"]["npc_policies"].append({"id":"publicity:textile:lyon_warehouse","firm":"firm:regional_textile","site_id":"site:regional_textile:lyon","kind":"SERVICE","item":"service_offer:lyon_storage","channel_id":"channel:development:lyon_board","valid_days":3,"minimum_stock":0,"sales_window":7,"sales_at_most":1,"max_fee":0,"cash_floor":4,"basis":"EXPLICIT_DEVELOPMENT_OWN_SALES_PUBLICITY_POLICY"})
	result["commercial_information"]["npc_policies"].append({"id":"publicity:textile:paris_bread","firm":"firm:regional_textile","site_id":competitor,"kind":"GOODS","item":"bread","channel_id":"channel:development:paris_board","valid_days":3,"minimum_stock":1,"sales_window":7,"sales_at_most":2,"max_fee":0,"cash_floor":4,"basis":"EXPLICIT_DEVELOPMENT_OWN_SALES_PUBLICITY_POLICY"})
	result["commercial_information"]["npc_policies"].append({"id":"publicity:food:paris_haircut","firm":"firm:regional_food","site_id":"site:regional_food:paris","kind":"SERVICE","item":"service_offer:paris_haircut_public","channel_id":"channel:development:paris_board","valid_days":3,"minimum_stock":0,"sales_window":7,"sales_at_most":0,"max_fee":0,"cash_floor":4,"basis":"EXPLICIT_DEVELOPMENT_OWN_SALES_PUBLICITY_POLICY"})
	return result

## Future employment terms and local recruitment are development assumptions.
## Same 72 background residents, enterprises, stocks and opening accounts.
static func labor_market_regional_template() -> Dictionary:
	var result:=commercial_information_regional_template()
	result["case_id"]="FORMAL_DYNAMIC_LOCAL_LABOR_DEVELOPMENT"
	result["labor_response_policies"]=[]
	for actor: String in ["cohort:stratified:paris_industrial","cohort:stratified:lyon_skilled"]:
		result["labor_response_policies"].append({"actor":actor,"arrears_days":4,"basis":"EXPLICIT_DEVELOPMENT_LABOR_RESPONSE"})
	result["labor_market"]={"job_rules":[],"authorities":[],"npc_policies":[],"worker_policies":[],"basis":"EXPLICIT_DEVELOPMENT_LABOR_MARKET"}
	var market:=result["labor_market"] as Dictionary
	# One initially empty assistant role at the existing Paris merchant. It shares
	# its existing store and publication work; it creates no worker or capacity.
	var assistant:="job:regional_textile:paris_assistant"
	result["jobs"].append({"id":assistant,"employer":"firm:regional_textile","site_id":"site:regional_textile:paris","positions":0,"skill":1,"hours":1,"place":"place:paris","wage_per_hour":3,"wage_delay":1,"notice_delay":1})
	for actor: Dictionary in result["actors"]:
		if actor["id"]=="cohort:stratified:paris_industrial": actor["cohort_profile"]["job_ids"].append(assistant)
	for store: Dictionary in result["retail_sites"]:
		if store["site_id"]=="site:regional_textile:paris":
			store["job_ids"].append(assistant)
			store["hours_per_day"]=2;store["daily_limit"]=6 # Finite two-hour development shop window; stock space is unchanged.
	# Short factory shifts permit an explicit competing staffing plan. Neither
	# workers nor installed production capacity increase with advertised slots.
	for job: Dictionary in result["jobs"]:
		if job["id"]=="job:regional_food:paris": job["positions"]=10;job["hours"]=1
		var recipients: Array[String]=[]
		for actor: Dictionary in result["actors"]:
			if actor["place_id"]==job["place"] and EconomyCohortRules.labor_members(actor)>0: recipients.append(actor["id"])
		if job["place"]=="place:paris": recipients.append("HOST_SELECTED_PLAYER")
		market["job_rules"].append({"job_id":job["id"],"max_positions":1 if job["id"]==assistant else 12,"min_wage":3 if job["id"]==assistant else 1,"max_wage":6,"wage_step":1,"position_step":4,"cooldown_days":2 if job["id"]==assistant else 3,"quote_days":12,"notice_days":1,"recipients":recipients,"cash_floor":5,"coverage_days":1,"basis":"EXPLICIT_DEVELOPMENT_FUTURE_EMPLOYMENT_TERMS"})
		market["npc_policies"].append({"job_id":job["id"],"vacancy_days":1 if job["id"]==assistant else 3,"window_days":7,"basis":"EXPLICIT_DEVELOPMENT_OWN_ACTIVITY_RECRUITMENT"})
	for firm: Dictionary in result["firms"]:
		market["authorities"].append({"id":"employment_authority:"+str(firm["id"]),"firm":firm["id"],"controller":"HOST_SELECTED_PLAYER" if firm["id"]=="firm:regional_upstream" else firm["id"],"operations":["recruit","amend"],"denomination":FormalLedgerState.DENOMINATION,"daily_wage_limit":144,"start_minute":0,"end_minute":60*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_EMPLOYMENT_AUTHORITY"})
	for actor: Dictionary in result["actors"]:
		if EconomyCohortRules.labor_members(actor)>0:
			market["worker_policies"].append({"actor":actor["id"],"review_days":1 if actor["id"]=="cohort:stratified:paris_industrial" else 3,"minimum_hourly_gain":1,"max_move_workers":2,"basis":"EXPLICIT_DEVELOPMENT_KNOWN_LOCAL_JOB_CHOICE"})
	return result

## Same resources/population as the labor scenario. These are voluntary developer
## mandates and a stated payment sequence, not historical insolvency law.
static func wind_down_regional_template() -> Dictionary:
	var result:=labor_market_regional_template()
	result["case_id"]="FORMAL_VOLUNTARY_ENTERPRISE_WIND_DOWN_DEVELOPMENT"
	result["wind_down"]={"basis":"EXPLICIT_DEVELOPMENT_VOLUNTARY_WIND_DOWN","authorities":[],"npc_policies":[]}
	for firm: Dictionary in result["firms"]:
		var id: String=firm["id"]
		result["wind_down"]["authorities"].append({"id":"voluntary_closure:"+id,"firm":id,"controller":"HOST_SELECTED_PLAYER" if id=="firm:regional_upstream" else id,"operations":["decide","dispose_inventory","settle","resume"],"limit":100,"start_minute":0,"end_minute":90*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_VOLUNTARY_WIND_DOWN_AUTHORITY"})
		if id!="firm:regional_upstream": result["wind_down"]["npc_policies"].append({"firm":id,"repayment_order":["WAGE","RENT","LOAN"],"max_payment_per_currency_day":15,"cash_floor":0,"review_days":2,"basis":"EXPLICIT_DEVELOPMENT_SETTLEMENT_ORDER_NOT_LEGAL_PRIORITY"})
	var liquidity:=liquidity_regional_template()
	for key: String in ["liquidity_policies","firm_finance_authorities","credit_offers","npc_finance"]: result[key]=liquidity[key].duplicate(true)
	# A real stocked local seller announces to existing commercial desks. Knowledge
	# is acquired through the original delayed board, not a global liquidation feed.
	result["commercial_information"]["npc_policies"].insert(0,{"id":"publicity:textile:lyon_disposable_clothes","firm":"firm:regional_textile","site_id":"site:regional_textile:lyon","kind":"GOODS","item":"clothes","channel_id":"channel:development:lyon_board","valid_days":7,"minimum_stock":1,"sales_window":7,"sales_at_most":2,"max_fee":0,"cash_floor":0,"basis":"EXPLICIT_DEVELOPMENT_OWN_SALES_PUBLICITY_POLICY"})
	for p: Dictionary in result["liquidity_policies"]:
		if p["firm"]=="firm:regional_food": p["wind_down_after_days"]=8
	result["labor_response_policies"].append({"actor":"cohort:stratified:lyon_lowsavings","arrears_days":7,"basis":"EXPLICIT_DEVELOPMENT_LABOR_RESPONSE"})
	# Existing skilled residents may apply for this lower-skill local occupation;
	# actual current quotations still have to arrive and the firm must accept.
	for a: Dictionary in result["actors"]:
		if a["id"]=="cohort:stratified:lyon_skilled": a["cohort_profile"]["job_ids"].append("job:regional_upstream:lyon")
	# Existing household exits remain worker decisions. No employer dismissal law.
	return result


## Same host place only. No machine, cash, workers or material is endowed here.
## Rates and compatibility are simulated inputs, not historical equipment facts.
static func capital_resale_regional_template() -> Dictionary:
	var result:=wind_down_regional_template()
	result["case_id"]="FORMAL_MOVABLE_CAPITAL_REGIONAL_DEVELOPMENT"
	for t: Dictionary in result["capital_investment"]["templates"]:
		if t["id"]=="investment:regional_textile:lyon": t["asset_type"]="development_detachable_processing_machine"
	var recipe:=func(hours: int)->Dictionary: return {"materials":{"production_tool":1},"hours":hours,"hours_per_day":1,"duration_minutes":1440,"budget":40,"skill":1}
	result["capital_resale"]={"basis":"EXPLICIT_DEVELOPMENT_MOVABLE_CAPITAL","types":[{"asset_type":"development_detachable_processing_machine","denomination":FormalLedgerState.DENOMINATION,"dismantle":recipe.call(2),"handover":recipe.call(1),"reinstall":recipe.call(2),"targets":{"site:regional_textile:lyon":["activity:regional_clothes"],"site:regional_upstream:lyon":["activity:regional_fiber"],"site:regional_food:paris":["activity:regional_mill"]},"transport":"SAME_PLACE_WORKED_HANDOVER_ONLY","basis":"EXPLICIT_DEVELOPMENT_MOVABLE_EQUIPMENT"}],"authorities":[],"contacts":[{"seller":"firm:regional_textile","buyer":"firm:regional_upstream","available_minute":0,"basis":"EXPLICIT_DEVELOPMENT_BILATERAL_CAPITAL_CONTACT"},{"seller":"firm:regional_textile","buyer":"firm:regional_food","available_minute":0,"basis":"EXPLICIT_DEVELOPMENT_BILATERAL_CAPITAL_CONTACT"}],"npc_policies":[{"firm":"firm:regional_textile","buyer":"firm:regional_upstream","target_site":"site:regional_upstream:lyon","price":35,"cash_floor":20,"review_days":2,"basis":"EXPLICIT_DEVELOPMENT_KNOWN_COUNTERPARTY_IDLE_CAPITAL"}]}
	for firm: Dictionary in result["firms"]:
		result["capital_resale"]["authorities"].append({"id":"capital_disposition:"+str(firm["id"]),"firm":firm["id"],"controller":"HOST_SELECTED_PLAYER" if firm["id"]=="firm:regional_upstream" else firm["id"],"operations":["disassemble","sell","handover","acquire","pay","install"],"limit":100,"start_minute":0,"end_minute":90*1440,"root_authority":"","basis":"EXPLICIT_DEVELOPMENT_CAPITAL_DISPOSITION_AUTHORITY"})
	result["procurement_budgets"].append({"id":"budget:development:used_equipment","subject":"organization:development_regional_upstream","root_authority":"capital_disposition:firm:regional_upstream","denomination":FormalLedgerState.DENOMINATION,"category":"capital_asset","start_minute":0,"end_minute":90*1440,"limit":70,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	return result

## Explicit engineering units only. No additional machine, vehicle, workforce,
## money or geographic connection is created. The finite shared facilities
## and vehicles use the existing liquidity-development definitions.
static func capital_transport_regional_template() -> Dictionary:
	var permissions:=capital_resale_regional_template()
	var result:=regional_template()
	for key: String in ["capital_resale","wind_down","firm_finance_authorities","credit_offers","npc_finance","development_organizations"]: result[key]=permissions[key].duplicate(true)
	for firm: Dictionary in result["firms"]: firm["host_organization_id"]="organization:development_"+str(firm["id"]).trim_prefix("firm:")
	result["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
	result["procurement_budgets"]=[]
	for t: Dictionary in result["capital_investment"]["templates"]:
		if t["id"]=="investment:regional_textile:lyon": t["asset_type"]="development_detachable_processing_machine"
	# Keep the original regional workforce and shifts. Advertise its existing
	# finite posts; the transport work competes with production at those sites.
	for policy: Dictionary in result["firm_operations"]:
		policy["manage_jobs"]=false;policy["planning_horizon"]=2;policy["buffer_days"]=0
	# A finite four-unit milling load makes the machine's selective pool matter.
	for firm: Dictionary in result["firms"]:
		for site: Dictionary in firm["sites"]:
			for activity: Dictionary in site["activities"]:
				if activity["id"]=="activity:regional_mill": activity["capacity_units"]=4
	result["case_id"]="FORMAL_UNIQUE_CAPITAL_TRANSPORT_DEVELOPMENT"
	var machine:="development_detachable_processing_machine"
	var unit:="development_link_payload_unit"
	var transport:=liquidity_regional_template()
	for key: String in ["transport_facilities","shared_transport"]: result[key]=transport[key].duplicate(true)
	for route: Dictionary in result["routes"]:
		for shared: Dictionary in transport["routes"]:
			if route["id"]==shared["id"]: route["carrier"]=shared["carrier"]
	for good: Dictionary in result["goods"]: good["unit_weight"]={"numerator":1,"denominator":1,"unit":unit,"basis":"EXPLICIT_DEVELOPMENT_SHARED_LINK_LOAD_ASSUMPTION"}
	var rule:=result["capital_resale"]["types"][0] as Dictionary
	rule["transport"]="EXPLICIT_SHARED_UNIQUE_ASSET_CARRIAGE"
	rule["maintenance_targets"]={"site:regional_food:paris":"investment:regional_food:paris","site:regional_upstream:lyon":"investment:regional_upstream:lyon","site:regional_textile:lyon":"investment:regional_textile:lyon"}
	for authority: Dictionary in result["capital_resale"]["authorities"]: authority["operations"].append("freight")
	for facility: Dictionary in result["transport_facilities"]: facility["asset_types"]=[machine]
	result["capital_transport"]={"basis":"EXPLICIT_DEVELOPMENT_UNIQUE_ASSET_CARRIAGE","loads":[{"asset_type":machine,"unit":unit,"numerator":4,"denominator":1,"handling_units":1,"basis":"SIMULATION_ENGINEERING_ASSUMPTION_NOT_HISTORICAL_TONNAGE"}],"offers":[{"id":"capital_carriage:lyon_paris","source_site":"site:regional_textile:lyon","target_site":"site:regional_food:paris","asset_type":machine,"legs":[{"edge_id":"edge:regional:lyon:paris","carrier":"firm:regional_upstream","fee":6}],"known_to":["firm:regional_food"],"valid_from":0,"valid_until":60*1440,"denomination":FormalLedgerState.DENOMINATION,"basis":"EXPLICIT_DEVELOPMENT_CARRIER_COMMITMENT_PAY_ON_UNLOAD"}]}
	for category: String in ["capital_asset","capital_freight"]:
		result["procurement_budgets"].append({"id":"budget:development:food:"+category,"subject":"organization:development_regional_food","root_authority":"capital_disposition:firm:regional_food","denomination":FormalLedgerState.DENOMINATION,"category":category,"start_minute":0,"end_minute":60*1440,"limit":70 if category=="capital_asset" else 12,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	# Finite autonomous policy uses the same directed contact and carriage offer.
	result["capital_resale"]["npc_policies"][0]["buyer"]="firm:regional_food"
	result["capital_resale"]["npc_policies"][0]["target_site"]="site:regional_food:paris"
	return result


## Finite opening stocks, cash and demand are engineering scenario inputs.
## No unique capital asset is endowed: an ordinary NPC investment must build it.
static func npc_capital_trade_regional_template() -> Dictionary:
	var result:=capital_transport_regional_template()
	result["case_id"]="FORMAL_AUTONOMOUS_CAPITAL_REALLOCATION_DEVELOPMENT"
	result["capital_resale"]["npc_policies"][0]["review_days"]=1
	result["capital_resale"]["autonomous_policies"]=[{"seller":"firm:regional_textile","buyer":"firm:regional_food","site_id":"site:regional_food:paris","activity_id":"activity:regional_mill","asset_type":"development_detachable_processing_machine","observation_days":2,"minimum_extra_batches":1,"max_payback_days":60,"max_price":45,"cash_floor":35,"review_days":1,"message_delay_days":1,"seller_idle_days":3,"maintenance_days":2,"basis":"EXPLICIT_DEVELOPMENT_OBSERVED_CAPACITY_ACQUISITION"}]
	# An ordinary order-driven build, with a long cooldown, not a date-triggered grant.
	result["capital_investment"]["npc_policies"]=[{"template_id":"investment:regional_textile:lyon","window_days":1,"minimum_pressure":1,"minimum_utilization_percent":0,"cooldown_days":90}]
	for f: Dictionary in result["firms"]:
		if f["id"]=="firm:regional_textile":
			f["cash"]=320
			for site: Dictionary in f["sites"]:
				if site["id"]=="site:regional_textile:lyon": site["stock"].merge({"machine":1,"building_material":4,"production_tool":4,"fiber":40,"clothes":1},true)
		if f["id"]=="firm:regional_food":
			f["cash"]=360
			for site: Dictionary in f["sites"]:
				if site["id"]=="site:regional_food:paris":
					site["stock"].merge({"grain":60,"production_tool":5,"building_material":6},true)
					# Tools and assembly compete normally; their opening targets are already met.
					site["targets"]["machine"]=0
					site["targets"]["production_tool"]=2
	for actor: Dictionary in result["actors"]:
		if actor["id"]=="cohort:regional:paris_food":
			actor["needs"]["food"]=4;actor["daily_need"]=4;actor["cash"]=1200
	for job: Dictionary in result["jobs"]:
		if job["site_id"]=="site:regional_food:paris": job["hours"]=3
	return result


## Bounded engineering competition. Existing firms, eight cohort members, the
## original vehicles and host links remain the finite physical resource sources.
static func npc_capital_competition_regional_template() -> Dictionary:
	var result:=npc_capital_trade_regional_template()
	result["case_id"]="FORMAL_FINITE_CAPITAL_COMPETITION_DEVELOPMENT"
	result["capital_resale"]["competition"]={"basis":"EXPLICIT_DEVELOPMENT_DIRECTED_CAPITAL_COMPETITION","acceptance_order":"BUYER_ID_ASCENDING","ranking":"OBSERVED_WINDOW_CONTRIBUTION_LESS_COMPLETE_ACQUISITION"}
	var second: Dictionary=result["capital_resale"]["npc_policies"][0].duplicate(true)
	second["buyer"]="firm:regional_upstream";second["target_site"]="site:regional_upstream:lyon"
	result["capital_resale"]["npc_policies"].append(second)
	var buyer: Dictionary=result["capital_resale"]["autonomous_policies"][0].duplicate(true)
	buyer["buyer"]="firm:regional_upstream";buyer["site_id"]="site:regional_upstream:lyon";buyer["activity_id"]="activity:regional_beans";buyer["message_delay_days"]=2
	result["capital_resale"]["autonomous_policies"].append(buyer)
	for p: Dictionary in result["capital_resale"]["autonomous_policies"]: p["review_days"]=2
	for p: Dictionary in result["capital_resale"]["npc_policies"]: p["review_days"]=2
	result["capital_resale"]["types"][0]["targets"]["site:regional_upstream:lyon"]=["activity:regional_beans"]
	for authority: Dictionary in result["capital_resale"]["authorities"]:
		if authority["firm"]=="firm:regional_upstream": authority["controller"]="firm:regional_upstream"
	# Keep player admission on a non-participating existing firm. The two buyers
	# have explicitly autonomous managers through the normal bootstrap identities.
	result["firms"].sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if a["id"]==b["id"]: return false
		if a["id"]=="firm:regional_household": return true
		if b["id"]=="firm:regional_household": return false
		return a["id"]<b["id"])
	for f: Dictionary in result["firms"]:
		if f["id"]!="firm:regional_upstream": continue
		f["cash"]=360;f["manager"]=f["id"]
		for site: Dictionary in f["sites"]:
			if site["id"]!="site:regional_upstream:lyon": continue
			site["capacity"]=5
			site["stock"]["production_tool"]=3
			for activity: Dictionary in site["activities"]:
				if activity["id"]=="activity:regional_beans": activity["capacity_units"]=4
	for job: Dictionary in result["jobs"]:
		if job["site_id"]=="site:regional_upstream:lyon": job["hours"]=3
	result["procurement_budgets"].append({"id":"budget:development:upstream:capital_asset","subject":"organization:development_regional_upstream","root_authority":"capital_disposition:firm:regional_upstream","denomination":FormalLedgerState.DENOMINATION,"category":"capital_asset","start_minute":0,"end_minute":60*1440,"limit":70,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	return result

## The same bounded network, with a second real construction seller. This is a
## scenario variant, not an extra startup flag or a date-triggered purchase order.
static func npc_capital_comparison_regional_template() -> Dictionary:
	var result:=npc_capital_competition_regional_template()
	result["case_id"]="FORMAL_FINITE_CAPITAL_QUOTATION_COMPARISON_DEVELOPMENT"
	result["capital_resale"]["npc_policies"].resize(1)
	result["capital_resale"]["autonomous_policies"].resize(1)
	var sale: Dictionary=result["capital_resale"]["npc_policies"][0].duplicate(true)
	sale["firm"]="firm:regional_upstream";sale["price"]=30
	result["capital_resale"]["npc_policies"].append(sale)
	var policy: Dictionary=result["capital_resale"]["autonomous_policies"][0].duplicate(true)
	policy["seller"]="firm:regional_upstream"
	result["capital_resale"]["autonomous_policies"].append(policy)
	for p: Dictionary in result["capital_resale"]["autonomous_policies"]: p["review_days"]=6
	for contact: Dictionary in result["capital_resale"]["contacts"]:
		if contact["buyer"]=="firm:regional_food": contact["available_minute"]=20*1440
	result["capital_resale"]["contacts"].append({"seller":"firm:regional_upstream","buyer":"firm:regional_food","available_minute":18*1440,"basis":"EXPLICIT_DEVELOPMENT_BILATERAL_CAPITAL_CONTACT"})
	for f: Dictionary in result["firms"]:
		if f["id"]!="firm:regional_upstream": continue
		for site: Dictionary in f["sites"]:
			if site["id"]!="site:regional_upstream:lyon": continue
			site["capacity"]=9
			site["stock"].merge({"machine":1,"building_material":4,"production_tool":4},true)
			for activity: Dictionary in site["activities"]:
				if activity["id"]=="activity:regional_beans": activity["capacity_units"]=1
	for t: Dictionary in result["capital_investment"]["templates"]:
		if t["id"]=="investment:regional_upstream:lyon": t["asset_type"]="development_detachable_processing_machine"
	result["capital_investment"]["npc_policies"].append({"template_id":"investment:regional_upstream:lyon","window_days":1,"minimum_pressure":1,"minimum_utilization_percent":0,"cooldown_days":90})
	var carriage: Dictionary=result["capital_transport"]["offers"][0].duplicate(true)
	carriage["id"]="capital_carriage:upstream_paris";carriage["source_site"]="site:regional_upstream:lyon";carriage["legs"][0]["fee"]=12
	result["capital_transport"]["offers"].append(carriage)
	return result

## One constructed machine, two successive autonomous acquisitions. Finite
## household savings can reduce funded bread demand through ordinary purchases;
## no date schedules a disposal, acceptance or change in production evidence.
static func npc_capital_recirculation_regional_template() -> Dictionary:
	var result:=npc_capital_competition_regional_template()
	result["case_id"]="FORMAL_AUTONOMOUS_CAPITAL_RECIRCULATION_DEVELOPMENT"
	var sales: Array=result["capital_resale"]["npc_policies"]
	sales[1]["firm"]="firm:regional_food";sales[1]["price"]=32
	var policies: Array=result["capital_resale"]["autonomous_policies"]
	policies[1]["seller"]="firm:regional_food";policies[1]["message_delay_days"]=1
	result["capital_resale"]["contacts"].append({"seller":"firm:regional_food","buyer":"firm:regional_upstream","available_minute":0,"basis":"EXPLICIT_DEVELOPMENT_BILATERAL_CAPITAL_CONTACT"})
	for actor: Dictionary in result["actors"]:
		if actor["id"]=="cohort:regional:paris_food": actor["cash"]=900
	# Both directed host bindings already exist. The reverse contract explicitly
	# uses the Paris carrier, vehicle and handling facility, not a new railway.
	var reverse: Dictionary=result["capital_transport"]["offers"][0].duplicate(true)
	reverse["id"]="capital_carriage:paris_lyon";reverse["source_site"]="site:regional_food:paris";reverse["target_site"]="site:regional_upstream:lyon"
	reverse["known_to"]=["firm:regional_upstream"]
	reverse["legs"]=[{"edge_id":"edge:regional:paris:lyon","carrier":"firm:regional_food","fee":6}]
	result["capital_transport"]["offers"].append(reverse)
	var freight: Dictionary={}
	for budget: Dictionary in result["procurement_budgets"]:
		if budget["category"]=="capital_freight": freight=budget.duplicate(true);break
	freight["id"]="budget:development:upstream:capital_freight";freight["subject"]="organization:development_regional_upstream";freight["root_authority"]="capital_disposition:firm:regional_upstream"
	result["procurement_budgets"].append(freight)
	return result

## Finite existing competition network. Only the declared manager changes;
## stocks, cash, workers, investment criteria and transport resources do not.
static func player_capital_trade_regional_template(role: String="buyer") -> Dictionary:
	var result:=npc_capital_competition_regional_template()
	var managed:="firm:regional_textile" if role=="seller" else "firm:regional_food"
	result["case_id"]="FORMAL_PLAYER_CAPITAL_SALE_DEVELOPMENT" if role=="seller" else "FORMAL_PLAYER_CAPITAL_TRADE_DEVELOPMENT"
	result["firms"].sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if a["id"]==b["id"]: return false
		if a["id"]==managed: return true
		if b["id"]==managed: return false
		return a["id"]<b["id"])
	var authorities: Array=[]
	for source: Dictionary in result["capital_resale"]["authorities"]:
		if source["firm"]!=managed: authorities.append(source);continue
		for operation: String in source["operations"]:
			var authority: Dictionary=source.duplicate(true)
			authority["id"]=source["id"]+("" if operation=="acquire" else ":"+operation)
			authority["controller"]="HOST_SELECTED_PLAYER";authority["operations"]=[operation]
			authority["root_authority"]="authority:development:player_capital:"+managed.trim_prefix("firm:")+":"+operation
			authorities.append(authority)
	result["capital_resale"]["authorities"]=authorities
	result["capital_resale"]["authority_places"]=[result["firms"][0]["sites"][0]["place_id"]]
	for budget: Dictionary in result["procurement_budgets"]:
		if budget["subject"]=="organization:development_"+managed.trim_prefix("firm:") and budget["category"]=="capital_freight": budget["root_authority"]+="\u003afreight"
	return result

## One opening resource set from the player capital network. Only future labor
## rules are adapted to its existing jobs and local residents. Sales use the
## original producer delivery channel; no shop, cash, worker or stock is copied.
static func economy_feedback_regional_template() -> Dictionary:
	var result:=player_capital_trade_regional_template()
	result["case_id"]="FORMAL_ECONOMY_FEEDBACK_DEVELOPMENT"
	var labor:=labor_market_regional_template()["labor_market"] as Dictionary
	var market:={"job_rules":[],"authorities":[],"npc_policies":[],"worker_policies":[],"basis":"EXPLICIT_DEVELOPMENT_LABOR_MARKET"}
	for job: Dictionary in result["jobs"]:
		for source: Dictionary in labor["job_rules"]:
			if source["job_id"]!=job["id"]: continue
			var rule:=source.duplicate(true)
			rule["recipients"]=[]
			for actor: Dictionary in result["actors"]:
				if actor["place_id"]==job["place"]: rule["recipients"].append(actor["id"])
			if job["place"]=="place:paris": rule["recipients"].append("HOST_SELECTED_PLAYER")
			market["job_rules"].append(rule)
		for source: Dictionary in labor["npc_policies"]:
			if source["job_id"]==job["id"] and job["employer"]!="firm:regional_food": market["npc_policies"].append(source.duplicate(true))
	for source: Dictionary in labor["authorities"]:
		if source["firm"]=="firm:regional_food": continue # Capital management grants no employment finance authority.
		var authority:=source.duplicate(true)
		authority["controller"]=authority["firm"]
		market["authorities"].append(authority)
	for actor: Dictionary in result["actors"]:
		if actor["control"]=="automatic": market["worker_policies"].append({"actor":actor["id"],"review_days":3,"minimum_hourly_gain":1,"max_move_workers":2,"basis":"EXPLICIT_DEVELOPMENT_KNOWN_LOCAL_JOB_CHOICE"})
	result["labor_market"]=market
	return result

## Optional sandbox experiment. Existing businesses and physical/cash endowments
## stay unchanged. The finite founder allocation is an explicit development
## right source, not historical calibration, company financing or management.
static func equity_feedback_regional_template() -> Dictionary:
	var result:=economy_feedback_regional_template()
	var issuer: String="firm:regional_food"
	var seller: String="firm:regional_household"
	var buyer: String="firm:regional_upstream"
	result["assets"]=[{"id":"asset:regional_food:ordinary","issuer":issuer,"total_shares":100,"holders":{seller:60,buyer:30,"HOST_SELECTED_PLAYER":10},"manager":issuer,"known_to":[seller,buyer,"HOST_SELECTED_PLAYER"]}]
	var participants: Array=[]
	for entry: Array in [[seller,false,true,"LIQUIDITY",2,300,0,5,100,0],[buyer,true,false,"HOLDING",3,0,36,5,49,160],["HOST_SELECTED_PLAYER",true,true,"PLAYER",1,0,0,20,49,0]]:
		participants.append({"actor":entry[0],"buy":entry[1],"sell":entry[2],"policy":entry[3],"period":entry[4],"target_cash":entry[5],"target_position":entry[6],"max_quantity":entry[7],"max_position":entry[8],"cash_floor":entry[9],"start":0,"end":30*1440,"bid_limit":12,"ask_limit":10,"basis":"EXPLICIT_DEVELOPMENT_PORTFOLIO_MANDATE"})
	result["equity_call_market"]={"basis":"GENERATED_SIMULATION_ASSUMPTION_EQUITY_CALL","asset_id":"asset:regional_food:ordinary","organization_id":"organization:development_regional_food","share_class":"ECONOMIC_INTEREST_NO_AUTOMATIC_CONTROL","genesis_basis":"EXPLICIT_DEVELOPMENT_FOUNDER_ALLOCATION","notice_days":1,"report_period":3,"max_valid_minutes":7*1440,"participants":participants}
	return result


## Same physical/cash endowments as the secondary-share world. The operating
## reserve is a disclosed managerial precaution, not fabricated wage/debt.
static func primary_equity_feedback_regional_template() -> Dictionary:
	var result:=equity_feedback_regional_template()
	for t: Dictionary in result["capital_investment"]["templates"]:
		if t["id"]=="investment:regional_food:paris": t["cash_floor"]=350
	for p: Dictionary in result["equity_call_market"]["participants"]:
		if p["actor"]=="firm:regional_upstream": p["sell"]=true
	result["equity_primary"]={"basis":"GENERATED_SIMULATION_ASSUMPTION_PRIMARY_PROGRAM","asset_id":"asset:regional_food:ordinary","issuer":"firm:regional_food","controller":"HOST_SELECTED_PLAYER","authority_id":"authority:development:primary:regional_food","max_new_shares":20,"price":10,"minimum":5,"duration_days":5,"start":0,"end":30*1440,"template_id":"investment:regional_food:paris","issuer_policy":"PLAYER","max_per_investor":10,"npc_quantity":5,"npc_target":45,"consenting_holders":["firm:regional_household","firm:regional_upstream","HOST_SELECTED_PLAYER"],"dilution_basis":"ALL_FOUNDERS_CONSENT_BOUNDED_PROGRAM_NO_PREEMPTION"}
	return result


## Optional, independently authorised cash-distribution experiment. No endowment.
static func cash_distribution_equity_feedback_regional_template() -> Dictionary:
	var result:=primary_equity_feedback_regional_template()
	result["equity_distribution"]={"basis":"GENERATED_SIMULATION_ASSUMPTION_SHAREHOLDER_CASH_DISTRIBUTION","asset_id":"asset:regional_food:ordinary","issuer":"firm:regional_food","controller":"HOST_SELECTED_PLAYER","authority_id":"authority:development:distribution:regional_food","max_total":240,"max_per_share":2,"cash_floor":350,"delay_days":2,"start":0,"end":90*1440,"consenting_holders":["firm:regional_household","firm:regional_upstream","HOST_SELECTED_PLAYER"]}
	return result

## Same endowments. Only existing finite service/use-right permissions compose.
static func cash_responsibility_feedback_regional_template() -> Dictionary:
	var result:=cash_distribution_equity_feedback_regional_template()
	result["service_market"]=service_regional_template()["service_market"].duplicate(true)
	result["service_market"]["npc_policies"]=[]
	var jobs: Array=[]
	for job: Dictionary in result["jobs"]: jobs.append(job["id"])
	for offer: Dictionary in result["service_market"]["offers"]: offer["job_ids"]=offer["job_ids"].filter(func(id: String)->bool:return id in jobs)
	for a: Dictionary in result["service_market"]["authorities"]:
		if a["firm"]=="firm:regional_food": a["controller"]="HOST_SELECTED_PLAYER"
		elif a["firm"]=="firm:regional_upstream": a["controller"]=a["firm"]
	var lease: Dictionary=lease_regional_template()["lease_market"]
	result["lease_market"]={"basis":lease["basis"],"objects":[],"offers":[],"authorities":[],"housing_targets":[],"npc_policies":[]}
	for o: Dictionary in lease["objects"]:
		if o["kind"]=="COMMERCIAL_PREMISES": result["lease_market"]["objects"].append(o.duplicate(true))
	for o: Dictionary in lease["offers"]:
		if o["object_id"]==result["lease_market"]["objects"][0]["id"]:
			var offer:=o.duplicate(true);offer["max_days"]=60
			result["lease_market"]["offers"].append(offer)
	for a: Dictionary in lease["authorities"]:
		if a["firm"] not in ["firm:regional_upstream","firm:regional_food"]: continue
		var authority:=a.duplicate(true)
		authority["controller"]="HOST_SELECTED_PLAYER" if a["firm"]=="firm:regional_food" else a["firm"]
		authority["limit"]=180
		result["lease_market"]["authorities"].append(authority)
	for category: String in ["service:storage","service:repair","lease:commercial_premises"]:
		result["procurement_budgets"].append({"id":"budget:responsibility:"+category,"subject":"organization:development_regional_food","root_authority":("lease_authority:" if category.begins_with("lease:") else "service_authority:")+"firm:regional_food","denomination":FormalLedgerState.DENOMINATION,"category":category,"start_minute":0,"end_minute":60*1440,"limit":180,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	result["procurement_budgets"].append({"id":"budget:responsibility:food_grain","subject":"organization:development_regional_food","root_authority":"development:food_grain_authority","denomination":FormalLedgerState.DENOMINATION,"category":"goods:grain","start_minute":0,"end_minute":60*1440,"limit":500,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"})
	return result

## Independent opt-in corporate manager; no copied cash, stock or population.
static func corporate_decisions_feedback_regional_template(mode: String="finance",active: bool=true) -> Dictionary:
	var result:=cash_responsibility_feedback_regional_template()
	result["equity_primary"]["issuer_policy"]="PROJECT_GAP"
	result["corporate_decisions"]={"basis":"GENERATED_SIMULATION_ASSUMPTION_CORPORATE_FINANCE","issuer":"firm:regional_food","controller":"HOST_NPC_MANAGER","period_days":3,"issue_enabled":active and mode=="finance","distribution_enabled":active and mode=="distribution","plan_investment":mode=="finance","retained_surplus":20,"per_share":1,"max_dilution_percent":20}
	var lease_policy: Dictionary=lease_regional_template()["lease_market"]["npc_policies"][1].duplicate(true)
	lease_policy["term_days"]=60;lease_policy["max_total"]=150
	result["lease_market"]["npc_policies"].append(lease_policy)
	if mode=="finance":
		result["capital_investment"]["npc_policies"].append({"template_id":"investment:regional_food:paris","window_days":3,"minimum_pressure":4,"minimum_utilization_percent":50,"cooldown_days":90})
	# This manager's capital mandate is formation of the approved local project;
	# existing sellers and other businesses retain their own operating policies.
	result["capital_resale"]["autonomous_policies"]=result["capital_resale"]["autonomous_policies"].filter(func(p: Dictionary)->bool:return p["buyer"]!="firm:regional_food" and p["seller"]!="firm:regional_food")
	return result
