class_name HistoricalAuthorityModel
extends RefCounted
## Typed, date-aware political authority relations for the formal 1900 world.
## Political-unit identity remains in the historical polity catalog; this model
## indexes authority edges without turning a presentation controller into legal
## sovereignty.

const RELATION_TYPES: Array[String] = [
	"sovereign",
	"suzerain",
	"protector",
	"administrator",
	"occupier",
	"de_facto_controller",
	"foreign_relations_controller",
	"condominium_party",
	"personal_sovereign",
	"claimant",
	# Compatibility-only edge. It preserves legacy controller_id information
	# when the legacy relationship is not specific enough to infer a role.
	"legacy_controller",
]

const PRESENTATION_CONTROLLER_PRIORITY: Array[String] = [
	"de_facto_controller",
	"occupier",
	"administrator",
	"protector",
	"suzerain",
	"foreign_relations_controller",
	"condominium_party",
	"personal_sovereign",
	"sovereign",
	"legacy_controller",
]

var initialization_error: String = ""

var _unit_ids: Dictionary = {}
var _relations_by_subject: Dictionary = {}
var _relation_by_id: Dictionary = {}
var _legacy_controller_by_subject: Dictionary = {}


func configure_from_path(path: String) -> bool:
	var document := _read_document(path)
	if document.is_empty():
		return false
	if not document.get("units", []) is Array:
		return _fail("authority source must contain a units array")
	return configure(document.get("units", []) as Array)


func configure(units: Array) -> bool:
	initialization_error = ""
	_unit_ids.clear()
	_relations_by_subject.clear()
	_relation_by_id.clear()
	_legacy_controller_by_subject.clear()

	for raw_unit: Variant in units:
		if not raw_unit is Dictionary:
			return _fail("political unit must be an object")
		var unit := raw_unit as Dictionary
		var entity_id := str(unit.get("id", "")).strip_edges()
		if entity_id.is_empty():
			return _fail("political unit is missing id")
		if _unit_ids.has(entity_id):
			return _fail("duplicate political unit id: %s" % entity_id)
		_unit_ids[entity_id] = true
		_relations_by_subject[entity_id] = []

	for raw_unit: Variant in units:
		var unit := raw_unit as Dictionary
		if not _configure_unit_relations(unit):
			return false

	for raw_subject: Variant in _relations_by_subject.keys():
		var subject_id := str(raw_subject)
		var relations := _relations_by_subject.get(subject_id, []) as Array
		relations.sort_custom(Callable(self, "_relation_less"))
		_relations_by_subject[subject_id] = relations
	return true


func get_authority_relations(subject_id: String) -> Array[Dictionary]:
	return _copy_relations(_relations_by_subject.get(subject_id, []) as Array)


func get_relations_by_type(subject_id: String, relationship_type: String) -> Array[Dictionary]:
	if relationship_type not in RELATION_TYPES:
		return []
	var result: Array[Dictionary] = []
	for raw_relation: Variant in (_relations_by_subject.get(subject_id, []) as Array):
		var relation := raw_relation as Dictionary
		if str(relation.get("relationship_type", "")) == relationship_type:
			result.append(relation.duplicate(true))
	return result


func get_sovereigns(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "sovereign")


func get_protectors(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "protector")


func get_administrators(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "administrator")


func get_occupiers(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "occupier")


func get_de_facto_controllers(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "de_facto_controller")


func get_foreign_relations_controllers(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "foreign_relations_controller")


func get_claimants(subject_id: String) -> Array[Dictionary]:
	return get_relations_by_type(subject_id, "claimant")


func get_active_relations(subject_id: String, date: String) -> Array[Dictionary]:
	if not _is_valid_date(date):
		return []
	var result: Array[Dictionary] = []
	for raw_relation: Variant in (_relations_by_subject.get(subject_id, []) as Array):
		var relation := raw_relation as Dictionary
		var valid_from := str(relation.get("valid_from", ""))
		var valid_to := str(relation.get("valid_to", ""))
		if date < valid_from:
			continue
		if not valid_to.is_empty() and date > valid_to:
			continue
		result.append(relation.duplicate(true))
	return result


func legacy_presentation_controller(subject_id: String) -> String:
	# Existing production records keep their exact visible controller_id. New
	# explicit records use a deterministic presentation-only role priority.
	if _legacy_controller_by_subject.has(subject_id):
		return str(_legacy_controller_by_subject.get(subject_id, ""))
	return _presentation_controller_from_relations(subject_id)


func first_sovereign_id(subject_id: String) -> String:
	var sovereigns := get_sovereigns(subject_id)
	if sovereigns.is_empty():
		return ""
	return str(sovereigns[0].get("authority_id", ""))


func has_subject(subject_id: String) -> bool:
	return _unit_ids.has(subject_id)


func relation_count() -> int:
	return _relation_by_id.size()


func _configure_unit_relations(unit: Dictionary) -> bool:
	var subject_id := str(unit.get("id", "")).strip_edges()
	var legacy_controller := str(unit.get("controller_id", "")).strip_edges()
	if not legacy_controller.is_empty():
		_legacy_controller_by_subject[subject_id] = legacy_controller

	if unit.has("authority_relations"):
		if not unit.get("authority_relations") is Array:
			return _fail("authority_relations must be an array for %s" % subject_id)
		for raw_relation: Variant in (unit.get("authority_relations") as Array):
			if not raw_relation is Dictionary:
				return _fail("authority relation must be an object for %s" % subject_id)
			if not _add_explicit_relation(subject_id, raw_relation as Dictionary):
				return false
		if not legacy_controller.is_empty():
			var resolved := _presentation_controller_from_relations(subject_id)
			if resolved != legacy_controller:
				return _fail(
					"mixed authority record conflicts with legacy controller_id for %s: %s != %s"
					% [subject_id, resolved, legacy_controller]
				)
		return true

	if legacy_controller.is_empty():
		return true
	if not _unit_ids.has(legacy_controller):
		return _fail(
			"legacy controller_id for %s references unknown actor: %s"
			% [subject_id, legacy_controller]
		)
	return _add_legacy_relation(unit, subject_id, legacy_controller)


func _add_explicit_relation(subject_id: String, raw_relation: Dictionary) -> bool:
	var relation_id := str(raw_relation.get("id", "")).strip_edges()
	var relation_subject := str(raw_relation.get("subject_id", subject_id)).strip_edges()
	var authority_id := str(raw_relation.get("authority_id", "")).strip_edges()
	var relationship_type := str(raw_relation.get("relationship_type", "")).strip_edges()
	var valid_from := str(raw_relation.get("valid_from", "")).strip_edges()
	var valid_to := str(raw_relation.get("valid_to", "")).strip_edges()

	if relation_id.is_empty():
		return _fail("authority relation for %s is missing id" % subject_id)
	if _relation_by_id.has(relation_id):
		return _fail("duplicate authority relation id: %s" % relation_id)
	if relation_subject != subject_id:
		return _fail(
			"authority relation %s subject %s does not match containing unit %s"
			% [relation_id, relation_subject, subject_id]
		)
	if not _unit_ids.has(relation_subject):
		return _fail("authority relation %s references unknown subject" % relation_id)
	if authority_id.is_empty() or not _unit_ids.has(authority_id):
		return _fail(
			"authority relation %s references unknown actor: %s"
			% [relation_id, authority_id]
		)
	if relationship_type not in RELATION_TYPES or relationship_type == "legacy_controller":
		return _fail(
			"authority relation %s has unknown or reserved type: %s"
			% [relation_id, relationship_type]
		)
	if not _is_valid_date(valid_from):
		return _fail("authority relation %s has invalid valid_from" % relation_id)
	if not valid_to.is_empty():
		if not _is_valid_date(valid_to):
			return _fail("authority relation %s has invalid valid_to" % relation_id)
		if valid_to < valid_from:
			return _fail("authority relation %s has inverted validity" % relation_id)

	var confidence_bp := raw_relation.get("confidence_bp", 10000)
	if typeof(confidence_bp) != TYPE_INT:
		return _fail("authority relation %s confidence_bp must be an integer" % relation_id)
	if int(confidence_bp) < 0 or int(confidence_bp) > 10000:
		return _fail("authority relation %s confidence_bp is out of range" % relation_id)
	var provenance_value := raw_relation.get("provenance", {})
	if not provenance_value is Dictionary:
		return _fail("authority relation %s provenance must be an object" % relation_id)
	var scope_value := raw_relation.get("scope", "")
	if typeof(scope_value) != TYPE_STRING:
		return _fail("authority relation %s scope must be a string" % relation_id)
	var uncertainty_value := raw_relation.get("uncertainty", "")
	if typeof(uncertainty_value) != TYPE_STRING:
		return _fail("authority relation %s uncertainty must be a string" % relation_id)

	var relation := {
		"id": relation_id,
		"subject_id": subject_id,
		"authority_id": authority_id,
		"relationship_type": relationship_type,
		"valid_from": valid_from,
		"valid_to": valid_to,
		"confidence_bp": int(confidence_bp),
		"uncertainty": str(uncertainty_value),
		"provenance": (provenance_value as Dictionary).duplicate(true),
		"scope": str(scope_value),
		"compatibility_generated": false,
	}
	return _insert_relation(relation)


func _add_legacy_relation(
	unit: Dictionary, subject_id: String, authority_id: String
) -> bool:
	var relationship := str(unit.get("relationship", "")).strip_edges()
	var relationship_type := _legacy_relationship_type(relationship)
	var valid_from := str(unit.get("valid_from", "")).strip_edges()
	var valid_to := str(unit.get("valid_to", "")).strip_edges()
	if not _is_valid_date(valid_from):
		return _fail("legacy authority for %s has invalid valid_from" % subject_id)
	if not valid_to.is_empty():
		if not _is_valid_date(valid_to):
			return _fail("legacy authority for %s has invalid valid_to" % subject_id)
		if valid_to < valid_from:
			return _fail("legacy authority for %s has inverted validity" % subject_id)
	var relation := {
		"id": "legacy:%s:%s" % [subject_id, authority_id],
		"subject_id": subject_id,
		"authority_id": authority_id,
		"relationship_type": relationship_type,
		"valid_from": valid_from,
		"valid_to": valid_to,
		"confidence_bp": 10000,
		"uncertainty": "legacy_role_not_inferred" if relationship_type == "legacy_controller" else "",
		"provenance": {
			"kind": "legacy_controller_adapter",
			"relationship": relationship,
		},
		"scope": "",
		"compatibility_generated": true,
	}
	return _insert_relation(relation)


func _legacy_relationship_type(relationship: String) -> String:
	match relationship:
		"military_occupation":
			return "occupier"
		"controlled_territory", "crown_colony", "administered_territory":
			return "administrator"
		"protectorate", "protected_state", "protected_territory":
			return "protector"
		"condominium":
			return "condominium_party"
		_:
			# Fail safe semantically: preserve the old controller without inventing
			# sovereignty, suzerainty, protection, or effective control.
			return "legacy_controller"


func _insert_relation(relation: Dictionary) -> bool:
	var relation_id := str(relation.get("id", ""))
	if _relation_by_id.has(relation_id):
		return _fail("duplicate authority relation id: %s" % relation_id)
	var subject_id := str(relation.get("subject_id", ""))
	var duplicate_key := _edge_duplicate_key(relation)
	for raw_existing: Variant in (_relations_by_subject.get(subject_id, []) as Array):
		var existing := raw_existing as Dictionary
		if _edge_duplicate_key(existing) == duplicate_key:
			return _fail("duplicate authority edge for %s" % subject_id)
	_relation_by_id[relation_id] = relation
	var relations := _relations_by_subject.get(subject_id, []) as Array
	relations.append(relation)
	_relations_by_subject[subject_id] = relations
	return true


func _presentation_controller_from_relations(subject_id: String) -> String:
	for relationship_type: String in PRESENTATION_CONTROLLER_PRIORITY:
		var matches := get_relations_by_type(subject_id, relationship_type)
		if not matches.is_empty():
			return str(matches[0].get("authority_id", ""))
	return ""


func _edge_duplicate_key(relation: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s" % [
		str(relation.get("subject_id", "")),
		str(relation.get("authority_id", "")),
		str(relation.get("relationship_type", "")),
		str(relation.get("valid_from", "")),
		str(relation.get("valid_to", "")),
		str(relation.get("scope", "")),
	]


func _relation_less(left: Dictionary, right: Dictionary) -> bool:
	var left_key := "%s|%s|%s|%s" % [
		str(left.get("relationship_type", "")),
		str(left.get("authority_id", "")),
		str(left.get("valid_from", "")),
		str(left.get("id", "")),
	]
	var right_key := "%s|%s|%s|%s" % [
		str(right.get("relationship_type", "")),
		str(right.get("authority_id", "")),
		str(right.get("valid_from", "")),
		str(right.get("id", "")),
	]
	return left_key < right_key


func _copy_relations(raw_relations: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_relation: Variant in raw_relations:
		if raw_relation is Dictionary:
			result.append((raw_relation as Dictionary).duplicate(true))
	return result


func _is_valid_date(value: String) -> bool:
	if value.length() != 10 or value[4] != "-" or value[7] != "-":
		return false
	var year_text := value.substr(0, 4)
	var month_text := value.substr(5, 2)
	var day_text := value.substr(8, 2)
	if not year_text.is_valid_int() or not month_text.is_valid_int() or not day_text.is_valid_int():
		return false
	var year := int(year_text)
	var month := int(month_text)
	var day := int(day_text)
	if year < 1 or month < 1 or month > 12 or day < 1:
		return false
	var days_in_month := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and _is_leap_year(year):
		return day <= 29
	return day <= int(days_in_month[month - 1])


func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail_document("authority source does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail_document("authority source could not be opened: %s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return _fail_document("authority source is malformed JSON: %s" % path)
	return parser.data as Dictionary


func _fail_document(message: String) -> Dictionary:
	initialization_error = message
	return {}


func _fail(message: String) -> bool:
	initialization_error = message
	return false
