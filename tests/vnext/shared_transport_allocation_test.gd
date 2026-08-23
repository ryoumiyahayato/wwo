extends SceneTree

const EPSILON: float = 0.000001

var checks: int = 0
var failures: int = 0
var determinism_digest: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_lifecycle_and_detached_request_freeze()
	_test_route_freeze_precedes_capacity_changes()
	_test_failure_atomicity()
	_test_fairness_a_one_bottleneck()
	_test_fairness_b_shared_first_edge()
	_test_fairness_c_shared_final_edge()
	_test_fairness_d_different_weights()
	_test_fairness_e_independent_bottlenecks()
	_test_fairness_f_priority_then_weight()
	_test_nested_multi_edge_conservation()
	_test_strict_external_priority_and_no_id_leakage()
	_test_time_window_is_eligibility_not_reservation()
	_test_disruption_and_restoration()
	_test_routing_semantics_and_pareto_constraints()
	_test_determinism_under_all_input_reorders()
	_test_causal_observability()
	_test_result_observer_isolation()
	_test_domain_neutral_competition_and_money_inertness()
	_test_public_api_bypass_prevention()
	_test_adversarial_conservation_and_finiteness()
	_test_performance_profile()
	_finish()


func _test_lifecycle_and_detached_request_freeze() -> void:
	var source_edge := _edge("e_ab", "A", "B", 100.0)
	var accepted_route: Array[String] = ["e_ab"]
	var constraints: Dictionary = {"allowed_modes": ["rail"]}
	var request := _request(
		"immutable_request", "grain", "A", "B", 40.0, 3, 2.0,
		accepted_route, constraints, 8, 12
	)
	var allocator := _allocator([source_edge])
	_check(allocator.phase() == VNextSpatialTransportAllocator.PHASE_COLLECTING,
		"LIFECYCLE starts in COLLECTING")
	_check(allocator.submit_request(request), "LIFECYCLE collects request")
	_check(allocator.allocate() == null, "LIFECYCLE cannot allocate while collecting")
	_check(allocator.freeze_request_set(), "LIFECYCLE freezes request semantics")
	_check(allocator.phase() == VNextSpatialTransportAllocator.PHASE_REQUESTS_FROZEN,
		"LIFECYCLE exposes REQUESTS_FROZEN boundary")

	# Every consumer-owned reference is changed after request freeze.
	accepted_route[0] = "missing"
	(constraints["allowed_modes"] as Array)[0] = "road"
	request._request_id = "mutated_id"
	request._quantity = 999.0
	request._priority_class = 99
	request._weight = 99.0
	request._earliest_time = 99
	request._latest_time = 100
	request._accepted_route = ["missing"]
	request._route_constraints = {"allowed_modes": ["road"]}
	source_edge._capacity_per_period = 1.0

	_check(allocator.allocate() == null,
		"LIFECYCLE request freeze alone cannot mutate capacity")
	_check(allocator.freeze_routes(10), "LIFECYCLE freezes route candidates")
	_check(allocator.phase() == VNextSpatialTransportAllocator.PHASE_ROUTES_FROZEN,
		"LIFECYCLE exposes ROUTES_FROZEN boundary")
	_equal(
		allocator.frozen_route("immutable_request").get("edge_ids", []),
		["e_ab"],
		"IMMUTABILITY route uses detached request snapshot"
	)
	var result := allocator.allocate()
	_check(result != null and result.is_valid(), "LIFECYCLE publishes only a valid frozen result")
	if result == null:
		return
	_equal(result.allocation_for("immutable_request"), 40.0,
		"IMMUTABILITY late quantity/priority/weight/time mutation is inert")
	_equal(result.edge_capacity("e_ab"), 100.0,
		"IMMUTABILITY consumer-owned edge mutation is inert")
	_check(allocator.phase() == VNextSpatialTransportAllocator.PHASE_ALLOCATED,
		"LIFECYCLE ends in ALLOCATED")
	_check(not allocator.submit_request(_request(
		"late", "grain", "A", "B", 1.0, 0, 1.0, ["e_ab"]
	)), "LIFECYCLE rejects late submission")


func _test_route_freeze_precedes_capacity_changes() -> void:
	var edges: Array = [
		_edge("e_main", "A", "B", 60.0, "rail", true, 1.0, false, 1.0, 1.0),
		_edge("e_backup_1", "A", "C", 100.0, "road", true, 1.0, false, 3.0, 3.0),
		_edge("e_backup_2", "C", "B", 100.0, "road", true, 1.0, false, 3.0, 3.0),
	]
	var allocator := _allocator(edges)
	_check(allocator.submit_requests([
		_request("request_a", "coal", "A", "B", 60.0, 1, 1.0),
		_request("request_b", "grain", "A", "B", 60.0, 1, 1.0),
	]), "ROUTE FREEZE collects all auto-routed demand")
	_check(allocator.freeze_request_set(), "ROUTE FREEZE freezes complete request set")
	_check(allocator.freeze_routes(0), "ROUTE FREEZE selects all candidates before allocation")
	_equal(allocator.route_candidate_count(), 2,
		"ROUTE FREEZE v1 records exactly one selected candidate per routable request")
	_equal(allocator.frozen_route("request_a").get("edge_ids", []), ["e_main"],
		"ROUTE FREEZE request A selects physical best route")
	_equal(allocator.frozen_route("request_b").get("edge_ids", []), ["e_main"],
		"ROUTE FREEZE request B cannot observe A's future residual capacity")

	var exposed_copy: VNextSharedTransportEdge = allocator.edge("e_main")
	exposed_copy._capacity_per_period = 0.0
	var result := allocator.allocate()
	if result == null:
		_check(false, "ROUTE FREEZE produces result")
		return
	_equal(result.allocation_for("request_a"), 30.0,
		"ROUTE FREEZE shares selected main route")
	_equal(result.allocation_for("request_b"), 30.0,
		"ROUTE FREEZE does not adaptively reroute B during allocation")
	_equal(result.edge_usage("e_backup_1"), 0.0,
		"ROUTE FREEZE backup remains unused in v1 single-route policy")


func _test_failure_atomicity() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_request(_request(
		"bad_route", "grain", "A", "B", 20.0, 1, 1.0, ["missing"]
	)), "FAILURE ATOMICITY collects syntactically valid request")
	_check(allocator.freeze_request_set(), "FAILURE ATOMICITY freezes request before route validation")
	_check(not allocator.freeze_routes(0),
		"FAILURE ATOMICITY invalid candidate aborts route freeze")
	_equal(allocator.last_error(), "invalid_route:bad_route",
		"FAILURE ATOMICITY reports exact invalid candidate")
	_check(allocator.phase() == VNextSpatialTransportAllocator.PHASE_REQUESTS_FROZEN,
		"FAILURE ATOMICITY leaves phase before allocation")
	_check(allocator.allocate() == null and allocator.allocation_result() == null,
		"FAILURE ATOMICITY publishes no half-result")
	_equal(allocator.edge("e_ab").effective_capacity(), 100.0,
		"FAILURE ATOMICITY preserves frozen physical capacity")

	var atomic_batch := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(not atomic_batch.submit_requests([
		_request("valid", "grain", "A", "B", 10.0, 1, 1.0, ["e_ab"]),
		{"request_id": "invalid"},
	]), "FAILURE ATOMICITY invalid batch member rejects whole submission")
	_equal(atomic_batch.request_count(), 0,
		"FAILURE ATOMICITY invalid submission leaves no partial request set")


func _test_fairness_a_one_bottleneck() -> void:
	var result := _result_for(
		[_edge("e", "A", "B", 100.0)],
		[
			_request("a", "grain", "A", "B", 100.0, 1, 1.0, ["e"]),
			_request("b", "coal", "A", "B", 100.0, 1, 1.0, ["e"]),
		]
	)
	_equal(result.allocation_for("a"), 50.0, "FAIRNESS A equal share request a")
	_equal(result.allocation_for("b"), 50.0, "FAIRNESS A equal share request b")


func _test_fairness_b_shared_first_edge() -> void:
	var result := _result_for(
		[
			_edge("e_ab", "A", "B", 50.0),
			_edge("e_bc", "B", "C", 100.0),
			_edge("e_bd", "B", "D", 100.0),
		],
		[
			_request("to_c", "grain", "A", "C", 100.0, 1, 1.0, ["e_ab", "e_bc"]),
			_request("to_d", "coal", "A", "D", 100.0, 1, 1.0, ["e_ab", "e_bd"]),
		]
	)
	_equal(result.allocation_for("to_c"), 25.0, "FAIRNESS B shares first edge for C")
	_equal(result.allocation_for("to_d"), 25.0, "FAIRNESS B shares first edge for D")
	_equal(result.edge_usage("e_ab"), 50.0, "FAIRNESS B saturates only common first edge")


func _test_fairness_c_shared_final_edge() -> void:
	var result := _result_for(
		[
			_edge("e_ab", "A", "B", 100.0),
			_edge("e_db", "D", "B", 100.0),
			_edge("e_bc", "B", "C", 50.0),
		],
		[
			_request("from_a", "grain", "A", "C", 100.0, 1, 1.0, ["e_ab", "e_bc"]),
			_request("from_d", "coal", "D", "C", 100.0, 1, 1.0, ["e_db", "e_bc"]),
		]
	)
	_equal(result.allocation_for("from_a"), 25.0, "FAIRNESS C shares final edge for A")
	_equal(result.allocation_for("from_d"), 25.0, "FAIRNESS C shares final edge for D")
	_equal(result.edge_usage("e_bc"), 50.0, "FAIRNESS C saturates common final edge")


func _test_fairness_d_different_weights() -> void:
	var result := _result_for(
		[_edge("e", "A", "B", 120.0)],
		[
			_request("w1", "grain", "A", "B", 100.0, 1, 1.0, ["e"]),
			_request("w2", "coal", "A", "B", 100.0, 1, 2.0, ["e"]),
			_request("w3", "mail", "A", "B", 100.0, 1, 3.0, ["e"]),
		]
	)
	_equal(result.allocation_for("w1"), 20.0, "FAIRNESS D weight 1 receives 1/6")
	_equal(result.allocation_for("w2"), 40.0, "FAIRNESS D weight 2 receives 2/6")
	_equal(result.allocation_for("w3"), 60.0, "FAIRNESS D weight 3 receives 3/6")


func _test_fairness_e_independent_bottlenecks() -> void:
	var result := _result_for(
		[
			_edge("e_ab", "A", "B", 60.0),
			_edge("e_bc", "B", "C", 30.0),
		],
		[
			_request("cross", "grain", "A", "C", 100.0, 1, 1.0, ["e_ab", "e_bc"]),
			_request("first_only", "coal", "A", "B", 100.0, 1, 1.0, ["e_ab"]),
			_request("final_only", "mail", "B", "C", 100.0, 1, 1.0, ["e_bc"]),
		]
	)
	_equal(result.allocation_for("cross"), 15.0,
		"FAIRNESS E cross-route is limited by both active bottlenecks")
	_equal(result.allocation_for("first_only"), 45.0,
		"FAIRNESS E redistributes first-edge residual after final edge binds")
	_equal(result.allocation_for("final_only"), 15.0,
		"FAIRNESS E final-only request shares final edge")
	_equal(result.edge_usage("e_ab"), 60.0, "FAIRNESS E first edge conserves")
	_equal(result.edge_usage("e_bc"), 30.0, "FAIRNESS E final edge conserves")


func _test_fairness_f_priority_then_weight() -> void:
	var result := _result_for(
		[_edge("e", "A", "B", 100.0)],
		[
			_request("high", "troop_movement", "A", "B", 40.0, 2, 1.0, ["e"]),
			_request("low_w1", "grain", "A", "B", 100.0, 1, 1.0, ["e"]),
			_request("low_w3", "coal", "A", "B", 100.0, 1, 3.0, ["e"]),
		]
	)
	_equal(result.allocation_for("high"), 40.0,
		"PRIORITY/F fairness gives strict class first access")
	_equal(result.allocation_for("low_w1"), 15.0,
		"PRIORITY/F lower class then shares residual by weight 1")
	_equal(result.allocation_for("low_w3"), 45.0,
		"PRIORITY/F lower class then shares residual by weight 3")


func _test_nested_multi_edge_conservation() -> void:
	var result := _result_for(
		[
			_edge("e_ab", "A", "B", 90.0),
			_edge("e_bc", "B", "C", 60.0),
			_edge("e_cd", "C", "D", 40.0),
			_edge("e_be", "B", "E", 35.0),
		],
		[
			_request("long", "grain", "A", "D", 100.0, 1, 2.0, ["e_ab", "e_bc", "e_cd"]),
			_request("middle", "coal", "B", "D", 100.0, 1, 1.0, ["e_bc", "e_cd"]),
			_request("branch", "mail", "A", "E", 100.0, 1, 1.0, ["e_ab", "e_be"]),
		]
	)
	_assert_conservation(result, "MULTI-EDGE nested")
	var long_quantity: float = result.allocation_for("long")
	for edge_id: String in ["e_ab", "e_bc", "e_cd"]:
		_check(result.edge_usage(edge_id) + EPSILON >= long_quantity,
			"MULTI-EDGE long request quantity is feasible on %s" % edge_id)


func _test_strict_external_priority_and_no_id_leakage() -> void:
	var first := _result_for(
		[_edge("e", "A", "B", 50.0)],
		[
			_request("aa_low", "civilian_grain", "A", "B", 50.0, 1, 1.0, ["e"]),
			_request("zz_high", "military_supply", "A", "B", 50.0, 2, 1.0, ["e"]),
		]
	)
	_equal(first.allocation_for("zz_high"), 50.0,
		"PRIORITY supplied class overrides lexicographically later ID")
	_equal(first.allocation_for("aa_low"), 0.0,
		"PRIORITY lower class may starve under explicit policy")

	var changed_policy := _result_for(
		[_edge("e", "A", "B", 50.0)],
		[
			_request("aa_low", "civilian_grain", "A", "B", 50.0, 3, 1.0, ["e"]),
			_request("zz_high", "military_supply", "A", "B", 50.0, 1, 1.0, ["e"]),
		]
	)
	_equal(changed_policy.allocation_for("aa_low"), 50.0,
		"PRIORITY Spatial executes changed external policy without domain morals")
	_equal(changed_policy.allocation_for("zz_high"), 0.0,
		"PRIORITY domain label does not silently restore military preference")


func _test_time_window_is_eligibility_not_reservation() -> void:
	var at_eight := _result_for(
		[_edge("e", "A", "B", 100.0)],
		[
			_request("now", "grain", "A", "B", 100.0, 1, 1.0, ["e"], {}, 8, 8),
			_request("future", "coal", "A", "B", 100.0, 9, 1.0, ["e"], {}, 10, 12),
		],
		8
	)
	_equal(at_eight.allocation_for("now"), 100.0,
		"TIME WINDOW future high-priority demand does not reserve current capacity")
	_equal(at_eight.allocation_for("future"), 0.0,
		"TIME WINDOW future request is ineligible")
	_equal(at_eight.reason_for("future"), "outside_time_window",
		"TIME WINDOW eligibility reason is explicit")

	var at_ten := _result_for(
		[_edge("e", "A", "B", 100.0)],
		[_request("future", "coal", "A", "B", 100.0, 9, 1.0, ["e"], {}, 10, 12)],
		10
	)
	_equal(at_ten.allocation_for("future"), 100.0,
		"TIME WINDOW request participates in a later eligible cycle")
	var after_deadline := _result_for(
		[_edge("e", "A", "B", 100.0)],
		[_request("future", "coal", "A", "B", 100.0, 9, 1.0, ["e"], {}, 10, 12)],
		13
	)
	_equal(after_deadline.allocation_for("future"), 0.0,
		"TIME WINDOW deadline is inclusive then expires without future reservation")


func _test_disruption_and_restoration() -> void:
	var partial := _result_for(
		[_edge("bridge", "A", "B", 100.0, "rail", true, 0.25)],
		[_request("cargo", "grain", "A", "B", 80.0, 1, 1.0, ["bridge"])]
	)
	_equal(partial.edge_capacity("bridge"), 25.0,
		"DISRUPTION bounded multiplier reduces effective capacity")
	_equal(partial.allocation_for("cargo"), 25.0,
		"DISRUPTION allocation follows effective not base capacity")
	_equal(partial.edge_diagnostic("bridge").get("disruption_capacity_loss"), 75.0,
		"DISRUPTION diagnostic preserves multiplier contribution")

	var closed := _result_for(
		[_edge("bridge", "A", "B", 100.0, "rail", true, 0.0)],
		[_request("cargo", "grain", "A", "B", 80.0, 1, 1.0, ["bridge"])]
	)
	_equal(closed.edge_capacity("bridge"), 0.0, "DISRUPTION full closure has zero capacity")
	_equal(closed.allocation_for("cargo"), 0.0, "DISRUPTION full closure moves nothing")

	var restored := _result_for(
		[_edge("bridge", "A", "B", 100.0, "rail", true, 1.0)],
		[_request("cargo", "grain", "A", "B", 80.0, 1, 1.0, ["bridge"])]
	)
	_equal(restored.edge_capacity("bridge"), 100.0,
		"DISRUPTION restoration recovers base-derived capacity")
	_equal(restored.allocation_for("cargo"), 80.0,
		"DISRUPTION restoration does not retain prior damage")
	_equal(restored.edge_ids(), ["bridge"],
		"DISRUPTION temporary state does not change topology identity")
	_check(_edge("invalid", "A", "B", 10.0, "rail", true, 1.01) == null,
		"DISRUPTION multiplier above one fails closed")


func _test_routing_semantics_and_pareto_constraints() -> void:
	var equal_a := _result_for(
		[
			_edge("z_equal", "A", "B", 100.0, "rail", true, 1.0, false, 1.0, 1.0),
			_edge("a_equal", "A", "B", 100.0, "rail", true, 1.0, false, 1.0, 1.0),
		],
		[_request("tie", "grain", "A", "B", 10.0, 1, 1.0)]
	)
	_equal(equal_a.request_result("tie").get("route", []), ["a_equal"],
		"ROUTING equal-cost tie uses lexicographic edge path")

	var directed := _result_for(
		[_edge("one_way", "A", "B", 100.0, "rail", true, 1.0, true)],
		[_request("reverse", "grain", "B", "A", 10.0, 1, 1.0)]
	)
	_equal(directed.reason_for("reverse"), "no_available_route",
		"ROUTING directed edge rejects reverse traversal")

	var invalid_endpoint := _result_for(
		[_edge("e", "A", "B", 100.0)],
		[_request("missing", "grain", "A", "Z", 10.0, 1, 1.0)]
	)
	_equal(invalid_endpoint.reason_for("missing"), "invalid_endpoint",
		"ROUTING invalid endpoint is distinguished from capacity")

	var zero_auto := _result_for(
		[_edge("zero", "A", "B", 0.0)],
		[_request("zero_auto", "grain", "A", "B", 10.0, 1, 1.0)]
	)
	_equal(zero_auto.reason_for("zero_auto"), "no_available_route",
		"ROUTING zero-capacity edge is unavailable to automatic routing")

	var pareto := _result_for(
		[
			_edge("expensive_fast", "A", "C", 100.0, "rail", true, 1.0, true, 1.0, 9.0),
			_edge("cheap_slow_1", "A", "B", 100.0, "rail", true, 1.0, true, 4.0, 1.0),
			_edge("cheap_slow_2", "B", "C", 100.0, "rail", true, 1.0, true, 0.0, 0.0),
			_edge("suffix", "C", "D", 100.0, "rail", true, 1.0, true, 2.0, 1.0),
		],
		[_request(
			"pareto", "grain", "A", "D", 10.0, 1, 1.0, [],
			{"max_travel_time": 5.0}
		)]
	)
	_equal(pareto.request_result("pareto").get("route", []),
		["expensive_fast", "suffix"],
		"ROUTING Pareto label retains higher-score path needed by max travel constraint")
	_equal(pareto.route_candidate_count(), 1,
		"ROUTING v1 explicitly publishes one selected candidate")
	_check(VNextSharedTransportRequest.create(
		"self", "grain", "A", "A", 1.0, "bulk", 1, 1.0, 0
	) == null, "ROUTING self transport is rejected as invalid no-op demand")


func _test_determinism_under_all_input_reorders() -> void:
	var edges_forward: Array = [
		_edge("z", "A", "B", 90.0, "rail", true, 1.0, false, 1.0, 1.0),
		_edge("a", "A", "B", 90.0, "rail", true, 1.0, false, 1.0, 1.0),
		_edge("bc", "B", "C", 60.0),
	]
	var requests_forward: Array = [
		_request("r3", "grain", "A", "C", 70.0, 1, 3.0),
		_request("r1", "coal", "A", "C", 70.0, 1, 1.0),
		_request("r2", "mail", "A", "C", 30.0, 2, 1.0),
	]
	var edges_reverse: Array = edges_forward.duplicate()
	edges_reverse.reverse()
	var requests_reverse: Array = requests_forward.duplicate()
	requests_reverse.reverse()
	var first := _result_for(edges_forward, requests_forward)
	var second := _result_for(edges_reverse, requests_reverse)
	var third := _result_for(edges_forward, requests_forward)
	var first_json: String = JSON.stringify(first.snapshot())
	_check(first_json == JSON.stringify(second.snapshot()),
		"DETERMINISM request and edge reorder preserve complete result")
	_check(first_json == JSON.stringify(third.snapshot()),
		"DETERMINISM repeated run in process preserves complete result")
	determinism_digest = first_json.sha256_text()
	print("[DETERMINISM] digest=" + determinism_digest)


func _test_causal_observability() -> void:
	var result := _result_for(
		[_edge("damaged_bridge", "A", "B", 100.0, "rail", true, 0.5)],
		[
			_request("high", "troop_movement", "A", "B", 30.0, 2, 1.0, ["damaged_bridge"]),
			_request("low", "civilian_grain", "A", "B", 40.0, 1, 1.0, ["damaged_bridge"]),
		]
	)
	var low: Dictionary = result.request_result("low")
	_equal(low.get("quantity"), 40.0, "OBSERVABILITY requested quantity")
	_equal(low.get("allocated_quantity"), 20.0, "OBSERVABILITY allocated quantity")
	_equal(low.get("unallocated_quantity"), 20.0, "OBSERVABILITY unmet quantity")
	_equal(low.get("allocation_fraction"), 0.5, "OBSERVABILITY allocation fraction")
	_equal(low.get("route"), ["damaged_bridge"], "OBSERVABILITY selected route")
	_equal(low.get("binding_edge_ids"), ["damaged_bridge"], "OBSERVABILITY binding edge")
	_check(bool(low.get("blocked_by_higher_priority", false)),
		"OBSERVABILITY explicitly marks higher-priority blocking")
	_equal(low.get("reason"), "higher_priority_and_shared_capacity",
		"OBSERVABILITY causal reason distinguishes priority/capacity")
	var route_diagnostics: Array = low.get("route_diagnostics", []) as Array
	_check(route_diagnostics.size() == 1, "OBSERVABILITY compact per-route edge diagnostic")
	if route_diagnostics.size() == 1:
		var edge_fact: Dictionary = route_diagnostics[0] as Dictionary
		_equal(edge_fact.get("effective_capacity"), 50.0,
			"OBSERVABILITY effective capacity")
		_equal(edge_fact.get("disruption_multiplier"), 0.5,
			"OBSERVABILITY disruption factor")
		_equal(edge_fact.get("disruption_capacity_loss"), 50.0,
			"OBSERVABILITY disruption contribution")
		_equal(edge_fact.get("capacity_used_by_higher_priorities"), 30.0,
			"OBSERVABILITY higher-priority consumption")
		_equal(edge_fact.get("capacity_used_at_priority"), 20.0,
			"OBSERVABILITY same-priority consumption")
	_check(str(low.get("deterministic_tie_rule", "")).contains("request_id_only"),
		"OBSERVABILITY tie rule says ID is only canonical rounding order")


func _test_result_observer_isolation() -> void:
	var allocator := _allocator([_edge("e", "A", "B", 100.0)])
	_check(allocator.submit_request(_request(
		"immutable", "grain", "A", "B", 40.0, 1, 1.0, ["e"]
	)), "IMMUTABILITY result fixture submits")
	_check(allocator.freeze_request_set(), "IMMUTABILITY result fixture freezes request")
	_check(allocator.freeze_routes(0), "IMMUTABILITY result fixture freezes route")
	var first := allocator.allocate()
	if first == null:
		_check(false, "IMMUTABILITY result fixture allocates")
		return
	var getter_copy: Dictionary = first.request_result("immutable")
	getter_copy["allocated_quantity"] = 999.0
	var snapshot_copy: Dictionary = first.snapshot()
	(snapshot_copy["requests"] as Array)[0]["allocated_quantity"] = 999.0
	first._allocations["immutable"] = 999.0
	first._request_results["immutable"]["allocated_quantity"] = 999.0
	first._edge_diagnostics["e"]["allocated_capacity"] = 999.0
	var second := allocator.allocation_result()
	_check(second != null and second.is_valid(),
		"IMMUTABILITY canonical result survives reflective consumer mutation")
	if second != null:
		_equal(second.allocation_for("immutable"), 40.0,
			"IMMUTABILITY another requester observes frozen allocation")
		_equal(second.edge_usage("e"), 40.0,
			"IMMUTABILITY consumer receives no mutable edge-state handle")


func _test_domain_neutral_competition_and_money_inertness() -> void:
	var base_records: Array = [
		{
			"request_id": "grain", "requester_system": "economy",
			"origin_region_id": "A", "destination_region_id": "B",
			"quantity": 60.0, "cargo_class": "civilian_grain",
			"priority_class": 1, "weight": 1.0, "earliest_time": 0,
			"accepted_route": ["e"],
		},
		{
			"request_id": "troops", "requester_system": "military",
			"origin_region_id": "A", "destination_region_id": "B",
			"quantity": 60.0, "cargo_class": "troop_movement",
			"priority_class": 1, "weight": 1.0, "earliest_time": 0,
			"accepted_route": ["e"],
		},
	]
	var with_money: Array = base_records.duplicate(true)
	(with_money[0] as Dictionary)["price"] = 1_000_000_000
	(with_money[1] as Dictionary)["paid_priority_fee"] = 9_999_999_999
	var base := _result_for([_edge("e", "A", "B", 100.0)], base_records)
	var paid := _result_for([_edge("e", "A", "B", 100.0)], with_money)
	_equal(base.allocation_for("grain"), 50.0,
		"DOMAIN competition sends civilian grain through same allocator")
	_equal(base.allocation_for("troops"), 50.0,
		"DOMAIN competition sends troop movement through same allocator")
	_equal(paid.allocations(), base.allocations(),
		"MONEY extra monetary fields cannot create or redirect physical capacity")
	_equal(paid.edge_usage("e"), 100.0,
		"MONEY total physical throughput remains Spatial-authoritative")


func _test_public_api_bypass_prevention() -> void:
	var allocator := _allocator([_edge("e", "A", "B", 100.0)])
	for forbidden_method: String in [
		"request_capacity", "reserve_capacity", "cancel", "cancel_capacity_request",
		"allocate_request", "allocate_capacity",
	]:
		_check(not allocator.has_method(forbidden_method),
			"BYPASS allocator has no public direct API %s" % forbidden_method)
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/spatial/shared_transport/spatial_transport_allocator.gd"
	)
	for forbidden_declaration: String in [
		"func request_capacity(", "func reserve_capacity(", "func cancel(",
		"func cancel_capacity_request(", "func allocate_request(",
	]:
		_check(not source.contains(forbidden_declaration),
			"BYPASS source cannot reintroduce %s" % forbidden_declaration)
	_check(not allocator.has_method("restore") and not allocator.has_method("snapshot"),
		"PERSISTENCE allocation cycle/result remain transient")

	var legacy_world := VNextSpatialWorld.new()
	var legacy_window := VNextSpatialCapacityWindow.new()
	for removed_method: String in ["request_capacity", "reserve_capacity"]:
		_check(not legacy_world.has_method(removed_method),
			"BYPASS legacy SpatialWorld no longer admits demand through %s" % removed_method)
		_check(not legacy_window.has_method(removed_method),
			"BYPASS capacity window no longer admits demand through %s" % removed_method)
	_check(legacy_world.has_method("request_capacity_batch"),
		"LEGACY boundary retains the product-required batch compatibility path")
	_check(legacy_world.has_method("cancel_capacity_request"),
		"LEGACY boundary retains Military cancellation pending product migration")
	_check(not legacy_window.has_method("cancel_capacity_request"),
		"BYPASS cancellation implementation is internal below SpatialWorld")

	var world_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/spatial/spatial_world.gd"
	)
	var window_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/spatial/spatial_capacity_window.gd"
	)
	for removed_declaration: String in ["func request_capacity(", "func reserve_capacity("]:
		_check(not world_source.contains(removed_declaration),
			"BYPASS SpatialWorld source cannot reintroduce %s" % removed_declaration)
		_check(not window_source.contains(removed_declaration),
			"BYPASS capacity-window source cannot reintroduce %s" % removed_declaration)
	_check(world_source.contains("LEGACY TRANSPORT COMPATIBILITY PATH")
		and window_source.contains("LEGACY TRANSPORT COMPATIBILITY PATH"),
		"LEGACY batch and cancellation paths carry explicit compatibility fencing")
	var world_batch_marker: int = world_source.find("# LEGACY TRANSPORT COMPATIBILITY PATH")
	var world_batch_declaration: int = world_source.find("func request_capacity_batch(")
	var window_batch_marker: int = window_source.find("# LEGACY TRANSPORT COMPATIBILITY PATH")
	var window_batch_declaration: int = window_source.find("func request_capacity_batch(")
	_check(world_batch_marker >= 0 and world_batch_marker < world_batch_declaration
		and world_batch_declaration - world_batch_marker < 400,
		"LEGACY SpatialWorld batch declaration is directly fenced")
	_check(window_batch_marker >= 0 and window_batch_marker < window_batch_declaration
		and window_batch_declaration - window_batch_marker < 400,
		"LEGACY capacity-window batch declaration is directly fenced")
	_check(world_source.contains("Military action cancellation is the only"),
		"LEGACY cancellation retains its exact runtime-caller classification")

	var core_sources: Array[String] = [
		"shared_transport_allocation_result.gd",
		"shared_transport_edge.gd",
		"shared_transport_request.gd",
		"shared_transport_route.gd",
		"spatial_shared_transport_topology.gd",
		"spatial_transport_allocator.gd",
	]
	for core_filename: String in core_sources:
		var core_source: String = FileAccess.get_file_as_string(
			"res://scripts/vnext/spatial/shared_transport/%s" % core_filename
		)
		for forbidden_call: String in [
			"request_capacity(", "reserve_capacity(",
			"cancel_capacity_request(", "request_capacity_batch(",
		]:
			_check(not core_source.contains(forbidden_call),
				"BYPASS new core %s cannot call legacy %s" % [core_filename, forbidden_call])

	var freeze_record: String = FileAccess.get_file_as_string(
		"res://docs/vnext/shared_transport_component_freeze.md"
	)
	_check(freeze_record.contains("e93ad2f")
		and freeze_record.contains("## Canonical component line"),
		"PROVENANCE freeze record fixes e93ad2f as the canonical component line")
	_check(freeze_record.contains("c41f07f50ac355b8c85b961cd3d633fa17f37ba9")
		and freeze_record.contains("not based on"),
		"PROVENANCE component freeze cannot imply trusted-product integration")


func _test_adversarial_conservation_and_finiteness() -> void:
	var edges: Array = []
	for index: int in 12:
		edges.append(_edge(
			"e_%02d" % index, "n_%02d" % index, "n_%02d" % (index + 1),
			35.0 + float((index * 17) % 41)
		))
	var requests: Array = []
	for index: int in 48:
		var start: int = index % 8
		var length: int = 1 + (index % 5)
		var route: Array[String] = []
		for edge_index: int in range(start, start + length):
			route.append("e_%02d" % edge_index)
		requests.append(_request(
			"req_%03d" % index,
			["grain", "coal", "military_supply", "mail"][index % 4],
			"n_%02d" % start,
			"n_%02d" % (start + length),
			5.0 + float((index * 13) % 37),
			index % 4,
			1.0 + float(index % 5),
			route
		))
	var result := _result_for(edges, requests)
	_assert_conservation(result, "CONSERVATION adversarial")
	for request_id: String in result.request_ids():
		var allocated: float = result.allocation_for(request_id)
		_check(is_finite(allocated) and allocated >= -EPSILON,
			"CONSERVATION %s finite and nonnegative" % request_id)


func _test_performance_profile() -> void:
	_profile_case("small", 16, 32)
	_profile_case("medium", 48, 128)
	_profile_case("stress_local", 96, 320)


func _profile_case(label: String, node_count: int, request_count: int) -> void:
	var memory_before: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var edges: Array = []
	for index: int in node_count - 1:
		edges.append(_edge(
			"line_%03d" % index,
			"node_%03d" % index,
			"node_%03d" % (index + 1),
			10000.0, "rail", true, 1.0, false, 1.0, 1.0
		))
	for index: int in node_count - 2:
		edges.append(_edge(
			"skip_%03d" % index,
			"node_%03d" % index,
			"node_%03d" % (index + 2),
			10000.0, "road", true, 1.0, false, 1.5, 1.5
		))
	var requests: Array = []
	for index: int in request_count:
		var destination: int = 1 + (index * 37) % (node_count - 1)
		requests.append(_request(
			"perf_%05d" % index, "synthetic", "node_000",
			"node_%03d" % destination, 1.0 + float(index % 7),
			index % 3, 1.0 + float(index % 4)
		))
	var allocator := _allocator(edges)
	_check(allocator.submit_requests(requests), "PERFORMANCE %s submits requests" % label)
	_check(allocator.freeze_request_set(), "PERFORMANCE %s freezes requests" % label)
	_check(allocator.freeze_routes(0), "PERFORMANCE %s freezes routes" % label)
	var result := allocator.allocate()
	var memory_after: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	_check(result != null and result.is_valid(), "PERFORMANCE %s result valid" % label)
	_check(allocator.route_candidate_count() == request_count,
		"PERFORMANCE %s candidate count equals routable requests" % label)
	_check(allocator.routing_duration_usec() < 10_000_000,
		"PERFORMANCE %s routing remains local stress safe" % label)
	_check(allocator.allocation_duration_usec() < 10_000_000,
		"PERFORMANCE %s allocation remains local stress safe" % label)
	var profile_line: String = (
		"[PERF] label=%s nodes=%d edges=%d requests=%d candidates=%d "
		+ "routing_ms=%.3f allocation_ms=%.3f memory_delta_kib=%.1f"
	) % [
			label, node_count, edges.size(), request_count,
			allocator.route_candidate_count(),
			float(allocator.routing_duration_usec()) / 1000.0,
			float(allocator.allocation_duration_usec()) / 1000.0,
			(memory_after - memory_before) / 1024.0,
		]
	print(profile_line)


func _result_for(
	edges: Array,
	requests: Array,
	allocation_time: int = 0
) -> VNextSharedTransportAllocationResult:
	var allocator := _allocator(edges)
	_check(allocator.submit_requests(requests), "fixture submits complete generic batch")
	_check(allocator.freeze_request_set(), "fixture freezes complete request set")
	_check(allocator.freeze_routes(allocation_time), "fixture freezes routes/candidates")
	var result := allocator.allocate()
	_check(result != null and result.is_valid(), "fixture publishes valid immutable result")
	return result


func _assert_conservation(
	result: VNextSharedTransportAllocationResult,
	label: String
) -> void:
	_check(result != null and result.is_valid(), label + " result validates")
	if result == null:
		return
	var usage_from_routes: Dictionary = {}
	for request_id: String in result.request_ids():
		var record: Dictionary = result.request_result(request_id)
		var requested: float = float(record.get("quantity", -1.0))
		var allocated: float = float(record.get("allocated_quantity", -1.0))
		_check(
			is_finite(requested) and is_finite(allocated)
			and allocated >= -EPSILON and allocated <= requested + EPSILON,
			"%s request %s bounded" % [label, request_id]
		)
		for raw_edge_id: Variant in record.get("route", []) as Array:
			var edge_id: String = str(raw_edge_id)
			usage_from_routes[edge_id] = (
				float(usage_from_routes.get(edge_id, 0.0)) + allocated
			)
	for edge_id: String in result.edge_ids():
		var usage: float = result.edge_usage(edge_id)
		var capacity: float = result.edge_capacity(edge_id)
		_check(
			is_finite(usage) and is_finite(capacity)
			and usage >= -EPSILON and usage <= capacity + EPSILON,
			"%s edge %s bounded" % [label, edge_id]
		)
		_approx(usage, float(usage_from_routes.get(edge_id, 0.0)),
			"%s edge %s equals route flow" % [label, edge_id])


func _allocator(edges: Array) -> VNextSpatialTransportAllocator:
	var allocator := VNextSpatialTransportAllocator.create(edges)
	_check(allocator != null and allocator.is_valid(),
		"fixture initializes detached Spatial topology")
	return allocator


func _edge(
	edge_id: String,
	from_region_id: String,
	to_region_id: String,
	capacity: float,
	mode: String = "rail",
	enabled: bool = true,
	disruption_multiplier: float = 1.0,
	directional: bool = false,
	travel_time: float = 1.0,
	base_transport_cost: float = 1.0
) -> VNextSharedTransportEdge:
	return VNextSharedTransportEdge.create(
		edge_id, from_region_id, to_region_id, mode, capacity, travel_time,
		enabled, disruption_multiplier, directional, base_transport_cost
	)


func _request(
	request_id: String,
	requester_system: String,
	origin_region_id: String,
	destination_region_id: String,
	quantity: float,
	priority_class: int,
	weight: float,
	accepted_route: Array[String] = [],
	route_constraints: Dictionary = {},
	earliest_time: int = 0,
	latest_time: Variant = null
) -> VNextSharedTransportRequest:
	return VNextSharedTransportRequest.create(
		request_id, requester_system, origin_region_id, destination_region_id,
		quantity, "generic_cargo", priority_class, weight, earliest_time,
		latest_time, accepted_route, route_constraints
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected,
		label + " (got %s, expected %s)" % [str(actual), str(expected)])


func _approx(actual: float, expected: float, label: String) -> void:
	_check(is_finite(actual) and absf(actual - expected) <= EPSILON,
		label + " (got %.9f, expected %.9f)" % [actual, expected])


func _finish() -> void:
	print("[TEST MATRIX] LIFECYCLE IMMUTABILITY FAIRNESS PRIORITY MULTI_EDGE DISRUPTION "
		+ "TIME_WINDOW DETERMINISM OBSERVABILITY BYPASS CONSERVATION FAILURE_ATOMICITY")
	print("Shared transport allocation core: %d checks, %d failures" % [checks, failures])
	if failures > 0 or checks <= 0:
		printerr("SHARED TRANSPORT CORE: BLOCKED — focused adversarial tests failed")
		quit(1)
	else:
		print("SHARED TRANSPORT CORE: PASS — FROZEN CORE VALIDATED")
		quit(0)
