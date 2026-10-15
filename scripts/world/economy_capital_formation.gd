class_name EconomyCapitalFormation
extends RefCounted
## Projects, equipment and built space assets only. Goods, wages, money and time belong
## to the injected formal world. A capacity pool is shared by its activities.
const FORMAT := "economy_capital_formation_v1"
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
		if key=="asset_id" and e._service_market.asset_busy(str(payload[key])): return _reject("EXTERNAL_MAINTENANCE_CONTRACT_REMAINS")
		if row.is_empty() or not e._manager(actor, row["firm"]): return _reject("NOT_CAPITAL_MANAGER")
		if kind == "investment_status" and (row["status"] in TERMINAL or payload["status"] not in ["ACTIVE", "PAUSED", "CANCELLED"]): return _reject("PROJECT_CANNOT_CHANGE_STATUS")
		if kind == "capital_status" and (row["status"] in ["MAINTENANCE", "RETIRED"] or payload["status"] not in ["ACTIVE", "PAUSED", "RETIRED"]): return _reject("EQUIPMENT_CANNOT_CHANGE_STATUS")
		var construction_control:Dictionary={}
		if kind=="investment_status" and row["kind"] in BUILD_KINDS and payload["status"]=="ACTIVE":
			construction_control=construction_permission(actor,template(row["template_id"]),row["budget"],now)
			if not construction_control["ok"]:return _reject(construction_control["reason"])
		if kind == "capital_status" and payload["status"] == row["status"]: return _reject("EQUIPMENT_ALREADY_IN_REQUESTED_STATE")
		if payload["status"] == "ACTIVE" and (e.site_closed(row["site_id"]) or e.firm_finished(row["firm"])): return _reject("CAPITAL_SITE_CLOSED")
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
	var terms := template(str(original.get("template_id", "")) if maintenance else str(payload.get("template_id", "")))
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
		if p["kind"] in BUILD_KINDS and not construction_interval_valid(p,e._production_minute()):
			p["reason"]="CONSTRUCTION_PERMISSION_OR_OPERATOR_NOT_VALID_FOR_INTERVAL"
			continue
		if not e._site_operating(site,e._production_minute()):
			p["reason"] = "SITE_NOT_OPERATING"
			continue
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
			var rate:=_work_rate(work_id,e._wages)
			if rate<0: p["reason"]="MISSING_ACTUAL_WAGE_SOURCE";continue
			var hours := mini(left, int(work["hours"])-int(used_work.get(work_id, 0)))
			if rate > 0: hours = mini(hours, maxi(0, int(p["budget"])-committed_cost(p))/rate)
			if hours <= 0: continue
			p["work"].append({"id": work_id, "hours": hours})
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
		if not e._manager(change["actor"], row["firm"]) or (key == "project_id" and row["status"] in TERMINAL) or (key == "asset_id" and row["status"] in ["MAINTENANCE", "RETIRED"]):
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
		var terms := terms_for(p)
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
	_pool_cache.erase(asset["site_id"])
	asset["status"] = status
	asset["events"].append({"minute": minute, "status": status, "source": source})

func begin_external_maintenance(c: Dictionary) -> bool:
	var e:=_economy()
	var a:=assets.get(c.get("asset_id",""),{}) as Dictionary
	var now:=e._world.game_clock.total_minutes()
	if a.is_empty() or e._service_market.contracts.get(c.get("id"))!=c or a["firm"]!=c["client"] or a["status"] not in ["ACTIVE","PAUSED"] or not e._site_operating(a["site_id"]) or now%1440!=0 or not template(a["template_id"]).has("maintenance"): return false
	for id: String in _active:
		if projects[id]["asset_id"]==a["id"]: return false
	_asset_event(a,"MAINTENANCE",now,c["action_id"])
	return true

func complete_external_maintenance(c: Dictionary) -> bool:
	var e:=_economy()
	var a:=assets.get(c.get("asset_id",""),{}) as Dictionary
	var now:=e._world.game_clock.total_minutes()
	if a.is_empty() or e._service_market.contracts.get(c.get("id"))!=c or a["status"]!="MAINTENANCE" or not e._site_operating(a["site_id"],maxi(0,now-1)) or now%1440!=0: return false
	var t:=template(a["template_id"])["maintenance"] as Dictionary
	if c["material_sources"].is_empty() or c["started_minute"]<0 or now-int(c["started_minute"])<int(t["duration_minutes"]) or e._service_market.work_hours(c,"REPAIR")!=t["hours"]: return false
	_asset_event(a,"ACTIVE",now,c["action_id"])
	return true

func pools(site: String, minute: int) -> Array[Dictionary]:
	var base := int(_economy()._spec["sites"][site]["capacity"])
	var cached := _pool_cache.get(site, {}) as Dictionary
	if cached.get("minute") == minute and cached.get("base") == base: return (cached["pools"] as Array[Dictionary]).duplicate(true)
	var result: Array[Dictionary] = []
	for id: String in _site_assets.get(site, []):
		var asset := assets[id] as Dictionary
		var state := ""
		for index: int in range(asset["events"].size()-1, -1, -1):
			var event := asset["events"][index] as Dictionary
			if int(event["minute"]) <= minute:
				state = event["status"]
				break
		if state == "ACTIVE" and template(asset["template_id"])["kind"] not in BUILD_KINDS: result.append({"id": id, "capacity": asset["capacity"], "activities": asset["activities"].duplicate()})
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
	for id: String in _site_assets.get(site, []):
		var asset := assets[id] as Dictionary
		if template(asset["template_id"])["kind"] in BUILD_KINDS:continue
		var start := -1
		for event: Dictionary in asset["events"]:
			if start >= 0: total += maxi(0, mini(through_day+1, int(event["minute"])/1440+1)-start)*int(asset["capacity"])
			start = int(event["minute"])/1440+1 if event["status"] == "ACTIVE" else -1
		if start >= 0: total += maxi(0, through_day+1-start)*int(asset["capacity"])
	return total

func invested_goods(site: String, good: String) -> int:
	var amount := 0
	for id: String in _site_projects.get(site, []): amount += int(projects[id]["materials"].get(good, 0))
	return amount

func keeper_reason(site: String) -> String:
	for id: String in _site_assets.get(site, []):
		if assets[id]["status"] in ["ACTIVE", "MAINTENANCE"]: return "STOP_EQUIPMENT_BEFORE_CUSTODIAL_SITE_CLOSURE"
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
		asset_ids.append_array(_site_assets.get(site, []))
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
	asset_ids.sort()
	for asset_id: String in asset_ids:
		var asset := (assets[asset_id] as Dictionary).duplicate(true)
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
	return {"format": FORMAT, "projects": projects.duplicate(true), "assets": assets.duplicate(true), "changes": changes.duplicate(true)}

func restore(value: Variant, saved: Dictionary) -> bool:
	if value == null: return true
	if not value is Dictionary or not FormalLedgerState.exact_fields(value, ["format", "projects", "assets", "changes"]) or value["format"] != FORMAT: return _fail("Invalid capital state")
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
	var work_used: Dictionary = {}
	var order_used: Dictionary = {}
	for id: Variant in projects:
		var p: Variant = projects[id]
		if not p is Dictionary or not EconomySliceConfig._fields(p, ["id", "action_id", "actor", "template_id", "firm", "site_id", "kind", "accepted_minute", "budget", "status", "materials", "material_minute", "work", "started_minute", "completed_minute", "orders", "asset_id", "reason"], ["material_sources", "construction_authority"]) or p["id"] != id or id != "capital_project:"+str(p["action_id"]): return _fail("Invalid capital project identity")
		var terms := template(str(p["template_id"]))
		if terms.is_empty() or p["firm"] != terms["firm"] or p["site_id"] != terms["site_id"] or not e._spec["sites"].has(p["site_id"]) or p["kind"] not in [terms["kind"], "MAINTENANCE"] or (p["kind"] == "MAINTENANCE" and not terms.has("maintenance")): return _fail("Capital project lacks site and permission")
		var command := saved.get("commands", {}).get(p["action_id"], {}) as Dictionary
		var payload := {"asset_id": p["asset_id"], "budget": p["budget"]} if p["kind"] == "MAINTENANCE" else {"template_id": p["template_id"], "budget": p["budget"]}
		if not command.get("result", {}).get("accepted", false) or command["envelope"]["actor"] != p["actor"] or command["envelope"]["command"]["payload"] != payload or command["envelope"]["command"]["minute"] != p["accepted_minute"] or command["envelope"]["command"]["kind"] != ("maintain_capital" if p["kind"] == "MAINTENANCE" else "invest") or not e._manager_at(p["actor"], p["firm"], int(p["accepted_minute"])): return _fail("Capital project lacks its accepted action")
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
		if p["status"] != "COMPLETED" or p["kind"] == "MAINTENANCE" or p["asset_id"] != id or id != "capital_asset:"+p["action_id"] or asset["in_service_minute"] != p["completed_minute"] or asset["firm"] != p["firm"] or asset["site_id"] != p["site_id"] or asset["materials"] != p["materials"]: return _fail("Asset lacks completed project")
		for key: String in ["template_id", "asset_type", "capacity", "activities", "basis"]:
			if asset[key] != terms.get(key, p.get(key)): return _fail("Asset capabilities differ from permission")
		if not asset["events"] is Array or asset["events"].is_empty(): return _fail("Missing asset availability history")
		var previous := -1
		var previous_status: String = ""
		for event: Variant in asset["events"]:
			if not event is Dictionary or not FormalLedgerState.exact_fields(event, ["minute", "status", "source"]) or not event["minute"] is int or int(event["minute"]) < int(asset["in_service_minute"]) or int(event["minute"]) < previous or int(event["minute"]) > now or int(event["minute"])%1440 != 0 or event["status"] not in ["ACTIVE", "PAUSED", "MAINTENANCE", "RETIRED"]: return _fail("Invalid asset availability boundary")
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
				if not control_ok and not maintenance_ok and not cancel_ok and not external_ok: return _fail("Equipment availability lacks its actual control or maintenance")
				if previous_status == "RETIRED": return _fail("Retired equipment was reactivated")
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
		if subject.is_empty() or not e._manager_at(row["actor"], subject["firm"], int(row["requested_minute"])) or (row["status"] == "APPLIED" and not e._manager_at(row["actor"], subject["firm"], int(row["effective_minute"]))): return _fail("Capital control lost its enterprise authority")
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
