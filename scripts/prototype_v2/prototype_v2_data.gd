class_name PrototypeV2Data
extends RefCounted
## Loads only the isolated static prototype fixtures. It never touches formal data loaders.

const FILES: Dictionary = {
	"world_coastlines": "res://data/prototype_v2/prototype_world_coastlines.json",
	"countries": "res://data/prototype_v2/prototype_countries.json",
	"regions": "res://data/prototype_v2/prototype_regions.json",
	"cities": "res://data/prototype_v2/prototype_cities.json",
	"ports": "res://data/prototype_v2/prototype_ports.json",
	"rail_segments": "res://data/prototype_v2/prototype_rail_segments.json",
	"road_segments": "res://data/prototype_v2/prototype_road_segments.json",
	"shipping_routes": "res://data/prototype_v2/prototype_shipping_routes.json",
	"characters": "res://data/prototype_v2/prototype_characters.json",
	"name_pool_fr": "res://data/prototype_v2/prototype_name_pool_fr.json",
	"relationships": "res://data/prototype_v2/prototype_relationships.json",
	"organizations": "res://data/prototype_v2/prototype_organizations.json",
	"institutions": "res://data/prototype_v2/prototype_institutions.json",
	"activity": "res://data/prototype_v2/prototype_world_activity.json",
	"map_modes": "res://data/prototype_v2/prototype_map_modes.json",
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
		errors.append("缺少原型静态数据：%s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取原型静态数据：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("原型静态数据不是 JSON 对象：%s" % path)
		return {}
	var document: Dictionary = parsed as Dictionary
	if document.get("prototype_only", false) != true:
		errors.append("原型静态数据缺少 prototype_only：%s" % path)
		return {}
	return document
