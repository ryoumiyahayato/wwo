class_name EvidenceLoader
extends RefCounted

const FLAGS_PATH: String = "res://data/world_map/historical/flags_1900.json"
const UNITS_PATH: String = "res://data/world_map/historical/political_units_1900.json"
const FLAG_VISUALS_PATH: String = "res://data/presentation/flag_visuals.json"
var errors: Array[String] = []
var flag_records: Dictionary = {}
var visual_resolver := HistoricalVisualResolver.new()

func load_current() -> bool:
	var document := ContentDocument.read(FLAGS_PATH, errors)
	flag_records = document.get("records", {}) as Dictionary
	var visuals := ContentDocument.read(FLAG_VISUALS_PATH, errors)
	var defaults := visuals.get("defaults", {}) as Dictionary
	var flags := visuals.get("flags", {}) as Dictionary
	for flag_id: String in flag_records:
		var override := flags.get(flag_id, {}) as Dictionary
		var style := defaults.duplicate()
		style.merge(override, true)
		(flag_records[flag_id] as Dictionary)["map_visual"] = style
	visual_resolver.configure(flag_records)
	errors.append_array(visual_resolver.errors)
	return errors.is_empty()

func flag_record(flag_id: String) -> Dictionary:
	return flag_records.get(flag_id, {}) as Dictionary
