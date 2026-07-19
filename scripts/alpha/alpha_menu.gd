class_name AlphaMenu
extends Control
## Explicit launcher for the quarantined Loran/Vesta grid implementation fixture.
## Normal launches are redirected to the formal V2.3 world-map menu.

const FORMAL_MENU_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_menu.tscn"
const FIXTURE_SCENE: String = "res://scenes/alpha/alpha_grid_fixture.tscn"
const FIXTURE_FLAG: String = "--alpha-grid-fixture"

var preset_option: OptionButton
var load_button: Button
var migrate_button: Button
var developer_check: CheckButton
var status_label: Label
var _config := AlphaConfig.new()

const REVIEW_LABELS: Dictionary = {
	"employed_worker": "普通受雇人物",
	"indebted_low_income": "低收入负债人物",
	"leveraged_enterprise": "高杠杆企业人物",
	"enterprise_near_bankruptcy": "企业接近破产",
	"isolated_professional": "有专业能力但缺乏关系",
	"weak_owner_strong_partner": "能力较弱但有优秀合作者",
	"local_official": "地方官员",
	"business_owner_in_politics": "企业所有者参与政治",
	"policy_changed_region": "政策造成地区经济变化",
	"interregional_trade_and_migration": "跨地区迁移和经营",
	"world_after_three_years": "已经运行三年的世界",
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not OS.get_cmdline_user_args().has(FIXTURE_FLAG):
		call_deferred("_return_to_formal_world")
		return
	_build_interface()
	if _config.load_all() != OK:
		status_label.text = "网格服务夹具配置无法加载：%s" % "; ".join(_config.errors)
		return
	for review_state_id: String in _config.review_state_ids():
		preset_option.add_item(str(REVIEW_LABELS.get(review_state_id, review_state_id)))
		preset_option.set_item_metadata(preset_option.item_count - 1, review_state_id)
	_refresh_availability()
	DisplayServer.window_set_title("《1900》· 网格服务回归夹具")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_to_formal_world()
		get_viewport().set_input_as_handled()


func _return_to_formal_world() -> void:
	var error: Error = get_tree().change_scene_to_file(FORMAL_MENU_SCENE)
	if error != OK:
		push_error("Unable to open formal world-map menu: %s" % error_string(error))


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("#10212a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var phase := Label.new()
	phase.text = "内部网格服务回归夹具"
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase.add_theme_color_override("font_color", Color("#e1a06c"))
	box.add_child(phase)
	var title := Label.new()
	title.text = "非玩家界面"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var warning := Label.new()
	warning.text = (
		"此入口只用于自动回归、迁移和性能定位。"
		+ String.chr(10)
		+ "洛岚—维斯塔10×8网格、原始对象字典和快捷动作均不是正式游戏内容。"
		+ String.chr(10)
		+ "普通游戏请返回正式世界地图。"
	)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_color_override("font_color", Color("#e7c7a9"))
	box.add_child(warning)
	box.add_child(_button("返回正式世界地图", _return_to_formal_world))
	var preset_label := Label.new()
	preset_label.text = "内部检查预设"
	box.add_child(preset_label)
	preset_option = OptionButton.new()
	box.add_child(preset_option)
	developer_check = CheckButton.new()
	developer_check.text = "启用内部检查命令（F12）"
	box.add_child(developer_check)
	box.add_child(_button("进入内部网格夹具", _open.bind("new")))
	load_button = _button("载入内部夹具存档", _open.bind("load"))
	box.add_child(load_button)
	migrate_button = _button("执行V2.3到夹具的迁移回归", _open.bind("migrate"))
	box.add_child(migrate_button)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	var footer := Label.new()
	footer.text = "必须使用 --alpha-grid-fixture 显式启动"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color("#72838a"))
	box.add_child(footer)


func _refresh_availability() -> void:
	load_button.disabled = not (
		FileAccess.file_exists(AlphaSaveService.REVIEW_PATH)
		or FileAccess.file_exists(AlphaSaveService.REVIEW_PATH + ".bak")
	)
	migrate_button.disabled = not (
		FileAccess.file_exists(V23SaveService.REVIEW_PATH)
		or FileAccess.file_exists(V23SaveService.REVIEW_PATH + ".bak")
	)
	status_label.text = "夹具存档：%s · 迁移回归输入：%s" % [
		"可用" if not load_button.disabled else "无",
		"可用" if not migrate_button.disabled else "无",
	]


func _open(mode: String) -> void:
	get_tree().set_meta(AlphaMain.LAUNCH_MODE_META, mode)
	get_tree().set_meta(
		AlphaMain.REVIEW_STATE_META,
		str(preset_option.get_item_metadata(preset_option.selected))
	)
	get_tree().set_meta(AlphaMain.DEVELOPER_META, developer_check.button_pressed)
	var error: Error = get_tree().change_scene_to_file(FIXTURE_SCENE)
	if error != OK:
		status_label.text = "无法进入内部网格夹具：%s" % error_string(error)


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(callback)
	return button
