class_name GlobeProjection
extends RefCounted
## One owner for geographic coordinates, source tessellation and visible-hemisphere clipping.

const SOURCE_EPSILON: float = 0.000001
const SURFACE_EDGE_DEGREES: float = 2.0
const SURFACE_EDGE_CHORD_SQUARED: float = 2.0-2.0*cos(deg_to_rad(SURFACE_EDGE_DEGREES))
const SURFACE_LONGITUDE_DEGREES: float = 8.0
const HIGH_LATITUDE: float = 55.0

static func lon_lat_to_unit(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	return Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))

static func to_unit_line(points: PackedVector2Array) -> PackedVector3Array:
	var output := PackedVector3Array()
	for point: Vector2 in points:
		output.append(lon_lat_to_unit(point))
	return output

static func display_line(points: PackedVector2Array) -> PackedVector3Array:
	# Same dyadic source-edge subdivision as the surface triangulator.
	# Original ring vertices remain; no cartographic line simplification.
	var output := PackedVector3Array()
	if points.is_empty(): return output
	var previous := points[0]
	output.append(lon_lat_to_unit(previous))
	for index: int in range(1,points.size()):
		var point := points[index]
		point.x += roundf((previous.x-point.x)/360.0)*360.0
		_append_display_edge(previous,point,output)
		previous = point
	# The same source endpoint can differ by a float32 rounding bit after a
	# 360-degree unwrap. A closed ring must share its exact encoded endpoint.
	if points.size()>1 and points[0]==points[-1] and output.size()>1: output[-1] = output[0]
	return output

static func _append_display_edge(a: Vector2, b: Vector2, output: PackedVector3Array, depth: int = 0) -> void:
	var unit_a := lon_lat_to_unit(a)
	var unit_b := lon_lat_to_unit(b)
	if depth<24 and (unit_a.distance_squared_to(unit_b)>SURFACE_EDGE_CHORD_SQUARED or absf(a.x-b.x)>SURFACE_LONGITUDE_DEGREES):
		var middle := (a+b)*0.5
		_append_display_edge(a,middle,output,depth+1)
		_append_display_edge(middle,b,output,depth+1)
	else:
		if output.is_empty() or output[-1]!=unit_b: output.append(unit_b)

static func renderable_triangle(points: PackedVector3Array) -> bool:
	# A sub-metre boolean sliver can collapse when WGS84 is encoded as unit
	# float32 vectors. Do not send coincident corners or NaN edge normals.
	if points.size()!=3: return false
	var a := points[1]-points[0]
	var b := points[2]-points[0]
	return points[0].is_finite() and points[1].is_finite() and points[2].is_finite() and a.length_squared()>0.0 and b.length_squared()>0.0 and (points[2]-points[1]).length_squared()>0.0 and a.cross(b).length_squared()>0.0

static func sphere_screen(point: Vector3, center: Vector2, radius: float) -> Vector2:
	return center + Vector2(point.x, -point.y) * radius

static func project_line(line: PackedVector3Array, basis: Basis, center: Vector2, radius: float) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	if line.size() < 2:
		return output
	var segment := PackedVector2Array()
	var previous := basis * line[0]
	var previous_visible := previous.z >= 0.0
	if previous_visible:
		segment.append(sphere_screen(previous, center, radius))
	for index: int in range(1, line.size()):
		var current := basis * line[index]
		var current_visible := current.z >= 0.0
		if current_visible != previous_visible:
			var ratio := previous.z / (previous.z - current.z)
			var horizon := previous.lerp(current, ratio)
			horizon.z = 0.0
			segment.append(sphere_screen(horizon, center, radius))
			if segment.size() > 1:
				output.append(segment)
			segment = PackedVector2Array()
			if current_visible:
				segment.append(sphere_screen(horizon, center, radius))
		if current_visible:
			segment.append(sphere_screen(current, center, radius))
		previous = current
		previous_visible = current_visible
	if segment.size() > 1:
		output.append(segment)
	return output

static func project_surface(triangle: Dictionary, basis: Basis, center: Vector2, radius: float) -> Dictionary:
	var source := triangle.points as PackedVector3Array
	var source_uvs := triangle.uvs as PackedVector2Array
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var previous := basis * source[source.size() - 1]
	var previous_uv := source_uvs[source_uvs.size() - 1]
	var previous_inside := previous.z >= 0.0
	for index: int in range(source.size()):
		var current := basis * source[index]
		var current_uv := source_uvs[index]
		var current_inside := current.z >= 0.0
		if current_inside != previous_inside:
			var ratio := previous.z / (previous.z - current.z)
			var horizon := previous.lerp(current, ratio)
			horizon.z = 0.0
			points.append(sphere_screen(horizon, center, radius))
			uvs.append(previous_uv.lerp(current_uv, ratio))
		if current_inside:
			points.append(sphere_screen(current, center, radius))
			uvs.append(current_uv)
		previous = current
		previous_uv = current_uv
		previous_inside = current_inside
	return {"points": points, "uvs": uvs, "component_index": triangle.component_index}

static func lon_lat_bounds(polygons: Array) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for polygon: PackedVector2Array in polygons:
		for point: Vector2 in polygon:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)

static func polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	# Center before multiplying: absolute longitude/screen coordinates lose
	# small island and clipped-triangle areas through float32 cancellation.
	var area := 0.0
	var origin := polygon[0]
	for index: int in range(1, polygon.size() - 1):
		var a := polygon[index] - origin
		var b := polygon[index + 1] - origin
		area += float(a.x) * float(b.y) - float(a.y) * float(b.x)
	return absf(area) * 0.5

static func normalize_ring(ring: PackedVector2Array) -> PackedVector2Array:
	var output := PackedVector2Array()
	for point: Vector2 in ring:
		if output.is_empty() or point.distance_squared_to(output[output.size() - 1]) > SOURCE_EPSILON * SOURCE_EPSILON:
			output.append(point)
	if output.size() > 1 and output[0].distance_squared_to(output[output.size() - 1]) <= SOURCE_EPSILON * SOURCE_EPSILON:
		output.resize(output.size() - 1)
	return output

static func unwrap_ring(ring: PackedVector2Array, reference: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	if ring.is_empty():
		return output
	# Put a date-line seam at the ring closure, never across its interior.
	var start := 0
	var maximum_jump := 180.0
	for index: int in range(ring.size()):
		var next := (index + 1) % ring.size()
		var jump := absf(ring[next].x - ring[index].x)
		if jump > maximum_jump:
			maximum_jump = jump
			start = next
	var previous := reference
	for offset: int in range(ring.size()):
		var point := ring[(start + offset) % ring.size()]
		while point.x - previous > 180.0:
			point.x -= 360.0
		while point.x - previous < -180.0:
			point.x += 360.0
		output.append(point)
		previous = point.x
	return normalize_ring(output)

static func partition_polygon(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	var bounds := lon_lat_bounds([polygon])
	var high_latitude := maxf(absf(bounds.position.y), absf(bounds.end.y)) >= HIGH_LATITUDE
	var step := Vector2(5.0, 5.0) if high_latitude else Vector2(20.0, 15.0)
	if polygon.size() <= 128 and bounds.size.x <= step.x and bounds.size.y <= step.y:
		return [polygon]
	var pieces: Array[PackedVector2Array] = []
	for x: int in range(floori(bounds.position.x / step.x), ceili(bounds.end.x / step.x)):
		for y: int in range(floori(bounds.position.y / step.y), ceili(bounds.end.y / step.y)):
			var low := Vector2(float(x) * step.x, float(y) * step.y)
			var high := low + step
			var cell := PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])
			for raw: PackedVector2Array in Geometry2D.intersect_polygons(polygon, cell):
				var piece := normalize_ring(raw)
				if piece.size() >= 3 and polygon_area(piece) > 0.0:
					pieces.append(piece)
	return pieces

static func subtract_holes(pieces: Array[PackedVector2Array], holes: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	for hole: PackedVector2Array in holes:
		var remaining: Array[PackedVector2Array] = []
		var cut := lon_lat_bounds([hole]).get_center().y
		for piece: PackedVector2Array in pieces:
			if Geometry2D.intersect_polygons(piece, hole).is_empty():
				remaining.append(piece)
				continue
			# Open a contained hole at its latitude midpoint before subtraction.
			# Every result is a simple exterior; the triangulator never receives
			# a detached hole ring or needs to guess its role from a sample point.
			var bounds := lon_lat_bounds([piece])
			var slices: Array[PackedVector2Array] = [piece]
			if cut > bounds.position.y and cut < bounds.end.y:
				slices = []
				for limits: Vector2 in [Vector2(bounds.position.y, cut), Vector2(cut, bounds.end.y)]:
					var cell := PackedVector2Array([Vector2(bounds.position.x, limits.x), Vector2(bounds.end.x, limits.x), Vector2(bounds.end.x, limits.y), Vector2(bounds.position.x, limits.y)])
					slices.append_array(Geometry2D.intersect_polygons(piece, cell))
			for slice: PackedVector2Array in slices:
				for raw: PackedVector2Array in Geometry2D.clip_polygons(slice, hole):
					var exterior := normalize_ring(raw)
					if exterior.size() >= 3 and polygon_area(exterior) > 0.0:
						remaining.append(exterior)
		pieces = remaining
	return pieces

static func triangulate_piece(polygon: PackedVector2Array) -> PackedInt32Array:
	# Donor 34ef460: triangulate in a centered, latitude-correct local plane.
	var bounds := lon_lat_bounds([polygon])
	var center := bounds.get_center()
	var scale_x := maxf(cos(deg_to_rad(center.y)), 0.15) if absf(center.y) > HIGH_LATITUDE else 1.0
	var local := PackedVector2Array()
	for point: Vector2 in polygon:
		local.append(Vector2((point.x - center.x) * scale_x, point.y - center.y))
	return Geometry2D.triangulate_polygon(local)

static func tessellate_triangle(triangle: PackedVector2Array, depth: int = 0) -> Array[PackedVector2Array]:
	# Split only overlong edges. Neighbours use the same edge criterion and
	# midpoint, instead of independently subdividing all three edges (T-junctions).
	var split_edge := -1
	var maximum_ratio := 1.0
	var units := to_unit_line(triangle)
	for edge: int in range(3):
		var a := triangle[edge]
		var b := triangle[(edge + 1) % 3]
		if units[edge].distance_squared_to(units[(edge+1)%3])<=SURFACE_EDGE_CHORD_SQUARED and absf(a.x-b.x)<=SURFACE_LONGITUDE_DEGREES: continue
		var angular_length := rad_to_deg(units[edge].angle_to(units[(edge + 1) % 3]))
		var ratio := maxf(angular_length / SURFACE_EDGE_DEGREES, absf(a.x - b.x) / SURFACE_LONGITUDE_DEGREES)
		if ratio > maximum_ratio:
			maximum_ratio = ratio
			split_edge = edge
	if split_edge < 0:
		return [triangle]
	if depth >= 24:
		push_error("Globe source edge exceeded tessellation depth")
		return []
	var a := triangle[split_edge]
	var b := triangle[(split_edge + 1) % 3]
	var midpoint := (a + b) * 0.5
	var opposite := triangle[(split_edge + 2) % 3]
	var output := tessellate_triangle(PackedVector2Array([a, midpoint, opposite]), depth + 1)
	output.append_array(tessellate_triangle(PackedVector2Array([midpoint, b, opposite]), depth + 1))
	return output

static func source_mesh(parts: Array, feature_id: String) -> Dictionary:
	var triangles: Array[Dictionary] = []
	var borders: Array[PackedVector3Array] = []
	if parts.is_empty():
		return {"triangles": triangles, "borders": borders}
	var reference := 0.0
	var largest := 0
	for part: Dictionary in parts:
		var outer := part.outer as PackedVector2Array
		if outer.size() > largest:
			largest = outer.size()
			reference = outer[0].x
	var prepared: Array[Dictionary] = []
	var outers: Array[PackedVector2Array] = []
	for part: Dictionary in parts:
		var outer := unwrap_ring(part.outer as PackedVector2Array, reference)
		if outer.size() < 3:
			push_error("Globe geometry %s component %d: invalid exterior after unwrap" % [feature_id, prepared.size()])
			continue
		var holes: Array[PackedVector2Array] = []
		for raw: PackedVector2Array in part.holes:
			holes.append(unwrap_ring(raw, reference))
		prepared.append({"outer": outer, "holes": holes, "component_index": prepared.size()})
		outers.append(outer)
		for ring: PackedVector2Array in [outer] + holes:
			var closed := ring.duplicate()
			closed.append(closed[0])
			var line := display_line(closed)
			borders.append(line)
	if outers.is_empty():
		return {"triangles": triangles, "borders": borders}
	var uv_bounds := lon_lat_bounds(outers)
	uv_bounds.size.x = maxf(uv_bounds.size.x, SOURCE_EPSILON)
	uv_bounds.size.y = maxf(uv_bounds.size.y, SOURCE_EPSILON)
	for part: Dictionary in prepared:
		var holes := part.holes as Array[PackedVector2Array]
		var pieces := subtract_holes(partition_polygon(part.outer as PackedVector2Array), holes)
		var component_start := triangles.size()
		for piece: PackedVector2Array in pieces:
			var indices := triangulate_piece(piece)
			if indices.is_empty():
				push_error("Globe geometry %s component %d: triangulation rejected prepared exterior" % [feature_id, part.component_index])
				continue
			for index: int in range(0, indices.size(), 3):
				var planar := PackedVector2Array([piece[indices[index]], piece[indices[index + 1]], piece[indices[index + 2]]])
				for child: PackedVector2Array in tessellate_triangle(planar):
					var uvs := PackedVector2Array()
					for point: Vector2 in child:
						var uv := (point - uv_bounds.position) / uv_bounds.size
						uvs.append(Vector2(uv.x, 1.0 - uv.y))
					triangles.append({"points": to_unit_line(child), "uvs": uvs, "component_index": part.component_index})
		if triangles.size() == component_start:
			push_error("Globe geometry %s component %d: no surface survived source preparation" % [feature_id, part.component_index])
	return {"triangles": triangles, "borders": borders, "uv_bounds": uv_bounds}

static func source_reference(parts: Array, feature_id: String) -> Dictionary:
	# Historical identity queries need rings and flag frames, not a second
	# globally triangulated/sphere-subdivided land surface.
	var reference := 0.0
	var largest := 0
	for part: Dictionary in parts:
		if (part.outer as PackedVector2Array).size()>largest:
			largest = (part.outer as PackedVector2Array).size()
			reference = (part.outer as PackedVector2Array)[0].x
	var prepared: Array[Dictionary] = []
	var borders: Array[PackedVector3Array] = []
	var outers: Array[PackedVector2Array] = []
	var main_bounds := Rect2()
	var main_area := -1.0
	for part: Dictionary in parts:
		var outer := unwrap_ring(part.outer as PackedVector2Array,reference)
		if outer.size()<3: continue
		var holes: Array[PackedVector2Array] = []
		for ring: PackedVector2Array in part.holes: holes.append(unwrap_ring(ring,reference))
		var bounds := lon_lat_bounds([outer])
		var box := AABB(lon_lat_to_unit(outer[0]),Vector3.ZERO)
		for point: Vector2 in outer: box = box.expand(lon_lat_to_unit(point))
		var axis := box.get_center()
		var component := {"outer":outer,"holes":holes,"bounds":bounds,"feature_id":feature_id,"cull_axis":axis.normalized(),"cull_angle":acos(clampf(axis.length()-box.size.length()*0.5,-1.0,1.0)),"borders":[]}
		prepared.append(component)
		outers.append(outer)
		var area := polygon_area(outer)
		for hole: PackedVector2Array in holes: area -= polygon_area(hole)
		area *= maxf(0.0,cos(deg_to_rad(bounds.get_center().y)))
		if area>main_area:
			main_area = area
			main_bounds = bounds
		for ring: PackedVector2Array in [outer]+holes:
			var closed := ring.duplicate()
			closed.append(closed[0])
			var line := display_line(closed)
			borders.append(line)
			(component.borders as Array).append(line)
	var frame := lon_lat_bounds(outers)
	frame.size = frame.size.max(Vector2.ONE*SOURCE_EPSILON)
	var flag := Rect2((main_bounds.position-frame.position)/frame.size,main_bounds.size/frame.size)
	flag.position.y = 1.0-flag.end.y
	flag.size = flag.size.max(Vector2.ONE*SOURCE_EPSILON)
	return {"parts":prepared,"borders":borders,"uv_bounds":frame,"flag_bounds":flag}

static func edge_key(a: Vector3, b: Vector3) -> String:
	var first := str(Vector3i(roundi(a.x * 1000000.0), roundi(a.y * 1000000.0), roundi(a.z * 1000000.0)))
	var second := str(Vector3i(roundi(b.x * 1000000.0), roundi(b.y * 1000000.0), roundi(b.z * 1000000.0)))
	return first + ":" + second if first < second else second + ":" + first

static func boundary_sources(meshes: Dictionary, features: Dictionary) -> Array[Dictionary]:
	# Only original geographic ring edges participate. Cell cuts and triangle
	# edges never enter this pass. Shared country edges are emitted once.
	var owners_by_edge: Dictionary = {}
	for entity_id: String in features:
		for ring: PackedVector3Array in meshes[features[entity_id]].borders:
			for index: int in range(ring.size() - 1):
				var key := edge_key(ring[index], ring[index + 1])
				if not owners_by_edge.has(key):
					owners_by_edge[key] = PackedStringArray()
				var owners := owners_by_edge[key] as PackedStringArray
				if not entity_id in owners:
					owners.append(entity_id)
				owners_by_edge[key] = owners
	var output: Array[Dictionary] = []
	var emitted: Dictionary = {}
	for entity_id: String in features:
		for ring: PackedVector3Array in meshes[features[entity_id]].borders:
			var points := PackedVector3Array()
			var current_owners := PackedStringArray()
			for index: int in range(ring.size() - 1):
				var key := edge_key(ring[index], ring[index + 1])
				var owners := owners_by_edge[key] as PackedStringArray
				if emitted.has(key) or owners != current_owners:
					if points.size() > 1:
						output.append({"points": points, "owners": current_owners})
					points = PackedVector3Array()
				current_owners = owners
				if emitted.has(key):
					continue
				emitted[key] = true
				if points.is_empty():
					points.append(ring[index])
				points.append(ring[index + 1])
			if points.size() > 1:
				output.append({"points": points, "owners": current_owners})
	return output
