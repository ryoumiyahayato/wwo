class_name VNextSpatialMapProjection
extends RefCounted
## Debug/test projection. It reads Spatial facts and owns no mutable world state.


func project(world: VNextSpatialWorld) -> Dictionary:
	if world == null or not world.is_valid():
		return {}
	var catalog: VNextSpatialCatalog = world.catalog()
	var regions: Array[Dictionary] = []
	for region_id: String in catalog.region_ids():
		var region: Dictionary = catalog.get_region(region_id)
		var facts: Dictionary = world.get_territorial_facts(region_id)
		regions.append({
			"id": region_id,
			"place_id": VNextSpatialCatalog.map_id_to_place_id(region_id),
			"name": str(region.get("name", "")),
			"sovereign_owner_id": str(facts.get("sovereign_owner_id", "")),
			"administrative_parent_id": str(facts.get("administrative_parent_id", "")),
			"military_controller_id": str(facts.get("military_controller_id", "")),
		})

	var infrastructure: Array[Dictionary] = []
	var important_links: Array[Dictionary] = []
	for link_id: String in catalog.link_ids():
		var state: Dictionary = world.infrastructure_state(link_id)
		var projected: Dictionary = {
			"id": link_id,
			"link_type": str(state.get("link_type", "")),
			"from_place_id": str(state.get("from_place_id", "")),
			"to_place_id": str(state.get("to_place_id", "")),
			"status": str(state.get("status", "")),
			"nominal_capacity": float(state.get("nominal_capacity", 0.0)),
			"effective_capacity": float(state.get("effective_capacity", 0.0)),
			"used_capacity": float(state.get("used_capacity", 0.0)),
			"remaining_capacity": float(state.get("remaining_capacity", 0.0)),
		}
		infrastructure.append(projected)
		if (
			str(state.get("link_type", "")) != VNextSpatialCatalog.LINK_TYPE_ROAD
			or bool(state.get("main", false))
		):
			important_links.append(projected.duplicate(true))

	var ports: Array[Dictionary] = []
	for port_id: String in catalog.port_ids():
		var port: Dictionary = catalog.get_port(port_id)
		ports.append({
			"id": port_id,
			"place_id": VNextSpatialCatalog.map_id_to_place_id(port_id),
			"name": str(port.get("name", "")),
			"city_id": str(port.get("city_id", "")),
			"status": _port_status(world, port_id),
		})

	var important_nodes: Array[Dictionary] = []
	for city_id: String in catalog.city_ids():
		var city: Dictionary = catalog.get_city(city_id)
		if not bool(city.get("major", false)):
			continue
		important_nodes.append({
			"id": city_id,
			"place_id": VNextSpatialCatalog.map_id_to_place_id(city_id),
			"kind": "city",
			"name": str(city.get("name", "")),
			"region_id": str(city.get("parent_region_id", "")),
		})
	for port_id: String in catalog.port_ids():
		var port: Dictionary = catalog.get_port(port_id)
		important_nodes.append({
			"id": port_id,
			"place_id": VNextSpatialCatalog.map_id_to_place_id(port_id),
			"kind": "port",
			"name": str(port.get("name", "")),
			"region_id": str(port.get("parent_region_id", "")),
		})
	important_nodes.sort_custom(Callable(self, "_compare_id"))

	return {
		"current_hour": world.current_hour(),
		"regions": regions,
		"infrastructure": infrastructure,
		"ports": ports,
		"important_nodes": important_nodes,
		"links": infrastructure.duplicate(true),
		"important_links": important_links,
	}


func build(world: VNextSpatialWorld) -> Dictionary:
	return project(world)


func _port_status(world: VNextSpatialWorld, port_id: String) -> String:
	var links: Array[Dictionary] = world.links_from(port_id, VNextSpatialCatalog.LINK_TYPE_SHIPPING)
	if links.is_empty():
		return "unconnected"
	var operational_count: int = 0
	var unavailable_count: int = 0
	for link: Dictionary in links:
		var state: Dictionary = world.infrastructure_state(str(link.get("link_id", "")))
		var status: String = str(state.get("status", ""))
		if status == VNextInfrastructureLinkState.STATUS_OPERATIONAL or status == VNextInfrastructureLinkState.STATUS_RESTORED:
			if float(state.get("effective_capacity", 0.0)) > 0.0:
				operational_count += 1
			else:
				unavailable_count += 1
		elif status == VNextInfrastructureLinkState.STATUS_CONSTRUCTION or status == VNextInfrastructureLinkState.STATUS_INTERRUPTED or status == VNextInfrastructureLinkState.STATUS_DESTROYED:
			unavailable_count += 1
		else:
			unavailable_count += 1
	if operational_count == links.size():
		return "operational"
	if unavailable_count == links.size():
		return "unavailable"
	return "degraded"


static func _compare_id(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("id", "")) < str(right.get("id", ""))
