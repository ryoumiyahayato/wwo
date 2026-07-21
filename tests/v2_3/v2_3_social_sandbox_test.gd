extends "res://tests/v2_3/v2_3_social_sandbox_test_base.gd"
## Corrected atomicity assertion: a failed social action rolls back only its own
## authority changes. Unrelated transactions are tested elsewhere and must not
## consume this deliberately injected failure.


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
