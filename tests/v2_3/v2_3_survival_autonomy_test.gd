extends SceneTree
## The player and formal NPCs use the same bounded household-maintenance policy.
## The test does not bypass the schedule, travel, inventory or ledger services.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "生活自理测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 survival autonomy")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var household_id: String = simulation.households.household_id_for_person(person_id)
	var household: Dictionary = simulation.households.households[household_id] as Dictionary
	household["food_stock_person_days"] = 2
	household["essentials_stock_person_days"] = 12
	simulation.households.households[household_id] = household
	var planned: Dictionary = simulation.survival_autonomy.process_hour(
		_next_hour_of_day(simulation.clock.total_hours, 6)
	)
	test.equal(int(planned.get("planned", 0)), 1, "食品接近警戒线时主动生成一次采购计划")
	var maintenance: Dictionary = simulation.survival_autonomy.maintenance_view(person_id)
	var active_need: Dictionary = maintenance.get("active_need", {}) as Dictionary
	test.equal(str(active_need.get("item_type", "")), "food", "主动计划对应真实食品需要")
	test.expect(
		simulation.schedule.has_pending_activity(person_id, "purchase_food", simulation.clock.total_hours),
		"采购通过唯一权威日程安排"
	)
	var plan: Dictionary = simulation.travel_execution.active_plan_for_person(person_id)
	test.expect(not plan.is_empty(), "不在市场时通过正式旅行服务建立采购行程")
	var travel_plan_id: String = str(plan.get("travel_plan_id", ""))
	var initial_cash: int = int(household.get("cash_centimes", 0))
	var purchase_hour: int = int(active_need.get("start_hour", simulation.clock.total_hours + 1))
	simulation.advance_hours(maxi(
		1,
		purchase_hour + 1 - simulation.clock.total_hours
	))
	var after_household: Dictionary = simulation.households.households[household_id] as Dictionary
	var stock_replenished: bool = int(after_household.get("food_stock_person_days", 0)) > 2
	var settlement_debug: Dictionary = {
		"clock_hour": simulation.clock.total_hours,
		"purchase_hour": purchase_hour,
		"household": after_household.duplicate(true),
		"position": simulation.spatial_locations.position_for(person_id),
		"travel_plan": (simulation.travel_execution.travel_plans.get(travel_plan_id, {}) as Dictionary).duplicate(true),
		"schedule": (simulation.schedule.schedules.get(person_id, []) as Array).duplicate(true),
		"recent_completed": simulation.schedule.recent_completed_activities.duplicate(true),
	}
	test.expect(
		stock_replenished,
		"实际到场和购买后食品库存得到补充：%s" % JSON.stringify(settlement_debug)
	)
	test.expect(int(after_household.get("cash_centimes", 0)) < initial_cash, "采购费用只通过住户账本扣除")
	test.expect(simulation.ledger.validate_balances(simulation.households.households).success, "自主采购后账本链保持一致")

	var reserve_sim := V23ProductSimulationV2.new()
	test.expect(reserve_sim.initialize(), "现金保留策略环境初始化")
	var reserve_household_id: String = reserve_sim.households.household_id_for_person(person_id)
	var reserve_household: Dictionary = reserve_sim.households.households[reserve_household_id] as Dictionary
	reserve_household["food_stock_person_days"] = 12
	reserve_household["essentials_stock_person_days"] = 4
	reserve_household["cash_centimes"] = 839
	reserve_sim.households.households[reserve_household_id] = reserve_household
	var reserve_result: Dictionary = reserve_sim.survival_autonomy.process_hour(
		_next_hour_of_day(reserve_sim.clock.total_hours, 6)
	)
	test.equal(int(reserve_result.get("blocked", 0)), 1, "非紧急采购不会耗尽人物预留生活资金")
	test.expect(
		not reserve_sim.schedule.has_pending_activity(person_id, "purchase_essentials", reserve_sim.clock.total_hours),
		"预留资金不足时不伪造采购活动"
	)
	reserve_household = reserve_sim.households.households[reserve_household_id] as Dictionary
	reserve_household["food_stock_person_days"] = 0
	reserve_household["essentials_stock_person_days"] = 12
	reserve_sim.households.households[reserve_household_id] = reserve_household
	reserve_sim.survival_autonomy.next_retry_hours["%s|food" % person_id] = reserve_sim.clock.total_hours
	var emergency_result: Dictionary = reserve_sim.survival_autonomy.process_hour(
		_next_hour_of_day(reserve_sim.clock.total_hours, 6)
	)
	test.equal(int(emergency_result.get("planned", 0)), 1, "食品耗尽时可以动用预留资金安排紧急采购")

	var override_sim := V23ProductSimulationV2.new()
	test.expect(override_sim.initialize(), "玩家覆盖策略环境初始化")
	var override_household_id: String = override_sim.households.household_id_for_person(person_id)
	var override_household: Dictionary = override_sim.households.households[override_household_id] as Dictionary
	override_household["food_stock_person_days"] = 0
	override_sim.households.households[override_household_id] = override_household
	override_sim.manual_location_holds[person_id] = {
		"location_id": "location_lille_pierre_home",
		"set_hour": override_sim.clock.total_hours,
		"source": "player",
	}
	var override_result: Dictionary = override_sim.survival_autonomy.process_hour(
		_next_hour_of_day(override_sim.clock.total_hours, 6)
	)
	test.equal(int(override_result.get("blocked", 0)), 1, "玩家明确位置指令覆盖自动采购移动")
	test.expect(
		not override_sim.schedule.has_pending_activity(person_id, "purchase_food", override_sim.clock.total_hours),
		"玩家覆盖时AI不偷偷写入采购日程"
	)
	var blocked_need: Dictionary = override_sim.survival_autonomy.maintenance_view(person_id).get("active_need", {}) as Dictionary
	test.equal(str(blocked_need.get("status", "")), "retry_next_day", "采购失败后保留次日重试状态")

	var snapshot: Dictionary = simulation.get_persistent_state()
	test.expect(simulation.survival_autonomy.validate_persistent_state(snapshot.get("survival_autonomy_state", {}) as Dictionary), "生活自理状态可保存")
	var restored := V23ProductSimulationV2.new()
	test.expect(restored.initialize(), "生活自理恢复目标初始化")
	test.expect(restored.restore_v2_3_state(snapshot).success, "生活自理状态随正式存档恢复")
	test.equal(
		JSON.stringify(restored.survival_autonomy.get_persistent_state()),
		JSON.stringify(simulation.survival_autonomy.get_persistent_state()),
		"重试、采购需要和决策历史往返保持"
	)
	test.finish(self, "V2.3 survival autonomy")


static func _next_hour_of_day(current_hour: int, target_hour: int) -> int:
	var value: Dictionary = V2DateTime.from_total_hour(current_hour)
	var delta: int = target_hour - int(value.get("hour", 0))
	if delta < 0:
		delta += 24
	return current_hour + delta
