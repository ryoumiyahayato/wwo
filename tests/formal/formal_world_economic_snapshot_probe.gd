extends SceneTree
## Fresh-process deterministic authoritative economic snapshot probe.


func _initialize() -> void:
	var simulation := WorldBootstrap.new().build()
	if not simulation.success:
		push_error(simulation.error)
		quit(1)
		return
	simulation.simulation_step.advance_minutes(30 * 24 * 60)
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		quit(1)
		return
	hashing.update(JSON.stringify(simulation.persistence.snapshot()).to_utf8_buffer())
	print("FORMAL_ECONOMIC_SNAPSHOT_SHA256=%s" % hashing.finish().hex_encode())
	quit(0)
