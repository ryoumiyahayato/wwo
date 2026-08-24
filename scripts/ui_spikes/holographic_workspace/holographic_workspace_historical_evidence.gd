extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd"
## Source-backed 1900 political boundary and flag provider.
## Global political geometry never falls back to modern Natural Earth polygons.

const HISTORICAL_GEOMETRY_PATH := "res://data/world_map/historical/cshapes_1900_snapshot.json"
const HISTORICAL_UNITS_PATH := "res://data/world_map/historical/political_units_1900.json"
const HISTORICAL_FLAGS_PATH := "res://data/world_map/historical/flags_1900.json"
const HISTORICAL_SNAPSHOT_DATE := "1900-03-12"
const GLOBAL_SOURCE_NOTICE := "1900-03-12 · CShapes 2.0 历史政治边界 · 旗帜含来源与适用年代"
const LOWER_ADMIN_NOTICE := "政治边界为1900历史GIS；下级行政区仍为现代参考或待补数据。"
const ADMIN1_REFERENCE_NOTICE := "现代一级行政区参考层，不代表1900年逐点历史边界。"
const FLAG_REFERENCE_NOTICE := "旗面包含程序化识别码；用于空间导航，不等同于历史旗帜复原。"

const NATIONALITY_ENTITY_ALIASES := {
	"FRA": "country_fra",
	"DEU": "german_empire",
	"GBR": "british_isles_1900",
	"USA": "united_states_1900",
	"RUS": "russian_empire",
	"TUR": "ottoman_empire",
	"CHN": "qing_empire",
	"JPN": "empire_of_japan",
	"KOR": "korean_empire",
	"ITA": "kingdom_of_italy",
	"ESP": "kingdom_of_spain",
	"PRT": "kingdom_of_portugal",
	"BEL": "kingdom_of_belgium",
	"NLD": "kingdom_of_netherlands",
	"CHE": "swiss_confederation",
	"ROU": "kingdom_of_romania",
	"SRB": "kingdom_of_serbia",
	"MNE": "principality_of_montenegro",
	"BGR": "principality_of_bulgaria",
	"GRC": "kingdom_of_greece",
	"IRN": "persia_qajar",
	"AFG": "emirate_of_afghanistan",
	"THA": "kingdom_of_siam",
	"NPL": "kingdom_of_nepal",
	"BTN": "kingdom_of_bhutan",
	"ETH": "ethiopian_empire",
	"LBR": "republic_of_liberia",
	"MAR": "moroccan_sultanate",
	"MEX": "mexican_republic",
	"BRA": "brazil_1900",
	"ARG": "argentina_1900",
}

var _dated_geometry_document: Dictionary = {}
var _dated_units_document: Dictionary = {}
var _historical_flag_document: Dictionary = {}
var _historical_flag_records: Dictionary = {}
var _geometry_feature_by_id: Dictionary = {}
var _missing_flag_record_ids: Array[String] = []
var _historical_imported_flag_texture_by_id: Dictionary = {}


func _ready() -> void:
	_dated_geometry_document = _read_document(HISTORICAL_GEOMETRY_PATH)
	_dated_units_document = _read_document(HISTORICAL_UNITS_PATH)
	_historical_flag_document = _read_document(HISTORICAL_FLAGS_PATH)
	_historical_flag_records = _historical_flag_document.get("records", {}) as Dictionary
	_index_dated_geometry()
	super._ready()
	_validate_historical_evidence()


func _index_dated_geometry() -> void:
	_geometry_feature_by_id.clear()
	for feature_value: Variant in (_dated_geometry_document.get("features", []) as Array):
		if feature_value is Dictionary:
			var feature := feature_value as Dictionary
			_geometry_feature_by_id[str(feature.get("id", ""))] = feature


func _rebuild_historical_political_world() -> void:
	_history_modern_record_by_iso.clear()
	_history_modern_polygons_by_iso.clear()
	_history_modern_anchor_by_iso.clear()
	_history_explicit_mapped_isos.clear()
	_history_provisional_entity_ids.clear()
	_countries.clear()
	_country_by_id.clear()
	_country_unit_polygons.clear()
	_country_anchor_units.clear()
	_history_entity_by_id.clear()
	_history_territories_by_entity.clear()
	_flag_texture_by_entity.clear()
	_historical_imported_flag_texture_by_id.clear()

	for unit_value: Variant in (_dated_units_document.get("units", []) as Array):
		if unit_value is Dictionary:
			_build_dated_historical_unit(unit_value as Dictionary)
	_mark_projection_dirty()
	_history_focus_dirty = true


func _build_dated_historical_unit(unit: Dictionary) -> void:
	var entity_id := str(unit.get("id", ""))
	var feature_id := str(unit.get("geometry_feature_id", ""))
	var feature := _geometry_feature_by_id.get(feature_id, {}) as Dictionary
	if entity_id.is_empty() or feature.is_empty():
		return
	var polygons := _geometry_to_unit_polygons(feature.get("geometry", {}) as Dictionary)
	if polygons.is_empty():
		return
	var anchor := _historical_anchor(unit, polygons)
	var flag_id := str(unit.get("flag_id", "no_single_standard_flag"))
	var palette_key := "SOURCE_FLAG_" + flag_id.to_upper()
	_flag_palettes[palette_key] = {
		"pattern": "source_asset",
		"colors": PackedColorArray([Color(0.32, 0.38, 0.38, 1.0)]),
	}
	var record := {
		"id": entity_id,
		"iso_a3": palette_key,
		"name": str(unit.get("name_zh", unit.get("source_name", entity_id))),
		"name_zh": str(unit.get("name_zh", unit.get("source_name", entity_id))),
		"short_name_zh": str(unit.get("short_name_zh", unit.get("name_zh", entity_id))),
		"label_rank": int(unit.get("label_rank", 5)),
		"status": str(unit.get("status", "sovereign")),
		"sovereign_id": str(unit.get("sovereign_id", "")),
		"controller_id": str(unit.get("controller_id", "")),
		"source_historical_id": str(unit.get("source_historical_id", entity_id)),
		"detail_mode": "single",
		"provisional": false,
		"member_count": 1,
		"gwcode": int(unit.get("gwcode", -1)),
		"valid_from": str(unit.get("valid_from", "")),
		"valid_to": str(unit.get("valid_to", "")),
		"flag_id": flag_id,
		"flag_mode": str(unit.get("flag_mode", "")),
		"flag_absence_reason": str(unit.get("flag_absence_reason", "")),
		"data_quality": "dated_historical_gis",
	}
	var config := unit.duplicate(true)
	config["core_members"] = [_legacy_navigation_key(entity_id, int(unit.get("gwcode", -1)))]
	var territory_key := _legacy_navigation_key(entity_id, int(unit.get("gwcode", -1)))
	var territory := {
		"iso_a3": territory_key,
		"name": record["name_zh"],
		"polygons": polygons,
		"anchor": anchor,
		"data_quality": "dated_historical_gis",
		"geometry_feature_id": feature_id,
	}
	_countries.append(record)
	_country_by_id[entity_id] = record
	_country_unit_polygons[entity_id] = polygons
	_country_anchor_units[entity_id] = anchor
	_history_entity_by_id[entity_id] = config
	_history_territories_by_entity[entity_id] = [territory]


func _geometry_to_unit_polygons(geometry: Dictionary) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	var geometry_type := str(geometry.get("type", ""))
	var coordinates: Array = geometry.get("coordinates", []) as Array
	if geometry_type == "Polygon":
		_append_outer_ring(coordinates, result)
	elif geometry_type == "MultiPolygon":
		for polygon_value: Variant in coordinates:
			if polygon_value is Array:
				_append_outer_ring(polygon_value as Array, result)
	return result


func _append_outer_ring(raw_polygon: Array, output: Array[PackedVector3Array]) -> void:
	if raw_polygon.is_empty() or not raw_polygon[0] is Array:
		return
	var ring := raw_polygon[0] as Array
	var polygon := PackedVector3Array()
	for coordinate_value: Variant in ring:
		if coordinate_value is Array and (coordinate_value as Array).size() >= 2:
			var coordinate := coordinate_value as Array
			polygon.append(_lon_lat_unit(float(coordinate[0]), float(coordinate[1])))
	if polygon.size() > 3 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.00001:
		polygon.resize(polygon.size() - 1)
	if polygon.size() >= 3:
		output.append(polygon)


func _lon_lat_unit(longitude: float, latitude: float) -> Vector3:
	var lon := deg_to_rad(longitude)
	var lat := deg_to_rad(latitude)
	var latitude_radius := cos(lat)
	return Vector3(sin(lon) * latitude_radius, sin(lat), cos(lon) * latitude_radius).normalized()


func _historical_anchor(unit: Dictionary, polygons: Array[PackedVector3Array]) -> Vector3:
	var capital := unit.get("capital", {}) as Dictionary
	if not str(capital.get("name", "")).is_empty():
		return _lon_lat_unit(float(capital.get("lon", 0.0)), float(capital.get("lat", 0.0)))
	var total := Vector3.ZERO
	var count := 0
	for polygon: PackedVector3Array in polygons:
		for point: Vector3 in polygon:
			total += point
			count += 1
	return (total / float(maxi(1, count))).normalized()


func _legacy_navigation_key(entity_id: String, gwcode: int) -> String:
	match entity_id:
		"country_fra": return "FRA"
		"german_empire": return "DEU"
		"british_isles_1900": return "GBR"
		"united_states_1900": return "USA"
		"russian_empire": return "RUS"
		"ottoman_empire": return "TUR"
		"qing_empire": return "CHN"
		"empire_of_japan": return "JPN"
		"korean_empire": return "KOR"
		_: return "GW_%d" % gwcode


func _flag_texture_for_entity(entity_id: String, _palette: Dictionary) -> ImageTexture:
	if _flag_texture_by_entity.has(entity_id):
		return _flag_texture_by_entity.get(entity_id) as ImageTexture
	var entity := _country_by_id.get(entity_id, {}) as Dictionary
	var flag_id := str(entity.get("flag_id", "no_single_standard_flag"))
	var flag_record := _historical_flag_records.get(flag_id, {}) as Dictionary
	var image: Image
	if str(flag_record.get("render_mode", "")) == "source_asset":
		image = _load_imported_flag_image(
			str(flag_record.get("asset_path", "")), flag_id
		)
	else:
		image = _neutral_documented_absence_image()
	if image == null or image.is_empty():
		if flag_id not in _missing_flag_record_ids:
			_missing_flag_record_ids.append(flag_id)
		image = _neutral_documented_absence_image()
	image.resize(FLAG_TEXTURE_WIDTH, FLAG_TEXTURE_HEIGHT, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_flag_texture_by_entity[entity_id] = texture
	return texture


func _load_imported_flag_image(asset_path: String, flag_id: String) -> Image:
	if (
		asset_path.is_empty()
		or not asset_path.begins_with("res://")
		or not ResourceLoader.exists(asset_path, "Texture2D")
	):
		push_error(
			"Historical evidence: flag '%s' has no importable Texture2D at %s"
			% [flag_id, asset_path]
		)
		return Image.new()
	var resource := ResourceLoader.load(
		asset_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE
	)
	if not resource is Texture2D:
		push_error(
			"Historical evidence: flag '%s' did not load as Texture2D at %s"
			% [flag_id, asset_path]
		)
		return Image.new()
	var imported_image := (resource as Texture2D).get_image()
	if imported_image == null or imported_image.is_empty():
		push_error(
			"Historical evidence: flag '%s' produced an empty imported image at %s"
			% [flag_id, asset_path]
		)
		return Image.new()
	_historical_imported_flag_texture_by_id[flag_id] = resource
	return imported_image.duplicate()


func _neutral_documented_absence_image() -> Image:
	var image := Image.create(FLAG_TEXTURE_WIDTH, FLAG_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(FLAG_TEXTURE_HEIGHT):
		for x: int in range(FLAG_TEXTURE_WIDTH):
			var stripe := int(floor(float(x + y) / 10.0)) % 2
			var shade := 0.29 if stripe == 0 else 0.38
			image.set_pixel(x, y, Color(shade, shade + 0.025, shade + 0.02, 1.0))
	return image


func _home_historical_entity_id() -> String:
	var profile := _character_profiles.get(active_character_key, {}) as Dictionary
	var nationality_id := str(profile.get("nationality_id", FOCUS_COUNTRY_ID))
	if _history_entity_by_id.has(nationality_id):
		return nationality_id
	var alias := nationality_id.trim_prefix("country_").to_upper() if nationality_id.begins_with("country_") else nationality_id.to_upper()
	var entity_id := str(NATIONALITY_ENTITY_ALIASES.get(alias, ""))
	return entity_id if _history_entity_by_id.has(entity_id) else FOCUS_COUNTRY_ID


func _historical_geometry_notice(_territories: Array) -> String:
	return "辖区数量：1 · CShapes 2.0 于1900-03-12有效的历史政治边界"


func _distinctive_pattern_for_entity(
	entity_id: String, fallback: String
) -> String:
	return HistoricalMapIdentityStyle.encode_entity_pattern(
		entity_id,
		super._distinctive_pattern_for_entity(entity_id, fallback),
		_country_by_id,
		_history_entity_by_id
	)


func _distinctive_flag_color(
	pattern: String, colors: PackedColorArray, u: float, v: float
) -> Color:
	var identity: Dictionary = HistoricalMapIdentityStyle.decode_pattern(pattern)
	if identity.is_empty():
		return super._distinctive_flag_color(pattern, colors, u, v)
	var base: Color = super._distinctive_flag_color(
		str(identity.get("base_pattern", "")), colors, u, v
	)
	return HistoricalMapIdentityStyle.apply_identity_code(
		base,
		colors,
		int(identity.get("ordinal", 0)),
		u,
		v,
		Callable(self, "_contrast_color")
	)


func _draw_global_world() -> void:
	super._draw_global_world()
	_draw_label(
		Vector2(_hemisphere_rect.position.x + 14.0, _hemisphere_rect.position.y + 34.0),
		FLAG_REFERENCE_NOTICE,
		9,
		Color(0.74, 0.77, 0.68, 0.72)
	)
	_draw_label(
		Vector2(_hemisphere_rect.position.x + 14.0, _hemisphere_rect.position.y + 19.0),
		GLOBAL_SOURCE_NOTICE,
		9,
		Color(0.79, 0.81, 0.70, 0.80)
	)


func _draw_world_admin1_layer() -> void:
	super._draw_world_admin1_layer()
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	var records: Array = (
		_world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array
	)
	var status: String = "现代参考" if not records.is_empty() else "无下级历史数据"
	var badge := Rect2(rect.end.x - 270.0, rect.position.y + 18.0, 246.0, 24.0)
	_panel(
		badge,
		Color(0.12, 0.09, 0.04, 0.96),
		Color(0.80, 0.58, 0.25, 0.72)
	)
	_draw_label(
		badge.position + Vector2(10.0, 16.0),
		"数据等级：" + status,
		10,
		Color(0.96, 0.79, 0.46, 1.0)
	)
	_draw_label(rect.position + Vector2(24.0, 79.0), LOWER_ADMIN_NOTICE, 9, Color(0.96, 0.74, 0.43, 0.92))


func _draw_world_admin1_local_layer() -> void:
	super._draw_world_admin1_local_layer()
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	var badge := Rect2(rect.end.x - 390.0, rect.position.y + 17.0, 366.0, 25.0)
	_panel(
		badge,
		Color(0.14, 0.08, 0.04, 0.97),
		Color(0.84, 0.49, 0.24, 0.78)
	)
	_draw_label(
		badge.position + Vector2(10.0, 17.0),
		ADMIN1_REFERENCE_NOTICE,
		9,
		Color(0.98, 0.79, 0.53, 1.0)
	)


func historical_evidence_report() -> Dictionary:
	var unit_count := _history_entity_by_id.size()
	var geometry_count := _geometry_feature_by_id.size()
	var local_flags := 0
	var controller_flags := 0
	var documented_absence := 0
	var unresolved := 0
	for entity_value: Variant in _country_by_id.values():
		var entity := entity_value as Dictionary
		match str(entity.get("flag_mode", "")):
			"local_historical_flag": local_flags += 1
			"controller_identification_flag": controller_flags += 1
			"documented_absence": documented_absence += 1
			_: unresolved += 1
	return {
		"snapshot_date": str(_dated_geometry_document.get("snapshot_date", "")),
		"geometry_provider": str(_dated_geometry_document.get("provider", "")),
		"geometry_license": str((_dated_geometry_document.get("source", {}) as Dictionary).get("license", "")),
		"commercial_use_allowed": bool((_dated_geometry_document.get("source", {}) as Dictionary).get("commercial_use_allowed", true)),
		"unit_count": unit_count,
		"geometry_feature_count": geometry_count,
		"provisional_count": _history_provisional_entity_ids.size(),
		"modern_geometry_fallback": false,
		"local_flag_count": local_flags,
		"controller_flag_count": controller_flags,
		"documented_absence_count": documented_absence,
		"unresolved_flag_count": unresolved + _missing_flag_record_ids.size(),
		"flag_registry_record_count": int(_historical_flag_document.get("record_count", 0)),
	}


func flag_coverage_report() -> Dictionary:
	var report := historical_evidence_report()
	return {
		"explicit_count": int(report.get("unit_count", 0)),
		"generated_count": int(report.get("unit_count", 0)) - int(report.get("unresolved_flag_count", 0)),
		"local_historical_flags": int(report.get("local_flag_count", 0)),
		"controller_identification_flags": int(report.get("controller_flag_count", 0)),
		"documented_absence": int(report.get("documented_absence_count", 0)),
		"unresolved_count": int(report.get("unresolved_flag_count", 0)),
	}


func navigation_coverage_report() -> Dictionary:
	var modern_reference := 0
	var terminal := 0
	for territory_values: Variant in _history_territories_by_entity.values():
		var territory := (territory_values as Array)[0] as Dictionary
		var key := str(territory.get("iso_a3", ""))
		if not (_world_admin1_by_iso.get(key, []) as Array).is_empty():
			modern_reference += 1
		else:
			terminal += 1
	return {
		"total_territories": _history_territories_by_entity.size(),
		"dated_historical_boundaries": _history_territories_by_entity.size(),
		"curated_navigation": 1 if _history_entity_by_id.has(FOCUS_COUNTRY_ID) else 0,
		"modern_reference": modern_reference,
		"country_terminal": terminal,
		"political_boundaries_historical": true,
		"global_admin1_historical": false,
		"fully_historical": false,
	}


func _validate_historical_evidence() -> void:
	if str(_dated_geometry_document.get("snapshot_date", "")) != HISTORICAL_SNAPSHOT_DATE:
		push_error("Historical evidence: unexpected snapshot date")
	if _history_entity_by_id.size() != 151:
		push_error("Historical evidence: expected 151 political units, found %d" % _history_entity_by_id.size())
	var report := historical_evidence_report()
	if int(report.get("unresolved_flag_count", 0)) != 0:
		push_error("Historical evidence: unresolved flag records remain")
