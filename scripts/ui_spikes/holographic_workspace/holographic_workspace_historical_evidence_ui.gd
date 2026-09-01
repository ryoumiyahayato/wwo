extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"
## Presentation copy for the dated evidence provider.


func _ready() -> void:
	if _dated_units_document.is_empty():
		_bootstrap_historical_political_evidence()
	super._ready()


func _bootstrap_historical_political_evidence() -> bool:
	if not _dated_units_document.is_empty():
		return true
	var bootstrap := HistoricalEvidenceStandaloneBootstrap.build(
		_historical_provenance_gate
	)
	if not bool(bootstrap.get("success", false)):
		_data_errors.append(
			"历史政治证据 bootstrap admission 失败：%s"
			% str(bootstrap.get("error", "unknown error"))
		)
		return false
	var bootstrap_gate := bootstrap.get("gate") as HistoricalProvenanceGate
	if _historical_provenance_gate == null:
		if not bind_historical_provenance_gate(bootstrap_gate):
			_data_errors.append("历史政治证据 bootstrap 无法绑定 Provenance gate")
			return false
		_historical_provenance_foundation = (
			bootstrap.get("foundation") as HistoricalProvenanceFoundation
		)
	var admitted_records := bootstrap.get("records", []) as Array
	_dated_units_document = {"units": admitted_records}
	return true


func _draw_historical_entity_focus() -> void:
	var entity: Dictionary = _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	var rect: Rect2 = _history_focus_rect()
	_panel(rect.grow(14.0), Color(0.018, 0.038, 0.045, 0.94), Color(0.67, 0.62, 0.42, 0.32))
	var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
	for index: int in range(territories.size()):
		var territory: Dictionary = territories[index] as Dictionary
		var territory_key: String = str(territory.get("iso_a3", ""))
		var selected: bool = territory_key == selected_historical_territory_iso
		var hovered: bool = territory_key == hover_historical_territory_iso
		var fill: Color = _history_territory_color(index, 0.36)
		var border: Color = Color(0.70, 0.79, 0.73, 0.55)
		var width: float = 1.0
		if selected:
			fill = Color(0.82, 0.60, 0.24, 0.54)
			border = Color(0.98, 0.82, 0.43, 0.98)
			width = 2.1
		elif hovered:
			fill = Color(0.34, 0.64, 0.59, 0.48)
			border = Color(0.82, 0.95, 0.88, 0.92)
			width = 1.7
		for polygon_value: Variant in (_history_focus_screen_polygons.get(territory_key, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, width, true)
		var anchor: Vector3 = territory.get("anchor", Vector3.ZERO) as Vector3
		if not anchor.is_zero_approx():
			var label_point := _lon_lat_to_history_rect(_unit_to_lon_lat(anchor), _history_focus_screen_bounds, rect)
			_draw_label(label_point + Vector2(5.0, 3.0), str(territory.get("name", territory_key)), 10)

	_draw_label(rect.position + Vector2(12.0, 24.0), "1900政治单元 · " + str(entity.get("name_zh", selected_country_id)), 16)
	_draw_label(
		rect.position + Vector2(12.0, 47.0),
		"边界来源：CShapes 2.0 · 快照日期：1900-03-12 · 有效期 %s—%s" % [
			str(entity.get("valid_from", "")),
			str(entity.get("valid_to", "")),
		],
		10,
		Color(0.70, 0.78, 0.75, 1.0)
	)
	var flag_id := str(entity.get("flag_id", ""))
	var flag_record := _historical_flag_records.get(flag_id, {}) as Dictionary
	var flag_type := str(flag_record.get("flag_type", "documented_absence"))
	var confidence := str(flag_record.get("confidence", ""))
	var flag_mode := str(entity.get("flag_mode", ""))
	var flag_copy := "旗帜：%s · %s · 置信度 %s" % [flag_id, flag_type, confidence]
	if flag_mode == "controller_identification_flag":
		flag_copy = "宗主权识别旗：%s · 不代表本地国旗" % flag_id
	elif flag_mode == "documented_absence":
		flag_copy = "无单一标准旗：" + str(entity.get("flag_absence_reason", "已记录为中性显示"))
	_draw_label(rect.position + Vector2(12.0, 67.0), flag_copy, 9, Color(0.91, 0.75, 0.44, 0.92))
	_draw_button(Rect2(rect.position.x + 12.0, rect.end.y - 38.0, 98.0, 28.0), "返回全球", "history_back_global", true)
	_draw_button(Rect2(rect.end.x - 136.0, rect.end.y - 38.0, 124.0, 28.0), "进入辖区", not selected_historical_territory_iso.is_empty() or territories.size() == 1)
