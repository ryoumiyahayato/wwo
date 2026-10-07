extends RefCounted
## Stable position range queries. Candidate counts include allies/self in range.
const RangeCursor = preload("res://experiments/war_resolver/continuous/range_cursor.gd")
var _records: Array[Dictionary] = []
var probes: int = 0

func begin_candidates(position: float, reach: float) -> RefCounted:
	var cursor: RangeCursor = RangeCursor.new()
	cursor.configure(self, position, reach)
	return cursor

func build(units: Dictionary, ids: Array[String], state: RefCounted = null) -> void:
	_records.clear()
	for id: String in ids:
		var unit: Dictionary = units[id] if state == null else state.examine_unit(id)
		var x: float = float(unit.position) if state == null or state.spatial_port == null else float(state.spatial_port.get_ref().xy(unit)[0])
		_records.append({"id": id, "x": x})
	_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id) if a.x == b.x else a.x < b.x)

func candidates(position: float, reach: float) -> Array[String]:
	var lower: int = _bound(position - reach, false)
	var upper: int = _bound(position + reach, true)
	var result: Array[String] = []
	for index: int in range(lower, upper):
		result.append(str(_records[index].id))
	result.sort()
	return result

func _bound(value: float, inclusive: bool) -> int:
	var low: int = 0
	var high: int = _records.size()
	while low < high:
		probes += 1
		var middle: int = (low + high) / 2
		if float(_records[middle].x) < value or inclusive and float(_records[middle].x) == value:
			low = middle + 1
		else:
			high = middle
	return low
