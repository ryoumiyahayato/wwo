class_name DeveloperCommandService
extends RefCounted
## Explicit debug mutations. Every command is gated by developer mode and logged.

var clock: SimulationClock
var map_service: MapControlService
var save_service := GameSaveService.new()


func _init(simulation_clock: SimulationClock, control_service: MapControlService) -> void:
	clock = simulation_clock
	map_service = control_service


func set_enabled(enabled: bool) -> void:
	GameSessionService.developer_mode = enabled
	_log("开发模式%s" % ("开启" if enabled else "关闭"))


func get_hidden_character_state(character_id: String) -> Dictionary:
	var character: CharacterData = _active(character_id)
	return {} if character == null else {
		"hidden_aptitudes": character.hidden_aptitudes.duplicate(true),
		"temperament_weights": character.temperament_weights.duplicate(true),
		"tendencies": character.tendencies.duplicate(true),
		"generation_seed": character.generation_seed,
		"random_state": character.random_state,
		"ai": {} if _society().ai.get_state(character_id) == null else _society().ai.get_state(character_id).to_dict(),
	}


func set_character_age(character_id: String, age: int) -> bool:
	var character: CharacterData = _active(character_id)
	if not _allowed() or character == null or age < 12 or age > 100:
		return false
	character.age = age
	_log("调整人物年龄", {"character_id": character_id, "age": age})
	return true


func set_character_value(character_id: String, field: String, value: int) -> bool:
	var character: CharacterData = _active(character_id)
	if not _allowed() or character == null:
		return false
	if field == "wealth" or field == "reputation":
		character.current_status[field] = clampi(value, 0, 100)
	elif character.skills.has(field):
		character.skills[field] = clampi(value, 0, 100)
	else:
		return false
	_log("调整人物数值", {"character_id": character_id, "field": field, "value": value})
	return true


func set_character_seed(character_id: String, seed_value: int, random_state: int) -> bool:
	var character: CharacterData = _active(character_id)
	if not _allowed() or character == null:
		return false
	character.generation_seed = seed_value
	character.random_state = random_state
	_log("调整人物随机状态", {"character_id": character_id})
	return true


func copy_character_seed(character_id: String) -> String:
	var character: CharacterData = _active(character_id)
	if character == null:
		return ""
	var text: String = "%d" % character.generation_seed
	DisplayServer.clipboard_set(text)
	return text


func set_true_tendency(character_id: String, tendency_id: String, value: int) -> bool:
	var character: CharacterData = _active(character_id)
	if not _allowed() or character == null or not character.tendencies.has(tendency_id):
		return false
	character.tendencies[tendency_id] = clampi(value, -100, 100)
	_log("调整人物真实倾向", {"character_id": character_id, "tendency_id": tendency_id})
	return true


func take_control(character_id: String) -> bool:
	if not _allowed() or _society() == null:
		return false
	var character: CharacterData = _society().roster.get_active(character_id)
	if character == null:
		character = _society().promote_background(character_id)
	if character == null:
		return false
	_society().ai.unregister(character_id)
	_society().roster.set_player_character(character)
	GameSessionService.transfer_player(character)
	_log("接管人物", {"character_id": character_id})
	return true


func promote_character(character_id: String) -> bool:
	var success: bool = _allowed() and _society() != null and _society().promote_background(character_id) != null
	if success:
		_log("升级背景人物", {"character_id": character_id})
	return success


func demote_character(character_id: String) -> bool:
	var success: bool = _allowed() and _society() != null and _society().demote_active(character_id) != null
	if success:
		_log("降级活跃人物", {"character_id": character_id})
	return success


func join_organization(character_id: String, organization_id: String) -> bool:
	var character: CharacterData = _active(character_id)
	var success: bool = _allowed() and character != null and _society().organizations.join_organization(character, organization_id)
	if success:
		_log("调整组织成员", {"character_id": character_id, "organization_id": organization_id})
	return success


func leave_organization(character_id: String, organization_id: String) -> bool:
	var character: CharacterData = _active(character_id)
	var success: bool = _allowed() and character != null and _society().organizations.leave_organization(character, organization_id)
	if success:
		_log("人物离开组织", {"character_id": character_id, "organization_id": organization_id})
	return success


func assign_position(character_id: String, organization_id: String, position_id: String) -> bool:
	var character: CharacterData = _active(character_id)
	var success: bool = _allowed() and character != null and _society().organizations.assign_position(character, organization_id, position_id)
	if success:
		_log("调整人物职位", {"character_id": character_id, "position_id": position_id})
	return success


func set_relationship(character_a_id: String, character_b_id: String, trust: float, affinity: float) -> bool:
	if not _allowed() or _society() == null:
		return false
	var relationship: RelationshipData = _society().relationships.create_or_update(character_a_id, character_b_id, clock.total_hours)
	if relationship == null:
		return false
	relationship.trust = clampf(trust, -1.0, 1.0)
	relationship.affinity = clampf(affinity, -1.0, 1.0)
	_log("调整人物关系", {"relationship_id": relationship.id})
	return true


func force_action(mode: String) -> bool:
	var action: ActionInstanceData = GameSessionService.current_action
	if not _allowed() or action == null or action.is_terminal():
		return false
	match mode:
		"pause":
			action.status = ActionInstanceData.STATUS_PAUSED
		"success", "failure", "complete":
			action.status = ActionInstanceData.STATUS_COMPLETED
			action.completion_hour = clock.total_hours
			action.last_update_hour = clock.total_hours
			action.accumulated_work = action.total_work
			action.outcome_code = action.outcome_code if mode == "complete" else mode
			action.result_description = "开发工具立即完成" if mode == "complete" else "开发工具强制%s" % ("成功" if mode == "success" else "失败")
		_:
			return false
	_log("强制行动状态", {"mode": mode, "action_id": action.id})
	return true


func set_map_control(unit_id: String, controller_country_id: String, strength: float, contested: float) -> bool:
	var success: bool = _allowed() and map_service.set_control_state(unit_id, controller_country_id, strength, contested)
	if success:
		_log("调整地图控制", {"unit_id": unit_id})
	return success


func apply_map_pressure(unit_id: String, country_id: String, intensity: float) -> bool:
	var success: bool = _allowed() and map_service.apply_control_pressure(unit_id, country_id, intensity)
	if success:
		_log("施加地图压力", {"unit_id": unit_id})
	return success


func force_contested(unit_id: String) -> bool:
	var unit: ControlUnitData = map_service.get_unit(unit_id)
	return false if unit == null else set_map_control(unit_id, unit.controller_country_id, unit.control_strength, 1.0)


func set_speed(multiplier: int) -> bool:
	return _allowed() and clock.set_speed(multiplier)


func step_hours(hours: int) -> bool:
	if not _allowed() or hours < 1 or hours > 744:
		return false
	clock.advance_hours(hours)
	_log("推进游戏时间", {"hours": hours})
	return true


func set_game_date(year: int, month: int, day: int, hour: int = 0) -> bool:
	if not _allowed() or not clock.set_datetime_for_debug(year, month, day, hour):
		return false
	_log("设置游戏日期", {"year": year, "month": month, "day": day, "hour": hour})
	return true


func set_settlement_paused(category: String, paused: bool) -> bool:
	if not _allowed() or _society() == null or not category in ["daily_ai", "monthly_ai"]:
		return false
	_society().set_settlement_paused(category, paused)
	_log("调整结算暂停", {"category": category, "paused": paused})
	return true


func save_manual() -> SaveOperationResult:
	return save_service.save_manual(clock, map_service)


func load_manual() -> SaveOperationResult:
	var loaded: SaveOperationResult = save_service.load_from_path(GameSaveService.MANUAL_PATH)
	return loaded if not loaded.success else save_service.restore_snapshot(loaded.snapshot, clock, map_service)


func execute_text_command(command_line: String) -> Dictionary:
	var parts: PackedStringArray = command_line.strip_edges().split(" ", false)
	if parts.is_empty():
		return {"success": false, "message": "命令为空"}
	var command: String = parts[0].to_lower()
	var success: bool = false
	var data: Dictionary = {}
	match command:
		"inspect":
			data = get_hidden_character_state(_part(parts, 1))
			success = not data.is_empty()
		"copy_seed":
			var copied: String = copy_character_seed(_part(parts, 1))
			data = {"seed": copied}
			success = not copied.is_empty()
		"seed":
			success = parts.size() >= 4 and set_character_seed(_part(parts, 1), int(_part(parts, 2)), int(_part(parts, 3)))
		"age":
			success = parts.size() >= 3 and set_character_age(_part(parts, 1), int(_part(parts, 2)))
		"value":
			success = parts.size() >= 4 and set_character_value(_part(parts, 1), _part(parts, 2), int(_part(parts, 3)))
		"tendency":
			success = parts.size() >= 4 and set_true_tendency(_part(parts, 1), _part(parts, 2), int(_part(parts, 3)))
		"take":
			success = take_control(_part(parts, 1))
		"promote":
			success = promote_character(_part(parts, 1))
		"demote":
			success = demote_character(_part(parts, 1))
		"join":
			success = join_organization(_part(parts, 1), _part(parts, 2))
		"leave":
			success = leave_organization(_part(parts, 1), _part(parts, 2))
		"position":
			success = assign_position(_part(parts, 1), _part(parts, 2), _part(parts, 3))
		"relationship":
			success = parts.size() >= 5 and set_relationship(_part(parts, 1), _part(parts, 2), float(_part(parts, 3)), float(_part(parts, 4)))
		"action":
			success = force_action(_part(parts, 1))
		"control":
			success = parts.size() >= 5 and set_map_control(_part(parts, 1), _part(parts, 2), float(_part(parts, 3)), float(_part(parts, 4)))
		"pressure":
			success = parts.size() >= 4 and apply_map_pressure(_part(parts, 1), _part(parts, 2), float(_part(parts, 3)))
		"contested":
			success = force_contested(_part(parts, 1))
		"date":
			success = parts.size() >= 4 and set_game_date(int(_part(parts, 1)), int(_part(parts, 2)), int(_part(parts, 3)), int(_part(parts, 4, "0")))
		"speed":
			success = set_speed(int(_part(parts, 1)))
		"step":
			success = step_hours(int(_part(parts, 1)))
		"pause_settlement":
			success = set_settlement_paused(_part(parts, 1), _part(parts, 2) in ["1", "true", "on"])
		_:
			return {"success": false, "message": "未知命令：%s" % command}
	return {"success": success, "message": "命令已执行" if success else "命令参数或状态不允许", "data": data}


func _allowed() -> bool:
	return GameSessionService.developer_mode


func _society() -> SocietySimulationService:
	return GameSessionService.society_service


func _active(character_id: String) -> CharacterData:
	return null if _society() == null else _society().roster.get_active(character_id)


func _log(message: String, details: Dictionary = {}) -> void:
	GameSessionService.settlement_log.add("developer", message, 0 if clock == null else clock.total_hours, details)


static func _part(parts: PackedStringArray, index: int, fallback: String = "") -> String:
	return parts[index] if index >= 0 and index < parts.size() else fallback
