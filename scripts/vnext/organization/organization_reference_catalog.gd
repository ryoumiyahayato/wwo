class_name VNextOrganizationReferenceCatalog
extends RefCounted

## Detached read view over Person/Place identities. OrganizationCore does not
## own either referenced domain and snapshots never serialize this catalog.

var _person_ids: Dictionary = {}
var _place_ids: Dictionary = {}


static func create(person_ids: Array[String], place_ids: Array[String]) -> VNextOrganizationReferenceCatalog:
	var catalog := VNextOrganizationReferenceCatalog.new()
	if not catalog._configure(person_ids, place_ids):
		return null
	return catalog


func person_ids() -> Array[String]:
	return _sorted_keys(_person_ids)


func place_ids() -> Array[String]:
	return _sorted_keys(_place_ids)


func has_person(person_id: String) -> bool:
	return _is_id_of_kind(person_id, "person") and _person_ids.has(person_id)


func has_place(place_id: String) -> bool:
	return _is_id_of_kind(place_id, "place") and _place_ids.has(place_id)


func fingerprint() -> String:
	return JSON.stringify({
		"person_ids": person_ids(),
		"place_ids": place_ids(),
	}).sha256_text()


func _configure(person_ids_value: Array[String], place_ids_value: Array[String]) -> bool:
	for person_id: String in person_ids_value:
		if not _is_id_of_kind(person_id, "person") or _person_ids.has(person_id):
			return false
		_person_ids[person_id] = true
	for place_id: String in place_ids_value:
		if not _is_id_of_kind(place_id, "place") or _place_ids.has(place_id):
			return false
		_place_ids[place_id] = true
	return true


static func _is_id_of_kind(candidate_id: String, expected_kind: String) -> bool:
	return VNextStableId.is_valid(candidate_id) and VNextStableId.kind_of(candidate_id) == expected_kind


static func _sorted_keys(source: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for raw_key: Variant in source.keys():
		if typeof(raw_key) == TYPE_STRING:
			output.append(str(raw_key))
	output.sort()
	return output
