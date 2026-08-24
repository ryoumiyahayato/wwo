extends SceneTree

var failures := 0
var checks := 0


class RejectingPoliticalSimulationService:
	extends FormalPoliticalSimulationService

	func settle_day(_day_index: int, _inputs: Dictionary) -> bool:
		return false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(
		simulation.initialize(),
		"原子日推进测试世界可初始化：%s" % simulation.initialization_error
	)
	if simulation.initialized:
		var rejecting_politics := RejectingPoliticalSimulationService.new()
		var inputs := simulation.economy.political_inputs()
		inputs["authority"] = simulation.political_authority.snapshot(true)
		_check(
			rejecting_politics.configure(inputs, 0),
			"故障注入政治服务可从合法正式状态初始化"
		)
		if rejecting_politics.initialized:
			simulation.politics = rejecting_politics
			_check(
				simulation.economy.set_political_modifiers(
					rejecting_politics.economy_modifiers()
				),
				"故障注入前政治经济联动状态有效"
			)
			var before := simulation.get_persistent_state().duplicate(true)
			simulation.advance_minutes(
				60 * FormalWorldEconomyService.HOURS_PER_DAY
			)
			_check(
				simulation.initialized,
				"政治日结算失败后正式世界保持可用"
			)
			_check(
				simulation.total_minutes == 0,
				"政治日结算失败后正式时间回滚"
			)
			_check(
				simulation.get_persistent_state() == before,
				"政治日结算失败后经济、历史权威与政治状态原子回滚"
			)
			_check(
				simulation.initialization_error
				== "正式政治日结算拒绝了正式世界状态",
				"政治日结算失败保留明确错误原因"
			)
	print("Formal daily rollback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
