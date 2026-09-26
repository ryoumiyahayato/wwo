class_name FormalWorldApplication
extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
## Formal product scene. The map consumes a projection of current runtime
## political identities; historical evidence remains available to history UI.

const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
const LAUNCH_WORLD_META: StringName = &"formal_world_launch_world"
const PACKAGED_PROBE_ARGUMENT: String = "--wwo-player-baseline-probe"
const PACKAGED_PROBE_ENTITY_ID: String = "state:country_fra"
const PACKAGED_PROBE_FLAG_ID: String = "france_tricolour_1794"
const TITLE_SCENE: String = "res://scenes/formal/formal_world_menu.tscn"
const WORKSPACE_PERSON: String = "person"
const WORKSPACE_ECONOMY: String = "economy"
const WORKSPACE_RELATIONS: String = "relations"
const WORKSPACE_ORGANIZATION: String = "organization"
const WORKSPACE_POLITICS: String = "politics"
const WORKSPACE_MILITARY: String = "military"
const WORKSPACE_MAP: String = "map"
const FORMAL_WORKSPACES: Array[Dictionary] = [
	{"id": WORKSPACE_PERSON, "label": "人物"},
	{"id": WORKSPACE_ECONOMY, "label": "工作/经济"},
	{"id": WORKSPACE_RELATIONS, "label": "关系/信息"},
	{"id": WORKSPACE_ORGANIZATION, "label": "组织"},
	{"id": WORKSPACE_POLITICS, "label": "政治"},
	{"id": WORKSPACE_MILITARY, "label": "军事"},
	{"id": WORKSPACE_MAP, "label": "地图/世界"},
]

var formal_simulation := FormalWorldSimulation.new()
var economy_panel_open: bool = true
var _formal_status: String = ""
var _last_summary: Dictionary = {}
var _packaged_probe_failures: int = 0
var _immutable_historical_evidence_report: Dictionary = {}
var _historical_evidence_surface_building: bool = false
var _player_context_cache: Dictionary = {}
var _formal_workspace: String = WORKSPACE_PERSON
var _system_menu_open: bool = false
var _organization_observation_cache: Dictionary = {}
var _defend_options_cache: Dictionary = {}

@onready var _background_cache_viewport: SubViewport = $BackgroundCacheViewport
@onready var _background_display: TextureRect = $Background


func _ready() -> void:
	_background_display.texture = _background_cache_viewport.get_texture()
	_resize_background_cache()
	var supplied_world: Variant = (
		get_tree().get_meta(LAUNCH_WORLD_META)
		if get_tree().has_meta(LAUNCH_WORLD_META)
		else null
	)
	if supplied_world is FormalWorldSimulation:
		formal_simulation = supplied_world as FormalWorldSimulation
	if get_tree().has_meta(LAUNCH_WORLD_META):
		get_tree().remove_meta(LAUNCH_WORLD_META)
	var formal_initialized := (
		formal_simulation.initialized or formal_simulation.initialize()
	)
	if formal_initialized:
		_refresh_player_context_cache()
		formal_simulation.state_changed.connect(_on_formal_state_changed)
		_dated_units_document = {
			"units": formal_simulation.historical_political_evidence_units(),
		}
		if not bind_historical_provenance_gate(formal_simulation.provenance_gate()):
			_data_errors.append("正式世界未能绑定 HistoricalProvenanceGate")
	_historical_evidence_surface_building = true
	super._ready()
	_historical_evidence_surface_building = false
	_immutable_historical_evidence_report = super.historical_evidence_report()
	if not formal_initialized:
		_formal_status = "正式世界初始化失败：%s" % formal_simulation.initialization_error
		_data_errors.append(_formal_status)
	else:
		var launch_mode := str(get_tree().get_meta(LAUNCH_MODE_META, "new"))
		if get_tree().has_meta(LAUNCH_MODE_META):
			get_tree().remove_meta(LAUNCH_MODE_META)
		if launch_mode == "load" and not supplied_world is FormalWorldSimulation:
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
		_refresh_player_context_cache()
	_refresh_shell_observations()
	sim_paused = true
	economy_panel_open = false
	_sync_political_presentation()
	_last_summary = formal_simulation.world_summary()
	queue_redraw()
	if PACKAGED_PROBE_ARGUMENT in OS.get_cmdline_user_args():
		_run_packaged_player_baseline_probe.call_deferred()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_resize_background_cache()


func _resize_background_cache() -> void:
	var size := get_viewport_rect().size
	var pixels := Vector2i(maxi(1, ceili(size.x)), maxi(1, ceili(size.y)))
	if _background_cache_viewport.size != pixels:
		_background_cache_viewport.size = pixels
	_background_cache_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _run_packaged_player_baseline_probe() -> void:
	await get_tree().process_frame
	_packaged_probe_require(formal_simulation.initialized, "正式模拟未初始化")
	_packaged_probe_require(_formal_workspace == WORKSPACE_PERSON, "正式产品未默认进入人物首页")
	_packaged_probe_require(shell_player_person_id() == formal_simulation.player_person_id(), "人物首页身份与PlayerState不一致")
	_packaged_probe_require(_data_errors.is_empty(), "正式模拟产生数据错误")
	_packaged_probe_require(_history_entity_by_id.size() == 146, "运行时政治实体数量不正确")
	_packaged_probe_require(
		formal_simulation.historical_evidence_view().record_count() == 151,
		"历史政治证据数量不正确"
	)
	_packaged_probe_require(_missing_flag_record_ids.is_empty(), "历史旗帜资源存在缺失")
	var evidence := historical_evidence_report()
	_packaged_probe_require(
		int(evidence.get("unresolved_flag_count", -1)) == 0,
		"历史旗帜证据仍未完全解析"
	)
	_packaged_probe_require(
		await _packaged_probe_click_action("formal_workspace:map"),
		"打包产品地图工作区入口不可点击"
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
	var france_flag_record := (
		_historical_flag_records.get(PACKAGED_PROBE_FLAG_ID, {}) as Dictionary
	)
	var france_flag_path := str(france_flag_record.get("asset_path", ""))
	var imported_france := imported_flags.get(PACKAGED_PROBE_FLAG_ID) as Texture2D
	print(
		"Historical flag runtime contract: path=%s exists=%s loaded_class=%s resource_path=%s"
		% [
			france_flag_path,
			ResourceLoader.exists(france_flag_path, "Texture2D"),
			imported_france.get_class() if imported_france != null else "null",
			str(imported_france.resource_path) if imported_france != null else "",
		]
	)
	_packaged_probe_require(
		imported_france != null and str(imported_france.resource_path) == france_flag_path,
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
		_refresh_player_context_cache()
		_sync_political_presentation()
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
		_refresh_player_context_cache()
		_sync_political_presentation()
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
		KEY_ESCAPE:
			if _system_menu_open:
				_system_menu_open = false
				queue_redraw()
			elif not active_hud_panel.is_empty() or info_open or economy_panel_open:
				active_hud_panel = ""
				info_open = false
				economy_panel_open = false
				queue_redraw()
			elif _formal_workspace != WORKSPACE_PERSON:
				set_formal_workspace(WORKSPACE_PERSON)
			else:
				super._unhandled_key_input(event)
				return
		KEY_E:
			if _formal_workspace == WORKSPACE_MAP:
				_toggle_formal_economy_panel()
			else:
				set_formal_workspace(WORKSPACE_ECONOMY)
		KEY_F5:
			_save_formal_state_from_ui()
		KEY_F9:
			_load_formal_state_from_ui()
		_:
			super._unhandled_key_input(event)
			return

	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _formal_workspace != WORKSPACE_MAP or _system_menu_open:
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
				_handle_button_click(button.position)
		accept_event()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			if _handle_button_click(button.position):
				accept_event()
				return
	if not active_hud_panel.is_empty() or info_open or economy_panel_open:
		if event is InputEventMouse or event is InputEventMouseMotion:
			accept_event()
			return
	super._gui_input(event)


func _draw() -> void:
	super._draw()
	if _formal_workspace == WORKSPACE_MAP:
		_draw_formal_world_status()
		if economy_panel_open:
			_draw_formal_polity_panel()
	else:
		_button_hits.clear()
		_draw_formal_shell_page()
	_draw_formal_navigation()
	if _system_menu_open:
		_draw_formal_system_menu()


func _on_formal_state_changed(change: Dictionary) -> void:
	if (
		bool(change.get("initialized", false))
		or bool(change.get("restored", false))
		or bool(change.get("player", false))
		or bool(change.get("economy", false))
	):
		_refresh_player_context_cache()
		_refresh_shell_observations()
		queue_redraw()


func _refresh_player_context_cache() -> void:
	_player_context_cache = (
		formal_simulation.player_context_view()
		if formal_simulation.initialized
		else {}
	)


func _refresh_shell_observations() -> void:
	if not formal_simulation.initialized:
		_organization_observation_cache = {}
		_defend_options_cache = {}
		return
	var organization_view := formal_simulation.organization_view()
	var responsibility_view := formal_simulation.organization_responsibility_view()
	_organization_observation_cache = {
		"organization_count": organization_view.organization_count(),
		"responsibility_count": responsibility_view.responsibility_count(),
		"responsibility_status_counts": responsibility_view.status_counts(),
		"responsibility_coverage": responsibility_view.coverage_summary(),
	}
	_defend_options_cache = formal_simulation.player_defend_options()


func formal_workspace_ids() -> Array[String]:
	var output: Array[String] = []
	for workspace: Dictionary in FORMAL_WORKSPACES:
		output.append(str(workspace.get("id", "")))
	return output


func formal_workspace_id() -> String:
	return _formal_workspace


func set_formal_workspace(workspace_id: String) -> bool:
	if not formal_workspace_ids().has(workspace_id):
		return false
	_formal_workspace = workspace_id
	active_hud_panel = ""
	info_open = false
	economy_panel_open = false
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	if workspace_id in [WORKSPACE_ORGANIZATION, WORKSPACE_MILITARY]:
		_refresh_shell_observations()
	queue_redraw()
	return true


func shell_player_person_id() -> String:
	return str(_player_context_cache.get("person_id", ""))


func formal_page_execution_actions() -> Array[String]:
	var actions: Array[String] = []
	if _formal_workspace == WORKSPACE_MILITARY:
		for option: Dictionary in _defend_options_cache.get("options", []) as Array:
			if bool(option.get("authorized", false)):
				actions.append("military.defend")
	return actions


func map_projection_revision() -> int:
	return _projection_revision


func formal_prototype_character_count() -> int:
	return _character_profiles.size()


func formal_system_menu_open() -> bool:
	return _system_menu_open


func player_card_person_id() -> String:
	return str(_player_context_cache.get("person_id", ""))


func character_detail_person_id() -> String:
	return str(_player_context_cache.get("person_id", ""))


func _draw_formal_world_status() -> void:
	var size := get_viewport_rect().size
	var rect := Rect2(330.0, size.y - 54.0, maxf(260.0, size.x - 660.0), 36.0)
	_panel(
		rect,
		Color(0.018, 0.038, 0.043, 0.94),
		Color(0.70, 0.62, 0.39, 0.34)
	)
	var fulfillment := int(_last_summary.get("fulfillment_bp", 0))
	var text := "1900世界  政治单元 %d  高细节经济 %d  核心可玩 %d  背景单元 %d  满足 %.1f%%" % [
		int(_last_summary.get("world_political_unit_count", 0)),
		int(_last_summary.get("major_economy_count", 0)),
		int(_last_summary.get("primary_playable_count", 0)),
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
		"正式世界政经",
		17,
		Color(0.95, 0.88, 0.67, 1.0)
	)
	_draw_label(
		rect.position + Vector2(20.0, 54.0),
		"146个运行时政治实体构成当前世界；151条历史证据保持只读。",
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
	for relation_value: Variant in polity.get("authority_relations", []) as Array:
		if relation_value is Dictionary:
			polity_lines.append(
				_authority_relation_label(relation_value as Dictionary)
			)
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
		"主要政权序位：%d" % int(country.get("rank", 0)),
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
		"该单元属于背景世界：保留身份、来源元数据与经济映射，不运行高细节经济。",
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


func _draw_formal_navigation() -> void:
	var nav_rect := Rect2(0.0, 0.0, size.x, 62.0)
	_remove_hits_under(nav_rect)
	draw_rect(nav_rect, Color(0.010, 0.025, 0.030, 0.985))
	draw_line(Vector2(0.0, 61.0), Vector2(size.x, 61.0), Color(0.72, 0.62, 0.36, 0.38), 1.0)
	_draw_label(Vector2(20.0, 25.0), "1900", 19, Color(0.96, 0.86, 0.61, 1.0))
	_draw_label(Vector2(20.0, 46.0), "FORMAL PERSON", 8, Color(0.60, 0.72, 0.68, 0.9))
	var x := 130.0
	for workspace: Dictionary in FORMAL_WORKSPACES:
		var workspace_id := str(workspace.get("id", ""))
		var rect := Rect2(x, 14.0, 112.0, 34.0)
		var active := workspace_id == _formal_workspace
		_panel(
			rect,
			Color(0.15, 0.13, 0.075, 0.96) if active else Color(0.035, 0.06, 0.062, 0.94),
			Color(0.88, 0.72, 0.38, 0.72) if active else Color(0.52, 0.54, 0.39, 0.28)
		)
		_register_hit(rect, "formal_workspace:%s" % workspace_id, true)
		_draw_label(rect.position + Vector2(12.0, 22.0), str(workspace.get("label", workspace_id)), 11)
		x += 118.0
	_draw_button(Rect2(size.x - 102.0, 14.0, 82.0, 34.0), "系统", "formal_system_toggle", true)


func _remove_hits_under(cover: Rect2) -> void:
	var retained: Array[Dictionary] = []
	for hit: Dictionary in _button_hits:
		var rect := hit.get("rect", Rect2()) as Rect2
		if not rect.intersects(cover, true):
			retained.append(hit)
	_button_hits = retained


func _draw_formal_shell_page() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.020, 0.024, 1.0))
	var content := Rect2(24.0, 82.0, size.x - 48.0, size.y - 106.0)
	_panel(content, Color(0.016, 0.037, 0.042, 0.99), Color(0.70, 0.61, 0.36, 0.32))
	match _formal_workspace:
		WORKSPACE_PERSON:
			_draw_person_workspace(content)
		WORKSPACE_ECONOMY:
			_draw_economy_workspace(content)
		WORKSPACE_RELATIONS:
			_draw_relations_workspace(content)
		WORKSPACE_ORGANIZATION:
			_draw_organization_workspace(content)
		WORKSPACE_POLITICS:
			_draw_politics_workspace(content)
		WORKSPACE_MILITARY:
			_draw_military_workspace(content)
	_draw_shell_footer(content)


func _draw_workspace_heading(rect: Rect2, title: String, subtitle: String) -> void:
	_draw_label(rect.position + Vector2(28.0, 42.0), title, 23, Color(0.96, 0.88, 0.67, 1.0))
	_draw_label(rect.position + Vector2(28.0, 68.0), subtitle, 10, Color(0.67, 0.77, 0.73, 0.96))
	draw_line(rect.position + Vector2(28.0, 84.0), Vector2(rect.end.x - 28.0, rect.position.y + 84.0), Color(0.64, 0.56, 0.33, 0.26), 1.0)


func _draw_person_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "人物首页", "同一 FormalWorldSimulation · 同一 player_person_id · 初始暂停")
	var label := str(_player_context_cache.get("display_label", "正式人物不可用"))
	var person_id := str(_player_context_cache.get("person_id", ""))
	var place := _player_context_cache.get("current_place", {}) as Dictionary
	var source := _player_context_cache.get("population_source", {}) as Dictionary
	var demographic := _player_context_cache.get("demographic_identity", {}) as Dictionary
	var memberships := _player_context_cache.get("memberships", []) as Array
	var appointments := _player_context_cache.get("appointments", []) as Array
	var provenance := _player_context_cache.get("provenance_summary", {}) as Dictionary
	_draw_label(rect.position + Vector2(38.0, 128.0), label, 28, Color(0.94, 0.79, 0.47, 1.0))
	var birth_year := int(demographic.get("birth_year", 0))
	var current_year := int(formal_simulation.date_time().get("year", 1900))
	var facts: Array[String] = [
		"状态：%s" % ("存活" if bool(_player_context_cache.get("alive", false)) else "非存活"),
		"出生年 / 约龄：%s / %s" % [str(birth_year) if birth_year > 0 else "不可用", str(current_year - birth_year) if birth_year > 0 else "不可用"],
		"当前地点：%s · %s" % [str(place.get("name", "不可用")), str(place.get("id", ""))],
		"人口来源：%s" % str(source.get("id", "不可用")),
		"正式 membership：%d · appointment：%d" % [memberships.size(), appointments.size()],
	]
	_draw_shell_lines(rect.position + Vector2(38.0, 166.0), facts, 22.0)
	var right := rect.position + Vector2(rect.size.x * 0.54, 122.0)
	_draw_label(right, "来源与正式身份", 15, Color(0.86, 0.87, 0.76, 1.0))
	_draw_shell_lines(right + Vector2(0.0, 32.0), [
		"技术 ID：%s" % person_id,
		"来源类型：%s" % str(provenance.get("kind", "不可用")),
		"规则版本：%s" % str(provenance.get("generation_rules_version", "不可用")),
		"接受候选序号：%s" % str(provenance.get("accepted_draft_index", "不可用")),
	], 22.0, 10, Color(0.72, 0.80, 0.76, 0.96))
	_draw_unavailable_notice(rect, "姓名、职业、技能、健康、工资、关系、个人计划：当前版本尚未模拟")


func _draw_economy_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "工作 / 经济", "个人工作与地区聚合经济严格分离")
	var economic := _player_context_cache.get("economic_observation", {}) as Dictionary
	_draw_label(rect.position + Vector2(38.0, 126.0), "个人工作", 17, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(rect.position + Vector2(38.0, 158.0), [
		"Employment owner：unavailable",
		"职业、雇佣合同、工资、个人现金：当前版本尚未模拟",
		"聚合人口或国库不会被解释为这个人的工资或财富。",
	], 24.0)
	var right := rect.position + Vector2(rect.size.x * 0.54, 126.0)
	_draw_label(right, "地区 / 聚合经济观察", 17, Color(0.91, 0.82, 0.58, 1.0))
	if bool(economic.get("available", false)):
		var totals := economic.get("daily_totals", {}) as Dictionary
		_draw_shell_lines(right + Vector2(0.0, 32.0), [
			"经济聚合：%s" % str(economic.get("economy_entity_id", "")),
			"聚合人口：%s" % _compact_integer(int(economic.get("population", 0))),
			"当日满足率：%.1f%%" % (float(totals.get("fulfillment_bp", 0)) / 100.0),
			"证据状态：%s" % str(economic.get("admission_status", "")),
		], 24.0)
	else:
		_draw_shell_lines(right + Vector2(0.0, 32.0), ["地区经济观察不可用：%s" % str(economic.get("reason", "unavailable"))], 24.0)
	_draw_unavailable_notice(rect, "地区 GDP、国库与市场人口都不是个人事实")


func _draw_relations_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "关系 / 信息", "能力边界与真实世界资料入口")
	_draw_label(rect.position + Vector2(38.0, 130.0), "当前 Formal 世界没有人物关系图或私人收件箱 owner。", 16)
	_draw_shell_lines(rect.position + Vector2(38.0, 172.0), [
		"好友：当前版本尚未模拟（不显示伪造的 0）",
		"私人消息：当前版本尚未模拟（不显示固定未读数）",
		"联系人 / 约见 / 发消息：没有 Formal 命令端口",
		"Organization Responsibility 仅作为机构 / 世界观察。",
		"机构观察记录：%d" % int(_organization_observation_cache.get("responsibility_count", 0)),
	], 28.0)
	_draw_unavailable_notice(rect, "此页面没有“标记已读”、发消息或约见按钮")


func _draw_organization_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "组织", "人物的真实 membership / appointment 与世界组织观察")
	var memberships := _player_context_cache.get("memberships", []) as Array
	var appointments := _player_context_cache.get("appointments", []) as Array
	_draw_label(rect.position + Vector2(38.0, 126.0), "我的正式记录", 17, Color(0.91, 0.82, 0.58, 1.0))
	var records: Array[String] = []
	for membership: Dictionary in memberships:
		records.append("成员 · %s" % str(membership.get("organization_id", "")))
	for appointment: Dictionary in appointments:
		records.append("任职 · %s / %s" % [str(appointment.get("organization_id", "")), str(appointment.get("position_id", ""))])
	if records.is_empty():
		records.append("暂无正式组织任职记录")
	_draw_shell_lines(rect.position + Vector2(38.0, 160.0), records.slice(0, 8), 24.0)
	var right := rect.position + Vector2(rect.size.x * 0.56, 126.0)
	_draw_label(right, "世界组织 / Responsibility", 17, Color(0.91, 0.82, 0.58, 1.0))
	var counts := _organization_observation_cache.get("responsibility_status_counts", {}) as Dictionary
	_draw_shell_lines(right + Vector2(0.0, 34.0), [
		"世界组织：%d" % int(_organization_observation_cache.get("organization_count", 0)),
		"责任观察：%d" % int(_organization_observation_cache.get("responsibility_count", 0)),
		"monitoring：%d" % int(counts.get("monitoring", 0)),
		"attention required：%d" % int(counts.get("attention_required", 0)),
	], 24.0)
	_draw_unavailable_notice(rect, "没有加入组织、升职、任命或工资命令；无任职不等于失业")


func _draw_politics_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "政治", "所在地与地图选择是观察上下文，不是玩家身份")
	var home := _player_context_cache.get("political_observation", {}) as Dictionary
	var selected := formal_simulation.polity_summary(_selected_polity_entity_id())
	_draw_label(rect.position + Vector2(38.0, 126.0), "所在地相关 polity", 17, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(rect.position + Vector2(38.0, 160.0), [
		"%s" % str(home.get("name_zh", "不可用")),
		"runtime：%s" % str(home.get("runtime_entity_id", "")),
		"source：%s" % str(home.get("source_entity_id", "")),
		"状态：%s · %s" % [str(home.get("status", "")), str(home.get("relationship", ""))],
	], 24.0)
	var right := rect.position + Vector2(rect.size.x * 0.56, 126.0)
	_draw_label(right, "当前地图观察对象", 17, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(right + Vector2(0.0, 34.0), [
		"%s" % str(selected.get("name_zh", selected.get("short_name_zh", "尚未选择"))),
		"ID：%s" % _selected_polity_entity_id(),
		"状态：%s" % str(selected.get("status", "")),
		"authority relations：%d" % (selected.get("authority_relations", []) as Array).size(),
	], 24.0)
	_draw_unavailable_notice(rect, "政策、投票、政变、革命和直接控制国家：当前版本没有人物命令")


func _draw_military_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "军事", "仅显示当前玩家可证明的 DEFEND acting context")
	_draw_label(rect.position + Vector2(38.0, 126.0), "acting person：%s" % str(_defend_options_cache.get("acting_person_id", "")), 13)
	var options := _defend_options_cache.get("options", []) as Array
	var y := 166.0
	var authorized_count := 0
	for index: int in range(options.size()):
		var option := options[index] as Dictionary
		if not bool(option.get("authorized", false)):
			continue
		authorized_count += 1
		_draw_label(rect.position + Vector2(38.0, y), "%s · AUTHORIZED" % str(option.get("formation_id", "")), 12, Color(0.72, 0.88, 0.73, 1.0))
		_draw_button(Rect2(rect.end.x - 168.0, rect.position.y + y - 22.0, 126.0, 28.0), "DEFEND 24h", "formal_defend:%d" % index, true)
		y += 38.0
	if authorized_count == 0:
		_draw_label(rect.position + Vector2(38.0, y), "当前没有可执行的 DEFEND。", 17, Color(0.91, 0.70, 0.45, 1.0))
		y += 36.0
		for reason: Variant in _defend_options_cache.get("unavailable_reasons", []) as Array:
			_draw_label(rect.position + Vector2(52.0, y), "— %s" % str(reason), 11, Color(0.72, 0.78, 0.74, 0.96))
			y += 22.0
	_draw_unavailable_notice(rect, "默认生产世界没有 formation 与 grant；不会注入 commander / army_test fixture")


func _draw_shell_lines(
	position: Vector2,
	lines: Array[String],
	line_height: float = 23.0,
	font_size: int = 11,
	color: Color = Color(0.84, 0.86, 0.79, 0.98)
) -> void:
	var y := position.y
	for line: String in lines:
		_draw_label(Vector2(position.x, y), line, font_size, color)
		y += line_height


func _draw_unavailable_notice(rect: Rect2, text: String) -> void:
	var notice := Rect2(rect.position.x + 28.0, rect.end.y - 78.0, rect.size.x - 56.0, 38.0)
	_panel(notice, Color(0.07, 0.055, 0.028, 0.72), Color(0.75, 0.58, 0.28, 0.28))
	_draw_label(notice.position + Vector2(14.0, 24.0), text, 10, Color(0.92, 0.76, 0.47, 0.98))


func _draw_shell_footer(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(28.0, rect.size.y - 14.0), "%s · %s · %s" % [_format_sim_datetime(), "已暂停" if sim_paused else "%d×运行" % sim_speed, _formal_status], 9, Color(0.60, 0.70, 0.67, 0.9))


func _draw_formal_system_menu() -> void:
	_button_hits.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.58))
	var rect := Rect2(size.x * 0.5 - 190.0, size.y * 0.5 - 166.0, 380.0, 332.0)
	_panel(rect, Color(0.012, 0.030, 0.035, 0.995), Color(0.82, 0.68, 0.37, 0.68))
	_draw_label(rect.position + Vector2(28.0, 42.0), "系统", 22, Color(0.96, 0.86, 0.62, 1.0))
	_draw_button(Rect2(rect.position + Vector2(28.0, 72.0), Vector2(324.0, 42.0)), "Save", "formal_save", true)
	_draw_button(Rect2(rect.position + Vector2(28.0, 122.0), Vector2(324.0, 42.0)), "Load", "formal_load", true)
	_draw_button(Rect2(rect.position + Vector2(28.0, 172.0), Vector2(324.0, 42.0)), "Back to Title", "formal_back_title", true)
	_draw_button(Rect2(rect.position + Vector2(28.0, 222.0), Vector2(324.0, 42.0)), "Quit", "formal_quit", true)
	_draw_button(Rect2(rect.position + Vector2(248.0, 280.0), Vector2(104.0, 28.0)), "关闭 Esc", "formal_system_toggle", true)


func _activate_button(action: String) -> void:
	match action:
		"formal_economy_toggle":
			_toggle_formal_economy_panel()
		"formal_save":
			_save_formal_state_from_ui()
		"formal_load":
			_load_formal_state_from_ui()
		"formal_system_toggle":
			_system_menu_open = not _system_menu_open
			queue_redraw()
		"formal_back_title":
			get_tree().change_scene_to_file(TITLE_SCENE)
		"formal_quit":
			get_tree().quit(0)
		"switch_character", "mark_read":
			# Formal identity is changed only by PlayerState-backed product flows.
			return
		_:
			if action.begins_with("formal_workspace:"):
				set_formal_workspace(action.trim_prefix("formal_workspace:"))
			elif action.begins_with("formal_defend:"):
				_execute_formal_defend(action.trim_prefix("formal_defend:").to_int())
			else:
				super._activate_button(action)


func _execute_formal_defend(option_index: int) -> void:
	var options := _defend_options_cache.get("options", []) as Array
	if option_index < 0 or option_index >= options.size():
		_formal_status = "DEFEND 选项已失效。"
		queue_redraw()
		return
	var option := options[option_index] as Dictionary
	var result := formal_simulation.player_defend_formation(
		option.get("acting_context", {}) as Dictionary,
		str(option.get("formation_id", "")),
		24
	)
	_formal_status = (
		"DEFEND 已通过 Formal 权限端口提交。"
		if bool(result.get("success", false))
		else "DEFEND 被拒绝：%s / %s" % [str(result.get("status", "")), str(result.get("authority_status", ""))]
	)
	_refresh_shell_observations()
	queue_redraw()


func _read_document(path: String) -> Dictionary:
	if path.get_file() == "characters.json" and path.contains("/world_map/"):
		# The file remains an isolated prototype fixture. Formal presentation never
		# opens it or treats its profiles as player facts.
		return {"identities": {}}
	return super._read_document(path)


func _seed_world_events() -> void:
	# Prototype institution agendas are not a personal inbox.
	_world_events.clear()
	_event_by_id.clear()
	activity_unread = 0


func _draw_corners() -> void:
	var compact: bool = size.x < 940.0 or size.y < 620.0
	var left_width: float = minf(284.0, size.x * 0.42)
	var right_width: float = minf(282.0, size.x * 0.42)
	var top_height: float = 56.0 if compact else 66.0
	var bottom_height: float = 58.0 if compact else 70.0
	var top_y := 74.0 if _formal_workspace == WORKSPACE_MAP else 18.0
	var country_rect := Rect2(18.0, top_y, left_width, top_height)
	var time_rect := Rect2(
		size.x - right_width - 18.0, top_y, right_width, top_height
	)
	var character_rect := Rect2(
		18.0, size.y - bottom_height - 18.0, left_width, bottom_height
	)
	var activity_rect := Rect2(
		size.x - right_width - 18.0,
		size.y - bottom_height - 18.0,
		right_width,
		bottom_height
	)
	_draw_corner(
		country_rect,
		_formal_home_polity_name(),
		"所在地相关政治观察",
		"toggle_country_panel",
		Color(0.72, 0.64, 0.38, 0.22),
		compact
	)
	_draw_corner(
		character_rect,
		_active_character_name(),
		_active_character_position(),
		"toggle_character_panel",
		Color(0.72, 0.64, 0.38, 0.22),
		compact
	)
	_draw_corner(
		activity_rect,
		"机构 / 世界观察",
		"个人消息当前版本尚未模拟",
		"toggle_activity_panel",
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
	var button_y: float = time_rect.end.y - 28.0
	_draw_button(
		Rect2(time_rect.position.x + 10.0, button_y, 44.0, 22.0),
		"Ⅱ" if sim_paused else "▶",
		"toggle_pause",
		true
	)
	_draw_button(
		Rect2(time_rect.position.x + 60.0, button_y, 38.0, 22.0),
		"1×", "speed:1", true
	)
	_draw_button(
		Rect2(time_rect.position.x + 102.0, button_y, 38.0, 22.0),
		"2×", "speed:2", true
	)
	_draw_button(
		Rect2(time_rect.position.x + 144.0, button_y, 38.0, 22.0),
		"4×", "speed:4", true
	)


func _draw_breadcrumbs() -> void:
	if _formal_workspace != WORKSPACE_MAP:
		super._draw_breadcrumbs()
		return
	_draw_label(Vector2(24.0, 160.0), _ellipsize(_breadcrumb_text(), 68), 13, Color(0.76, 0.82, 0.78, 1.0))
	if space_level != WORLD:
		_draw_button(Rect2(24.0, 176.0, 92.0, 30.0), "返回上层", "back", true)
		_draw_button(Rect2(126.0, 176.0, 92.0, 30.0), "返回世界", "world", true)


func _draw_character_panel(rect: Rect2) -> void:
	if not bool(_player_context_cache.get("available", false)):
		_draw_label(rect.position + Vector2(24.0, 42.0), "正式玩家上下文不可用", 19)
		_draw_label(
			rect.position + Vector2(24.0, 76.0),
			str(_player_context_cache.get("reason", "player_person_unavailable")),
			11,
			Color(0.91, 0.70, 0.45, 0.98)
		)
		return
	var person_id := str(_player_context_cache.get("person_id", ""))
	var place := _player_context_cache.get("current_place", {}) as Dictionary
	var demographic := (
		_player_context_cache.get("demographic_identity", {}) as Dictionary
	)
	var source := _player_context_cache.get("population_source", {}) as Dictionary
	var memberships := _player_context_cache.get("memberships", []) as Array
	var appointments := _player_context_cache.get("appointments", []) as Array
	_draw_label(
		rect.position + Vector2(24.0, 38.0),
		str(_player_context_cache.get("display_label", "正式人物")),
		20
	)
	_draw_label(
		rect.position + Vector2(24.0, 68.0),
		"正式玩家 · %s" % ("存活" if bool(
			_player_context_cache.get("alive", false)
		) else "非存活"),
		13
	)
	_draw_label(
		rect.position + Vector2(24.0, 98.0),
		"所在地：%s（%s）" % [
			str(place.get("name", "不可用")), str(place.get("id", ""))
		],
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 126.0),
		"人口来源：%s · 出生年：%s" % [
			str(source.get("id", "不可用")),
			str(demographic.get("birth_year", "不可用")),
		],
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 154.0),
		"正式成员记录：%d · 正式任命记录：%d" % [
			memberships.size(), appointments.size()
		],
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 184.0),
		"姓名、职业、工资、健康、关系、技能、私人消息：当前版本尚未模拟",
		11,
		Color(0.91, 0.70, 0.45, 0.98)
	)
	_draw_label(
		rect.position + Vector2(24.0, rect.end.y - 26.0),
		"技术身份：%s" % person_id,
		9,
		Color(0.68, 0.75, 0.72, 0.92)
	)


func _draw_country_panel(rect: Rect2) -> void:
	var political := (
		_player_context_cache.get("political_observation", {}) as Dictionary
	)
	var home_entity_id := str(political.get("polity_id", ""))
	var selected_entity_id := selected_country_id
	_draw_label(
		rect.position + Vector2(24.0, 38.0),
		str(political.get("name", "所在地政治观察不可用")),
		20
	)
	_draw_label(
		rect.position + Vector2(24.0, 72.0),
		"所在地关联实体：%s" % (home_entity_id if not home_entity_id.is_empty() else "不可用"),
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 102.0),
		"当前观察对象：%s" % (
			selected_entity_id if not selected_entity_id.is_empty() else "尚未选择"
		),
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 132.0),
		"地图选择只改变观察对象，不改变玩家、人口 claim 或所在地。",
		11,
		Color(0.91, 0.70, 0.45, 0.98)
	)
	_draw_label(
		rect.position + Vector2(24.0, 162.0),
		"政策命令与人物政治行动：当前版本尚未模拟",
		11,
		Color(0.73, 0.82, 0.78, 1.0)
	)


func home_country_detail_report() -> Dictionary:
	var home_entity_id := _home_historical_entity_id()
	return {
		"player_person_id": formal_simulation.player_person_id(),
		"home_entity_id": home_entity_id,
		"selected_entity_id": selected_country_id,
		"selected_is_home": selected_country_id == home_entity_id,
	}


func _draw_activity_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 40.0), "关系 / 信息能力", 19)
	_draw_label(
		rect.position + Vector2(24.0, 78.0),
		"当前 Formal 世界没有人物关系图或私人收件箱 owner。",
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 108.0),
		"因此不显示假联系人、假未读数或“标记已读”操作。",
		12,
		Color(0.91, 0.70, 0.45, 0.98)
	)
	_draw_label(
		rect.position + Vector2(24.0, 146.0),
		"Organization Responsibility 仅作为机构 / 世界观察。",
		11,
		Color(0.73, 0.82, 0.78, 1.0)
	)


func _draw_city_characters(rect: Rect2) -> void:
	if not bool(_player_context_cache.get("available", false)):
		return
	var place := _player_context_cache.get("current_place", {}) as Dictionary
	if str(place.get("map_id", "")) != selected_city_id:
		return
	var badge := Rect2(
		rect.position.x + 34.0, rect.end.y - 54.0, 280.0, 30.0
	)
	_panel(
		badge,
		Color(0.07, 0.10, 0.095, 0.88),
		Color(0.54, 0.70, 0.63, 0.34)
	)
	_draw_label(
		badge.position + Vector2(10.0, 20.0),
		"%s · 正式玩家" % str(
			_player_context_cache.get("display_label", "正式人物")
		),
		11
	)


func _switch_character() -> void:
	# Runtime identity switching is intentionally unavailable in Formal v1.
	return


func _active_character_name() -> String:
	return str(_player_context_cache.get("display_label", "正式人物不可用"))


func _active_character_position() -> String:
	var place := _player_context_cache.get("current_place", {}) as Dictionary
	if not bool(place.get("available", false)):
		return "所在地不可用"
	return "正式玩家 · %s" % str(place.get("name", place.get("id", "")))


func _activity_summary() -> String:
	return "个人关系与消息当前版本尚未模拟"


func _formal_home_polity_name() -> String:
	var observation := (
		_player_context_cache.get("political_observation", {}) as Dictionary
	)
	if bool(observation.get("available", false)):
		return str(observation.get("name_zh", "所在地政治观察"))
	return "所在地政治观察不可用"


func _home_historical_entity_id() -> String:
	var observation := (
		_player_context_cache.get("political_observation", {}) as Dictionary
	)
	return str(observation.get("runtime_entity_id", ""))


func _selected_polity_entity_id() -> String:
	if formal_simulation.has_polity(selected_country_id):
		return selected_country_id

	var home_id := _home_historical_entity_id()
	if not home_id.begins_with("state:"):
		home_id = formal_simulation.political_registry_view().runtime_id_for_source(
			home_id
		)
	if formal_simulation.has_polity(home_id):
		return home_id

	if formal_simulation.has_polity("state:country_fra"):
		return "state:country_fra"

	return formal_simulation.first_polity_id()


func _rebuild_historical_political_world() -> void:
	if (
		_historical_evidence_surface_building
		or not formal_simulation.initialized
	):
		super._rebuild_historical_political_world()
		return
	var historical_document := _dated_units_document
	_dated_units_document = {
		"units": formal_simulation.current_world_political_units(),
	}
	super._rebuild_historical_political_world()
	_dated_units_document = historical_document


func _sync_political_presentation() -> void:
	if not formal_simulation.initialized:
		return
	var previous_selection := selected_country_id
	_rebuild_historical_political_world()
	if formal_simulation.has_polity(previous_selection):
		selected_country_id = previous_selection
	else:
		selected_country_id = ""
		hover_country_id = ""
		selected_historical_territory_iso = ""
	_mark_projection_dirty()
	queue_redraw()


func historical_evidence_report() -> Dictionary:
	if _immutable_historical_evidence_report.is_empty():
		return super.historical_evidence_report()
	return _immutable_historical_evidence_report.duplicate(true)


func _authority_relation_label(relation: Dictionary) -> String:
	var relation_names := {
		"administration": "行政关系",
		"occupation": "占领关系",
		"protection": "保护关系",
		"legacy_controller": "历史兼容关系",
	}
	var relation_type := str(relation.get("relation_type", ""))
	return "%s：%s → %s（%s 至 %s）" % [
		str(relation_names.get(relation_type, relation_type)),
		str(relation.get("source_runtime_id", "")),
		str(relation.get("target_runtime_id", "")),
		str(relation.get("valid_from", "")),
		str(relation.get("valid_to", "")),
	]


func _compact_integer(value: int) -> String:
	if value >= 1000000000:
		return "%.2f十亿" % (float(value) / 1000000000.0)
	if value >= 1000000:
		return "%.2f百万" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1f千" % (float(value) / 1000.0)
	return str(value)
