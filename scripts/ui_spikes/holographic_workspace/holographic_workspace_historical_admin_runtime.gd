extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence_ui.gd"
## Generic 1900 country profile and historical first-level administration layer.
## Country-specific names, aliases, summaries and administrative units live in data files.

const MAJOR_STATE_PROFILE_PATH := "res://data/world_map/historical/major_state_profiles_1900.json"
const HISTORICAL_ADMIN_PATH := "res://data/world_map/historical/historical_admin1_1900.json"
const ADMIN_PAGE_SIZE := 24

var selected_admin_unit_id: String = ""
var admin_page_index: int = 0
var _major_state_profile_by_entity: Dictionary = {}
var _entity_by_nationality_alias: Dictionary = {}
var _historical_admin_by_entity: Dictionary = {}


func _ready() -> void:
	_load_major_state_profiles()
	_load_historical_admin_records()
	super._ready()


func _load_major_state_profiles() -> void:
	_major_state_profile_by_entity.clear()
	_entity_by_nationality_alias.clear()
	var document := _read_document(MAJOR_STATE_PROFILE_PATH)
	for profile_value: Variant in (document.get("profiles", []) as Array):
		if not profile_value is Dictionary:
			continue
		var profile := (profile_value as Dictionary).duplicate(true)
		var entity_id := str(profile.get("entity_id", ""))
		if entity_id.is_empty():
			continue
		_major_state_profile_by_entity[entity_id] = profile
		for alias_value: Variant in (profile.get("aliases", []) as Array):
			var alias := str(alias_value).to_upper()
			if not alias.is_empty():
				_entity_by_nationality_alias[alias] = entity_id


func _load_historical_admin_records() -> void:
	_historical_admin_by_entity.clear()
	var document := _read_document(HISTORICAL_ADMIN_PATH)
	for country_value: Variant in (document.get("countries", []) as Array):
		if not country_value is Dictionary:
			continue
		var country := (country_value as Dictionary).duplicate(true)
		var entity_id := str(country.get("entity_id", ""))
		if entity_id.is_empty():
			continue
		var runtime_units: Array[Dictionary] = []
		var index := 0
		for unit_value: Variant in (country.get("units", []) as Array):
			var unit_name := str(unit_value)
			if unit_name.is_empty():
				continue
			runtime_units.append({
				"id": "%s_admin_%03d" % [entity_id, index],
				"name_zh": unit_name,
			})
			index += 1
		country["runtime_units"] = runtime_units
		_historical_admin_by_entity[entity_id] = country


func _home_historical_entity_id() -> String:
	var profile := _character_profiles.get(active_character_key, {}) as Dictionary
	var nationality_id := str(profile.get("nationality_id", ""))
	if _history_entity_by_id.has(nationality_id):
		return nationality_id
	var alias := nationality_id.trim_prefix("country_").to_upper() if nationality_id.begins_with("country_") else nationality_id.to_upper()
	var mapped_entity := str(_entity_by_nationality_alias.get(alias, ""))
	if _history_entity_by_id.has(mapped_entity):
		return mapped_entity
	return FOCUS_COUNTRY_ID


func _draw_historical_entity_focus() -> void:
	super._draw_historical_entity_focus()
	var profile := _major_state_profile_by_entity.get(selected_country_id, {}) as Dictionary
	if profile.is_empty():
		return
	var rect := _history_focus_rect()
	var brief := str(profile.get("brief_zh", ""))
	var sentences := brief.split("。", false)
	var y := 91.0
	for index: int in range(mini(2, sentences.size())):
		var sentence := str(sentences[index]).strip_edges()
		if sentence.is_empty():
			continue
		_draw_label(rect.position + Vector2(12.0, y), sentence + "。", 10, Color(0.84, 0.86, 0.79, 0.96))
		y += 19.0
	var observer_note := _observer_note_for(selected_country_id)
	if not observer_note.is_empty():
		_draw_label(rect.position + Vector2(12.0, y + 2.0), "当前视角：" + observer_note, 9, Color(0.94, 0.76, 0.45, 0.96))


func _observer_note_for(target_entity_id: String) -> String:
	var document := _read_document(MAJOR_STATE_PROFILE_PATH)
	var observer_notes := document.get("observer_notes_zh", {}) as Dictionary
	var home_entity_id := _home_historical_entity_id()
	var by_target := observer_notes.get(home_entity_id, {}) as Dictionary
	return str(by_target.get(target_entity_id, ""))


func _enter_region() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and _historical_admin_by_entity.has(selected_country_id):
		space_level = REGION
		selected_admin_unit_id = ""
		admin_page_index = 0
		selected_world_admin1_id = ""
		_set_info_open(false)
		viewport_container.visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()
		return
	super._enter_region()


func _draw_region_map() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and _historical_admin_by_entity.has(selected_country_id):
		_draw_historical_admin_index()
		return
	super._draw_region_map()


func _draw_historical_admin_index() -> void:
	var country := _historical_admin_by_entity.get(selected_country_id, {}) as Dictionary
	var units := country.get("runtime_units", []) as Array
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	_panel(rect, Color(0.018, 0.039, 0.046, 0.97), Color(0.67, 0.62, 0.42, 0.38))
	var entity := _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	_draw_label(rect.position + Vector2(24.0, 34.0), str(entity.get("name_zh", selected_country_id)) + " · " + str(country.get("level_name_zh", "一级行政区")), 17)
	_draw_label(rect.position + Vector2(24.0, 58.0), "史料依据：" + str(country.get("source_basis", "")), 10, Color(0.72, 0.80, 0.75, 0.94))
	var geometry_status := str(country.get("geometry_status", ""))
	var status_copy := "历史边界已接入" if geometry_status.contains("historical_geometry_available") else "历史名称与层级已核对；边界数字化未完成，禁止回退成现代行政区。"
	_draw_label(rect.position + Vector2(24.0, 78.0), status_copy, 9, Color(0.96, 0.72, 0.40, 0.96))

	var page_count := maxi(1, int(ceil(float(units.size()) / float(ADMIN_PAGE_SIZE))))
	admin_page_index = clampi(admin_page_index, 0, page_count - 1)
	var start_index := admin_page_index * ADMIN_PAGE_SIZE
	var end_index := mini(units.size(), start_index + ADMIN_PAGE_SIZE)
	var columns := 3
	var rows := 8
	var cell_width := (rect.size.x - 64.0) / float(columns)
	var cell_height := 35.0
	for visible_index: int in range(end_index - start_index):
		var unit := units[start_index + visible_index] as Dictionary
		var column := visible_index / rows
		var row := visible_index % rows
		var unit_rect := Rect2(
			rect.position + Vector2(24.0 + float(column) * cell_width, 102.0 + float(row) * cell_height),
			Vector2(cell_width - 10.0, 27.0)
		)
		var unit_id := str(unit.get("id", ""))
		_draw_button(unit_rect, str(unit.get("name_zh", unit_id)), "historical_admin_select:" + unit_id, true)
		if unit_id == selected_admin_unit_id:
			draw_rect(unit_rect.grow(2.0), Color(0.98, 0.82, 0.43, 0.90), false, 1.6)
	if page_count > 1:
		_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 40.0, 88.0, 27.0), "上一页", "historical_admin_prev", admin_page_index > 0)
		_draw_label(rect.position + Vector2(126.0, rect.size.y - 22.0), "%d / %d" % [admin_page_index + 1, page_count], 10)
		_draw_button(Rect2(rect.position.x + 178.0, rect.end.y - 40.0, 88.0, 27.0), "下一页", "historical_admin_next", admin_page_index < page_count - 1)
	if not selected_admin_unit_id.is_empty():
		var selected_name := _historical_admin_unit_name(selected_admin_unit_id)
		_draw_label(rect.position + Vector2(294.0, rect.size.y - 22.0), "已选择：" + selected_name, 10, Color(0.94, 0.80, 0.50, 1.0))


func _activate_button(action: String) -> void:
	if action.begins_with("historical_admin_select:"):
		selected_admin_unit_id = action.trim_prefix("historical_admin_select:")
		queue_redraw()
		return
	if action == "historical_admin_prev":
		admin_page_index = maxi(0, admin_page_index - 1)
		selected_admin_unit_id = ""
		queue_redraw()
		return
	if action == "historical_admin_next":
		admin_page_index += 1
		selected_admin_unit_id = ""
		queue_redraw()
		return
	super._activate_button(action)


func _go_back() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and space_level == REGION and _historical_admin_by_entity.has(selected_country_id):
		space_level = WORLD
		selected_admin_unit_id = ""
		admin_page_index = 0
		queue_redraw()
		return
	super._go_back()


func _breadcrumb_text() -> String:
	var text := super._breadcrumb_text()
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and not selected_admin_unit_id.is_empty():
		text += " / " + _historical_admin_unit_name(selected_admin_unit_id)
	return text


func _historical_admin_unit_name(unit_id: String) -> String:
	var country := _historical_admin_by_entity.get(selected_country_id, {}) as Dictionary
	for unit_value: Variant in (country.get("runtime_units", []) as Array):
		var unit := unit_value as Dictionary
		if str(unit.get("id", "")) == unit_id:
			return str(unit.get("name_zh", unit_id))
	return unit_id


func historical_admin_coverage_report() -> Dictionary:
	var detailed_count := _historical_admin_by_entity.size()
	var profile_count := _major_state_profile_by_entity.size()
	var unresolved_geometry := 0
	for country_value: Variant in _historical_admin_by_entity.values():
		var country := country_value as Dictionary
		if not str(country.get("geometry_status", "")).contains("historical_geometry_available"):
			unresolved_geometry += 1
	return {
		"profile_count": profile_count,
		"detailed_country_count": detailed_count,
		"unresolved_geometry_count": unresolved_geometry,
		"modern_admin_names_forbidden": true,
	}
