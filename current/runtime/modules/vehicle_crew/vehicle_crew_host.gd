extends Node
## Current game's adapter. Registry itself is portable to other vehicles/WWO.
const Registry = preload("res://modules/vehicle_crew/crew_registry.gd")
const Clearance = preload("res://modules/vehicle_crew/exit_clearance.gd")
const ROLE_MAP := {"车长": "commander", "炮手": "gunner", "驾驶员": "driver", "装填手": "loader", "无线电员": "radio", "通讯员": "radio"}
var main: Node3D
var registry = Registry.new()
var vehicle_id := "player_vehicle"
var person_ids: Array[String] = []
var role_labels: Array = []
var toggle: Button
var panel: PanelContainer
var picker: OptionButton
var status_label: Label
var expanded := false
var _tick := 0.0
var pending_returns: Dictionary = {}
var last_batch: Dictionary = {}
var _batch_sequence := 0
var _takeover_remaining := 0.0
var _takeover_person := ""
var _takeover_start_hp := 0.0
const TAKEOVER_SECONDS := 2.5
const TAKEOVER_RELOAD_MULTIPLIER := 1.35
const TAKEOVER_OBSERVATION_MULTIPLIER := 0.65
const RETURN_STALL_SECONDS := 12.0
const REASONS := {"vehicle_moving":"车辆仍在移动，请先停车", "boarding_obstructed":"人与车辆之间有障碍，请走到车旁", "unsafe_exit":"出口被阻挡或没有安全地面", "boarding_denied":"乘员须在车旁6米内", "dead_person":"阵亡乘员不能转移", "occupied_seat":"座位已占用", "not_aboard":"乘员已在车外", "already_aboard":"乘员已在车内", "actor_unavailable":"乘员实体不可用", "construction_busy":"正在执行工程订单，未改派", "return_injured":"回车途中受伤，已取消回车", "return_blocked":"回车路径受阻，已停止回车", "actor_changed":"乘员实体已变更，已取消回车", "vehicle_changed":"车辆已变更，已取消回车", "scene_changed":"场景已重置，已取消回车", "return_immobile":"乘员无法行走", "unknown_person":"未知乘员"}

func setup(owner_main: Node3D) -> void:
	main = owner_main
	_make_ui()

func on_stage_reset() -> void:
	_takeover_remaining = 0.0
	_takeover_person = ""
	for pid in pending_returns.keys(): _finish_return(pid, {"ok":false, "reason":"scene_changed"}, false)
	last_batch.clear()
	registry = Registry.new()
	person_ids.clear()
	role_labels.clear()
	if is_instance_valid(picker): picker.clear()

func bind_player() -> void:
	on_stage_reset()
	if main.get("player_combat") == null or main.get("ai_host") == null or not is_instance_valid(main.hero): return
	if int(main.get("unit")) == 2: return
	var combat = main.player_combat
	var roles: Array = []
	role_labels = combat.crew_roles.duplicate()
	var fallback := ["commander", "gunner", "driver", "loader", "radio"]
	for i in role_labels.size(): roles.append(ROLE_MAP.get(str(role_labels[i]), fallback[i]))
	var result: Dictionary = registry.bind_vehicle(vehicle_id, roles, combat.crew, {"requires_loader": roles.has("loader"), "missing_loader_reload_multiplier": 1.5})
	if not result.ok:
		_note("乘员绑定失败：" + str(result.reason))
		return
	for i in combat.crew.size():
		var person: Dictionary = combat.crew[i]
		var pid := str(person.person_id)
		person_ids.append(pid)
		main.ai_host.register_bound_crew(pid, person, main.hero.global_position, roles[i])
		picker.add_item(str(role_labels[i]), i)
	_refresh()

func can_fire() -> bool:
	return person_ids.is_empty() or registry.can_fire(vehicle_id)

func can_drive() -> bool:
	return not person_ids.is_empty() and registry.can_drive(vehicle_id)

func reload_multiplier() -> float:
	return registry.reload_multiplier(vehicle_id) * (TAKEOVER_RELOAD_MULTIPLIER if bool(takeover_status().active) else 1.0)

func disembark_person(person_id: String) -> Dictionary:
	if is_instance_valid(main.hero) and absf(float(main.hero.get_meta("vehicle_speed",0.0)))>0.5: return {"ok":false,"reason":"vehicle_moving"}
	if not _actor_exists(person_id): return {"ok": false, "reason": "actor_unavailable"}
	var actor = main.ai_host.actors[person_id]
	if not actor.embarked: return {"ok": false, "reason": "not_aboard"}
	# Test multiple exits; never put actors inside ground, tank or scenery.
	var exits:Array=[]
	for marker in main.hero.find_children("Exit*","Node3D",true,false):exits.append(main.hero.to_local(marker.global_position))
	exits.append_array([Vector3(3,0,0), Vector3(-3,0,0), Vector3(0,0,4), Vector3(0,0,-4), Vector3(4.5,0,2), Vector3(-4.5,0,-2)])
	for offset in exits:
		var point: Vector3 = main.hero.global_position + main.hero.global_basis * offset
		point.y = main.terrain_height(point.x, point.z) + 0.12
		var result: Dictionary = registry.disembark(person_id, point, _safe_exit)
		if result.ok:
			main.ai_host.set_crew_embarked(person_id, false, point)
			_refresh()
			return result
		if str(result.reason) != "unsafe_exit": return result
	return {"ok": false, "reason": "unsafe_exit"}

func embark_person(person_id: String) -> Dictionary:
	var index := person_ids.find(person_id)
	if index < 0: return {"ok": false, "reason": "unknown_person"}
	if _actor_exists(person_id) and _construction_busy(main.ai_host.actors[person_id]): return {"ok":false, "reason":"construction_busy"}
	var result: Dictionary = registry.embark(person_id, vehicle_id, str(index), _boarding_allowed)
	if str(result.get("reason",""))=="boarding_denied":
		var access := boarding_access(person_id)
		if not access.ok: result["reason"] = access.reason
	if result.ok:
		main.ai_host.set_crew_embarked(person_id, true, main.hero.global_position)
		_clear_return_metadata(person_id)
	_refresh()
	return result

func _actor_exists(person_id: String) -> bool:
	return is_instance_valid(main) and main.get("ai_host") != null and main.ai_host.actors.has(person_id) and is_instance_valid(main.ai_host.actors[person_id])

func _safe_exit(person_id: String, _vehicle: String, point: Vector3) -> bool:
	if not _actor_exists(person_id): return false
	# Physics queries can lag transforms/collision reactivation until the next tick.
	# Reserve against the live scene immediately so a batch cannot select one exit twice.
	for other_id in main.ai_host.actors:
		if str(other_id) == person_id: continue
		var other = main.ai_host.actors[other_id]
		if not is_instance_valid(other) or other.embarked: continue
		var offset: Vector3 = other.global_position - point
		if absf(offset.y) < 1.85 and Vector2(offset.x,offset.z).length() < 0.8: return false
	var exclude: Array[RID] = [main.ai_host.actors[person_id].get_rid()]
	var space := main.get_world_3d().direct_space_state
	if not Clearance.is_safe(space, point, exclude, 0xFFFFFFFF): return false
	# Validate exactly the enabled actor capsule at the final spawn transform too.
	# The generic conservative clearance shape uses a different bottom offset.
	var actor = main.ai_host.actors[person_id]
	var body_shape := actor.get_node_or_null("BodyCollision") as CollisionShape3D
	if body_shape == null or body_shape.shape == null: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape.shape
	query.transform = Transform3D(actor.global_basis, point) * body_shape.transform
	query.collision_mask = 0xFFFFFFFF
	query.exclude = exclude
	query.margin = 0.001
	return space.intersect_shape(query, 1).is_empty()

## Only the registered original vehicle is legal in this increment. No body/vehicle hopping.
func boarding_access(person_id: String) -> Dictionary:
	if not _actor_exists(person_id) or not is_instance_valid(main.hero): return {"ok":false,"reason":"actor_unavailable"}
	var actor = main.ai_host.actors[person_id]
	if actor.embarked: return {"ok":false,"reason":"already_aboard"}
	if actor.global_position.distance_to(main.hero.global_position)>6.0: return {"ok":false,"reason":"boarding_denied"}
	if absf(float(main.hero.get_meta("vehicle_speed",0.0)))>0.5: return {"ok":false,"reason":"vehicle_moving"}
	var excludes: Array[RID] = [actor.get_rid()]
	if main.hero is CollisionObject3D: excludes.append(main.hero.get_rid())
	for body in main.hero.find_children("*","CollisionObject3D",true,false): excludes.append(body.get_rid())
	var start: Vector3 = actor.global_position+Vector3.UP*1.0
	var end: Vector3 = main.hero.global_position+Vector3.UP*1.0
	# Terrain/structure obstruction only; moving infantry are not boarding walls.
	var query := PhysicsRayQueryParameters3D.create(start,end,1|8,excludes)
	if not main.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return {"ok":false,"reason":"boarding_obstructed"}
	return {"ok":true}

func _boarding_allowed(person_id: String, _vehicle: String, _seat: String) -> bool:
	return bool(boarding_access(person_id).ok)

func report_transfer(result: Dictionary, success_text: String) -> void:
	_note(success_text if bool(result.get("ok",false)) else str(REASONS.get(result.get("reason",""),result.get("reason",""))))

func request_commander_exit() -> Dictionary:
	var result := disembark_person(commander_person_id())
	if result.ok and main.has_method("toggle_scope") and bool(main.get("scoped")): main.toggle_scope()
	report_transfer(result,"车长已下车 · 原车组继续留岗")
	return result

func _make_ui() -> void:
	toggle = Button.new()
	toggle.text = "乘员上下车"
	toggle.position = Vector2(1070,270)
	toggle.size = Vector2(182,43)
	main.hud.add_child(toggle)
	toggle.pressed.connect(func(): expanded = not expanded; _refresh())
	panel = PanelContainer.new()
	panel.position = Vector2(750,310)
	panel.z_index = 40
	var background:=StyleBoxFlat.new();background.bg_color=Color(.055,.085,.10,.97);background.border_color=Color(.5,.65,.7,.7);background.set_border_width_all(1);background.set_corner_radius_all(8);panel.add_theme_stylebox_override("panel",background)
	panel.custom_minimum_size = Vector2(247,225)
	main.hud.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	picker = OptionButton.new()
	column.add_child(picker)
	picker.item_selected.connect(func(_i): _refresh())
	for spec in [["所选下车", false, false], ["所选上车", true, false], ["全员下车", false, true], ["全员上车", true, true]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size.y = 36
		column.add_child(button)
		button.pressed.connect(_transfer_pressed.bind(bool(spec[1]), bool(spec[2])))
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 235
	column.add_child(status_label)
	_refresh()

func _transfer_pressed(board: bool, all_people: bool) -> void:
	var selected: Array = person_ids.duplicate() if all_people else ([person_ids[picker.selected]] if picker.selected >= 0 and picker.selected < person_ids.size() else [])
	_batch_sequence += 1
	last_batch = {"id":_batch_sequence, "board":board, "success":0, "pending":0, "failures":{}}
	for pid in selected:
		var result: Dictionary = request_embark(pid, _batch_sequence) if board else disembark_person(pid)
		_record_batch_result(result)
	expanded = false
	if (int(last_batch.success)>0 or int(last_batch.pending)>0) and main.has_method("toggle_scope") and bool(main.get("scoped")): main.toggle_scope()
	_refresh()
	_note(batch_summary(last_batch))

func _record_batch_result(result: Dictionary) -> void:
	if bool(result.get("pending",false)): last_batch.pending += 1
	elif bool(result.get("ok",false)): last_batch.success += 1
	else:
		var reason := str(result.get("reason","unknown_person"))
		last_batch.failures[reason] = int(last_batch.failures.get(reason,0)) + 1

func batch_summary(batch: Dictionary) -> String:
	var pieces: Array[String] = ["%d人已%s" % [int(batch.get("success",0)), "上车" if bool(batch.get("board",true)) else "下车"]]
	if int(batch.get("pending",0))>0: pieces.append("%d人正在走回车旁" % int(batch.pending))
	for reason in batch.get("failures",{}):
		pieces.append("%d人：%s" % [int(batch.failures[reason]), str(REASONS.get(reason,reason))])
	return "；".join(pieces)

## Queue real physical return only after immediate boarding fails for distance.
func request_embark(person_id: String, batch_id: int = -1) -> Dictionary:
	if pending_returns.has(person_id):
		pending_returns[person_id].batch_id = batch_id
		return {"ok":false, "pending":true, "reason":"returning"}
	var immediate := embark_person(person_id)
	if immediate.ok or str(immediate.get("reason","")) != "boarding_denied": return immediate
	if not _actor_exists(person_id): return {"ok":false, "reason":"actor_unavailable"}
	var actor = main.ai_host.actors[person_id]
	# The canonical player walks back manually, never through an AI return order.
	if bool(actor.get_meta("player_controlled",false)): return immediate
	if _construction_busy(actor): return {"ok":false, "reason":"construction_busy"}
	if not actor.is_physics_processing() or float(actor.move_speed)<=0.0: return {"ok":false, "reason":"return_immobile"}
	var p: Dictionary = registry.person_ref(person_id)
	if p.parts.get("left_leg", "healthy") == "disabled" and p.parts.get("right_leg", "healthy") == "disabled": return {"ok":false, "reason":"return_immobile"}
	var distance: float = actor.global_position.distance_to(main.hero.global_position)
	pending_returns[person_id] = {"actor_instance":actor.get_instance_id(), "vehicle_instance":main.hero.get_instance_id(), "hp":float(p.hp), "best_distance":distance, "stall":0.0, "batch_id":batch_id}
	actor.set_meta("crew_return_order", {"destination":main.hero.global_position, "stop_distance":5.6, "owner":get_instance_id()})
	return {"ok":false, "pending":true, "reason":"returning"}

func _construction_busy(actor: Node) -> bool:
	return bool(actor.get_meta("construction_order",false)) or not actor.brain.order.is_empty()

func _clear_return_metadata(person_id: String) -> void:
	if not _actor_exists(person_id): return
	var actor = main.ai_host.actors[person_id]
	var order: Dictionary = actor.get_meta("crew_return_order",{})
	if int(order.get("owner",-1)) == get_instance_id():
		actor.remove_meta("crew_return_order")
		actor.velocity.x = 0.0
		actor.velocity.z = 0.0
		if actor.brain.state == "return_to_vehicle": actor.brain._set_state("disabled" if float(actor.brain.hp)<=0.0 else "idle")

func _finish_return(person_id: String, result: Dictionary, notify: bool = true) -> void:
	if not pending_returns.has(person_id): return
	var task: Dictionary = pending_returns[person_id]
	if _actor_exists(person_id) and main.ai_host.actors[person_id].get_instance_id() == int(task.actor_instance): _clear_return_metadata(person_id)
	pending_returns.erase(person_id)
	if not last_batch.is_empty() and int(last_batch.id) == int(task.batch_id):
		last_batch.pending = maxi(0,int(last_batch.pending)-1)
		_record_batch_result(result)
		if notify: _note(batch_summary(last_batch))
	elif notify:
		_note("乘员已回车" if bool(result.get("ok",false)) else str(REASONS.get(result.get("reason",""),result.get("reason",""))))

func _physics_process(delta: float) -> void:
	_tick_takeover(delta)
	for pid in pending_returns.keys():
		var task: Dictionary = pending_returns[pid]
		if not _actor_exists(pid):
			_finish_return(pid,{"ok":false,"reason":"actor_unavailable"})
			continue
		var actor = main.ai_host.actors[pid]
		var p: Dictionary = registry.person_ref(pid)
		var failure := ""
		if actor.get_instance_id()!=int(task.actor_instance): failure = "actor_changed"
		elif not is_instance_valid(main.hero) or main.hero.get_instance_id()!=int(task.vehicle_instance): failure = "vehicle_changed"
		elif bool(main.get("garage")): failure = "scene_changed"
		elif p.is_empty() or not bool(p.get("alive",false)) or float(p.get("hp",0))<=0: failure = "dead_person"
		elif _construction_busy(actor): failure = "construction_busy"
		elif float(p.hp)<float(task.hp): failure = "return_injured"
		elif not actor.is_physics_processing(): failure = "return_immobile"
		if not failure.is_empty():
			_finish_return(pid,{"ok":false,"reason":failure})
			continue
		var distance: float = actor.global_position.distance_to(main.hero.global_position)
		if distance<=5.9:
			_finish_return(pid,embark_person(pid))
			continue
		if distance<float(task.best_distance)-0.1:
			task.best_distance = distance
			task.stall = 0.0
		else: task.stall += delta
		if float(task.stall)>=RETURN_STALL_SECONDS:
			_finish_return(pid,{"ok":false,"reason":"return_blocked"})
			continue
		actor.set_meta("crew_return_order", {"destination":main.hero.global_position,"stop_distance":5.6,"owner":get_instance_id()})

func _exit_tree() -> void:
	for pid in pending_returns.keys(): _finish_return(pid,{"ok":false,"reason":"scene_changed"},false)

func _note(text: String) -> void:
	if is_instance_valid(main): main.set("message", text)
	if is_instance_valid(status_label): status_label.text = text
	if is_instance_valid(main):
		var controls = main.get("battle_controls")
		if is_instance_valid(controls) and controls.has_method("show_notice"): controls.show_notice(text)

func _refresh() -> void:
	if not is_instance_valid(toggle): return
	var show: bool = is_instance_valid(main) and main.get("game_mode") == "skirmish" and not bool(main.get("garage")) and not person_ids.is_empty()
	toggle.visible = show
	panel.visible = show and expanded
	for i in person_ids.size():
		var p: Dictionary = registry.person_ref(person_ids[i])
		var label := "阵亡" if not bool(p.alive) else ("车内" if p.location.kind == "vehicle" else ("回车中" if pending_returns.has(person_ids[i]) else "车外"))
		picker.set_item_text(i, str(role_labels[i]) + " · " + label + (" · 受伤" if bool(p.alive) and float(p.hp)<10 else ""))
	if expanded and picker.selected>=0 and picker.selected<person_ids.size():
		var person:Dictionary=registry.person_ref(person_ids[picker.selected])
		var names:={"head":"头","torso":"躯干","left_arm":"左臂","right_arm":"右臂","left_leg":"左腿","right_leg":"右腿"}
		var wounds:Array[String]=[]
		for key in person.parts:
			if str(person.parts[key])!="healthy":wounds.append(str(names.get(key,key))+"受损")
		status_label.text="、".join(wounds) if not wounds.is_empty() else "各部位完好"

func _process(delta: float) -> void:
	_tick += delta
	if _tick > 0.25:
		_tick = 0.0
		_refresh()

func onboard_indices() -> Array[int]:
	var result: Array[int] = []
	for i in person_ids.size():
		var p: Dictionary = registry.person_ref(person_ids[i])
		if p.get("location", {}).get("kind", "") == "vehicle" and p.location.get("vehicle_id", "") == vehicle_id: result.append(i)
	return result

## Portable save uses actual live world positions, without spawning or cloning people.
func snapshot() -> Dictionary:
	var data: Dictionary = registry.serialize()
	if main.get("vehicle_ammo")!=null:data["vehicle_ammo"]=main.vehicle_ammo.snapshot()
	for pid in person_ids:
		if _actor_exists(pid) and data.people[pid].location.kind == "world":
			var point: Vector3 = main.ai_host.actors[pid].global_position
			data.people[pid].location.position = [point.x, point.y, point.z]
	return data

## Original role identity survives effective-duty reassignment.
func commander_person_id() -> String:
	var seats: Dictionary = registry.vehicle(vehicle_id).get("seats",{})
	for index in person_ids.size():
		if str(seats.get(str(index),{}).get("role",""))=="commander": return person_ids[index]
	return ""

func takeover_status() -> Dictionary:
	var pid := commander_person_id()
	var p: Dictionary = registry.person_ref(pid)
	var active: bool = not p.is_empty() and registry._role_capable(p,"gunner") and p.get("location",{}).get("kind","")=="vehicle" and str(p.get("state",{}).get("assigned_role",""))=="gunner"
	return {"active":active,"pending":not _takeover_person.is_empty(),"remaining":_takeover_remaining,"person_id":pid}

func observation_multiplier() -> float:
	return TAKEOVER_OBSERVATION_MULTIPLIER if bool(takeover_status().active) else 1.0

func _takeover_allowed() -> Dictionary:
	var pid := commander_person_id()
	var p: Dictionary = registry.person_ref(pid)
	if p.is_empty() or not registry._role_capable(p,"gunner"): return {"ok":false,"reason":"车长已失能，不能接替炮手"}
	if p.get("location",{}).get("kind","")!="vehicle": return {"ok":false,"reason":"车长须先回到车内"}
	var seats: Dictionary = registry.vehicle(vehicle_id).get("seats",{})
	var unavailable_gunner := false
	for index in person_ids.size():
		if str(seats.get(str(index),{}).get("role",""))!="gunner": continue
		var gunner: Dictionary = registry.person_ref(person_ids[index])
		unavailable_gunner = not registry._role_capable(gunner,"gunner")
		break
	if not unavailable_gunner: return {"ok":false,"reason":"原炮手仍能履职，无需接替"}
	return {"ok":true,"person_id":pid}

func request_commander_takeover() -> Dictionary:
	if bool(takeover_status().active): return {"ok":false,"reason":"车长已兼任炮手"}
	if not _takeover_person.is_empty(): return {"ok":false,"pending":true,"reason":"正在切换炮手岗位"}
	var allowed := _takeover_allowed()
	if not bool(allowed.ok):
		_note(str(allowed.reason))
		return allowed
	_takeover_person = str(allowed.person_id)
	_takeover_start_hp = float(registry.person_ref(_takeover_person).hp)
	_takeover_remaining = TAKEOVER_SECONDS
	_note("车长正在接替炮手（2.5秒）")
	return {"ok":true,"pending":true,"remaining":_takeover_remaining}

func _tick_takeover(delta: float) -> void:
	if _takeover_person.is_empty(): return
	var allowed := _takeover_allowed()
	if bool(allowed.ok) and float(registry.person_ref(_takeover_person).get("hp",0.0))<_takeover_start_hp:
		allowed = {"ok":false,"reason":"车长受伤，岗位切换已取消"}
	if not bool(allowed.ok) or bool(main.get("garage")) or (main.has_method("is_battle_active") and not main.is_battle_active()):
		_takeover_person = ""
		_takeover_remaining = 0.0
		_note(str(allowed.get("reason","岗位切换已取消")))
		return
	_takeover_remaining = maxf(0.0,_takeover_remaining-delta)
	if _takeover_remaining>0.0: return
	var result: Dictionary = registry.assign_role(_takeover_person,"gunner")
	_takeover_person = ""
	_note("车长已兼任炮手：装填时间增加35%，观察范围降低35%" if result.ok else "岗位切换失败")
	_refresh()

## Read-only projection of the same person records used by combat and occupancy.
func crew_status_text() -> String:
	var labels: Array[String] = []
	var seats: Dictionary = registry.vehicle(vehicle_id).get("seats",{})
	for i in person_ids.size():
		var p: Dictionary = registry.person_ref(person_ids[i])
		var role := str(seats.get(str(i),{}).get("role",""))
		var state := "在岗"
		if not bool(p.get("alive",false)) or float(p.get("hp",0.0))<=0.0: state = "阵亡"
		elif not registry._role_capable(p,role): state = "失能"
		elif p.get("location",{}).get("kind","")!="vehicle": state = "离车"
		elif str(p.get("state",{}).get("assigned_role",""))=="gunner": state = "兼炮手"
		elif float(p.get("hp",10.0))<float(p.get("max_hp",10.0)): state = "受伤"
		labels.append(str(role_labels[i])+" "+state)
	return " / ".join(labels)

func gunner_needs_takeover() -> bool:
	return bool(_takeover_allowed().ok) and not bool(takeover_status().active)
