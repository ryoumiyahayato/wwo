class_name AlphaTopologyService
extends RefCounted
## Validates the shared-vertex 10x8 cell topology and location reachability.


func validate(cells: Dictionary, routes: Array[Dictionary]) -> Dictionary:
	var errors: Array[String] = []
	var closed_count: int = 0
	var self_intersection_count: int = 0
	var occupied: Dictionary = {}
	var directed_neighbors: Dictionary = {}
	var total_area: float = 0.0
	for raw_cell_id: Variant in cells.keys():
		var cell_id: String = str(raw_cell_id)
		var cell: Dictionary = cells[cell_id] as Dictionary
		var polygon: Array = cell.get("polygon", []) as Array
		if polygon.size() < 5 or polygon.front() != polygon.back():
			errors.append("非闭合多边形：%s" % cell_id)
		else:
			closed_count += 1
		if _self_intersects(polygon):
			self_intersection_count += 1
			errors.append("自相交多边形：%s" % cell_id)
		total_area += absf(_polygon_area(polygon))
		var grid_key: String = "%d,%d" % [
			int(cell.get("grid_x", -1)), int(cell.get("grid_y", -1)),
		]
		if occupied.has(grid_key):
			errors.append("重叠网格单元：%s/%s" % [occupied[grid_key], cell_id])
		occupied[grid_key] = cell_id
		for raw_neighbor_id: Variant in cell.get("neighbor_ids", []) as Array:
			directed_neighbors["%s>%s" % [cell_id, str(raw_neighbor_id)]] = true
	for raw_edge: Variant in directed_neighbors.keys():
		var edge: String = str(raw_edge)
		var parts: PackedStringArray = edge.split(">")
		if (
			parts.size() != 2
			or not cells.has(parts[1])
			or not directed_neighbors.has("%s>%s" % [parts[1], parts[0]])
		):
			errors.append("错误邻接：%s" % edge)
	for y: int in range(8):
		for x: int in range(10):
			if not occupied.has("%d,%d" % [x, y]):
				errors.append("拓扑缝隙：%d,%d" % [x, y])
	for raw_cell_id: Variant in cells.keys():
		var cell: Dictionary = cells[raw_cell_id] as Dictionary
		if str(cell.get("region_id", "")).is_empty():
			errors.append("无所属地区单元：%s" % str(raw_cell_id))
	var reachability: Dictionary = _validate_reachability(routes)
	errors.append_array(reachability.get("errors", []) as Array[String])
	return {
		"success": errors.is_empty(),
		"errors": errors,
		"cell_count": cells.size(),
		"closed_polygon_count": closed_count,
		"self_intersection_count": self_intersection_count,
		"overlap_count": maxi(0, cells.size() - occupied.size()),
		"gap_count": maxi(0, 80 - occupied.size()),
		"total_area": snappedf(total_area, 0.001),
		"expected_area": 80.0,
		"logical_neighbor_pairs": int(directed_neighbors.size() / 2),
		"reachable_location_count": int(
			reachability.get("reachable_location_count", 0)
		),
	}


func _validate_reachability(routes: Array[Dictionary]) -> Dictionary:
	var adjacency: Dictionary = {}
	for raw_route: Variant in routes:
		var route: Dictionary = raw_route as Dictionary
		var from_id: String = str(route.get("from_location_id", ""))
		var to_id: String = str(route.get("to_location_id", ""))
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		if not adjacency.has(to_id):
			adjacency[to_id] = []
		(adjacency[from_id] as Array).append(to_id)
		if bool(route.get("bidirectional", false)):
			(adjacency[to_id] as Array).append(from_id)
	var errors: Array[String] = []
	if adjacency.is_empty():
		errors.append("交通图为空")
		return {"errors": errors, "reachable_location_count": 0}
	var start_id: String = str(adjacency.keys()[0])
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for raw_target: Variant in adjacency.get(current, []) as Array:
			var target: String = str(raw_target)
			if visited.has(target):
				continue
			visited[target] = true
			queue.append(target)
	for raw_location_id: Variant in adjacency.keys():
		var location_id: String = str(raw_location_id)
		if not visited.has(location_id):
			errors.append("不可到达地点：%s" % location_id)
	return {
		"errors": errors,
		"reachable_location_count": visited.size(),
	}


static func _polygon_area(polygon: Array) -> float:
	var area: float = 0.0
	for index: int in range(polygon.size() - 1):
		var left: Array = polygon[index] as Array
		var right: Array = polygon[index + 1] as Array
		area += float(left[0]) * float(right[1]) - float(right[0]) * float(left[1])
	return area * 0.5


static func _self_intersects(polygon: Array) -> bool:
	if polygon.size() < 5:
		return true
	for first: int in range(polygon.size() - 1):
		var first_next: int = first + 1
		for second: int in range(first + 2, polygon.size() - 1):
			var second_next: int = second + 1
			if first == 0 and second_next == polygon.size() - 1:
				continue
			if _segments_cross(
				polygon[first] as Array,
				polygon[first_next] as Array,
				polygon[second] as Array,
				polygon[second_next] as Array
			):
				return true
	return false


static func _segments_cross(a: Array, b: Array, c: Array, d: Array) -> bool:
	var ab_c: float = _cross(a, b, c)
	var ab_d: float = _cross(a, b, d)
	var cd_a: float = _cross(c, d, a)
	var cd_b: float = _cross(c, d, b)
	return ab_c * ab_d < 0.0 and cd_a * cd_b < 0.0


static func _cross(a: Array, b: Array, c: Array) -> float:
	return (
		(float(b[0]) - float(a[0])) * (float(c[1]) - float(a[1]))
		- (float(b[1]) - float(a[1])) * (float(c[0]) - float(a[0]))
	)
