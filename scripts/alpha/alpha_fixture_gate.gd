class_name AlphaFixtureGate
extends Control
## Prevents the quarantined Loran/Vesta grid fixture from appearing in normal play.

const FORMAL_MENU_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_menu.tscn"
const FIXTURE_SCENE: String = "res://scenes/alpha/alpha_grid_fixture.tscn"
const FIXTURE_FLAG: String = "--alpha-grid-fixture"
const ALLOW_META: StringName = &"allow_alpha_grid_fixture"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("_route")


func _route() -> void:
	var allowed: bool = (
		OS.get_cmdline_user_args().has(FIXTURE_FLAG)
		or bool(get_tree().get_meta(ALLOW_META, false))
	)
	if get_tree().has_meta(ALLOW_META):
		get_tree().remove_meta(ALLOW_META)
	var target: String = FIXTURE_SCENE if allowed else FORMAL_MENU_SCENE
	var error: Error = get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Unable to route Alpha fixture scene: %s" % error_string(error))
