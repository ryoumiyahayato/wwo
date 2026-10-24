extends RefCounted
## Commands over the installed MilitaryState, with the existing authorization owner.
const State = preload("res://scripts/vnext/military/military_material_state.gd")
var world: WorldState
var persistence: FormalPersistence
var issuer_id := "custody-runtime-%d-%d-%d"%[OS.get_process_id(),int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
var _physical_executor: WeakRef
var _staged_physical_receipt: Dictionary={}
var _staged_before: Dictionary={}
var _staged_after: Dictionary={}
var reuse_validated_stage:=false

func bind(value: WorldState,storage: FormalPersistence) -> bool:
	world=value;persistence=storage
	return world!=null and State.references_error(world).is_empty()

func view() -> Dictionary:
	return world.military_state.material_registry.get("view",{}).duplicate(true)

func command(kind: String,context: Dictionary,payload: Dictionary) -> Dictionary:
	if kind not in State.OPERATIONS or kind=="use":return State.fail("UNKNOWN_MATERIAL_COMMAND")
	var authorized:=authorize(kind,context,float(payload.get("quantity",0)))
	if not authorized.ok:return authorized
	var p:=payload.duplicate(true)
	if kind=="reserve":p.lease_id="custody:%d"%(world.military_state.material_registry.events.size()+1)
	if kind in ["issue","recover"]:p.issuer_id=issuer_id
	return commit(kind,context,p)

func request_use(context: Dictionary,lease_id: String) -> Dictionary:
	var checked:=authorize("use",context,1)
	if not checked.ok:return checked
	var v:=view();var lease: Dictionary=v.leases.get(lease_id,{})
	if lease.get("status")!="issued" or lease.get("person_id")!=context.person_id:return State.fail("NOT_ISSUED_TO_PERSON")
	if lease.issuer_id!=issuer_id:return State.fail("COLD_LEASE_REQUIRES_EXPLICIT_RECOVER")
	return {"ok":true,"request":{"lease_id":lease_id,"issuer_id":issuer_id,"generation":lease.generation,"quantity":lease.quantity,"before":lease.native.duplicate(true)}}

func adopt_use(context: Dictionary,receipt: Dictionary) -> Dictionary:
	var registry: Dictionary=world.military_state.material_registry
	if registry.is_empty():return State.fail("UNKNOWN_UNMODELED_MATERIAL_REGISTRY")
	var rid:=str(receipt.get("receipt_id",""))
	if registry.view.receipts.has(rid):
		return {"ok":true,"duplicate":true} if registry.view.receipts[rid]==receipt else State.fail("CONFLICTING_MATERIAL_RECEIPT")
	var checked:=authorize("use",context,1)
	if not checked.ok:return checked
	if receipt.get("issuer_id")!=issuer_id:return State.fail("WRONG_CUSTODY_RUNTIME")
	if receipt.has("physical"):
		if _physical_executor==null or _physical_executor.get_ref()==null or receipt!=_staged_physical_receipt:return State.fail("PHYSICAL_RECEIPT_REQUIRES_LIVE_EXECUTOR_EVENT")
		var physical_authority:=authorize_physical(receipt.physical)
		if not physical_authority.ok:return physical_authority
		if reuse_validated_stage and registry==_staged_before and not _staged_after.is_empty():
			world.military_state.material_registry=_staged_after
			_staged_physical_receipt={};_staged_before={};_staged_after={}
			return {"ok":true,"duplicate":false,"validated_stage_reused":true}
	var result:=commit("use",context,receipt)
	if result.get("ok",false) and receipt.has("physical"):_staged_physical_receipt={}
	return result

func register_physical_executor(executor: Object) -> bool:
	if executor==null:return false
	if _physical_executor!=null:return _physical_executor.get_ref()==executor
	_physical_executor=weakref(executor);return true

func stage_physical_use(executor: Object, context: Dictionary, receipt: Dictionary) -> Dictionary:
	if _physical_executor==null or _physical_executor.get_ref()!=executor or not _staged_physical_receipt.is_empty():return State.fail("PHYSICAL_EXECUTOR_NOT_BOUND_OR_BUSY")
	var authorized:=authorize("use",context,1)
	if not authorized.ok:return authorized
	if receipt.get("issuer_id")!=issuer_id or not receipt.get("physical") is Dictionary:return State.fail("INVALID_PHYSICAL_RUNTIME_OR_RECEIPT")
	var physical_authority:=authorize_physical(receipt.physical)
	if not physical_authority.ok:return physical_authority
	var registry: Dictionary=world.military_state.material_registry
	var sequence: int=registry.events.size()+1
	var event: Dictionary={"event_id":"%s:event:%d"%[State.config().source_id,sequence],"sequence":sequence,"kind":"use","minute":world.game_clock.total_minutes(),"actor_id":context.person_id,"context":context.duplicate(true),"payload":receipt.duplicate(true)}
	# Validate the detached candidate after the real ray, without adopting it.
	var candidate:=State.append(registry,event)
	if not candidate.ok:return candidate
	_staged_physical_receipt=receipt.duplicate(true)
	_staged_before=registry.duplicate(true)
	_staged_after=candidate.state
	return {"ok":true}

func discard_staged_physical(executor: Object) -> void:
	if _physical_executor!=null and _physical_executor.get_ref()==executor:_staged_physical_receipt={};_staged_before={};_staged_after={}

func recover_emitted(context: Dictionary, evidence: Dictionary) -> Dictionary:
	var allowed:=authorize("recover",context,1)
	if not allowed.ok:return allowed
	var existing: Dictionary=view().get("receipts",{})
	var receipt_value: Dictionary=evidence.get("receipt",{})
	var rid:=str(receipt_value.get("receipt_id",""))
	if existing.has(rid):return {"ok":true,"duplicate":true,"replayed_native":false} if existing[rid]==receipt_value else State.fail("CONFLICTING_MATERIAL_RECEIPT")
	var inspected: Dictionary=load("res://practice/recovery.gd").assess(world,persistence,evidence)
	if not inspected.get("ok",false):return inspected
	if inspected.state=="ALREADY_ADOPTED":return {"ok":true,"duplicate":true,"replayed_native":false}
	if inspected.state!="EMITTED_UNADOPTED":return State.fail("NO_PROVEN_EMITTED_EVENT_TO_RECOVER")
	world.military_state.material_registry=inspected.candidate
	var audit: Array=persistence._save_metadata.get("practice_recovery_audit",[])
	audit.append({"receipt_id":evidence.receipt.receipt_id,"lease_id":evidence.receipt.lease_id,"actor_id":context.person_id,"recovery_context":context.duplicate(true),"action_qualification":evidence.qualification.duplicate(true),"result":"ADOPTED_SAME_EMITTED_EVENT","native_replayed":false,"minute":world.game_clock.total_minutes()})
	persistence._save_metadata["practice_recovery_audit"]=audit
	return {"ok":true,"duplicate":false,"replayed_native":false,"receipt_id":evidence.receipt.receipt_id}

func authorize_physical(physical: Dictionary) -> Dictionary:
	if physical.get("person_id")!=world.player_state.player_id() or physical.get("anchor_place_id")!=world.person_overlay.current_place(world.player_state.player_id()):return State.fail("INVALID_PHYSICAL_PERSON_OR_PLACE")
	for operation: String in ["carry","fire"]:
		var context_value: Variant=physical.get(operation+"_context")
		if not context_value is Dictionary:return State.fail("INVALID_PHYSICAL_AUTHORITY_CONTEXT")
		var proof:=world.authorization_check.resolve_authority(context_value,"military.practice."+operation,AuthorizationCheck.STAGE_DOMAIN_EXECUTION,str(physical.get("area_id","")),str(physical.get("anchor_place_id","")),world.player_state.player_id(),1.0,world.game_clock.current_hour())
		if proof.status!=AuthorizationCheck.ALLOWED:return {"ok":false,"reason":"PHYSICAL_"+operation.to_upper()+"_PERMISSION_DENIED","authorization":proof}
	return {"ok":true}

func authorize(kind: String,context: Dictionary,quantity: float) -> Dictionary:
	if world.military_state.has_projection_lease():return State.fail("BODY_PROJECTION_LEASE_ACTIVE")
	if persistence!=null and persistence.is_save_in_progress():return State.fail("FORMAL_SAVE_IN_PROGRESS")
	if not world.military_state.local_operations.get("active",{}).is_empty():return State.fail("TRAINING_INTERVAL_ALREADY_DELEGATED")
	if world.military_state.material_registry.is_empty():return State.fail("UNKNOWN_UNMODELED_MATERIAL_REGISTRY")
	var person_id:=str(context.get("person_id",""));var v:=view()
	if person_id!=world.player_state.player_id() or not world.person_overlay.is_alive(person_id):return State.fail("CURRENT_ALIVE_PLAYER_REQUIRED")
	if world.person_travel!=null and world.person_travel.is_in_transit(person_id):return State.fail("PERSON_IN_TRANSIT")
	if world.person_overlay.current_place(person_id)!=v.asset.place_id:return State.fail("CUSTODIAN_NOT_AT_DEPOT")
	if context.get("represented_organization_id")!=v.asset.owner_id:return State.fail("NOT_RESOURCE_OWNER_ORGANIZATION")
	var proof:=world.authorization_check.resolve_authority(context,"military.material."+kind,AuthorizationCheck.STAGE_DOMAIN_EXECUTION,v.asset.asset_id,v.asset.place_id,person_id,quantity,world.game_clock.current_hour())
	if proof.status!=AuthorizationCheck.ALLOWED:return {"ok":false,"reason":"MATERIAL_PERMISSION_DENIED","authorization":proof}
	return {"ok":true,"authorization":proof}

func commit(kind: String,context: Dictionary,payload: Dictionary) -> Dictionary:
	var s: Dictionary=world.military_state.material_registry
	var seq: int=s.events.size()+1
	var event: Dictionary={"event_id":"%s:event:%d"%[State.config().source_id,seq],"sequence":seq,"kind":kind,"minute":world.game_clock.total_minutes(),"actor_id":context.person_id,"context":context.duplicate(true),"payload":payload.duplicate(true)}
	var changed:=State.append(s,event)
	if not changed.ok:return changed
	world.military_state.material_registry=changed.state
	return {"ok":true,"duplicate":false,"event_id":event.event_id,"lease_id":payload.get("lease_id",""),"view":view()}
