class_name FormalEconomicOpening
extends RefCounted
## One bounded ordinary opening. It uses host persons/accounts and the native
## execution kernel. Saved worlds bind their saved config without genesis.
const SINGLE_PATH := "res://data/formal/paris_workshop_opening_r1.json"
const MATERIAL_RENEWAL_CASE := "FORMAL_PARIS_FINITE_MATERIAL_RENEWAL_R1"
const SECOND_WORKER_CASE := "FORMAL_PARIS_TWO_WORKERS_OPENING_R1"
const GRAIN_BREAD_CASE := "FORMAL_PARIS_GRAIN_BREAD_CYCLE_R1"
const PATH := "res://data/formal/paris_employment_opening_r1.json"

static func for_source(source_id: String) -> Dictionary:
	if "--formal-single-employer-opening" in OS.get_cmdline_user_args(): return single_employer(source_id)
	if source_id != "country_fra": return {}
	if "--formal-grain-bread-opening" in OS.get_cmdline_user_args(): return grain_bread(source_id)
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
	return result

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

## A separate genesis declaration, not an amendment of existing employment or
## the old 8+4 mandates. The grain activity is a development production assumption,
## not a simulation of land, seed, seasons or agricultural resources.
static func grain_bread(source_id: String) -> Dictionary:
	var result := second_worker(source_id)
	if result.is_empty(): return result
	result["case_id"] = GRAIN_BREAD_CASE
	result["management_scope"]["id"] = "scope:formal_paris_grain_bread_cycle_r1"
	for actor: Dictionary in result["actors"]:
		if actor["control"] == "automatic": actor["stock"]["bread"] = 1
	for firm: Dictionary in result["firms"]:
		var upstream: bool = firm["id"] == "firm:opening_paris_workshop"
		var site: Dictionary = firm["sites"][0]
		site["stock"] = {"beans": 0, "bread": 0 if upstream else 10, "grain": 4 if upstream else 2}
		if upstream:
			site["targets"] = {"beans": 0, "bread": 0, "grain": 8}
			site["prices"] = {"grain": 2}
			site["activities"] = [{"id": "activity:opening_paris_development_grain", "place_id": "place:paris", "outputs": {"grain": 2}, "materials": EconomySliceConfig.ZERO.duplicate(), "hours": 1, "capacity_units": 1, "enabled": true, "basis": "DEVELOPMENT_CONFIGURATION"}]
	for job: Dictionary in result["jobs"]:
		job["wage_per_hour"] = 1
		job["wage_delay"] = 0
	result["retail_sites"][0]["stock_units"] = {"grain": 1}
	result["information"] = result["information"].filter(func(row: Dictionary) -> bool: return row["candidate"] != "firm:opening_paris_workshop|bread|site:opening_paris_workshop:paris")
	for opening: Dictionary in result["opening_organizations"]:
		var trade: Dictionary = opening["material_trade"]
		var name: String = opening["firm_id"].trim_prefix("firm:")
		trade.merge({"id": "material_mandate:" + name + ":grain_bread_1:" + trade["operation"], "issuer": opening["organization_id"], "price": 2, "quantity_limit": 64, "valid_from": 0, "valid_until": 60 * 1440, "revocation_id": "material_resolution:" + name + ":grain_bread_1:revoke:" + trade["operation"], "basis": "GENERATED_OPENING_GRAIN_BREAD_ORGANIZATION_RESOLUTION"}, true)
		opening["notice"] = "本显式新开局的模拟组织，持有原企业账户与本站产出。工坊以实际劳动及基础容量按1生产小时产2粮，无材料输入，仅为简化开发能力，不代表土地、种子或季节系统；面包坊按1粮及1生产小时产2面包。各岗位2小时、时薪1、完成劳动当日到期；各1小时销售，日限4件。组织在开局分别决定SELL/PROCURE，限原对手、粮食单价2、累计64粮、有效区间[0,86400)，卖方保底4。授权和本组织固定撤销决议均在开局声明，原企业只执行既定条款，无自行扩额或续期权；雇员和玩家无签发权。撤销或到期仅阻止后续受理，保留已受理责任。居民各1个开仓面包，全部开仓合计6粮、12面包、4300现金，仅入账一次。"
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
