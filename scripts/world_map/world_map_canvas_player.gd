class_name WorldMapCanvasPlayer
extends "res://scripts/world_map/world_map_canvas_detail.gd"
## Foreign cities currently have regional-centre records but not detailed local
## children. City scope therefore anchors to the actual centre instead of going
## blank; future neighbourhood records can use that centre ID as their parent.


func _update_current_city_parent() -> void:
	var location: Dictionary = _v2_3_local_location_lookup.get(
		_observer_location_id(), {}
	) as Dictionary
	if location.is_empty():
		return
	var location_id: String = str(location.get("location_id", ""))
	var location_type: String = str(location.get("location_type", ""))
	if location_type == "regional_centre" and not location_id.is_empty():
		_current_city_parent_id = location_id
		return
	var parent_id: String = str(location.get("parent_region_id", ""))
	if not parent_id.is_empty():
		_current_city_parent_id = parent_id


func _location_visible_in_scope(location: Dictionary, scope: String) -> bool:
	if scope != MAP_SCOPE_CITY:
		return super._location_visible_in_scope(location, scope)
	if location.is_empty():
		return false
	var location_id: String = str(location.get("location_id", ""))
	var parent_id: String = str(location.get("parent_region_id", ""))
	if _current_city_parent_id.begins_with("location_"):
		return (
			location_id == _current_city_parent_id
			or parent_id == _current_city_parent_id
		)
	return parent_id == _current_city_parent_id and str(
		location.get("location_type", "")
	) != "regional_centre"


func _city_anchor_for_parent(parent_id: String) -> Vector2:
	var exact: Dictionary = _v2_3_local_location_lookup.get(parent_id, {}) as Dictionary
	if not exact.is_empty():
		return project_lon_lat(exact.get("world_position", []))
	return super._city_anchor_for_parent(parent_id)
