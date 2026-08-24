extends "res://tests/v2_3/v2_3_social_sandbox_test_base.gd"
## Corrected atomicity assertion: a failed social action rolls back only its own
## authority changes. Unrelated transactions are tested elsewhere and must not
## consume this deliberately injected failure.


func _test_declared_conflicts(sandbox: V23SocialSandboxServiceV2) -> void:
	super._test_declared_conflicts(sandbox)
	_test_stale_position_revalidation()
	_test_vacant_position_control()
	_test_stale_commitment_revalidation()
	_test_open_commitment_control()
	_test_stale_employment_revalidation()
	_test_active_employment_control()
	_test_temporary_work_without_employment()


func _test_stale_position_revalidation() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "过期职位计划回归环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var actor_a: String = V2LifeLoopSimulation.PIERRE_ID
	var actor_b: String = "character_jules_martin"
	var task: Dictionary = _submit_position_task(simulation, sandbox, actor_a)
	test.expect(not task.is_empty(), "人物 A 通过正式社会沙盒建立有效职位任务")
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	var position_id: String = str(task.get("position_id", ""))
	_cancel_other_social_tasks(sandbox, task_id)
	var claim_result: V2LifeLoopResult = simulation.organizations.claim_position(
		actor_b, position_id, simulation.clock.total_hours, "test:prior_position_claim"
	)
	test.expect(claim_result.success, "人物 B 通过权威组织 API 合法取得同一职位")
	if not claim_result.success:
		return
	var events_before: int = sandbox.event_ledger.size()
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	var position: Dictionary = simulation.organizations.get_position(position_id)
	test.equal(str(position.get("holder_person_id", "")), actor_b, "人物 B 的先行合法职位变更没有被过期任务回滚")
	test.equal(str(stored_task.get("status", "")), "failed", "人物 A 的过期职位任务正常失败")
	test.equal(str(stored_task.get("failure_step", "")), "position_prerequisite", "失败归类为职位前置条件重验")
	test.expect(str(stored_task.get("failure_step", "")) != "atomic_commit", "现实变化不归类为原子提交故障")
	test.expect(str(stored_task.get("failure_reason", "")).contains("不再空缺"), "失败原因明确指出职位已不再空缺")
	test.equal(_successful_position_events_for(sandbox, task_id), 0, "人物 A 没有虚假的成功职位事件")
	test.expect(sandbox.event_ledger.size() >= events_before, "过期计划失败没有倒退既有事件账本")


func _test_vacant_position_control() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "空缺职位控制环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var task: Dictionary = _submit_position_task(
		simulation, sandbox, V2LifeLoopSimulation.PIERRE_ID
	)
	test.expect(not task.is_empty(), "职位仍空缺时可通过正式路径建立任务")
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	_cancel_other_social_tasks(sandbox, task_id)
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.expect(str(stored_task.get("status", "")) in ["completed", "failed"], "空缺职位任务经过既有随机结算路径")
	test.expect(str(stored_task.get("failure_step", "")) != "position_prerequisite", "条件保持有效时不产生职位前置失败")


func _submit_position_task(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2,
	actor_id: String
) -> Dictionary:
	var goal: Dictionary = {}
	for candidate: Dictionary in sandbox.goals_for(actor_id):
		if str(candidate.get("signal_key", "")).begins_with("position:"):
			goal = candidate
			break
	if goal.is_empty():
		return {}
	var result: V2LifeLoopResult = sandbox.submit_intent(
		actor_id,
		str(goal.get("goal_id", "")),
		"seek_position",
		"",
		"player",
		{"current_hour": simulation.clock.total_hours, "preparation": 700}
	)
	return result.data.get("task", {}) as Dictionary if result.success else {}


static func _cancel_other_social_tasks(
	sandbox: V23SocialSandboxServiceV2, retained_task_id: String
) -> void:
	for task_id_variant: Variant in sandbox.tasks.keys():
		var task_id: String = str(task_id_variant)
		if task_id == retained_task_id:
			continue
		var task: Dictionary = sandbox.tasks[task_id] as Dictionary
		if str(task.get("status", "")) == "scheduled":
			task["status"] = "cancelled"
			sandbox.tasks[task_id] = task


static func _successful_position_events_for(
	sandbox: V23SocialSandboxServiceV2, task_id: String
) -> int:
	var count: int = 0
	for event: Dictionary in sandbox.event_ledger:
		if (
			str(event.get("task_id", "")) == task_id
			and str(event.get("method_id", "")) == "seek_position"
			and bool(event.get("success", false))
		):
			count += 1
	return count


func _test_stale_commitment_revalidation() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "过期承诺计划回归环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var actor_id: String = "jeanne"
	var beneficiary_id: String = "character_jules_martin"
	var create_result: V2LifeLoopResult = sandbox._create_commitment(
		actor_id, beneficiary_id, "test:commitment_created", simulation.clock.total_hours
	)
	test.expect(create_result.success, "通过既有承诺领域路径建立开放承诺")
	if not create_result.success:
		return
	var commitment: Dictionary = create_result.data.get("commitment", {}) as Dictionary
	var commitment_id: String = str(commitment.get("commitment_id", ""))
	_cancel_all_scheduled_social_tasks(sandbox, simulation.clock.total_hours)
	sandbox.set_player_person("character_albert_dumont")
	var task: Dictionary = _submit_repay_task(
		simulation, sandbox, actor_id, beneficiary_id
	)
	test.expect(
		str(task.get("commitment_id", "")) == commitment_id,
		"偿还任务绑定计划时适用的具体承诺"
	)
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	_cancel_other_social_tasks(sandbox, task_id)
	var settle_result: V2LifeLoopResult = sandbox._settle_commitment(
		actor_id, beneficiary_id, "test:earlier_settlement", simulation.clock.total_hours
	)
	test.expect(settle_result.success, "更早行动通过既有权威路径履行同一承诺")
	if not settle_result.success:
		return
	var settled_before: Dictionary = (
		sandbox.commitments.get(commitment_id, {}) as Dictionary
	).duplicate(true)
	var commitment_count_before: int = sandbox.commitments.size()
	var relationship_before: Array[Dictionary] = (
		simulation.dynamic_relationships.contact_candidates(actor_id, simulation.knowledge)
	)
	var events_before: Array[Dictionary] = sandbox.event_ledger.duplicate(true)
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.equal(str(stored_task.get("status", "")), "failed", "过期偿还任务正常失败")
	test.equal(str(stored_task.get("failure_step", "")), "commitment_prerequisite", "失败归类为承诺前置条件重验")
	test.expect(str(stored_task.get("failure_step", "")) != "atomic_commit", "承诺状态变化不归类为原子提交故障")
	test.equal(sandbox.commitments.get(commitment_id, {}), settled_before, "更早履行的承诺状态和结算因果保持不变")
	test.equal(sandbox.commitments.size(), commitment_count_before, "过期偿还没有增加承诺总数")
	test.equal(_open_commitments_for(sandbox, actor_id, beneficiary_id), 0, "过期偿还没有伪造开放替代承诺")
	test.equal(
		simulation.dynamic_relationships.contact_candidates(actor_id, simulation.knowledge),
		relationship_before,
		"过期任务没有回滚或重复更早履行的关系效果"
	)
	test.expect(
		sandbox.event_ledger.slice(0, events_before.size()) == events_before,
		"更早存在的事件账本前缀没有被过期任务回滚"
	)
	test.equal(_successful_repay_events_for(sandbox, task_id), 0, "过期任务没有虚假成功偿还事件")


func _test_open_commitment_control() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "开放承诺控制环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var actor_id: String = "jeanne"
	var beneficiary_id: String = "character_jules_martin"
	var create_result: V2LifeLoopResult = sandbox._create_commitment(
		actor_id, beneficiary_id, "test:control_commitment", simulation.clock.total_hours
	)
	test.expect(create_result.success, "控制场景建立开放承诺")
	_cancel_all_scheduled_social_tasks(sandbox, simulation.clock.total_hours)
	sandbox.set_player_person("character_albert_dumont")
	var task: Dictionary = _submit_repay_task(
		simulation, sandbox, actor_id, beneficiary_id
	)
	test.expect(not task.is_empty(), "开放承诺可通过正式路径建立偿还任务")
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	_cancel_other_social_tasks(sandbox, task_id)
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.expect(str(stored_task.get("status", "")) in ["completed", "failed"], "开放承诺任务经过既有随机结算路径")
	test.expect(str(stored_task.get("failure_step", "")) != "commitment_prerequisite", "有效开放承诺不产生承诺前置失败")


static func _submit_repay_task(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2,
	actor_id: String,
	beneficiary_id: String
) -> Dictionary:
	var goal: Dictionary = _goal(sandbox.goals_for(actor_id), "maintenance")
	var result: V2LifeLoopResult = sandbox.submit_intent(
		actor_id,
		str(goal.get("goal_id", "")),
		"repay_favor",
		beneficiary_id,
		"npc",
		{
			"current_hour": simulation.clock.total_hours,
			"preparation": 700,
			"location_id": "location_lille_centre",
		}
	)
	return result.data.get("task", {}) as Dictionary if result.success else {}


static func _cancel_all_scheduled_social_tasks(
	sandbox: V23SocialSandboxServiceV2, current_hour: int
) -> void:
	for raw_task: Variant in sandbox.tasks.values():
		var task: Dictionary = raw_task as Dictionary
		if str(task.get("status", "")) != "scheduled":
			continue
		var actor_id: String = str(task.get("actor_id", ""))
		var actor_activity_id: String = str(task.get("schedule_activity_id", ""))
		if not actor_activity_id.is_empty():
			sandbox._schedule.cancel_activity_by_id(
				actor_id, actor_activity_id, current_hour, "test_isolation"
			)
		var target_id: String = str(task.get("target_id", ""))
		var target_activity_id: String = str(
			task.get("target_schedule_activity_id", "")
		)
		if not target_id.is_empty() and not target_activity_id.is_empty():
			sandbox._schedule.cancel_activity_by_id(
				target_id, target_activity_id, current_hour, "test_isolation"
			)
		task["status"] = "cancelled"
		sandbox.tasks[str(task.get("task_id", ""))] = task


static func _open_commitments_for(
	sandbox: V23SocialSandboxServiceV2, actor_id: String, beneficiary_id: String
) -> int:
	var count: int = 0
	for commitment: Dictionary in sandbox.commitments.values():
		if (
			str(commitment.get("promisor_id", "")) == actor_id
			and str(commitment.get("beneficiary_id", "")) == beneficiary_id
			and str(commitment.get("status", "")) == "open"
		):
			count += 1
	return count


static func _successful_repay_events_for(
	sandbox: V23SocialSandboxServiceV2, task_id: String
) -> int:
	var count: int = 0
	for event: Dictionary in sandbox.event_ledger:
		if (
			str(event.get("task_id", "")) == task_id
			and str(event.get("method_id", "")) == "repay_favor"
			and bool(event.get("success", false))
		):
			count += 1
	return count


func _test_stale_employment_revalidation() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "过期劳动关系回归环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var actor_id: String = V2LifeLoopSimulation.PIERRE_ID
	var task: Dictionary = _submit_employment_task(
		simulation, sandbox, actor_id, "reliable_work"
	)
	test.expect(not task.is_empty(), "通过正式沙盒建立劳动关系绑定任务")
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	var contract_id: String = str(task.get("employment_contract_id", ""))
	test.expect(not contract_id.is_empty(), "劳动关系绑定任务保存具体合同 ID")
	var snapshot: Dictionary = V23SaveService.new().build_snapshot(simulation)
	var saved_sandbox: Dictionary = snapshot.get("social_sandbox_state", {}) as Dictionary
	var saved_tasks: Dictionary = saved_sandbox.get("tasks", {}) as Dictionary
	test.equal(
		str((saved_tasks.get(task_id, {}) as Dictionary).get(
			"employment_contract_id", ""
		)),
		contract_id,
		"现有可扩展任务存档保留劳动合同绑定"
	)
	_cancel_other_social_tasks(sandbox, task_id)
	var organization_before: Dictionary = simulation.organizations.get_persistent_state()
	var contract_count_before: int = simulation.employment.contracts.size()
	var termination: V2LifeLoopResult = simulation.employment.change_contract_status_by_id(
		contract_id, actor_id, "resigned", simulation.clock.total_hours,
		"test:earlier_employment_termination"
	)
	test.expect(termination.success, "通过权威就业 API 先行终止绑定合同")
	if not termination.success:
		return
	var terminated_before: Dictionary = (
		simulation.employment.contracts.get(contract_id, {}) as Dictionary
	).duplicate(true)
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.equal(str(stored_task.get("status", "")), "failed", "过期劳动关系任务正常失败")
	test.equal(str(stored_task.get("failure_step", "")), "employment_prerequisite", "失败归类为就业前置条件重验")
	test.expect(str(stored_task.get("failure_step", "")) != "atomic_commit", "就业现实变化不归类为原子提交故障")
	test.equal(simulation.employment.contracts.get(contract_id, {}), terminated_before, "先行合同终止状态和因果没有被回滚")
	test.equal(simulation.employment.contracts.size(), contract_count_before, "过期任务没有创建替代劳动合同")
	test.equal(simulation.organizations.get_persistent_state(), organization_before, "无关组织权威状态没有被过期任务改变")
	test.equal(_successful_method_events_for(sandbox, task_id, "reliable_work"), 0, "过期任务没有虚假成功工作事件")


func _test_active_employment_control() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "有效劳动关系控制环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var task: Dictionary = _submit_employment_task(
		simulation, sandbox, V2LifeLoopSimulation.PIERRE_ID, "reliable_work"
	)
	test.expect(not task.is_empty(), "有效劳动关系可建立正式工作任务")
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	task.erase("employment_contract_id")
	sandbox.tasks[task_id] = task
	test.equal(
		sandbox._current_employment_prerequisite_failure(task), "",
		"旧待处理任务可从唯一雇主和工作地点安全重建合同"
	)
	_cancel_other_social_tasks(sandbox, task_id)
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.expect(str(stored_task.get("status", "")) in ["completed", "failed"], "有效劳动关系任务进入既有结果管线")
	test.expect(str(stored_task.get("failure_step", "")) != "employment_prerequisite", "当前有效合同不产生就业前置失败")


func _test_temporary_work_without_employment() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "无合同临时工作控制环境可初始化")
	if not simulation.initialized:
		return
	var actor_id: String = V2LifeLoopSimulation.PIERRE_ID
	var contract: Dictionary = simulation.employment.contract_for_person(actor_id)
	var termination: V2LifeLoopResult = simulation.employment.change_contract_status_by_id(
		str(contract.get("contract_id", "")), actor_id, "resigned",
		simulation.clock.total_hours, "test:temporary_work_no_employment"
	)
	test.expect(termination.success, "临时工作控制场景通过权威 API 结束既有合同")
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var task: Dictionary = _submit_employment_task(
		simulation, sandbox, actor_id, "temporary_work"
	)
	test.expect(not task.is_empty(), "临时工作不要求已有有效劳动合同")
	if task.is_empty():
		return
	var task_id: String = str(task.get("task_id", ""))
	_cancel_other_social_tasks(sandbox, task_id)
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours))
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.expect(str(stored_task.get("failure_step", "")) != "employment_prerequisite", "非就业绑定方法不进入就业前置重验")


static func _submit_employment_task(
	simulation: V23ProductSimulationV2,
	sandbox: V23SocialSandboxServiceV2,
	actor_id: String,
	method_id: String
) -> Dictionary:
	var goal: Dictionary = _goal(sandbox.goals_for(actor_id), "maintenance")
	var result: V2LifeLoopResult = sandbox.submit_intent(
		actor_id,
		str(goal.get("goal_id", "")),
		method_id,
		"",
		"player",
		{"current_hour": simulation.clock.total_hours, "preparation": 700}
	)
	return result.data.get("task", {}) as Dictionary if result.success else {}


static func _successful_method_events_for(
	sandbox: V23SocialSandboxServiceV2, task_id: String, method_id: String
) -> int:
	var count: int = 0
	for event: Dictionary in sandbox.event_ledger:
		if (
			str(event.get("task_id", "")) == task_id
			and str(event.get("method_id", "")) == method_id
			and bool(event.get("success", false))
		):
			count += 1
	return count


func _test_atomic_commit_rollback() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "原子回滚环境可初始化")
	if not simulation.initialized:
		return
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var actor_id: String = V2LifeLoopSimulation.PIERRE_ID
	var goal: Dictionary = _goal(sandbox.goals_for(actor_id), "maintenance")
	var result: V2LifeLoopResult = sandbox.submit_intent(
		actor_id,
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
	var task_id: String = str(task.get("task_id", ""))
	var due_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
	# The fault injector is intentionally one-shot. Remove unrelated scheduled
	# tasks so it targets this task rather than whichever NPC proposal sorts first.
	for other_task_id_variant: Variant in sandbox.tasks.keys():
		var other_task_id: String = str(other_task_id_variant)
		if other_task_id == task_id:
			continue
		var other_task: Dictionary = sandbox.tasks[other_task_id] as Dictionary
		if str(other_task.get("status", "")) == "scheduled":
			other_task["status"] = "cancelled"
			other_task["failure_step"] = "test_isolation"
			sandbox.tasks[other_task_id] = other_task
	simulation.advance_hours(maxi(0, due_hour - simulation.clock.total_hours - 1))
	var memberships_before: Array[Dictionary] = simulation.organizations.memberships_for_person(actor_id)
	var relationships_before: Array[Dictionary] = simulation.dynamic_relationships.contact_candidates(
		actor_id, simulation.knowledge
	)
	var cash_before: int = int(
		simulation.households.household_for_person(actor_id).get("cash_centimes", 0)
	)
	var task_events_before: int = _events_for_task(sandbox, task_id)
	sandbox.fail_next_commit_for_test = true
	simulation.advance_hours(1)
	test.equal(
		simulation.organizations.memberships_for_person(actor_id),
		memberships_before,
		"提交故障只回滚故障行动涉及的人物组织状态"
	)
	test.equal(
		simulation.dynamic_relationships.contact_candidates(actor_id, simulation.knowledge),
		relationships_before,
		"提交故障只回滚故障行动涉及的人物关系状态"
	)
	test.equal(
		int(simulation.households.household_for_person(actor_id).get("cash_centimes", 0)),
		cash_before,
		"提交故障回滚故障行动涉及的人物资金状态"
	)
	test.equal(
		_events_for_task(sandbox, task_id),
		task_events_before,
		"提交故障不为该任务追加虚假事件"
	)
	var stored_task: Dictionary = sandbox.tasks.get(task_id, {}) as Dictionary
	test.equal(str(stored_task.get("status", "")), "failed", "故障任务记录失败状态")
	test.equal(str(stored_task.get("failure_step", "")), "atomic_commit", "故障任务记录原子提交阶段")


static func _events_for_task(
	sandbox: V23SocialSandboxServiceV2,
	task_id: String
) -> int:
	var count: int = 0
	for event: Dictionary in sandbox.event_ledger:
		if (
			str(event.get("task_id", "")) == task_id
			or str(event.get("cause_task_id", "")) == task_id
			or task_id in (event.get("entity_ids", []) as Array)
		):
			count += 1
	return count
