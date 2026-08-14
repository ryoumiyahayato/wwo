extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy: VNextMarketEconomy = VNextMarketEconomy.new()
	_check(economy.configure_1900(), "Economy configures before Spatial integration")
	if economy.catalog == null:
		_finish()
		return
	var spatial_catalog := VNextSpatialCatalog.new()
	_check(spatial_catalog.load_legacy_world_map(), "Spatial catalog loads the official legacy map")
	var spatial_world: VNextSpatialWorld = VNextSpatialWorld.create(spatial_catalog)
	_check(spatial_world != null and spatial_world.is_valid(), "Spatial world owns the integration authority")
	if spatial_world == null or not spatial_world.is_valid():
		_finish()
		return
	var link_ids: Array[String] = spatial_catalog.link_ids()
	_check(not link_ids.is_empty(), "Spatial catalog exposes physical links")
	if link_ids.is_empty():
		_finish()
		return
	var shared_link_id: String = link_ids[0]
	_check(spatial_world.set_nominal_capacity(shared_link_id, 50.0), "Spatial link capacity is configured at the authority")
	var route_mapping: Dictionary = {}
	for edge: Dictionary in economy.catalog.transport_edges:
		route_mapping[str(edge.get("edge_id", ""))] = [shared_link_id]
	var incomplete_mapping: Dictionary = route_mapping.duplicate(true)
	if not economy.catalog.transport_edges.is_empty():
		incomplete_mapping.erase(str((economy.catalog.transport_edges[0] as Dictionary).get("edge_id", "")))
	_check(not economy.attach_spatial_transport_authority(spatial_world, incomplete_mapping, 0), "incomplete route mapping fails closed")
	_check(economy.attach_spatial_transport_authority(spatial_world, route_mapping, 0), "Economy attaches route demand to Spatial links")
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(economy.set_fixture_route_budget(str(edge.get("edge_id", "")), 0.0), "fixture budget is closed while Spatial owns capacity")
	var origin: String = economy.catalog.region_market_id("region:loran_southridge")
	var destination: String = economy.catalog.region_market_id("region:loran_riverback")
	_check(economy.set_region_inventory(origin, "coal", 200000.0), "Spatial integration source stock is prepared")
	_check(economy.set_region_inventory(destination, "coal", 0.0), "Spatial integration destination demand is prepared")
	_check(bool(economy.settle_day(0).get("success", false)), "Economy submits a complete demand batch to Spatial")
	var summary: Dictionary = spatial_world.capacity_summary(shared_link_id)
	var used_capacity: float = float(summary.get("used_capacity", 0.0))
	_check(used_capacity > 0.0, "Spatial final allocation is nonzero")
	_check(used_capacity <= 50.000001, "Spatial final allocation stays within physical capacity")
	var reservations: Array = summary.get("reservations", []) as Array
	var total_demand: float = 0.0
	for raw_reservation: Variant in reservations:
		if raw_reservation is Dictionary:
			total_demand += float((raw_reservation as Dictionary).get("demand", 0.0))
	_check(total_demand > used_capacity + 0.000001, "Spatial contention retains all demand before final allocation")
	var shipments_with_spatial_allocation: int = 0
	var partial_final_allocations: int = 0
	var shipment_allocation_total: float = 0.0
	for shipment: Dictionary in economy.shipments:
		if not shipment.has("spatial_allocation_units"):
			continue
		shipments_with_spatial_allocation += 1
		var demand: float = float(shipment.get("transport_demand_units", 0.0))
		var allocated: float = float(shipment.get("spatial_allocation_units", 0.0))
		shipment_allocation_total += allocated
		_check(demand + 0.000001 >= allocated, "Economy never records allocation above submitted demand")
		_check((shipment.get("spatial_request_ids", []) as Array).size() > 0, "shipment retains Spatial request references")
		_check((shipment.get("spatial_link_ids", []) as Array).has(shared_link_id), "shipment retains the authoritative Spatial link")
		if allocated + 0.000001 < demand:
			partial_final_allocations += 1
	_check(shipments_with_spatial_allocation > 0, "Economy records shipments from Spatial final allocations")
	_check(partial_final_allocations > 0, "Economy applies a partial Spatial final allocation")
	_check(shipment_allocation_total <= used_capacity + 0.000001, "Economy shipment progress does not exceed Spatial used capacity")
	_check(economy.validate_integrity(), "Spatial-backed Economy preserves physical conservation")
	_finish()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("VNext market economy Spatial integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)
