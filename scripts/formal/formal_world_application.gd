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
const ECONOMY_TAB_OVERVIEW: String = "overview"
const ECONOMY_TAB_MARKETS: String = "markets"
const ECONOMY_TAB_COMMODITIES: String = "commodities"
const ECONOMY_TAB_SHORTAGES: String = "shortages"
const ECONOMY_TAB_TRANSPORT: String = "transport"
const ECONOMY_TABS: Array[Dictionary] = [
	{"id": ECONOMY_TAB_OVERVIEW, "label": "Overview"},
	{"id": ECONOMY_TAB_MARKETS, "label": "Markets"},
	{"id": ECONOMY_TAB_COMMODITIES, "label": "Commodities"},
	{"id": ECONOMY_TAB_SHORTAGES, "label": "Shortages"},
	{"id": ECONOMY_TAB_TRANSPORT, "label": "Transport"},
]
const POLITICS_TAB_LOCAL: String = "local"
const POLITICS_TAB_OBSERVED: String = "observed"
const POLITICS_TAB_COMPARE: String = "compare"
const POLITICS_TABS: Array[Dictionary] = [
	{"id": POLITICS_TAB_LOCAL, "label": "Local"},
	{"id": POLITICS_TAB_OBSERVED, "label": "Observed"},
	{"id": POLITICS_TAB_COMPARE, "label": "Local vs Observed"},
]
const ORGANIZATION_TAB_MY_RECORDS: String = "my_records"
const ORGANIZATION_TAB_BROWSER: String = "organizations"
const ORGANIZATION_TAB_RESPONSIBILITY: String = "responsibility"
const ORGANIZATION_TABS: Array[Dictionary] = [
	{"id": ORGANIZATION_TAB_MY_RECORDS, "label": "My Records"},
	{"id": ORGANIZATION_TAB_BROWSER, "label": "Organizations"},
	{"id": ORGANIZATION_TAB_RESPONSIBILITY, "label": "Responsibility"},
]
const MAP_MODE_POLITICAL: String = "political"
const MAP_MODE_FULFILLMENT: String = "economy_fulfillment"
const MAP_MODE_SHORTAGE: String = "economy_shortage"
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
var _defend_options_cache: Dictionary = {}
var _economy_tab: String = ECONOMY_TAB_OVERVIEW
var _economy_observation_dirty: bool = true
var _economy_catalog_cache: Dictionary = {}
var _commodity_catalog_cache: Dictionary = {}
var _selected_market_cache: Dictionary = {}
var _commodity_rows_cache: Array[Dictionary] = []
var _shortage_observation_cache: Dictionary = {}
var _shortage_rows_cache: Array[Dictionary] = []
var _transport_observation_cache: Dictionary = {}
var _observed_market_id: String = ""
var _market_page: int = 0
var _commodity_page: int = 0
var _shortage_page: int = 0
var _transport_page: int = 0
var _commodity_search: String = ""
var _commodity_sort: String = "unmet"
var _shortage_sort: String = "unmet"
var _economy_refresh_count: int = 0
var _map_observation_mode: String = MAP_MODE_POLITICAL
var _economy_overlay_cache: Dictionary = {}
var _politics_tab: String = POLITICS_TAB_COMPARE
var _local_political_observation_cache: Dictionary = {}
var _observed_political_observation_cache: Dictionary = {}
var _organization_tab: String = ORGANIZATION_TAB_MY_RECORDS
var _organization_catalog_cache: Dictionary = {}
var _player_organization_cache: Dictionary = {}
var _organization_detail_cache: Dictionary = {}
var _organization_responsibility_cache: Dictionary = {}
var _selected_organization_id: String = ""
var _organization_page: int = 0
var _responsibility_page: int = 0
var _organization_refresh_count: int = 0

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
		_economy_observation_dirty = true
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
		_economy_observation_dirty = true
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
	if (
		_formal_workspace == WORKSPACE_ECONOMY
		and _economy_tab == ECONOMY_TAB_COMMODITIES
		and key_event.keycode not in [KEY_ESCAPE, KEY_F5, KEY_F9]
	):
		if key_event.keycode == KEY_BACKSPACE:
			_commodity_search = _commodity_search.left(maxi(0, _commodity_search.length() - 1))
		elif key_event.keycode == KEY_DELETE:
			_commodity_search = ""
		elif key_event.unicode >= 32 and not key_event.ctrl_pressed and not key_event.alt_pressed and not key_event.meta_pressed:
			_commodity_search = (_commodity_search + char(key_event.unicode)).left(32)
		else:
			super._unhandled_key_input(event)
			return
		_rebuild_commodity_rows_cache()
		queue_redraw()
		get_viewport().set_input_as_handled()
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
	var selection_before := selected_country_id
	super._gui_input(event)
	if selected_country_id != selection_before:
		var mapped_market := formal_simulation.market_id_for_polity(
			_selected_polity_entity_id()
		)
		if not mapped_market.is_empty():
			_observed_market_id = mapped_market
			if _formal_workspace == WORKSPACE_ECONOMY:
				_refresh_selected_market()
		_refresh_political_observations()
		queue_redraw()


func _draw() -> void:
	super._draw()
	if _formal_workspace == WORKSPACE_MAP:
		_draw_formal_world_status()
		_draw_economy_map_controls()
		if economy_panel_open:
			_draw_formal_polity_panel()
	else:
		_button_hits.clear()
		_draw_formal_shell_page()
	_draw_formal_navigation()
	if _system_menu_open:
		_draw_formal_system_menu()


func _draw_country_flag_skins() -> void:
	if _map_observation_mode == MAP_MODE_POLITICAL:
		super._draw_country_flag_skins()


func _political_fill_color(entity_id: String, alpha: float) -> Color:
	if _map_observation_mode == MAP_MODE_POLITICAL:
		return super._political_fill_color(entity_id, alpha)
	var values := _economy_overlay_cache.get("values_by_polity_id", {}) as Dictionary
	var observation := values.get(entity_id, {}) as Dictionary
	if observation.is_empty():
		return Color(0.22, 0.27, 0.27, minf(alpha, 0.72))
	var normalized := float(observation.get("normalized_bp", 0)) / 10000.0
	if _map_observation_mode == MAP_MODE_FULFILLMENT:
		var fulfillment := float(observation.get("value", 0.0)) / 10000.0
		var color := Color(0.66, 0.20, 0.13).lerp(Color(0.18, 0.68, 0.49), clampf(fulfillment, 0.0, 1.0))
		color.a = minf(alpha, 0.84)
		return color
	var shortage_color := Color(0.24, 0.48, 0.45).lerp(Color(0.82, 0.24, 0.12), normalized)
	shortage_color.a = minf(alpha, 0.84)
	return shortage_color


func _draw_economy_map_controls() -> void:
	var rect := Rect2(324.0, 72.0, 632.0, 45.0)
	_panel(rect, Color(0.012, 0.031, 0.035, 0.95), Color(0.67, 0.58, 0.34, 0.36))
	var options: Array[Dictionary] = [
		{"id": MAP_MODE_POLITICAL, "label": "Political"},
		{"id": MAP_MODE_FULFILLMENT, "label": "Economy Fulfillment"},
		{"id": MAP_MODE_SHORTAGE, "label": "Economy Shortage"},
	]
	var x := rect.position.x + 8.0
	for option: Dictionary in options:
		var mode_id := str(option.get("id", ""))
		var width := 105.0 if mode_id == MAP_MODE_POLITICAL else 182.0
		var button_rect := Rect2(x, rect.position.y + 8.0, width, 28.0)
		_draw_button(button_rect, str(option.get("label", mode_id)), "formal_map_mode:%s" % mode_id, true)
		if mode_id == _map_observation_mode:
			draw_line(button_rect.position + Vector2(7.0, 26.0), button_rect.end - Vector2(7.0, 2.0), Color(0.96, 0.76, 0.38, 0.95), 2.0)
		x += width + 6.0
	if _map_observation_mode == MAP_MODE_POLITICAL:
		return
	var legend := Rect2(700.0, 124.0, 238.0, 54.0)
	_panel(legend, Color(0.012, 0.031, 0.035, 0.94), Color(0.54, 0.66, 0.55, 0.30))
	var title := "满足率  低 → 高" if _map_observation_mode == MAP_MODE_FULFILLMENT else "短缺量  低 → 高"
	_draw_label(legend.position + Vector2(12.0, 22.0), title, 10, Color(0.90, 0.84, 0.66, 1.0))
	for index: int in 8:
		var ratio := float(index) / 7.0
		var color := (
			Color(0.66, 0.20, 0.13).lerp(Color(0.18, 0.68, 0.49), ratio)
			if _map_observation_mode == MAP_MODE_FULFILLMENT
			else Color(0.24, 0.48, 0.45).lerp(Color(0.82, 0.24, 0.12), ratio)
		)
		draw_rect(Rect2(legend.position + Vector2(12.0 + index * 24.0, 32.0), Vector2(24.0, 12.0)), color)
	_draw_label(legend.position + Vector2(12.0, 51.0), "灰色：无可靠 Formal 映射 / 尚未日结", 8, Color(0.70, 0.76, 0.72, 0.95))


func _on_formal_state_changed(change: Dictionary) -> void:
	if (
		bool(change.get("initialized", false))
		or bool(change.get("restored", false))
		or bool(change.get("player", false))
		or bool(change.get("economy", false))
	):
		_refresh_player_context_cache()
		if bool(change.get("economy", false)) or bool(change.get("restored", false)):
			_economy_observation_dirty = true
			if _formal_workspace == WORKSPACE_ECONOMY:
				_refresh_economy_observations()
			elif _formal_workspace == WORKSPACE_MAP and _map_observation_mode != MAP_MODE_POLITICAL:
				_refresh_economy_overlay()
		_refresh_shell_observations()
		queue_redraw()


func _refresh_player_context_cache() -> void:
	_player_context_cache = (
		formal_simulation.player_context_view()
		if formal_simulation.initialized
		else {}
	)
	_refresh_political_observations()


func _refresh_political_observations() -> void:
	if not formal_simulation.initialized:
		_local_political_observation_cache = {}
		_observed_political_observation_cache = {}
		return
	var local_id := _home_historical_entity_id()
	_local_political_observation_cache = formal_simulation.political_observation(
		local_id
	)
	_observed_political_observation_cache = (
		formal_simulation.political_observation(_selected_polity_entity_id())
	)


func _set_politics_tab(tab_id: String) -> bool:
	for tab: Dictionary in POLITICS_TABS:
		if str(tab.get("id", "")) == tab_id:
			_politics_tab = tab_id
			_refresh_political_observations()
			queue_redraw()
			return true
	return false


func _refresh_shell_observations() -> void:
	if not formal_simulation.initialized:
		_defend_options_cache = {}
		return
	_defend_options_cache = formal_simulation.player_defend_options()


func _refresh_organization_observations() -> void:
	if not formal_simulation.initialized:
		_organization_catalog_cache = {}
		_player_organization_cache = {}
		_organization_detail_cache = {}
		_organization_responsibility_cache = {}
		return
	_organization_catalog_cache = formal_simulation.organization_observation_catalog()
	_player_organization_cache = formal_simulation.player_organization_observation()
	_organization_responsibility_cache = formal_simulation.organization_responsibility_observation()
	var rows := _organization_catalog_cache.get("rows", []) as Array
	if _selected_organization_id.is_empty() and not rows.is_empty():
		_selected_organization_id = str((rows[0] as Dictionary).get("organization_id", ""))
	_organization_detail_cache = formal_simulation.organization_observation(
		_selected_organization_id
	)
	_organization_refresh_count += 1


func _set_organization_tab(tab_id: String) -> bool:
	for tab: Dictionary in ORGANIZATION_TABS:
		if str(tab.get("id", "")) == tab_id:
			_organization_tab = tab_id
			_refresh_organization_observations()
			queue_redraw()
			return true
	return false


func _select_organization(organization_id: String) -> bool:
	var detail := formal_simulation.organization_observation(organization_id)
	if not bool(detail.get("available", false)):
		return false
	_selected_organization_id = organization_id
	_organization_detail_cache = detail
	queue_redraw()
	return true


func _my_market_id() -> String:
	var economic := _player_context_cache.get("economic_observation", {}) as Dictionary
	var economy_id := str(economic.get("economy_entity_id", ""))
	return formal_simulation.market_registry_view().market_id_for_economic_aggregate(
		economy_id
	)


func _selected_polity_market_id() -> String:
	return formal_simulation.market_id_for_polity(_selected_polity_entity_id())


func _refresh_economy_catalog() -> void:
	_economy_catalog_cache = formal_simulation.economy_observation_catalog()
	_commodity_catalog_cache = formal_simulation.commodity_catalog_observation()
	if _observed_market_id.is_empty():
		_observed_market_id = _selected_polity_market_id()
	if _observed_market_id.is_empty():
		_observed_market_id = _my_market_id()


func _refresh_selected_market() -> void:
	_selected_market_cache = formal_simulation.market_observation(
		_observed_market_id
	)
	_rebuild_commodity_rows_cache()


func _refresh_economy_observations(force: bool = false) -> void:
	if not formal_simulation.initialized:
		return
	var current_revision := formal_simulation.economy_observation_revision()
	var cached_revision := int(_economy_catalog_cache.get("state_revision", -2))
	if force or _economy_observation_dirty or cached_revision != current_revision:
		_refresh_economy_catalog()
		_economy_observation_dirty = false
		_economy_refresh_count += 1
	match _economy_tab:
		ECONOMY_TAB_OVERVIEW, ECONOMY_TAB_MARKETS, ECONOMY_TAB_COMMODITIES:
			_refresh_selected_market()
		ECONOMY_TAB_SHORTAGES:
			_shortage_observation_cache = formal_simulation.shortage_observation()
			_rebuild_shortage_rows_cache()
		ECONOMY_TAB_TRANSPORT:
			_transport_observation_cache = formal_simulation.transport_observation()


func _refresh_economy_overlay() -> void:
	if _map_observation_mode == MAP_MODE_POLITICAL:
		_economy_overlay_cache = {}
		return
	var mode := "fulfillment" if _map_observation_mode == MAP_MODE_FULFILLMENT else "shortage"
	_economy_overlay_cache = formal_simulation.economy_overlay_observation(mode)
	_economy_observation_dirty = false
	queue_redraw()


func _rebuild_commodity_rows_cache() -> void:
	var rows := DataRecordUtils.to_dictionary_array(
		_selected_market_cache.get("commodities", [])
	)
	var query := _commodity_search.to_lower()
	if not query.is_empty():
		var filtered: Array[Dictionary] = []
		for row: Dictionary in rows:
			if (
				str(row.get("commodity_id", "")).to_lower().contains(query)
				or str(row.get("name_zh", "")).to_lower().contains(query)
			):
				filtered.append(row)
		rows = filtered
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match _commodity_sort:
			"commodity":
				return str(a.get("commodity_id", "")) < str(b.get("commodity_id", ""))
			"fulfillment":
				return int(a.get("fulfillment_bp", -1)) < int(b.get("fulfillment_bp", -1))
			_:
				return float(a.get("unmet", 0.0)) > float(b.get("unmet", 0.0))
	)
	_commodity_rows_cache = rows
	_commodity_page = clampi(_commodity_page, 0, maxi(0, (rows.size() - 1) / 9))


func _rebuild_shortage_rows_cache() -> void:
	var rows := DataRecordUtils.to_dictionary_array(
		_shortage_observation_cache.get("rows", [])
	)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match _shortage_sort:
			"fulfillment":
				return int(a.get("fulfillment_bp", -1)) < int(b.get("fulfillment_bp", -1))
			"commodity":
				return str(a.get("commodity_id", "")) < str(b.get("commodity_id", ""))
			"market":
				return str(a.get("market_id", "")) < str(b.get("market_id", ""))
			_:
				return float(a.get("unmet", 0.0)) > float(b.get("unmet", 0.0))
	)
	_shortage_rows_cache = rows
	_shortage_page = clampi(_shortage_page, 0, maxi(0, (rows.size() - 1) / 9))


func _set_economy_tab(tab_id: String) -> bool:
	var valid := false
	for tab: Dictionary in ECONOMY_TABS:
		if str(tab.get("id", "")) == tab_id:
			valid = true
			break
	if not valid:
		return false
	_economy_tab = tab_id
	_refresh_economy_observations()
	queue_redraw()
	return true


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
	if workspace_id == WORKSPACE_ECONOMY:
		_refresh_economy_observations()
	elif workspace_id == WORKSPACE_POLITICS:
		_refresh_political_observations()
	elif workspace_id == WORKSPACE_ORGANIZATION:
		_refresh_organization_observations()
	elif workspace_id == WORKSPACE_MAP and _map_observation_mode != MAP_MODE_POLITICAL:
		_refresh_economy_overlay()
	if workspace_id == WORKSPACE_MILITARY:
		_refresh_shell_observations()
	queue_redraw()
	return true


func shell_player_person_id() -> String:
	return str(_player_context_cache.get("person_id", ""))


func local_political_observation() -> Dictionary:
	return _local_political_observation_cache.duplicate(true)


func observed_political_observation() -> Dictionary:
	return _observed_political_observation_cache.duplicate(true)


func politics_tab_id() -> String:
	return _politics_tab


func organization_refresh_count() -> int:
	return _organization_refresh_count


func selected_organization_id() -> String:
	return _selected_organization_id


func selected_organization_observation() -> Dictionary:
	return _organization_detail_cache.duplicate(true)


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


func economy_tab_id() -> String:
	return _economy_tab


func economy_observed_market_id() -> String:
	return _observed_market_id


func economy_my_market_id() -> String:
	return _my_market_id()


func economy_catalog_observation() -> Dictionary:
	return _economy_catalog_cache.duplicate(true)


func economy_selected_market_observation() -> Dictionary:
	return _selected_market_cache.duplicate(true)


func economy_shortage_observation() -> Dictionary:
	return _shortage_observation_cache.duplicate(true)


func economy_transport_observation() -> Dictionary:
	return _transport_observation_cache.duplicate(true)


func economy_observation_refresh_count() -> int:
	return _economy_refresh_count


func map_observation_mode() -> String:
	return _map_observation_mode


func economy_overlay_observation() -> Dictionary:
	return _economy_overlay_cache.duplicate(true)


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
	_draw_workspace_heading(rect, "工作 / 经济", "个人工作 unavailable · Formal Economy / Market 只读观察")
	_draw_economy_subnavigation(rect)
	match _economy_tab:
		ECONOMY_TAB_MARKETS:
			_draw_market_browser(rect)
		ECONOMY_TAB_COMMODITIES:
			_draw_commodity_browser(rect)
		ECONOMY_TAB_SHORTAGES:
			_draw_shortage_browser(rect)
		ECONOMY_TAB_TRANSPORT:
			_draw_transport_browser(rect)
		_:
			_draw_economy_overview(rect)


func _draw_economy_subnavigation(rect: Rect2) -> void:
	var x := rect.position.x + 30.0
	for tab: Dictionary in ECONOMY_TABS:
		var tab_id := str(tab.get("id", ""))
		var tab_rect := Rect2(x, rect.position.y + 96.0, 126.0, 28.0)
		_draw_button(tab_rect, str(tab.get("label", tab_id)), "formal_economy_tab:%s" % tab_id, true)
		if tab_id == _economy_tab:
			draw_line(tab_rect.position + Vector2(7.0, 26.0), tab_rect.end - Vector2(7.0, 2.0), Color(0.96, 0.76, 0.38, 0.95), 2.0)
		x += 132.0


func _draw_economy_overview(rect: Rect2) -> void:
	var economic := _player_context_cache.get("economic_observation", {}) as Dictionary
	var place := _player_context_cache.get("current_place", {}) as Dictionary
	var source := _player_context_cache.get("population_source", {}) as Dictionary
	var left := Rect2(rect.position + Vector2(30.0, 140.0), Vector2(rect.size.x * 0.36, 350.0))
	var right := Rect2(rect.position + Vector2(rect.size.x * 0.40, 140.0), Vector2(rect.size.x * 0.57, 350.0))
	_panel(left, Color(0.020, 0.046, 0.050, 0.76), Color(0.48, 0.61, 0.52, 0.22))
	_panel(right, Color(0.020, 0.046, 0.050, 0.76), Color(0.67, 0.58, 0.34, 0.28))
	_draw_label(left.position + Vector2(18.0, 30.0), "个人工作", 16, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(left.position + Vector2(18.0, 66.0), [
		"人物：%s" % shell_player_person_id(),
		"地点：%s" % str(place.get("name", place.get("id", "不可用"))),
		"人口来源：%s" % str(source.get("id", "不可用")),
		"Employment owner：unavailable",
		"职业 / 合同 / 工资 / 个人现金：尚未模拟",
	], 28.0, 11)
	_draw_label(right.position + Vector2(18.0, 30.0), "地区 / 聚合经济观察", 16, Color(0.91, 0.82, 0.58, 1.0))
	if not bool(economic.get("available", false)):
		_draw_shell_lines(right.position + Vector2(18.0, 66.0), ["不可用：%s" % str(economic.get("reason", "unavailable"))], 27.0)
		return
	var totals := _selected_market_cache.get("daily_totals", {}) as Dictionary
	var settled := bool(_selected_market_cache.get("settled", false))
	var fulfillment := "尚未日结" if not settled else "%.1f%%" % (float(totals.get("fulfillment_bp", 0)) / 100.0)
	_draw_shell_lines(right.position + Vector2(18.0, 66.0), [
		"经济聚合：%s" % str(_selected_market_cache.get("economic_aggregate_id", economic.get("economy_entity_id", ""))),
		"Market：%s" % str(_selected_market_cache.get("market_id", _my_market_id())),
		"人口：%s" % _compact_integer(int(_selected_market_cache.get("population", economic.get("population", 0)))),
		"需求 / 消费 / 未满足：%s / %s / %s" % [
			_format_units_or_pending(totals, "demand_units", settled),
			_format_units_or_pending(totals, "consumed_units", settled),
			_format_units_or_pending(totals, "unmet_units", settled),
		],
		"满足率：%s" % fulfillment,
		"在途运输：%d · 相关路线：%d" % [int(_selected_market_cache.get("active_shipment_count", 0)), int(_selected_market_cache.get("route_count", 0))],
		"证据状态：%s" % str(_selected_market_cache.get("admission_status", economic.get("admission_status", ""))),
		"当前时间：%s" % _format_sim_datetime(),
	], 27.0, 11)
	_draw_unavailable_notice(rect, "聚合经济是地区事实；不会被解释为个人工资、钱包或就业")


func _draw_market_browser(rect: Rect2) -> void:
	var rows := DataRecordUtils.to_dictionary_array(_economy_catalog_cache.get("markets", []))
	var page_size := 7
	var page_count := maxi(1, ceili(float(rows.size()) / float(page_size)))
	_market_page = clampi(_market_page, 0, page_count - 1)
	_draw_label(rect.position + Vector2(32.0, 153.0), "Formal Markets · %d" % rows.size(), 15, Color(0.91, 0.82, 0.58, 1.0))
	_draw_button(Rect2(rect.end.x - 330.0, rect.position.y + 136.0, 92.0, 28.0), "My Market", "formal_market_my", not _my_market_id().is_empty())
	_draw_button(Rect2(rect.end.x - 230.0, rect.position.y + 136.0, 198.0, 28.0), "Observed Polity Market", "formal_market_map_observed", not _selected_polity_market_id().is_empty())
	var header_y := rect.position.y + 187.0
	_draw_table_header(Vector2(rect.position.x + 32.0, header_y), ["Market / Aggregate", "Population", "Fulfillment", "Unmet", "Ship", "Routes"])
	var start := _market_page * page_size
	for local_index: int in page_size:
		var index := start + local_index
		if index >= rows.size():
			break
		var row := rows[index]
		var totals := row.get("daily_totals", {}) as Dictionary
		var settled := bool(row.get("settled", false))
		var row_rect := Rect2(rect.position.x + 30.0, header_y + 14.0 + local_index * 43.0, rect.size.x - 60.0, 38.0)
		var selected := str(row.get("market_id", "")) == _observed_market_id
		_panel(row_rect, Color(0.09, 0.075, 0.035, 0.76) if selected else Color(0.026, 0.052, 0.055, 0.72), Color(0.82, 0.67, 0.34, 0.50) if selected else Color(0.42, 0.56, 0.50, 0.18))
		_register_hit(row_rect, "formal_market_select:%s" % str(row.get("market_id", "")), true)
		_draw_market_row(row_rect, row, totals, settled)
	_draw_pager(rect, _market_page, page_count, "formal_market_page")
	_draw_label(rect.position + Vector2(32.0, rect.end.y - 48.0), "当前观察：%s · 玩家仍为 %s" % [_observed_market_id, shell_player_person_id()], 9, Color(0.72, 0.80, 0.75, 0.96))


func _draw_commodity_browser(rect: Rect2) -> void:
	var page_size := 9
	var page_count := maxi(1, ceili(float(_commodity_rows_cache.size()) / float(page_size)))
	_commodity_page = clampi(_commodity_page, 0, page_count - 1)
	_draw_label(rect.position + Vector2(32.0, 151.0), "Market：%s · Formal commodities %d" % [_observed_market_id, int(_commodity_catalog_cache.get("commodity_count", 0))], 14, Color(0.91, 0.82, 0.58, 1.0))
	_draw_label(rect.position + Vector2(32.0, 178.0), "Search：%s%s" % [_commodity_search, "▌" if _commodity_search.length() < 32 else ""], 10, Color(0.75, 0.84, 0.79, 1.0))
	_draw_button(Rect2(rect.position.x + 260.0, rect.position.y + 158.0, 70.0, 25.0), "Clear", "formal_commodity_search_clear", not _commodity_search.is_empty())
	_draw_sort_buttons(rect.position + Vector2(360.0, 158.0), "formal_commodity_sort", _commodity_sort, ["unmet", "fulfillment", "commodity"])
	var header_y := rect.position.y + 207.0
	_draw_table_header(Vector2(rect.position.x + 32.0, header_y), ["Commodity", "Demand", "Consumed", "Unmet", "Fulfill", "Stock", "Price", "In"])
	var start := _commodity_page * page_size
	for local_index: int in page_size:
		var index := start + local_index
		if index >= _commodity_rows_cache.size():
			break
		_draw_commodity_row(Rect2(rect.position.x + 30.0, header_y + 12.0 + local_index * 31.0, rect.size.x - 60.0, 28.0), _commodity_rows_cache[index])
	_draw_pager(rect, _commodity_page, page_count, "formal_commodity_page")


func _draw_shortage_browser(rect: Rect2) -> void:
	var page_size := 9
	var page_count := maxi(1, ceili(float(_shortage_rows_cache.size()) / float(page_size)))
	_shortage_page = clampi(_shortage_page, 0, page_count - 1)
	_draw_label(rect.position + Vector2(32.0, 153.0), "Formal Shortages · %d · %s" % [_shortage_rows_cache.size(), _format_sim_datetime()], 14, Color(0.91, 0.82, 0.58, 1.0))
	_draw_sort_buttons(rect.position + Vector2(390.0, 137.0), "formal_shortage_sort", _shortage_sort, ["unmet", "fulfillment", "commodity", "market"])
	var header_y := rect.position.y + 188.0
	_draw_table_header(Vector2(rect.position.x + 32.0, header_y), ["Commodity", "Market / Economy", "Demand", "Consumed", "Unmet", "Fulfill"])
	var start := _shortage_page * page_size
	for local_index: int in page_size:
		var index := start + local_index
		if index >= _shortage_rows_cache.size():
			break
		_draw_shortage_row(Rect2(rect.position.x + 30.0, header_y + 12.0 + local_index * 31.0, rect.size.x - 60.0, 28.0), _shortage_rows_cache[index])
	if _shortage_rows_cache.is_empty():
		_draw_label(rect.position + Vector2(42.0, 240.0), "当前没有已日结的 unmet > 0 记录；这不是伪造的零短缺。", 12, Color(0.76, 0.80, 0.73, 1.0))
	_draw_pager(rect, _shortage_page, page_count, "formal_shortage_page")


func _draw_transport_browser(rect: Rect2) -> void:
	var shipments := DataRecordUtils.to_dictionary_array(_transport_observation_cache.get("active_shipments", []))
	var routes := DataRecordUtils.to_dictionary_array(_transport_observation_cache.get("routes", []))
	var source_rows := shipments if not shipments.is_empty() else routes
	var page_size := 8
	var page_count := maxi(1, ceili(float(source_rows.size()) / float(page_size)))
	_transport_page = clampi(_transport_page, 0, page_count - 1)
	_draw_label(rect.position + Vector2(32.0, 153.0), "Formal Transport · active shipments %d · routes %d" % [shipments.size(), routes.size()], 14, Color(0.91, 0.82, 0.58, 1.0))
	_draw_label(rect.position + Vector2(32.0, 180.0), "当前展示：%s" % ("在途运输" if not shipments.is_empty() else "路线目录（当前无在途运输）"), 10, Color(0.72, 0.80, 0.75, 1.0))
	var header_y := rect.position.y + 211.0
	_draw_table_header(Vector2(rect.position.x + 32.0, header_y), ["Identity", "Source", "Destination", "Commodity / Mode", "Amount", "Arrival / Duration"])
	var start := _transport_page * page_size
	for local_index: int in page_size:
		var index := start + local_index
		if index >= source_rows.size():
			break
		_draw_transport_row(Rect2(rect.position.x + 30.0, header_y + 12.0 + local_index * 34.0, rect.size.x - 60.0, 31.0), source_rows[index], not shipments.is_empty())
	_draw_pager(rect, _transport_page, page_count, "formal_transport_page")


func _format_units_or_pending(totals: Dictionary, key: String, settled: bool) -> String:
	return "尚未日结" if not settled else "%.1f" % float(totals.get(key, 0.0))


func _draw_table_header(position: Vector2, labels: Array[String]) -> void:
	var column_width := (size.x - 112.0) / maxf(1.0, float(labels.size()))
	for index: int in labels.size():
		_draw_label(position + Vector2(index * column_width + 8.0, 0.0), labels[index], 9, Color(0.62, 0.72, 0.68, 0.96))


func _draw_market_row(rect: Rect2, row: Dictionary, totals: Dictionary, settled: bool) -> void:
	var columns := [
		"%s\n%s" % [str(row.get("market_id", "")), str(row.get("economic_aggregate_id", ""))],
		_compact_integer(int(row.get("population", 0))),
		"—" if not settled else "%.1f%%" % (float(totals.get("fulfillment_bp", 0)) / 100.0),
		"—" if not settled else "%.1f" % float(totals.get("unmet_units", 0.0)),
		str(row.get("active_shipment_count", 0)),
		str(row.get("route_count", 0)),
	]
	var widths := PackedFloat32Array([0.32, 0.16, 0.15, 0.15, 0.10, 0.10])
	var x := rect.position.x + 10.0
	for index: int in columns.size():
		var text := str(columns[index]).replace("\n", " · ")
		_draw_label(Vector2(x, rect.position.y + 24.0), _ellipsize(text, 38 if index == 0 else 16), 9)
		x += rect.size.x * widths[index]


func _draw_commodity_row(rect: Rect2, row: Dictionary) -> void:
	_panel(rect, Color(0.025, 0.050, 0.053, 0.72), Color(0.40, 0.54, 0.49, 0.16))
	var settled := bool(row.get("settled", false))
	var values: Array[String] = [
		"%s · %s" % [str(row.get("name_zh", "")), str(row.get("commodity_id", ""))],
		"—" if not settled else "%.1f" % float(row.get("demand", 0.0)),
		"—" if not settled else "%.1f" % float(row.get("consumed", 0.0)),
		"—" if not settled else "%.1f" % float(row.get("unmet", 0.0)),
		"—" if int(row.get("fulfillment_bp", -1)) < 0 else "%.1f%%" % (float(row.get("fulfillment_bp", 0)) / 100.0),
		"%.1f" % float(row.get("inventory", 0.0)),
		"%d¢" % int(row.get("price_centimes", 0)),
		str(row.get("incoming_shipment_count", 0)),
	]
	var widths := PackedFloat32Array([0.23, 0.11, 0.11, 0.11, 0.11, 0.12, 0.11, 0.08])
	_draw_table_values(rect, values, widths)


func _draw_shortage_row(rect: Rect2, row: Dictionary) -> void:
	_panel(rect, Color(0.052, 0.043, 0.030, 0.76), Color(0.67, 0.49, 0.25, 0.20))
	var values: Array[String] = [
		"%s · %s" % [str(row.get("name_zh", "")), str(row.get("commodity_id", ""))],
		"%s · %s" % [str(row.get("market_id", "")), str(row.get("economic_aggregate_id", ""))],
		"%.1f" % float(row.get("demand", 0.0)),
		"%.1f" % float(row.get("consumed", 0.0)),
		"%.1f" % float(row.get("unmet", 0.0)),
		"%.1f%%" % (float(row.get("fulfillment_bp", 0)) / 100.0),
	]
	var widths := PackedFloat32Array([0.24, 0.31, 0.12, 0.12, 0.11, 0.10])
	_draw_table_values(rect, values, widths)


func _draw_transport_row(rect: Rect2, row: Dictionary, shipment: bool) -> void:
	_panel(rect, Color(0.025, 0.050, 0.053, 0.72), Color(0.40, 0.54, 0.49, 0.16))
	var values: Array[String] = []
	if shipment:
		values = [
			str(row.get("shipment_id", "")),
			str(row.get("origin_entity_id", "")),
			str(row.get("destination_entity_id", "")),
			str(row.get("commodity_id", "")),
			"%.1f" % float(row.get("units", 0.0)),
			"h%d · %s" % [int(row.get("arrival_hour", 0)), str(row.get("route_id", ""))],
		]
	else:
		values = [
			str(row.get("route_id", "")),
			str(row.get("from", "")),
			str(row.get("to", "")),
			str(row.get("mode", "")),
			"%.1f/day" % float(row.get("capacity_units_per_day", 0.0)),
			"%dh" % int(row.get("duration_hours", 0)),
		]
	var widths := PackedFloat32Array([0.20, 0.20, 0.20, 0.15, 0.12, 0.13])
	_draw_table_values(rect, values, widths)


func _draw_table_values(rect: Rect2, values: Array[String], widths: PackedFloat32Array) -> void:
	var x := rect.position.x + 8.0
	for index: int in values.size():
		_draw_label(Vector2(x, rect.position.y + 19.0), _ellipsize(values[index], 29 if index < 3 else 18), 9)
		x += rect.size.x * widths[index]


func _draw_sort_buttons(position: Vector2, action_prefix: String, selected: String, options: Array[String]) -> void:
	var x := position.x
	for option: String in options:
		var rect := Rect2(x, position.y, 92.0, 25.0)
		_draw_button(rect, option, "%s:%s" % [action_prefix, option], true)
		if option == selected:
			draw_line(rect.position + Vector2(6.0, 23.0), rect.end - Vector2(6.0, 2.0), Color(0.94, 0.73, 0.34, 0.94), 2.0)
		x += 97.0


func _draw_pager(rect: Rect2, page: int, page_count: int, action_prefix: String) -> void:
	var y := rect.end.y - 48.0
	_draw_button(Rect2(rect.end.x - 210.0, y - 22.0, 58.0, 26.0), "Prev", "%s:-1" % action_prefix, page > 0)
	_draw_label(Vector2(rect.end.x - 142.0, y - 4.0), "%d / %d" % [page + 1, page_count], 9, Color(0.73, 0.80, 0.76, 1.0))
	_draw_button(Rect2(rect.end.x - 84.0, y - 22.0, 58.0, 26.0), "Next", "%s:1" % action_prefix, page + 1 < page_count)


func _draw_relations_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "关系 / 信息", "能力边界与真实世界资料入口")
	_draw_label(rect.position + Vector2(38.0, 130.0), "当前 Formal 世界没有人物关系图或私人收件箱 owner。", 16)
	_draw_shell_lines(rect.position + Vector2(38.0, 172.0), [
		"好友：当前版本尚未模拟（不显示伪造的 0）",
		"私人消息：当前版本尚未模拟（不显示固定未读数）",
		"联系人 / 约见 / 发消息：没有 Formal 命令端口",
		"Organization Responsibility 仅作为机构 / 世界观察。",
		"机构观察记录：请在“组织 → Responsibility”中浏览正式记录",
	], 28.0)
	_draw_unavailable_notice(rect, "此页面没有“标记已读”、发消息或约见按钮")


func _draw_organization_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "组织", "OrganizationCore 结构、Authority grant 与机构责任均为只读观察")
	var x := rect.position.x + 32.0
	for tab: Dictionary in ORGANIZATION_TABS:
		var tab_id := str(tab.get("id", ""))
		var width := 152.0 if tab_id != ORGANIZATION_TAB_RESPONSIBILITY else 166.0
		var tab_rect := Rect2(x, rect.position.y + 94.0, width, 30.0)
		_draw_button(tab_rect, str(tab.get("label", tab_id)), "formal_organization_tab:%s" % tab_id, true)
		if tab_id == _organization_tab:
			draw_line(tab_rect.position + Vector2(8.0, 28.0), tab_rect.end - Vector2(8.0, 2.0), Color(0.96, 0.76, 0.38, 0.95), 2.0)
		x += width + 8.0
	match _organization_tab:
		ORGANIZATION_TAB_BROWSER:
			_draw_organization_browser(rect)
		ORGANIZATION_TAB_RESPONSIBILITY:
			_draw_organization_responsibility(rect)
		_:
			_draw_player_organization_records(rect)
	_draw_unavailable_notice(rect, "没有加入组织、升职、任命或工资命令；无任职不等于失业")


func _draw_player_organization_records(rect: Rect2) -> void:
	var memberships := _player_organization_cache.get("memberships", []) as Array
	var appointments := _player_organization_cache.get("appointments", []) as Array
	var capabilities := _player_organization_cache.get("effective_capabilities", []) as Array
	var grants := _player_organization_cache.get("current_authority_grants", []) as Array
	var left := rect.position + Vector2(38.0, 154.0)
	_draw_label(left, "我的 Formal Organization 记录", 17, Color(0.91, 0.82, 0.58, 1.0))
	var lines: Array[String] = [
		"acting person：%s" % str(_player_organization_cache.get("person_id", "")),
		"memberships：%d" % memberships.size(),
		"appointments：%d" % appointments.size(),
		"effective capabilities：%d" % capabilities.size(),
		"current authority grants：%d" % grants.size(),
	]
	if memberships.is_empty() and appointments.is_empty():
		lines.append("暂无正式组织记录")
	for membership: Dictionary in memberships:
		lines.append("成员 · %s" % str(membership.get("organization_id", "")))
	for appointment: Dictionary in appointments:
		lines.append("任职 · %s / %s" % [str(appointment.get("organization_id", "")), str(appointment.get("position_id", ""))])
	_draw_shell_lines(left + Vector2(0.0, 36.0), lines.slice(0, 10), 24.0)
	var right := rect.position + Vector2(rect.size.x * 0.57, 154.0)
	_draw_label(right, "能力可用性说明", 17, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(right + Vector2(0.0, 36.0), [
		"No formal capability grant" if grants.is_empty() else "存在当前 holder-valid Formal grant",
		"能力只来自 membership / appointment / Authority owner。",
		"Organization Responsibility 是机构事项，不是“我的任务”。",
		"DEFEND 仍在军事页通过正式权限端口提交并重验。",
	], 24.0)


func _draw_organization_browser(rect: Rect2) -> void:
	var rows := _organization_catalog_cache.get("rows", []) as Array
	var page_size := 8
	var max_page := maxi(0, (rows.size() - 1) / page_size)
	_organization_page = clampi(_organization_page, 0, max_page)
	var start := _organization_page * page_size
	var left_rect := Rect2(rect.position + Vector2(32.0, 142.0), Vector2(rect.size.x * 0.45, 390.0))
	_draw_label(left_rect.position, "正式组织 %d · page %d/%d" % [rows.size(), _organization_page + 1, max_page + 1], 15, Color(0.91, 0.82, 0.58, 1.0))
	var y := left_rect.position.y + 30.0
	for index: int in range(start, mini(rows.size(), start + page_size)):
		var row := rows[index] as Dictionary
		var organization_id := str(row.get("organization_id", ""))
		var item_rect := Rect2(left_rect.position.x, y - 17.0, left_rect.size.x - 12.0, 39.0)
		_panel(item_rect, Color(0.07, 0.09, 0.085, 0.82) if organization_id == _selected_organization_id else Color(0.025, 0.05, 0.052, 0.75), Color(0.67, 0.57, 0.34, 0.34))
		_register_hit(item_rect, "formal_organization_select:%s" % organization_id, true)
		_draw_label(Vector2(item_rect.position.x + 10.0, y), _ellipsize(str(row.get("display_label", organization_id)), 39), 10)
		_draw_label(Vector2(item_rect.position.x + 10.0, y + 16.0), "%s · active=%s · members=%d · appointments=%d" % [str(row.get("organization_kind", "")), str(row.get("active", false)), int(row.get("member_count", 0)), int(row.get("appointment_count", 0))], 8, Color(0.67, 0.76, 0.72, 0.95))
		y += 43.0
	_draw_button(Rect2(left_rect.position.x, left_rect.end.y - 8.0, 72.0, 25.0), "上一页", "formal_organization_page:-1", _organization_page > 0)
	_draw_button(Rect2(left_rect.position.x + 80.0, left_rect.end.y - 8.0, 72.0, 25.0), "下一页", "formal_organization_page:1", _organization_page < max_page)
	_draw_organization_detail(rect.position + Vector2(rect.size.x * 0.50, 142.0))


func _draw_organization_detail(position: Vector2) -> void:
	var detail := _organization_detail_cache
	var evidence := detail.get("composition_evidence", {}) as Dictionary
	var responsibilities := detail.get("responsibilities", []) as Array
	_draw_label(position, "Organization Detail", 15, Color(0.91, 0.82, 0.58, 1.0))
	_draw_label(position + Vector2(0.0, 30.0), _ellipsize(str(detail.get("display_label", "不可用")), 50), 14, Color(0.86, 0.87, 0.76, 1.0))
	_draw_shell_lines(position + Vector2(0.0, 58.0), [
		"ID：%s" % str(detail.get("organization_id", "")),
		"kind / active：%s / %s" % [str(detail.get("organization_kind", "")), str(detail.get("active", false))],
		"parent / children：%s / %d" % [str(detail.get("parent_organization_id", "none")) if not str(detail.get("parent_organization_id", "")).is_empty() else "none", (detail.get("child_organization_ids", []) as Array).size()],
		"place reference：%s" % (str(detail.get("primary_place_id", "")) if not str(detail.get("primary_place_id", "")).is_empty() else "unavailable"),
		"members / appointments：%d / %d" % [(detail.get("member_ids", []) as Array).size(), (detail.get("appointments", []) as Array).size()],
		"positions / declared capabilities：%d / %d" % [(detail.get("positions", []) as Array).size(), (detail.get("declared_capability_ids", []) as Array).size()],
		"current authority grants：%d" % (detail.get("current_authority_grants", []) as Array).size(),
		"institution responsibility：%d" % responsibilities.size(),
		"evidence：%s · exact historical name=%s" % [str(evidence.get("basis_class", "unavailable")), str(evidence.get("historical_exact_name_claimed", false))],
	], 22.0, 9)


func _draw_organization_responsibility(rect: Rect2) -> void:
	var rows := _organization_responsibility_cache.get("rows", []) as Array
	var counts := _organization_responsibility_cache.get("status_counts", {}) as Dictionary
	var page_size := 9
	var max_page := maxi(0, (rows.size() - 1) / page_size)
	_responsibility_page = clampi(_responsibility_page, 0, max_page)
	_draw_label(rect.position + Vector2(38.0, 150.0), "机构责任 / 世界观察 · %d" % rows.size(), 17, Color(0.91, 0.82, 0.58, 1.0))
	_draw_label(rect.position + Vector2(38.0, 178.0), "MONITORING %d · ATTENTION_REQUIRED %d · NO_DETAILED_ECONOMY %d" % [int(counts.get("MONITORING", 0)), int(counts.get("ATTENTION_REQUIRED", 0)), int(counts.get("NO_DETAILED_ECONOMY", 0))], 9, Color(0.70, 0.80, 0.75, 0.96))
	var y := rect.position.y + 218.0
	var start := _responsibility_page * page_size
	for index: int in range(start, mini(rows.size(), start + page_size)):
		var row := rows[index] as Dictionary
		var economy_id := str(row.get("economy_entity_id", ""))
		var fulfillment_bp := int(row.get("current_fulfillment_bp", -1))
		_draw_label(Vector2(rect.position.x + 48.0, y), "%s · %s · economy=%s · fulfillment=%s" % [_ellipsize(str(row.get("display_label", row.get("organization_id", ""))), 42), str(row.get("status", "")), economy_id if not economy_id.is_empty() else "unavailable", str(fulfillment_bp) if fulfillment_bp >= 0 else "unavailable"], 9)
		y += 28.0
	_draw_button(Rect2(rect.position.x + 38.0, rect.end.y - 112.0, 72.0, 25.0), "上一页", "formal_responsibility_page:-1", _responsibility_page > 0)
	_draw_button(Rect2(rect.position.x + 118.0, rect.end.y - 112.0, 72.0, 25.0), "下一页", "formal_responsibility_page:1", _responsibility_page < max_page)
	_draw_label(rect.position + Vector2(rect.size.x * 0.57, rect.end.y - 94.0), "这些是 Organization Responsibility，不是玩家消息、通知或个人任务。", 10, Color(0.91, 0.70, 0.45, 1.0))


func _draw_politics_workspace(rect: Rect2) -> void:
	_draw_workspace_heading(rect, "政治", "LOCAL POLITY 与 OBSERVED POLITY 独立；地图选择只改变观察对象")
	var x := rect.position.x + 32.0
	for tab: Dictionary in POLITICS_TABS:
		var tab_id := str(tab.get("id", ""))
		var width := 176.0 if tab_id == POLITICS_TAB_COMPARE else 112.0
		var tab_rect := Rect2(x, rect.position.y + 94.0, width, 30.0)
		_draw_button(tab_rect, str(tab.get("label", tab_id)), "formal_politics_tab:%s" % tab_id, true)
		if tab_id == _politics_tab:
			draw_line(tab_rect.position + Vector2(8.0, 28.0), tab_rect.end - Vector2(8.0, 2.0), Color(0.96, 0.76, 0.38, 0.95), 2.0)
		x += width + 8.0
	match _politics_tab:
		POLITICS_TAB_LOCAL:
			_draw_political_observation_detail(rect, _local_political_observation_cache, "LOCAL POLITY · 玩家所在地政治环境")
		POLITICS_TAB_OBSERVED:
			_draw_political_observation_detail(rect, _observed_political_observation_cache, "OBSERVED POLITY · 地图观察对象")
		_:
			_draw_political_comparison(rect)
	_draw_unavailable_notice(rect, "政策、投票、政变、革命和直接控制国家：当前版本没有人物命令")


func _draw_political_comparison(rect: Rect2) -> void:
	var left := rect.position + Vector2(38.0, 154.0)
	var right := rect.position + Vector2(rect.size.x * 0.54, 154.0)
	_draw_political_summary_column(left, _local_political_observation_cache, "LOCAL POLITY")
	_draw_political_summary_column(right, _observed_political_observation_cache, "OBSERVED POLITY")
	var same := str(_local_political_observation_cache.get("runtime_id", "")) == str(_observed_political_observation_cache.get("runtime_id", ""))
	_draw_label(rect.position + Vector2(38.0, 390.0), "上下文：%s · player=%s · place保持不变" % ["相同政治实体" if same else "两个不同政治实体", formal_simulation.player_person_id()], 10, Color(0.74, 0.83, 0.78, 0.96))


func _draw_political_summary_column(position: Vector2, observation: Dictionary, heading: String) -> void:
	var evidence := observation.get("historical_evidence", {}) as Dictionary
	_draw_label(position, heading, 16, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(position + Vector2(0.0, 32.0), [
		str(observation.get("display_name", "不可用")),
		"runtime：%s" % str(observation.get("runtime_id", "")),
		"source：%s" % str(observation.get("source_historical_id", "")),
		"当前身份：%s" % str(observation.get("lifecycle_status", "")),
		"历史状态：%s · %s" % [str(evidence.get("status", "不可用")), str(evidence.get("relationship", "不可用"))],
		"权威关系：%d" % (observation.get("authority_relations", []) as Array).size(),
		"有效期：%s → %s" % [str(evidence.get("valid_from", "不可用")), str(evidence.get("valid_to", "不可用"))],
	], 23.0)


func _draw_political_observation_detail(rect: Rect2, observation: Dictionary, heading: String) -> void:
	var evidence := observation.get("historical_evidence", {}) as Dictionary
	var left := rect.position + Vector2(38.0, 154.0)
	var right := rect.position + Vector2(rect.size.x * 0.56, 154.0)
	_draw_label(left, heading, 17, Color(0.91, 0.82, 0.58, 1.0))
	_draw_shell_lines(left + Vector2(0.0, 34.0), [
		str(observation.get("display_name", "不可用")),
		"runtime identity：%s" % str(observation.get("runtime_id", "")),
		"lifecycle：%s" % str(observation.get("lifecycle_status", "")),
		"historical source：%s" % str(observation.get("source_historical_id", "")),
		"状态 / 关系：%s / %s" % [str(evidence.get("status", "不可用")), str(evidence.get("relationship", "不可用"))],
		"有效期：%s → %s" % [str(evidence.get("valid_from", "不可用")), str(evidence.get("valid_to", "不可用"))],
	], 23.0)
	_draw_label(right, "Authority / Historical Evidence", 17, Color(0.91, 0.82, 0.58, 1.0))
	var lines: Array[String] = [
		"当前世界日期：%s" % _format_sim_datetime(),
		"authority relations：%d" % (observation.get("authority_relations", []) as Array).size(),
		"geometry：%s · %s" % [str(evidence.get("geometry_provider", "不可用")), str(evidence.get("geometry_feature_id", "不可用"))],
		"data quality：%s" % str(evidence.get("data_quality", "不可用")),
		"flag evidence id：%s" % str(evidence.get("flag_id", "不可用")),
		"flag mode：%s" % str(evidence.get("flag_mode", "不可用")),
	]
	for relation: Dictionary in observation.get("authority_relations", []) as Array:
		lines.append(_authority_relation_label(relation))
	_draw_shell_lines(right + Vector2(0.0, 34.0), lines.slice(0, 10), 22.0, 10)


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
			elif action.begins_with("formal_economy_tab:"):
				_set_economy_tab(action.trim_prefix("formal_economy_tab:"))
			elif action == "formal_market_my":
				_select_observed_market(_my_market_id())
			elif action == "formal_market_map_observed":
				_select_observed_market(_selected_polity_market_id())
			elif action.begins_with("formal_market_select:"):
				_select_observed_market(action.trim_prefix("formal_market_select:"))
			elif action.begins_with("formal_market_page:"):
				_market_page = maxi(0, _market_page + action.trim_prefix("formal_market_page:").to_int())
				queue_redraw()
			elif action.begins_with("formal_commodity_page:"):
				_commodity_page = maxi(0, _commodity_page + action.trim_prefix("formal_commodity_page:").to_int())
				queue_redraw()
			elif action.begins_with("formal_commodity_sort:"):
				_commodity_sort = action.trim_prefix("formal_commodity_sort:")
				_rebuild_commodity_rows_cache()
				queue_redraw()
			elif action == "formal_commodity_search_clear":
				_commodity_search = ""
				_rebuild_commodity_rows_cache()
				queue_redraw()
			elif action.begins_with("formal_shortage_page:"):
				_shortage_page = maxi(0, _shortage_page + action.trim_prefix("formal_shortage_page:").to_int())
				queue_redraw()
			elif action.begins_with("formal_shortage_sort:"):
				_shortage_sort = action.trim_prefix("formal_shortage_sort:")
				_rebuild_shortage_rows_cache()
				queue_redraw()
			elif action.begins_with("formal_transport_page:"):
				_transport_page = maxi(0, _transport_page + action.trim_prefix("formal_transport_page:").to_int())
				queue_redraw()
			elif action.begins_with("formal_map_mode:"):
				_set_map_observation_mode(action.trim_prefix("formal_map_mode:"))
			elif action.begins_with("formal_politics_tab:"):
				_set_politics_tab(action.trim_prefix("formal_politics_tab:"))
			elif action.begins_with("formal_organization_tab:"):
				_set_organization_tab(action.trim_prefix("formal_organization_tab:"))
			elif action.begins_with("formal_organization_select:"):
				_select_organization(action.trim_prefix("formal_organization_select:"))
			elif action.begins_with("formal_organization_page:"):
				_organization_page = maxi(0, _organization_page + action.trim_prefix("formal_organization_page:").to_int())
				queue_redraw()
			elif action.begins_with("formal_responsibility_page:"):
				_responsibility_page = maxi(0, _responsibility_page + action.trim_prefix("formal_responsibility_page:").to_int())
				queue_redraw()
			elif action.begins_with("formal_defend:"):
				_execute_formal_defend(action.trim_prefix("formal_defend:").to_int())
			else:
				super._activate_button(action)


func _select_observed_market(market_id: String) -> bool:
	if market_id.is_empty():
		_formal_status = "所选对象没有可靠的 Formal market 映射。"
		queue_redraw()
		return false
	var observation := formal_simulation.market_observation(market_id)
	if not bool(observation.get("available", false)):
		_formal_status = "Market 不可用：%s" % str(observation.get("reason", "unknown"))
		queue_redraw()
		return false
	_observed_market_id = market_id
	_selected_market_cache = observation
	_market_page = 0
	_commodity_page = 0
	_rebuild_commodity_rows_cache()
	_formal_status = "观察市场已切换；玩家身份与所在地未改变。"
	queue_redraw()
	return true


func _set_map_observation_mode(mode_id: String) -> bool:
	if mode_id not in [MAP_MODE_POLITICAL, MAP_MODE_FULFILLMENT, MAP_MODE_SHORTAGE]:
		return false
	_map_observation_mode = mode_id
	if mode_id == MAP_MODE_POLITICAL:
		_economy_overlay_cache = {}
	else:
		_refresh_economy_overlay()
	queue_redraw()
	return true


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
