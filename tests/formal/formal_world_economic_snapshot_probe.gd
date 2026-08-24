extends SceneTree
## Fresh-process deterministic authoritative economic snapshot probe.


func _initialize() -> void:
	var simulation := FormalWorldSimulation.new()
	if not simulation.initialize():
		push_error(simulation.initialization_error)
		quit(1)
		return
	simulation.advance_minutes(30 * 24 * 60)
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		quit(1)
		return
	hashing.update(JSON.stringify(simulation.get_persistent_state()).to_utf8_buffer())
	print("FORMAL_ECONOMIC_SNAPSHOT_SHA256=%s" % hashing.finish().hex_encode())
	quit(0)
