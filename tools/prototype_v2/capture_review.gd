extends SceneTree
## Instantiates the isolated prototype scene for deterministic non-headless review captures.


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/prototype_v2/prototype_v2_main.tscn") as PackedScene
	if packed == null:
		push_error("Unable to load prototype capture scene")
		quit(1)
		return
	var view: PrototypeV2Main = packed.instantiate() as PrototypeV2Main
	root.add_child(view)
	current_scene = view
	# PrototypeV2Main owns the requested review state, PNG write, and exit code.
	while true:
		await process_frame
