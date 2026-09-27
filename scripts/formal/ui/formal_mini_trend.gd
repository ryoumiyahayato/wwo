class_name FormalMiniTrend
extends Control
## Lightweight presentation-only sparkline. The caller supplies an immutable
## timestamp/value series; this control never queries or owns Economy state.

var _points: PackedVector2Array = PackedVector2Array()
var _line_color: Color = Color(0.48, 0.86, 0.67, 1.0)
var _zero_baseline: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_series(
	rows: Array,
	timestamp_key: String,
	value_key: String,
	line_color: Color,
	zero_baseline: bool = false
) -> void:
	var next_points := PackedVector2Array()
	for value: Variant in rows:
		if not value is Dictionary:
			continue
		var row := value as Dictionary
		next_points.append(Vector2(
			float(row.get(timestamp_key, next_points.size())),
			float(row.get(value_key, 0.0))
		))
	_points = next_points
	_line_color = line_color
	_zero_baseline = zero_baseline
	queue_redraw()


func point_count() -> int:
	return _points.size()


func _draw() -> void:
	if _points.size() < 2 or size.x <= 4.0 or size.y <= 4.0:
		return
	var minimum_x := _points[0].x
	var maximum_x := _points[0].x
	var minimum_y := 0.0 if _zero_baseline else _points[0].y
	var maximum_y := _points[0].y
	for point: Vector2 in _points:
		minimum_x = minf(minimum_x, point.x)
		maximum_x = maxf(maximum_x, point.x)
		minimum_y = minf(minimum_y, point.y)
		maximum_y = maxf(maximum_y, point.y)
	var span_x := maxf(1.0, maximum_x - minimum_x)
	var span_y := maxf(0.0001, maximum_y - minimum_y)
	var plot := Rect2(2.0, 2.0, size.x - 4.0, size.y - 4.0)
	var screen_points := PackedVector2Array()
	for point: Vector2 in _points:
		screen_points.append(Vector2(
			plot.position.x + (point.x - minimum_x) / span_x * plot.size.x,
			plot.end.y - (point.y - minimum_y) / span_y * plot.size.y
		))
	draw_line(
		Vector2(plot.position.x, plot.end.y),
		plot.end,
		Color(_line_color.r, _line_color.g, _line_color.b, 0.16),
		1.0
	)
	draw_polyline(screen_points, _line_color, 2.0, true)
	draw_circle(screen_points[screen_points.size() - 1], 2.8, _line_color)
