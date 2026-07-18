class_name SpatialLocationService
extends RefCounted
## Indexed formal locations, person positions and person-scoped discovery.

const LOCATION_STATES: PackedStringArray = [
	"at_location", "waiting", "in_transit", "interrupted",
]

var locations: Dictionary = {}
var person_positions: Dictionary = {}
var known_location_ids: Dictionary = {}
var _type_index: Dictionary = {}
var _service_index: Dictionary = {}


func configure(location_records: Array, people: Array, start_hour: int) -> V2LifeLoopResult:
	locations.clear()
	person_positions.clear()
	known_location_ids.clear()
	_type_index.clear()
	_service_index.clear()
	for raw_location: Variant in location_records:
		if not raw_location is Dictionary:
			return V2LifeLoopResult.fail("invalid_location", "地点记录无效")
		var location: Dictionary = (raw_location as Dictionary).duplicate(true)
		var location_id: String = str(location.get("location_id", ""))
		if location_id.is_empty() or locations.has(location_id):
			return V2LifeLoopResult.fail(
				"duplicate_location", "地点 ID 缺失或重复", location_id, [location_id]
			)
		locations[location_id] = location
		_index_append(_type_index, str(location.get("location_type", "")), location_id)
		for raw_service: Variant in location.get("available_services", []) as Array:
			_index_append(_service_index, str(raw_service), location_id)
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		var home_id: String = str(person.get("home_location_id", ""))
		if person_id.is_empty() or not locations.has(home_id):
			return V2LifeLoopResult.fail(
				"invalid_person_location", "人物初始地点无效", person_id, [person_id, home_id]
			)
		person_positions[person_id] = _initial_position(person_id, home_id, start_hour)
		var known: Dictionary = {}
		for raw_location: Variant in location_records:
			var location: Dictionary = raw_location as Dictionary
			if person_id in (location.get("known_by_default_person_ids", []) as Array):
				known[str(location.get("location_id", ""))] = true
		known_location_ids[person_id] = known
	return V2LifeLoopResult.ok(
		"正式地点已建立",
		{"location_count": locations.size(), "person_count": person_positions.size()}
	)


func get_location(location_id: String) -> Dictionary:
	var value: Variant = locations.get(location_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func location_name(location_id: String, person_id: String = "", truth_view: bool = false) -> String:
	if not locations.has(location_id):
		return "未知地点"
	if not truth_view and not person_id.is_empty() and not knows_location(person_id, location_id):
		return "未知地点"
	return str((locations[location_id] as Dictionary).get("display_name", location_id))


func knows_location(person_id: String, location_id: String) -> bool:
	return (
		known_location_ids.has(person_id)
		and (known_location_ids[person_id] as Dictionary).has(location_id)
	)


func discover_location(person_id: String, location_id: String) -> V2LifeLoopResult:
	if not person_positions.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到人物", person_id, [person_id])
	if not locations.has(location_id):
		return V2LifeLoopResult.fail("unknown_location", "找不到地点", location_id, [location_id])
	var known: Dictionary = known_location_ids.get(person_id, {}) as Dictionary
	var already_known: bool = known.has(location_id)
	known[location_id] = true
	known_location_ids[person_id] = known
	return V2LifeLoopResult.ok(
		"地点已在认知范围内",
		{"already_known": already_known, "location_id": location_id},
		[person_id, location_id]
	)


func hide_location(person_id: String, location_id: String) -> V2LifeLoopResult:
	if not known_location_ids.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到人物", person_id, [person_id])
	var position: Dictionary = person_positions.get(person_id, {}) as Dictionary
	if str(position.get("current_location_id", "")) == location_id:
		return V2LifeLoopResult.fail(
			"current_location_required", "不能隐藏人物当前所在地点", location_id,
			[person_id, location_id]
		)
	(known_location_ids[person_id] as Dictionary).erase(location_id)
	return V2LifeLoopResult.ok("地点已从人物认知中隐藏", {}, [person_id, location_id])


func known_locations(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var known: Dictionary = known_location_ids.get(person_id, {}) as Dictionary
	var ids: Array[String] = []
	for raw_id: Variant in known.keys():
		ids.append(str(raw_id))
	ids.sort()
	for location_id: String in ids:
		if locations.has(location_id):
			result.append((locations[location_id] as Dictionary).duplicate(true))
	return result


func position_for(person_id: String) -> Dictionary:
	var value: Variant = person_positions.get(person_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func begin_transit(
	person_id: String,
	route_id: String,
	edge_id: String,
	segment_index: int,
	start_hour: int,
	arrival_hour: int,
	destination_id: String
) -> V2LifeLoopResult:
	if not person_positions.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到人物", person_id, [person_id])
	if not locations.has(destination_id):
		return V2LifeLoopResult.fail(
			"unknown_location", "旅行目的地不存在", destination_id, [person_id, destination_id]
		)
	var position: Dictionary = person_positions[person_id] as Dictionary
	if str(position.get("location_state", "")) == "in_transit":
		return V2LifeLoopResult.fail(
			"already_in_transit", "人物已经在途中", str(position.get("current_route_id", "")),
			[person_id]
		)
	position["location_state"] = "in_transit"
	position["current_route_id"] = route_id
	position["current_edge_id"] = edge_id
	position["route_segment_index"] = segment_index
	position["route_started_datetime"] = V2DateTime.iso_from_total_hour(start_hour)
	position["expected_arrival_datetime"] = V2DateTime.iso_from_total_hour(arrival_hour)
	position["travel_destination_id"] = destination_id
	person_positions[person_id] = position
	return V2LifeLoopResult.ok("人物进入途中状态", {}, [person_id, route_id, edge_id])


func set_waiting(
	person_id: String, route_id: String, edge_id: String, destination_id: String
) -> V2LifeLoopResult:
	if not person_positions.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到人物", person_id, [person_id])
	var position: Dictionary = person_positions[person_id] as Dictionary
	position["location_state"] = "waiting"
	position["current_route_id"] = route_id
	position["current_edge_id"] = edge_id
	position["travel_destination_id"] = destination_id
	person_positions[person_id] = position
	return V2LifeLoopResult.ok("人物正在等待交通", {}, [person_id, route_id])


func complete_segment(
	person_id: String, arrival_location_id: String, total_hour: int, final_segment: bool
) -> V2LifeLoopResult:
	if not person_positions.has(person_id) or not locations.has(arrival_location_id):
		return V2LifeLoopResult.fail(
			"invalid_arrival", "无法完成路段到达", arrival_location_id,
			[person_id, arrival_location_id]
		)
	var position: Dictionary = person_positions[person_id] as Dictionary
	position["current_location_id"] = arrival_location_id
	position["last_arrival_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	position["current_edge_id"] = ""
	position["location_state"] = "at_location" if final_segment else "waiting"
	if final_segment:
		position["current_route_id"] = ""
		position["route_segment_index"] = -1
		position["route_started_datetime"] = ""
		position["expected_arrival_datetime"] = ""
		position["travel_destination_id"] = ""
	else:
		position["route_segment_index"] = int(position.get("route_segment_index", 0)) + 1
	person_positions[person_id] = position
	discover_location(person_id, arrival_location_id)
	return V2LifeLoopResult.ok(
		"已到达%s" % location_name(arrival_location_id, person_id),
		{"position": position.duplicate(true)}, [person_id, arrival_location_id]
	)


func interrupt(person_id: String, reason: String) -> V2LifeLoopResult:
	if not person_positions.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到人物", person_id, [person_id])
	var position: Dictionary = person_positions[person_id] as Dictionary
	position["location_state"] = "interrupted"
	position["interruption_reason"] = reason
	position["current_edge_id"] = ""
	person_positions[person_id] = position
	return V2LifeLoopResult.ok("旅行已中断", {}, [person_id])


func force_set_at_location(
	person_id: String, location_id: String, total_hour: int
) -> V2LifeLoopResult:
	if not person_positions.has(person_id) or not locations.has(location_id):
		return V2LifeLoopResult.fail(
			"invalid_position", "无法设置人物地点", location_id,
			[person_id, location_id]
		)
	var position: Dictionary = person_positions[person_id] as Dictionary
	position["current_location_id"] = location_id
	position["location_state"] = "at_location"
	position["current_route_id"] = ""
	position["current_edge_id"] = ""
	position["route_segment_index"] = -1
	position["route_started_datetime"] = ""
	position["expected_arrival_datetime"] = ""
	position["travel_destination_id"] = ""
	position["last_arrival_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	position["interruption_reason"] = ""
	person_positions[person_id] = position
	discover_location(person_id, location_id)
	return V2LifeLoopResult.ok("人物地点已设置", {"position": position}, [person_id, location_id])


func is_open(location_id: String, total_hour: int) -> bool:
	if not locations.has(location_id):
		return false
	var location: Dictionary = locations[location_id] as Dictionary
	var rules: Dictionary = location.get("opening_hours", {}) as Dictionary
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	var key: String = "weekday" if int(value.get("weekday", 0)) < 5 else "weekend"
	var raw_range: Variant = rules.get(key, rules.get("all", []))
	if not raw_range is Array or (raw_range as Array).size() != 2:
		return false
	var hour: int = int(value.get("hour", -1))
	return hour >= int((raw_range as Array)[0]) and hour < int((raw_range as Array)[1])


func provides_service(location_id: String, service_id: String) -> bool:
	return (
		locations.has(location_id)
		and service_id in (
			(locations[location_id] as Dictionary).get("available_services", []) as Array
		)
	)


func locations_for_service(service_id: String) -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _service_index.get(service_id, []) as Array:
		result.append(str(raw_id))
	return result


func get_persistent_state() -> Dictionary:
	return {
		"person_positions": person_positions.duplicate(true),
		"known_location_ids": known_location_ids.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("person_positions", {}) is Dictionary
		or not state.get("known_location_ids", {}) is Dictionary
	):
		return false
	var restored_positions: Dictionary = state["person_positions"] as Dictionary
	var restored_known: Dictionary = state["known_location_ids"] as Dictionary
	if restored_positions.size() != person_positions.size():
		return false
	for raw_person_id: Variant in restored_positions.keys():
		var person_id: String = str(raw_person_id)
		if not person_positions.has(person_id) or not restored_known.has(person_id):
			return false
		var position: Dictionary = restored_positions[person_id] as Dictionary
		if (
			str(position.get("location_state", "")) not in LOCATION_STATES
			or not locations.has(str(position.get("current_location_id", "")))
		):
			return false
		var known: Variant = restored_known[person_id]
		if not known is Dictionary:
			return false
		for raw_location_id: Variant in (known as Dictionary).keys():
			if not locations.has(str(raw_location_id)):
				return false
	person_positions = restored_positions.duplicate(true)
	known_location_ids = restored_known.duplicate(true)
	return true


static func _initial_position(person_id: String, home_id: String, start_hour: int) -> Dictionary:
	return {
		"person_id": person_id,
		"current_location_id": home_id,
		"location_state": "at_location",
		"current_route_id": "",
		"current_edge_id": "",
		"route_segment_index": -1,
		"route_started_datetime": "",
		"expected_arrival_datetime": "",
		"travel_destination_id": "",
		"last_arrival_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"interruption_reason": "",
	}


static func _index_append(index: Dictionary, key: String, value: String) -> void:
	var values: Array = index.get(key, []) as Array
	values.append(value)
	index[key] = values
