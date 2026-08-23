class_name FormalWorldApplication
extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
## Formal product scene: the complete dated political world is the map authority.
## Fifty ranked polities receive high-detail economy; all remaining political
## units stay visible as background/non-player world actors.

const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
const PACKAGED_PROBE_ARGUMENT: String = "--wwo-player-baseline-probe"
const PACKAGED_PROBE_ENTITY_ID: String = "country_fra"
const PACKAGED_PROBE_FLAG_ID: String = "france_tricolour_1794"
const NEUTRAL_SESSION_NAME: String = "WWO PRODUCT SESSION"
const NEUTRAL_SESSION_DETAIL: String = "Player identity not integrated."
const POLITICS_UNAVAILABLE: String = (
	"Simulation not integrated into current product runtime."
)
const ORGANIZATION_UNAVAILABLE: String = (
	"Current organization runtime not integrated."
)
const MILITARY_UNAVAILABLE: String = "Dynamic military runtime not integrated."

var formal_simulation := FormalWorldSimulation.new()
var product_runtime_gate := ProductRuntimeGate.new()
var economy_panel_open: bool = false
var developer_mode_enabled: bool = false
var _formal_status: String = ""
var _last_summary: Dictionary = {}
var _packaged_probe_failures: int = 0


func _ready() -> void:
	active_character_key = "product_session"
	activity_unread = 0
	history_war_layer_visible = false
	super._ready()
	_clear_rejected_presentation_state()
	if not formal_simulation.initialize():
		_formal_status = "正式世界初始化失败：%s" % formal_simulation.initialization_error
		_data_errors.append(_formal_status)
	else:
		var launch_mode := str(get_tree().get_meta(LAUNCH_MODE_META, "new"))
		if get_tree().has_meta(LAUNCH_MODE_META):
			get_tree().remove_meta(LAUNCH_MODE_META)
		if launch_mode == "load":
			var result := _load_formal_state()
			_formal_status = result.message
			if _formal_status.is_empty():
				_formal_status = (
					"正式世界存档已恢复。"
					if result.success
					else "正式世界存档恢复失败；当前状态保持1900-01-01 00:00。"
				)
		else:
			_formal_status = "新的1900正式世界已建立。"
		_last_summary = formal_simulation.world_summary()
	queue_redraw()
	if PACKAGED_PROBE_ARGUMENT in OS.get_cmdline_user_args():
		_run_packaged_player_baseline_probe.call_deferred()


func _run_packaged_player_baseline_probe() -> void:
	await get_tree().process_frame
	_packaged_probe_require(formal_simulation.initialized, "正式模拟未初始化")
	_packaged_probe_require(_data_errors.is_empty(), "正式模拟产生数据错误")
	_packaged_probe_require(_history_entity_by_id.size() == 151, "历史政治单元数量不正确")
	_packaged_probe_require(
		_prototype_presentation_count() == 0,
		"正式产品仍展示prototype_only内容"
	)
	_packaged_probe_require(_spike_city_count() == 0, "正式产品仍注入spike城市")
	_packaged_probe_require(_world_events.is_empty(), "正式产品仍播种静态机构议程事件")
	_packaged_probe_require(_history_conflicts.is_empty(), "正式产品仍加载静态军事冲突")
	_packaged_probe_require(_missing_flag_record_ids.is_empty(), "历史旗帜资源存在缺失")
	var evidence := historical_evidence_report()
	_packaged_probe_require(
		int(evidence.get("unresolved_flag_count", -1)) == 0,
		"历史旗帜证据仍未完全解析"
	)

	_ensure_projection_cache()
	var france_point := _country_screen_anchors.get(PACKAGED_PROBE_ENTITY_ID, Vector2.INF) as Vector2
	_packaged_probe_require(
		france_point != Vector2.INF,
		"默认半球视角没有法兰西选择锚点"
	)
	if france_point != Vector2.INF:
		_packaged_probe_mouse_button(france_point, true)
		_packaged_probe_mouse_button(france_point, false)
	await get_tree().process_frame
	_packaged_probe_require(
		selected_country_id == PACKAGED_PROBE_ENTITY_ID,
		"打包产品地图点击未选择法兰西政治单元"
	)
	_packaged_probe_require(info_open, "打包产品实体选择没有打开详情反馈")
	_packaged_probe_require(
		not formal_simulation.polity_summary(PACKAGED_PROBE_ENTITY_ID).is_empty(),
		"打包产品选中实体没有政经详情"
	)
	var imported_flags := _historical_imported_flag_texture_by_id as Dictionary
	_packaged_probe_require(
		imported_flags.get(PACKAGED_PROBE_FLAG_ID) is Texture2D,
		"打包产品没有通过导入Texture2D解析法兰西历史旗帜"
	)

	var date_before := _format_sim_datetime()
	_packaged_probe_require(
		await _packaged_probe_click_action("toggle_time_panel"),
		"打包产品时间面板入口不可点击"
	)
	_packaged_probe_require(
		await _packaged_probe_click_action("speed:4"),
		"打包产品4倍速控件不可点击"
	)
	var clock := get_node("ClockTimer") as Timer
	for _index: int in range(24):
		clock.timeout.emit()
	await get_tree().process_frame
	_packaged_probe_require(
		_format_sim_datetime() != date_before,
		"打包产品时间推进没有改变可见日期"
	)
	_packaged_probe_require(
		await _packaged_probe_click_action("toggle_pause"),
		"打包产品暂停控件不可点击"
	)
	_packaged_probe_require(sim_paused, "打包产品暂停控件未暂停正式时间")

	if _packaged_probe_failures > 0:
		push_error(
			"Packaged player baseline probe: %d failures" % _packaged_probe_failures
		)
	else:
		print("Packaged player baseline probe: title, world, polity, resource, and time passed")
	get_tree().quit(1 if _packaged_probe_failures > 0 else 0)


func _packaged_probe_click_action(action: String) -> bool:
	queue_redraw()
	for _index: int in range(3):
		await get_tree().process_frame
	for index: int in range(_button_hits.size() - 1, -1, -1):
		var record: Dictionary = _button_hits[index]
		if str(record.get("action", "")) != action or not bool(record.get("enabled", false)):
			continue
		var rect: Rect2 = record.get("rect", Rect2()) as Rect2
		_packaged_probe_mouse_button(rect.get_center(), true)
		_packaged_probe_mouse_button(rect.get_center(), false)
		await get_tree().process_frame
		return true
	return false


func _packaged_probe_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	_gui_input(event)


func _packaged_probe_require(condition: bool, message: String) -> void:
	if condition:
		return
	_packaged_probe_failures += 1
	push_error("Packaged player baseline probe: " + message)


func _read_document(path: String) -> Dictionary:
	return product_runtime_gate.filter_document(path, super._read_document(path))


func _seed_world_events() -> void:
	_world_events.clear()
	_event_by_id.clear()
	activity_unread = 0


func _install_spike_city_coverage() -> void:
	# The supplements are a UI spike catalog, not production city identity.
	pass


func _load_administrative_visual_data() -> void:
	_administrative_notice = ""
	_administrative_unit_by_id.clear()
	_administrative_polygons_by_id.clear()
	_administrative_anchor_by_id.clear()
	_administrative_units_by_region.clear()
	_administrative_screen_polygons.clear()


func _load_world_admin1_data() -> void:
	_world_admin1_by_iso.clear()
	_world_admin1_by_id.clear()
	_world_admin1_screen_polygons.clear()
	_world_admin1_unit_cache.clear()
	_world_admin1_country_count = 0


func _load_flag_palettes() -> void:
	# Dated evidence installs source-backed palettes while building its 151 units.
	_flag_palettes.clear()


func _load_historical_conflicts() -> void:
	_history_conflicts.clear()


func _clear_rejected_presentation_state() -> void:
	_regions.clear()
	_region_by_id.clear()
	_region_polygons.clear()
	_cities.clear()
	_city_by_id.clear()
	_cities_by_region.clear()
	_institutions.clear()
	_institution_by_id.clear()
	_institutions_by_city.clear()
	_institutions_by_region.clear()
	_character_profiles.clear()
	_country_profile.clear()
	_world_events.clear()
	_event_by_id.clear()
	_history_conflicts.clear()
	_load_administrative_visual_data()
	_load_world_admin1_data()
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	selected_event_id = ""
	selected_admin_unit_id = ""
	selected_world_admin1_id = ""
	selected_administrative_unit_id = ""
	hover_administrative_unit_id = ""
	activity_unread = 0
	history_war_layer_visible = false


func _prototype_presentation_count() -> int:
	return (
		_regions.size()
		+ _cities.size()
		+ _institutions.size()
		+ _character_profiles.size()
		+ _country_profile.size()
		+ _world_events.size()
		+ _history_conflicts.size()
		+ _administrative_unit_by_id.size()
		+ _world_admin1_by_id.size()
	)


func _spike_city_count() -> int:
	var count := 0
	for city: Dictionary in _cities:
		if str(city.get("id", "")).ends_with("_spike") or bool(
			city.get("spike_supplement", false)
		):
			count += 1
	return count


func _home_historical_entity_id() -> String:
	return ""


func _active_character_name() -> String:
	return NEUTRAL_SESSION_NAME


func _active_character_position() -> String:
	return NEUTRAL_SESSION_DETAIL


func _activity_summary() -> String:
	return "Unsupported agendas and events are unavailable."


func _switch_character() -> void:
	_open_product_panel("session")


func _draw_corners() -> void:
	var compact := size.x < 940.0 or size.y < 620.0
	var left_width := minf(284.0, size.x * 0.42)
	var right_width := minf(282.0, size.x * 0.42)
	var top_height := 56.0 if compact else 66.0
	var bottom_height := 58.0 if compact else 70.0
	var country_rect := Rect2(18.0, 18.0, left_width, top_height)
	var time_rect := Rect2(
		size.x - right_width - 18.0, 18.0, right_width, top_height
	)
	var session_rect := Rect2(
		18.0, size.y - bottom_height - 18.0, left_width, bottom_height
	)
	var truth_rect := Rect2(
		size.x - right_width - 18.0,
		size.y - bottom_height - 18.0,
		right_width,
		bottom_height
	)
	var country_title := "1900 DATED WORLD"
	if _history_entity_by_id.has(selected_country_id):
		var entity := _history_entity_by_id.get(selected_country_id, {}) as Dictionary
		country_title = str(
			entity.get("short_name_zh", entity.get("name_zh", selected_country_id))
		)
	_draw_corner(
		country_rect,
		country_title,
		"151 units · 1900-03-12 · read-only projection",
		"product_integration",
		Color(0.72, 0.64, 0.38, 0.22),
		compact
	)
	_draw_corner(
		session_rect,
		NEUTRAL_SESSION_NAME,
		NEUTRAL_SESSION_DETAIL,
		"product_session",
		Color(0.72, 0.64, 0.38, 0.22),
		compact
	)
	_draw_corner(
		truth_rect,
		"PRODUCT TRUTH BASELINE",
		"P/O/M unavailable · F12 owners",
		"product_integration",
		Color(0.72, 0.50, 0.25, 0.22),
		compact
	)
	_panel(
		time_rect,
		Color(0.025, 0.055, 0.06, 0.88),
		Color(0.72, 0.64, 0.38, 0.22)
	)
	_register_hit(time_rect, "toggle_time_panel", true)
	_draw_label(time_rect.position + Vector2(12.0, 22.0), _format_sim_datetime(), 13)
	var button_y := time_rect.end.y - 28.0
	_draw_button(
		Rect2(time_rect.position.x + 10.0, button_y, 44.0, 22.0),
		"Ⅱ" if sim_paused else "▶",
		"toggle_pause",
		true
	)
	_draw_button(
		Rect2(time_rect.position.x + 60.0, button_y, 38.0, 22.0),
		"1×",
		"speed:1",
		true
	)
	_draw_button(
		Rect2(time_rect.position.x + 102.0, button_y, 38.0, 22.0),
		"2×",
		"speed:2",
		true
	)
	_draw_button(
		Rect2(time_rect.position.x + 144.0, button_y, 38.0, 22.0),
		"4×",
		"speed:4",
		true
	)


func _draw_active_hud_panel() -> void:
	if active_hud_panel.is_empty():
		return
	if active_hud_panel == "time":
		super._draw_active_hud_panel()
		return
	var rect := Rect2(
		maxf(24.0, size.x * 0.18),
		maxf(90.0, size.y * 0.14),
		maxf(360.0, size.x * 0.64),
		maxf(340.0, size.y * 0.70)
	)
	_panel(
		rect,
		Color(0.018, 0.035, 0.038, 0.985),
		Color(0.78, 0.70, 0.46, 0.42)
	)
	_register_hit(rect, "noop", true)
	_draw_button(
		Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 30.0, 26.0),
		"×",
		"close_hud_panel",
		true
	)
	match active_hud_panel:
		"session":
			_draw_unavailable_panel(
				rect,
				"PLAYER IDENTITY",
				NEUTRAL_SESSION_DETAIL,
				"This session has no fictional historical person attached."
			)
		"politics":
			_draw_unavailable_panel(rect, "POLITICS", POLITICS_UNAVAILABLE, "Prototype policy and agendas are not product state.")
		"organization":
			_draw_unavailable_panel(rect, "ORGANIZATION", ORGANIZATION_UNAVAILABLE, "Prototype institution dictionaries are quarantined.")
		"military":
			_draw_unavailable_panel(rect, "MILITARY", MILITARY_UNAVAILABLE, "Legacy static conflict overlays are not rendered.")
		"city_status":
			_draw_unavailable_panel(rect, "CITY", "NOT AVAILABLE YET", "No approved historical city runtime is integrated. No city state is invented.")
		"integration":
			_draw_integration_panel(rect)
		"provenance":
			_draw_provenance_panel(rect)
		_:
			super._draw_active_hud_panel()


func _draw_unavailable_panel(
	rect: Rect2, title: String, message: String, detail: String
) -> void:
	_draw_label(rect.position + Vector2(28.0, 44.0), title, 22, Color(0.95, 0.84, 0.58, 1.0))
	_draw_label(rect.position + Vector2(28.0, 88.0), message, 15)
	_draw_label(rect.position + Vector2(28.0, 122.0), detail, 11, Color(0.74, 0.82, 0.78, 0.96))
	_draw_label(rect.position + Vector2(28.0, 166.0), "SUPPORTED RESULT: EXPLICITLY UNAVAILABLE", 11, Color(0.94, 0.68, 0.39, 1.0))


func _draw_integration_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(28.0, 44.0), "PRODUCT INTEGRATION STATUS", 22, Color(0.95, 0.84, 0.58, 1.0))
	var lines: Array[String] = [
		"WORLD / POLITICAL — ACTIVE · authoritative dated data",
		"TIME — ACTIVE · FormalWorldSimulation",
		"ECONOMY — ACTIVE · FormalWorldEconomyService",
		"LOCAL GEOGRAPHY — NOT AVAILABLE YET",
		"CITY — NOT AVAILABLE YET",
		"POPULATION — NOT INTEGRATED",
		"ORGANIZATION — NOT INTEGRATED",
		"POLITICS — NOT INTEGRATED",
		"MILITARY — NOT INTEGRATED",
		"E1 PRODUCT INTEGRATION — NO",
	]
	_draw_panel_lines(rect, 84.0, lines, Color(0.82, 0.86, 0.80, 0.98), 11)
	_draw_label(rect.position + Vector2(28.0, rect.size.y - 72.0), "Developer owners are runtime-derived; F12 is the keyboard shortcut.", 10, Color(0.91, 0.72, 0.43, 0.96))
	var button_y := rect.end.y - 48.0
	_draw_button(Rect2(rect.position.x + 28.0, button_y, 118.0, 28.0), "POLITICS", "product_politics", true)
	_draw_button(Rect2(rect.position.x + 156.0, button_y, 138.0, 28.0), "ORGANIZATION", "product_organization", true)
	_draw_button(Rect2(rect.position.x + 304.0, button_y, 118.0, 28.0), "MILITARY", "product_military", true)
	_draw_button(Rect2(rect.end.x - 190.0, button_y, 162.0, 28.0), "DEVELOPER OWNERS", "product_enable_provenance", true)


func _draw_provenance_panel(rect: Rect2) -> void:
	var provenance := product_runtime_provenance()
	_draw_label(rect.position + Vector2(28.0, 38.0), "PRODUCT RUNTIME PROVENANCE", 20, Color(0.95, 0.84, 0.58, 1.0))
	_draw_label(rect.position + Vector2(28.0, 62.0), "BUILD HEAD  " + str(provenance.get("build_head", "NOT AVAILABLE")), 8)
	_draw_label(rect.position + Vector2(28.0, 80.0), "PRODUCT ENTRY  " + str(provenance.get("product_entry", "")), 8)
	var y := 104.0
	for owner_value: Variant in (provenance.get("owners", []) as Array):
		var owner := owner_value as Dictionary
		var owner_text := "%s: %s" % [str(owner.get("label", "OWNER")), str(owner.get("status", ""))]
		if str(owner.get("status", "")) == "ACTIVE":
			owner_text += " · %s · %s" % [str(owner.get("owner", "")), str(owner.get("mode", ""))]
		_draw_label(rect.position + Vector2(28.0, y), owner_text, 9, Color(0.82, 0.86, 0.80, 0.98))
		y += 21.0
	_draw_label(rect.position + Vector2(28.0, y + 4.0), "E1 PRODUCT INTEGRATION: NO", 10, Color(0.94, 0.68, 0.39, 1.0))


func _runtime_owner_specs() -> Array[Dictionary]:
	var spatial_active := (
		_history_entity_by_id.size() == 151
		and int(historical_evidence_report().get("unit_count", 0)) == 151
	)
	return [
		{"label": "PRODUCT ENTRY", "owner": self, "mode": "AUTHORITATIVE"},
		{"label": "WORLD/POLITICAL OWNER", "owner": self if spatial_active else null, "mode": "AUTHORITATIVE"},
		{"label": "TIME OWNER", "owner": formal_simulation if formal_simulation.initialized else null, "mode": "AUTHORITATIVE"},
		{"label": "ECONOMY OWNER", "owner": formal_simulation.economy if formal_simulation.initialized else null, "mode": "AUTHORITATIVE"},
		{"label": "SPATIAL OWNER", "owner": self if spatial_active else null, "mode": "READ-ONLY PROJECTION"},
		{"label": "POPULATION OWNER", "owner": null, "detail": "Aggregate economy inputs are not a population simulation."},
		{"label": "ORGANIZATION OWNER", "owner": null},
		{"label": "POLITICS OWNER", "owner": null},
		{"label": "MILITARY OWNER", "owner": null},
		{"label": "PERSISTENCE OWNER", "owner": formal_simulation if formal_simulation.initialized else null, "mode": "TRANSITIONAL"},
	]


func product_runtime_provenance() -> Dictionary:
	return ProductRuntimeProvenance.capture(_runtime_owner_specs())


func _domain_owner_state() -> Dictionary:
	return {
		"world": {"owner": self if _history_entity_by_id.size() == 151 else null, "claimed_active": true},
		"time": {"owner": formal_simulation if formal_simulation.initialized else null, "claimed_active": formal_simulation.initialized},
		"economy": {"owner": formal_simulation.economy if formal_simulation.initialized else null, "claimed_active": formal_simulation.initialized},
		"population": {"owner": null, "claimed_active": false},
		"organization": {"owner": null, "claimed_active": not _institutions.is_empty()},
		"politics": {"owner": null, "claimed_active": not _world_events.is_empty() or not _country_profile.is_empty()},
		"military": {"owner": null, "claimed_active": not _history_conflicts.is_empty() or history_war_layer_visible},
	}


func _presentation_state() -> Dictionary:
	return {
		"prototype_visible_count": _prototype_presentation_count(),
		"fixture_dependency_count": _fixture_dependency_count(),
		"spike_city_count": _spike_city_count(),
	}


func _fixture_dependency_count() -> int:
	var paths: Array[String] = product_runtime_gate.accepted_document_paths.duplicate()
	paths.append(str(ProjectSettings.get_setting("application/run/main_scene", "")))
	paths.append(scene_file_path)
	for argument: String in OS.get_cmdline_user_args():
		paths.append(argument)
	var count := 0
	for path: String in paths:
		var normalized := path.to_lower().replace("\\", "/")
		if (
			"/tests/" in normalized
			or "/fixtures/" in normalized
			or "/demo/" in normalized
			or "test-world" in normalized
		):
			count += 1
	return count


func product_integration_gate_report() -> Dictionary:
	var provenance := product_runtime_provenance()
	return product_runtime_gate.runtime_report(
		_presentation_state(),
		_domain_owner_state(),
		str(provenance.get("product_entry", "")),
		str(provenance.get("runtime_scene", ""))
	)


func runtime_evidence_snapshot() -> Dictionary:
	return {
		"provenance": product_runtime_provenance(),
		"integration_gate": product_integration_gate_report(),
		"selected_country": selected_country_id,
		"selected_region": selected_region_id,
		"selected_city": selected_city_id,
		"legacy_prototype_content_visible": _prototype_presentation_count() > 0,
		"synthetic_fixture": _fixture_dependency_count() > 0,
	}


func _open_product_panel(panel: String) -> void:
	economy_panel_open = false
	active_hud_panel = "" if active_hud_panel == panel else panel
	queue_redraw()


func _focus_selected_country() -> void:
	if selected_country_id.is_empty() or not _history_entity_by_id.has(selected_country_id):
		return
	space_level = WORLD
	world_mode = WORLD_HISTORICAL_ENTITY_FOCUS
	selected_historical_territory_iso = ""
	hover_historical_territory_iso = ""
	selected_event_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	viewport_container.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_info_open(false)
	_history_focus_dirty = true
	queue_redraw()


func _draw_historical_entity_focus() -> void:
	super._draw_historical_entity_focus()
	var rect := _history_focus_rect()
	_draw_label(rect.position + Vector2(12.0, rect.size.y - 72.0), "READ-ONLY DATED POLITICAL PROJECTION", 10, Color(0.91, 0.72, 0.43, 0.96))
	_draw_label(rect.position + Vector2(12.0, rect.size.y - 54.0), "POLITICS RUNTIME: NOT INTEGRATED", 9, Color(0.82, 0.86, 0.80, 0.96))
	_draw_button(Rect2(rect.end.x - 164.0, rect.end.y - 38.0, 152.0, 28.0), "查看地方可用性", "enter_region", true)


func _enter_region() -> void:
	if world_mode != WORLD_HISTORICAL_ENTITY_FOCUS or not _history_entity_by_id.has(selected_country_id):
		return
	if selected_historical_territory_iso.is_empty():
		selected_historical_territory_iso = _default_historical_territory_iso(selected_country_id)
	space_level = REGION
	selected_admin_unit_id = ""
	selected_world_admin1_id = ""
	selected_administrative_unit_id = ""
	selected_region_id = ""
	selected_city_id = ""
	_set_info_open(false)
	viewport_container.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	queue_redraw()


func _draw_region_map() -> void:
	_draw_historical_territory_layer()
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	var notice_rect := Rect2(rect.position + Vector2(52.0, 92.0), Vector2(rect.size.x - 104.0, 112.0))
	_panel(notice_rect, Color(0.018, 0.035, 0.038, 0.97), Color(0.94, 0.61, 0.28, 0.62))
	_draw_label(notice_rect.position + Vector2(20.0, 30.0), "DETAILED HISTORICAL SUBDIVISION", 16, Color(0.95, 0.84, 0.58, 1.0))
	_draw_label(notice_rect.position + Vector2(20.0, 57.0), "NOT AVAILABLE YET", 15)
	_draw_label(notice_rect.position + Vector2(20.0, 84.0), "Country-level dated boundary remains available. Modern Admin-1 is not used as 1900 truth.", 9, Color(0.76, 0.83, 0.79, 0.96))
	_draw_button(Rect2(rect.end.x - 142.0, rect.end.y - 40.0, 118.0, 28.0), "CITY STATUS", "product_city_status", true)


func _draw_city_map() -> void:
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	_panel(rect, Color(0.018, 0.039, 0.046, 0.97), Color(0.67, 0.62, 0.42, 0.38))
	_draw_label(rect.position + Vector2(28.0, 42.0), "CITY", 20, Color(0.95, 0.84, 0.58, 1.0))
	_draw_label(rect.position + Vector2(28.0, 82.0), "NOT AVAILABLE YET", 15)
	_draw_label(rect.position + Vector2(28.0, 116.0), "No approved historical city runtime is integrated. No city state is invented.", 11)


func _go_back() -> void:
	if not active_hud_panel.is_empty():
		active_hud_panel = ""
		queue_redraw()
		return
	if info_open or info_progress > 0.01:
		_set_info_open(false)
		return
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and space_level != WORLD:
		space_level = WORLD
		queue_redraw()
		return
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS:
		_return_to_global_world()
		return
	super._go_back()


func _breadcrumb_text() -> String:
	if world_mode != WORLD_HISTORICAL_ENTITY_FOCUS:
		return "世界 / 1900-03-12 dated political projection"
	var entity := _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	var text := "世界 / 1900政治单元 / " + str(entity.get("short_name_zh", entity.get("name_zh", selected_country_id)))
	if space_level == REGION:
		text += " / detailed historical subdivision: NOT AVAILABLE YET"
	return text


func _draw_historical_conflicts() -> void:
	pass


func _draw_world_event_markers() -> void:
	pass


func _draw_history_layer_controls() -> void:
	pass


func _advance_simulation_minutes(minutes: int) -> void:
	if formal_simulation.initialized and minutes > 0:
		_last_summary = formal_simulation.advance_minutes(minutes)


func _format_sim_datetime() -> String:
	var value := formal_simulation.date_time()
	if value.is_empty():
		return "无效时间"
	return "%04d年%02d月%02d日 %02d:%02d" % [
		int(value.get("year", 0)),
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
	]


func _time_source_description() -> String:
	return "正式模拟权威时间；半球与HUD仅派生显示"


func _load_formal_state() -> SaveOperationResult:
	var result := formal_simulation.load_from_user()
	if result.success:
		_last_summary = formal_simulation.world_summary()
	return result


func _toggle_formal_economy_panel() -> void:
	economy_panel_open = not economy_panel_open
	queue_redraw()


func _save_formal_state_from_ui() -> void:
	var result := formal_simulation.save_to_user()
	_formal_status = result.message
	if _formal_status.is_empty():
		_formal_status = (
			"正式世界已保存。"
			if result.success
			else "正式世界保存失败。"
		)
	queue_redraw()


func _load_formal_state_from_ui() -> void:
	var result := formal_simulation.load_from_user()
	_formal_status = result.message
	if _formal_status.is_empty():
		_formal_status = (
			"正式世界存档已恢复。"
			if result.success
			else "没有可恢复的正式世界存档。"
		)
	if result.success:
		_last_summary = formal_simulation.world_summary()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		super._unhandled_key_input(event)
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		super._unhandled_key_input(event)
		return

	match key_event.keycode:
		KEY_E:
			_toggle_formal_economy_panel()
		KEY_P:
			_open_product_panel("politics")
		KEY_O:
			_open_product_panel("organization")
		KEY_M:
			_open_product_panel("military")
		KEY_C:
			_open_product_panel("city_status")
		KEY_F12:
			developer_mode_enabled = not developer_mode_enabled
			if developer_mode_enabled:
				economy_panel_open = false
				active_hud_panel = "provenance"
			elif active_hud_panel == "provenance":
				active_hud_panel = ""
			queue_redraw()
		KEY_F5:
			_save_formal_state_from_ui()
		KEY_F9:
			_load_formal_state_from_ui()
		_:
			super._unhandled_key_input(event)
			return

	get_viewport().set_input_as_handled()


func _draw() -> void:
	super._draw()
	_draw_formal_world_status()
	if economy_panel_open:
		_draw_formal_polity_panel()


func _draw_formal_world_status() -> void:
	var size := get_viewport_rect().size
	var rect := Rect2(330.0, size.y - 54.0, maxf(260.0, size.x - 660.0), 36.0)
	if not _formal_status.is_empty():
		_draw_label(
			Vector2(rect.position.x + 14.0, rect.position.y - 8.0),
			_ellipsize(_formal_status, 46),
			8,
			Color(0.91, 0.72, 0.43, 0.96)
		)
	_panel(
		rect,
		Color(0.018, 0.038, 0.043, 0.94),
		Color(0.70, 0.62, 0.39, 0.34)
	)
	var fulfillment := int(_last_summary.get("fulfillment_bp", 0))
	var text := "1900世界  历史政治单元 %d  Formal聚合经济 %d  背景政治单元 %d  满足 %.1f%%" % [
		int(_last_summary.get("world_political_unit_count", 0)),
		int(_last_summary.get("major_economy_count", 0)),
		int(_last_summary.get("background_polity_count", 0)),
		float(fulfillment) / 100.0,
	]
	_draw_label(
		rect.position + Vector2(14.0, 23.0),
		text,
		10,
		Color(0.88, 0.88, 0.77, 0.98)
	)
	_draw_button(
		Rect2(rect.end.x - 82.0, rect.position.y + 5.0, 72.0, 26.0),
		"政经 E",
		"formal_economy_toggle",
		true
	)


func _draw_formal_polity_panel() -> void:
	var size := get_viewport_rect().size
	var width := clampf(size.x * 0.30, 330.0, 430.0)
	var rect := Rect2(size.x - width - 18.0, 92.0, width, size.y - 170.0)
	_panel(
		rect,
		Color(0.014, 0.031, 0.037, 0.975),
		Color(0.78, 0.66, 0.38, 0.44)
	)
	_draw_formal_panel_header(rect)
	var selected_id := _selected_polity_entity_id()
	var polity := formal_simulation.polity_summary(selected_id)
	_draw_polity_content(rect, selected_id, polity)
	_draw_formal_panel_buttons(rect)


func _draw_formal_panel_header(rect: Rect2) -> void:
	_draw_label(
		rect.position + Vector2(20.0, 31.0),
		"FORMAL ECONOMY · AGGREGATE",
		17,
		Color(0.95, 0.88, 0.67, 1.0)
	)
	_draw_label(
		rect.position + Vector2(20.0, 54.0),
		"Owner: FormalWorldEconomyService · E1 product integration: NO",
		9,
		Color(0.76, 0.81, 0.78, 0.95)
	)


func _draw_polity_content(
	rect: Rect2, selected_id: String, polity: Dictionary
) -> void:
	var y := 86.0
	if polity.is_empty():
		_draw_label(
			rect.position + Vector2(20.0, y),
			"在半球上选择政治单元。",
			11
		)
		return
	_draw_label(
		rect.position + Vector2(20.0, y),
		str(polity.get("name_zh", polity.get("short_name_zh", selected_id))),
		14
	)
	y += 24.0
	var polity_lines: Array[String] = [
		"层级：%s" % str(polity.get("playability_tier_zh", "背景政治单元")),
		"地位：%s · %s" % [
			str(polity.get("status", "unknown")),
			str(polity.get("relationship", "")),
		],
	]
	var controller_id := str(polity.get("controller_id", ""))
	if not controller_id.is_empty():
		polity_lines.append("控制方：%s" % controller_id)
	y = _draw_panel_lines(
		rect,
		y,
		polity_lines,
		Color(0.82, 0.84, 0.78, 0.96),
		10
	)
	y += 5.0
	if bool(polity.get("has_detailed_economy", false)):
		_draw_detailed_economy(rect, y, polity.get("economy", {}) as Dictionary)
	else:
		_draw_background_polity_notice(rect, y)


func _draw_detailed_economy(
	rect: Rect2, y: float, country: Dictionary
) -> void:
	var totals := country.get("daily_totals", {}) as Dictionary
	var economy_lines: Array[String] = [
		"聚合经济目录序位：%d" % int(country.get("rank", 0)),
		"人口：%s" % _compact_integer(int(country.get("population", 0))),
		"人均产出锚：%d（2011国际元口径）" % int(
			country.get("income_per_capita", 0)
		),
		"城市化率：%.1f%%" % (
			float(country.get("urban_share_bp", 0)) / 100.0
		),
		"数据状态：%.1f%% · %s" % [
			float(country.get("overall_confidence_bp", 0)) / 100.0,
			str(country.get("admission_status", "bounded_estimate")),
		],
		"当日满足率：%.1f%%" % (
			float(totals.get("fulfillment_bp", 0)) / 100.0
		),
		"关联在途运输：%d" % int(country.get("active_shipments", 0)),
	]
	_draw_panel_lines(
		rect,
		y,
		economy_lines,
		Color(0.86, 0.87, 0.80, 0.98),
		10
	)


func _draw_background_polity_notice(rect: Rect2, y: float) -> void:
	_draw_label(
		rect.position + Vector2(20.0, y),
		"该单元属于背景世界：保留日期化政治边界；不运行Formal聚合经济。",
		9,
		Color(0.91, 0.70, 0.45, 0.98)
	)


func _draw_panel_lines(
	rect: Rect2,
	y: float,
	lines: Array[String],
	color: Color,
	font_size: int
) -> float:
	for line: String in lines:
		_draw_label(
			rect.position + Vector2(20.0, y),
			line,
			font_size,
			color
		)
		y += 19.0
	return y


func _draw_formal_panel_buttons(rect: Rect2) -> void:
	var button_y := rect.end.y - 38.0
	_draw_button(
		Rect2(rect.position.x + 18.0, button_y, 84.0, 26.0),
		"保存 F5",
		"formal_save",
		true
	)
	_draw_button(
		Rect2(rect.position.x + 110.0, button_y, 84.0, 26.0),
		"读取 F9",
		"formal_load",
		true
	)
	_draw_button(
		Rect2(rect.end.x - 88.0, button_y, 70.0, 26.0),
		"关闭",
		"formal_economy_toggle",
		true
	)
	if not _formal_status.is_empty():
		_draw_label(
			rect.position + Vector2(20.0, rect.size.y - 51.0),
			_formal_status,
			8,
			Color(0.72, 0.78, 0.72, 0.92)
		)


func _activate_button(action: String) -> void:
	match action:
		"product_session", "toggle_character_panel", "switch_character":
			_open_product_panel("session")
		"product_politics":
			_open_product_panel("politics")
		"product_organization":
			_open_product_panel("organization")
		"product_military", "toggle_history_war_layer":
			_open_product_panel("military")
		"product_city_status":
			_open_product_panel("city_status")
		"product_integration", "toggle_country_panel", "toggle_activity_panel", "mark_read":
			_open_product_panel("integration")
		"product_provenance":
			if developer_mode_enabled:
				_open_product_panel("provenance")
		"product_enable_provenance":
			developer_mode_enabled = true
			economy_panel_open = false
			active_hud_panel = "provenance"
			queue_redraw()
		"formal_economy_toggle":
			active_hud_panel = ""
			_toggle_formal_economy_panel()
		"formal_save":
			_save_formal_state_from_ui()
		"formal_load":
			_load_formal_state_from_ui()
		_:
			super._activate_button(action)


func _selected_polity_entity_id() -> String:
	if formal_simulation.has_polity(selected_country_id):
		return selected_country_id

	var home_id := _home_historical_entity_id()
	if formal_simulation.has_polity(home_id):
		return home_id

	if formal_simulation.has_polity("country_fra"):
		return "country_fra"

	return formal_simulation.first_polity_id()


func _compact_integer(value: int) -> String:
	if value >= 1000000000:
		return "%.2f十亿" % (float(value) / 1000000000.0)
	if value >= 1000000:
		return "%.2f百万" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1f千" % (float(value) / 1000.0)
	return str(value)
