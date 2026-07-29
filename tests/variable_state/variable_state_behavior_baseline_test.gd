extends SceneTree
## Behavioral baseline for the first variable-state refactor. The duplicated
## GameSessionService.selected_country_id member intentionally remains present.

const FIXTURE_RESOURCE_PATH: String = "res://tests/fixtures/save/current_save_v1.json"
const FIXTURE_USER_PATH: String = "user://tests/variable_state/committed_current_save_v1.json"
const WORLD_PATH: String = "res://data/world/demo_world.json"
const HEMISPHERE_RUNTIME_PATH: String = "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"
const PLAYER_SEED: int = 190001

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_current_fixture_loads()
	_test_save_key_matches_player_country()
	_test_mismatch_rejected_without_partial_commit()
	_test_transfer_player()
	_test_succession_success()
	_test_succession_rollback()
	_test_map_selection_isolated_from_player_country()
	_test_clear_empties_player_and_derived_country()
	_cleanup_user_fixture()
	GameSessionService.clear()
	test.finish(self, "Variable-state behavior baseline")


func _test_current_fixture_loads() -> void:
	var fixture: Dictionary = _read_fixture()
	test.expect(not fixture.is_empty(), "提交的SAVE_VERSION=1真实fixture可读取")
	if fixture.is_empty():
		return
	test.equal(
		int(fixture.get("save_version", -1)),
		GameSaveService.SAVE_VERSION,
		"fixture使用当前SAVE_VERSION"
	)
	test.expect(_copy_fixture_to_user(), "fixture复制到生产加载允许的user://路径")
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	var service := GameSaveService.new()
	var loaded: SaveOperationResult = service.load_from_path(FIXTURE_USER_PATH)
	test.expect(loaded.success, "现有未重构代码可解析并校验fixture")
	if not loaded.success:
		return
	var restored: SaveOperationResult = service.restore_snapshot(
		loaded.snapshot,
		runtime["clock"] as SimulationClock,
		runtime["map"] as MapControlService
	)
	test.expect(restored.success, "现有未重构代码可完整恢复fixture")
	if not restored.success:
		return
	test.equal(
		GameSessionService.player_character.id,
		str(fixture["player_character_id"]),
		"fixture恢复当前玩家人物"
	)
	test.equal(
		GameSessionService.selected_country_id,
		GameSessionService.player_character.country_id,
		"fixture恢复后玩家国家双写仍一致"
	)


func _test_save_key_matches_player_country() -> void:
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	var snapshot: Dictionary = GameSaveService.new().build_snapshot(
		runtime["clock"] as SimulationClock,
		runtime["map"] as MapControlService
	)
	test.expect(not snapshot.is_empty(), "当前生产保存逻辑生成完整快照")
	test.equal(
		str(snapshot.get("selected_country_id", "")),
		GameSessionService.player_character.country_id,
		"保存键selected_country_id等于player_character.country_id"
	)


func _test_mismatch_rejected_without_partial_commit() -> void:
	var fixture: Dictionary = _read_fixture()
	var runtime := _create_runtime()
	if fixture.is_empty() or runtime.is_empty():
		return
	var clock: SimulationClock = runtime["clock"] as SimulationClock
	var map_service: MapControlService = runtime["map"] as MapControlService
	clock.advance_hours(7)
	var unit_ids: Array[String] = map_service.get_sorted_unit_ids()
	if not unit_ids.is_empty():
		var unit: ControlUnitData = map_service.get_unit(unit_ids[0])
		map_service.set_control_state(
			unit.id, unit.controller_country_id, 0.61, 0.22
		)
	GameSessionService.pending_load_path = "user://tests/sentinel-before-failure.json"
	GameSessionService.pending_menu_message = "sentinel-before-failure"
	var tampered: Dictionary = fixture.duplicate(true)
	var player_country: String = _fixture_player_country(tampered)
	var other_country: String = _other_country_id(
		map_service.data_set, player_country
	)
	test.expect(not other_country.is_empty(), "fixture世界提供另一个有效国家")
	if other_country.is_empty():
		return
	tampered["selected_country_id"] = other_country
	var before: Dictionary = _capture_runtime(clock, map_service)
	var result: SaveOperationResult = GameSaveService.new().restore_snapshot(
		tampered, clock, map_service
	)
	test.expect(not result.success, "旧键与玩家国家不一致时加载失败")
	test.equal(result.error_code, "broken_reference", "国家不一致返回引用错误")
	test.equal(
		_capture_runtime(clock, map_service),
		before,
		"国家不一致失败前后完整运行状态一致"
	)


func _test_transfer_player() -> void:
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	var society: SocietySimulationService = runtime["society"] as SocietySimulationService
	var target: CharacterData
	for character_id: String in society.roster.get_active_ids(false):
		target = society.roster.get_active(character_id)
		if target != null:
			break
	if target == null:
		var background_ids: Array[String] = society.roster.get_background_ids()
		if not background_ids.is_empty():
			target = society.promote_background(background_ids[0])
	test.expect(target != null, "transfer_player测试拥有真实目标人物")
	if target == null:
		return
	GameSessionService.transfer_player(target)
	test.expect(
		GameSessionService.player_character == target,
		"transfer_player切换当前玩家对象"
	)
	test.equal(
		GameSessionService.selected_country_id,
		target.country_id,
		"transfer_player同步现有玩家国家副本"
	)
	test.expect(
		GameSessionService.current_action == null,
		"transfer_player清除当前行动"
	)


func _test_succession_success() -> void:
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	var society: SocietySimulationService = runtime["society"] as SocietySimulationService
	var candidate_id: String = _prepare_background_succession_candidate(society)
	test.expect(not candidate_id.is_empty(), "继承成功测试建立真实背景候选")
	if candidate_id.is_empty():
		return
	var old_player_id: String = society.roster.player_character_id
	var result: SuccessionResult = society.execute_player_succession(
		candidate_id, "voluntary", 24
	)
	test.expect(result.successor != null, "人物继承事务成功")
	if result.successor == null:
		return
	test.equal(
		society.roster.player_character_id,
		candidate_id,
		"继承成功后名册玩家切换"
	)
	test.equal(
		GameSessionService.player_character.id,
		candidate_id,
		"继承成功后会话玩家切换"
	)
	test.equal(
		GameSessionService.selected_country_id,
		GameSessionService.player_character.country_id,
		"继承成功后现有玩家国家副本保持一致"
	)
	test.expect(
		society.roster.get_exited(old_player_id) != null,
		"继承成功记录原玩家退出"
	)


func _test_succession_rollback() -> void:
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	var society: SocietySimulationService = runtime["society"] as SocietySimulationService
	var candidate_id: String = _prepare_background_succession_candidate(society)
	test.expect(not candidate_id.is_empty(), "继承回滚测试建立真实背景候选")
	if candidate_id.is_empty():
		return
	society.roster.rules.active_character_limit = 0
	var clock: SimulationClock = runtime["clock"] as SimulationClock
	var map_service: MapControlService = runtime["map"] as MapControlService
	var before: Dictionary = _capture_runtime(clock, map_service)
	var result: SuccessionResult = society.execute_player_succession(
		candidate_id, "voluntary", 48
	)
	test.expect(result.successor == null, "候选升级失败触发继承事务回滚")
	test.expect(not result.errors.is_empty(), "继承回滚返回明确错误")
	test.equal(
		_capture_runtime(clock, map_service),
		before,
		"继承事务失败前后完整运行状态一致"
	)


func _test_map_selection_isolated_from_player_country() -> void:
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	var data_set: CoreDataSet = runtime["data_set"] as CoreDataSet
	var session_country_before: String = GameSessionService.selected_country_id
	var map_country: String = _other_country_id(data_set, session_country_before)
	test.expect(not map_country.is_empty(), "地图选择隔离测试拥有另一国家")
	if map_country.is_empty():
		return
	var runtime_script: Script = load(HEMISPHERE_RUNTIME_PATH) as Script
	var hemisphere: Control = runtime_script.new() as Control
	hemisphere.set("selected_country_id", map_country)
	test.equal(
		GameSessionService.selected_country_id,
		session_country_before,
		"修改半球地图selected_country_id不改变玩家国家"
	)
	var society: SocietySimulationService = runtime["society"] as SocietySimulationService
	var transfer_target: CharacterData
	for character_id: String in society.roster.get_active_ids(false):
		var active: CharacterData = society.roster.get_active(character_id)
		if active != null:
			transfer_target = active
			break
	if transfer_target == null:
		var background_ids: Array[String] = society.roster.get_background_ids()
		if not background_ids.is_empty():
			transfer_target = society.promote_background(background_ids[0])
	test.expect(transfer_target != null, "地图隔离测试拥有可转移玩家人物")
	if transfer_target != null:
		GameSessionService.transfer_player(transfer_target)
		test.equal(
			str(hemisphere.get("selected_country_id")),
			map_country,
			"修改玩家国家不改变半球地图选择"
		)
	hemisphere.free()


func _test_clear_empties_player_and_derived_country() -> void:
	var runtime := _create_runtime()
	if runtime.is_empty():
		return
	GameSessionService.clear()
	test.expect(GameSessionService.player_character == null, "clear后玩家为空")
	test.equal(GameSessionService.selected_country_id, "", "clear后现有国家副本为空")
	test.equal(_derived_player_country_id(), "", "clear后由玩家派生的国家为空")


func _create_runtime() -> Dictionary:
	GameSessionService.clear()
	var load_result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		WORLD_PATH
	)
	test.expect(load_result.is_success(), "行为测试世界数据可加载")
	if not load_result.is_success():
		return {}
	var data_set: CoreDataSet = load_result.data_set
	var country_ids: Array[String] = []
	for raw_id: Variant in data_set.countries:
		country_ids.append(str(raw_id))
	country_ids.sort()
	test.expect(not country_ids.is_empty(), "行为测试世界包含可生成人物的国家")
	if country_ids.is_empty():
		return {}
	var character_config: CharacterGenerationConfig = (
		CharacterGenerationConfig.load_from_file()
	)
	test.expect(character_config.is_valid(), "正式人物生成配置可加载")
	if not character_config.is_valid():
		return {}
	var generator := CharacterGenerator.new(
		data_set,
		character_config,
		DeterministicRandomService.new(PLAYER_SEED),
		StableIdService.new()
	)
	var generated: CharacterGenerationResult = generator.generate_character(
		country_ids[0], CharacterGenerator.MODE_STANDARD
	)
	test.expect(generated.is_success(), "行为测试玩家由当前生产逻辑生成")
	if not generated.is_success():
		return {}
	var player: CharacterData = generated.character
	GameSessionService.set_player(player)
	var map_rules := MapRulesConfig.new()
	test.expect(map_rules.load_from_file() == OK, "地图规则可加载")
	if not map_rules.error_message.is_empty():
		return {}
	var clock_config := SimulationClockConfig.new()
	test.expect(clock_config.load_from_file() == OK, "时钟规则可加载")
	if not clock_config.error_message.is_empty():
		return {}
	var map_service := MapControlService.new(data_set, map_rules)
	var clock := SimulationClock.new(clock_config)
	var society := SocietySimulationService.new()
	test.expect(
		society.initialize(player, data_set),
		"当前社会服务可初始化：%s" % society.initialization_error
	)
	if not society.initialization_error.is_empty():
		return {}
	GameSessionService.society_service = society
	GameSessionService.set_world_services(clock, map_service)
	return {
		"data_set": data_set,
		"player": player,
		"society": society,
		"clock": clock,
		"map": map_service,
	}


func _prepare_background_succession_candidate(
	society: SocietySimulationService
) -> String:
	var old_player: CharacterData = GameSessionService.player_character
	for candidate_id: String in society.roster.get_background_ids(
		old_player.country_id
	):
		var relationship: RelationshipData = society.relationships.create_or_update(
			old_player.id,
			candidate_id,
			0,
			{
				"familiarity": 0.9,
				"trust": 0.8,
				"affinity": 0.7,
				"is_public": true,
			},
			"succession_baseline"
		)
		if relationship == null:
			continue
		for candidate: SuccessionCandidateData in society.succession.get_candidates(
			old_player.id
		):
			if candidate.character_id == candidate_id:
				return candidate_id
	return ""


func _capture_runtime(
	clock: SimulationClock, map_service: MapControlService
) -> Dictionary:
	var society: SocietySimulationService = GameSessionService.society_service
	var action_state: Variant = null
	if GameSessionService.current_action != null:
		action_state = GameSessionService.current_action.to_dict()
	var society_state: Dictionary = {}
	if society != null:
		society_state = {
			"roster": society.roster.get_persistent_state(),
			"organizations": society.organizations.get_persistent_state(),
			"relationships": society.relationships.get_persistent_state(),
			"ai": society.ai.get_persistent_state(),
			"world_activity": society.world_activity.get_persistent_state(),
			"paused_settlement_categories": (
				society.paused_settlement_categories.duplicate(true)
			),
			"active_character_limit": society.roster.rules.active_character_limit,
		}
	return {
		"clock": clock.get_persistent_state(),
		"map": map_service.get_persistent_state(),
		"player": (
			null
			if GameSessionService.player_character == null
			else GameSessionService.player_character.to_dict()
		),
		"selected_country_id": GameSessionService.selected_country_id,
		"current_action": action_state,
		"recent_action_result": (
			GameSessionService.recent_action_result.duplicate(true)
		),
		"action_history": GameSessionService.action_history.duplicate(true),
		"action_id_state": GameSessionService.action_id_service.get_state(),
		"society": society_state,
		"developer_mode": GameSessionService.developer_mode,
		"settlement_log": GameSessionService.settlement_log.get_state(),
		"performance_metrics": GameSessionService.performance_stats.get_snapshot(),
		"pending_load_path": GameSessionService.pending_load_path,
		"pending_menu_message": GameSessionService.pending_menu_message,
		"world_clock_identity": (
			0
			if GameSessionService.world_clock == null
			else GameSessionService.world_clock.get_instance_id()
		),
		"world_map_identity": (
			0
			if GameSessionService.world_map_service == null
			else GameSessionService.world_map_service.get_instance_id()
		),
		"society_identity": (
			0
			if society == null
			else society.get_instance_id()
		),
	}


func _read_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_RESOURCE_PATH, FileAccess.READ)
	if file == null:
		test.expect(false, "可读取提交的fixture文件")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	test.expect(parsed is Dictionary, "fixture根节点是JSON对象")
	return (parsed as Dictionary) if parsed is Dictionary else {}


func _copy_fixture_to_user() -> bool:
	_cleanup_user_fixture()
	var source := FileAccess.open(FIXTURE_RESOURCE_PATH, FileAccess.READ)
	if source == null:
		return false
	var target_absolute: String = ProjectSettings.globalize_path(FIXTURE_USER_PATH)
	if DirAccess.make_dir_recursive_absolute(target_absolute.get_base_dir()) != OK:
		return false
	var target := FileAccess.open(FIXTURE_USER_PATH, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string(source.get_as_text())
	target.flush()
	target.close()
	return true


func _cleanup_user_fixture() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = FIXTURE_USER_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fixture_player_country(snapshot: Dictionary) -> String:
	var player_id: String = str(snapshot.get("player_character_id", ""))
	var characters: Dictionary = snapshot.get("characters", {}) as Dictionary
	for raw_record: Variant in characters.get("active", []) as Array:
		if (
			raw_record is Dictionary
			and str((raw_record as Dictionary).get("id", "")) == player_id
		):
			return str((raw_record as Dictionary).get("country_id", ""))
	return ""


func _other_country_id(data_set: CoreDataSet, country_id: String) -> String:
	var ids: Array[String] = []
	for raw_id: Variant in data_set.countries:
		ids.append(str(raw_id))
	ids.sort()
	for candidate: String in ids:
		if candidate != country_id:
			return candidate
	return ""


func _derived_player_country_id() -> String:
	return (
		""
		if GameSessionService.player_character == null
		else GameSessionService.player_character.country_id
	)
