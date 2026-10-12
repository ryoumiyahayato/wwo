extends RefCounted
## Stable bottom-up merge, one comparison/copy per step; buffers bounded by scope cap.
var sorted: Array = []
var _buffer: Array = []
var _points: bool = false
var _width: int = 1
var _left: int = 0
var _middle: int = 0
var _right: int = 0
var _a: int = 0
var _b: int = 0
var _out: int = 0
var done: bool = false
var comparisons: int = 0
var records_written: int = 0

func configure(values: Array, points: bool = false) -> void:
	sorted = values.duplicate()
	_buffer = values.duplicate()
	_points = points
	done = values.size() < 2
	_begin_pair()

func _begin_pair() -> void:
	_middle = mini(sorted.size(), _left + _width)
	_right = mini(sorted.size(), _left + 2 * _width)
	_a = _left
	_b = _middle
	_out = _left

func step() -> bool:
	if done:
		return true
	if _out < _right:
		var take_a: bool = _b >= _right
		if _a < _middle and _b < _right:
			comparisons += 1
			take_a = not _before(sorted[_b], sorted[_a])
		if _a >= _middle:
			take_a = false
		_buffer[_out] = sorted[_a] if take_a else sorted[_b]
		_a += int(take_a)
		_b += int(not take_a)
		_out += 1
		records_written += 1
	else:
		_left += 2 * _width
		if _left >= sorted.size():
			var previous: Array = sorted
			sorted = _buffer
			_buffer = previous
			_width *= 2
			_left = 0
			done = _width >= sorted.size()
		_begin_pair()
	return done

func _before(a: Variant, b: Variant) -> bool:
	if not _points:
		return str(a) < str(b)
	return str(a.id) < str(b.id) if a.x == b.x else float(a.x) < float(b.x)
