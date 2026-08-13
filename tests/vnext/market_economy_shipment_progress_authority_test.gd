extends SceneTree

const HOURS_PER_DAY: int = 24

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy: VNextMarketEconomy = VNextMarketEconomy.new()
	_check(economy.configure_1900(), "shipment authority Economy configures")
	if economy.catalog == null:
		_finish()
		return

	var spatial_catalog: VNextSpatialCatalog = VNextSpatialCatalog.new()
	_check(spatial_catalog.load_legacy_world_map(), "shipment authority Spatial catalog loads")
	var spatial_world: VNextSpatialWorld = VNextSpatialWorld.create(spatial_catalog)
	_check(spatial_world != null and spatial_world.is_valid(), "shipment authority Spatial world configures")
	if spatial_world == null or not spatial_world.is_valid():
		_finish()
		return

	var link_ids: Array[String] = spatial_catalog.link_ids()
	_check(not link_ids.is_empty(), "shipment authority fixture has a Spatial link")
	if link_ids.is_empty():
		_finish()
		return
	var shared_link_id: String = link_ids[0]
	_check(spatial_world.set_nominal_capacity(shared_link_id, 7000.0), "shipment authority capacity is configured")

	var route_mapping: Dictionary = {}
	for edge: Dictionary in economy.catalog.transport_edges:
		route_mapping[str(edge.get("edge_id", ""))] = [shared_link_id]
	_check(
		economy.attach_spatial_transport_authority(spatial_world, route_mapping, 0),
		"Economy attaches to Spatial hour zero"
	)
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(
			economy.set_fixture_route_budget(str(edge.get("edge_id", "")), 0.0),
			"fixture route budget is disabled while Spatial owns transport"
		)

	var origin_one: String = economy.catalog.region_market_id("region:loran_southridge")
	var destination_one: String = economy.catalog.region_market_id("region:loran_riverback")
	var origin_two: String = economy.catalog.region_market_id("region:loran_dawnbay")
	var destination_two: String = economy.catalog.region_market_id("region:loran_forgeplain")
	_check(economy.set_region_inventory(origin_one, "coal", 200000.0), "slow shipment source is prepared")
	_check(economy.set_region_inventory(destination_one, "coal", 0.0), "slow shipment destination is depleted")
	_check(economy.set_region_inventory(origin_two, "coal", 200000.0), "concurrent shipment source is prepared")
	_check(economy.set_region_inventory(destination_two, "coal", 0.0), "concurrent shipment destination is depleted")
	_check(bool(economy.settle_day(0).get("success", false)), "shipment authority dispatch day settles")
	_check(spatial_world.current_hour() == 0, "dispatch leaves authoritative Spatial time at hour zero")

	var active_shipments: Array[Dictionary] = _active_shipments(economy)
	_check(active_shipments.size() >= 2, "fixture creates concurrent active shipments")
	var slow_shipment: Dictionary = _shipment_with_latest_arrival(active_shipments)
	var fast_shipment: Dictionary = _shipment_with_earliest_arrival(active_shipments)
	var slow_id: String = str(slow_shipment.get("shipment_id", ""))
	var fast_id: String = str(fast_shipment.get("shipment_id", ""))
	var slow_arrival_day: int = int(slow_shipment.get("arrival_day", -1))
	var fast_arrival_day: int = int(fast_shipment.get("arrival_day", -1))
	_check(not slow_id.is_empty() and not fast_id.is_empty(), "concurrent shipment IDs are stable")
	_check(slow_id != fast_id, "concurrent fixture selects two distinct shipments")
	_check(slow_arrival_day > fast_arrival_day, "concurrent fixture has distinct arrival boundaries")
	_check(slow_arrival_day > 1, "slow shipment remains in transit after one day")
	_check(
		int(slow_shipment.get("arrival_day", -1)) == int(slow_shipment.get("dispatch_day", -1)) + maxi(
			1, int(ceil(float(slow_shipment.get("duration_hours", 0)) / float(HOURS_PER_DAY)))
		),
		"slow shipment arrival uses its existing dispatch and travel-duration contract"
	)
	if slow_id.is_empty() or fast_id.is_empty() or slow_arrival_day <= fast_arrival_day or slow_arrival_day <= 1:
		_finish()
		return

	_test_future_progress_is_atomic(economy, spatial_world, slow_id)

	var slow_before_day_zero: Dictionary = _shipment_by_id(economy.snapshot(), slow_id)
	var slow_total_units: float = float(slow_before_day_zero.get("total_units", 0.0))
	var slow_day_zero_partial: float = slow_total_units * 0.25
	var day_zero_result: Dictionary = economy.apply_shipment_progress(slow_id, slow_day_zero_partial, 0)
	_check(bool(day_zero_result.get("success", false)), "day-zero partial shipment progress remains valid")
	_check(
		is_equal_approx(
			float(_shipment_by_id(economy.snapshot(), slow_id).get("units", 0.0)),
			slow_total_units - slow_day_zero_partial
		),
		"day-zero partial progress preserves outstanding cargo"
	)

	_check(spatial_world.advance_to_hour(HOURS_PER_DAY), "Spatial advances legitimately to day one")
	var slow_before_day_one: Dictionary = _shipment_by_id(economy.snapshot(), slow_id)
	var slow_day_one_partial: float = float(slow_before_day_one.get("units", 0.0)) * 0.25
	var day_one_result: Dictionary = economy.apply_shipment_progress(slow_id, slow_day_one_partial, 1)
	_check(bool(day_one_result.get("success", false)), "current Spatial-time partial progress succeeds")

	var pre_arrival_before: String = JSON.stringify(economy.snapshot())
	var pre_arrival_spatial_before: String = JSON.stringify(spatial_world.snapshot())
	var slow_remaining_before: float = float(_shipment_by_id(economy.snapshot(), slow_id).get("units", 0.0))
	var pre_arrival_result: Dictionary = economy.apply_shipment_progress(slow_id, slow_remaining_before, 1)
	_check(not bool(pre_arrival_result.get("success", false)), "pre-arrival final delivery fails closed")
	_check(str(pre_arrival_result.get("code", "")) == "shipment_arrival_not_ready", "pre-arrival failure is explicit")
	_check(JSON.stringify(economy.snapshot()) == pre_arrival_before, "pre-arrival rejection is atomic in Economy")
	_check(JSON.stringify(spatial_world.snapshot()) == pre_arrival_spatial_before, "pre-arrival rejection preserves Spatial attribution")
	_check(_shipment_by_id(economy.snapshot(), slow_id).size() > 0, "pre-arrival rejection keeps shipment active")

	var saved_economy: Dictionary = JSON.parse_string(JSON.stringify(economy.snapshot())) as Dictionary
	var saved_spatial: Dictionary = JSON.parse_string(JSON.stringify(spatial_world.snapshot())) as Dictionary
	var restored_economy: VNextMarketEconomy = VNextMarketEconomy.new()
	_check(restored_economy.configure_1900(), "restored shipment Economy configures")
	var restored_catalog: VNextSpatialCatalog = VNextSpatialCatalog.new()
	_check(restored_catalog.load_legacy_world_map(), "restored shipment Spatial catalog loads")
	var restored_spatial: VNextSpatialWorld = VNextSpatialWorld.create(restored_catalog)
	_check(restored_spatial != null and restored_spatial.is_valid(), "restored shipment Spatial world configures")
	if restored_spatial == null or not restored_spatial.is_valid():
		_finish()
		return
	_check(restored_spatial.restore(saved_spatial), "in-transit Spatial snapshot restores")
	_check(restored_economy.restore(saved_economy), "in-transit Economy snapshot restores")
	_check(spatial_world.restore(saved_spatial), "original Spatial snapshot restores before replay")
	_check(economy.restore(saved_economy), "original Economy snapshot restores before replay")
	_check(
		restored_economy.attach_spatial_transport_authority(
			restored_spatial, route_mapping, restored_spatial.current_hour()
		),
		"restored Economy reattaches the same Spatial authority"
	)
	_equal(JSON.stringify(restored_economy.snapshot()), JSON.stringify(economy.snapshot()), "in-transit restore is deterministic before continuation")
	_equal(JSON.stringify(restored_spatial.snapshot()), JSON.stringify(spatial_world.snapshot()), "Spatial restore is deterministic before continuation")

	var restored_future_before: String = JSON.stringify(restored_economy.snapshot())
	var restored_future_result: Dictionary = restored_economy.apply_shipment_progress(slow_id, slow_remaining_before, 999)
	_check(not bool(restored_future_result.get("success", false)), "restored future-time bypass remains rejected")
	_check(JSON.stringify(restored_economy.snapshot()) == restored_future_before, "restored future rejection remains atomic")

	var fast_remaining: float = float(_shipment_by_id(economy.snapshot(), fast_id).get("units", 0.0))
	var slow_before_fast_delivery: Dictionary = _shipment_by_id(economy.snapshot(), slow_id)
	var restored_slow_before_fast_delivery: Dictionary = _shipment_by_id(restored_economy.snapshot(), slow_id)
	var fast_result: Dictionary = economy.apply_shipment_progress(fast_id, fast_remaining, 1)
	var restored_fast_result: Dictionary = restored_economy.apply_shipment_progress(fast_id, fast_remaining, 1)
	_check(bool(fast_result.get("success", false)), "eligible concurrent shipment delivers at its boundary")
	_check(bool(restored_fast_result.get("success", false)), "restored eligible concurrent shipment delivers")
	_check(
		is_equal_approx(
			float(_shipment_by_id(economy.snapshot(), slow_id).get("units", 0.0)),
			float(slow_before_fast_delivery.get("units", 0.0))
		),
		"one eligible shipment cannot advance another shipment"
	)
	_check(
		is_equal_approx(
			float(_shipment_by_id(restored_economy.snapshot(), slow_id).get("units", 0.0)),
			float(restored_slow_before_fast_delivery.get("units", 0.0))
		),
		"restored concurrent shipment remains independently bounded"
	)

	var fast_again: Dictionary = economy.apply_shipment_progress(fast_id, 0.000001, 1)
	_check(not bool(fast_again.get("success", false)), "completed shipment cannot deliver twice")

	var slow_arrival_hour: int = slow_arrival_day * HOURS_PER_DAY
	_check(spatial_world.advance_to_hour(slow_arrival_hour), "Spatial advances to the slow shipment arrival boundary")
	_check(restored_spatial.advance_to_hour(slow_arrival_hour), "restored Spatial advances to the same arrival boundary")
	var slow_remaining_at_arrival: float = float(_shipment_by_id(economy.snapshot(), slow_id).get("units", 0.0))
	var restored_slow_remaining_at_arrival: float = float(_shipment_by_id(restored_economy.snapshot(), slow_id).get("units", 0.0))
	var arrival_result: Dictionary = economy.apply_shipment_progress(slow_id, slow_remaining_at_arrival, slow_arrival_day)
	var restored_arrival_result: Dictionary = restored_economy.apply_shipment_progress(
		slow_id, restored_slow_remaining_at_arrival, slow_arrival_day
	)
	_check(bool(arrival_result.get("success", false)), "final delivery succeeds at the legitimate arrival boundary")
	_check(bool(restored_arrival_result.get("success", false)), "restored final delivery succeeds at the same boundary")
	_check(_shipment_by_id(economy.snapshot(), slow_id).is_empty(), "arrival removes the completed shipment exactly once")
	_check(_shipment_by_id(restored_economy.snapshot(), slow_id).is_empty(), "restored arrival removes the completed shipment exactly once")
	_equal(JSON.stringify(restored_economy.snapshot()), JSON.stringify(economy.snapshot()), "shipment progress restore continuation is deterministic")
	_equal(JSON.stringify(restored_spatial.snapshot()), JSON.stringify(spatial_world.snapshot()), "Spatial continuation remains deterministic")
	_check(economy.validate_integrity() and restored_economy.validate_integrity(), "shipment authority repair preserves Economy conservation")
	_finish()


func _test_future_progress_is_atomic(
	economy: VNextMarketEconomy, spatial_world: VNextSpatialWorld, shipment_id: String
) -> void:
	var before_economy: String = JSON.stringify(economy.snapshot())
	var before_spatial: String = JSON.stringify(spatial_world.snapshot())
	var before_shipment: Dictionary = _shipment_by_id(economy.snapshot(), shipment_id)
	var destination_id: String = str(before_shipment.get("destination_market_id", ""))
	var commodity_id: String = str(before_shipment.get("commodity_id", ""))
	var before_inventory: float = economy.inventory_units(destination_id, commodity_id)
	var before_in_transit: float = float(
		economy.commodity_snapshot(destination_id, commodity_id).get("in_transit_import_units", 0.0)
	)
	var result: Dictionary = economy.apply_shipment_progress(
		shipment_id, float(before_shipment.get("units", 0.0)), 999
	)
	_check(not bool(result.get("success", false)), "future shipment progress is explicitly rejected")
	_check(str(result.get("code", "")) == "spatial_time_not_ready", "future-time rejection is explicit")
	_check(economy.inventory_units(destination_id, commodity_id) == before_inventory, "future rejection preserves destination inventory")
	_check(JSON.stringify(economy.snapshot()) == before_economy, "future rejection preserves all Economy snapshot state")
	_check(JSON.stringify(spatial_world.snapshot()) == before_spatial, "future rejection preserves Spatial capacity attribution")
	_check(_shipment_by_id(economy.snapshot(), shipment_id).size() > 0, "future rejection keeps shipment active")
	_check(
		is_equal_approx(
			float(_shipment_by_id(economy.snapshot(), shipment_id).get("units", 0.0)),
			float(before_shipment.get("units", 0.0))
		),
		"future rejection preserves remaining cargo"
	)
	_check(
		is_equal_approx(
			float(economy.commodity_snapshot(destination_id, commodity_id).get("in_transit_import_units", 0.0)),
			before_in_transit
		),
		"future rejection preserves in-transit imports"
	)


func _active_shipments(economy: VNextMarketEconomy) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for shipment: Dictionary in economy.shipments:
		if str(shipment.get("status", "")) == "in_transit" and float(shipment.get("units", 0.0)) > 0.000001:
			result.append(shipment.duplicate(true))
	return result


func _shipment_with_latest_arrival(shipments_value: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for shipment: Dictionary in shipments_value:
		if result.is_empty() or int(shipment.get("arrival_day", -1)) > int(result.get("arrival_day", -1)):
			result = shipment
	return result


func _shipment_with_earliest_arrival(shipments_value: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for shipment: Dictionary in shipments_value:
		if result.is_empty() or int(shipment.get("arrival_day", 999999999)) < int(result.get("arrival_day", 999999999)):
			result = shipment
	return result


func _shipment_by_id(snapshot_value: Dictionary, shipment_id: String) -> Dictionary:
	for raw_shipment: Variant in snapshot_value.get("shipments", []) as Array:
		if raw_shipment is Dictionary:
			var shipment: Dictionary = raw_shipment as Dictionary
			if str(shipment.get("shipment_id", "")) == shipment_id:
				return shipment
	return {}


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
	print("VNext market economy shipment progress authority: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)
