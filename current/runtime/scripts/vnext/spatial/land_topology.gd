class_name LandTopology
extends RefCounted
## Bounded authoritative land geometry and lineage, owned by SpatialWorld.
## No controller, sovereignty, UI nodes, time settlement or historical inference.
const SCHEMA_ID: String = "land_topology_v1"
var _seed: Dictionary = {}
var _seed_catalog: VNextTerritoryUnitCatalog
var _units: Dictionary = {}
var _polygons: Dictionary = {}
var _parents: Dictionary = {}
var _retired: Dictionary = {}
var _buckets: Dictionary = {}
var _bounds: Dictionary = {}
var _revision: int = 0
var _display_summary_revision: int = -1
var _display_summary: Dictionary = {}
var _display_coverage_bounds := Rect2()
var _initialized: bool = false
var _restored_seed_ids: Array[String] = []
var _n: float
var _af: float
var _rho0: float
var _eccentricity: float

func initialize(seed: Dictionary) -> bool:
	if _initialized or seed.get("schema_id") != "land_unit_seed_v1" or not seed.get("seed_units") is Array or not seed.get("limits") is Dictionary or not seed.get("projection") is Dictionary:
		return false
	_seed = seed.duplicate(true)
	if not _configure_projection() or not _valid_limits():
		return false
	_seed_catalog = VNextTerritoryUnitCatalog.new()
	if not _seed_catalog.configure(str(_seed.seed_version)):
		return false
	for raw: Variant in seed.seed_units as Array:
		if not raw is Dictionary:
			return false
		var row := raw as Dictionary
		var id := str(row.get("id", ""))
		var polygon := _polygon_from_value(row.get("local_polygon"))
		var unit := VNextTerritoryUnit.new()
		if _units.has(id) or not _valid_polygon(polygon) or not unit.configure(id,str(_seed.seed_version),_geometry_ref(id),str(_seed.source_snapshot_id),row.get("neighbor_ids")):
			return false
		if not _seed_catalog.add_unit(unit):
			return false
		_units[id] = unit
		_polygons[id] = polygon
		_parents[id] = ""
	if not _seed_catalog.seal() or _units.size() > int(_seed.limits.max_active_units):
		return false
	if not _valid_seed_extensions():
		return false
	if not _validate_coverage(_seed.source_geometry as Dictionary,land_ids()):
		return false
	if not _validate_neighbors(_units,_polygons):
		return false
	for id: String in land_ids():
		_index_add(id)
	_initialized = true
	return true

func is_initialized() -> bool:
	return _initialized

func seed_catalog() -> VNextTerritoryUnitCatalog:
	return _seed_catalog

func has_land(id: String) -> bool:
	return _units.has(id)

func has_identity(id: String) -> bool:
	return _units.has(id) or _retired.has(id)

func display_revision() -> int:
	return _revision

func land_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_units.keys())
	ids.sort()
	return ids

func restored_seed_ids() -> Array[String]:
	# Only complete appended coverage batches can be added while loading an older save.
	return _restored_seed_ids.duplicate()

func polygon(id: String) -> PackedVector2Array:
	return (_polygons.get(id,PackedVector2Array()) as PackedVector2Array).duplicate()

func land_ids_in_bounds(bounds: Rect2) -> Array[String]:
	if not bounds.position.is_finite() or not bounds.size.is_finite(): return []
	bounds = bounds.intersection(coverage_bounds())
	if not bounds.has_area(): return []
	var first := _bucket(bounds.position)
	var last := _bucket(bounds.end)
	var candidates: Dictionary = {}
	for x: int in range(first.x,last.x+1):
		for y: int in range(first.y,last.y+1):
			for id: String in _buckets.get(Vector2i(x,y),{}) as Dictionary:
				if bounds.intersects(_bounds[id],true): candidates[id] = true
	var ids: Array[String] = []
	ids.assign(candidates.keys())
	ids.sort()
	return ids

func land_bounds(id: String) -> Rect2:
	return _bounds.get(id,Rect2())

func neighbors(id: String) -> Array[String]:
	return (_units[id] as VNextTerritoryUnit).neighbor_ids() if has_land(id) else []

func identity(id: String) -> Dictionary:
	if _retired.has(id):
		var old := (_retired[id] as Dictionary).duplicate(true)
		old["active"] = false
		return old
	if not has_land(id):
		return {}
	var row := (_units[id] as VNextTerritoryUnit).to_detached_dict()
	row["active"] = true
	row["parent_id"] = _parents[id]
	row["geometry_basis"] = "GENERATED_PARTITION"
	return row

func pick_local(point: Vector2) -> String:
	var candidates: Array = (_buckets.get(_bucket(point),{}) as Dictionary).keys()
	candidates.sort()
	for id: String in candidates:
		if (_bounds[id] as Rect2).grow(float(_seed.limits.edge_tolerance_m)).has_point(point) and Geometry2D.is_point_in_polygon(point,_polygons[id]):
			# Border ties use stable IDs; there is no camera/LOD-based identity.
			return id
	return ""

func pick_geographic(lon_lat: Vector2) -> String:
	return pick_local(from_geographic(lon_lat))

func geographic_polygon(id: String) -> PackedVector2Array:
	var output := PackedVector2Array()
	var points := polygon(id)
	for i: int in range(points.size()):
		var start := points[i]
		var end := points[(i+1)%points.size()]
		# Sample the stored projected edge for display; no new geometry or land identities.
		var segments := clampi(ceili(start.distance_to(end)/5000.0),1,32)
		for j: int in range(segments):
			output.append(to_geographic(start.lerp(end,float(j)/float(segments))))
	return output

func coverage_bounds() -> Rect2:
	_refresh_display_summary()
	return _display_coverage_bounds

func coverage_summary() -> Dictionary:
	_refresh_display_summary()
	return _display_summary.duplicate()

func _refresh_display_summary() -> void:
	if _display_summary_revision==_revision: return
	var source := _seed.get("source_geometry",{}) as Dictionary
	var total := 0.0
	var first := true
	for id: String in _polygons:
		total += area(_polygons[id])
		var bounds := _bounds[id] as Rect2
		_display_coverage_bounds = bounds if first else _display_coverage_bounds.merge(bounds)
		first = false
	_display_summary = {"scope_id":str(_seed.get("coverage_id","")),"coverage":"BOUNDED_GENERATED_LAND",
		"active_units":_units.size(),"area_km2":total/1000000.0,
		"extent_basis":source.get("outer_extent_basis",""),"water_policy":source.get("water_policy",""),"international_edge_policy":source.get("international_edge_policy","")}
	_display_summary_revision = _revision

func center_geographic(id: String) -> Vector2:
	var points := polygon(id)
	if points.is_empty(): return Vector2.ZERO
	var center := Vector2.ZERO
	for point: Vector2 in points: center += point
	center /= float(points.size())
	if not Geometry2D.is_point_in_polygon(center,points):
		var triangles := Geometry2D.triangulate_polygon(points)
		var largest := 0.0
		for i: int in range(0,triangles.size(),3):
			var a := points[triangles[i]]
			var b := points[triangles[i+1]]
			var c := points[triangles[i+2]]
			var triangle_area := absf((b-a).cross(c-a))
			if triangle_area>largest:
				largest = triangle_area
				center = (a+b+c)/3.0
	return to_geographic(center)

func query_geographic(lon_lat: Vector2, width_km: int) -> Dictionary:
	# Query windows aggregate existing identities; they are not new land units.
	if not _initialized or width_km not in [50,25,5]: return {}
	if not is_finite(lon_lat.x) or not is_finite(lon_lat.y) or absf(lon_lat.y) >= 90.0: return {}
	var point := from_geographic(lon_lat)
	var width := float(width_km)*1000.0
	var origin := Vector2(floor(point.x/width),floor(point.y/width))*width
	var bounds := Rect2(origin,Vector2.ONE*width)
	var ids := land_ids_in_bounds(bounds)
	var ring := PackedVector2Array([origin,origin+Vector2(width,0),bounds.end,origin+Vector2(0,width)])
	var members: Array[Dictionary] = []
	var covered := 0.0
	for id: String in ids:
		if not bounds.intersects(_bounds[id]): continue
		var overlap := _intersection_area(ring,_polygons[id])
		if overlap <= 0.0: continue
		covered += overlap
		members.append({"land_id":id,"area_km2":overlap/1000000.0})
	return {"width_km":width_km,"members":members,"covered_area_km2":covered/1000000.0,
		"uncovered_area_km2":maxf(0.0,width*width-covered)/1000000.0,
		"coverage":"BOUNDED_GENERATED_LAND","query_origin_m":origin}

func prepare_split(id: String, first_id: String, first: PackedVector2Array, second_id: String, second: PackedVector2Array) -> Dictionary:
	if not _initialized or not has_land(id) or has_identity(first_id) or has_identity(second_id) or first_id == second_id or not VNextTerritoryUnit.is_valid_territory_unit_id(first_id) or not VNextTerritoryUnit.is_valid_territory_unit_id(second_id):
		return {}
	if _units.size()+1 > int(_seed.limits.max_active_units) or _retired.size()+1 > int(_seed.limits.max_retired_units):
		return {}
	var a := _normalized(first)
	var b := _normalized(second)
	if not _valid_split(_polygons[id],a,b):
		return {}
	var children: Array[String] = [first_id,second_id]
	children.sort()
	var polygons: Dictionary = {first_id:a,second_id:b}
	var affected := (_units[id] as VNextTerritoryUnit).neighbor_ids()
	var replacement_units: Dictionary = {}
	for child: String in children:
		var adjacent: Array[String] = []
		for other: String in affected:
			if _share_edge(polygons[child],_polygons[other]):
				adjacent.append(other)
		for other: String in children:
			if other != child and _share_edge(polygons[child],polygons[other]):
				adjacent.append(other)
		var unit := _make_unit(child,adjacent)
		if unit == null:
			return {}
		replacement_units[child] = unit
	for other: String in affected:
		var adjacent := (_units[other] as VNextTerritoryUnit).neighbor_ids()
		adjacent.erase(id)
		for child: String in children:
			if _share_edge(_polygons[other],polygons[child]):
				adjacent.append(child)
		var unit := _make_unit(other,adjacent)
		if unit == null:
			return {}
		replacement_units[other] = unit
	return {"parent":id,"children":children,"polygons":polygons,"units":replacement_units,"expected_revision":_revision}

func commit_split(plan: Dictionary) -> void:
	# SpatialWorld preflights both authoritative owners, then commits without yielding.
	assert(int(plan.expected_revision) == _revision and has_land(str(plan.parent)))
	var id := str(plan.parent)
	_retired[id] = {"id":id,"local_polygon":(_polygons[id] as PackedVector2Array).duplicate(),"parent_id":_parents[id],"child_ids":(plan.children as Array).duplicate(),"split_revision":_revision+1,"geometry_ref":_geometry_ref(id),"source_snapshot_ref":str(_seed.source_snapshot_id)}
	_index_remove(id)
	_units.erase(id)
	_polygons.erase(id)
	_parents.erase(id)
	for replacement: String in plan.units as Dictionary:
		_units[replacement] = plan.units[replacement]
	for child: String in plan.children as Array:
		_polygons[child] = (plan.polygons[child] as PackedVector2Array).duplicate()
		_parents[child] = id
		_index_add(child)
	_revision += 1

func snapshot() -> Dictionary:
	var active: Array[Dictionary] = []
	for id: String in land_ids():
		var row := (_units[id] as VNextTerritoryUnit).to_detached_dict()
		row["local_polygon"] = polygon(id)
		row["parent_id"] = _parents[id]
		active.append(row)
	var retired: Array[Dictionary] = []
	var ids: Array = _retired.keys()
	ids.sort()
	for id: String in ids:
		retired.append((_retired[id] as Dictionary).duplicate(true))
	return {"schema_id":SCHEMA_ID,"seed_version":_seed.seed_version,"revision":_revision,"active":active,"retired":retired}

func restored_copy(value: Dictionary) -> LandTopology:
	if value.size() != 5 or value.get("schema_id") != SCHEMA_ID or value.get("seed_version") != _seed.seed_version or not value.get("revision") is int or not value.get("active") is Array or not value.get("retired") is Array:
		return null
	var candidate := LandTopology.new()
	if not candidate.initialize(_seed):
		return null
	if not candidate._restore_records(value):
		return null
	return candidate

func _restore_records(value: Dictionary) -> bool:
	if int(value.revision) < 0 or int(value.revision) != (value.retired as Array).size() or (value.active as Array).is_empty() or (value.active as Array).size() > int(_seed.limits.max_active_units) or (value.retired as Array).size() > int(_seed.limits.max_retired_units):
		return false
	var units: Dictionary = {}
	var polygons: Dictionary = {}
	var parents: Dictionary = {}
	var retired: Dictionary = {}
	var revisions: Dictionary = {}
	for raw: Variant in value.active as Array:
		if not raw is Dictionary:
			return false
		var row := raw as Dictionary
		if not _exact_fields(row,["territory_unit_id","catalog_version","geometry_ref","source_snapshot_ref","neighbor_ids","local_polygon","parent_id"]) or not row.get("parent_id") is String:
			return false
		var unit := VNextTerritoryUnit.new()
		if not unit.configure(row.territory_unit_id,row.catalog_version,row.geometry_ref,row.source_snapshot_ref,row.neighbor_ids) or row.catalog_version != _seed.seed_version or row.source_snapshot_ref != _seed.source_snapshot_id or row.geometry_ref != _geometry_ref(str(row.territory_unit_id)):
			return false
		var id := unit.territory_unit_id()
		var points := _polygon_from_value(row.local_polygon)
		if units.has(id) or not _valid_polygon(points):
			return false
		units[id] = unit
		polygons[id] = points
		parents[id] = row.parent_id
	for raw: Variant in value.retired as Array:
		if not raw is Dictionary:
			return false
		var row := raw as Dictionary
		if not _exact_fields(row,["id","local_polygon","parent_id","child_ids","split_revision","geometry_ref","source_snapshot_ref"]) or not row.id is String or not row.parent_id is String or not row.child_ids is Array or (row.child_ids as Array).size() != 2 or not row.split_revision is int:
			return false
		var id := str(row.id)
		if not VNextTerritoryUnit.is_valid_territory_unit_id(id) or units.has(id) or retired.has(id) or row.source_snapshot_ref != _seed.source_snapshot_id or row.geometry_ref != _geometry_ref(id) or int(row.split_revision) < 1 or int(row.split_revision) > int(value.revision) or revisions.has(row.split_revision):
			return false
		var points := _polygon_from_value(row.local_polygon)
		if not _valid_polygon(points) or not row.child_ids[0] is String or not row.child_ids[1] is String or row.child_ids[0] == row.child_ids[1]:
			return false
		revisions[row.split_revision] = true
		retired[id] = row.duplicate(true)
		retired[id]["local_polygon"] = points
		polygons[id] = points
		parents[id] = row.parent_id
	var referenced: Dictionary = {}
	for id: String in retired:
		var row := retired[id] as Dictionary
		for child: String in row.child_ids as Array:
			if not polygons.has(child) or parents[child] != id or referenced.has(child):
				return false
			if retired.has(child) and int(retired[child].split_revision) <= int(row.split_revision):
				return false
			referenced[child] = true
		if not _valid_split(polygons[id],polygons[row.child_ids[0]],polygons[row.child_ids[1]]):
			return false
	# The original roots remain mandatory. New batches must be wholly present or absent.
	var appended: Dictionary = {}
	var missing_batch := false
	for extension: Dictionary in _seed.get("seed_extensions",[]) as Array:
		var missing := 0
		for id: String in extension.root_ids as Array:
			if not polygons.has(id): missing += 1
		if missing == 0:
			if missing_batch: return false
		elif missing == (extension.root_ids as Array).size():
			missing_batch = true
			for id: String in extension.root_ids as Array: appended[id] = true
		else: return false
	if units.size()+appended.size() > int(_seed.limits.max_active_units): return false
	var roots: Dictionary = {}
	for root: Dictionary in _seed.seed_units as Array:
		var id := str(root.id)
		roots[id] = true
		if appended.has(id):
			polygons[id] = _polygon_from_value(root.local_polygon)
			parents[id] = ""
		if not polygons.has(id) or parents[id] != "" or not _same_coverage(polygons[id],_polygon_from_value(root.local_polygon)):
			return false
	for id: String in polygons:
		if not roots.has(id) and not referenced.has(id):
			return false
	# Check saved adjacency before adding the new edge neighbors. Malformed saves still reject.
	if not _validate_neighbors(units,polygons): return false
	for id: String in appended: units[id] = _units[id]
	if not appended.is_empty():
		for id: String in units:
			var adjacent: Array[String] = []
			for other: String in units:
				if other != id and _share_edge(polygons[id],polygons[other]): adjacent.append(other)
			var unit := _make_unit(id,adjacent)
			if unit == null: return false
			units[id] = unit
		if not _validate_neighbors(units,polygons): return false
	_units = units
	_polygons.clear()
	_parents.clear()
	for id: String in units:
		_polygons[id] = polygons[id]
		_parents[id] = parents[id]
	_retired = retired
	_revision = int(value.revision)
	_restored_seed_ids.assign(appended.keys())
	_restored_seed_ids.sort()
	_buckets.clear()
	_bounds.clear()
	for id: String in land_ids():
		_index_add(id)
	return true

func _valid_seed_extensions() -> bool:
	if not _seed.get("seed_extensions",[]) is Array: return false
	var batches: Dictionary = {}
	var roots: Dictionary = {}
	for raw: Variant in _seed.get("seed_extensions",[]) as Array:
		if not raw is Dictionary: return false
		var row := raw as Dictionary
		if not row.get("id") is String or str(row.id).is_empty() or batches.has(row.id) or not row.get("root_ids") is Array or (row.root_ids as Array).is_empty(): return false
		batches[row.id] = true
		for id: Variant in row.root_ids as Array:
			if not id is String or not _units.has(id) or roots.has(id): return false
			roots[id] = true
	return roots.size() < _units.size()

func _make_unit(id: String, adjacent: Array[String]) -> VNextTerritoryUnit:
	var unit := VNextTerritoryUnit.new()
	if not unit.configure(id,str(_seed.seed_version),_geometry_ref(id),str(_seed.source_snapshot_id),adjacent):
		return null
	return unit

func _geometry_ref(id: String) -> String:
	return "land_geometry:"+id

func _valid_limits() -> bool:
	var limits := _seed.limits as Dictionary
	for key: String in ["max_active_units","max_retired_units","min_area_m2","area_tolerance_m2","edge_tolerance_m","coordinate_quantum_m","index_cell_m"]:
		if not limits.get(key) is int and not limits.get(key) is float:
			return false
		if not is_finite(float(limits[key])) or float(limits[key]) <= 0:
			return false
	return float(limits.max_active_units) == floor(float(limits.max_active_units)) and float(limits.max_retired_units) == floor(float(limits.max_retired_units))

func _polygon_from_value(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	var points := PackedVector2Array()
	if not value is Array:
		return points
	for raw: Variant in value as Array:
		if not raw is Array or (raw as Array).size() != 2 or typeof(raw[0]) not in [TYPE_FLOAT,TYPE_INT] or typeof(raw[1]) not in [TYPE_FLOAT,TYPE_INT]:
			return PackedVector2Array()
		points.append(Vector2(float(raw[0]),float(raw[1])))
	return points

func _normalized(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	var quantum := float(_seed.limits.coordinate_quantum_m)
	for i: int in range(result.size()):
		result[i] = Vector2(snappedf(result[i].x,quantum),snappedf(result[i].y,quantum))
	return result

static func area(points: PackedVector2Array) -> float:
	var result := 0.0
	for i: int in range(points.size()):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		result += float(a.x)*float(b.y)-float(b.x)*float(a.y)
	return absf(result)*.5

func _valid_polygon(points: PackedVector2Array) -> bool:
	# Simple concave rings allow sourced administrative cuts; holes/multiparts reject.
	if points.size() < 3 or points.size() > 64 or area(points) < float(_seed.limits.min_area_m2):
		return false
	var seen: Dictionary = {}
	for i: int in range(points.size()):
		var point := points[i]
		if not is_finite(point.x) or not is_finite(point.y) or seen.has(point):
			return false
		seen[point] = true
		var first := points[(i+1)%points.size()]-point
		var second := points[(i+2)%points.size()]-points[(i+1)%points.size()]
		# Scalar doubles retain small sourced corners beside long projected edges.
		var cross := float(first.x)*float(second.y)-float(first.y)*float(second.x)
		if absf(cross) <= pow(float(_seed.limits.edge_tolerance_m),2):
			return false
		for j: int in range(i+1,points.size()):
			if j == i+1 or (i==0 and j==points.size()-1): continue
			if Geometry2D.segment_intersects_segment(point,points[(i+1)%points.size()],points[j],points[(j+1)%points.size()]) != null: return false
	# Restore rejects off-quantum geometry rather than silently rewriting saved bits.
	return points == _normalized(points) and Geometry2D.triangulate_polygon(points).size() == (points.size()-2)*3

func _intersection_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var result := 0.0
	for part: PackedVector2Array in Geometry2D.intersect_polygons(a,b):
		result += area(part)
	return result

func _same_coverage(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var tolerance := float(_seed.limits.area_tolerance_m2)
	return absf(area(a)-area(b)) <= tolerance and absf(_intersection_area(a,b)-area(a)) <= tolerance

func _valid_split(parent: PackedVector2Array, a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var tolerance := float(_seed.limits.area_tolerance_m2)
	return _valid_polygon(a) and _valid_polygon(b) and absf(area(a)+area(b)-area(parent)) <= tolerance and _intersection_area(a,b) <= tolerance and absf(_intersection_area(parent,a)-area(a)) <= tolerance and absf(_intersection_area(parent,b)-area(b)) <= tolerance

func _validate_coverage(source: Dictionary, ids: Array[String]) -> bool:
	# Multi-part source coverage is not a multi-part land unit. Each formal unit
	# retains the existing connected, simple polygon representation and limit.
	var parts: Array = source.get("local_polygons",[])
	if parts.is_empty() and source.has("local_polygon"): parts = [[source.local_polygon]]
	if parts.is_empty(): return false
	var scopes: Array = []
	var scope_area := 0.0
	for part: Array in parts:
		if part.is_empty(): return false
		var rings: Array[PackedVector2Array] = []
		for value: Variant in part:
			var ring := _polygon_from_value(value)
			if ring.size()<3: return false
			for point: Vector2 in ring:
				if not is_finite(point.x) or not is_finite(point.y): return false
			rings.append(ring)
			scope_area += area(ring) if rings.size()==1 else -area(ring)
		scopes.append(rings)
	var total := 0.0
	var tolerance := float(_seed.limits.area_tolerance_m2)
	for i: int in range(ids.size()):
		var points := _polygons[ids[i]] as PackedVector2Array
		total += area(points)
		var bounds := _polygon_bounds(points)
		var covered := 0.0
		for rings: Array in scopes:
			if not bounds.intersects(_polygon_bounds(rings[0]),true): continue
			covered += _intersection_area(rings[0],points)
			for hole: int in range(1,rings.size()): covered -= _intersection_area(rings[hole],points)
		if absf(covered-area(points)) > tolerance:
			return false
		for j: int in range(i):
			if bounds.intersects(_polygon_bounds(_polygons[ids[j]])) and _intersection_area(points,_polygons[ids[j]]) > tolerance:
				return false
	return absf(total-scope_area) <= tolerance

static func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var bounds := Rect2(points[0],Vector2.ZERO)
	for point: Vector2 in points: bounds = bounds.expand(point)
	return bounds

func _share_edge(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var epsilon := float(_seed.limits.edge_tolerance_m)
	if not _polygon_bounds(a).grow(epsilon).intersects(_polygon_bounds(b),true): return false
	for i: int in range(a.size()):
		var start := a[i]
		var direction := a[(i+1)%a.size()]-start
		var length := direction.length()
		if length <= epsilon:
			continue
		for j: int in range(b.size()):
			var c := b[j]-start
			var d := b[(j+1)%b.size()]-start
			var c_cross := (float(direction.x)*float(c.y)-float(direction.y)*float(c.x))/length
			var d_cross := (float(direction.x)*float(d.y)-float(direction.y)*float(d.x))/length
			if absf(c_cross) > epsilon or absf(d_cross) > epsilon:
				continue
			var c_dot := (float(direction.x)*float(c.x)+float(direction.y)*float(c.y))/length
			var d_dot := (float(direction.x)*float(d.x)+float(direction.y)*float(d.y))/length
			if minf(length,maxf(c_dot,d_dot))-maxf(0,minf(c_dot,d_dot)) > epsilon:
				return true
	return false

func _validate_neighbors(units: Dictionary, polygons: Dictionary) -> bool:
	var ids: Array[String] = []
	ids.assign(units.keys())
	ids.sort()
	for id: String in ids:
		var adjacent := (units[id] as VNextTerritoryUnit).neighbor_ids()
		for other: String in ids:
			if other != id and adjacent.has(other) != _share_edge(polygons[id],polygons[other]):
				return false
		for other: String in adjacent:
			if not units.has(other) or not (units[other] as VNextTerritoryUnit).neighbor_ids().has(id):
				return false
	return true

func _bucket(point: Vector2) -> Vector2i:
	var size := float(_seed.limits.index_cell_m)
	return Vector2i(floori(point.x/size),floori(point.y/size))

func _index_add(id: String) -> void:
	var points := _polygons[id] as PackedVector2Array
	var bounds := Rect2(points[0],Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	_bounds[id] = bounds
	var first := _bucket(bounds.position)
	var last := _bucket(bounds.end)
	for x: int in range(first.x,last.x+1):
		for y: int in range(first.y,last.y+1):
			var key := Vector2i(x,y)
			if not _buckets.has(key):
				_buckets[key] = {}
			_buckets[key][id] = true

func _index_remove(id: String) -> void:
	var bounds := _bounds[id] as Rect2
	var first := _bucket(bounds.position)
	var last := _bucket(bounds.end)
	for x: int in range(first.x,last.x+1):
		for y: int in range(first.y,last.y+1):
			var key := Vector2i(x,y)
			(_buckets[key] as Dictionary).erase(id)
			if (_buckets[key] as Dictionary).is_empty():
				_buckets.erase(key)
	_bounds.erase(id)

static func _exact_fields(row: Dictionary, fields: Array[String]) -> bool:
	if row.size() != fields.size():
		return false
	for field: String in fields:
		if not row.has(field):
			return false
	return true

func _configure_projection() -> bool:
	var p := _seed.projection as Dictionary
	if p.get("crs") != "EPSG:2154" or not p.get("origin_m") is Array or (p.origin_m as Array).size() != 2:
		return false
	for key: String in ["a","inverse_flattening","lat_0","lon_0","lat_1","lat_2","x_0","y_0"]:
		if typeof(p.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(p[key])):
			return false
	var f := 1.0/float(p.inverse_flattening)
	_eccentricity = sqrt(2*f-f*f)
	var phi1 := deg_to_rad(float(p.lat_1))
	var phi2 := deg_to_rad(float(p.lat_2))
	_n = (log(_m(phi1))-log(_m(phi2)))/(log(_t(phi1))-log(_t(phi2)))
	_af = float(p.a)*_m(phi1)/(_n*pow(_t(phi1),_n))
	_rho0 = _af*pow(_t(deg_to_rad(float(p.lat_0))),_n)
	return is_finite(_n) and is_finite(_af) and is_finite(_rho0)

func _m(phi: float) -> float:
	return cos(phi)/sqrt(1-_eccentricity*_eccentricity*pow(sin(phi),2))

func _t(phi: float) -> float:
	return tan(PI*.25-phi*.5)/pow((1-_eccentricity*sin(phi))/(1+_eccentricity*sin(phi)),_eccentricity*.5)

func from_geographic(lon_lat: Vector2) -> Vector2:
	var p := _seed.projection as Dictionary
	var rho := _af*pow(_t(deg_to_rad(lon_lat.y)),_n)
	var angle := _n*(deg_to_rad(lon_lat.x)-deg_to_rad(float(p.lon_0)))
	return Vector2(float(p.x_0)+rho*sin(angle)-float(p.origin_m[0]),float(p.y_0)+_rho0-rho*cos(angle)-float(p.origin_m[1]))

func to_geographic(local_point: Vector2) -> Vector2:
	var p := _seed.projection as Dictionary
	var x := float(local_point.x)+float(p.origin_m[0])-float(p.x_0)
	var y := _rho0-(float(local_point.y)+float(p.origin_m[1])-float(p.y_0))
	var t := pow(sqrt(x*x+y*y)/_af,1.0/_n)
	var phi := PI*.5-2*atan(t)
	for iteration: int in range(10):
		phi = PI*.5-2*atan(t*pow((1-_eccentricity*sin(phi))/(1+_eccentricity*sin(phi)),_eccentricity*.5))
	return Vector2(rad_to_deg(deg_to_rad(float(p.lon_0))+atan2(x,y)/_n),rad_to_deg(phi))
