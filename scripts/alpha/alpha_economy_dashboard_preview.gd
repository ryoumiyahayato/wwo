class_name AlphaEconomyDashboardPreview
extends Control
## Player-visible audit preview for the population-linked commodity market.
## It uses the isolated eight-region Alpha fixture and does not claim formal-world integration.

const FORMAL_MENU_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_menu.tscn"
const PREVIEW_DAYS: int = 30
const CAPTURE_PREFIX: String = "--economy-audit-capture="

var simulation := AlphaSimulationService.new()
var summary_labels: Dictionary = {}
var region_option: OptionButton
var commodity_option: OptionButton
var market_tree: Tree
var flow_list: ItemList
var ai_list: ItemList
var status_label: Label
var date_label: Label
var _selected_region_id: String = ""
var _selected_commodity_id: String = "bread"
var _capture_path: String = ""
var _capture_in_progress: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().min_size = Vector2i(1100, 620)
	_build_interface()
	if not simulation.initialize():
		status_label.text = "经济系统初始化失败：%s" % simulation.initialization_error
		status_label.add_theme_color_override("font_color", Color("#db796d"))
		return
	simulation.advance_hours(PREVIEW_DAYS * 24)
	_populate_selectors()
	_refresh_all()
	_capture_path = _capture_argument()
	if not _capture_path.is_empty():
		_capture_in_progress = true
		call_deferred("_capture_after_frames")
	DisplayServer.window_set_title("《1900》· 经济系统审计预览")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back_to_menu()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("#0d151b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_summary_row())
	root.add_child(_build_body())
	root.add_child(_build_footer())


func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 58)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	panel.add_child(bar)

	var title := Label.new()
	title.text = "1900 经济系统审计"
	title.add_theme_font_size_override("font_size", 21)
	title.custom_minimum_size = Vector2(230, 0)
	bar.add_child(title)

	date_label = Label.new()
	date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(date_label)
	bar.add_child(_button("+1日", _advance_days.bind(1)))
	bar.add_child(_button("+30日", _advance_days.bind(30)))
	bar.add_child(_button("返回正式菜单", _back_to_menu))
	return panel


func _build_summary_row() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 86)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)
	for definition: Dictionary in [
		{"id": "population", "title": "总人口"},
		{"id": "fulfillment", "title": "消费满足率"},
		{"id": "unemployment", "title": "失业率"},
		{"id": "imports", "title": "今日国际进口"},
		{"id": "exports", "title": "今日国际出口"},
		{"id": "ai", "title": "AI决策记录"},
	]:
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(150, 64)
		var heading := Label.new()
		heading.text = str(definition["title"])
		heading.add_theme_color_override("font_color", Color("#8fa6ae"))
		box.add_child(heading)
		var value := Label.new()
		value.text = "—"
		value.add_theme_font_size_override("font_size", 19)
		box.add_child(value)
		summary_labels[str(definition["id"])] = value
		grid.add_child(box)
	return panel


func _build_body() -> Control:
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 225
	split.add_child(_build_region_panel())

	var center_right := HSplitContainer.new()
	center_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_right.split_offset = 720
	center_right.add_child(_build_market_panel())
	center_right.add_child(_build_activity_panel())
	split.add_child(center_right)
	return split


func _build_region_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(225, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "地区市场"
	heading.add_theme_font_size_override("font_size", 17)
	box.add_child(heading)
	region_option = OptionButton.new()
	region_option.item_selected.connect(_on_region_selected)
	box.add_child(region_option)

	var commodity_heading := Label.new()
	commodity_heading.text = "地图/流量关注商品"
	box.add_child(commodity_heading)
	commodity_option = OptionButton.new()
	commodity_option.item_selected.connect(_on_commodity_selected)
	box.add_child(commodity_option)

	var note := Label.new()
	note.text = (
		"此页面展示当前商品市场的真实运行状态。\n"
		+ "地区名称仍来自隔离的Alpha样本，尚未接入正式里尔与全球历史行政区。"
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("#c6a77a"))
	note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(note)
	return panel


func _build_market_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "商品库存、价格与当日交易流"
	heading.add_theme_font_size_override("font_size", 17)
	box.add_child(heading)

	market_tree = Tree.new()
	market_tree.name = "MarketTree"
	market_tree.columns = 9
	market_tree.column_titles_visible = true
	var titles: Array[String] = [
		"商品", "价格", "库存", "需求", "生产", "消费", "短缺", "进口", "出口",
	]
	for index: int in range(titles.size()):
		market_tree.set_column_title(index, titles[index])
		market_tree.set_column_expand(index, index == 0)
		if index > 0:
			market_tree.set_column_custom_minimum_width(index, 68)
	market_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(market_tree)
	return panel


func _build_activity_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var flow_heading := Label.new()
	flow_heading.text = "近期交易与调拨"
	flow_heading.add_theme_font_size_override("font_size", 16)
	box.add_child(flow_heading)
	flow_list = ItemList.new()
	flow_list.name = "FlowList"
	flow_list.custom_minimum_size = Vector2(0, 210)
	flow_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(flow_list)

	var ai_heading := Label.new()
	ai_heading.text = "人物AI经济决策"
	ai_heading.add_theme_font_size_override("font_size", 16)
	box.add_child(ai_heading)
	ai_list = ItemList.new()
	ai_list.name = "AiDecisionList"
	ai_list.custom_minimum_size = Vector2(0, 190)
	ai_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(ai_list)
	return panel


func _build_footer() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 42)
	status_label = Label.new()
	status_label.name = "AuditStatus"
	status_label.text = "正在初始化经济系统……"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)
	return panel


func _populate_selectors() -> void:
	region_option.clear()
	var region_ids: Array[String] = []
	for raw_id: Variant in simulation.commodity_market.region_states:
		region_ids.append(str(raw_id))
	region_ids.sort()
	for region_id: String in region_ids:
		region_option.add_item(_region_label(region_id))
		region_option.set_item_metadata(region_option.item_count - 1, region_id)
	if not region_ids.is_empty():
		_selected_region_id = region_ids[0]

	commodity_option.clear()
	var commodity_ids: Array[String] = []
	for raw_id: Variant in simulation.commodity_market.commodities:
		commodity_ids.append(str(raw_id))
	commodity_ids.sort_custom(func(a: String, b: String) -> bool:
		return _commodity_label(a) < _commodity_label(b)
	)
	for commodity_id: String in commodity_ids:
		commodity_option.add_item(_commodity_label(commodity_id))
		commodity_option.set_item_metadata(commodity_option.item_count - 1, commodity_id)
		if commodity_id == _selected_commodity_id:
			commodity_option.select(commodity_option.item_count - 1)
	if not simulation.commodity_market.commodities.has(_selected_commodity_id) and not commodity_ids.is_empty():
		_selected_commodity_id = commodity_ids[0]


func _refresh_all() -> void:
	if not simulation.initialized:
		return
	var summary: Dictionary = simulation.commodity_market.world_summary()
	date_label.text = "%s · 已运行 %d 日" % [
		V2DateTime.iso_from_total_hour(simulation.clock.total_hours),
		simulation.clock.total_hours / 24,
	]
	(summary_labels["population"] as Label).text = _compact_number(int(summary.get("population", 0)))
	(summary_labels["fulfillment"] as Label).text = _percent(int(summary.get("fulfillment_bp", 0)))
	(summary_labels["unemployment"] as Label).text = _percent(int(summary.get("unemployment_bp", 0)))
	(summary_labels["imports"] as Label).text = _quantity(float(summary.get("international_import_units", 0.0)))
	(summary_labels["exports"] as Label).text = _quantity(float(summary.get("international_export_units", 0.0)))
	(summary_labels["ai"] as Label).text = str(simulation.alpha_ai.decisions.size())
	_refresh_market_tree()
	_refresh_flow_list()
	_refresh_ai_list()
	status_label.text = (
		"运行正常：%d种商品、%d个生产设施、%d个地区；"
		+ "当前页面为可操作审计预览，正式世界经济接入仍待完成。"
	) % [
		simulation.commodity_market.commodities.size(),
		simulation.commodity_market.production_sites.size(),
		simulation.commodity_market.region_states.size(),
	]


func _refresh_market_tree() -> void:
	market_tree.clear()
	var root: TreeItem = market_tree.create_item()
	var report: Dictionary = simulation.commodity_market.region_report(_selected_region_id)
	var inventory: Dictionary = report.get("inventory", {}) as Dictionary
	var prices: Dictionary = report.get("prices", {}) as Dictionary
	var metrics: Dictionary = report.get("daily_metrics", {}) as Dictionary
	var rows: Array[Dictionary] = []
	for raw_id: Variant in simulation.commodity_market.commodities:
		var commodity_id: String = str(raw_id)
		var demand: float = _metric(metrics, "demand", commodity_id)
		var produced: float = _metric(metrics, "produced", commodity_id)
		var consumed: float = _metric(metrics, "consumed", commodity_id)
		var unmet: float = _metric(metrics, "unmet", commodity_id)
		var imported: float = _metric(metrics, "international_imports", commodity_id)
		var exported: float = _metric(metrics, "international_exports", commodity_id)
		if (
			demand <= 0.0001 and produced <= 0.0001 and consumed <= 0.0001
			and unmet <= 0.0001 and imported <= 0.0001 and exported <= 0.0001
			and float(inventory.get(commodity_id, 0.0)) <= 0.0001
		):
			continue
		rows.append({
			"id": commodity_id,
			"priority": unmet * 1000.0 + imported * 10.0 + demand,
			"demand": demand,
			"produced": produced,
			"consumed": consumed,
			"unmet": unmet,
			"imported": imported,
			"exported": exported,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0))
	)
	for row: Dictionary in rows:
		var commodity_id: String = str(row["id"])
		var item: TreeItem = market_tree.create_item(root)
		item.set_text(0, _commodity_label(commodity_id))
		item.set_text(1, _money(int(prices.get(commodity_id, 0))))
		item.set_text(2, _quantity(float(inventory.get(commodity_id, 0.0))))
		item.set_text(3, _quantity(float(row["demand"])))
		item.set_text(4, _quantity(float(row["produced"])))
		item.set_text(5, _quantity(float(row["consumed"])))
		item.set_text(6, _quantity(float(row["unmet"])))
		item.set_text(7, _quantity(float(row["imported"])))
		item.set_text(8, _quantity(float(row["exported"])))
		if commodity_id == _selected_commodity_id:
			item.set_custom_color(0, Color("#e7c36b"))


func _refresh_flow_list() -> void:
	flow_list.clear()
	var report: Dictionary = simulation.commodity_market.region_report(_selected_region_id)
	var metrics: Dictionary = report.get("daily_metrics", {}) as Dictionary
	var entries: Array[Dictionary] = []
	for definition: Dictionary in [
		{"key": "regional_received", "label": "区域调入"},
		{"key": "regional_sent", "label": "区域调出"},
		{"key": "international_imports", "label": "国际进口"},
		{"key": "international_exports", "label": "国际出口"},
	]:
		var values: Dictionary = metrics.get(str(definition["key"]), {}) as Dictionary
		for raw_id: Variant in values:
			var amount: float = float(values[raw_id])
			if amount <= 0.0001:
				continue
			entries.append({
				"label": "%s · %s  %s" % [
					str(definition["label"]), _commodity_label(str(raw_id)), _quantity(amount),
				],
				"amount": amount,
			})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("amount", 0.0)) > float(b.get("amount", 0.0))
	)
	for index: int in range(mini(14, entries.size())):
		flow_list.add_item(str(entries[index]["label"]))
	if flow_list.item_count == 0:
		flow_list.add_item("今日无跨地区或国际流量")


func _refresh_ai_list() -> void:
	ai_list.clear()
	var decisions: Array[Dictionary] = simulation.alpha_ai.decisions
	var start: int = maxi(0, decisions.size() - 12)
	for index: int in range(decisions.size() - 1, start - 1, -1):
		var decision: Dictionary = decisions[index]
		ai_list.add_item("%s · %s · %s" % [
			str(decision.get("person_id", "")).get_slice("_", 1),
			str(decision.get("action_id", "wait")),
			"成功" if bool(decision.get("execution_success", false)) else "未执行",
		])
	if ai_list.item_count == 0:
		ai_list.add_item("尚无AI决策记录")


func _advance_days(days: int) -> void:
	if simulation.initialized:
		simulation.advance_hours(maxi(0, days) * 24)
		_refresh_all()


func _on_region_selected(index: int) -> void:
	_selected_region_id = str(region_option.get_item_metadata(index))
	_refresh_all()


func _on_commodity_selected(index: int) -> void:
	_selected_commodity_id = str(commodity_option.get_item_metadata(index))
	_refresh_all()


func _back_to_menu() -> void:
	if _capture_in_progress:
		return
	get_tree().change_scene_to_file(FORMAL_MENU_SCENE)


func _capture_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_PREFIX):
			return argument.trim_prefix(CAPTURE_PREFIX)
	return ""


func _capture_after_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(_capture_path)
	print("ECONOMY_AUDIT_CAPTURE=%s ERROR=%s" % [_capture_path, error_string(error)])
	get_tree().quit(0 if error == OK else 1)


func _region_label(region_id: String) -> String:
	var profile: Dictionary = simulation.world.regions.get(region_id, {}) as Dictionary
	var role: String = str(profile.get("economic_role", ""))
	return "%s · %s" % [region_id.get_slice(":", 1), role.left(12)]


func _commodity_label(commodity_id: String) -> String:
	var commodity: Dictionary = simulation.commodity_market.commodities.get(
		commodity_id, {}
	) as Dictionary
	return str(commodity.get("name_zh", commodity_id))


func _metric(metrics: Dictionary, key: String, commodity_id: String) -> float:
	return float((metrics.get(key, {}) as Dictionary).get(commodity_id, 0.0))


func _money(centimes: int) -> String:
	return "%.2f" % (float(centimes) / 100.0)


func _quantity(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.1fK" % (value / 1000.0)
	return "%.1f" % value


func _compact_number(value: int) -> String:
	return _quantity(float(value))


func _percent(basis_points: int) -> String:
	return "%.1f%%" % (float(basis_points) / 100.0)


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(96, 38)
	button.pressed.connect(callback)
	return button
