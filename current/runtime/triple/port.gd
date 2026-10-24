extends RefCounted
## Narrow file contract. Imported bodies are patched into native shared references once.
const SCHEMA := "wwo-local-lease-v1"
var request: Dictionary = {}
var installed := false
var closed := false
var returned: Dictionary = {}
var error := ""

func read_request(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "请求不是JSON对象"
		return false
	request = parsed
	if request.get("schema") != SCHEMA or request.get("source_kind") != "SYNTHETIC_ISOLATED_HOST" or request.get("solver_owner") != "godot_local" or request.get("region_id") != preload("res://triple/space.gd").REGION_ID:
		error = "接口版本、空间或唯一求解owner不匹配"
		return false
	if str(request.get("lease_id", "")).is_empty() or str(request.get("session_id", "")).is_empty() or not request.get("crew") is Array or request.crew.size()!=5:
		error = "缺少租约或五人原车组"
		return false
	for i: int in 5:
		var person: Variant = request.crew[i]
		if not person is Dictionary or person.get("person_id") != "player_vehicle:person:%d" % i or not person.get("parts") is Dictionary or not person.get("alive") is bool or not person.get("hp") is float and not person.get("hp") is int:
			error = "本接续切片只接受原车组稳定ID和身体状态"
			return false
		if not is_finite(float(person.hp)) or float(person.hp)<0 or float(person.hp)>10:
			error = "身体状态无效"
			return false
	if not request.get("position_local") is Array or request.position_local.size()!=3:
		error = "缺少米制位置"
		return false
	for value: Variant in request.position_local:
		if not (value is float or value is int) or not is_finite(float(value)):
			error = "非有限坐标"
			return false
	if absf(float(request.position_local[0]))>=2490 or absf(float(request.position_local[2]))>=2490:
		error = "位置超出已制作战场"
		return false
	if path.begins_with("res://"):
		# F5 explicitly opens a new isolated sample, never reuses an external lease.
		request.session_id="sample-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
		request.lease_id="sample-local-%d"%Time.get_ticks_usec()
	else:
		if not str(request.lease_id).is_valid_filename() or not str(request.session_id).is_valid_filename():
			error="租约ID格式无效"
			return false
		var directory:=ProjectSettings.globalize_path("user://leases")
		DirAccess.make_dir_recursive_absolute(directory)
		var claim_path:=directory+"/"+str(request.session_id)+"_"+str(request.lease_id)
		if DirAccess.make_dir_absolute(claim_path)!=OK:
			error="该传入文件已由局部实例领取。请使用宿主签发的新租约文件。"
			return false
	return true

func install(battle: Node) -> bool:
	if installed: return false
	# Validate the native ammo candidate before mutating any person.
	var ammo: Dictionary = battle.vehicle_ammo.snapshot()
	if request.has("native_ammo"):
		ammo = request.native_ammo.duplicate(true)
	else:
		var pool: Dictionary = ammo.vehicles.player_vehicle.primary
		for kind: String in pool.reserve:
			var spent := int(request.get("prior_spent",{}).get(kind,0))
			if spent<0 or spent>int(pool.reserve[kind]):
				error="传入消耗超出原生装载"
				return false
			pool.reserve[kind]-=spent
			pool.spent_rounds[kind]=spent
			pool.spent+=spent
		pool.last_commit=1 if pool.spent>0 else 0
		ammo.sequence=1 if pool.spent>0 else 0
	var result: Dictionary = battle.vehicle_ammo.restore(ammo)
	if not result.get("ok",false):
		error = str(result)
		return false
	for i: int in 5:
		var person: Dictionary = battle.player_combat.crew[i]
		var location: Dictionary = person.location
		person.merge(request.crew[i].duplicate(true),true)
		person.location=location
	if request.has("vehicle_modules"): battle.player_combat.modules=request.vehicle_modules.duplicate(true)
	if request.has("player_rng_state"): battle.player_combat.rng.state=int(request.player_rng_state)
	var p: Array = request.position_local
	battle.hero.position=Vector3(p[0],p[1],p[2])
	battle.hero.rotation.y=float(request.get("yaw",PI))
	battle.align_vehicle_ground(battle.hero)
	battle.elapsed=float(request.get("local_elapsed",0))
	battle.shot_sequence=int(request.get("shot_sequence",0))
	battle.shot_audit=request.get("shot_audit",[]).duplicate(true)
	battle.incoming_audit=request.get("incoming_audit",[]).duplicate(true)
	battle.tank_shell_fire.settled=request.get("native_settled",{}).duplicate(true)
	if request.has("terrain_state"):
		var replay: Dictionary=battle.terrain_damage.replay_state(request.terrain_state)
		if not replay.get("ok",false):
			error=str(replay)
			return false
	battle.continuity_bound=true
	installed=true
	return true

func snapshot(battle: Node) -> Dictionary:
	var position: Vector3 = battle.hero.position
	return pack({"schema":SCHEMA,"session_id":request.session_id,"lease_id":request.lease_id,
		"region_id":request.region_id,"base_revision":request.base_revision,
		"vehicle_id":"player_vehicle","model_id":battle.selected_catalog_id,
		"crew":battle.player_combat.crew,"registry":battle.crew_host.registry.serialize(),
		"position_local":position,"position_region":preload("res://triple/space.gd").world_position(position),
		"yaw":battle.hero.rotation.y,"native_ammo":battle.vehicle_ammo.snapshot(),
		"vehicle_modules":battle.player_combat.modules,"player_rng_state":str(battle.player_combat.rng.state),
		"local_elapsed":battle.elapsed,"absolute_seconds":float(request.absolute_seconds)+battle.elapsed-float(request.get("local_elapsed",0)),
		"shot_sequence":battle.shot_sequence,"shot_audit":battle.shot_audit,
		"incoming_audit":battle.incoming_audit,"terrain_state":battle.terrain_damage.save_state(),
		"native_settled":battle.tank_shell_fire.settled,"actor_count":battle.ai_host.actors.size(),
		"hero_instance":battle.hero.get_instance_id(),"crew_owner_instance":battle.crew_host.get_instance_id(),
		"source_kind":"SYNTHETIC_ISOLATED_HOST","solver_owner":"godot_local"})

func export_return(battle: Node, path: String) -> bool:
	if not installed or closed:
		error="租约未安装或已经交还"
		return false
	if not battle.get_tree().get_nodes_in_group("artillery_projectile").is_empty() or not battle.terrain_explosion_outbox.is_empty() or not battle.terrain_damage.jobs.is_empty() or not battle.terrain_damage.pending.is_empty() or is_instance_valid(battle.smoke_root):
		error="局部仍有飞行弹、烟幕或地形事务。返回战场待其完成后再交还。"
		return false
	if battle.player_infantry_controller.active() or not battle.crew_host.pending_returns.is_empty():
		error="有限文件接续仅支持全员原座。请先完成上下车动作。"
		return false
	for person: Dictionary in battle.player_combat.crew:
		if person.location.kind!="vehicle":
			error="有限文件接续仅支持全员原座"
			return false
	returned=snapshot(battle)
	returned["return_id"]=str(request.lease_id)+":return"
	returned["solver_owner"]="host_pending_commit"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		error="无法写入交还文件"
		return false
	file.store_string(JSON.stringify(returned,"\t"))
	file.close()
	closed=true
	return true

static func pack(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[str(key)]=pack(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(pack(item))
		return result
	return value
