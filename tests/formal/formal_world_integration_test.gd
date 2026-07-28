extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	var historical := AlphaHistoricalWorldEconomyData.new()
	_check(historical.configure(), "历史经济数据可加载：%s" % historical.initialization_error)
	if failures == 0:
		_check(historical.simulation_countries().size() == 50, "50个历史政治实体进入有界模拟目录")
		_check(historical.formal_countries().size() <= historical.simulation_countries().size(), "严格验证目录不宽于有界目录")
	var economy := FormalWorldEconomyService.new()
	_check(economy.configure(), "正式世界经济可初始化：%s" % economy.initialization_error)
	if failures == 0:
		var initial := economy.world_summary()
		_check(int(initial.get("country_count", 0)) == 50, "正式经济包含50国")
		_check(int(initial.get("commodity_count", 0)) >= 60, "正式经济复用完整商品目录")
		_check(int(initial.get("route_count", 0)) >= 30, "正式经济使用历史稀疏航路")
		var after := economy.advance_hours(90 * 24)
		_check(int(after.get("total_hour", 0)) == 90 * 24, "90日结算完成")
		_check(int(after.get("fulfillment_bp", -1)) >= 0, "世界需求满足率有效")
		_check(_no_negative_inventory(economy.country_states), "所有国家库存非负")
		var saved := economy.get_persistent_state()
		var restored := FormalWorldEconomyService.new()
		_check(restored.configure(), "恢复目标可初始化")
		_check(restored.restore_persistent_state(saved), "正式经济存档可恢复")
		_check(restored.world_summary() == economy.world_summary(), "正式经济恢复后摘要等价")
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "正式世界组合根可初始化：%s" % simulation.initialization_error)
	if failures == 0:
		simulation.advance_minutes(48 * 60)
		var state := simulation.get_persistent_state()
		var restored_simulation := FormalWorldSimulation.new()
		_check(restored_simulation.initialize(), "恢复组合根可初始化")
		_check(restored_simulation.restore_persistent_state(state), "正式世界组合根可恢复")
		_check(restored_simulation.world_summary() == simulation.world_summary(), "组合根恢复后经济摘要等价")
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "正式半球场景可加载")
	if scene != null:
		var instance := scene.instantiate()
		_check(instance is FormalWorldApplication, "正式场景使用FormalWorldApplication而非V23产品模拟")
		instance.free()
	print("Formal world integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _no_negative_inventory(states: Dictionary) -> bool:
	for raw_state: Variant in states.values():
		var state := raw_state as Dictionary
		for value: Variant in (state.get("inventory", {}) as Dictionary).values():
			if float(value) < 0.0:
				return false
	return true


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
