extends RefCounted
## Explicit end-of-run research export. Never called by a person read.
static func collect(session: RefCounted) -> Dictionary:
	var world: RefCounted = session.world
	var result: Dictionary = {"view": "DEBUG_TRUTH", "pending": world.env.state.public_pending(), "instance_id": world.get_instance_id(),
		"selected_script_disabled": world.selected_script_disabled, "reader_work": session.reader.work.duplicate(), "calls": session.calls,
		"persistent_host": {"receipt_ids": session.receipts.size(), "timeline": session.reader.timeline.size(), "timeline_dropped": session.reader.dropped,
			"pending_inputs": session.unresolved.size(), "cached_view_bytes": JSON.stringify(session.cache).to_utf8_buffer().size(),
			"receipt_bytes": JSON.stringify(session.receipts).to_utf8_buffer().size(), "timeline_bytes": JSON.stringify(session.reader.timeline).to_utf8_buffer().size()}}
	if not world.env.state.public_pending():
		result.formal = world.physical()
		for key: String in ["world_counters", "gameplay_work", "personal_work"]:
			result.formal.erase(key)
		result.formal.random_state = world.env.state.random_state.duplicate(true)
		result.formal.structure = world.env.structure._nodes.duplicate(true)
		result.formal.relationships = world.env.structure.history.duplicate(true)
		result.ledger_balanced = world.balanced()
		result.materializations = world.env.lod.work.leaf_records_materialized
	return result

static func save(session: RefCounted, folder: String) -> void:
	var started: int = Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var result: Dictionary = collect(session)
	result.export_usec_before_file = Time.get_ticks_usec() - started
	var file: FileAccess = FileAccess.open(folder.path_join("debug_truth.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result) + "\n")
	session.costs.export_usec = Time.get_ticks_usec() - started
