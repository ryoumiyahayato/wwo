extends SceneTree
## Formal conformance guard for the autonomous social sandbox.
##
## This test deliberately uses V23ProductSimulationV2, the same composition
## root used by the normal product entry. It does not grant positions, move
## people, write relationships or inject final social outcomes.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := V23Config.new()
	test.equal(config.load_all(), OK, "正式社会沙盒配置可加载")
	var people: Array = config.social_people()
	var rules: Dictionary = config.sandbox_rules()
	var methods: Array = rules.get("methods", []) as Array
	test.expect(people.size() >= 6, "当前里尔社会至少包含六名具体人物")
	test.expect(methods.size() >= 24, "统一方法目录具有实际可用范围")
	var method_ids: Dictionary = {}
	var illegal_count: int = 0
	var seek_position: Dictionary = {}
	for raw_method: Variant in methods:
		if not raw_method is Dictionary:
			continue
		var method: Dictionary = raw_method as Dictionary
		var method_id: String = str(method.get("method_id", ""))
		test.expect(
			not method_id.is_empty() and not method_ids.has(method_id),
			"方法 ID 唯一：%s" % method_id
		)
		method_ids[method_id] = true
		illegal_count += 1 if bool(method.get("illegal", false)) else 0
		if method_id == "seek_position":
			seek_position = method
	test.expect(illegal_count >= 6, "违法方法不是模拟总开关之外的禁用项")
	test.expect(
		str(seek_position.get("label_zh", "")) == "争取组织职位"
		and not seek_position.has("conflict_key"),
		"争取职位方法不再绑定固定工作组路线"
	)

	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "正式 V2 社会沙盒可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 formal social sandbox conformance")
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	test.expect(sandbox != null, "正式组合根使用完成版社会沙盒协调器")
	if sandbox == null:
		test.finish(self, "V2.3 formal social sandbox conformance")
		return

	_test_unique_authorities(simulation, sandbox)
	_test_situations_and_stable_goals(simulation, sandbox, people)
	_test_player_and_npc_use_same_task_shape(simulation, sandbox)
	_test_declared_conflicts(sandbox)
	_test_atomic_commit_rollback()
	_test_autonomous_month(simulation, sandbox, people)
	_test_save_round_trip(simulation)
	_test_determinism()
	test.finish(self, "V2.3 formal social sandbox conformance")


func _test_unique_authorities(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2
) -> void:
	test.equal(sandbox._schedule, simulation.schedule, "复用唯一日程服务")
	test.equal(sandbox._locations, simulation.spatial_locations, "复用唯一地点服务")
	test.equal(sandbox._knowledge, simulation.knowledge, "复用唯一知识服务")
	test.equal(
		sandbox._relationships,
		simulation.dynamic_relationships,
		"复用唯一动态关系服务"
	)
	test.equal(sandbox._organizations, simulation.organizations, "复用唯一组织服务")
	test.equal(sandbox._ledger, simulation.ledger, "复用唯一资金账本")


func _test_situations_and_stable_goals(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2,
	people: Array
) -> void:
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var pierre_before: Dictionary = _goals_by_signal(sandbox.goals_for(pierre))
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person_id: String = str((raw_person as Dictionary).get("person_id", ""))
		var situations: Array[Dictionary] = sandbox.situations_for(person_id)
		var goals: Array[Dictionary] = sandbox.goals_for(person_id)
		test.expect(not situations.is_empty(), "人物具有现实处境：%s" % person_id)
		test.expect(not goals.is_empty(), "人物具有候选目标：%s" % person_id)
		var goal_signals: Dictionary = _goals_by_signal(goals)
		for situation: Dictionary in situations:
			var signal_key: String = str(situation.get("signal_key", ""))
			test.expect(
				str(situation.get("kind", "")) in [
					"maintenance", "threat", "opportunity", "ambition",
				]
				and not signal_key.is_empty()
				and not (situation.get("provenance", []) as Array).is_empty()
				and not str(situation.get("expected_consequence", "")).is_empty()
				and not str(situation.get("invalidation_condition", "")).is_empty(),
				"处境可追溯且具有后果与失效条件：%s/%s" % [person_id, signal_key]
			)
			test.expect(
				goal_signals.has(signal_key),
				"当前正式里尔范围内的有效处境没有被四目标上限截断：%s/%s"
				% [person_id, signal_key]
			)
	sandbox.mark_dirty([pierre])
	sandbox.reevaluate_dirty(simulation.clock.total_hours)
	var pierre_after: Dictionary = _goals_by_signal(sandbox.goals_for(pierre))
	for signal_key: String in pierre_before.keys():
		if not pierre_after.has(signal_key):
			continue
		test.equal(
			str((pierre_after[signal_key] as Dictionary).get("goal_id", "")),
			str((pierre_before[signal_key] as Dictionary).get("goal_id", "")),
			"同一人物和处境键保持稳定目标 ID：%s" % signal_key
		)


func _test_player_and_npc_use_same_task_shape(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2
) -> void:
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var goal: Dictionary = _goal(sandbox.goals_for(pierre), "maintenance")
	var result: V2LifeLoopResult = sandbox.submit_intent(
		pierre,
		str(goal.get("goal_id", "")),
		"reliable_work",
		"",
		"player",
		{
			"current_hour": simulation.clock.total_hours,
			"preparation": 700,
		}
	)
	test.expect(result.success, "玩家通过正式统一意图入口建立任务")
	if not result.success:
		return
	var player_task: Dictionary = result.data.get("task", {}) as Dictionary
	test.equal(str(player_task.get("source", "")), "player", "任务保留玩家来源")
	var npc_task: Dictionary = {}
	for raw_task: Variant in sandbox.tasks.values():
		if not raw_task is Dictionary:
			continue
		var task: Dictionary = raw_task as Dictionary
		if str(task.get("source", "")) == "npc":
			npc_task = task
			break
	test.expect(not npc_task.is_empty(), "NPC 初始化后通过同一服务形成实际任务")
	if npc_task.is_empty():
		return
	for field: String in [
		"task_id", "intent_id", "actor_id", "method_id", "goal_id",
		"location_id", "start_hour", "end_hour", "status", "source",
	]:
		test.expect(player_task.has(field) and npc_task.has(field), "玩家与 NPC 任务共享字段：%s" % field)


func _test_declared_conflicts(sandbox: V23SocialSandboxServiceV2) -> void:
	var keys: Array[String] = sandbox._proposal_conflict_keys(
		{
			"actor_id": "actor_a",
			"target_id": "actor_b",
			"start_hour": 100,
			"end_hour": 102,
			"method_id": "seek_position",
		},
		{"conflict_key": "organization:position:sample"}
	)
	test.expect(keys.has("person:actor_a:100:102"), "行动者时段声明为冲突对象")
	test.expect(keys.has("person:actor_b:100:102"), "行动对象时段声明为冲突对象")
	test.expect(
		keys.has("unique:organization:position:sample"),
		"唯一职位声明为冲突对象"
	)


func _test_atomic_commit_rollback() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "原子回滚环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var goal: Dictionary = _goal(
		sandbox.goals_for(V2LifeLoopSimulation.PIERRE_ID), "maintenance"
	)
	var result: V2LifeLoopResult = sandbox.submit_intent(
		V2LifeLoopSimulation.PIERRE_ID,
		str(goal.get("goal_id", "")),
		"reliable_work",
		"",
		"player",
		{"current_hour": simulation.clock.total_hours, "preparation": 700}
	)
	test.expect(result.success, "原子回滚任务可通过正式管线建立")
	if not result.success:
		return
	var task: Dictionary = result.data.get("task", {}) as Dictionary
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours - 1))
	var organization_before: Dictionary = simulation.organizations.get_persistent_state()
	var relationship_before: Dictionary = simulation.dynamic_relationships.get_persistent_state()
	var ledger_before: Dictionary = simulation.ledger.get_persistent_state()
	var event_count: int = sandbox.event_ledger.size()
	sandbox.fail_next_commit_for_test = true
	simulation.advance_hours(1)
	test.equal(simulation.organizations.get_persistent_state(), organization_before, "提交故障回滚组织状态")
	test.equal(simulation.dynamic_relationships.get_persistent_state(), relationship_before, "提交故障回滚关系状态")
	test.equal(simulation.ledger.get_persistent_state(), ledger_before, "提交故障回滚资金状态")
	test.equal(sandbox.event_ledger.size(), event_count, "提交故障不追加虚假事件")


func _test_autonomous_month(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2,
	people: Array
) -> void:
	var started: int = Time.get_ticks_msec()
	simulation.run_days(30)
	var elapsed: int = Time.get_ticks_msec() - started
	test.equal(simulation.v2_3_hours_processed, 30 * 24, "玩家零输入时正式世界推进三十日")
	test.expect(elapsed < 30000, "三十日社会闭环在共享回归预算内")
	test.expect(not sandbox.event_ledger.is_empty(), "三十日内自然产生客观社会事件")
	test.expect(sandbox.tasks.size() <= 256, "任务历史保持有界")
	test.expect(sandbox.intents.size() <= 256, "意图历史保持有界")
	test.expect(sandbox.event_ledger.size() <= 1024, "重要事件账本保持有界")
	var seen: Dictionary = {}
	var previous_order: String = ""
	var npc_actors: Dictionary = {}
	var saw_failure: bool = false
	var saw_success: bool = false
	for event: Dictionary in sandbox.event_ledger:
		var event_id: String = str(event.get("event_id", ""))
		var order: String = str(event.get("ordering_key", ""))
		test.expect(
			not event_id.is_empty()
			and not seen.has(event_id)
			and (previous_order.is_empty() or order > previous_order),
			"事件 ID 唯一且按权威顺序追加"
		)
		test.expect(not bool(event.get("guaranteed_success", false)), "准备程度不形成必胜事件")
		seen[event_id] = true
		previous_order = order
		if str(event.get("source", "")) == "npc":
			npc_actors[str(event.get("actor_id", ""))] = true
		saw_success = saw_success or bool(event.get("success", false))
		saw_failure = saw_failure or not bool(event.get("success", false))
	test.expect(not npc_actors.is_empty(), "至少一名非玩家人物自主完成正式行动")
	test.expect(saw_success and saw_failure, "自然运行同时包含成功和失败而非单向剧本")
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var truth: Array[Dictionary] = sandbox.visible_events_for(pierre, true, 1024)
	var perceived: Array[Dictionary] = sandbox.visible_events_for(pierre, false, 1024)
	test.expect(perceived.size() <= truth.size(), "人物认知不会超过客观事件账本")
	test.expect(
		simulation.knowledge.records_for_person(pierre).size()
		< simulation.knowledge.records.size(),
		"知识仍按人物隔离"
	)
	var kinds: Dictionary = {}
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person_id: String = str((raw_person as Dictionary).get("person_id", ""))
		for situation: Dictionary in sandbox.situations_for(person_id):
			kinds[str(situation.get("kind", ""))] = true
	test.expect(kinds.has("maintenance"), "持续运行保留维持压力")
	test.expect(kinds.has("ambition"), "持续运行保留人物抱负")
	test.expect(kinds.has("threat") or kinds.has("opportunity"), "持续运行产生威胁或机会")


func _test_save_round_trip(simulation: V23ProductSimulationV2) -> void:
	var service := V23SaveService.new()
	var snapshot: Dictionary = service.build_snapshot(simulation)
	test.expect(service.validate_snapshot(snapshot).is_empty(), "正式社会闭环快照完整")
	var restored := V23ProductSimulationV2.new()
	test.expect(restored.initialize(), "恢复目标可初始化")
	if not restored.initialized:
		return
	test.expect(service.restore(snapshot, restored).success, "社会闭环可从正式快照恢复")
	test.equal(
		restored.social_sandbox.get_persistent_state(),
		simulation.social_sandbox.get_persistent_state(),
		"事件、任务、目标、承诺与证据往返保持"
	)
	test.equal(
		restored.organizations.get_persistent_state(),
		simulation.organizations.get_persistent_state(),
		"组织成员和职位往返保持"
	)


func _test_determinism() -> void:
	var first := V23ProductSimulationV2.new()
	var second := V23ProductSimulationV2.new()
	test.expect(first.initialize() and second.initialize(), "双确定性环境可初始化")
	if not first.initialized or not second.initialized:
		return
	first.run_days(7)
	second.run_days(7)
	test.equal(
		first.determinism_snapshot(),
		second.determinism_snapshot(),
		"相同初态和种子产生相同目标、任务、事件与认知"
	)


static func _goal(source: Array[Dictionary], kind: String) -> Dictionary:
	for goal: Dictionary in source:
		if str(goal.get("kind", "")) == kind:
			return goal
	return {}


static func _goals_by_signal(source: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for goal: Dictionary in source:
		var signal_key: String = str(goal.get("signal_key", ""))
		if not signal_key.is_empty():
			result[signal_key] = goal
	return result
