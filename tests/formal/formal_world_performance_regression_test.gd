extends SceneTree
## Structural guards for measured formal-world rendering hot paths.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(packed != null, "formal world performance scene loads")
	if packed == null:
		_finish()
		return
	var view := packed.instantiate() as FormalWorldApplication
	_check(view != null, "formal world performance scene instantiates")
	if view == null:
		_finish()
		return
	root.add_child(view)
	await process_frame
	await process_frame
	_check(view.formal_simulation.initialized, "formal world initializes for performance guards")

	var shared_flag_pair := _find_shared_flag_pair(view)
	_check(shared_flag_pair.size() == 2, "historical catalog contains a shared flag identity")
	if shared_flag_pair.size() == 2:
		view.debug_reset_performance_metrics()
		var first := view.call(
			"_flag_texture_for_entity", shared_flag_pair[0], {}
		) as Texture2D
		var second := view.call(
			"_flag_texture_for_entity", shared_flag_pair[1], {}
		) as Texture2D
		var shared_snapshot := view.debug_performance_snapshot()
		_check(first != null and second != null, "shared historical flag texture resolves")
		_check(first == second, "entities with one flag id reuse one texture instance")
		_check(
			int(shared_snapshot.get("flag_resource_load_count", 0)) <= 1,
			"one flag id causes at most one imported resource load"
		)

	view.debug_reset_performance_metrics()
	view._toggle_formal_economy_panel()
	await process_frame
	await process_frame
	var hud_snapshot := view.debug_performance_snapshot()
	_check(
		int(hud_snapshot.get("projection_rebuild_count", -1)) == 0,
		"HUD-only changes do not rebuild map projection"
	)

	view.debug_reset_performance_metrics()
	view.call("_on_flag_timer_timeout")
	await process_frame
	await process_frame
	var animation_snapshot := view.debug_performance_snapshot()
	_check(
		int(animation_snapshot.get("projection_rebuild_count", -1)) == 0,
		"flag animation redraw does not rebuild map projection"
	)
	_check(
		int(animation_snapshot.get("flag_cache_rebuild_count", -1)) == 0,
		"flag animation redraw does not rebuild clipped flag geometry"
	)

	var source := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"
	)
	_check(
		not source.contains("Image.load_from_file"),
		"formal flag rendering never bypasses Godot resource imports"
	)
	view.queue_free()
	await process_frame
	_finish()


func _find_shared_flag_pair(view: FormalWorldApplication) -> Array[String]:
	var first_entity_by_flag: Dictionary = {}
	var countries := view.get("_country_by_id") as Dictionary
	for raw_entity_id: Variant in countries:
		var entity_id := str(raw_entity_id)
		var record := countries[raw_entity_id] as Dictionary
		var flag_id := str(record.get("flag_id", ""))
		if flag_id.is_empty():
			continue
		if first_entity_by_flag.has(flag_id):
			return [str(first_entity_by_flag[flag_id]), entity_id]
		first_entity_by_flag[flag_id] = entity_id
	return []


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("Formal world performance regression: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
