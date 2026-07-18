extends SceneTree
## Segment settlement, location boundaries, cost and idempotency.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "旅行结算环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 travel execution")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var start_hour: int = simulation.clock.total_hours + 1
	var cash_before: int = int(
		simulation.households.household_for_person(person_id).get(
			"cash_centimes", 0
		)
	)
	var created: V2LifeLoopResult = simulation.travel_execution.create_plan(
		person_id, "location_lille_fives_factory", "fastest", start_hour,
		cash_before, 0
	)
	test.expect(created.success, "正式旅行计划可创建")
	var plan: Dictionary = created.data.get("travel_plan", {}) as Dictionary
	var segment: Dictionary = (plan.get("route_segments", []) as Array)[0] as Dictionary
	test.equal(
		str(simulation.spatial_locations.position_for(person_id).get(
			"current_location_id", ""
		)),
		"location_lille_pierre_home",
		"出发边界前仍在原地点"
	)
	var activity: Dictionary = {
		"activity_type": "travel_urban_transit",
		"travel_plan_id": plan.get("travel_plan_id", ""),
		"route_segment_index": 0,
		"route_segment_id": segment.get("route_segment_id", ""),
	}
	var settled: V2LifeLoopResult = simulation.travel_execution.settle_activity(
		person_id, activity, start_hour,
		simulation.households, simulation.ledger, simulation.conditions
	)
	test.expect(settled.success, "旅行小时按正式路段结算")
	var position: Dictionary = simulation.spatial_locations.position_for(person_id)
	test.equal(
		position.get("current_location_id"),
		"location_lille_fives_factory",
		"仅在路段到达边界更新实际地点"
	)
	test.equal(position.get("location_state"), "at_location", "最后路段完成后离开途中状态")
	test.equal(
		int(simulation.households.household_for_person(person_id).get(
			"cash_centimes", 0
		)),
		cash_before - 5,
		"付费路段在出发时扣费"
	)
	var transport_transactions: Array[Dictionary] = []
	for transaction: Dictionary in simulation.ledger.transactions:
		if str(transaction.get("category", "")) == "transport":
			transport_transactions.append(transaction)
	test.equal(transport_transactions.size(), 1, "交通票价只生成一条账本记录")
	var repeated: V2LifeLoopResult = simulation.travel_execution.settle_activity(
		person_id, activity, start_hour,
		simulation.households, simulation.ledger, simulation.conditions
	)
	test.expect(repeated.success, "重复结算调用保持幂等")
	test.equal(
		int(simulation.households.household_for_person(person_id).get(
			"cash_centimes", 0
		)),
		cash_before - 5,
		"重复结算不会再次扣款"
	)
	test.equal(
		str(simulation.travel_execution.travel_plans[
			str(plan.get("travel_plan_id", ""))
		].get("status", "")),
		"completed",
		"旅行计划进入终态"
	)
	test.finish(self, "V2.3 travel execution")
