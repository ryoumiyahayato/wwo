extends "res://scripts/v2_3/v2_3_minimal_hud_overlay.gd"
## Final visual cover: prevent legacy corner text from bleeding through the symbolic HUD.


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.016, 0.030, 0.034, 1.0), true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)


func _draw_newspaper_corner() -> void:
	var rect := _newspaper_rect()
	draw_rect(rect, Color(0.74, 0.73, 0.66, 1.0), true)
	draw_rect(rect, Color(0.25, 0.28, 0.25, 0.82), false, 1.0)
	draw_line(rect.position + Vector2(12.0, 26.0), rect.position + Vector2(rect.size.x - 12.0, 26.0), Color(0.24, 0.27, 0.24, 0.72), 2.0)
	draw_line(rect.position + Vector2(12.0, 30.0), rect.position + Vector2(rect.size.x - 12.0, 30.0), Color(0.24, 0.27, 0.24, 0.42), 1.0)
	_draw_text(rect.position + Vector2(13.0, 20.0), "已知信息", 13, INK)
	var messages := _message_headlines()
	for index: int in range(mini(3, messages.size())):
		_draw_text(rect.position + Vector2(15.0, 49.0 + float(index) * 18.0), "— " + str(messages[index]), 10, INK_MUTED)


func _character_cover_rect() -> Rect2:
	return Rect2(12.0, size.y - 112.0, minf(346.0, size.x * 0.42), 100.0)
