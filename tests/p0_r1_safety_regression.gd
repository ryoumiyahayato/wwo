extends SceneTree
## Safety regression for transactional restore, validation, backup recovery and one-shot effects.

var _checks: int = 0
var _failures: int = 0
const PROBE_PATH: String = "user://saves/p0_r1_safety_probe.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_path(PROBE_PATH)
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可创建安全回归测试人物")
	if player == null:
		_finish()
		return
	GameSessionService.set_player(player)

	var scene_resource: Resource = load("res://scenes/map/strategic_map_view.tscn")
	var view: Control = null
	if scene_resource is PackedScene:
		view = (scene_resource as PackedScene).instantiate() as Control
	_expect(view != null, "战略地图场景可实例化")
	if view == null:
		_finish()
		return
	get_root().add_child(view)
	current_scene = view
	await process_frame

	var clock: SimulationClock = GameSessionService.world_clock
	var map_service: MapControlService = GameSessionService.world_map_service
	var society: SocietySimulationService = GameSessionService.society_service
	var save_service := GameSaveService.new()
	_expect(clock != null and map_service != null and society != null, "安全回归建立完整权威会话")
	if clock == null or map_service == null or society == null:
		_finish()
		return

	clock.advance_hours(48)
	var snapshot: Dictionary = save_service.build_snapshot(clock, map_service)
	_expect(not snapshot.is_empty(), "可构建完整存档快照")

	_test_transactional_restore(save_service, snapshot, clock, map_service)
	_test_incompatible_config_rejected(save_service, snapshot)
	_test_invalid_action_rejected(save_service, clock, map_service, society)
	_test_social_index_mismatches(save_service, snapshot, clock, map_service)
	_test_domain_hook_consumed_once(society, map_service, clock)
	_test_backup_recovery(save_service, snapshot)

	_cleanup_path(PROBE_PATH)
	GameSessionService.clear()
	_finish()


func _test_transactional_restore(
	save_service: GameSaveService,
	snapshot: Dictionary,
	clock: SimulationClock,
	map_service: MapControlService
) -> void:
	var before_clock: Dictionary = clock.get_persistent_state()
	var before_world: Dictionary = map_service.get_persistent_state()
	var before_player_id: String = GameSessionService.player_character.id
	var broken: Dictionary = snapshot.duplicate(true)
	var broken_world: Dictionary = broken["world"] as Dictionary
	var broken_units: Dictionary = broken_world["control_units"] as Dictionary
	var unit_id: String = "control:r3_c4"
	var unit_state: Dictionary = broken_units[unit_id] as Dictionary
	unit_state["controller_country_id"] = map_service.get_other_country_id(
		str(unit_state["controller_country_id"])
	)
	var broken_time: Dictionary = broken["game_time"] as Dictionary
	broken_time["speed_multiplier"] = 3

	var result: SaveOperationResult = save_service.restore_snapshot(broken, clock, map_service)
	_expect(not result.success, "非法时钟状态导致恢复失败")
	_expect(clock.get_persistent_state() == before_clock, "恢复失败后权威时钟完全回滚")
	_expect(map_service.get_persistent_state() == before_world, "恢复失败后权威地图完全回滚")
	_expect(GameSessionService.player_character.id == before_player_id, "恢复失败后玩家会话未被替换")


func _test_incompatible_config_rejected(
	save_service: GameSaveService,
	snapshot: Dictionary
) -> void:
	var incompatible: Dictionary = snapshot.duplicate(true)
	var versions: Dictionary = incompatible["config_versions"] as Dictionary
	versions["action"] = 999
	var errors: Array[String] = save_service.validate_snapshot(incompatible)
	_expect(not errors.is_empty(), "不兼容配置版本被拒绝")
	_expect("; ".join(errors).contains("配置版本不兼容"), "配置版本错误具有明确说明")


func _test_invalid_action_rejected(
	save_service: GameSaveService,
	clock: SimulationClock,
	map_service: MapControlService,
	society: SocietySimulationService
) -> void:
	var rules := ActionRulesConfig.new()
	_expect(rules.load_from_file() == OK, "行动规则可供存档安全测试加载")
	if rules.error_message != "":
		return
	var definition: ActionDefinitionData = map_service.data_set.actions[
		"action:study_skill"
	] as ActionDefinitionData
	var context_service := PlayerActionContextService.new(rules, society, map_service)
	var action_service := ActionService.new(rules, GameSessionService.action_id_service)
	var started: ActionStartResult = action_service.start_action(
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		context_service.build_context(definition, GameSessionService.player_character, "")
	)
	_expect(started.is_success(), "可建立合法进行中行动快照")
	if not started.is_success():
		return
	GameSessionService.current_action = started.action
	var action_snapshot: Dictionary = save_service.build_snapshot(clock, map_service)
	GameSessionService.current_action = null

	var invalid_efficiency: Dictionary = action_snapshot.duplicate(true)
	var invalid_action: Dictionary = invalid_efficiency["current_action"] as Dictionary
	invalid_action["current_efficiency"] = 0.0
	var before_clock: Dictionary = clock.get_persistent_state()
	var before_world: Dictionary = map_service.get_persistent_state()
	var result: SaveOperationResult = save_service.restore_snapshot(
		invalid_efficiency, clock, map_service
	)
	_expect(not result.success, "零效率行动存档被拒绝")
	_expect(clock.get_persistent_state() == before_clock, "非法行动不会修改时钟")
	_expect(map_service.get_persistent_state() == before_world, "非法行动不会修改地图")

	var invalid_context: Dictionary = action_snapshot.duplicate(true)
	var context_action: Dictionary = invalid_context["current_action"] as Dictionary
	var context: Dictionary = context_action["context"] as Dictionary
	context["funding"] = 101.0
	result = save_service.restore_snapshot(invalid_context, clock, map_service)
	_expect(not result.success, "超范围行动上下文被拒绝")

	var inconsistent_state: Dictionary = action_snapshot.duplicate(true)
	var state_action: Dictionary = inconsistent_state["current_action"] as Dictionary
	state_action["status"] = ActionInstanceData.STATUS_COMPLETED
	state_action["completion_hour"] = clock.total_hours
	state_action["estimated_completion_hour"] = clock.total_hours
	state_action["outcome_code"] = "success"
	state_action["result_applied"] = false
	result = save_service.restore_snapshot(inconsistent_state, clock, map_service)
	_expect(not result.success, "完成状态与未应用结果不一致的行动被拒绝")


func _test_social_index_mismatches(
	save_service: GameSaveService,
	snapshot: Dictionary,
	clock: SimulationClock,
	map_service: MapControlService
) -> void:
	var player_id: String = str(snapshot["player_character_id"])
	var organization_mismatch: Dictionary = snapshot.duplicate(true)
	var org_player: Dictionary = _find_active_record(
		organization_mismatch["characters"] as Dictionary, player_id
	)
	var organization_ids: Array = org_player["organization_ids"] as Array
	organization_ids.append("organization:loran_government")
	var result: SaveOperationResult = save_service.restore_snapshot(
		organization_mismatch, clock, map_service
	)
	_expect(not result.success, "人物与组织成员双向索引不一致时拒绝恢复")

	var relationship_mismatch: Dictionary = snapshot.duplicate(true)
	var relationship_player: Dictionary = _find_active_record(
		relationship_mismatch["characters"] as Dictionary, player_id
	)
	var relationship_ids: Array = relationship_player["relationship_ids"] as Array
	relationship_ids.append("relationship:99999999")
	result = save_service.restore_snapshot(relationship_mismatch, clock, map_service)
	_expect(not result.success, "人物与关系记录双向索引不一致时拒绝恢复")


func _test_domain_hook_consumed_once(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var definition: ActionDefinitionData = map_service.data_set.actions[
		"action:seek_position"
	] as ActionDefinitionData
	var action := ActionInstanceData.new()
	action.id = "action_instance:99999999"
	action.definition_id = definition.id
	action.actor_character_id = GameSessionService.player_character.id
	action.target_id = "organization:loran_government"
	action.status = ActionInstanceData.STATUS_COMPLETED
	action.completion_hour = clock.total_hours
	action.outcome_code = "success"
	var first_applied: bool = society.apply_action_domain_effect(
		action, definition, map_service
	)
	_expect(not first_applied, "无组织成员资格时职位领域结果不产生变化")
	_expect(action.domain_effect_applied, "无变化的领域结果仍被标记为已消费")
	var second_applied: bool = society.apply_action_domain_effect(
		action, definition, map_service
	)
	_expect(not second_applied, "已消费的领域结果不会再次执行")


func _test_backup_recovery(
	save_service: GameSaveService,
	snapshot: Dictionary
) -> void:
	var saved: SaveOperationResult = save_service.save_to_path(PROBE_PATH, snapshot)
	_expect(saved.success, "安全回归可写入隔离探针存档")
	if not saved.success:
		return
	var absolute: String = ProjectSettings.globalize_path(PROBE_PATH)
	var backup: String = absolute + ".bak"
	var source := FileAccess.open(absolute, FileAccess.READ)
	var original_text: String = "" if source == null else source.get_as_text()
	if source != null:
		source.close()
	var backup_file := FileAccess.open(backup, FileAccess.WRITE)
	if backup_file != null:
		backup_file.store_string(original_text)
		backup_file.close()
	var corrupt_primary := FileAccess.open(absolute, FileAccess.WRITE)
	if corrupt_primary != null:
		corrupt_primary.store_string("{ invalid json")
		corrupt_primary.close()

	var loaded: SaveOperationResult = save_service.load_from_path(PROBE_PATH)
	_expect(loaded.success, "主存档损坏时可读取安全备份")
	_expect(loaded.message.contains("安全备份"), "备份恢复结果明确标记来源")
	_expect(loaded.snapshot == snapshot, "安全备份恢复完整原始快照")


func _find_active_record(state: Dictionary, character_id: String) -> Dictionary:
	for raw_record: Variant in state["active"] as Array:
		if raw_record is Dictionary and str((raw_record as Dictionary).get("id", "")) == character_id:
			return raw_record as Dictionary
	return {}


func _make_test_player() -> CharacterData:
	var world: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	if not world.is_success() or not config.is_valid():
		return null
	var generator := CharacterGenerator.new(
		world.data_set,
		config,
		DeterministicRandomService.new(19000101),
		StableIdService.new()
	)
	var result: CharacterGenerationResult = generator.generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	return null if not result.is_success() else result.character


func _cleanup_path(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	for candidate: String in [absolute, absolute + ".tmp", absolute + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
		return
	_failures += 1
	printerr("[FAIL] %s" % description)


func _finish() -> void:
	_cleanup_path(PROBE_PATH)
	if _failures > 0:
		printerr("P0-R1 SAFETY REGRESSION FAILED: %d/%d checks failed" % [_failures, _checks])
		quit(1)
		return
	print("P0-R1 SAFETY REGRESSION PASSED: %d checks" % _checks)
	quit(0)
