extends SceneTree
## Fresh-process deterministic Market identity snapshot probe.


func _initialize() -> void:
	var simulation := FormalWorldSimulation.new()
	if not simulation.initialize():
		push_error(simulation.initialization_error)
		quit(1)
		return
	var market_view := simulation.market_registry_view()
	var canonical := {
		"revision": market_view.revision(),
		"mapping_fingerprint": market_view.mapping_fingerprint(),
		"markets": market_view.markets(),
	}
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		quit(1)
		return
	hashing.update(JSON.stringify(canonical).to_utf8_buffer())
	print("FORMAL_MARKET_SNAPSHOT_SHA256=%s" % hashing.finish().hex_encode())
	quit(0)
