class_name V23PlayerInterface
extends V23MinuteFormalInterfaceV2
## Small product HUD additions: explicit map-layer switching and readable
## household supply status. Neither surface exposes internal AI state.


func _draw() -> void:
	super._draw()
	if life_binding == null:
		return
	if open_panel.is_empty() and not system_menu_open and not time_menu_open:
		_draw_map_layer_controls()
		_draw_supply_status()


func _draw_v2_3_sandbox_panel() -> void:
	super._draw_v2_3_sandbox_panel()
	var binding: V23PlayerUiBinding = life_binding as V23PlayerUiBinding
	if binding == null:
		return
	var view: Dictionary = binding.sandbox_view()
	var preview: Dictionary = view.get("preview", {}) as Dictionary
	if str(preview.get("error_code", "")) != "requires_leave_authorization":
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(
		Rect2(rect.position.x + 18.0, rect.end.y - 78.0, rect.size.x - 36.0, 54.0),
		Color(AMBER, 0.08),
		Color(AMBER, 0.35),
		7
	)
	_text(
		Vector2(rect.position.x + 30.0, rect.end.y - 49.0),
		"行程会占用合同工时，需要由玩家确认请假。",
		10,
		AMBER
	)
	_primary_action(
		Rect2(rect.end.x - 188.0, rect.end.y - 68.0, 158.0, 35.0),
		"请假并建立计划",
		"sandbox_plan_confirm_leave",
		null,
		"解除与行程重叠的工作义务，再原子建立行动计划"
	)


func _draw_map_layer_controls() -> void:
	var map: WorldMapCanvas = _map_canvas()
	if map == null:
		return
	var current_scope: String = map.get_map_scope()
	var rect := Rect2(20.0, 122.0, 272.0, 38.0)
	_surface(rect, Color(0.025, 0.055, 0.06, 0.90), Color(GOLD, 0.22), 8)
	var items: Array = [
		["世界", WorldMapCanvas.MAP_SCOPE_WORLD],
		["区域交通", WorldMapCanvas.MAP_SCOPE_REGIONAL],
		["城市", WorldMapCanvas.MAP_SCOPE_CITY],
	]
	var widths: Array[float] = [68.0, 96.0, 68.0]
	var x: float = rect.position.x + 8.0
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		_compact_action(
			Rect2(x, rect.position.y + 6.0, widths[index], 26.0),
			str(item[0]),
			current_scope == str(item[1]),
			"map_scope",
			str(item[1]),
			"切换地图层级"
		)
		x += widths[index] + 7.0


func _draw_supply_status() -> void:
	var binding: V23PlayerUiBinding = life_binding as V23PlayerUiBinding
	if binding == null:
		return
	var maintenance: Dictionary = binding.person_view().get("maintenance", {}) as Dictionary
	if maintenance.is_empty():
		return
	var rect := Rect2(20.0, 612.0, 304.0, 32.0)
	_surface(rect, Color(0.025, 0.055, 0.06, 0.88), Color(INK_DIM, 0.18), 7)
	var active_need: Dictionary = maintenance.get("active_need", {}) as Dictionary
	var suffix: String = ""
	if not active_need.is_empty():
		var item_label: String = "食品" if str(active_need.get("item_type", "")) == "food" else "生活用品"
		var status: String = str(active_need.get("status", ""))
		suffix = " · %s%s" % [item_label, "已安排补充" if status.contains("scheduled") else "次日重试"]
	_text(
		rect.position + Vector2(12.0, 21.0),
		"食品约 %d 天 · 生活用品约 %d 天%s" % [
			int(maintenance.get("food_days", 0)),
			int(maintenance.get("essentials_days", 0)),
			suffix,
		],
		10,
		AMBER if int(maintenance.get("food_days", 0)) <= 2 or int(maintenance.get("essentials_days", 0)) <= 2 else INK_MUTED
	)


func _activate(action: String, payload: Variant) -> void:
	if action == "map_scope":
		var map: WorldMapCanvas = _map_canvas()
		if map != null:
			map.set_map_scope(str(payload))
		queue_redraw()
		return
	if action == "sandbox_plan_confirm_leave":
		var binding: V23PlayerUiBinding = life_binding as V23PlayerUiBinding
		if binding != null:
			var result: V2LifeLoopResult = binding.submit_selected_sandbox_plan_with_leave()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		queue_redraw()
		return
	super._activate(action, payload)


func _map_canvas() -> WorldMapCanvas:
	var parent: Node = get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PrototypeMap") as WorldMapCanvas
