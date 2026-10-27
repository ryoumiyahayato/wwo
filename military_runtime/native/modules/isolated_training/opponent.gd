extends "res://military_runtime/native/modules/ai_armor/armor_host.gd"
## One authored encounter, not the original nine-vehicle deployment.
## Original observation/thought/motor/aim/capability/damage own their rules.
const Shell = preload("res://military_runtime/native/modules/artillery/artillery_shell.gd")
const Ballistics = preload("res://military_runtime/native/modules/vehicle_weapons/tank_ballistics.gd")
const TankFire = preload("res://military_runtime/native/modules/vehicle_weapons/tank_shell_fire.gd")
const AmmoConfig = preload("res://military_runtime/native/modules/vehicle_ammo/ammo_config.gd")
const AmmoProfiles = preload("res://military_runtime/native/scripts/ammo_profiles.gd")
const WeaponVFX = preload("res://military_runtime/native/scripts/weapon_vfx_profile.gd")
const Feedback = preload("res://military_runtime/native/scripts/hit_feedback.gd")
const ENEMY_ID: String = "training_red_0"
# Existing central_saddle road, inside its protected deployment rectangle.
# This is setup, never a live target-derived relocation or a respawn.
const START_XZ: Vector2 = Vector2(0.0, 110.0)
var _bound: bool = false
var _visual_changed: bool = false
var _previous_visual_state: Array = []

func bind_existing(model: Node3D, state: Combat) -> Dictionary:
	if _bound or not units.is_empty():
		return {"ok": false, "reason": "encounter_already_bound"}
	var position: Vector3 = Vector3(START_XZ.x, main.terrain_damage.sample_height(START_XZ.x, START_XZ.y), START_XZ.y)
	if not position.is_finite() or state.crew.size() != 3:
		return {"ok": false, "reason": "original_opponent_unavailable"}
	var turret: Node3D = model.find_child("Turret", true, false) as Node3D
	var barrel: Node3D = model.find_child("Barrel", true, false) as Node3D
	var muzzle: Node3D = model.find_child("Muzzle", true, false) as Node3D
	if turret == null or barrel == null or muzzle == null:
		return {"ok": false, "reason": "original_opponent_muzzle_unavailable"}
	model.hide()
	model.global_position = position
	model.rotation = Vector3.ZERO
	model.set_meta("actor_id", ENEMY_ID)
	model.set_meta("team_id", "red")
	model.set_meta("actor_kind", "vehicle")
	var exclusions: Array[RID] = []
	for body: CollisionObject3D in model.find_children("*", "CollisionObject3D", true, false):
		body.set_meta("actor_id", ENEMY_ID)
		body.set_meta("team_id", "red")
		exclusions.append(body.get_rid())
	var envelope: BoxShape3D = BoxShape3D.new()
	envelope.size = Vector3(3.4, 1.4, 5.4)
	var unit: Dictionary = {
		"id": ENEMY_ID, "team": "red", "model": model, "combat": state,
		"turret": turret, "barrel": barrel, "muzzle": muzzle,
		"mg_muzzle": model.find_child("MG_Muzzle", true, false), "mg_reload": 0.0,
		"exclude": exclusions, "shape": envelope, "home": position,
		"goal": position + Vector3(0.0, 0.0, -12.0),
		"memory": {}, "scan_cursor": 0, "target": {}, "think": 0.0,
		"reload": 5.0, "speed": 0.0, "travel": 0.0,
		"left_travel": 0.0, "right_travel": 0.0, "shots": 0,
		"blocked": 0, "avoid": 0.0, "index": 0, "focus_id": "",
		"target_acquired_at": elapsed, "stable_aim": 0.0, "deployment_route": [],
		"visual_weapons": {"primary": {"weapon_id": "game_tank_cannon"}, "mg": {"weapon_id": "game_vehicle_mg"}},
		"ballistics": Ballistics.configuration({})
	}
	if not main.vehicle_ammo.register_vehicle(ENEMY_ID, AmmoConfig.loadout("cannon", true)):
		return {"ok": false, "reason": "opponent_ammo_already_registered"}
	units[ENEMY_ID] = unit
	_add_team_panels(model, "red", Vector3(0.0, 0.95, 0.0), Vector3(2.7, 1.05, 4.6))
	damage_feedback.setup(unit)
	main.terrain_damage.set_simulation_anchors([main.hero.global_position, position])
	main.align_vehicle_ground(model, true)
	_bound = true
	return {"ok": true}

func deployment_ready() -> bool:
	if not _bound:
		return false
	var unit: Dictionary = units[ENEMY_ID]
	var support: Dictionary = main.align_vehicle_ground(unit.model, true)
	if not bool(support.get("driveable", false)):
		return false
	var exclusions: Array[RID] = unit.exclude.duplicate()
	for ground: Node in get_tree().get_nodes_in_group("drivable_ground"):
		if ground is CollisionObject3D:
			exclusions.append((ground as CollisionObject3D).get_rid())
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = unit.shape
	query.transform = unit.model.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	query.exclude = exclusions
	query.collision_mask = 1 | 8 | 128
	return main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _physics_process(delta: float) -> void:
	if not _bound or not bool(main.get("session_ready")):
		return
	super._physics_process(delta)

func _advance_unit_combat(unit: Dictionary, delta: float) -> void:
	# The adopted target Combat already advances once in main._advance_game_clock.
	# In particular, player smoke must not expire twice as fast after adoption.
	if unit.combat != main.combat:
		super._advance_unit_combat(unit, delta)

func _process(delta: float) -> void:
	if not _bound:
		return
	super._process(delta)
	var state: Array = []
	for unit: Dictionary in units.values():
		state.append(unit.model.global_transform)
		state.append(unit.turret.transform)
		state.append(unit.barrel.transform)
		state.append(unit.model.visible)
		state.append(unit.get("feedback_signature", ""))
	_visual_changed = state != _previous_visual_state
	_previous_visual_state = state

func has_animation_activity() -> bool:
	return _visual_changed

func _aim_point(unit: Dictionary) -> Vector3:
	var observed: Vector3 = unit.target.position
	if str(unit.target.get("actor_kind", "vehicle")) == "infantry" and is_instance_valid(unit.mg_muzzle):
		return observed # Original MG remains a muzzle-ray weapon.
	var offset: Vector3 = observed - unit.muzzle.global_position
	var horizontal_range: float = Vector2(offset.x, offset.z).length()
	# Original gravity solver, fed ONLY the quantized optical observation.
	# No hidden actor transform, velocity/lead, or in-flight homing is available.
	var axis: Vector3 = Ballistics.bore_axis(offset.normalized(), horizontal_range, unit.ballistics)
	return unit.muzzle.global_position + axis * offset.length()

func _fire(unit: Dictionary, direction: Vector3, machinegun: bool = false) -> void:
	if machinegun:
		super._fire(unit, direction, true)
		return
	if not _alive(unit) or not _role_alive(unit, "炮手") or elapsed < float(unit.get("safety_retry_until", 0.0)) or not VisualContact.fresh(unit.target, elapsed):
		return
	if float(unit.reload) > 0.0 or not is_instance_valid(unit.muzzle) or not unit.muzzle.is_inside_tree():
		return
	if get_tree().get_nodes_in_group("artillery_projectile").size() >= TankFire.MAX_ACTIVE:
		return
	var config: Dictionary = unit.ballistics
	if not Ballistics.valid(config):
		return
	var barrel_axis: Vector3 = direction.normalized()
	direction = Gunnery.shot_axis(barrel_axis, float(unit.speed), int(unit.shots), int(unit.index), false)
	var origin: Vector3 = unit.muzzle.global_position
	var exclusions: Array[RID] = unit.exclude
	# This ray is only the original friendly-fire safety gate, NEVER impact authority.
	var safety_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * float(config.range), 1 | 8 | 128, exclusions)
	var safety_hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(safety_query)
	var safety_end: Vector3 = safety_hit.get("position", origin + direction * float(config.range))
	if (not safety_hit.is_empty() and FriendlySafety.collider_team(safety_hit.collider) == str(unit.team)) or FriendlySafety.friendly_corridor(main.get_world_3d().direct_space_state, origin, safety_end, exclusions, str(unit.team)):
		unit["safety_retry_until"] = elapsed + 0.15
		return
	var shell: Shell = Shell.new()
	shell.gravity = config.gravity
	shell.lifetime_limit = config.lifetime
	shell.horizontal_limit = config.range
	main.stage.add_child(shell)
	var pose: Transform3D = Transform3D(Basis.looking_at(direction, Vector3.UP), origin)
	if not shell.setup(pose, float(config.speed), exclusions, Callable(main, "effect_point_visible"), Callable(main, "indirect_surface_height")):
		main.stage.remove_child(shell)
		shell.queue_free()
		return
	var period: float = 6.0 if _role_alive(unit, "装填手") else 8.0
	var committed: Dictionary = main.vehicle_ammo.commit_fire(str(unit.id), "primary", main.vehicle_ammo.request_id(), period, true, true)
	if not bool(committed.get("ok", false)):
		main.stage.remove_child(shell)
		shell.queue_free()
		unit["ammo_reason"] = str(committed.get("reason", ""))
		return
	unit["ammo_reason"] = ""
	unit["ammo_commit"] = committed.commit
	unit["shot_barrel_axis"] = barrel_axis
	unit["shot_cone_radians"] = Gunnery.cone_radians(float(unit.speed), false)
	var audit_id: int = _audit_shot(unit, origin, direction, origin + direction * float(config.range), {}, false)
	var visual_weapon: Dictionary = WeaponVFX.describe(unit, "cannon", "primary")
	var row: Dictionary = {"id": audit_id, "actor_id": str(unit.id), "vehicle_id": str(unit.id),
		"accepted": true, "weapon": "tank_cannon", "round": str(committed.round), "ammo_commit": int(committed.commit),
		"origin": origin, "direction": direction, "speed": config.speed, "gravity": config.gravity,
		"horizontal_limit": config.range, "flight_state": "flying"}
	main.incoming_audit.append(row)
	if main.incoming_audit.size() > 128:
		main.incoming_audit.pop_front()
	_update_combat_flight(audit_id, {"flight_state": "flying", "speed": config.speed, "gravity": config.gravity})
	# A launch/safety endpoint must not masquerade as an actual hit in the audit.
	combat_audit.entries.back().erase("hit_position")
	shell.add_to_group("tank_projectile")
	shell.impacted.connect(_shell_impact.bind(main.stage_generation, audit_id, int(committed.commit), visual_weapon))
	shell.expired.connect(_shell_expired.bind(main.stage_generation, audit_id))
	unit.reload = period - float(unit.get("reload_overshoot", 0.0))
	unit.shots += 1
	shots_fired += 1
	_launch_feedback(unit, visual_weapon)
	main.request_training_frame()

func _launch_feedback(unit: Dictionary, visual_weapon: Dictionary) -> void:
	var origin: Vector3 = unit.muzzle.global_position
	var axis: Vector3 = -unit.muzzle.global_basis.z.normalized()
	if main.combat_effects.fire(origin, origin + axis * 0.5, "cannon", false, "ground", true, false, Callable(main, "effect_point_visible"), "muzzle_only", {"visual_weapon": visual_weapon}):
		var effect: Dictionary = main.combat_effects.events.back()
		effect.tracer = false
		effect.projectile.hide()
	var visual: Dictionary = WeaponVFX.resolve(visual_weapon, "cannon")
	var barrel: Node3D = unit.barrel
	if not barrel.has_meta("rest_position"):
		barrel.set_meta("rest_position", barrel.position)
	var rest: Vector3 = barrel.get_meta("rest_position")
	barrel.position = rest + barrel.basis.z.normalized() * float(visual.recoil_distance)
	var tween: Tween = main.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(barrel, "position", rest, float(visual.recoil_time))

func _flight_row(audit_id: int) -> Dictionary:
	for row: Dictionary in main.incoming_audit:
		if int(row.get("id", -1)) == audit_id and str(row.get("actor_id", "")) == ENEMY_ID:
			return row
	return {}

func _update_combat_flight(audit_id: int, fields: Dictionary) -> void:
	var clean: Dictionary = combat_audit._plain(fields)
	for record: Dictionary in combat_audit.entries:
		if int(record.audit_id) == audit_id:
			record.merge(clean, true)
			return

func _shell_expired(event: Dictionary, generation: int, audit_id: int) -> void:
	_finish_flight(event, generation, audit_id, "expired")

func _finish_flight(event: Dictionary, generation: int, audit_id: int, state: String) -> bool:
	if not is_instance_valid(main) or generation != int(main.stage_generation):
		return false
	var row: Dictionary = _flight_row(audit_id)
	if row.is_empty() or str(row.get("flight_state", "")) != "flying":
		return false
	row["flight_state"] = state
	row["flight_seconds"] = event.flight_seconds
	row["impact"] = event.position
	row["distance"] = (row.origin as Vector3).distance_to(event.position)
	_update_combat_flight(audit_id, {"flight_state": state, "flight_seconds": event.flight_seconds, "hit_position": event.position})
	main.request_training_frame()
	return true

func _shell_impact(event: Dictionary, generation: int, audit_id: int, commit: int, visual_weapon: Dictionary) -> void:
	if not _finish_flight(event, generation, audit_id, "impacted") or main.garage or main.battle_finished:
		return
	var collider: Object = event.get("collider")
	var hit_actor: String = actor_id(collider)
	var hit_kind: String = "ground" if bool(event.get("terrain_sample", false)) else "obstacle"
	if is_instance_valid(collider):
		hit_kind = str(collider.get_meta("kind", "obstacle"))
	var row: Dictionary = _flight_row(audit_id)
	row["hit_actor_id"] = hit_actor
	row["hit_kind"] = hit_kind
	row["impact_direction"] = event.direction
	row["impact_normal"] = event.normal
	_update_combat_flight(audit_id, {"hit_actor_id": hit_actor, "hit_key": str(collider.get_meta("key", "")) if is_instance_valid(collider) else "", "hit_normal": event.normal, "impact_direction": event.direction})
	var actual_hit: Dictionary = event.duplicate()
	event["hit"] = actual_hit
	event["hit_actor_id"] = hit_actor
	event["actor_id"] = ENEMY_ID
	event["team_id"] = "red"
	event["weapon"] = "cannon"
	event["round"] = "ap"
	event["penetration"] = 110
	event["ammo_commit"] = commit
	event["audit_id"] = audit_id
	if hit_actor == "player":
		main.apply_ai_hit(event)
	elif units.has(hit_actor):
		receive_hit(event)
	elif not hit_actor.is_empty() and is_instance_valid(main.ai_host):
		main.ai_host.infantry_apply_hit(event)
	var feedback: Dictionary = Feedback.contact(actual_hit, hit_kind, audit_id, event.direction)
	feedback["visual_weapon"] = visual_weapon
	if bool(event.get("terrain_sample", false)):
		feedback.surface = "ground"
	if main.combat_effects.fire(event.position, event.position, "cannon", true, str(feedback.surface), false, false, Callable(main, "effect_point_visible"), "ap", feedback):
		main.combat_effects.begin_impact(main.combat_effects.events.back())
		main.combat_effects._apply_visibility(main.combat_effects.events.back())
	main.explode_terrain(event.position, AmmoProfiles.explosive_mass("cannon_ap"))

func encounter_snapshot() -> Dictionary:
	# Local status/driver facts ONLY. Never feed this through enemy HUD/minimap intel.
	var result: Dictionary = snapshot()
	result["driver_facts_only"] = true
	result["elapsed"] = elapsed
	result["setup_position_xz"] = START_XZ
	result["shot_audit"] = recent_shots()
	for id: String in result.units:
		var unit: Dictionary = units[id]
		result.units[id]["ammo"] = main.vehicle_ammo.status(id, "primary")
		result.units[id]["memory"] = unit.memory.duplicate(true)
		result.units[id]["observation"] = unit.target.duplicate(true)
		result.units[id]["speed_mps"] = float(unit.speed)
		result.units[id]["reload_remaining"] = float(unit.reload)
	return result
