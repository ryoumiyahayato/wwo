class_name AlphaMenu
extends Control
## Alpha launcher with presets, safe load and explicit V2.3 migration.

const MAIN_SCENE: String = "res://scenes/alpha/alpha_main.tscn"

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
	_build_interface()
	if _config.load_all() != OK:
		status_label.text = "Alpha 配置无法加载：%s" % "; ".join(_config.errors)
		return
	for review_state_id: String in _config.review_state_ids():
		preset_option.add_item(str(REVIEW_LABELS.get(
			review_state_id, review_state_id
		)))
		preset_option.set_item_metadata(
			preset_option.item_count - 1, review_state_id
		)
	_refresh_availability()
	DisplayServer.window_set_title("《1900》· Alpha")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("#10212a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 0)
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
	phase.text = "首个持续运行的完整可玩 Alpha"
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase.add_theme_color_override("font_color", Color("#d5bd72"))
	box.add_child(phase)
	var title := Label.new()
	title.text = "《1900》"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "人物、劳动、商业、债务、合作、组织与政治处于同一运行世界"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	var preset_label := Label.new()
	preset_label.text = "起始人物与处境"
	box.add_child(preset_label)
	preset_option = OptionButton.new()
	box.add_child(preset_option)
	developer_check = CheckButton.new()
	developer_check.text = "启用开发检查面板（F12）"
	box.add_child(developer_check)
	box.add_child(_button("进入新世界", _open.bind("new")))
	load_button = _button("载入 Alpha 存档", _open.bind("load"))
	box.add_child(load_button)
	migrate_button = _button("迁移并载入 V2.3 存档", _open.bind("migrate"))
	box.add_child(migrate_button)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	box.add_child(_button("退出", get_tree().quit))
	var footer := Label.new()
	footer.text = "离线 · 单一小时钟 · 1280×720 · Compatibility"
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
	status_label.text = "Alpha 存档：%s · 可迁移 V2.3：%s" % [
		"可用" if not load_button.disabled else "无",
		"是" if not migrate_button.disabled else "否",
	]


func _open(mode: String) -> void:
	get_tree().set_meta(AlphaMain.LAUNCH_MODE_META, mode)
	get_tree().set_meta(
		AlphaMain.REVIEW_STATE_META,
		str(preset_option.get_item_metadata(preset_option.selected))
	)
	get_tree().set_meta(AlphaMain.DEVELOPER_META, developer_check.button_pressed)
	var error: Error = get_tree().change_scene_to_file(MAIN_SCENE)
	if error != OK:
		status_label.text = "无法进入 Alpha 世界：%s" % error_string(error)


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(callback)
	return button
