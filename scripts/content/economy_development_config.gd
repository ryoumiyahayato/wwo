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
static func formal_arrival_notices(settings: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job: Dictionary in settings.get("jobs", []):
		result.append({"place_id": job["place"], "kind": "job", "candidate": job["id"]})
	for firm: Dictionary in settings.get("firms", []):
		for site: Dictionary in firm.get("sites", []):
			for good: String in site["prices"]:
				result.append({"place_id": site["place_id"], "kind": "supplier", "candidate": str(firm["id"])+"|"+good+"|"+str(site["id"])})
	return result

## A selection is resolved after host population, identities, accounts and places
## exist. Explicit person IDs never materialize a new person. An empty selection
## chooses only already admitted people at the configured operating places.
static func formal_regional_request(person_ids: Array[String] = []) -> Dictionary:
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": regional_template()}

## Separate opt-in selection; does not restore or change any main-menu entry.
static func formal_stratified_request(person_ids: Array[String] = []) -> Dictionary:
	if OS.get_cmdline_user_args().has("--formal-liquidity-policy"): return formal_liquidity_request(person_ids)
	return {"format": "HOST_REGION_SELECTION", "person_ids": person_ids.duplicate(), "select_people_at_sites": person_ids.is_empty(), "configuration": stratified_regional_template()}

static func formal_liquidity_request(person_ids: Array[String] = []) -> Dictionary:
	return {"format":"HOST_REGION_SELECTION","person_ids":person_ids.duplicate(),"select_people_at_sites":person_ids.is_empty(),"configuration":liquidity_regional_template()}

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
					if int(counts.get(good, 0)) >= 3: continue
					result["information"].append({"actor": id, "kind": "supplier", "candidate": str(firm["id"]) + "|" + good + "|" + str(site["id"]), "delivery_day": 0})
					counts[good] = int(counts.get(good, 0)) + 1
		for job: Dictionary in result["jobs"]:
			if job["place"] == place: result["information"].append({"actor": id, "kind": "job", "candidate": job["id"], "delivery_day": 0})
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
		result["firms"][0]["manager"] = world.player_state.player_id()
	for authority: Dictionary in result.get("firm_finance_authorities",[]):
		if authority["controller"]=="HOST_SELECTED_PLAYER": authority["controller"]=world.player_state.player_id()
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
