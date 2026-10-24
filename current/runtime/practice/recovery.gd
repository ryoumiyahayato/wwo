extends RefCounted
## Coordinates durable native evidence with the existing formal material owner.
const Native = preload("res://practice/native_return.gd")
const MaterialLedger = preload("res://scripts/vnext/military/military_material_state.gd")
const Shot = preload("res://practice/shot_contract.gd")
const BUNDLE := "formal_practice_portable_v1"
const PROTOCOL := "formal_practice_recovery_v1"

static func instance(persistence: FormalPersistence) -> String:
	return str(persistence._save_metadata.get("military_scenario",{}).get("practice_instance_id",""))

static func assess(world: WorldState, persistence: FormalPersistence, evidence: Dictionary) -> Dictionary:
	if persistence._save_metadata.get("practice_recovery_protocol","") not in ["",PROTOCOL]:return {"ok":false,"state":"FROZEN","reason":"UNKNOWN_RECOVERY_PROTOCOL"}
	if world.military_state.material_registry.get("schema")==MaterialLedger.RECOVERY_SCHEMA and persistence._save_metadata.get("practice_recovery_protocol")!=PROTOCOL:return {"ok":false,"state":"FROZEN","reason":"RECOVERY_PROTOCOL_METADATA_MISSING"}
	if not evidence.get("ok",false):return {"ok":false,"state":"FROZEN","reason":evidence.get("reason","MISSING_REQUIRED_EVIDENCE")}
	if evidence.get("instance_id")!=instance(persistence):return {"ok":false,"state":"FROZEN","reason":"EVIDENCE_INSTANCE_MISMATCH"}
	var view: Dictionary=world.military_state.material_registry.get("view",{})
	var receipt: Dictionary=evidence.get("receipt",{})
	if evidence.status=="idle":
		if not receipt.is_empty():return {"ok":false,"state":"FROZEN","reason":"IDLE_WITH_SHOT_RECEIPT"}
		var anchor: Dictionary=evidence.get("lease_anchor",{})
		var lease_id: String=str(view.get("asset",{}).get("lease_id",""))
		if not lease_id.is_empty() and anchor!=view.leases.get(lease_id,{}):return {"ok":false,"state":"FROZEN","reason":"IDLE_LEASE_ANCHOR_CONFLICT"}
		return {"ok":true,"state":"NOT_EMITTED","reason":"Durable idle boundary; no shot was prepared"}
	var rid: String=str(receipt.get("receipt_id",""))
	if view.get("receipts",{}).has(rid):
		if view.receipts[rid]!=receipt:return {"ok":false,"state":"FROZEN","reason":"CONFLICTING_ADOPTED_RECEIPT"}
		if persistence._save_metadata.get("practice_recovery_protocol")==PROTOCOL and persistence._save_metadata.get("practice_last_receipt",rid)!=rid:return {"ok":false,"state":"FROZEN","reason":"EVIDENCE_BEHIND_FORMAL_CHECKPOINT"}
		return {"ok":true,"state":"ALREADY_ADOPTED","reason":"Formal journal already contains this exact event"}
	if evidence.status=="prepared_after_muzzle_ray":return {"ok":false,"state":"UNCERTAIN","reason":"Ray prepared; emission completion cannot be proven"}
	if evidence.status!="emitted_pending_formal_save":return {"ok":false,"state":"FROZEN","reason":"COMPLETION_WITHOUT_FORMAL_EVENT"}
	var lease: Dictionary=view.get("leases",{}).get(str(receipt.get("lease_id","")),{})
	if lease.is_empty() or lease.status!="issued" or lease.person_id!=world.player_state.player_id() or receipt.get("issuer_id")!=lease.issuer_id or receipt.get("generation")!=lease.generation or receipt.get("before")!=lease.native:return {"ok":false,"state":"FROZEN","reason":"EMITTED_LEASE_OR_BUDGET_CONFLICT"}
	var context_value: Dictionary=evidence.get("use_context",{})
	var qualification: Dictionary=evidence.get("qualification",{})
	for operation: String in ["carry","fire"]:
		var proof: Variant=qualification.get(operation)
		if not proof is Dictionary or proof.get("status")!=AuthorizationCheck.ALLOWED:return {"ok":false,"state":"FROZEN","reason":"ACTION_TIME_AUTHORITY_EVIDENCE_MISSING"}
	var physical: Dictionary=receipt.get("physical",{})
	var state: Dictionary=world.military_state.material_registry
	var seq: int=state.events.size()+1
	var event: Dictionary={"event_id":"%s:event:%d"%[MaterialLedger.config().source_id,seq],"sequence":seq,"kind":"use","minute":physical.get("minute",-1),"actor_id":world.player_state.player_id(),"context":context_value,"payload":receipt}
	var candidate:=MaterialLedger.append(state,event)
	if not candidate.get("ok",false):return {"ok":false,"state":"FROZEN","reason":candidate.get("reason","INVALID_EMITTED_EVENT")}
	if not Shot.references_error(world,physical).is_empty():return {"ok":false,"state":"FROZEN","reason":"ACTION_AUTHORITY_REFERENCE_INVALID"}
	return {"ok":true,"state":"EMITTED_UNADOPTED","reason":"Exact native result can be adopted without firing again","candidate":candidate.state}

static func evidence(persistence: FormalPersistence) -> Dictionary:
	var file_path:=Native.path(instance(persistence))
	return Native.read_file(file_path) if FileAccess.file_exists(file_path) else {"ok":false,"reason":"MISSING_REQUIRED_EVIDENCE"}

static func portable_error(path: String) -> String:
	var result:=read_portable(path)
	return "" if result.get("ok",false) else str(result.get("reason","INVALID_PORTABLE_SAVE"))

static func export_portable(path: String, persistence: FormalPersistence) -> String:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(Native.path(instance(persistence))))
	if not raw is Dictionary:return "MISSING_REQUIRED_EVIDENCE"
	var document: Dictionary={"schema":BUNDLE,"world":FormalWorldPersistenceDocument.encode(persistence.snapshot(),persistence._save_metadata),"native_evidence":raw}
	return AtomicJsonFileStore.write_verified(path,document,Callable(load("res://practice/recovery.gd"),"portable_error"),true)

static func read_portable(path: String) -> Dictionary:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or raw.size()!=3 or not raw.has_all(["schema","world","native_evidence"]) or raw.schema!=BUNDLE or not raw.world is Dictionary or not raw.native_evidence is Dictionary:return {"ok":false,"reason":"PORTABLE_SCHEMA_OR_MISSING_COMPONENT"}
	var decoded:=FormalWorldPersistenceDocument.decode(raw.world)
	if not decoded.get("success",false):return {"ok":false,"reason":decoded.get("error","INVALID_WORLD_DOCUMENT")}
	var reader:=FormalPersistence.new()
	var built:=reader.restore_candidate(decoded.snapshot)
	if not built.success:return {"ok":false,"reason":built.error}
	built.persistence._save_metadata=decoded.save_metadata.duplicate(true)
	built.operation=SaveOperationResult.ok(path)
	var native:=Native.decode(raw.native_evidence)
	var check:=assess(built.world,built.persistence,native)
	# Unknown/uncertain *valid* boundaries may travel, but cannot be resolved by import.
	if not native.get("ok",false) or check.get("state")=="FROZEN":return {"ok":false,"reason":check.get("reason","INVALID_EVIDENCE")}
	return {"ok":true,"built":built,"evidence":raw.native_evidence,"assessment":check}
