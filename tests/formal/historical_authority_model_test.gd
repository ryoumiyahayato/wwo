extends SceneTree

const POLITICAL_UNITS_PATH := "res://data/world_map/historical/political_units_1900.json"
const SNAPSHOT_DATE := "1900-03-12"

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_synthetic_fixtures_a_to_i()
	_check_invalid_fixture_j()
	_check_production_regression()
	_check_save_restore_reconstruction()
	print("Historical authority model: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_synthetic_fixtures_a_to_i() -> void:
	var units: Array = [
		_actor("actor_a"),
		_actor("actor_b"),
		_actor("actor_c"),
		_explicit_unit("simple_state", [
			_relation("a-sovereign", "simple_state", "simple_state", "sovereign"),
		]),
		_explicit_unit("bosnia_like", [
			_relation("b-sovereign", "bosnia_like", "actor_a", "sovereign"),
			_relation("b-administrator", "bosnia_like", "actor_b", "administrator"),
		]),
		_explicit_unit("egypt_like", [
			_relation("c-sovereign", "egypt_like", "actor_a", "sovereign"),
			_relation("c-occupier", "egypt_like", "actor_b", "occupier"),
			_relation("c-de-facto", "egypt_like", "actor_b", "de_facto_controller"),
		]),
		_explicit_unit("sudan_like", [
			_relation("d-condominium-a", "sudan_like", "actor_a", "condominium_party"),
			_relation("d-condominium-b", "sudan_like", "actor_b", "condominium_party"),
		]),
		_explicit_unit("afghanistan_like", [
			_relation("e-foreign", "afghanistan_like", "actor_b", "foreign_relations_controller"),
		]),
		_explicit_unit("bsac_like", [
			_relation("f-protector", "bsac_like", "actor_a", "protector"),
			_relation("f-administrator", "bsac_like", "actor_b", "administrator"),
		]),
		_explicit_unit("philippines_like", [
			_relation("g-claim", "philippines_like", "actor_a", "claimant"),
			_relation("g-de-facto", "philippines_like", "actor_b", "de_facto_controller"),
		], "contested"),
		_explicit_unit("chaco_like", [
			_relation("h-claim-a", "chaco_like", "actor_a", "claimant"),
			_relation("h-claim-b", "chaco_like", "actor_b", "claimant"),
		], "unresolved"),
		{
			"id": "legacy_record",
			"valid_from": "1890-01-01",
			"valid_to": "1910-12-31",
			"status": "dependency",
			"relationship": "controlled_territory",
			"controller_id": "actor_b",
		},
	]
	var model := HistoricalAuthorityModel.new()
	_check(model.configure(units), "A-I fixtures configure: %s" % model.initialization_error)
	if not model.initialization_error.is_empty():
		return

	# A — simple sovereign.
	_check(model.get_sovereigns("simple_state").size() == 1, "A simple state has one sovereign edge")
	_check(model.first_sovereign_id("simple_state") == "simple_state", "A local polity identity survives self-sovereignty")

	# B — legal sovereign and administrator coexist.
	_check(model.get_sovereigns("bosnia_like").size() == 1, "B Bosnia-like sovereign survives")
	_check(model.get_administrators("bosnia_like").size() == 1, "B Bosnia-like administrator survives")
	_check(
		str(model.get_sovereigns("bosnia_like")[0].get("authority_id", ""))
		!= str(model.get_administrators("bosnia_like")[0].get("authority_id", "")),
		"B sovereign and administrator are structurally independent"
	)

	# C — sovereignty and effective control are different facts.
	_check(model.get_sovereigns("egypt_like").size() == 1, "C Egypt-like legal sovereign exists")
	_check(model.get_occupiers("egypt_like").size() == 1, "C Egypt-like occupier exists")
	_check(model.get_de_facto_controllers("egypt_like").size() == 1, "C Egypt-like de-facto controller exists")
	_check(
		model.first_sovereign_id("egypt_like") == "actor_a"
		and model.legacy_presentation_controller("egypt_like") == "actor_b",
		"C sovereign and presentation/effective controller can differ"
	)

	# D — condominium is explicitly multi-party.
	_check(model.get_relations_by_type("sudan_like", "condominium_party").size() == 2, "D Sudan-like two condominium parties coexist")

	# E — foreign-relations control does not synthesize sovereignty.
	_check(model.get_foreign_relations_controllers("afghanistan_like").size() == 1, "E Afghanistan-like foreign-relations controller exists")
	_check(model.get_sovereigns("afghanistan_like").is_empty(), "E foreign-relations controller is not sovereign")

	# F — protector and administrator remain separate.
	_check(model.get_protectors("bsac_like").size() == 1, "F BSAC-like protector exists")
	_check(model.get_administrators("bsac_like").size() == 1, "F BSAC-like administrator exists")
	_check(model.get_sovereigns("bsac_like").is_empty(), "F protector does not become sovereign")

	# G — claim and de-facto control coexist without conflation.
	_check(model.get_claimants("philippines_like").size() == 1, "G Philippines-like claimant exists")
	_check(model.get_de_facto_controllers("philippines_like").size() == 1, "G Philippines-like de-facto controller exists")
	_check(model.legacy_presentation_controller("philippines_like") == "actor_b", "G claim does not displace de-facto presentation control")

	# H — unresolved territory may have multiple claimants and no sovereign.
	_check(model.get_claimants("chaco_like").size() == 2, "H Chaco-like multiple claimants coexist")
	_check(model.get_sovereigns("chaco_like").is_empty(), "H unresolved territory has no mandatory sovereign")

	# I — controller_id-only compatibility is deterministic and conservative.
	_check(model.legacy_presentation_controller("legacy_record") == "actor_b", "I legacy controller presentation remains unchanged")
	_check(model.get_administrators("legacy_record").size() == 1, "I controlled_territory maps to compatibility administrator")
	_check(model.get_sovereigns("legacy_record").is_empty(), "I legacy controller never synthesizes sovereignty")
	var legacy_relation := model.get_authority_relations("legacy_record")[0]
	_check(bool(legacy_relation.get("compatibility_generated", false)), "I compatibility edge is explicitly marked")

	# Validity boundary and uncertainty representation.
	_check(model.get_active_relations("bosnia_like", "1890-01-01").size() == 2, "Validity includes valid_from boundary")
	_check(model.get_active_relations("bosnia_like", "1910-12-31").size() == 2, "Validity includes valid_to boundary")
	_check(model.get_active_relations("bosnia_like", "1911-01-01").is_empty(), "Validity excludes dates after valid_to")
	var uncertain := model.get_claimants("philippines_like")[0]
	_check(int(uncertain.get("confidence_bp", -1)) == 8500, "Uncertainty uses bounded confidence_bp")
	_check(str(uncertain.get("uncertainty", "")) == "contested evidence", "Uncertainty note survives normalization")


func _check_invalid_fixture_j() -> void:
	var base_actors: Array = [_actor("actor_a"), _actor("actor_b")]

	var unknown_actor := base_actors.duplicate(true)
	unknown_actor.append(_explicit_unit("invalid_unknown_actor", [
		_relation("j-unknown-actor", "invalid_unknown_actor", "missing_actor", "sovereign"),
	]))
	_check_rejected(unknown_actor, "J rejects unknown authority actor")

	var unknown_type := base_actors.duplicate(true)
	unknown_type.append(_explicit_unit("invalid_unknown_type", [
		_relation("j-unknown-type", "invalid_unknown_type", "actor_a", "invented_role"),
	]))
	_check_rejected(unknown_type, "J rejects unknown relation type")

	var invalid_interval := base_actors.duplicate(true)
	var inverted := _relation("j-inverted", "invalid_interval", "actor_a", "sovereign")
	inverted["valid_from"] = "1910-01-01"
	inverted["valid_to"] = "1900-01-01"
	invalid_interval.append(_explicit_unit("invalid_interval", [inverted]))
	_check_rejected(invalid_interval, "J rejects inverted validity interval")

	var invalid_date := base_actors.duplicate(true)
	var bad_date := _relation("j-bad-date", "invalid_date", "actor_a", "sovereign")
	bad_date["valid_from"] = "1900-02-30"
	invalid_date.append(_explicit_unit("invalid_date", [bad_date]))
	_check_rejected(invalid_date, "J rejects impossible calendar date")

	var duplicate_identity := base_actors.duplicate(true)
	duplicate_identity.append(_explicit_unit("duplicate_identity", [
		_relation("j-duplicate", "duplicate_identity", "actor_a", "claimant"),
		_relation("j-duplicate", "duplicate_identity", "actor_b", "claimant"),
	]))
	_check_rejected(duplicate_identity, "J rejects duplicate relation identity")

	var duplicate_edge := base_actors.duplicate(true)
	duplicate_edge.append(_explicit_unit("duplicate_edge", [
		_relation("j-edge-a", "duplicate_edge", "actor_a", "claimant"),
		_relation("j-edge-b", "duplicate_edge", "actor_a", "claimant"),
	]))
	_check_rejected(duplicate_edge, "J rejects duplicate semantic edge")

	var mixed_conflict := base_actors.duplicate(true)
	var mixed := _explicit_unit("mixed_conflict", [
		_relation("j-mixed", "mixed_conflict", "actor_a", "administrator"),
	])
	mixed["controller_id"] = "actor_b"
	mixed_conflict.append(mixed)
	_check_rejected(mixed_conflict, "J malformed mixed legacy/explicit record fails closed")


func _check_production_regression() -> void:
	var document := _read_document(POLITICAL_UNITS_PATH)
	_check(not document.is_empty(), "Production political document loads")
	if document.is_empty():
		return
	var units := document.get("units", []) as Array
	_check(int(document.get("unit_count", -1)) == 151, "Production unit count remains 151")
	_check(units.size() == 151, "Production units array remains 151")
	_check(str(document.get("snapshot_date", "")) == SNAPSHOT_DATE, "Production snapshot remains 1900-03-12")
	var policy := document.get("policy", {}) as Dictionary
	_check(not bool(policy.get("modern_geometry_fallback_allowed", true)), "Modern political fallback remains disabled")

	var model := HistoricalAuthorityModel.new()
	_check(model.configure(units), "All 151 production legacy records load: %s" % model.initialization_error)
	if not model.initialization_error.is_empty():
		return

	var by_id: Dictionary = {}
	for raw_unit: Variant in units:
		var unit := raw_unit as Dictionary
		var entity_id := str(unit.get("id", ""))
		by_id[entity_id] = unit
		_check(
			model.legacy_presentation_controller(entity_id) == str(unit.get("controller_id", "")),
			"Legacy presentation controller preserved for %s" % entity_id
		)

	var positive_ids: Array[String] = [
		"german_empire",
		"kingdom_of_italy",
		"russian_empire",
		"emirate_of_bukhara",
		"khanate_of_khiva",
		"congo_free_state",
		"cshapes_gw_470",
		"kingdom_of_nepal",
		"kingdom_of_siam",
		"qing_empire",
		"korean_empire",
		"empire_of_japan",
		"taiwan_under_japan",
		"cshapes_gw_920",
		"republic_of_colombia_1900",
	]
	for entity_id: String in positive_ids:
		_check(by_id.has(entity_id) and model.has_subject(entity_id), "Positive control remains admitted: %s" % entity_id)
	for index: int in range(901, 907):
		var australian_id := "cshapes_gw_%d" % index
		_check(by_id.has(australian_id) and model.has_subject(australian_id), "Australian colony remains admitted: %s" % australian_id)

	# Positive controls protect current Wave-0 behavior, not historical repairs.
	_check(str((by_id.get("emirate_of_bukhara", {}) as Dictionary).get("controller_id", "")) == "russian_empire", "Bukhara legacy production controller remains unchanged")
	_check(str((by_id.get("khanate_of_khiva", {}) as Dictionary).get("controller_id", "")) == "russian_empire", "Khiva legacy production controller remains unchanged")
	_check(str((by_id.get("taiwan_under_japan", {}) as Dictionary).get("controller_id", "")) == "empire_of_japan", "Taiwan legacy production controller remains unchanged")
	_check(str((by_id.get("republic_of_colombia_1900", {}) as Dictionary).get("valid_to", "")) == "1903-11-02", "Colombia/Panama baseline validity remains unchanged")
	_check(not by_id.has("panama_1900"), "Wave 0 does not admit a new Panama political unit")


func _check_save_restore_reconstruction() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "Formal simulation initializes with reconstructed authority graph: %s" % source.initialization_error)
	if not source.initialized:
		return
	var source_relations := source.get_authority_relations("emirate_of_bukhara")
	_check(source.legacy_presentation_controller("emirate_of_bukhara") == "russian_empire", "Formal composition root exposes compatibility controller through authority API")
	_check(source.get_sovereigns("emirate_of_bukhara").is_empty(), "Formal runtime no longer turns Bukhara legacy controller into sovereign")
	var state := source.get_persistent_state()
	_check(not state.has("authority"), "Authority graph is reconstructed static data, not serialized into save root")
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "Authority reconstruction target initializes")
	if not restored.initialized:
		return
	_check(restored.restore_persistent_state(state), "Existing formal save schema restores without authority serialization")
	_check(restored.get_authority_relations("emirate_of_bukhara") == source_relations, "Authority graph deterministically reconstructs across save/restore")
	var summary := restored.polity_summary("emirate_of_bukhara")
	_check(str(summary.get("controller_id", "")) == "russian_empire", "Polity summary preserves legacy visible controller")
	_check(str(summary.get("sovereign_id", "")) == "", "Polity summary does not synthesize legacy sovereignty")


func _actor(entity_id: String) -> Dictionary:
	return {
		"id": entity_id,
		"valid_from": "1800-01-01",
		"valid_to": "",
		"status": "fixture_actor",
		"relationship": "fixture",
		"controller_id": "",
	}


func _explicit_unit(
	entity_id: String, relations: Array, status: String = "fixture"
) -> Dictionary:
	return {
		"id": entity_id,
		"valid_from": "1890-01-01",
		"valid_to": "1910-12-31",
		"status": status,
		"relationship": "fixture",
		"controller_id": "",
		"authority_relations": relations,
	}


func _relation(
	relation_id: String,
	subject_id: String,
	authority_id: String,
	relationship_type: String
) -> Dictionary:
	return {
		"id": relation_id,
		"subject_id": subject_id,
		"authority_id": authority_id,
		"relationship_type": relationship_type,
		"valid_from": "1890-01-01",
		"valid_to": "1910-12-31",
		"confidence_bp": 8500 if relationship_type == "claimant" else 10000,
		"uncertainty": "contested evidence" if relationship_type == "claimant" else "",
		"provenance": {"kind": "synthetic_wave0_fixture"},
		"scope": "",
	}


func _check_rejected(units: Array, message: String) -> void:
	var model := HistoricalAuthorityModel.new()
	_check(not model.configure(units) and not model.initialization_error.is_empty(), message)


func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return {}
	return parser.data as Dictionary


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("Historical authority model: " + message)
