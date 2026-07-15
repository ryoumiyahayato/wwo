class_name GameSaveService
extends RefCounted

const SAVE_VERSION: int = 1
const MANUAL_PATH: String = "user://saves/manual.json"
const AUTOSAVE_PATH: String = "user://saves/autosave.json"
const CONFIG_VERSIONS: Dictionary = {
	"world": 1,
	"clock": 1,
	"character": 1,
	"action": 1,
	"society": 1,
}
const REQUIRED_CHARACTER_FIELDS: Array[String] = [
	"id", "name", "age", "country_id", "region_id", "occupation_id", "occupation",
	"public_position", "organization_ids", "relationship_ids", "hidden_aptitudes",
	"temperament_weights", "skills", "manifested_traits", "tendencies",
	"known_tendencies", "current_status", "is_active", "random_mode",
	"random_category", "is_challenge_start", "generation_seed", "random_state",
]


func build_snapshot(clock: SimulationClock, map_service: MapControlService) -> Dictionary:
	var society: SocietySimulationService = GameSessionService.society_service
	if clock == null or map_service == null or society == null or not GameSessionService.has_player():
		return {}
	_archive_terminal_player_action(society, map_service)
	return {
		"save_version": SAVE_VERSION,
		"config_versions": CONFIG_VERSIONS.duplicate(true),
		"game_time": clock.get_persistent_state(),
		"player_character_id": society.roster.player_character_id,
		"selected_country_id": GameSessionService.selected_country_id,
		"world": map_service.get_persistent_state(),
		"characters": society.roster.get_persistent_state(),
		"organizations": society.organizations.get_persistent_state(),
		"relationships": society.relationships.get_persistent_state(),
		"ai_states": society.ai.get_persistent_state(),
		"settlement_state": {"paused_categories": society.paused_settlement_categories.duplicate(true)},
		"current_action": null if GameSessionService.current_action == null else GameSessionService.current_action.to_dict(),
		"recent_action_result": GameSessionService.recent_action_result.duplicate(true),
		"action_history": GameSessionService.action_history.duplicate(true),
		"random_state": {"action_id_service": GameSessionService.action_id_service.get_state()},
		"developer_mode": GameSessionService.developer_mode,
		"settlement_log": GameSessionService.settlement_log.get_state(),
		"performance_metrics": GameSessionService.performance_stats.get_snapshot(),
	}


func save_manual(clock: SimulationClock, map_service: MapControlService) -> SaveOperationResult:
	return save_to_path(MANUAL_PATH, build_snapshot(clock, map_service))


func save_autosave(clock: SimulationClock, map_service: MapControlService) -> SaveOperationResult:
	return save_to_path(AUTOSAVE_PATH, build_snapshot(clock, map_service))


func save_to_path(path: String, snapshot: Dictionary) -> SaveOperationResult:
	var started: int = Time.get_ticks_usec()
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors), path)
	if not path.begins_with("user://") or not path.ends_with(".json"):
		return SaveOperationResult.fail("unsafe_path", "存档只能写入 user:// 下的 JSON 文件", path)
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if make_error != OK:
		return SaveOperationResult.fail("directory_error", error_string(make_error), path)
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return SaveOperationResult.fail("write_error", error_string(FileAccess.get_open_error()), path)
	file.store_string(JSON.stringify(snapshot, "\t", false))
	file.flush()
	file.close()
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(absolute_path):
		var backup_error: Error = DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return SaveOperationResult.fail("replace_error", error_string(backup_error), path)
	var replace_error: Error = DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(temporary_path)
		return SaveOperationResult.fail("replace_error", error_string(replace_error), path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	GameSessionService.performance_stats.record("save", Time.get_ticks_usec() - started)
	GameSessionService.settlement_log.add(
		"save",
		"存档写入完成",
		int((snapshot["game_time"] as Dictionary)["total_hours"]),
		{"path": path}
	)
	return SaveOperationResult.ok(path, snapshot)


func load_from_path(path: String) -> SaveOperationResult:
	var started: int = Time.get_ticks_usec()
	if not path.begins_with("user://") or not path.ends_with(".json"):
		return SaveOperationResult.fail("unsafe_path", "存档只能从 user:// 下的 JSON 文件读取", path)
	var primary: SaveOperationResult = _load_snapshot_file(path)
	if primary.success:
		GameSessionService.performance_stats.record("load_parse", Time.get_ticks_usec() - started)
		return primary
	var backup_path: String = path + ".bak"
	if FileAccess.file_exists(backup_path):
		var backup: SaveOperationResult = _load_snapshot_file(backup_path)
		if backup.success:
			backup.path = path
			backup.message = "主存档不可用，已读取安全备份"
			GameSessionService.performance_stats.record("load_parse", Time.get_ticks_usec() - started)
			return backup
	return primary


func _load_snapshot_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "存档不存在", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail("read_error", error_string(FileAccess.get_open_error()), path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
			path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail("invalid_snapshot", "存档根节点必须是对象", path)
	var snapshot: Dictionary = parser.data as Dictionary
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors), path)
	return SaveOperationResult.ok(path, snapshot)


func restore_snapshot(
	snapshot: Dictionary,
	clock: SimulationClock,
	map_service: MapControlService
) -> SaveOperationResult:
	var started: int = Time.get_ticks_usec()
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty() or clock == null or map_service == null:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"; ".join(errors) if not errors.is_empty() else "运行服务不可用"
		)
	var top_player_id: String = str(snapshot["player_character_id"])
	var character_state: Dictionary = snapshot["characters"] as Dictionary
	var active_records: Array = character_state["active"] as Array
	var player_record: Dictionary = {}
	for raw_record: Variant in active_records:
		if raw_record is Dictionary and str((raw_record as Dictionary).get("id", "")) == top_player_id:
			player_record = raw_record as Dictionary
			break
	if player_record.is_empty():
		return SaveOperationResult.fail("broken_reference", "玩家人物不在活跃人物中")

	var temporary_society := SocietySimulationService.new()
	var seed_player := CharacterData.from_dict(player_record)
	if not temporary_society.initialize(seed_player, map_service.data_set):
		return SaveOperationResult.fail("restore_error", temporary_society.initialization_error)
	if not temporary_society.roster.restore_persistent_state(character_state):
		return SaveOperationResult.fail("restore_error", "人物名册无效或超过活跃上限")
	var restored_player: CharacterData = temporary_society.roster.get_active(top_player_id)
	if restored_player == null:
		return SaveOperationResult.fail("broken_reference", "恢复后的玩家人物不存在")
	if not temporary_society.organizations.restore_persistent_state(snapshot["organizations"] as Array):
		return SaveOperationResult.fail("restore_error", "组织状态无效")
	for raw_organization: Variant in temporary_society.organizations.organizations.values():
		var organization: OrganizationData = raw_organization as OrganizationData
		for member_id: String in organization.member_ids:
			if not temporary_society.roster.has_character(member_id):
				return SaveOperationResult.fail("broken_reference", "组织成员引用无效：%s" % member_id)
	if not temporary_society.relationships.restore_persistent_state(snapshot["relationships"] as Dictionary):
		return SaveOperationResult.fail("restore_error", "关系状态或关系 ID 计数器无效")
	var social_error: String = SocialSaveValidator.new().validate(temporary_society)
	if not social_error.is_empty():
		return SaveOperationResult.fail("broken_reference", social_error)

	var raw_action_id_state: Dictionary = (snapshot["random_state"] as Dictionary)["action_id_service"] as Dictionary
	var action_ids := StableIdService.new()
	if not action_ids.restore_state(raw_action_id_state):
		return SaveOperationResult.fail("restore_error", "行动 ID 状态无效")
	var current_hour: int = int((snapshot["game_time"] as Dictionary).get("total_hours", -1))
	var previous_world_state: Dictionary = map_service.get_persistent_state()
	if not map_service.restore_persistent_state(snapshot["world"] as Dictionary):
		return SaveOperationResult.fail("restore_error", "地图状态无效")

	var seen_action_ids: Dictionary = {}
	if snapshot["current_action"] is Dictionary:
		var player_action_id: String = str(
			(snapshot["current_action"] as Dictionary).get("id", "")
		)
		if player_action_id.is_empty():
			return _fail_and_restore_map(
				map_service, previous_world_state, "broken_reference", "玩家行动缺少实例 ID"
			)
		seen_action_ids[player_action_id] = top_player_id
	var restored_history: Array[Dictionary] = []
	for raw_history_record: Variant in snapshot.get("action_history", []) as Array:
		restored_history.append((raw_history_record as Dictionary).duplicate(true))
	var restored_recent: Dictionary = (
		(snapshot.get("recent_action_result", {}) as Dictionary).duplicate(true)
	)
	var history_error: String = _validate_action_result_records(
		restored_history,
		restored_recent,
		map_service,
		current_hour,
		raw_action_id_state,
		seen_action_ids
	)
	if not history_error.is_empty():
		return _fail_and_restore_map(
			map_service, previous_world_state, "broken_reference", history_error
		)
	var ai_action_error: String = _validate_ai_action_records(
		snapshot["ai_states"] as Array,
		temporary_society,
		map_service,
		current_hour,
		raw_action_id_state,
		seen_action_ids
	)
	if not ai_action_error.is_empty():
		return _fail_and_restore_map(
			map_service, previous_world_state, "broken_reference", ai_action_error
		)
	if not temporary_society.ai.restore_persistent_state(snapshot["ai_states"] as Array):
		return _fail_and_restore_map(
			map_service, previous_world_state, "restore_error", "AI 状态未覆盖全部活跃 NPC"
		)

	var settlement_state: Dictionary = snapshot.get("settlement_state", {}) as Dictionary
	var paused_categories: Variant = settlement_state.get("paused_categories", {})
	if not paused_categories is Dictionary:
		return _fail_and_restore_map(
			map_service, previous_world_state, "restore_error", "暂停结算类别无效"
		)
	temporary_society.paused_settlement_categories = (paused_categories as Dictionary).duplicate(true)

	var selected_country_id: String = str(snapshot["selected_country_id"])
	if not map_service.data_set.countries.has(selected_country_id):
		return _fail_and_restore_map(
			map_service, previous_world_state, "broken_reference", "所选国家引用无效"
		)
	if selected_country_id != restored_player.country_id:
		return _fail_and_restore_map(
			map_service, previous_world_state, "broken_reference", "所选国家与玩家人物国家不一致"
		)

	var restored_action: ActionInstanceData
	if snapshot["current_action"] != null:
		var action_record: Dictionary = snapshot["current_action"] as Dictionary
		var action_error: String = ActionSaveValidator.new().validate(
			action_record,
			temporary_society,
			map_service,
			current_hour,
			raw_action_id_state
		)
		if not action_error.is_empty():
			return _fail_and_restore_map(
				map_service, previous_world_state, "broken_reference", action_error
			)
		restored_action = ActionInstanceData.from_dict(action_record)
		if restored_action.is_terminal():
			var migrated_record: Dictionary = GameSessionService.build_action_result_record(
				restored_action, restored_player
			)
			if not migrated_record.is_empty():
				restored_history.append(migrated_record.duplicate(true))
				while restored_history.size() > 100:
					restored_history.pop_front()
				restored_recent = migrated_record
			restored_action = null

	var log_service := SettlementLogService.new()
	if not log_service.restore_state(snapshot.get("settlement_log", {"max_entries": 200, "entries": []}) as Dictionary):
		return _fail_and_restore_map(
			map_service, previous_world_state, "restore_error", "结算日志无效"
		)
	var performance := PerformanceStatsService.new()
	if not performance.restore_state(snapshot.get("performance_metrics", {}) as Dictionary):
		return _fail_and_restore_map(
			map_service, previous_world_state, "restore_error", "性能统计无效"
		)

	var previous_clock_state: Dictionary = clock.get_persistent_state()
	if not clock.restore_persistent_state(snapshot["game_time"] as Dictionary):
		map_service.restore_persistent_state(previous_world_state)
		clock.restore_persistent_state(previous_clock_state)
		return SaveOperationResult.fail("restore_error", "游戏时间与累计小时不一致或字段无效")

	GameSessionService.player_character = restored_player
	GameSessionService.selected_country_id = selected_country_id
	GameSessionService.current_action = restored_action
	GameSessionService.restore_action_results(restored_recent, restored_history)
	GameSessionService.action_id_service = action_ids
	GameSessionService.society_service = temporary_society
	GameSessionService.developer_mode = bool(snapshot.get("developer_mode", false))
	GameSessionService.settlement_log = log_service
	GameSessionService.performance_stats = performance
	temporary_society.attach_world(clock, map_service)
	performance.record("restore", Time.get_ticks_usec() - started)
	log_service.add("load", "存档恢复完成", clock.total_hours)
	return SaveOperationResult.ok("", snapshot)


func _fail_and_restore_map(
	map_service: MapControlService,
	previous_world_state: Dictionary,
	code: String,
	message: String
) -> SaveOperationResult:
	map_service.restore_persistent_state(previous_world_state)
	return SaveOperationResult.fail(code, message)


func _validate_ai_action_records(
	records: Array,
	society: SocietySimulationService,
	map_service: MapControlService,
	current_hour: int,
	action_id_state: Dictionary,
	seen_action_ids: Dictionary
) -> String:
	var validator := ActionSaveValidator.new()
	for raw_state: Variant in records:
		if not raw_state is Dictionary:
			return "AI 状态记录必须是对象"
		var state: Dictionary = raw_state as Dictionary
		var character_id: String = str(state.get("character_id", ""))
		var raw_action: Variant = state.get("current_action_record", {})
		if not raw_action is Dictionary:
			return "NPC 进行中行动必须是对象"
		var action_record: Dictionary = raw_action as Dictionary
		if action_record.is_empty():
			continue
		if str(action_record.get("actor_character_id", "")) != character_id:
			return "NPC 行动人物与 AI 状态人物不一致"
		var action_id: String = str(action_record.get("id", ""))
		if action_id.is_empty():
			return "NPC 行动缺少实例 ID：%s" % character_id
		if seen_action_ids.has(action_id):
			return "行动实例 ID 重复：%s（%s 与 %s）" % [
				action_id, str(seen_action_ids[action_id]), character_id
			]
		seen_action_ids[action_id] = character_id
		var action := ActionInstanceData.from_dict(action_record)
		if action.status not in [ActionInstanceData.STATUS_ACTIVE, ActionInstanceData.STATUS_PAUSED]:
			return "NPC 持久行动必须处于进行中或暂停状态"
		if str(state.get("current_action_id", "")) != action.definition_id:
			return "NPC 当前行动标识与行动记录不一致：%s" % character_id
		var error: String = validator.validate(
			action_record,
			society,
			map_service,
			current_hour,
			action_id_state,
			false
		)
		if not error.is_empty():
			return "NPC 行动 %s 无效：%s" % [character_id, error]
	return ""


func validate_snapshot(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(snapshot.get("save_version", -1)) != SAVE_VERSION:
		errors.append("不支持的存档版本")
	for field: String in ["config_versions", "game_time", "world", "characters", "relationships", "random_state"]:
		if not snapshot.get(field) is Dictionary:
			errors.append("字段 %s 必须是对象" % field)
	for field: String in ["organizations", "ai_states"]:
		if not snapshot.get(field) is Array:
			errors.append("字段 %s 必须是数组" % field)
	for optional_field: String in ["settlement_state", "settlement_log", "performance_metrics"]:
		if snapshot.has(optional_field) and not snapshot[optional_field] is Dictionary:
			errors.append("字段 %s 必须是对象" % optional_field)
	if snapshot.has("recent_action_result") and not snapshot["recent_action_result"] is Dictionary:
		errors.append("最近行动结果字段必须是对象")
	if snapshot.has("action_history") and not snapshot["action_history"] is Array:
		errors.append("行动日志字段必须是数组")
	var player_id: String = str(snapshot.get("player_character_id", ""))
	if player_id.is_empty():
		errors.append("缺少玩家人物 ID")
	if str(snapshot.get("selected_country_id", "")).is_empty():
		errors.append("缺少所选国家 ID")
	if not snapshot.has("current_action") or (snapshot["current_action"] != null and not snapshot["current_action"] is Dictionary):
		errors.append("当前行动字段无效")
	if not errors.is_empty():
		return errors
	var config_versions: Dictionary = snapshot["config_versions"] as Dictionary
	for config_id: String in CONFIG_VERSIONS:
		if int(config_versions.get(config_id, -1)) != int(CONFIG_VERSIONS[config_id]):
			errors.append("配置版本不兼容：%s" % config_id)
	var characters: Dictionary = snapshot["characters"] as Dictionary
	if str(characters.get("player_character_id", "")) != player_id:
		errors.append("顶层玩家 ID 与人物名册玩家 ID 不一致")
	for field: String in ["background", "active", "exited"]:
		if not characters.get(field) is Array:
			errors.append("人物字段 %s 必须是数组" % field)
	if not characters.get("activation_seeds") is Dictionary:
		errors.append("人物激活种子必须是对象")
	if characters.get("active") is Array:
		for raw_character: Variant in characters["active"]:
			if not raw_character is Dictionary:
				errors.append("活跃人物记录必须是对象")
				break
			for field: String in REQUIRED_CHARACTER_FIELDS:
				if not (raw_character as Dictionary).has(field):
					errors.append("活跃人物缺少字段 %s" % field)
					break
	var random_state: Dictionary = snapshot["random_state"] as Dictionary
	if not random_state.get("action_id_service") is Dictionary:
		errors.append("缺少行动 ID 状态")
	var settlement_state: Variant = snapshot.get("settlement_state", {})
	if settlement_state is Dictionary and not (settlement_state as Dictionary).get("paused_categories", {}) is Dictionary:
		errors.append("暂停结算类别必须是对象")
	return errors


func _archive_terminal_player_action(
	society: SocietySimulationService, map_service: MapControlService
) -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null or not action.is_terminal():
		return
	if action.status == ActionInstanceData.STATUS_COMPLETED and not action.domain_effect_applied:
		var definition: ActionDefinitionData = map_service.data_set.actions.get(
			action.definition_id
		) as ActionDefinitionData
		if definition != null:
			society.apply_action_domain_effect(action, definition, map_service)
	GameSessionService.archive_current_action(GameSessionService.player_character)


func _validate_action_result_records(
	history: Array[Dictionary],
	recent: Dictionary,
	map_service: MapControlService,
	current_hour: int,
	action_id_state: Dictionary,
	seen_action_ids: Dictionary
) -> String:
	if history.size() > 100:
		return "行动日志超过 100 条上限"
	for record: Dictionary in history:
		var error: String = _validate_action_result_record(
			record, map_service, current_hour, action_id_state
		)
		if not error.is_empty():
			return error
		var action_id: String = str(record.get("action_id", ""))
		if seen_action_ids.has(action_id):
			return "行动实例 ID 重复：%s" % action_id
		seen_action_ids[action_id] = str(record.get("actor_character_id", ""))
	if not recent.is_empty():
		var recent_error: String = _validate_action_result_record(
			recent, map_service, current_hour, action_id_state
		)
		if not recent_error.is_empty():
			return recent_error
		if history.is_empty() or recent != history[history.size() - 1]:
			return "最近行动结果与行动日志末条不一致"
	return ""


func _validate_action_result_record(
	record: Dictionary,
	map_service: MapControlService,
	current_hour: int,
	action_id_state: Dictionary
) -> String:
	for field: String in [
		"action_id", "definition_id", "actor_character_id", "target_id",
		"study_skill_id", "status", "outcome_code", "result_description",
		"skill_id",
	]:
		if typeof(record.get(field, null)) != TYPE_STRING:
			return "行动结果字段 %s 必须是字符串" % field
	for field: String in ["skill_delta", "wealth_delta", "duration_hours", "completion_hour"]:
		if typeof(record.get(field, null)) not in [TYPE_INT, TYPE_FLOAT]:
			return "行动结果字段 %s 必须是数值" % field
	var action_id: String = str(record.get("action_id", ""))
	if not ActionSaveValidator.id_state_covers(
		action_id_state, action_id, "action_instance"
	):
		return "行动日志 ID 计数器落后：%s" % action_id
	if not map_service.data_set.actions.has(str(record.get("definition_id", ""))):
		return "行动日志定义引用无效"
	if str(record.get("status", "")) not in [
		ActionInstanceData.STATUS_COMPLETED,
		ActionInstanceData.STATUS_CANCELLED,
		ActionInstanceData.STATUS_INTERRUPTED,
	]:
		return "行动日志包含非终态行动"
	if str(record.get("result_description", "")).is_empty():
		return "行动日志缺少结果摘要"
	if int(record.get("duration_hours", -1)) < 0:
		return "行动日志用时无效"
	var completion_hour: int = int(record.get("completion_hour", -1))
	if completion_hour < 0 or completion_hour > current_hour:
		return "行动日志完成时间无效"
	return ""
