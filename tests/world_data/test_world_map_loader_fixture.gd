extends SceneTree
## Focused loader smoke test without relying on the global class cache.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loader_script: Script = load("res://scripts/world_map/internal/world_map_data_impl.gd") as Script
	if loader_script == null:
		_fail("world-map data loader script could not be loaded")
		_finish()
		return
	var loader: RefCounted = loader_script.new() as RefCounted
	if loader == null:
		_fail("world-map data loader could not be instantiated")
		_finish()
		return
	var loaded: bool = bool(loader.call("load_all"))
	if not loaded:
		_fail("world-map data loader reported a formal data load failure")
	var expected_keys: Array[String] = [
		"world_coastlines", "countries", "regions", "cities", "ports",
		"rail_segments", "road_segments", "shipping_routes", "characters",
		"name_pool_fr", "relationships", "organizations", "institutions",
		"activity", "map_modes", "map_geometry_cache",
	]
	for key: String in expected_keys:
		var document: Dictionary = loader.call("get_document", key) as Dictionary
		if document.is_empty():
			_fail("formal loader returned an empty document for %s" % key)
	_finish()


func _fail(message: String) -> void:
	failures += 1
	push_error(message)


func _finish() -> void:
	if failures == 0:
		print("World-map loader fixture smoke test: PASS")
	else:
		print("World-map loader fixture smoke test: FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
