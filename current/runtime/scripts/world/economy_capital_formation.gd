class_name EconomyCapitalFormation
extends RefCounted
## Projects, equipment and built space assets only. Goods, wages, money and time belong
## to the injected formal world. A capacity pool is shared by its activities.
const FORMAT := "economy_capital_formation_v1"
const MOVE_KINDS = ["DISMANTLE", "HANDOVER", "REINSTALL"]
var resale_offers: Dictionary = {}
var resale_trades: Dictionary = {}
# Derived from delivered R1 messages and this settlement only; never a second queue.
var _known_quotes: Dictionary = {}
var _npc_observations: Dictionary = {}
var _npc_reviews: Dictionary = {}

const BUILD_KINDS := ["RESIDENTIAL_BUILD", "COMMERCIAL_PREMISES_BUILD"]
const LIMIT := 256
const TERMINAL := ["COMPLETED", "CANCELLED"]
var error: String = ""
var _kernel: WeakRef
var projects: Dictionary = {}
var assets: Dictionary = {}
var changes: Dictionary = {}
var _active: Array[String] = []
var _pending: Array[String] = []
var _site_assets: Dictionary = {}
var _site_projects: Dictionary = {}
var _labor_allocations: Dictionary = {}
var _project_changes: Dictionary = {}
var _active_by_site: Dictionary = {}
var _firm_last_project: Dictionary = {}
var _labor_totals: Dictionary = {}
var _last_build_work: Dictionary = {}
var _templates: Dictionary = {}
var _pool_cache: Dictionary = {}
var _templates_ready: bool = false
var _construction_claims: Dictionary = {}

func bind(kernel: EconomyR1Slice) -> void:
	_kernel = weakref(kernel)

func _economy() -> EconomyR1Slice:
	return _kernel.get_ref() as EconomyR1Slice

static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	if not resale_configuration_valid(settings, spec): return false
	if not settings.has("capital_investment"): return true
	var value: Variant = settings["capital_investment"]
	if not value is Dictionary or not EconomySliceConfig._fields(value, ["templates", "npc_policies"], ["building_policies"]) or not value["templates"] is Array or value["templates"].size() > 128 or not value["npc_policies"] is Array: return false
	var sites := spec["sites"].duplicate(true) as Dictionary
	var firms := spec["firms"].duplicate(true) as Dictionary
	for option: Dictionary in settings.get("runtime_expansions", []):
		# A declared future company still has to pass host commercial identity,
		# account and zero-endowment admission before any investment can start.
		for firm: Variant in option["extension"].get("firms", []):
			if not firm is Dictionary or not firm.get("id") is String or not firm.get("sites") is Array: return false
			if not firms.has(firm["id"]): firms[firm["id"]] = firm
			for raw: Variant in firm["sites"]:
				if not raw is Dictionary or not raw.get("id") is String or not raw.get("activities") is Array: return false
				var site := raw.duplicate(true) as Dictionary
				site["firm_id"] = firm["id"]
				if not sites.has(site["id"]): sites[site["id"]] = site
		for item: Variant in option["extension"].get("sites", []):
			if not item is Dictionary or not item.get("site") is Dictionary or not item.get("firm_id") is String or not item["site"].get("id") is String or not item["site"].get("activities") is Array: return false
			var site := item["site"].duplicate(true) as Dictionary
			site["firm_id"] = item["firm_id"]
			sites[site["id"]] = site
	var uses: Dictionary = {}
	for good: Dictionary in settings.get("goods", []): uses[good["id"]] = good.get("capital_uses", [])
	var seen: Dictionary = {}
	for row: Variant in value["templates"]:
		if not row is Dictionary or not EconomySliceConfig._fields(row, ["id", "firm", "site_id", "kind", "asset_type", "capacity", "activities", "materials", "hours", "hours_per_day", "duration_minutes", "max_projects", "budget", "cash_floor", "denomination", "basis"], ["maintenance", "building"]): return false
		for key: String in ["id", "firm", "site_id", "asset_type", "denomination"]:
			if not row[key] is String or row[key].is_empty(): return false
		if seen.has(row["id"]) or not firms.has(row["firm"]) or not sites.has(row["site_id"]) or sites[row["site_id"]]["firm_id"] != row["firm"] or row["kind"] not in ["EXPAND", "INSTALL", "NEW_SITE"]+BUILD_KINDS or row["basis"] != "DEVELOPMENT_CAPITAL_PERMISSION": return false
		if row["denomination"] != firms[row["firm"]].get("denomination", FormalLedgerState.DENOMINATION): return false
		for key: String in ["capacity", "hours", "hours_per_day", "duration_minutes", "max_projects", "budget"]:
			if not FormalLedgerState.valid_amount(row[key]) or int(row[key]) < 1 or int(row[key]) > 1000000: return false
		if int(row["max_projects"]) > 4 or not FormalLedgerState.valid_amount(row["cash_floor"]) or not _materials_valid(row["materials"], spec["good_ids"]) or not row["activities"] is Array or (row["activities"].is_empty() and row["kind"] not in BUILD_KINDS): return false
		var equipment := false
		for good: String in row["materials"]:
			var purposes: Array = uses.get(good, [])
			if purposes.is_empty(): return false
			equipment = equipment or purposes.has("INSTALLABLE_EQUIPMENT")
		if row["kind"] in BUILD_KINDS:
			if not _building_valid(row,sites,settings) or not (uses.get("building_material",[]) as Array).has("CONSTRUCTION_MATERIAL") or not row["materials"].has("building_material"): return false
		elif row.has("building") or not equipment: return false
		var ids: Array[String] = []
		for activity: Dictionary in sites[row["site_id"]]["activities"]: ids.append(activity["id"])
		var allowed: Dictionary = {}
		for id: Variant in row["activities"]:
			if not id is String or not ids.has(id) or allowed.has(id): return false
			allowed[id] = true
		if row["kind"] == "NEW_SITE" and int(sites[row["site_id"]]["capacity"]) != 0: return false
		if row.has("maintenance"):
			var maintenance: Variant = row["maintenance"]
			if not maintenance is Dictionary or not FormalLedgerState.exact_fields(maintenance, ["materials", "hours", "hours_per_day", "duration_minutes"]) or not _materials_valid(maintenance["materials"], spec["good_ids"]): return false
			for good: String in maintenance["materials"]:
				if not (uses.get(good, []) as Array).has("MAINTENANCE_INPUT"): return false
			for key: String in ["hours", "hours_per_day", "duration_minutes"]:
				if not FormalLedgerState.valid_amount(maintenance[key]) or int(maintenance[key]) < 1 or int(maintenance[key]) > 1000000: return false
		seen[row["id"]] = row
	var policies: Dictionary = {}
	for row: Variant in value["npc_policies"]:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["template_id", "window_days", "minimum_pressure", "minimum_utilization_percent", "cooldown_days"]): return false
		if not row["template_id"] is String or not seen.has(row["template_id"]) or policies.has(row["template_id"]) or seen[row["template_id"]]["kind"] in BUILD_KINDS: return false
		for key: String in ["window_days", "minimum_pressure", "cooldown_days"]:
			if not FormalLedgerState.valid_amount(row[key]) or int(row[key]) < 1 or int(row[key]) > 365: return false
		if not FormalLedgerState.valid_amount(row["minimum_utilization_percent"]) or int(row["minimum_utilization_percent"]) > 100: return false
		if int(row["window_days"]) > 30: return false
		policies[row["template_id"]] = true
	var rights: Dictionary={};var objects: Dictionary={};var spaces:Dictionary={}
	for row: Dictionary in value["templates"]:
		if row["kind"] not in BUILD_KINDS:continue
		var building:=row["building"] as Dictionary
		if rights.has(building["permit"]["id"]) or spaces.has(building["permit"]["space_id"]) or objects.has(building["object"]["id"]):return false
		rights[building["permit"]["id"]]=true;spaces[building["permit"]["space_id"]]=true;objects[building["object"]["id"]]=true
	var build_policies: Variant=value.get("building_policies",[])
	if not build_policies is Array or build_policies.size()>32:return false
	var policy_ids: Dictionary={}
	for p: Variant in build_policies:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["template_id","window_days","minimum_paid_rent","cash_floor","require_no_vacancy","basis"]) or not seen.has(p.get("template_id")) or seen[p["template_id"]]["kind"] not in BUILD_KINDS or policy_ids.has(p["template_id"]) or not p["require_no_vacancy"] is bool or p["basis"]!="EXPLICIT_DEVELOPMENT_BUILD_FROM_OWN_PAID_RENT":return false
		for key: String in ["window_days","minimum_paid_rent","cash_floor"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]>1000000:return false
		if p["window_days"]<1 or p["window_days"]>30 or p["minimum_paid_rent"]<1:return false
		policy_ids[p["template_id"]]=true
	return true

static func _building_valid(t:Dictionary,sites:Dictionary,settings:Dictionary)->bool:
	var b:Variant=t.get("building")
	if not b is Dictionary or not FormalLedgerState.exact_fields(b,["permit","object","offer"]) or not b["permit"] is Dictionary or not b["object"] is Dictionary or not b["offer"] is Dictionary or not settings.has("lease_market") or not t["activities"].is_empty():return false
	var p:=b["permit"] as Dictionary;var o:=b["object"] as Dictionary
	if not FormalLedgerState.exact_fields(p,["id","space_id","unit","holder","controller","place_id","kind","slots","valid_from","valid_until","source","root_authority","basis","slot_rule"]):return false
	for key:String in ["id","space_id","unit","holder","controller","place_id","kind","source","root_authority"]:
		if not p[key] is String or (p[key].is_empty() and key!="root_authority"):return false
	if p["unit"]!="development_construction_plot_share" or not p["space_id"].begins_with("construction_space:") or p["holder"]!=t["firm"] or p["place_id"]!=sites[t["site_id"]]["place_id"] or p["kind"]!=t["kind"] or p["slots"]!=1 or p["basis"]!="EXPLICIT_DEVELOPMENT_CONSTRUCTION_USE_PERMISSION" or p["slot_rule"]!="RESERVE_ON_ACCEPTANCE_NO_AUTOMATIC_REUSE":return false
	for key:String in ["valid_from","valid_until"]:
		if not FormalLedgerState.valid_amount(p[key]) or p[key]%1440!=0:return false
	if p["valid_until"]<=p["valid_from"]:return false
	if o.get("lessor")!=t["firm"] or o.get("place_id")!=p["place_id"] or o.get("kind")!=("RESIDENTIAL_SPACE" if t["kind"]=="RESIDENTIAL_BUILD" else "COMMERCIAL_PREMISES") or o.get("capacity")!=t["capacity"] or o.get("capital_asset_id")!="" or o.get("capacity_basis")!="CAPITAL_ASSET_CAPACITY_PROJECTION":return false
	if o.get("rights_source")!={"id":p["id"],"holder":t["firm"],"basis":"COMPLETED_CAPITAL_PROJECT_REQUIRED","note":p["source"]}:return false
	return b["offer"].get("object_id")==o.get("id") and b["offer"].get("denomination")==t["denomination"]

static func _materials_valid(value: Variant, goods: Array) -> bool:
	if not value is Dictionary or value.is_empty(): return false
	for good: Variant in value:
		if not good is String or not goods.has(good) or not FormalLedgerState.valid_amount(value[good]) or int(value[good]) < 1 or int(value[good]) > 1000000: return false
	return true

func invalidate_configuration() -> void:
	_templates.clear()
	_templates_ready = false
	_pool_cache.clear()

func template(id: String) -> Dictionary:
	if not _templates_ready:
		for row: Dictionary in _economy().config.get("capital_investment", {}).get("templates", []): _templates[row["id"]] = row
		_templates_ready = true
	return _templates.get(id, {})

func request(actor: String, payload: Dictionary, action_id: String, kind: String) -> Dictionary:
	var e := _economy()
	var now := e._world.game_clock.total_minutes()
	if kind in ["investment_status", "capital_status"]:
		var key := "project_id" if kind == "investment_status" else "asset_id"
		if not FormalLedgerState.exact_fields(payload, [key, "status"]) or not payload[key] is String or not payload["status"] is String: return _reject("INVALID_CAPITAL_CONTROL")
		var row := projects.get(payload[key], {}) as Dictionary if kind == "investment_status" else assets.get(payload[key], {}) as Dictionary
		if key=="project_id" and row.get("kind") in MOVE_KINDS: return _reject("MOBILE_WORK_RETAINS_PROGRESS_NO_CANCELLATION_POLICY")
		var current := asset_state(str(payload[key])) if key=="asset_id" else {}
		var control_firm: String = current.get("owner", row.get("firm", ""))
		var control_site: String = current.get("site_id", row.get("site_id", ""))
		if key=="asset_id" and (move_busy(str(payload[key])) or current.get("status") in ["DISMANTLING","DETACHED","REINSTALLING"]): return _reject("EQUIPMENT_NOT_INSTALLED_OR_COMMITTED_TO_TRANSFER")
		if key=="asset_id" and e._service_market.asset_busy(str(payload[key])): return _reject("EXTERNAL_MAINTENANCE_CONTRACT_REMAINS")
		if row.is_empty() or not e._manager(actor, control_firm): return _reject("NOT_CAPITAL_MANAGER")
		if kind == "investment_status" and (row["status"] in TERMINAL or payload["status"] not in ["ACTIVE", "PAUSED", "CANCELLED"]): return _reject("PROJECT_CANNOT_CHANGE_STATUS")
		if kind == "capital_status" and (row["status"] in ["MAINTENANCE", "RETIRED"] or payload["status"] not in ["ACTIVE", "PAUSED", "RETIRED"]): return _reject("EQUIPMENT_CANNOT_CHANGE_STATUS")
		var construction_control:Dictionary={}
		if kind=="investment_status" and row["kind"] in BUILD_KINDS and payload["status"]=="ACTIVE":
			construction_control=construction_permission(actor,template(row["template_id"]),row["budget"],now)
			if not construction_control["ok"]:return _reject(construction_control["reason"])
		if kind == "capital_status" and payload["status"] == row["status"]: return _reject("EQUIPMENT_ALREADY_IN_REQUESTED_STATE")
		if payload["status"] == "ACTIVE" and (e.site_closed(control_site) or e.firm_finished(control_firm)): return _reject("CAPITAL_SITE_CLOSED")
		if changes.size() >= LIMIT: return _reject("CAPITAL_HISTORY_LIMIT")
		for id: String in _pending:
			if changes[id]["kind"] == kind and changes[id]["payload"][key] == payload[key]: return _reject("CAPITAL_CHANGE_PENDING")
		changes[action_id] = {"id": action_id, "actor": actor, "kind": kind, "payload": payload.duplicate(true), "requested_minute": now, "boundary_minute": (e.day+1)*1440, "effective_minute": -1, "status": "QUEUED", "reason": ""}
		if not construction_control.is_empty():changes[action_id]["construction_authority"]=construction_control
		_pending.append(action_id)
		if kind == "investment_status":
			if not _project_changes.has(payload[key]): _project_changes[payload[key]] = []
			_project_changes[payload[key]].append(action_id)
		return {"accepted": true, "reason": "QUEUED", "boundary_minute": (e.day+1)*1440}
	var maintenance := kind == "maintain_capital"
	if maintenance and _economy()._service_market.asset_busy(str(payload.get("asset_id",""))): return _reject("EXTERNAL_MAINTENANCE_CONTRACT_REMAINS")
	var fields: Array[String] = []
	fields.assign(["asset_id", "budget"] if maintenance else ["template_id", "budget"])
	if not FormalLedgerState.exact_fields(payload, fields) or not FormalLedgerState.valid_amount(payload["budget"]) or int(payload["budget"]) < 1: return _reject("INVALID_INVESTMENT")
	if not payload["asset_id" if maintenance else "template_id"] is String: return _reject("INVALID_CAPITAL_ID")
	var original := assets.get(payload.get("asset_id", ""), {}) as Dictionary
	var terms := maintenance_template(str(payload.get("asset_id","")),now) if maintenance else template(str(payload.get("template_id", "")))
	if maintenance and (move_busy(str(payload.get("asset_id",""))) or live_asset_offer(str(payload.get("asset_id","")))): return _reject("ASSET_COMMITTED_TO_DISPOSAL")
	if terms.is_empty() or (maintenance and (original.is_empty() or not terms.has("maintenance") or original["status"] not in ["ACTIVE", "PAUSED"])): return _reject("NO_CONFIGURED_CAPITAL_PERMISSION")
	var firm := str(terms["firm"])
	var site := str(terms["site_id"])
	if not e._manager(actor, firm): return _reject("NOT_FIRM_MANAGER")
	if not e._spec["sites"].has(site): return _reject("PREPARE_LEGAL_ZERO_RESOURCE_SITE_FIRST")
	if not e._site_operating(site) or e._firm_winding_down(firm) or e.site_closed(site): return _reject("FIRM_NOT_ACCEPTING_INVESTMENT")
	if projects.size() >= LIMIT or int(payload["budget"]) > int(terms["budget"]): return _reject("INVESTMENT_BUDGET_OR_PROJECT_LIMIT")
	if active_count(firm) >= int(terms["max_projects"]): return _reject("CONCURRENT_INVESTMENT_LIMIT")
	if maintenance:
		for id: String in _active:
			if projects[id]["asset_id"] == original["id"]: return _reject("MAINTENANCE_ALREADY_REQUESTED")
	var construction:Dictionary={}
	if not maintenance and terms["kind"] in BUILD_KINDS:
		construction=construction_permission(actor,terms,int(payload["budget"]),now)
		if not construction.get("ok",false):return _reject(construction.get("reason","NO_CONSTRUCTION_PERMISSION"))
		if _construction_claims.has(terms["building"]["permit"]["id"]):return _reject("CONSTRUCTION_SPACE_ALREADY_COMMITTED")
		if e._world.ledger_state.available_balance(e._account(firm,terms["denomination"]))<int(payload["budget"])+e._capital_cash_protected(firm,terms):return _reject("CONSTRUCTION_REAL_CASH_NOT_AVAILABLE")
	var id := "capital_project:"+action_id
	projects[id] = {"id": id, "action_id": action_id, "actor": actor, "template_id": terms["id"], "firm": firm, "site_id": site, "kind": "MAINTENANCE" if maintenance else terms["kind"], "accepted_minute": now, "budget": payload["budget"], "status": "ACCEPTED", "materials": {}, "material_minute": -1, "work": [], "started_minute": -1, "completed_minute": -1, "orders": [], "asset_id": original.get("id", ""), "reason": ""}
	if not construction.is_empty():
		projects[id]["construction_authority"]=construction
		_construction_claims[terms["building"]["permit"]["id"]]=id
	_active.append(id)
	if not _active_by_site.has(site): _active_by_site[site] = []
	_active_by_site[site].append(id)
	_firm_last_project[firm] = now
	if not _site_projects.has(site): _site_projects[site] = []
	_site_projects[site].append(id)
	return {"accepted": true, "reason": "ACCEPTED", "project_id": id, "budget": payload["budget"]}

func terms_for(project: Dictionary) -> Dictionary:
	if project["kind"] in MOVE_KINDS: return move_terms(project)
	var terms := template(project["template_id"]).duplicate(true)
	if project["kind"] == "MAINTENANCE": terms.merge(terms["maintenance"], true)
	return terms

func active_count(firm: String) -> int:
	var count := 0
	for id: String in _active:
		if projects[id]["firm"] == firm: count += 1
	return count

func goods_needed(site: String, good: String) -> int:
	var amount := 0
	for id: String in _active_by_site.get(site, []):
		var p := projects[id] as Dictionary
		if p["status"] not in TERMINAL and p["status"] != "PAUSED" and p["materials"].is_empty(): amount += int(terms_for(p)["materials"].get(good, 0))
	return amount

func labor_needed(site: String) -> int:
	var amount := 0
	for id: String in _active_by_site.get(site, []):
		var p := projects[id] as Dictionary
		if p["status"] not in TERMINAL and p["status"] != "PAUSED": amount += mini(int(terms_for(p)["hours_per_day"]), maxi(0, int(terms_for(p)["hours"])-work_hours(p)))
	return amount

func work_hours(p: Dictionary) -> int:
	var result := 0
	for row: Dictionary in p["work"]: result += int(row["hours"])
	return result

func allocated_hours(site: String, settled_day: int = -1) -> int:
	return int(_labor_totals.get(site, 0)) if settled_day < 0 else int(_labor_allocations.get(site, {}).get(settled_day, 0))

func _index_labor(site: String, settled_day: int, hours: int) -> void:
	if not _labor_allocations.has(site): _labor_allocations[site] = {}
	_labor_totals[site] = int(_labor_totals.get(site, 0))+hours
	_labor_allocations[site][settled_day] = int(_labor_allocations[site].get(settled_day, 0))+hours

func remaining_labor_budget(p: Dictionary) -> int:
	var e := _economy()
	var rate: int=maxi(0,e._labor_market.estimate_rate(p["site_id"],terms_for(p)["denomination"]))
	var hours := maxi(0, int(terms_for(p)["hours"])-work_hours(p))
	return FormalLedgerState.MAX_AMOUNT if rate > 0 and hours > FormalLedgerState.MAX_AMOUNT/rate else hours*rate

func committed_cost(p: Dictionary, orders: Dictionary = {}, work_records: Dictionary = {}, wages: Dictionary = {}) -> int:
	var e := _economy()
	if orders.is_empty(): orders = e._orders
	if work_records.is_empty(): work_records = e._work_records
	if wages.is_empty(): wages = e._wages
	var amount := 0
	for id: String in p["orders"]:
		var row := orders.get(id, {}) as Dictionary
		amount += (int(row.get("quantity", 0))-int(row.get("cancelled", 0))) * (int(row.get("price", 0))+e._freight(row.get("route_legs", [])))
	for row: Dictionary in p["work"]:
		var rate:=_work_rate(row["id"],wages)
		if rate<0 or not work_records.has(row["id"]): return FormalLedgerState.MAX_AMOUNT
		amount += int(row["hours"]) * rate
	return amount

func build() -> void:
	var e := _economy()
	var now := e._world.game_clock.total_minutes()
	var used_work: Dictionary = {}
	for id: String in _active.duplicate():
		var p := projects[id] as Dictionary
		if p["status"] == "PAUSED" or int(p["accepted_minute"]) >= now: continue
		var terms := terms_for(p)
		var site := str(p["site_id"])
		if p["kind"] in MOVE_KINDS and not move_work_allowed(p, e._production_minute()):
			p["reason"]="CURRENT_MOBILE_WORK_AUTHORITY_OR_STATE_UNAVAILABLE"
			continue
		if p["kind"] in BUILD_KINDS and not construction_interval_valid(p,e._production_minute()):
			p["reason"]="CONSTRUCTION_PERMISSION_OR_OPERATOR_NOT_VALID_FOR_INTERVAL"
			continue
		if not e._site_operating(site,e._production_minute()):
			p["reason"] = "SITE_NOT_OPERATING"
			continue
		if p["kind"] == "MAINTENANCE" and not maintenance_project_valid(p,e._production_minute()):
			p["reason"]="CURRENT_SITE_RECIPE_OR_OWNER_UNAVAILABLE";continue
		if p["kind"] == "MAINTENANCE" and assets[p["asset_id"]]["status"] != "MAINTENANCE":
			p["reason"] = "WAITING_MAINTENANCE_BOUNDARY"
			continue
		if p["materials"].is_empty():
			if p["kind"] in BUILD_KINDS and not construction_interval_valid(p,now):
				p["status"]="WAITING_RESOURCES";p["reason"]="CURRENT_CONSTRUCTION_PERMISSION_NOT_AVAILABLE"
				continue
			if not e._site_operating(site):
				p["reason"]="NO_CURRENT_SITE_RIGHT_FOR_NEW_MATERIAL_STAGE"
				continue
			if not e.capital_take_goods(site, terms["materials"], id):
				p["status"] = "WAITING_RESOURCES"
				p["reason"] = "CAPITAL_GOODS_NOT_AT_SITE"
				continue
			p["materials"] = terms["materials"].duplicate(true)
			p["material_minute"] = now
			p["started_minute"] = now
			if p["kind"] in MOVE_KINDS: p["material_permission"]=move_execution_permission(p)
		p["status"] = "BUILDING"
		p["reason"] = ""
		var left := mini(int(terms["hours_per_day"]), maxi(0, int(terms["hours"])-work_hours(p)))
		for work_id: String in e._capital_work_ids:
			var work := e._work_records[work_id] as Dictionary
			if int(work["day"]) != e.day or e._spec["jobs"][work["job"]]["site_id"] != site: continue
			# Goods arriving at this midnight cannot be installed with work from
			# the preceding interval. Construction starts with the next day's work.
			if int(p["started_minute"]) >= e.day*1440: continue
			if e._spec["jobs"][work["job"]].get("denomination", FormalLedgerState.DENOMINATION) != terms["denomination"]: continue
			if (p["kind"] in MOVE_KINDS or p["kind"]=="MAINTENANCE") and e._spec["jobs"][work["job"]]["skill"]<terms.get("skill",1): continue
			var rate:=_work_rate(work_id,e._wages)
			if rate<0: p["reason"]="MISSING_ACTUAL_WAGE_SOURCE";continue
			var hours := mini(left, int(work["hours"])-int(used_work.get(work_id, 0)))
			if rate > 0: hours = mini(hours, maxi(0, int(p["budget"])-committed_cost(p))/rate)
			if hours <= 0: continue
			p["work"].append({"id": work_id, "hours": hours})
			if p["kind"] in MOVE_KINDS: p["work_permissions"].append(move_execution_permission(p))
			if e._costs.enabled: e._costs.assign_work(work_id, hours, "CAPITAL", id)
			_index_labor(site, e.day, hours)
			used_work[work_id] = int(used_work.get(work_id, 0))+hours
			e._labor[site] = int(e._labor.get(site, 0))-hours
			left -= hours
			if left == 0: break
		if work_hours(p) >= int(terms["hours"]): p["status"] = "WAITING_INSTALLATION"
		elif committed_cost(p) >= int(p["budget"]): p["reason"] = "INVESTMENT_BUDGET_EXHAUSTED"
		elif left > 0: p["reason"] = "WAITING_ACTUAL_CONSTRUCTION_LABOR"

	_last_build_work = used_work

func elapsed_minutes(p: Dictionary, minute: int) -> int:
	if int(p["started_minute"]) < 0: return 0
	var paused := -1
	var withheld := 0
	var rows: Array[Dictionary] = []
	for id: String in _project_changes.get(p["id"], []):
		var row := changes[id] as Dictionary
		if row.get("kind") == "investment_status" and row.get("status") == "APPLIED" and row.get("payload", {}).get("project_id") == p["id"] and int(row.get("effective_minute", -1)) <= minute: rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
	for row: Dictionary in rows:
		var boundary := maxi(int(p["started_minute"]), int(row["effective_minute"]))
		if row["payload"]["status"] == "PAUSED" and paused < 0: paused = boundary
		elif row["payload"]["status"] != "PAUSED" and paused >= 0:
			withheld += maxi(0, boundary-paused)
			paused = -1
	if paused >= 0: withheld += maxi(0, minute-paused)
	return maxi(0, minute-int(p["started_minute"])-withheld)

func boundary() -> void:
	var e := _economy()
	var now := e._world.game_clock.total_minutes()
	for id: String in _pending.duplicate():
		var change := changes[id] as Dictionary
		if int(change["boundary_minute"]) > now: continue
		_pending.erase(id)
		var key := "project_id" if change["kind"] == "investment_status" else "asset_id"
		var row := projects[change["payload"][key]] as Dictionary if key == "project_id" else assets[change["payload"][key]] as Dictionary
		change["effective_minute"] = now
		var control_firm: String = asset_state(str(row["id"])).get("owner", row["firm"]) if key=="asset_id" else row["firm"]
		if not e._manager(change["actor"], control_firm) or (key == "project_id" and row["status"] in TERMINAL) or (key == "asset_id" and row["status"] in ["MAINTENANCE", "RETIRED"]):
			change["status"] = "DEFERRED"
			change["reason"] = "AUTHORITY_OR_CAPITAL_STATE_CHANGED"
			continue
		change["status"] = "APPLIED"
		if key == "project_id":
			row["status"] = "WAITING_RESOURCES" if change["payload"]["status"] == "ACTIVE" else change["payload"]["status"]
			if row["status"] == "CANCELLED":
				_active.erase(row["id"])
				_active_by_site[row["site_id"]].erase(row["id"])
				if row["kind"] == "MAINTENANCE": _asset_event(assets[row["asset_id"]], "PAUSED", now, id)
		else: _asset_event(row, change["payload"]["status"], now, id)
	for id: String in _active.duplicate():
		var p := projects[id] as Dictionary
		if p["status"] == "PAUSED": continue
		if p["kind"] in MOVE_KINDS:
			move_boundary(p, now)
			continue
		var terms := terms_for(p)
		# End-of-day NPC decisions cannot stop capacity in the interval just settled.
		if p["kind"] == "MAINTENANCE" and now<=int(p["accepted_minute"]): continue
		if p["kind"] == "MAINTENANCE" and not maintenance_project_valid(p,now):
			p["reason"]="CURRENT_SITE_RECIPE_OR_OWNER_UNAVAILABLE";continue
		if p["kind"] == "MAINTENANCE" and assets[p["asset_id"]]["status"] in ["ACTIVE", "PAUSED"]: _asset_event(assets[p["asset_id"]], "MAINTENANCE", now, p["action_id"])
		if p["status"] != "WAITING_INSTALLATION" or elapsed_minutes(p, now) < int(terms["duration_minutes"]): continue
		if p["kind"] in BUILD_KINDS and not construction_interval_valid(p,maxi(0,now-1)):
			p["reason"]="CONSTRUCTION_DELIVERY_PERMISSION_NOT_AVAILABLE";continue
		if not e._site_operating(p["site_id"]):
			p["reason"] = "INSTALLATION_SITE_NOT_OPERATING"
			continue
		p["status"] = "COMPLETED"
		p["completed_minute"] = now
		_active.erase(id)
		_active_by_site[p["site_id"]].erase(id)
		if p["kind"] == "MAINTENANCE":
			_asset_event(assets[p["asset_id"]], "ACTIVE", now, p["action_id"])
		else:
			var asset_id: String = "capital_asset:"+str(p["action_id"])
			p["asset_id"] = asset_id
			assets[asset_id] = {"id": asset_id, "firm": p["firm"], "site_id": p["site_id"], "template_id": p["template_id"], "asset_type": terms["asset_type"], "project_id": id, "materials": p["materials"].duplicate(true), "capacity": terms["capacity"], "activities": terms["activities"].duplicate(), "in_service_minute": now, "status": "ACTIVE", "basis": terms["basis"], "events": [{"minute": now, "status": "ACTIVE", "source": p["action_id"]}]}
			if not _site_assets.has(p["site_id"]): _site_assets[p["site_id"]] = []
			_site_assets[p["site_id"]].append(asset_id)
			_pool_cache.erase(p["site_id"])
			if p["kind"] in BUILD_KINDS:e._leases.register_completed_asset(asset_id)

func _asset_event(asset: Dictionary, status: String, minute: int, source: String) -> void:
	_pool_cache.clear()
	asset["status"] = status
	asset["events"].append({"minute": minute, "status": status, "source": source})

func begin_external_maintenance(c: Dictionary) -> bool:
	var e:=_economy()
	var a:=assets.get(c.get("asset_id",""),{}) as Dictionary
	var now:=e._world.game_clock.total_minutes()
	if a.is_empty() or move_busy(str(a.get("id",""))) or e._service_market.contracts.get(c.get("id"))!=c or asset_state(a["id"])["owner"]!=c["client"] or a["status"] not in ["ACTIVE","PAUSED"] or not e._site_operating(asset_state(a["id"])["site_id"]) or now%1440!=0 or not template(a["template_id"]).has("maintenance"): return false
	for id: String in _active:
		if projects[id]["asset_id"]==a["id"]: return false
	_asset_event(a,"MAINTENANCE",now,c["action_id"])
	return true

func complete_external_maintenance(c: Dictionary) -> bool:
	var e:=_economy()
	var a:=assets.get(c.get("asset_id",""),{}) as Dictionary
	var now:=e._world.game_clock.total_minutes()
	if a.is_empty() or e._service_market.contracts.get(c.get("id"))!=c or a["status"]!="MAINTENANCE" or not e._site_operating(asset_state(a["id"])["site_id"],maxi(0,now-1)) or now%1440!=0: return false
	var t:=template(a["template_id"])["maintenance"] as Dictionary
	if c["material_sources"].is_empty() or c["started_minute"]<0 or now-int(c["started_minute"])<int(t["duration_minutes"]) or e._service_market.work_hours(c,"REPAIR")!=t["hours"]: return false
	_asset_event(a,"ACTIVE",now,c["action_id"])
	return true

func pools(site: String, minute: int) -> Array[Dictionary]:
	var base := int(_economy()._spec["sites"][site]["capacity"])
	var cached := _pool_cache.get(site, {}) as Dictionary
	if cached.get("minute") == minute and cached.get("base") == base: return (cached["pools"] as Array[Dictionary]).duplicate(true)
	var result: Array[Dictionary] = []
	for id: String in assets:
		var asset := assets[id] as Dictionary
		var current := asset_state(id, minute)
		if current["status"] == "ACTIVE" and current["installed_site"] == site and template(asset["template_id"])["kind"] not in BUILD_KINDS: result.append({"id": id, "capacity": asset["capacity"], "activities": current["activities"].duplicate()})
	# Preserve restrictive machines before the universal base pool.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["activities"].size() < b["activities"].size() if a["activities"].size() != b["activities"].size() else a["id"] < b["id"])
	if base > 0: result.append({"id": "base:"+site, "capacity": base, "activities": []})
	_pool_cache[site] = {"minute": minute, "base": base, "pools": result.duplicate(true)}
	return result

static func pool_available(value: Array[Dictionary], activity: String = "") -> int:
	var total := 0
	for row: Dictionary in value:
		if activity.is_empty() or row["activities"].is_empty() or row["activities"].has(activity): total += int(row["capacity"])
	return total

static func use_pool(value: Array[Dictionary], activity: String, amount: int) -> void:
	for row: Dictionary in value:
		if not row["activities"].is_empty() and not row["activities"].has(activity): continue
		var used := mini(amount, int(row["capacity"]))
		row["capacity"] = int(row["capacity"])-used
		amount -= used
		if amount == 0: break

func capacity(site: String, minute: int, activity: String = "") -> int:
	return pool_available(pools(site, minute), activity)

func cumulative_capacity(site: String, through_day: int) -> int:
	var total := through_day*int(_economy()._spec["sites"][site]["capacity"])
	# Integrate the same installation intervals used by production. No second capacity pool.
	for id: String in assets:
		var asset := assets[id] as Dictionary
		if template(asset["template_id"])["kind"] in BUILD_KINDS: continue
		var edges: Array[int] = [int(asset["in_service_minute"]), through_day*1440]
		for event: Dictionary in asset["events"]:
			if event["minute"] <= through_day*1440: edges.append(event["minute"])
		for trade: Dictionary in resale_trades.values():
			if trade["asset_id"]==id and trade["delivered_minute"]>=0 and trade["delivered_minute"]<=through_day*1440: edges.append(trade["delivered_minute"])
		edges.sort()
		for index: int in range(edges.size()-1):
			var state := asset_state(id,edges[index])
			if state["status"]=="ACTIVE" and state["installed_site"]==site: total += maxi(0,edges[index+1]/1440-edges[index]/1440)*int(asset["capacity"])
	return total

func invested_goods(site: String, good: String) -> int:
	var amount := 0
	for id: String in _site_projects.get(site, []): amount += int(projects[id]["materials"].get(good, 0))
	return amount

func keeper_reason(site: String) -> String:
	for id: String in assets:
		var current := asset_state(id)
		if current["site_id"] == site and (asset_moved(id) or current["status"] in ["ACTIVE", "MAINTENANCE"]): return "CAPITAL_ASSET_RETAINS_ACTUAL_SITE_CUSTODY"
	for id: String in _site_projects.get(site, []):
		if projects[id]["status"] not in TERMINAL or (projects[id]["status"] == "CANCELLED" and not projects[id]["materials"].is_empty()): return "CAPITAL_PROJECT_OR_CONSUMED_WORK_IN_PROGRESS_REQUIRES_KEEPER"
	# Closure retains this stock-point identity, host place and corporate owner.
	# Paused/retired assets remain installed under that owner's custody.
	return ""

func view(firm: String) -> Dictionary:
	var result := {"projects": [], "assets": [], "options": [], "npc_policy": [], "credit_offers": [], "accounts": [], "building_policy": [], "basis": "ACTUAL_PROJECTS_AND_INSTALLED_ASSETS"}
	var e := _economy()
	result["credit_offers"] = e._credit.visible(firm, e._known_credit_lenders(firm), e._world.game_clock.total_minutes())["offers"]
	for account: Dictionary in e._world.ledger_state.own_accounts(firm):
		account["available"] = e._world.ledger_state.available_balance(account["account_id"])
		result["accounts"].append(account)
	var project_ids: Array[String] = []
	var asset_ids: Array[String] = []
	for site: String in e._spec["firms"][firm]["sites"]:
		project_ids.append_array(_site_projects.get(site, []))
		pass # Current title is derived below; original site indices retain formation history.
	project_ids.sort_custom(func(a: String, b: String) -> bool: return int(projects[a]["accepted_minute"]) < int(projects[b]["accepted_minute"]) if projects[a]["accepted_minute"] != projects[b]["accepted_minute"] else a < b)
	for project_id: String in project_ids:
		var row := projects[project_id] as Dictionary
		var p := row.duplicate(true)
		p["terms"] = terms_for(row)
		p["labor_hours"] = work_hours(row)
		p["committed_cost"] = committed_cost(row)
		if e._costs.enabled: p["direct_cost"] = e._costs.project_cost(project_id)
		p["budget_remaining"] = maxi(0, int(row["budget"])-int(p["committed_cost"]))
		p["missing"] = {}
		for good: String in p["terms"]["materials"]:
			p["missing"][good] = maxi(0, int(p["terms"]["materials"][good])-int(row["materials"].get(good, 0))-e.capital_free_goods(row["site_id"], good))
		p["remaining_minutes"] = maxi(0, int(p["terms"]["duration_minutes"])-elapsed_minutes(row, e._world.game_clock.total_minutes())) if int(row["started_minute"]) >= 0 else null
		p["payments"] = []
		p["procurement"] = []
		for order_id: String in row["orders"]: p["procurement"].append(e._order_view(e._orders[order_id]))
		p["wage_liability"] = 0
		for work: Dictionary in row["work"]:
			var wage := e._wages.get(work["id"], {}) as Dictionary
			p["wage_liability"] += int(work["hours"])*_work_rate(work["id"],e._wages)
			p["payments"].append({"work_id": work["id"], "construction_hours": work["hours"], "whole_work_wage_paid": wage.get("paid", 0), "whole_work_wage_remaining": wage.get("remaining", 0)})
		result["projects"].append(p)
	for id: String in assets:
		if asset_state(id)["owner"]==firm: asset_ids.append(id)
	asset_ids.sort()
	for asset_id: String in asset_ids:
		var asset := (assets[asset_id] as Dictionary).duplicate(true)
		asset["current_use"] = asset_state(asset_id)
		asset["internal_maintenance_ready"]=not maintenance_template(asset_id,e._world.game_clock.total_minutes()).is_empty() and asset["current_use"]["status"] in ["ACTIVE","PAUSED"] and not move_busy(asset_id)
		asset["maintenance_recipe"]=maintenance_template(asset_id,e._world.game_clock.total_minutes()).get("id","")
		asset["mobility"] = mobility_costs(asset_id)
		if e._costs.enabled:
			asset["cost_lifecycle"] = e._costs.asset_cost(asset_id)
			asset["origin_cost"] = asset["cost_lifecycle"]["origin_cost"]
		if template(asset["template_id"])["kind"] in BUILD_KINDS:asset["rental_use"]=e._leases.asset_view(asset_id)
		result["assets"].append(asset)
	for row: Dictionary in e.config.get("capital_investment", {}).get("templates", []):
		if row["firm"] == firm:
			var option := row.duplicate(true)
			option["site_ready"] = e._spec["sites"].has(row["site_id"])
			if row["kind"] in BUILD_KINDS:
				var auth:=construction_permission(e.firm_manager_at(firm,e._world.game_clock.total_minutes()),row,row["budget"],e._world.game_clock.total_minutes())
				option["site_ready"]=option["site_ready"] and auth["ok"] and not _construction_claims.has(row["building"]["permit"]["id"])
				option["construction_reason"]=auth.get("reason","CONSTRUCTION_SPACE_ALREADY_COMMITTED" if _construction_claims.has(row["building"]["permit"]["id"]) else "READY")
				option["known_estimate"]=known_build_estimate(row)
			result["options"].append(option)
	for row: Dictionary in e.config.get("capital_investment", {}).get("npc_policies", []):
		if template(row["template_id"]).get("firm") == firm: result["npc_policy"].append(row.duplicate(true))
	for policy:Dictionary in e.config.get("capital_investment",{}).get("building_policies",[]):
		if template(policy["template_id"])["firm"]==firm:result["building_policy"].append(policy.duplicate(true))
	return result

func snapshot() -> Dictionary:
	var result := {"format": FORMAT, "projects": projects.duplicate(true), "assets": assets.duplicate(true), "changes": changes.duplicate(true)}
	if not resale_offers.is_empty() or not resale_trades.is_empty(): result["resale"]={"offers":resale_offers.duplicate(true),"trades":resale_trades.duplicate(true)}
	return result

func restore(value: Variant, saved: Dictionary) -> bool:
	if value == null: return true
	if not value is Dictionary or not EconomySliceConfig._fields(value, ["format", "projects", "assets", "changes"], ["resale"]) or value["format"] != FORMAT: return _fail("Invalid capital state")
	for key: String in ["projects", "assets", "changes"]:
		if not value[key] is Dictionary or value[key].size() > LIMIT: return _fail("Invalid capital state collection")
	projects = value["projects"].duplicate(true)
	assets = value["assets"].duplicate(true)
	changes = value["changes"].duplicate(true)
	_pool_cache.clear()
	_active.clear()
	_pending.clear()
	_site_assets.clear()
	_site_projects.clear()
	_labor_allocations.clear()
	_labor_totals.clear()
	_active_by_site.clear()
	_firm_last_project.clear()
	_project_changes.clear()
	_construction_claims.clear()
	for id: Variant in changes:
		var row: Variant = changes[id]
		if row is Dictionary and row.get("kind") == "investment_status" and row.get("payload") is Dictionary and row["payload"].get("project_id") is String:
			var project_id := str(row["payload"]["project_id"])
			if not _project_changes.has(project_id): _project_changes[project_id] = []
			_project_changes[project_id].append(id)
	var e := _economy()
	var now := e._world.game_clock.total_minutes()
	var resale: Variant=value.get("resale", {"offers":{},"trades":{}})
	if not resale is Dictionary or not FormalLedgerState.exact_fields(resale,["offers","trades"]) or not resale["offers"] is Dictionary or not resale["trades"] is Dictionary: return _fail("Invalid capital resale state")
	resale_offers=resale["offers"].duplicate(true);resale_trades=resale["trades"].duplicate(true)
	_known_quotes.clear();_npc_observations.clear();_npc_reviews.clear()
	for raw: Variant in resale_offers.values():
		if not raw is Dictionary or not EconomySliceConfig._fields(raw,["id","action_id","actor","asset_id","seller","source_site","buyer","target_site","price","denomination","minute","expires_minute","authority","withdrawn","withdrawal_action","terms"],["equipment"]): return _fail("Malformed capital offer")
		for k: String in ["id","action_id","actor","asset_id","seller","source_site","buyer","target_site","denomination","withdrawal_action","terms"]:
			if not raw[k] is String: return _fail("Invalid capital offer reference")
		for k: String in ["minute","expires_minute","price"]:
			if not raw[k] is int: return _fail("Invalid capital offer time or money")
	for raw: Variant in resale_trades.values():
		if not raw is Dictionary or not FormalLedgerState.exact_fields(raw,["id","action_id","actor","offer_id","asset_id","seller","buyer","source_site","target_site","accepted_minute","delivered_minute","state","authority","payment_authority","delivery_project","cancel_action"]): return _fail("Malformed capital trade")
		for k: String in ["id","action_id","actor","offer_id","asset_id","seller","buyer","source_site","target_site","state","delivery_project","cancel_action"]:
			if not raw[k] is String: return _fail("Invalid capital trade reference")
		for k: String in ["accepted_minute","delivered_minute"]:
			if not raw[k] is int: return _fail("Invalid capital trade time")
	for id: Variant in assets:
		var a: Variant=assets[id]
		if not a is Dictionary or not FormalLedgerState.exact_fields(a,["id","firm","site_id","template_id","asset_type","project_id","materials","capacity","activities","in_service_minute","status","basis","events"]) or not a["template_id"] is String or template(a["template_id"]).is_empty(): return _fail("Malformed original capital asset")
	for raw: Dictionary in resale_offers.values():
		if not assets.has(raw["asset_id"]) or not e._spec["sites"].has(raw["source_site"]) or not e._spec["sites"].has(raw["target_site"]) or not e._spec["firms"].has(raw["seller"]) or not e._spec["firms"].has(raw["buyer"]): return _fail("Capital quotation has missing physical or corporate reference")
	for raw: Dictionary in resale_trades.values():
		if not assets.has(raw["asset_id"]) or not resale_offers.has(raw["offer_id"]) or not e._spec["sites"].has(raw["source_site"]) or not e._spec["sites"].has(raw["target_site"]) or not e._spec["firms"].has(raw["seller"]) or not e._spec["firms"].has(raw["buyer"]): return _fail("Capital trade has missing physical or corporate reference")
	var work_used: Dictionary = {}
	var order_used: Dictionary = {}
	for id: Variant in projects:
		var p: Variant = projects[id]
		if not p is Dictionary or not EconomySliceConfig._fields(p, ["id", "action_id", "actor", "template_id", "firm", "site_id", "kind", "accepted_minute", "budget", "status", "materials", "material_minute", "work", "started_minute", "completed_minute", "orders", "asset_id", "reason"], ["material_sources", "construction_authority", "mobility_authority", "trade_id", "work_permissions", "material_permission", "completion_permission"]) or p["id"] != id or id != "capital_project:"+str(p["action_id"]): return _fail("Invalid capital project identity")
		var terms := template(str(p["template_id"]))
		if terms.is_empty() or (p["firm"] != terms["firm"] and p["kind"] not in MOVE_KINDS) or (p["site_id"] != terms["site_id"] and p["kind"] not in MOVE_KINDS) or not e._spec["sites"].has(p["site_id"]) or (p["kind"] not in [terms["kind"], "MAINTENANCE"] and p["kind"] not in MOVE_KINDS) or (p["kind"] == "MAINTENANCE" and not terms.has("maintenance")): return _fail("Capital project lacks site and permission")
		var command := saved.get("commands", {}).get(p["action_id"], {}) as Dictionary
		var payload := {"asset_id": p["asset_id"], "budget": p["budget"]} if p["kind"] == "MAINTENANCE" else {"template_id": p["template_id"], "budget": p["budget"]}
		if p["kind"] in MOVE_KINDS:
			if not valid_move_source(p,command,saved): return _fail("Mobile capital work lacks original authority or asset state")
		elif p.has("mobility_authority") or p.has("trade_id") or p.has("work_permissions") or p.has("material_permission") or p.has("completion_permission"): return _fail("Original construction claims an unrelated mobile work proof")
		elif not command.get("result", {}).get("accepted", false) or command["envelope"]["actor"] != p["actor"] or command["envelope"]["command"]["payload"] != payload or command["envelope"]["command"]["minute"] != p["accepted_minute"] or command["envelope"]["command"]["kind"] != ("maintain_capital" if p["kind"] == "MAINTENANCE" else "invest") or not e._manager_at(p["actor"], p["firm"], int(p["accepted_minute"])): return _fail("Capital project lacks its accepted action")
		if p["kind"]=="MAINTENANCE" and (not maintenance_project_valid(p,p["accepted_minute"]) or p["template_id"]!=maintenance_template(p["asset_id"],p["accepted_minute"]).get("id")): return _fail("Maintenance lacks current owner, type and site recipe")
		if p["kind"] in BUILD_KINDS:
			var permit:Dictionary=terms["building"]["permit"]
			if _construction_claims.has(permit["id"]) or not valid_construction_proof(p.get("construction_authority"),p["actor"],terms,p["budget"],p["accepted_minute"]) or command["result"].get("project_id")!=id:return _fail("Building lacks original independent construction permission or repeats its space")
			_construction_claims[permit["id"]]=id
		elif p.has("construction_authority"):return _fail("Equipment claims an unrelated building permission")
		if not FormalLedgerState.valid_amount(p["budget"]) or int(p["budget"]) < 1 or int(p["budget"]) > int(terms["budget"]) or not p["work"] is Array or not p["orders"] is Array or not p["materials"] is Dictionary or p["status"] not in ["ACCEPTED", "WAITING_RESOURCES", "BUILDING", "WAITING_INSTALLATION", "COMPLETED", "PAUSED", "CANCELLED"]: return _fail("Invalid project budget or state")
		for key: String in ["accepted_minute", "material_minute", "started_minute", "completed_minute"]:
			if not p[key] is int or int(p[key]) < (-1 if key != "accepted_minute" else 0) or int(p[key]) > now: return _fail("Invalid project time")
		terms = terms_for(p)
		if not p["materials"].is_empty() and (p["materials"] != terms["materials"] or int(p["material_minute"]) <= int(p["accepted_minute"]) or p["started_minute"] != p["material_minute"] or int(p["material_minute"])%1440 != 0): return _fail("Installed capital lost its goods input")
		if p["materials"].is_empty() and (p["started_minute"] != -1 or p["material_minute"] != -1 or not p["work"].is_empty()): return _fail("Construction precedes real goods")
		var per_day: Dictionary = {}
		for row: Variant in p["work"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["id", "hours"]) or not row["id"] is String or not saved.get("work_records", {}).has(row["id"]) or not FormalLedgerState.valid_amount(row["hours"]) or int(row["hours"]) <= 0: return _fail("Invalid construction labor allocation")
			var work := saved["work_records"][row["id"]] as Dictionary
			if p["kind"] in MOVE_KINDS and e._spec["jobs"][work["job"]]["skill"]<terms["skill"]: return _fail("Mobile capital work lacks configured job qualification")
			if e._spec["jobs"][work["job"]]["site_id"] != p["site_id"] or e._spec["jobs"][work["job"]].get("denomination", FormalLedgerState.DENOMINATION) != terms["denomination"] or int(work["day"])*1440 <= int(p["started_minute"]) or (int(p["completed_minute"]) >= 0 and int(work["day"])*1440 > int(p["completed_minute"])): return _fail("Construction work lacks actual place or time")
			if p["kind"] in BUILD_KINDS and not construction_interval_valid(p,int(work["day"])*1440-1):return _fail("Construction labor outside actual permit/operator interval")
			work_used[row["id"]] = int(work_used.get(row["id"], 0))+int(row["hours"])
			if int(work_used[row["id"]]) > int(work["hours"]): return _fail("Construction reused labor")
			per_day[work["day"]] = int(per_day.get(work["day"], 0))+int(row["hours"])
			_index_labor(p["site_id"], int(work["day"]), int(row["hours"]))
			if int(per_day[work["day"]]) > int(terms["hours_per_day"]): return _fail("Construction exceeds daily allocation")
		if work_hours(p) > int(terms["hours"]) or committed_cost(p, saved.get("orders", {}), saved.get("work_records", {}),saved.get("wages",{})) > int(p["budget"]): return _fail("Construction exceeds labor or budget")
		for order_id: Variant in p["orders"]:
			var order := saved.get("orders", {}).get(order_id, {}) as Dictionary
			if order.is_empty() or order_used.has(order_id) or order["buyer"] != p["firm"] or order["buyer_site"] != p["site_id"] or order["denomination"] != terms["denomination"] or not terms["materials"].has(order["good"]) or not str(order["action_id"]).contains(":"+str(p["id"])+"|"): return _fail("Project procurement lacks its original order")
			order_used[order_id] = true
		if p["status"] == "COMPLETED" and (p["materials"] != terms["materials"] or work_hours(p) != int(terms["hours"]) or elapsed_minutes(p, int(p["completed_minute"])) < int(terms["duration_minutes"]) or int(p["completed_minute"])%1440 != 0): return _fail("Capital completion precedes actual inputs")
		if p["kind"] in BUILD_KINDS and p["status"]=="COMPLETED" and not construction_interval_valid(p,int(p["completed_minute"])-1):return _fail("Building completed outside permitted delivery boundary")
		if p["status"] != "COMPLETED" and p["completed_minute"] != -1: return _fail("Unfinished project has completion time")
		if not _site_projects.has(p["site_id"]): _site_projects[p["site_id"]] = []
		_site_projects[p["site_id"]].append(id)
		_firm_last_project[p["firm"]] = maxi(int(_firm_last_project.get(p["firm"], 0)), int(p["accepted_minute"]))
		if p["status"] not in TERMINAL:
			_active.append(id)
			if not _active_by_site.has(p["site_id"]): _active_by_site[p["site_id"]] = []
			_active_by_site[p["site_id"]].append(id)
	for id: Variant in assets:
		var asset: Variant = assets[id]
		if not asset is Dictionary or not FormalLedgerState.exact_fields(asset, ["id", "firm", "site_id", "template_id", "asset_type", "project_id", "materials", "capacity", "activities", "in_service_minute", "status", "basis", "events"]) or asset["id"] != id or not projects.has(asset["project_id"]): return _fail("Invalid installed asset")
		var p := projects[asset["project_id"]] as Dictionary
		var terms := template(p["template_id"])
		if p["status"] != "COMPLETED" or p["kind"] in ["MAINTENANCE"]+MOVE_KINDS or p["asset_id"] != id or id != "capital_asset:"+p["action_id"] or asset["in_service_minute"] != p["completed_minute"] or asset["firm"] != p["firm"] or asset["site_id"] != p["site_id"] or asset["materials"] != p["materials"]: return _fail("Asset lacks completed project")
		for key: String in ["template_id", "asset_type", "capacity", "activities", "basis"]:
			if asset[key] != terms.get(key, p.get(key)): return _fail("Asset capabilities differ from permission")
		if not asset["events"] is Array or asset["events"].is_empty(): return _fail("Missing asset availability history")
		var previous := -1
		var previous_status: String = ""
		for event: Variant in asset["events"]:
			if not event is Dictionary or not FormalLedgerState.exact_fields(event, ["minute", "status", "source"]) or not event["minute"] is int or int(event["minute"]) < int(asset["in_service_minute"]) or int(event["minute"]) < previous or int(event["minute"]) > now or int(event["minute"])%1440 != 0 or event["status"] not in ["ACTIVE", "PAUSED", "MAINTENANCE", "RETIRED", "DISMANTLING", "DETACHED", "REINSTALLING"]: return _fail("Invalid asset availability boundary")
			if not saved.get("commands", {}).get(event["source"], {}).get("result", {}).get("accepted", false): return _fail("Asset state lacks action source")
			if previous < 0:
				if event != {"minute": asset["in_service_minute"], "status": "ACTIVE", "source": p["action_id"]}: return _fail("Asset first availability lacks its installation")
			else:
				var change := changes.get(event["source"], {}) as Dictionary
				var maintenance := projects.get("capital_project:"+str(event["source"]), {}) as Dictionary
				var control_ok: bool = change.get("status") == "APPLIED" and change.get("kind") == "capital_status" and change.get("effective_minute") == event["minute"] and change.get("payload") == {"asset_id": id, "status": event["status"]}
				var maintenance_ok: bool = maintenance.get("kind") == "MAINTENANCE" and maintenance.get("asset_id") == id and int(event["minute"]) > int(maintenance.get("accepted_minute", now)) and ((event["status"] == "MAINTENANCE") or (event["status"] == "ACTIVE" and maintenance.get("completed_minute") == event["minute"]))
				var cancel_ok: bool = change.get("status") == "APPLIED" and change.get("kind") == "investment_status" and change.get("effective_minute") == event["minute"] and event["status"] == "PAUSED" and change.get("payload", {}).get("status") == "CANCELLED" and projects.get(change.get("payload", {}).get("project_id", ""), {}).get("asset_id") == id
				var external: Dictionary=saved.get("service_market",{}).get("contracts",{}).get("service:"+str(event["source"]),{})
				var external_ok: bool=external.get("kind")=="REPAIR" and external.get("asset_id")==id and ((event["status"]=="MAINTENANCE" and external.get("started_minute")==event["minute"]) or (event["status"]=="ACTIVE" and external.get("repair_result_minute")==event["minute"]))
				var move := projects.get("capital_project:"+str(event["source"]),{}) as Dictionary
				var move_ok: bool=move.get("asset_id")==id and move.get("kind") in MOVE_KINDS and ((event["status"]==("DISMANTLING" if move["kind"]=="DISMANTLE" else "REINSTALLING") and event["minute"]==(int(move["accepted_minute"])/1440+1)*1440) or (event["status"]==("DETACHED" if move["kind"]=="DISMANTLE" else "ACTIVE") and move.get("completed_minute")==event["minute"])) and move["kind"]!="HANDOVER"
				if not control_ok and not maintenance_ok and not cancel_ok and not external_ok and not move_ok: return _fail("Equipment availability lacks its actual control or maintenance")
				if previous_status == "RETIRED": return _fail("Retired equipment was reactivated")
				if event["status"]=="DISMANTLING" and previous_status not in ["ACTIVE","PAUSED"]: return _fail("Dismantling bypassed an asset lock")
				if event["status"]=="REINSTALLING" and previous_status!="DETACHED": return _fail("Installation bypassed physical delivery")
			previous = int(event["minute"])
			previous_status = event["status"]
		if asset["status"] != asset["events"].back()["status"]: return _fail("Asset current state differs from history")
		if not _site_assets.has(asset["site_id"]): _site_assets[asset["site_id"]] = []
		_site_assets[asset["site_id"]].append(id)
	for p: Dictionary in projects.values():
		if p["status"] == "COMPLETED" and not assets.has(p["asset_id"]): return _fail("Completed project lost its installed asset")
	for id: Variant in changes:
		var row: Variant = changes[id]
		if not row is Dictionary or not EconomySliceConfig._fields(row, ["id", "actor", "kind", "payload", "requested_minute", "boundary_minute", "effective_minute", "status", "reason"], ["construction_authority"]) or row["id"] != id or row["kind"] not in ["investment_status", "capital_status"] or row["status"] not in ["QUEUED", "APPLIED", "DEFERRED"]: return _fail("Invalid capital control history")
		var cmd := saved.get("commands", {}).get(id, {}) as Dictionary
		if not cmd.get("result", {}).get("accepted", false) or cmd["envelope"]["actor"] != row["actor"] or cmd["envelope"]["command"]["kind"] != row["kind"] or cmd["envelope"]["command"]["payload"] != row["payload"] or cmd["envelope"]["command"]["minute"] != row["requested_minute"]: return _fail("Capital control lacks accepted command")
		if row["boundary_minute"] != (int(row["requested_minute"])/1440+1)*1440 or (row["status"] == "QUEUED" and (row["effective_minute"] != -1 or int(row["boundary_minute"]) <= now)) or (row["status"] != "QUEUED" and row["effective_minute"] != row["boundary_minute"]): return _fail("Invalid capital control boundary")
		var key := "project_id" if row["kind"] == "investment_status" else "asset_id"
		if not row["payload"] is Dictionary or not FormalLedgerState.exact_fields(row["payload"], [key, "status"]) or not row["payload"][key] is String or not row["payload"]["status"] is String: return _fail("Invalid capital control payload")
		var subject := projects.get(row["payload"][key], {}) as Dictionary if key == "project_id" else assets.get(row["payload"][key], {}) as Dictionary
		var control_firm: String=asset_state(subject.get("id",""),int(row["requested_minute"])).get("owner",subject.get("firm","")) if key=="asset_id" else subject.get("firm","")
		if subject.is_empty() or not e._manager_at(row["actor"], control_firm, int(row["requested_minute"])) or (row["status"] == "APPLIED" and not e._manager_at(row["actor"], control_firm, int(row["effective_minute"]))): return _fail("Capital control lost its enterprise authority")
		var resumes_building:bool=key=="project_id" and subject["kind"] in BUILD_KINDS and row["payload"]["status"]=="ACTIVE"
		if resumes_building:
			if not valid_construction_proof(row.get("construction_authority"),row["actor"],template(subject["template_id"]),subject["budget"],row["requested_minute"]):return _fail("Building resume lacks its independent construction authority")
		elif row.has("construction_authority"):return _fail("Unrelated capital control claims construction authority")
		if row["payload"]["status"] not in (["ACTIVE", "PAUSED", "CANCELLED"] if key == "project_id" else ["ACTIVE", "PAUSED", "RETIRED"]): return _fail("Unknown capital lifecycle status")
		if row["status"] == "QUEUED": _pending.append(id)
	for p: Dictionary in projects.values():
		var last: Dictionary = {}
		for id: String in _project_changes.get(p["id"], []):
			var row := changes[id] as Dictionary
			if row["status"] == "APPLIED" and (last.is_empty() or int(row["effective_minute"]) > int(last["effective_minute"])): last = row
		if p["status"] in ["PAUSED", "CANCELLED"] and (last.is_empty() or last["payload"]["status"] != p["status"]): return _fail("Project stop lacks applied control")
		if not last.is_empty() and last["payload"]["status"] in ["PAUSED", "CANCELLED"] and p["status"] != last["payload"]["status"]: return _fail("Stopped project changed without authorized resume")
	if not validate_resale(saved): return false
	for receipt: Dictionary in saved.get("receipts",{}).values():
		if receipt.get("kind")=="capital_offer":
			if not quote_message_valid(receipt): return _fail("Invalid delivered capital quotation")
			adopt_quote(receipt)
	return true

func _reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}

func _fail(reason: String) -> bool:
	error = reason
	return false


func construction_permission(actor:String,t:Dictionary,amount:int,minute:int)->Dictionary:
	var e:=_economy();var permit:=t["building"]["permit"] as Dictionary
	if minute%1440!=0 or actor!=permit["controller"] or e.firm_manager_at(t["firm"],minute)!=actor or not e._manager_at(actor,t["firm"],minute) or minute<permit["valid_from"] or minute>=permit["valid_until"] or not e._world.spatial_catalog.has_place(permit["place_id"]):return {"ok":false,"reason":"NO_CURRENT_INDEPENDENT_CONSTRUCTION_USE_PERMISSION"}
	var org:String=e._cargo_fulfilment._host_organization(t["firm"])
	if org.is_empty() or not e._world.organization_state.is_organization_active(org):return {"ok":false,"reason":"CONSTRUCTION_ORGANIZATION_NOT_ACTIVE"}
	var result:={"ok":true,"permit_id":permit["id"],"actor":actor,"amount":amount,"minute":minute,"root_proof":{}}
	if not permit["root_authority"].is_empty():
		var request:={"operation":"economy.construct","target":permit["id"],"place":permit["place_id"],"category":t["kind"],"amount":amount}
		var ctx:Dictionary=e._cargo_fulfilment._available_context(actor,t["firm"],request,permit["root_authority"])
		var checked:Dictionary=e._cargo_fulfilment._authorize(actor,t["firm"],request["operation"],request["target"],request["place"],request["category"],amount,{str(t["firm"])+"|economy.construct|"+str(t["kind"]):ctx})
		if not checked["ok"] or checked["proof"].get("authority_id")!=permit["root_authority"]:return {"ok":false,"reason":"FORMAL_CONSTRUCTION_ROOT_AUTHORITY_REQUIRED"}
		result["root_proof"]=checked["proof"]
	return result

func valid_construction_proof(proof:Variant,actor:String,t:Dictionary,amount:int,minute:int)->bool:
	var permit:=t["building"]["permit"] as Dictionary;var e:=_economy()
	if not proof is Dictionary or not FormalLedgerState.exact_fields(proof,["ok","permit_id","actor","amount","minute","root_proof"]) or proof["ok"]!=true or proof["permit_id"]!=permit["id"] or proof["actor"]!=actor or proof["amount"]!=amount or proof["minute"]!=minute or minute%1440!=0 or actor!=permit["controller"] or e.firm_manager_at(t["firm"],minute)!=actor or not e._manager_at(actor,t["firm"],minute) or minute<permit["valid_from"] or minute>=permit["valid_until"]:return false
	var root:Variant=proof["root_proof"]
	if permit["root_authority"].is_empty():return root=={}
	return root is Dictionary and e._cargo_fulfilment._saved_authority(root) and root.get("authority_id")==permit["root_authority"] and root.get("subject")==t["firm"] and root.get("actor")==actor and root.get("amount")==amount and root.get("minute")==minute and root.get("operation")=="economy.construct" and root.get("target")==permit["id"] and root.get("place")==permit["place_id"] and root.get("category")==t["kind"]

func construction_interval_valid(p:Dictionary,minute:int)->bool:
	var permit:=template(p["template_id"])["building"]["permit"] as Dictionary
	return minute>=permit["valid_from"] and minute<permit["valid_until"] and _economy().firm_manager_at(p["firm"],minute)==p["actor"] and _economy()._manager_at(p["actor"],p["firm"],minute)

func known_build_estimate(t:Dictionary)->Dictionary:
	var e:=_economy();var amount:=0;var currency:String=t["denomination"]
	for good:String in t["materials"]:
		var quantity:=int(t["materials"][good]);var price:=-1
		if e._costs.enabled and e.capital_free_goods(t["site_id"],good)>=quantity:
			var rows:Array[Dictionary]=e._lots.selection("SITE|"+str(t["site_id"]),good,quantity)
			var cost:Dictionary=e._costs.cost_of(e._costs.ranges(rows))
			if cost["unknown"].is_empty() and (cost["amounts"].is_empty() or (cost["amounts"].size()==1 and cost["amounts"].has(currency))):price=int(cost["amounts"].get(currency,0))
		if price<0:
			for offer:Dictionary in e._input_offers(t["site_id"],good,e.day+30,quantity):
				if offer["denomination"]==currency:price=(int(offer["price"])+int(offer["freight_per_unit"]))*quantity;break
		if price<0:return {"known":false,"reason":"NO_COMPARABLE_OWN_COST_OR_KNOWN_SUPPLIER:"+good}
		amount+=price
	var rate: int=e._labor_market.estimate_rate(t["site_id"],currency)
	if rate<0:return {"known":false,"reason":"NO_ACTUAL_LOCAL_CONSTRUCTION_JOB"}
	return {"known":true,"amount":amount+rate*int(t["hours"]),"denomination":currency,"basis":"KNOWN_QUOTES_AND_ACTUAL_WAGE_RATES_NOT_REALIZED_COST"}

func npc_build()->void:
	var e:=_economy();var now:int=e._world.game_clock.total_minutes()
	for policy:Dictionary in e.config.get("capital_investment",{}).get("building_policies",[]):
		var t:=template(policy["template_id"]);var firm:String=t["firm"]
		if e.firm_manager_at(firm,now)!=firm or _construction_claims.has(t["building"]["permit"]["id"]) or not e._site_operating(t["site_id"]) or e._firm_winding_down(firm):continue
		var observations:Dictionary=e._leases.finance_view(firm,policy["window_days"])
		if observations["rent_cash_received"].get(t["denomination"],0)<policy["minimum_paid_rent"]:continue
		if policy["require_no_vacancy"] and e._leases.own_vacancy(firm)>0:continue
		var estimate:=known_build_estimate(t)
		var known_hours:=0
		for id:String in e._capital_work_ids:
			var work:Dictionary=e._work_records[id]
			if e._spec["jobs"][work["job"]]["site_id"]==t["site_id"]:known_hours+=int(work["hours"])
		if not estimate["known"] or estimate["amount"]>t["budget"] or known_hours<=0:continue
		var cash:int=e._world.ledger_state.available_balance(e._account(firm,t["denomination"]))
		if cash<int(t["budget"])+e._capital_cash_protected(firm,t)+int(policy["cash_floor"]):continue
		e._accept(firm,e._auto_command(firm,"invest",{"template_id":t["id"],"budget":t["budget"]},t["id"]),true)

# A construction allocation references the original accrued wage, including
# unpaid wages and accepted historical rates. Future advertisements cannot reprice it.
func _work_rate(id: String,wages: Dictionary) -> int:
	var w: Variant=wages.get(id)
	if not w is Dictionary or not FormalLedgerState.valid_amount(w.get("amount")) or not FormalLedgerState.valid_amount(w.get("hours")) or w["hours"]<1 or int(w["amount"])%int(w["hours"])!=0: return -1
	return int(w["amount"])/int(w["hours"])


## Origin stays immutable. Later work shares original projects, materials and wages.
static func resale_configuration_valid(settings: Dictionary, spec: Dictionary) -> bool:
	if not settings.has("capital_resale"): return true
	var cfg: Variant=settings["capital_resale"]
	if not cfg is Dictionary or not EconomySliceConfig._fields(cfg,["basis","types","authorities","contacts","npc_policies"],["autonomous_policies","competition","authority_places"]) or cfg["basis"]!="EXPLICIT_DEVELOPMENT_MOVABLE_CAPITAL" or not cfg["types"] is Array or not cfg["authorities"] is Array or not cfg["npc_policies"] is Array or not cfg["contacts"] is Array or cfg["contacts"].size()>32 or cfg["types"].size()>16 or cfg["authorities"].size()>32 or cfg["npc_policies"].size()>16: return false
	if cfg.has("authority_places"):
		if settings.get("case_id") not in ["FORMAL_PLAYER_CAPITAL_TRADE_DEVELOPMENT","FORMAL_PLAYER_CAPITAL_SALE_DEVELOPMENT","FORMAL_ECONOMY_FEEDBACK_DEVELOPMENT"] or not cfg["authority_places"] is Array: return false
		var declared_places: Array[String]=[]
		for permission: Variant in cfg["authorities"]:
			if not permission is Dictionary or not str(permission.get("root_authority","")).begins_with("authority:development:player_capital:") or not spec["firms"].has(permission.get("firm")): continue
			var place: String=spec["sites"][spec["firms"][permission["firm"]]["sites"][0]]["place_id"]
			if place not in declared_places: declared_places.append(place)
		if declared_places.size()!=1 or cfg["authority_places"]!=declared_places: return false
	var seen: Dictionary={}
	for t: Variant in cfg["types"]:
		if not t is Dictionary or not EconomySliceConfig._fields(t,["asset_type","denomination","dismantle","handover","reinstall","targets","transport","basis"],["maintenance_targets"]) or not t["asset_type"] is String or t["asset_type"].is_empty() or seen.has(t["asset_type"]) or not FormalLedgerState.currency_id(t["denomination"]) or t["basis"]!="EXPLICIT_DEVELOPMENT_MOVABLE_EQUIPMENT" or not t["targets"] is Dictionary or t["targets"].is_empty() or t["transport"] not in ["SAME_PLACE_WORKED_HANDOVER_ONLY","EXPLICIT_SHARED_UNIQUE_ASSET_CARRIAGE"]: return false
		if t.has("maintenance_targets"):
			if not t["maintenance_targets"] is Dictionary: return false
			for site: Variant in t["maintenance_targets"]:
				var found:=false
				for recipe: Dictionary in settings.get("capital_investment",{}).get("templates",[]):
					if recipe["id"]==t["maintenance_targets"][site] and recipe["site_id"]==site and recipe.has("maintenance"): found=true
				if not found: return false
		seen[t["asset_type"]]=true
		for kind: String in ["dismantle","handover","reinstall"]:
			var recipe: Variant=t[kind]
			if not recipe is Dictionary or not FormalLedgerState.exact_fields(recipe,["materials","hours","hours_per_day","duration_minutes","budget","skill"]): return false
			if not _materials_valid(recipe["materials"],EconomySliceConfig.good_ids(settings)): return false
			for k: String in ["hours","hours_per_day","duration_minutes","budget","skill"]:
				if not FormalLedgerState.valid_amount(recipe[k]) or recipe[k]<1: return false
			if recipe["duration_minutes"]%1440!=0 or recipe["hours_per_day"]>recipe["hours"]: return false
		for site: Variant in t["targets"]:
			if not spec["sites"].has(site) or not t["targets"][site] is Array or t["targets"][site].is_empty(): return false
			var activities: Array=[]
			for a: Dictionary in spec["sites"][site]["activities"]: activities.append(a["id"])
			for a: Variant in t["targets"][site]:
				if not activities.has(a): return false
	seen.clear()
	for a: Variant in cfg["authorities"]:
		if not a is Dictionary or not FormalLedgerState.exact_fields(a,["id","firm","controller","operations","limit","start_minute","end_minute","root_authority","basis"]) or not a["id"] is String or seen.has(a["id"]) or not spec["firms"].has(a["firm"]) or not a["controller"] is String or not a["root_authority"] is String or not a["operations"] is Array or a["basis"]!="EXPLICIT_DEVELOPMENT_CAPITAL_DISPOSITION_AUTHORITY": return false
		for op: Variant in a["operations"]:
			if op not in ["disassemble","sell","handover","acquire","pay","install","freight"]: return false
		for k: String in ["limit","start_minute","end_minute"]:
			if not FormalLedgerState.valid_amount(a[k]): return false
		if a["limit"]<1 or a["end_minute"]<=a["start_minute"]: return false
		seen[a["id"]]=true
	var competition: bool=cfg.has("competition")
	if competition:
		var rule: Variant=cfg["competition"]
		if not rule is Dictionary or rule!={"basis":"EXPLICIT_DEVELOPMENT_DIRECTED_CAPITAL_COMPETITION","acceptance_order":"BUYER_ID_ASCENDING","ranking":"OBSERVED_WINDOW_CONTRIBUTION_LESS_COMPLETE_ACQUISITION"}: return false
	seen.clear()
	for contact: Variant in cfg["contacts"]:
		if not contact is Dictionary or not FormalLedgerState.exact_fields(contact,["seller","buyer","available_minute","basis"]) or not spec["firms"].has(contact["seller"]) or not spec["firms"].has(contact["buyer"]) or contact["seller"]==contact["buyer"] or not FormalLedgerState.valid_amount(contact["available_minute"]) or contact["basis"]!="EXPLICIT_DEVELOPMENT_BILATERAL_CAPITAL_CONTACT": return false
	for row: Variant in cfg["npc_policies"]:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["firm","buyer","target_site","price","cash_floor","review_days","basis"]) or not spec["firms"].has(row["firm"]) or not spec["firms"].has(row["buyer"]) or row["firm"]==row["buyer"] or not spec["sites"].has(row["target_site"]) or spec["sites"][row["target_site"]]["firm_id"]!=row["buyer"] or seen.has(str(row["firm"])+"|"+str(row["buyer"]) if competition else row["firm"]) or row["basis"]!="EXPLICIT_DEVELOPMENT_KNOWN_COUNTERPARTY_IDLE_CAPITAL": return false
		for k: String in ["price","cash_floor","review_days"]:
			if not FormalLedgerState.valid_amount(row[k]): return false
		if row["price"]<1 or row["review_days"]<1: return false
		seen[str(row["firm"])+"|"+str(row["buyer"]) if competition else row["firm"]]=true
	var buyers: Dictionary={}
	if not cfg.get("autonomous_policies",[]) is Array or cfg.get("autonomous_policies",[]).size()>16: return false
	if not cfg.get("autonomous_policies",[]).is_empty() and not settings.has("cost_accounting"): return false
	for p: Variant in cfg.get("autonomous_policies",[]):
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["seller","buyer","site_id","activity_id","asset_type","observation_days","minimum_extra_batches","max_payback_days","max_price","cash_floor","review_days","message_delay_days","seller_idle_days","maintenance_days","basis"]): return false
		if not spec["firms"].has(p["seller"]) or not spec["firms"].has(p["buyer"]) or buyers.has(str(p["buyer"])+"|"+str(p["seller"]) if competition else p["buyer"]) or not spec["sites"].has(p["site_id"]) or spec["sites"][p["site_id"]]["firm_id"]!=p["buyer"] or p["basis"]!="EXPLICIT_DEVELOPMENT_OBSERVED_CAPACITY_ACQUISITION": return false
		var paired:=false
		for row: Dictionary in cfg["npc_policies"]:
			if row["firm"]==p["seller"] and row["buyer"]==p["buyer"] and row["target_site"]==p["site_id"]: paired=true
		var compatible:=false
		for t: Dictionary in cfg["types"]:
			if t["asset_type"]==p["asset_type"] and p["activity_id"] in t["targets"].get(p["site_id"],[]): compatible=true
		if not paired or not compatible: return false
		for k: String in ["observation_days","minimum_extra_batches","max_payback_days","max_price","cash_floor","review_days","message_delay_days","seller_idle_days","maintenance_days"]:
			if not FormalLedgerState.valid_amount(p[k]) or (k!="cash_floor" and p[k]<1): return false
		if p["observation_days"]>30 or p["seller_idle_days"]>30 or p["message_delay_days"]>30 or p["review_days"]>30: return false
		if competition:
			for prior: Dictionary in buyers.values():
				if prior["buyer"]!=p["buyer"]: continue
				for key: String in ["site_id","activity_id","asset_type","observation_days","minimum_extra_batches","max_payback_days","max_price","cash_floor","review_days","maintenance_days"]:
					if prior[key]!=p[key]: return false
		buyers[str(p["buyer"])+"|"+str(p["seller"]) if competition else p["buyer"]]=p


	return true

func move_rule(id: String) -> Dictionary:
	var a:=assets.get(id,{}) as Dictionary
	if a.is_empty() or template(a["template_id"])["kind"] in BUILD_KINDS: return {}
	for t: Dictionary in _economy().config.get("capital_resale",{}).get("types",[]):
		if t["asset_type"]==a["asset_type"]: return t
	return {}

func asset_moved(id: String) -> bool:
	for p: Dictionary in projects.values():
		if p["asset_id"]==id and p["kind"] in MOVE_KINDS: return true
	return false

func asset_state(id: String, minute: int=-1) -> Dictionary:
	var a:=assets.get(id,{}) as Dictionary
	if a.is_empty(): return {}
	if minute<0: minute=_economy()._world.game_clock.total_minutes()
	var result:={"owner":a["firm"],"custodian":a["firm"],"site_id":a["site_id"],"installed_site":a["site_id"],"activities":a["activities"].duplicate(),"status":"","place_id":_economy()._place(a["site_id"]),"transport":"NONE"}
	for event: Dictionary in a["events"]:
		if event["minute"]<=minute: result["status"]=event["status"]
	var last: int=-1
	for t: Dictionary in resale_trades.values():
		if t.get("asset_id")==id and int(t.get("delivered_minute",-1))>=0 and int(t["delivered_minute"])<=minute and int(t["delivered_minute"])>=last:
			last=t["delivered_minute"];result["owner"]=t["buyer"];result["custodian"]=t["buyer"];result["site_id"]=t["target_site"]
	var installed: int=-1
	for p: Dictionary in projects.values():
		if p.get("asset_id")==id and p.get("kind")=="REINSTALL" and int(p.get("completed_minute",-1))>=0 and int(p["completed_minute"])<=minute and int(p["completed_minute"])>=installed:
			installed=p["completed_minute"];result["installed_site"]=p["site_id"]
			result["activities"]=move_rule(id).get("targets",{}).get(p["site_id"],[]).duplicate()
	if result["status"] not in ["ACTIVE","PAUSED","MAINTENANCE","RETIRED"]: result["installed_site"]=""
	result["place_id"]=_economy()._place(result["site_id"])
	result.merge(_economy()._capital_transport.custody(id,minute),true)
	return result

func move_busy(id: String) -> bool:
	for p: String in _active:
		if projects[p]["asset_id"]==id: return true
	for t: Dictionary in resale_trades.values():
		if t["asset_id"]==id and t["state"]=="ACCEPTED": return true
	return false

func move_permission(actor: String, firm: String, op: String, amount: int=0) -> Dictionary:
	var e:=_economy();var now: int=e._world.game_clock.total_minutes()
	if e.firm_manager_at(firm,now)!=actor or e.firm_finished(firm): return {"ok":false,"reason":"CURRENT_CAPITAL_CONTROLLER_REQUIRED"}
	var organization: String=e._spec["firms"].get(firm,{}).get("host_organization_id","")
	if not organization.is_empty() and not e._world.organization_state.is_organization_active(organization): return {"ok":false,"reason":"CAPITAL_ORGANIZATION_INACTIVE"}
	for p: Dictionary in e.config.get("capital_resale",{}).get("authorities",[]):
		if p["firm"]!=firm or p["controller"]!=actor or op not in p["operations"] or amount>p["limit"] or now<p["start_minute"] or now>=p["end_minute"]: continue
		var proof:={"ok":true,"actor":actor,"firm":firm,"operation":op,"amount":amount,"minute":now,"before_boundary":e.processing,"source":p.duplicate(true)}
		if not p["root_authority"].is_empty():
			var operation:="economy.procure" if op=="acquire" else "economy.capital."+op
			var place: String=e._place(e._primary_site(firm))
			var scope:={"operation":operation,"target":firm,"place":place,"category":"capital_asset","amount":amount}
			var context: Dictionary=e._cargo_fulfilment._available_context(actor,firm,scope,p["root_authority"])
			var auth: Dictionary=e._cargo_fulfilment._authorize(actor,firm,operation,firm,place,"capital_asset",amount,{firm+"|"+operation+"|capital_asset":context})
			if not auth["ok"] or auth["proof"].get("authority_id")!=p["root_authority"]: continue
			proof["root_proof"]=auth["proof"]
		return proof
	return {"ok":false,"reason":"NO_SEPARATE_CAPITAL_"+op.to_upper()+"_AUTHORITY"}

func move_proof_valid(proof: Variant, actor: String, firm: String, op: String, amount: int, minute: int) -> bool:
	if not proof is Dictionary or not EconomySliceConfig._fields(proof,["ok","actor","firm","operation","amount","minute","before_boundary","source"],["root_proof"]) or proof["ok"]!=true or proof["actor"]!=actor or proof["firm"]!=firm or proof["operation"]!=op or proof["amount"]!=amount or proof["minute"]!=minute or not proof["before_boundary"] is bool: return false
	var p: Variant=proof["source"];var e:=_economy()
	if not p is Dictionary or not e.config.get("capital_resale",{}).get("authorities",[]).has(p) or p["firm"]!=firm or p["controller"]!=actor or op not in p["operations"] or amount>p["limit"] or minute<p["start_minute"] or minute>=p["end_minute"] or e.firm_manager_at(firm,maxi(0,minute-1) if proof["before_boundary"] else minute)!=actor: return false
	if p["root_authority"].is_empty(): return not proof.has("root_proof")
	var root:=proof.get("root_proof",{}) as Dictionary
	return e._cargo_fulfilment._saved_authority(root) and root.get("authority_id")==p["root_authority"] and root.get("actor")==actor and root.get("subject")==firm and root.get("operation")==("economy.procure" if op=="acquire" else "economy.capital."+op) and root.get("target")==firm and root.get("place")==e._place(e._primary_site(firm)) and root.get("category")=="capital_asset" and root.get("amount")==amount and root.get("minute")==minute

func move_terms(p: Dictionary) -> Dictionary:
	var t:=move_rule(p["asset_id"])
	if t.is_empty(): return {}
	var result: Dictionary=t[str(p["kind"]).to_lower()].duplicate(true)
	result["denomination"]=t["denomination"];result["cash_floor"]=0
	return result


func acceptance_check(actor: String, o: Dictionary) -> Dictionary:
	var e:=_economy();var now: int=e._world.game_clock.total_minutes();var state:=asset_state(o["asset_id"])
	if not known_offer(o,now): return _reject("CAPITAL_QUOTATION_NOT_YET_RECEIVED")
	if not exclusive_trade(o["asset_id"]).is_empty(): return _reject("ASSET_EXCLUSIVE_TRADE_ALREADY_ACCEPTED")
	for previous: Dictionary in resale_trades.values():
		if previous["offer_id"]==o["id"]: return _reject("CAPITAL_QUOTATION_ALREADY_ACCEPTED")
	if o["withdrawn"] or now>=o["expires_minute"] or move_busy(o["asset_id"]) or state["status"]!="DETACHED" or state["owner"]!=o["seller"] or state["site_id"]!=o["source_site"] or e._firm_winding_down(o["buyer"]) or not e._site_operating(o["target_site"]): return _reject("CAPITAL_OFFER_STALE_OR_BUYER_CLOSED")
	var proof:=move_permission(actor,o["buyer"],"acquire",o["price"]);var pay:=move_permission(actor,o["buyer"],"pay",o["price"])
	if not proof["ok"] or not pay["ok"]: return _reject("SEPARATE_ASSET_PURCHASE_AND_PAYMENT_AUTHORITY_REQUIRED")
	var plan: Dictionary=e._budgets.plan(o["buyer"],o["denomination"],"capital_asset",o["price"],now)
	if not plan["ok"]: return _reject(plan["reason"])
	if plan.has("rule_id") and plan["root_authority"] not in [proof["source"]["id"],proof.get("root_proof",{}).get("authority_id","")]: return _reject("ASSET_BUDGET_REQUIRES_ORIGINAL_PURCHASE_AUTHORITY")
	if competition_enabled() and cross_trade(o):
		var carriage:=known_carriage_estimate(o)
		if not carriage["known"]: return _reject(carriage["reason"])
		var freight_plan: Dictionary=e._budgets.plan(o["buyer"],o["denomination"],"capital_freight",carriage["freight"],now)
		var freight_proof:=move_permission(actor,o["buyer"],"freight",carriage["freight"])
		if not freight_plan.get("ok",false) or not freight_plan.has("rule_id") or not freight_proof["ok"] or freight_plan["root_authority"]!=freight_proof["source"]["id"] or not move_permission(actor,o["buyer"],"pay",carriage["freight"])["ok"]: return _reject("SEPARATE_CAPITAL_FREIGHT_AUTHORITY_AND_BUDGET_REQUIRED")
		if e._world.ledger_state.available_balance(e._account(o["buyer"],o["denomination"]))<int(o["price"])+int(carriage["freight"]): return _reject("PURCHASE_AND_FREIGHT_CASH_UNAVAILABLE")
	if resale_trades.size()>=LIMIT or e._world.ledger_state.available_balance(e._account(o["buyer"],o["denomination"]))<o["price"]: return _reject("CAPITAL_PURCHASE_CASH_OR_HISTORY_LIMIT")
	return {"accepted":true,"reason":"ORIGINAL_CAPITAL_ACCEPTANCE_CHECK_READY","authority":proof,"payment_authority":pay,"plan":plan}

func move_request(actor: String, kind: String, payload: Dictionary, action: String) -> Dictionary:
	var e:=_economy();var now: int=e._world.game_clock.total_minutes()
	if not e.config.has("capital_resale"): return _reject("MOVABLE_CAPITAL_NOT_ENABLED")
	if kind in ["dismantle_capital","reinstall_capital"]:
		if not FormalLedgerState.exact_fields(payload,["asset_id"]) or not assets.has(payload["asset_id"]): return _reject("UNKNOWN_CAPITAL_ASSET")
		var id: String=payload["asset_id"];var state:=asset_state(id);var rule:=move_rule(id)
		if rule.is_empty() or state["status"] in ["MAINTENANCE","RETIRED"] or e._service_market.asset_busy(id) or move_busy(id): return _reject("ASSET_NOT_MOVABLE_OR_STILL_COMMITTED")
		for pending: String in _pending:
			if changes[pending]["payload"].get("asset_id")==id: return _reject("CAPITAL_CONTROL_ALREADY_PENDING")
		var dismantle: bool=kind=="dismantle_capital"
		if state["status"] not in (["ACTIVE","PAUSED"] if dismantle else ["DETACHED"]): return _reject("ASSET_NOT_IN_REQUIRED_PHYSICAL_STATE")
		if not dismantle and (not rule["targets"].has(state["site_id"]) or e._firm_winding_down(state["owner"])): return _reject("NO_COMPATIBLE_CURRENT_INSTALLATION_RIGHT")
		var terms: Dictionary=rule["dismantle" if dismantle else "reinstall"]
		var proof:=move_permission(actor,state["owner"],"disassemble" if dismantle else "install",terms["budget"])
		if not proof["ok"]: return _reject(proof["reason"])
		if not e._site_operating(state["site_id"]): return _reject("CURRENT_SITE_RIGHT_NOT_AVAILABLE")
		return new_move_project(actor,action,id,state["owner"],state["site_id"],"DISMANTLE" if dismantle else "REINSTALL",proof)
	if kind=="offer_capital_asset":
		if not FormalLedgerState.exact_fields(payload,["asset_id","buyer","target_site","price","valid_days"]) or not assets.has(payload["asset_id"]) or not e._spec["firms"].has(payload["buyer"]) or not e._spec["sites"].has(payload["target_site"]) or not FormalLedgerState.valid_amount(payload["price"]) or payload["price"]<1 or not FormalLedgerState.valid_amount(payload["valid_days"]) or payload["valid_days"]<1 or payload["valid_days"]>14: return _reject("INVALID_DIRECTED_CAPITAL_OFFER")
		var state:=asset_state(payload["asset_id"]);var rule:=move_rule(payload["asset_id"])
		if e.firm_manager_at(state["owner"],now)!=actor: return _reject("CURRENT_CAPITAL_OWNER_DISPOSAL_AUTHORITY_REQUIRED")
		if rule.is_empty() or state["status"]!="DETACHED" or move_busy(payload["asset_id"]) or e._service_market.asset_busy(payload["asset_id"]): return _reject("DISMANTLE_AND_RELEASE_ASSET_BEFORE_SALE")
		if not known_capital_counterparty(state["owner"],payload["buyer"]): return _reject("CAPITAL_BUYER_NOT_KNOWN_BY_DECLARED_CONTACT")
		if state["owner"]==payload["buyer"] or e._owner(payload["target_site"])!=payload["buyer"] or not rule["targets"].has(payload["target_site"]): return _reject("BUYER_OR_ACTIVITY_INCOMPATIBLE")
		if state["place_id"]!=e._place(payload["target_site"]) and (rule["transport"]!="EXPLICIT_SHARED_UNIQUE_ASSET_CARRIAGE" or e._capital_transport.routes(payload["asset_id"],state["site_id"],payload["target_site"],payload["buyer"]).is_empty()): return _reject("UNIQUE_ASSET_FREIGHT_ROUTE_WEIGHT_AND_ADOPTION_NOT_CONFIGURED")
		if not e._site_operating(payload["target_site"]): return _reject("BUYER_PREMISES_NOT_AVAILABLE")
		for o: Dictionary in resale_offers.values():
			if o["asset_id"]==payload["asset_id"] and o["expires_minute"]>now and not o["withdrawn"] and not capital_offer_used(o["id"]) and (not competition_enabled() or o["buyer"]==payload["buyer"]): return _reject("ASSET_ALREADY_HAS_LIVE_OFFER_FOR_RECIPIENT" if competition_enabled() else "ASSET_ALREADY_HAS_LIVE_OFFER")
		if resale_offers.size()>=LIMIT: return _reject("CAPITAL_OFFER_HISTORY_LIMIT")
		var proof:=move_permission(actor,state["owner"],"sell",payload["price"])
		if not proof["ok"]: return _reject(proof["reason"])
		var id:="capital_offer:"+action
		resale_offers[id]={"id":id,"action_id":action,"actor":actor,"asset_id":payload["asset_id"],"seller":state["owner"],"source_site":state["site_id"],"buyer":payload["buyer"],"target_site":payload["target_site"],"price":payload["price"],"denomination":rule["denomination"],"minute":now,"expires_minute":now+payload["valid_days"]*1440,"authority":proof,"withdrawn":false,"withdrawal_action":"","terms":"SELLER_TITLE_UNTIL_WORKED_DESTINATION_DELIVERY" if state["place_id"]!=e._place(payload["target_site"]) else "SELLER_TITLE_AND_CUSTODY_UNTIL_WORKED_SAME_PLACE_DELIVERY"}
		if not autonomous_policy(payload["buyer"],state["owner"]).is_empty():
			resale_offers[id]["equipment"]={"asset_type":assets[payload["asset_id"]]["asset_type"],"capacity":assets[payload["asset_id"]]["capacity"],"activities":rule["targets"][payload["target_site"]].duplicate()}
			# The existing addressed R1 channel carries a locked quotation, not goods.
			e._schedule_message(payload["buyer"],"capital_offer",id,e.day+int(autonomous_policy(payload["buyer"],state["owner"])["message_delay_days"]),e.day)
		return {"accepted":true,"reason":"DIRECT_CAPITAL_QUOTATION","offer_id":id}
	if kind=="withdraw_capital_offer":
		if not FormalLedgerState.exact_fields(payload,["offer_id"]) or not resale_offers.has(payload["offer_id"]): return _reject("UNKNOWN_CAPITAL_OFFER")
		var o:=resale_offers[payload["offer_id"]] as Dictionary
		if capital_offer_used(o["id"]) or move_busy(o["asset_id"]) or not move_permission(actor,o["seller"],"sell",o["price"])["ok"]: return _reject("ACCEPTED_TRADE_OR_NO_DISPOSAL_AUTHORITY")
		o["withdrawn"]=true;o["withdrawal_action"]=action
		return {"accepted":true,"reason":"FUTURE_CAPITAL_OFFER_WITHDRAWN"}
	if kind=="accept_capital_offer":
		if not FormalLedgerState.exact_fields(payload,["offer_id"]) or not resale_offers.has(payload["offer_id"]): return _reject("UNKNOWN_CAPITAL_OFFER")
		var o:=resale_offers[payload["offer_id"]] as Dictionary
		var check:=acceptance_check(actor,o)
		if not check["accepted"]: return check
		var proof: Dictionary=check["authority"];var pay: Dictionary=check["payment_authority"];var plan: Dictionary=check["plan"]
		var id:="capital_trade:"+action;var account: String=e._account(o["buyer"],o["denomination"])
		if not e._world.ledger_state.reserve(id,account,o["price"]): return _reject("CAPITAL_CASH_RESERVATION_FAILED")
		if not e._budgets.commit(id,[plan]):
			e._world.ledger_state.release(id,o["price"])
			return _reject("CAPITAL_CUMULATIVE_BUDGET_COMMITMENT_FAILED")
		resale_trades[id]={"id":id,"action_id":action,"actor":actor,"offer_id":o["id"],"asset_id":o["asset_id"],"seller":o["seller"],"buyer":o["buyer"],"source_site":o["source_site"],"target_site":o["target_site"],"accepted_minute":now,"delivered_minute":-1,"state":"ACCEPTED","authority":proof,"payment_authority":pay,"delivery_project":"","cancel_action":""}
		return {"accepted":true,"reason":"ASSET_PRICE_RESERVED_TITLE_NOT_TRANSFERRED","trade_id":id}
	if kind in ["deliver_capital_asset","cancel_capital_trade"]:
		if not FormalLedgerState.exact_fields(payload,["trade_id"]) or not resale_trades.has(payload["trade_id"]): return _reject("UNKNOWN_CAPITAL_TRADE")
		var t:=resale_trades[payload["trade_id"]] as Dictionary;var o:=resale_offers[t["offer_id"]] as Dictionary
		if t["state"]!="ACCEPTED" or not t["delivery_project"].is_empty(): return _reject("CAPITAL_DELIVERY_ALREADY_STARTED_OR_SETTLED")
		if kind=="cancel_capital_trade" and not e._capital_transport.for_trade(t["id"]).is_empty(): return _reject("CARRIER_CUSTODY_COMMITMENT_REMAINS_NO_CANCELLATION_POLICY")
		if kind=="cancel_capital_trade":
			var cancel_proof:=move_permission(actor,t["buyer"],"acquire",o["price"])
			if not cancel_proof["ok"]: return _reject("CURRENT_AUTHORIZED_BUYER_REQUIRED")
			e._world.ledger_state.release(t["id"],o["price"])
			assert(e._budgets.settle("cancel:"+t["id"],t["id"],0,o["price"],o["price"]))
			t["state"]="CANCELLED";t["cancel_action"]=action
			return {"accepted":true,"reason":"UNSTARTED_DELIVERY_CANCELLED_PRIOR_DISMANTLING_COST_RETAINED","authority":cancel_proof}
		var state:=asset_state(t["asset_id"]);var rule:=move_rule(t["asset_id"])
		var cross:=cross_trade(t)
		if state["owner"]!=t["seller"] or state["status"]!="DETACHED" or state["place_id"]!=e._place(t["target_site"]): return _reject("ASSET_NOT_AT_CONTRACT_HANDOVER_PLACE")
		if cross and e._capital_transport.for_trade(t["id"]).get("stage")!="AWAITING_RECIPIENT": return _reject("ACTUAL_DESTINATION_UNLOADING_REQUIRED")
		if not cross and state["site_id"]!=t["source_site"]: return _reject("ASSET_NOT_AT_CONTRACT_HANDOVER_PLACE")
		var proof:=move_permission(actor,t["buyer"] if cross else t["seller"],"handover",rule["handover"]["budget"])
		if not proof["ok"]: return _reject(proof["reason"])
		var result:=new_move_project(actor,action,t["asset_id"],t["buyer"] if cross else t["seller"],t["target_site"] if cross else t["source_site"],"HANDOVER",proof,t["id"])
		if result["accepted"]: t["delivery_project"]=result["project_id"]
		return result
	return _reject("UNKNOWN_MOBILE_CAPITAL_ACTION")

func new_move_project(actor: String, action: String, asset: String, firm: String, site: String, kind: String, proof: Dictionary, trade: String="") -> Dictionary:
	if projects.size()>=LIMIT: return _reject("CAPITAL_PROJECT_HISTORY_LIMIT")
	var id:="capital_project:"+action;var now: int=_economy()._world.game_clock.total_minutes()
	var p:={"id":id,"action_id":action,"actor":actor,"template_id":assets[asset]["template_id"],"firm":firm,"site_id":site,"kind":kind,"accepted_minute":now,"budget":move_rule(asset)[kind.to_lower()]["budget"],"status":"ACCEPTED","materials":{},"material_minute":-1,"work":[],"started_minute":-1,"completed_minute":-1,"orders":[],"asset_id":asset,"reason":"","mobility_authority":proof,"trade_id":trade,"work_permissions":[],"material_permission":{},"completion_permission":{}}
	projects[id]=p;_active.append(id)
	if not _active_by_site.has(site): _active_by_site[site]=[]
	_active_by_site[site].append(id)
	if not _site_projects.has(site): _site_projects[site]=[]
	_site_projects[site].append(id)
	return {"accepted":true,"reason":"REAL_CAPITAL_WORK_ACCEPTED","project_id":id}

func move_work_allowed(p: Dictionary, minute: int) -> bool:
	var e:=_economy();var op: String={"DISMANTLE":"disassemble","HANDOVER":"handover","REINSTALL":"install"}[p["kind"]]
	if not move_permission(p["actor"],p["firm"],op,p["budget"])["ok"] or e._service_market.asset_busy(p["asset_id"]): return false
	var state:=asset_state(p["asset_id"],minute)
	if p["kind"]=="HANDOVER" and cross_trade(resale_trades[p["trade_id"]]):
		var t:=resale_trades[p["trade_id"]] as Dictionary
		return state["owner"]==t["seller"] and state["place_id"]==e._place(t["target_site"]) and e._capital_transport.for_trade(t["id"]).get("stage")=="AWAITING_RECIPIENT"
	return state["owner"]==p["firm"] and state["site_id"]==p["site_id"] and state["status"]=={"DISMANTLE":"DISMANTLING","HANDOVER":"DETACHED","REINSTALL":"REINSTALLING"}[p["kind"]]

func move_boundary(p: Dictionary, now: int) -> void:
	var e:=_economy();var a:=assets[p["asset_id"]] as Dictionary
	if now<=p["accepted_minute"]: return
	var state:=asset_state(a["id"])
	var transitional: String="DISMANTLING" if p["kind"]=="DISMANTLE" else "REINSTALLING"
	if p["kind"]!="HANDOVER" and state["status"]!=transitional:
		if now!=(int(p["accepted_minute"])/1440+1)*1440:
			p["reason"]="WAITING_LAWFUL_TRANSITION_BOUNDARY";return
		_asset_event(a,transitional,now,p["action_id"])
	if p["status"]!="WAITING_INSTALLATION" or now-p["started_minute"]<move_terms(p)["duration_minutes"]: return
	if not move_work_allowed(p,maxi(0,now-1)) or not e._site_operating(p["site_id"]): p["reason"]="CURRENT_DELIVERY_OR_INSTALLATION_RIGHT_UNAVAILABLE";return
	if p["kind"]=="HANDOVER":
		var t:=resale_trades[p["trade_id"]] as Dictionary;var o:=resale_offers[t["offer_id"]] as Dictionary
		if not e._site_operating(t["target_site"]) or asset_state(a["id"])["owner"]!=t["seller"]: p["reason"]="BUYER_PREMISES_OR_SELLER_TITLE_UNAVAILABLE";return
		var batch: String="capital_payment:"+t["id"]
		var legs:=capital_payment_legs(t)
		var release:={t["id"]:o["price"]}
		if not e._world.ledger_state.payment_ready(batch,legs,now,release) or not e._budgets.change_ready(t["id"],o["price"],0,o["price"]): p["reason"]="ORIGINAL_RESERVED_ASSET_PAYMENT_NOT_READY";return
		assert(e._world.ledger_state.batch_payment(batch,legs,now,release))
		assert(e._budgets.settle(batch,t["id"],o["price"],0,o["price"]))
		t["state"]="DELIVERED";t["delivered_minute"]=now
		if cross_trade(t): e._capital_transport.delivered(t["id"])
		_pool_cache.clear()
	else: _asset_event(a,"DETACHED" if p["kind"]=="DISMANTLE" else "ACTIVE",now,p["action_id"])
	p["completion_permission"]=move_execution_permission(p)
	p["status"]="COMPLETED";p["completed_minute"]=now;p["reason"]=""
	_active.erase(p["id"]);_active_by_site[p["site_id"]].erase(p["id"])

func capital_payment_legs(t: Dictionary) -> Array[Dictionary]:
	var e:=_economy();var o:=resale_offers[t["offer_id"]] as Dictionary
	return [{"transaction_id":"capital_payment:"+t["id"],"from_account_id":e._account(t["buyer"],o["denomination"]),"to_account_id":e._account(t["seller"],o["denomination"]),"amount":o["price"],"kind":"capital_equipment","reference_id":t["id"]}]

func resale_cash_reservations() -> Dictionary:
	var result: Dictionary={}
	for t: Dictionary in resale_trades.values():
		if t["state"]=="ACCEPTED":
			var o:=resale_offers[t["offer_id"]] as Dictionary
			result[t["id"]]={"account_id":_economy()._account(t["buyer"],o["denomination"]),"amount":o["price"]}
	return result

func resale_budget_contracts() -> Dictionary:
	var result: Dictionary={}
	for t: Dictionary in resale_trades.values():
		var o:=resale_offers[t["offer_id"]] as Dictionary
		result[t["id"]]={"kind":"CAPITAL_ASSET","buyer":t["buyer"],"category":"capital_asset","denomination":o["denomination"],"quantity":o["price"],"accepted_minute":t["accepted_minute"],"delivered":o["price"] if t["state"]=="DELIVERED" else 0,"cancelled":o["price"] if t["state"]=="CANCELLED" else 0,"route_legs":[]}
	return result


func valid_move_source(p: Dictionary, command: Dictionary, _saved: Dictionary) -> bool:
	if not p.get("work_permissions") is Array or not p.get("material_permission") is Dictionary or not p.get("completion_permission") is Dictionary: return false
	if not assets.has(p["asset_id"]) or p["template_id"]!=assets[p["asset_id"]]["template_id"] or move_rule(p["asset_id"]).is_empty() or not p.get("trade_id") is String: return false
	if p["kind"]=="HANDOVER" and (not resale_trades.has(p["trade_id"]) or resale_trades[p["trade_id"]]["delivery_project"]!=p["id"]): return false
	if p["kind"]!="HANDOVER" and p["trade_id"]!="": return false
	var kind: String={"DISMANTLE":"dismantle_capital","HANDOVER":"deliver_capital_asset","REINSTALL":"reinstall_capital"}[p["kind"]]
	var payload: Dictionary={"trade_id":p["trade_id"]} if p["kind"]=="HANDOVER" else {"asset_id":p["asset_id"]}
	var op: String={"DISMANTLE":"disassemble","HANDOVER":"handover","REINSTALL":"install"}[p["kind"]]
	return command.get("result",{}).get("accepted",false) and command["result"].get("project_id")==p["id"] and command["envelope"]["actor"]==p["actor"] and command["envelope"]["command"]=={"action_id":p["action_id"],"minute":p["accepted_minute"],"kind":kind,"payload":payload} and move_proof_valid(p.get("mobility_authority"),p["actor"],p["firm"],op,p["budget"],p["accepted_minute"]) and p["budget"]==move_terms(p)["budget"]

func validate_resale(saved: Dictionary) -> bool:
	for o: Dictionary in resale_offers.values():
		if autonomous_policy(o["buyer"],o["seller"]).is_empty():
			if o.has("equipment"): return _fail("Legacy capital quotation acquired unsupported equipment disclosure")
			continue
		if not assets.has(o["asset_id"]) or o.get("equipment")!={"asset_type":assets[o["asset_id"]]["asset_type"],"capacity":assets[o["asset_id"]]["capacity"],"activities":move_rule(o["asset_id"]).get("targets",{}).get(o["target_site"],[])}: return _fail("Capital quotation equipment disclosure differs from original asset")
		var id:=quote_message_id(o)
		var count:=1 if saved.get("receipts",{}).has(id) else 0
		for message: Dictionary in saved.get("messages",[]):
			if message.get("id")==id: count+=1
		if count!=1: return _fail("Directed capital quotation lost or duplicated its original R1 message")
	var e:=_economy();var now: int=e._world.game_clock.total_minutes();var live: Dictionary={};var accepted_offers: Dictionary={}
	if resale_offers.size()>LIMIT or resale_trades.size()>LIMIT: return _fail("Capital resale history exceeds limit")
	for id: String in resale_offers:
		var o: Variant=resale_offers[id]
		if not o is Dictionary or not EconomySliceConfig._fields(o,["id","action_id","actor","asset_id","seller","source_site","buyer","target_site","price","denomination","minute","expires_minute","authority","withdrawn","withdrawal_action","terms"],["equipment"]) or o["id"]!=id or id!="capital_offer:"+str(o["action_id"]) or not assets.has(o["asset_id"]) or move_rule(o["asset_id"]).is_empty() or not FormalLedgerState.valid_amount(o["price"]) or o["price"]<1 or not o["minute"] is int or o["minute"]<0 or o["minute"]>now or not o["expires_minute"] is int or o["expires_minute"]<=o["minute"] or o["terms"]!=("SELLER_TITLE_UNTIL_WORKED_DESTINATION_DELIVERY" if cross_trade(o) else "SELLER_TITLE_AND_CUSTODY_UNTIL_WORKED_SAME_PLACE_DELIVERY") or not o["withdrawn"] is bool or not o["withdrawal_action"] is String: return _fail("Invalid capital quotation identity or amount")
		var c:=saved.get("commands",{}).get(o["action_id"],{}) as Dictionary
		var payload: Dictionary=c.get("envelope",{}).get("command",{}).get("payload",{})
		if not c.get("result",{}).get("accepted",false) or c["result"].get("offer_id")!=id or c["envelope"]["actor"]!=o["actor"] or c["envelope"]["command"]["minute"]!=o["minute"] or c["envelope"]["command"]["kind"]!="offer_capital_asset" or payload!={"asset_id":o["asset_id"],"buyer":o["buyer"],"target_site":o["target_site"],"price":o["price"],"valid_days":(int(o["expires_minute"])-int(o["minute"]))/1440} or not move_proof_valid(o["authority"],o["actor"],o["seller"],"sell",o["price"],o["minute"]): return _fail("Capital quotation lacks original disposal authority")
		if not known_capital_counterparty(o["seller"],o["buyer"],o["minute"]) or not e._spec["sites"].has(o["source_site"]) or not e._spec["sites"].has(o["target_site"]) or e._owner(o["target_site"])!=o["buyer"] or (cross_trade(o) and not historical_route(o)) or not move_rule(o["asset_id"])["targets"].has(o["target_site"]) or o["denomination"]!=move_rule(o["asset_id"])["denomination"]: return _fail("Capital quotation has no compatible lawful delivery")
		if o["withdrawn"]:
			var withdrawal: Dictionary=saved["commands"].get(o["withdrawal_action"],{})
			if not withdrawal.get("result",{}).get("accepted",false) or withdrawal["envelope"]["command"]["kind"]!="withdraw_capital_offer" or withdrawal["envelope"]["command"]["payload"]!={"offer_id":id}: return _fail("Capital offer withdrawal lacks action")
		elif o["withdrawal_action"]!="": return _fail("Unwithdrawn offer claims a withdrawal")
	for id: String in resale_trades:
		var t: Variant=resale_trades[id]
		if not t is Dictionary or not FormalLedgerState.exact_fields(t,["id","action_id","actor","offer_id","asset_id","seller","buyer","source_site","target_site","accepted_minute","delivered_minute","state","authority","payment_authority","delivery_project","cancel_action"]) or t["id"]!=id or id!="capital_trade:"+str(t["action_id"]) or not resale_offers.has(t["offer_id"]) or t["state"] not in ["ACCEPTED","DELIVERED","CANCELLED"] or not t["delivery_project"] is String or not t["cancel_action"] is String or not t["delivered_minute"] is int or not t["accepted_minute"] is int: return _fail("Invalid capital trade")
		if accepted_offers.has(t["offer_id"]): return _fail("Capital quotation accepted twice")
		accepted_offers[t["offer_id"]]=true
		var o:=resale_offers[t["offer_id"]] as Dictionary
		for key: String in ["asset_id","seller","buyer","source_site","target_site"]:
			if t[key]!=o[key]: return _fail("Capital trade differs from locked quotation")
		if t["accepted_minute"]<o["minute"] or t["accepted_minute"]>=o["expires_minute"] or t["accepted_minute"]>now or not move_proof_valid(t["authority"],t["actor"],t["buyer"],"acquire",o["price"],t["accepted_minute"]) or not move_proof_valid(t["payment_authority"],t["actor"],t["buyer"],"pay",o["price"],t["accepted_minute"]): return _fail("Capital trade lacks locked authority or time")
		var c:=saved.get("commands",{}).get(t["action_id"],{}) as Dictionary
		if not c.get("result",{}).get("accepted",false) or c["result"].get("trade_id")!=id or c["envelope"]["actor"]!=t["actor"] or c["envelope"]["command"]["kind"]!="accept_capital_offer" or c["envelope"]["command"]["minute"]!=t["accepted_minute"] or c["envelope"]["command"]["payload"]!={"offer_id":t["offer_id"]}: return _fail("Capital trade lacks original accepted action")
		if not autonomous_policy(t["buyer"],t["seller"]).is_empty():
			var receipt: Dictionary=saved.get("receipts",{}).get(quote_message_id(o),{})
			if not quote_message_valid(receipt) or int(receipt["delivery_day"])*1440>t["accepted_minute"]: return _fail("Capital acquisition predates delivered quotation")
		var project:=projects.get(t["delivery_project"],{}) as Dictionary
		if not t["delivery_project"].is_empty() and (project.get("kind")!="HANDOVER" or project.get("trade_id")!=id or project.get("asset_id")!=t["asset_id"] or project.get("firm")!=(t["buyer"] if cross_trade(t) else t["seller"]) or project.get("site_id")!=(t["target_site"] if cross_trade(t) else t["source_site"])): return _fail("Capital delivery lacks actual work project")
		if t["state"]=="DELIVERED":
			if project.get("status")!="COMPLETED" or project.get("completed_minute")!=t["delivered_minute"] or not valid_resale_payment("capital_payment:"+id): return _fail("Capital title has no actual delivery and atomic payment")
		else:
			if t["delivered_minute"]!=-1 or not e._world.ledger_state.payment_batch("capital_payment:"+id).is_empty(): return _fail("Uncompleted capital trade has payment or title")
			if t["state"]=="ACCEPTED":
				if live.has(t["asset_id"]): return _fail("Equipment sold to two outstanding buyers")
				live[t["asset_id"]]=true
			else:
				var cancel: Dictionary=saved["commands"].get(t["cancel_action"],{})
				if not t["delivery_project"].is_empty() or not cancel.get("result",{}).get("accepted",false) or not move_proof_valid(cancel["result"].get("authority"),cancel["envelope"]["actor"],t["buyer"],"acquire",o["price"],cancel["envelope"]["command"]["minute"]) or cancel["envelope"]["command"]["kind"]!="cancel_capital_trade" or cancel["envelope"]["command"]["minute"]<t["accepted_minute"] or cancel["envelope"]["command"]["payload"]!={"trade_id":id}: return _fail("Capital cancellation lacks unstarted buyer action")
	# Directed quotations may coexist; accepted responsibility intervals may not.
	var intervals: Dictionary={}
	for t: Dictionary in resale_trades.values():
		var end: int=now+1
		if t["state"]=="DELIVERED": end=t["delivered_minute"]
		elif t["state"]=="CANCELLED": end=saved["commands"][t["cancel_action"]]["envelope"]["command"]["minute"]
		if not intervals.has(t["asset_id"]): intervals[t["asset_id"]]=[]
		intervals[t["asset_id"]].append({"start":t["accepted_minute"],"end":end,"id":t["id"]})
	for asset: String in intervals:
		var rows: Array=intervals[asset]
		rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["start"]<b["start"] if a["start"]!=b["start"] else a["id"]<b["id"])
		var through: int=-1
		for row: Dictionary in rows:
			if row["start"]<through: return _fail("Capital asset has overlapping exclusive trade intervals")
			through=maxi(through,int(row["end"]))
	for action: String in saved.get("commands",{}):
		var entry:=saved["commands"][action] as Dictionary
		if not entry.get("result",{}).get("accepted",false): continue
		var command:=entry["envelope"]["command"] as Dictionary
		if command["kind"] in ["dismantle_capital","deliver_capital_asset","reinstall_capital"] and not projects.has("capital_project:"+action): return _fail("Accepted mobile work lost its original project")
		if command["kind"]=="offer_capital_asset" and not resale_offers.has("capital_offer:"+action): return _fail("Accepted capital quotation was removed")
		if command["kind"]=="accept_capital_offer" and not resale_trades.has("capital_trade:"+action): return _fail("Accepted capital contract was removed")
		if command["kind"]=="cancel_capital_trade" and resale_trades.get(command["payload"].get("trade_id"),{}).get("cancel_action")!=action: return _fail("Capital cancellation lost its contract")
		if command["kind"]=="withdraw_capital_offer" and resale_offers.get(command["payload"].get("offer_id"),{}).get("withdrawal_action")!=action: return _fail("Capital withdrawal lost its quotation")
	# Rebuild one chronological owner/custody chain; no independently editable owner.
	for asset: String in assets:
		var chain: Array[Dictionary]=[]
		for p: Dictionary in projects.values():
			if p["asset_id"]!=asset or p["kind"] not in MOVE_KINDS: continue
			if p["status"] in ["CANCELLED","PAUSED"]: return _fail("Mobile capital work was silently abandoned")
			if p["kind"]!="HANDOVER":
				var transition:={"minute":(int(p["accepted_minute"])/1440+1)*1440,"status":"DISMANTLING" if p["kind"]=="DISMANTLE" else "REINSTALLING","source":p["action_id"]}
				if transition["minute"]<=now and not assets[asset]["events"].has(transition): return _fail("Mobile equipment lost its stop-use boundary")
				if p["status"]=="COMPLETED" and not assets[asset]["events"].has({"minute":p["completed_minute"],"status":"DETACHED" if p["kind"]=="DISMANTLE" else "ACTIVE","source":p["action_id"]}): return _fail("Mobile equipment completion lost installation history")
			if p["kind"]=="REINSTALL" and not move_rule(asset)["targets"].has(p["site_id"]): return _fail("Mobile equipment has no compatible target activity")
		for p: Dictionary in projects.values():
			if p["asset_id"]==asset and p["kind"] in MOVE_KINDS:
				chain.append({"minute":p["accepted_minute"],"rank":4 if p["kind"]=="HANDOVER" else 1,"type":"WORK","row":p})
				if p["completed_minute"]>=0: chain.append({"minute":p["completed_minute"],"rank":0,"type":"FINISH","row":p})
		for t: Dictionary in resale_trades.values():
			if t["asset_id"]==asset and t["state"]!="CANCELLED": chain.append({"minute":t["accepted_minute"],"rank":3,"type":"TRADE","row":t})
		for o: Dictionary in resale_offers.values():
			if o["asset_id"]==asset: chain.append({"minute":o["minute"],"rank":2,"type":"QUOTE","row":o})
		chain.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["minute"]<b["minute"] if a["minute"]!=b["minute"] else a["rank"]<b["rank"])
		var owner: String=assets[asset]["firm"];var site: String=assets[asset]["site_id"];var busy: String="";var reserved: String="";var detached:=false
		for fact: Dictionary in chain:
			var row:=fact["row"] as Dictionary
			if fact["type"]=="WORK":
				if not busy.is_empty() or row["firm"]!=(resale_trades[row["trade_id"]]["buyer"] if row["kind"]=="HANDOVER" and cross_trade(resale_trades[row["trade_id"]]) else owner) or row["site_id"]!=(resale_trades[row["trade_id"]]["target_site"] if row["kind"]=="HANDOVER" and cross_trade(resale_trades[row["trade_id"]]) else site) or (row["kind"]=="DISMANTLE" and (detached or not reserved.is_empty())) or (row["kind"]!="DISMANTLE" and not detached) or (row["kind"]=="REINSTALL" and not reserved.is_empty()): return _fail("Equipment work duplicates custody or installation")
				if row["kind"]=="DISMANTLE" and asset_state(asset,int(row["accepted_minute"]))["status"] not in ["ACTIVE","PAUSED"]: return _fail("Equipment dismantled from unavailable or retired state")
				if row["kind"]=="HANDOVER" and reserved!=row["trade_id"]: return _fail("Equipment handover has no exclusive accepted trade")
				busy=row["id"]
			elif fact["type"]=="FINISH":
				if busy!=row["id"]: return _fail("Equipment completion has no original work")
				busy=""
				if row["kind"]=="HANDOVER":
					var trade:=resale_trades[row["trade_id"]] as Dictionary
					if trade["state"]!="DELIVERED": return _fail("Completed delivery has no title transfer")
					owner=trade["buyer"];site=trade["target_site"];reserved=""
				else: detached=row["kind"]=="DISMANTLE"
			elif fact["type"]=="QUOTE":
				if row["seller"]!=owner or row["source_site"]!=site or not detached or not busy.is_empty() or not reserved.is_empty(): return _fail("Capital quotation has no current detached owner interval")
			else:
				if not detached or not busy.is_empty() or not reserved.is_empty() or row["seller"]!=owner or row["source_site"]!=site: return _fail("Equipment trade rewrites title or double sells")
				if row["state"]!="CANCELLED": reserved=row["id"]
	return true

func valid_resale_payment(id: String) -> bool:
	var t:=resale_trades.get(id.trim_prefix("capital_payment:"),{}) as Dictionary
	if t.get("state")!="DELIVERED": return false
	var batch: Dictionary=_economy()._world.ledger_state.payment_batch(id)
	var o:=resale_offers[t["offer_id"]] as Dictionary
	var leg:=capital_payment_legs(t)[0]
	var tx: Dictionary=_economy()._world.ledger_state.transaction(id)
	for key: String in leg:
		if tx.get(key)!=leg[key]: return false
	return batch=={"transactions":[id],"releases":{t["id"]:o["price"]},"minute":t["delivered_minute"]} and tx.get("effective_minute")==t["delivered_minute"] and tx.get("denomination")==o["denomination"]

func mobility_costs(asset: String) -> Dictionary:
	var e:=_economy();var result:={"work":[],"transactions":[],"transport":_economy()._capital_transport.view(asset),"historical_formation_unchanged":true,"capitalization":"UNCONFIGURED_SEPARATE_ACQUISITION_DISMANTLING_AND_INSTALLATION","disposal_profit":null}
	for p: Dictionary in projects.values():
		if p["asset_id"]==asset and p["kind"] in MOVE_KINDS: result["work"].append({"project_id":p["id"],"kind":p["kind"],"firm":p["firm"],"site_id":p["site_id"],"hours":work_hours(p),"cost":e._costs.project_cost(p["id"]) if e._costs.enabled else {"unknown":["COST_ACCOUNTING_DISABLED"]}})
	for t: Dictionary in resale_trades.values():
		if t["asset_id"]==asset: result["transactions"].append(t.duplicate(true).merged({"price":resale_offers[t["offer_id"]]["price"],"denomination":resale_offers[t["offer_id"]]["denomination"]}))
	return result


func resale_business(actor: String, firm: String) -> Dictionary:
	var e:=_economy();var now: int=e._world.game_clock.total_minutes();var result:={"enabled":e.config.has("capital_resale"),"actions":[],"offers":[],"trades":[],"equipment":[],"work":[],"transport":"EXPLICIT_SHARED_UNIQUE_ASSET_CARRIAGE" if e.config.has("capital_transport") else "SAME_PLACE_WORKED_HANDOVER_ONLY_CROSS_PLACE_BLOCKED"}
	if e.firm_manager_at(firm,now)!=actor: return {}
	for id: String in assets:
		var state:=asset_state(id);var rule:=move_rule(id)
		if state["owner"]!=firm or rule.is_empty(): continue
		result["equipment"].append({"id":id,"asset_type":assets[id]["asset_type"],"capacity":assets[id]["capacity"],"current_use":state.duplicate(true),"original_firm":assets[id]["firm"],"original_site":assets[id]["site_id"],"project_id":assets[id]["project_id"],"exclusive":move_busy(id),"maintenance_recipe":maintenance_template(id,now).get("id","")})
		if move_busy(id): continue
		if state["status"] in ["ACTIVE","PAUSED"] and move_permission(actor,firm,"disassemble",rule["dismantle"]["budget"])["ok"]: result["actions"].append({"label":"申请真实拆卸 "+id,"kind":"dismantle_capital","payload":{"asset_id":id}})
		var maintenance:=maintenance_template(id,now)
		if state["status"] in ["ACTIVE","PAUSED"] and not maintenance.is_empty() and not e._service_market.asset_busy(id): result["actions"].append({"label":"申请当前企业内部维护","kind":"maintain_capital","payload":{"asset_id":id,"budget":maintenance["budget"]}})
		if state["status"]=="DETACHED" and not e._firm_winding_down(firm) and rule["targets"].has(state["site_id"]) and move_permission(actor,firm,"install",rule["reinstall"]["budget"])["ok"]: result["actions"].append({"label":"申请原设备重新安装 "+id,"kind":"reinstall_capital","payload":{"asset_id":id}})
		for policy: Dictionary in e.config.get("capital_resale",{}).get("npc_policies",[]):
			if policy["firm"]==firm and state["status"]=="DETACHED" and not live_asset_offer(id,policy["buyer"] if competition_enabled() else "") and move_permission(actor,firm,"sell",policy["price"])["ok"]: result["actions"].append({"label":"向 "+str(policy["buyer"])+" 报价 "+str(policy["price"])+" · "+str(policy["target_site"]),"kind":"offer_capital_asset","payload":{"asset_id":id,"buyer":policy["buyer"],"target_site":policy["target_site"],"price":policy["price"],"valid_days":7}})
	for o: Dictionary in resale_offers.values():
		if firm not in [o["seller"],o["buyer"]] or (firm==o["buyer"] and not known_offer(o,now)): continue
		var quote: Dictionary={}
		for key: String in ["id","asset_id","seller","buyer","source_site","target_site","price","denomination","minute","expires_minute","terms","equipment"]:
			if o.has(key): quote[key]=o[key].duplicate(true) if o[key] is Dictionary else o[key]
		quote["availability"]=offer_availability(o,now)
		quote["received_minute"]=int(e._receipts.get(quote_message_id(o),{}).get("delivery_day",-1))*1440 if not autonomous_policy(o["buyer"],o["seller"]).is_empty() else o["minute"]
		if o["buyer"]==firm:
			var check:=acceptance_check(actor,o)
			quote["estimate"]=acquisition_estimate(o)
			result["actions"].append({"label":"接受设备报价 "+str(o["price"]),"kind":"accept_capital_offer","payload":{"offer_id":o["id"]},"can_execute":check["accepted"],"reason":check["reason"]})
		elif not capital_offer_used(o["id"]) and not o["withdrawn"] and o["expires_minute"]>now and not move_busy(o["asset_id"]) and asset_state(o["asset_id"])["owner"]==o["seller"]: result["actions"].append({"label":"撤回未来设备报价","kind":"withdraw_capital_offer","payload":{"offer_id":o["id"]}})
		result["offers"].append(quote)
	for t: Dictionary in resale_trades.values():
		if firm not in [t["seller"],t["buyer"]]: continue
		result["trades"].append(t.duplicate(true).merged({"purchase_reserved":resale_offers[t["offer_id"]]["price"] if t["state"]=="ACCEPTED" else 0,"current_use":asset_state(t["asset_id"]),"carriage":e._capital_transport.view(t["asset_id"])}))
		if t["state"]=="ACCEPTED" and t["delivery_project"].is_empty() and ((not cross_trade(t) and e._capital_transport.for_trade(t["id"]).is_empty()) or (cross_trade(t) and firm==t["buyer"] and e._capital_transport.for_trade(t["id"]).get("stage")=="AWAITING_RECIPIENT")): result["actions"].append({"label":"开始实际设备交接工作","kind":"deliver_capital_asset","payload":{"trade_id":t["id"]}} if firm==t["seller"] or cross_trade(t) else {"label":"取消尚未交接的设备交易","kind":"cancel_capital_trade","payload":{"trade_id":t["id"]}})
	for p: Dictionary in projects.values():
		if p["firm"]==firm and p["kind"] in MOVE_KINDS+["MAINTENANCE"]:
			result["work"].append({"id":p["id"],"asset_id":p["asset_id"],"kind":p["kind"],"site_id":p["site_id"],"status":p["status"],"hours":work_hours(p),"required_hours":terms_for(p)["hours"],"materials":p["materials"].duplicate(true),"reason":p["reason"],"cost":e._costs.project_cost(p["id"]),"completed_minute":p["completed_minute"]})
	result["acquisition_review"]=_npc_reviews.get(firm,{}).duplicate(true)
	result["actions"].append_array(e._capital_transport.actions(actor,firm))
	for action: Dictionary in result["actions"]:
		if not action.has("can_execute"): action["can_execute"]=true
		if action["kind"]=="offer_capital_asset" and not known_capital_counterparty(firm,action["payload"]["buyer"]): action["can_execute"]=false;action["reason"]="CAPITAL_BUYER_NOT_KNOWN_BY_DECLARED_CONTACT"
		action["key"]=action["kind"]+"|"+str(action["payload"].get("offer_id",action["payload"].get("trade_id",action["payload"].get("transport_id",action["payload"].get("asset_id","")))))+"|"+str(action["payload"].get("buyer",""))
		if not action.has("reason"): action["reason"]="EXECUTION_RECHECK_REQUIRED"
	return result

func npc_resale() -> void:
	var e:=_economy()
	if not e.config.get("capital_resale",{}).get("autonomous_policies",[]).is_empty():
		npc_autonomous_resale()
		return
	for policy: Dictionary in e.config.get("capital_resale",{}).get("npc_policies",[]):
		if e.day%int(policy["review_days"])!=0: continue
		var seller: String=policy["firm"];var buyer: String=policy["buyer"]
		if e.firm_manager_at(seller,e.day*1440)==seller and e._firm_winding_down(seller):
			for action: Dictionary in resale_business(seller,seller).get("actions",[]):
				if action["kind"] in ["dismantle_capital","offer_capital_asset","deliver_capital_asset","dispatch_capital_transport"]: e._npc_submit(seller,action["kind"],action["payload"],"capital_resale:"+str(action["payload"]),{"purpose":policy["basis"]});break
		if e.firm_manager_at(buyer,e.day*1440)!=buyer or e._firm_winding_down(buyer): continue
		var fulfilling:=false
		for obligation: Dictionary in resale_business(buyer,buyer).get("actions",[]):
			if obligation["kind"] in ["commission_capital_transport","deliver_capital_asset","reinstall_capital"]:
				e._npc_submit(buyer,obligation["kind"],obligation["payload"],"capital_resale:"+str(obligation["payload"]),{"purpose":policy["basis"]});fulfilling=true;break
		if fulfilling: continue
		var site: String=policy["target_site"];var pressure:=0
		for id: String in e._active_orders:
			if e._orders[id]["seller_site"]==site: pressure+=int(e._orders[id]["pending"])
		if pressure<1 or e._mature_wage_position(buyer,FormalLedgerState.DENOMINATION)["amount"]>0: continue
		for action: Dictionary in resale_business(buyer,buyer).get("actions",[]):
			if action["kind"] not in ["accept_capital_offer","reinstall_capital"]: continue
			if action["kind"]=="accept_capital_offer":
				var o:=resale_offers[action["payload"]["offer_id"]] as Dictionary
				var freight:=0
				if cross_trade(o):
					var routes:=e._capital_transport.routes(o["asset_id"],o["source_site"],o["target_site"],buyer)
					if routes.is_empty(): continue
					for leg: Dictionary in routes[0]["legs"]: freight+=int(leg["fee"])
				if o["price"]>policy["price"] or e._world.ledger_state.available_balance(e._account(buyer,o["denomination"]))<int(o["price"])+freight+int(policy["cash_floor"])+e._due_credit_amount(buyer,o["denomination"]): continue
			e._npc_submit(buyer,action["kind"],action["payload"],"capital_resale:"+str(action["payload"]),{"purpose":policy["basis"],"own_pending_quantity":pressure});break


func known_capital_counterparty(seller: String, buyer: String, minute: int=-1) -> bool:
	if minute<0: minute=_economy()._world.game_clock.total_minutes()
	for p: Dictionary in _economy().config.get("capital_resale",{}).get("contacts",[]):
		if p["seller"]==seller and p["buyer"]==buyer and p["available_minute"]<=minute: return true
	return false


func installed_assets(site: String) -> Array[String]:
	var result: Array[String]=[]
	for id: String in assets:
		if asset_state(id)["installed_site"]==site: result.append(id)
	return result

func live_asset_offer(asset: String, buyer: String="") -> bool:
	var now: int=_economy()._world.game_clock.total_minutes()
	for o: Dictionary in resale_offers.values():
		if o["asset_id"]==asset and (buyer.is_empty() or o["buyer"]==buyer) and not capital_offer_used(o["id"]) and not o["withdrawn"] and o["expires_minute"]>now: return true
	return false


func capital_offer_used(id: String) -> bool:
	for t: Dictionary in resale_trades.values():
		if t["offer_id"]==id: return true
	return false


## Lease gates are checked after their authoritative candidate state is restored.
## Later site closures never invalidate historical work at that site.
func validate_mobility_presence() -> bool:
	var e:=_economy()
	for p: Dictionary in projects.values():
		if p["kind"] not in MOVE_KINDS: continue
		var op: String={"DISMANTLE":"disassemble","HANDOVER":"handover","REINSTALL":"install"}[p["kind"]]
		if p["work_permissions"].size()!=p["work"].size(): return _fail("Mobile capital work lacks its actual execution authority")
		var times: Array[int]=[p["accepted_minute"]]
		if p["material_minute"]>=0:
			if not move_proof_valid(p["material_permission"],p["actor"],p["firm"],op,p["budget"],p["material_minute"]): return _fail("Mobile material use lacks actual authority")
			times.append(p["material_minute"])
		elif not p["material_permission"].is_empty(): return _fail("Unstarted mobile work claims material authority")
		for index: int in p["work"].size():
			var allocation:=p["work"][index] as Dictionary
			var minute: int=int(e._work_records[allocation["id"]]["day"])*1440
			if not move_proof_valid(p["work_permissions"][index],p["actor"],p["firm"],op,p["budget"],minute): return _fail("Mobile work lacks permission for its actual allocation time")
			times.append(maxi(0,minute-1))
		if p["completed_minute"]>=0:
			if not move_proof_valid(p["completion_permission"],p["actor"],p["firm"],op,p["budget"],p["completed_minute"]): return _fail("Mobile capital completion lacks actual delivery authority")
			times.append(p["completed_minute"])
		elif not p["completion_permission"].is_empty(): return _fail("Uncompleted mobile work claims delivery authority")
		for minute: int in times:
			if not e._leases.site_allowed(p["site_id"],minute): return _fail("Mobile capital work lacks actual premises use")
		if p["kind"]=="HANDOVER" and p["completed_minute"]>=0:
			var t:=resale_trades[p["trade_id"]] as Dictionary
			if not e._leases.site_allowed(t["target_site"],p["completed_minute"]): return _fail("Equipment delivered without lawful buyer premises")
	for p: Dictionary in projects.values():
		if p["kind"]!="MAINTENANCE": continue
		if asset_state(p["asset_id"],p["accepted_minute"])["status"] not in ["ACTIVE","PAUSED"]: return _fail("Maintenance started without an installed available asset")
		var times: Array[int]=[p["accepted_minute"]]
		if p["material_minute"]>=0: times.append(p["material_minute"])
		if p["completed_minute"]>=0: times.append(p["completed_minute"])
		for work: Dictionary in p["work"]:
			var fact:=e._work_records[work["id"]] as Dictionary
			if e._spec["jobs"][fact["job"]]["skill"]<1: return _fail("Maintenance work lacks current site qualification")
			times.append(maxi(0,int(fact["day"])*1440-1))
		for minute: int in times:
			if not maintenance_project_valid(p,minute) or not e._leases.site_allowed(p["site_id"],minute): return _fail("Maintenance lost current site, owner or recipe")
		var repair_end: int=p["completed_minute"] if p["completed_minute"]>=0 else FormalLedgerState.MAX_AMOUNT
		for change_id: String in _project_changes.get(p["id"],[]):
			var change:=changes[change_id] as Dictionary
			if change["status"]=="APPLIED" and change["payload"]["status"]=="CANCELLED": repair_end=mini(repair_end,change["effective_minute"])
		for other: Dictionary in projects.values():
			if other["asset_id"]!=p["asset_id"] or other["id"]==p["id"] or other["kind"] not in MOVE_KINDS: continue
			if other["accepted_minute"]<repair_end and (other["completed_minute"]<0 or p["accepted_minute"]<other["completed_minute"]): return _fail("Equipment maintenance overlaps exclusive mobile work")
	return true

func move_execution_permission(p: Dictionary) -> Dictionary:
	var op: String={"DISMANTLE":"disassemble","HANDOVER":"handover","REINSTALL":"install"}[p["kind"]]
	return move_permission(p["actor"],p["firm"],op,p["budget"])


func cross_trade(t: Dictionary) -> bool:
	return _economy()._place(t["source_site"])!=_economy()._place(t["target_site"])

func historical_route(o: Dictionary) -> bool:
	for route: Dictionary in _economy().config.get("capital_transport",{}).get("offers",[]):
		if route["source_site"]==o["source_site"] and route["target_site"]==o["target_site"] and o["buyer"] in route["known_to"] and _economy()._capital_transport.compatible(route,o["asset_id"],o["minute"],false): return true
	return false

func maintenance_template(asset: String, minute: int) -> Dictionary:
	if not assets.has(asset): return {}
	var state:=asset_state(asset,minute)
	var original:=template(assets[asset]["template_id"])
	var mapping: Dictionary=move_rule(asset).get("maintenance_targets",{})
	var recipe:=template(mapping.get(state["site_id"],"")) if mapping.has(state["site_id"]) else original if state["site_id"]==original["site_id"] and state["owner"]==original["firm"] else {}
	return recipe if recipe.get("firm")==state["owner"] and recipe.get("site_id")==state["installed_site"] and recipe.has("maintenance") and state["transport"]=="NONE" else {}

func maintenance_project_valid(p: Dictionary, minute: int) -> bool:
	var recipe:=maintenance_template(p["asset_id"],minute)
	return recipe.get("id")==p["template_id"] and recipe.get("firm")==p["firm"] and recipe.get("site_id")==p["site_id"]


func autonomous_policy(buyer: String, seller: String="") -> Dictionary:
	for p: Dictionary in _economy().config.get("capital_resale",{}).get("autonomous_policies",[]):
		if p["buyer"]==buyer and (seller.is_empty() or p["seller"]==seller): return p
	return {}

func quote_message_id(o: Dictionary) -> String:
	return "message:"+str(o["buyer"])+":capital_offer:"+str(o["id"])

func quote_message_valid(m: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(m,["id","actor","kind","candidate","observed_day","delivery_day"]) or m.get("kind")!="capital_offer" or not resale_offers.has(m.get("candidate")): return false
	var o: Dictionary=resale_offers[m["candidate"]];var p:=autonomous_policy(o["buyer"],o["seller"])
	return not p.is_empty() and m["id"]==quote_message_id(o) and m["actor"]==o["buyer"] and m["observed_day"]==int(o["minute"])/1440 and m["delivery_day"]==int(o["minute"])/1440+int(p["message_delay_days"]) and known_capital_counterparty(o["seller"],o["buyer"],o["minute"])

func adopt_quote(m: Dictionary) -> void:
	if not _known_quotes.has(m["actor"]): _known_quotes[m["actor"]]={}
	_known_quotes[m["actor"]][m["candidate"]]=m["delivery_day"]
	# Bounded current inbox; original messages remain in the R1 history.
	while _known_quotes[m["actor"]].size()>32: _known_quotes[m["actor"]].erase(_known_quotes[m["actor"]].keys()[0])

func known_offer(o: Dictionary, minute: int) -> bool:
	if autonomous_policy(o["buyer"],o["seller"]).is_empty(): return true
	var receipt: Dictionary=_economy()._receipts.get(quote_message_id(o),{})
	return quote_message_valid(receipt) and int(receipt["delivery_day"])*1440<=minute

# This counterfactual uses the production allocator before actual stock is consumed.
# It never adopts capacity, makes goods, books labor or predicts other firms' plans.
func observe_acquisition(site: String, hours: int) -> void:
	var e:=_economy();var p:=autonomous_policy(e._owner(site))
	if p.is_empty() or p["site_id"]!=site: return
	_npc_observations[p["buyer"]]={}
	for id: String in _known_quotes.get(p["buyer"],{}):
		var o: Dictionary=resale_offers[id]
		var directed:=autonomous_policy(p["buyer"],o["seller"])
		if directed.is_empty(): continue
		if o["target_site"]!=site or o.get("equipment",{}).get("asset_type")!=p["asset_type"] or capital_offer_used(id) or o["withdrawn"] or e._world.game_clock.total_minutes()>=o["expires_minute"]: continue
		var base: Dictionary=e._allocate_production(site,hours,e._production_minute(),{"capacity":0,"activities":[]})
		var expanded: Dictionary=e._allocate_production(site,hours,e._production_minute(),o["equipment"])
		var qualified:=0;var rule:=move_rule(o["asset_id"])
		var skill: int=maxi(int(rule["handover"]["skill"]),int(rule["reinstall"]["skill"]))
		for work_id: String in e._capital_work_ids:
			var work: Dictionary=e._work_records[work_id];var job: Dictionary=e._spec["jobs"][work["job"]]
			if job["site_id"]==site and int(job["skill"])>=skill and job.get("denomination",FormalLedgerState.DENOMINATION)==o["denomination"]: qualified+=maxi(0,int(work["hours"])-e._costs.assigned_hours(work_id))
		_npc_observations[p["buyer"]][id]={"day":e.day,"available_hours":hours,"qualified_installation_hours":qualified,"baseline":base,"expanded":expanded}

func npc_material_price(site: String, good: String, currency: String) -> int:
	var e:=_economy()
	if e._spec["sites"][site]["prices"].has(good) and e._sale_currency(site)==currency: return e._price(site,good)
	for o: Dictionary in e._input_offers(site,good,e.day+30):
		if o["denomination"]==currency: return int(o["price"])+int(o["freight_per_unit"])
	return -1

## Contract-cost projection only. It neither applies an NPC return threshold nor
## promises future labor, materials or resource adoption to the player.
func acquisition_estimate(o: Dictionary) -> Dictionary:
	var e:=_economy();var rule:=move_rule(o["asset_id"]);var site: String=o["target_site"]
	var result:={"known":false,"price":o["price"],"freight":null,"handling":null,"installation":null,"total":null,"unknown":[],"materials":{},"hours":0,"materials_available":true,"site_allowed":e._site_operating(site),"basis":"KNOWN_CONTRACTS_REGISTERED_WAGES_AND_KNOWN_MATERIAL_PRICES_ESTIMATE"}
	var carriage:=known_carriage_estimate(o)
	if carriage["known"]:
		result["freight"]=carriage["freight"];result["handling"]=carriage["handling"];result["carriage_offer"]=carriage["offer_id"]
	else: result["unknown"].append(carriage["reason"])
	var paid_work: Array[String]=["reinstall"]
	if cross_trade(o): paid_work.push_front("handover")
	for kind: String in paid_work:
		result["hours"]+=int(rule[kind]["hours"])
		for good: String in rule[kind]["materials"]: result["materials"][good]=int(result["materials"].get(good,0))+int(rule[kind]["materials"][good])
	var rate: int=e._labor_market.estimate_rate(site,o["denomination"])
	var installation: int=maxi(0,rate)*int(result["hours"])
	var work_cost_known: bool=rate>=0
	if rate<0: result["unknown"].append("NO_KNOWN_TARGET_LABOR_RATE")
	for good: String in result["materials"]:
		var price:=npc_material_price(site,good,o["denomination"])
		if price<0: result["unknown"].append("UNKNOWN_INSTALLATION_MATERIAL_PRICE:"+good);work_cost_known=false
		else: installation+=price*int(result["materials"][good])
		if e.capital_free_goods(site,good)<int(result["materials"][good]): result["materials_available"]=false
	if work_cost_known: result["installation"]=installation
	result["known"]=result["unknown"].is_empty()
	if result["known"]: result["total"]=int(o["price"])+int(result["freight"])+int(result["handling"])+installation
	return result

func acquisition_review(p: Dictionary, o: Dictionary) -> Dictionary:
	var e:=_economy();var site: String=p["site_id"];var buyer: String=p["buyer"];var now: int=e._world.game_clock.total_minutes()
	var result:={"day":e.day,"offer_id":o["id"],"reason":"NO_CURRENT_CAPACITY_OBSERVATION","purchase":false,"basis":p["basis"]}
	if competition_enabled():
		for id: String in _active:
			if projects[id]["firm"]==buyer:
				result["reason"]="OWN_CAPITAL_WORK_AWAITS_COMPLETION";return result
		for t: Dictionary in resale_trades.values():
			if t["buyer"]==buyer and (t["state"]=="ACCEPTED" or received_installation_pending(t["asset_id"],buyer)):
				result["reason"]="OWN_ACCEPTED_CAPITAL_OBLIGATION_AWAITS_FULFILMENT";return result
	if o["denomination"]!=e._sale_currency(site): result["reason"]="NO_COMMON_DENOMINATION_FOR_OPERATING_CONTRIBUTION";return result
	var evidence: Dictionary=_npc_observations.get(buyer,{}).get(o["id"],{})
	if evidence.get("day")!=e.day: return result
	result["production"]=evidence.duplicate(true)
	var extra:=int(evidence["expanded"]["batches"].get(p["activity_id"],0))-int(evidence["baseline"]["batches"].get(p["activity_id"],0))
	result["extra_batches"]=extra
	if extra<int(p["minimum_extra_batches"]): result["reason"]="MATERIAL_LABOR_OR_DEMAND_BINDS_BEFORE_ADDITIONAL_EQUIPMENT";return result
	var days: Dictionary={}
	var related: Dictionary=e._activity(site,p["activity_id"])["outputs"].duplicate()
	# Follow only this site's own recipe dependencies, never other firms' plans.
	for pass_index: int in e._spec["sites"][site]["activities"].size():
		var changed:=false
		for activity: Dictionary in e._spec["sites"][site]["activities"]:
			var downstream:=false
			for good: String in related:
				if int(activity["materials"].get(good,0))>0: downstream=true
			if downstream:
				for good: String in activity["outputs"]:
					if not related.has(good): related[good]=true;changed=true
		if not changed: break
	# Only original funded sales of the affected products count as observations.
	for good: String in e._spec["sites"][site]["prices"]:
		if not related.has(good): continue
		for date: int in range(maxi(0,e.day-int(p["observation_days"])+1),e.day+1):
			if int(e._order_days.get(site+"|"+good,{}).get(date,0))>0: days[date]=true
	result["observed_sales_days"]=days.keys()
	if days.size()<int(p["observation_days"]): result["reason"]="INSUFFICIENT_SUSTAINED_OWN_FUNDED_DEMAND";return result
	var rule:=move_rule(o["asset_id"])
	if o["seller"]!=p["seller"] or o["target_site"]!=site or o.get("equipment",{}).get("asset_type")!=p["asset_type"] or p["activity_id"] not in o.get("equipment",{}).get("activities",[]) or not known_offer(o,now): result["reason"]="NO_RECEIVED_COMPATIBLE_QUOTATION";return result
	if not e._site_operating(site) or not e._leases.site_allowed(site) or not move_permission(buyer,buyer,"install",rule["reinstall"]["budget"])["ok"]: result["reason"]="INSTALLATION_PREMISES_OR_AUTHORITY_UNAVAILABLE";return result
	var carriage:=known_carriage_estimate(o)
	if not carriage["known"]: result["reason"]=carriage["reason"];return result
	var freight: int=carriage["freight"]
	var handling_estimate: int=carriage["handling"]
	var rate: int=e._labor_market.estimate_rate(site,o["denomination"])
	if rate<0 or evidence["qualified_installation_hours"]<maxi(int(rule["reinstall"]["hours_per_day"]),int(rule["handover"]["hours_per_day"])): result["reason"]="NO_CURRENT_INSTALLATION_WORKFORCE";return result
	var install:=0;var materials: Dictionary={}
	var paid_work: Array[String]=["reinstall"]
	if cross_trade(o): paid_work.push_front("handover")
	for kind: String in paid_work:
		install+=rate*int(rule[kind]["hours"])
		for good: String in rule[kind]["materials"]: materials[good]=int(materials.get(good,0))+int(rule[kind]["materials"][good])
	for good: String in materials:
		var price:=npc_material_price(site,good,o["denomination"])
		if e.capital_free_goods(site,good)<materials[good] or price<0: result["reason"]="INSTALLATION_MATERIAL_OR_KNOWN_COST_UNAVAILABLE:"+good;return result
		install+=price*int(materials[good])
	var gain:=0;var sales_pressure: Dictionary={}
	for good: String in e._goods:
		var delta:=int(evidence["expanded"]["stock"][good])-int(evidence["baseline"]["stock"][good])
		if delta==0: continue
		if delta>0:
			if related.has(good) and e._spec["sites"][site]["prices"].has(good):
				# Configured stock targets and cash/price-refused enquiries alone
				# cannot justify buying capacity to accumulate unsold output.
				var pressure: int=maxi(0,e._received_pressure(site,good)+e._committed(site,good)+e._observed_daily_orders(site,good)-int(evidence["baseline"]["stock"][good]))
				var sellable:=mini(delta,pressure)
				sales_pressure[good]=sellable
				gain+=sellable*e._price(site,good)
		else:
			var price:=npc_material_price(site,good,o["denomination"])
			if price<0: result["reason"]="UNKNOWN_INCREMENTAL_INPUT_COST:"+good;return result
			gain+=delta*price
	gain-=maxi(0,int(evidence["expanded"]["labor_used"])-int(evidence["baseline"]["labor_used"]))*rate
	var total:=int(o["price"])+freight+install+handling_estimate
	var ready_minutes: int=carriage["minutes"]
	for kind: String in ["handover","reinstall"]:
		ready_minutes+=1440+maxi(int(rule[kind]["duration_minutes"]),(int(rule[kind]["hours"])+int(rule[kind]["hours_per_day"])-1)/int(rule[kind]["hours_per_day"])*1440)
	var lead_days: int=(ready_minutes+1439)/1440
	var productive_days: int=maxi(0,int(p["max_payback_days"])-lead_days)

	var cash: int=e._world.ledger_state.available_balance(e._account(buyer,o["denomination"]))
	var wages: int=e._mature_wage_position(buyer,o["denomination"])["amount"]
	# Protect every already accrued unpaid wage, not only today's mature claims.
	var accrued:=0
	for id: String in e._open_wages:
		var w: Dictionary=e._wages[id]
		if w["employer"]==buyer and w["denomination"]==o["denomination"]: accrued+=int(w["remaining"])
	var debt:=0
	for loan: Dictionary in e._credit.visible(buyer,[],now,true)["loans"]:
		if loan["borrower"]==buyer and loan["denomination"]==o["denomination"]: debt+=int(loan["remaining"])
	var capital_work:=0
	if competition_enabled():
		for id: String in _active:
			var project: Dictionary=projects[id]
			if project["firm"]==buyer: capital_work+=maxi(0,int(project["budget"])-committed_cost(project))
	var rent:=0
	for claim: Dictionary in e._wind_down.obligations(buyer):
		if claim["kind"]=="RENT" and claim["currency"]==o["denomination"]: rent+=int(claim["remaining"])
	result.merge({"denomination":o["denomination"],"activity_id":p["activity_id"],"evaluation_days":p["max_payback_days"],"ready_minutes_estimate":ready_minutes,"productive_days_estimate":productive_days,"net_window_contribution_estimate":gain*productive_days-total,"carriage_offer":carriage["offer_id"],"price":o["price"],"freight_estimate":freight,"installation_estimate":install,"buyer_handling_estimate":handling_estimate,"total_estimate":total,"incremental_daily_margin_estimate":gain,"extra_output_with_observed_pressure":sales_pressure,"available_cash":cash,"accrued_wages":accrued,"outstanding_credit":debt,"unpaid_rent":rent,"other_capital_work_protection":capital_work,"cash_floor":p["cash_floor"],"estimate_basis":"OWN_CURRENT_PLAN_STOCK_WORK_KNOWN_PRICES_NOT_GUARANTEED_FUTURE_RETURN"})
	if wages>0 or o["price"]>p["max_price"] or cash<total+accrued+debt+rent+capital_work+int(p["cash_floor"]): result["reason"]="CASH_PRICE_OR_EXISTING_LIABILITY_LIMIT_NO_AUTOMATIC_LOAN";return result
	if gain<=0 or total>gain*(productive_days if competition_enabled() else int(p["max_payback_days"])): result["reason"]="OBSERVED_INCREMENTAL_MARGIN_DOES_NOT_JUSTIFY_ACQUISITION";return result
	for category: String in ["capital_asset","capital_freight"]:
		if category=="capital_freight" and not cross_trade(o): continue
		var amount: int=o["price"] if category=="capital_asset" else freight
		var budget: Dictionary=e._budgets.plan(buyer,o["denomination"],category,amount,now)
		if not budget.get("ok",false) or (category=="capital_freight" and cross_trade(o) and not budget.has("rule_id")): result["reason"]="SEPARATE_PURCHASE_OR_FREIGHT_BUDGET_UNAVAILABLE";return result
		var proof:=move_permission(buyer,buyer,"acquire" if category=="capital_asset" else "freight",amount)
		if not proof["ok"] or not move_permission(buyer,buyer,"pay",amount)["ok"]: result["reason"]="SEPARATE_PURCHASE_PAYMENT_OR_FREIGHT_AUTHORITY_UNAVAILABLE";return result
		if budget.has("rule_id") and budget["root_authority"] not in [proof["source"]["id"],proof.get("root_proof",{}).get("authority_id","")]: result["reason"]="ORIGINAL_BUDGET_AUTHORITY_UNAVAILABLE";return result
	result["purchase"]=true;result["reason"]="OBSERVED_CAPACITY_BOTTLENECK_AFFORDABLE_KNOWN_EQUIPMENT"
	return result

func npc_autonomous_resale() -> void:
	if competition_enabled():
		npc_competitive_resale()
		return
	var e:=_economy();var now: int=e._world.game_clock.total_minutes()
	for p: Dictionary in e.config["capital_resale"]["autonomous_policies"]:
		var seller: String=p["seller"];var buyer: String=p["buyer"]
		# An already accepted obligation is serviced independently of new investment.
		for firm: String in [seller,buyer]:
			if e.firm_manager_at(firm,now)!=firm: continue
			for a: Dictionary in resale_business(firm,firm).get("actions",[]):
				if a["kind"] not in ["dispatch_capital_transport","commission_capital_transport","deliver_capital_asset","reinstall_capital"]: continue
				if a["kind"]=="reinstall_capital":
					if not received_installation_pending(a["payload"]["asset_id"],firm): continue
				e._npc_submit(firm,a["kind"],a["payload"],"capital_fulfil",{"purpose":"ORIGINAL_ACCEPTED_CAPITAL_OBLIGATION"});break
		if e.day%int(p["review_days"])!=0: continue
		if e.firm_manager_at(seller,now)==seller:
			for a: Dictionary in resale_business(seller,seller).get("actions",[]):
				if a["kind"] not in ["dismantle_capital","offer_capital_asset"]: continue
				var asset: Dictionary=assets[a["payload"]["asset_id"]]
				if asset["asset_type"]!=p["asset_type"]: continue
				if a["kind"]=="dismantle_capital" and not npc_surplus_equipment(asset,int(p["seller_idle_days"])): continue
				e._npc_submit(seller,a["kind"],a["payload"],"capital_disposal",{"purpose":"OWN_INSTALLED_SURPLUS_CAPACITY_NO_PENDING_SALES","idle_days":p["seller_idle_days"]});break
		if e.firm_manager_at(buyer,now)!=buyer or e._firm_winding_down(buyer): continue
		for id: String in _known_quotes.get(buyer,{}):
			var o: Dictionary=resale_offers[id]
			if capital_offer_used(id) or o["withdrawn"] or now>=o["expires_minute"]: continue
			var review:=acquisition_review(p,o);_npc_reviews[buyer]=review
			if review["purchase"]:
				var accepted: Dictionary=e._npc_submit(buyer,"accept_capital_offer",{"offer_id":id},"capital_acquisition",review)
				_npc_reviews[buyer]["execution_result"]=accepted.get("reason","")
				break
		# One actual maintenance responsibility after a configured service interval.
		for t: Dictionary in resale_trades.values():
			if t["buyer"]!=buyer or t["state"]!="DELIVERED": continue
			var state:=asset_state(t["asset_id"])
			if state["owner"]!=buyer or state["status"]!="ACTIVE" or state["installed_site"]!=p["site_id"] or move_busy(t["asset_id"]): continue
			var last: int=t["delivered_minute"];var maintained:=false
			for project: Dictionary in projects.values():
				if project["asset_id"]==t["asset_id"] and project["kind"]=="REINSTALL": last=maxi(last,int(project["completed_minute"]))
				if project["asset_id"]==t["asset_id"] and project["firm"]==buyer and project["kind"]=="MAINTENANCE" and project["accepted_minute"]>=t["delivered_minute"]: maintained=true
			if maintained or now-last<int(p["maintenance_days"])*1440: continue
			var terms:=maintenance_template(t["asset_id"],now)
			if terms.is_empty(): continue
			e._npc_submit(buyer,"maintain_capital",{"asset_id":t["asset_id"],"budget":terms["budget"]},"capital_maintenance:"+t["asset_id"],{"purpose":"OWN_RECEIVED_EQUIPMENT_SERVICE_INTERVAL"})

func npc_surplus_equipment(asset: Dictionary, days: int) -> bool:
	var e:=_economy();var state:=asset_state(asset["id"]);var site: String=state["installed_site"]
	if site.is_empty() or e.day-installation_minute(asset["id"])/1440<days or not e._costs.enabled: return false
	var pending:=false
	for id: String in e._active_orders:
		if e._orders[id]["seller_site"]==site and int(e._orders[id]["pending"])+int(e._orders[id]["transit"])>0: pending=true
	if pending:
		if not competition_enabled(): return false
		var intended:=0
		for activity: Dictionary in e._spec["sites"][site]["activities"]: intended+=int(e._plans.get(site,{}).get("activities",{}).get(activity["id"],{}).get("desired",0))*int(activity["capacity_units"])
		if intended>int(e._spec["sites"][site]["capacity"])*int(e._operations_policy(site)["planning_horizon"]): return false
	for date: int in range(e.day-days+1,e.day+1):
		var used:=0
		for a: Dictionary in e._spec["sites"][site]["activities"]:
			used+=int(e._costs.productions.get("production:"+str(date)+":"+site+":"+str(a["id"]),{}).get("batches",0))*int(a["capacity_units"])
		if used>int(e._spec["sites"][site]["capacity"]): return false
	return true


# Derived from the original formation and completed projects. A later dismantle
# does not revive a fulfilled installation obligation from an earlier purchase.
func installation_minute(asset: String, minute: int=-1) -> int:
	if minute<0: minute=_economy()._world.game_clock.total_minutes()
	var last: int=assets[asset]["in_service_minute"]
	for p: Dictionary in projects.values():
		if p["asset_id"]==asset and p["kind"]=="REINSTALL" and p["completed_minute"]>=0 and p["completed_minute"]<=minute: last=maxi(last,int(p["completed_minute"]))
	return last

func received_installation_pending(asset: String, firm: String) -> bool:
	if asset_state(asset)["owner"]!=firm: return false
	var received: Dictionary={}
	for t: Dictionary in resale_trades.values():
		if t["asset_id"]==asset and t["buyer"]==firm and t["state"]=="DELIVERED" and (received.is_empty() or t["delivered_minute"]>received["delivered_minute"]): received=t
	if received.is_empty(): return false
	for p: Dictionary in projects.values():
		if p["asset_id"]==asset and p["kind"]=="REINSTALL" and p["firm"]==firm and p["site_id"]==received["target_site"] and p["completed_minute"]>=received["delivered_minute"]: return false
	return true

func competition_enabled() -> bool:
	return _economy().config.get("capital_resale",{}).has("competition")

func exclusive_trade(asset: String) -> Dictionary:
	for t: Dictionary in resale_trades.values():
		if t["asset_id"]==asset and t["state"]=="ACCEPTED": return t
	return {}

func offer_availability(o: Dictionary, minute: int) -> String:
	if o["withdrawn"]: return "QUOTATION_WITHDRAWN"
	if minute>=int(o["expires_minute"]): return "QUOTATION_EXPIRED"
	if not known_offer(o,minute): return "QUOTATION_NOT_RECEIVED"
	if not exclusive_trade(o["asset_id"]).is_empty(): return "ASSET_EXCLUSIVE_TRADE_ALREADY_ACCEPTED"
	var state:=asset_state(o["asset_id"],minute)
	if state["owner"]!=o["seller"]: return "ASSET_NO_LONGER_OWNED_BY_QUOTING_SELLER"
	if capital_offer_used(o["id"]): return "QUOTATION_ALREADY_USED"
	if move_busy(o["asset_id"]) or state["status"]!="DETACHED": return "ASSET_NOT_RELEASED_FOR_SALE"
	return "AVAILABLE"

# Known carrier terms and registered facility windows only. Resource adoption is
# still deferred to SharedTransport; this estimate never guarantees availability.
func known_carriage_estimate(o: Dictionary) -> Dictionary:
	if not cross_trade(o): return {"known":true,"offer_id":"","freight":0,"handling":0,"minutes":0}
	var e:=_economy();var now: int=e._world.game_clock.total_minutes();var choices: Array[Dictionary]=[]
	for route: Dictionary in e._capital_transport.routes(o["asset_id"],o["source_site"],o["target_site"],o["buyer"]):
		if route["denomination"]!=o["denomination"]: continue
		var fee:=0;var handling_cost:=0;var ready:=now;var known:=true
		for leg: Dictionary in route["legs"]:
			var b: Dictionary=e._shared.bindings[leg["edge_id"]]
			var origin: String=b["handling_site"]
			var destination: String=e._shared.facilities[b["node_resources"]["destination_handling"]]["site_id"]
			var load_rate: int=e._labor_market.estimate_rate(origin,o["denomination"])
			var unload_rate: int=e._labor_market.estimate_rate(destination,o["denomination"])
			if load_rate<0 or unload_rate<0: known=false;break
			var units: int=e._capital_transport.handling_units(o["asset_id"])
			fee+=int(leg["fee"])
			if e._owner(origin)==o["buyer"]: handling_cost+=units*int(b["handling_hours_per_unit"])*load_rate
			if e._owner(destination)==o["buyer"]: handling_cost+=units*int(b["node_resources"]["unloading_hours_per_unit"])*unload_rate
			var departure: int=-1
			for minute: int in b["entry_minutes"]:
				if minute+int(b["window_minutes"])>ready: departure=maxi(ready,minute);break
			if departure<0: known=false;break
			ready=departure+int(b["loading_minutes"])+int(b["travel_minutes"])
			var unloaded: int=-1
			for w: Dictionary in e._shared.facilities[b["node_resources"]["destination_handling"]]["windows"]:
				var start: int=maxi(ready,int(w["start_minute"]))
				if start+int(b["node_resources"]["unloading_minutes"])<=int(w["end_minute"]): unloaded=start+int(b["node_resources"]["unloading_minutes"]);break
			if unloaded<0: known=false;break
			ready=unloaded
		if known: choices.append({"known":true,"offer_id":route["id"],"freight":fee,"handling":handling_cost,"minutes":ready-now})
	if choices.is_empty(): return {"known":false,"reason":"NO_KNOWN_LEGAL_CARRIAGE_WITH_COMPARABLE_COST_AND_HANDLING"}
	choices.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if int(a["freight"])+int(a["handling"])!=int(b["freight"])+int(b["handling"]): return int(a["freight"])+int(a["handling"])<int(b["freight"])+int(b["handling"])
		if a["minutes"]!=b["minutes"]: return a["minutes"]<b["minutes"]
		return a["offer_id"]<b["offer_id"])
	return choices[0]

func npc_competitive_resale() -> void:
	var e:=_economy();var now: int=e._world.game_clock.total_minutes()
	var policies: Array[Dictionary]=[];policies.assign(e.config["capital_resale"]["autonomous_policies"])
	policies.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["buyer"]<b["buyer"] if a["buyer"]!=b["buyer"] else a["seller"]<b["seller"])
	var firms: Array[String]=[];var buyers: Array[String]=[]
	for p: Dictionary in policies:
		for firm: String in [p["seller"],p["buyer"]]:
			if firm not in firms: firms.append(firm)
		if p["buyer"] not in buyers: buyers.append(p["buyer"])
	firms.sort();buyers.sort()
	# Contracts already undertaken retain their original legal execution paths.
	for firm: String in firms:
		if e.firm_manager_at(firm,now)!=firm: continue
		for a: Dictionary in resale_business(firm,firm).get("actions",[]):
			if a["kind"] not in ["dispatch_capital_transport","commission_capital_transport","deliver_capital_asset","reinstall_capital"]: continue
			if a["kind"]=="commission_capital_transport":
				var t: Dictionary=resale_trades[a["payload"]["trade_id"]]
				var decision: Dictionary=e._commands[t["action_id"]]["result"].get("decision",{})
				if decision.has("carriage_offer") and decision["carriage_offer"]!=a["payload"]["offer_id"]: continue
			if a["kind"]=="reinstall_capital":
				if not received_installation_pending(a["payload"]["asset_id"],firm): continue
			e._npc_submit(firm,a["kind"],a["payload"],"capital_fulfil",{"purpose":"ORIGINAL_ACCEPTED_CAPITAL_OBLIGATION"});break
	var dismantled: Dictionary={}
	for p: Dictionary in policies:
		var seller: String=p["seller"]
		var sale_policy: Dictionary={}
		for row: Dictionary in e.config["capital_resale"]["npc_policies"]:
			if row["firm"]==seller and row["buyer"]==p["buyer"]: sale_policy=row;break
		if sale_policy.is_empty() or e.day%int(sale_policy["review_days"])!=0 or e.firm_manager_at(seller,now)!=seller: continue
		for a: Dictionary in resale_business(seller,seller).get("actions",[]):
			if a["kind"] not in ["dismantle_capital","offer_capital_asset"]: continue
			var asset: Dictionary=assets[a["payload"]["asset_id"]]
			if asset["asset_type"]!=p["asset_type"]: continue
			if a["kind"]=="dismantle_capital":
				if dismantled.has(seller) or not npc_surplus_equipment(asset,int(p["seller_idle_days"])): continue
				e._npc_submit(seller,a["kind"],a["payload"],"capital_disposal",{"purpose":"OWN_INSTALLED_SURPLUS_CAPACITY","idle_days":p["seller_idle_days"]});dismantled[seller]=true
			elif a["payload"]["buyer"]==p["buyer"]:
				e._npc_submit(seller,a["kind"],a["payload"],"capital_quote:"+str(asset["id"]).trim_prefix("capital_asset:")+":"+p["buyer"],{"purpose":"DECLARED_BILATERAL_CAPITAL_QUOTATION","recipient":p["buyer"]})
	# Every buyer forms its own intention against the same pre-acceptance facts.
	# The explicitly configured buyer-ID order only serializes original actions.
	var intentions: Dictionary={}
	for buyer: String in buyers:
		var p:=autonomous_policy(buyer)
		if e.day%int(p["review_days"])!=0 or e.firm_manager_at(buyer,now)!=buyer or e._firm_winding_down(buyer): continue
		var reviews: Array[Dictionary]=[];var ranked: Array[Dictionary]=[]
		for id: String in _known_quotes.get(buyer,{}):
			var o: Dictionary=resale_offers[id];var directed:=autonomous_policy(buyer,o["seller"])
			if directed.is_empty(): continue
			var availability:=offer_availability(o,now)
			var review: Dictionary={"day":e.day,"offer_id":id,"purchase":false,"reason":availability}
			if availability=="AVAILABLE": review=acquisition_review(directed,o)
			if review["purchase"]: ranked.append(review)
			reviews.append(review)
		reviews.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["offer_id"]<b["offer_id"])
		ranked.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			if a["net_window_contribution_estimate"]!=b["net_window_contribution_estimate"]: return a["net_window_contribution_estimate"]>b["net_window_contribution_estimate"]
			if a["total_estimate"]!=b["total_estimate"]: return a["total_estimate"]<b["total_estimate"]
			if a["ready_minutes_estimate"]!=b["ready_minutes_estimate"]: return a["ready_minutes_estimate"]<b["ready_minutes_estimate"]
			return a["offer_id"]<b["offer_id"])
		_npc_reviews[buyer]={"day":e.day,"purchase":not ranked.is_empty(),"reason":"NO_EXECUTABLE_KNOWN_CAPITAL_QUOTATION","alternatives":reviews,"ranking":"OBSERVED_WINDOW_CONTRIBUTION_LESS_COMPLETE_ACQUISITION"}
		if ranked.is_empty():
			if reviews.size()==1: _npc_reviews[buyer]["reason"]=reviews[0]["reason"]
			continue
		var selected: Dictionary=ranked[0].duplicate(true)
		selected["alternatives"]=reviews.duplicate(true);selected["acceptance_order"]="BUYER_ID_ASCENDING"
		intentions[buyer]=selected
	for buyer: String in buyers:
		if not intentions.has(buyer): continue
		var decision: Dictionary=intentions[buyer]
		var result: Dictionary=e._npc_submit(buyer,"accept_capital_offer",{"offer_id":decision["offer_id"]},"capital_acquisition",decision)
		_npc_reviews[buyer]=decision.duplicate(true)
		_npc_reviews[buyer]["execution_result"]=result.get("reason","")
	# Maintenance stays with the actual current owner and installed recipe.
	for buyer: String in buyers:
		var p:=autonomous_policy(buyer)
		if e.day%int(p["review_days"])!=0 or e.firm_manager_at(buyer,now)!=buyer or e._firm_winding_down(buyer): continue
		for t: Dictionary in resale_trades.values():
			if t["buyer"]!=buyer or t["state"]!="DELIVERED": continue
			var state:=asset_state(t["asset_id"])
			if state["owner"]!=buyer or state["status"]!="ACTIVE" or state["installed_site"]!=p["site_id"] or move_busy(t["asset_id"]): continue
			var last: int=t["delivered_minute"];var maintained:=false
			for project: Dictionary in projects.values():
				if project["asset_id"]!=t["asset_id"]: continue
				if project["kind"]=="REINSTALL": last=maxi(last,int(project["completed_minute"]))
				if project["firm"]==buyer and project["kind"]=="MAINTENANCE" and project["accepted_minute"]>=t["delivered_minute"]: maintained=true
			if maintained or now-last<int(p["maintenance_days"])*1440: continue
			var terms:=maintenance_template(t["asset_id"],now)
			if not terms.is_empty(): e._npc_submit(buyer,"maintain_capital",{"asset_id":t["asset_id"],"budget":terms["budget"]},"capital_maintenance:"+t["asset_id"],{"purpose":"OWN_RECEIVED_EQUIPMENT_SERVICE_INTERVAL"})
