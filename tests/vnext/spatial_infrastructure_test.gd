extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_catalog_reuses_legacy_map()
	_test_topology_queries_are_deterministic()
	_test_infrastructure_state_and_capacity_formula()
	_test_shared_capacity_contention_and_rollover()
	_test_deterministic_request_permutation()
	_test_batch_capacity_submission()
	_test_territorial_mutation_and_projection()
	_test_snapshot_restore_and_transactional_rejection()
	_test_time_partition_and_bounded_state()
	print("VNext spatial infrastructure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_catalog_reuses_legacy_map() -> void:
	var catalog := _catalog()
	_check(catalog != null and catalog.is_loaded(), "legacy world-map sources load into one catalog")
	if catalog == null or not catalog.is_loaded():
		return
	_equal(catalog.region_ids().size(), 9, "catalog reuses all legacy regions")
	_equal(catalog.city_ids().size(), 32, "catalog reuses all legacy cities")
	_equal(catalog.port_ids().size(), 8, "catalog reuses all legacy ports")
	_equal(catalog.links_of_type(VNextSpatialCatalog.LINK_TYPE_ROAD).size(), 3, "catalog reuses legacy roads")
	_equal(catalog.links_of_type(VNextSpatialCatalog.LINK_TYPE_RAIL).size(), 9, "catalog reuses legacy rail")
	_equal(catalog.links_of_type(VNextSpatialCatalog.LINK_TYPE_SHIPPING).size(), 3, "catalog reuses legacy shipping")
	_check(catalog.get_city("place:paris").get("id") == "paris", "place stable query resolves legacy map ID")
	_check(catalog.get_city("paris").get("id") == "paris", "raw map query remains available at catalog boundary")
	_check(catalog.get_link("rail_paris_lille").get("link_id") == "rail_paris_lille", "link IDs remain map-owned IDs")
	_check(
		FileAccess.file_exists("res://data/world_map/regions.json")
		and FileAccess.file_exists("res://data/world_map/rail_segments.json"),
		"catalog reads existing map JSON instead of a second spatial dataset"
	)


func _test_topology_queries_are_deterministic() -> void:
	var world := _world()
	if world == null:
		return
	var link_ids: Array[String] = []
	for link: Dictionary in world.links_of_type(VNextSpatialCatalog.LINK_TYPE_RAIL):
		link_ids.append(str(link.get("link_id", "")))
	var sorted_ids: Array[String] = link_ids.duplicate()
	sorted_ids.sort()
	_equal(link_ids, sorted_ids, "rail topology query uses canonical link order")
	_equal(
		world.links_between("place:paris", "place:lille", VNextSpatialCatalog.LINK_TYPE_RAIL).size(),
		1,
		"rail endpoint query resolves stable place IDs"
	)
	_equal(
		world.links_between("rouen", "paris", VNextSpatialCatalog.LINK_TYPE_ROAD).size(),
		1,
		"road endpoint query is available"
	)
	_equal(
		world.links_between("port_le_havre", "port_london", VNextSpatialCatalog.LINK_TYPE_SHIPPING).size(),
		1,
		"sea endpoint query is available"
	)
	_check(
		world.neighboring_place_ids("paris", VNextSpatialCatalog.LINK_TYPE_RAIL).has("place:lille"),
		"neighbor query returns canonical place IDs"
	)


func _test_infrastructure_state_and_capacity_formula() -> void:
	var world := _world()
	if world == null:
		return
	var link_id: String = "rail_paris_lille"
	_check(world.set_nominal_capacity(link_id, 100), "nominal capacity accepts finite non-negative value")
	_equal(world.infrastructure_state(link_id).get("status"), "operational", "new link is operational")
	_equal(world.infrastructure_state(link_id).get("nominal_capacity"), 100.0, "nominal capacity is authoritative")
	_equal(world.infrastructure_state(link_id).get("effective_capacity"), 100.0, "operational effective capacity equals nominal")
	_equal(world.effective_capacity(link_id), 100.0, "direct effective-capacity query matches authoritative state")
	_check(world.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_DAMAGED), "damaged status mutation is legal")
	_equal(world.infrastructure_state(link_id).get("effective_capacity"), 50.0, "damaged status deterministically reduces capacity")
	_check(world.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "interrupted status mutation is legal")
	_equal(world.infrastructure_state(link_id).get("effective_capacity"), 0.0, "interrupted link has zero effective capacity")
	var before_invalid: Dictionary = world.infrastructure_state(link_id)
	_check(not world.set_infrastructure_status(link_id, "unknown_status"), "unknown infrastructure status is rejected")
	_equal(world.infrastructure_state(link_id), before_invalid, "rejected status mutation is transactional")
	_check(not world.set_nominal_capacity(link_id, -1), "negative nominal capacity is rejected")
	_check(not world.set_infrastructure_condition(link_id, INF), "infinite condition is rejected")
	_check(world.restore_infrastructure(link_id), "restoration returns link to service")
	_equal(world.infrastructure_state(link_id).get("status"), VNextInfrastructureLinkState.STATUS_RESTORED, "restoration uses explicit restored status")
	_equal(world.infrastructure_state(link_id).get("effective_capacity"), 100.0, "restoration recovers effective capacity")


func _test_shared_capacity_contention_and_rollover() -> void:
	var world := _world()
	if world == null:
		return
	var link_id: String = "rail_paris_lille"
	_check(world.set_nominal_capacity(link_id, 100), "contention fixture configures rail capacity")
	var first: Dictionary = _submit_legacy_capacity(world, "request_b", link_id, 0, 60)
	var second: Dictionary = _submit_legacy_capacity(world, "request_a", link_id, 0, 60)
	_check(bool(first.get("accepted", false)) and bool(second.get("accepted", false)), "same-hour fixture requests are accepted")
	_equal(world.reservation_result("request_a", link_id, 0).get("allocated_capacity"), 60.0, "canonical lower request ID receives first allocation")
	_equal(world.reservation_result("request_b", link_id, 0).get("allocated_capacity"), 40.0, "contention produces deterministic partial allocation")
	_equal(world.used_capacity(link_id), 100.0, "used capacity never exceeds effective capacity")
	_equal(world.remaining_capacity(link_id), 0.0, "remaining capacity is authoritative")
	_check(not _submit_legacy_capacity(world, "request_a", link_id, 0, 1).get("accepted", false), "duplicate request ID is rejected")
	_check(world.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "interruption can occur with active reservations")
	_equal(world.used_capacity(link_id), 0.0, "interruption removes usable allocation")
	_equal(world.remaining_capacity(link_id), 0.0, "zero-capacity behavior is explicit")
	_check(world.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_RESTORED), "restoration reopens the same hour")
	_equal(world.used_capacity(link_id), 100.0, "restoration deterministically recomputes allocations")
	_check(world.advance_hours(1), "hour boundary advances explicitly")
	_equal(world.current_hour(), 1, "capacity window rolls to next absolute hour")
	_equal(world.capacity_summary(link_id).get("reservations").size(), 0, "window rollover drops completed reservations")
	_check(not _submit_legacy_capacity(world, "old_window", link_id, 0, 1).get("accepted", false), "past-hour request is rejected")
	_check(_submit_legacy_capacity(world, "new_window", link_id, 1, 20).get("accepted", false), "current-hour request is accepted")


func _test_deterministic_request_permutation() -> void:
	var first := _world()
	var second := _world()
	if first == null or second == null:
		return
	_check(first.set_nominal_capacity("rail_paris_lille", 100), "permutation fixture configures first capacity")
	_check(second.set_nominal_capacity("rail_paris_lille", 100), "permutation fixture configures second capacity")
	_submit_legacy_capacity(first, "request_z", "rail_paris_lille", 0, 80)
	_submit_legacy_capacity(first, "request_a", "rail_paris_lille", 0, 80)
	_submit_legacy_capacity(second, "request_a", "rail_paris_lille", 0, 80)
	_submit_legacy_capacity(second, "request_z", "rail_paris_lille", 0, 80)
	_equal(first.snapshot(), second.snapshot(), "request insertion permutation does not change snapshot")
	_equal(first.capacity_summary("rail_paris_lille"), second.capacity_summary("rail_paris_lille"), "request insertion permutation does not change allocation")


func _test_batch_capacity_submission() -> void:
	var first := _world()
	var second := _world()
	if first == null or second == null:
		return
	_check(first.set_nominal_capacity("rail_paris_lille", 100), "batch fixture configures first capacity")
	_check(second.set_nominal_capacity("rail_paris_lille", 100), "batch fixture configures second capacity")
	var reverse_batch: Array[Dictionary] = [
		{"request_id": "request_b", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
		{"request_id": "request_a", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
	]
	var forward_batch: Array[Dictionary] = [
		{"request_id": "request_a", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
		{"request_id": "request_b", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
	]
	_check(first.request_capacity_batch(reverse_batch).get("accepted", false), "reverse batch is accepted transactionally")
	_check(second.request_capacity_batch(forward_batch).get("accepted", false), "forward batch is accepted transactionally")
	var final_batch: Dictionary = first.reservation_results_batch(reverse_batch)
	_check(final_batch.get("accepted", false), "batch final reservation query is accepted")
	_equal(((final_batch.get("results", {}) as Dictionary).get("request_a", {}) as Dictionary).get("allocated_capacity"), 60.0, "batch final query preserves canonical allocation")
	_equal(first.reservation_result("request_a", "rail_paris_lille", 0).get("allocated_capacity"), 60.0, "batch canonical lower ID gets first allocation")
	_equal(first.reservation_result("request_b", "rail_paris_lille", 0).get("allocated_capacity"), 40.0, "batch canonical higher ID gets partial allocation")
	_equal(first.capacity_summary("rail_paris_lille"), second.capacity_summary("rail_paris_lille"), "batch insertion permutations have identical final allocation")
	var before_invalid := first.snapshot()
	var invalid_batch: Array[Dictionary] = [
		{"request_id": "request_c", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 10.0},
		{"request_id": "request_c", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 10.0},
	]
	_check(not first.request_capacity_batch(invalid_batch).get("accepted", false), "duplicate batch request is rejected")
	_equal(first.snapshot(), before_invalid, "rejected batch leaves Spatial window unchanged")


func _test_territorial_mutation_and_projection() -> void:
	var world := _world()
	if world == null:
		return
	var initial: Dictionary = world.get_territorial_facts("northern_industrial_belt")
	_equal(initial.get("sovereign_owner_id"), "country_fra", "region starts with legacy sovereign owner")
	_equal(initial.get("military_controller_id"), "country_fra", "region starts with legacy military controller")
	_check(world.set_sovereign_owner("northern_industrial_belt", "british_empire"), "sovereign owner mutation uses explicit API")
	_check(world.set_military_controller("northern_industrial_belt", "british_empire"), "military controller mutation uses explicit API")
	_equal(world.get_territorial_facts("northern_industrial_belt").get("sovereign_owner_id"), "british_empire", "owner query reflects authoritative mutation")
	var before_invalid: Dictionary = world.get_territorial_facts("northern_industrial_belt")
	_check(not world.set_sovereign_owner("northern_industrial_belt", "country:not_real"), "unknown owner is rejected")
	_equal(world.get_territorial_facts("northern_industrial_belt"), before_invalid, "invalid owner leaves territorial state unchanged")
	_check(not world.set_administrative_parent("northern_industrial_belt", "northern_industrial_belt"), "self administrative parent is rejected")
	_check(world.set_administrative_parent("northern_industrial_belt", "paris_basin"), "region administrative parent mutation is legal")
	_check(not world.set_administrative_parent("paris_basin", "northern_industrial_belt"), "administrative parent cycle is rejected")
	_check(world.set_administrative_parent("northern_industrial_belt", ""), "administrative parent can be cleared at boundary")

	var projection := VNextSpatialMapProjection.new()
	var before_projection: Dictionary = projection.project(world)
	var before_link: Dictionary = _record_by_id(before_projection.get("infrastructure", []), "rail_paris_lille")
	_equal(before_link.get("status"), "operational", "projection exposes current infrastructure status")
	_check(world.set_infrastructure_status("rail_paris_lille", VNextInfrastructureLinkState.STATUS_INTERRUPTED), "projection fixture interrupts rail link")
	var after_projection: Dictionary = projection.project(world)
	var after_link: Dictionary = _record_by_id(after_projection.get("infrastructure", []), "rail_paris_lille")
	_equal(after_link.get("status"), VNextInfrastructureLinkState.STATUS_INTERRUPTED, "projection synchronizes interrupted rail status")
	var region_projection: Dictionary = _record_by_id(after_projection.get("regions", []), "northern_industrial_belt")
	_equal(region_projection.get("sovereign_owner_id"), "british_empire", "projection exposes current region owner")
	_equal(after_projection.get("ports").size(), 8, "projection includes port status records")
	_check(after_projection.has("important_nodes") and after_projection.has("important_links"), "projection includes important nodes and links")


func _test_snapshot_restore_and_transactional_rejection() -> void:
	var source := _world()
	var target := _world()
	if source == null or target == null:
		return
	_check(source.set_nominal_capacity("rail_paris_lille", 100), "snapshot fixture configures capacity")
	_check(source.set_sovereign_owner("northern_industrial_belt", "british_empire"), "snapshot fixture changes owner")
	_check(source.set_military_controller("northern_industrial_belt", "british_empire"), "snapshot fixture changes controller")
	_check(_submit_legacy_capacity(source, "snapshot_request", "rail_paris_lille", 0, 70).get("accepted", false), "snapshot fixture creates reservation")
	var saved: Dictionary = source.snapshot()
	_check(target.restore(saved), "complete spatial snapshot restores")
	_equal(target.snapshot(), saved, "snapshot restore preserves infrastructure, territory and capacity")
	var json_parser := JSON.new()
	_check(json_parser.parse(JSON.stringify(saved)) == OK, "spatial snapshot serializes as JSON")
	if json_parser.data is Dictionary:
		var json_target := _world()
		_check(json_target.restore(json_parser.data as Dictionary), "JSON-parsed spatial snapshot restores")
		_equal(json_target.snapshot(), saved, "JSON round trip preserves spatial state")

	var malformed_cases: Array[Dictionary] = []
	var unknown_place: Dictionary = saved.duplicate(true)
	var unknown_place_territories: Array = unknown_place["territories"]
	unknown_place_territories[0]["entity_id"] = "missing_place"
	malformed_cases.append({"snapshot": unknown_place, "label": "unknown place"})
	var unknown_link: Dictionary = saved.duplicate(true)
	var unknown_link_infra: Array = unknown_link["infrastructure"]
	unknown_link_infra[0]["link_id"] = "rail_missing"
	malformed_cases.append({"snapshot": unknown_link, "label": "unknown link"})
	var invalid_owner: Dictionary = saved.duplicate(true)
	(invalid_owner["territories"] as Array)[0]["sovereign_owner_id"] = "country:not_real"
	malformed_cases.append({"snapshot": invalid_owner, "label": "invalid owner"})
	var invalid_status: Dictionary = saved.duplicate(true)
	(invalid_status["infrastructure"] as Array)[0]["status"] = "not_a_status"
	malformed_cases.append({"snapshot": invalid_status, "label": "invalid infrastructure status"})
	var negative_capacity: Dictionary = saved.duplicate(true)
	(negative_capacity["infrastructure"] as Array)[0]["nominal_capacity"] = -1.0
	malformed_cases.append({"snapshot": negative_capacity, "label": "negative capacity"})
	var nonfinite_capacity: Dictionary = saved.duplicate(true)
	(nonfinite_capacity["infrastructure"] as Array)[0]["nominal_capacity"] = NAN
	malformed_cases.append({"snapshot": nonfinite_capacity, "label": "NaN capacity"})
	var used_over_effective: Dictionary = saved.duplicate(true)
	var usage_records: Array = (used_over_effective["capacity_window"] as Dictionary)["link_usage"]
	for usage: Dictionary in usage_records:
		if usage.get("link_id") == "rail_paris_lille":
			usage["used_capacity"] = 101.0
	malformed_cases.append({"snapshot": used_over_effective, "label": "used over effective"})
	var duplicate_reservation: Dictionary = saved.duplicate(true)
	var reservation_records: Array = (duplicate_reservation["capacity_window"] as Dictionary)["reservations"]
	reservation_records.append(reservation_records[0].duplicate(true))
	malformed_cases.append({"snapshot": duplicate_reservation, "label": "duplicate reservation"})
	var orphan_reservation: Dictionary = saved.duplicate(true)
	(orphan_reservation["capacity_window"] as Dictionary)["reservations"][0]["link_id"] = "rail_missing"
	malformed_cases.append({"snapshot": orphan_reservation, "label": "orphan reservation"})
	var wrong_window: Dictionary = saved.duplicate(true)
	(wrong_window["capacity_window"] as Dictionary)["reservations"][0]["window_hour"] = 99
	malformed_cases.append({"snapshot": wrong_window, "label": "wrong reservation window"})
	var malformed_collection: Dictionary = saved.duplicate(true)
	var untyped_territories: Array = []
	for item: Variant in malformed_collection["territories"] as Array:
		untyped_territories.append(item)
	untyped_territories.append(42)
	malformed_collection["territories"] = untyped_territories
	malformed_cases.append({"snapshot": malformed_collection, "label": "malformed collection item"})

	for case: Dictionary in malformed_cases:
		_expect_restore_failure(target, case["snapshot"] as Dictionary, str(case["label"]))


func _test_time_partition_and_bounded_state() -> void:
	var partitioned := _world()
	var jumped := _world()
	if partitioned == null or jumped == null:
		return
	for _step: int in range(24):
		_check(partitioned.advance_hours(1), "one-hour partition advances")
	_check(jumped.advance_hours(24), "24-hour jump advances explicit boundaries")
	_equal(partitioned.current_hour(), 24, "partitioned time reaches hour 24")
	_equal(jumped.current_hour(), 24, "large time jump reaches same hour")
	_equal(partitioned.snapshot(), jumped.snapshot(), "24x1 hour equals 1x24 hour state")
	var snapshot: Dictionary = partitioned.snapshot()
	_check(snapshot.get("infrastructure").size() == 15, "persistent infrastructure state remains one record per link")
	_check(snapshot.get("territories").size() == 49, "persistent territorial state remains one record per place")
	var capacity_window: Dictionary = snapshot.get("capacity_window")
	_check(capacity_window.get("reservations").size() == 0, "completed windows do not grow persistent reservation history")
	_check(not JSON.stringify(snapshot).contains("health"), "state model does not substitute a universal health field")


func _expect_restore_failure(world: VNextSpatialWorld, malformed: Dictionary, label: String) -> void:
	var before: Dictionary = world.snapshot()
	_check(not world.restore(malformed), "%s snapshot is rejected" % label)
	_equal(world.snapshot(), before, "%s restore is transactional" % label)


func _submit_legacy_capacity(
	world: VNextSpatialWorld,
	request_id: String,
	link_id: String,
	window_hour: int,
	demand: Variant
) -> Dictionary:
	return world.request_capacity_batch([{
		"request_id": request_id,
		"link_id": link_id,
		"window_hour": window_hour,
		"demand": demand,
	}])


func _catalog() -> VNextSpatialCatalog:
	var catalog := VNextSpatialCatalog.new()
	_check(catalog.load_legacy_world_map(), "spatial catalog fixture loads")
	return catalog


func _world() -> VNextSpatialWorld:
	var catalog := _catalog()
	if catalog == null or not catalog.is_loaded():
		return null
	var world := VNextSpatialWorld.create(catalog)
	_check(world != null and world.is_valid(), "spatial world fixture initializes")
	return world


func _record_by_id(records_value: Variant, record_id: String) -> Dictionary:
	if typeof(records_value) != TYPE_ARRAY:
		return {}
	for raw_record: Variant in records_value as Array:
		if typeof(raw_record) == TYPE_DICTIONARY and str((raw_record as Dictionary).get("id", "")) == record_id:
			return raw_record as Dictionary
	return {}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
