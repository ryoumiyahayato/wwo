class_name GameSaveService
extends RefCounted
## Versioned JSON save boundary with validation and temporary-file replacement.

const SAVE_VERSION: int = 1
const MANUAL_PATH: String = "user://saves/manual.json"
const AUTOSAVE_PATH: String = "user://saves/autosave.json"
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
	return {
		"save_version": SAVE_VERSION,
		"config_versions": {"world": 1, "clock": 1, "character": 1, "action": 1, "society": 1},
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
	var directory: String = absolute_path.get_base_dir()
	var make_error: Error = DirAccess.make_dir_recursive_absolute(directory)
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
	GameSessionService.settlement_log.add("save", "存档写入完成", int((snapshot["game_time"] as Dictionary)["total_hours"]), {"path": path})
	return SaveOperationResult.ok(path, snapshot)


func load_from_path(path: String) -> SaveOperationResult:
	var started: int = Time.get_ticks_usec()
	if not path.begins_with("user://"):
		return SaveOperationResult.fail("unsafe_path", "存档只能从 user:// 读取", path)
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "存档不存在", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail("read_error", error_string(FileAccess.get_open_error()), path)
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if parse_error != OK:
		return SaveOperationResult.fail("malformed_json", "第 %d 行：%s" % [json.get_error_line(), json.get_error_message()], path)
	if not json.data is Dictionary:
		return SaveOperationResult.fail("invalid_snapshot", "存档根节点必须是对象", path)
	var snapshot: Dictionary = json.data as Dictionary
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors), path)
	GameSessionService.performance_stats.record("load_parse", Time.get_ticks_usec() - started)
	return SaveOperationResult.ok(path, snapshot)


func restore_snapshot(snapshot: Dictionary, clock: SimulationClock, map_service: MapControlService) -> SaveOperationResult:
	var started: int = Time.get_ticks_usec()
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty() or clock == null or map_service == null:
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors) if not errors.is_empty() else "运行服务不可用")
	var character_state: Dictionary = snapshot["characters"] as Dictionary
	var active_records: Array = character_state["active"] as Array
	var player_record: Dictionary = {}
	for raw_record: Variant in active_records:
		if str((raw_record as Dictionary).get("id", "")) == str(snapshot["player_character_id"]):
			player_record = raw_record as Dictionary
			break
	if player_record.is_empty():
		return SaveOperationResult.fail("broken_reference", "玩家人物不在活跃人物中")
	var temporary_society := SocietySimulationService.new()
	var player := CharacterData.from_dict(player_record)
	if not temporary_society.initialize(player, map_service.data_set):
		return SaveOperationResult.fail("restore_error", temporary_society.initialization_error)
	if not temporary_society.roster.restore_persistent_state(character_state):
		return SaveOperationResult.fail("restore_error", "人物名册无效")
	if not temporary_society.organizations.restore_persistent_state(snapshot["organizations"] as Array):
		return SaveOperationResult.fail("restore_error", "组织状态无效")
	for raw_organization: Variant in temporary_society.organizations.organizations.values():
		var organization: OrganizationData = raw_organization as OrganizationData
		for member_id: String in organization.member_ids:
			if not temporary_society.roster.has_character(member_id):
				return SaveOperationResult.fail("broken_reference", "组织成员引用无效：%s" % member_id)
		if not organization.leader_character_id.is_empty() and not organization.member_ids.has(organization.leader_character_id):
			return SaveOperationResult.fail("broken_reference", "组织领导不在成员列表")
	if not temporary_society.relationships.restore_persistent_state(snapshot["relationships"] as Dictionary):
		return SaveOperationResult.fail("restore_error", "关系状态无效")
	if not temporary_society.ai.restore_persistent_state(snapshot["ai_states"] as Array):
		return SaveOperationResult.fail("restore_error", "AI 状态无效")
	var settlement_state: Dictionary = snapshot.get("settlement_state", {}) as Dictionary
	temporary_society.paused_settlement_categories = (settlement_state.get("paused_categories", {}) as Dictionary).duplicate(true)
	var action_ids := StableIdService.new()
	if not action_ids.restore_state(((snapshot["random_state"] as Dictionary)["action_id_service"] as Dictionary)):
		return SaveOperationResult.fail("restore_error", "行动 ID 状态无效")
	var selected_country_id: String = str(snapshot.get("selected_country_id", player.country_id))
	if not map_service.data_set.countries.has(selected_country_id):
		return SaveOperationResult.fail("broken_reference", "所选国家引用无效")
	if snapshot["current_action"] != null:
		var action_record: Dictionary = snapshot["current_action"] as Dictionary
		if not temporary_society.roster.has_character(str(action_record.get("actor_character_id", ""))) or not map_service.data_set.actions.has(str(action_record.get("definition_id", ""))):
			return SaveOperationResult.fail("broken_reference", "当前行动引用无效")
	if not map_service.restore_persistent_state(snapshot["world"] as Dictionary):
		return SaveOperationResult.fail("restore_error", "地图状态无效")
	if not clock.restore_persistent_state(snapshot["game_time"] as Dictionary):
		return SaveOperationResult.fail("restore_error", "游戏时间无效")
	var log_service := SettlementLogService.new()
	if not log_service.restore_state(snapshot.get("settlement_log", {"max_entries": 200, "entries": []}) as Dictionary):
		return SaveOperationResult.fail("restore_error", "结算日志无效")
	var performance := PerformanceStatsService.new()
	if not performance.restore_state(snapshot.get("performance_metrics", {}) as Dictionary):
		return SaveOperationResult.fail("restore_error", "性能统计无效")
	GameSessionService.player_character = temporary_society.roster.get_active(str(snapshot["player_character_id"]))
	GameSessionService.selected_country_id = selected_country_id
	GameSessionService.current_action = null if snapshot["current_action"] == null else ActionInstanceData.from_dict(snapshot["current_action"] as Dictionary)
	GameSessionService.action_id_service = action_ids
	GameSessionService.society_service = temporary_society
	GameSessionService.developer_mode = bool(snapshot.get("developer_mode", false))
	GameSessionService.settlement_log = log_service
	GameSessionService.performance_stats = performance
	temporary_society.attach_clock(clock)
	performance.record("restore", Time.get_ticks_usec() - started)
	log_service.add("load", "存档恢复完成", clock.total_hours)
	return SaveOperationResult.ok("", snapshot)


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
	if str(snapshot.get("player_character_id", "")).is_empty():
		errors.append("缺少玩家人物 ID")
	if not snapshot.has("current_action") or (snapshot["current_action"] != null and not snapshot["current_action"] is Dictionary):
		errors.append("当前行动字段无效")
	if errors.is_empty():
		var characters: Dictionary = snapshot["characters"] as Dictionary
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
	return errors
