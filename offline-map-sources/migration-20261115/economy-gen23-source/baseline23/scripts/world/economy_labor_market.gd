class_name EconomyLaborMarket
extends RefCounted
## Future quotation/consent facts. Workers, contracts, work, wages and cash stay
## in their existing R1 / Population / Ledger authorities.
const FORMAT := "economy_labor_market_v1"
var quotes: Dictionary = {}
var amendments: Dictionary = {}
var error: String = ""
var ready: bool = true
var _ref: WeakRef
var _rules: Dictionary = {}
var _current: Dictionary = {}
var _pending: Dictionary = {}
var _known: Dictionary = {}
var _last: Dictionary = {}
var _ends: Dictionary = {}
var _changed: Dictionary = {}
var _reviews: Dictionary = {}
var _active_amendments: Dictionary = {}
var _versions: Dictionary = {}
var _observations: Dictionary = {}
func economy() -> RefCounted: return _ref.get_ref()
func bind(e: RefCounted) -> void:
	_ref=weakref(e)
	for rule: Dictionary in e.config.get("labor_market",{}).get("job_rules",[]): _rules[rule["job_id"]]=rule
static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	if not settings.has("labor_market"): return true
	var v: Variant=settings["labor_market"]
	if not v is Dictionary or not FormalLedgerState.exact_fields(v,["job_rules","authorities","npc_policies","worker_policies","basis"]) or v["basis"]!="EXPLICIT_DEVELOPMENT_LABOR_MARKET": return false
	for key: String in ["job_rules","authorities","npc_policies","worker_policies"]:
		if not v[key] is Array or v[key].size()>32: return false
	var rules: Dictionary={}
	for p: Variant in v["job_rules"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["job_id","max_positions","min_wage","max_wage","wage_step","position_step","cooldown_days","quote_days","notice_days","recipients","cash_floor","coverage_days","basis"]) or not spec["jobs"].has(p.get("job_id")) or rules.has(p["job_id"]) or p["basis"]!="EXPLICIT_DEVELOPMENT_FUTURE_EMPLOYMENT_TERMS": return false
		for key: String in ["max_positions","min_wage","max_wage","wage_step","position_step","cooldown_days","quote_days","notice_days","cash_floor","coverage_days"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]>1000000: return false
		if p["max_positions"]<1 or p["min_wage"]<1 or p["max_wage"]<p["min_wage"] or p["wage_step"]<1 or p["position_step"]<1 or p["cooldown_days"]<1 or p["cooldown_days"]>30 or p["notice_days"]<1 or p["notice_days"]>7 or p["coverage_days"]<1 or p["coverage_days"]>7 or p["quote_days"]<=p["cooldown_days"] or p["quote_days"]>30: return false
		var job:=spec["jobs"][p["job_id"]] as Dictionary
		if job["positions"]>p["max_positions"] or job["wage_per_hour"]<p["min_wage"] or job["wage_per_hour"]>p["max_wage"] or not p["recipients"] is Array or p["recipients"].size()>16: return false
		var seen: Dictionary={}
		for actor: Variant in p["recipients"]:
			if not actor is String or seen.has(actor) or (not spec["actors"].has(actor) and actor!="HOST_SELECTED_PLAYER"): return false
			seen[actor]=true
		rules[p["job_id"]]=p
	var ids: Dictionary={}
	for p: Variant in v["authorities"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["id","firm","controller","operations","denomination","daily_wage_limit","start_minute","end_minute","root_authority","basis"]) or not p.get("id") is String or p["id"].is_empty() or ids.has(p["id"]) or not spec["firms"].has(p.get("firm")) or not p["controller"] is String or (not spec["actors"].has(p["controller"]) and not spec["firms"].has(p["controller"]) and p["controller"]!="HOST_SELECTED_PLAYER") or not p["operations"] is Array or p["operations"].is_empty() or not p["root_authority"] is String or p["basis"]!="EXPLICIT_DEVELOPMENT_EMPLOYMENT_AUTHORITY" or not FormalLedgerState.currency_id(p["denomination"]): return false
		for op: Variant in p["operations"]:
			if op not in ["recruit","amend"]: return false
		for key: String in ["daily_wage_limit","start_minute","end_minute"]:
			if not FormalLedgerState.valid_amount(p[key]): return false
		if p["end_minute"]<=p["start_minute"]: return false
		ids[p["id"]]=true
	ids.clear()
	for p: Variant in v["npc_policies"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["job_id","vacancy_days","window_days","basis"]) or not rules.has(p.get("job_id")) or ids.has(p["job_id"]) or not FormalLedgerState.valid_amount(p["vacancy_days"]) or p["vacancy_days"]<1 or not FormalLedgerState.valid_amount(p["window_days"]) or p["window_days"]<1 or p["window_days"]>30 or p["basis"]!="EXPLICIT_DEVELOPMENT_OWN_ACTIVITY_RECRUITMENT": return false
		ids[p["job_id"]]=true
	ids.clear()
	for p: Variant in v["worker_policies"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["actor","review_days","minimum_hourly_gain","max_move_workers","basis"]) or not spec["actors"].has(p.get("actor")) or spec["actors"][p["actor"]]["control"]!="automatic" or ids.has(p["actor"]) or p["basis"]!="EXPLICIT_DEVELOPMENT_KNOWN_LOCAL_JOB_CHOICE": return false
		for key: String in ["review_days","minimum_hourly_gain","max_move_workers"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]<1 or p[key]>30: return false
		ids[p["actor"]]=true
	return true
func controls(job: String) -> bool: return _rules.has(job)
func opening(job: String) -> Dictionary:
	var j:=economy()._spec["jobs"][job] as Dictionary
	return {"id":"job_quote:opening:"+job,"action_id":"","actor":"","job_id":job,"version":0,"positions":j["positions"],"wage_per_hour":j["wage_per_hour"],"denomination":j.get("denomination",FormalLedgerState.DENOMINATION),"hours":j["hours"],"skill":j["skill"],"wage_delay":j["wage_delay"],"recruiting":true,"requested_minute":0,"effective_minute":0,"valid_until":int(_rules[job]["quote_days"])*1440,"status":"APPLIED","permission":{},"application_permission":{},"reason":"OPENING_EXPLICIT_FIXED_CONDITIONS"}
func current(job: String) -> Dictionary: return quotes[_current[job]] if _current.has(job) else opening(job)
func quote(id: String) -> Dictionary:
	if quotes.has(id): return quotes[id]
	var job:=id.trim_prefix("job_quote:opening:")
	return opening(job) if controls(job) and id=="job_quote:opening:"+job else {}
func posting(job: String) -> Dictionary:
	var q:=current(job)
	return {"positions":q["positions"],"version":q["version"],"published_day":int(q["effective_minute"])/1440}
func contract_job(c: Dictionary) -> Dictionary:
	var j:=economy()._job(c["job"]) as Dictionary
	if c.has("terms"): j.merge(c["terms"],true)
	elif controls(c["job"]): j["wage_per_hour"]=economy()._spec["jobs"][c["job"]]["wage_per_hour"]
	return j
func permission(actor: String, job: String, op: String, amount: int) -> Dictionary:
	var e:=economy();var j:=e._spec["jobs"][job] as Dictionary
	var at: int=e._world.game_clock.total_minutes()
	if e.firm_manager_at(j["employer"],at)!=actor: return {"ok":false,"reason":"NOT_CURRENT_EMPLOYMENT_MANAGER"}
	for p: Dictionary in e.config.get("labor_market",{}).get("authorities",[]):
		if p["firm"]!=j["employer"] or p["controller"]!=actor or op not in p["operations"] or p["denomination"]!=j.get("denomination",FormalLedgerState.DENOMINATION) or amount>p["daily_wage_limit"] or at<p["start_minute"] or at>=p["end_minute"]: continue
		var result:={"ok":true,"authority_id":p["id"],"actor":actor,"job_id":job,"operation":op,"amount":amount,"minute":at,"source":p.duplicate(true)}
		if not p["root_authority"].is_empty():
			var operation:="economy.employment."+op
			var requirement:={"operation":operation,"target":job,"place":j["place"],"category":"employment","amount":amount}
			var context: Dictionary=e._cargo_fulfilment._available_context(actor,j["employer"],requirement,p["root_authority"])
			var authorization: Dictionary=e._cargo_fulfilment._authorize(actor,j["employer"],operation,job,j["place"],"employment",amount,{j["employer"]+"|"+operation+"|employment":context})
			if not authorization["ok"] or authorization["proof"].get("authority_id")!=p["root_authority"]: continue
			result["root_proof"]=authorization["proof"]
		return result
	return {"ok":false,"reason":"NO_INDEPENDENT_EMPLOYMENT_"+op.to_upper()+"_AUTHORITY"}
func occupied(job: String) -> int:
	var result:=0
	for c: Dictionary in economy()._all_contract_rows(economy()._contracts):
		if c["job"]==job: result+=int(c["workers"])
	return result
func protected_cash(firm: String, currency: String) -> int:
	var e:=economy()
	return int(e._mature_wage_position(firm,currency)["amount"])+e._due_credit_amount(firm,currency)
func daily_payroll(firm: String, currency: String) -> int:
	var result:=0;var e:=economy()
	for c: Dictionary in e._all_contract_rows(e._contracts):
		var j:=contract_job(c)
		if j["employer"]==firm and j["denomination"]==currency: result+=int(c["workers"])*int(j["hours"])*int(j["wage_per_hour"])
	return result
func affordable(job: String, wage: int, new_workers: int) -> bool:
	var e:=economy();var j:=e._spec["jobs"][job] as Dictionary;var r:=_rules[job] as Dictionary
	var currency: String=j.get("denomination",FormalLedgerState.DENOMINATION)
	var exposure:=daily_payroll(j["employer"],currency)+maxi(0,new_workers)*int(j["hours"])*wage
	return e._world.ledger_state.available_balance(e._account(j["employer"],currency))>=int(r["cash_floor"])+protected_cash(j["employer"],currency)+exposure*int(r["coverage_days"])
func request(actor: String, kind: String, p: Dictionary, action: String, preview: bool=false) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if kind=="propose_employment_terms": return _propose(actor,p,action,preview)
	if kind=="accept_employment_terms": return _confirm(actor,p,action,preview)
	if not FormalLedgerState.exact_fields(p,["job_id","positions","wage_per_hour","recruiting"]) or not controls(str(p.get("job_id",""))) or not p["recruiting"] is bool or not FormalLedgerState.valid_amount(p["positions"]) or not FormalLedgerState.valid_amount(p["wage_per_hour"]): return reject("INVALID_FUTURE_JOB_QUOTATION")
	var job: String=p["job_id"];var r:=_rules[job] as Dictionary;var old:=current(job);var j:=e._spec["jobs"][job] as Dictionary
	if _pending.has(job) or now-int(_last.get(job,-1000000))<int(r["cooldown_days"])*1440: return reject("JOB_CHANGE_PENDING_OR_COOLDOWN")
	if p["positions"]>r["max_positions"] or p["positions"]<occupied(job) or absi(int(p["positions"])-int(old["positions"]))>r["position_step"]: return reject("POSITION_BOUND_OR_END_EXISTING_CONTRACTS_FIRST")
	if p["wage_per_hour"]<r["min_wage"] or p["wage_per_hour"]>r["max_wage"] or absi(int(p["wage_per_hour"])-int(old["wage_per_hour"]))>r["wage_step"]: return reject("FUTURE_WAGE_BOUND_OR_STEP")
	if p["recruiting"] and (not e._site_accepting(j["site_id"]) or e._firm_winding_down(j["employer"])): return reject("NO_LAWFUL_SITE_FOR_NEW_RECRUITMENT")
	if p["recruiting"] and int(p["positions"])>occupied(job) and not affordable(job,p["wage_per_hour"],int(p["positions"])-occupied(job)): return reject("FUTURE_PAYROLL_CASH_OBSERVATION_INSUFFICIENT_NOT_RESERVED")
	var proof:=permission(actor,job,"recruit",int(p["positions"])*int(j["hours"])*int(p["wage_per_hour"]))
	if not proof["ok"]: return reject(proof["reason"])
	if preview: return {"accepted":true,"reason":"BOUNDED_FUTURE_TERMS_NO_WAGE_FUNDS_RESERVED"}
	var q:=opening(job);q.merge({"id":"job_quote:"+action,"action_id":action,"actor":actor,"version":_next_version(job),"positions":p["positions"],"wage_per_hour":p["wage_per_hour"],"recruiting":p["recruiting"],"requested_minute":now,"effective_minute":(e.day+1)*1440,"valid_until":(e.day+1+int(r["quote_days"]))*1440,"status":"QUEUED","permission":proof,"reason":""},true)
	quotes[q["id"]]=q;_pending[job]=q["id"];_last[job]=now
	return {"accepted":true,"reason":"FUTURE_RECRUITMENT_QUEUED_NOT_EMPLOYED_OR_CASH_SECURED","quote_id":q["id"],"effective_minute":q["effective_minute"]}
func _next_version(job: String) -> int:
	_versions[job]=int(_versions.get(job,0))+1
	return _versions[job]
func boundary() -> void:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	for job: String in _pending.keys():
		var q:=quotes[_pending[job]] as Dictionary
		if q["effective_minute"]>now: continue
		var j:=e._spec["jobs"][job] as Dictionary
		var proof:=permission(q["actor"],job,"recruit",int(q["positions"])*int(q["hours"])*int(q["wage_per_hour"]))
		if not proof["ok"] or q["positions"]<occupied(job) or (q["recruiting"] and (not e._site_accepting(j["site_id"]) or e._firm_winding_down(j["employer"]))): q["status"]="DEFERRED";q["reason"]=proof.get("reason","EXISTING_CONTRACTS_EXCEED_PROPOSED_SLOTS" if q["positions"]<occupied(job) else "WORK_SITE_NO_LONGER_ACCEPTING_RECRUITMENT")
		else:
			q["status"]="APPLIED";q["application_permission"]=proof;_current[job]=q["id"];e._job_postings[job]=posting(job)
			e._commercial.publish_recruitment(q)
		_pending.erase(job)
	for id: String in _active_amendments.keys():
		var a:=amendments[id] as Dictionary
		if a["status"]=="OFFERED" and now>=quote(a["quote_id"])["valid_until"]: a["status"]="EXPIRED";a["reason"]="UNACCEPTED_TERMS_EXPIRED";_active_amendments.erase(id);continue
		if a["status"]!="QUEUED" or a["effective_minute"]>now: continue
		var c:=e._contract_for(a["worker"],a["job_id"]) as Dictionary
		var terms:=quote(a["quote_id"])
		var proof:=permission(a["actor"],a["job_id"],"amend",int(c.get("workers",0))*int(terms["hours"])*int(terms["wage_per_hour"]))
		if c!=a["old_contract"] or not proof["ok"]: a["status"]="DEFERRED";a["reason"]=proof.get("reason","WORKER_ALLOCATION_CHANGED_BEFORE_CONSENT_BOUNDARY");_active_amendments.erase(id);continue
		var replacement:=e._commands[a["acceptance_id"]]["result"]["employment"].duplicate(true) as Dictionary
		if e._cohort_profile(a["worker"]).is_empty(): e._contracts[a["worker"]]=replacement
		else: e._contracts[a["worker"]]["allocations"][a["job_id"]]=replacement
		a["status"]="APPLIED";a["application_permission"]=proof;_changed[c["employment_action_id"]]=a["effective_minute"]
		_active_amendments.erase(id)
func lock_contract(c: Dictionary, action: String, q: Dictionary) -> void:
	c["employment_action_id"]=action
	c["terms"]={"quote_id":q["id"],"version":q["version"],"wage_per_hour":q["wage_per_hour"],"hours":q["hours"],"denomination":q["denomination"],"wage_delay":q["wage_delay"],"accepted_minute":economy()._world.game_clock.total_minutes(),"effective_minute":economy()._world.game_clock.total_minutes()}
func applicable(actor: String, job: String, id: String) -> Dictionary:
	var q:=current(job);var now: int=economy()._world.game_clock.total_minutes()
	if id!=q["id"] or not knows(actor,id) or now<q["effective_minute"] or now>=q["valid_until"] or not q["recruiting"]: return reject("STALE_UNKNOWN_OR_CLOSED_RECRUITMENT_QUOTE")
	if not affordable(job,int(q["wage_per_hour"]),1): return reject("EMPLOYER_CURRENT_PAYROLL_CASH_PRESSURE")
	return {"accepted":true,"quote":q}
func known_job(actor: String, job: String) -> Dictionary:
	var e:=economy();var result:=e._spec["jobs"][job].duplicate(true) as Dictionary
	var q:=quote(str(_known.get(actor,{}).get(job,"")))
	if q.is_empty() and job in e._actors.get(actor,{}).get("known_jobs",[]): q=opening(job)
	if q.is_empty(): result["positions"]=0;result["wage_per_hour"]=0;return result
	result.merge({"positions":q["positions"],"wage_per_hour":q["wage_per_hour"],"denomination":q["denomination"],"job_quote_id":q["id"],"posting_version":q["version"],"observed_day":int(q["effective_minute"])/1440,"valid_until":q["valid_until"],"recruiting":q["recruiting"],"quote_current":q["id"]==current(job)["id"] and e._world.game_clock.total_minutes()<q["valid_until"]},true)
	return result
func knows(actor: String, id: String) -> bool:
	var q:=quote(id)
	if q.is_empty(): return false
	if economy()._receipts.has("recruitment:"+id+":"+actor): return true
	return q["version"]==0 and q["job_id"] in economy()._actors.get(actor,{}).get("known_jobs",[])
func adopted_message(message: Dictionary) -> void:
	var actor: String=message["actor"];var job: String=message["candidate"]
	if not _known.has(actor): _known[actor]={}
	if int(quote(str(_known[actor].get(job,""))).get("version",-1))<=int(message["version"]): _known[actor][job]=message["quote_id"]
func observe_person(actor: String) -> void:
	var e:=economy()
	for job: String in _rules:
		if actor in _rules[job]["recipients"] and e._at_place(actor,e._spec["jobs"][job]["place"]): e._commercial.publish_recruitment(current(job),actor)
func message(q: Dictionary, actor: String, now: int) -> Dictionary:
	var j:=economy()._spec["jobs"][q["job_id"]] as Dictionary
	return {"id":"recruitment:"+str(q["id"])+":"+actor,"actor":actor,"kind":"job_posting","candidate":q["job_id"],"observed_day":int(q["effective_minute"])/1440,"delivery_day":now/1440+int(_rules[q["job_id"]]["notice_days"]),"source":"labor_market","quote_id":q["id"],"version":q["version"],"positions":q["positions"],"employer":j["employer"],"site_id":j["site_id"],"skill":q["skill"],"hours":q["hours"],"wage_per_hour":q["wage_per_hour"],"denomination":q["denomination"],"valid_from":q["effective_minute"],"valid_until":q["valid_until"],"contact_minute":now,"action_id":q["action_id"]}
func valid_message(m: Dictionary) -> bool:
	var q:=quote(str(m.get("quote_id","")))
	return not q.is_empty() and q["status"]=="APPLIED" and m.get("actor") in _rules[q["job_id"]]["recipients"] and FormalLedgerState.valid_amount(m.get("contact_minute")) and m["contact_minute"]>=q["effective_minute"] and m["contact_minute"]<q["valid_until"] and m==message(q,m["actor"],m["contact_minute"])
func reindex_ends() -> void:
	_ends.clear()
	for row: Dictionary in economy()._employment_ends.values(): record_end(row)
func record_end(row: Dictionary) -> void:
	if row.get("status")!="APPLIED": return
	for c: Dictionary in economy()._contract_rows(row["contract"]):
		if not c.has("employment_action_id") or (row.has("job_id") and row["job_id"]!=c["job"]): continue
		var id: String=c["employment_action_id"]
		if not _ends.has(id): _ends[id]=[]
		_ends[id].append({"minute":row["effective_minute"],"workers":row.get("workers",c["workers"])})
func employment_at(actor: String, id: String, minute: int, commands: Dictionary) -> Dictionary:
	var entry:=commands.get(id,{}) as Dictionary;var c:=entry.get("result",{}).get("employment",{}).duplicate(true) as Dictionary
	if entry.get("envelope",{}).get("command",{}).get("kind")=="accept_employment_terms" and amendments.get(entry["envelope"]["command"]["payload"].get("proposal_id"),{}).get("status")!="APPLIED": return {}
	if entry.get("envelope",{}).get("actor")!=actor or not entry.get("result",{}).get("accepted",false) or c.is_empty() or c.get("employment_action_id")!=id or not c.get("terms") is Dictionary or c["terms"].get("effective_minute",minute+1)>minute or int(_changed.get(id,FormalLedgerState.MAX_AMOUNT))<=minute: return {}
	for ending: Dictionary in _ends.get(id,[]):
		if ending["minute"]<=minute: c["workers"]=int(c["workers"])-int(ending["workers"])
	return c if int(c["workers"])>0 else {}
func valid_contract(c: Dictionary, actor: String, commands: Dictionary, minute: int) -> bool:
	if not c.has("employment_action_id") or not c.has("terms"): return false
	var t:=c["terms"] as Dictionary;var q:=quote(str(t.get("quote_id","")))
	if q.is_empty() or not FormalLedgerState.exact_fields(t,["quote_id","version","wage_per_hour","hours","denomination","wage_delay","accepted_minute","effective_minute"]): return false
	for key: String in ["version","wage_per_hour","hours","denomination","wage_delay"]:
		if t[key]!=q[key]: return false
	return q["job_id"]==c["job"] and employment_at(actor,c["employment_action_id"],minute,commands)==c
func _propose(actor: String, p: Dictionary, action: String, preview: bool) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if not FormalLedgerState.exact_fields(p,["worker","job_id","quote_id"]) or not controls(str(p.get("job_id",""))) or not p["worker"] is String or not e._spec["actors"].has(p["worker"]) or not p["quote_id"] is String: return reject("INVALID_EMPLOYMENT_AMENDMENT")
	var c:=e._contract_for(p["worker"],p["job_id"]) as Dictionary;var q:=current(p["job_id"])
	if c.is_empty() or not c.has("terms") or q["id"]!=p["quote_id"] or now>=q["valid_until"]: return reject("NO_CURRENT_CONTRACT_OR_FUTURE_TERMS")
	if c["terms"]["wage_per_hour"]==q["wage_per_hour"]: return reject("ACCEPTED_WAGE_ALREADY_MATCHES_OFFER")
	var delta:=maxi(0,int(q["wage_per_hour"])-int(c["terms"]["wage_per_hour"]))*int(c["workers"])*int(q["hours"])
	var firm: String=e._spec["jobs"][p["job_id"]]["employer"];var currency: String=q["denomination"]
	var rule:=_rules[p["job_id"]] as Dictionary
	if e._world.ledger_state.available_balance(e._account(firm,currency))<int(rule["cash_floor"])+protected_cash(firm,currency)+(daily_payroll(firm,currency)+delta)*int(rule["coverage_days"]): return reject("AMENDED_FUTURE_PAYROLL_NOT_AFFORDABLE")
	var proof:=permission(actor,p["job_id"],"amend",int(c["workers"])*int(q["hours"])*int(q["wage_per_hour"]))
	if not proof["ok"]: return reject(proof["reason"])
	for aid: String in _active_amendments:
		var a:=amendments[aid] as Dictionary
		if a["worker"]==p["worker"] and a["job_id"]==p["job_id"] and a["status"] in ["OFFERED","QUEUED"]: return reject("EMPLOYMENT_AMENDMENT_ALREADY_PENDING")
	if preview: return {"accepted":true,"reason":"WORKER_CONFIRMATION_REQUIRED_NO_UNILATERAL_WAGE_CHANGE"}
	var id:="employment_amendment:"+action
	amendments[id]={"id":id,"action_id":action,"actor":actor,"worker":p["worker"],"job_id":p["job_id"],"quote_id":p["quote_id"],"old_contract":c.duplicate(true),"proposed_minute":now,"acceptance_id":"","effective_minute":-1,"status":"OFFERED","permission":proof,"application_permission":{},"reason":""}
	_active_amendments[id]=true
	return {"accepted":true,"reason":"FUTURE_TERMS_OFFERED_WORKER_CONSENT_REQUIRED","proposal_id":id}
func _confirm(actor: String, p: Dictionary, action: String, preview: bool=false) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if not FormalLedgerState.exact_fields(p,["proposal_id"]) or not p["proposal_id"] is String or not amendments.has(p["proposal_id"]): return reject("UNKNOWN_EMPLOYMENT_AMENDMENT")
	var a:=amendments[p["proposal_id"]] as Dictionary;var q:=quote(a["quote_id"])
	if a["worker"]==actor and a["status"]=="OFFERED" and not knows(actor,q["id"]): return reject("FUTURE_EMPLOYMENT_TERMS_NOT_RECEIVED")
	if a["worker"]!=actor or a["status"]!="OFFERED" or now>=q["valid_until"] or e._contract_for(actor,a["job_id"])!=a["old_contract"] or e._employment_end_pending(actor): return reject("ONLY_CURRENT_WORKER_CAN_CONFIRM_UNCHANGED_CONTRACT")
	if preview: return {"accepted":true,"reason":"OWN_CONSENT_NEXT_DAILY_BOUNDARY_OLD_WORK_REMAINS"}
	var c:=a["old_contract"].duplicate(true) as Dictionary
	lock_contract(c,action,q);c["terms"]["effective_minute"]=(e.day+1)*1440
	a["acceptance_id"]=action;a["effective_minute"]=(e.day+1)*1440;a["status"]="QUEUED"
	return {"accepted":true,"reason":"CONSENT_RECORDED_OLD_REGISTERED_WORK_RETAINS_OLD_RATE","employment":c,"proposal_id":a["id"],"effective_minute":a["effective_minute"]}
func ordered_jobs(actor: String, ids: Array) -> Array:
	var e:=economy();var result:=ids.duplicate()
	if not worker_policy(actor).is_empty():
		result.sort_custom(func(a: String,b: String)->bool:
			var x:=e._known_job(actor,a) as Dictionary;var y:=e._known_job(actor,b) as Dictionary
			if x["denomination"]!=y["denomination"]: return str(x["denomination"])<str(y["denomination"]) # No fictitious cross-currency conversion.
			return int(x["wage_per_hour"])>int(y["wage_per_hour"]) if x["wage_per_hour"]!=y["wage_per_hour"] else a<b)
	return result
func worker_policy(actor: String) -> Dictionary:
	for p: Dictionary in economy().config.get("labor_market",{}).get("worker_policies",[]):
		if p["actor"]==actor: return p
	return {}
func worker_decisions() -> void:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	for p: Dictionary in e.config.get("labor_market",{}).get("worker_policies",[]):
		var actor: String=p["actor"]
		if e.day-int(_reviews.get(actor,-1000))<int(p["review_days"]) or e._employment_end_pending(actor): continue
		_reviews[actor]=e.day
		for c: Dictionary in e._contract_rows(e._contracts.get(actor,{})):
			if controls(c["job"]) and not e._npc_job_payable(actor,c["job"]):
				e._accept(actor,e._auto_command(actor,"leave_job",{"job_id":c["job"],"workers":c["workers"]},"known_own_wage_arrears:"+str(c["job"])),true)
				break
		if e._employment_end_pending(actor): continue
		for aid: String in _active_amendments.keys():
			var a:=amendments[aid] as Dictionary
			if a["worker"]==actor and a["status"]=="OFFERED" and quote(a["quote_id"])["wage_per_hour"]>=contract_job(a["old_contract"])["wage_per_hour"]:
				e._accept(actor,e._auto_command(actor,"accept_employment_terms",{"proposal_id":a["id"]},a["id"]),true)
		if not e._cohort_profile(actor).is_empty() and EconomyCohortRules.free_span(e._spec["actors"][actor],e._contracts.get(actor,{})).y>0: continue
		var choices:=ordered_jobs(actor,e._actors[actor]["known_jobs"])
		for id: String in choices:
			if not controls(id) or not e._contract_for(actor,id).is_empty() or not cohort_allowed(actor,id): continue
			var job:=known_job(actor,id)
			if not job.get("quote_current",false) or not job.get("recruiting",false) or not e._at_place(actor,job["place"]) or not e._npc_job_payable(actor,id) or int(job["positions"])<1 or not e._site_accepting(job["site_id"]) or int(e._spec["actors"][actor]["skill"])<int(job["skill"]): continue
			for c: Dictionary in e._contract_rows(e._contracts.get(actor,{})):
				var old:=contract_job(c)
				if not controls(c["job"]) or old["employer"]==job["employer"] or old["denomination"]!=job["denomination"] or int(job["wage_per_hour"])-int(old["wage_per_hour"])<int(p["minimum_hourly_gain"]): continue
				var count:=mini(int(c["workers"]),mini(int(p["max_move_workers"]),int(job["positions"])))
				if count<1: continue
				if count<int(c["workers"]) and e._contract_rows(e._contracts.get(actor,{})).size()>=int(e._cohort_profile(actor)["max_jobs"]): continue
				e._accept(actor,e._auto_command(actor,"leave_job",{} if e._cohort_profile(actor).is_empty() else {"job_id":c["job"],"workers":count},"known_better_job:"+id),true)
				break
			if e._employment_end_pending(actor): break
func cohort_allowed(actor: String, job: String) -> bool:
	return EconomyCohortRules.allows_job(economy()._spec["actors"][actor],job)
func needed_hours(site: String) -> int:
	var e:=economy()
	if not e._site_accepting(site) or e._firm_winding_down(e._owner(site)): return 0
	var retail:=0
	if e._retail.has_site(site):
		for good: String in e._retail._sites[site]["stock_units"]:
			if int(e._stocks[site][good])>0 or e._exposure(site,good)>0: retail=e._retail.labor_needed(site);break
	return int(e._allocate_production(site,FormalLedgerState.MAX_AMOUNT)["labor_used"])+e._capital.labor_needed(site)+e._shared.labor_needed(site)+e._service_market.labor_needed(site)+retail
func needed_for_job(id: String) -> int:
	var e:=economy();var site: String=e._spec["jobs"][id]["site_id"]
	var other:=0
	for c: Dictionary in e._all_contract_rows(e._contracts):
		if c["job"]!=id and e._spec["jobs"][c["job"]]["site_id"]==site: other+=int(c["workers"])*int(contract_job(c)["hours"])
	var exclusive:=0
	for sid: String in e._service_market._active:
		var c:=e._service_market.contracts[sid] as Dictionary;var o:=e._service_market._offers[c["offer_id"]] as Dictionary
		if c["provider_site"]==site and not c["paused"] and o["job_ids"]==[id]: exclusive+=int(o["hours_per_day"])
	return maxi(exclusive,maxi(0,needed_hours(site)-other))
func npc_decisions() -> void:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	for p: Dictionary in e.config.get("labor_market",{}).get("npc_policies",[]):
		var id: String=p["job_id"];var j:=e._spec["jobs"][id] as Dictionary;var r:=_rules[id] as Dictionary;var q:=current(id)
		if e.firm_manager_at(j["employer"],now)!=j["employer"]: continue
		var need:=0 if e._firm_winding_down(j["employer"]) or e.firm_finished(j["employer"]) else needed_for_job(id);var hired:=occupied(id)
		if not _observations.has(id): _observations[id]=[]
		var samples:=_observations[id] as Array
		if samples.is_empty() or samples.back()["day"]!=e.day: samples.append({"day":e.day,"required_hours":need,"unfilled":maxi(0,need-hired*int(j["hours"]))})
		while not samples.is_empty() and samples[0]["day"]<=e.day-int(p["window_days"]): samples.pop_front()
		var vacancy_days:=0
		for index: int in range(samples.size()-1,-1,-1):
			if samples[index]["unfilled"]<=0 or samples[index]["day"]!=e.day-vacancy_days: break
			vacancy_days+=1
		if _pending.has(id) or now-int(_last.get(id,-1000000))<int(r["cooldown_days"])*1440: continue
		var target:=mini(int(r["max_positions"]),maxi(hired,(need+int(j["hours"])-1)/int(j["hours"])))
		var positions:=clampi(target,maxi(hired,int(q["positions"])-int(r["position_step"])),int(q["positions"])+int(r["position_step"]))
		var wage:=int(q["wage_per_hour"]);var recruiting:=need>0 and affordable(id,wage,maxi(0,positions-hired))
		if recruiting and positions>hired and vacancy_days>=int(p["vacancy_days"]): wage=mini(int(r["max_wage"]),wage+int(r["wage_step"]))
		if not recruiting: positions=hired;wage=maxi(int(r["min_wage"]),wage-int(r["wage_step"]))
		positions=clampi(positions,maxi(hired,int(q["positions"])-int(r["position_step"])),int(q["positions"])+int(r["position_step"]))
		if positions==q["positions"] and wage==q["wage_per_hour"] and recruiting==q["recruiting"] and now+2*1440<q["valid_until"]: continue
		e._accept(j["employer"],e._auto_command(j["employer"],"set_job_offer",{"job_id":id,"positions":positions,"wage_per_hour":wage,"recruiting":recruiting},id),true)
func snapshot() -> Dictionary: return {"format":FORMAT,"quotes":quotes.duplicate(true),"amendments":amendments.duplicate(true),"reviews":_reviews.duplicate(true),"observations":_observations.duplicate(true)}
func reject(reason: String) -> Dictionary: return {"accepted":false,"reason":reason}
func fail(reason: String) -> bool: error=reason;return false

# These are projections of the original received messages and accepted actions.
func apply_payload(actor: String, job: String) -> Dictionary:
	var result:={"job_id":job}
	if controls(job): result["job_quote_id"]=known_job(actor,job).get("job_quote_id","")
	return result
func latest_notice(actor: String, job: String) -> Dictionary:
	var id: String=_known.get(actor,{}).get(job,"")
	return economy()._receipts.get("recruitment:"+id+":"+actor,{})
func work_contract(work: Dictionary, command: Dictionary, commands: Dictionary) -> Dictionary:
	var c:=employment_at(str(work.get("actor","")),str(work.get("employment_action_id","")),int(command.get("minute",-1)),commands)
	return c if not c.is_empty() and c["job"]==work.get("job") and valid_contract(c,work["actor"],commands,command["minute"]) else {}
func _proof_valid(proof: Variant, actor: String, job: String, op: String, amount: int, minute: int) -> bool:
	if not proof is Dictionary or not EconomySliceConfig._fields(proof,["ok","authority_id","actor","job_id","operation","amount","minute","source"],["root_proof"]) or proof["ok"]!=true or proof["actor"]!=actor or proof["job_id"]!=job or proof["operation"]!=op or proof["amount"]!=amount or proof["minute"]!=minute or not proof["source"] is Dictionary: return false
	var e:=economy();var j:=e._spec["jobs"][job] as Dictionary;var p:=proof["source"] as Dictionary
	if not e.config["labor_market"]["authorities"].has(p) or p["id"]!=proof["authority_id"] or p["firm"]!=j["employer"] or p["controller"]!=actor or op not in p["operations"] or p["denomination"]!=j.get("denomination",FormalLedgerState.DENOMINATION) or amount>p["daily_wage_limit"] or minute<p["start_minute"] or minute>=p["end_minute"] or e.firm_manager_at(j["employer"],minute)!=actor: return false
	if p["root_authority"].is_empty(): return not proof.has("root_proof")
	var root:=proof.get("root_proof",{}) as Dictionary
	return e._cargo_fulfilment._saved_authority(root) and root.get("authority_id")==p["root_authority"] and root.get("subject")==j["employer"] and root.get("actor")==actor and root.get("amount")==amount and root.get("minute")==minute and root.get("operation")=="economy.employment."+op and root.get("target")==job and root.get("place")==j["place"] and root.get("category")=="employment"
func _known_at(actor: String, q: Dictionary, minute: int, saved: Dictionary) -> bool:
	for m: Dictionary in saved["receipts"].values():
		if m.get("actor")!=actor or m.get("candidate")!=q["job_id"] or int(m.get("delivery_day",FormalLedgerState.MAX_AMOUNT))*1440>minute: continue
		if m.get("source")=="labor_market" and m.get("quote_id")==q["id"]: return true
		if q["version"]==0 and m.get("kind")=="job": return true
	return false
func _quote_at(job: String, minute: int) -> Dictionary:
	var result:=opening(job)
	for q: Dictionary in quotes.values():
		if q["job_id"]==job and q["status"]=="APPLIED" and q["effective_minute"]<=minute and q["version"]>result["version"]: result=q
	return result
func restore(raw: Variant, saved: Dictionary) -> bool:
	quotes.clear();amendments.clear();_current.clear();_pending.clear();_known.clear();_last.clear();_changed.clear();_reviews.clear();_active_amendments.clear();_versions.clear();_observations.clear()
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if raw==null:
		ready=true
		return true
	if _rules.is_empty() or not raw is Dictionary or not FormalLedgerState.exact_fields(raw,["format","quotes","amendments","reviews","observations"]) or raw["format"]!=FORMAT or not raw["quotes"] is Dictionary or not raw["amendments"] is Dictionary or not raw["reviews"] is Dictionary or not raw["observations"] is Dictionary or not saved.get("commands") is Dictionary or not saved.get("receipts") is Dictionary: return fail("Invalid labor quotation snapshot")
	quotes=raw["quotes"].duplicate(true);amendments=raw["amendments"].duplicate(true);_reviews=raw["reviews"].duplicate(true);_observations=raw["observations"].duplicate(true)
	var by_job: Dictionary={}
	var active_pairs: Dictionary={}
	for id: Variant in quotes:
		var q: Variant=quotes[id]
		if not id is String or not q is Dictionary or not q.get("action_id") is String or not controls(str(q.get("job_id",""))) or not _same_fields(q,opening(q["job_id"])) or id!=q["id"] or id!="job_quote:"+str(q["action_id"]) or not q["actor"] is String or not q["recruiting"] is bool or q["status"] not in ["QUEUED","APPLIED","DEFERRED"] or not q["reason"] is String: return fail("Invalid stable job quotation")
		for key: String in ["version","positions","wage_per_hour","hours","skill","wage_delay","requested_minute","effective_minute","valid_until"]:
			if not FormalLedgerState.valid_amount(q[key]): return fail("Invalid integer job quotation terms")
		var job: String=q["job_id"];var r:=_rules[job] as Dictionary;var base:=opening(job)
		if q["status"]=="APPLIED":
			if not _proof_valid(q["application_permission"],q["actor"],job,"recruit",int(q["positions"])*int(q["hours"])*int(q["wage_per_hour"]),q["effective_minute"]): return fail("Effective recruitment lost execution authority")
		elif q["application_permission"]!={}: return fail("Unapplied recruitment contains execution proof")
		for key: String in ["hours","skill","wage_delay","denomination"]:
			if q[key]!=base[key]: return fail("Job quote changed immutable job scope")
		if q["positions"]>r["max_positions"] or q["wage_per_hour"]<r["min_wage"] or q["wage_per_hour"]>r["max_wage"] or q["requested_minute"]>now or q["effective_minute"]!=(int(q["requested_minute"])/1440+1)*1440 or q["valid_until"]!=int(q["effective_minute"])+int(r["quote_days"])*1440 or (q["status"]=="QUEUED")!=(int(q["effective_minute"])>now): return fail("Job quotation exceeds limits or time boundary")
		var entry:=saved["commands"].get(q["action_id"],{}) as Dictionary
		var cmd:=entry.get("envelope",{}).get("command",{}) as Dictionary
		if entry.get("envelope",{}).get("actor")!=q["actor"] or cmd.get("kind")!="set_job_offer" or cmd.get("minute")!=q["requested_minute"] or cmd.get("payload")!={"job_id":job,"positions":q["positions"],"wage_per_hour":q["wage_per_hour"],"recruiting":q["recruiting"]} or entry.get("result",{}).get("accepted")!=true or entry["result"].get("quote_id")!=id or entry["result"].get("effective_minute")!=q["effective_minute"] or not _proof_valid(q["permission"],q["actor"],job,"recruit",int(q["positions"])*int(q["hours"])*int(q["wage_per_hour"]),q["requested_minute"]): return fail("Job quotation lacks original employment authority and action")
		if not by_job.has(job): by_job[job]=[]
		by_job[job].append(q)
	for job: String in by_job:
		by_job[job].sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["version"]<b["version"])
		var previous:=opening(job);var last_request: int=-1000000;var version:=0;var r:=_rules[job] as Dictionary
		for q: Dictionary in by_job[job]:
			version+=1
			if q["version"]!=version or q["requested_minute"]-last_request<int(r["cooldown_days"])*1440 or absi(int(q["positions"])-int(previous["positions"]))>r["position_step"] or absi(int(q["wage_per_hour"])-int(previous["wage_per_hour"]))>r["wage_step"]: return fail("Job quotation history changed bounds or cooldown")
			last_request=q["requested_minute"]
			if q["status"]=="APPLIED": previous=q;_current[job]=q["id"]
			if q["status"]=="QUEUED": _pending[job]=q["id"]
		_versions[job]=version;_last[job]=last_request
	for id: Variant in amendments:
		var a: Variant=amendments[id]
		if not a is Dictionary or not FormalLedgerState.exact_fields(a,["id","action_id","actor","worker","job_id","quote_id","old_contract","proposed_minute","acceptance_id","effective_minute","status","permission","application_permission","reason"]) or id!=a["id"] or id!="employment_amendment:"+str(a["action_id"]) or not a["actor"] is String or not a["worker"] is String or not e._spec["actors"].has(a["worker"]) or not a["quote_id"] is String or not a["action_id"] is String or not a["acceptance_id"] is String or not controls(str(a["job_id"])) or not a["old_contract"] is Dictionary or not a["reason"] is String or a["status"] not in ["OFFERED","QUEUED","APPLIED","DEFERRED","EXPIRED"] or not FormalLedgerState.valid_amount(a["proposed_minute"]) or a["proposed_minute"]>now: return fail("Invalid worker terms proposal")
		var q:=quote(a["quote_id"]);var entry:=saved["commands"].get(a["action_id"],{}) as Dictionary;var cmd:=entry.get("envelope",{}).get("command",{}) as Dictionary
		if q.is_empty() or _quote_at(a["job_id"],a["proposed_minute"])["id"]!=q["id"] or a["proposed_minute"]>=q["valid_until"] or entry.get("envelope",{}).get("actor")!=a["actor"] or cmd.get("kind")!="propose_employment_terms" or cmd.get("minute")!=a["proposed_minute"] or cmd.get("payload")!={"worker":a["worker"],"job_id":a["job_id"],"quote_id":a["quote_id"]} or entry.get("result",{}).get("proposal_id")!=id or not entry["result"].get("accepted",false) or not _proof_valid(a["permission"],a["actor"],a["job_id"],"amend",int(a["old_contract"].get("workers",0))*int(q["hours"])*int(q["wage_per_hour"]),a["proposed_minute"]): return fail("Employment amendment lacks manager proposal")
		if a["status"] in ["OFFERED","EXPIRED"]:
			if (a["status"]=="EXPIRED" and now<q["valid_until"]) or a["acceptance_id"]!="" or a["effective_minute"]!=-1: return fail("Unconfirmed wage amendment became effective")
		else:
			var accept:=saved["commands"].get(a["acceptance_id"],{}) as Dictionary;var c:=accept.get("result",{}).get("employment",{}) as Dictionary
			var command:=accept.get("envelope",{}).get("command",{}) as Dictionary
			if accept.get("envelope",{}).get("actor")!=a["worker"] or command.get("kind")!="accept_employment_terms" or command.get("payload")!={"proposal_id":id} or not accept.get("result",{}).get("accepted",false) or command.get("minute",-1)<a["proposed_minute"] or command["minute"]>=q["valid_until"] or a["effective_minute"]!=(int(command["minute"])/1440+1)*1440 or c.get("employment_action_id")!=a["acceptance_id"] or c.get("job")!=a["job_id"] or c.get("workers")!=a["old_contract"].get("workers") or c.get("labor_start",-1)!=a["old_contract"].get("labor_start",-1): return fail("Employment amendment lacks worker consent")
			if (a["status"]=="QUEUED")!=(int(a["effective_minute"])>now): return fail("Employment amendment applied outside its boundary")
			if a["status"]=="APPLIED":
				if not _proof_valid(a["application_permission"],a["actor"],a["job_id"],"amend",int(a["old_contract"]["workers"])*int(q["hours"])*int(q["wage_per_hour"]),a["effective_minute"]): return fail("Future wage amendment lost effective authority")
				_changed[a["old_contract"]["employment_action_id"]]=a["effective_minute"]
		if a["status"]!="APPLIED" and a["application_permission"]!={}: return fail("Unapplied wage amendment contains execution proof")
		if a["status"] in ["OFFERED","QUEUED"]:
			var key: String=a["worker"]+"|"+a["job_id"]
			if active_pairs.has(key): return fail("Duplicate pending worker wage proposal")
			active_pairs[key]=true;_active_amendments[id]=true
	reindex_ends()
	for id: String in _ends:
		var remaining: int=saved["commands"].get(id,{}).get("result",{}).get("employment",{}).get("workers",0)
		for ending: Dictionary in _ends[id]:
			remaining-=int(ending["workers"])
			if remaining<0: return fail("Employment exits released worker shares more than once")
	# Validate the original accepted source once. Daily work uses the source index.
	for id: String in saved["commands"]:
		var entry:=saved["commands"][id] as Dictionary;var c:=entry.get("result",{}).get("employment",{}) as Dictionary
		if c.is_empty(): continue
		var actor: String=entry["envelope"]["actor"];var cmd:=entry["envelope"]["command"] as Dictionary
		var q:=quote(str(c.get("terms",{}).get("quote_id","")))
		if q.is_empty() or not entry["result"].get("accepted",false) or c.get("employment_action_id")!=id or c.get("job")!=q["job_id"] or not FormalLedgerState.valid_amount(c.get("workers")) or c["workers"]<1 or not e._spec["actors"].has(actor) or c["workers"]>EconomyCohortRules.labor_members(e._spec["actors"][actor]) or e._spec["actors"][actor]["skill"]<q["skill"] or not cohort_allowed(actor,q["job_id"]) or c.get("denomination")!=q["denomination"] or not c.get("terms") is Dictionary: return fail("Accepted employment lost original worker and quote")
		var expected:={"quote_id":q["id"],"version":q["version"],"wage_per_hour":q["wage_per_hour"],"hours":q["hours"],"denomination":q["denomination"],"wage_delay":q["wage_delay"],"accepted_minute":cmd["minute"],"effective_minute":cmd["minute"]}
		if cmd["kind"]=="apply":
			if cmd["payload"].get("job_id")!=q["job_id"] or cmd["payload"].get("job_quote_id")!=q["id"] or _quote_at(q["job_id"],cmd["minute"])["id"]!=q["id"] or not q["recruiting"] or cmd["minute"]>=q["valid_until"] or not _known_at(actor,q,cmd["minute"],saved): return fail("Job acceptance used unknown, stale or closed terms")
		elif cmd["kind"]=="accept_employment_terms":
			var a:=amendments.get(cmd["payload"].get("proposal_id"),{}) as Dictionary
			if a.get("acceptance_id")!=id or a.get("worker")!=actor or a.get("quote_id")!=q["id"] or not _known_at(actor,q,cmd["minute"],saved): return fail("Accepted wage terms lost consent")
			expected["effective_minute"]=a["effective_minute"]
		else: return fail("Employment source is not acceptance")
		if c["terms"]!=expected: return fail("Accepted employment wage or effective boundary changed")
		var fields: Array[String]=["job","workers","denomination","terms","employment_action_id"]
		if not e._cohort_profile(actor).is_empty():
			if not FormalLedgerState.valid_amount(c.get("labor_start")): return fail("Invalid accepted worker share start")
			fields.append("labor_start")
		if not FormalLedgerState.exact_fields(c,fields): return fail("Invalid accepted worker allocation")
	for a: Dictionary in amendments.values():
		if not valid_contract(a["old_contract"],a["worker"],saved["commands"],a["proposed_minute"]): return fail("Employment proposal rewrote old contract")
	for row: Dictionary in e._employment_ends.values():
		for c: Dictionary in e._contract_rows(row["contract"]):
			if c.has("terms") and not valid_contract(c,row["worker"],saved["commands"],saved["commands"].get(_ending_action(row),{}).get("envelope",{}).get("command",{}).get("minute",-1)): return fail("Worker exit lost original wage or shares")
	for m: Dictionary in saved["receipts"].values():
		if m.get("source")=="labor_market":
			if not valid_message(m) or m["delivery_day"]*1440>now: return fail("Recruitment information arrived before delivery")
			adopted_message(m)
	for m: Dictionary in saved["messages"]:
		if m.get("source")=="labor_market" and (not valid_message(m) or m["delivery_day"]*1440<=now): return fail("Invalid pending recruitment message")
	for actor: Variant in _reviews:
		if not actor is String or worker_policy(actor).is_empty() or not FormalLedgerState.valid_amount(_reviews[actor]) or _reviews[actor]>saved["day"]: return fail("Invalid labor review boundary")
	for job: Variant in _observations:
		var policy: Dictionary={}
		for p: Dictionary in e.config["labor_market"]["npc_policies"]:
			if p["job_id"]==job: policy=p
		if not job is String or policy.is_empty() or not _observations[job] is Array or _observations[job].size()>policy["window_days"]: return fail("Invalid finite staffing observations")
		var previous: int=-1
		for sample: Variant in _observations[job]:
			if not sample is Dictionary or not FormalLedgerState.exact_fields(sample,["day","required_hours","unfilled"]) or not FormalLedgerState.valid_amount(sample["day"]) or not FormalLedgerState.valid_amount(sample["required_hours"]) or not FormalLedgerState.valid_amount(sample["unfilled"]) or sample["day"]<=previous or sample["day"]>saved["day"] or sample["unfilled"]>sample["required_hours"]: return fail("Invalid staffing observation boundary")
			previous=sample["day"]
	ready=true
	return _validate_allocations(saved)
func _ending_action(row: Dictionary) -> String:
	for id: String in economy()._employment_ends:
		if economy()._employment_ends[id]==row: return id
	return ""
func _validate_allocations(saved: Dictionary) -> bool:
	var moments: Dictionary={};var sources: Dictionary={};var e:=economy()
	for id: String in saved["commands"]:
		var entry:=saved["commands"][id] as Dictionary;var c:=entry.get("result",{}).get("employment",{}) as Dictionary
		if c.is_empty(): continue
		sources[id]=entry["envelope"]["actor"];moments[c["terms"]["effective_minute"]]=true
	for values: Array in _ends.values():
		for end: Dictionary in values: moments[end["minute"]]=true
	for q: Dictionary in quotes.values():
		if q["status"]=="APPLIED": moments[q["effective_minute"]]=true
	for minute: int in moments:
		if minute>e._world.game_clock.total_minutes(): continue
		var occupied_jobs: Dictionary={};var spans: Dictionary={};var counts: Dictionary={}
		for id: String in sources:
			var actor: String=sources[id];var c:=employment_at(actor,id,minute,saved["commands"])
			if c.is_empty(): continue
			occupied_jobs[c["job"]]=int(occupied_jobs.get(c["job"],0))+int(c["workers"])
			counts[actor]=int(counts.get(actor,0))+1
			if counts[actor]>int(e._cohort_profile(actor).get("max_jobs",1)): return fail("Historical worker exceeds concurrent job limit")
			if not e._cohort_profile(actor).is_empty():
				var span:=Vector2i(c["labor_start"],int(c["labor_start"])+int(c["workers"]))
				if span.x<0 or span.y>EconomyCohortRules.labor_members(e._spec["actors"][actor]): return fail("Historical cohort shares exceed population")
				for other: Vector2i in spans.get(actor,[]):
					if span.x<other.y and other.x<span.y: return fail("Historical cohort employment shares overlap")
				if not spans.has(actor): spans[actor]=[]
				spans[actor].append(span)
		for job: String in occupied_jobs:
			if occupied_jobs[job]>_quote_at(job,minute)["positions"]: return fail("Historical employment exceeds quoted positions")
	return true
func validate_presence() -> bool:
	var e:=economy()
	for collection: Variant in [e._messages,e._receipts.values()]:
		for m: Dictionary in collection:
			if m.get("source")=="labor_market" and (not e.subject_active_at(m["actor"],m["contact_minute"]) or not e._service_market._resident._present_at(m["actor"],e._spec["jobs"][m["candidate"]]["place"],m["contact_minute"])): return fail("Recruitment contact lacks actual local presence")
	return true
func business_view(actor: String, firm: String, site: String) -> Dictionary:
	var e:=economy();var rows: Array[Dictionary]=[];var actions: Array[Dictionary]=[]
	for id: String in _rules:
		var j:=e._spec["jobs"][id] as Dictionary
		if j["employer"]!=firm or j["site_id"]!=site: continue
		var q:=current(id);var r:=_rules[id] as Dictionary
		var contracts: Array[Dictionary]=[]
		for worker: String in e._contracts:
			var accepted:=e._contract_for(worker,id) as Dictionary
			if not accepted.is_empty(): contracts.append({"worker":worker,"contract":accepted.duplicate(true)})
		rows.append({"contracts":contracts,"job_id":id,"current_quote":q.duplicate(true),"employed_workers":occupied(id),"vacancies":maxi(0,int(q["positions"])-occupied(id)),"bounds":r.duplicate(true),"pending_quote":str(_pending.get(id,""))})
		_add_action(actions,actor,"set_job_offer",{"job_id":id,"positions":q["positions"],"wage_per_hour":q["wage_per_hour"],"recruiting":true},"发布或续发当前未来条件 "+id)
		for delta: int in [-1,0,1]:
			var payload:={"job_id":id,"positions":q["positions"],"wage_per_hour":clampi(int(q["wage_per_hour"])+delta*int(r["wage_step"]),r["min_wage"],r["max_wage"]),"recruiting":false if delta==0 else true}
			_add_action(actions,actor,"set_job_offer",payload,("停止未来招聘 " if delta==0 else "未来空缺加薪 " if delta>0 else "未来空缺降薪 ")+id)
		for delta: int in [-1,1]:
			_add_action(actions,actor,"set_job_offer",{"job_id":id,"positions":clampi(int(q["positions"])+delta*int(r["position_step"]),occupied(id),r["max_positions"]),"wage_per_hour":q["wage_per_hour"],"recruiting":true},("增加未来名额 " if delta>0 else "减少空缺名额 ")+id)
		for worker: String in e._contracts:
			var c:=e._contract_for(worker,id) as Dictionary
			if c.is_empty(): continue
			_add_action(actions,actor,"propose_employment_terms",{"worker":worker,"job_id":id,"quote_id":q["id"]},"向 "+worker+" 提出未来工资条件（须本人同意）")
	return {"enabled":not rows.is_empty(),"jobs":rows,"actions":actions,"wage_funds_reserved":false,"contract_rule":"ACCEPTED_CONDITIONS_AND_OLD_WAGE_CLAIMS_RETAINED"}
func _add_action(rows: Array[Dictionary],actor: String,kind: String,payload: Dictionary,label: String) -> void:
	var check:=request(actor,kind,payload,"",true)
	rows.append({"kind":kind,"payload":payload,"label":label,"can_execute":check["accepted"],"reason":check["reason"]})
func worker_view(actor: String) -> Dictionary:
	var rows: Array[Dictionary]=[]
	for id: String in _active_amendments:
		var a:=amendments[id] as Dictionary
		if a["worker"]==actor and a["status"]=="OFFERED":
			var check:=_confirm(actor,{"proposal_id":id},"",true)
			rows.append({"kind":"accept_employment_terms","payload":{"proposal_id":id},"label":"同意未来工资条件 "+str(quote(a["quote_id"])["wage_per_hour"])+" / 小时","can_execute":check["accepted"],"reason":check["reason"]})
	return {"enabled":not _rules.is_empty(),"actions":rows,"employment":economy()._contracts.get(actor,{}).duplicate(true)}

func _same_fields(value: Dictionary, source: Dictionary) -> bool:
	var fields: Array[String]=[]
	fields.assign(source.keys())
	return FormalLedgerState.exact_fields(value,fields)

func estimate_rate(site: String,currency: String) -> int:
	var e:=economy();var rate: int=-1
	for id: String in e._spec["jobs"]:
		var job:=e._job(id) as Dictionary
		if job["site_id"]==site and job.get("denomination",FormalLedgerState.DENOMINATION)==currency: rate=maxi(rate,int(job["wage_per_hour"]))
	for c: Dictionary in e._all_contract_rows(e._contracts):
		var job:=contract_job(c)
		if job["site_id"]==site and job["denomination"]==currency: rate=maxi(rate,int(job["wage_per_hour"]))
	return rate

func region_summary(region: String,allowed: Dictionary) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	var result:={"effective_positions":0,"accepted_workers":0,"open_vacancies":0,"accepted_daily_payroll_by_currency":{},"basis":"CURRENT_ACCEPTED_CONTRACTS_NOT_RESERVED_FUTURE_WAGES","job_scope":"EXPLICIT_DYNAMIC_JOB_RULES"}
	for id: String in _rules:
		var j:=e._spec["jobs"][id] as Dictionary
		if (not allowed.is_empty() and not allowed.has(j["employer"])) or e._region_for(j["place"])!=region: continue
		var q:=current(id);var hired:=occupied(id)
		var open: bool=q["recruiting"] and now<q["valid_until"] and e._site_accepting(j["site_id"])
		result["effective_positions"]+=int(q["positions"]) if open else hired
		result["accepted_workers"]+=hired
		result["open_vacancies"]+=maxi(0,int(q["positions"])-hired) if open else 0
	for c: Dictionary in e._all_contract_rows(e._contracts):
		var job:=contract_job(c)
		if not controls(c["job"]) or e._region_for(job["place"])!=region or (not allowed.is_empty() and not allowed.has(job["employer"])): continue
		var pay:=result["accepted_daily_payroll_by_currency"] as Dictionary
		pay[job["denomination"]]=int(pay.get(job["denomination"],0))+int(c["workers"])*int(job["hours"])*int(job["wage_per_hour"])
	return result
func pinned_source_exists(actor: String,job: String,commands: Dictionary,minute: int) -> bool:
	for id: String in commands:
		var c:=commands[id].get("result",{}).get("employment",{}) as Dictionary
		if c.get("job")==job and not employment_at(actor,id,minute,commands).is_empty(): return true
	return false
