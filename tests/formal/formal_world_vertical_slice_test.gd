extends SceneTree
## Canonical player-facing vertical slice. It uses only the configured title,
## formal scene, registered UI hit targets and real input events.

const MENU_SCENE := "res://scenes/formal/formal_world_menu.tscn"
const TIME_SUPPORT := preload(
	"res://tests/variable_state/formal_time_test_support.gd"
)

var failures: int = 0
var checks: int = 0
var save_backup: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	save_backup = TIME_SUPPORT.backup_formal_save()
	if not _require(
		not bool(save_backup.get("read_error", false)),
		"无法备份现有正式存档"
	) or not _require(
		TIME_SUPPORT.cleanup_formal_save(),
		"无法建立隔离的纵切旅程存档"
	):
		await _finish()
		return

	var change_error := change_scene_to_file(MENU_SCENE)
	if not _require(change_error == OK, "BOOT 未能加载正式标题场景"):
		await _finish()
		return
	await _settle_frames(5)
	var menu := current_scene as FormalWorldMenu
	if not _require(
		menu != null and menu.title_label.text == "1900",
		"BOOT 未到达正式标题"
	):
		await _finish()
		return

	await _press_key(KEY_SPACE)
	var application := await _wait_for_application()
	if not _require(application != null, "ENTER WORLD 未进入正式世界"):
		await _finish()
		return
	if not _require(application.formal_simulation.initialized, "正式世界未初始化"):
		await _finish()
		return
	if not _require(application._data_errors.is_empty(), "正式地图/HUD 存在数据错误"):
		await _finish()
		return

	application._ensure_projection_cache()
	if not _require(
		application._history_entity_by_id.size() == 151,
		"正式世界地图未就绪"
	):
		await _finish()
		return
	var player := application.formal_simulation.player_summary()
	_require(str(player.get("name_zh", "")) == "埃蒂安·莫罗", "当前玩家人物未显示")
	var visible_player := application._character_profiles.get(
		application.active_character_key, {}
	) as Dictionary
	_require(
		application._character_profiles.size() == 1
		and str(visible_player.get("id", "")) == str(player.get("person_id", ""))
		and str(visible_player.get("display_name_zh", ""))
		== str(player.get("name_zh", "")),
		"正式 HUD 与垂直切片显示了不同的当前玩家"
	)
	_require(
		str(player.get("position_title_zh", "")) == "港口调度员",
		"玩家岗位未显示"
	)
	_require(
		str(player.get("organization_name_zh", "")) == "马赛港务机构",
		"玩家组织未显示"
	)
	_require(
		bool(player.get("membership_active", false)),
		"组织成员身份未由权威状态确认"
	)
	_require(
		str(
			(player.get("employment", {}) as Dictionary).get(
				"employer_organization_id", ""
			)
		) == "organization:marseille_port_authority",
		"雇佣关系未与成员关系分别呈现"
	)
	_require(bool(player.get("authorized", false)), "岗位能力未授予运输优先权")
	var session := application.formal_simulation.player_session
	var organization_id := str(session.organization.get("organization_id", ""))
	var position_id := str(session.organization.get("position_id", ""))
	var capability_id := str(session.organization.get("capability_id", ""))
	_require(
		session.organization_core.revoke_capability(
			organization_id, position_id, capability_id
		),
		"负向授权测试无法撤销岗位能力"
	)
	var unauthorized_result := (
		application.formal_simulation.authorize_supply_transport_priority()
	)
	_require(
		not bool(unauthorized_result.get("success", true))
		and str(unauthorized_result.get("code", "")) == "not_authorized",
		"没有岗位能力的玩家动作未被权威拒绝"
	)
	_require(
		session.organization_core.grant_capability(
			organization_id, position_id, capability_id
		),
		"负向授权测试无法恢复岗位能力"
	)
	_require(session.is_authorized_for_decision(), "岗位能力恢复后授权未生效")

	# No transport is fabricated before a real shortage creates one.
	var initial_slice := application.formal_simulation.vertical_slice_summary()
	_require(
		str(initial_slice.get("shipment_status", "")) == "not_scheduled",
		"新世界不应伪造初始运输"
	)
	var early_result := (
		application.formal_simulation.authorize_supply_transport_priority()
	)
	_require(
		not bool(early_result.get("success", true))
		and str(early_result.get("code", "")) == "shipment_unavailable",
		"无真实运输时权威操作必须拒绝"
	)

	# Two visible week advances form the real day-14 Egyptian shortage and route.
	if not _require(
		await _click_action(application, "vertical_slice_week"),
		"推进 7 日按钮不可用"
	):
		await _finish()
		return
	if not _require(
		await _click_action(application, "vertical_slice_week"),
		"第二次推进 7 日按钮不可用"
	):
		await _finish()
		return
	var problem := application.formal_simulation.vertical_slice_summary()
	var destination := problem.get("destination", {}) as Dictionary
	var route := problem.get("route", {}) as Dictionary
	var shipment := problem.get("shipment", {}) as Dictionary
	_require(float(destination.get("demand_units", 0.0)) > 0.0, "面包需求未显示")
	_require(float(destination.get("unmet_units", 0.0)) > 0.0, "面包缺口未显示")
	_require(
		is_zero_approx(float(destination.get("inventory_units", -1.0))),
		"面包库存未显示"
	)
	_require(int(destination.get("price_centimes", 0)) > 0, "面包价格未显示")
	_require(
		float(destination.get("produced_units", 0.0)) > 0.0,
		"面包生产未显示"
	)
	_require(str(route.get("route_id", "")) == "sea:006", "真实运输路线未显示")
	_require(str(route.get("origin_port", "")) == "Marseille", "运输起点未显示")
	_require(
		str(route.get("destination_port", "")) == "Alexandria",
		"运输终点未显示"
	)
	_require(str(route.get("mode", "")) == "steamship", "运输方式未显示")
	_require(
		is_equal_approx(float(route.get("capacity_units_per_day", 0.0)), 1296.0),
		"权威路线容量未显示"
	)
	_require(
		str(problem.get("shipment_status", "")) == "in_transit",
		"真实在途运输未显示"
	)
	_require(float(shipment.get("units", 0.0)) > 0.0, "运输数量未显示")
	_require(int(problem.get("eta_hours", 0)) == 120, "标准 ETA 未显示")

	if not _require(
		await _click_action(application, "vertical_slice_locate"),
		"SELECT HOME REGION 按钮不可用"
	):
		await _finish()
		return
	_require(application.selected_country_id == "country_fra", "未选择正式法国实体")
	_require(
		application.selected_region_id == "mediterranean_coast",
		"未选择地中海沿岸"
	)
	_require(application.space_level == application.REGION, "未通过正式产品路由进入大区")

	var original_arrival := int(shipment.get("arrival_hour", 0))
	var unmet_before := float(destination.get("unmet_units", 0.0))
	if not _require(
		await _click_action(application, "vertical_slice_authorize"),
		"授权动作按钮不可用"
	):
		await _finish()
		return
	var authorized := application.formal_simulation.vertical_slice_summary()
	var authorized_shipment := authorized.get("shipment", {}) as Dictionary
	_require(
		bool(authorized_shipment.get("priority_authorized", false)),
		"权威运输状态未记录优先授权"
	)
	_require(
		int(authorized_shipment.get("arrival_hour", 0)) == original_arrival - 24,
		"港口优先通关未把 ETA 提前一日"
	)
	_require(int(authorized.get("eta_hours", 0)) == 96, "玩家可见 ETA 未刷新")
	var authorized_decision := authorized.get("decision", {}) as Dictionary
	var last_action := authorized_decision.get("last_action", {}) as Dictionary
	_require(
		str(last_action.get("shipment_id", ""))
		== str(authorized_shipment.get("shipment_id", "")),
		"玩家行动未进入正式会话权威状态"
	)
	var duplicate_result := (
		application.formal_simulation.authorize_supply_transport_priority()
	)
	_require(
		not bool(duplicate_result.get("success", true))
		and str(duplicate_result.get("code", "")) == "already_authorized",
		"同一运输不可重复授权"
	)

	var progress_before := int(authorized.get("progress_bp", 0))
	if not _require(
		await _click_action(application, "vertical_slice_day"),
		"ADVANCE DAY 按钮不可用"
	):
		await _finish()
		return
	var after_day := application.formal_simulation.vertical_slice_summary()
	_require(
		int(after_day.get("progress_bp", 0)) > progress_before,
		"推进一日后运输进度未变化"
	)
	_require(int(after_day.get("eta_hours", 0)) == 72, "推进一日后 ETA 未变化")

	for _day: int in range(3):
		if not await _click_action(application, "vertical_slice_day"):
			_require(false, "到货前推进一日按钮不可用")
			await _finish()
			return
	var delivered := application.formal_simulation.vertical_slice_summary()
	var delivered_destination := delivered.get("destination", {}) as Dictionary
	_require(
		str(delivered.get("shipment_status", "")) == "delivered",
		"优先运输未在 ETA 到货"
	)
	_require(int(delivered.get("progress_bp", 0)) == 10000, "到货进度未显示 100%")
	_require(
		float(delivered_destination.get("unmet_units", unmet_before)) < unmet_before,
		"真实到货未改善面包缺口"
	)
	_require(
		float(delivered_destination.get("unmet_units", 0.0)) > 0.0,
		"纵切没有伪造完全消除供应问题"
	)

	await _press_key(KEY_F5)
	_require(
		FileAccess.file_exists(FormalWorldSimulation.SAVE_PATH),
		"SAVE 未创建正式存档"
	)
	var saved_state := (
		application.formal_simulation.get_persistent_state().duplicate(true)
	)
	var saved_slice := (
		application.formal_simulation.vertical_slice_summary().duplicate(true)
	)
	change_error = change_scene_to_file(MENU_SCENE)
	if not _require(change_error == OK, "RESTART 未返回正式标题"):
		await _finish()
		return
	await _settle_frames(5)
	menu = current_scene as FormalWorldMenu
	_require(
		menu != null and menu.status_label.text.contains("存档"),
		"重启标题未提供继续反馈"
	)
	await _press_key(KEY_SPACE)
	var continued := await _wait_for_application()
	if not _require(continued != null, "CONTINUE 未恢复正式世界"):
		await _finish()
		return
	var continued_state := continued.formal_simulation.get_persistent_state()
	_require(
		int(continued_state.get("total_minutes", -1))
		== int(saved_state.get("total_minutes", -2)),
		"重启继续未恢复权威时间"
	)
	var session_difference := TIME_SUPPORT.first_semantic_difference(
		continued_state.get("player_session", {}),
		saved_state.get("player_session", {})
	)
	_require(
		session_difference.is_empty(),
		"重启继续未恢复玩家、成员、岗位、授权和行动：%s" % session_difference
	)
	var slice_difference := TIME_SUPPORT.first_semantic_difference(
		continued.formal_simulation.vertical_slice_summary(), saved_slice
	)
	_require(
		slice_difference.is_empty(),
		"重启继续未恢复人物、授权、行动与经济结果：%s" % slice_difference
	)

	await _finish()


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
		if (
			str(record.get("action", "")) != action
			or not bool(record.get("enabled", false))
		):
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


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _require(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		return true
	failures += 1
	push_error("Formal vertical slice: " + message)
	return false


func _finish() -> void:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	if not TIME_SUPPORT.restore_formal_save(save_backup):
		failures += 1
		push_error("Formal vertical slice: 无法恢复测试前正式存档")
	print("Formal vertical slice: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
