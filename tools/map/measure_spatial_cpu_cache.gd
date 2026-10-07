extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var before := OS.get_static_memory_usage()
	var loader := LocalSpatialLoader.new()
	loader.request()
	while not loader.poll():
		await create_timer(.01).timeout
	var canonical := OS.get_static_memory_usage()
	var lods := LocalSpatialLod.prepare(loader.content.line_chunks)
	var caches := OS.get_static_memory_usage()
	var rows := {"debug_build":OS.is_debug_build(),"before_bytes":before,"canonical_bytes":canonical,"canonical_delta_bytes":canonical-before,"lod_cache_bytes":caches,"lod_delta_bytes":caches-canonical,"lod_stats":lods.lod_stats,"load":loader.content.metrics}
	var file := FileAccess.open("res://local-artifacts/map-resource-r2/cpu-cache.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  "))
	loader.dispose()
	quit(0)
