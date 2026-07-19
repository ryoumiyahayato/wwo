class_name WorldMapCanvas
extends "res://scripts/world_map/internal/world_map_canvas_impl.gd"
## Formal world-map canvas surface. Rendering remains batched and LOD-driven.


func focus_player_location() -> void:
	camera_focus_id = PLAYER_CITY_ID
	var configured_focus: float = float(
		(_modes.get("zoom", {}) as Dictionary).get(
			"player_location_focus", 180.0
		)
	)
	_set_view(
		_camera_focus_point("lille"),
		minf(get_maximum_zoom(), configured_focus),
		_map_anchor()
	)
