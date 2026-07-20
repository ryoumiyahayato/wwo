extends SceneTree
## Generates reviewer-facing product saves through the formal V2.3 save
## service. These are local build artifacts and are intentionally excluded
## from source exports.

const OUTPUT_DIR: String = "user://saves/social_sandbox_review"

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var normal := V23ProductSimulation.new()
	if _initialized(normal, "normal_start"):
		_save(normal, "01_normal_start.json")

	var unattended := V23ProductSimulation.new()
	if _initialized(unattended, "unattended_30d"):
		unattended.run_days(30)
		_save(unattended, "02_unattended_30d.json")

	var conflict := V23ProductSimulation.new()
	if _initialized(conflict, "position_conflict"):
		_resolve_position_conflict(conflict)
		_save(conflict, "03_position_conflict.json")

	var cognition := V23ProductSimulation.new()
	if _initialized(cognition, "different_cognition"):
		_resolve_position_conflict(cognition)
		_seed_review_cognition(cognition)
		_save(cognition, "04_different_cognition.json")

	var secret := V23ProductSimulation.new()
	if _initialized(secret, "secret_action"):
		_resolve_secret_action(secret)
		_save(secret, "05_secret_action_consequence.json")

	print(
		"Social review saves: %s (%d failures)"
		% [ProjectSettings.globalize_path(OUTPUT_DIR), failures]
	)
	quit(0 if failures == 0 else 1)


func _initialized(
	simulation: V23ProductSimulation, label: String
) -> bool:
	if simulation.initialize():
		return true
	failures += 1
	push_error("%s 初始化失败：%s" % [
		label, simulation.initialization_error,
	])
	return false


func _save(simulation: V23ProductSimulation, filename: String) -> void:
	var path: String = "%s/%s" % [OUTPUT_DIR, filename]
	var result: SaveOperationResult = V23SaveService.new().save(
		simulation, path
	)
	if result.success:
		print("WROTE ", ProjectSettings.globalize_path(path))
	else:
		failures += 1
		push_error("评审存档生成失败：%s / %s" % [
			filename, result.message,
		])


func _resolve_position_conflict(
	simulation: V23ProductSimulation
) -> void:
	var jules_tasks: Array[Dictionary] = (
		simulation.social_sandbox.tasks_for(
			V23LifeLoopSimulation.JULES_ID
		)
	)
	if jules_tasks.is_empty():
		failures += 1
		push_error("职位冲突评审状态没有生成候选任务")
		return
	var due_hour: int = int(jules_tasks.front().get("end_hour", -1))
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


func _seed_review_cognition(
	simulation: V23ProductSimulation
) -> void:
	var position: Dictionary = simulation.organizations.get_position(
		"factory_fives_workgroup_three:delegate"
	)
	var actual_holder: String = str(position.get("holder_person_id", ""))
	var false_holder: String = (
		"character_louis_bernard"
		if actual_holder != "character_louis_bernard"
		else V23LifeLoopSimulation.JULES_ID
	)
	simulation.knowledge.record_fact(
		V2LifeLoopSimulation.PIERRE_ID,
		"review:delegate_holder",
		"factory_fives_workgroup_three:delegate",
		"position_holder",
		{"holder_person_id": false_holder},
		"review_fixture_letter",
		"message",
		simulation.clock.total_hours,
		420,
		"rumor",
		simulation.clock.total_hours + 7 * 24,
		"",
		"review:cognition:pierre:false_delegate"
	)
	simulation.knowledge.record_fact(
		V2LifeLoopSimulation.ALBERT_ID,
		"review:delegate_holder",
		"factory_fives_workgroup_three:delegate",
		"position_holder",
		{"holder_person_id": actual_holder},
		"review_fixture_direct_observation",
		"direct_observation",
		simulation.clock.total_hours,
		1000,
		"confirmed",
		simulation.clock.total_hours + 7 * 24,
		"",
		"review:cognition:albert:true_delegate"
	)


func _resolve_secret_action(
	simulation: V23ProductSimulation
) -> void:
	var albert: String = V2LifeLoopSimulation.ALBERT_ID
	var lucien: String = V23LifeLoopSimulation.LUCIEN_ID
	var ambition: Dictionary = {}
	for goal: Dictionary in simulation.social_sandbox.goals_for(albert):
		if str(goal.get("kind", "")) == "ambition":
			ambition = goal
			break
	var submission: V2LifeLoopResult = (
		simulation.social_sandbox.submit_intent(
			albert,
			str(ambition.get("goal_id", "")),
			"bribe",
			lucien,
			"player",
			{
				"current_hour": simulation.clock.total_hours,
				"preparation": 1000,
			}
		)
	)
	if not submission.success:
		failures += 1
		push_error("秘密行动评审任务生成失败：%s" % submission.user_message)
		return
	var task: Dictionary = submission.data.get("task", {}) as Dictionary
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
	simulation.advance_hours(1)
