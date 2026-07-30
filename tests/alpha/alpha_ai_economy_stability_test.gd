extends SceneTree
## Full Alpha simulation with person AI, commodity settlement, save state and performance bounds.

const YEARS: int = 3
const HOURS: int = YEARS * 365 * 24
const PERFORMANCE_TARGET_USEC: int = 180_000_000
const ABSOLUTE_SAFETY_CAP_USEC: int = 300_000_000
const ECONOMIC_AI_ACTIONS: Array[String] = [
	"work", "seek_job", "migrate_for_work", "seek_credit", "repay_debt",
	"found_enterprise", "manage_enterprise", "establish_partnership",
	"sell_enterprise",
]

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var process_started_usec: int = Time.get_ticks_usec()
	var initialize_started_usec: int = Time.get_ticks_usec()
	var simulation := AlphaSimulationService.new()
	test.expect(simulation.initialize(), "AI经济稳定性测试可初始化完整Alpha模拟")
	var initialize_usec: int = Time.get_ticks_usec() - initialize_started_usec
	var started_usec: int = Time.get_ticks_usec()
	simulation.advance_hours(HOURS)
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var summary: Dictionary = simulation.commodity_market.world_summary()
	var integrity: Dictionary = simulation.validate_alpha_integrity()
	test.expect(bool(integrity.get("success", false)), "三年AI运行后跨服务引用完整")
	test.expect(
		bool(simulation.commodity_market.validate_integrity().get("success", false)),
		"三年AI运行后商品库存和价格完整"
	)
	test.expect(int(summary.get("population", 0)) > 0, "人口需求持续参与市场")
	test.expect(int(summary.get("fulfillment_bp", 0)) >= 0, "满足率保持有效")
	test.expect(int(summary.get("unemployment_bp", 0)) in range(0, 10001), "失业率保持有效")
	test.expect(simulation.alpha_ai.decisions.size() > 0, "人物AI在经济运行期间持续决策")
	test.expect(simulation.alpha_ai.decisions.size() <= 512, "AI决策历史保持有界")
	test.expect(simulation.commodity_market.history.size() <= 96, "市场历史保持有界")
	var economic_decisions: int = 0
	var successful_economic_decisions: int = 0
	for decision: Dictionary in simulation.alpha_ai.decisions:
		if str(decision.get("action_id", "")) in ECONOMIC_AI_ACTIONS:
			economic_decisions += 1
			if bool(decision.get("execution_success", false)):
				successful_economic_decisions += 1
	test.expect(economic_decisions > 0, "AI产生就业、信贷或企业类经济决策")
	test.expect(successful_economic_decisions > 0, "至少一项AI经济决策实际执行成功")
	var failure_events: int = 0
	for event: Dictionary in simulation.alpha_events:
		if str(event.get("fact_type", "")) == "commodity_market_failure":
			failure_events += 1
	test.equal(failure_events, 0, "三年运行没有商品市场日结失败")
	var state: Dictionary = simulation.get_alpha_persistent_state()
	var serialized_bytes: int = JSON.stringify(state).to_utf8_buffer().size()
	test.expect(serialized_bytes < 12_000_000, "三年存档状态小于12MB")
	test.expect(
		elapsed_usec < ABSOLUTE_SAFETY_CAP_USEC,
		"三年AI经济模拟未超过单次运行绝对安全上限"
	)
	test.expect(simulation.alpha_maximum_hour_usec < 1_000_000, "单小时结算未出现一秒级阻塞")
	var normalized_state_json: String = JSON.stringify(
		_normalized_state(state)
	)
	var restored := AlphaSimulationService.new()
	var restore_started_usec: int = Time.get_ticks_usec()
	var restore_initialized: bool = restored.initialize()
	var restore_result: V2LifeLoopResult = (
		restored.restore_alpha_state(state)
		if restore_initialized
		else V2LifeLoopResult.fail("initialize_failed", "")
	)
	var restored_state_json: String = ""
	if restore_result.success:
		restored_state_json = JSON.stringify(
			_normalized_state(restored.get_alpha_persistent_state())
		)
	var restore_usec: int = Time.get_ticks_usec() - restore_started_usec
	var state_equivalent: bool = (
		restore_result.success
		and normalized_state_json == restored_state_json
	)
	print("ALPHA_AI_ECONOMY_METRICS=%s" % JSON.stringify({
		"years": YEARS,
		"hours": HOURS,
		"random_seed": simulation.random.get_seed(),
		"initialize_usec": initialize_usec,
		"elapsed_usec": elapsed_usec,
		"performance_target_usec": PERFORMANCE_TARGET_USEC,
		"performance_target_met": elapsed_usec < PERFORMANCE_TARGET_USEC,
		"absolute_safety_cap_usec": ABSOLUTE_SAFETY_CAP_USEC,
		"average_hour_usec": float(elapsed_usec) / float(HOURS),
		"maximum_hour_usec": simulation.alpha_maximum_hour_usec,
		"ai_decisions_retained": simulation.alpha_ai.decisions.size(),
		"economic_ai_decisions_retained": economic_decisions,
		"successful_economic_ai_decisions_retained": successful_economic_decisions,
		"market_history_retained": simulation.commodity_market.history.size(),
		"save_state_bytes": serialized_bytes,
		"state_summary_sha256": normalized_state_json.sha256_text(),
		"restore_usec": restore_usec,
		"restore_success": restore_result.success,
		"restored_state_summary_sha256": restored_state_json.sha256_text(),
		"state_equivalent": state_equivalent,
		"process_total_usec": Time.get_ticks_usec() - process_started_usec,
		"world_summary": summary,
	}))
	test.finish(self, "Alpha AI economy stability")


func _normalized_state(value: Variant, key_name: String = "") -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value as Dictionary
			var normalized: Dictionary = {}
			for key: Variant in source:
				var normalized_key: String = str(key)
				if normalized_key == "alpha_maximum_hour_usec":
					continue
				normalized[normalized_key] = _normalized_state(
					source[key], normalized_key
				)
			return normalized
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value as Array:
				normalized_array.append(_normalized_state(item))
			if key_name == "processed_keys":
				normalized_array.sort()
			return normalized_array
		_:
			return value
