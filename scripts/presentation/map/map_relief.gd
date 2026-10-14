class_name MapRelief
extends RefCounted
## Two bounded Presentation textures; the source DEM is never a runtime resource.
const PREWARM_MPP: float = 8500.0
const RELEASE_MPP: float = 11000.0
var textures: Dictionary = {}
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
	if not result.errors.is_empty():
		return false
	if _level not in _wanted:
		_attempted.erase(_level)
		return false
	var texture := ImageTexture.create_from_image(result.image as Image)
	textures[_level] = texture
	return true

func dispose() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	textures.clear()

