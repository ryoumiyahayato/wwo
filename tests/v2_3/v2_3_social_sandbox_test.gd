extends SceneTree
## Property-oriented regression for the autonomous social sandbox core.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := V23Config.new()
	test.equal(config.load_all(), OK, "社会沙盒配置可加载")
	var people: Array = config.social_people()
	var rules: Dictionary = config.sandbox_rules()
	var methods: Array = rules.get("methods", []) as Array
	test.expect(people.size() >= 6, "社会世界至少包含六个人物节点")
	test.expect(_has_person(people, "character_louis_bernard"), "路易是普通人物节点")
	test.expect(methods.size() >= 24, "数据目录至少有二十四种具体方法")
	var method_ids: Dictionary = {}
	var illegal_count: int = 0
	for raw_method: Variant in methods:
		var method: Dictionary = raw_method as Dictionary
		var method_id: String = str(method.get("method_id", ""))
		test.expect(
			not method_id.is_empty() and not method_ids.has(method_id),
			"方法 ID 唯一：%s" % method_id
		)
		test.expect(
			int(method.get("duration_hours", 0)) >= 1
			and int(method.get("base_score", -1)) in range(0, 1001)
			and not (method.get("goal_kinds", []) as Array).is_empty(),
			"方法规则完整：%s" % method_id
		)
		method_ids[method_id] = true
		illegal_count += 1 if bool(method.get("illegal", false)) else 0
	test.expect(illegal_count >= 6, "多种违法方法允许尝试并携带风险")
	for method_id: String in [
		"reliable_work", "temporary_work", "ask_raise", "quit_job",
		"request_help", "repay_favor", "make_promise", "contact_person",
		"refuse_request", "exchange_favor", "persuade", "threaten",
		"deceive", "share_rumor", "form_alliance", "ask_question",
		"observe", "investigate", "verify_fact", "hide_evidence",
		"steal_document", "forge_document", "leak_information",
		"join_organization", "leave_organization", "seek_position",
		"support_candidate", "oppose_candidate", "call_meeting",
		"disobey_order", "bribe", "sabotage",
	]:
		test.expect(method_ids.has(method_id), "方法目录包含 %s" % method_id)

	var simulation := V23ProductSimulation.new()
	test.expect(simulation.initialize(), "正式产品社会沙盒可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 social sandbox")
		return
	var sandbox: V23SocialSandboxService = simulation.social_sandbox
	test.equal(sandbox._schedule, simulation.schedule, "复用唯一日程服务")
	test.equal(sandbox._locations, simulation.spatial_locations, "复用唯一地点服务")
	test.equal(sandbox._knowledge, simulation.knowledge, "复用唯一认知服务")
	test.equal(
		sandbox._relationships,
		simulation.dynamic_relationships,
		"复用唯一 V2.3 动态关系服务"
	)
	test.equal(sandbox._organizations, simulation.organizations, "复用唯一组织服务")
	test.equal(sandbox._ledger, simulation.ledger, "复用唯一资金账本")
	test.equal(simulation.organizations.organizations.size(), 4, "组织结构接入既有服务")
	test.equal(
		str(simulation.organizations.get_position(
			"factory_fives_workgroup_three:delegate"
		).get("holder_person_id", "")),
		"",
		"工厂代表职位起始为空缺"
	)
	var binding := V23ControlledUiBinding.new(simulation, true)
	var sandbox_view: Dictionary = binding.sandbox_view()
	test.expect(bool(sandbox_view.get("available", false)), "正式 UI 绑定开放处境行动视图")
	test.expect(
		not (sandbox_view.get("situations", []) as Array).is_empty()
		and not (sandbox_view.get("goals", []) as Array).is_empty()
		and not (sandbox_view.get("methods", []) as Array).is_empty(),
		"UI 同时展示人物处境、目标与具体方法"
	)
	test.expect(
		V23LifeLoopInterface.V2_3_PANEL_IDS.has("v2_3_sandbox"),
		"正式窗口导航包含处境行动面板"
	)
	test.expect(
		(binding.debug_state().get("social_sandbox", {}) as Dictionary).has(
			"selected_explanation"
		),
		"调试视图暴露 NPC 决策解释"
	)

	for raw_person: Variant in people:
		var person_id: String = str((raw_person as Dictionary).get("person_id", ""))
		var derived: Array[Dictionary] = sandbox.situations_for(person_id)
		var person_goals: Array[Dictionary] = sandbox.goals_for(person_id)
		test.expect(not derived.is_empty(), "人物具有派生处境：%s" % person_id)
		test.expect(not person_goals.is_empty(), "人物具有派生目标：%s" % person_id)
		test.expect(person_goals.size() <= 4, "人物目标保持有限：%s" % person_id)
		for situation_record: Dictionary in derived:
			test.expect(
				str(situation_record.get("kind", "")) in [
					"maintenance", "threat", "opportunity", "ambition",
				]
				and not (
					situation_record.get("provenance", []) as Array
				).is_empty()
				and not str(
					situation_record.get("expected_consequence", "")
				).is_empty()
				and not str(
					situation_record.get("invalidation_condition", "")
				).is_empty()
				and int(
					situation_record.get("urgency", -1)
				) in range(0, 1001)
				and int(situation_record.get("expires_hour", -1))
				> simulation.clock.total_hours,
				"处境包含类别、来源、后果、紧迫度、期限和失效条件"
			)
		for goal: Dictionary in person_goals:
			test.expect(
				str(goal.get("person_id", "")) == person_id
				and not str(goal.get("signal_id", "")).is_empty()
				and str(goal.get("status", "")) == "active",
				"目标可追溯到人物处境"
			)

	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var albert: String = V2LifeLoopSimulation.ALBERT_ID
	var lucien: String = V23LifeLoopSimulation.LUCIEN_ID
	var pierre_goal: Dictionary = _goal(
		sandbox.goals_for(pierre), "maintenance"
	)
	var albert_goal: Dictionary = _goal(
		sandbox.goals_for(albert), "ambition"
	)
	var work: V2LifeLoopResult = sandbox.submit_intent(
		pierre, str(pierre_goal.get("goal_id", "")), "reliable_work",
		"", "player",
		{"current_hour": simulation.clock.total_hours, "preparation": 1000}
	)
	test.expect(work.success, "玩家通过统一意图 API 安排工作方法")
	var work_task: Dictionary = work.data.get("task", {}) as Dictionary
	test.equal(str(work_task.get("source", "")), "player", "任务保留玩家来源")
	test.expect(
		not str(work_task.get("schedule_activity_id", "")).is_empty(),
		"任务绑定权威日程活动"
	)
	test.expect(bool(work_task.get("embedded", false)), "社会任务可嵌入真实班次")
	var promise: V2LifeLoopResult = sandbox.submit_intent(
		albert, str(albert_goal.get("goal_id", "")), "make_promise",
		lucien, "player",
		{"current_hour": simulation.clock.total_hours, "preparation": 1000}
	)
	test.expect(promise.success, "承诺使用同一意图和日程管线")
	var illegal: V2LifeLoopResult = sandbox.submit_intent(
		albert, str(albert_goal.get("goal_id", "")), "bribe",
		lucien, "player",
		{"current_hour": simulation.clock.total_hours, "preparation": 1000}
	)
	test.expect(illegal.success, "违法方法可进入实际任务而非硬门禁")
	test.expect(bool(illegal.data.get("illegal_attempt", false)), "违法尝试明确标识")
	test.expect(
		int((illegal.data.get("task", {}) as Dictionary).get("start_hour", -1))
		>= int((promise.data.get("task", {}) as Dictionary).get("end_hour", -1)),
		"同一人物的任务不重复占用已预留日程块"
	)
	var relationship_before: Dictionary = (
		simulation.dynamic_relationships.get_persistent_state()
	)
	var started: int = Time.get_ticks_msec()
	simulation.run_days(30)
	var elapsed: int = Time.get_ticks_msec() - started
	test.equal(simulation.v2_3_hours_processed, 720, "正式产品自主推进三十日")
	test.expect(elapsed < 15000, "三十日社会闭环在回归预算内")
	test.expect(not sandbox.event_ledger.is_empty(), "三十日产生客观社会事件")
	test.expect(sandbox.tasks.size() <= 256, "任务历史有界")
	test.expect(sandbox.intents.size() <= 256, "意图历史有界")
	test.expect(sandbox.event_ledger.size() <= 1024, "事件账本有界")
	var seen: Dictionary = {}
	var previous_order: String = ""
	var saw_illegal: bool = false
	var saw_guarantee: bool = false
	var saw_albert_npc_action: bool = false
	for event: Dictionary in sandbox.event_ledger:
		var event_id: String = str(event.get("event_id", ""))
		var ordering_key: String = str(event.get("ordering_key", ""))
		test.expect(
			not event_id.is_empty()
			and not seen.has(event_id)
			and (previous_order.is_empty() or ordering_key > previous_order),
			"事件按时间、相位和序列追加且 ID 唯一"
		)
		test.expect(
			int(event.get("phase", -1))
			== V23SocialSandboxService.PHASE_COMMIT
			and bool(event.get("attempted", false))
			and not str(event.get("task_id", "")).is_empty()
			and event.has("cause_event_id"),
			"事件区分提交排序与独立因果字段"
		)
		seen[event_id] = true
		previous_order = ordering_key
		saw_illegal = saw_illegal or bool(event.get("illegal", false))
		saw_guarantee = saw_guarantee or (
			bool(event.get("guaranteed_success", false))
			and bool(event.get("success", false))
		)
		saw_albert_npc_action = saw_albert_npc_action or (
			str(event.get("actor_id", "")) == albert
			and str(event.get("source", "")) == "npc"
		)
	test.expect(saw_illegal, "违法尝试进入客观事件账本")
	test.expect(saw_guarantee, "充分准备形成保证成功上界")
	test.expect(
		saw_albert_npc_action,
		"未由玩家控制的正式人物阿尔贝走同一自治行动管线"
	)
	var delegate: Dictionary = simulation.organizations.get_position(
		"factory_fives_workgroup_three:delegate"
	)
	test.expect(
		str(delegate.get("holder_person_id", "")) in [
			V23LifeLoopSimulation.JULES_ID, "character_louis_bernard",
		],
		"普通工作组成员自主产生职位结果"
	)
	test.expect(
		simulation.dynamic_relationships.get_persistent_state()
		!= relationship_before,
		"真实互动改变既有动态关系"
	)
	test.expect(not sandbox.commitments.is_empty(), "承诺成为可保存社会后果")
	test.expect(
		simulation.ledger.validate_balances(
			simulation.households.households
		).success,
		"社会行动后账本链保持一致"
	)
	var truth: Array[Dictionary] = sandbox.visible_events_for(pierre, true, 1024)
	var perceived: Array[Dictionary] = sandbox.visible_events_for(
		pierre, false, 1024
	)
	test.expect(perceived.size() <= truth.size(), "人物认知不超过客观真相")
	test.expect(
		simulation.knowledge.records_for_person(pierre).size()
		< simulation.knowledge.records.size(),
		"知识按人物隔离而非复制事件账本"
	)
	var kinds: Dictionary = {}
	for raw_person: Variant in people:
		for situation_record: Dictionary in sandbox.situations_for(str(
			(raw_person as Dictionary).get("person_id", "")
		)):
			kinds[str(situation_record.get("kind", ""))] = true
	test.expect(kinds.has("maintenance"), "闭环保留维持压力")
	test.expect(kinds.has("threat"), "闭环产生真实威胁")
	test.expect(
		kinds.has("opportunity")
		or not str(delegate.get("holder_person_id", "")).is_empty(),
		"机会会出现并在被占用后自然失效"
	)
	test.expect(kinds.has("ambition"), "闭环保留人物抱负")
	test.expect(
		not sandbox.explanation_for(V23LifeLoopSimulation.JULES_ID).is_empty()
		and not sandbox.explanation_for(
			"character_louis_bernard"
		).is_empty(),
		"NPC 决策解释有据可查"
	)

	var snapshot: Dictionary = V23SaveService.new().build_snapshot(simulation)
	test.expect(
		V23SaveService.new().validate_snapshot(snapshot).is_empty(),
		"社会沙盒快照通过完整性校验"
	)
	var restored := V23ProductSimulation.new()
	test.expect(restored.initialize(), "恢复目标可初始化")
	test.expect(
		V23SaveService.new().restore(snapshot, restored).success,
		"社会沙盒随产品快照原子恢复"
	)
	test.equal(
		restored.social_sandbox.get_persistent_state(),
		simulation.social_sandbox.get_persistent_state(),
		"稳定任务、事件、承诺和证据 ID 往返保持"
	)
	test.equal(
		restored.organizations.get_persistent_state(),
		simulation.organizations.get_persistent_state(),
		"组织成员和唯一职位往返保持"
	)
	var legacy_source := V23ProductSimulation.new()
	var legacy_target := V23ProductSimulation.new()
	test.expect(
		legacy_source.initialize() and legacy_target.initialize(),
		"旧快照补建双环境可初始化"
	)
	var legacy: Dictionary = legacy_source.get_persistent_state()
	legacy.erase("social_sandbox_state")
	test.expect(
		legacy_target.restore_v2_3_state(legacy).success,
		"缺失沙盒字段的旧 V2.3 快照确定性补建"
	)
	test.expect(
		legacy_target.social_sandbox.event_ledger.is_empty()
		and not legacy_target.social_sandbox.goals_for(pierre).is_empty(),
		"旧快照补建目标但不伪造历史事件"
	)

	_test_atomic_rollback()
	_test_position_conflict()
	_test_cash_effect()
	_test_cross_seed_guarantee()
	_test_determinism()
	test.finish(self, "V2.3 social sandbox")


func _test_atomic_rollback() -> void:
	var simulation := V23ProductSimulation.new()
	test.expect(simulation.initialize(), "原子回滚环境可初始化")
	var goal: Dictionary = _goal(
		simulation.social_sandbox.goals_for(
			V2LifeLoopSimulation.PIERRE_ID
		), "maintenance"
	)
	var result: V2LifeLoopResult = simulation.social_sandbox.submit_intent(
		V2LifeLoopSimulation.PIERRE_ID,
		str(goal.get("goal_id", "")), "reliable_work", "", "player",
		{"current_hour": simulation.clock.total_hours, "preparation": 1000}
	)
	test.expect(result.success, "原子回滚任务可建立")
	var task: Dictionary = result.data.get("task", {}) as Dictionary
	simulation.advance_hours(maxi(
		0,
		int(task.get("end_hour", simulation.clock.total_hours + 1))
		- simulation.clock.total_hours - 1
	))
	var organization_before: Dictionary = simulation.organizations.get_persistent_state()
	var relationship_before: Dictionary = (
		simulation.dynamic_relationships.get_persistent_state()
	)
	var ledger_before: Dictionary = simulation.ledger.get_persistent_state()
	var event_count: int = simulation.social_sandbox.event_ledger.size()
	simulation.social_sandbox.fail_next_commit_for_test = true
	simulation.advance_hours(1)
	test.equal(
		simulation.organizations.get_persistent_state(),
		organization_before,
		"提交故障回滚组织状态"
	)
	test.equal(
		simulation.dynamic_relationships.get_persistent_state(),
		relationship_before,
		"提交故障回滚关系状态"
	)
	test.equal(
		simulation.ledger.get_persistent_state(),
		ledger_before,
		"提交故障回滚资金状态"
	)
	test.equal(
		simulation.social_sandbox.event_ledger.size(),
		event_count,
		"提交故障不追加虚假事件"
	)
	test.equal(
		str((simulation.social_sandbox.tasks[
			str(task.get("task_id", ""))
		] as Dictionary).get("failure_step", "")),
		"atomic_commit",
		"回滚任务记录失败阶段"
	)


func _test_cross_seed_guarantee() -> void:
	var successes: Array[bool] = []
	for offset: int in range(3):
		var simulation := V23ProductSimulation.new()
		test.expect(simulation.initialize(), "跨种子环境 %d 初始化" % offset)
		simulation.random.set_seed(2301900 + offset * 7919)
		var goal: Dictionary = _goal(
			simulation.social_sandbox.goals_for(
				V2LifeLoopSimulation.PIERRE_ID
			), "maintenance"
		)
		var result: V2LifeLoopResult = simulation.social_sandbox.submit_intent(
			V2LifeLoopSimulation.PIERRE_ID,
			str(goal.get("goal_id", "")), "reliable_work", "", "player",
			{"current_hour": simulation.clock.total_hours, "preparation": 1000}
		)
		test.expect(result.success, "跨种子任务 %d 安排" % offset)
		var task: Dictionary = result.data.get("task", {}) as Dictionary
		simulation.advance_hours(
			int(task.get("end_hour", simulation.clock.total_hours + 1))
			- simulation.clock.total_hours
		)
		var event: Dictionary = _event_for_task(
			simulation.social_sandbox.event_ledger,
			str(task.get("task_id", ""))
		)
		successes.append(
			bool(event.get("success", false))
			and bool(event.get("guaranteed_success", false))
		)
	test.expect(not false in successes, "保证成功上界跨三个种子成立")


func _test_position_conflict() -> void:
	var simulation := V23ProductSimulation.new()
	test.expect(simulation.initialize(), "唯一职位冲突环境可初始化")
	var jules_tasks: Array[Dictionary] = simulation.social_sandbox.tasks_for(
		V23LifeLoopSimulation.JULES_ID
	)
	var louis_tasks: Array[Dictionary] = simulation.social_sandbox.tasks_for(
		"character_louis_bernard"
	)
	test.expect(
		not jules_tasks.is_empty() and not louis_tasks.is_empty(),
		"两名普通成员都从职位空缺形成竞争任务"
	)
	var due_hour: int = int(jules_tasks.front().get("end_hour", -1))
	test.equal(
		due_hour,
		int(louis_tasks.front().get("end_hour", -2)),
		"同一空缺任务进入同小时结算批次"
	)
	simulation.advance_hours(maxi(
		0, due_hour - simulation.clock.total_hours - 1
	))
	for person_id: String in [
		V23LifeLoopSimulation.JULES_ID, "character_louis_bernard",
	]:
		simulation.spatial_locations.force_set_at_location(
			person_id,
			"location_lille_fives_factory",
			simulation.clock.total_hours
		)
	simulation.advance_hours(1)
	var success_count: int = 0
	var conflict_count: int = 0
	for event: Dictionary in simulation.social_sandbox.event_ledger:
		if str(event.get("method_id", "")) != "seek_position":
			continue
		success_count += 1 if bool(event.get("success", false)) else 0
		conflict_count += 1 if str(event.get(
			"failure_step", ""
		)) == "conflict_resolution" else 0
	test.equal(success_count, 1, "唯一职位批次只允许一个成功者")
	test.equal(conflict_count, 1, "失败者记录明确冲突阶段")
	test.expect(
		not str(simulation.organizations.get_position(
			"factory_fives_workgroup_three:delegate"
		).get("holder_person_id", "")).is_empty(),
		"冲突提交后唯一职位有且仅有持有人"
	)


func _test_cash_effect() -> void:
	var simulation := V23ProductSimulation.new()
	test.expect(simulation.initialize(), "现金社会后果环境可初始化")
	var albert: String = V2LifeLoopSimulation.ALBERT_ID
	var lucien: String = V23LifeLoopSimulation.LUCIEN_ID
	var goal: Dictionary = _goal(
		simulation.social_sandbox.goals_for(albert), "ambition"
	)
	var result: V2LifeLoopResult = simulation.social_sandbox.submit_intent(
		albert, str(goal.get("goal_id", "")), "bribe", lucien, "player",
		{"current_hour": simulation.clock.total_hours, "preparation": 1000}
	)
	test.expect(result.success, "现金型违法尝试可建立任务")
	var task: Dictionary = result.data.get("task", {}) as Dictionary
	var due_hour: int = int(task.get("end_hour", -1))
	simulation.advance_hours(maxi(
		0, due_hour - simulation.clock.total_hours - 1
	))
	for person_id: String in [albert, lucien]:
		simulation.spatial_locations.force_set_at_location(
			person_id,
			"location_lille_prefecture_office",
			simulation.clock.total_hours
		)
	var cash_before: int = int(
		simulation.households.household_for_person(albert).get(
			"cash_centimes", 0
		)
	)
	simulation.advance_hours(1)
	var event: Dictionary = _event_for_task(
		simulation.social_sandbox.event_ledger,
		str(task.get("task_id", ""))
	)
	test.expect(
		bool(event.get("success", false))
		and bool(event.get("illegal", false)),
		"违法现金方法在真实同地后完成权威结算"
	)
	test.equal(
		int(simulation.households.household_for_person(albert).get(
			"cash_centimes", 0
		)),
		cash_before - 200,
		"现金支出只由既有账本改变住户余额"
	)
	test.expect(
		simulation.ledger.has_key(
			"sandbox:%s:cost" % str(event.get("event_id", ""))
		),
		"现金社会后果具有账本幂等键"
	)
	test.expect(
		simulation.ledger.validate_balances(
			simulation.households.households
		).success,
		"现金社会后果后账本链仍一致"
	)


func _test_determinism() -> void:
	var first := V23ProductSimulation.new()
	var second := V23ProductSimulation.new()
	test.expect(
		first.initialize() and second.initialize(),
		"社会沙盒双确定性环境初始化"
	)
	first.run_days(30)
	second.run_days(30)
	test.equal(
		first.determinism_snapshot(),
		second.determinism_snapshot(),
		"相同初态的目标、方法、冲突、事件和认知完全确定"
	)


static func _has_person(people: Array, person_id: String) -> bool:
	for raw_person: Variant in people:
		if (
			raw_person is Dictionary
			and str((raw_person as Dictionary).get("person_id", "")) == person_id
		):
			return true
	return false


static func _goal(source: Array[Dictionary], kind: String) -> Dictionary:
	for goal: Dictionary in source:
		if str(goal.get("kind", "")) == kind:
			return goal
	return {}


static func _event_for_task(
	events: Array[Dictionary], task_id: String
) -> Dictionary:
	for event: Dictionary in events:
		if str(event.get("task_id", "")) == task_id:
			return event
	return {}
