class_name PrototypeV2Data
extends RefCounted
## Internal loader for the accepted world-map dataset used by the current V2.2 scene.
## The legacy class name is retained only as an implementation compatibility ID.

const FILES: Dictionary = {
	"world_coastlines": "res://data/world_map/world_coastlines.json",
	"countries": "res://data/world_map/countries.json",
	"regions": "res://data/world_map/regions.json",
	"cities": "res://data/world_map/cities.json",
	"ports": "res://data/world_map/ports.json",
	"rail_segments": "res://data/world_map/rail_segments.json",
	"road_segments": "res://data/world_map/road_segments.json",
	"shipping_routes": "res://data/world_map/shipping_routes.json",
	"characters": "res://data/world_map/characters.json",
	"name_pool_fr": "res://data/world_map/name_pool_fr.json",
	"relationships": "res://data/world_map/relationships.json",
	"organizations": "res://data/world_map/organizations.json",
	"institutions": "res://data/world_map/institutions.json",
	"activity": "res://data/world_map/world_activity.json",
	"map_modes": "res://data/world_map/map_modes.json",
	"map_geometry_cache": "res://data/world_map/map_geometry_cache.json",
}

var records: Dictionary = {}
var errors: Array[String] = []


func load_all() -> bool:
	records.clear()
	errors.clear()
	for key_variant: Variant in FILES.keys():
		var key: String = str(key_variant)
		var path: String = str(FILES[key])
		var document: Dictionary = _load_document(path)
		if not document.is_empty():
			records[key] = document
	return errors.is_empty() and records.size() == FILES.size()


func get_document(key: String) -> Dictionary:
	var value: Variant = records.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("缺少世界地图数据：%s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取世界地图数据：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("世界地图数据不是 JSON 对象：%s" % path)
		return {}
	return parsed as Dictionary
