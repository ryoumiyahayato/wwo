extends RefCounted

var _generation: int
var _mutex := Mutex.new()

func invalidate() -> int:
	_mutex.lock()
	_generation += 1
	var generation := _generation
	_mutex.unlock()
	return generation

func _overlay_current(generation: int) -> bool:
	_mutex.lock()
	var current := generation==_generation
	_mutex.unlock()
	return current

func prepare(rows: Array[Dictionary], query: Dictionary, topology: LandTopology, view: Rect2, revision: int, generation: int, physical_water: Array[Dictionary]) -> Dictionary:
	var uploads: Array[Dictionary] = []
	var query_components: Array = []
	var water_cuts: Array[Dictionary] = []
	if not rows.is_empty():
		water_cuts = _overlay_water_cuts(physical_water,topology,view,generation)
	for row: Dictionary in rows:
		if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
		var components: Array = []
		var paths: Array[Dictionary] = []
		if row.kind in ["sovereignty","control"]:
			paths = _current_shared_paths(row,topology,generation)
		elif str(row.get("basis",""))=="current_members":
			paths = _member_overlay_paths(row,topology,view,generation)
		else:
			var document := AdministrativeLoader.department_geometry(row.descriptor,str(row.lod))
			if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
			for part: Array in document.get("display_pick_polygons",document.get("local_polygons",[])) as Array:
				var rings: Array[PackedVector2Array] = []
				for raw: Variant in part: rings.append(topology._polygon_from_value(raw))
				components.append(rings)
			if str(row.id)==str(query.get("id","")) and row.lod=="detail":
				for part: Array in document.get("local_polygons",[]) as Array:
					var rings: Array[PackedVector2Array] = []
					for raw: Variant in part: rings.append(topology._polygon_from_value(raw))
					query_components.append(rings)
			var display_rings: Array[Dictionary] = []
			if document.has("display_lines"):
				var field := "display_outline_lines" if row.get("variant","")=="outline" else "display_lines"
				for raw: Array in document.get(field,[]) as Array: display_rings.append({"points":topology._polygon_from_value(raw),"closed":false})
			else:
				for part: Array in components:
					for ring: PackedVector2Array in part: display_rings.append({"points":ring,"closed":true})
			for display_ring: Dictionary in display_rings:
				var ring := display_ring.points as PackedVector2Array
				if ring.size()<2: continue
				var edges := ring.size() if bool(display_ring.closed) else ring.size()-1
				var points := PackedVector3Array()
				for index: int in range(edges):
					var a := ring[index]
					var b := ring[(index+1)%ring.size()]
					if view.intersects(Rect2(a,Vector2.ZERO).expand(b),true):
						if points.is_empty(): points.append(GlobeProjection.lon_lat_to_unit(topology.to_geographic(a)))
						points.append_array(_projected_overlay_segment(a,b,topology,str(row.lod)=="detail").slice(1))
					elif points.size()>1:
						paths.append({"points":points}); points = PackedVector3Array()
					if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
				if points.size()>1: paths.append({"points":points})
		# Both inputs are historical land-boundary ink, not maritime claims.
		# Apply the same installed physical-water display cut to both.
		if not water_cuts.is_empty(): paths = _clip_overlay_water(paths,water_cuts,generation)
		var lines: Array[Dictionary] = []
		var segments := 0
		var chunks: Array[Dictionary] = []
		for path: Dictionary in paths:
			var points := path.points as PackedVector3Array
			var loop := points.size()>2 and points[0].is_equal_approx(points[-1])
			var start := 0
			while start<points.size()-1:
				var end := mini(start+256,points.size()-1)
				var line := {"kind":"overlay","points":points.slice(start,end+1)}
				if start>0: line["before"] = points[start-1]
				elif loop: line["before"] = points[-2]
				elif path.has("before"): line["before"] = path.before
				if end<points.size()-1: line["after"] = points[end+1]
				elif loop: line["after"] = points[1]
				elif path.has("after"): line["after"] = path.after
				lines.append(line)
				segments += end-start
				start = end
				if segments>=2048:
					chunks.append(_encode_overlay_chunk(lines))
					lines = []; segments = 0
				if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
		if not lines.is_empty(): chunks.append(_encode_overlay_chunk(lines))
		if chunks.is_empty(): chunks.append({})
		for index: int in range(chunks.size()):
			uploads.append({"id":row.id,"kind":row.kind,"level":row.get("level",1),"lod":row.lod,"variant":row.get("variant",""),"encoded":chunks[index],"last":index==chunks.size()-1,"basis":row.get("basis",""),"owners":row.get("owners",[]),"components":components if index==chunks.size()-1 and row.kind=="administration" else []})
	var overlaps: Dictionary = {}
	if not query.is_empty() and _overlay_current(generation):
		if query_components.is_empty():
			for part: Array in AdministrativeLoader.department_geometry(query.descriptor,"detail").get("local_polygons",[]) as Array:
				var rings: Array[PackedVector2Array] = []
				for raw: Variant in part: rings.append(topology._polygon_from_value(raw))
				query_components.append(rings)
		for id: String in query.polygons:
			if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
			var points := query.polygons[id] as PackedVector2Array
			var overlap := 0.0
			var bounds := LandTopology._polygon_bounds(points)
			for part: Array in query_components:
				if not bounds.intersects(LandTopology._polygon_bounds(part[0]),true): continue
				overlap += topology._intersection_area(points,part[0])
				for index: int in range(1,part.size()): overlap -= topology._intersection_area(points,part[index])
			if overlap>0.0: overlaps[id] = overlap
	return {"generation":generation,"uploads":uploads,"query":str(query.get("id","")),"overlaps":overlaps,"revision":revision}

static func _encode_overlay_chunk(lines: Array[Dictionary]) -> Dictionary:
	var result := GlobeBoundaryBatch.encode(lines,"overlay",true)
	var box := AABB()
	var first := true
	for line: Dictionary in lines:
		for point: Vector3 in line.points:
			box=AABB(point,Vector3.ZERO) if first else box.expand(point)
			first=false
	var axis := box.get_center().normalized()
	var minimum_dot := 1.0
	for line: Dictionary in lines:
		for point: Vector3 in line.points: minimum_dot=minf(minimum_dot,axis.dot(point))
	result["cull_axis"]=axis
	result["cull_angle"]=acos(clampf(minimum_dot,-1.0,1.0))+.000001
	return result

func _overlay_water_cuts(features: Array[Dictionary], topology: LandTopology, view: Rect2, generation: int) -> Array[Dictionary]:
	# Installed physical water polygons only. These cuts affect ink, never
	# historical GIS, political membership or the separate picking components.
	var result: Array[Dictionary] = []
	if not view.has_area(): return result
	var reference := topology.to_geographic(view.get_center()).x
	var origin := topology.to_geographic(view.position)
	origin.x = reference+wrapf(origin.x-reference,-180.0,180.0)
	var geographic_view := Rect2(origin,Vector2.ZERO)
	for point: Vector2 in [view.end,Vector2(view.end.x,view.position.y),Vector2(view.position.x,view.end.y),view.get_center()]:
		var coordinate := topology.to_geographic(point)
		coordinate.x = reference+wrapf(coordinate.x-reference,-180.0,180.0)
		geographic_view = geographic_view.expand(coordinate)
	if geographic_view.size.x>180.0: return result
	var shift := Transform2D(0.0,-geographic_view.get_center())
	for feature: Dictionary in features:
		for part: Array in (feature.geometry as Dictionary).coordinates as Array:
			if not _overlay_current(generation): return []
			var rings: Array[PackedVector2Array] = []
			for raw: Array in part:
				var ring := PackedVector2Array()
				for coordinate: Array in raw: ring.append(Vector2(float(coordinate[0]),float(coordinate[1])))
				rings.append(GlobeProjection.unwrap_ring(ring,reference))
			if rings.is_empty() or not geographic_view.intersects(GlobeProjection.lon_lat_bounds([rings[0]]),true): continue
			var holes: Array[Dictionary] = []
			for index: int in range(1,rings.size()):
				var hole := shift*rings[index]
				holes.append({"polygon":hole,"bounds":GlobeProjection.lon_lat_bounds([hole])})
			var exterior := shift*rings[0]
			result.append({"polygon":exterior,"holes":holes,"bounds":GlobeProjection.lon_lat_bounds([exterior]),"shift":shift})
	return result

func _clip_overlay_water(paths: Array[Dictionary], cuts: Array[Dictionary], generation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var shift := cuts[0].shift as Transform2D
	var reference := -shift.origin.x
	for path: Dictionary in paths:
		var line := PackedVector2Array()
		# The path and water must occupy the same longitude copy. Normalized
		# +/-180 coordinates otherwise turn a short coastal segment into a chord.
		for point: Vector3 in path.points as PackedVector3Array:
			var coordinate := RegionProjection.lon_lat(point)
			coordinate.x = reference+wrapf(coordinate.x-reference,-180.0,180.0)
			line.append(coordinate)
		var shifted := shift*line
		var bounds := GlobeProjection.lon_lat_bounds([shifted])
		var candidates: Array[Dictionary] = []
		for cut: Dictionary in cuts:
			if (cut.bounds as Rect2).intersects(bounds,true): candidates.append(cut)
		if candidates.is_empty():
			result.append(path)
			continue
		var pieces: Array[PackedVector2Array] = [shifted]
		for cut: Dictionary in candidates:
			if not _overlay_current(generation): return []
			var next: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces:
				if not (cut.bounds as Rect2).intersects(GlobeProjection.lon_lat_bounds([piece]),true): next.append(piece)
				else:
					# W = exterior minus land holes. Keep outside(exterior) plus
					# inside(each hole), without triangulating or subtracting global
					# water polygons again just to clip a bounded historical line.
					next.append_array(Geometry2D.clip_polyline_with_polygon(piece,cut.polygon))
					var piece_bounds := GlobeProjection.lon_lat_bounds([piece])
					for hole: Dictionary in cut.holes:
						if not _overlay_current(generation): return []
						if (hole.bounds as Rect2).intersects(piece_bounds,true):
							next.append_array(Geometry2D.intersect_polyline_with_polygon(piece,hole.polygon))
			pieces = next
			if pieces.is_empty(): break
		for piece: PackedVector2Array in pieces:
			if piece.size()>1: result.append({"points":GlobeProjection.display_line(shift.affine_inverse()*piece)})
	return result

func _projected_overlay_segment(a: Vector2, b: Vector2, topology: LandTopology, detail: bool) -> PackedVector3Array:
	# Historical GIS segments are straight in their source chart, not in the
	# current screen projection. Sample that same segment; never snap it to a coast.
	var steps := maxi(1,ceili(a.distance_to(b)/(2000.0 if detail else 12000.0)))
	var points := PackedVector3Array()
	for step: int in range(steps+1):
		points.append(GlobeProjection.lon_lat_to_unit(topology.to_geographic(a.lerp(b,float(step)/steps))))
	return points



func _current_shared_paths(row: Dictionary, topology: LandTopology, generation: int) -> Array[Dictionary]:
	# Only a real shared edge of two known formal units can become this border.
	# Unknown exterior coverage is not filled in as an invented national frontier.
	var result: Array[Dictionary] = []
	var first := row.polygons[0] as PackedVector2Array
	var second := row.polygons[1] as PackedVector2Array
	for index: int in range(first.size()):
		var a := first[index]
		var b := first[(index+1)%first.size()]
		var direction := b-a
		var length_squared := direction.length_squared()
		if length_squared<=0.0: continue
		for edge: int in range(second.size()):
			if not _overlay_current(generation): return []
			var c := second[edge]
			var d := second[(edge+1)%second.size()]
			if absf(direction.cross(c-a))/sqrt(length_squared)>0.01 or absf(direction.cross(d-a))/sqrt(length_squared)>0.01: continue
			var low := clampf(minf((c-a).dot(direction),(d-a).dot(direction))/length_squared,0.0,1.0)
			var high := clampf(maxf((c-a).dot(direction),(d-a).dot(direction))/length_squared,0.0,1.0)
			if high>low: result.append({"points":_projected_overlay_segment(a.lerp(b,low),a.lerp(b,high),topology,true)})
	return result

func _member_overlay_paths(row: Dictionary, topology: LandTopology, view: Rect2, generation: int) -> Array[Dictionary]:
	# Remove only shared edges of actual members. Unknown land remains outside the outline.
	var result: Array[Dictionary] = []
	for id: String in row.polygons:
		var ring := row.polygons[id] as PackedVector2Array
		for index: int in range(ring.size()):
			if not _overlay_current(generation): return []
			var a := ring[index]
			var b := ring[(index+1)%ring.size()]
			if not view.intersects(Rect2(a,Vector2.ZERO).expand(b),true): continue
			var direction := b-a
			var length_squared := direction.length_squared()
			if length_squared<=0.0: continue
			var covered: Array[Vector2] = []
			var cuts: Array[float] = [0.0,1.0]
			for neighbor: PackedVector2Array in row.neighbors.get(id,[]):
				for edge: int in range(neighbor.size()):
					var c := neighbor[edge]
					var d := neighbor[(edge+1)%neighbor.size()]
					if absf(direction.cross(c-a))/sqrt(length_squared)>0.01 or absf(direction.cross(d-a))/sqrt(length_squared)>0.01: continue
					var low := clampf(minf((c-a).dot(direction),(d-a).dot(direction))/length_squared,0.0,1.0)
					var high := clampf(maxf((c-a).dot(direction),(d-a).dot(direction))/length_squared,0.0,1.0)
					if high<=low: continue
					covered.append(Vector2(low,high)); cuts.append(low); cuts.append(high)
			cuts.sort()
			for interval: int in range(cuts.size()-1):
				if cuts[interval+1]<=cuts[interval]: continue
				var midpoint := (cuts[interval]+cuts[interval+1])*0.5
				var shared := false
				for span: Vector2 in covered:
					if midpoint>=span.x and midpoint<=span.y: shared = true; break
				if shared: continue
				result.append({"points":_projected_overlay_segment(a.lerp(b,cuts[interval]),a.lerp(b,cuts[interval+1]),topology,str(row.lod)=="detail")})
	return result
