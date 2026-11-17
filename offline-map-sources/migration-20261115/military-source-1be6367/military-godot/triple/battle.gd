extends "res://scripts/main.gd"
signal map_requested
var continuity_bound := false

func _ready() -> void:
	super._ready()
	ai_host.set_script(preload("res://triple/local_host.gd"))
	ai_host.setup(self)
	combined_battle_enabled = false

func load_terrain() -> void:
	terrain_damage = preload("res://ridgevale/terrain.gd").new()
	stage.add_child(terrain_damage)
	terrain_root = terrain_damage
	var result: Dictionary = terrain_damage.configure(Vector3.ZERO,null)
	if not result.get("ok",false):
		push_error(str(result))
		return
	var scenery := preload("res://ridgevale/world.gd").new()
	stage.add_child(scenery)
	scenery.build(terrain_damage)

func switch_mode() -> void:
	if continuity_bound: map_requested.emit()
	else: super.switch_mode()

func choose_game_mode(mode: String) -> void:
	if continuity_bound: map_requested.emit()
	else: super.choose_game_mode(mode)

func reset_range() -> void:
	message = "宿主接续中。重置不属于地图切换。"
	refresh_hud()

func cycle_terrain() -> void:
	map_requested.emit()
