class_name PrototypeV2MapLayer
extends Node2D
## One batched CanvasItem layer. It owns no per-map-object child nodes.

var layer_id: String = ""
var draw_callback: Callable
var redraw_count: int = 0
var size: Vector2 = Vector2.ZERO


func configure(next_layer_id: String, callback: Callable) -> void:
	layer_id = next_layer_id
	draw_callback = callback


func request_redraw() -> void:
	redraw_count += 1
	queue_redraw()


func _draw() -> void:
	if draw_callback.is_valid():
		draw_callback.call(self)
