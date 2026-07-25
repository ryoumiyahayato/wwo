class_name V23PlayerInterface
extends "res://scripts/v2_3/v2_3_minute_formal_interface_v2.gd"
## Product-facing readability rules and the restrained icon/book workspace overlay.

const PLAYER_MINIMUM_FONT_SIZE: int = 12
const MINIMAL_HUD_OVERLAY_SCRIPT = preload("res://scripts/v2_3/v2_3_minimal_hud_overlay_polish.gd")

var minimal_hud_overlay: V23MinimalHudOverlay


func _ready() -> void:
	super._ready()
	minimal_hud_overlay = MINIMAL_HUD_OVERLAY_SCRIPT.new() as V23MinimalHudOverlay
	minimal_hud_overlay.name = "MinimalHudOverlay"
	minimal_hud_overlay.configure(self)
	add_child(minimal_hud_overlay)
	move_child(minimal_hud_overlay, get_child_count() - 1)


func _text(position: Vector2, value: String, font_size: int, color: Color, max_width: float = -1.0) -> void:
	super._text(position, value, maxi(font_size, PLAYER_MINIMUM_FONT_SIZE), color, max_width)


func _draw() -> void:
	super._draw()
	if life_binding == null:
		return
	if open_panel.is_empty() and not system_menu_open:
		_draw_map_layer_controls()


func _draw_country_corner() -> void:
	pass


func _draw_character_corner() -> void:
	pass


func _draw_time_corner() -> void:
	pass


func _draw_activity_corner() -> void:
	pass


func legacy_corner_draws_suppressed() -> bool:
	return true


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
	_surface(Rect2(rect.position.x + 18.0, rect.end.y - 82.0, rect.size.x - 36.0, 58.0), Color(AMBER, 0.08), Color(AMBER, 0.35), 7)
	_text(Vector2(rect.position.x + 30.0, rect.end.y - 50.0), "行程会占用合同工时，需要由玩家确认请假。", 12, AMBER)
	_primary_action(Rect2(rect.end.x - 192.0, rect.end.y - 72.0, 162.0, 39.0), "请假并建立计划", "sandbox_plan_confirm_leave", null, "解除与行程重叠的工作义务，再原子建立行动计划")


func _draw_map_layer_controls() -> void:
	var map: WorldMapCanvas = _map_canvas()
	if map == null:
		return
	var current_scope: String = map.get_map_scope()
	var rect := Rect2(20.0, 122.0, 284.0, 42.0)
	_surface(rect, Color(0.025, 0.055, 0.06, 0.90), Color(GOLD, 0.22), 8)
	var items: Array = [["世界", WorldMapCanvas.MAP_SCOPE_WORLD], ["区域交通", WorldMapCanvas.MAP_SCOPE_REGIONAL], ["城市", WorldMapCanvas.MAP_SCOPE_CITY]]
	var widths: Array[float] = [72.0, 102.0, 72.0]
	var x: float = rect.position.x + 8.0
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		_compact_action(Rect2(x, rect.position.y + 6.0, widths[index], 30.0), str(item[0]), current_scope == str(item[1]), "map_scope", str(item[1]), "切换地图层级")
		x += widths[index] + 7.0


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
