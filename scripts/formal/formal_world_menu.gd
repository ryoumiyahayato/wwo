class_name FormalWorldMenu
extends Control
## Formal product entry. New Game uses FormalNewGameService; Load adopts a
## validated candidate world and never falls back to New Game.

const WORLD_SCENE: String = "res://scenes/formal/formal_world_main.tscn"
const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
const LAUNCH_WORLD_META: StringName = &"formal_world_launch_world"
const PACKAGED_PROBE_ARGUMENT: String = "--wwo-player-baseline-probe"
const DISPLAY_VERSION: String = "V0.001"

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var prompt_label: Label = %PromptLabel
@onready var status_label: Label = %StatusLabel
@onready var title_actions: HBoxContainer = %TitleActions
@onready var wizard_panel: VBoxContainer = %WizardPanel
@onready var step_label: Label = %StepLabel
@onready var detail_label: Label = %DetailLabel
@onready var origin_selector: OptionButton = %OriginSelector
@onready var place_selector: OptionButton = %PlaceSelector
@onready var candidate_actions: VBoxContainer = %CandidateActions
@onready var next_button: Button = %NextButton
@onready var reroll_button: Button = %RerollButton
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton

var _new_game_service := FormalNewGameService.new()
var _catalog: Dictionary = {}
var _candidates: Array[Dictionary] = []
var _selected_candidate_index: int = -1
var _draft_index: int = 0
var _entering: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("1900 · %s" % DISPLAY_VERSION)
	title_label.text = "1900"
	version_label.text = DISPLAY_VERSION
	prompt_label.text = "选择一项正式产品流程"
	status_label.text = "找到 Formal 存档（主档）。" if _formal_save_exists() else "尚无 Formal 存档。"
	_show_title()
	if PACKAGED_PROBE_ARGUMENT in OS.get_cmdline_user_args():
		_start_packaged_new_game.call_deferred()


func _on_new_game_pressed() -> void:
	if _entering:
		return
	_catalog = _new_game_service.start_catalog()
	if not bool(_catalog.get("available", false)):
		_show_error("无法建立起点目录：%s" % str(_catalog.get("reason", "未知错误")))
		return
	_populate_origins()
	_show_origin()


func _on_load_pressed() -> void:
	if _entering:
		return
	if not _formal_save_exists():
		_show_error("没有可读取的 Formal 主档或 .bak。")
		return
	status_label.text = "正在校验 Formal 主档……"
	var world := FormalWorldSimulation.new()
	if not world.initialize():
		_show_error("读取候选世界初始化失败：%s" % world.initialization_error)
		return
	var result := world.load_from_user()
	if not result.success:
		_show_error("读取失败：%s" % result.message)
		return
	_enter_world("load", world)


func _on_quit_pressed() -> void:
	get_tree().quit(0)


func _on_origin_selected(_index: int) -> void:
	_populate_places()


func _on_next_pressed() -> void:
	if origin_selector.selected < 0 or place_selector.selected < 0:
		_show_error("请选择人口来源与合法起始地点。")
		return
	var preview := _new_game_service.preview_player_candidates(_current_preview_request())
	if not bool(preview.get("success", false)):
		_show_error("候选预览失败：%s" % str(preview.get("message", "未知错误")))
		return
	_candidates.assign(preview.get("candidates", []) as Array)
	_selected_candidate_index = -1
	_rebuild_candidate_buttons()
	_show_candidates()


func _on_reroll_pressed() -> void:
	_draft_index += 1
	_on_next_pressed()


func _on_candidate_pressed(index: int) -> void:
	if index < 0 or index >= _candidates.size():
		return
	_selected_candidate_index = index
	var candidate := _candidates[index]
	step_label.text = "确认人物"
	detail_label.text = (
		"%s\n人口来源：%s\n起始地点：%s\n出生年：%d（约 %d 岁）\n\n"
		+ "姓名、职业、工资、财富、关系与技能当前版本尚未模拟。"
	) % [
		str(candidate.get("display_label", "人物")),
		str(candidate.get("population_origin_id", "")),
		_place_name(str(candidate.get("start_place_id", ""))),
		int(candidate.get("birth_year", 0)),
		int(candidate.get("approximate_age", 0)),
	]
	origin_selector.visible = false
	place_selector.visible = false
	candidate_actions.visible = false
	next_button.visible = false
	reroll_button.visible = false
	confirm_button.visible = true
	cancel_button.text = "返回候选"


func _on_confirm_pressed() -> void:
	if _selected_candidate_index < 0 or _selected_candidate_index >= _candidates.size():
		return
	var candidate := _candidates[_selected_candidate_index]
	status_label.text = "正在原子建立正式人物与世界……"
	var request_id := "new_game:%s" % str(candidate.get("candidate_token", "")).left(16)
	var result := _new_game_service.create_new_game(
		str(candidate.get("candidate_token", "")), request_id
	)
	if not bool(result.get("success", false)):
		_show_error("确认失败：%s" % str(result.get("message", "未知错误")))
		return
	var world_value: Variant = result.get("world")
	if not world_value is FormalWorldSimulation:
		_show_error("确认失败：未产生可交付的 Formal 世界。")
		return
	_enter_world("new", world_value as FormalWorldSimulation)


func _on_cancel_pressed() -> void:
	if _selected_candidate_index >= 0:
		_selected_candidate_index = -1
		_show_candidates()
		return
	_show_title()


func _show_title() -> void:
	_selected_candidate_index = -1
	title_actions.visible = true
	wizard_panel.visible = false
	prompt_label.visible = true


func _show_origin() -> void:
	title_actions.visible = false
	wizard_panel.visible = true
	prompt_label.visible = false
	step_label.text = "Character Origin"
	detail_label.text = (
		"起点只来自 FormalPopulationInputView 与已组合的 Spatial 地点映射。\n"
		+ "地图几何覆盖不授予人口来源。"
	)
	origin_selector.visible = true
	place_selector.visible = true
	candidate_actions.visible = false
	next_button.visible = true
	reroll_button.visible = false
	confirm_button.visible = false
	cancel_button.text = "取消"
	status_label.text = "选择人口来源与合法起始地点。"


func _show_candidates() -> void:
	title_actions.visible = false
	wizard_panel.visible = true
	prompt_label.visible = false
	step_label.text = "候选人物"
	detail_label.text = "以下只是纯预览；尚未建立人物、claim 或世界。"
	origin_selector.visible = false
	place_selector.visible = false
	candidate_actions.visible = true
	next_button.visible = false
	reroll_button.visible = true
	confirm_button.visible = false
	cancel_button.text = "返回起点"
	status_label.text = "选择一个候选进入确认。"


func _populate_origins() -> void:
	origin_selector.clear()
	for origin: Dictionary in _catalog.get("origins", []):
		origin_selector.add_item(str(origin.get("id", "")))
		origin_selector.set_item_metadata(
			origin_selector.item_count - 1, str(origin.get("id", ""))
		)
	if origin_selector.item_count > 0:
		var france_index := -1
		for index: int in origin_selector.item_count:
			if str(origin_selector.get_item_metadata(index)) == "country_fra":
				france_index = index
				break
		origin_selector.select(france_index if france_index >= 0 else 0)
	_populate_places()


func _populate_places() -> void:
	place_selector.clear()
	var origin := _selected_origin()
	for place: Dictionary in origin.get("places", []):
		place_selector.add_item("%s · %s" % [
			str(place.get("name", place.get("map_id", ""))),
			str(place.get("spatial_kind", "place")),
		])
		place_selector.set_item_metadata(
			place_selector.item_count - 1, str(place.get("id", ""))
		)
	if place_selector.item_count > 0:
		var lille_index := -1
		for index: int in place_selector.item_count:
			if str(place_selector.get_item_metadata(index)) == "place:lille":
				lille_index = index
				break
		place_selector.select(lille_index if lille_index >= 0 else 0)


func _rebuild_candidate_buttons() -> void:
	for child: Node in candidate_actions.get_children():
		child.queue_free()
	for index: int in _candidates.size():
		var candidate := _candidates[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(520.0, 42.0)
		button.text = "%s  ·  %s  ·  %d年（约%d岁）" % [
			str(candidate.get("display_label", "人物")),
			_place_name(str(candidate.get("start_place_id", ""))),
			int(candidate.get("birth_year", 0)),
			int(candidate.get("approximate_age", 0)),
		]
		button.pressed.connect(_on_candidate_pressed.bind(index))
		candidate_actions.add_child(button)


func _current_preview_request() -> Dictionary:
	return {
		"population_origin_id": str(origin_selector.get_item_metadata(origin_selector.selected)),
		"start_place_id": str(place_selector.get_item_metadata(place_selector.selected)),
		"birth_year_min": 1860,
		"birth_year_max": 1882,
		"random_origin": false,
		"locked_fields": {},
		"seed": 19000101,
		"rules_version": FormalNewGameService.RULES_VERSION,
		"draft_index": _draft_index,
	}


func _selected_origin() -> Dictionary:
	if origin_selector.selected < 0:
		return {}
	var origin_id := str(origin_selector.get_item_metadata(origin_selector.selected))
	for origin: Dictionary in _catalog.get("origins", []):
		if str(origin.get("id", "")) == origin_id:
			return origin
	return {}


func _place_name(place_id: String) -> String:
	for origin: Dictionary in _catalog.get("origins", []):
		for place: Dictionary in origin.get("places", []):
			if str(place.get("id", "")) == place_id:
				return str(place.get("name", place.get("map_id", place_id)))
	return place_id


func _enter_world(mode: String, world: FormalWorldSimulation) -> void:
	if _entering:
		return
	_entering = true
	get_tree().set_meta(LAUNCH_MODE_META, mode)
	get_tree().set_meta(LAUNCH_WORLD_META, world)
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error == OK:
		return
	get_tree().remove_meta(LAUNCH_MODE_META)
	get_tree().remove_meta(LAUNCH_WORLD_META)
	_entering = false
	_show_error("无法打开正式世界：%s" % error_string(error))


func _start_packaged_new_game() -> void:
	_on_new_game_pressed()
	if not wizard_panel.visible or origin_selector.item_count <= 0 or place_selector.item_count <= 0:
		get_tree().quit(1)
		return
	_on_next_pressed()
	if _candidates.is_empty():
		get_tree().quit(1)
		return
	_on_candidate_pressed(0)
	_on_confirm_pressed()


func _show_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("#c57b67"))
	_entering = false


func _formal_save_exists() -> bool:
	return (
		FileAccess.file_exists(FormalWorldSimulation.SAVE_PATH)
		or FileAccess.file_exists(FormalWorldSimulation.SAVE_PATH + ".bak")
	)
