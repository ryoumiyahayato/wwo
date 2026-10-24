class_name EconomyCargoFulfilment
extends RefCounted
## Loss observations and agreed dispositions of existing cargo contracts.
## No cash, inventory or time authority lives here.
var losses: Dictionary = {}
var dispositions: Dictionary = {}
var notices: Dictionary = {}
var _notices_by_loss: Dictionary = {}
var _losses_by_order: Dictionary = {} # Derived finite responsibility index.
var _losses_by_shipment: Dictionary = {}
var _replacements_by_order: Dictionary = {}
var _dispositions_by_order: Dictionary = {}
var _disposition_days: Dictionary = {} # Derived subject / actual decision day.
var _open_dispositions: Dictionary = {}
var _ref: WeakRef

func bind(e: RefCounted) -> void:
	_ref = weakref(e)

func _index_loss(fact: Dictionary) -> void:
	for pair: Array in [[_losses_by_order, fact["order_id"]], [_losses_by_shipment, fact["shipment_id"]]]:
		var index := pair[0] as Dictionary
		if not index.has(pair[1]): index[pair[1]] = []
		if fact["id"] not in index[pair[1]]: index[pair[1]].append(fact["id"])

func economy() -> RefCounted:
	return _ref.get_ref()

func _index_disposition(d: Dictionary) -> void:
	var dates: Array[int] = [int(d["minute"])/1440]
	for proof: Dictionary in d["confirmed"].values():
		var date := int(proof["minute"])/1440
		if not dates.has(date): dates.append(date)
	if int(d["executed_minute"]) >= 0 and not dates.has(int(d["executed_minute"])/1440): dates.append(int(d["executed_minute"])/1440)
	for subject: String in d["parties"]:
		if not _disposition_days.has(subject): _disposition_days[subject] = {}
		if not _open_dispositions.has(subject): _open_dispositions[subject] = {}
		for date: int in dates:
			if not _disposition_days[subject].has(date): _disposition_days[subject][date] = {}
			_disposition_days[subject][date][d["id"]] = true
		if d["status"] == "EXECUTED": _open_dispositions[subject].erase(d["id"])
		else: _open_dispositions[subject][d["id"]] = true
	if economy()._costs.enabled: economy()._costs._scores_cache.clear()

## Recent decisions and all still-open responsibilities. This is a query index,
## never a second payable ledger, and is rebuilt from the original contracts.
func cost_dispositions(subject: String, since_day: int) -> Array[Dictionary]:
	var ids: Dictionary = _open_dispositions.get(subject, {}).duplicate()
	for date: int in range(since_day, economy().day+1):
		for id: String in _disposition_days.get(subject, {}).get(date, {}): ids[id] = true
	var ordered: Array = ids.keys()
	ordered.sort()
	var result: Array[Dictionary] = []
	for id: String in ordered: result.append(dispositions[id])
	return result

func controls(actor: String, subject: String, financial: bool = false) -> bool:
	var e := economy()
	if subject == actor and e._actors.has(actor): return true
	for carrier: Dictionary in e.config.get("carriers", []):
		if carrier["id"] == subject:
			var controller := str(carrier.get("settlement_controller" if financial else "custody_controller", ""))
			return not controller.is_empty() and (controller == actor or (e._spec["firms"].has(controller) and e._manager(actor, controller)))
	var firm: String = e._owner(subject)
	if not e._spec["firms"].has(firm) or not e._manager(actor, firm): return false
	if financial and actor != firm: return e._spec["firms"][firm].get("cargo_settlement_controller", "") == actor
	return true

## Specific domain authorization. Organization remains the grant/delegation owner.
func _host_organization(subject: String) -> String:
	var e := economy()
	var firm: Dictionary = e._spec["firms"].get(e._owner(subject), {})
	if not firm.is_empty(): return str(firm.get("host_organization_id", ""))
	for carrier: Dictionary in e.config.get("carriers", []):
		if carrier["id"] == subject: return str(carrier.get("host_organization_id", ""))
	return ""

func _authorize(actor: String, subject: String, operation: String, target: String, place: String, category: String, amount: int, contexts: Dictionary) -> Dictionary:
	var e := economy()
	var organization := _host_organization(subject)
	if organization.is_empty():
		return {"ok": controls(actor, subject, true), "proof": {"actor":actor, "minute":e._world.game_clock.total_minutes()}}
	var context: Variant = contexts.get(subject+"|"+operation+"|"+category, contexts.get(subject+"|"+operation, {}))
	var person: String = e.firm_manager_at(actor, e._world.game_clock.total_minutes()) if e._spec["firms"].has(actor) else actor
	if not context is Dictionary or context.get("person_id") != person or context.get("represented_organization_id") != organization or e._world.authorization_check == null: return {"ok":false,"reason":"MISSING_SPECIFIC_CARGO_AUTHORIZATION:"+subject+":"+operation}
	var proof: Dictionary = e._world.authorization_check.resolve_authority(context, operation, AuthorizationCheck.STAGE_DOMAIN_EXECUTION, target, place, category, float(amount), e._world.game_clock.current_hour(), str(context.get("decision_id", "")))
	if proof.get("status") != AuthorizationCheck.ALLOWED: return {"ok":false,"reason":"CARGO_AUTHORIZATION:"+str(proof.get("reason", "DENIED"))}
	# Financial/domain permissions must come from an actual grant, not a broad position capability.
	if not e._world.organization_state._authority_grants.has(proof.get("authority_id")): return {"ok":false,"reason":"CARGO_REQUIRES_SCOPED_ROOT_GRANT"}
	proof["grant_at_adoption"] = e._world.organization_state.authority_grant(proof["authority_id"])
	proof["organization_revision"] = e._world.organization_state._revision
	proof["appointment_at_adoption"] = e._world.organization_state.appointment(context["acting_organization_id"],context["appointment_id"]) if not str(context["appointment_id"]).is_empty() else {}
	proof["membership_at_adoption"] = e._world.organization_state.is_member(context["acting_organization_id"],person)
	proof["delegations_at_adoption"] = {}
	for source_id: String in proof["basis_chain"]:
		if source_id!=proof["authority_id"]: proof["delegations_at_adoption"][source_id]=e._world.organization_state.delegation(source_id)
	proof.merge({"stage":AuthorizationCheck.STAGE_DOMAIN_EXECUTION,"actor":actor,"person_id":person,"subject":subject,"minute":e._world.game_clock.total_minutes(),"operation":operation,"target":target,"place":place,"category":category,"amount":amount,"context":context.duplicate(true)})
	return {"ok":true,"proof":proof}

func _decision_requirements(terms: Dictionary, party: String, order: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mode := str(terms["mode"])
	var currency := str(terms.get("payment", {}).get("denomination", order["denomination"]))
	result.append({"operation":"economy.cargo."+mode.to_lower(),"target":order["id"],"place":order["from_place_id"],"category":"cargo:"+mode.to_lower()+":"+currency,"amount":int(terms.get("payment", {}).get("amount", terms["quantity"]))})
	if mode == "REPLACE":
		var costs: Dictionary = {}
		for fee: Dictionary in terms["fees"]:
			if fee["payer"] != party: continue
			var key := str(fee["edge_id"])+"|"+str(fee["denomination"])
			costs[key] = int(costs.get(key, 0))+int(fee["amount"])
		for key: String in costs:
			result.append({"operation":"economy.procure","target":economy()._all_routes()[key.get_slice("|",0)]["carrier"],"place":order["from_place_id"],"category":"freight:"+key.get_slice("|",0),"amount":costs[key]})
	return result

func _decision_confirmation(actor: String, party: String, terms: Dictionary, order: Dictionary, contexts: Dictionary) -> Dictionary:
	if _host_organization(party).is_empty(): return {"actor":actor,"minute":economy()._world.game_clock.total_minutes()} if controls(actor,party,true) else {}
	var proofs: Array[Dictionary] = []
	for requirement: Dictionary in _decision_requirements(terms, party, order):
		var result := _authorize(actor, party, requirement["operation"], requirement["target"], requirement["place"], requirement["category"], requirement["amount"], contexts)
		if not result["ok"]: return {}
		proofs.append(result["proof"])
	return {"actor":actor,"minute":economy()._world.game_clock.total_minutes(),"authority_proofs":proofs}

## Read only current grants for the involved organization and exact action scope.
func _available_context(actor: String, party: String, requirement: Dictionary, root: String="") -> Dictionary:
	var e:=economy()
	var organization:=_host_organization(party)
	if organization.is_empty(): return {}
	var person: String=e.firm_manager_at(actor,e._world.game_clock.total_minutes()) if e._spec["firms"].has(actor) else actor
	for grant: Dictionary in e._world.organization_state._authority_grants.values():
		if grant["represented_entity"]!=organization or grant["operation"]!=requirement["operation"] or (not root.is_empty() and grant["authority_id"]!=root): continue
		var holder:=grant["holder"] as Dictionary
		var candidates: Array[Dictionary]=[]
		if holder["kind"]=="person" and holder["person_id"]==person: candidates.append(OrganizationState.acting_context(person,organization,organization,grant["authority_id"]))
		elif holder["kind"]=="membership": candidates.append(OrganizationState.acting_context(person,organization,organization,grant["authority_id"],"",true))
		elif holder["kind"]=="position":
			for id: String in e._world.organization_state.appointment_ids(organization):
				var assignment: Dictionary=e._world.organization_state.appointment(organization,id)
				if assignment["person_id"]==person and assignment["position_id"]==holder["local_id"]: candidates.append(OrganizationState.acting_context(person,organization,organization,grant["authority_id"],id))
		for delegation: Dictionary in e._world.organization_state._delegations.values():
			if delegation["recipient_person_id"]!=person: continue
			var effective: Dictionary=e._world.authorization_check._effective_delegation(delegation["delegation_id"] ,e._world.game_clock.current_hour(),{})
			if effective.get("source_authority_id")==grant["authority_id"]: candidates.append(OrganizationState.acting_context(person,organization,organization,grant["authority_id"],"",false,"",delegation["delegation_id"]))
		for context: Dictionary in candidates:
			var values: Dictionary={party+"|"+requirement["operation"]+"|"+requirement["category"]:context}
			if _authorize(actor,party,requirement["operation"],requirement["target"],requirement["place"],requirement["category"],requirement["amount"],values)["ok"]: return context
	return {}

func action_authorizations(actor: String, loss_id: String, mode: String, quantity_value: int, disposition_id: String="", execution: bool=false) -> Dictionary:
	var e:=economy()
	var d: Dictionary=dispositions.get(disposition_id,{})
	if not d.is_empty(): loss_id=d["loss_id"]
	var loss: Dictionary=losses.get(loss_id,{})
	var order: Dictionary=e._orders.get(loss.get("order_id",""),{})
	if order.is_empty(): return {}
	var terms: Dictionary=d.get("terms",{"mode":mode,"quantity":quantity_value,"fees":[]})
	var parties: Array=d.get("parties",[order["buyer"],order["seller"]])
	var result: Dictionary={}
	for party: String in parties:
		var requirements:=_decision_requirements(terms,party,order)
		if execution and terms["mode"] in ["REFUND","DAMAGES"] and terms["payment"]["payer"]==party:
			requirements.append({"operation":"economy.cargo.pay","target":d["id"],"place":order["from_place_id"],"category":"cargo:"+str(terms["mode"]).to_lower()+":"+str(terms["payment"]["denomination"]),"amount":terms["payment"]["amount"]})
		for r: Dictionary in requirements:
			var root := ""
			if r["operation"]=="economy.procure":
				for fee: Dictionary in terms.get("fees",[]):
					if fee["payer"]!=party or r["category"]!="freight:"+str(fee["edge_id"]): continue
					for budget: Dictionary in e._budgets.rules:
						if budget["subject"]==e._budgets.subject_aliases.get(party,party) and budget["denomination"]==fee["denomination"] and budget["category"]==r["category"] and budget["basis"]!="EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY" and e._world.game_clock.total_minutes()>=budget["start_minute"] and e._world.game_clock.total_minutes()<budget["end_minute"]: root=budget["root_authority"]
			var context:=_available_context(actor,party,r,root)
			if not context.is_empty(): result[party+"|"+r["operation"]+"|"+r["category"]]=context
	return result

func _saved_authority(proof: Variant) -> bool:
	var e := economy()
	if not proof is Dictionary or not proof.get("context") is Dictionary or proof.get("status") != AuthorizationCheck.ALLOWED or not FormalLedgerState.valid_amount(proof.get("minute")) or not FormalLedgerState.valid_amount(proof.get("amount")) or proof["minute"] > e._world.game_clock.total_minutes(): return false
	if not proof.get("actor") is String or not proof.get("person_id") is String or proof.get("stage",AuthorizationCheck.STAGE_DOMAIN_EXECUTION)!=AuthorizationCheck.STAGE_DOMAIN_EXECUTION: return false
	if e._spec["firms"].has(proof["actor"]) and e.firm_manager_at(proof["actor"],proof["minute"])!=proof["person_id"]: return false
	if not e._spec["firms"].has(proof["actor"]) and proof["actor"]!=proof["person_id"]: return false
	var grant: Dictionary = e._world.organization_state.authority_grant(str(proof.get("authority_id", "")))
	if grant.is_empty() or grant.get("represented_entity") != _host_organization(str(proof.get("subject", ""))) or grant.get("operation") != proof.get("operation"): return false
	var historical: Variant = proof.get("grant_at_adoption",grant)
	if not historical is Dictionary: return false
	var live_terms := grant.duplicate(true)
	var original_terms: Dictionary = historical.duplicate(true)
	live_terms.erase("revoked_at")
	original_terms.erase("revoked_at")
	if live_terms!=original_terms or not e._world.authorization_check._grant_time_valid(historical,int(proof["minute"])/60): return false
	if not e._world.authorization_check._grant_time_valid(grant,int(proof["minute"])/60):
		if grant.get("revoked_at")!=int(proof["minute"])/60 or not FormalLedgerState.valid_amount(proof.get("organization_revision")) or proof["organization_revision"]>=e._world.organization_state._revision: return false
	if proof["context"].get("person_id") != proof.get("person_id") or proof["context"].get("represented_organization_id") != grant["represented_entity"]: return false
	var delegated := str(proof["context"].get("delegation_id", ""))
	if not delegated.is_empty():
		var chain: Variant=proof.get("basis_chain")
		var originals: Variant=proof.get("delegations_at_adoption",{})
		if not chain is Array or chain.size()<2 or chain[0]!=proof["authority_id"] or chain.back()!=delegated or not originals is Dictionary: return false
		var prior:=str(proof["authority_id"])
		for i: int in range(1,chain.size()):
			var original: Variant=originals.get(chain[i])
			var current: Dictionary=e._world.organization_state.delegation(chain[i])
			if not original is Dictionary or current.is_empty() or original.get("source_id")!=prior or original.get("source_kind")!=("authority" if i==1 else "delegation"): return false
			var before: Dictionary=original.duplicate(true)
			var after:=current.duplicate(true)
			before.erase("revoked_at"); after.erase("revoked_at")
			if before!=after or not e._world.authorization_check._delegation_time_valid(original,int(proof["minute"])/60) or not e._world.authorization_check._scope_matches(original,proof["target"],proof["place"],proof["category"],float(proof["amount"])): return false
			if not e._world.authorization_check._delegation_time_valid(current,int(proof["minute"])/60) and (current["revoked_at"]!=int(proof["minute"])/60 or proof.get("organization_revision",e._world.organization_state._revision)>=e._world.organization_state._revision): return false
			prior=str(chain[i])
		return originals[delegated]["recipient_person_id"]==proof["person_id"] and e._world.authorization_check._scope_matches(grant,proof["target"],proof["place"],proof["category"],float(proof["amount"]))
	if proof.get("basis_chain")!=[proof["authority_id"]] or not e._world.authorization_check._scope_matches(grant,proof["target"],proof["place"],proof["category"],float(proof["amount"])): return false
	if e._world.authorization_check._holder_matches_context(grant["holder"],proof["context"]): return true
	var assignment: Variant=proof.get("appointment_at_adoption",{})
	if grant["holder"]["kind"]=="position": return assignment is Dictionary and assignment.get("appointment_id")==proof["context"]["appointment_id"] and assignment.get("person_id")==proof["person_id"] and assignment.get("position_id")==grant["holder"]["local_id"] and grant["holder"]["organization_id"]==proof["context"]["acting_organization_id"]
	return grant["holder"]["kind"]=="membership" and proof.get("membership_at_adoption",false) and grant["holder"]["organization_id"]==proof["context"]["acting_organization_id"]

func request(actor: String, kind: String, p: Dictionary, id: String) -> Dictionary:
	match kind:
		"report_cargo_loss": return _report(actor, p, id)
		"confirm_cargo_loss": return _confirm_loss(actor, p)
		"notify_cargo_loss": return _notify(actor, p, id)
		"propose_cargo_disposition": return _propose(actor, p, id)
		"confirm_cargo_disposition": return _confirm_disposition(actor, p)
		"execute_cargo_disposition": return _execute(actor, p)
	return _result(false, "UNKNOWN_CARGO_ACTION")

func _notify(actor: String, p: Dictionary, id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(p, ["loss_id", "recipient", "delivery_minute", "basis"]) or not losses.has(p["loss_id"]) or not FormalLedgerState.valid_amount(p["delivery_minute"]) or p["delivery_minute"] < economy()._world.game_clock.total_minutes() or not p["basis"] is String or p["basis"].is_empty(): return _result(false, "NOTICE_REQUIRES_EXPLICIT_DELIVERY_TIME_AND_BASIS")
	var f := losses[p["loss_id"]] as Dictionary
	var order := economy()._orders.get(f["order_id"], {}) as Dictionary
	var service: Dictionary=economy()._service_market.contracts.get(f.get("service_id",""),{})
	var recipients: Array=[]
	if not order.is_empty(): recipients=[order["buyer"],order["seller"]]
	elif not service.is_empty(): recipients=[service["client"],service["provider"]]
	if not f["parties"].any(func(party: String) -> bool: return controls(actor, party)) or p["recipient"] not in recipients: return _result(false, "NOT_AUTHORIZED_CONTRACT_LOSS_NOTICE")
	notices[id] = {"id": id, "loss_id": f["id"], "sender": actor, "recipient": p["recipient"], "sent_minute": economy()._world.game_clock.total_minutes(), "delivery_minute": p["delivery_minute"], "basis": p["basis"]}
	if not _notices_by_loss.has(f["id"]): _notices_by_loss[f["id"]] = []
	_notices_by_loss[f["id"]].append(id)
	return {"accepted": true, "reason": "LOSS_NOTICE_SCHEDULED", "notice_id": id}

func knows_loss(actor: String, id: String) -> bool:
	var f := losses.get(id, {}) as Dictionary
	if f.is_empty(): return false
	for party: String in f["confirmed"]:
		if controls(actor, party): return true
	for notice_id: String in _notices_by_loss.get(id, []):
		var n := notices[notice_id] as Dictionary
		if n["loss_id"] == id and controls(actor, n["recipient"]) and int(n["delivery_minute"]) <= economy()._world.game_clock.total_minutes(): return true
	return false

func replacement_references(order_id: String, rows: Array[Dictionary], portions: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id: String in _replacements_by_order.get(order_id, []):
		var d := dispositions[id] as Dictionary
		var roots: Dictionary = {}
		for row: Dictionary in d["replacement_portions"]: roots[row["portion_id"]] = true
		for row: Dictionary in rows:
			var parent := str(row["portion_id"])
			while portions.has(parent):
				if roots.has(parent):
					if d["id"] not in result: result.append(d["id"])
					break
				parent = str(portions[parent]["parent_portion_id"])
	return result

func _report(actor: String, p: Dictionary, id: String) -> Dictionary:
	var e := economy()
	if not FormalLedgerState.exact_fields(p, ["portions", "basis", "process"]) or not p["portions"] is Array or not p["basis"] is String or p["basis"].is_empty() or not p["process"] is String or p["process"].is_empty(): return _result(false, "LOSS_REQUIRES_SOURCE_AND_PROCESS")
	var rows: Array[Dictionary] = []
	for raw: Variant in p["portions"]:
		if not raw is Dictionary: return _result(false, "INVALID_LOSS_PORTIONS")
		rows.append(raw)
	if not e._lots.ready(rows): return _result(false, "LOSS_LACKS_ACTUAL_REMAINDER")
	var first := e._lots.portions[rows[0]["portion_id"]] as Dictionary
	var location := str(first["location"])
	var service_id := location.trim_prefix("SERVICE|") if location.begins_with("SERVICE|") else str(first["reserved_for"]) if e._service_market.contracts.has(first["reserved_for"]) else ""
	var shipment_id := location.trim_prefix("CARGO|") if location.begins_with("CARGO|") else ""
	var order_id := str(e._shipments[shipment_id]["order_id"]) if not shipment_id.is_empty() and e._shipments.has(shipment_id) else str(first["reserved_for"])
	if location.contains("|FREIGHT|"): order_id = location.get_slice("|FREIGHT|", 1)
	if not service_id.is_empty(): order_id=""
	var quantity := 0
	for row: Dictionary in rows:
		var item := e._lots.portions[row["portion_id"]] as Dictionary
		for key: String in ["location", "owner", "custodian", "good", "unit", "place_id", "reserved_for"]:
			if item[key] != first[key]: return _result(false, "LOSS_REQUIRES_ONE_CUSTODY_RESPONSIBILITY")
		if int(row["quantity"]) > FormalLedgerState.MAX_AMOUNT-quantity: return _result(false, "LOSS_QUANTITY_BOUNDS")
		quantity += int(row["quantity"])
	if not controls(actor, first["owner"]) and not controls(actor, first["custodian"]): return _result(false, "NOT_LOSS_OWNER_OR_CUSTODIAN")
	if not service_id.is_empty() and not e._service_market.loss_ready(service_id,quantity): return _result(false,"LOSS_HAS_NO_CURRENT_WAREHOUSE_CUSTODY")
	if not shipment_id.is_empty() and not e._shipments.has(shipment_id): return _result(false, "MISSING_LOSS_SHIPMENT")
	var parties: Array[String] = []
	parties.append(first["owner"])
	if first["custodian"] != first["owner"]: parties.append(first["custodian"])
	var confirmed: Dictionary = {}
	for party: String in parties:
		if controls(actor, party): confirmed[party] = {"actor": actor, "minute": e._world.game_clock.total_minutes()}
	losses[id] = {"id": id, "rows": rows, "quantity": quantity, "good": first["good"], "unit": first["unit"], "owner": first["owner"], "custodian": first["custodian"], "location": location, "place_id": first["place_id"], "shipment_id": shipment_id, "order_id": order_id, "stage": e._shipments.get(shipment_id, {}).get("stage", "STORAGE"), "leg_index": e._shipments.get(shipment_id, {}).get("leg_index", -1), "observed_minute": e._world.game_clock.total_minutes(), "basis": p["basis"], "process": p["process"], "parties": parties, "confirmed": confirmed, "status": "OBSERVED", "adopted_minute": -1, "resolved": 0, "personal_fact": {}}
	if not service_id.is_empty(): losses[id]["service_id"]=service_id
	_index_loss(losses[id])
	return _adopt_loss(losses[id])

func _confirm_loss(actor: String, p: Dictionary) -> Dictionary:
	if not FormalLedgerState.exact_fields(p, ["loss_id"]) or not losses.has(p["loss_id"]): return _result(false, "UNKNOWN_LOSS")
	var fact := losses[p["loss_id"]] as Dictionary
	var permitted := false
	for party: String in fact["parties"]:
		if controls(actor, party):
			permitted = true
			if not fact["confirmed"].has(party): fact["confirmed"][party] = {"actor": actor, "minute": economy()._world.game_clock.total_minutes()}
	if not permitted: return _result(false, "NOT_LOSS_CONFIRMING_PARTY")
	return _adopt_loss(fact)

func _adopt_loss(fact: Dictionary) -> Dictionary:
	var e := economy()
	if fact["status"] == "ADOPTED": return {"accepted": true, "reason": "ALREADY_ADOPTED", "loss_id": fact["id"]}
	if not fact["confirmed"].has(fact["custodian"]): return {"accepted": true, "reason": "AWAITING_ACTUAL_CUSTODIAN_CONFIRMATION", "loss_id": fact["id"]}
	var rows: Array[Dictionary] = []
	rows.assign(fact["rows"])
	if not e._lots.ready(rows): return _result(false, "LOSS_SOURCE_CHANGED_BEFORE_ADOPTION")
	for row: Dictionary in rows:
		var portion := e._lots.portions[row["portion_id"]] as Dictionary
		for key: String in ["owner", "custodian", "location", "place_id"]:
			if portion[key] != fact[key]: return _result(false, "LOSS_CUSTODY_CHANGED_BEFORE_ADOPTION")
	var prepared: Dictionary = {}
	var personal: Dictionary = {}
	if e._declared_named(fact["owner"]):
		var custody := str(fact["location"]).trim_prefix("PERSON|"+str(fact["owner"])+"|")
		if not str(fact["shipment_id"]).is_empty(): custody = "FREIGHT|"+str(fact["order_id"])
		personal = {"person_id": fact["owner"], "commodity_id": "native:"+str(fact["good"]), "quantity": fact["quantity"], "allocations": e._personal_allocations_for_portions(fact["owner"], fact["good"], rows, custody), "source_id": fact["id"], "effective_minute": e._world.game_clock.total_minutes()}
		prepared = e._world.personal_economy_state.prepare_native_loss(personal)
		if prepared.is_empty(): return _result(false, "LOSS_PERSONAL_PARTITIONS_CHANGED")
	if not e._lots.record_loss(fact["id"], rows, e._world.game_clock.total_minutes(), fact["basis"], fact["process"]): return _result(false, "LOSS_ADOPTION_FAILED")
	if fact.has("service_id"): e._service_market.adopted_loss(fact["service_id"],fact["id"],rows,fact["quantity"])
	if not prepared.is_empty(): e._world.personal_economy_state.adopt_native_change(prepared)
	fact["personal_fact"] = personal
	fact["status"] = "ADOPTED"
	fact["adopted_minute"] = e._world.game_clock.total_minutes()
	if not str(fact["shipment_id"]).is_empty():
		var cargo := e._shipments[fact["shipment_id"]] as Dictionary
		var order := e._orders[fact["order_id"]] as Dictionary
		e._shared.release_storage(fact["shipment_id"],fact["good"],fact["quantity"],"loss:"+str(fact["id"]))
		cargo["quantity"] -= int(fact["quantity"])
		order["transit"] -= int(fact["quantity"])
		order["pending"] += int(fact["quantity"])
		e._refresh_loss_pending(order)
	return {"accepted": true, "reason": "LOSS_ADOPTED_CONTRACT_RETAINED", "loss_id": fact["id"], "quantity": fact["quantity"]}

func unresolved(order_id: String) -> int:
	var total := 0
	for id: String in _losses_by_order.get(order_id, []):
		var fact := losses[id] as Dictionary
		if fact["order_id"] == order_id and fact["status"] == "ADOPTED": total += int(fact["quantity"])-int(fact["resolved"])
	return total

func cargo_loss(shipment_id: String) -> int:
	var total := 0
	for id: String in _losses_by_shipment.get(shipment_id, []):
		var fact := losses[id] as Dictionary
		if fact["shipment_id"] == shipment_id and fact["status"] == "ADOPTED": total += int(fact["quantity"])
	return total

func site_loss(order_id: String) -> int:
	var total := 0
	for id: String in _losses_by_order.get(order_id, []):
		var fact := losses[id] as Dictionary
		if fact["order_id"] == order_id and fact["status"] == "ADOPTED" and str(fact["location"]).begins_with("SITE|"): total += int(fact["quantity"])
	return total

func _propose(actor: String, p: Dictionary, id: String) -> Dictionary:
	var e := economy()
	var contexts: Variant = p.get("authorizations", {})
	if not contexts is Dictionary: return _result(false, "INVALID_CARGO_AUTHORIZATION_CONTEXTS")
	p = p.duplicate(true)
	p.erase("authorizations")
	if not EconomySliceConfig._fields(p, ["loss_id", "mode", "quantity", "basis"], ["fees", "payment"]) or not losses.has(p["loss_id"]) or p["mode"] not in ["KEEP", "REPLACE", "RELEASE", "REFUND", "DAMAGES"] or not p["basis"] is String or p["basis"].is_empty() or not FormalLedgerState.valid_amount(p["quantity"]) or int(p["quantity"]) <= 0: return _result(false, "INVALID_DISPOSITION_TERMS")
	var loss := losses[p["loss_id"]] as Dictionary
	if loss.has("service_id"): return _result(false,"WAREHOUSE_LOSS_HAS_NO_SELECTED_SERVICE_RESTITUTION_TERMS")
	if not knows_loss(actor, p["loss_id"]): return _result(false, "NO_RECEIVED_LOSS_INFORMATION")
	var order := e._orders.get(loss["order_id"], {}) as Dictionary
	if loss["status"] != "ADOPTED" or order.is_empty(): return _result(false, "NO_ADOPTED_CONTRACT_SHORTFALL")
	var parties: Array[String] = []
	parties.append(order["buyer"])
	if order["seller"] not in parties: parties.append(order["seller"])
	
	if p["mode"] in ["REPLACE", "RELEASE", "KEEP"] and int(p["quantity"]) > int(loss["quantity"])-int(loss["resolved"]): return _result(false, "SHORTFALL_ALREADY_COVERED")
	if p["mode"] == "REPLACE":
		if not p.get("fees") is Array or p["fees"].size() > 32: return _result(false, "REPLACEMENT_REQUIRES_EXPLICIT_FREIGHT_TERMS")
		for leg: Dictionary in order["route_legs"]:
			var carrier := str(e._all_routes()[leg["edge_id"]]["carrier"])
			if not carrier.is_empty() and carrier not in parties: parties.append(carrier)
		for fee: Variant in p["fees"]:
			if not fee is Dictionary or not FormalLedgerState.exact_fields(fee, ["payer", "recipient", "denomination", "amount", "edge_id", "basis", "payment_milestone"]) or fee.get("payment_milestone") != "REPLACEMENT_ACCEPTANCE" or fee["edge_id"] not in order["route_legs"].map(func(leg: Dictionary) -> String: return leg["edge_id"]) or not e._all_routes().has(fee["edge_id"]) or e._all_routes()[fee["edge_id"]]["carrier"] != fee["recipient"] or not _valid_payment(fee): return _result(false, "INVALID_REPLACEMENT_FEE")
			for party: String in [fee["payer"], fee["recipient"]]:
				if party not in parties: parties.append(party)
	if p["mode"] in ["REFUND", "DAMAGES"]:
		var payment_fields: Array[String] = ["payer", "recipient", "denomination", "amount", "basis"]
		if p["mode"] == "REFUND": payment_fields.append("original_transaction_id")
		if not p.get("payment") is Dictionary or not FormalLedgerState.exact_fields(p["payment"], payment_fields) or not _valid_payment(p["payment"]): return _result(false, "PAYMENT_REQUIRES_AMOUNT_CURRENCY_AND_PARTIES")
		var pay := p["payment"] as Dictionary
		for party: String in [pay["payer"], pay["recipient"]]:
			if party not in parties: parties.append(party)
		if p["mode"] == "REFUND" and not _refund_available(pay, loss["order_id"]): return _result(false, "REFUND_LACKS_ORIGINAL_PAYMENT_REMAINDER")
	var confirmed: Dictionary = {}
	for party: String in parties:
		var proof := _decision_confirmation(actor, party, p, order, contexts)
		if not proof.is_empty(): confirmed[party] = proof
	if confirmed.is_empty(): return _result(false, "NO_SPECIFIC_CARGO_SETTLEMENT_AUTHORITY")
	dispositions[id] = {"id": id, "loss_id": loss["id"], "terms": p.duplicate(true), "parties": parties, "confirmed": confirmed, "status": "AGREED" if confirmed.size() == parties.size() else "PROPOSED", "minute": e._world.game_clock.total_minutes(), "executed_minute": -1, "payments": [], "replacement_portions": [], "custody_fact": {}}
	_index_disposition(dispositions[id])
	if not _dispositions_by_order.has(order["id"]): _dispositions_by_order[order["id"]] = []
	_dispositions_by_order[order["id"]].append(id)
	return {"accepted": true, "reason": "DISPOSITION_PROPOSED", "disposition_id": id}

func _valid_payment(p: Dictionary) -> bool:
	var e := economy()
	return p.get("payer") is String and p.get("recipient") is String and p["payer"] != p["recipient"] and not e._account(p["payer"], str(p.get("denomination", ""))).is_empty() and not e._account(p["recipient"], str(p.get("denomination", ""))).is_empty() and FormalLedgerState.currency_id(p.get("denomination")) and FormalLedgerState.valid_amount(p.get("amount")) and int(p["amount"]) > 0 and p.get("basis") is String and not p["basis"].is_empty()

func _refund_available(p: Dictionary, order_id: String, own: String = "") -> bool:
	var e := economy()
	var tx: Dictionary = e._world.ledger_state.transaction(str(p.get("original_transaction_id", "")))
	if tx.is_empty() or tx["kind"] not in ["goods", "freight"] or tx["reference_id"] != order_id or tx["from_account_id"] != e._account(p["recipient"], p["denomination"]) or tx["to_account_id"] != e._account(p["payer"], p["denomination"]): return false
	var used := 0
	for id: String in _dispositions_by_order.get(order_id, []):
		var d := dispositions[id] as Dictionary
		if d["id"] == own or d["terms"]["mode"] != "REFUND": continue
		if d["terms"]["payment"].get("original_transaction_id") == p.get("original_transaction_id"): used += int(d["terms"]["payment"]["amount"])
	return int(p["amount"]) <= int(tx["amount"])-used

func _confirm_disposition(actor: String, p: Dictionary) -> Dictionary:
	if not EconomySliceConfig._fields(p, ["disposition_id"], ["authorizations"]) or not p.get("authorizations", {}) is Dictionary or not dispositions.has(p["disposition_id"]): return _result(false, "UNKNOWN_DISPOSITION")
	var d := dispositions[p["disposition_id"]] as Dictionary
	var allowed := false
	for party: String in d["parties"]:
		var proof := _decision_confirmation(actor, party, d["terms"], economy()._orders[losses[d["loss_id"]]["order_id"]], p.get("authorizations", {}))
		if not proof.is_empty():
			allowed = true
			if not d["confirmed"].has(party): d["confirmed"][party] = proof
	if not allowed: return _result(false, "NO_CARGO_SETTLEMENT_AUTHORITY")
	if d["status"] == "PROPOSED" and d["confirmed"].size() == d["parties"].size(): d["status"] = "AGREED"
	_index_disposition(d)
	return {"accepted": true, "reason": d["status"], "disposition_id": d["id"]}

func _execute(actor: String, p: Dictionary) -> Dictionary:
	if not EconomySliceConfig._fields(p, ["disposition_id"], ["authorizations"]) or not p.get("authorizations", {}) is Dictionary or not dispositions.has(p["disposition_id"]): return _result(false, "UNKNOWN_DISPOSITION")
	var e := economy()
	var d := dispositions[p["disposition_id"]] as Dictionary
	if not d["parties"].any(func(party: String) -> bool: return controls(actor, party) or not _decision_confirmation(actor, party, d["terms"], e._orders[losses[d["loss_id"]]["order_id"]], p.get("authorizations", {})).is_empty()): return _result(false, "NOT_DISPOSITION_PARTY")
	if d["status"] == "EXECUTED": return {"accepted": true, "reason": "ALREADY_EXECUTED", "disposition_id": d["id"]}
	if d["confirmed"].size() != d["parties"].size(): return _result(false, "MISSING_COUNTERPARTY_CONSENT")
	var loss := losses[d["loss_id"]] as Dictionary
	var order := e._orders[loss["order_id"]] as Dictionary
	var terms := d["terms"] as Dictionary
	var q := int(terms["quantity"])
	var minute: int = e._world.game_clock.total_minutes()
	if terms["mode"] in ["REPLACE", "RELEASE", "KEEP"] and q > int(loss["quantity"])-int(loss["resolved"]): return _result(false, "SHORTFALL_ALREADY_COVERED")
	if terms["mode"] == "REPLACE":
		var personal: bool = order["kind"] == "PERSONAL_FREIGHT"
		var source := "PERSON|"+str(order["buyer"])+"|STORED|"+str(order["from_place_id"]) if personal else "SITE|"+str(order["seller_site"])
		var rows: Array[Dictionary] = e._lots.selection(source, order["good"], q)
		if not e._lots.ready(rows): return _result(false, "NO_NEW_ACTUAL_REPLACEMENT_STOCK")
		var prepared: Dictionary = {}
		var custody: Dictionary = {}
		if personal:
			if not e._at_place(order["buyer"], order["from_place_id"]): return _result(false, "PERSONAL_REPLACEMENT_OWNER_NOT_AT_SOURCE")
			custody = e._custody_fact(order["buyer"], order["good"], q, "STORED|"+str(order["from_place_id"]), "FREIGHT|"+str(order["id"]), d["id"], "freight_replace")
			rows = e._physical_person_rows(order["buyer"], order["good"], custody["allocations"])
			if not e._lots.ready(rows): return _result(false, "NO_NEW_ACTUAL_REPLACEMENT_STOCK")
			prepared = e._world.personal_economy_state.prepare_native_custody(custody)
			if prepared.is_empty(): return _result(false, "PERSONAL_REPLACEMENT_SOURCE_PARTITIONS_MISSING")
		var fees: Dictionary = _prepare_fees(d, minute, actor, p.get("authorizations", {}))
		if not fees.get("ok", false): return _result(false, str(fees.get("reason", "FEE_PREPARATION_FAILED")))
		if not fees["legs"].is_empty() and not e._world.ledger_state.batch_payment("cargo:"+str(d["id"]), fees["legs"], minute): return _result(false, "REPLACEMENT_FEE_UNFUNDED")
		_adopt_fees(d, fees)
		d["execution_authorizations"] = fees["authorizations"]
		var reserved: Array[Dictionary] = e._lots.move(rows, "PERSON|"+str(order["buyer"])+"|FREIGHT|"+str(order["id"]) if personal else "SITE|"+str(order["seller_site"]), order["from_place_id"], minute, "", "", "" if personal else order["id"])
		if personal: e._world.personal_economy_state.adopt_native_change(prepared)
		d["custody_fact"] = custody
		assert(not reserved.is_empty())
		d["replacement_portions"] = rows
		loss["resolved"] += q
	elif terms["mode"] == "RELEASE":
		if not e._release_loss_obligation(order, q, d["id"]): return _result(false, "RELEASE_ADOPTION_FAILED")
		loss["resolved"] += q
	elif terms["mode"] in ["REFUND", "DAMAGES"]:
		var pay := terms["payment"] as Dictionary
		if terms["mode"] == "REFUND" and not _refund_available(pay, order["id"], d["id"]): return _result(false, "REFUND_REMAINDER_CHANGED")
		var authority := _authorize(actor, pay["payer"], "economy.cargo.pay", d["id"], order["from_place_id"], "cargo:"+str(terms["mode"]).to_lower()+":"+str(pay["denomination"]), pay["amount"], p.get("authorizations", {}))
		if not authority["ok"]: return _result(false, str(authority.get("reason", "NO_PAYMENT_EXECUTION_AUTHORITY")))
		var leg := {"transaction_id": "cargo_payment:"+str(d["id"]), "from_account_id": e._account(pay["payer"], pay["denomination"]), "to_account_id": e._account(pay["recipient"], pay["denomination"]), "amount": pay["amount"], "kind": "cargo_refund" if terms["mode"] == "REFUND" else "cargo_damages", "reference_id": d["id"]}
		var legs: Array[Dictionary] = [leg]
		if not e._world.ledger_state.batch_payment("cargo:"+str(d["id"]), legs, minute):
			d["status"] = "PAYABLE"
			_index_disposition(d)
			return {"accepted": false, "reason": "AGREED_PAYMENT_REMAINS_UNFUNDED", "disposition_id": d["id"], "responsibility_changed": true}
		d["payments"] = legs
		d["execution_authorizations"] = [authority["proof"]] if not _host_organization(pay["payer"]).is_empty() else []
	d["status"] = "EXECUTED"
	d["executed_minute"] = minute
	_index_disposition(d)
	if terms["mode"] == "REPLACE":
		if not _replacements_by_order.has(order["id"]): _replacements_by_order[order["id"]] = []
		_replacements_by_order[order["id"]].append(d["id"])
	return {"accepted": true, "reason": "DISPOSITION_EXECUTED", "disposition_id": d["id"], "quantity": q}

func _execution_requirements(d: Dictionary, order: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var terms := d["terms"] as Dictionary
	if terms["mode"] in ["REFUND","DAMAGES"]:
		var pay := terms["payment"] as Dictionary
		if not _host_organization(pay["payer"]).is_empty():
			result.append({"subject":pay["payer"],"operation":"economy.cargo.pay","target":d["id"],"place":order["from_place_id"],"category":"cargo:"+str(terms["mode"]).to_lower()+":"+str(pay["denomination"]),"amount":pay["amount"]})
	elif terms["mode"]=="REPLACE":
		for fee: Dictionary in terms["fees"]:
			var subject: String=economy()._budgets.subject_aliases.get(fee["payer"],fee["payer"])
			var root := ""
			for budget: Dictionary in economy()._budgets.rules:
				if budget["subject"]==subject and budget["denomination"]==fee["denomination"] and budget["category"]=="freight:"+str(fee["edge_id"]) and d["executed_minute"]>=budget["start_minute"] and d["executed_minute"]<budget["end_minute"] and budget["basis"]!="EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY": root=budget["root_authority"]
			if _host_organization(fee["payer"]).is_empty() and root.is_empty(): continue
			var requirement := {"subject":fee["payer"],"operation":"economy.procure","target":fee["recipient"],"place":order["from_place_id"],"category":"freight:"+str(fee["edge_id"]),"amount":_fee_authority_amount(terms["fees"],fee)}
			if not root.is_empty(): requirement["authority_id"]=root
			result.append(requirement)
	return result

func _fee_authority_amount(fees: Array, selected: Dictionary) -> int:
	var total := 0
	for fee: Dictionary in fees:
		if fee["payer"] == selected["payer"] and fee["edge_id"] == selected["edge_id"] and fee["denomination"] == selected["denomination"]:
			if fee["amount"] > FormalLedgerState.MAX_AMOUNT-total: return FormalLedgerState.MAX_AMOUNT
			total += int(fee["amount"])
	return total

func _prepare_fees(d: Dictionary, minute: int, actor: String, contexts: Dictionary) -> Dictionary:
	var e := economy()
	var legs: Array[Dictionary] = []
	var plans: Dictionary = {}
	var extra: Dictionary = {}
	var proofs: Array[Dictionary] = []
	for i: int in d["terms"]["fees"].size():
		var fee := d["terms"]["fees"][i] as Dictionary
		var plan: Dictionary = e._budgets.plan(fee["payer"], fee["denomination"], "freight:"+str(fee["edge_id"]), fee["amount"], minute)
		if not plan.get("ok", false): return plan
		if plan.has("rule_id"):
			var r: Dictionary = e._budgets.rule(plan["rule_id"])
			if r["basis"] != "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY" or not _host_organization(fee["payer"]).is_empty():
				var authority := _authorize(actor, fee["payer"], "economy.procure", fee["recipient"], e._orders[losses[d["loss_id"]]["order_id"]]["from_place_id"], "freight:"+str(fee["edge_id"]), _fee_authority_amount(d["terms"]["fees"], fee), contexts)
				if not authority["ok"]: return authority
				if r["basis"] != "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY" and authority["proof"].get("authority_id") != r["root_authority"]: return {"ok":false,"reason":"EXTRA_FREIGHT_ROOT_BUDGET_MISMATCH"}
				proofs.append(authority["proof"])
			extra[r["id"]] = int(extra.get(r["id"], 0))+int(fee["amount"])
			if extra[r["id"]] > int(r["limit"])-int(e._budgets._used.get(r["id"], 0)): return {"ok": false, "reason": "CUMULATIVE_EXTRA_FREIGHT_BUDGET_EXCEEDED"}
		if not _host_organization(fee["payer"]).is_empty() and not plan.has("rule_id"): return {"ok":false,"reason":"FORMAL_EXTRA_FREIGHT_REQUIRES_EXPLICIT_BUDGET_WINDOW"}
		var key := "cargo_fee:"+str(d["id"])+":"+str(i)
		plans[key] = [plan]
		legs.append({"transaction_id": key, "from_account_id": e._account(fee["payer"], fee["denomination"]), "to_account_id": e._account(fee["recipient"], fee["denomination"]), "amount": fee["amount"], "kind": "cargo_extra_freight", "reference_id": d["id"]})
	return {"ok": true, "legs": legs, "plans": plans, "authorizations": proofs}

func _adopt_fees(d: Dictionary, prepared: Dictionary) -> void:
	var e := economy()
	for key: String in prepared["plans"]:
		var plans: Array[Dictionary] = []
		plans.assign(prepared["plans"][key])
		var committed: bool = e._budgets.commit(key, plans)
		var spent: bool = e._budgets.settle("cargo_spent:"+key, key, 1, 0, 1)
		assert(committed and spent)
	d["payments"] = prepared["legs"]

func fee_contracts() -> Dictionary:
	var result: Dictionary = {}
	for d: Dictionary in dispositions.values():
		if d["status"] != "EXECUTED" or d["terms"]["mode"] != "REPLACE": continue
		for i: int in d["terms"]["fees"].size():
			var f := d["terms"]["fees"][i] as Dictionary
			var id := "cargo_fee:"+str(d["id"])+":"+str(i)
			result[id] = {"id": id, "kind": "TRANSFER", "buyer": f["payer"], "denomination": f["denomination"], "quantity": 1, "price": 0, "good": "", "accepted_minute": d["executed_minute"], "delivered": 1, "cancelled": 0, "route_legs": [{"edge_id": f["edge_id"], "freight_per_unit": f["amount"]}]}
	return result

func _authority_view(proof: Dictionary) -> Dictionary:
	return {"authority_id":proof.get("authority_id",""),"subject":proof.get("subject",""),"operation":proof.get("operation",""),"target":proof.get("target",""),"category":proof.get("category",""),"amount":proof.get("amount",0),"minute":proof.get("minute",0)}

func visible(actor: String, order_id: String = "") -> Dictionary:
	var result := {"losses": [], "dispositions": []}
	var loss_ids: Array = losses.keys() if order_id.is_empty() else _losses_by_order.get(order_id, []).duplicate()
	loss_ids.reverse()
	for loss_id: String in loss_ids:
		var fact := losses[loss_id] as Dictionary
		if (order_id.is_empty() or fact["order_id"] == order_id) and knows_loss(actor, fact["id"]):
			var row := fact.duplicate(true)
			row["can_confirm"] = controls(actor, fact["custodian"])
			var order := economy()._orders.get(fact["order_id"], {}) as Dictionary
			row["can_propose"] = not order.is_empty() and (controls(actor, order["buyer"], true) or controls(actor, order["seller"], true))
			for mode: String in ["RELEASE","REPLACE"]:
				var contexts:=action_authorizations(actor,fact["id"],mode,1)
				var terms: Dictionary={"mode":mode,"quantity":1,"fees":[]}
				row["can_propose_"+mode.to_lower()]=not order.is_empty() and [order["buyer"],order["seller"]].any(func(party: String)->bool:return not _decision_confirmation(actor,party,terms,order,contexts).is_empty())
			result["losses"].append(row)
			if result["losses"].size() >= 32: break
	var disposition_ids: Array = dispositions.keys() if order_id.is_empty() else _dispositions_by_order.get(order_id, []).duplicate()
	disposition_ids.reverse()
	for disposition_id: String in disposition_ids:
		var d := dispositions[disposition_id] as Dictionary
		if (order_id.is_empty() or losses[d["loss_id"]]["order_id"] == order_id) and d["parties"].any(func(p: String) -> bool: return controls(actor, p) or controls(actor, p, true)):
			var row := d.duplicate(true)
			row["order_id"] = losses[d["loss_id"]]["order_id"]
			var contexts:=action_authorizations(actor,"","",0,d["id"])
			row["can_consent"] = d["parties"].any(func(p: String) -> bool: return not _decision_confirmation(actor,p,d["terms"],economy()._orders[losses[d["loss_id"]]["order_id"]],contexts).is_empty())
			row["scoped_authority_required"] = d["parties"].any(func(p: String)->bool:return not _host_organization(p).is_empty())
			for confirmation: Dictionary in row["confirmed"].values():
				if confirmation.has("authority_proofs"): confirmation["authority_proofs"]=confirmation["authority_proofs"].map(func(proof: Dictionary)->Dictionary:return _authority_view(proof))
			if row.has("execution_authorizations"): row["execution_authorizations"]=row["execution_authorizations"].map(func(proof: Dictionary)->Dictionary:return _authority_view(proof))
			result["dispositions"].append(row)
			if result["dispositions"].size() >= 32: break
	return result

func snapshot() -> Dictionary:
	return {"losses": losses.duplicate(true), "dispositions": dispositions.duplicate(true), "notices": notices.duplicate(true)}

func valid_payment_batch(id: String) -> bool:
	var d := dispositions.get(id.trim_prefix("cargo:"), {}) as Dictionary
	if d.is_empty() or d["status"] != "EXECUTED" or d["payments"].is_empty(): return false
	var e := economy()
	var batch: Dictionary = e._world.ledger_state.payment_batch(id)
	if batch.is_empty() or batch["minute"] != d["executed_minute"] or not batch["releases"].is_empty(): return false
	var expected: Array[Dictionary] = []
	var mode := str(d["terms"]["mode"])
	if mode == "REPLACE":
		for i: int in d["terms"]["fees"].size():
			var p := d["terms"]["fees"][i] as Dictionary
			expected.append({"transaction_id": "cargo_fee:"+str(d["id"])+":"+str(i), "from_account_id": e._account(p["payer"], p["denomination"]), "to_account_id": e._account(p["recipient"], p["denomination"]), "amount": p["amount"], "kind": "cargo_extra_freight", "reference_id": d["id"]})
	elif mode in ["REFUND", "DAMAGES"]:
		var p := d["terms"]["payment"] as Dictionary
		expected.append({"transaction_id": "cargo_payment:"+str(d["id"]), "from_account_id": e._account(p["payer"], p["denomination"]), "to_account_id": e._account(p["recipient"], p["denomination"]), "amount": p["amount"], "kind": "cargo_refund" if mode == "REFUND" else "cargo_damages", "reference_id": d["id"]})
	if d["payments"] != expected or batch["transactions"].size() != expected.size(): return false
	for leg: Dictionary in d["payments"]:
		var tx: Dictionary = e._world.ledger_state.transaction(leg["transaction_id"])
		if tx.is_empty() or tx["effective_minute"] != d["executed_minute"]: return false
		for k: String in leg:
			if tx.get(k) != leg[k]: return false
	return true

func _valid_confirmations(parties: Array, confirmed: Dictionary, start: int, saved: Dictionary, financial: bool = false) -> bool:
	var e := economy()
	for party: String in confirmed:
		var proof: Variant = confirmed[party]
		if party not in parties or not proof is Dictionary or not EconomySliceConfig._fields(proof, ["actor", "minute"], ["authority_proofs"]) or not proof["actor"] is String or not FormalLedgerState.valid_amount(proof["minute"]) or proof["minute"] < start or proof["minute"] > e._world.game_clock.total_minutes(): return false
		var actor := str(proof["actor"])
		if proof.has("authority_proofs"):
			if not financial or not proof["authority_proofs"] is Array or proof["authority_proofs"].is_empty(): return false
			for authority: Variant in proof["authority_proofs"]:
				if not _saved_authority(authority) or authority.get("subject") != party or authority.get("actor") != actor or authority.get("minute") != proof["minute"]: return false
			continue
		if actor == party and (saved["actors"].has(actor) or e._spec["firms"].has(actor)): continue
		var carrier_valid := false
		for carrier: Dictionary in e.config.get("carriers", []):
			if carrier["id"] != party: continue
			var controller := str(carrier.get("settlement_controller" if financial else "custody_controller", ""))
			carrier_valid = not controller.is_empty() and (actor == controller or (e._spec["firms"].has(controller) and e._manager_at(actor, controller, proof["minute"])))
		if carrier_valid: continue
		if not e._spec["firms"].has(e._owner(party)) or not e._manager_at(actor, e._owner(party), proof["minute"]): return false
		if financial and e._spec["firms"][e._owner(party)].get("cargo_settlement_controller", "") != actor: return false
	return true

func restore(raw: Variant, saved: Dictionary) -> bool:
	if raw == null: return true # Old losses retain their old recorded boundary.
	if not raw is Dictionary or not EconomySliceConfig._fields(raw, ["losses", "dispositions"], ["notices"]) or not raw["losses"] is Dictionary or not raw["dispositions"] is Dictionary or not raw.get("notices", {}) is Dictionary: return false
	var e := economy()
	for key: String in ["orders", "shipments", "commands", "actors"]:
		if not saved.get(key) is Dictionary: return false
	if not saved.get("stock_lots") is Dictionary or not saved["stock_lots"].get("portions") is Dictionary: return false
	var adopted: Dictionary = {}
	for id: String in raw["losses"]:
		var f: Variant = raw["losses"][id]
		if not f is Dictionary or not EconomySliceConfig._fields(f, ["id", "rows", "quantity", "good", "unit", "owner", "custodian", "location", "place_id", "shipment_id", "order_id", "stage", "leg_index", "observed_minute", "basis", "process", "parties", "confirmed", "status", "adopted_minute", "resolved", "personal_fact"],["service_id"]) or f["id"] != id or f["status"] not in ["OBSERVED", "ADOPTED"] or not f["rows"] is Array or f["rows"].is_empty() or not FormalLedgerState.valid_amount(f["quantity"]) or f["quantity"] <= 0 or not FormalLedgerState.valid_amount(f["resolved"]) or f["resolved"] > f["quantity"] or not FormalLedgerState.valid_amount(f["observed_minute"]) or not f["confirmed"] is Dictionary or not f["parties"] is Array or not f["personal_fact"] is Dictionary: return false
		if f.has("service_id"):
			var service: Dictionary=saved.get("service_market",{}).get("contracts",{}).get(f["service_id"],{})
			if service.get("kind")!="STORAGE" or f["owner"]!=service.get("client") or not f["order_id"].is_empty() or not f["shipment_id"].is_empty() or f["good"]!=service.get("good") or f["resolved"]!=0 or f["location"] not in ["SERVICE|"+str(f["service_id"]),"SITE|"+str(service.get("source_site",""))]: return false
		for key: String in ["good", "unit", "owner", "custodian", "location", "place_id", "shipment_id", "order_id", "stage", "basis", "process"]:
			if not f[key] is String: return false
		if typeof(f["leg_index"]) != TYPE_INT or typeof(f["adopted_minute"]) != TYPE_INT or f["observed_minute"] > e._world.game_clock.total_minutes() or f["basis"].is_empty() or f["process"].is_empty(): return false
		var parties: Array = [f["owner"]]
		if f["custodian"] != f["owner"]: parties.append(f["custodian"])
		if f["parties"] != parties or not _valid_confirmations(parties, f["confirmed"], f["observed_minute"], saved): return false
		var total := 0
		for row: Variant in f["rows"]:
			if not row is Dictionary or not saved.get("stock_lots", {}).get("portions", {}).has(row.get("portion_id")) or not FormalLedgerState.valid_amount(row.get("quantity")) or int(row["quantity"]) <= 0: return false
			var portion_raw: Variant = saved["stock_lots"]["portions"][row["portion_id"]]
			if not portion_raw is Dictionary: return false
			var portion := portion_raw as Dictionary
			for key: String in ["source_id", "owner", "custodian", "location", "place_id", "good", "unit"]:
				if not portion.get(key) is String: return false
			if row.get("source_id") != portion["source_id"]: return false
			for k: String in ["owner", "custodian", "location", "place_id", "good", "unit"]:
				if portion.get(k) != f[k]: return false
			total += int(row["quantity"])
		if total != f["quantity"]: return false
		if not str(f["order_id"]).is_empty():
			var order_raw: Variant = saved["orders"].get(f["order_id"])
			if not order_raw is Dictionary or not order_raw.get("route_legs") is Array or not order_raw.get("buyer") is String or not order_raw.get("seller") is String: return false
			for leg: Variant in order_raw["route_legs"]:
				if not leg is Dictionary or not e._all_routes().has(leg.get("edge_id")): return false
		if not str(f["shipment_id"]).is_empty():
			var cargo_raw: Variant = saved["shipments"].get(f["shipment_id"])
			if not cargo_raw is Dictionary or cargo_raw.get("order_id") != f["order_id"] or f["location"] != "CARGO|"+str(f["shipment_id"]) or f["stage"] not in ["LOADING", "TRANSIT", "WAITING", "AWAITING_RECIPIENT", "WAITING_UNLOAD", "UNLOADING"] or f["leg_index"] < 0 or f["leg_index"] >= saved["orders"][f["order_id"]]["route_legs"].size(): return false
		if f["status"] == "ADOPTED":
			var physical: Variant = saved.get("stock_lots", {}).get("losses", {}).get(id)
			if not physical is Dictionary or physical.get("portions") != f["rows"] or physical.get("basis") != f["basis"] or physical.get("process") != f["process"] or physical.get("minute") != f["adopted_minute"] or f["adopted_minute"] < f["observed_minute"] or f["adopted_minute"] > e._world.game_clock.total_minutes() or not f["confirmed"].has(f["custodian"]): return false
			adopted[id] = 0
		elif f["adopted_minute"] != -1 or f["resolved"] != 0 or not f["personal_fact"].is_empty(): return false
	losses = raw["losses"].duplicate(true)
	dispositions = raw["dispositions"].duplicate(true)
	_losses_by_order.clear()
	_losses_by_shipment.clear()
	_replacements_by_order.clear()
	_dispositions_by_order.clear()
	_disposition_days.clear()
	_open_dispositions.clear()
	for fact: Dictionary in losses.values(): _index_loss(fact)
	for id: String in dispositions:
		var d: Variant = dispositions[id]
		if not d is Dictionary or not EconomySliceConfig._fields(d, ["id", "loss_id", "terms", "parties", "confirmed", "status", "minute", "executed_minute", "payments", "replacement_portions"], ["custody_fact", "execution_authorizations"]) or d["id"] != id or not adopted.has(d["loss_id"]) or not d["terms"] is Dictionary or d["terms"].get("loss_id") != d["loss_id"] or d["terms"].get("mode") not in ["KEEP", "REPLACE", "RELEASE", "REFUND", "DAMAGES"] or not FormalLedgerState.valid_amount(d["terms"].get("quantity")) or d["terms"]["quantity"] <= 0 or d["status"] not in ["PROPOSED", "AGREED", "PAYABLE", "EXECUTED"] or not d["parties"] is Array or not d["confirmed"] is Dictionary or not FormalLedgerState.valid_amount(d["minute"]) or not _valid_confirmations(d["parties"], d["confirmed"], d["minute"], saved, true) or not d["payments"] is Array or not d["replacement_portions"] is Array: return false
		var order := saved["orders"][losses[d["loss_id"]]["order_id"]] as Dictionary
		if not _dispositions_by_order.has(order["id"]): _dispositions_by_order[order["id"]] = []
		_dispositions_by_order[order["id"]].append(id)
		if not EconomySliceConfig._fields(d["terms"], ["loss_id", "mode", "quantity", "basis"], ["fees", "payment"]) or not d["terms"]["basis"] is String or d["terms"]["basis"].is_empty() or not d.get("custody_fact", {}) is Dictionary: return false
		var parties: Array = [order["buyer"]]
		if order["seller"] not in parties: parties.append(order["seller"])
		var mode := str(d["terms"]["mode"])
		if mode == "REPLACE":
			if not d["terms"].get("fees") is Array: return false
			for leg: Dictionary in order["route_legs"]:
				var carrier := str(e._all_routes()[leg["edge_id"]]["carrier"])
				if not carrier.is_empty() and carrier not in parties: parties.append(carrier)
			for fee: Variant in d["terms"]["fees"]:
				if not fee is Dictionary or not _valid_payment(fee) or fee.get("payment_milestone") != "REPLACEMENT_ACCEPTANCE" or fee.get("edge_id") not in order["route_legs"].map(func(leg: Dictionary) -> String: return leg["edge_id"]) or e._all_routes()[fee["edge_id"]]["carrier"] != fee["recipient"]: return false
				for party: String in [fee["payer"], fee["recipient"]]:
					if party not in parties: parties.append(party)
		elif mode in ["REFUND", "DAMAGES"]:
			var pay: Variant = d["terms"].get("payment")
			if not pay is Dictionary or not _valid_payment(pay) or (mode == "REFUND" and not _refund_available(pay, order["id"], id)): return false
			for party: String in [pay["payer"], pay["recipient"]]:
				if party not in parties: parties.append(party)
		for party: String in d["confirmed"]:
			var confirmation := d["confirmed"][party] as Dictionary
			if not confirmation.has("authority_proofs"): continue
			var requirements := _decision_requirements(d["terms"], party, order)
			if requirements.size() != confirmation["authority_proofs"].size(): return false
			for i: int in requirements.size():
				for key: String in requirements[i]:
					if confirmation["authority_proofs"][i].get(key) != requirements[i][key]: return false
		if d.has("execution_authorizations"):
			if not d["execution_authorizations"] is Array or d["status"]!="EXECUTED": return false
			var expected := _execution_requirements(d,order)
			if expected.size()!=d["execution_authorizations"].size(): return false
			for i: int in expected.size():
				var proof: Variant=d["execution_authorizations"][i]
				if not _saved_authority(proof) or proof["minute"] != d["executed_minute"]: return false
				for key: String in expected[i]:
					if proof.get(key)!=expected[i][key]: return false
		if d["parties"] != parties or (d["status"] != "PROPOSED" and d["confirmed"].size() != parties.size()): return false
		if d["status"] != "EXECUTED":
			if d["executed_minute"] != -1 or not d["payments"].is_empty() or not d["replacement_portions"].is_empty(): return false
			continue
		if not FormalLedgerState.valid_amount(d["executed_minute"]) or d["executed_minute"] < d["minute"] or d["executed_minute"] > e._world.game_clock.total_minutes(): return false
		if mode in ["REPLACE", "RELEASE"]: adopted[d["loss_id"]] += int(d["terms"]["quantity"])
		if mode == "REPLACE":
			var q := 0
			for row: Variant in d["replacement_portions"]:
				if not row is Dictionary or not saved["stock_lots"]["portions"].has(row.get("portion_id")) or not FormalLedgerState.valid_amount(row.get("quantity")): return false
				var portion_raw: Variant = saved["stock_lots"]["portions"][row["portion_id"]]
				if not portion_raw is Dictionary or typeof(portion_raw.get("opened_minute")) != TYPE_INT: return false
				var portion := portion_raw as Dictionary
				var location := "PERSON|"+str(order["buyer"])+"|STORED|"+str(order["from_place_id"]) if order["kind"] == "PERSONAL_FREIGHT" else "SITE|"+str(order["seller_site"])
				if portion["owner"] != order["seller"] or portion["location"] != location or portion["good"] != order["good"] or row.get("source_id") != portion["source_id"] or portion["opened_minute"] > d["executed_minute"]: return false
				q += int(row["quantity"])
			if q != d["terms"]["quantity"]: return false
			if order["kind"] == "PERSONAL_FREIGHT" and not e._valid_custody_fact(d.get("custody_fact", {}), order["buyer"], order["good"], q, "STORED|"+str(order["from_place_id"]), "FREIGHT|"+str(order["id"]), id, "freight_replace", d["executed_minute"]): return false
		if mode in ["REFUND", "DAMAGES"] and d["payments"].size() != 1: return false
		if mode == "REPLACE":
			if d["payments"].size() != d["terms"]["fees"].size(): return false
			if not _replacements_by_order.has(order["id"]): _replacements_by_order[order["id"]] = []
			_replacements_by_order[order["id"]].append(id)
		if mode in ["RELEASE", "KEEP"] and not d["payments"].is_empty(): return false
		if mode == "RELEASE":
			var release: Variant = saved.get("procurement_budget", {}).get("settlements", {}).get("loss_release:"+id)
			if not release is Dictionary or release.get("order_id") != order["id"] or release.get("quantity") != order["quantity"] or int(release.get("cancelled", 0)) < int(d["terms"]["quantity"]) or int(release["cancelled"]) > int(order["cancelled"]): return false
		if not d["payments"].is_empty() and not valid_payment_batch("cargo:"+id): return false
	for id: String in adopted:
		if adopted[id] != losses[id]["resolved"]: return false
	for id: String in raw.get("notices", {}):
		var n: Variant = raw["notices"][id]
		if not n is Dictionary or not FormalLedgerState.exact_fields(n, ["id", "loss_id", "sender", "recipient", "sent_minute", "delivery_minute", "basis"]) or n["id"] != id or not losses.has(n["loss_id"]) or not FormalLedgerState.valid_amount(n["sent_minute"]) or n["sent_minute"] > e._world.game_clock.total_minutes() or not FormalLedgerState.valid_amount(n["delivery_minute"]) or n["delivery_minute"] < n["sent_minute"]: return false
		var order := saved["orders"].get(losses[n["loss_id"]]["order_id"], {}) as Dictionary
		var service: Dictionary=saved.get("service_market",{}).get("contracts",{}).get(losses[n["loss_id"]].get("service_id",""),{})
		var cmd: Dictionary = saved["commands"].get(id, {})
		var recipients: Array=[]
		if not order.is_empty(): recipients=[order["buyer"],order["seller"]]
		elif not service.is_empty(): recipients=[service["client"],service["provider"]]
		if n["recipient"] not in recipients or cmd.get("envelope", {}).get("actor") != n["sender"] or cmd.get("envelope", {}).get("command", {}).get("kind") != "notify_cargo_loss" or not cmd.get("result", {}).get("accepted", false): return false
		var f:=losses[n["loss_id"]] as Dictionary
		if not f["parties"].any(func(party: String)->bool:return _valid_confirmations(f["parties"],{party:{"actor":n["sender"],"minute":n["sent_minute"]}},f["observed_minute"],saved)): return false
	notices = raw.get("notices", {}).duplicate(true)
	_notices_by_loss.clear()
	for notice_id: String in notices:
		var loss_id := str(notices[notice_id]["loss_id"])
		if not _notices_by_loss.has(loss_id): _notices_by_loss[loss_id] = []
		_notices_by_loss[loss_id].append(notice_id)
	for d: Dictionary in dispositions.values(): _index_disposition(d)
	return true

func keeper_reason(subject: String) -> String:
	for d: Dictionary in dispositions.values():
		if d["status"] in ["AGREED", "PAYABLE"] and subject in d["parties"]: return "CARGO_DISPOSITION_OR_AGREED_PAYMENT_REMAINS"
	for fact: Dictionary in losses.values():
		if fact["status"] == "OBSERVED" and subject in fact["parties"]: return "CARGO_LOSS_AWAITS_CUSTODY_CONFIRMATION"
	return ""

func _result(ok: bool, reason: String) -> Dictionary:
	return {"accepted": ok, "reason": reason}
