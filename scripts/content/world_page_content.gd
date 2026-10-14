class_name WorldPageContent
extends RefCounted
## Detached selected polity/settlement display evidence and dated flag.

var _date: String
var _profile: Dictionary
var _administration: Dictionary
var _flag: Dictionary
var _texture: Texture2D
var _place: Dictionary

func _init(date: String = "", profile: Dictionary = {}, administration: Dictionary = {}, flag: Dictionary = {}, texture: Texture2D = null, place: Dictionary = {}) -> void:
	_date = date
	_profile = profile.duplicate(true)
	_administration = administration.duplicate(true)
	_flag = flag.duplicate(true)
	_texture = texture
	_place = place.duplicate(true)

func place() -> Dictionary:
	return _place.duplicate(true)

func date() -> String:
	return _date

func profile() -> Dictionary:
	return _profile.duplicate(true)

func administration() -> Dictionary:
	return _administration.duplicate(true)

func flag() -> Dictionary:
	return _flag.duplicate(true)

func texture() -> Texture2D:
	return _texture
