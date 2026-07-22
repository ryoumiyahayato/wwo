extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23ProductSimulationV2.new()
	print("initialize=", simulation.initialize())
	var sandbox := simulation.social_sandbox as V23SocialSandboxServiceV2
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var maintenance: Dictionary = {}
	for goal: Dictionary in sandbox.goals_for(pierre):
		if str(goal.get("kind", "")) == "maintenance":
			maintenance = goal
			break
	var player_result: V2LifeLoopResult = sandbox.submit_intent(
		pierre,
		str(maintenance.get("goal_id", "")),
		"reliable_work",
		"",
		"player",
		{"current_hour": simulation.clock.total_hours, "preparation": 700}
	)
	print("player_result_success=", player_result.success)
	print("player_result_message=", player_result.message)
	print("player_result_data=", player_result.data)
	for person: Dictionary in simulation.v2_3_config.social_people():
		var person_id: String = str(person.get("person_id", ""))
		print("initial person=", person_id)
		print("  goals=", sandbox.goals_for(person_id))
		print("  tasks=", sandbox.tasks_for(person_id, true))
		print("  explanation=", sandbox.explanation_for(person_id))
	simulation.run_days(3)
	print("after_3_days events=", sandbox.event_ledger)
	for person: Dictionary in simulation.v2_3_config.social_people():
		var person_id: String = str(person.get("person_id", ""))
		print("after person=", person_id)
		print("  tasks=", sandbox.tasks_for(person_id, true))
		print("  explanation=", sandbox.explanation_for(person_id))
	quit(0)
