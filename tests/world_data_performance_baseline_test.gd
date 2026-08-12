extends SceneTree
## Lightweight contract test for the standalone world-data benchmark.

const Benchmark = preload("res://tools/world_data_performance_baseline.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_result_schema_contract()
	_test_runtime_world_data()
	_test_geometry_and_spatial_query()
	print("World data performance baseline harness: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_result_schema_contract() -> void:
	var errors: Array[String] = Benchmark.validate_result_schema(Benchmark.schema_probe())
	_check(errors.is_empty(), "benchmark result schema probe is valid: %s" % [errors])
	var limitations: Array = Benchmark.schema_probe().get("limitations", []) as Array
	_check(limitations.has(Benchmark.BENCHMARK_SEMANTICS), "benchmark schema identifies machine-specific, non-universal timing semantics")
	var invalid_probe: Dictionary = Benchmark.schema_probe().duplicate(true)
	(invalid_probe["limitations"] as Array).clear()
	_check(not Benchmark.validate_result_schema(invalid_probe).is_empty(), "benchmark result schema rejects missing timing semantics")


func _test_runtime_world_data() -> void:
	var data := PrototypeV2Data.new()
	_check(data.load_all(), "PrototypeV2Data loads all runtime world-map documents")
	_check(data.records.size() == 16, "runtime loader has the fixed 16-document workload")
	var countries: Array = data.get_document("countries").get("countries", []) as Array
	var regions: Array = data.get_document("regions").get("regions", []) as Array
	var cities: Array = data.get_document("cities").get("cities", []) as Array
	_check(countries.size() > 0, "country dataset has records")
	_check(regions.size() > 0, "region dataset has records")
	_check(cities.size() > 0, "city dataset has records")


func _test_geometry_and_spatial_query() -> void:
	var geometry: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/world_map/map_geometry_cache.json"
	))
	_check(geometry is Dictionary, "geometry cache parses as a dictionary")
	var spatial := PrototypeV2SpatialIndex.new()
	spatial.configure(Rect2(Vector2.ZERO, Vector2(100.0, 100.0)), 10.0, 2)
	spatial.insert(0, Rect2(10.0, 10.0, 20.0, 20.0))
	spatial.insert(1, Rect2(70.0, 70.0, 20.0, 20.0))
	var output: Array[int] = []
	spatial.query_point(Vector2(15.0, 15.0), output)
	_check(output.has(0), "uniform-grid point query returns the matching record")
	_check(not output.has(1), "uniform-grid point query excludes a distant record")
	var data := PrototypeV2Data.new()
	if not data.load_all():
		return
	var canvas := PrototypeV2MapCanvas.new()
	canvas.setup(data)
	_check(not canvas.get_country("country_fra").is_empty(), "map ID index resolves France")
	_check(not canvas.get_city("lille").is_empty(), "map ID index resolves Lille")
	_check(canvas.debug_architecture_state().get("spatial_index", "") == "uniform_grid", "map reports uniform-grid spatial indexing")
	canvas.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
		return
	_failures += 1
	push_error("FAIL: " + message)
