extends "res://military_runtime/native/triple/battle.gd"
## Initialization/presentation adapter. Native main/mobile/crew/ammo/flight own gameplay.
signal preparation_failed(reason: String)
signal frame_requested
var material_provider: Object
var session_ready: bool = false
var session_locked: bool = false
var preparation_error: String = ""
var battlefield_profile: String = "single_opponent"
var measure_startup := false
var startup_usec: Dictionary = {}
var prepared_terrain: Node3D
var prepared_scenery: Node3D
const BattlefieldDeployment = preload("res://military_runtime/native/modules/isolated_training/battlefield_deployment.gd")

func request_training_frame() -> void:
	frame_requested.emit()

func _ready() -> void:
	var started := Time.get_ticks_usec() if measure_startup else 0
	# Deliberately do not call main._ready(): its standalone helpers alter root MSAA,
	# SceneTree interpolation/physics rate and install diagnostic/command-line hosts.
	# This is only its initialization glue; no vehicle or weapon rule is replaced.
	combined_battle_enabled = false
	vehicle_contacts.setup(self)
	fire_control.setup(self)
	load_catalog()
	font = load("res://military_runtime/native/cedar/system_font.tres") as Font
	stage = Node3D.new()
	add_child(stage)
	decor = Node3D.new()
	add_child(decor)
	camera = Camera3D.new()
	camera.fov = 47.0
	camera.near = 0.08
	camera.far = 3200.0
	add_child(camera)
	# The observer viewport already has its own World3D, lighting and environment.
	build_hud()
	if is_instance_valid(damage_overlay):
		damage_overlay.queue_free()
		damage_overlay = null
	hud.custom_viewport = get_viewport()
	# Preserve the opening stage reset before the native range transition.
	clear_stage()
	ai_host = preload("res://military_runtime/native/modules/isolated_training/battlefield_infantry.gd").new() if battlefield_profile == BattlefieldDeployment.PROFILE else preload("res://military_runtime/native/triple/local_host.gd").new()
	add_child(ai_host)
	ai_host.setup(self)
	crew_host = preload("res://military_runtime/native/modules/vehicle_crew/vehicle_crew_host.gd").new()
	add_child(crew_host)
	crew_host.setup(self)
	player_infantry_controller = preload("res://military_runtime/native/modules/vehicle_crew/player_infantry_controller.gd").new()
	add_child(player_infantry_controller)
	player_infantry_controller.setup(self)
	player_infantry_controller.control_changed.connect(_on_control_changed)
	battle_controls = preload("res://military_runtime/native/modules/isolated_training/controls.gd").new()
	battle_controls.setup(self)
	refresh_hud()
	if measure_startup: startup_usec["scene_ready"] = Time.get_ticks_usec()-started

func load_model(index: int, player_model: bool = false) -> Node3D:
	var started := Time.get_ticks_usec() if measure_startup else 0
	var model := super.load_model(index,player_model)
	if measure_startup: startup_usec["model_load_and_instantiate"] = int(startup_usec.get("model_load_and_instantiate",0))+Time.get_ticks_usec()-started
	return model

func prepare_encounter() -> Dictionary:
	if is_instance_valid(armor_host):
		return {"ok": false, "reason": "encounter_already_installed"}
	if battlefield_profile == BattlefieldDeployment.PROFILE:
		armor_host = preload("res://military_runtime/native/modules/isolated_training/battlefield_armor.gd").new()
		add_child(armor_host)
		armor_host.setup(self)
		var armor_result: Dictionary = await armor_host.prepare_battlefield(BattlefieldDeployment.vehicle_rows(terrain_damage), crew_host.registry)
		if not bool(armor_result.get("ok", false)):
			return armor_result
		return await ai_host.deploy_infantry(BattlefieldDeployment.infantry_rows(terrain_damage))
	armor_host = preload("res://military_runtime/native/modules/isolated_training/opponent.gd").new()
	add_child(armor_host)
	armor_host.setup(self)
	return armor_host.bind_existing(target, combat)

func encounter_ready() -> bool:
	if not is_instance_valid(armor_host) or not armor_host.deployment_ready():
		return false
	if battlefield_profile == BattlefieldDeployment.PROFILE:
		if not terrain_damage.stream_queue.is_empty():
			return false
		for id: String in ai_host.field_roster:
			var actor: CharacterBody3D = ai_host.actors[id]
			if not terrain_damage.is_position_loaded(actor.global_position):
				return false
	return true

func _on_control_changed(_on_foot: bool) -> void:
	fire_control.cancel("车长上下车，指示已撤销")
	clear_vehicle_fire_input()
	scoped = false
	hero.show()
	battle_controls.reset_pointers()
	battle_controls.request_camera_snap()

func load_terrain() -> void:
	if session_locked:
		_deny_rebuild()
		return
	if not is_instance_valid(prepared_terrain) or not is_instance_valid(prepared_scenery):
		preparation_error = "native_terrain_not_prepared"
		preparation_failed.emit(preparation_error)
		return
	terrain_damage = prepared_terrain
	terrain_root = terrain_damage
	prepared_terrain.reparent(stage,false)
	prepared_scenery.reparent(stage,false)
	prepared_terrain = null
	prepared_scenery = null

func build_range() -> void:
	if session_locked:
		_deny_rebuild()
		return
	super.build_range()
	# Original skirmish hides its original fixed target. Restore that target, not an
	# army, and preserve the separate internal-crew ray layer (never all layer 1).
	if is_instance_valid(target):
		for child: Node in target.find_children("*", "CollisionObject3D", true, false):
			var collider: CollisionObject3D = child as CollisionObject3D
			collider.collision_layer = 2 if collider.has_meta("crew_index") else 1
			collider.collision_mask = 0 if collider.has_meta("crew_index") else 1
		target.show()
		terrain_damage.fixed_target = target

func update_visibility() -> void:
	super.update_visibility()
	if is_instance_valid(target) and not garage:
		# Keep original LOS/weather/smoke evaluation; only remove skirmish's blanket hide.
		target.visible = visibility_reason == "visible"

func load_display() -> void:
	if session_locked:
		_deny_rebuild()
		return
	super.load_display()

func clear_stage() -> void:
	if session_locked:
		_deny_rebuild()
		return
	super.clear_stage()

func choose_game_mode(mode: String) -> void:
	if session_locked or mode != "skirmish":
		_deny_rebuild()
		return
	super.choose_game_mode(mode)

func switch_mode() -> void:
	map_requested.emit()

func select_unit(_index: int) -> void:
	_deny_rebuild()

func select_catalog(_id: String) -> void:
	_deny_rebuild()

func cycle_target() -> void:
	_deny_rebuild()

func cycle_terrain() -> void:
	_deny_rebuild()

func reset_range() -> void:
	_deny_rebuild()

func flip_target() -> void:
	_deny_rebuild()

func toggle_crew() -> void:
	_deny_rebuild()

func cycle_crew() -> void:
	_deny_rebuild()

func restore_vehicle_ammunition(_snapshot_data: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "isolated_session_no_ammo_restore"}

func _deny_rebuild() -> void:
	message = "本次隔离训练保留原车组、弹药和靶损。返回观察不会重置；仅明确结束可关闭。"
	if is_instance_valid(battle_controls):
		battle_controls.show_notice(message)
