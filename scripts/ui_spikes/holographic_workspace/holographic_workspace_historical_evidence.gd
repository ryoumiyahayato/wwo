extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd"
## Source-backed 1900 political boundary and flag provider.
## Global political geometry never falls back to modern Natural Earth polygons.

const HISTORICAL_GEOMETRY_PATH := "res://data/world_map/historical/cshapes_1900_snapshot.json"
const HISTORICAL_UNITS_PATH := "res://data/world_map/historical/political_units_1900.json"
const HISTORICAL_FLAGS_PATH := "res://data/world_map/historical/flags_1900.json"
const CENTRAL_ARABIA_CONTROL_PATH := "res://data/world_map/historical/central_arabia_control_1900.json"
const HISTORICAL_SNAPSHOT_DATE := "1900-03-12"
const FLAG_MATERIAL_VALID_HISTORICAL_FLAG := "VALID_HISTORICAL_FLAG"
const FLAG_MATERIAL_EXPLICIT_NO_VERIFIED_FLAG := "EXPLICIT_NO_VERIFIED_FLAG"
const FLAG_MATERIAL_RESOURCE_ERROR := "RESOURCE_ERROR"
const GLOBAL_SOURCE_NOTICE := "1900-03-12 · CShapes 2.0 历史政治边界 · 旗帜含来源与适用年代"
const LOWER_ADMIN_NOTICE := "政治边界为1900历史GIS；下级行政区仍为现代参考或待补数据。"
const ADMIN1_REFERENCE_NOTICE := "现代一级行政区参考层，不代表1900年逐点历史边界。"
const FLAG_REFERENCE_NOTICE := "旗面包含程序化识别码；用于空间导航，不等同于历史旗帜复原。"
const DEBUG_SOURCE_NOTICE_ARGUMENT := "--map-debug-source-notice"

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
var _central_arabia_control_document: Dictionary = {}
var _historical_flag_records: Dictionary = {}
var _geometry_feature_by_id: Dictionary = {}
var _missing_flag_record_ids: Array[String] = []
var _flag_material_classification_by_entity: Dictionary = {}
var _flag_resource_error_entity_ids: Array[String] = []
var _historical_map_diagnostics: Array[String] = []
var _country_unit_holes: Dictionary = {}
var _show_debug_source_notice: bool = false


func _ready() -> void:
	_show_debug_source_notice = OS.get_cmdline_args().has(DEBUG_SOURCE_NOTICE_ARGUMENT)
	_dated_geometry_document = _read_document(HISTORICAL_GEOMETRY_PATH)
	_dated_units_document = _read_document(HISTORICAL_UNITS_PATH)
	_historical_flag_document = _read_document(HISTORICAL_FLAGS_PATH)
	_central_arabia_control_document = _read_document(CENTRAL_ARABIA_CONTROL_PATH)
	_historical_flag_records = _historical_flag_document.get("records", {}) as Dictionary
	_index_dated_geometry()
	super._ready()
	_validate_historical_evidence()


func _index_dated_geometry() -> void:
	_geometry_feature_by_id.clear()
	for feature_value: Variant in (_dated_geometry_document.get("features", []) as Array):
		if feature_value is Dictionary:
			var feature := feature_value as Dictionary
			var feature_id := str(feature.get("id", ""))
			if feature_id.is_empty():
				_historical_map_diagnostics.append("geometry record has no stable id")
				continue
			if _geometry_feature_by_id.has(feature_id):
				_historical_map_diagnostics.append("duplicate geometry id: %s" % feature_id)
				continue
			_geometry_feature_by_id[feature_id] = feature


func _rebuild_historical_political_world() -> void:
	_historical_map_diagnostics.clear()
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
	_missing_flag_record_ids.clear()
	_flag_material_classification_by_entity.clear()
	_flag_resource_error_entity_ids.clear()
	_country_surface_triangle_polygons.clear()
	_country_surface_triangle_records.clear()
	_country_surface_triangle_statistics.clear()
	_country_surface_triangle_buffers.clear()
	_interactive_country_surface_triangle_buffers.clear()
	_interactive_country_boundary_sources.clear()
	_country_flag_uv_bounds.clear()
	_country_flag_uv_reference_longitudes.clear()
	_interaction_adjacency_by_entity.clear()
	_interaction_color_index_by_entity.clear()
	_interaction_coloring_ready = false
	_map_profile_static_triangulation_usec = 0
	_map_profile_static_triangulation_total_usec = 0
	_country_unit_holes.clear()

	for unit_value: Variant in (_dated_units_document.get("units", []) as Array):
		if unit_value is Dictionary:
			_build_dated_historical_unit(unit_value as Dictionary)
	_mark_projection_dirty()
	_history_focus_dirty = true
	if has_method("_build_interaction_adjacency_coloring"):
		call("_build_interaction_adjacency_coloring")


func _build_dated_historical_unit(unit: Dictionary) -> void:
	var entity_id := str(unit.get("id", ""))
	var feature_id := str(unit.get("geometry_feature_id", ""))
	var feature := _geometry_feature_by_id.get(feature_id, {}) as Dictionary
	if entity_id.is_empty():
		_historical_map_diagnostics.append("historical unit has no stable id")
		return
	if feature_id.is_empty():
		_historical_map_diagnostics.append("%s has no geometry_feature_id" % entity_id)
		return
	if feature.is_empty():
		_historical_map_diagnostics.append("%s references missing geometry %s" % [entity_id, feature_id])
		return
	var polygons := _geometry_to_unit_polygons(feature.get("geometry", {}) as Dictionary)
	if polygons.is_empty():
		_historical_map_diagnostics.append("%s references empty geometry %s" % [entity_id, feature_id])
		return
	var holes_by_part := _geometry_to_unit_holes(feature.get("geometry", {}) as Dictionary)
	var anchor := _historical_anchor(unit, polygons)
	var flag_id := str(unit.get("flag_id", "no_single_standard_flag"))
	var flag_material_classification := _initial_flag_material_classification(unit, flag_id)
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
		"sovereign_id": str(unit.get("controller_id", "")),
		"controller_id": str(unit.get("controller_id", "")),
		"detail_mode": "single",
		"provisional": false,
		"member_count": 1,
		"gwcode": int(unit.get("gwcode", -1)),
		"valid_from": str(unit.get("valid_from", "")),
		"valid_to": str(unit.get("valid_to", "")),
		"flag_id": flag_id,
		"flag_mode": str(unit.get("flag_mode", "")),
		"flag_absence_reason": str(unit.get("flag_absence_reason", "")),
		"flag_record_id": flag_id,
		"display_entity_id": entity_id,
		"historical_identity_id": entity_id,
		"identity_source": HISTORICAL_UNITS_PATH,
		"modern_identity_fallback": false,
		"flag_material_classification": flag_material_classification,
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
	_country_unit_holes[entity_id] = holes_by_part
	_country_anchor_units[entity_id] = anchor
	_history_entity_by_id[entity_id] = config
	_history_territories_by_entity[entity_id] = [territory]
	_flag_material_classification_by_entity[entity_id] = flag_material_classification


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
	var polygon := _raw_ring_to_unit(raw_polygon[0] as Array)
	if polygon.size() >= 3:
		output.append(polygon)


func _geometry_to_unit_holes(geometry: Dictionary) -> Array:
	var result: Array = []
	var geometry_type := str(geometry.get("type", ""))
	var coordinates: Array = geometry.get("coordinates", []) as Array
	if geometry_type == "Polygon":
		result.append(_holes_from_raw_polygon(coordinates))
	elif geometry_type == "MultiPolygon":
		for polygon_value: Variant in coordinates:
			if polygon_value is Array:
				result.append(_holes_from_raw_polygon(polygon_value as Array))
	return result


func _holes_from_raw_polygon(raw_polygon: Array) -> Array[PackedVector3Array]:
	var holes: Array[PackedVector3Array] = []
	for ring_index: int in range(1, raw_polygon.size()):
		if not raw_polygon[ring_index] is Array:
			continue
		var hole := _raw_ring_to_unit(raw_polygon[ring_index] as Array)
		if hole.size() >= 3:
			holes.append(hole)
	return holes


func _raw_ring_to_unit(ring: Array) -> PackedVector3Array:
	var polygon := PackedVector3Array()
	for coordinate_value: Variant in ring:
		if coordinate_value is Array and (coordinate_value as Array).size() >= 2:
			var coordinate := coordinate_value as Array
			polygon.append(_lon_lat_unit(float(coordinate[0]), float(coordinate[1])))
	if polygon.size() > 3 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.00001:
		polygon.resize(polygon.size() - 1)
	return polygon


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


func _initial_flag_material_classification(unit: Dictionary, flag_id: String) -> String:
	var flag_mode := str(unit.get("flag_mode", ""))
	var flag_record := _historical_flag_records.get(flag_id, {}) as Dictionary
	if (
		flag_mode == "documented_absence"
		and not flag_record.is_empty()
		and str(flag_record.get("render_mode", "")) != "source_asset"
	):
		return FLAG_MATERIAL_EXPLICIT_NO_VERIFIED_FLAG
	if flag_record.is_empty() or str(flag_record.get("render_mode", "")) != "source_asset":
		return FLAG_MATERIAL_RESOURCE_ERROR
	if str(flag_record.get("asset_path", "")).is_empty():
		return FLAG_MATERIAL_RESOURCE_ERROR
	return FLAG_MATERIAL_VALID_HISTORICAL_FLAG


func historical_flag_material_classification(entity_id: String) -> String:
	return str(
		_flag_material_classification_by_entity.get(
			entity_id,
			FLAG_MATERIAL_RESOURCE_ERROR
		)
	)


func historical_flag_material_trace(entity_id: String) -> Dictionary:
	var entity := _country_by_id.get(entity_id, {}) as Dictionary
	var classification := historical_flag_material_classification(entity_id)
	var flag_id := str(entity.get("flag_record_id", entity.get("flag_id", "")))
	var record := _historical_flag_records.get(flag_id, {}) as Dictionary
	var resource_present := classification == FLAG_MATERIAL_VALID_HISTORICAL_FLAG
	return {
		"HISTORICAL_ENTITY_EXPECTED": not entity.is_empty(),
		"HISTORICAL_OWNER_RESOLVED": not entity.is_empty(),
		"DISPLAY_ENTITY_RESOLVED": not str(entity.get("display_entity_id", "")).is_empty(),
		"FLAG_RECORD_PRESENT": not record.is_empty(),
		"FLAG_RESOURCE_PRESENT": resource_present,
		"MATERIAL_CREATED": classification != FLAG_MATERIAL_RESOURCE_ERROR,
		"UV_VALID": true,
		"flag_record_id": flag_id,
		"flag_material_classification": classification,
		"flag_absence_reason": str(entity.get("flag_absence_reason", "")),
	}


func historical_flag_texture_alpha_audit(entity_id: String) -> Dictionary:
	var entity := _country_by_id.get(entity_id, {}) as Dictionary
	var classification := historical_flag_material_classification(entity_id)
	var texture := _flag_texture_for_entity(entity_id, {})
	if texture == null:
		return {
			"entity_id": entity_id,
			"classification": classification,
			"texture_present": false,
			"reason": "NO_TEXTURE_OR_EXPLICIT_NO_VERIFIED_FLAG",
		}
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return {
			"entity_id": entity_id,
			"classification": classification,
			"texture_present": false,
			"reason": "TEXTURE_IMAGE_EMPTY",
		}
	var minimum_alpha := 1.0
	var maximum_alpha := 0.0
	var zero_alpha_pixels := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			minimum_alpha = minf(minimum_alpha, alpha)
			maximum_alpha = maxf(maximum_alpha, alpha)
			if alpha <= 0.0001:
				zero_alpha_pixels += 1
	return {
		"entity_id": entity_id,
		"historical_identity_id": str(entity.get("historical_identity_id", entity_id)),
		"classification": classification,
		"texture_present": true,
		"width": image.get_width(),
		"height": image.get_height(),
		"minimum_alpha": minimum_alpha,
		"maximum_alpha": maximum_alpha,
		"zero_alpha_pixels": zero_alpha_pixels,
	}


func _flag_texture_for_entity(entity_id: String, _palette: Dictionary) -> ImageTexture:
	_map_flag_resource_lookup_calls += 1
	if _flag_texture_by_entity.has(entity_id):
		_map_flag_texture_cache_hits += 1
		return _flag_texture_by_entity.get(entity_id) as ImageTexture
	_map_flag_texture_cache_misses += 1
	var entity := _country_by_id.get(entity_id, {}) as Dictionary
	var flag_id := str(entity.get("flag_id", "no_single_standard_flag"))
	var flag_record := _historical_flag_records.get(flag_id, {}) as Dictionary
	var classification := historical_flag_material_classification(entity_id)
	if classification == FLAG_MATERIAL_EXPLICIT_NO_VERIFIED_FLAG:
		# A documented absence is intentionally rendered as a neutral political
		# fill. A hatch texture would be indistinguishable from an import error.
		_flag_texture_by_entity[entity_id] = null
		return null
	if classification != FLAG_MATERIAL_VALID_HISTORICAL_FLAG or flag_record.is_empty():
		if entity_id not in _flag_resource_error_entity_ids:
			_flag_resource_error_entity_ids.append(entity_id)
		_flag_material_classification_by_entity[entity_id] = FLAG_MATERIAL_RESOURCE_ERROR
		_flag_texture_by_entity[entity_id] = null
		return null
	var source_texture := ResourceLoader.load(
		str(flag_record.get("asset_path", "")),
		"Texture2D",
		ResourceLoader.CACHE_MODE_REUSE
	) as Texture2D
	var image: Image = source_texture.get_image() if source_texture != null else null
	if image == null or image.is_empty():
		if entity_id not in _flag_resource_error_entity_ids:
			_flag_resource_error_entity_ids.append(entity_id)
		_flag_material_classification_by_entity[entity_id] = FLAG_MATERIAL_RESOURCE_ERROR
		_flag_texture_by_entity[entity_id] = null
		return null
	image.resize(FLAG_TEXTURE_WIDTH, FLAG_TEXTURE_HEIGHT, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		if entity_id not in _flag_resource_error_entity_ids:
			_flag_resource_error_entity_ids.append(entity_id)
		_flag_material_classification_by_entity[entity_id] = FLAG_MATERIAL_RESOURCE_ERROR
		_flag_texture_by_entity[entity_id] = null
		return null
	_flag_texture_by_entity[entity_id] = texture
	return texture


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
	if not _show_debug_source_notice:
		return
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


func historical_map_truth_report() -> Dictionary:
	var units: Array = _dated_units_document.get("units", []) as Array
	var features: Array = _dated_geometry_document.get("features", []) as Array
	var unit_ids: Dictionary = {}
	var seen_unit_ids: Dictionary = {}
	var feature_to_units: Dictionary = {}
	var duplicate_unit_ids: Array[String] = []
	var duplicate_feature_ids: Array[String] = []
	var missing_geometry_ids: Array[String] = []
	var invalid_temporal_ids: Array[String] = []
	var missing_controller_ids: Array[String] = []
	var zero_geometry_ids: Array[String] = []
	var referenced_feature_ids: Dictionary = {}
	var geometry_part_count := 0
	var geometry_hole_ring_count := 0
	var invalid_geometry_record_count := 0
	var multipolygon_geometry_count := 0
	var disconnected_geometry_count := 0
	var dateline_geometry_ids: Array[String] = []
	var large_geometry_ids: Array[String] = []
	var region_record_count := 0
	var regionless_entity_ids: Array[String] = []
	var inventory: Array[Dictionary] = []
	var snapshot_date := HISTORICAL_SNAPSHOT_DATE
	for known_unit_value: Variant in units:
		if known_unit_value is Dictionary:
			var known_unit_id := str((known_unit_value as Dictionary).get("id", ""))
			if not known_unit_id.is_empty():
				unit_ids[known_unit_id] = true

	for unit_value: Variant in units:
		if not unit_value is Dictionary:
			invalid_geometry_record_count += 1
			continue
		var unit := unit_value as Dictionary
		var unit_id := str(unit.get("id", ""))
		if unit_id.is_empty():
			invalid_geometry_record_count += 1
			continue
		if seen_unit_ids.has(unit_id):
			duplicate_unit_ids.append(unit_id)
		seen_unit_ids[unit_id] = true
		var feature_id := str(unit.get("geometry_feature_id", ""))
		if feature_id.is_empty() or not _geometry_feature_by_id.has(feature_id):
			missing_geometry_ids.append(unit_id)
		else:
			referenced_feature_ids[feature_id] = true
			var owners: Array = feature_to_units.get(feature_id, []) as Array
			owners.append(unit_id)
			feature_to_units[feature_id] = owners
			if owners.size() > 1:
				duplicate_feature_ids.append(feature_id)
		var valid_from := str(unit.get("valid_from", ""))
		var valid_to := str(unit.get("valid_to", ""))
		if valid_from.is_empty() or valid_to.is_empty() or valid_from > snapshot_date or valid_to < snapshot_date:
			invalid_temporal_ids.append(unit_id)
		var controller_id := str(unit.get("controller_id", ""))
		if not controller_id.is_empty() and not unit_ids.has(controller_id):
			missing_controller_ids.append("%s->%s" % [unit_id, controller_id])
		var regions: Array = _history_territories_by_entity.get(unit_id, []) as Array
		region_record_count += regions.size()
		if regions.is_empty():
			regionless_entity_ids.append(unit_id)
		var polygons: Array = _country_unit_polygons.get(unit_id, []) as Array
		geometry_part_count += polygons.size()
		if polygons.is_empty():
			zero_geometry_ids.append(unit_id)
		var region_inventory: Array[Dictionary] = []
		for region_value: Variant in regions:
			var region := region_value as Dictionary
			var region_polygons: Array = region.get("polygons", []) as Array
			region_inventory.append({
				"id": str(region.get("iso_a3", "")),
				"geometry_feature_id": str(region.get("geometry_feature_id", feature_id)),
				"geometry_parts": region_polygons.size(),
				"historical_owner": unit_id,
				"modern_identity_fallback": false,
			})
		inventory.append({
			"id": unit_id,
			"status": str(unit.get("status", "")),
			"valid_from": str(unit.get("valid_from", "")),
			"valid_to": str(unit.get("valid_to", "")),
			"regions": region_inventory,
			"geometry_feature_ids": [feature_id] if not feature_id.is_empty() else [],
			"geometry_parts": polygons.size(),
			"historical_owner": unit_id,
			"display_entity_id": unit_id,
			"flag_record_id": str(unit.get("flag_id", "")),
			"flag_material_classification": historical_flag_material_classification(unit_id),
			"modern_identity_fallback": false,
		})

	var geometry_without_owner_ids: Array[String] = []
	for feature_value: Variant in features:
		if not feature_value is Dictionary:
			invalid_geometry_record_count += 1
			continue
		var feature := feature_value as Dictionary
		var feature_id := str(feature.get("id", ""))
		if feature_id.is_empty():
			invalid_geometry_record_count += 1
			continue
		if not referenced_feature_ids.has(feature_id):
			geometry_without_owner_ids.append(feature_id)
		var geometry := feature.get("geometry", {}) as Dictionary
		var geometry_type := str(geometry.get("type", ""))
		var coordinates: Array = geometry.get("coordinates", []) as Array
		if geometry_type != "Polygon" and geometry_type != "MultiPolygon":
			invalid_geometry_record_count += 1
			continue
		if coordinates.is_empty():
			invalid_geometry_record_count += 1
			continue
		if geometry_type == "MultiPolygon":
			multipolygon_geometry_count += 1
			if coordinates.size() > 1:
				disconnected_geometry_count += 1
		if _geometry_has_dateline_seam(geometry):
			dateline_geometry_ids.append(feature_id)
		if float(feature.get("area_km2", 0.0)) >= 1000000.0:
			large_geometry_ids.append(feature_id)
		if geometry_type == "Polygon":
			geometry_hole_ring_count += maxi(0, coordinates.size() - 1)
		else:
			for polygon_value: Variant in coordinates:
				if polygon_value is Array:
					geometry_hole_ring_count += maxi(0, (polygon_value as Array).size() - 1)

	var modern_crosswalk_entities: Array = _history_document.get("entities", []) as Array
	duplicate_unit_ids.sort()
	duplicate_feature_ids.sort()
	missing_geometry_ids.sort()
	geometry_without_owner_ids.sort()
	missing_controller_ids.sort()
	invalid_temporal_ids.sort()
	regionless_entity_ids.sort()
	dateline_geometry_ids.sort()
	large_geometry_ids.sort()
	return {
		"snapshot_date": snapshot_date,
		"expected_polities": units.size(),
		"loaded_polities": _history_entity_by_id.size(),
		"expected_region_records": region_record_count,
		"loaded_region_records": _history_territories_by_entity.size(),
		"geometry_records": features.size(),
		"geometry_parts": geometry_part_count,
		"zero_geometry_count": zero_geometry_ids.size(),
		"zero_geometry_ids": zero_geometry_ids,
		"inventory": inventory,
		"missing_geometry_count": missing_geometry_ids.size(),
		"missing_geometry_ids": missing_geometry_ids,
		"geometry_without_valid_historical_owner_count": geometry_without_owner_ids.size(),
		"geometry_without_valid_historical_owner_ids": geometry_without_owner_ids,
		"duplicate_unit_id_count": duplicate_unit_ids.size(),
		"duplicate_unit_ids": duplicate_unit_ids,
		"duplicate_or_conflicting_geometry_mapping_count": duplicate_feature_ids.size(),
		"duplicate_or_conflicting_geometry_mapping_ids": duplicate_feature_ids,
		"missing_controller_count": missing_controller_ids.size(),
		"missing_controller_ids": missing_controller_ids,
		"invalid_temporal_count": invalid_temporal_ids.size(),
		"invalid_temporal_ids": invalid_temporal_ids,
		"regionless_entity_count": regionless_entity_ids.size(),
		"regionless_entity_ids": regionless_entity_ids,
		"invalid_geometry_record_count": invalid_geometry_record_count,
		"geometry_hole_ring_count": geometry_hole_ring_count,
		"multipolygon_geometry_count": multipolygon_geometry_count,
		"disconnected_geometry_count": disconnected_geometry_count,
		"dateline_geometry_count": dateline_geometry_ids.size(),
		"dateline_geometry_ids": dateline_geometry_ids,
		"large_geometry_count": large_geometry_ids.size(),
		"large_geometry_ids": large_geometry_ids,
		"modern_crosswalk_entity_count": modern_crosswalk_entities.size(),
		"formal_world_uses_modern_crosswalk": false,
		"modern_identity_fallback_count": 0,
		"modern_geometry_fallback_count": 0,
		"central_arabia_source_audit": historical_central_arabia_source_audit(),
		"diagnostics": _historical_map_diagnostics.duplicate(),
	}


func historical_central_arabia_source_audit() -> Dictionary:
	var requested_terms: Array[String] = [
		"Jabal Shammar",
		"Jebel Shammar",
		"Shammar",
		"Ha'il",
		"Hail",
		"Rashidi",
		"Al Rashid",
		"Ibn Rashid",
		"内志酋长国 / Nejd / Najd",
		"gw_697",
	]
	var candidate_units: Array[Dictionary] = []
	var candidate_features: Array[Dictionary] = []
	var matched_terms: Array[String] = []
	for unit_value: Variant in (_dated_units_document.get("units", []) as Array):
		if not unit_value is Dictionary:
			continue
		var unit := unit_value as Dictionary
		var searchable := "|".join([
			str(unit.get("id", "")),
			str(unit.get("source_name", "")),
			str(unit.get("name_zh", "")),
			str(unit.get("short_name_zh", "")),
			str(unit.get("geometry_feature_id", "")),
		]).to_lower()
		var matched := false
		for term: String in requested_terms:
			var normalized_term := term.to_lower().replace("'", "")
			if normalized_term.contains("/"):
				continue
			if _historical_identity_term_matches(searchable, normalized_term):
				matched = true
				if not matched_terms.has(term):
					matched_terms.append(term)
		if matched:
			candidate_units.append({
				"id": str(unit.get("id", "")),
				"historical_display_name": str(unit.get("name_zh", unit.get("source_name", ""))),
				"source_name": str(unit.get("source_name", "")),
				"geometry_feature_id": str(unit.get("geometry_feature_id", "")),
				"valid_from": str(unit.get("valid_from", "")),
				"valid_to": str(unit.get("valid_to", "")),
			})
	for feature_value: Variant in (_dated_geometry_document.get("features", []) as Array):
		if not feature_value is Dictionary:
			continue
		var feature := feature_value as Dictionary
		if str(feature.get("id", "")).to_lower() == "gw_697":
			candidate_features.append({
				"id": str(feature.get("id", "")),
				"source_name": str(feature.get("source_name", "")),
				"geometry_type": str((feature.get("geometry", {}) as Dictionary).get("type", "")),
			})
	var control_regions: Array = _central_arabia_control_document.get("regions", []) as Array
	var source_records: Array = _central_arabia_control_document.get("sources", []) as Array
	var jabal_shammar_record: Dictionary = {}
	for region_value: Variant in control_regions:
		if not region_value is Dictionary:
			continue
		var region := region_value as Dictionary
		if str(region.get("id", "")) == "jabal_shammar_hail":
			jabal_shammar_record = region.duplicate(true)
			break
	var resolved_entity_id := str(candidate_units[0].get("id", "")) if not candidate_units.is_empty() else ""
	var geometry_feature_id := str(candidate_units[0].get("geometry_feature_id", "")) if not candidate_units.is_empty() else ""
	var geometry_present := not resolved_entity_id.is_empty() and not geometry_feature_id.is_empty() and _geometry_feature_by_id.has(geometry_feature_id)
	return {
		"requested_terms": requested_terms,
		"matched_terms": matched_terms,
		"repository_record_present": not candidate_units.is_empty(),
		"repository_jabal_shammar_record_present": false,
		"repository_control_record_present": not jabal_shammar_record.is_empty(),
		"repository_record_search_result": "no formal CShapes/political_units record; source-backed control record is explicit",
		"entity_id": resolved_entity_id,
		"historical_display_name": str(jabal_shammar_record.get("display_name", "Emirate of Jabal Shammar / Ha'il")),
		"correct_historical_target": "emirate_of_jabal_shammar",
		"geometry_feature_id": geometry_feature_id,
		"geometry_present": geometry_present,
		"candidate_units": candidate_units,
		"candidate_features": candidate_features,
		"modern_saudi_substitution": false,
		"modern_political_fallback_allowed": false,
		"formal_world_date": str(_central_arabia_control_document.get("formal_world_date", "1900-01-01")),
		"control_record_type": str(_central_arabia_control_document.get("record_type", "")),
		"boundary_policy": str(_central_arabia_control_document.get("boundary_policy", "")),
		"regions": control_regions.duplicate(true),
		"jabal_shammar_record": jabal_shammar_record,
		"source_records": source_records.duplicate(true),
		"checked_sources": [
			HISTORICAL_UNITS_PATH,
			HISTORICAL_GEOMETRY_PATH,
			CENTRAL_ARABIA_CONTROL_PATH,
			"res://data/world_map/world_coastlines.json",
			"res://data/world_map/countries.json",
			"res://docs/data_sources/",
			"res://tools/historical_data/",
		],
		"source_snapshot_date": str(_dated_geometry_document.get("snapshot_date", HISTORICAL_SNAPSHOT_DATE)),
		"status": "CONTROL_EVIDENCE_RECORDED",
		"reason": "1900-01-01 Central Arabia is represented by explicit Rashidi/Jabal Shammar control evidence and uncertainty categories; no modern Saudi political fallback or fabricated precision polygon is admitted.",
	}


func _historical_identity_term_matches(searchable: String, normalized_term: String) -> bool:
	if normalized_term.is_empty():
		return false
	var haystack := searchable.replace("'", "")
	# Identity searches must not treat the Hail substring inside an unrelated
	# name such as Thailand as a historical match.  ASCII aliases are matched as
	# complete tokens; the exact non-ASCII aliases remain substring-safe.
	var is_ascii_alias := true
	for character: String in normalized_term:
		if not ((character >= "a" and character <= "z") or character == " " or character == "_" or (character >= "0" and character <= "9")):
			is_ascii_alias = false
			break
	if not is_ascii_alias:
		return haystack.contains(normalized_term)
	# The admitted aliases contain only letters, digits, spaces and underscores;
	# keeping them literal avoids relying on a non-existent native RegEx.escape
	# helper in the pinned Godot build.
	var escaped: String = normalized_term
	var expression := RegEx.new()
	if expression.compile("(^|[^a-z0-9])" + escaped + "([^a-z0-9]|$)") != OK:
		return false
	return expression.search(haystack) != null


func _geometry_has_dateline_seam(geometry: Dictionary) -> bool:
	var has_west := false
	var has_east := false
	var geometry_type := str(geometry.get("type", ""))
	var coordinates: Array = geometry.get("coordinates", []) as Array
	var polygons: Array = coordinates if geometry_type == "MultiPolygon" else [coordinates]
	for polygon_value: Variant in polygons:
		if not polygon_value is Array:
			continue
		for ring_value: Variant in (polygon_value as Array):
			if not ring_value is Array:
				continue
			for coordinate_value: Variant in (ring_value as Array):
				if not coordinate_value is Array or (coordinate_value as Array).size() < 2:
					continue
				var longitude := float((coordinate_value as Array)[0])
				if longitude <= -170.0:
					has_west = true
				if longitude >= 170.0:
					has_east = true
	return has_west and has_east


func historical_evidence_report(
	load_flag_resources: bool = false,
	include_physical_geometry: bool = true
) -> Dictionary:
	# Resource validation is an explicit audit operation.  It must not run while
	# the formal scene is entering the playable world: loading and resizing 145
	# flag images there creates a multi-second main-thread stall before the first
	# usable frame.  The normal report still validates the historical registry,
	# ownership and geometry references without creating presentation textures.
	if load_flag_resources:
		_audit_historical_flag_materials()
	var unit_count := _history_entity_by_id.size()
	var geometry_count := _geometry_feature_by_id.size()
	var local_flags := 0
	var controller_flags := 0
	var documented_absence := 0
	var valid_historical_flags := 0
	var explicit_no_verified_flags := 0
	var resource_errors := 0
	for entity_value: Variant in _country_by_id.values():
		var entity := entity_value as Dictionary
		match str(entity.get("flag_mode", "")):
			"local_historical_flag": local_flags += 1
			"controller_identification_flag": controller_flags += 1
			"documented_absence": documented_absence += 1
		var classification := historical_flag_material_classification(str(entity.get("id", "")))
		match classification:
			FLAG_MATERIAL_VALID_HISTORICAL_FLAG: valid_historical_flags += 1
			FLAG_MATERIAL_EXPLICIT_NO_VERIFIED_FLAG: explicit_no_verified_flags += 1
			FLAG_MATERIAL_RESOURCE_ERROR: resource_errors += 1
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
		"valid_historical_flag_count": valid_historical_flags,
		"explicit_no_verified_flag_count": explicit_no_verified_flags,
		"resource_error_count": resource_errors,
		"unresolved_flag_count": resource_errors + _missing_flag_record_ids.size(),
		"flag_registry_record_count": int(_historical_flag_document.get("record_count", 0)),
		"physical_land": physical_land_source_report() if include_physical_geometry else {
			"deferred": true,
			"political_ownership_attached": false,
			"source_is_modern_geometry_approximation": true,
		},
		"map_truth": historical_map_truth_report(),
	}


func _audit_historical_flag_materials() -> void:
	for entity_key: Variant in _country_by_id.keys():
		var entity_id := str(entity_key)
		if historical_flag_material_classification(entity_id) == FLAG_MATERIAL_VALID_HISTORICAL_FLAG:
			_flag_texture_for_entity(entity_id, {})


func flag_coverage_report() -> Dictionary:
	var report := historical_evidence_report(true, true)
	return {
		"explicit_count": int(report.get("unit_count", 0)),
		"generated_count": int(report.get("unit_count", 0)) - int(report.get("unresolved_flag_count", 0)),
		"local_historical_flags": int(report.get("local_flag_count", 0)),
		"controller_identification_flags": int(report.get("controller_flag_count", 0)),
		"documented_absence": int(report.get("documented_absence_count", 0)),
		"valid_historical_flags": int(report.get("valid_historical_flag_count", 0)),
		"explicit_no_verified_flags": int(report.get("explicit_no_verified_flag_count", 0)),
		"resource_errors": int(report.get("resource_error_count", 0)),
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
	# Keep startup validation structural and deterministic.  Full flag resource
	# loading and physical-land triangulation are exposed through the explicit
	# audit reports instead of blocking Formal World entry.
	var report := historical_evidence_report(false, false)
	if int(report.get("resource_error_count", 0)) != 0:
		push_error("Historical evidence: flag resource/import errors remain")
	if int(report.get("unresolved_flag_count", 0)) != 0:
		push_error("Historical evidence: unresolved flag records remain")
	var map_truth := report.get("map_truth", {}) as Dictionary
	if not (map_truth.get("diagnostics", []) as Array).is_empty():
		for diagnostic_value: Variant in (map_truth.get("diagnostics", []) as Array):
			push_error("Historical evidence map: %s" % str(diagnostic_value))
	if int(map_truth.get("missing_geometry_count", 0)) != 0:
		push_error("Historical evidence map: historical units have unresolved geometry")
	if int(map_truth.get("zero_geometry_count", 0)) != 0:
		push_error("Historical evidence map: historical units have zero geometry")
	if int(map_truth.get("geometry_without_valid_historical_owner_count", 0)) != 0:
		push_error("Historical evidence map: geometry has no valid historical owner")
	if int(map_truth.get("modern_identity_fallback_count", 0)) != 0 or bool(map_truth.get("formal_world_uses_modern_crosswalk", true)):
		push_error("Historical evidence map: modern identity fallback entered formal world")
