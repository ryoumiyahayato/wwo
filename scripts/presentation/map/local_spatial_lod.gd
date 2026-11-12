class_name LocalSpatialLod
extends RefCounted
## Finite load-time caches derived from admitted facts, never new source facts.
const TOLERANCE_M: Dictionary = {"coarse": 600.0, "medium": 120.0, "local": 0.0}
const EARTH_RADIUS_M: float = 6371008.8

static func prepare(content: LocalSpatialContent, lods: Array[String] = ["coarse", "medium", "local"], current: Callable = Callable(), ink_frames: Dictionary = {}, political_cells: Dictionary = {}, only_features: Array[String] = []) -> Dictionary:
	# Hold immutable source references inside this worker. The installed layer
	# may keep the old Content alive until its complete successor is displayed.
	content.geometry_mutex.lock()
	var source := content.line_chunks
	var source_features := content.features
	content.geometry_mutex.unlock()
	var chunks: Array[Dictionary] = []
	# Only actual legal-sovereign changes alter the initial display partition.
	var changed_cells: Dictionary = {}
	for id: String in political_cells:
		if bool((political_cells[id] as Dictionary).get("sovereignty_changed",true)): changed_cells[id] = political_cells[id]
	for lod_name: String in lods:
		if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[],"cancelled":true}
		if bool(content.metadata.get("physical_foundation",false)):
			var coverage := false
			for feature: Dictionary in source_features:
				if str(feature.kind) in ["land_reference","ocean_reference"] and lod_name in (feature.get("presentation_lods",[]) as Array):
					coverage = true
					break
			if not coverage: return {"error":"物理分片不包含请求的LOD："+lod_name}
		var groups: Dictionary = {}
		var group_styles: Dictionary = {}
		var surface_groups: Dictionary = {}
		var counts: Dictionary = {}
		for chunk: Dictionary in source:
			if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[],"cancelled":true}
			if chunk.has("lod") and str(chunk.lod) != lod_name:
				continue
			if chunk.has("compiled_asset"):
				if not only_features.is_empty() and str(chunk.land_feature_id) not in only_features: continue
				var compiled := _prepared_display(chunk,changed_cells,only_features,ink_frames,current)
				if compiled.has("error"): return compiled
				chunks.append_array(compiled.chunks as Array)
				continue
			var kind := str(chunk.kind)
			if not only_features.is_empty() and str(chunk.get("feature_id","")) not in only_features: continue
			if chunk.has("polygons"):
				var faces: Array[Dictionary] = []
				var precomputed := str(chunk.get("lod_geometry_role",""))=="PRECOMPUTED_DISPLAY_TRIANGLES"
				if precomputed:
					var face_index := 0
					# These are already constrained source triangles. Re-running the
					# polygon pipeline both wastes work and rejects subpixel slivers
					# that collapse in Godot's float32 vectors. Degenerate display
					# faces have no area; no source or territorial polygon is edited.
					for polygon: Array in chunk.polygons as Array:
						if face_index%128==0 and (content.cancelled or (current.is_valid() and not current.call())): return {"chunks":[],"lods":[],"cancelled":true}
						var reference := ""
						var ink_indices := chunk.get("ink_indices",[]) as Array
						if face_index<ink_indices.size(): reference = str((chunk.ink_references as Array)[int(ink_indices[face_index])])
						face_index += 1
						if not ink_frames.has(reference): reference = ""
						var ring := polygon[0] as Array
						var triangle := PackedVector2Array()
						for point: Array in ring.slice(0,3): triangle.append(Vector2(float(point[0]),float(point[1])))
						if GlobeProjection.polygon_area(triangle)<=0.0: continue
						var component_frame := _component_frame(ink_frames.get(reference),triangle)
						# The water branch must retain the same typed container as the
						# land branch; an untyped ternary literal aborts this worker.
						var pieces: Array[Dictionary] = []
						if kind=="land_reference":
							pieces = _political_pieces(triangle,reference,changed_cells)
						else:
							pieces.append({"ring":triangle,"reference":reference})
						if not changed_cells.is_empty():
							var source_area := GlobeProjection.polygon_area(triangle)
							var display_area := 0.0
							for piece: Dictionary in pieces: display_area += GlobeProjection.polygon_area(piece.ring as PackedVector2Array)
							if absf(display_area-source_area)>maxf(source_area*0.0001,0.0000000001):
								return {"error":"当前政治分区未保留完整物理三角形；保留已安装物理底图。"}
						for piece: Dictionary in pieces:
							var ring_piece := piece.ring as PackedVector2Array
							var indices := PackedInt32Array([0,1,2]) if ring_piece.size()==3 else GlobeProjection.triangulate_piece(ring_piece)
							if indices.is_empty(): return {"chunks":[],"lods":[],"error":"政治显示分区无法三角化；保留上一有效地图。"}
							for first: int in range(0,indices.size(),3):
								var planar := PackedVector2Array([ring_piece[indices[first]],ring_piece[indices[first+1]],ring_piece[indices[first+2]]])
								for child: PackedVector2Array in GlobeProjection.tessellate_triangle(planar):
									var uvs := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
									var ink := str(piece.reference)
									var original := str(piece.get("original_reference",""))
									if component_frame.has_area():
										var frame := component_frame
										var longitude := (child[0].x+child[1].x+child[2].x)/3.0
										var wrap := 360.0*roundf((frame.get_center().x-longitude)/360.0)
										for corner: int in range(3):
											var point := child[corner]
											point.x += wrap
											var uv := (point-frame.position)/frame.size
											uvs[corner] = Vector2(uv.x,1.0-uv.y)
									faces.append({"points":GlobeProjection.to_unit_line(child),"uvs":uvs,"component_index":0,"ink_reference":ink,"original_ink_reference":original})
				for polygon: Array in chunk.polygons as Array:
					if precomputed: break
					var rings: Array[PackedVector2Array] = []
					for ring: Array in polygon:
						var points := PackedVector2Array()
						for coordinate: Array in ring:
							points.append(Vector2(float(coordinate[0]), float(coordinate[1])))
						if points.size() > 3 and points[0].is_equal_approx(points[-1]): points.resize(points.size()-1)
						rings.append(points)
					if not rings.is_empty():
						var mesh := GlobeProjection.source_mesh([{ "outer": rings[0], "holes": rings.slice(1)}], str(chunk.feature_id))
						faces.append_array(mesh.triangles as Array[Dictionary])
				# Limit a single upload step; exact offline patch triangles need no
				# camera-time topology or second political geometry.
				# A complete physical partition is drawn once. References identify
				# exact historical intersections, never a nearby country donor.
				var water_class := HydrographyStyle.surface_class(chunk)
				var water_transition := HydrographyStyle.surface_transition(str(chunk.feature_id))
				for face: Dictionary in faces:
					var reference := str(face.get("ink_reference",""))
					var original := str(face.get("original_ink_reference",""))
					face.erase("original_ink_reference")
					face.erase("ink_reference")
					var key := kind+":"+water_class+":"+str(water_transition)+":"+reference+":"+original+(":"+str(chunk.feature_id) if kind=="land_reference" else "")
					if not surface_groups.has(key): surface_groups[key] = {"kind":kind,"water_class":water_class,"water_transition":water_transition,"faces":[],"feature_ids":[],"ink_reference":reference,"original_ink_reference":original}
					(surface_groups[key].faces as Array).append(face)
					if chunk.feature_id not in surface_groups[key].feature_ids: (surface_groups[key].feature_ids as Array).append(chunk.feature_id)
				continue
			var stroke_scale := float(chunk.get("stroke_scale",1.0))
			var replacement_key := str(chunk.get("feature_id","")) if str(chunk.get("feature_id",""))=="river:seine" else ""
			var water_style := str(chunk.get("water_line_style",""))
			var line_group := kind+":"+str(stroke_scale)+":"+replacement_key+"|"+water_style
			if not groups.has(line_group):
				groups[line_group] = []
				group_styles[line_group] = {"kind":kind,"lod":lod_name,"stroke_scale":stroke_scale,"replacement_key":replacement_key,"water_line_style":water_style}
				counts[line_group] = 0
			for boundary: Dictionary in chunk.boundaries as Array:
				var points := boundary.points as PackedVector3Array
				var parts: Array[PackedVector3Array] = [points]
				if kind=="coast" and str(boundary.feature_id).begins_with("coast:physical_") and str(boundary.feature_id).get_slice("_",2)=="0":
					parts = _without_polar_closure(points)
				for line_points: PackedVector3Array in parts:
					if lod_name != "local" and not chunk.has("lod"):
						line_points = simplify(line_points, float(TOLERANCE_M[lod_name]))
					if kind=="river" and lod_name=="local" and not content.surface_reference.is_empty():
						line_points = _sample_chart_line(line_points,content.surface_reference)
					if line_points.size() < 2:
						continue
					var prepared_line := {"kind":kind, "points":line_points, "feature_id":boundary.feature_id, "source_fact_id":boundary.get("source_fact_id", "local_spatial:" + str(boundary.feature_id))}
					if boundary.has("before") and line_points[0]==points[0]: prepared_line["before"] = boundary.before
					if boundary.has("after") and line_points[-1]==points[-1]: prepared_line["after"] = boundary.after
					# Split before admission. A complete river must not overrun an
					# upload budget just because its source is one long polyline.
					var batch_limit: int = 1024 if chunk.has("lod") else 256
					var first: int = 0
					var last: int = line_points.size()-1
					var closed: bool = line_points.size()>2 and line_points[0].is_equal_approx(line_points[last])
					while first<last:
						if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[],"cancelled":true}
						var end: int = mini(last,first+mini(128,batch_limit-int(counts[line_group])))
						var part: Dictionary = prepared_line.duplicate()
						part["points"] = line_points.slice(first,end+1)
						# Neighbours span slices, so slicing creates no artificial caps
						# or changed joins. Original endpoint neighbours retain priority.
						if first>0: part["before"] = line_points[first-1]
						elif closed and not part.has("before"): part["before"] = line_points[last-1]
						if end<last: part["after"] = line_points[end+1]
						elif closed and not part.has("after"): part["after"] = line_points[1]
						(groups[line_group] as Array).append(part)
						counts[line_group] += end-first
						first = end
						if int(counts[line_group])==batch_limit:
							chunks.append((group_styles[line_group] as Dictionary).merged({"boundaries":groups[line_group]}))
							groups[line_group] = []
							counts[line_group] = 0
		for key: String in surface_groups:
			var group := surface_groups[key] as Dictionary
			var faces := group.faces as Array
			for first: int in range(0,faces.size(),2048):
				chunks.append({"kind":group.kind,"lod":lod_name,"faces":faces.slice(first,first+2048),"feature_id":group.feature_ids[0],"source_feature_ids":group.feature_ids,"water_class":group.water_class,"water_transition":group.water_transition,"ink_reference":group.ink_reference,"source_feature_id":group.feature_ids[0],"original_ink_reference":group.original_ink_reference,"component_uv":group.kind=="land_reference"})
		for key: String in groups:
			if not (groups[key] as Array).is_empty():
				chunks.append((group_styles[key] as Dictionary).merged({"boundaries":groups[key]}))
	for chunk: Dictionary in chunks:
		if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[],"cancelled":true}
		if chunk.has("payload"): continue # Native packed arrays already encoded offline.
		var bounds := AABB()
		var initialized := false
		var arrays: Array[PackedVector3Array] = []
		if chunk.has("faces"):
			for face: Dictionary in chunk.faces: arrays.append(face.points as PackedVector3Array)
		else:
			for boundary: Dictionary in chunk.boundaries: arrays.append(boundary.points as PackedVector3Array)
		for points: PackedVector3Array in arrays:
			for point: Vector3 in points:
				if not initialized:
					bounds = AABB(point,Vector3.ZERO)
					initialized = true
				else: bounds = bounds.expand(point)
		var center := bounds.get_center()
		var lower_dot := center.length() - bounds.size.length()*0.5
		chunk["cull_axis"] = center.normalized()
		chunk["cull_angle"] = acos(clampf(lower_dot,-1.0,1.0)) + deg_to_rad(GlobeProjection.SURFACE_EDGE_DEGREES)
		if chunk.has("faces"):
			chunk["face_count"] = (chunk.faces as Array).size()
			# Keep bounded visible land faces for geographic feedback, not sovereignty.
			# Physical queries use the installed source polygon, not another
			# permanent dictionary and UV array for every displayed triangle.
			chunk["payload"] = GlobeSurfaceBatch.encode(chunk.faces as Array,false)
			if (chunk.payload as Dictionary).has("error"): return {"error":str(chunk.payload.error)+" "+str(chunk.get("source_feature_id",""))}
			chunk["face_count"] = int((chunk.payload as Dictionary).get("face_count",0))
			chunk.erase("faces")
		else:
			var boundaries: Array[Dictionary] = []
			boundaries.assign(chunk.boundaries as Array)
			chunk["payload"] = GlobeBoundaryBatch.encode(boundaries,str(chunk.kind),str(chunk.kind) in ["coast","river"])
			chunk.erase("boundaries")
	# All float32-degenerate faces may legitimately encode to no draw. Omit
	# those empty batches here; an actual upload failure must not be ignored.
	for index: int in range(chunks.size()-1,-1,-1):
		if (chunks[index].payload as Dictionary).is_empty(): chunks.remove_at(index)
	return {"chunks":chunks, "lods":lods}

static func _component_frame(description: Variant, triangle: PackedVector2Array) -> Rect2:
	if description is Rect2: return description
	if not description is Dictionary: return Rect2()
	var center := (triangle[0]+triangle[1]+triangle[2])/3.0
	for component: Dictionary in (description as Dictionary).get("components",[]) as Array:
		var bounds := component.bounds as Rect2
		var point := center
		point.x += 360.0*roundf((bounds.get_center().x-point.x)/360.0)
		if bounds.grow(GlobeProjection.SOURCE_EPSILON).has_point(point) and Geometry2D.is_point_in_polygon(point,component.outer as PackedVector2Array):
			var in_hole := false
			for hole: PackedVector2Array in component.get("holes",[]) as Array:
				if Geometry2D.is_point_in_polygon(point,hole): in_hole = true; break
			if in_hole: continue
			# All fragments of this original connected polygon share its frame,
			# across physical tiles and both display LODs. No territorial change.
			bounds.size = bounds.size.max(Vector2.ONE*GlobeProjection.SOURCE_EPSILON)
			return bounds
	# Numerical boundary misses keep the previous largest-component frame,
	# never regress to an entity's global envelope for a remote island.
	var frame := (description as Dictionary).get("frame",Rect2()) as Rect2
	var flag := (description as Dictionary).get("flag",Rect2(Vector2.ZERO,Vector2.ONE)) as Rect2
	return Rect2(frame.position+Vector2(flag.position.x,1.0-flag.end.y)*frame.size,flag.size*frame.size)

static func _prepared_display(source: Dictionary, cells: Dictionary, only: Array[String], frames: Dictionary, current: Callable) -> Dictionary:
	var decoded := StrategicSpatialLoader.read_display(source.compiled_asset as Dictionary,str(source.shard_id),str(source.lod))
	if decoded.has("error"): return decoded
	var result: Array[Dictionary] = []
	var dynamic := false
	var bounds := source.bounds as Rect2
	for id: String in cells:
		if bounds.intersects((cells[id] as Dictionary).bounds as Rect2,true): dynamic = true; break
	for chunk: Dictionary in decoded.chunks as Array:
		# R37 coalesces the coast inside one physical shard and omits its
		# feature ID. Recover that exact ID from the validated shard header so
		# incremental additions include the coast alongside their new land.
		if str(chunk.kind)=="coast" and not chunk.has("source_feature_id"):
			chunk["source_feature_id"] = "coast:"+str(source.shard_id)
		if not only.is_empty() and str(chunk.get("source_feature_id","")) not in only: continue
		if dynamic and str(chunk.kind)=="land_reference": continue
		result.append(chunk)
	if dynamic and (only.is_empty() or str(source.land_feature_id) in only):
		# A real changed sovereign uses the original planar ink, only for this
		# affected shard. Coast, other shards and physical queries stay intact.
		var ink := StrategicSpatialLoader._read_ink(source.ink_descriptor as Dictionary)
		if ink.has("error"): return ink
		var content := LocalSpatialContent.new()
		content.line_chunks.append({"kind":"land_reference","lod":source.lod,"feature_id":source.land_feature_id,"lod_geometry_role":"PRECOMPUTED_DISPLAY_TRIANGLES","polygons":ink.triangles,"ink_indices":ink.indices,"ink_references":ink.references})
		var lods: Array[String] = [str(source.lod)]
		var prepared := prepare(content,lods,current,frames,cells)
		if prepared.has("error"): return prepared
		result.append_array(prepared.chunks as Array)
	return {"chunks":result}

static func _political_pieces(triangle: PackedVector2Array, reference: String, cells: Dictionary) -> Array[Dictionary]:
	var remaining: Array[PackedVector2Array] = [triangle]
	var result: Array[Dictionary] = []
	var bounds := GlobeProjection.lon_lat_bounds([triangle])
	for id: String in cells:
		var cell := cells[id] as Dictionary
		# Administrative initialization eligibility and control changes are not
		# evidence that the legal sovereign/flag footprint has changed.
		if not bool(cell.get("sovereignty_changed",true)): continue
		if not bounds.intersects(cell.bounds as Rect2,true): continue
		var shift := Transform2D(0.0,-bounds.get_center())
		var cut := shift*(cell.ring as PackedVector2Array)
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in remaining:
			if not (cell.bounds as Rect2).intersects(GlobeProjection.lon_lat_bounds([piece]),true):
				next.append(piece); continue
			var local := shift*piece
			for inside: PackedVector2Array in Geometry2D.intersect_polygons(local,cut):
				if GlobeProjection.polygon_area(inside)>0.0: result.append({"ring":shift.affine_inverse()*inside,"reference":id,"original_reference":reference})
			for outside: PackedVector2Array in GlobeProjection.subtract_holes([local],[cut]): next.append(shift.affine_inverse()*outside)
		remaining = next
		if remaining.is_empty(): break
	for piece: PackedVector2Array in remaining: result.append({"ring":piece,"reference":reference})
	return result

static func _sample_chart_line(points: PackedVector3Array, surface: Dictionary) -> PackedVector3Array:
	# Insert samples only along the existing line, inside the acquired DEM.
	# This supports height projection without inventing banks or a new route.
	if points.size()<2: return points
	var step := float(surface.step_degrees)
	var bounds := Rect2(Vector2(float(surface.west_cell_centre),float(surface.north_cell_centre)-(int(surface.height)-1)*step),Vector2(int(surface.width)-1,int(surface.height)-1)*step)
	var result := PackedVector3Array([points[0]])
	for index: int in range(points.size()-1):
		var a := RegionProjection.lon_lat(points[index])
		var b := RegionProjection.lon_lat(points[index+1])
		var delta := b-a
		var enter := 0.0
		var leave := 1.0
		for edge: Vector2 in [Vector2(-delta.x,a.x-bounds.position.x),Vector2(delta.x,bounds.end.x-a.x),Vector2(-delta.y,a.y-bounds.position.y),Vector2(delta.y,bounds.end.y-a.y)]:
			if is_zero_approx(edge.x):
				if edge.y<0.0: leave = -1.0
			elif edge.x<0.0: enter = maxf(enter,edge.y/edge.x)
			else: leave = minf(leave,edge.y/edge.x)
		if enter<leave:
			var count := clampi(ceili(delta.length()*(leave-enter)/step),1,256)
			for sample: int in range(count+1):
				var t := lerpf(enter,leave,float(sample)/count)
				if t>0.000001 and t<0.999999: result.append(GlobeProjection.lon_lat_to_unit(a+delta*t))
		result.append(points[index+1])
	return result

static func _without_polar_closure(points: PackedVector3Array) -> Array[PackedVector3Array]:
	# NE land's Antarctic polygon closes along the date line to the pole.
	# Its planar closure belongs to fill geometry, never a physical shoreline.
	var parts: Array[PackedVector3Array] = []
	var part := PackedVector3Array()
	for index: int in range(points.size()):
		var point := points[index]
		if index > 0:
			var previous := points[index-1]
			var closure := previous.y < -0.99 and point.y < -0.99 and absf(previous.x)<0.000001 and absf(point.x)<0.000001 and previous.z<=0.000001 and point.z<=0.000001
			if closure:
				if part.size()>=2: parts.append(part)
				part = PackedVector3Array()
		part.append(point)
	if part.size()>=2: parts.append(part)
	return parts

static func simplify(points: PackedVector3Array, tolerance_m: float) -> PackedVector3Array:
	if points.size() <= 2:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size()-1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size()-1)]
	var tolerance_squared := pow(tolerance_m / EARTH_RADIUS_M, 2.0)
	while not stack.is_empty():
		var span := stack.pop_back() as Vector2i
		var a := points[span.x]
		var delta := points[span.y] - a
		var denominator := delta.length_squared()
		var farthest: int = -1
		var maximum := tolerance_squared
		for index: int in range(span.x+1, span.y):
			var ratio := clampf((points[index]-a).dot(delta)/denominator, 0.0, 1.0) if denominator > 0.0 else 0.0
			var distance := points[index].distance_squared_to(a+delta*ratio)
			if distance > maximum:
				maximum = distance
				farthest = index
		if farthest >= 0:
			keep[farthest] = 1
			stack.append(Vector2i(span.x, farthest))
			stack.append(Vector2i(farthest, span.y))
	var result := PackedVector3Array()
	for index: int in range(points.size()):
		if keep[index] == 1:
			result.append(points[index])
	# A subpixel closed island/loop may disappear in coarse view, never become
	# a zero-length stroke. Its canonical feature and evidence remain intact.
	if result.size() == 2 and result[0].is_equal_approx(result[1]):
		return PackedVector3Array()
	return result

# One finite CPU preparation on the existing map content path. No Nodes,
# ImageTextures, materials or RenderingServer access on this worker.
static func prepare_terrain(surface: Dictionary, frame: Basis, lines: Array[Dictionary], covers: Array[Dictionary], current: Callable) -> Dictionary:
	var job := TerrainPreparation.new()
	return job.prepare(surface,frame,lines,covers,current)

static func height_grid(grid: Vector2, layout: Vector4, stride: float) -> Vector2:
	var result := grid
	for axis: int in range(2):
		var extent: float = layout[axis+2]
		result[axis] = layout[axis]+(grid[axis]/stride if grid[axis]<0.0 else extent+(grid[axis]-extent)/stride if grid[axis]>extent else grid[axis])
	return result

static func height_sample(values: PackedFloat32Array, size: Vector2i, grid: Vector2) -> float:
	var cell := Vector2i(grid.floor()).clamp(Vector2i.ZERO,size-Vector2i(2,2))
	var t := (grid-Vector2(cell)).clamp(Vector2.ZERO,Vector2.ONE)
	var a := values[cell.y*size.x+cell.x];var b := values[cell.y*size.x+cell.x+1]
	var c := values[(cell.y+1)*size.x+cell.x];var d := values[(cell.y+1)*size.x+cell.x+1]
	return a+(b-a)*t.x+(c-a)*t.y if t.x+t.y<=1.0 else d+(c-d)*(1.0-t.x)+(b-d)*(1.0-t.y)

class TerrainPreparation:
	extends RefCounted
	const COVER_MASK_SIZE: int = 256
	var _surface_reference: Dictionary = {}
	var _surface_covers: Array[Dictionary] = []
	var _surface_chart_frame := Basis()
	var _surface_chart_anchor_km := Vector2.ZERO
	var _local_surface_anchor := Vector2.ZERO
	var _surface_base_height: float = 0.0
	var _surface_vertices := PackedVector3Array()
	var _surface_ray_vertices := PackedVector3Array()
	var _surface_indices := PackedInt32Array()
	var _surface_pick_chunks: Array[Dictionary] = []
	var _surface_water_vertices := PackedVector3Array()
	var _surface_water_chunks: Array[Dictionary] = []
	var _surface_water_cells: Dictionary = {}
	var _surface_water_bytes := PackedByteArray()
	var _woodland_bytes := PackedByteArray()
	var _height_bytes := PackedByteArray()
	var _height_size := Vector2i.ZERO
	var _height_layout := Vector4.ZERO
	var _height_stride: float = 1.0
	var _height_bounds := Vector4.ZERO
	var _display_heights := PackedFloat32Array()
	var _context_water_bytes := PackedByteArray()
	var _context_water_bounds := Vector4.ZERO
	var _terrain_arrays: Array = []
	var _cover_arrays: Array = []
	var _line_arrays: Array = []
	var _woodland_positions: Array[Vector3] = []
	var _current: Callable
	var _context_image: Image
	var _context_bounds := Rect2()

	func prepare(surface: Dictionary, frame: Basis, lines: Array[Dictionary], covers: Array[Dictionary], current: Callable) -> Dictionary:
		_surface_reference = surface
		_surface_covers = covers
		_surface_chart_frame = frame
		_current = current
		var anchor := surface.anchor_lon_lat as Array
		_local_surface_anchor = Vector2(float(anchor[0]),float(anchor[1]))
		_surface_chart_anchor_km = RegionProjection.forward(GlobeProjection.lon_lat_to_unit(_local_surface_anchor),frame)
		_surface_base_height = _surface_height(_local_surface_anchor)
		var context := (surface.get("presentation",{}) as Dictionary).get("context_height_asset",{}) as Dictionary
		if not context.is_empty():
			var decoded := GeographyLoader.decode_relief("local_context", {"local_context":context})
			if not decoded.has("image"): return {"error":"外围参考高程无法解码"}
			_context_image = decoded.image
			var bounds := context.bounds_lon_lat as Array
			_context_bounds = Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2])-float(bounds[0]),float(bounds[3])-float(bounds[1]))
		if not current.call(): return {}
		_make_water_mask()
		if not current.call(): return {}
		_make_woodland_mask()
		if not current.call(): return {}
		_make_surface_mesh()
		if not current.call(): return {}
		_make_context_water(lines)
		if not current.call(): return {}
		_make_woodland_positions()
		if not current.call(): return {}
		_make_surface_lines(lines)
		if not current.call(): return {}
		_make_surface_cover()
		if not current.call(): return {}
		return {"anchor":_local_surface_anchor,"anchor_km":_surface_chart_anchor_km,
			"vertices":_surface_vertices,"ray_vertices":_surface_ray_vertices,"indices":_surface_indices,"pick_chunks":_surface_pick_chunks,
			"water_vertices":_surface_water_vertices,"water_chunks":_surface_water_chunks,"water_bytes":_surface_water_bytes,
			"woodland_bytes":_woodland_bytes,"woodland_positions":_woodland_positions,"height_bytes":_height_bytes,"height_size":_height_size,"height_layout":_height_layout,"height_stride":_height_stride,"height_bounds":_height_bounds,"context_water_bytes":_context_water_bytes,"context_water_bounds":_context_water_bounds,"terrain_arrays":_terrain_arrays,"cover_arrays":_cover_arrays,"line_arrays":_line_arrays}

	func _make_context_water(features: Array[Dictionary]) -> void:
		if not bool((_surface_reference.get("presentation",{}) as Dictionary).get("show_bounded_water",false)):return
		var polygons: Array[Array] = []
		var bounds := Rect2();var first := true
		for feature: Dictionary in features:
			if feature.get("kind")!="water_surface":continue
			var geometry:=feature.get("geometry",{}) as Dictionary
			var shapes: Array = [geometry.coordinates] if geometry.get("type")=="Polygon" else geometry.get("coordinates",[])
			for polygon: Array in shapes:
				var rings: Array[PackedVector2Array] = []
				for raw: Array in polygon:
					var ring:=PackedVector2Array()
					for point: Array in raw:
						var ll:=Vector2(float(point[0]),float(point[1]));ring.append(ll)
						bounds=Rect2(ll,Vector2.ZERO) if first else bounds.expand(ll);first=false
					rings.append(ring)
				polygons.append(rings)
		if first or not bounds.has_area():return
		_context_water_bounds=Vector4(bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y)
		_context_water_bytes.resize(512*512);_context_water_bytes.fill(0)
		for row: int in range(512):
			if not _current.call():return
			var latitude:=lerpf(bounds.end.y,bounds.position.y,(row+.5)/512.0)
			for polygon: Array in polygons:
				# Even-odd scanlines preserve acquired island holes. Cost follows
				# polygon edges and filled spans, not pixel-count times all edges.
				var crossings: Array[float] = []
				for ring: PackedVector2Array in polygon:
					for index: int in range(ring.size()):
						var a:=ring[index];var b:=ring[(index+1)%ring.size()]
						if (a.y>latitude)!=(b.y>latitude):crossings.append(a.x+(b.x-a.x)*(latitude-a.y)/(b.y-a.y))
				crossings.sort()
				for index: int in range(0,crossings.size()-1,2):
					var first_column:=clampi(ceili((crossings[index]-bounds.position.x)/bounds.size.x*512.0-.5),0,512)
					var last_column:=clampi(ceili((crossings[index+1]-bounds.position.x)/bounds.size.x*512.0-.5),0,512)
					for column: int in range(first_column,last_column):_context_water_bytes[row*512+column]=255

	func _surface_metric(unit: Vector3) -> Vector2:
		return (RegionProjection.forward(unit,_surface_chart_frame)-_surface_chart_anchor_km)*1000.0

	func _surface_height(coordinate: Vector2) -> float:
		var d := _surface_reference
		var x := clampf((coordinate.x-float(d.west_cell_centre))/float(d.step_degrees),0.0,float(d.width)-1.0)
		var y := clampf((float(d.north_cell_centre)-coordinate.y)/float(d.step_degrees),0.0,float(d.height)-1.0)
		var column := mini(int(x),int(d.width)-2)
		var row := mini(int(y),int(d.height)-2)
		var dx := x-column
		var dy := y-row
		var rows := d.height_rows_m as Array
		var top_left := float(rows[row][column])
		var top_right := float(rows[row][column+1])
		var bottom_left := float(rows[row+1][column])
		var bottom_right := float(rows[row+1][column+1])
		return top_left+(top_right-top_left)*dx+(bottom_left-top_left)*dy if dx+dy<=1.0 else bottom_right+(bottom_left-bottom_right)*(1.0-dx)+(top_right-bottom_right)*(1.0-dy)

	func _surface_grid(coordinate: Vector2) -> Vector2:
		return Vector2((coordinate.x-float(_surface_reference.west_cell_centre))/float(_surface_reference.step_degrees),(float(_surface_reference.north_cell_centre)-coordinate.y)/float(_surface_reference.step_degrees))

	func _edge_weight(grid: Vector2) -> float:
		var extent := Vector2(int(_surface_reference.width)-1,int(_surface_reference.height)-1)
		var margin := grid.min(extent-grid)
		# A geographic edge transition, never a screen-fixed opacity rectangle.
		return smoothstep(0.0,maxf(2.0,extent.x*0.12),margin.x)*smoothstep(0.0,maxf(2.0,extent.y*0.12),margin.y)

	func _surface_ground_y(coordinate: Vector2) -> float:
		if _surface_vertices.is_empty(): return 0.0
		var grid := _surface_grid(coordinate)
		if not _display_heights.is_empty():return LocalSpatialLod.height_sample(_display_heights,_height_size,LocalSpatialLod.height_grid(grid,_height_layout,_height_stride))
		var width := int(_surface_reference.width)
		var column := clampi(int(grid.x),0,width-2)
		var row := clampi(int(grid.y),0,int(_surface_reference.height)-2)
		var dx := clampf(grid.x-column,0.0,1.0)
		var dy := clampf(grid.y-row,0.0,1.0)
		var a := _surface_vertices[row*width+column].y
		var b := _surface_vertices[row*width+column+1].y
		var c := _surface_vertices[(row+1)*width+column].y
		var d := _surface_vertices[(row+1)*width+column+1].y
		return a+(b-a)*dx+(c-a)*dy if dx+dy<=1.0 else d+(c-d)*(1.0-dx)+(b-d)*(1.0-dy)

	func _make_woodland_mask() -> void:
		# A display mask of the supplied modern OSM polygons, not a DEM-derived
		# biome. Paint the existing ground instead of drawing a second slope.
		var extent := Vector2(int(_surface_reference.width)-1,int(_surface_reference.height)-1)
		for cover: Dictionary in _surface_covers:
			if str(cover.kind)!="woodland": continue
			if _woodland_bytes.is_empty():
				_woodland_bytes.resize(COVER_MASK_SIZE*COVER_MASK_SIZE)
				_woodland_bytes.fill(0)
			for raw: Array in cover.triangles as Array:
				if not _current.call(): return
				var triangle := PackedVector2Array()
				for point: Array in raw:
					triangle.append(_surface_grid(Vector2(float(point[0]),float(point[1])))/extent*COVER_MASK_SIZE)
				var bounds := GlobeProjection.lon_lat_bounds([triangle])
				for y: int in range(clampi(floori(bounds.position.y),0,COVER_MASK_SIZE-1),clampi(ceili(bounds.end.y),0,COVER_MASK_SIZE-1)+1):
					for x: int in range(clampi(floori(bounds.position.x),0,COVER_MASK_SIZE-1),clampi(ceili(bounds.end.x),0,COVER_MASK_SIZE-1)+1):
						var index := y*COVER_MASK_SIZE+x
						if _woodland_bytes[index]==0 and Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),triangle): _woodland_bytes[index] = 255

	func _make_woodland_positions() -> void:
		# A bounded visual sample inside the admitted mask, never forest density.
		var settings := (_surface_reference.get("presentation",{}) as Dictionary).get("woodland_instances",{}) as Dictionary
		if settings.is_empty() or _woodland_bytes.is_empty(): return
		var extent := Vector2(int(_surface_reference.width)-1,int(_surface_reference.height)-1)
		var north_step := float(_surface_reference.step_degrees)*111195.0
		var east_step := north_step*cos(deg_to_rad(_local_surface_anchor.y))
		var spacing := maxf(32.0,float(settings.get("spacing_m",65.0)))
		var grid_step := Vector2(spacing/east_step,spacing/north_step)
		var radius := float(settings.get("footprint_radius_m",3.5))
		var candidates: Array[Vector3] = []
		for row: int in range(ceili(extent.y/grid_step.y)):
			if not _current.call(): return
			for column: int in range(ceili(extent.x/grid_step.x)):
				var grid := Vector2((column+0.5)*grid_step.x,(row+0.5)*grid_step.y)
				if grid.x>=extent.x or grid.y>=extent.y or _edge_weight(grid)<0.90: continue
				var inside := true
				for offset: Vector2 in [Vector2.ZERO,Vector2(-1,-1),Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(0,1),Vector2(1,1)]:
					var sample := (grid+offset*Vector2(radius/east_step,radius/north_step))/extent*COVER_MASK_SIZE
					var pixel := Vector2i(sample)
					if pixel.x<0 or pixel.y<0 or pixel.x>=COVER_MASK_SIZE or pixel.y>=COVER_MASK_SIZE or _woodland_bytes[pixel.y*COVER_MASK_SIZE+pixel.x]==0:
						inside = false; break
				if not inside: continue
				var coordinate := Vector2(float(_surface_reference.west_cell_centre)+grid.x*float(_surface_reference.step_degrees),float(_surface_reference.north_cell_centre)-grid.y*float(_surface_reference.step_degrees))
				if _water_at(coordinate): continue
				var metric := _surface_metric(GlobeProjection.lon_lat_to_unit(coordinate))
				candidates.append(Vector3(metric.x,_surface_ground_y(coordinate),-metric.y))
		# Close to the acquired anchor first; deterministic and bounded.
		candidates.sort_custom(func(a: Vector3,b: Vector3) -> bool: return Vector2(a.x,a.z).length_squared()<Vector2(b.x,b.z).length_squared())
		_woodland_positions.assign(candidates.slice(0,clampi(int(settings.get("max_instances",96)),0,128)))

	func _make_water_mask() -> void:
		_surface_water_cells.clear()
		_surface_water_bytes = PackedByteArray()
		var has_water := false
		for cover: Dictionary in _surface_covers:
			if str(cover.kind)=="water_surface": has_water = true; break
		if not has_water: return
		_surface_water_bytes.resize(COVER_MASK_SIZE*COVER_MASK_SIZE)
		_surface_water_bytes.fill(0)
		var width := int(_surface_reference.width)
		var height := int(_surface_reference.height)
		var extent := Vector2(width-1,height-1)
		for cover: Dictionary in _surface_covers:
			if not _current.call(): return
			if str(cover.kind)!="water_surface": continue
			for raw: Array in cover.triangles as Array:
				var triangle := PackedVector2Array()
				for point: Array in raw: triangle.append(_surface_grid(Vector2(float(point[0]),float(point[1]))))
				var bounds := GlobeProjection.lon_lat_bounds([triangle])
				for row: int in range(clampi(floori(bounds.position.y),0,height-2),clampi(floori(bounds.end.y),0,height-2)+1):
					if not _current.call(): return
					for column: int in range(clampi(floori(bounds.position.x),0,width-2),clampi(floori(bounds.end.x),0,width-2)+1):
						var key := row*width+column
						if not _surface_water_cells.has(key): _surface_water_cells[key] = []
						(_surface_water_cells[key] as Array).append(triangle)
				var pixels := Rect2(bounds.position/extent*COVER_MASK_SIZE,bounds.size/extent*COVER_MASK_SIZE)
				for y: int in range(clampi(floori(pixels.position.y),0,COVER_MASK_SIZE-1),clampi(ceili(pixels.end.y),0,COVER_MASK_SIZE-1)+1):
					for x: int in range(clampi(floori(pixels.position.x),0,COVER_MASK_SIZE-1),clampi(ceili(pixels.end.x),0,COVER_MASK_SIZE-1)+1):
						if Geometry2D.is_point_in_polygon((Vector2(x,y)+Vector2.ONE*0.5)/COVER_MASK_SIZE*extent,triangle): _surface_water_bytes[y*COVER_MASK_SIZE+x] = 255


	func _water_at(coordinate: Vector2) -> bool:
		if _surface_water_bytes.is_empty() or not _surface_contains(coordinate): return false
		var uv := _surface_grid(coordinate)/Vector2(int(_surface_reference.width)-1,int(_surface_reference.height)-1)
		var pixel := Vector2i((uv*COVER_MASK_SIZE).clamp(Vector2.ZERO,Vector2.ONE*(COVER_MASK_SIZE-1)))
		return _surface_water_bytes[pixel.y*COVER_MASK_SIZE+pixel.x]>0

	func _bank_weight(coordinate: Vector2) -> float:
		if _surface_water_bytes.is_empty(): return 0.0
		var uv := _surface_grid(coordinate)/Vector2(int(_surface_reference.width)-1,int(_surface_reference.height)-1)
		var centre := Vector2i((uv*COVER_MASK_SIZE).clamp(Vector2.ZERO,Vector2.ONE*(COVER_MASK_SIZE-1)))
		var wet := 0.0
		var count := 0
		for offset: Vector2i in [Vector2i.ZERO,Vector2i(-2,0),Vector2i(2,0),Vector2i(0,-2),Vector2i(0,2)]:
			var pixel := centre+offset
			# Dataset edges are not banks. Only acquired water geometry is sampled.
			if pixel.x<0 or pixel.y<0 or pixel.x>=COVER_MASK_SIZE or pixel.y>=COVER_MASK_SIZE: continue
			wet += 1.0 if _surface_water_bytes[pixel.y*COVER_MASK_SIZE+pixel.x]>0 else 0.0
			count += 1
		return 1.0-wet/maxi(count,1)

	func _surface_contains(coordinate: Vector2) -> bool:
		if _surface_reference.is_empty(): return false
		var west := float(_surface_reference.west_cell_centre)
		var north := float(_surface_reference.north_cell_centre)
		var step := float(_surface_reference.step_degrees)
		return coordinate.x>=west and coordinate.x<=west+(int(_surface_reference.width)-1)*step and coordinate.y<=north and coordinate.y>=north-(int(_surface_reference.height)-1)*step

	func _make_surface_mesh() -> void:
		var d := _surface_reference
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var relief_uv := PackedVector2Array()
		var indices := PackedInt32Array()
		for row: int in range(int(d.height)):
			if not _current.call(): return
			for column: int in range(int(d.width)):
				var coordinate := Vector2(float(d.west_cell_centre)+column*float(d.step_degrees),float(d.north_cell_centre)-row*float(d.step_degrees))
				var metric := _surface_metric(GlobeProjection.lon_lat_to_unit(coordinate))
				vertices.append(Vector3(metric.x,float(d.height_rows_m[row][column])-_surface_base_height,-metric.y))
				normals.append(Vector3.ZERO)
		for row: int in range(int(d.height)-1):
			if not _current.call(): return
			for column: int in range(int(d.width)-1):
				var a := row*int(d.width)+column
				var b := a+1
				var c := a+int(d.width)
				var e := c+1
				indices.append_array(PackedInt32Array([a,c,b,b,c,e]))
		for index: int in range(0,indices.size(),3):
			var a := indices[index]
			var b := indices[index+1]
			var c := indices[index+2]
			var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
			normals[a] += normal; normals[b] += normal; normals[c] += normal
		for index: int in range(normals.size()): normals[index] = normals[index].normalized()
		for index: int in range(vertices.size()):
			# Actual slope and absolute elevation, not per-shard min/max stretching.
			var elevation := maxf(0.0,vertices[index].y+_surface_base_height)
			relief_uv.append(Vector2(log(1.0+elevation/400.0)/log(16.0),0.0))
			var grid := Vector2(index%int(d.width),index/int(d.width))
			var edge := 1.0 if _context_image!=null else _edge_weight(grid)
			colors.append(Color(0,0,0,edge))
		# A data edge is not a descent to the anchor's elevation. Keep every
		# native height and its actual normal. Only the material's geographic
		# coverage retires at the edge; there is no artificial ramp or side wall.
		_surface_vertices = vertices
		var heights := PackedFloat32Array()
		for vertex: Vector3 in vertices: heights.append(vertex.y)
		_height_bytes = heights.to_byte_array()
		_height_size = Vector2i(int(d.width),int(d.height))
		_height_layout = Vector4(0,0,int(d.width)-1,int(d.height)-1)
		_height_bounds = Vector4(float(d.west_cell_centre),float(d.north_cell_centre)-(int(d.height)-1)*float(d.step_degrees),float(d.west_cell_centre)+(int(d.width)-1)*float(d.step_degrees),float(d.north_cell_centre))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var render_vertices := vertices.duplicate()
		var render_normals := normals.duplicate()
		var render_colors := colors.duplicate()
		var render_relief_uv := relief_uv.duplicate()
		var survey_uv := PackedVector2Array()
		# Geographic material sampling also needs survey UV on non-forest DEMs.
		var extent := Vector2(int(d.width)-1,int(d.height)-1)
		for index: int in range(vertices.size()): survey_uv.append(Vector2(index%int(d.width),index/int(d.width))/extent)
		var render_survey_uv := survey_uv.duplicate()
		var render_indices := PackedInt32Array()
		var pick_groups: Dictionary = {}
		for offset: int in range(0,indices.size(),3):
			if offset%192==0 and not _current.call(): return
			var first_index := render_indices.size()
			var ids := PackedInt32Array([indices[offset],indices[offset+1],indices[offset+2]])
			var grid := PackedVector2Array()
			for id: int in ids: grid.append(Vector2(id%int(d.width),id/int(d.width)))
			var column := int(minf(grid[0].x,minf(grid[1].x,grid[2].x)))
			var row := int(minf(grid[0].y,minf(grid[1].y,grid[2].y)))
			var key := row*int(d.width)+column
			if not _surface_water_cells.has(key):
				render_indices.append_array(ids)
			else:
				var holes: Array[PackedVector2Array] = []
				holes.assign(_surface_water_cells[key] as Array)
				# Cut land at the actual acquired water triangles. Moving the water
				# upwards cannot solve land/water depth conflict; remove the overlap.
				for piece: PackedVector2Array in GlobeProjection.subtract_holes([grid],holes):
					var triangles := Geometry2D.triangulate_polygon(piece)
					for index: int in triangles:
						var delta := piece[index]-grid[0]
						var e := grid[1]-grid[0]
						var f := grid[2]-grid[0]
						var determinant := e.cross(f)
						var b := delta.cross(f)/determinant
						var c := e.cross(delta)/determinant
						var a := 1.0-b-c
						render_indices.append(render_vertices.size())
						render_vertices.append(vertices[ids[0]]*a+vertices[ids[1]]*b+vertices[ids[2]]*c)
						render_normals.append((normals[ids[0]]*a+normals[ids[1]]*b+normals[ids[2]]*c).normalized())
						render_colors.append(colors[ids[0]]*a+colors[ids[1]]*b+colors[ids[2]]*c)
						render_relief_uv.append(relief_uv[ids[0]]*a+relief_uv[ids[1]]*b+relief_uv[ids[2]]*c)
						if not survey_uv.is_empty(): render_survey_uv.append(survey_uv[ids[0]]*a+survey_uv[ids[1]]*b+survey_uv[ids[2]]*c)
			if render_indices.size()>first_index:
				var tile := Vector2i(column/8,row/8)
				if not pick_groups.has(tile): pick_groups[tile] = []
				(pick_groups[tile] as Array).append_array(render_indices.slice(first_index,render_indices.size()))
		# Reorder indices only. The same triangles, native heights and holes
		# render unchanged; each pick AABB covers an 8x8 source-cell area.
		if _context_image!=null:
			var context_arrays := _context_ring(render_vertices,render_normals,render_colors,render_survey_uv,render_relief_uv)
			render_vertices = context_arrays.vertices; render_normals = context_arrays.normals
			render_colors = context_arrays.colors; render_survey_uv = context_arrays.uv; render_relief_uv = context_arrays.uv2
			# Reuse the existing AABB picker with bounded context tiles. A single
			# 16km bucket made the first mouse press visit every outer triangle.
			var context_indices:=PackedInt32Array(context_arrays.indices)
			for offset: int in range(0,context_indices.size(),3):
				var a:=context_indices[offset];var b:=context_indices[offset+1];var c:=context_indices[offset+2]
				var centre:=(render_vertices[a]+render_vertices[b]+render_vertices[c])/3.0
				var tile:=Vector2i(floori(centre.x/1000.0),floori(centre.z/1000.0))
				if not pick_groups.has(tile):pick_groups[tile]=[]
				(pick_groups[tile] as Array).append_array([a,b,c])
		render_indices = PackedInt32Array()
		_surface_pick_chunks.clear()
		for group: Array in pick_groups.values():
			var start := render_indices.size()
			render_indices.append_array(PackedInt32Array(group))
			var bounds := AABB(render_vertices[render_indices[start]],Vector3.ZERO)
			for index: int in range(start,render_indices.size()): bounds = bounds.expand(render_vertices[render_indices[index]])
			_surface_pick_chunks.append({"start":start,"end":render_indices.size(),"bounds":bounds.grow(0.01)})
		if _context_image!=null:
			# The product grid retains fine rows/columns through the outer ring.
			# Triangle normals there would change their sampling footprint at those
			# rows and print a cross. Differentiate the SAME joined height field at
			# the context source spacing, independent of tessellation density.
			var source:=(_surface_reference.presentation as Dictionary).context_height_asset as Dictionary
			var delta:=Vector2(float(source.display_spacing_degrees[0]),float(source.display_spacing_degrees[1]))/float(d.step_degrees)*0.5
			var metres:=Vector2(cos(deg_to_rad(_local_surface_anchor.y)),1.0)*float(d.step_degrees)*111195.0
			var axes:=RegionProjection.tangent_axes(GlobeProjection.lon_lat_to_unit(_local_surface_anchor),_surface_chart_frame)
			var normal_basis:=Basis(Vector3(axes.x.x,0,-axes.x.y),Vector3.UP,Vector3(-axes.y.x,0,axes.y.y))
			for index: int in range(render_vertices.size()):
				if index%192==0 and not _current.call():return
				var grid:=render_survey_uv[index]*extent
				# One derivative of the joined height field on BOTH sides of the
				# survey edge. Heights and fine interior sampling remain intact.
				var distance:=((grid-grid.clamp(Vector2.ZERO,extent))*metres).length()
				var sample_delta:=Vector2.ONE.lerp(delta,smoothstep(0.0,400.0,distance))
				var gradient_samples: Array[float]=[]
				for offset: Vector2 in [Vector2(-sample_delta.x,0),Vector2(sample_delta.x,0),Vector2(0,-sample_delta.y),Vector2(0,sample_delta.y)]:
					gradient_samples.append(LocalSpatialLod.height_sample(_display_heights,_height_size,LocalSpatialLod.height_grid(grid+offset,_height_layout,_height_stride)))
				render_normals[index]=(normal_basis*Vector3(-(gradient_samples[1]-gradient_samples[0])/(2.0*sample_delta.x*metres.x),1.0,-(gradient_samples[3]-gradient_samples[2])/(2.0*sample_delta.y*metres.y))).normalized()
		arrays[Mesh.ARRAY_VERTEX] = render_vertices
		arrays[Mesh.ARRAY_NORMAL] = render_normals
		arrays[Mesh.ARRAY_COLOR] = render_colors
		if not render_survey_uv.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = render_survey_uv
		arrays[Mesh.ARRAY_TEX_UV2] = render_relief_uv
		arrays[Mesh.ARRAY_INDEX] = render_indices
		_surface_ray_vertices = render_vertices
		_surface_indices = render_indices
		_terrain_arrays = arrays
		_surface_water_cells.clear()

	func _context_height(coordinate: Vector2) -> float:
		# R42's documented log-height channel, before colour composition. It is
		# quantized Copernicus DSM at ~150x217 m, never swissALTI3D measurement.
		var uv := Vector2((coordinate.x-_context_bounds.position.x)/_context_bounds.size.x,(_context_bounds.end.y-coordinate.y)/_context_bounds.size.y)
		var pixel := uv*Vector2(_context_image.get_size())-Vector2.ONE*.5
		var base := Vector2i(pixel.floor())
		var fraction := pixel-Vector2(base)
		var values: Array[float] = []
		for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
			var point := (base+offset).clamp(Vector2i.ZERO,_context_image.get_size()-Vector2i.ONE)
			values.append(200.0*(pow(26.0,_context_image.get_pixelv(point).r)-1.0))
		return lerpf(lerpf(values[0],values[1],fraction.x),lerpf(values[2],values[3],fraction.x),fraction.y)

	func _context_ring(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array) -> Dictionary:
		var d := _surface_reference
		var extent := Vector2i(int(d.width)-1,int(d.height)-1)
		var step := float(d.step_degrees)
		var metres := Vector2(step*111195.0*cos(deg_to_rad(_local_surface_anchor.y)),step*111195.0)
		var west := float(d.west_cell_centre);var north := float(d.north_cell_centre)
		var layout := LocalSpatialContent.context_layout(d)
		var xs: Array[int]=layout.xs;var ys: Array[int]=layout.ys
		var low := layout.low as Vector2i
		var stride := int(layout.stride)
		_height_size=Vector2i(xs.size(),ys.size());_height_layout=Vector4(low.x,low.y,extent.x,extent.y);_height_stride=stride
		_height_bounds=Vector4(west+xs[0]*step,north-ys[-1]*step,west+xs[-1]*step,north-ys[0]*step)
		_display_heights.resize(xs.size()*ys.size())
		var lookup := PackedInt32Array(); var indices := PackedInt32Array()
		for y: int in ys:
			if not _current.call(): return {"vertices":vertices,"normals":normals,"colors":colors,"uv":uv,"uv2":uv2,"indices":[]}
			for x: int in xs:
				if x>=0 and x<=extent.x and y>=0 and y<=extent.y:
					lookup.append(y*int(d.width)+x);_display_heights[lookup.size()-1]=vertices[lookup[-1]].y;continue
				var grid := Vector2(x,y)
				var edge := grid.clamp(Vector2.ZERO,Vector2(extent))
				var coordinate := Vector2(float(d.west_cell_centre)+x*float(d.step_degrees),float(d.north_cell_centre)-y*float(d.step_degrees))
				var boundary := Vector2(float(d.west_cell_centre)+edge.x*float(d.step_degrees),float(d.north_cell_centre)-edge.y*float(d.step_degrees))
				var metric := _surface_metric(GlobeProjection.lon_lat_to_unit(coordinate))
				var distance := metric.distance_to(_surface_metric(GlobeProjection.lon_lat_to_unit(boundary)))
				# A labelled display transition reconciles DSM/DTM and vertical datum
				# differences in a 400m collar; the acquired native samples stay intact.
				var h := _context_height(coordinate)+(_surface_height(boundary)-_context_height(boundary))*(1.0-smoothstep(0.0,400.0,distance))
				var rim := minf(minf(x-xs[0],xs[-1]-x)*metres.x,minf(y-ys[0],ys[-1]-y)*metres.y)
				var weight := smoothstep(0.0,600.0,rim)
				lookup.append(vertices.size())
				vertices.append(Vector3(metric.x,h-_surface_base_height,-metric.y))
				_display_heights[lookup.size()-1]=h-_surface_base_height
				normals.append(Vector3.ZERO);colors.append(Color(0,0,0,weight))
				uv.append(grid/Vector2(extent));uv2.append(Vector2(log(1.0+maxf(0.0,h)/400.0)/log(16.0),0.0))
		for row: int in range(ys.size()-1):
			for column: int in range(xs.size()-1):
				if xs[column]>=0 and xs[column+1]<=extent.x and ys[row]>=0 and ys[row+1]<=extent.y: continue
				var a := row*xs.size()+column;var b := a+1;var c := a+xs.size();var e := c+1
				indices.append_array([lookup[a],lookup[c],lookup[b],lookup[b],lookup[c],lookup[e]])
		# Context normals use the joined height field in _make_surface_mesh.
		_height_bytes=_display_heights.to_byte_array()
		return {"vertices":vertices,"normals":normals,"colors":colors,"uv":uv,"uv2":uv2,"indices":Array(indices)}

	func _make_surface_cover() -> void:
		_cover_arrays = []
		_surface_water_vertices = PackedVector3Array()
		_surface_water_chunks.clear()
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var relief_uv := PackedVector2Array()
		var colors := PackedColorArray()
		var water_groups: Dictionary = {}
		# Offline intersection with native DEM triangles preserves island holes,
		# river banks and the exact surface interpolation. No guessed river width.
		for cover: Dictionary in _surface_covers:
			if not _current.call(): return
			if str(cover.kind)!="water_surface": continue
			for triangle: Array in cover.triangles as Array:
				var first := triangle[0] as Array
				var grid := _surface_grid(Vector2(float(first[0]),float(first[1])))
				var tile := Vector2i(floori(grid.x/8.0),floori(grid.y/8.0))
				if not water_groups.has(tile): water_groups[tile] = []
				var water_group := water_groups[tile] as Array
				for raw: Array in triangle:
					var coordinate := Vector2(float(raw[0]),float(raw[1]))
					var metric := _surface_metric(GlobeProjection.lon_lat_to_unit(coordinate))
					var edge := _edge_weight(_surface_grid(coordinate))
					var altitude := float(cover.reference_elevation_m)-_surface_base_height if cover.has("reference_elevation_m") else _surface_ground_y(coordinate)
					var vertex := Vector3(metric.x,altitude,-metric.y)
					vertices.append(vertex)
					# Preserve the acquired water's existing colour/height convention.
					var ink := HydrographyStyle.water_ink(_bank_weight(coordinate)).srgb_to_linear()
					colors.append(Color(ink.r,ink.g,ink.b,edge))
					normals.append(Vector3.UP)
					var elevation := maxf(0.0,altitude+_surface_base_height)
					relief_uv.append(Vector2(log(1.0+elevation/400.0)/log(16.0),-1.0))
					water_group.append(vertex)
		for group: Array in water_groups.values():
			var start := _surface_water_vertices.size()
			_surface_water_vertices.append_array(PackedVector3Array(group))
			var bounds := AABB(_surface_water_vertices[start],Vector3.ZERO)
			for index: int in range(start,_surface_water_vertices.size()): bounds = bounds.expand(_surface_water_vertices[index])
			_surface_water_chunks.append({"start":start,"end":_surface_water_vertices.size(),"bounds":bounds.grow(0.01)})
		if vertices.is_empty(): return
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV2] = relief_uv
		arrays[Mesh.ARRAY_COLOR] = colors
		_cover_arrays = arrays

	func _make_surface_lines(features: Array[Dictionary]) -> void:
		_line_arrays = []
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var d := _surface_reference
		var west := float(d.west_cell_centre)
		var north := float(d.north_cell_centre)
		var east := west+(int(d.width)-1)*float(d.step_degrees)
		var south := north-(int(d.height)-1)*float(d.step_degrees)
		for feature: Dictionary in features:
			if bool(_surface_reference.get("river_chart_only",false)): break
			if not _current.call(): return
			if str(feature.kind)!="river" or str(feature.geometry.type)!="LineString": continue
			var coordinates := feature.geometry.coordinates as Array
			for index: int in range(coordinates.size()-1):
				var a := Vector2(float(coordinates[index][0]),float(coordinates[index][1]))
				var b := Vector2(float(coordinates[index+1][0]),float(coordinates[index+1][1]))
				var delta := b-a
				var enter := 0.0
				var leave := 1.0
				for edge: Vector2 in [Vector2(-delta.x,a.x-west),Vector2(delta.x,east-a.x),Vector2(-delta.y,a.y-south),Vector2(delta.y,north-a.y)]:
					if is_zero_approx(edge.x):
						if edge.y<0.0: leave = -1.0
					elif edge.x<0.0: enter = maxf(enter,edge.y/edge.x)
					else: leave = minf(leave,edge.y/edge.x)
				if enter>=leave: continue
				var start := a+delta*enter
				var end := a+delta*leave
				var steps := clampi(ceili(start.distance_to(end)/float(d.step_degrees)),1,128)
				for part: int in range(steps):
					if _water_at(start.lerp(end,(float(part)+0.5)/steps)): continue
					for fraction: float in [float(part)/steps,float(part+1)/steps]:
						var coordinate := start.lerp(end,fraction)
						var metric := _surface_metric(GlobeProjection.lon_lat_to_unit(coordinate))
						vertices.append(Vector3(metric.x,_surface_ground_y(coordinate)+0.05,-metric.y))
						var ink := HydrographyStyle.color("river").srgb_to_linear()
						colors.append(Color(ink.r,ink.g,ink.b,_edge_weight(_surface_grid(coordinate))))
		_append_height_contours(vertices,colors)
		if vertices.is_empty(): return
		# A thin centreline symbol follows the DEM; it is not a water polygon/width.
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		_line_arrays = arrays

	func _append_height_contours(vertices: PackedVector3Array, colors: PackedColorArray) -> void:
		# About twelve readable height bands from this admitted DEM, using the
		# existing contour geometry. Explicit presentation intervals still win.
		var range_m := float(_surface_reference.get("height_max_m",0.0))-float(_surface_reference.get("height_min_m",0.0))
		var raw_step := maxf(1.0,range_m/12.0)
		var decade := pow(10.0,floor(log(raw_step)/log(10.0)))
		var fraction := raw_step/decade
		var default_interval := decade*(1.0 if fraction<=1.0 else 2.0 if fraction<=2.0 else 5.0 if fraction<=5.0 else 10.0) if range_m>1.0 else 0.0
		var interval := float((_surface_reference.get("presentation",{}) as Dictionary).get("contour_interval_m",default_interval))
		if interval<=0.0: return
		var width := int(_surface_reference.width)
		for row: int in range(int(_surface_reference.height)-1):
			if not _current.call(): return
			for column: int in range(width-1):
				var a := row*width+column
				for ids: Array in [[a,a+width,a+1],[a+1,a+width,a+width+1]]:
					var points := PackedVector3Array([_surface_vertices[ids[0]],_surface_vertices[ids[1]],_surface_vertices[ids[2]]])
					var low := minf(points[0].y,minf(points[1].y,points[2].y))+_surface_base_height
					var high := maxf(points[0].y,maxf(points[1].y,points[2].y))+_surface_base_height
					for level: int in range(ceili(low/interval),floori(high/interval)+1):
						var height := level*interval-_surface_base_height
						var intersections := PackedVector3Array()
						var grids := PackedVector2Array()
						for edge: int in range(3):
							var start := points[edge]
							var end := points[(edge+1)%3]
							if (start.y<height)==(end.y<height) or is_equal_approx(start.y,end.y): continue
							var ratio := (height-start.y)/(end.y-start.y)
							intersections.append(start.lerp(end,ratio)+Vector3.UP*0.06)
							var g0 := Vector2(int(ids[edge])%width,int(ids[edge])/width)
							var g1 := Vector2(int(ids[(edge+1)%3])%width,int(ids[(edge+1)%3])/width)
							grids.append(g0.lerp(g1,ratio))
						if intersections.size()!=2 or intersections[0].distance_squared_to(intersections[1])<0.0001: continue
						for index: int in range(2):
							vertices.append(intersections[index])
							colors.append(Color(0.23,0.19,0.13,_edge_weight(grids[index])*0.32))
