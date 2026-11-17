class_name PoliticalLayer
extends RefCounted
const STRUCTURE = preload("res://scripts/presentation/map/economy/economic_structure_style.gd")
## World-scale PoliticalMapRegions; historical/local authority stays in content.

var records: Dictionary = {}
var economies: Dictionary = {}
var show_output_values: bool = false
var output_values: Dictionary = {}
var output_maximum: float = 0.0
var anchors: Dictionary = {}
var places: Dictionary = {}
var resolved_visuals: Dictionary = {}
var visual_textures: Dictionary = {}
var boundary_features: Dictionary = {}
var display_faces_by_feature: Dictionary = {}
var _query_parts: Array[Dictionary] = []
var region_frames: Dictionary = {}
var display_accounting: Dictionary = {}
var display_date: String = ""
var _whole_owner_by_feature: Dictionary = {}
var _regions: Array[Dictionary] = []
var _scope_features: Array = []
var _partial_scopes: Dictionary = {}
var _display_document: Dictionary = {}
var _bound_document: Dictionary = {}
var _bound_owners: Dictionary = {}
var _has_bound_geometry: bool = false

func display_active(owner: String, geometry_period: Dictionary) -> bool:
	# Dated display authority and dated source polygon are separate evidence.
	# Only explicit display-only records may supply the predecessor interval.
	var identity := records.get(owner,{}) as Dictionary
	var period := identity if bool(identity.get("display_only",false)) else geometry_period
	return period.is_empty() or display_date>=str(period.get("valid_from","")) and display_date<str(period.get("valid_to","9999-12-31"))

func refresh(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView, place_records: Array[Dictionary], _time: Dictionary, geometry: MapGeometryContent, display: ResolvedMapContent) -> void:
	records.clear()
	economies.clear()
	anchors.clear()
	places.clear()
	resolved_visuals.clear()
	visual_textures.clear()
	boundary_features.clear()
	_whole_owner_by_feature.clear()
	_regions.clear()
	region_frames.clear()
	display_date = display.date()
	_display_document = display.display_document()
	_scope_features = _display_document.get("scope_feature_ids", []) as Array
	_partial_scopes = _display_document.get("partial_scope_masks", {}) as Dictionary
	var units := display.units()
	for unit: Dictionary in units:
		var identity := str(unit.id)
		var feature_id := str(unit.get("geometry_feature_id", ""))
		boundary_features[identity] = feature_id
		_whole_owner_by_feature[feature_id] = identity
		if not feature_id in _scope_features or _partial_scopes.has(feature_id):
			records[identity] = unit
			if not bool(unit.get("is_runtime_polity",true)):
				records[identity] = unit.duplicate(true)
				(records[identity] as Dictionary)["display_only"] = true
	# A world-map region is its own presentation record. It neither promotes
	# tribes into polities nor reuses historical influence masks as boundaries.
	for region: Dictionary in _display_document.get("political_map_regions", []) as Array:
		var owner := str(region.id)
		records[owner] = {
			"id":owner,"source_historical_id":region.historical_authority_id,
			"geometry_feature_id":"arabia_undelimited_desert_1900",
			"political_map_region_id":owner,"representative_visual_id":region.representative_visual_id,
			"is_runtime_polity":false,"display_only":true,"label_rank":2,
			"name_zh":region.name_zh,"short_name_zh":region.short_name_zh,
			"label_anchor":region.label_anchor,
			"valid_from":_display_document.get("valid_from",""),"valid_to":_display_document.get("valid_to",""),
			"boundary_kind":region.get("boundary_kind",""),"confidence":region.get("confidence","low"),
		}
		region_frames[owner] = region.flag_frame
		var prepared := region.duplicate(true)
		prepared["owner"] = owner
		prepared["cells"] = _prepare_cells(region.mask_cells as Array)
		_regions.append(prepared)
	for owner: String in records:
		var unit := records[owner] as Dictionary
		var resolved := display.visual(owner)
		resolved_visuals[owner] = resolved
		var texture := display.texture(owner)
		if texture != null:
			visual_textures[owner] = texture
		if bool(unit.get("is_runtime_polity", true)):
			economies[owner] = CurrentWorldPoliticalProjection.polity_summary(owner, registry, evidence, economy).get("economy", {})
		var anchor := unit.get("label_anchor", unit.get("capital", {})) as Dictionary
		if unit.has("label_anchor") or not str(anchor.get("name", "")).is_empty():
			anchors[owner] = GlobeProjection.lon_lat_to_unit(Vector2(float(anchor.get("lon", 0)), float(anchor.get("lat", 0))))
		else:
			var sum := Vector3.ZERO
			for part: Dictionary in geometry.parts(str(unit.get("geometry_feature_id", ""))):
				for point: Vector2 in part.outer as PackedVector2Array:
					sum += GlobeProjection.lon_lat_to_unit(point)
			anchors[owner] = sum.normalized()
	for place: Dictionary in place_records:
		places[str(place.get("place_id", ""))] = place

func _prepare_cells(raw_cells: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for cell: Dictionary in raw_cells:
		var outer := _ring(cell.outer as Array)
		var holes: Array[PackedVector2Array] = []
		for hole: Array in cell.holes as Array:
			holes.append(_ring(hole))
		output.append({"outer": outer, "holes": holes, "bounds": GlobeProjection.lon_lat_bounds([outer])})
	return output

func refresh_economies(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView, mode: String) -> bool:
	# Economic observations do not change ownership, anchors or source meshes.
	var appearance_changed := false
	for owner: String in records:
		if bool((records[owner] as Dictionary).get("is_runtime_polity",true)):
			var previous := color(owner,mode)
			var was_available := economic_available(owner)
			economies[owner] = CurrentWorldPoliticalProjection.polity_summary(owner,registry,evidence,economy).get("economy",{})
			appearance_changed = appearance_changed or previous!=color(owner,mode) or was_available!=economic_available(owner)
	return appearance_changed

func _ring(raw: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for point: Array in raw:
		ring.append(Vector2(float(point[0]), float(point[1])))
	return ring

func _lon_lat(points: PackedVector3Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for point: Vector3 in points:
		ring.append(Vector2(rad_to_deg(atan2(point.x, point.z)), rad_to_deg(asin(clampf(point.y, -1.0, 1.0)))))
	return ring

func _intersect_cell(ring: PackedVector2Array, cell: Dictionary) -> Array[PackedVector2Array]:
	if not (cell.bounds as Rect2).intersects(GlobeProjection.lon_lat_bounds([ring]), true):
		return []
	# Local coordinates avoid cancellation when clipping small coastal faces.
	var shift := Transform2D(0.0, -GlobeProjection.lon_lat_bounds([ring]).get_center())
	var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(shift * ring, shift * (cell.outer as PackedVector2Array))
	var holes: Array[PackedVector2Array] = []
	for hole: PackedVector2Array in cell.holes as Array[PackedVector2Array]:
		holes.append(shift * hole)
	pieces = GlobeProjection.subtract_holes(pieces, holes)
	var output: Array[PackedVector2Array] = []
	for piece: PackedVector2Array in pieces:
		if GlobeProjection.polygon_area(piece) > 0.0000000001:
			output.append(shift.affine_inverse() * piece)
	return output

func bind_source_queries(meshes: Dictionary, force: bool = true) -> bool:
	if not force and _has_bound_geometry and _bound_document==_display_document and _bound_owners==_whole_owner_by_feature: return false
	_bound_document = _display_document
	_bound_owners = _whole_owner_by_feature.duplicate()
	_has_bound_geometry = true
	_query_parts.clear()
	display_faces_by_feature.clear()
	for feature_id: String in meshes:
		for source: Dictionary in (meshes[feature_id] as Dictionary).parts:
			var part := source.duplicate()
			part["scope_cells"] = _prepare_cells(_partial_scopes.get(feature_id,[]) as Array)
			_query_parts.append(part)
	return true

func query_at(unit: Vector3) -> Dictionary:
	var coordinate := RegionProjection.lon_lat(unit)
	for index: int in range(_query_parts.size()-1,-1,-1):
		var part := _query_parts[index]
		if unit.angle_to(part.cull_axis as Vector3)>float(part.cull_angle)+0.000001: continue
		var point := coordinate
		point.x += 360.0*roundf(((part.bounds as Rect2).get_center().x-point.x)/360.0)
		if not _contains_cell(point,part): continue
		return {"found":true,"owner":_final_owner_at(point,[part])}
	return {"found":false,"owner":""}

func query_edge(point: Vector2, camera: RegionCamera, basis: Basis, center: Vector2, radius: float, unit: Vector3) -> String:
	# Keep the existing four-pixel small-island/coast affordance using source
	# ring segments; never prepare every historical face just for hovering.
	var margin := 4.0*camera.km_per_pixel/RegionProjection.EARTH_RADIUS_KM if camera.active else 4.0/maxf(radius,1.0)
	var best := 4.0
	var owner := ""
	for part: Dictionary in _query_parts:
		if unit.angle_to(part.cull_axis as Vector3)>float(part.cull_angle)+margin: continue
		var feature := str(part.feature_id)
		if feature in _scope_features: continue
		for line: PackedVector3Array in part.borders:
			var segments: Array[PackedVector2Array] = []
			if camera.active:
				var segment := PackedVector2Array()
				for vertex: Vector3 in line:
					if vertex.dot(camera.tangent_frame.z)<0.0:
						if segment.size()>1: segments.append(segment)
						segment = PackedVector2Array()
					else: segment.append(camera.project(vertex))
				if segment.size()>1: segments.append(segment)
			else: segments = GlobeProjection.project_line(line,basis,center,radius)
			for segment: PackedVector2Array in segments:
				for index: int in range(segment.size()-1):
					var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,segment[index],segment[index+1]))
					if distance>=best: continue
					best = distance
					owner = str(_whole_owner_by_feature.get(feature,""))
	return owner

func bind_source_meshes(meshes: Dictionary, force: bool = true) -> bool:
	if not force and _has_bound_geometry and _bound_document == _display_document and _bound_owners == _whole_owner_by_feature:
		return false
	_bound_document = _display_document.duplicate(true)
	_bound_owners = _whole_owner_by_feature.duplicate()
	_has_bound_geometry = true
	display_faces_by_feature.clear()
	display_accounting = {"source_planar_area": 0.0, "display_planar_area": 0.0, "display_pieces": 0, "unassigned_pieces": 0}
	for feature_id: String in meshes:
		var output: Array[Dictionary] = []
		var source_faces := (meshes[feature_id] as Dictionary).triangles as Array
		var scope_cells := _prepare_cells(_partial_scopes.get(feature_id, []) as Array)
		for face_index: int in range(source_faces.size()):
			var triangle := source_faces[face_index] as Dictionary
			if not feature_id in _scope_features:
				var original := triangle.duplicate()
				original["owner"] = str(_whole_owner_by_feature.get(feature_id, ""))
				original["source_face_index"] = face_index
				output.append(original)
				continue
			var ring := _lon_lat(triangle.points as PackedVector3Array)
			var source_area := GlobeProjection.polygon_area(Transform2D(0.0, -ring[0]) * ring)
			display_accounting.source_planar_area += source_area
			if not scope_cells.is_empty():
				var intersects_scope := false
				var bounds := GlobeProjection.lon_lat_bounds([ring])
				for cell: Dictionary in scope_cells:
					intersects_scope = intersects_scope or (cell.bounds as Rect2).intersects(bounds, true)
				if not intersects_scope:
					var original := triangle.duplicate()
					original["owner"] = str(_whole_owner_by_feature.get(feature_id, ""))
					original["source_face_index"] = face_index
					output.append(original)
					display_accounting.display_planar_area += source_area
					continue
			var scoped: Array[PackedVector2Array] = [ring]
			if not scope_cells.is_empty():
				scoped.clear()
				var outside: Array[PackedVector2Array] = [ring]
				for cell: Dictionary in scope_cells:
					scoped.append_array(_intersect_cell(ring, cell))
					outside = GlobeProjection.subtract_holes(outside, [cell.outer as PackedVector2Array])
				for piece: PackedVector2Array in outside:
						_append_piece(output, piece, triangle, face_index, str(_whole_owner_by_feature.get(feature_id, "")), "", feature_id)
			for scope_piece: PackedVector2Array in scoped:
				for region: Dictionary in _regions:
					for cell: Dictionary in region.cells as Array[Dictionary]:
						for piece: PackedVector2Array in _intersect_cell(scope_piece, cell):
							_append_piece(output, piece, triangle, face_index, str(region.owner), str(region.id), feature_id)
		display_faces_by_feature[feature_id] = output
		display_accounting.display_pieces += output.size()
	return true

func _append_piece(output: Array[Dictionary], ring: PackedVector2Array, source: Dictionary, face_index: int, owner: String, region_id: String, feature_id: String) -> void:
	var center := ring[0]
	var local_ring := Transform2D(0.0, -center) * ring
	var area := GlobeProjection.polygon_area(local_ring)
	if area <= 0.0000000001:
		return
	display_accounting.display_planar_area += area
	var indices := Geometry2D.triangulate_polygon(local_ring)
	if indices.is_empty():
		push_error("Display mask could not triangulate retained source face")
		return
	for index: int in range(0, indices.size(), 3):
		var points := PackedVector3Array()
		var uvs := PackedVector2Array()
		for offset: int in range(3):
			var point := ring[indices[index+offset]]
			points.append(GlobeProjection.lon_lat_to_unit(point))
			if not region_id.is_empty():
				# All source components of this authority use its one geographic frame.
				var frame := region_frames[owner] as Array
				uvs.append(Vector2((point.x-float(frame[0]))/(float(frame[2])-float(frame[0])), (float(frame[3])-point.y)/(float(frame[3])-float(frame[1]))))
			else:
				var source_ring := _lon_lat(source.points as PackedVector3Array)
				var first := source_ring[1]-source_ring[0]
				var second := source_ring[2]-source_ring[0]
				var delta := point-source_ring[0]
				var source_uvs := source.uvs as PackedVector2Array
				uvs.append(source_uvs[0]+(source_uvs[1]-source_uvs[0])*delta.cross(second)/first.cross(second)+(source_uvs[2]-source_uvs[0])*first.cross(delta)/first.cross(second))
		output.append({"points":points,"uvs":uvs,"component_index":source.component_index,"source_face_index":face_index,
			"source_feature_id":feature_id,"owner":owner,"political_map_region_id":region_id})
		if owner.is_empty():
			display_accounting.unassigned_pieces += 1

func display_boundary_sources(original: Array[Dictionary], geography: MapGeometryContent) -> Array[Dictionary]:
	# Source rings and authored display frontiers are candidates only. The two
	# final surface owners decide whether a candidate has cartographic meaning.
	var area := Rect2(Vector2(33.9, 11.9), Vector2(27.2, 23.2))
	var land: Array[Dictionary] = []
	for feature_id: String in geography.feature_ids():
		for part: Dictionary in geography.parts(feature_id):
			var bounds := GlobeProjection.lon_lat_bounds([part.outer])
			if bounds.intersects(area, true):
				land.append({"outer":part.outer,"holes":part.holes,"bounds":bounds,"feature_id":feature_id,
					"scope_cells":_prepare_cells(_partial_scopes.get(feature_id, []) as Array)})
	var cuts: Array[PackedVector2Array] = []
	for region: Dictionary in _regions:
		for cell: Dictionary in region.cells as Array[Dictionary]:
			cuts.append(cell.outer as PackedVector2Array)
	for raw: Array in _partial_scopes.values():
		for cell: Dictionary in _prepare_cells(raw):
			cuts.append(cell.outer as PackedVector2Array)
	var output: Array[Dictionary] = []
	var emitted: Dictionary = {}
	for boundary: Dictionary in original:
		var points := _lon_lat(boundary.points as PackedVector3Array)
		if not area.intersects(GlobeProjection.lon_lat_bounds([points]), true):
			var owners := boundary.owners as PackedStringArray
			output.append({"points":boundary.points,"owners":owners,"kind":"macro" if owners.size() > 1 else "coast"})
			continue
		_extract_final_edges(points, cuts, land, emitted, output)
	for border: Dictionary in _display_document.get("boundaries", []) as Array:
		_extract_final_edges(_ring(border.points as Array), cuts, land, emitted, output)
	return output

func _contains_cell(point: Vector2, cell: Dictionary) -> bool:
	if not (cell.bounds as Rect2).has_point(point) or not _strictly_inside_ring(point, cell.outer as PackedVector2Array):
		return false
	for hole: PackedVector2Array in cell.holes:
		if _strictly_inside_ring(point, hole):
			return false
	return true

func _strictly_inside_ring(point: Vector2, ring: PackedVector2Array) -> bool:
	# Border-side samples must not use an inclusive "on edge" tolerance: it
	# can report both sides inside the first region and erase a real frontier.
	var inside := false
	var previous := ring[ring.size() - 1] - point
	for vertex: Vector2 in ring:
		var current := vertex - point
		if (current.y > 0.0) != (previous.y > 0.0):
			var crossing_x := float(current.x) + (float(previous.x) - float(current.x)) * -float(current.y) / (float(previous.y) - float(current.y))
			if crossing_x > 0.0:
				inside = not inside
		previous = current
	return inside

func _final_owner_at(point: Vector2, land: Array[Dictionary]) -> String:
	var whole_owner := ""
	for part: Dictionary in land:
		if not _contains_cell(point, part):
			continue
		var feature_id := str(part.feature_id)
		var scoped := feature_id in _scope_features
		if scoped and _partial_scopes.has(feature_id):
			scoped = false
			for cell: Dictionary in part.scope_cells as Array[Dictionary]:
				scoped = scoped or _contains_cell(point, cell)
		if scoped:
			for region: Dictionary in _regions:
				for cell: Dictionary in region.cells as Array[Dictionary]:
					if _contains_cell(point, cell):
						return str(region.owner)
		else:
			whole_owner = str(_whole_owner_by_feature.get(feature_id, ""))
	return whole_owner

func _extract_final_edges(points: PackedVector2Array, cuts: Array[PackedVector2Array], land: Array[Dictionary], emitted: Dictionary, output: Array[Dictionary]) -> void:
	var line := PackedVector2Array()
	var current_owners := PackedStringArray()
	for index: int in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var delta := b - a
		if delta.length_squared() < 0.000000000001:
			continue
		var ratios: Array[float] = [0.0, 1.0]
		for ring: PackedVector2Array in cuts:
			for edge: int in range(ring.size()):
				var crossing: Variant = Geometry2D.segment_intersects_segment(a, b, ring[edge], ring[(edge + 1) % ring.size()])
				if crossing is Vector2:
					var ratio := ((crossing as Vector2) - a).dot(delta) / delta.length_squared()
					if ratio > 0.00001 and ratio < 0.99999:
						ratios.append(ratio)
		ratios.sort()
		for piece: int in range(ratios.size() - 1):
			var start := a + delta * ratios[piece]
			var end := a + delta * ratios[piece + 1]
			if start.distance_squared_to(end) < 0.000000000001:
				continue
			var middle := (start + end) * 0.5
			var offset := Vector2(-delta.y, delta.x).normalized() * minf(0.00015, start.distance_to(end) * 0.1)
			var left := _final_owner_at(middle + offset, land)
			var right := _final_owner_at(middle - offset, land)
			var owners := PackedStringArray()
			if left != right:
				if not left.is_empty():
					owners.append(left)
				if not right.is_empty():
					owners.append(right)
				owners.sort()
			var key := GlobeProjection.edge_key(GlobeProjection.lon_lat_to_unit(start), GlobeProjection.lon_lat_to_unit(end))
			var skip := owners.is_empty() or emitted.has(key)
			if skip or owners != current_owners or (not line.is_empty() and not line[line.size() - 1].is_equal_approx(start)):
				if line.size() > 1:
					output.append({"points":GlobeProjection.to_unit_line(line),"owners":current_owners,"kind":"macro" if current_owners.size() == 2 else "coast"})
				line = PackedVector2Array()
				current_owners = owners
			if skip:
				continue
			emitted[key] = true
			if line.is_empty():
				line.append(start)
			line.append(end)
	if line.size() > 1:
		output.append({"points":GlobeProjection.to_unit_line(line),"owners":current_owners,"kind":"macro" if current_owners.size() == 2 else "coast"})

func economic_available(entity_id: String) -> bool:
	var totals := (economies.get(entity_id,{}) as Dictionary).get("daily_totals",{}) as Dictionary
	var value: Variant = totals.get("fulfillment_bp")
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=10000.0

func output_value(entity_id: String) -> Variant:
	var aggregate := str((economies.get(entity_id,{}) as Dictionary).get("economic_aggregate_id",""))
	return output_values.get(aggregate)

func color(entity_id: String, mode: String) -> Color:
	if mode=="geographic": return Color("69745e")
	if mode=="military": return Color("69745e")
	if mode=="economic":
		if show_output_values:
			var value: Variant = output_value(entity_id)
			return STRUCTURE.output_color(float(value),output_maximum) if value!=null else Color("465451")
		return STRUCTURE.color(str((records.get(entity_id,{}) as Dictionary).get("source_historical_id","")))
	if mode != "political":
		var economy := economies.get(entity_id, {}) as Dictionary
		var totals := economy.get("daily_totals", {}) as Dictionary
		# Unknown is not zero, and these observations are not production output.
		if mode not in ["fulfillment","shortage"] or not economic_available(entity_id):
			return Color("465451")
		var fulfillment := clampf(float(totals.get("fulfillment_bp", 0)) / 10000.0, 0.0, 1.0)
		return Color("98654e").lerp(Color("689789"), fulfillment) if mode == "fulfillment" else Color("708e86").lerp(Color("b05f43"), 1.0 - fulfillment)
	if visual_textures.has(entity_id):
		return Color.WHITE
	return Color(str((resolved_visuals.get(entity_id, {}) as Dictionary).get("color", "#6b8075")))
