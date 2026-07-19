class_name AlphaGridFixture
extends AlphaMain
## Internal-only presentation for the quarantined Loran/Vesta service fixture.

const FORMAL_MENU_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_menu.tscn"


func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("《1900》· 内部网格服务回归夹具")
	status_label.text = "内部回归夹具：不代表正式地图、玩家界面或完整可玩 Alpha。"
	status_label.add_theme_color_override("font_color", Color("#e1a06c"))


func _build_top_bar() -> Control:
	var panel: Control = super._build_top_bar()
	var bar: HBoxContainer = panel.get_child(0) as HBoxContainer
	if bar != null and bar.get_child_count() > 0:
		var title: Label = bar.get_child(0) as Label
		if title != null:
			title.text = "内部网格夹具"
			title.tooltip_text = "已否决的洛岚—维斯塔10×8实现，只供自动回归"
	return panel


func _refresh_detail() -> void:
	if binding == null or _selected_object_id.is_empty():
		detail_title.text = "内部对象检查"
		detail_text.text = (
			"该入口不提供玩家对象界面。"
			+ String.chr(10)
			+ "选择对象后仅显示最小诊断摘要；完整结构由自动测试读取。"
		)
		_clear_actions()
		return
	var detail: Dictionary = binding.object_detail(
		_selected_kind, _selected_object_id
	)
	detail_title.text = "内部诊断 · %s" % str(
		KIND_LABELS.get(_selected_kind, _selected_kind)
	)
	detail_text.text = _diagnostic_summary(detail)
	_clear_actions()
	for action: Dictionary in binding.available_actions(
		_selected_kind, _selected_object_id
	):
		actions_box.add_child(_button(
			"内部调用：%s" % str(action.get("label", "")),
			_execute_action.bind(str(action.get("action_id", "")))
		))


func _diagnostic_summary(detail: Dictionary) -> String:
	var lines: Array[String] = [
		"此处不是正式人物/企业/组织界面。",
		"对象来自已隔离的架空网格服务夹具。",
		"",
		"对象ID：%s" % _selected_object_id,
	]
	for key: String in [
		"name", "display_name", "status", "occupation", "public_position",
		"country_id", "region_id", "location_id", "owner_id", "controller_id",
		"cash_centimes", "balance_centimes", "principal_centimes",
	]:
		if detail.has(key):
			lines.append("%s：%s" % [_diagnostic_label(key), str(detail[key])])
	var nested_count: int = 0
	for key_variant: Variant in detail.keys():
		var value: Variant = detail[key_variant]
		if value is Dictionary or value is Array:
			nested_count += 1
	if nested_count > 0:
		lines.append("")
		lines.append("已隐藏 %d 组内部嵌套字段。" % nested_count)
	lines.append("原始JSON已从可见界面移除。")
	return String.chr(10).join(lines)


func _diagnostic_label(key: String) -> String:
	return str({
		"name": "名称",
		"display_name": "显示名称",
		"status": "状态",
		"occupation": "职业",
		"public_position": "公开身份",
		"country_id": "国家引用",
		"region_id": "地区引用",
		"location_id": "地点引用",
		"owner_id": "所有者引用",
		"controller_id": "控制者引用",
		"cash_centimes": "现金",
		"balance_centimes": "余额",
		"principal_centimes": "本金",
	}.get(key, key))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(FORMAL_MENU_SCENE)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_F12 and dev_panel != null:
			dev_panel.visible = not dev_panel.visible
			get_viewport().set_input_as_handled()


func _back_to_menu() -> void:
	get_tree().change_scene_to_file(FORMAL_MENU_SCENE)
