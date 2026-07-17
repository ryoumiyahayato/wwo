class_name PrototypeV2SpatialIndex
extends RefCounted
## Fixed uniform-grid index with reusable query output and generation stamps.

var _world_bounds: Rect2
var _cell_size: float = 90.0
var _columns: int = 1
var _rows: int = 1
var _buckets: Dictionary = {}
var _stamps: PackedInt32Array = PackedInt32Array()
var _generation: int = 1
var last_query_cells: int = 0
var last_query_candidates: int = 0


func configure(world_bounds: Rect2, cell_size: float, record_capacity: int) -> void:
	_world_bounds = world_bounds
	_cell_size = maxf(cell_size, 1.0)
	_columns = maxi(1, int(ceil(world_bounds.size.x / _cell_size)))
	_rows = maxi(1, int(ceil(world_bounds.size.y / _cell_size)))
	_buckets.clear()
	_stamps.resize(maxi(0, record_capacity))
	_stamps.fill(0)
	_generation = 1


func insert(record_index: int, bounds: Rect2) -> void:
	if record_index < 0 or record_index >= _stamps.size():
		return
	var first: Vector2i = _cell_for_point(bounds.position)
	var last: Vector2i = _cell_for_point(bounds.end)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var key: int = y * _columns + x
			var bucket: Array[int] = []
			if _buckets.has(key):
				bucket = _buckets[key] as Array[int]
			bucket.append(record_index)
			_buckets[key] = bucket


func query(bounds: Rect2, output: Array[int]) -> void:
	output.clear()
	last_query_cells = 0
	last_query_candidates = 0
	if _stamps.is_empty():
		return
	_generation += 1
	if _generation >= 2147483000:
		_stamps.fill(0)
		_generation = 1
	var first: Vector2i = _cell_for_point(bounds.position)
	var last: Vector2i = _cell_for_point(bounds.end)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			last_query_cells += 1
			var key: int = y * _columns + x
			if not _buckets.has(key):
				continue
			var bucket: Array[int] = _buckets[key] as Array[int]
			for record_index: int in bucket:
				if _stamps[record_index] == _generation:
					continue
				_stamps[record_index] = _generation
				output.append(record_index)
	last_query_candidates = output.size()


func query_point(point: Vector2, output: Array[int]) -> void:
	query(Rect2(point - Vector2.ONE * 0.001, Vector2.ONE * 0.002), output)


func _cell_for_point(point: Vector2) -> Vector2i:
	var relative: Vector2 = point - _world_bounds.position
	return Vector2i(
		clampi(int(floor(relative.x / _cell_size)), 0, _columns - 1),
		clampi(int(floor(relative.y / _cell_size)), 0, _rows - 1)
	)
