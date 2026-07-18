class_name TravelGraphService
extends RefCounted
## Pre-indexed deterministic local travel graph.

var edges: Dictionary = {}
var modes: Dictionary = {}
var adjacency: Dictionary = {}
var mode_edge_index: Dictionary = {}
var known_edge_ids: Dictionary = {}


func configure(
	edge_records: Array,
	mode_records: Array,
	location_service: SpatialLocationService
) -> V2LifeLoopResult:
	edges.clear()
	modes.clear()
	adjacency.clear()
	mode_edge_index.clear()
	known_edge_ids.clear()
	for raw_location_id: Variant in location_service.locations.keys():
		adjacency[str(raw_location_id)] = []
	for raw_mode: Variant in mode_records:
		if not raw_mode is Dictionary:
			return V2LifeLoopResult.fail("invalid_transport_mode", "交通方式记录无效")
		var mode: Dictionary = (raw_mode as Dictionary).duplicate(true)
		var mode_id: String = str(mode.get("mode_id", ""))
		if mode_id.is_empty() or modes.has(mode_id):
			return V2LifeLoopResult.fail(
				"duplicate_transport_mode", "交通方式 ID 缺失或重复", mode_id
			)
		modes[mode_id] = mode
		mode_edge_index[mode_id] = []
	for raw_edge: Variant in edge_records:
		if not raw_edge is Dictionary:
			return V2LifeLoopResult.fail("invalid_edge", "交通边记录无效")
		var edge: Dictionary = (raw_edge as Dictionary).duplicate(true)
		var edge_id: String = str(edge.get("edge_id", ""))
		var from_id: String = str(edge.get("from_location_id", ""))
		var to_id: String = str(edge.get("to_location_id", ""))
		if (
			edge_id.is_empty() or edges.has(edge_id)
			or not adjacency.has(from_id) or not adjacency.has(to_id)
		):
			return V2LifeLoopResult.fail(
				"invalid_edge_reference", "交通边 ID 或地点引用无效", edge_id,
				[edge_id, from_id, to_id]
			)
		edges[edge_id] = edge
		_append_arc(from_id, edge_id, from_id, to_id)
		if bool(edge.get("bidirectional", false)):
			_append_arc(to_id, edge_id, to_id, from_id)
		for raw_mode_id: Variant in edge.get("available_modes", []) as Array:
			var mode_id: String = str(raw_mode_id)
			if not modes.has(mode_id):
				return V2LifeLoopResult.fail(
					"unknown_transport_mode", "交通边引用未知方式", mode_id, [edge_id]
				)
			(mode_edge_index[mode_id] as Array).append(edge_id)
	for raw_person_id: Variant in location_service.known_location_ids.keys():
		var person_id: String = str(raw_person_id)
		var known: Dictionary = {}
		for raw_edge_id: Variant in edges.keys():
			var edge_id: String = str(raw_edge_id)
			var edge: Dictionary = edges[edge_id] as Dictionary
			if (
				location_service.knows_location(person_id, str(edge.get("from_location_id", "")))
				and location_service.knows_location(person_id, str(edge.get("to_location_id", "")))
			):
				known[edge_id] = true
		known_edge_ids[person_id] = known
	if not graph_is_connected():
		return V2LifeLoopResult.fail("disconnected_graph", "正式交通图不连通")
	return V2LifeLoopResult.ok(
		"正式交通图已建立",
		{"node_count": adjacency.size(), "edge_count": edges.size(), "mode_count": modes.size()}
	)


func outgoing(location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_arc: Variant in adjacency.get(location_id, []) as Array:
		result.append((raw_arc as Dictionary).duplicate(true))
	return result


func get_edge(edge_id: String) -> Dictionary:
	var value: Variant = edges.get(edge_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func get_mode(mode_id: String) -> Dictionary:
	var value: Variant = modes.get(mode_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func knows_edge(person_id: String, edge_id: String) -> bool:
	return (
		known_edge_ids.has(person_id)
		and (known_edge_ids[person_id] as Dictionary).has(edge_id)
	)


func discover_edge(person_id: String, edge_id: String) -> V2LifeLoopResult:
	if not known_edge_ids.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到人物", person_id, [person_id])
	if not edges.has(edge_id):
		return V2LifeLoopResult.fail("unknown_route", "找不到交通边", edge_id, [edge_id])
	var known: Dictionary = known_edge_ids[person_id] as Dictionary
	known[edge_id] = true
	known_edge_ids[person_id] = known
	return V2LifeLoopResult.ok("交通连接已获知", {}, [person_id, edge_id])


func segment_options(
	arc: Dictionary, departure_hour: int
) -> Array[Dictionary]:
	var edge_id: String = str(arc.get("edge_id", ""))
	if not edges.has(edge_id):
		return []
	var edge: Dictionary = edges[edge_id] as Dictionary
	if not bool(edge.get("active", false)):
		return []
	var result: Array[Dictionary] = []
	var mode_ids: Array[String] = []
	for raw_mode_id: Variant in edge.get("available_modes", []) as Array:
		mode_ids.append(str(raw_mode_id))
	mode_ids.sort()
	for mode_id: String in mode_ids:
		var waiting: int = waiting_hours(edge_id, mode_id, departure_hour)
		if waiting < 0:
			continue
		var duration: int = int(
			(edge.get("duration_hours_by_mode", {}) as Dictionary).get(mode_id, 0)
		)
		result.append({
			"route_segment_id": "%s:%s:%s" % [
				edge_id, str(arc.get("from_location_id", "")), mode_id,
			],
			"edge_id": edge_id,
			"from_location_id": str(arc.get("from_location_id", "")),
			"to_location_id": str(arc.get("to_location_id", "")),
			"mode_id": mode_id,
			"departure_hour": departure_hour + waiting,
			"arrival_hour": departure_hour + waiting + duration,
			"duration_hours": duration,
			"waiting_hours": waiting,
			"cost_centimes": int(
				(edge.get("cost_centimes_by_mode", {}) as Dictionary).get(mode_id, 0)
			),
			"fatigue": int(
				(edge.get("fatigue_by_mode", {}) as Dictionary).get(mode_id, 0)
			),
			"stress": int(
				(edge.get("stress_by_mode", {}) as Dictionary).get(mode_id, 0)
			),
		})
	return result


func waiting_hours(edge_id: String, mode_id: String, departure_hour: int) -> int:
	if not edges.has(edge_id):
		return -1
	var edge: Dictionary = edges[edge_id] as Dictionary
	var ranges: Dictionary = edge.get("opening_hours_by_mode", {}) as Dictionary
	var raw_range: Variant = ranges.get(mode_id, [])
	if not raw_range is Array or (raw_range as Array).size() != 2:
		return -1
	var open_hour: int = int((raw_range as Array)[0])
	var close_hour: int = int((raw_range as Array)[1])
	var hour_of_day: int = int(V2DateTime.from_total_hour(departure_hour).get("hour", -1))
	if hour_of_day >= open_hour and hour_of_day < close_hour:
		return 0
	if open_hour == 0 and close_hour == 24:
		return 0
	if hour_of_day < open_hour:
		return open_hour - hour_of_day
	return 24 - hour_of_day + open_hour


func graph_is_connected() -> bool:
	if adjacency.is_empty():
		return false
	var start_id: String = str(adjacency.keys()[0])
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for raw_arc: Variant in adjacency.get(current, []) as Array:
			var target: String = str((raw_arc as Dictionary).get("to_location_id", ""))
			if visited.has(target):
				continue
			visited[target] = true
			queue.append(target)
	return visited.size() == adjacency.size()


func get_persistent_state() -> Dictionary:
	var active_edges: Dictionary = {}
	for raw_edge_id: Variant in edges.keys():
		var edge_id: String = str(raw_edge_id)
		active_edges[edge_id] = bool((edges[edge_id] as Dictionary).get("active", false))
	return {
		"active_edges": active_edges,
		"known_edge_ids": known_edge_ids.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("active_edges", {}) is Dictionary
		or not state.get("known_edge_ids", {}) is Dictionary
	):
		return false
	var active: Dictionary = state["active_edges"] as Dictionary
	if active.size() != edges.size():
		return false
	for raw_edge_id: Variant in active.keys():
		var edge_id: String = str(raw_edge_id)
		if not edges.has(edge_id):
			return false
		var edge: Dictionary = edges[edge_id] as Dictionary
		edge["active"] = bool(active[edge_id])
		edges[edge_id] = edge
	var restored_known: Dictionary = state["known_edge_ids"] as Dictionary
	for raw_person_id: Variant in restored_known.keys():
		if not known_edge_ids.has(str(raw_person_id)) or not restored_known[raw_person_id] is Dictionary:
			return false
		for raw_edge_id: Variant in (restored_known[raw_person_id] as Dictionary).keys():
			if not edges.has(str(raw_edge_id)):
				return false
	known_edge_ids = restored_known.duplicate(true)
	return true


func _append_arc(location_id: String, edge_id: String, from_id: String, to_id: String) -> void:
	var arcs: Array = adjacency[location_id] as Array
	arcs.append({
		"edge_id": edge_id,
		"from_location_id": from_id,
		"to_location_id": to_id,
	})
	arcs.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("edge_id", "")) < str(
			(right as Dictionary).get("edge_id", "")
		)
	)
	adjacency[location_id] = arcs
