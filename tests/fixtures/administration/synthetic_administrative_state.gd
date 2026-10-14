extends RefCounted
## Independent experiment ONLY. Not installed in WorldState or exported to Release.
## The synthetic catalog explicitly admits land IDs; no map or historical polygon input.

const SCHEMA: String = "synthetic_administrative_experiment_r1"
var _catalog: VNextTerritoryUnitCatalog
var _places: Array[String] = []
var _polities: Array[String] = []
var _regions: Dictionary = {}
var _membership: Dictionary = {}
var _members: Dictionary = {}
var revision: int = 0
var touched_members: int = 0
var affected_regions: Array[String] = []

func _init(catalog: VNextTerritoryUnitCatalog, places: Array[String], polities: Array[String]) -> void:
	_catalog = catalog
	_places = places.duplicate()
	_polities = polities.duplicate()

func create_region(id: String, polity: String, name: String, kind: String, capital: String = "") -> bool:
	if _catalog == null or not _catalog.is_sealed() or not id.begins_with("administrative_region:") or not id.trim_prefix("administrative_region:").is_valid_identifier() or _regions.has(id) or not _polities.has(polity) or name.strip_edges().is_empty() or kind.strip_edges().is_empty() or (not capital.is_empty() and not _places.has(capital)):
		return false
	_regions[id] = {"id": id, "polity_id": polity, "historical_name": name, "current_name": name, "unit_type": kind, "level": 1, "parent_region_id": null, "active": true, "capital_place_id": capital, "membership_revision": 0}
	_members[id] = {}
	return true

func region(id: String) -> Dictionary:
	return (_regions.get(id, {}) as Dictionary).duplicate(true)

func members(id: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign((_members.get(id, {}) as Dictionary).keys())
	ids.sort()
	return ids

func membership(land_id: String) -> String:
	return str(_membership.get(land_id, ""))

func rename(id: String, name: String) -> bool:
	if not _active(id) or name.strip_edges().is_empty():
		return false
	_regions[id]["current_name"] = name
	return true

func set_capital(id: String, place: String) -> bool:
	if not _active(id) or (not place.is_empty() and not _places.has(place)):
		return false
	_regions[id]["capital_place_id"] = place
	return true

func transfer(land_ids: Array[String], target: String) -> bool:
	if land_ids.is_empty() or not _active(target):
		return false
	var unique: Dictionary = {}
	var affected: Dictionary = {}
	# Preflight the entire batch before changing either direction of the index.
	for land: String in land_ids:
		if not _catalog.has_unit(land) or unique.has(land):
			return false
		unique[land] = true
		var previous := membership(land)
		if not previous.is_empty() and str(_regions[previous].polity_id) != str(_regions[target].polity_id):
			return false
		if previous == target:
			continue
		if not previous.is_empty():
			affected[previous] = true
		affected[target] = true
	affected_regions.clear()
	touched_members = 0
	if affected.is_empty():
		return true
	revision += 1
	for land: String in land_ids:
		var previous := membership(land)
		if previous == target:
			continue
		if not previous.is_empty():
			(_members[previous] as Dictionary).erase(land)
		_members[target][land] = true
		_membership[land] = target
		touched_members += 1
	affected_regions.assign(affected.keys())
	affected_regions.sort()
	for id: String in affected_regions:
		_regions[id]["membership_revision"] = revision
	return true

func deactivate(id: String) -> bool:
	if not _active(id) or not (_members[id] as Dictionary).is_empty():
		return false
	revision += 1
	_regions[id]["active"] = false
	_regions[id]["membership_revision"] = revision
	affected_regions = [id]
	return true

func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	var ids: Array = _regions.keys()
	ids.sort()
	for id: String in ids:
		var record := region(id)
		record["members"] = members(id)
		records.append(record)
	return {"schema_id": SCHEMA, "catalog_binding": _catalog.binding(), "revision": revision, "regions": records}

func restore(value: Dictionary) -> bool:
	if value.size() != 4 or value.get("schema_id") != SCHEMA or not _catalog.validates_binding(value.get("catalog_binding")) or not value.get("regions") is Array or not value.get("revision") is int or int(value.revision) < 0:
		return false
	var candidate: Variant = get_script().new(_catalog, _places, _polities)
	var seen: Dictionary = {}
	for raw: Variant in value.regions as Array:
		if not raw is Dictionary:
			return false
		var record := raw as Dictionary
		if record.size() != 11:
			return false
		for field: String in ["id", "polity_id", "historical_name", "current_name", "unit_type", "capital_place_id", "active", "membership_revision", "level", "parent_region_id", "members"]:
			if not record.has(field):
				return false
		for field: String in ["id", "polity_id", "historical_name", "current_name", "unit_type", "capital_place_id"]:
			if not record.get(field) is String:
				return false
		if not record.get("active") is bool or not record.get("membership_revision") is int or int(record.membership_revision) < 0 or int(record.membership_revision) > int(value.revision) or not record.get("level") is int or record.level != 1 or record.get("parent_region_id") != null or not record.get("members") is Array or str(record.current_name).strip_edges().is_empty():
			return false
		if not candidate.create_region(record.id, record.polity_id, record.historical_name, record.unit_type, record.capital_place_id):
			return false
		for land: Variant in record.members as Array:
			if not land is String or seen.has(land) or not _catalog.has_unit(land) or not record.active:
				return false
			seen[land] = true
			candidate._membership[land] = record.id
			candidate._members[record.id][land] = true
		var restored := record.duplicate(true)
		restored.erase("members")
		candidate._regions[record.id] = restored
	_regions = candidate._regions
	_membership = candidate._membership
	_members = candidate._members
	revision = int(value.revision)
	affected_regions.clear()
	touched_members = 0
	return true

func _active(id: String) -> bool:
	return _regions.has(id) and bool(_regions[id].active)

func boundary_edges(id: String, geometry_by_land: Dictionary) -> Array[Dictionary]:
	# Synthetic topology has exact shared vertices and edges; this is NOT a GIS union.
	# Real-world noding, holes, tolerances and geodesic seams remain unimplemented.
	var edges: Dictionary = {}
	for land: String in members(id):
		var polygon := geometry_by_land[land] as PackedVector2Array
		for index: int in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			var endpoints := [a, b]
			if a.x > b.x or (a.x == b.x and a.y > b.y):
				endpoints = [b, a]
			var key := var_to_bytes(endpoints).hex_encode()
			if edges.has(key):
				edges.erase(key)
			else:
				edges[key] = {"points": PackedVector2Array(endpoints)}
	var output: Array[Dictionary] = []
	var keys: Array = edges.keys()
	keys.sort()
	for key: String in keys:
		output.append(edges[key])
	return output
