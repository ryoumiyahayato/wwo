extends Node
## A single explicitly ended isolated session in the observer's existing SubViewport.
## No WorldState, formal player, persistence, lease export or standalone engine host.
signal prepared(status: Dictionary)
signal failed(reason: String)
signal observer_requested

const NativeBattle = preload("res://military_runtime/native/modules/isolated_training/battle.gd")
const NativePort = preload("res://military_runtime/native/triple/port.gd")
const REQUEST_PATH: String = "res://military_runtime/native/triple/default_request.json"
const REQUIRED_MODELS: Array[String] = [
	"res://military_runtime/native/assets/user_derived/models/user_heavy_mbt_aimable.glb",
	"res://military_runtime/native/assets/models/kestrel_scout.glb",
	"res://military_runtime/native/assets/user_derived/models/user_rifleman_armed.glb"
]
var _battle: NativeBattle
var _port: NativePort
var _viewport: SubViewport
var _world_root: Node3D
var _provider: Object
var _observer_camera: Camera3D
var _state: String = "idle"
var _error: String = ""
var _generation: int = 0
var _collision_states: Dictionary = {}
var _input_exclusions: Array[Rect2] = []
var _global_settings: Dictionary = {}
var _pause_when_prepared: bool = false
var _render_hold: float = 0.0
var _last_camera_pose: Transform3D = Transform3D.IDENTITY
var _last_hero_pose: Transform3D = Transform3D.IDENTITY
var _was_dynamic: bool = false
var _turret: Node3D
var _barrel: Node3D
var _last_turret_pose: Transform3D = Transform3D.IDENTITY
var _last_barrel_pose: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10000

func request_frame() -> void:
	if not is_instance_valid(_viewport):
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_render_hold = 0.25

func _process(delta: float) -> void:
	if _state != "running" or not is_instance_valid(_battle):
		return
	_render_hold = maxf(0.0, _render_hold - delta)
	var dynamic: bool = _needs_animation_frame()
	if _render_hold > 0.0 or dynamic or _was_dynamic:
		# One final clean frame retires the last muzzle/impact/terrain animation.
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_last_camera_pose = _battle.camera.global_transform
		_last_hero_pose = _battle.hero.global_transform
		if is_instance_valid(_turret):
			_last_turret_pose = _turret.transform
		if is_instance_valid(_barrel):
			_last_barrel_pose = _barrel.transform
	_was_dynamic = dynamic

func _needs_animation_frame() -> bool:
	if not _battle.camera.global_transform.is_equal_approx(_last_camera_pose):
		return true
	if not _battle.hero.global_transform.is_equal_approx(_last_hero_pose):
		return true
	if is_instance_valid(_turret) and not _turret.transform.is_equal_approx(_last_turret_pose):
		return true
	if is_instance_valid(_barrel) and not _barrel.transform.is_equal_approx(_last_barrel_pose):
		return true
	# Native end_battle freezes stage projectiles/effects. Their retained flying
	# facts must not request frames forever after the final outcome frame.
	if _battle.battle_finished:
		return false
	if _battle.reload_remaining > 0.0 or _battle.mg_remaining > 0.0 or _battle.weather_index == 1:
		return true
	if is_instance_valid(_battle.smoke_root) or not _battle.effect_nodes.is_empty():
		return true
	if is_instance_valid(_battle.combat_effects) and not _battle.combat_effects.events.is_empty():
		return true
	if not _battle.terrain_damage.stream_queue.is_empty() or not _battle.terrain_damage.jobs.is_empty() or not _battle.terrain_damage.pending.is_empty():
		return true
	if not _battle.crew_host.pending_returns.is_empty() or float(_battle.crew_host.get("_takeover_remaining")) > 0.0:
		return true
	for shot: Dictionary in _battle.shot_audit:
		if str(shot.get("flight_state", "")) == "flying":
			return true
	for shot: Dictionary in _battle.incoming_audit:
		if str(shot.get("flight_state", "")) == "flying":
			return true
	if is_instance_valid(_battle.armor_host) and _battle.armor_host.has_animation_activity():
		return true
	for actor: CharacterBody3D in _battle.ai_host.actors.values():
		if is_instance_valid(actor) and not bool(actor.get("embarked")) and actor.velocity.length_squared() > 0.0001:
			return true
	return false

func start(options: Dictionary) -> void:
	if _state != "idle" and _state != "closed" and _state != "failed":
		failed.emit("existing_session_use_pause_or_resume")
		return
	_state = "preparing"
	_error = ""
	_pause_when_prepared = false
	_was_dynamic = false
	_generation += 1
	var generation: int = _generation
	_viewport = options.get("viewport") as SubViewport
	_world_root = options.get("world_root") as Node3D
	_provider = options.get("provider") as Object
	if not is_inside_tree() or not is_instance_valid(_viewport) or not _viewport.is_inside_tree():
		_fail("an_existing_observer_subviewport_is_required")
		return
	if not _viewport.own_world_3d:
		_fail("observer_subviewport_must_already_own_its_world")
		return
	if is_instance_valid(_world_root) and (_world_root.get_viewport() != _viewport or not _world_root.global_transform.is_equal_approx(Transform3D.IDENTITY)):
		_fail("world_root_must_use_identity_local_metres_in_observer_viewport")
		return
	if not is_instance_valid(_provider) or not _provider.has_method("set_external_native_owner") or not _provider.has_method("create_surface_material"):
		_fail("shared_terrain_provider_contract_required")
		return
	for path: String in REQUIRED_MODELS:
		if not ResourceLoader.exists(path):
			_fail("missing_original_training_resource: " + path)
			return
	_port = NativePort.new()
	if not _port.read_request(REQUEST_PATH):
		_fail(_port.error)
		return
	_observer_camera = _viewport.get_camera_3d()
	_provider.call("set_external_native_owner", true)
	if _provider.has_signal("changed") and not _provider.is_connected("changed", request_frame):
		_provider.connect("changed", request_frame)
	_capture_global_settings()
	_battle = NativeBattle.new()
	_battle.name = "IsolatedNativeTankSession"
	_battle.material_provider = _provider
	_battle.process_mode = Node.PROCESS_MODE_ALWAYS
	_battle.map_requested.connect(_request_observer)
	_battle.frame_requested.connect(request_frame)
	if is_instance_valid(_world_root):
		_world_root.add_child(_battle)
	else:
		_viewport.add_child(_battle)
	_battle.choose_game_mode("skirmish")
	# Initialization must not change formal-tree or root-viewport settings. No
	# helper that continuously writes these globals is installed in NativeBattle.
	_restore_global_settings()
	if not _battle.preparation_error.is_empty():
		_fail(_battle.preparation_error)
		return
	for frame: int in range(30):
		await get_tree().physics_frame
		if generation != _generation or not is_instance_valid(_battle):
			return
		if _battle.crew_host.person_ids.size() == 5:
			break
	if _battle.crew_host.person_ids.size() != 5:
		_fail("original_five_person_crew_did_not_bind")
		return
	if not _port.install(_battle):
		_fail(_port.error)
		return
	# Install only once: preserves injured commander and already-spent 9 rounds.
	_battle.session_locked = true
	var encounter: Dictionary = _battle.prepare_encounter()
	if not bool(encounter.get("ok", false)):
		_fail(str(encounter.get("reason", "encounter_install_failed")))
		return
	var opponent_ready: bool = false
	for deployment_frame: int in range(120):
		await get_tree().physics_frame
		if generation != _generation or not is_instance_valid(_battle):
			return
		if _battle.encounter_ready():
			opponent_ready = true
			break
	if not opponent_ready:
		_fail("original_opponent_deployment_not_ready")
		return
	_battle.session_ready = true
	for child: Node in _battle.find_children("*", "", true, false):
		if child.process_mode == Node.PROCESS_MODE_ALWAYS:
			child.process_mode = Node.PROCESS_MODE_INHERIT
	_battle.battle_controls.presentation_exclusions = _input_exclusions.duplicate()
	_battle.battle_controls.request_camera_snap()
	_turret = _battle.hero.find_child("Turret", true, false) as Node3D
	_barrel = _battle.hero.find_child("Barrel", true, false) as Node3D
	_state = "running"
	request_frame()
	if _pause_when_prepared:
		pause()
	prepared.emit(get_status())

func pause() -> void:
	if _state == "preparing":
		_pause_when_prepared = true
		return
	if _state != "running" or not is_instance_valid(_battle):
		return
	_battle.battle_controls.reset_pointers()
	_battle.clear_vehicle_fire_input()
	_battle.session_ready = false
	_battle.process_mode = Node.PROCESS_MODE_DISABLED
	_collision_states.clear()
	for child: Node in _battle.find_children("*", "CollisionObject3D", true, false):
		var body: CollisionObject3D = child as CollisionObject3D
		_collision_states[body.get_instance_id()] = {"body": body, "layer": body.collision_layer, "mask": body.collision_mask}
		body.collision_layer = 0
		body.collision_mask = 0
	_battle.hide()
	_battle.hud.hide()
	if is_instance_valid(_observer_camera):
		_observer_camera.make_current()
	_state = "paused"
	# Cede only AFTER every native collider is disabled. Observer can now restore.
	if is_instance_valid(_provider):
		_provider.call("set_external_native_owner", false)
	request_frame()

func resume() -> void:
	if _state == "preparing":
		_pause_when_prepared = false
		return
	if _state != "paused" or not is_instance_valid(_battle):
		return
	# Remove observer near collision before restoring this same native session.
	if is_instance_valid(_provider):
		_provider.call("set_external_native_owner", true)
	for saved: Dictionary in _collision_states.values():
		var body: CollisionObject3D = saved.get("body") as CollisionObject3D
		if is_instance_valid(body):
			body.collision_layer = int(saved.layer)
			body.collision_mask = int(saved.mask)
	_collision_states.clear()
	_battle.show()
	_battle.hud.show()
	_battle.camera.make_current()
	_battle.battle_controls.reset_pointers()
	_battle.battle_controls.request_camera_snap()
	_battle.session_ready = true
	_battle.process_mode = Node.PROCESS_MODE_ALWAYS
	_state = "running"
	request_frame()

func get_native_battle() -> Node3D:
	# Debug/manual-driver access only, never a status snapshot or a formal control object.
	return _battle

func get_native_camera() -> Camera3D:
	return _battle.camera if is_instance_valid(_battle) else null

func close() -> void:
	_generation += 1
	_release_session()
	_state = "closed"

func set_input_exclusions(rectangles: Array[Rect2]) -> void:
	_input_exclusions = rectangles.duplicate()
	if is_instance_valid(_battle) and is_instance_valid(_battle.battle_controls):
		_battle.battle_controls.presentation_exclusions = _input_exclusions.duplicate()

func get_player_status() -> Dictionary:
	# Cheap host banner projection. Never construct the full driver/encounter facts.
	var status: Dictionary = {"state": _state, "ready": _state in ["running", "paused"]}
	if not bool(status.ready) or not is_instance_valid(_battle) or not is_instance_valid(_battle.hero):
		return status
	var primary: Dictionary = _battle.vehicle_ammo.status("player_vehicle", "primary")
	status.merge({"on_foot": _battle.player_infantry_controller.active(),
		"driving": {"speed_mps": float(_battle.hero.get_meta("vehicle_speed", 0.0))},
		"ammo": {"loaded": str(primary.get("loaded", "")), "loading": str(primary.get("loading", "")),
			"next": str(primary.get("next", "")), "total": int(primary.get("total", 0)),
			"remaining": float(primary.get("remaining", 0.0))},
		"reload_remaining": float(primary.get("remaining", 0.0))})
	return status

func get_status() -> Dictionary:
	var status: Dictionary = {"state": _state, "ready": _state in ["running", "paused"],
		"paused": _state == "paused", "error": _error, "isolated": true,
		"source_kind": "SYNTHETIC_ISOLATED_HOST", "formal_world_player": false,
		"writes_formal_world": false, "terrain_owner": "native_ridgevale" if _state == "running" else "observer"}
	if not is_instance_valid(_battle) or not is_instance_valid(_battle.hero):
		return status
	var controls: Control = _battle.battle_controls
	status.merge({"session_id": str(_port.request.get("session_id", "")),
		"vehicle_id": "player_vehicle", "model_id": _battle.selected_catalog_id,
		"elapsed": _battle.elapsed, "position_local": _battle.hero.position,
		"world_position": _battle.hero.global_position,
		"transform_local": _battle.hero.transform, "crew": _battle.player_combat.crew.duplicate(true),
		"crew_registry": _battle.crew_host.registry.serialize(),
		"vehicle_modules": _battle.player_combat.modules.duplicate(true),
		"ammo": _battle.vehicle_ammo.status("player_vehicle", "primary").duplicate(true),
		"native_ammo": _battle.vehicle_ammo.snapshot(),
		"shot_audit": _battle.shot_audit.duplicate(true), "shot_sequence": _battle.shot_sequence,
		"incoming_audit": _battle.incoming_audit.duplicate(true),
		"target": {"model_id": "kestrel_scout", "position_local": _battle.target.position,
			"modules": _battle.combat.modules.duplicate(true), "crew": _battle.combat.crew.duplicate(true)},
		"driving": {"speed_mps": float(_battle.hero.get_meta("vehicle_speed", 0.0)),
			"travel_m": float(controls.get("travel")), "blocked": bool(controls.get("drive_blocked")),
			"can_drive": _battle.crew_host.can_drive(), "ground_support": _battle.hero.get_meta("ground_support", {})},
		"on_foot": _battle.player_infantry_controller.active(),
		"battle_finished": _battle.battle_finished, "battle_result": _battle.battle_result,
		"message": _battle.message, "native_actor_count": _battle.ai_host.actors.size(),
		"terrain": _battle.terrain_damage.simulation_stream_snapshot()}, true)
	if is_instance_valid(_battle.armor_host):
		status["encounter"] = _battle.armor_host.encounter_snapshot()
	return status.duplicate(true)

func _request_observer() -> void:
	pause()
	observer_requested.emit()

func _fail(reason: String) -> void:
	_error = reason
	_generation += 1
	_release_session()
	_state = "failed"
	failed.emit(reason)

func _release_session() -> void:
	_restore_global_settings()
	if is_instance_valid(_battle):
		_battle.session_ready = false
		_battle.process_mode = Node.PROCESS_MODE_DISABLED
		for child: Node in _battle.find_children("*", "CollisionObject3D", true, false):
			var body: CollisionObject3D = child as CollisionObject3D
			body.collision_layer = 0
			body.collision_mask = 0
		_battle.hud.hide()
		_battle.hide()
		_battle.get_parent().remove_child(_battle)
		_battle.queue_free()
	_battle = null
	_collision_states.clear()
	if is_instance_valid(_observer_camera):
		_observer_camera.make_current()
	if is_instance_valid(_provider):
		if _provider.has_signal("changed") and _provider.is_connected("changed", request_frame):
			_provider.disconnect("changed", request_frame)
		if _provider.has_method("set_external_native_owner"):
			_provider.call("set_external_native_owner", false)
	request_frame()

func _capture_global_settings() -> void:
	var tree: SceneTree = get_tree()
	var root: Window = tree.root
	_global_settings = {"physics_hz": Engine.physics_ticks_per_second,
		"interpolation": tree.is_physics_interpolation_enabled(), "paused": tree.paused,
		"quit_on_go_back": tree.quit_on_go_back, "accumulated_input": Input.use_accumulated_input,
		"root_msaa": root.msaa_3d, "root_scaling_mode": root.scaling_3d_mode,
		"root_scaling": root.scaling_3d_scale, "viewport_msaa": _viewport.msaa_3d}

func _restore_global_settings() -> void:
	if _global_settings.is_empty() or not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	Engine.physics_ticks_per_second = int(_global_settings.physics_hz)
	tree.set_physics_interpolation_enabled(bool(_global_settings.interpolation))
	tree.paused = bool(_global_settings.paused)
	tree.quit_on_go_back = bool(_global_settings.quit_on_go_back)
	Input.use_accumulated_input = bool(_global_settings.accumulated_input)
	tree.root.msaa_3d = int(_global_settings.root_msaa) as Viewport.MSAA
	tree.root.scaling_3d_mode = int(_global_settings.root_scaling_mode) as Viewport.Scaling3DMode
	tree.root.scaling_3d_scale = float(_global_settings.root_scaling)
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = int(_global_settings.viewport_msaa) as Viewport.MSAA
	_global_settings.clear()

func _exit_tree() -> void:
	_generation += 1
	_release_session()
