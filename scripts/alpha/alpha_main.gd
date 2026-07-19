class_name AlphaMain
extends Control
## 1280x720 Alpha shell. Timers advance the clock; no business logic runs per frame.

const MENU_SCENE: String = "res://scenes/alpha/alpha_menu.tscn"
const LAUNCH_MODE_META: StringName = &"alpha_launch_mode"
const PRESET_META: StringName = &"alpha_preset_id"
const REVIEW_STATE_META: StringName = &"alpha_review_state_id"
const DEVELOPER_META: StringName = &"alpha_developer_mode"

const KIND_LABELS: Dictionary = {
	"person": "人物",
	"location": "地点",
	"enterprise": "企业",
	"organization": "组织",
	"job": "工作",
	"contract": "合同",
	"lender": "贷款人",
	"good": "商品/服务",
	"asset": "资产",
}
const INTENTS: Array[Dictionary] = [
	{"id": "observe", "label": "观察当前处境", "filter": "all"},
	{"id": "employment", "label": "关注劳动与职业", "filter": "job"},
	{"id": "enterprise", "label": "关注企业经营", "filter": "enterprise"},
	{"id": "debt", "label": "关注债务期限", "filter": "contract"},
	{"id": "organization", "label": "关注组织与职位", "filter": "organization"},
	{"id": "migration", "label": "关注地区与迁移", "filter": "location"},
]

var simulation: AlphaSimulationService
var binding: AlphaUiBinding
var map_canvas: AlphaMapCanvas
var header_label: Label
var cash_label: Label
var status_label: Label
var object_kind: OptionButton
var object_search: LineEdit
var object_list: ItemList
var detail_title: Label
var detail_text: RichTextLabel
var actions_box: VBoxContainer
var event_list: ItemList
var intent_option: OptionButton
var map_mode_option: OptionButton
var pause_button: Button
var dev_panel: VBoxContainer
var dev_input: LineEdit
var _selected_kind: String = "person"
var _selected_object_id: String = ""
var _view_dirty: bool = true
var _clock_timer: Timer
var _refresh_timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	simulation = AlphaSimulationService.new()
	var preset_id: String = str(get_tree().get_meta(
		PRESET_META, AlphaSimulationService.DEFAULT_PRESET_ID
	))
	var review_state_id: String = str(get_tree().get_meta(
		REVIEW_STATE_META, AlphaSimulationService.DEFAULT_REVIEW_STATE_ID
	))
	if not simulation.set_launch_review_state(review_state_id):
		simulation.set_launch_preset(preset_id)
	if not simulation.initialize():
		_show_fatal(simulation.initialization_error)
		return
	var developer_mode: bool = bool(get_tree().get_meta(DEVELOPER_META, false))
	binding = AlphaUiBinding.new(simulation, developer_mode)
	map_canvas.setup(simulation)
	binding.view_changed.connect(_mark_view_dirty)
	simulation.clock.pause_changed.connect(_on_pause_changed)
	_apply_launch_mode()
	_clock_timer.start()
	_refresh_timer.start()
	_refresh_all()
	DisplayServer.window_set_title("《1900》· 完整 Alpha")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_SCENE)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_F12 and dev_panel != null:
			dev_panel.visible = not dev_panel.visible
			get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("#101821")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	root.add_child(_build_top_bar())
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 220
	root.add_child(body)
	body.add_child(_build_object_browser())
	var center_right := HSplitContainer.new()
	center_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_right.split_offset = 665
	body.add_child(center_right)
	center_right.add_child(_build_map_panel())
	center_right.add_child(_build_detail_panel())
	root.add_child(_build_bottom_bar())
	_clock_timer = Timer.new()
	_clock_timer.wait_time = 0.1
	_clock_timer.timeout.connect(_on_clock_tick)
	add_child(_clock_timer)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.25
	_refresh_timer.timeout.connect(_refresh_if_dirty)
	add_child(_refresh_timer)


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 52)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	panel.add_child(bar)
	var title := Label.new()
	title.text = "《1900》 Alpha"
	title.add_theme_font_size_override("font_size", 19)
	title.custom_minimum_size = Vector2(150, 0)
	bar.add_child(title)
	header_label = Label.new()
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(header_label)
	cash_label = Label.new()
	cash_label.custom_minimum_size = Vector2(210, 0)
	bar.add_child(cash_label)
	pause_button = _button("继续", _toggle_pause)
	bar.add_child(pause_button)
	bar.add_child(_button("+1小时", _advance.bind(1)))
	bar.add_child(_button("+1日", _advance.bind(24)))
	var speed := OptionButton.new()
	speed.tooltip_text = "时间速度"
	for value: int in [1, 2, 4, 8, 16]:
		speed.add_item("×%d" % value, value)
	speed.item_selected.connect(func(index: int) -> void:
		if binding != null:
			binding.set_speed(speed.get_item_id(index))
	)
	bar.add_child(speed)
	bar.add_child(_button("保存", _save))
	bar.add_child(_button("载入", _load))
	bar.add_child(_button("菜单", _back_to_menu))
	return panel


func _build_object_browser() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var label := Label.new()
	label.text = "世界对象"
	label.add_theme_font_size_override("font_size", 16)
	box.add_child(label)
	object_kind = OptionButton.new()
	for kind: String in AlphaUiBinding.OBJECT_KINDS:
		object_kind.add_item(str(KIND_LABELS.get(kind, kind)))
		object_kind.set_item_metadata(object_kind.item_count - 1, kind)
	object_kind.item_selected.connect(_on_kind_selected)
	box.add_child(object_kind)
	object_search = LineEdit.new()
	object_search.placeholder_text = "筛选名称或状态"
	object_search.text_changed.connect(func(_text: String) -> void:
		_refresh_object_list()
	)
	box.add_child(object_search)
	object_list = ItemList.new()
	object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	object_list.item_selected.connect(_on_object_selected)
	box.add_child(object_list)
	return panel


func _build_map_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	panel.add_child(box)
	var controls := HBoxContainer.new()
	var mode_label := Label.new()
	mode_label.text = "地图"
	controls.add_child(mode_label)
	map_mode_option = OptionButton.new()
	for mode: String in AlphaMapCanvas.MODES:
		map_mode_option.add_item(str(AlphaMapCanvas.MODE_LABELS[mode]))
		map_mode_option.set_item_metadata(map_mode_option.item_count - 1, mode)
	map_mode_option.item_selected.connect(func(index: int) -> void:
		map_canvas.set_map_mode(str(map_mode_option.get_item_metadata(index)))
	)
	controls.add_child(map_mode_option)
	var intent_label := Label.new()
	intent_label.text = "当前打算"
	controls.add_child(intent_label)
	intent_option = OptionButton.new()
	intent_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for intent: Dictionary in INTENTS:
		intent_option.add_item(str(intent.get("label", "")))
		intent_option.set_item_metadata(intent_option.item_count - 1, intent)
	intent_option.item_selected.connect(_on_intent_selected)
	controls.add_child(intent_option)
	box.add_child(controls)
	map_canvas = AlphaMapCanvas.new()
	map_canvas.custom_minimum_size = Vector2(570, 430)
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_canvas.object_selected.connect(_on_map_object_selected)
	box.add_child(map_canvas)
	return panel


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	detail_title = Label.new()
	detail_title.text = "对象详情"
	detail_title.add_theme_font_size_override("font_size", 16)
	box.add_child(detail_title)
	detail_text = RichTextLabel.new()
	detail_text.bbcode_enabled = false
	detail_text.fit_content = false
	detail_text.scroll_active = true
	detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(detail_text)
	var action_heading := Label.new()
	action_heading.text = "可执行行为"
	box.add_child(action_heading)
	actions_box = VBoxContainer.new()
	box.add_child(actions_box)
	dev_panel = VBoxContainer.new()
	dev_panel.visible = false
	var dev_label := Label.new()
	dev_label.text = "开发模式（F12）"
	dev_panel.add_child(dev_label)
	dev_input = LineEdit.new()
	dev_input.placeholder_text = "hour 24 / cash 5000 / skill finance 80"
	dev_input.text_submitted.connect(_run_dev_command)
	dev_panel.add_child(dev_input)
	dev_panel.add_child(_button("执行开发命令", func() -> void:
		_run_dev_command(dev_input.text)
	))
	box.add_child(dev_panel)
	return panel


func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 118)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status_label = Label.new()
	status_label.text = "世界已初始化。"
	box.add_child(status_label)
	event_list = ItemList.new()
	event_list.custom_minimum_size = Vector2(0, 80)
	box.add_child(event_list)
	return panel


func _refresh_all() -> void:
	if binding == null:
		return
	var header: Dictionary = binding.world_header()
	header_label.text = "%s · %s · %s" % [
		str(header.get("datetime", "")),
		str(header.get("player_name", "")),
		str(header.get("region_id", "")),
	]
	cash_label.text = "现金 %d · 债务 %d" % [
		int(header.get("cash_centimes", 0)),
		int(header.get("debt_centimes", 0)),
	]
	pause_button.text = "继续" if bool(header.get("paused", true)) else "暂停"
	_refresh_object_list()
	_refresh_detail()
	_refresh_events()
	map_canvas.queue_redraw()
	_view_dirty = false


func _refresh_object_list() -> void:
	if binding == null:
		return
	object_list.clear()
	for item: Dictionary in binding.object_list(
		_selected_kind, object_search.text
	):
		var index: int = object_list.add_item("%s\n%s" % [
			str(item.get("label", "")),
			str(item.get("secondary", "")),
		])
		object_list.set_item_metadata(index, str(item.get("id", "")))


func _refresh_detail() -> void:
	if binding == null or _selected_object_id.is_empty():
		detail_title.text = "对象详情"
		detail_text.text = "从左侧或地图选择具体世界对象。"
		_clear_actions()
		return
	var detail: Dictionary = binding.object_detail(
		_selected_kind, _selected_object_id
	)
	detail_title.text = "%s · %s" % [
		str(KIND_LABELS.get(_selected_kind, _selected_kind)),
		_selected_object_id,
	]
	detail_text.text = JSON.stringify(detail, "\t", false)
	_clear_actions()
	for action: Dictionary in binding.available_actions(
		_selected_kind, _selected_object_id
	):
		actions_box.add_child(_button(
			str(action.get("label", "")),
			_execute_action.bind(str(action.get("action_id", "")))
		))


func _refresh_events() -> void:
	event_list.clear()
	var combined: Array[Dictionary] = []
	combined.append_array(simulation.alpha_events)
	combined.append_array(simulation.world_dynamics.events)
	var start: int = maxi(0, combined.size() - 20)
	for index: int in range(combined.size() - 1, start - 1, -1):
		var event: Dictionary = combined[index]
		event_list.add_item("%s · %s" % [
			V2DateTime.iso_from_total_hour(int(event.get("total_hour", 0))),
			str(event.get("summary", "")),
		])


func _clear_actions() -> void:
	for child: Node in actions_box.get_children():
		child.queue_free()


func _on_kind_selected(index: int) -> void:
	_selected_kind = str(object_kind.get_item_metadata(index))
	_selected_object_id = ""
	_refresh_object_list()
	_refresh_detail()


func _on_object_selected(index: int) -> void:
	_selected_object_id = str(object_list.get_item_metadata(index))
	map_canvas.set_selected_object(_selected_object_id)
	_refresh_detail()


func _on_map_object_selected(kind: String, object_id: String) -> void:
	status_label.text = "地图单元：%s（%s）" % [object_id, kind]


func _on_intent_selected(index: int) -> void:
	if binding == null:
		return
	var intent: Dictionary = intent_option.get_item_metadata(index) as Dictionary
	simulation.set_current_intent(
		"intent:%s" % str(intent.get("id", "")),
		str(intent.get("label", "")),
		[_selected_object_id] if not _selected_object_id.is_empty() else [],
		str(intent.get("filter", "all"))
	)
	var filter_kind: String = str(intent.get("filter", "all"))
	if filter_kind in AlphaUiBinding.OBJECT_KINDS:
		var kind_index: int = AlphaUiBinding.OBJECT_KINDS.find(filter_kind)
		object_kind.select(kind_index)
		_on_kind_selected(kind_index)


func _execute_action(action_id: String) -> void:
	var result: Dictionary = binding.execute_action(
		action_id, _selected_object_id
	)
	_show_result(result)


func _toggle_pause() -> void:
	if binding != null:
		binding.set_pause(not simulation.clock.is_paused)


func _advance(hours: int) -> void:
	if binding != null:
		binding.advance_hours(hours)
		_refresh_all()


func _save() -> void:
	_show_result(binding.save_review())


func _load() -> void:
	_show_result(binding.load_review())


func _run_dev_command(command: String) -> void:
	if binding != null:
		_show_result(binding.developer_command(command))
		dev_input.clear()


func _on_clock_tick() -> void:
	if simulation == null or not simulation.initialized:
		return
	var advanced: int = simulation.advance_real_seconds(_clock_timer.wait_time)
	if advanced > 0:
		_view_dirty = true


func _refresh_if_dirty() -> void:
	if _view_dirty:
		_refresh_all()


func _mark_view_dirty() -> void:
	_view_dirty = true


func _on_pause_changed(_paused: bool) -> void:
	_view_dirty = true


func _apply_launch_mode() -> void:
	var mode: String = str(get_tree().get_meta(LAUNCH_MODE_META, "new"))
	for key: StringName in [
		LAUNCH_MODE_META, PRESET_META, REVIEW_STATE_META, DEVELOPER_META,
	]:
		if get_tree().has_meta(key):
			get_tree().remove_meta(key)
	match mode:
		"load":
			_show_result(binding.load_review())
		"migrate":
			_show_result(binding.migrate_v2_3_review())


func _show_result(result: Dictionary) -> void:
	status_label.text = (
		"完成：%s" % str(result.get("message", ""))
		if bool(result.get("success", false))
		else "未执行：%s · %s" % [
			str(result.get("code", "")), str(result.get("message", "")),
		]
	)
	status_label.add_theme_color_override(
		"font_color",
		Color("#a9d5bd") if bool(result.get("success", false)) else Color("#e2a28c")
	)
	_view_dirty = true


func _show_fatal(message: String) -> void:
	status_label.text = "Alpha 初始化失败：%s" % message
	status_label.add_theme_color_override("font_color", Color("#e27e72"))


func _back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	return button
