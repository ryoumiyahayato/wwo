class_name ResolvedMapContent
extends RefCounted
## One dated display resolution, with copied identities and preserved evidence.

var _date: String
var _units: Array[Dictionary] = []
var _document: Dictionary = {}
var _visuals: Dictionary = {}
var _textures: Dictionary = {}

func _init(date: String = "", units: Array[Dictionary] = [], document: Dictionary = {}, visuals: Dictionary = {}, textures: Dictionary = {}) -> void:
	_date = date
	_units.assign(units.duplicate(true))
	_document = document.duplicate(true)
	_visuals = visuals.duplicate(true)
	_textures = textures.duplicate()

func date() -> String:
	return _date

func units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_units.duplicate(true))
	return result

func display_document() -> Dictionary:
	return _document.duplicate(true)

func visual(owner: String) -> Dictionary:
	return (_visuals.get(owner, {}) as Dictionary).duplicate(true)

func texture(owner: String) -> Texture2D:
	return _textures.get(owner) as Texture2D
