class_name WorldMapCanvas
extends "res://scripts/world_map/internal/world_map_canvas_impl.gd"
## Formal world-map canvas surface. Rendering remains batched and LOD-driven.


func focus_player_location() -> void:
	var focus_location_id: String = ""
	var observer_id: String = str(
		_v2_3_local_overlay.get("observer_id", "")
	)
	for raw_position: Variant in (
		_v2_3_local_overlay.get("person_positions", []) as Array
	):
		if not raw_position is Dictionary:
			continue
		var position: Dictionary = raw_position as Dictionary
		if str(position.get("person_id", "")) != observer_id:
			continue
		focus_location_id = str(
			position.get(
				"current_location_id",
				position.get("travel_destination_id", "")
			)
		)
		break
	var focus_point: Vector2 = _camera_focus_point("lille")
	if _v2_3_local_location_points.has(focus_location_id):
		focus_point = _v2_3_local_location_points[focus_location_id] as Vector2
		camera_focus_id = focus_location_id
	else:
		camera_focus_id = PLAYER_CITY_ID
	var configured_focus: float = float(
		(_modes.get("zoom", {}) as Dictionary).get(
			"player_location_focus", 180.0
		)
	)
	_set_view(
		focus_point,
		minf(get_maximum_zoom(), configured_focus),
		_map_anchor()
	)
