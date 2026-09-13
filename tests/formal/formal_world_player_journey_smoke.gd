extends SceneTree
## Release journey guard for the normal player route. This intentionally starts
## at the configured title scene and sends player input instead of directly
## invoking menu transition or save/load methods.

const MENU_SCENE := "res://scenes/formal/formal_world_menu.tscn"
const INTENDED_POLITY_ID := "state:country_fra"
const TIME_SUPPORT := preload(
	"res://tests/variable_state/formal_time_test_support.gd"
)

var failures: int = 0
var checks: int = 0
var application_scene_count: int = 0
var save_backup: Dictionary = {}
var save_isolation_started: bool = false


func _initialize() -> void:
	node_added.connect(_on_node_added)
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	save_backup = TIME_SUPPORT.backup_formal_save()
	if not _require(not bool(save_backup.get("read_error", false)), "无法备份现有正式存档"):
		await _finish()
		return
	save_isolation_started = true
	if not _require(TIME_SUPPORT.cleanup_formal_save(), "无法建立隔离的无存档旅程"):
		await _finish()
		return

	var configured_main_scene := str(
		ProjectSettings.get_setting("application/run/main_scene", "")
	)
	if not _require(
		configured_main_scene == MENU_SCENE,
		"application/run/main_scene没有指向正式标题场景"
	):
		await _finish()
		return
	var change_error := change_scene_to_file(configured_main_scene)
	if not _require(change_error == OK, "产品标题场景无法作为正式入口加载"):
		await _finish()
		return
	await _settle_frames(5)
	var menu := current_scene as FormalWorldMenu
	if not _require(menu != null, "BOOT未到达FormalWorldMenu"):
		await _finish()
		return
	if not _require(menu.title_label.text == "1900", "标题未显示1900"):
		await _finish()
		return
	if not _require(menu.prompt_label.text.contains("按任意键"), "标题没有可执行的进入提示"):
		await _finish()
		return

	await _press_key(KEY_SPACE)
	var application := await _wait_for_application()
	if not _require(application != null, "空格输入未从标题进入正式世界"):
		await _finish()
		return
	if not _require(application_scene_count == 1, "一次标题输入创建了多个正式世界场景"):
		await _finish()
		return
	if not _require(application.formal_simulation.initialized, "正式世界模拟未初始化"):
		await _finish()
		return
	if not _require(application._data_errors.is_empty(), "地图初始化产生玩家可见数据错误"):
		await _finish()
		return

	application._ensure_projection_cache()
	var france_point := application._country_screen_anchors.get(
		INTENDED_POLITY_ID, Vector2.INF
	) as Vector2
	if not _require(france_point != Vector2.INF, "默认半球视角没有法兰西选择锚点"):
		await _finish()
		return
	_send_mouse_button(application, france_point, true)
	_send_mouse_button(application, france_point, false)
	await _settle_frames(3)
	if not _require(
		application.selected_country_id == INTENDED_POLITY_ID,
		"地图点击未选择预期的法兰西政治单元"
	):
		await _finish()
		return
	if not _require(application.info_open, "实体选择没有打开可见详情反馈"):
		await _finish()
		return
	if not _require(
		not application.formal_simulation.polity_summary(INTENDED_POLITY_ID).is_empty(),
		"所选政治单元没有可见政经详情数据"
	):
		await _finish()
		return

	# Lower-level map and evidence assertions are meaningful only after the
	# player has entered the world and selected the intended polity above.
	if not _require(application._history_entity_by_id.size() == 146, "当前地图未持有146个运行时政治实体"):
		await _finish()
		return
	if not _require(
		application.formal_simulation.historical_evidence_view().record_count() == 151,
		"历史页面未保留151条政治证据"
	):
		await _finish()
		return
	if not _require(application._flag_screen_polygons.size() >= 12, "当前半球没有形成可见政治实体图形"):
		await _finish()
		return
	if not _require(application.viewport_container.is_visible_in_tree(), "半球地图视口不可见"):
		await _finish()
		return
	var evidence := application.historical_evidence_report()
	if not _require(int(evidence.get("unit_count", -1)) == 151, "历史证据报告未保留151条记录"):
		await _finish()
		return
	if not _require(int(evidence.get("unresolved_flag_count", -1)) == 0, "历史旗帜覆盖仍有未解析记录"):
		await _finish()
		return
	if not _require(application._missing_flag_record_ids.is_empty(), "历史旗帜运行时资源缺失"):
		await _finish()
		return

	var date_before := application._format_sim_datetime()
	var economy_before := _visible_economy_signature(application)
	if not _require(await _click_action(application, "toggle_time_panel"), "时间面板入口不可点击"):
		await _finish()
		return
	if not _require(await _click_action(application, "speed:4"), "4倍速控件不可点击"):
		await _finish()
		return
	var clock := application.get_node("ClockTimer") as Timer
	for _index: int in range(24):
		clock.timeout.emit()
	await _settle_frames(3)
	if not _require(application._format_sim_datetime() != date_before, "推进整日后可见日期未变化"):
		await _finish()
		return
	if not _require(_visible_economy_signature(application) != economy_before, "推进整日后可见经济摘要未变化"):
		await _finish()
		return
	if not _require(await _click_action(application, "toggle_pause"), "暂停控件不可点击"):
		await _finish()
		return
	if not _require(application.sim_paused, "暂停控件未暂停正式时间"):
		await _finish()
		return

	await _press_key(KEY_F5)
	await _settle_frames(3)
	if not _require(FileAccess.file_exists(FormalWorldSimulation.SAVE_PATH), "F5未创建正式存档"):
		await _finish()
		return
	if not _require(application._formal_status.contains("保存"), "保存没有玩家可见反馈"):
		await _finish()
		return
	var saved_date := application._format_sim_datetime()
	var saved_economy := _visible_economy_signature(application)
	var saved_polity := application.formal_simulation.polity_summary(
		INTENDED_POLITY_ID
	).duplicate(true)

	if not _require(await _click_action(application, "speed:4"), "保存后无法继续时间"):
		await _finish()
		return
	for _index: int in range(6):
		clock.timeout.emit()
	await _settle_frames(2)
	if not _require(await _click_action(application, "toggle_pause"), "读取前无法暂停时间"):
		await _finish()
		return
	if not _require(application._format_sim_datetime() != saved_date, "保存后时间没有继续变化"):
		await _finish()
		return

	await _press_key(KEY_F9)
	await _settle_frames(3)
	if not _require(application._formal_status.contains("恢复"), "F9读取没有玩家可见反馈"):
		await _finish()
		return
	if not _require(application._format_sim_datetime() == saved_date, "读取未恢复可见日期"):
		await _finish()
		return
	if not _require(_visible_economy_signature(application) == saved_economy, "读取未恢复可见经济摘要"):
		await _finish()
		return
	if not _require(
		TIME_SUPPORT.first_semantic_difference(
			application.formal_simulation.polity_summary(INTENDED_POLITY_ID), saved_polity
		).is_empty(),
		"读取未恢复所选政治单元的玩家可见状态"
	):
		await _finish()
		return

	change_error = change_scene_to_file(MENU_SCENE)
	if not _require(change_error == OK, "无法返回标题验证继续游戏"):
		await _finish()
		return
	await _settle_frames(5)
	menu = current_scene as FormalWorldMenu
	if not _require(menu != null and menu.status_label.text.contains("存档"), "重启标题未提示继续正式存档"):
		await _finish()
		return
	await _press_key(KEY_SPACE)
	var continued := await _wait_for_application()
	if not _require(continued != null and application_scene_count == 2, "重启后未且仅未创建一个继续世界"):
		await _finish()
		return
	if not _require(continued._format_sim_datetime() == saved_date, "重启继续未恢复可见日期"):
		await _finish()
		return
	if not _require(_visible_economy_signature(continued) == saved_economy, "重启继续未恢复可见经济摘要"):
		await _finish()
		return

	await _finish()


func _on_node_added(node: Node) -> void:
	if node is FormalWorldApplication:
		application_scene_count += 1


func _wait_for_application() -> FormalWorldApplication:
	for _index: int in range(120):
		if current_scene is FormalWorldApplication:
			await _settle_frames(4)
			return current_scene as FormalWorldApplication
		await process_frame
	return null


func _press_key(keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame


func _click_action(application: FormalWorldApplication, action: String) -> bool:
	application.queue_redraw()
	await _settle_frames(3)
	for index: int in range(application._button_hits.size() - 1, -1, -1):
		var record := application._button_hits[index] as Dictionary
		if str(record.get("action", "")) != action or not bool(record.get("enabled", false)):
			continue
		var rect := record.get("rect", Rect2()) as Rect2
		_send_mouse_button(application, rect.get_center(), true)
		_send_mouse_button(application, rect.get_center(), false)
		await _settle_frames(2)
		return true
	return false


func _send_mouse_button(
	application: FormalWorldApplication, position: Vector2, pressed: bool
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	application._gui_input(event)


func _visible_economy_signature(application: FormalWorldApplication) -> String:
	var polity := application.formal_simulation.polity_summary(INTENDED_POLITY_ID)
	var economy := polity.get("economy", {}) as Dictionary
	var daily := economy.get("daily_totals", {}) as Dictionary
	return "%d:%d:%d" % [
		int(application._last_summary.get("fulfillment_bp", -1)),
		int(daily.get("fulfillment_bp", -1)),
		int(economy.get("active_shipments", -1)),
	]


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _require(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		return true
	failures += 1
	push_error("Formal player journey: " + message)
	return false


func _finish() -> void:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	if save_isolation_started:
		if not TIME_SUPPORT.restore_formal_save(save_backup):
			failures += 1
			push_error("Formal player journey: 无法恢复审计前正式存档")
		else:
			var restored_backup := TIME_SUPPORT.backup_formal_save()
			if not _require(
				_save_artifacts_match(save_backup, restored_backup),
				"正式旅程结束后没有逐件恢复原有存档及其备份工件"
			):
				push_error("Formal player journey: save artifact set changed")
	print("Formal player journey: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _save_artifacts_match(left: Dictionary, right: Dictionary) -> bool:
	if bool(right.get("read_error", false)):
		return false
	var left_artifacts := left.get("artifacts", {}) as Dictionary
	var right_artifacts := right.get("artifacts", {}) as Dictionary
	if left_artifacts.size() != right_artifacts.size():
		return false
	for suffix: String in TIME_SUPPORT.FORMAL_SAVE_ARTIFACT_SUFFIXES:
		var left_artifact := left_artifacts.get(suffix, {}) as Dictionary
		var right_artifact := right_artifacts.get(suffix, {}) as Dictionary
		if bool(left_artifact.get("exists", false)) != bool(right_artifact.get("exists", false)):
			return false
		var left_bytes := left_artifact.get("bytes", PackedByteArray()) as PackedByteArray
		var right_bytes := right_artifact.get("bytes", PackedByteArray()) as PackedByteArray
		if left_bytes != right_bytes:
			return false
	return true
