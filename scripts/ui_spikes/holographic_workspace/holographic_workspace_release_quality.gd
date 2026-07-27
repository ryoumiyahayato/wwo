extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd"
## Data-quality and identity layer: do not present modern reference geometry as verified 1900 GIS.

const IDENTITY_PREFIX := "identity:"
const IDENTITY_SEPARATOR := "::"
const ADMIN1_REFERENCE_NOTICE := "现代一级行政区参考层，不代表1900年逐点历史边界。"
const FLAG_REFERENCE_NOTICE := "旗面包含程序化识别码；用于空间导航，不等同于历史旗帜复原。"


func _distinctive_pattern_for_entity(entity_id: String, fallback: String) -> String:
	var base_pattern := super._distinctive_pattern_for_entity(entity_id, fallback)
	var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
	if entity.is_empty() or bool(entity.get("provisional", false)):
		return base_pattern
	return "%s%d%s%s" % [IDENTITY_PREFIX, _explicit_entity_ordinal(entity_id), IDENTITY_SEPARATOR, base_pattern]


func _distinctive_flag_color(pattern: String, colors: PackedColorArray, u: float, v: float) -> Color:
	if not pattern.begins_with(IDENTITY_PREFIX):
		return super._distinctive_flag_color(pattern, colors, u, v)
	var separator_index := pattern.find(IDENTITY_SEPARATOR)
	if separator_index < 0:
		return super._distinctive_flag_color(pattern, colors, u, v)
	var ordinal_text := pattern.substr(IDENTITY_PREFIX.length(), separator_index - IDENTITY_PREFIX.length())
	var base_pattern := pattern.substr(separator_index + IDENTITY_SEPARATOR.length())
	var base := super._distinctive_flag_color(base_pattern, colors, u, v)
	return _apply_identity_code(base, colors, int(ordinal_text), u, v)


func _apply_identity_code(base: Color, colors: PackedColorArray, ordinal: int, u: float, v: float) -> Color:
	if u < 0.585 or v < 0.625:
		return base
	var plate := base.lerp(Color(0.08, 0.10, 0.10, 1.0), 0.34)
	var code := ordinal + 1
	var columns: Array[float] = [0.625, 0.708333, 0.791667, 0.875]
	var rows: Array[float] = [0.6875, 0.8125]
	var bit := 0
	for row: float in rows:
		for column: float in columns:
			if Vector2(u, v).distance_to(Vector2(column, row)) < 0.037:
				return _contrast_color(colors, plate) if (code & (1 << bit)) != 0 else plate
			bit += 1
	return plate


func _explicit_entity_ordinal(entity_id: String) -> int:
	var ids: Array[String] = []
	for entity_key: Variant in _history_entity_by_id.keys():
		var candidate_id := str(entity_key)
		var entity: Dictionary = _country_by_id.get(candidate_id, {}) as Dictionary
		if not entity.is_empty() and not bool(entity.get("provisional", false)):
			ids.append(candidate_id)
	ids.sort()
	return maxi(0, ids.find(entity_id))


func _draw_global_world() -> void:
	super._draw_global_world()
	_draw_label(
		Vector2(_hemisphere_rect.position.x + 14.0, _hemisphere_rect.position.y + 19.0),
		FLAG_REFERENCE_NOTICE,
		9,
		Color(0.74, 0.77, 0.68, 0.72)
	)


func _draw_world_admin1_layer() -> void:
	super._draw_world_admin1_layer()
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	var records: Array = _world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array
	var status := "现代参考" if not records.is_empty() else "无下级历史数据"
	var badge := Rect2(rect.end.x - 270.0, rect.position.y + 18.0, 246.0, 24.0)
	_panel(badge, Color(0.12, 0.09, 0.04, 0.96), Color(0.80, 0.58, 0.25, 0.72))
	_draw_label(badge.position + Vector2(10.0, 16.0), "数据等级：" + status, 10, Color(0.96, 0.79, 0.46, 1.0))


func _draw_world_admin1_local_layer() -> void:
	super._draw_world_admin1_local_layer()
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	var badge := Rect2(rect.end.x - 390.0, rect.position.y + 17.0, 366.0, 25.0)
	_panel(badge, Color(0.14, 0.08, 0.04, 0.97), Color(0.84, 0.49, 0.24, 0.78))
	_draw_label(badge.position + Vector2(10.0, 17.0), ADMIN1_REFERENCE_NOTICE, 9, Color(0.98, 0.79, 0.53, 1.0))


func navigation_coverage_report() -> Dictionary:
	var total_territories := 0
	var curated_navigation := 0
	var modern_reference := 0
	var country_terminal := 0
	for entity_key: Variant in _history_territories_by_entity.keys():
		var entity_id := str(entity_key)
		for territory_value: Variant in (_history_territories_by_entity.get(entity_id, []) as Array):
			var territory := territory_value as Dictionary
			var iso := str(territory.get("iso_a3", "")).to_upper()
			if iso.is_empty():
				continue
			total_territories += 1
			if entity_id == FOCUS_COUNTRY_ID and iso == "FRA":
				curated_navigation += 1
			elif not (_world_admin1_by_iso.get(iso, []) as Array).is_empty():
				modern_reference += 1
			else:
				country_terminal += 1
	return {
		"total_territories": total_territories,
		"curated_navigation": curated_navigation,
		"modern_reference": modern_reference,
		"country_terminal": country_terminal,
		"fully_historical": false,
	}
