class_name V23ProductSimulationV2
extends V23ProductSimulation
## Product composition using the completed social sandbox and bounded household
## self-maintenance through the existing schedule, travel, inventory and ledger.

var survival_autonomy := V23SurvivalAutonomyServiceV2.new()


func initialize(simulation_clock: SimulationClock = null) -> bool:
	social_sandbox = V23SocialSandboxServiceV2.new()
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
