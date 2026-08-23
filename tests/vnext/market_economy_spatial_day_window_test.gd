extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy: VNextMarketEconomy = VNextMarketEconomy.new()
	_check(economy.configure_1900(), "Economy configures for multi-day Spatial window coverage")
	if economy.catalog == null:
		_finish()
		return
	var spatial_catalog := VNextSpatialCatalog.new()
	_check(spatial_catalog.load_legacy_world_map(), "Spatial catalog loads for multi-day window coverage")
	var spatial_world: VNextSpatialWorld = VNextSpatialWorld.create(spatial_catalog)
	_check(spatial_world != null and spatial_world.is_valid(), "Spatial world configures as the physical authority")
	if spatial_world == null or not spatial_world.is_valid():
		_finish()
		return
	var link_ids: Array[String] = spatial_catalog.link_ids()
	_check(not link_ids.is_empty(), "Spatial exposes a link for multi-day contention")
	if link_ids.is_empty():
		_finish()
		return
	var shared_link_id: String = link_ids[0]
	_check(spatial_world.set_nominal_capacity(shared_link_id, 7000.0), "Spatial capacity is configured once at the authority")
	var route_mapping: Dictionary = {}
	for edge: Dictionary in economy.catalog.transport_edges:
		route_mapping[str(edge.get("edge_id", ""))] = [shared_link_id]
	_check(
		economy.attach_spatial_transport_authority(spatial_world, route_mapping, 0),
		"Economy attaches its demand adapter to Spatial hour zero"
	)
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(economy.set_fixture_route_budget(str(edge.get("edge_id", "")), 0.0), "fixture capacity is disabled under Spatial authority")
	var origin: String = economy.catalog.region_market_id("region:loran_southridge")
	var destination: String = economy.catalog.region_market_id("region:loran_riverback")
	var second_origin: String = economy.catalog.region_market_id("region:loran_dawnbay")
	var second_destination: String = economy.catalog.region_market_id("region:loran_forgeplain")
	_check(economy.set_region_inventory(origin, "coal", 200000.0), "multi-day source inventory is prepared")
	_check(economy.set_region_inventory(destination, "coal", 0.0), "multi-day destination demand is prepared")
	_check(economy.set_region_inventory(second_origin, "coal", 200000.0), "concurrent source inventory is prepared")
	_check(economy.set_region_inventory(second_destination, "coal", 0.0), "concurrent destination demand is prepared")
	_check(bool(economy.settle_day(0).get("success", false)), "day zero submits all applicable demand")
	var day0_summary: Dictionary = spatial_world.capacity_summary(shared_link_id)
	var day0_reservations: Array = day0_summary.get("reservations", []) as Array
	_check(spatial_world.current_hour() == 0, "day zero remains in the attached Spatial hour")
	_check(day0_reservations.size() > 0, "day zero retains active Spatial reservations")
	var day0_request_ids: Array[String] = _request_ids(day0_reservations)
	_check(_sum_reservation_demand(day0_reservations) > 50.0, "day zero retains demand above physical capacity before final allocation")
	_check(_active_spatial_shipment_count(economy) > 1, "day zero creates concurrent outstanding Economy shipments")
	var day0_shipment: Dictionary = _first_active_spatial_shipment(economy)
	var day0_shipment_id: String = str(day0_shipment.get("shipment_id", ""))
	var day0_units: float = float(day0_shipment.get("units", 0.0))
	_check(not day0_shipment_id.is_empty() and day0_units > 0.0, "day zero exposes an outstanding shipment for partial progress")
	var partial_progress: Dictionary = economy.apply_shipment_progress(day0_shipment_id, day0_units * 0.5, 0)
	_check(bool(partial_progress.get("success", false)), "partial multi-day shipment progress is accepted")
	_check(_active_spatial_shipment_count(economy) > 0, "partial progress keeps unresolved shipment state")
	_check(
		float(economy.commodity_snapshot(destination, "coal").get("in_transit_import_units", 0.0)) > 0.0,
		"partial progress preserves authoritative outstanding in-transit units"
	)

	_check(
		bool(_submit_legacy_capacity(spatial_world, "military:day0:safety", shared_link_id, 0, 10.0).get("accepted", false)),
		"other-domain demand exists in the day zero Spatial window"
	)
	var before_stale_attempt: String = JSON.stringify(spatial_world.capacity_summary(shared_link_id))
	var economy_before_stale_attempt: String = JSON.stringify(economy.snapshot())
	var stale_result: Dictionary = economy.settle_day(1)
	_check(not bool(stale_result.get("success", false)), "day one fails closed while shared Spatial time is still day zero")
	_check(str(stale_result.get("code", "")) == "spatial_window_not_ready", "stale-window failure is explicit")
	_check(JSON.stringify(spatial_world.capacity_summary(shared_link_id)) == before_stale_attempt, "stale-window failure preserves other-domain reservations")
	_check(JSON.stringify(economy.snapshot()) == economy_before_stale_attempt, "stale-window failure preserves Economy market state")

	_check(spatial_world.advance_to_hour(24), "shared time authority advances Spatial to day one")
	_check(spatial_world.current_hour() == 24, "day one uses the externally selected absolute window")
	_check(
		bool(_submit_legacy_capacity(spatial_world, "military:day1:safety", shared_link_id, 24, 10.0).get("accepted", false)),
		"other-domain demand is submitted before Economy in the same day-one window"
	)
	_check(bool(economy.settle_day(1).get("success", false)), "day one submits into the externally selected Spatial window")
	var day1_summary: Dictionary = spatial_world.capacity_summary(shared_link_id)
	var day1_reservations: Array = day1_summary.get("reservations", []) as Array
	_check(day1_reservations.size() > 0, "day one receives a fresh Spatial reservation set")
	for raw_reservation: Variant in day1_reservations:
		if raw_reservation is Dictionary:
			var reservation: Dictionary = raw_reservation as Dictionary
			_check(int(reservation.get("window_hour", -1)) == 24, "day one reservations use the new absolute window")
			_check(not day0_request_ids.has(str(reservation.get("request_id", ""))), "day zero reservations do not leak into day one")
	_check(_contains_request(day1_reservations, "military:day1:safety"), "Military demand remains in the shared final-allocation set")
	var military_final: Dictionary = spatial_world.reservation_result("military:day1:safety", shared_link_id, 24)
	_check(bool(military_final.get("accepted", false)), "Military reads the final shared-window allocation")
	_check(
		_is_reservation_allocation(day1_reservations, "military:day1:safety", float(military_final.get("allocated_capacity", -1.0))),
		"final allocation ordering is observed after the complete Economy batch"
	)
	_check(_active_spatial_shipment_count(economy) > 0, "day one preserves unresolved shipments across the tick")

	var saved_economy: Dictionary = JSON.parse_string(JSON.stringify(economy.snapshot())) as Dictionary
	var saved_spatial: Dictionary = JSON.parse_string(JSON.stringify(spatial_world.snapshot())) as Dictionary
	var restored_economy: VNextMarketEconomy = VNextMarketEconomy.new()
	var restored_catalog := VNextSpatialCatalog.new()
	_check(restored_economy.configure_1900(), "restored Economy configures")
	_check(restored_catalog.load_legacy_world_map(), "restored Spatial catalog loads")
	var restored_spatial: VNextSpatialWorld = VNextSpatialWorld.create(restored_catalog)
	_check(restored_spatial != null and restored_spatial.is_valid(), "restored Spatial world configures")
	if restored_spatial == null or not restored_spatial.is_valid():
		_finish()
		return
	_check(restored_spatial.restore(saved_spatial), "Spatial active window restores mid-transit")
	_check(restored_economy.restore(saved_economy), "Economy outstanding shipments restore mid-transit")
	_check(spatial_world.restore(saved_spatial), "original Spatial snapshot restores before replay")
	_check(economy.restore(saved_economy), "original Economy snapshot restores before replay")
	_check(
		restored_economy.attach_spatial_transport_authority(
			restored_spatial, route_mapping, restored_spatial.current_hour()
		),
		"restored Economy reattaches the same Spatial authority"
	)
	_check(
		economy.attach_spatial_transport_authority(
			spatial_world, route_mapping, spatial_world.current_hour()
		),
		"original Economy reattaches the same Spatial authority"
	)
	_check(spatial_world.advance_to_hour(48), "shared time authority advances original Spatial to day two")
	_check(restored_spatial.advance_to_hour(48), "shared time authority advances restored Spatial to day two")
	_check(bool(economy.settle_day(2).get("success", false)), "original continuation advances to day two")
	_check(bool(restored_economy.settle_day(2).get("success", false)), "restored continuation advances to day two")
	_check(spatial_world.advance_to_hour(72), "shared time authority advances original Spatial to day three")
	_check(restored_spatial.advance_to_hour(72), "shared time authority advances restored Spatial to day three")
	_check(bool(economy.settle_day(3).get("success", false)), "original continuation advances to day three")
	_check(bool(restored_economy.settle_day(3).get("success", false)), "restored continuation advances to day three")
	_equal(JSON.stringify(economy.snapshot()), JSON.stringify(restored_economy.snapshot()), "Economy continuation is deterministic after mid-transit restore")
	_equal(JSON.stringify(spatial_world.snapshot()), JSON.stringify(restored_spatial.snapshot()), "Spatial continuation is deterministic after mid-transit restore")
	_check(economy.validate_integrity() and restored_economy.validate_integrity(), "multi-day Spatial integration preserves physical conservation")
	_finish()


func _request_ids(reservations: Array) -> Array[String]:
	var request_ids: Array[String] = []
	for raw_reservation: Variant in reservations:
		if raw_reservation is Dictionary:
			request_ids.append(str((raw_reservation as Dictionary).get("request_id", "")))
	return request_ids


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


func _sum_reservation_demand(reservations: Array) -> float:
	var total: float = 0.0
	for raw_reservation: Variant in reservations:
		if raw_reservation is Dictionary:
			total += float((raw_reservation as Dictionary).get("demand", 0.0))
	return total


func _active_spatial_shipment_count(economy: VNextMarketEconomy) -> int:
	var count: int = 0
	for shipment: Dictionary in economy.shipments:
		if shipment.has("spatial_allocation_units") and str(shipment.get("status", "")) == "in_transit":
			count += 1
	return count


func _first_active_spatial_shipment(economy: VNextMarketEconomy) -> Dictionary:
	for shipment: Dictionary in economy.shipments:
		if shipment.has("spatial_allocation_units") and str(shipment.get("status", "")) == "in_transit":
			return shipment
	return {}


func _contains_request(reservations: Array, request_id: String) -> bool:
	for raw_reservation: Variant in reservations:
		if raw_reservation is Dictionary and str((raw_reservation as Dictionary).get("request_id", "")) == request_id:
			return true
	return false


func _is_reservation_allocation(reservations: Array, request_id: String, expected: float) -> bool:
	for raw_reservation: Variant in reservations:
		if raw_reservation is Dictionary and str((raw_reservation as Dictionary).get("request_id", "")) == request_id:
			return is_equal_approx(float((raw_reservation as Dictionary).get("allocated_capacity", -1.0)), expected)
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: String, expected: String, label: String) -> void:
	_check(actual == expected, label)


func _finish() -> void:
	print("VNext market economy Spatial day-window restore: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)
