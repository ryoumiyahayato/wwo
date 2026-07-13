class_name GameSaveService
extends RefCounted
## Versioned JSON save boundary with validation, backup recovery and transactional restore.

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
const ACTION_CONTEXT_NUMERIC_FIELDS: Array[String] = [
	"organization_support", "relationship_support", "funding", "preparation", "target_resistance",
]
const ACTION_TERMINAL_STATUSES: Array[String] = [
	ActionInstanceData.STATUS_COMPLETED,
	ActionInstanceData.STATUS_CANCELLED,
	ActionInstanceData.STATUS_INTERRUPTED,
]
const VALID_ACTION_OUTCOMES: Array[String] = ["failure", "success", "guaranteed_success"]


func build_snapshot(clock: SimulationClock, map_service: MapControlService) -> Dictionary:
	var society: SocietySimulationService = GameSessionService.society_service
	if clock == null or map_service == null or society == null or not GameSessionService.has_player():
		return {}
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
	GameSessionService.settlement_log.add(
		"save", "存档写入完成",
		int((snapshot["game_time"] as Dictionary)["total_hours"]), {"path": path}
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
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json", "第 %d 行：%s" % [json.get_error_line(), json.get_error_message()], path
		)
	if not json.data is Dictionary:
		return SaveOperationResult.fail("invalid_snapshot", "存档根节点必须是对象", path)
	var snapshot: Dictionary = json.data as Dictionary
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
	var character_state: Dictionary = snapshot["characters"] as Dictionary
	var active_records: Array = character_state["active"] as Array
	var player_record: Dictionary = {}
	for raw_record: Variant in active_records:
		if not raw_record is Dictionary:
			return SaveOperationResult.fail("restore_error", "活跃人物记录无效")
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
	var social_index_error: String = _validate_social_indexes(temporary_society)
	if not social_index_error.is_empty():
		return SaveOperationResult.fail("broken_reference", social_index_error)
	if not temporary_society.ai.restore_persistent_state(snapshot["ai_states"] as Array):
		return SaveOperationResult.fail("restore_error", "AI 状态无效")

	var settlement_state: Dictionary = snapshot.get("settlement_state", {}) as Dictionary
	var paused_categories: Variant = settlement_state.get("paused_categories", {})
	if not paused_categories is Dictionary:
		return SaveOperationResult.fail("restore_error", "暂停结算类别无效")
	temporary_society.paused_settlement_categories = (paused_categories as Dictionary).duplicate(true)

	var action_ids := StableIdService.new()
	if not action_ids.restore_state(
		((snapshot["random_state"] as Dictionary)["action_id_service"] as Dictionary)
	):
		return SaveOperationResult.fail("restore_error", "行动 ID 状态无效")
	var selected_country_id: String = str(snapshot.get("selected_country_id", player.country_id))
	if not map_service.data_set.countries.has(selected_country_id):
		return SaveOperationResult.fail("broken_reference", "所选国家引用无效")

	var restored_action: ActionInstanceData
	if snapshot["current_action"] != null:
		var action_record: Dictionary = snapshot["current_action"] as Dictionary
		var saved_hour: int = int((snapshot["game_time"] as Dictionary).get("total_hours", -1))
		var action_error: String = _validate_current_action(
			action_record, temporary_society, map_service, saved_hour
		)
		if not action_error.is_empty():
			return SaveOperationResult.fail("broken_reference", action_error)
		restored_action = ActionInstanceData.from_dict(action_record)

	var log_service := SettlementLogService.new()
	if not log_service.restore_state(
		snapshot.get("settlement_log", {"max_entries": 200, "entries": []}) as Dictionary
	):
		return SaveOperationResult.fail("restore_error", "结算日志无效")
	var performance := PerformanceStatsService.new()
	if not performance.restore_state(snapshot.get("performance_metrics", {}) as Dictionary):
		return SaveOperationResult.fail("restore_error", "性能统计无效")

	# Commit mutable world state only after every independent structure has validated.
	var previous_world_state: Dictionary = map_service.get_persistent_state()
	var previous_clock_state: Dictionary = clock.get_persistent_state()
	if not map_service.restore_persistent_state(snapshot["world"] as Dictionary):
		return SaveOperationResult.fail("restore_error", "地图状态无效")
	if not clock.restore_persistent_state(snapshot["game_time"] as Dictionary):
		map_service.restore_persistent_state(previous_world_state)
		clock.restore_persistent_state(previous_clock_state)
		return SaveOperationResult.fail("restore_error", "游戏时间无效")

	GameSessionService.player_character = temporary_society.roster.get_active(
		str(snapshot["player_character_id"])
	)
	GameSessionService.selected_country_id = selected_country_id
	GameSessionService.current_action = restored_action
	GameSessionService.action_id_service = action_ids
	GameSessionService.society_service = temporary_society
	GameSessionService.developer_mode = bool(snapshot.get("developer_mode", false))
	GameSessionService.settlement_log = log_service
	GameSessionService.performance_stats = performance
	temporary_society.attach_world(clock, map_service)
	performance.record("restore", Time.get_ticks_usec() - started)
	log_service.add("load", "存档恢复完成", clock.total_hours)
	return SaveOperationResult.ok("", snapshot)


func _validate_current_action(
	record: Dictionary,
	society: SocietySimulationService,
	map_service: MapControlService,
	current_hour: int
) -> String:
	var actor_id: String = str(record.get("actor_character_id", ""))
	var definition_id: String = str(record.get("definition_id", ""))
	if actor_id.is_empty() or society.roster.get_active(actor_id) == null:
		return "当前行动人物引用无效"
	if actor_id != society.roster.player_character_id:
		return "当前行动不属于存档中的玩家人物"
	if not map_service.data_set.actions.has(definition_id):
		return "当前行动定义引用无效"
	if current_hour < 0:
		return "当前行动对应的存档时间无效"
	if not record.get("context") is Dictionary or not record.get("applied_effects") is Dictionary:
		return "当前行动上下文或结果结构无效"

	var action := ActionInstanceData.from_dict(record)
	var definition: ActionDefinitionData = map_service.data_set.actions[definition_id] as ActionDefinitionData
	if action.id.is_empty() or not StableIdService.is_valid_id(action.id) or StableIdService.get_namespace(action.id) != "action_instance":
		return "当前行动 ID 无效"
	if action.status not in [
		ActionInstanceData.STATUS_ACTIVE,
		ActionInstanceData.STATUS_PAUSED,
		ActionInstanceData.STATUS_COMPLETED,
		ActionInstanceData.STATUS_CANCELLED,
		ActionInstanceData.STATUS_INTERRUPTED,
	]:
		return "当前行动状态无效"
	if action.total_work <= 0.0 or not is_equal_approx(action.total_work, definition.total_work):
		return "当前行动总工作量与定义不一致"
	if action.accumulated_work < 0.0 or action.accumulated_work > action.total_work:
		return "当前行动进度无效"
	if action.current_efficiency <= 0.0 or action.current_efficiency > maxf(definition.base_progress_per_hour * 1000.0, 1.0):
		return "当前行动效率无效"
	if action.effective_value < -10000.0 or action.effective_value > 10000.0 or action.outlook.is_empty():
		return "当前行动计算指标无效"
	if action.start_hour < 0 or action.last_update_hour < action.start_hour or action.last_update_hour > current_hour:
		return "当前行动时间字段无效"

	var context_error: String = _validate_action_context(record["context"] as Dictionary, action)
	if not context_error.is_empty():
		return context_error
	var state_error: String = _validate_action_state(action)
	if not state_error.is_empty():
		return state_error
	var target_error: String = _validate_action_target(action, definition, society, map_service)
	if not target_error.is_empty():
		return target_error
	return ""


func _validate_action_context(context: Dictionary, action: ActionInstanceData) -> String:
	if typeof(context.get("target_id", "")) != TYPE_STRING:
		return "当前行动目标字段类型无效"
	if str(context.get("target_id", "")) != action.target_id:
		return "当前行动目标与上下文不一致"
	var raw_permissions: Variant = context.get("position_permissions", null)
	if not raw_permissions is Array:
		return "当前行动职位权限字段无效"
	var seen_permissions: Dictionary = {}
	for raw_permission: Variant in raw_permissions as Array:
		if typeof(raw_permission) != TYPE_STRING:
			return "当前行动职位权限必须为字符串"
		var permission: String = str(raw_permission)
		if permission.is_empty() or seen_permissions.has(permission):
			return "当前行动职位权限存在空值或重复值"
		seen_permissions[permission] = true
	for field: String in ACTION_CONTEXT_NUMERIC_FIELDS:
		var raw_value: Variant = context.get(field, null)
		if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT]:
			return "当前行动上下文字段 %s 类型无效" % field
		var value: float = float(raw_value)
		if value < 0.0 or value > 100.0:
			return "当前行动上下文字段 %s 超出范围" % field
	return ""


func _validate_action_state(action: ActionInstanceData) -> String:
	var unfinished: bool = action.status in [
		ActionInstanceData.STATUS_ACTIVE,
		ActionInstanceData.STATUS_PAUSED,
	]
	if unfinished:
		if action.accumulated_work >= action.total_work or action.completion_hour != -1:
			return "未完成行动具有完成状态数据"
		if not action.outcome_code.is_empty() or action.result_applied or action.domain_effect_applied:
			return "未完成行动具有已结算结果"
		if not action.result_description.is_empty() or not action.applied_effects.is_empty():
			return "未完成行动包含结果载荷"
		if not action.interruption_reason.is_empty():
			return "未完成行动包含中断原因"
		if action.status == ActionInstanceData.STATUS_ACTIVE and action.estimated_completion_hour <= action.last_update_hour:
			return "进行中行动预计完成时间无效"
		if action.status == ActionInstanceData.STATUS_PAUSED and action.estimated_completion_hour != -1:
			return "暂停行动预计完成时间无效"
		return ""

	if action.status == ActionInstanceData.STATUS_COMPLETED:
		if not is_equal_approx(action.accumulated_work, action.total_work):
			return "已完成行动工作量未完成"
		if action.completion_hour < action.start_hour or action.completion_hour > action.last_update_hour:
			return "已完成行动完成时间无效"
		if action.estimated_completion_hour != action.completion_hour:
			return "已完成行动预计完成时间不一致"
		if action.outcome_code not in VALID_ACTION_OUTCOMES or not action.result_applied:
			return "已完成行动结果状态无效"
		if action.result_description.is_empty() or action.applied_effects.is_empty():
			return "已完成行动缺少结算载荷"
		if not action.interruption_reason.is_empty():
			return "已完成行动不应包含中断原因"
		return ""

	if action.completion_hour != -1 or action.estimated_completion_hour != -1:
		return "取消或中断行动具有完成时间"
	if not action.outcome_code.is_empty() or action.result_applied or action.domain_effect_applied:
		return "取消或中断行动具有已结算结果"
	if not action.result_description.is_empty() or not action.applied_effects.is_empty():
		return "取消或中断行动包含结果载荷"
	if action.status == ActionInstanceData.STATUS_INTERRUPTED and action.interruption_reason.is_empty():
		return "中断行动缺少中断原因"
	if action.status == ActionInstanceData.STATUS_CANCELLED and not action.interruption_reason.is_empty():
		return "取消行动不应包含中断原因"
	return ""


func _validate_action_target(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	society: SocietySimulationService,
	map_service: MapControlService
) -> String:
	if definition.category in ["build_relationship", "investigate_character"]:
		if not society.roster.has_character(action.target_id) or action.target_id == action.actor_character_id:
			return "当前行动人物目标无效"
	elif definition.category in ["join_organization", "seek_position"]:
		if society.organizations.get_organization(action.target_id) == null:
			return "当前行动组织目标无效"
	elif definition.category in ["promote_policy", "support_control"]:
		if map_service.get_unit(action.target_id) == null:
			return "当前行动地图目标无效"
	elif not action.target_id.is_empty():
		return "无需目标的行动包含异常目标"
	return ""


func _validate_social_indexes(society: SocietySimulationService) -> String:
	var character_ids: Array[String] = _get_all_character_ids(society.roster)
	var expected_organizations: Dictionary = {}
	for organization_id: String in society.organizations.get_organization_ids():
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		for member_id: String in organization.member_ids:
			var memberships: Array[String] = DataRecordUtils.to_string_array(
				expected_organizations.get(member_id, [])
			)
			memberships.append(organization_id)
			expected_organizations[member_id] = memberships

	var expected_relationships: Dictionary = {}
	for raw_relationship: Variant in society.relationships.relationships.values():
		var relationship: RelationshipData = raw_relationship as RelationshipData
		for character_id: String in [relationship.character_a_id, relationship.character_b_id]:
			var ids: Array[String] = DataRecordUtils.to_string_array(
				expected_relationships.get(character_id, [])
			)
			ids.append(relationship.id)
			expected_relationships[character_id] = ids

	for character_id: String in character_ids:
		var character: Variant = society.roster.get_public_character(character_id)
		if character == null:
			return "人物公开记录不存在：%s" % character_id
		var actual_organizations: Array[String] = _get_character_organization_ids(character)
		var organization_error: String = _validate_exact_id_index(
			actual_organizations,
			DataRecordUtils.to_string_array(expected_organizations.get(character_id, [])),
			"人物 %s 的组织索引" % character_id
		)
		if not organization_error.is_empty():
			return organization_error
		var actual_relationships: Array[String] = _get_character_relationship_ids(character)
		var relationship_error: String = _validate_exact_id_index(
			actual_relationships,
			DataRecordUtils.to_string_array(expected_relationships.get(character_id, [])),
			"人物 %s 的关系索引" % character_id
		)
		if not relationship_error.is_empty():
			return relationship_error
		var public_position: String = _get_character_public_position(character)
		var position_names: Array[String] = []
		for organization_id: String in actual_organizations:
			var position_name: String = society.organizations.get_position_name(
				character_id, organization_id
			)
			if not position_name.is_empty():
				position_names.append(position_name)
		if public_position.is_empty() and not position_names.is_empty():
			return "人物 %s 缺少公开职位索引" % character_id
		if not public_position.is_empty() and not position_names.has(public_position):
			return "人物 %s 的公开职位与组织职位不一致" % character_id
	return ""


func _get_all_character_ids(roster: CharacterRosterService) -> Array[String]:
	var ids: Array[String] = []
	for source: Dictionary in [
		roster.background_characters,
		roster.active_characters,
		roster.exited_characters,
	]:
		for raw_id: Variant in source:
			ids.append(str(raw_id))
	ids.sort()
	return ids


func _get_character_organization_ids(character: Variant) -> Array[String]:
	if character is CharacterData:
		return DataRecordUtils.to_string_array((character as CharacterData).organization_ids)
	if character is BackgroundCharacterData:
		return DataRecordUtils.to_string_array((character as BackgroundCharacterData).organization_ids)
	return []


func _get_character_relationship_ids(character: Variant) -> Array[String]:
	if character is CharacterData:
		return DataRecordUtils.to_string_array((character as CharacterData).relationship_ids)
	if character is BackgroundCharacterData:
		return DataRecordUtils.to_string_array((character as BackgroundCharacterData).relationship_ids)
	return []


func _get_character_public_position(character: Variant) -> String:
	if character is CharacterData:
		return (character as CharacterData).public_position
	if character is BackgroundCharacterData:
		return (character as BackgroundCharacterData).public_position
	return ""


func _validate_exact_id_index(
	actual: Array[String],
	expected: Array[String],
	label: String
) -> String:
	var seen: Dictionary = {}
	for id: String in actual:
		if id.is_empty() or seen.has(id):
			return "%s 包含空值或重复值" % label
		seen[id] = true
	var actual_sorted: Array[String] = actual.duplicate()
	var expected_sorted: Array[String] = expected.duplicate()
	actual_sorted.sort()
	expected_sorted.sort()
	if actual_sorted != expected_sorted:
		return "%s 与权威服务不一致" % label
	return ""


func validate_snapshot(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(snapshot.get("save_version", -1)) != SAVE_VERSION:
		errors.append("不支持的存档版本")
	for field: String in [
		"config_versions", "game_time", "world", "characters", "relationships", "random_state",
	]:
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
	if not snapshot.has("current_action") or (
		snapshot["current_action"] != null and not snapshot["current_action"] is Dictionary
	):
		errors.append("当前行动字段无效")
	if errors.is_empty():
		var config_versions: Dictionary = snapshot["config_versions"] as Dictionary
		for config_id: String in CONFIG_VERSIONS:
			if int(config_versions.get(config_id, -1)) != int(CONFIG_VERSIONS[config_id]):
				errors.append("配置版本不兼容：%s" % config_id)
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
		var settlement_state: Variant = snapshot.get("settlement_state", {})
		if settlement_state is Dictionary and not (
			settlement_state as Dictionary
		).get("paused_categories", {}) is Dictionary:
			errors.append("暂停结算类别必须是对象")
	return errors
