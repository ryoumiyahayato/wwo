class_name MapRelief
extends RefCounted
## Two bounded Presentation textures; the source DEM is never a runtime resource.
const PREWARM_MPP: float = 8500.0
const RELEASE_MPP: float = 11000.0
var textures: Dictionary = {}
var metrics: Dictionary = {"loads": {}, "load_counts": {}, "source_resolutions": 0, "resident_bytes": 0}
var errors: Array[String] = []
var decode_asset: Callable
var _assets: Dictionary = {}
var _wanted: Array[String] = []
var _attempted: Dictionary = {}
var _thread: Thread
var _level: String = ""

func request(visible: bool, mpp: float) -> bool:
	_wanted.assign(["world"] if visible else [])
	if visible and (mpp <= PREWARM_MPP or (textures.has("region") and mpp < RELEASE_MPP)):
		_wanted.append("region")
	var changed := false
	for level: String in textures.keys():
		if level not in _wanted:
			textures.erase(level)
			_attempted.erase(level)
			changed = true
	_update_resident()
	if _thread == null and decode_asset.is_valid():
		for level: String in _wanted:
			if not textures.has(level) and not _attempted.has(level):
				_level = level
				_attempted[level] = true
				_thread = Thread.new()
				_thread.start(decode_asset.bind(level, _assets.duplicate(true)))
				break
	return changed

func preparing() -> bool:
	return _thread != null

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var result := _thread.wait_to_finish() as Dictionary
	_thread = null
	errors.append_array(result.errors as Array[String])
	if result.has("assets"):
		_assets = result.assets as Dictionary
		metrics["source_resolutions"] = int(metrics.source_resolutions) + 1
	if not result.errors.is_empty():
		return false
	if _level not in _wanted:
		_attempted.erase(_level)
		return false
	var started := Time.get_ticks_usec()
	var texture := ImageTexture.create_from_image(result.image as Image)
	textures[_level] = texture
	var sample := result.metrics as Dictionary
	sample["texture_create_gpu_enqueue_usec"] = Time.get_ticks_usec() - started
	sample["ready_usec"] = Time.get_ticks_usec()
	sample["first_visible_usec"] = 0
	var loads := metrics.loads as Dictionary
	if not loads.has(_level): loads[_level] = []
	(loads[_level] as Array).append(sample)
	if (loads[_level] as Array).size() > 4: (loads[_level] as Array).pop_front()
	var counts := metrics.load_counts as Dictionary
	counts[_level] = int(counts.get(_level, 0)) + 1
	_update_resident()
	return true

func needs_presented(detail_used: bool) -> bool:
	for level: String in textures:
		if level == "region" and not detail_used: continue
		var samples := (metrics.loads as Dictionary).get(level, []) as Array
		if not samples.is_empty() and int((samples[-1] as Dictionary).first_visible_usec) == 0: return true
	return false

func mark_presented(detail_used: bool) -> void:
	for level: String in textures:
		if level == "region" and not detail_used: continue
		var samples := (metrics.loads as Dictionary).get(level, []) as Array
		if not samples.is_empty():
			var sample := samples[-1] as Dictionary
			if int(sample.first_visible_usec) == 0:
				sample["first_visible_usec"] = Time.get_ticks_usec() - int(sample.started_usec)

func _update_resident() -> void:
	var bytes: int = 0
	for texture: Texture2D in textures.values():
		bytes += 2 * texture.get_width() * texture.get_height()
	metrics["resident_bytes"] = bytes
	metrics["resident_levels"] = textures.keys()

func dispose() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	textures.clear()
	_update_resident()

