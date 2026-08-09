extends SceneTree

var checks: int = 0
var failures: int = 0
var map: VNextMilitaryMapAdapter
var service := VNextMilitaryService.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	map = VNextMilitaryMapAdapter.new()
	_check(map.load_existing_map(), "军事适配器加载现有世界地图与军事语义 overlay")
	if map != null and map.errors.is_empty():
		_test_map_queries_and_transport()
		_test_timed_movement_and_no_teleport()
		_test_deploy_and_concentrate()
		_test_supply_network_and_cut_route()
		_test_attack_and_defense_results()
		_test_multi_month_stability_and_snapshot()
	_test_does_not_touch_runtime()
	print("VNext military strategic system: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_map_queries_and_transport() -> void:
	_check(map.get_city_ids().size() == 32, "适配器复用现有 32 个城市记录")
	_check(map.get_all_links().size() == 15, "适配器复用现有道路、铁路和航运链接")
	_equal(map.get_region_id_for_city("paris"), "paris_basin", "巴黎使用既有宏观地区 ID")
	_equal(map.get_region_id_for_city("berlin"), "german_empire", "没有宏观地区的城市使用既有国家 ID 作为战略 fallback 区")
	var paris_view: Dictionary = map.get_region_report("paris_basin")
	_check(not paris_view.is_empty(), "地区查询返回巴黎盆地军事视图")
	_check(str(paris_view.get("terrain_id", "")) == "urban", "地区查询返回地形")
	_check((paris_view.get("city_ids", []) as Array).has("paris"), "地区查询返回城市")
	_check(not (paris_view.get("rail_link_ids", []) as Array).is_empty(), "地区查询返回铁路连接")
	_check((paris_view.get("resources", []) as Array).has("capital"), "地区查询返回关键资源语义")
	_equal(paris_view.get("controller_country_id"), "country_fra", "地区视图返回初始控制方")
	_check(float(paris_view.get("strategic_value", 0.0)) > 0.9, "首都地区具有高战略价值")
	var road_modes: Array[String] = ["road"]
	var rail_modes: Array[String] = ["rail"]
	var road_route: Dictionary = map.find_route("paris", "rouen", road_modes)
	var rail_route: Dictionary = map.find_route("paris", "rouen", rail_modes)
	_check(bool(road_route.get("reachable", false)), "巴黎到鲁昂道路路线可达")
	_check(bool(rail_route.get("reachable", false)), "巴黎到鲁昂铁路路线可达")
	_check(int(rail_route.get("duration_hours", 0)) < int(road_route.get("duration_hours", 0)), "铁路实际比道路更快")
	_check(float(rail_route.get("supply_capacity_per_day", 0.0)) > float(road_route.get("supply_capacity_per_day", 0.0)), "铁路实际拥有更高补给运输能力")
	var london_route: Dictionary = map.find_route("paris", "london")
	_check(bool(london_route.get("reachable", false)), "巴黎到伦敦可通过铁路加港口航线到达")
	_check((london_route.get("mode_sequence", []) as Array).has("shipping"), "跨海路线实际使用港口航运")
	var berlin_route: Dictionary = map.find_route("paris", "berlin")
	_check(not bool(berlin_route.get("reachable", false)), "没有现有交通连接时巴黎不能瞬移到柏林")
	var plains: Dictionary = map.get_region_terrain("northern_industrial_belt")
	var urban: Dictionary = map.get_region_terrain("paris_basin")
	_check(float(urban.get("defense_factor", 0.0)) > float(plains.get("defense_factor", 0.0)), "城市地形提高防御因素")
	var paris_lyon_rail: Dictionary = map.find_route("paris", "lyon", rail_modes)
	_check(float(paris_lyon_rail.get("duration_hours", 0.0)) > 0.0, "铁路路线时间由地理距离和目标地形计算")


func _test_timed_movement_and_no_teleport() -> void:
	var state := _new_state()
	if state == null:
		return
	_check(service.create_formation(
		state,
		map,
		"formation:france_rail",
		"country_fra",
		"paris",
		12000,
		{"equipment_factor": 0.95, "artillery": 0.6},
		0.8,
		0.82,
		0.78
	), "创建战略编制并记录兵力、装备、组织与士气")
	var move_result: Dictionary = service.move(state, map, "formation:france_rail", "lyon", 0)
	_check(bool(move_result.get("success", false)), "移动行动成功排入时间线")
	var action_id: String = str(move_result.get("action_id", ""))
	var eta_hour: int = int(move_result.get("eta_hour", 0))
	_check(eta_hour > 1, "巴黎到里昂移动需要实际时间")
	_equal(state.get_formation("formation:france_rail").current_city_id, "paris", "移动开始后部队仍在起点而非瞬移")
	_check(state.get_formation("formation:france_rail").action_state == VNextMilitaryFormation.ACTION_MOVING, "移动中部队行动状态为 moving")
	_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "推进一小时成功")
	_equal(state.get_formation("formation:france_rail").current_city_id, "paris", "未到达 ETA 前当前位置不变")
	_check(float(service.get_action(state, action_id).get("progress", 0.0)) > 0.0, "未完成移动报告真实进度")
	_check(bool(service.advance_to_hour(state, map, eta_hour).get("success", false)), "推进到 ETA 完成移动")
	_equal(state.get_formation("formation:france_rail").current_city_id, "lyon", "到达 ETA 后部队进入目标城市")
	_equal(state.get_formation("formation:france_rail").action_state, VNextMilitaryFormation.ACTION_IDLE, "移动完成后行动状态恢复 idle")
	_check(not bool(service.move(state, map, "formation:france_rail", "berlin", eta_hour).get("success", false)), "无路线的移动被拒绝")
	_check(not bool(service.advance_to_hour(state, map, eta_hour - 1).get("success", false)), "军事时间不能倒退")
	var view: Dictionary = service.get_formation_view(state, map, "formation:france_rail")
	_check(view.get("personnel", 0) is int and int(view.get("personnel", 0)) > 0, "编制视图返回非负兵力")
	_check(view.has("supply_status") and view.has("current_city_id"), "编制视图返回补给与位置状态")


func _test_deploy_and_concentrate() -> void:
	var state := _new_state()
	if state == null:
		return
	_check(service.create_formation(state, map, "formation:deploy", "country_fra", "paris", 5000), "创建部署编制")
	var deploy_result: Dictionary = service.deploy(state, map, "formation:deploy", "rouen", 0)
	_check(bool(deploy_result.get("success", false)), "部署行动成功排入时间线")
	var deploy_eta: int = int(deploy_result.get("eta_hour", 0))
	_check(deploy_eta > 0, "部署行动消耗实际时间")
	_check(bool(service.advance_to_hour(state, map, deploy_eta).get("success", false)), "部署行动按 ETA 完成")
	_equal(state.get_formation("formation:deploy").current_city_id, "rouen", "部署行动将编制送达目标城市")
	_check(service.create_formation(state, map, "formation:concentrate_paris", "country_fra", "paris", 4000), "创建集中行动巴黎编制")
	_check(service.create_formation(state, map, "formation:concentrate_rouen", "country_fra", "rouen", 4000), "创建集中行动鲁昂编制")
	var concentration_ids: Array[String] = ["formation:concentrate_paris", "formation:concentrate_rouen"]
	var concentration: Dictionary = service.concentrate(
		state,
		map,
		concentration_ids,
		"lyon",
		state.last_simulated_hour
	)
	_check(bool(concentration.get("success", false)), "集中行动可以同时排入多个战略编制")
	var concentration_action_ids: Array = concentration.get("action_ids", []) as Array
	_check(concentration_action_ids.size() == 2, "集中行动为每个编制建立独立行动 ID")
	var concentration_eta: int = state.last_simulated_hour
	for raw_action_id: Variant in concentration_action_ids:
		concentration_eta = maxi(concentration_eta, int(service.get_action(state, str(raw_action_id)).get("eta_hour", 0)))
	_check(bool(service.advance_to_hour(state, map, concentration_eta).get("success", false)), "集中行动按最长 ETA 完成")
	_equal(state.get_formation("formation:concentrate_paris").current_city_id, "lyon", "集中行动送达巴黎编制")
	_equal(state.get_formation("formation:concentrate_rouen").current_city_id, "lyon", "集中行动送达鲁昂编制")


func _test_supply_network_and_cut_route() -> void:
	var state := _new_state()
	if state == null:
		return
	_check(service.create_formation(
		state,
		map,
		"formation:france_mediterranean",
		"country_fra",
		"marseille",
		2400,
		{"equipment_factor": 0.9},
		0.75,
		0.8,
		0.8
	), "创建地中海战略编制")
	_check(service.set_supply_input(state, map, "paris_basin", {
		"food": 5000.0,
		"ammunition": 700.0,
		"equipment": 150.0,
		"transport_capacity": 500.0,
	}), "接受固定资源输入而不生产经济资源")
	var open_supply_route: Dictionary = map.find_route(
		"paris",
		"marseille",
		[],
		"country_fra",
		state.region_controls,
		false
	)
	_check(bool(open_supply_route.get("reachable", false)), "主要补给路线在控制连续时可达")
	_check(float(map.get_route_capacity_per_day(open_supply_route)) > 0.0, "补给路线具有有限运输容量")
	var before_advance: Dictionary = service.advance_to_hour(state, map, 24)
	_check(bool(before_advance.get("success", false)), "供应正常时按日结算补给")
	var formation: VNextMilitaryFormation = state.get_formation("formation:france_mediterranean")
	var supplied_organization: float = formation.organization
	var supplied_morale: float = formation.morale
	var supplied_personnel: int = formation.personnel
	_check(formation.supply_level >= 0.95, "铁路补给在容量范围内达到完整供应")
	_equal(formation.supply_status, "full", "完整供应具有明确状态")
	_check((before_advance.get("supply", {}) as Dictionary).has(formation.formation_id), "补给结算返回需求与交付明细")
	_check(service.set_region_controller(state, map, "rhone_valley", "country_bel", "测试切断主铁路走廊"), "控制权变化可以切断中间区域")
	var blocked_supply_route: Dictionary = map.find_route(
		"paris",
		"marseille",
		[],
		"country_fra",
		state.region_controls,
		false
	)
	_check(not bool(blocked_supply_route.get("reachable", false)), "敌方控制中间区域后补给路线不可达")
	var after_break: Dictionary = service.advance_to_hour(state, map, 48)
	_check(bool(after_break.get("success", false)), "断补给后仍按时间推进")
	_check(formation.supply_level < 0.4, "断补给真正降低补给水平")
	_equal(formation.supply_status, "cut", "断补给具有 cut 状态")
	_check(formation.organization < supplied_organization, "断补给真实降低组织")
	_check(formation.morale < supplied_morale, "断补给真实降低士气")
	_check(formation.personnel < supplied_personnel, "长期断补给真实产生人员损耗")
	_check(formation.personnel >= 0, "补给损耗不会产生负兵力")
	var mediterranean_view: Dictionary = service.get_region_view(state, map, "mediterranean_coast")
	_equal(mediterranean_view.get("controller_country_id"), "country_fra", "断补给不错误改变目标区控制权")
	_check((mediterranean_view.get("transport_link_ids", []) as Array).size() > 0, "地区视图保留既有交通链接")


func _test_attack_and_defense_results() -> void:
	var assault_state := _new_state()
	if assault_state == null:
		return
	_check(service.set_region_controller(assault_state, map, "northern_industrial_belt", "country_bel", "建立可测试敌方控制区"), "设置敌方控制区用于战略战斗")
	_check(service.create_formation(
		assault_state,
		map,
		"formation:france_assault",
		"country_fra",
		"paris",
		20000,
		{"equipment_factor": 1.0, "artillery": 0.8},
		0.95,
		0.95,
		0.95
	), "创建高准备攻击编制")
	_check(service.create_formation(
		assault_state,
		map,
		"formation:belgium_defense",
		"country_bel",
		"lille",
		4000,
		{"equipment_factor": 0.75},
		0.55,
		0.55,
		0.55
	), "创建防守编制")
	_check(service.set_supply_input(assault_state, map, "paris_basin", {
		"food": 20000.0,
		"ammunition": 4000.0,
		"equipment": 500.0,
		"transport_capacity": 2500.0,
	}), "为攻击方提供固定粮食弹药装备与运输输入")
	_check(service.set_supply_input(assault_state, map, "northern_industrial_belt", {
		"food": 10000.0,
		"ammunition": 1500.0,
		"equipment": 250.0,
		"transport_capacity": 1200.0,
	}), "为防守方提供独立固定补给输入")
	var defense_order: Dictionary = service.defend(assault_state, map, "formation:belgium_defense", 0, 72)
	_check(bool(defense_order.get("success", false)), "防守编制可以建立防御姿态")
	var prepared_supply := service.advance_to_hour(assault_state, map, 24)
	_check(bool(prepared_supply.get("success", false)), "战斗前补给按时间结算")
	var preview: Dictionary = service.preview_battle(assault_state, map, "formation:france_assault", "lille")
	_check(float(preview.get("attacker_power", 0.0)) > 0.0 and float(preview.get("defender_power", 0.0)) > 0.0, "战斗预览同时计算攻击与防守力量")
	_check(float(preview.get("defender_posture_multiplier", 1.0)) > 1.0, "防御姿态实际进入战斗预览")
	_check((preview.get("factors", []) as Array).has("地形") and (preview.get("factors", []) as Array).has("补给"), "战斗预览列出地形与补给因素")
	var attack_order: Dictionary = service.attack(assault_state, map, "formation:france_assault", "lille", 24)
	_check(bool(attack_order.get("success", false)), "进攻行动成功排入时间线")
	_equal(attack_order.get("war_status"), "active", "进攻向 Integration 暴露战争进行状态")
	var attack_eta: int = int(attack_order.get("eta_hour", 0))
	_check(attack_eta > 24, "进攻包含移动与准备时间")
	_check(bool(service.advance_to_hour(assault_state, map, attack_eta - 1).get("success", false)), "战斗 ETA 前仍可推进")
	_equal(assault_state.region_controls.get("northern_industrial_belt"), "country_bel", "战斗完成前区域控制权不变")
	var battle_tick: Dictionary = service.advance_to_hour(assault_state, map, attack_eta)
	var battles: Array = battle_tick.get("battles", []) as Array
	_check(battles.size() == 1, "到达进攻 ETA 后只结算一次战斗")
	if battles.size() == 1:
		var battle: Dictionary = battles[0] as Dictionary
		_equal(battle.get("outcome"), "attacker_win", "高兵力高准备攻击得到可重复胜利")
		_check(bool(battle.get("control_changed", false)), "胜利战斗改变军事区域控制权")
		_equal(assault_state.region_controls.get("northern_industrial_belt"), "country_fra", "胜利后军事查询显示法国控制")
		_check(int(battle.get("attacker_losses", 0)) > 0 and int(battle.get("defender_losses", 0)) > 0, "战斗产生双方可解释损耗")
		_equal(battle.get("war_status"), "resolved", "战斗结果向 Integration 暴露战争结算状态")
		var casualties: Dictionary = battle.get("casualties", {}) as Dictionary
		_check(int(casualties.get("attacker", -1)) == int(battle.get("attacker_losses", -2)) and int(casualties.get("defender", -1)) == int(battle.get("defender_losses", -2)), "战斗结果提供双方伤亡接口")
		_check(is_finite(float(battle.get("mobilization_pressure", -1.0))) and float(battle.get("mobilization_pressure", -1.0)) >= 0.0 and float(battle.get("mobilization_pressure", -1.0)) <= 1.0, "战斗结果提供有界动员压力")
		_check((battle.get("factors", {}) as Dictionary).has("terrain_defense_factor"), "战斗结果记录地形防御因素")
	_check(assault_state.get_formation("formation:france_assault").personnel >= 0, "胜利后攻击编制兵力仍非负")

	var hold_state := _new_state()
	if hold_state == null:
		return
	_check(service.set_region_controller(hold_state, map, "northern_industrial_belt", "country_bel", "建立防守测试区"), "建立防守结果测试区")
	_check(service.create_formation(hold_state, map, "formation:weak_assault", "country_fra", "paris", 3500, {"equipment_factor": 0.65}, 0.45, 0.45, 0.45), "创建较弱攻击编制")
	_check(service.create_formation(hold_state, map, "formation:strong_defense", "country_bel", "lille", 12000, {"equipment_factor": 1.0}, 0.9, 0.9, 0.9), "创建较强防守编制")
	_check(service.set_supply_input(hold_state, map, "paris_basin", {"food": 5000.0, "ammunition": 700.0, "equipment": 120.0, "transport_capacity": 500.0}), "提供弱攻击方固定输入")
	_check(service.set_supply_input(hold_state, map, "northern_industrial_belt", {"food": 12000.0, "ammunition": 2000.0, "equipment": 300.0, "transport_capacity": 1600.0}), "提供强防守方固定输入")
	_check(bool(service.defend(hold_state, map, "formation:strong_defense", 0, 96).get("success", false)), "强防守编制建立防御姿态")
	_check(bool(service.advance_to_hour(hold_state, map, 24).get("success", false)), "防守测试推进到准备完成")
	var hold_attack: Dictionary = service.attack(hold_state, map, "formation:weak_assault", "lille", 24)
	_check(bool(hold_attack.get("success", false)), "较弱攻击仍按战略规则开始行动")
	var hold_eta: int = int(hold_attack.get("eta_hour", 0))
	var hold_tick: Dictionary = service.advance_to_hour(hold_state, map, hold_eta)
	var hold_battles: Array = hold_tick.get("battles", []) as Array
	_check(hold_battles.size() == 1, "防守测试结算一次战斗")
	if hold_battles.size() == 1:
		var hold_battle: Dictionary = hold_battles[0] as Dictionary
		_check(str(hold_battle.get("outcome", "")) in ["defender_hold", "stalemate"], "兵力与防御姿态足以守住目标")
		_equal(hold_state.region_controls.get("northern_industrial_belt"), "country_bel", "防守成功或胶着不会错误占领区域")


func _test_multi_month_stability_and_snapshot() -> void:
	var state := _new_state()
	if state == null:
		return
	_check(service.create_formation(state, map, "formation:long_war", "country_fra", "marseille", 2500, {"equipment_factor": 0.9}, 0.7, 0.75, 0.75), "创建多月战争编制")
	_check(service.set_supply_input(state, map, "paris_basin", {"food": 5000.0, "ammunition": 700.0, "equipment": 150.0, "transport_capacity": 500.0}), "为多月战争提供固定输入")
	var full_run_success: bool = true
	for day: int in range(1, 181):
		var result: Dictionary = service.advance_to_hour(state, map, day * 24)
		if not bool(result.get("success", false)):
			full_run_success = false
			break
	_check(full_run_success, "多月战争 180 日按日推进")
	var formation: VNextMilitaryFormation = state.get_formation("formation:long_war")
	_check(state.last_simulated_hour == 180 * 24, "多月战争使用单调军事时间边界")
	_check(formation.personnel > 0, "完整补给下多月战争不会凭空消灭部队")
	_check(formation.supply_level >= 0.95, "完整补给下多月战争保持供应")
	_check(is_finite(formation.morale) and is_finite(formation.organization) and is_finite(formation.supply_level), "多月战争没有 NaN 或无限状态")
	_check(service.set_region_controller(state, map, "rhone_valley", "country_bel", "长期战争断补给测试"), "多月战争可以改变中间区域控制")
	var cut_run_success: bool = true
	for day: int in range(181, 241):
		var result: Dictionary = service.advance_to_hour(state, map, day * 24)
		if not bool(result.get("success", false)):
			cut_run_success = false
			break
	_check(cut_run_success, "断补给战争 60 日按日推进")
	_check(formation.supply_level < 0.4, "断补给多月运行后补给确实恶化")
	_check(formation.personnel >= 0, "断补给多月运行后兵力不为负")
	_check(formation.morale >= 0.0 and formation.organization >= 0.0 and formation.equipment_factor() >= 0.0, "断补给多月运行后所有战斗状态仍有界")
	var saved: Dictionary = state.snapshot()
	var restored := VNextMilitaryState.new()
	_check(restored.restore(saved, map), "军事动态状态可以恢复并验证地图引用")
	var invalid_snapshot: Dictionary = saved.duplicate(true)
	var invalid_garrisons: Dictionary = invalid_snapshot["region_garrisons"] as Dictionary
	invalid_garrisons["paris_basin"] = -1
	var invalid_restored := VNextMilitaryState.new()
	_check(not invalid_restored.restore(invalid_snapshot, map), "无效驻军快照被拒绝")
	_equal(restored.snapshot(), saved, "军事状态快照往返保持行动、控制、补给与战斗数据")


func _test_does_not_touch_runtime() -> void:
	var runtime_source: String = FileAccess.get_file_as_string("res://scripts/vnext/world_runtime.gd")
	_check(not runtime_source.contains("VNextMilitary"), "军事系统没有接入 world_runtime.gd")
	var adapter_source: String = FileAccess.get_file_as_string("res://scripts/vnext/map/military_map_adapter.gd")
	_check(adapter_source.contains("PrototypeV2Data"), "军事地图明确复用既有地图数据入口")
	_check(adapter_source.contains("strategic_military_overlay.json"), "军事补充数据是稳定 ID overlay 而非第二世界地图")


func _new_state() -> VNextMilitaryState:
	var state := VNextMilitaryState.new()
	_check(state.initialize(map), "军事状态使用地图控制与驻军初始化")
	_check(state.is_valid(map), "初始化军事状态通过一致性检查")
	return state


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
