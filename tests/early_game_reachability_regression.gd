extends SceneTree
## Realistic-budget, cross-seed early-game reachability regression.

const SEED_COUNT: int = 1000
const DAY_30: int = 30 * 24
const DAY_60: int = 60 * 24
const DAY_90: int = 90 * 24
const DAY_180: int = 180 * 24

var _failures: int = 0
var _world: CoreDataSet
var _map: MapControlService
var _rules: ActionRulesConfig
var _generation_config: CharacterGenerationConfig
var _stage_counts: Dictionary = {
	"work_30": 0,
	"relationship_60": 0,
	"organization_90": 0,
	"position_path_180": 0,
	"position_success_line_180": 0,
}
var _failure_reasons: Dictionary = {}
var _total_spent: int = 0
var _total_income: int = 0
var _total_relationship_hour: int = 0
var _total_organization_hour: int = 0
var _total_position_hour: int = 0
var _total_studies: int = 0
var _position_effective_total: float = 0.0
var _position_effective_minimum: float = INF
var _position_effective_maximum: float = -INF
var _worst_seed: int = -1
var _worst_stage: int = 99
var _worst_hour: int = -1
var _lowest_position_seed: int = -1
var _lowest_position_effective: float = INF
var _lowest_position_hour: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LogService.set_minimum_level(LogService.Level.ERROR)
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	_rules = ActionRulesConfig.new()
	_generation_config = CharacterGenerationConfig.load_from_file()
	var map_rules := MapRulesConfig.new()
	if (
		not loaded.is_success()
		or _rules.load_from_file() != OK
		or not _generation_config.is_valid()
		or map_rules.load_from_file() != OK
	):
		print("[FAIL] 无法加载 1000 种子可达性测试依赖")
		quit(1)
		return
	_world = loaded.data_set
	_map = MapControlService.new(_world, map_rules)

	for seed_value: int in range(1, SEED_COUNT + 1):
		_run_seed(seed_value)
		if seed_value % 100 == 0:
			print("[PROGRESS] 已验证 %d/%d 个标准种子" % [seed_value, SEED_COUNT])

	_print_report()
	_expect(int(_stage_counts["work_30"]) == SEED_COUNT, "30 日内完成一次成功本职工作")
	_expect(int(_stage_counts["relationship_60"]) == SEED_COUNT, "60 日内通过行动建立或加深第一条关系")
	_expect(int(_stage_counts["organization_90"]) == SEED_COUNT, "90 日内通过行动加入第一个组织")
	_expect(int(_stage_counts["position_path_180"]) == SEED_COUNT, "180 日内实际创建合法争取职位行动")
	_expect(int(_stage_counts["position_success_line_180"]) == SEED_COUNT, "180 日内争取职位条件达到确定成功线")
	_expect(_total_studies <= SEED_COUNT * 2, "每个种子最多学习两次")
	_expect(_deadlock_count() == 0, "不存在确定性早期死局")
	GameSessionService.clear()
	if _failures == 0:
		print("EARLY-GAME REACHABILITY PASSED: %d seeds" % SEED_COUNT)
		quit(0)
	else:
		print("EARLY-GAME REACHABILITY FAILED: %d checks" % _failures)
		quit(1)


func _run_seed(seed_value: int) -> void:
	var generator := CharacterGenerator.new(
		_world,
		_generation_config,
		DeterministicRandomService.new(seed_value),
		StableIdService.new()
	)
	var countries: Array[String] = [
		"country:loran_federation", "country:vesta_union",
	]
	var generated: CharacterGenerationResult = generator.generate_character(
		countries[(seed_value - 1) % countries.size()],
		CharacterGenerator.MODE_STANDARD
	)
	if not generated.is_success():
		_fail_seed(seed_value, 0, 0, "generation_failed")
		return
	var character: CharacterData = generated.character
	GameSessionService.set_player(character)
	var society := SocietySimulationService.new()
	if not society.initialize(character, _world):
		_fail_seed(seed_value, 0, 0, "society_initialization_failed")
		return
	var context_service := PlayerActionContextService.new(_rules, society, _map)
	var action_service := ActionService.new(
		_rules, GameSessionService.action_id_service
	)
	var current_hour: int = 0
	var spent: int = 0
	var income: int = 0
	var studies: int = 0
	var initial_wealth: int = int(character.current_status.get("wealth", 0))

	var work: ActionDefinitionData = _world.actions.get(
		"action:perform_work"
	) as ActionDefinitionData
	var work_extra: int = mini(
		context_service.get_max_extra_funding(),
		int(character.current_status.get("wealth", 0))
		- context_service.get_base_funding_cost(work)
	)
	var work_result: Dictionary = _execute_action(
		society,
		context_service,
		action_service,
		character,
		work,
		current_hour,
		"",
		maxi(work_extra, 0)
	)
	if not bool(work_result.get("started", false)):
		_fail_seed(seed_value, 0, current_hour, "work_start_failed")
		return
	current_hour = int(work_result["hour"])
	spent += int(work_result["cost"])
	income += int(work_result["wealth_after"]) - int(work_result["wealth_after_funding"])
	if (
		str(work_result.get("outcome", "")) == "failure"
		or current_hour > DAY_30
	):
		_fail_seed(
			seed_value,
			0,
			current_hour,
			"work_failure" if str(work_result.get("outcome", "")) == "failure" else "work_after_30_days"
		)
		return
	_stage_counts["work_30"] = int(_stage_counts["work_30"]) + 1

	var relationship: ActionDefinitionData = _world.actions.get(
		"action:build_relationship"
	) as ActionDefinitionData
	var relationship_extra: int = _maximum_affordable_extra(
		context_service, relationship, character
	)
	var relationship_target: String = _best_target(
		context_service,
		action_service,
		relationship,
		character,
		relationship_extra,
		society
	)
	if relationship_target.is_empty():
		_fail_seed(seed_value, 1, current_hour, "relationship_target_missing")
		return
	var relationship_result: Dictionary = _execute_action(
		society,
		context_service,
		action_service,
		character,
		relationship,
		current_hour,
		relationship_target,
		relationship_extra
	)
	if not bool(relationship_result.get("started", false)):
		_fail_seed(seed_value, 1, current_hour, "relationship_start_failed")
		return
	current_hour = int(relationship_result["hour"])
	spent += int(relationship_result["cost"])
	if (
		str(relationship_result.get("outcome", "")) == "failure"
		or not bool(relationship_result.get("domain_applied", false))
		or current_hour > DAY_60
	):
		var reason: String = "relationship_failure"
		if not bool(relationship_result.get("domain_applied", false)):
			reason = "relationship_domain_failed"
		elif current_hour > DAY_60:
			reason = "relationship_after_60_days"
		_fail_seed(seed_value, 1, current_hour, reason)
		return
	_stage_counts["relationship_60"] = int(_stage_counts["relationship_60"]) + 1
	_total_relationship_hour += current_hour

	var join: ActionDefinitionData = _world.actions.get(
		"action:join_organization"
	) as ActionDefinitionData
	while (
		int(character.current_status.get("wealth", 0))
		< context_service.get_base_funding_cost(join)
		and current_hour <= DAY_90
	):
		var earning: Dictionary = _execute_action(
			society,
			context_service,
			action_service,
			character,
			work,
			current_hour,
			"",
			0
		)
		if not bool(earning.get("started", false)):
			break
		current_hour = int(earning["hour"])
		spent += int(earning["cost"])
		income += int(earning["wealth_after"]) - int(earning["wealth_after_funding"])
	var join_extra: int = _maximum_affordable_extra(
		context_service, join, character
	)
	var organization_target: String = _best_target(
		context_service,
		action_service,
		join,
		character,
		join_extra,
		society
	)
	if organization_target.is_empty():
		_fail_seed(seed_value, 2, current_hour, "organization_target_missing")
		return
	var join_result: Dictionary = _execute_action(
		society,
		context_service,
		action_service,
		character,
		join,
		current_hour,
		organization_target,
		join_extra
	)
	if not bool(join_result.get("started", false)):
		_fail_seed(seed_value, 2, current_hour, "organization_start_failed")
		return
	current_hour = int(join_result["hour"])
	spent += int(join_result["cost"])
	if (
		str(join_result.get("outcome", "")) == "failure"
		or not bool(join_result.get("domain_applied", false))
		or current_hour > DAY_90
	):
		var reason: String = "organization_failure"
		if not bool(join_result.get("domain_applied", false)):
			reason = "organization_domain_failed"
		elif current_hour > DAY_90:
			reason = "organization_after_90_days"
		_fail_seed(seed_value, 2, current_hour, reason)
		return
	_stage_counts["organization_90"] = int(_stage_counts["organization_90"]) + 1
	_total_organization_hour += current_hour

	var position: ActionDefinitionData = _world.actions.get(
		"action:seek_position"
	) as ActionDefinitionData
	for skill_id: String in ["political_activity", "public_speaking"]:
		var position_context: Dictionary = context_service.build_context(
			position,
			character,
			organization_target,
			_maximum_affordable_extra(context_service, position, character)
		)
		if action_service.calculate_effective_value(
			position, character, position_context
		) >= position.success_threshold:
			break
		var study: ActionDefinitionData = _world.actions.get(
			"action:study_skill"
		) as ActionDefinitionData
		while (
			int(character.current_status.get("wealth", 0))
			< context_service.get_base_funding_cost(study)
			and current_hour <= DAY_180
		):
			var earning: Dictionary = _execute_action(
				society, context_service, action_service, character,
				work, current_hour, "", 0
			)
			if not bool(earning.get("started", false)):
				break
			current_hour = int(earning["hour"])
			income += int(earning["wealth_after"]) - int(earning["wealth_after_funding"])
		var study_extra: int = _minimum_success_extra(
			context_service, action_service, study, character, "", skill_id
		)
		var study_result: Dictionary = _execute_action(
			society,
			context_service,
			action_service,
			character,
			study,
			current_hour,
			"",
			study_extra,
			skill_id
		)
		if not bool(study_result.get("started", false)):
			break
		current_hour = int(study_result["hour"])
		spent += int(study_result["cost"])
		studies += 1

	while (
		int(character.current_status.get("wealth", 0))
		< context_service.get_base_funding_cost(position)
		and current_hour <= DAY_180
	):
		var earning: Dictionary = _execute_action(
			society, context_service, action_service, character,
			work, current_hour, "", 0
		)
		if not bool(earning.get("started", false)):
			break
		current_hour = int(earning["hour"])
		income += int(earning["wealth_after"]) - int(earning["wealth_after_funding"])
	var position_extra: int = _maximum_affordable_extra(
		context_service, position, character
	)
	var position_context: Dictionary = context_service.build_context(
		position, character, organization_target, position_extra
	)
	var position_effective: float = action_service.calculate_effective_value(
		position, character, position_context
	)
	_position_effective_total += position_effective
	_position_effective_minimum = minf(_position_effective_minimum, position_effective)
	_position_effective_maximum = maxf(_position_effective_maximum, position_effective)
	if position_effective < _lowest_position_effective:
		_lowest_position_seed = seed_value
		_lowest_position_effective = position_effective
		_lowest_position_hour = current_hour
	if position_effective >= position.success_threshold:
		_stage_counts["position_success_line_180"] = int(
			_stage_counts["position_success_line_180"]
		) + 1
	var position_start: ActionStartResult = context_service.start_player_action(
		action_service,
		position,
		character,
		current_hour,
		organization_target,
		position_extra
	)
	if not position_start.is_success() or current_hour > DAY_180:
		_fail_seed(
			seed_value,
			3,
			current_hour,
			"position_start_failed" if not position_start.is_success() else "position_after_180_days"
		)
		return
	spent += context_service.get_funding_cost(position, position_extra)
	_stage_counts["position_path_180"] = int(_stage_counts["position_path_180"]) + 1
	_total_position_hour += current_hour
	_total_spent += spent
	_total_income += income
	_total_studies += studies
	_update_worst(seed_value, 4, current_hour)
	if int(character.current_status.get("wealth", 0)) > initial_wealth + income:
		_fail_reason("unexpected_wealth_source")


func _execute_action(
	society: SocietySimulationService,
	context_service: PlayerActionContextService,
	action_service: ActionService,
	character: CharacterData,
	definition: ActionDefinitionData,
	current_hour: int,
	target_id: String,
	extra_funding: int,
	study_skill_id: String = ""
) -> Dictionary:
	var wealth_before: int = int(character.current_status.get("wealth", 0))
	var result: ActionStartResult = context_service.start_player_action(
		action_service,
		definition,
		character,
		current_hour,
		target_id,
		extra_funding,
		study_skill_id
	)
	if not result.is_success():
		return {"started": false, "errors": result.errors}
	var action: ActionInstanceData = result.action
	var wealth_after_funding: int = int(character.current_status.get("wealth", 0))
	var completion_hour: int = maxi(action.estimated_completion_hour, current_hour + 1)
	action_service.update_to_hour(
		action, definition, character, completion_hour, _map
	)
	var domain_applied: bool = false
	if action.status == ActionInstanceData.STATUS_COMPLETED:
		domain_applied = society.apply_character_action_domain_effect(
			action, definition, character, _map, "budget_test_contact"
		)
	return {
		"started": true,
		"hour": action.completion_hour,
		"cost": wealth_before - wealth_after_funding,
		"wealth_after_funding": wealth_after_funding,
		"wealth_after": int(character.current_status.get("wealth", 0)),
		"outcome": action.outcome_code,
		"domain_applied": domain_applied,
	}


func _best_target(
	context_service: PlayerActionContextService,
	action_service: ActionService,
	definition: ActionDefinitionData,
	character: CharacterData,
	extra_funding: int,
	society: SocietySimulationService
) -> String:
	var target_ids: Array[String] = []
	if definition.category == "build_relationship":
		target_ids = society.roster.get_living_ids(character.country_id)
	else:
		target_ids = society.organizations.get_organization_ids()
	var best_id: String = ""
	var best_effective: float = -INF
	for target_id: String in target_ids:
		if target_id == character.id or not context_service.get_target_validation_error(
			definition, character, target_id
		).is_empty():
			continue
		var context: Dictionary = context_service.build_context(
			definition, character, target_id, extra_funding
		)
		var effective: float = action_service.calculate_effective_value(
			definition, character, context
		)
		if effective > best_effective or (
			is_equal_approx(effective, best_effective) and target_id < best_id
		):
			best_id = target_id
			best_effective = effective
	return best_id


func _maximum_affordable_extra(
	context_service: PlayerActionContextService,
	definition: ActionDefinitionData,
	character: CharacterData
) -> int:
	return clampi(
		int(character.current_status.get("wealth", 0))
		- context_service.get_base_funding_cost(definition),
		0,
		context_service.get_max_extra_funding()
	)


func _minimum_success_extra(
	context_service: PlayerActionContextService,
	action_service: ActionService,
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String,
	study_skill_id: String
) -> int:
	var affordable: int = _maximum_affordable_extra(
		context_service, definition, character
	)
	for extra: int in range(affordable + 1):
		var context: Dictionary = context_service.build_context(
			definition, character, target_id, extra, study_skill_id
		)
		if action_service.calculate_effective_value(
			definition, character, context
		) >= definition.success_threshold:
			return extra
	return affordable


func _fail_seed(seed_value: int, stage: int, hour: int, reason: String) -> void:
	_fail_reason(reason)
	_update_worst(seed_value, stage, hour)


func _fail_reason(reason: String) -> void:
	_failure_reasons[reason] = int(_failure_reasons.get(reason, 0)) + 1


func _update_worst(seed_value: int, stage: int, hour: int) -> void:
	if stage < _worst_stage or (stage == _worst_stage and hour > _worst_hour):
		_worst_seed = seed_value
		_worst_stage = stage
		_worst_hour = hour


func _deadlock_count() -> int:
	return SEED_COUNT - mini(
		int(_stage_counts["position_path_180"]),
		int(_stage_counts["position_success_line_180"])
	)


func _print_report() -> void:
	print("\n=== 1000 种子正常开局预算报告 ===")
	for stage_id: String in [
		"work_30", "relationship_60", "organization_90",
		"position_path_180", "position_success_line_180",
	]:
		var count: int = int(_stage_counts[stage_id])
		print("[RATE] %s: %d/%d (%.2f%%)" % [
			stage_id, count, SEED_COUNT, float(count) * 100.0 / float(SEED_COUNT),
		])
	var reasons: Array[String] = []
	for raw_reason: Variant in _failure_reasons:
		reasons.append(str(raw_reason))
	reasons.sort()
	if reasons.is_empty():
		print("[FAILURE_REASONS] 无")
	else:
		for reason: String in reasons:
			print("[FAILURE_REASON] %s: %d" % [reason, int(_failure_reasons[reason])])
	if _deadlock_count() > 0:
		print("[WORST_SEED] seed=%d stage=%d hour=%d" % [
			_worst_seed, _worst_stage, _worst_hour,
		])
	else:
		print("[WORST_SEED] seed=%d position_effective=%.2f hour=%d" % [
			_lowest_position_seed,
			_lowest_position_effective,
			_lowest_position_hour,
		])
	print("[AVERAGE_COST] 支出 %.2f / 工作收入 %.2f" % [
		float(_total_spent) / float(SEED_COUNT),
		float(_total_income) / float(SEED_COUNT),
	])
	print("[AVERAGE_TIME] 关系 %.2f 天 / 组织 %.2f 天 / 职位路径 %.2f 天" % [
		float(_total_relationship_hour) / float(SEED_COUNT * 24),
		float(_total_organization_hour) / float(SEED_COUNT * 24),
		float(_total_position_hour) / float(SEED_COUNT * 24),
	])
	print("[AVERAGE_STUDIES] %.3f（上限 2）" % (
		float(_total_studies) / float(SEED_COUNT)
	))
	print("[POSITION_EFFECTIVE] min=%.2f avg=%.2f max=%.2f success_line=55.00" % [
		_position_effective_minimum,
		_position_effective_total / float(SEED_COUNT),
		_position_effective_maximum,
	])
	print("[DETERMINISTIC_DEADLOCKS] %d" % _deadlock_count())


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failures += 1
		print("[FAIL] %s" % message)
