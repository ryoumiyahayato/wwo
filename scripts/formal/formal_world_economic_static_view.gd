class_name FormalWorldEconomicStaticView
extends RefCounted
## Immutable static economic evidence snapshot. No runtime state is stored here.

var _revision: String = ""
var _fingerprint: String = ""
var _countries: Array[Dictionary] = []
var _country_by_id: Dictionary = {}
var _formal_verified_countries: Array[Dictionary] = []
var _commodities: Array[Dictionary] = []
var _crosswalk_records: Array[Dictionary] = []
var _maritime_corridors: Array[Dictionary] = []
var _river_corridors: Array[Dictionary] = []
var _provenance: Dictionary = {}


func _init(snapshot: Dictionary = {}) -> void:
	_revision = str(snapshot.get("revision", ""))
	_fingerprint = str(snapshot.get("fingerprint", ""))
	_countries = DataRecordUtils.to_dictionary_array(snapshot.get("countries", []))
	for record: Dictionary in _countries:
		var entity_id := str(record.get("entity_id", ""))
		if not entity_id.is_empty():
			_country_by_id[entity_id] = record.duplicate(true)
	_formal_verified_countries = DataRecordUtils.to_dictionary_array(
		snapshot.get("formal_verified_countries", [])
	)
	_commodities = DataRecordUtils.to_dictionary_array(snapshot.get("commodities", []))
	_crosswalk_records = DataRecordUtils.to_dictionary_array(
		snapshot.get("crosswalk_records", [])
	)
	_maritime_corridors = DataRecordUtils.to_dictionary_array(
		snapshot.get("maritime_corridors", [])
	)
	_river_corridors = DataRecordUtils.to_dictionary_array(
		snapshot.get("river_corridors", [])
	)
	_provenance = (snapshot.get("provenance", {}) as Dictionary).duplicate(true)


func is_configured() -> bool:
	return not _revision.is_empty() and not _fingerprint.is_empty()


func revision() -> String:
	return _revision


func fingerprint() -> String:
	return _fingerprint


func countries() -> Array[Dictionary]:
	return _countries.duplicate(true)


func country(entity_id: String) -> Dictionary:
	return (_country_by_id.get(entity_id, {}) as Dictionary).duplicate(true)


func formal_verified_countries() -> Array[Dictionary]:
	return _formal_verified_countries.duplicate(true)


func commodities() -> Array[Dictionary]:
	return _commodities.duplicate(true)


func crosswalk_records() -> Array[Dictionary]:
	return _crosswalk_records.duplicate(true)


func maritime_corridors() -> Array[Dictionary]:
	return _maritime_corridors.duplicate(true)


func river_corridors() -> Array[Dictionary]:
	return _river_corridors.duplicate(true)


func provenance() -> Dictionary:
	return _provenance.duplicate(true)
