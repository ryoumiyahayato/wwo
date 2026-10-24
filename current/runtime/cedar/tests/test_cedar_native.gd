extends SceneTree
## SUPPLIED, NOT EXECUTED in the assistant environment. Requires Godot 4.6.3.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func require(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)
func _run() -> void:
	var field = load("res://cedar/heightfield.gd").new()
	require(field.valid, "heightfield valid")
	if not field.valid:
		quit(1)
		return
	require(is_finite(field.sample(0.0, 0.0)), "origin finite")
	require(field.normal_at(0,0).length() > 0.99, "normal finite unit")
	var terrain = load("res://cedar/terrain.gd").new()
	root.add_child(terrain)
	var result: Dictionary = terrain.configure(Vector3.ZERO, null)
	require(bool(result.get("ok", false)), "terrain configured")
	require(terrain.source_id == "cedar_valley_20261019_v1", "separate terrain save source")
	require(terrain.chunks.size() >= 9, "initial collision chunks")
	for point in [Vector3.ZERO, Vector3(-6,0,-7), Vector3(-180,0,112), Vector3(2500,0,2500)]:
		require(is_finite(terrain.sample_height(point.x, point.z)), "finite terrain sample " + str(point))
	var scenery = load("res://cedar/world.gd").new()
	root.add_child(scenery)
	scenery.build(terrain)
	var state: Dictionary = scenery.snapshot()
	require(state.placements == 370, "manifest placement count")
	require(state.static_obstacles == 370, "static collider count")
	require(state.actors_created == 0, "no combat actors from scenery")
	for item in scenery.manifest.asset_statistics:
		require(ResourceLoader.exists("res://cedar/assets/" + str(item.mesh) + ".glb"), "asset exists " + str(item.mesh))
	print(JSON.stringify({"test":"cedar_native_resource_smoke", "ok":failures.is_empty(), "failures":failures, "note":"Does not validate full gameplay, rendering or Android."}))
	quit(0 if failures.is_empty() else 1)
