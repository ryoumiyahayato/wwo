class_name UIDrawing
extends RefCounted
## Shared drawing primitives; no world data or input state.

static func create_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "Microsoft JhengHei", "SimSun"])
	return font

static func panel(canvas: CanvasItem, rect: Rect2, fill: Color, border: Color) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(rect, border, false, 1.0)

static func label(canvas: CanvasItem, font: Font, point: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0), width: float = -1.0) -> void:
	canvas.draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)
