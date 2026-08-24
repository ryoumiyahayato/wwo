extends SceneTree
## Ten-year balance guard for the actual 151-unit hemisphere world and its
## 50-polity high-detail economy. The two-country/eight-region fixture is not
## instantiated anywhere in this test.

const YEARS: int = 10
const HOURS_PER_YEAR: int = 365 * 24
const MIN_ANNUAL_FULFILLMENT_BP: int = 2000
const MIN_FINAL_FULFILLMENT_BP: int = 3000
const MAX_SAVE_BYTES: int = 20_000_000
const MAX_ELAPSED_USEC: int = 240_000_000

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(
		simulation.initialize(),
		"正式半球长期经济可通过唯一时间源初始化：%s" % simulation.initialization_error
	)
	if failures > 0:
		_finish({})
		return
	var economy := simulation.economy
	var started_usec := Time.get_ticks_usec()
	var annual_fulfillment: Array[int] = []
	for year: int in range(1, YEARS + 1):
		var summary := simulation.advance_minutes(HOURS_PER_YEAR * 60)
		var fulfillment := int(summary.get("fulfillment_bp", -1))
		annual_fulfillment.append(fulfillment)
		_check(
			fulfillment >= MIN_ANNUAL_FULFILLMENT_BP,
			"第%d年世界需求满足率不发生系统性崩溃" % year
		)
		_check(
			int(summary.get("world_political_unit_count", 0)) == 151,
			"第%d年完整政治世界仍存在" % year
		)
		_check(
			int(summary.get("major_economy_count", 0)) == 50,
			"第%d年主要政权高细节目录保持50个" % year
		)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	var final_summary := simulation.world_summary()
	_check(
		int(final_summary.get("fulfillment_bp", -1)) >= MIN_FINAL_FULFILLMENT_BP,
		"十年末世界需求满足率保持在30%以上"
	)
	_check(_state_is_numerically_sound(economy), "十年运行后价格、库存和日结状态有效")
	_check(economy.routes.size() >= 30, "正式历史运输网络持续可用")
	_check(economy.shipments.size() <= 5000, "在途运输队列保持有界")
	var save_state := simulation.get_persistent_state()
	var serialized_bytes := JSON.stringify(save_state).to_utf8_buffer().size()
	_check(serialized_bytes < MAX_SAVE_BYTES, "十年正式世界存档小于20MB")
	_check(elapsed_usec < MAX_ELAPSED_USEC, "十年正式世界模拟在CI安全时间内完成")
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "十年存档恢复目标可初始化")
	_check(restored.restore_persistent_state(save_state), "十年正式世界存档可恢复")
	_check(
		restored.world_summary() == final_summary,
		"十年存档恢复后世界摘要等价"
	)
	_finish({
		"years": YEARS,
		"elapsed_usec": elapsed_usec,
		"annual_fulfillment_bp": annual_fulfillment,
		"save_state_bytes": serialized_bytes,
		"active_shipments": economy.shipments.size(),
		"final_summary": final_summary,
	})


func _state_is_numerically_sound(economy: FormalWorldEconomyService) -> bool:
	for raw_state: Variant in economy.country_states.values():
		var state := raw_state as Dictionary
		if not state.get("inventory", {}) is Dictionary:
			return false
		if not state.get("prices", {}) is Dictionary:
			return false
		if not state.get("daily_totals", {}) is Dictionary:
			return false
		for raw_units: Variant in (state.get("inventory", {}) as Dictionary).values():
			var units := float(raw_units)
			if is_nan(units) or is_inf(units) or units < 0.0:
				return false
		for raw_price: Variant in (state.get("prices", {}) as Dictionary).values():
			var price := int(raw_price)
			if price <= 0 or price >= 2_000_000_000:
				return false
	return true


func _finish(metrics: Dictionary) -> void:
	print("FORMAL_WORLD_LONG_TERM_METRICS=%s" % JSON.stringify(metrics))
	print("Formal world long-term balance: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
