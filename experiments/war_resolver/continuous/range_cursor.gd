extends RefCounted
## Each binary-search probe, candidate read and stable-ID sort is resumable.
const Sort = preload("res://experiments/war_resolver/continuous/sort_cursor.gd")
var result: Array[String] = []
var done: bool = false
var _index: RefCounted
var _position: float
var _reach: float
var _phase: String = "lower"
var _low: int = 0
var _high: int = 0
var _lower: int = 0
var _upper: int = 0
var _cursor: int = 0
var _sort: Sort

func configure(index: RefCounted, position: float, reach: float) -> void:
	_index = index
	_position = position
	_reach = reach
	_high = index._records.size()

func step() -> bool:
	match _phase:
		"lower", "upper":
			if _low < _high:
				_index.probes += 1
				var middle: int = (_low + _high) / 2
				var value: float = _position + _reach if _phase == "upper" else _position - _reach
				if float(_index._records[middle].x) < value or _phase == "upper" and float(_index._records[middle].x) == value:
					_low = middle + 1
				else:
					_high = middle
			elif _phase == "lower":
				_lower = _low
				_low = 0
				_high = _index._records.size()
				_phase = "upper"
			else:
				_upper = _low
				_cursor = _lower
				_phase = "gather"
		"gather":
			if _cursor < _upper:
				result.append(str(_index._records[_cursor].id))
				_cursor += 1
			else:
				_sort = Sort.new()
				_sort.configure(result)
				_phase = "sort"
		"sort":
			if _sort.step():
				result = _sort.sorted
				done = true
				_phase = "done"
	return done
