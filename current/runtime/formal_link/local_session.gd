class_name FormalLocalSession
extends RefCounted
## Narrow training capability over the installed Formal owners. No economy stock.
const LocalState = preload("res://scripts/vnext/military/military_local_state.gd")
const Authority = preload("res://formal_link/authority.gd")
var persistence: FormalPersistence
const Ammo = preload("res://modules/vehicle_ammo/vehicle_ammo.gd")
const Terrain = preload("res://modules/terrain_damage/streamed_battle_terrain.gd")
const BODY_SOURCE := "TRAINING_BODY_NOT_FORMAL_MEDICAL_RECORD"
const VEHICLE_ID := "training_vehicle:ridgevale_mbt_01"
const CONTENT_SOURCE := "res://triple/default_request.json"
var world: WorldState
var step: SimulationStep
var adopting := false
var error := ""
var runtime_issuer := "formal-runtime-%d-%d"%[OS.get_process_id(),get_instance_id()]
var issued_here: Dictionary={}

func bind(value: WorldState, simulation: SimulationStep, storage: FormalPersistence=null) -> bool:
	world=value;step=simulation;persistence=storage
	if world==null or step==null or not validate_references(world):return false
	state()
	step.local_operation_guard=Callable(self,"time_advance_allowed")
	return true

func state() -> Dictionary:
	if world.military_state.local_operations.is_empty():
		world.military_state.local_operations=LocalState.empty_state()
	return world.military_state.local_operations

func time_advance_allowed() -> bool:
	return not world.military_state.has_projection_lease() and (persistence==null or not persistence.is_save_in_progress()) and (adopting or world.military_state.local_operations.get("active",{}).is_empty())

func issue(person_id: String, mode: String="training") -> Dictionary:
	if world.military_state.has_projection_lease():return fail("BODY_PROJECTION_LEASE_ACTIVE")
	if not world.military_state.duty_operations.get("active","").is_empty():return fail("NAMED_DUTY_ACTIVE")
	if persistence!=null and persistence.is_save_in_progress():return fail("FORMAL_SAVE_IN_PROGRESS")
	if person_id!=world.player_state.player_id() or not world.person_overlay.is_alive(person_id):return fail("SELF_CONTROL_REQUIRED")
	if mode!="training":return Authority.assess(world,person_id)
	if not world.military_state.material_registry.is_empty():
		for custody: Dictionary in world.military_state.material_registry.view.leases.values():
			if custody.status in ["reserved","issued"]:return fail("MATERIAL_CUSTODY_ACTIVE")
	if world.person_travel!=null and world.person_travel.is_in_transit(person_id):return fail("PERSON_IN_TRANSIT")
	var place_id:=world.person_overlay.current_place(person_id)
	if world.spatial_world.get_place(place_id).is_empty():return fail("MISSING_FORMAL_PLACE")
	var data:=state()
	if not (data.active as Dictionary).is_empty():return fail("LOCAL_LEASE_ACTIVE")
	if (data.adoptions as Dictionary).size()>=128:return fail("LOCAL_HISTORY_LIMIT_REACHED")
	var participants: Dictionary=data.participants
	if not participants.has(person_id):participants[person_id]=new_training_record(person_id,place_id)
	var record: Dictionary=participants[person_id]
	if str(record.place_id)!=place_id:return fail("TRAINING_ANCHOR_CHANGED_REQUIRES_EXPLICIT_NEW_MAPPING")
	var lease_id: String="%s-local-%d"%[str(data.branch_id),int(data.next_lease)]
	data.next_lease=int(data.next_lease)+1
	var context: Dictionary={"schema":"formal_local_binding_v1","person_id":person_id,"place_id":place_id,"vehicle_id":VEHICLE_ID,"native_vehicle_alias":"player_vehicle","mode":"training","georegistered":false,"resource_source":"prototype_vehicle_ammo_v1","body_source":BODY_SOURCE,"auxiliary_crew_source":CONTENT_SOURCE,"formal_individual_vehicle":false}
	var request: Dictionary=record.local.duplicate(true)
	request.merge({"schema":"wwo-local-lease-v1","source_kind":"FORMAL_WORLD_TRAINING","solver_owner":"godot_local","issuer_id":runtime_issuer,"session_id":str(data.branch_id),"lease_id":lease_id,"base_revision":int(data.revision),"region_id":preload("res://triple/space.gd").REGION_ID,"absolute_seconds":world.game_clock.total_minutes()*60+float(record.pending_seconds),"formal_context":context},true)
	data.active={"lease_id":lease_id,"person_id":person_id,"place_id":place_id,"start_minute":world.game_clock.total_minutes(),"base_revision":int(data.revision),"person_record":world.person_overlay.person(person_id),"request":request.duplicate(true)}
	issued_here[lease_id]=true
	return {"ok":true,"request":request}

func new_training_record(person_id: String,place_id: String) -> Dictionary:
	var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CONTENT_SOURCE))
	var crew: Array=template.crew.duplicate(true)
	for i: int in crew.size():
		crew[i].person_id=person_id if i==0 else "training_person:ridgevale_aux_%d"%i
		crew[i].display_name="正式玩家（训练身体）" if i==0 else "训练辅助%d"%i
		crew[i].hp=10.0;crew[i].alive=true
		crew[i].body_source=BODY_SOURCE
		for part: String in crew[i].parts:crew[i].parts[part]="healthy"
	var ammo:=new_ammo()
	var local: Dictionary={"crew":crew,"vehicle_id":VEHICLE_ID,"model_id":"user_heavy_mbt","position_local":template.position_local,"yaw":template.get("yaw",PI),"native_ammo":ammo.snapshot(),"local_elapsed":0.0,"shot_sequence":0,"shot_audit":[],"incoming_audit":[],"native_settled":{},"terrain_state":{"version":1,"source_id":"ridgevale_5km_c1_20261020","edits":[]}}
	return {"person_id":person_id,"place_id":place_id,"vehicle_id":VEHICLE_ID,"pending_seconds":0.0,"pending_usec":0,"accounted_local_usec":0,"local":local,"allocation_source":CONTENT_SOURCE,"adoption_count":0}

static func new_ammo() -> RefCounted:
	var ammo:=Ammo.new();ammo.new_battle(1)
	ammo.register_vehicle("player_vehicle",Ammo.Config.loadout("cannon"))
	return ammo

func adopt(result: Dictionary) -> Dictionary:
	if persistence!=null and persistence.is_save_in_progress():return fail("FORMAL_SAVE_IN_PROGRESS")
	var data:=state()
	var lease_id:=str(result.get("lease_id",""))
	if (data.adoptions as Dictionary).has(lease_id):
		var adopted: Dictionary=data.adoptions[lease_id]
		if result!=adopted.result:return fail("CONFLICTING_DUPLICATE")
		return {"ok":true,"duplicate":true,"revision":adopted.revision,"adoption_count":1}
	if not issued_here.has(lease_id):return fail("LEASE_REQUIRES_ISSUING_RUNTIME")
	var active: Dictionary=data.active
	if active.is_empty() or lease_id!=str(active.lease_id):return fail("STALE_OR_UNKNOWN_LEASE")
	if world.game_clock.total_minutes()!=int(active.start_minute) or int(data.revision)!=int(active.base_revision):return fail("STALE_WORLD_REVISION_OR_TIME")
	if world.person_overlay.person(str(active.person_id))!=active.person_record or world.player_state.player_id()!=str(active.person_id):return fail("FORMAL_PERSON_CHANGED")
	var reason:=result_error(result,active.request)
	if not reason.is_empty():return fail(reason)
	var participant: Dictionary=data.participants[active.person_id]
	var elapsed: float=float(result.local_elapsed)-float(active.request.local_elapsed)
	var cumulative_usec:=int(round(float(result.local_elapsed)*1000000.0))
	var delta_usec:=cumulative_usec-int(participant.accounted_local_usec)
	if delta_usec<0:return fail("LOCAL_TIME_ROLLBACK")
	var seconds_usec:=int(participant.pending_usec)+delta_usec
	var minutes:=int(seconds_usec/60000000)
	adopting=true
	var advanced: Dictionary=step.advance_minutes(minutes)
	adopting=false
	if not bool(advanced.get("success",true)):return fail("FORMAL_STEP_FAILED: "+str(advanced))
	participant.accounted_local_usec=cumulative_usec
	participant.pending_usec=seconds_usec%60000000
	participant.pending_seconds=participant.pending_usec/1000000.0
	participant.local=result.duplicate(true)
	participant.adoption_count=int(participant.adoption_count)+1
	data.revision=int(data.revision)+1
	data.adoptions[lease_id]={"revision":int(data.revision),"adoption_count":1,"person_id":str(active.person_id),"world_minute":world.game_clock.total_minutes(),"advanced_minutes":minutes,"pending_seconds":participant.pending_seconds,"result":result.duplicate(true)}
	data.active={}
	issued_here.erase(lease_id)
	return {"ok":true,"duplicate":false,"revision":int(data.revision),"adoption_count":1,"advanced_minutes":minutes,"pending_seconds":participant.pending_seconds}

static func result_error(result: Dictionary,request: Dictionary) -> String:
	for key: String in ["schema","session_id","lease_id","issuer_id","base_revision","region_id","formal_context","source_kind"]:
		if result.get(key)!=request.get(key):return "RETURN_CONTEXT_MISMATCH:"+key
	if result.get("solver_owner")!="host_pending_commit" or result.get("return_id")!=str(request.lease_id)+":return":return "INVALID_RETURN_OWNER"
	if result.get("vehicle_id")!=VEHICLE_ID or result.get("model_id")!="user_heavy_mbt":return "VEHICLE_MAPPING_MISMATCH"
	var elapsed: float=float(result.get("local_elapsed",-1))-float(request.local_elapsed)
	if not is_finite(elapsed) or elapsed<0 or elapsed>1800:return "INVALID_LOCAL_INTERVAL"
	if not is_finite(float(result.get("absolute_seconds",-1))) or absf(float(result.absolute_seconds)-float(request.absolute_seconds)-elapsed)>.001:return "LOCAL_TIME_MISMATCH"
	var position: Variant=result.get("position_local")
	if not position is Array or position.size()!=3:return "INVALID_LOCAL_POSITION"
	for value: Variant in position:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return "INVALID_LOCAL_POSITION"
	if absf(float(position[0]))>=2490 or absf(float(position[2]))>=2490:return "OUTSIDE_TRAINING_BATTLEFIELD"
	var crew: Variant=result.get("crew")
	if not crew is Array or crew.size()!=5:return "CREW_MAPPING_MISMATCH"
	for i: int in 5:
		if not crew[i] is Dictionary or crew[i].get("person_id")!=request.crew[i].person_id or crew[i].get("body_source")!=BODY_SOURCE:return "CREW_MAPPING_MISMATCH"
		if crew[i].get("location",{}).get("kind")!="vehicle" or crew[i].location.get("vehicle_id")!=VEHICLE_ID:return "UNFINISHED_SEAT_TRANSFER"
		if typeof(crew[i].get("hp")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(crew[i].hp)) or float(crew[i].hp)<0 or float(crew[i].hp)>10:return "INVALID_TRAINING_BODY"
		if not crew[i].get("alive") is bool or not crew[i].get("parts") is Dictionary or crew[i].parts.size()!=request.crew[i].parts.size():return "INVALID_TRAINING_BODY"
		for part: String in crew[i].parts:
			if not request.crew[i].parts.has(part) or crew[i].parts[part] not in ["healthy","injured","destroyed"]:return "INVALID_TRAINING_BODY"
	if not result.get("terrain_state") is Dictionary or not terrain_valid(result.terrain_state):return "INVALID_TRAINING_TERRAIN_STATE"
	var ammo:=new_ammo()
	var restored: Dictionary=ammo.restore(result.get("native_ammo",{}))
	if not restored.get("ok",false):return "INVALID_NATIVE_AMMO:"+str(restored)
	var before: Dictionary=request.native_ammo.vehicles.player_vehicle
	var after: Dictionary=result.native_ammo.vehicles.player_vehicle
	for mount: String in before:
		for round_type: String in before[mount].spent_rounds:
			if int(after[mount].spent_rounds[round_type])<int(before[mount].spent_rounds[round_type]):return "AMMO_REFILL_REJECTED"
	var new_shots: int=int(result.get("shot_sequence",-1))-int(request.shot_sequence)
	var spent:=0
	for mount: String in before:spent+=int(after[mount].spent)-int(before[mount].spent)
	if new_shots<0 or new_shots!=spent or not result.get("shot_audit") is Array or result.shot_audit.size()!=int(result.shot_sequence):return "SHOT_RESOURCE_MISMATCH"
	if result.shot_audit.size()>128:return "LOCAL_EVENT_WINDOW_EXCEEDED"
	for i: int in request.shot_audit.size():
		if result.shot_audit[i]!=request.shot_audit[i]:return "HISTORICAL_EVENT_CHANGED"
	var seen: Dictionary={}
	var cannon_count:=0
	for shot: Dictionary in result.shot_audit:
		var id:=int(shot.get("id",-1))
		if id<1 or seen.has(id) or not shot.get("accepted",false):return "UNSETTLED_OR_DUPLICATE_SHOT"
		if shot.get("weapon")=="tank_cannon":
			if shot.get("flight_state")!="impacted":return "UNSETTLED_OR_DUPLICATE_SHOT"
			cannon_count+=1
		seen[id]=true
	if not result.get("native_settled") is Dictionary or result.native_settled.size()!=cannon_count:return "UNSETTLED_SHOT_COUNT"
	for key: String in request.native_settled:
		if result.native_settled.get(key)!=request.native_settled[key]:return "HISTORICAL_SETTLEMENT_CHANGED"
	return LocalState.local_error(result,str(request.formal_context.person_id),true)

static func terrain_valid(value: Dictionary) -> bool:
	# Reuse the original replay parser without configuring meshes/collision.
	var terrain:=Terrain.new()
	terrain.source_id="ridgevale_5km_c1_20261020"
	var result: Dictionary=terrain.replay_state(value)
	terrain.free()
	return bool(result.get("ok",false))

func interrupt(lease_id: String) -> Dictionary:
	if persistence!=null and persistence.is_save_in_progress():return fail("FORMAL_SAVE_IN_PROGRESS")
	var data:=state();var active: Dictionary=data.active
	if active.is_empty() or str(active.lease_id)!=lease_id:return fail("STALE_OR_UNKNOWN_LEASE")
	data.interruptions.append({"lease_id":lease_id,"person_id":str(active.person_id),"world_minute":world.game_clock.total_minutes(),"adopted":false,"reason":"explicit_discard_uncommitted_interval"})
	data.active={};data.revision=int(data.revision)+1
	issued_here.erase(lease_id)
	return {"ok":true,"uncommitted_actions_discarded":true}

static func state_valid(data: Dictionary) -> bool:
	return LocalState.valid(data)

static func validate_references(value: WorldState) -> bool:
	return LocalState.references_error(value).is_empty()

func fail(reason: String) -> Dictionary:
	error=reason
	return {"ok":false,"reason":reason}
