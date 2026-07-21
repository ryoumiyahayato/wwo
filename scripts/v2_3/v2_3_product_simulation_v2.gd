class_name V23ProductSimulationV2
extends V23ProductSimulation
## Product composition using the completed social sandbox and bounded household
## self-maintenance through the existing schedule, travel, inventory and ledger.

var survival_autonomy := V23SurvivalAutonomyServiceV2.new()


func initialize(simulation_clock: SimulationClock = null) -> bool:
	social_sandbox = V23SocialSandboxServiceV3.new()
	(social_sandbox as V23SocialSandboxServiceV2).attach_product(self)
	if not super.initialize(simulation_clock):
		return false
	var autonomy_result: V2LifeLoopResult = survival_autonomy.configure(
		self, v2_3_config.social_people(), clock.total_hours
	)
	if not autonomy_result.success:
		return _fail_v2_3_initialization(autonomy_result.user_message)
	state_changed.emit({"survival_autonomy_initialized": true})
	return true


func authorize_leave_and_submit_social_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String,
	options: Dictionary
) -> V2LifeLoopResult:
	var preview: V2LifeLoopResult = social_sandbox.preview_intent(
		actor_id, goal_id, method_id, target_id, options
	)
	if preview.success:
		return social_sandbox.submit_intent(
			actor_id, goal_id, method_id, target_id, "player", options
		)
	if preview.error_code != "requires_leave_authorization":
		return preview
	var departure_hour: int = int(preview.data.get("start_hour", -1))
	var arrival_hour: int = int(preview.data.get("arrival_hour", -1))
	if departure_hour < clock.total_hours or arrival_hour <= departure_hour:
		return V2LifeLoopResult.fail(
			"invalid_leave_window",
			"无法确定需要解除的工作时段，请重新选择计划时间。"
		)
	var schedule_before: Dictionary = schedule.get_persistent_state()
	var travel_before: Dictionary = travel_execution.get_persistent_state()
	var spatial_before: Dictionary = spatial_locations.get_persistent_state()
	var leave_before: Dictionary = leave.get_persistent_state()
	var sandbox_before: Dictionary = social_sandbox.get_persistent_state()
	var manual_holds_before: Dictionary = manual_location_holds.duplicate(true)
	var authorization: V2LifeLoopResult = leave.authorize(
		actor_id,
		departure_hour,
		arrival_hour,
		clock.total_hours,
		employment
	)
	if not authorization.success:
		return authorization
	var record: Dictionary = authorization.data.get(
		"leave_authorization", {}
	) as Dictionary
	leave.release_contract_schedule(record, schedule)
	_replan_commutes_for_leave_record(record)
	var result: V2LifeLoopResult = social_sandbox.submit_intent(
		actor_id, goal_id, method_id, target_id, "player", options
	)
	if not result.success:
		schedule.restore_persistent_state(schedule_before)
		travel_execution.restore_persistent_state(travel_before)
		spatial_locations.restore_persistent_state(spatial_before)
		leave.restore_persistent_state(leave_before)
		social_sandbox.restore_persistent_state(sandbox_before)
		manual_location_holds = manual_holds_before
		return result
	notifications.add(
		"personal",
		"event",
		"请假并建立行动计划",
		"已解除与行程重叠的工作义务，并建立实际行程与行动日程。",
		clock.total_hours,
		"leave_for_social_plan:%s:%d" % [actor_id, departure_hour],
		result.affected_entity_ids
	)
	state_changed.emit({
		"leave": true,
		"social_sandbox": true,
		"player_override": true,
	})
	return result


func _settle_hour(total_hour: int) -> void:
	super._settle_hour(total_hour)
	var autonomy_result: Dictionary = survival_autonomy.process_hour(total_hour + 1)
	if int(autonomy_result.get("planned", 0)) > 0 or int(autonomy_result.get("blocked", 0)) > 0:
		state_changed.emit({"survival_autonomy": autonomy_result})


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["survival_autonomy_state"] = survival_autonomy.get_persistent_state()
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var base_result: V2LifeLoopResult = super.validate_v2_3_state(state)
	if not base_result.success:
		return base_result
	if state.has("survival_autonomy_state") and not survival_autonomy.validate_persistent_state(
		state.get("survival_autonomy_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("corrupt_save", "人物生活自理状态损坏")
	return V2LifeLoopResult.ok("正式世界状态有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.restore_v2_3_state(state)
	if not result.success:
		return result
	var configured: V2LifeLoopResult = survival_autonomy.configure(
		self, v2_3_config.social_people(), clock.total_hours
	)
	if not configured.success:
		return configured
	if state.has("survival_autonomy_state") and not survival_autonomy.restore_persistent_state(
		state.get("survival_autonomy_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("survival_autonomy_restore_failed", "人物生活自理状态恢复失败")
	state_changed.emit({"survival_autonomy_restored": true})
	return result


func determinism_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.determinism_snapshot()
	snapshot["survival_autonomy"] = survival_autonomy.get_persistent_state()
	return snapshot
