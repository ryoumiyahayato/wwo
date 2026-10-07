extends SceneTree


func _initialize() -> void:
	var world := WorldBootstrap.new().build()
	if not world.success:
		push_error("Formal world fingerprint probe initialization failed: %s" % world.error)
		quit(1)
		return
	var fingerprint := world.persistence.authoritative_fingerprint()
	if fingerprint.length() != 64:
		push_error("Formal world fingerprint probe did not produce SHA-256")
		quit(1)
		return
	print("FORMAL_WORLD_FINGERPRINT_SHA256=" + fingerprint)
	quit(0)
