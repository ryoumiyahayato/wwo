extends SceneTree

const EPSILON: float = 0.000001

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_c01_one_request_sufficient_capacity()
	_test_c02_request_exceeds_capacity()
	_test_c03_same_priority_weighted_share()
	_test_c04_source_order_is_irrelevant()
	_test_c05_priority_precedence()
	_test_c06_multi_edge_bottleneck()
	_test_c07_overlapping_routes_share_edge()
	_test_c08_disabled_edge_zero_capacity()
	_test_c09_reduced_capacity_edge()
	_test_c10_no_edge_exceeds_capacity()
	_test_c11_no_request_exceeds_demand()
	_test_c12_aggregate_capacity_conservation()
	_test_c13_economy_military_compete()
	_test_c14_requesters_cannot_allocate_directly()
	_test_c15_duplicate_request_id_fails_closed()
	_test_c16_invalid_route_fails_closed()
	_test_deterministic_auto_routing()
	_test_request_contract_and_route_constraints()
	_test_existing_spatial_topology_reuse()
	_test_result_is_immutable_to_consumers()
	_finish()


func _test_c01_one_request_sufficient_capacity() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	var request := _request("req_a", "economy", "A", "B", 40.0, 1, 1.0, ["e_ab"])
	_check(allocator.submit_request(request), "C-01 submits one generic request")
	_check(allocator.freeze_request_set(), "C-01 freezes the complete request set")
	var result := allocator.allocate(0)
	_check(result != null and result.is_valid(), "C-01 produces a valid immutable result")
	if result == null:
		return
	_equal(result.allocation_for("req_a"), 40.0, "C-01 allocates the full request")
	_equal(result.edge_usage("e_ab"), 40.0, "C-01 records physical edge usage")
	_equal(result.status_for("req_a"), "allocated", "C-01 marks a full allocation")


func _test_c02_request_exceeds_capacity() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_request(_request("req_a", "economy", "A", "B", 150.0, 1, 1.0, ["e_ab"])), "C-02 submits demand above capacity")
	_check(allocator.freeze_request_set(), "C-02 freezes the request set")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.allocation_for("req_a"), 100.0, "C-02 caps allocation at edge capacity")
	_check(result.status_for("req_a") == "partial", "C-02 reports a partial allocation")


func _test_c03_same_priority_weighted_share() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_requests([
		_request("req_a", "economy", "A", "B", 80.0, 1, 1.0, ["e_ab"]),
		_request("req_b", "military", "A", "B", 80.0, 1, 1.0, ["e_ab"]),
	]), "C-03 submits same-priority competitors")
	_check(allocator.freeze_request_set(), "C-03 freezes all competitors before allocation")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.allocation_for("req_a"), 50.0, "C-03 gives equal-weight request A a fair share")
	_equal(result.allocation_for("req_b"), 50.0, "C-03 gives equal-weight request B a fair share")
	_equal(result.edge_usage("e_ab"), 100.0, "C-03 consumes exactly the shared capacity")


func _test_c04_source_order_is_irrelevant() -> void:
	var first := _allocator([_edge("e_ab", "A", "B", 100.0)])
	var second := _allocator([_edge("e_ab", "A", "B", 100.0)])
	var request_a := _request("req_a", "economy", "A", "B", 80.0, 1, 1.0, ["e_ab"])
	var request_b := _request("req_b", "military", "A", "B", 80.0, 1, 2.0, ["e_ab"])
	_check(first.submit_requests([request_b, request_a]), "C-04 submits reverse source order")
	_check(second.submit_requests([request_a, request_b]), "C-04 submits forward source order")
	_check(first.freeze_request_set() and second.freeze_request_set(), "C-04 freezes both canonical request sets")
	var first_result := first.allocate(0)
	var second_result := second.allocate(0)
	_check(first_result != null and second_result != null, "C-04 allocates both permutations")
	if first_result == null or second_result == null:
		return
	_equal(JSON.stringify(first_result.snapshot()), JSON.stringify(second_result.snapshot()), "C-04 source reorder produces identical result")


func _test_c05_priority_precedence() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_requests([
		_request("req_low", "economy", "A", "B", 80.0, 1, 1.0, ["e_ab"]),
		_request("req_high", "military", "A", "B", 80.0, 2, 1.0, ["e_ab"]),
	]), "C-05 submits high and low priority demand")
	_check(allocator.freeze_request_set(), "C-05 freezes priority classes")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.allocation_for("req_high"), 80.0, "C-05 higher priority receives preferential access")
	_equal(result.allocation_for("req_low"), 20.0, "C-05 lower priority receives only remaining capacity")


func _test_c06_multi_edge_bottleneck() -> void:
	var allocator := _allocator([
		_edge("e_ab", "A", "B", 100.0),
		_edge("e_bc", "B", "C", 30.0),
	])
	_check(allocator.submit_request(_request("req_route", "economy", "A", "C", 80.0, 1, 1.0, ["e_ab", "e_bc"])), "C-06 submits a multi-edge request")
	_check(allocator.freeze_request_set(), "C-06 accepts a contiguous route")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.allocation_for("req_route"), 30.0, "C-06 reserves consistently through the bottleneck")
	_equal(result.edge_usage("e_ab"), 30.0, "C-06 reserves the first edge by the same quantity")
	_equal(result.edge_usage("e_bc"), 30.0, "C-06 reserves the bottleneck edge by the same quantity")


func _test_c07_overlapping_routes_share_edge() -> void:
	var allocator := _allocator([
		_edge("e_ab", "A", "B", 50.0),
		_edge("e_bc", "B", "C", 100.0),
		_edge("e_bd", "B", "D", 100.0),
	])
	_check(allocator.submit_requests([
		_request("req_c", "economy", "A", "C", 80.0, 1, 1.0, ["e_ab", "e_bc"]),
		_request("req_d", "military", "A", "D", 80.0, 1, 1.0, ["e_ab", "e_bd"]),
	]), "C-07 submits overlapping multi-edge routes")
	_check(allocator.freeze_request_set(), "C-07 freezes overlapping routes")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.allocation_for("req_c"), 25.0, "C-07 shares the common edge with request C")
	_equal(result.allocation_for("req_d"), 25.0, "C-07 shares the common edge with request D")
	_equal(result.edge_usage("e_ab"), 50.0, "C-07 common edge is not over-reserved")
	_equal(result.edge_usage("e_bc"), 25.0, "C-07 first branch usage is conserved")
	_equal(result.edge_usage("e_bd"), 25.0, "C-07 second branch usage is conserved")


func _test_c08_disabled_edge_zero_capacity() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0, "rail", false)])
	_check(allocator.submit_request(_request("req_disabled", "economy", "A", "B", 50.0, 1, 1.0, ["e_ab"])), "C-08 submits demand on a disabled edge")
	_check(allocator.freeze_request_set(), "C-08 validates topology even when unavailable")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.edge_capacity("e_ab"), 0.0, "C-08 disabled edge has zero effective capacity")
	_equal(result.allocation_for("req_disabled"), 0.0, "C-08 disabled edge receives no allocation")
	_equal(result.edge_usage("e_ab"), 0.0, "C-08 disabled edge records zero usage")


func _test_c09_reduced_capacity_edge() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0, "rail", true, 0.25)])
	_check(allocator.submit_request(_request("req_damaged", "economy", "A", "B", 80.0, 1, 1.0, ["e_ab"])), "C-09 submits demand on a disrupted edge")
	_check(allocator.freeze_request_set(), "C-09 freezes disrupted capacity")
	var result := allocator.allocate(0)
	if result == null:
		return
	_equal(result.edge_capacity("e_ab"), 25.0, "C-09 disruption multiplier reduces capacity physically")
	_equal(result.allocation_for("req_damaged"), 25.0, "C-09 allocation follows reduced physical capacity")


func _test_c10_no_edge_exceeds_capacity() -> void:
	var allocator := _allocator([
		_edge("e_ab", "A", "B", 50.0),
		_edge("e_bc", "B", "C", 100.0),
		_edge("e_bd", "B", "D", 100.0),
	])
	_check(allocator.submit_requests([
		_request("req_c", "economy", "A", "C", 80.0, 1, 1.0, ["e_ab", "e_bc"]),
		_request("req_d", "military", "A", "D", 80.0, 1, 1.0, ["e_ab", "e_bd"]),
	]), "C-10 submits a capacity invariant fixture")
	_check(allocator.freeze_request_set(), "C-10 freezes invariant fixture")
	var result := allocator.allocate(0)
	if result == null:
		return
	for edge_id: String in result.edge_ids():
		_check(result.edge_usage(edge_id) <= result.edge_capacity(edge_id) + EPSILON, "C-10 edge %s stays within capacity" % edge_id)


func _test_c11_no_request_exceeds_demand() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_requests([
		_request("req_a", "economy", "A", "B", 15.0, 1, 1.0, ["e_ab"]),
		_request("req_b", "military", "A", "B", 150.0, 1, 3.0, ["e_ab"]),
	]), "C-11 submits bounded-demand fixtures")
	_check(allocator.freeze_request_set(), "C-11 freezes bounded-demand fixtures")
	var result := allocator.allocate(0)
	if result == null:
		return
	for request_id: String in result.request_ids():
		_check(result.allocation_for(request_id) <= result.requested_quantity(request_id) + EPSILON, "C-11 request %s stays within demand" % request_id)


func _test_c12_aggregate_capacity_conservation() -> void:
	var allocator := _allocator([
		_edge("e_ab", "A", "B", 50.0),
		_edge("e_bc", "B", "C", 100.0),
		_edge("e_bd", "B", "D", 100.0),
	])
	_check(allocator.submit_requests([
		_request("req_c", "economy", "A", "C", 80.0, 1, 1.0, ["e_ab", "e_bc"]),
		_request("req_d", "military", "A", "D", 80.0, 1, 1.0, ["e_ab", "e_bd"]),
	]), "C-12 submits conservation fixtures")
	_check(allocator.freeze_request_set(), "C-12 freezes conservation fixtures")
	var result := allocator.allocate(0)
	if result == null:
		return
	var usage_from_routes: Dictionary = {}
	for request_id: String in result.request_ids():
		var record: Dictionary = result.request_result(request_id)
		var allocated: float = float(record.get("allocated_quantity", 0.0))
		for raw_edge_id: Variant in record.get("route", []) as Array:
			var edge_id: String = str(raw_edge_id)
			usage_from_routes[edge_id] = float(usage_from_routes.get(edge_id, 0.0)) + allocated
	for edge_id: String in result.edge_ids():
		_equal(result.edge_usage(edge_id), float(usage_from_routes.get(edge_id, 0.0)), "C-12 route allocations conserve usage on %s" % edge_id)
		_check(result.edge_usage(edge_id) <= result.edge_capacity(edge_id) + EPSILON, "C-12 usage on %s is physically bounded" % edge_id)


func _test_c13_economy_military_compete() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_requests([
		_request("economy:shipment:1", "economy", "A", "B", 80.0, 1, 1.0, ["e_ab"]),
		_request("military:convoy:1", "military", "A", "B", 80.0, 1, 1.0, ["e_ab"]),
	]), "C-13 submits Economy and Military synthetic demand together")
	_check(allocator.freeze_request_set(), "C-13 freezes both domains in one batch")
	var result := allocator.allocate(0)
	if result == null:
		return
	_check(result.allocation_for("economy:shipment:1") > 0.0, "C-13 Economy receives a shared allocation")
	_check(result.allocation_for("military:convoy:1") > 0.0, "C-13 Military receives a shared allocation")
	_equal(result.edge_usage("e_ab"), 100.0, "C-13 both domains consume one shared physical budget")


func _test_c14_requesters_cannot_allocate_directly() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(not allocator.has_method("allocate_request"), "C-14 allocator exposes no direct requester allocation API")
	_check(allocator.submit_request(_request("req_a", "economy", "A", "B", 40.0, 1, 1.0, ["e_ab"])), "C-14 requester can submit demand only")
	_check(allocator.allocation_result() == null, "C-14 submission alone produces no capacity result")
	_check(allocator.allocate(0) == null, "C-14 allocation before freeze fails closed")
	_check(allocator.freeze_request_set(), "C-14 Spatial freezes before allocation")
	_check(allocator.allocate(0) != null, "C-14 only Spatial allocation phase produces a result")


func _test_c15_duplicate_request_id_fails_closed() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	var first := _request("duplicate", "economy", "A", "B", 40.0, 1, 1.0, ["e_ab"])
	var second := _request("duplicate", "military", "A", "B", 90.0, 2, 1.0, ["e_ab"])
	_check(allocator.submit_request(first), "C-15 accepts the first request ID")
	_check(not allocator.submit_request(second), "C-15 rejects the duplicate request ID")
	_equal(allocator.request_count(), 1, "C-15 duplicate rejection leaves one canonical request")
	_check(allocator.last_error() == "duplicate_request_id", "C-15 duplicate rejection is explicit")


func _test_c16_invalid_route_fails_closed() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_request(_request("bad_route", "economy", "A", "C", 20.0, 1, 1.0, ["missing_edge"])), "C-16 accepts syntactically valid demand before topology validation")
	_check(not allocator.freeze_request_set(), "C-16 invalid accepted route blocks the frozen batch")
	_check(allocator.last_error() == "invalid_route:bad_route", "C-16 invalid route fails closed with an explicit reason")
	_check(allocator.allocate(0) == null, "C-16 invalid route cannot produce an allocation")


func _test_deterministic_auto_routing() -> void:
	var allocator := _allocator([
		_edge("e_slow", "A", "C", 100.0, "road", true, 1.0, false, 20.0, 1.0),
		_edge("e_fast_1", "A", "B", 100.0, "rail", true, 1.0, false, 2.0, 1.0),
		_edge("e_fast_2", "B", "C", 100.0, "rail", true, 1.0, false, 2.0, 1.0),
	])
	var request := _request("auto_route", "economy", "A", "C", 10.0, 1, 1.0)
	_check(allocator.submit_request(request), "auto-routing submits a request without an accepted route")
	_check(allocator.freeze_request_set(), "auto-routing freezes the request")
	var result := allocator.allocate(0)
	if result == null:
		return
	var route: Array = result.request_result("auto_route").get("route", []) as Array
	_equal(JSON.stringify(route), JSON.stringify(["e_fast_1", "e_fast_2"]), "auto-routing uses deterministic physical route cost")
	_equal(result.allocation_for("auto_route"), 10.0, "auto-routing allocates along the selected route")


func _test_request_contract_and_route_constraints() -> void:
	var constrained_allocator := _allocator([
		_edge("e_road", "A", "B", 100.0, "road", true, 1.0, false, 5.0, 10.0),
		_edge("e_rail", "A", "B", 100.0, "rail", true, 1.0, false, 1.0, 1.0),
	])
	_check(constrained_allocator.submit_request_record({
		"request_id": "constrained",
		"requester_system": "generic_system",
		"origin_region_id": "A",
		"destination_region_id": "B",
		"quantity": 10.0,
		"cargo_class": "bulk",
		"priority_class": 1,
		"weight": 1.0,
		"earliest_time": 0,
		"latest_time": 2,
		"route_constraints": {"allowed_modes": ["road"]},
	}), "request contract accepts generic dictionary fields")
	_check(constrained_allocator.freeze_request_set(), "route constraints freeze with the complete request set")
	var constrained_result := constrained_allocator.allocate(1)
	if constrained_result != null:
		_equal(JSON.stringify(constrained_result.request_result("constrained").get("route", [])), JSON.stringify(["e_road"]), "allowed mode constraint selects only physical road")
		_equal(constrained_result.allocation_for("constrained"), 10.0, "inclusive latest time keeps an active request allocatable")

	var outside_allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(outside_allocator.submit_request(_request("future", "generic_system", "A", "B", 10.0, 1, 1.0, ["e_ab"], {}, 3, 4)), "time-window fixture submits an earliest/latest request")
	_check(outside_allocator.freeze_request_set(), "time-window fixture freezes before checking eligibility")
	var outside_result := outside_allocator.allocate(2)
	if outside_result != null:
		_equal(outside_result.allocation_for("future"), 0.0, "request before earliest time receives no allocation")
		_equal(outside_result.status_for("future"), "outside_time_window", "out-of-window status is explicit")

	var malformed_allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(malformed_allocator.submit_request(_request("bad_constraints", "generic_system", "A", "B", 10.0, 1, 1.0, [], {"allowed_modes": []})), "malformed constraint fixture enters collection only")
	_check(not malformed_allocator.freeze_request_set(), "empty allowed-mode constraint fails closed at freeze")


func _test_existing_spatial_topology_reuse() -> void:
	var catalog := VNextSpatialCatalog.new()
	_check(catalog.load_legacy_world_map(), "existing Spatial catalog loads for topology reuse")
	if not catalog.is_loaded():
		return
	var world := VNextSpatialWorld.create(catalog)
	_check(world != null and world.is_valid(), "existing Spatial world remains the authority for link state")
	if world == null:
		return
	var topology := VNextSpatialSharedTransportTopology.from_spatial_world(world)
	_check(topology != null and topology.is_valid(), "transport core can reference existing Spatial topology")
	if topology == null:
		return
	_equal(topology.edge_ids(), catalog.link_ids(), "transport topology reuses authoritative Spatial link IDs")
	var allocator := VNextSpatialTransportAllocator.create_from_topology(topology)
	_check(allocator != null and allocator.is_valid(), "allocator accepts the reused topology without a second map")


func _test_result_is_immutable_to_consumers() -> void:
	var allocator := _allocator([_edge("e_ab", "A", "B", 100.0)])
	_check(allocator.submit_request(_request("immutable", "economy", "A", "B", 40.0, 1, 1.0, ["e_ab"])), "immutability fixture submits demand")
	_check(allocator.freeze_request_set(), "immutability fixture freezes demand")
	var result := allocator.allocate(0)
	if result == null:
		return
	var snapshot: Dictionary = result.snapshot()
	(snapshot["requests"] as Array)[0]["allocated_quantity"] = 999.0
	var request_copy: Dictionary = result.request_result("immutable")
	request_copy["allocated_quantity"] = 999.0
	_check(result.allocation_for("immutable") == 40.0, "consumer mutations cannot alter immutable result")
	_check(result.is_immutable(), "result advertises immutable ownership boundary")
	_check(not allocator.submit_request(_request("late", "economy", "A", "B", 1.0, 1, 1.0, ["e_ab"])), "requests cannot be added after freeze/allocation")


func _allocator(edges: Array) -> VNextSpatialTransportAllocator:
	var allocator := VNextSpatialTransportAllocator.create(edges)
	_check(allocator != null and allocator.is_valid(), "allocator fixture initializes a valid Spatial network")
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
		edge_id,
		from_region_id,
		to_region_id,
		mode,
		capacity,
		travel_time,
		enabled,
		disruption_multiplier,
		directional,
		base_transport_cost
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
		request_id,
		requester_system,
		origin_region_id,
		destination_region_id,
		quantity,
		"generic_cargo",
		priority_class,
		weight,
		earliest_time,
		latest_time,
		accepted_route,
		route_constraints
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label + " (got %s, expected %s)" % [str(actual), str(expected)])


func _finish() -> void:
	print("Shared transport allocation core: %d checks, %d failures" % [checks, failures])
	if failures > 0 or checks <= 0:
		printerr("SHARED TRANSPORT CORE: BLOCKED — focused C tests failed")
		quit(1)
	else:
		print("SHARED TRANSPORT CORE: PASS — READY FOR INTEGRATION REVIEW")
		quit(0)
