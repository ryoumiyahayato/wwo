extends RefCounted
## All time is game seconds. Index construction is input preparation, not resolver work.

const VERSION: String = "land-war-resolver-v0.1"
var time: float = 0.0
var seed: int = 1
var random_state: Dictionary = {"algorithm": "keyed-mod-prime-v1", "draws": 0}
var units: Dictionary = {}
var areas: Dictionary = {}
var missions: Dictionary = {}
var coordination: Dictionary = {}
var mission_dependents: Dictionary = {}
var contacts: Dictionary = {}
var area_units: Dictionary = {}
var active_areas: Dictionary = {}
var touched_units: Dictionary = {}
var touched_areas: Dictionary = {}
var totals: Dictionary = {"personnel": 0.0, "ammunition": 0.0, "equipment": 0.0,
	"casualties": 0.0, "ammo_spent": 0.0, "equipment_lost": 0.0}
var counters: Dictionary = {"areas_examined": 0, "units_examined": 0,
	"contacts_resolved": 0, "events_processed": 0, "segments": 0}
var events: Array[Dictionary] = []
var event_ids: Dictionary = {}


func add_area(record: Dictionary) -> void:
	assert(not areas.has(record.id))
	assert(float(record.frontage) >= 0.0 and float(record.size_km) > 0.0)
	assert(float(record.cover) >= 0.0 and float(record.cover) <= 1.0)
	assert(float(record.concealment) >= 0.0 and float(record.concealment) <= 1.0)
	assert(float(record.visibility) >= 0.0 and float(record.visibility) <= 1.0)
	assert(float(record.movement_modifier) >= 0.0)
	areas[record.id] = record.duplicate(true)
	area_units[record.id] = {}


func add_mission(record: Dictionary) -> void:
	assert(not missions.has(record.id))
	assert(record.posture in ["idle", "hold", "advance", "support", "withdraw"])
	missions[record.id] = record.duplicate(true)


func add_unit(record: Dictionary) -> void:
	assert(not units.has(record.id) and areas.has(record.area_id) and missions.has(record.mission_id))
	assert(float(record.effective) >= 0.0 and float(record.effective) <= float(record.personnel_total))
	assert(float(record.ammunition) >= 0.0 and float(record.equipment) >= 0.0)
	assert(is_equal_approx(float(record.personnel_total), float(record.effective) + float(record.casualties)))
	units[record.id] = record.duplicate(true)
	area_units[record.area_id][record.id] = true
	totals.personnel += float(record.personnel_total)
	totals.ammunition += float(record.ammunition) + float(record.ammo_spent)
	totals.equipment += float(record.equipment) + float(record.equipment_lost)
	totals.casualties += float(record.casualties)
	totals.ammo_spent += float(record.ammo_spent)
	totals.equipment_lost += float(record.equipment_lost)
	if str(missions[record.mission_id].posture) != "idle" or float(record.suppression) > 0.001:
		wake(str(record.area_id))


func wake(area_id: String) -> void:
	active_areas[area_id] = true
	touched_areas[area_id] = true


func examine_unit(unit_id: String) -> Dictionary:
	counters.units_examined += 1
	return units[unit_id]


func set_coordination(unit_id: String, assignment: Dictionary) -> void:
	assert(units.has(unit_id) and not coordination.has(unit_id))
	coordination[unit_id] = assignment.duplicate(true)
	for mission_id: String in assignment.get("after", []):
		assert(missions.has(mission_id))
		if not mission_dependents.has(mission_id):
			mission_dependents[mission_id] = {}
		mission_dependents[mission_id][unit_id] = true
	if float(assignment.get("release_time", time)) > time:
		assert(schedule_event("release_" + unit_id, float(assignment.release_time), "coordination_release", {"unit_id": unit_id}))
	wake(str(units[unit_id].area_id))


func schedule_event(id: String, due: float, kind: String, payload: Dictionary) -> bool:
	if id.is_empty() or event_ids.has(id) or not is_finite(due) or due < time:
		return false
	if kind not in ["order", "reinforcement", "area_change", "coordination_release"]:
		return false
	# Validate references at submission; reinforcement is to an existing input area.
	if kind == "order" and (not units.has(payload.get("unit_id", "")) or not missions.has(payload.get("mission_id", ""))):
		return false
	if kind == "reinforcement" and (not payload.has("unit") or units.has(payload.unit.id) or not areas.has(payload.unit.area_id) or not missions.has(payload.unit.mission_id)):
		return false
	if kind == "area_change" and not areas.has(payload.get("area_id", "")):
		return false
	if kind == "coordination_release" and not units.has(payload.get("unit_id", "")):
		return false
	event_ids[id] = true
	events.append({"id": id, "time": due, "kind": kind, "payload": payload.duplicate(true)})
	var index: int = events.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _before(events[index], events[parent]):
			break
		var swap: Dictionary = events[parent]
		events[parent] = events[index]
		events[index] = swap
		index = parent
	return true


func next_event_time() -> float:
	return INF if events.is_empty() else float(events[0].time)


func pop_event() -> Dictionary:
	var result: Dictionary = events[0]
	var last: Dictionary = events.pop_back()
	if events.is_empty():
		return result
	events[0] = last
	var index: int = 0
	while index * 2 + 1 < events.size():
		var child: int = index * 2 + 1
		if child + 1 < events.size() and _before(events[child + 1], events[child]):
			child += 1
		if not _before(events[child], events[index]):
			break
		var swap: Dictionary = events[index]
		events[index] = events[child]
		events[child] = swap
		index = child
	return result


static func _before(a: Dictionary, b: Dictionary) -> bool:
	return str(a.id) < str(b.id) if float(a.time) == float(b.time) else float(a.time) < float(b.time)


static func sorted_ids(records: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id: Variant in records:
		result.append(str(id))
	result.sort()
	return result


func variation(key: String, epoch: int) -> float:
	# Immutable keyed draws: observer, faction label, and container order are absent.
	var value: int = posmod(seed, 2147483647)
	for character: int in key.to_utf8_buffer():
		value = (value * 31 + character) % 2147483647
	value = (value * 48271 + epoch) % 2147483647
	random_state.draws += 1
	return 0.96 + float(value % 1001) / 1000.0 * 0.08


func snapshot() -> Dictionary:
	# Explicit diagnostic export may scan the snapshot; resolve_until never uses it.
	return {"version": VERSION, "time": time, "seed": seed,
		"random_state": random_state.duplicate(true), "units": units.duplicate(true),
		"areas": areas.duplicate(true), "missions": missions.duplicate(true),
		"coordination": coordination.duplicate(true), "mission_dependents": mission_dependents.duplicate(true),
		"contacts": contacts.duplicate(true),
		"active_areas": active_areas.duplicate(), "events": events.duplicate(true),
		"totals": totals.duplicate(), "counters": counters.duplicate()}
