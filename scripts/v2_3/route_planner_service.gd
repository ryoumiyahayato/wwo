class_name RoutePlannerService
extends RefCounted
## Deterministic fastest/cheapest planning over person-known graph state.

var graph: TravelGraphService
var locations: SpatialLocationService
var _cache: Dictionary = {}
var cache_hits: int = 0
var cache_misses: int = 0


func configure(
	graph_service: TravelGraphService,
	location_service: SpatialLocationService
) -> void:
	graph = graph_service
	locations = location_service
	_cache.clear()
	cache_hits = 0
	cache_misses = 0


func plan_route(
	person_id: String,
	origin_id: String,
	destination_id: String,
	departure_hour: int,
	preference: String,
	available_cash_centimes: int,
	fatigue: int = 0,
	essential: bool = false
) -> V2LifeLoopResult:
	if preference not in ["fastest", "cheapest"]:
		return _failure("invalid_preference", "路线偏好无效", preference, [person_id])
	if not locations.locations.has(origin_id) or not locations.locations.has(destination_id):
		return _failure(
			"unknown_location", "起点或终点不存在", "%s -> %s" % [origin_id, destination_id],
			[person_id, origin_id, destination_id]
		)
	if (
		not locations.knows_location(person_id, origin_id)
		or not locations.knows_location(person_id, destination_id)
	):
		return _failure(
			"unknown_location", "人物不知道该起点或目的地", destination_id,
			[person_id, origin_id, destination_id], ["先通过观察、消息或介绍发现地点"]
		)
	if origin_id == destination_id:
		return V2LifeLoopResult.ok("人物已经在目的地", _route_payload(
			person_id, origin_id, destination_id, departure_hour, preference, []
		), [person_id, origin_id])
	var cache_key: String = "%s|%s|%s|%d|%s|%d|%d|%s" % [
		person_id, origin_id, destination_id, departure_hour, preference,
		available_cash_centimes, fatigue, str(essential),
	]
	if _cache.has(cache_key):
		cache_hits += 1
		return V2LifeLoopResult.ok(
			"已使用确定性路线缓存",
			(_cache[cache_key] as Dictionary).duplicate(true),
			[person_id, origin_id, destination_id]
		)
	cache_misses += 1
	var best: Dictionary = {
		origin_id: {
			"location_id": origin_id,
			"arrival_hour": departure_hour,
			"cost_centimes": 0,
			"fatigue": 0,
			"waiting_hours": 0,
			"segments": [],
			"path_key": "",
		},
	}
	var frontier: Array[Dictionary] = [(best[origin_id] as Dictionary).duplicate(true)]
	while not frontier.is_empty():
		frontier.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return _state_less(left, right, preference)
		)
		var current: Dictionary = frontier.pop_front()
		var current_id: String = str(current.get("location_id", ""))
		var stored: Dictionary = best.get(current_id, {}) as Dictionary
		if _state_signature(current) != _state_signature(stored):
			continue
		if current_id == destination_id:
			var payload: Dictionary = _route_payload(
				person_id, origin_id, destination_id, departure_hour,
				preference, current.get("segments", []) as Array
			)
			_cache[cache_key] = payload.duplicate(true)
			return V2LifeLoopResult.ok(
				"路线已生成", payload, [person_id, origin_id, destination_id]
			)
		for arc: Dictionary in graph.outgoing(current_id):
			var edge_id: String = str(arc.get("edge_id", ""))
			if not graph.knows_edge(person_id, edge_id):
				continue
			for option: Dictionary in graph.segment_options(
				arc, int(current.get("arrival_hour", departure_hour))
			):
				var mode_id: String = str(option.get("mode_id", ""))
				if (
					mode_id == "walk" and fatigue >= 950 and not essential
					and int(option.get("duration_hours", 0)) > 1
				):
					continue
				var next_cost: int = (
					int(current.get("cost_centimes", 0))
					+ int(option.get("cost_centimes", 0))
				)
				if next_cost > available_cash_centimes:
					continue
				var next_segments: Array = (
					current.get("segments", []) as Array
				).duplicate(true)
				next_segments.append(option.duplicate(true))
				var candidate: Dictionary = {
					"location_id": str(option.get("to_location_id", "")),
					"arrival_hour": int(option.get("arrival_hour", departure_hour)),
					"cost_centimes": next_cost,
					"fatigue": (
						int(current.get("fatigue", 0))
						+ int(option.get("fatigue", 0))
						+ int(option.get("waiting_hours", 0)) * 3
					),
					"waiting_hours": (
						int(current.get("waiting_hours", 0))
						+ int(option.get("waiting_hours", 0))
					),
					"segments": next_segments,
					"path_key": _path_key(next_segments),
				}
				var next_id: String = str(candidate.get("location_id", ""))
				if not best.has(next_id) or _state_less(candidate, best[next_id] as Dictionary, preference):
					best[next_id] = candidate
					frontier.append(candidate.duplicate(true))
	return _failure(
		"no_affordable_route", "没有可负担且已知的可用路线",
		"%s -> %s cash=%d" % [origin_id, destination_id, available_cash_centimes],
		[person_id, origin_id, destination_id],
		["选择更便宜路线", "等待交通营业", "先发现连接", "增加可用现金"]
	)


func invalidate_cache() -> void:
	_cache.clear()


func debug_cache_state() -> Dictionary:
	return {
		"entry_count": _cache.size(),
		"hits": cache_hits,
		"misses": cache_misses,
	}


func _route_payload(
	person_id: String,
	origin_id: String,
	destination_id: String,
	departure_hour: int,
	preference: String,
	segments: Array
) -> Dictionary:
	var nodes: Array[String] = [origin_id]
	var total_cost: int = 0
	var total_fatigue: int = 0
	var total_waiting: int = 0
	var modes: Array[String] = []
	var arrival_hour: int = departure_hour
	for raw_segment: Variant in segments:
		var segment: Dictionary = raw_segment as Dictionary
		nodes.append(str(segment.get("to_location_id", "")))
		total_cost += int(segment.get("cost_centimes", 0))
		total_fatigue += int(segment.get("fatigue", 0))
		total_waiting += int(segment.get("waiting_hours", 0))
		arrival_hour = int(segment.get("arrival_hour", arrival_hour))
		var mode_id: String = str(segment.get("mode_id", ""))
		if mode_id not in modes:
			modes.append(mode_id)
	return {
		"success": true,
		"person_id": person_id,
		"origin_id": origin_id,
		"destination_id": destination_id,
		"route_preference": preference,
		"path_nodes": nodes,
		"route_segments": segments.duplicate(true),
		"transport_modes": modes,
		"departure_hour": departure_hour,
		"departure_datetime": V2DateTime.iso_from_total_hour(departure_hour),
		"arrival_hour": arrival_hour,
		"arrival_datetime": V2DateTime.iso_from_total_hour(arrival_hour),
		"total_duration_hours": arrival_hour - departure_hour,
		"total_cost_centimes": total_cost,
		"estimated_fatigue": total_fatigue,
		"waiting_hours": total_waiting,
		"failure_reason": "",
		"path_key": _path_key(segments),
	}


static func _state_less(left: Dictionary, right: Dictionary, preference: String) -> bool:
	if right.is_empty():
		return true
	var left_cost: int = int(left.get("cost_centimes", 0))
	var right_cost: int = int(right.get("cost_centimes", 0))
	var left_arrival: int = int(left.get("arrival_hour", 0))
	var right_arrival: int = int(right.get("arrival_hour", 0))
	if preference == "fastest":
		if left_arrival != right_arrival:
			return left_arrival < right_arrival
		if left_cost != right_cost:
			return left_cost < right_cost
	else:
		if left_cost != right_cost:
			return left_cost < right_cost
		if left_arrival != right_arrival:
			return left_arrival < right_arrival
	return str(left.get("path_key", "")) < str(right.get("path_key", ""))


static func _path_key(segments: Array) -> String:
	var parts: PackedStringArray = []
	for raw_segment: Variant in segments:
		var segment: Dictionary = raw_segment as Dictionary
		parts.append("%s/%s" % [
			str(segment.get("edge_id", "")), str(segment.get("mode_id", "")),
		])
	return ">".join(parts)


static func _state_signature(state: Dictionary) -> String:
	return "%s|%d|%d|%s" % [
		str(state.get("location_id", "")),
		int(state.get("arrival_hour", 0)),
		int(state.get("cost_centimes", 0)),
		str(state.get("path_key", "")),
	]


static func _failure(
	code: String,
	message: String,
	detail: String,
	entities: Array[String],
	alternatives: Array[String] = []
) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = V2LifeLoopResult.fail(code, message, detail, entities)
	result.suggested_alternatives = alternatives.duplicate()
	return result
