extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var historical := AlphaHistoricalWorldEconomyData.new()
	_check(
		historical.configure(),
		"历史经济数据可加载：%s" % historical.initialization_error
	)
	if failures == 0:
		_check(
			historical.simulation_countries().size() == 50,
			"50个主要政权进入高细节经济目录"
		)
		_check(
			historical.formal_countries().size()
			<= historical.simulation_countries().size(),
			"严格验证目录不宽于有界主要政权目录"
		)

	var economy := FormalWorldEconomyService.new()
	_check(
		economy.configure(),
		"正式世界经济可初始化：%s" % economy.initialization_error
	)
	if failures == 0:
		var initial := economy.world_summary()
		_check(
			int(initial.get("world_political_unit_count", 0)) == 151,
			"世界地图包含151个1900政治单元，而非只有50国"
		)
		_check(
			int(initial.get("major_economy_count", 0)) == 50,
			"50个主要政权使用高细节经济"
		)
		_check(
			int(initial.get("primary_playable_count", 0)) == 30,
			"前30个政权进入当前核心可玩层"
		)
		_check(
			int(initial.get("secondary_roster_count", 0)) == 20,
			"第31至50位保留为次要政权候选"
		)
		_check(
			int(initial.get("background_polity_count", 0)) == 101,
			"其余101个政治单元作为背景世界存在"
		)
		_check(
			not economy.country_states.has("country:loran_federation")
			and not economy.country_states.has("country:vesta_union"),
			"正式世界不包含两国八地区架空夹具"
		)
		var background := economy.polity_summary("cshapes_gw_31")
		_check(not background.is_empty(), "背景政治单元仍可在半球选择")
		_check(
			not bool(background.get("has_detailed_economy", true)),
			"背景政治单元不运行高细节经济"
		)
		_check(
			int(initial.get("commodity_count", 0)) >= 60,
			"正式经济直接读取完整商品目录"
		)
		_check(
			int(initial.get("route_count", 0)) >= 30,
			"正式经济使用历史稀疏航路"
		)
		var after := economy.advance_hours(90 * 24)
		_check(int(after.get("total_hour", 0)) == 90 * 24, "90日结算完成")
		_check(
			int(after.get("fulfillment_bp", -1)) >= 0,
			"主要政权长期需求满足率有效"
		)
		_check(
			_no_negative_inventory(economy.country_states),
			"所有高细节政权库存非负"
		)
		var saved := economy.get_persistent_state()
		var restored := FormalWorldEconomyService.new()
		_check(restored.configure(), "恢复目标可初始化")
		_check(restored.restore_persistent_state(saved), "正式经济存档可恢复")
		_check(
			restored.world_summary() == economy.world_summary(),
			"正式经济恢复后摘要等价"
		)

	var simulation := FormalWorldSimulation.new()
	_check(
		simulation.initialize(),
		"正式世界组合根可初始化：%s" % simulation.initialization_error
	)
	if failures == 0:
		simulation.advance_minutes(48 * 60)
		var state := simulation.get_persistent_state()
		var restored_simulation := FormalWorldSimulation.new()
		_check(restored_simulation.initialize(), "恢复组合根可初始化")
		_check(
			restored_simulation.restore_persistent_state(state),
			"正式世界组合根可恢复"
		)
		_check(
			restored_simulation.world_summary() == simulation.world_summary(),
			"组合根恢复后世界摘要等价"
		)

	_check(
		str(ProjectSettings.get_setting("application/run/main_scene", ""))
		== "res://scenes/formal/formal_world_menu.tscn",
		"产品默认入口已迁移到正式半球目录"
	)
	var menu_scene := load("res://scenes/formal/formal_world_menu.tscn") as PackedScene
	_check(menu_scene != null, "正式世界标题场景可加载")
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		_check(menu is FormalWorldMenu, "标题场景不再使用V2.3菜单类")
		menu.free()

	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "正式半球场景可加载")
	if scene != null:
		var instance := scene.instantiate()
		_check(
			instance is FormalWorldApplication,
			"正式场景使用FormalWorldApplication而非V2.3产品模拟"
		)
		get_root().add_child(instance)
		await process_frame
		await process_frame
		var application := instance as FormalWorldApplication
		_check(
			application.formal_simulation.initialized,
			"正式半球执行ready后初始化统一正式世界"
		)
		var runtime_summary := application.formal_simulation.world_summary()
		_check(
			int(runtime_summary.get("world_political_unit_count", 0)) == 151,
			"正式半球运行时持有完整政治世界"
		)
		_check(
			int(runtime_summary.get("major_economy_count", 0)) == 50,
			"正式半球运行时持有50个主要经济体"
		)
		_check(
			application.get_node_or_null("PrototypeMap") == null,
			"正式运行场景不再包含旧平面PrototypeMap"
		)
		_check(
			application.get_node_or_null(
				"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D"
			) != null,
			"正式运行场景以真实三维半球作为地图"
		)
		application.sim_paused = false
		application.sim_speed = 1
		var before_hour := application.formal_simulation.economy.total_hour
		for _tick: int in range(4):
			application._on_clock_timer_timeout()
		_check(
			application.formal_simulation.economy.total_hour >= before_hour + 1,
			"解除暂停后半球时钟与正式经济使用同一推进源"
		)
		application.economy_panel_open = false
		application._activate_button("formal_economy_toggle")
		_check(
			application.economy_panel_open,
			"正式半球政经面板可由正式交互打开"
		)
		application.queue_free()
		await process_frame

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
