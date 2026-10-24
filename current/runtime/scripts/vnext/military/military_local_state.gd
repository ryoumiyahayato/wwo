extends RefCounted
## Persistence contract for the bounded training capability. No solver or army stock.
const Ammo = preload("res://modules/vehicle_ammo/vehicle_ammo.gd")
const SCHEMA := "formal_local_operations_v2"
const TIME_POLICY := "formal_minutes_cumulative_local_usec_v1"
const VEHICLE := "training_vehicle:ridgevale_mbt_01"
const BODY := "TRAINING_BODY_NOT_FORMAL_MEDICAL_RECORD"
const CONTENT := "res://triple/default_request.json"
const PARTS := ["head","torso","left_arm","right_arm","left_leg","right_leg"]

static func empty_state() -> Dictionary:
	return {"schema":SCHEMA,"time_policy":TIME_POLICY,"branch_id":"formal-branch-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()],"next_lease":1,"revision":0,"participants":{},"active":{},"adoptions":{},"interruptions":[]}

static func migrate(raw: Dictionary) -> Dictionary:
	if raw.is_empty():return {"ok":true,"state":{},"from":"empty"}
	var data:=raw.duplicate(true)
	var previous:=str(data.get("schema",""))
	if previous=="formal_local_operations_v1":
		if not exact_keys(data,["schema","branch_id","next_lease","revision","participants","active","adoptions","interruptions"]) or not data.participants is Dictionary:return failure("INVALID_V1_FIELDS")
		for id: Variant in data.participants:
			var p: Variant=data.participants[id]
			if not p is Dictionary or not p.get("local") is Dictionary or not number(p.local.get("local_elapsed")) or not number(p.get("pending_seconds")):return failure("INVALID_V1_TIME")
			p.accounted_local_usec=int(round(float(p.local.local_elapsed)*1000000.0))
			p.pending_usec=int(round(float(p.pending_seconds)*1000000.0))
			# Legacy floating seconds close enough to a minute retain that boundary.
			if p.pending_usec>=60000000:return failure("AMBIGUOUS_V1_MINUTE_BOUNDARY")
			p.pending_seconds=p.pending_usec/1000000.0
		data.schema=SCHEMA;data.time_policy=TIME_POLICY
	elif previous!=SCHEMA:return failure("UNKNOWN_LOCAL_SCHEMA:"+previous)
	var reason:=error(data)
	if not reason.is_empty():return failure(reason)
	return {"ok":true,"state":data,"from":previous}

static func valid(data: Dictionary) -> bool:
	return error(data).is_empty()

static func error(data: Dictionary) -> String:
	if data.is_empty():return ""
	if not exact_keys(data,["schema","time_policy","branch_id","next_lease","revision","participants","active","adoptions","interruptions"]):return "UNKNOWN_LOCAL_FIELDS"
	if data.schema!=SCHEMA or data.time_policy!=TIME_POLICY:return "UNKNOWN_TIME_POLICY_OR_SCHEMA"
	if not data.branch_id is String or not str(data.branch_id).is_valid_filename() or not str(data.branch_id).begins_with("formal-branch-"):return "INVALID_BRANCH"
	if not integer(data.next_lease) or data.next_lease<1 or not integer(data.revision):return "INVALID_LOCAL_REVISION"
	if not data.participants is Dictionary or data.participants.size()>1 or not data.active is Dictionary or not data.adoptions is Dictionary or data.adoptions.size()>128 or not data.interruptions is Array:return "INVALID_BOUNDED_STATE"
	if int(data.revision)!=data.adoptions.size()+data.interruptions.size() or int(data.next_lease)!=int(data.revision)+1+int(not data.active.is_empty()):return "LEASE_SEQUENCE_MISMATCH"
	var by_person: Dictionary={}
	var seen: Dictionary={}
	for lease: Variant in data.adoptions:
		var a: Variant=data.adoptions[lease]
		var serial:=lease_serial(str(lease),data.branch_id)
		if serial<1 or serial>=int(data.next_lease) or seen.has(serial) or not a is Dictionary:return "INVALID_ADOPTION_ID"
		seen[serial]=true
		if not exact_keys(a,["revision","adoption_count","person_id","world_minute","advanced_minutes","pending_seconds","result"]) or int(a.revision)!=serial or a.adoption_count!=1 or not integer(a.world_minute) or not integer(a.advanced_minutes) or not number(a.pending_seconds) or a.pending_seconds<0 or a.pending_seconds>=60:return "INVALID_ADOPTION_RECORD"
		if not data.participants.has(a.person_id) or not a.result is Dictionary or a.result.get("lease_id")!=lease:return "ADOPTION_PERSON_OR_LEASE_MISMATCH"
		var reason:=local_error(a.result,str(a.person_id),true)
		if not reason.is_empty():return reason
		if a.result.get("session_id")!=data.branch_id or a.result.get("base_revision")!=serial-1:return "ADOPTION_BRANCH_OR_REVISION_MISMATCH"
		if absf(float(a.result.absolute_seconds)-(int(a.world_minute)*60.0+float(a.pending_seconds)))>0.000002:return "ADOPTION_CLOCK_MISMATCH"
		if not by_person.has(a.person_id):by_person[a.person_id]=[]
		by_person[a.person_id].append(a)
	for item: Variant in data.interruptions:
		if not item is Dictionary or not exact_keys(item,["lease_id","person_id","world_minute","adopted","reason"]):return "INVALID_INTERRUPTION"
		var serial:=lease_serial(str(item.lease_id),data.branch_id)
		if serial<1 or serial>=int(data.next_lease) or seen.has(serial) or not data.participants.has(item.person_id) or not integer(item.world_minute) or item.adopted!=false or item.reason!="explicit_discard_uncommitted_interval":return "INVALID_INTERRUPTION"
		seen[serial]=true
	for id: Variant in data.participants:
		var p: Variant=data.participants[id]
		if not id is String or not p is Dictionary or not exact_keys(p,["person_id","place_id","vehicle_id","pending_seconds","pending_usec","accounted_local_usec","local","allocation_source","adoption_count"]):return "INVALID_PARTICIPANT_FIELDS"
		if p.person_id!=id or p.vehicle_id!=VEHICLE or p.allocation_source!=CONTENT or not p.place_id is String or not str(p.place_id).begins_with("place:"):return "UNKNOWN_TRAINING_PROVENANCE"
		if not integer(p.accounted_local_usec) or not integer(p.pending_usec) or p.pending_usec>=60000000 or not number(p.pending_seconds) or absf(float(p.pending_seconds)-p.pending_usec/1000000.0)>0.0000001:return "INVALID_COMMITTED_FRACTION"
		if not p.local is Dictionary:return "INVALID_LOCAL_RECORD"
		var history: Array=by_person.get(id,[])
		history.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return int(a.revision)<int(b.revision))
		if p.adoption_count!=history.size():return "ADOPTION_COUNT_MISMATCH"
		var reason:=local_error(p.local,id,not history.is_empty())
		if not reason.is_empty():return reason
		if int(round(float(p.local.local_elapsed)*1000000.0))!=p.accounted_local_usec:return "LOCAL_ELAPSED_ROLLBACK"
		if history.is_empty():
			if p.accounted_local_usec!=0 or p.pending_usec!=0 or int(p.local.shot_sequence)!=0:return "UNBACKED_INITIAL_TRAINING_STATE"
		else:
			var last: Dictionary=history.back()
			if p.local!=last.result or absf(float(last.pending_seconds)-float(p.pending_seconds))>0.000002:return "COMMITTED_STATE_OR_INVENTORY_ROLLBACK"
		var previous: Dictionary={}
		for a: Dictionary in history:
			if not previous.is_empty():
				if int(a.world_minute)<int(previous.world_minute) or float(a.result.local_elapsed)<float(previous.result.local_elapsed):return "HISTORY_TIME_ROLLBACK"
				if not ammo_monotonic(previous.result.native_ammo,a.result.native_ammo):return "HISTORY_AMMO_ROLLBACK"
				for i: int in previous.result.shot_audit.size():
					if a.result.shot_audit.size()<=i or a.result.shot_audit[i]!=previous.result.shot_audit[i]:return "HISTORY_EVENT_REWRITE"
			previous=a
	var active: Dictionary=data.active
	if not active.is_empty():
		if not exact_keys(active,["lease_id","person_id","place_id","start_minute","base_revision","person_record","request"]) or not data.participants.has(active.person_id) or active.base_revision!=data.revision or not integer(active.start_minute):return "INVALID_ACTIVE_LEASE"
		var serial:=lease_serial(str(active.lease_id),data.branch_id)
		if serial!=int(data.next_lease)-1 or seen.has(serial):return "INVALID_ACTIVE_SEQUENCE"
		seen[serial]=true
		var p: Dictionary=data.participants[active.person_id]
		if active.place_id!=p.place_id or not active.request is Dictionary or not active.person_record is Dictionary:return "ACTIVE_MAPPING_MISMATCH"
		var request: Dictionary=active.request
		if request.get("lease_id")!=active.lease_id or request.get("session_id")!=data.branch_id or request.get("base_revision")!=data.revision or request.get("solver_owner")!="godot_local":return "ACTIVE_REQUEST_MISMATCH"
		if not context_valid(request.get("formal_context"),str(active.person_id)) or request.formal_context.place_id!=p.place_id:return "ACTIVE_CONTEXT_MISMATCH"
		for key: String in p.local:
			if key in ["schema","source_kind","solver_owner","session_id","lease_id","issuer_id","base_revision","absolute_seconds","formal_context","return_id","region_id"]:continue
			if request.get(key)!=p.local[key]:return "ACTIVE_INVENTORY_OR_BODY_CHANGED"
		if not number(request.get("absolute_seconds")) or absf(float(request.absolute_seconds)-(int(active.start_minute)*60.0+float(p.pending_seconds)))>0.000002:return "ACTIVE_CLOCK_MISMATCH"
	if seen.size()!=int(data.next_lease)-1:return "MISSING_LEASE_HISTORY"
	return ""

static func local_error(local: Dictionary,person_id: String,returned: bool) -> String:
	if local.get("vehicle_id")!=VEHICLE or local.get("model_id")!="user_heavy_mbt":return "UNKNOWN_VEHICLE_PROVENANCE"
	if not number(local.get("local_elapsed")) or local.local_elapsed<0 or not integer(local.get("shot_sequence")):return "INVALID_LOCAL_TIME_OR_EVENT_SEQUENCE"
	var position: Variant=local.get("position_local")
	if not position is Array or position.size()!=3:return "INVALID_POSITION"
	for value: Variant in position:
		if not number(value):return "INVALID_POSITION"
	if absf(float(position[0]))>=2490 or absf(float(position[2]))>=2490:return "OUTSIDE_TRAINING_AREA"
	var crew: Variant=local.get("crew")
	if not crew is Array or crew.size()!=5:return "INVALID_CREW"
	for i: int in 5:
		var b: Variant=crew[i]
		var id:=person_id if i==0 else "training_person:ridgevale_aux_%d"%i
		if not b is Dictionary or b.get("person_id")!=id or b.get("body_source")!=BODY or not b.get("alive") is bool or not number(b.get("hp")) or b.hp<0 or b.hp>10 or not b.get("parts") is Dictionary or b.parts.size()!=6:return "INVALID_TRAINING_BODY"
		for part: String in PARTS:
			if b.parts.get(part) not in ["healthy","injured","destroyed"]:return "UNKNOWN_BODY_PART_STATE"
		if returned and (not b.get("location") is Dictionary or b.location.get("kind")!="vehicle" or b.location.get("vehicle_id")!=VEHICLE):return "UNFINISHED_CREW_TRANSFER"
	var native: Variant=local.get("native_ammo")
	if not native is Dictionary:return "INVALID_AMMO"
	var ammo:=new_ammo()
	if not ammo.restore(native).get("ok",false):return "INVALID_OR_UNKNOWN_AMMO_ALLOCATION"
	if not local.get("shot_audit") is Array or local.shot_audit.size()!=int(local.shot_sequence) or local.shot_audit.size()>128 or not local.get("native_settled") is Dictionary:return "INVALID_EVENT_HISTORY"
	var spent:=0
	for pool: Dictionary in native.vehicles.player_vehicle.values():spent+=int(pool.spent)
	if spent!=int(local.shot_sequence):return "SHOT_RESOURCE_MISMATCH"
	var settled_shots: Dictionary={}
	for key: Variant in local.native_settled:
		if not key is String or local.native_settled[key]!=true:return "INVALID_SETTLEMENT_KEY"
		var pieces: PackedStringArray=key.split(":")
		if pieces.size()!=2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int() or int(pieces[0])<0 or int(pieces[1])<1 or settled_shots.has(int(pieces[1])):return "INVALID_SETTLEMENT_KEY"
		# The original shell owner uses stage_generation:shot_id, not ammo epoch.
		settled_shots[int(pieces[1])]=true
	var cannon:=0
	for i: int in local.shot_audit.size():
		var shot: Variant=local.shot_audit[i]
		if not shot is Dictionary or shot.get("id")!=i+1 or shot.get("accepted")!=true:return "INVALID_EVENT_ID"
		if shot.get("weapon")=="tank_cannon":
			if shot.get("flight_state")!="impacted" or not integer(shot.get("ammo_commit")) or not settled_shots.has(int(shot.id)):return "UNSETTLED_EVENT"
			cannon+=1
	if local.native_settled.size()!=cannon:return "UNBACKED_SETTLEMENT"
	if not terrain_valid(local.get("terrain_state")):return "INVALID_TERRAIN_REPLAY"
	if returned:
		if local.get("schema")!="wwo-local-lease-v1" or local.get("source_kind")!="FORMAL_WORLD_TRAINING" or local.get("solver_owner")!="host_pending_commit" or local.get("return_id")!=str(local.get("lease_id"))+":return" or not number(local.get("absolute_seconds")) or not context_valid(local.get("formal_context"),person_id):return "UNKNOWN_RETURN_CONTEXT"
	return ""

static func context_valid(value: Variant,person_id: String) -> bool:
	return value is Dictionary and value.get("schema")=="formal_local_binding_v1" and value.get("person_id")==person_id and value.get("vehicle_id")==VEHICLE and value.get("native_vehicle_alias")=="player_vehicle" and value.get("mode")=="training" and value.get("georegistered")==false and value.get("formal_individual_vehicle")==false and value.get("resource_source")=="prototype_vehicle_ammo_v1" and value.get("body_source")==BODY and value.get("auxiliary_crew_source")==CONTENT

static func references_error(world) -> String:
	var data: Dictionary=world.military_state.local_operations
	var reason:=error(data)
	if not reason.is_empty() or data.is_empty():return reason
	var minute: int=world.game_clock.total_minutes()
	for id: String in data.participants:
		if not world.person_overlay.has_person(id) or world.spatial_world.get_place(str(data.participants[id].place_id)).is_empty():return "UNKNOWN_FORMAL_PERSON_OR_PLACE"
	for a: Dictionary in data.adoptions.values():
		if minute<int(a.world_minute):return "FORMAL_CLOCK_BEFORE_COMMITTED_LOCAL_STATE"
	for i: Dictionary in data.interruptions:
		if minute<int(i.world_minute):return "FORMAL_CLOCK_BEFORE_INTERRUPTION"
	if not data.active.is_empty():
		var active: Dictionary=data.active
		if minute!=int(active.start_minute) or world.player_state.player_id()!=str(active.person_id) or world.person_overlay.person(str(active.person_id))!=active.person_record:return "ACTIVE_FORMAL_PERSON_OR_CLOCK_CHANGED"
	return ""

static func terrain_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1 or value.get("source_id")!="ridgevale_5km_c1_20261020" or not value.get("edits") is Array or value.edits.size()>120000:return false
	var seen: Dictionary={}
	for row: Variant in value.edits:
		if not row is Array or row.size()!=3:return false
		for x: Variant in row:
			if not number(x):return false
		if row[0]!=round(float(row[0])) or row[1]!=round(float(row[1])) or absf(float(row[0]))>2500 or absf(float(row[1]))>2500 or row[2]>0 or row[2]<-4:return false
		var key:=Vector2i(int(row[0]),int(row[1]))
		if seen.has(key):return false
		seen[key]=true
	return true

static func ammo_monotonic(before: Dictionary,after: Dictionary) -> bool:
	for mount: String in before.vehicles.player_vehicle:
		for round_type: String in before.vehicles.player_vehicle[mount].spent_rounds:
			if int(after.vehicles.player_vehicle[mount].spent_rounds[round_type])<int(before.vehicles.player_vehicle[mount].spent_rounds[round_type]):return false
	return true

static func new_ammo() -> RefCounted:
	var ammo:=Ammo.new();ammo.new_battle(1);ammo.register_vehicle("player_vehicle",Ammo.Config.loadout("cannon"));return ammo

static func lease_serial(lease: String,branch: String) -> int:
	var prefix:=branch+"-local-"
	var suffix:=lease.trim_prefix(prefix)
	return int(suffix) if lease.begins_with(prefix) and suffix.is_valid_int() and str(int(suffix))==suffix else -1

static func exact_keys(value: Dictionary,keys: Array) -> bool:
	return value.size()==keys.size() and value.has_all(keys)

static func number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and absf(float(value))<9007199254740991.0

static func integer(value: Variant) -> bool:
	return number(value) and float(value)>=0 and float(value)==floorf(float(value))

static func failure(reason: String) -> Dictionary:
	return {"ok":false,"state":{},"error":reason}
