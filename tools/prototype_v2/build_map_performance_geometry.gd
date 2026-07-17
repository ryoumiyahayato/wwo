extends SceneTree
## Offline builder for fixed Robinson world geometry, five LODs, and static anchors.

const OUTPUT_PATH := "res://data/prototype_v2/prototype_map_geometry_cache.json"
const WORLD_SIZE := Vector2(1080.0, 540.0)
const ROBINSON_X := [
	1.0, 0.9986, 0.9954, 0.99, 0.9822, 0.973, 0.96, 0.9427, 0.9216,
	0.8962, 0.8679, 0.835, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213,
	0.5722, 0.5322,
]
const ROBINSON_Y := [
	0.0, 0.062, 0.124, 0.186, 0.248, 0.31, 0.372, 0.434, 0.4958,
	0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394,
	0.9761, 1.0,
]
const ROBINSON_X_EXTENT := 2.6662696851
const ROBINSON_Y_EXTENT := 1.3523
const COUNTRY_LODS := {
	"lod0": 0.65,
	"lod1": 0.25,
	"lod2": 0.10,
	"lod3": 0.04,
	"lod4": 0.015,
}
const ADMINISTRATIVE_LODS := {
	"lod3": 0.04,
	"lod4": 0.012,
}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var coastlines: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_world_coastlines.json"
	)
	var countries_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_countries.json"
	)
	var regions_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_regions.json"
	)
	var cities_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_cities.json"
	)
	var ports_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_ports.json"
	)
	var institutions_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_institutions.json"
	)
	var organizations_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_organizations.json"
	)
	var rail_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_rail_segments.json"
	)
	var road_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_road_segments.json"
	)
	var shipping_document: Dictionary = _load_json(
		"res://data/prototype_v2/prototype_shipping_routes.json"
	)
	var source_documents: Array[Dictionary] = [
		coastlines,
		countries_document,
		regions_document,
		cities_document,
		ports_document,
		institutions_document,
		organizations_document,
		rail_document,
		road_document,
		shipping_document,
	]
	for document: Dictionary in source_documents:
		if document.is_empty():
			quit(1)
			return

	var country_id_by_iso: Dictionary = {}
	for country_variant: Variant in countries_document.get("countries", []):
		var country: Dictionary = country_variant as Dictionary
		for iso_variant: Variant in country.get("geometry_iso_a3", []):
			country_id_by_iso[str(iso_variant)] = str(country.get("id", ""))

	var projected_feature_polygons: Array[Array] = []
	for feature_variant: Variant in coastlines.get("features", []):
		var feature: Dictionary = feature_variant as Dictionary
		var polygons: Array = []
		for polygon_variant: Variant in _feature_polygons(feature):
			var polygon: Dictionary = polygon_variant as Dictionary
			var projected_holes: Array = []
			for hole_variant: Variant in polygon.get("holes", []):
				projected_holes.append(_project_ring(hole_variant))
			polygons.append({
				"outer": _project_ring(polygon.get("outer", [])),
				"holes": projected_holes,
			})
		projected_feature_polygons.append(polygons)

	var country_lods: Dictionary = {}
	for lod_id_variant: Variant in COUNTRY_LODS.keys():
		var lod_id: String = str(lod_id_variant)
		var epsilon: float = float(COUNTRY_LODS[lod_id])
		var lod_features: Array = []
		var features: Array = coastlines.get("features", []) as Array
		for feature_index: int in range(features.size()):
			var feature: Dictionary = features[feature_index] as Dictionary
			var cached_polygons: Array = _serialize_polygons(
				projected_feature_polygons[feature_index],
				epsilon,
				true
			)
			var bounds: Rect2 = _bounds_for_serialized_polygons(cached_polygons)
			lod_features.append({
				"source_index": feature_index,
				"stable_id": str(feature.get("stable_id", feature.get("id", ""))),
				"iso_a3": str(feature.get("iso_a3", "")),
				"country_id": str(country_id_by_iso.get(str(feature.get("iso_a3", "")), "")),
				"continent": str(feature.get("continent", "")),
				"bounds": _rect_to_array(bounds),
				"polygons": cached_polygons,
			})
		country_lods[lod_id] = lod_features

	var raw_administrative_polygons: Dictionary = {}
	for unit_variant: Variant in regions_document.get("administrative_units", []):
		var unit: Dictionary = unit_variant as Dictionary
		var unit_id: String = str(unit.get("stable_id", unit.get("id", "")))
		var projected_polygons: Array[PackedVector2Array] = []
		for polygon_variant: Variant in unit.get("geometry", []):
			var polygon: Dictionary = polygon_variant as Dictionary
			var projected: PackedVector2Array = _project_ring(polygon.get("outer", []))
			if projected.size() >= 3:
				projected_polygons.append(projected)
		raw_administrative_polygons[unit_id] = projected_polygons

	var administrative_lods: Dictionary = {}
	for lod_id_variant: Variant in ADMINISTRATIVE_LODS.keys():
		var lod_id: String = str(lod_id_variant)
		var epsilon: float = float(ADMINISTRATIVE_LODS[lod_id])
		var lod_units: Array = []
		for unit_variant: Variant in regions_document.get("administrative_units", []):
			var unit: Dictionary = unit_variant as Dictionary
			var unit_id: String = str(unit.get("stable_id", unit.get("id", "")))
			var serialized: Array = _serialize_polygon_rings(
				raw_administrative_polygons.get(unit_id, []) as Array[PackedVector2Array],
				epsilon
			)
			lod_units.append({
				"unit_id": unit_id,
				"bounds": _rect_to_array(_bounds_for_serialized_rings(serialized)),
				"polygons": serialized,
			})
		administrative_lods[lod_id] = lod_units

	var macro_regions: Array = []
	for region_variant: Variant in regions_document.get("regions", []):
		var region: Dictionary = region_variant as Dictionary
		var merged: Array[PackedVector2Array] = []
		for unit_id_variant: Variant in region.get("administrative_unit_ids", []):
			var unit_polygons: Array[PackedVector2Array] = raw_administrative_polygons.get(
				str(unit_id_variant),
				[]
			) as Array[PackedVector2Array]
			for polygon: PackedVector2Array in unit_polygons:
				_merge_polygon_into_collection(merged, polygon)
		var lod_polygons: Dictionary = {}
		for lod_id_variant: Variant in ADMINISTRATIVE_LODS.keys():
			var lod_id: String = str(lod_id_variant)
			lod_polygons[lod_id] = _serialize_polygon_rings(
				merged,
				float(ADMINISTRATIVE_LODS[lod_id])
			)
		var bounds: Rect2 = _bounds_for_serialized_rings(
			lod_polygons.get("lod4", []) as Array
		)
		macro_regions.append({
			"region_id": str(region.get("id", "")),
			"bounds": _rect_to_array(bounds),
			"lods": lod_polygons,
		})

	var anchors := {
		"countries": _project_record_points(
			countries_document.get("countries", []) as Array,
			"id",
			"label_anchor"
		),
		"regions": _project_record_points(
			regions_document.get("regions", []) as Array,
			"id",
			"label_anchor"
		),
		"administrative_units": _project_record_points(
			regions_document.get("administrative_units", []) as Array,
			"stable_id",
			"label_anchor"
		),
		"cities": _project_record_points(
			cities_document.get("cities", []) as Array,
			"id",
			"lon_lat"
		),
		"ports": _project_record_points(
			ports_document.get("ports", []) as Array,
			"id",
			"lon_lat"
		),
		"institutions": _project_record_points(
			institutions_document.get("institutions", []) as Array,
			"id",
			"lon_lat"
		),
		"organizations": _project_record_points(
			organizations_document.get("catalog", []) as Array,
			"id",
			"lon_lat"
		),
		"camera_focus": {
			"world": _point_to_array(_project_lon_lat([4.0, 14.0])),
			"europe": _point_to_array(_project_lon_lat([9.0, 49.0])),
			"france": _point_to_array(_project_lon_lat([2.25, 47.1])),
			"lille": _point_to_array(_project_lon_lat([3.064, 50.637])),
		},
	}
	var city_points: Dictionary = anchors.get("cities", {}) as Dictionary
	var transport := {
		"rail": _project_city_segments(
			rail_document.get("segments", []) as Array,
			city_points
		),
		"road": _project_city_segments(
			road_document.get("segments", []) as Array,
			city_points
		),
		"shipping": _project_waypoint_routes(
			shipping_document.get("routes", []) as Array
		),
	}
	var result := {
		"prototype_only": true,
		"schema_version": 1,
		"generated_by": "res://tools/prototype_v2/build_map_performance_geometry.gd",
		"projection": {
			"id": "robinson_fixed_world_1080x540",
			"world_size": [WORLD_SIZE.x, WORLD_SIZE.y],
		},
		"lod_thresholds": {
			"lod0_max": 1.5,
			"lod1_max": 6.2,
			"lod2_max": 12.0,
			"lod3_max": 48.0,
			"lod4_max": 96.0,
		},
		"country_lods": country_lods,
		"administrative_lods": administrative_lods,
		"macro_regions": macro_regions,
		"anchors": anchors,
		"transport": transport,
		"war_example": {
			"control_polygon": _serialize_fixed_polygon([
				[4.1, 49.1],
				[7.9, 48.0],
				[8.2, 50.8],
				[4.4, 51.0],
			]),
			"front_points": _project_points([
				[5.8, 49.8],
				[5.95, 49.45],
				[5.75, 49.1],
				[6.0, 48.75],
				[5.82, 48.4],
			]),
		},
		"graticule": _build_graticule(),
	}
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to open geometry cache output")
		quit(1)
		return
	file.store_string(JSON.stringify(result))
	print("MAP_PERFORMANCE_GEOMETRY_SAVED %s" % OUTPUT_PATH)
	quit(0)


func _load_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid JSON document %s" % path)
		return {}
	return parsed as Dictionary


func _feature_polygons(feature: Dictionary) -> Array:
	var polygons: Array = feature.get("polygons", []) as Array
	if not polygons.is_empty():
		return polygons
	var result: Array = []
	for ring_variant: Variant in feature.get("rings", []):
		result.append({"outer": ring_variant, "holes": []})
	return result


func _project_ring(source: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if source is Array:
		for point_variant: Variant in source as Array:
			result.append(_project_lon_lat(point_variant))
	if result.size() >= 2 and result[0].is_equal_approx(result[-1]):
		result.remove_at(result.size() - 1)
	return result


func _project_lon_lat(value: Variant) -> Vector2:
	var source: Array = value as Array if value is Array else []
	if source.size() < 2:
		return Vector2.ZERO
	var longitude_radians: float = deg_to_rad(clampf(float(source[0]), -180.0, 180.0))
	var latitude: float = clampf(float(source[1]), -90.0, 90.0)
	var coefficient_index: float = absf(latitude) / 5.0
	var lower: int = clampi(int(floor(coefficient_index)), 0, ROBINSON_X.size() - 1)
	var upper: int = mini(lower + 1, ROBINSON_X.size() - 1)
	var weight: float = coefficient_index - float(lower)
	var x_coefficient: float = lerpf(float(ROBINSON_X[lower]), float(ROBINSON_X[upper]), weight)
	var y_coefficient: float = lerpf(float(ROBINSON_Y[lower]), float(ROBINSON_Y[upper]), weight)
	var projected_x: float = 0.8487 * longitude_radians * x_coefficient
	var projected_y: float = 1.3523 * signf(latitude) * y_coefficient
	return Vector2(
		(projected_x / (ROBINSON_X_EXTENT * 2.0) + 0.5) * WORLD_SIZE.x,
		(0.5 - projected_y / (ROBINSON_Y_EXTENT * 2.0)) * WORLD_SIZE.y
	)


func _serialize_polygons(source: Array, epsilon: float, include_triangles: bool) -> Array:
	var result: Array = []
	for polygon_variant: Variant in source:
		var polygon: Dictionary = polygon_variant as Dictionary
		var outer: PackedVector2Array = _simplify_closed_ring(
			polygon.get("outer", PackedVector2Array()) as PackedVector2Array,
			epsilon
		)
		if outer.size() < 3:
			continue
		var holes: Array = []
		for hole_variant: Variant in polygon.get("holes", []):
			var hole: PackedVector2Array = _simplify_closed_ring(
				hole_variant as PackedVector2Array,
				epsilon
			)
			if hole.size() >= 3:
				holes.append({
					"outer": _points_to_array(hole),
					"triangles": _ints_to_array(
						Geometry2D.triangulate_polygon(hole)
					),
				})
		var serialized := {
			"outer": _points_to_array(outer),
			"holes": holes,
		}
		if include_triangles:
			serialized["triangles"] = _ints_to_array(
				Geometry2D.triangulate_polygon(outer)
			)
		result.append(serialized)
	return result


func _serialize_polygon_rings(
	source: Array[PackedVector2Array],
	epsilon: float
) -> Array:
	var result: Array = []
	for polygon: PackedVector2Array in source:
		var simplified: PackedVector2Array = _simplify_closed_ring(polygon, epsilon)
		if simplified.size() < 3:
			continue
		result.append({
			"outer": _points_to_array(simplified),
			"triangles": _ints_to_array(Geometry2D.triangulate_polygon(simplified)),
		})
	return result


func _simplify_closed_ring(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 4 or epsilon <= 0.0:
		return points.duplicate()
	var pivot: int = points.size() / 2
	var first_arc := PackedVector2Array()
	for index: int in range(pivot + 1):
		first_arc.append(points[index])
	var second_arc := PackedVector2Array()
	for index: int in range(pivot, points.size()):
		second_arc.append(points[index])
	second_arc.append(points[0])
	var first_simplified: PackedVector2Array = _simplify_open(first_arc, epsilon)
	var second_simplified: PackedVector2Array = _simplify_open(second_arc, epsilon)
	var result := PackedVector2Array()
	for point: Vector2 in first_simplified:
		result.append(point)
	for index: int in range(1, second_simplified.size() - 1):
		result.append(second_simplified[index])
	return result if result.size() >= 3 else points.duplicate()


func _simplify_open(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()
	var maximum_distance: float = -1.0
	var split_index: int = -1
	for index: int in range(1, points.size() - 1):
		var distance: float = _distance_to_segment(
			points[index],
			points[0],
			points[-1]
		)
		if distance > maximum_distance:
			maximum_distance = distance
			split_index = index
	if maximum_distance <= epsilon or split_index < 0:
		return PackedVector2Array([points[0], points[-1]])
	var first := PackedVector2Array()
	for index: int in range(split_index + 1):
		first.append(points[index])
	var second := PackedVector2Array()
	for index: int in range(split_index, points.size()):
		second.append(points[index])
	var left: PackedVector2Array = _simplify_open(first, epsilon)
	var right: PackedVector2Array = _simplify_open(second, epsilon)
	left.resize(left.size() - 1)
	left.append_array(right)
	return left


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(start)
	var ratio: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _merge_polygon_into_collection(
	collection: Array[PackedVector2Array],
	source: PackedVector2Array
) -> void:
	var pending: PackedVector2Array = source
	var index: int = 0
	while index < collection.size():
		var merged: Array[PackedVector2Array] = Geometry2D.merge_polygons(
			collection[index],
			pending
		)
		if merged.size() == 1:
			pending = merged[0]
			collection.remove_at(index)
			index = 0
		else:
			index += 1
	collection.append(pending)


func _project_record_points(records: Array, id_field: String, point_field: String) -> Dictionary:
	var result: Dictionary = {}
	for record_variant: Variant in records:
		var record: Dictionary = record_variant as Dictionary
		if not record.has(point_field):
			continue
		var record_id: String = str(record.get(id_field, record.get("id", "")))
		if record_id.is_empty():
			continue
		var point: Vector2 = _project_lon_lat(record.get(point_field, []))
		result[record_id] = _point_to_array(point)
	return result


func _project_city_segments(records: Array, city_points: Dictionary) -> Array:
	var result: Array = []
	for record_variant: Variant in records:
		var record: Dictionary = record_variant as Dictionary
		var from_id: String = str(record.get("from_city_id", ""))
		var to_id: String = str(record.get("to_city_id", ""))
		if not city_points.has(from_id) or not city_points.has(to_id):
			continue
		var start: Vector2 = _array_to_vector(city_points[from_id])
		var end: Vector2 = _array_to_vector(city_points[to_id])
		result.append({
			"id": str(record.get("id", "")),
			"start": _point_to_array(start),
			"end": _point_to_array(end),
			"bounds": _rect_to_array(Rect2(start, Vector2.ZERO).expand(end)),
		})
	return result


func _project_waypoint_routes(records: Array) -> Array:
	var result: Array = []
	for record_variant: Variant in records:
		var record: Dictionary = record_variant as Dictionary
		var points := PackedVector2Array()
		for point_variant: Variant in record.get("waypoints_lon_lat", []):
			points.append(_project_lon_lat(point_variant))
		result.append({
			"id": str(record.get("id", "")),
			"points": _points_to_array(points),
			"bounds": _rect_to_array(_bounds_for_points(points)),
		})
	return result


func _project_points(source: Array) -> Array:
	var points := PackedVector2Array()
	for point_variant: Variant in source:
		points.append(_project_lon_lat(point_variant))
	return _points_to_array(points)


func _serialize_fixed_polygon(source: Array) -> Dictionary:
	var points := PackedVector2Array()
	for point_variant: Variant in source:
		points.append(_project_lon_lat(point_variant))
	return {
		"outer": _points_to_array(points),
		"triangles": _ints_to_array(Geometry2D.triangulate_polygon(points)),
	}


func _build_graticule() -> Array:
	var result: Array = []
	for longitude: int in range(-150, 180, 30):
		var points := PackedVector2Array()
		for latitude: int in range(-80, 81, 5):
			points.append(_project_lon_lat([longitude, latitude]))
		result.append(_points_to_array(points))
	for latitude: int in range(-60, 61, 30):
		var points := PackedVector2Array()
		for longitude: int in range(-180, 181, 5):
			points.append(_project_lon_lat([longitude, latitude]))
		result.append(_points_to_array(points))
	return result


func _bounds_for_serialized_polygons(polygons: Array) -> Rect2:
	var points := PackedVector2Array()
	for polygon_variant: Variant in polygons:
		var polygon: Dictionary = polygon_variant as Dictionary
		for point_variant: Variant in polygon.get("outer", []):
			points.append(_array_to_vector(point_variant))
	return _bounds_for_points(points)


func _bounds_for_serialized_rings(polygons: Array) -> Rect2:
	return _bounds_for_serialized_polygons(polygons)


func _bounds_for_points(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _points_to_array(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append(_point_to_array(point))
	return result


func _ints_to_array(values: PackedInt32Array) -> Array:
	var result: Array = []
	for value: int in values:
		result.append(value)
	return result


func _point_to_array(point: Vector2) -> Array:
	return [snappedf(point.x, 0.0001), snappedf(point.y, 0.0001)]


func _rect_to_array(rect: Rect2) -> Array:
	return [
		snappedf(rect.position.x, 0.0001),
		snappedf(rect.position.y, 0.0001),
		snappedf(rect.size.x, 0.0001),
		snappedf(rect.size.y, 0.0001),
	]


func _array_to_vector(value: Variant) -> Vector2:
	var source: Array = value as Array if value is Array else []
	if source.size() < 2:
		return Vector2.ZERO
	return Vector2(float(source[0]), float(source[1]))
