extends SceneTree
const Sort = preload("res://experiments/war_resolver/continuous/sort_cursor.gd")
const Index = preload("res://experiments/war_resolver/aggregation/contact_index.gd")
var checks: int = 0
var failures: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)
func _initialize() -> void:
	for input: Array in [[], ["b"], ["z", "a", "a", "c", "b"], ["9", "10", "1"]]:
		var expected: Array = input.duplicate()
		expected.sort()
		var sort: Sort = Sort.new()
		sort.configure(input)
		var steps: int = 0
		while not sort.step() and steps < 100:
			steps += 1
		check(sort.sorted == expected, "incremental stable lexical reference")
	var index: Index = Index.new()
	var records: Array[Dictionary] = [{"id": "z", "x": 0.0}, {"id": "b", "x": 2.0}, {"id": "a", "x": 2.0}, {"id": "c", "x": 1.0}]
	var point_sort: Sort = Sort.new()
	point_sort.configure(records, true)
	while not point_sort.step():
		pass
	check(point_sort.sorted == [{"id": "z", "x": 0.0}, {"id": "c", "x": 1.0}, {"id": "a", "x": 2.0}, {"id": "b", "x": 2.0}], "physical sort tie uses stable ID")
	index._records = point_sort.sorted
	for pair: Array in [[0.0, 0.0], [1.0, 1.0], [2.0, 0.0], [5.0, 0.0]]:
		index.probes = 0
		var expected: Array[String] = index.candidates(pair[0], pair[1])
		var native_probes: int = index.probes
		index.probes = 0
		var cursor: RefCounted = index.begin_candidates(pair[0], pair[1])
		while not cursor.step():
			pass
		check(cursor.result == expected and index.probes == native_probes, "range endpoints/order/probes match independent native reference")
	print("Task9 cursors: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
