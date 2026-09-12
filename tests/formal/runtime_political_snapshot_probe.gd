extends SceneTree
## A validation probe run in separate Godot processes. The validation wrapper
## compares the emitted hashes to enforce fresh-process political determinism.

const HASH_MARKER: String = "RUNTIME_POLITICAL_SNAPSHOT_SHA256="


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	if not simulation.initialize():
		push_error(
			"Runtime political snapshot probe initialization failed: %s" % (
				simulation.initialization_error
			)
		)
		quit(1)
		return
	var snapshot := simulation.get_persistent_state().get(
		"runtime_politics", {}
	) as Dictionary
	var hashing := HashingContext.new()
	if (
		hashing.start(HashingContext.HASH_SHA256) != OK
		or hashing.update(JSON.stringify(snapshot).to_utf8_buffer()) != OK
	):
		push_error("Runtime political snapshot probe could not hash snapshot")
		quit(1)
		return
	print(HASH_MARKER + hashing.finish().hex_encode())
	quit(0)
