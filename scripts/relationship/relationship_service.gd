class_name RelationshipService
extends RefCounted
## Sparse relationship store: only contacted pairs receive a record.

var roster: CharacterRosterService
var defaults: Dictionary
var id_service: StableIdService
var relationships: Dictionary = {}
var _id_by_pair: Dictionary = {}


func _init(
	character_roster: CharacterRosterService,
	relationship_defaults: Dictionary,
	stable_id_service: StableIdService
) -> void:
	roster = character_roster
	defaults = relationship_defaults.duplicate(true)
	id_service = stable_id_service


func create_or_update(
	character_a_id: String,
	character_b_id: String,
	current_hour: int,
	deltas: Dictionary = {},
	interest_link: String = "contact"
) -> RelationshipData:
	if character_a_id == character_b_id or current_hour < 0 or not roster.has_character(character_a_id) or not roster.has_character(character_b_id):
		return null
	var pair_key: String = _pair_key(character_a_id, character_b_id)
	var relationship: RelationshipData
	if _id_by_pair.has(pair_key):
		relationship = relationships[str(_id_by_pair[pair_key])] as RelationshipData
	else:
		relationship = RelationshipData.new()
		relationship.id = id_service.next_id("relationship")
		var ids: Array[String] = [character_a_id, character_b_id]
		ids.sort()
		relationship.character_a_id = ids[0]
		relationship.character_b_id = ids[1]
		relationship.familiarity = float(defaults.get("familiarity", 0.0))
		relationship.trust = float(defaults.get("trust", 0.0))
		relationship.affinity = float(defaults.get("affinity", 0.0))
		relationship.is_public = bool(defaults.get("is_public", true))
		relationship.interest_link = interest_link
		relationship.last_interaction_hour = current_hour
		relationships[relationship.id] = relationship
		_id_by_pair[pair_key] = relationship.id
		_attach_relationship_id(character_a_id, relationship.id)
		_attach_relationship_id(character_b_id, relationship.id)
	relationship.familiarity = clampf(relationship.familiarity + float(deltas.get("familiarity", 0.0)), 0.0, 1.0)
	relationship.trust = clampf(relationship.trust + float(deltas.get("trust", 0.0)), -1.0, 1.0)
	relationship.affinity = clampf(relationship.affinity + float(deltas.get("affinity", 0.0)), -1.0, 1.0)
	if deltas.has("is_public"):
		relationship.is_public = bool(deltas["is_public"])
	if not interest_link.is_empty():
		relationship.interest_link = interest_link
	relationship.last_interaction_hour = current_hour
	return relationship


func get_between(character_a_id: String, character_b_id: String) -> RelationshipData:
	var relationship_id: String = str(_id_by_pair.get(_pair_key(character_a_id, character_b_id), ""))
	return relationships.get(relationship_id) as RelationshipData


func get_for_character(character_id: String) -> Array[RelationshipData]:
	var output: Array[RelationshipData] = []
	for raw_relationship: Variant in relationships.values():
		var relationship: RelationshipData = raw_relationship as RelationshipData
		if relationship.character_a_id == character_id or relationship.character_b_id == character_id:
			output.append(relationship)
	output.sort_custom(func(a: RelationshipData, b: RelationshipData) -> bool: return a.id < b.id)
	return output


func size() -> int:
	return relationships.size()


func get_persistent_state() -> Dictionary:
	var output: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id: Variant in relationships:
		ids.append(str(raw_id))
	ids.sort()
	for relationship_id: String in ids:
		output.append((relationships[relationship_id] as RelationshipData).to_dict())
	return {"records": output, "id_state": id_service.get_state()}


func restore_persistent_state(state: Dictionary) -> bool:
	var raw_records: Variant = state.get("records", [])
	var raw_id_state: Variant = state.get("id_state", {})
	if not raw_records is Array or not raw_id_state is Dictionary:
		return false
	var restored: Dictionary = {}
	var pairs: Dictionary = {}
	var maximum_id_value: int = 0
	for raw_record: Variant in raw_records:
		if not raw_record is Dictionary:
			return false
		var relationship := RelationshipData.from_dict(raw_record as Dictionary)
		var id_value: int = _generated_relationship_id_value(relationship.id)
		var pair: String = _pair_key(relationship.character_a_id, relationship.character_b_id)
		if id_value < 1 or relationship.character_a_id == relationship.character_b_id or not roster.has_character(relationship.character_a_id) or not roster.has_character(relationship.character_b_id) or relationship.familiarity < 0.0 or relationship.familiarity > 1.0 or relationship.trust < -1.0 or relationship.trust > 1.0 or relationship.affinity < -1.0 or relationship.affinity > 1.0 or relationship.last_interaction_hour < 0 or restored.has(relationship.id) or pairs.has(pair):
			return false
		maximum_id_value = maxi(maximum_id_value, id_value)
		restored[relationship.id] = relationship
		pairs[pair] = relationship.id
	var restored_ids := StableIdService.new()
	if not restored_ids.restore_state(raw_id_state as Dictionary):
		return false
	if int((raw_id_state as Dictionary).get("relationship", 0)) < maximum_id_value:
		return false
	relationships = restored
	_id_by_pair = pairs
	id_service = restored_ids
	return true


func _attach_relationship_id(character_id: String, relationship_id: String) -> void:
	var active: CharacterData = roster.get_active(character_id)
	if active != null and not active.relationship_ids.has(relationship_id):
		active.relationship_ids.append(relationship_id)
		return
	var background: BackgroundCharacterData = roster.get_background(character_id)
	if background != null and not background.relationship_ids.has(relationship_id):
		background.relationship_ids.append(relationship_id)


static func _generated_relationship_id_value(value: String) -> int:
	if not StableIdService.is_valid_id(value) or StableIdService.get_namespace(value) != "relationship":
		return -1
	var slug: String = value.get_slice(":", 1)
	return int(slug) if slug.is_valid_int() else -1


static func _pair_key(character_a_id: String, character_b_id: String) -> String:
	var ids: Array[String] = [character_a_id, character_b_id]
	ids.sort()
	return "%s|%s" % ids
