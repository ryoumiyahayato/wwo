extends SceneTree

var vnext_identity_checks: int = 0
var vnext_identity_failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_five_valid_kinds()
	_test_valid_local_id()
	_test_uppercase_rejected()
	_test_space_and_other_symbols_rejected()
	_test_empty_ids_rejected()
	_test_unknown_kind_rejected()
	_test_multiple_colons_rejected()
	_test_compose_parse_round_trip()
	_test_valid_unique_catalog()
	_test_duplicate_catalog_id_rejected()
	_test_invalid_catalog_record_rejected()
	_test_query_by_canonical_id()
	_test_unknown_id_does_not_create_record()
	_test_input_order_does_not_change_id_semantics()
	print(
		"VNext stable ID catalog: %d checks, %d failures"
		% [vnext_identity_checks, vnext_identity_failures]
	)
	quit(1 if vnext_identity_failures > 0 or vnext_identity_checks <= 0 else 0)


func _test_five_valid_kinds() -> void:
	var canonical_examples: Array[String] = [
		"person:alice_example",
		"place:country_fra",
		"organization:parliament_france",
		"event:election_france_1900",
		"economy:country_fra",
	]
	for candidate_canonical_id: String in canonical_examples:
		_check(
			VNextStableId.is_valid(candidate_canonical_id),
			"supported kind is valid: %s" % candidate_canonical_id
		)


func _test_valid_local_id() -> void:
	_equal(
		VNextStableId.compose("person", "alice_01-test"),
		"person:alice_01-test",
		"lowercase letters, digits, underscore, and hyphen are valid local id characters"
	)


func _test_uppercase_rejected() -> void:
	_check(not VNextStableId.is_valid("person:Alice"), "uppercase local id is rejected")
	_equal(VNextStableId.compose("PERSON", "alice"), "", "uppercase kind is rejected")


func _test_space_and_other_symbols_rejected() -> void:
	_check(not VNextStableId.is_valid("place:country fra"), "spaces are rejected")
	_check(not VNextStableId.is_valid("person:alice.example"), "other symbols are rejected")


func _test_empty_ids_rejected() -> void:
	_check(not VNextStableId.is_valid(""), "empty canonical id is rejected")
	_check(not VNextStableId.is_valid("person:"), "empty local id is rejected")
	_check(not VNextStableId.is_valid(":alice"), "empty kind is rejected")
	_equal(VNextStableId.compose("person", ""), "", "compose rejects empty local id")


func _test_unknown_kind_rejected() -> void:
	_check(not VNextStableId.is_valid("country:fra"), "unknown kind is rejected")
	_equal(VNextStableId.compose("country", "fra"), "", "compose rejects unknown kind")


func _test_multiple_colons_rejected() -> void:
	_check(not VNextStableId.is_valid("event:france:election"), "multiple colons are rejected")
	_equal(VNextStableId.kind_of("event:france:election"), "", "invalid id has no parsed kind")


func _test_compose_parse_round_trip() -> void:
	var composed_id: String = VNextStableId.compose("event", "election_france_1900")
	_equal(composed_id, "event:election_france_1900", "compose produces canonical id")
	_equal(VNextStableId.kind_of(composed_id), "event", "kind parses from composed id")
	_equal(
		VNextStableId.local_id_of(composed_id),
		"election_france_1900",
		"local id parses from composed id"
	)
	_equal(
		VNextStableId.compose(
			VNextStableId.kind_of(composed_id), VNextStableId.local_id_of(composed_id)
		),
		composed_id,
		"compose and parse round trip is stable"
	)


func _test_valid_unique_catalog() -> void:
	var catalog_records: Array = _catalog_fixture()
	_check(VNextCatalogContract.validate(catalog_records), "unique valid catalog is accepted")
	_equal(
		catalog_records[0].get("id"),
		"person:alice_example",
		"catalog validation does not rewrite input id"
	)


func _test_duplicate_catalog_id_rejected() -> void:
	var duplicate_records: Array = [
		{"id": "place:country_fra", "display_name": "France"},
		{"id": "place:country_fra", "display_name": "French Republic"},
	]
	_check(not VNextCatalogContract.validate(duplicate_records), "duplicate canonical id is rejected")


func _test_invalid_catalog_record_rejected() -> void:
	_check(
		not VNextCatalogContract.validate([{"display_name": "Missing ID"}]),
		"catalog record missing id is rejected"
	)
	_check(
		not VNextCatalogContract.validate([{"id": "place:Country_FRA"}]),
		"catalog record with invalid id is rejected"
	)
	_check(
		not VNextCatalogContract.validate([{"id": 42}]),
		"catalog record with non-string id is rejected"
	)
	_check(
		not VNextCatalogContract.validate(["place:country_fra"]),
		"non-dictionary catalog record is rejected"
	)


func _test_query_by_canonical_id() -> void:
	var catalog_records: Array = _catalog_fixture()
	var found_record: Variant = VNextCatalogContract.record_by_id(
		catalog_records, "place:country_fra"
	)
	_check(typeof(found_record) == TYPE_DICTIONARY, "canonical id query returns the matching record")
	_equal(
		_dictionary_field(found_record, "display_name"),
		"France",
		"canonical id query returns deterministic record data"
	)
	_equal(
		VNextCatalogContract.record_by_id(catalog_records, "France"),
		null,
		"display name is not accepted as an id"
	)


func _test_unknown_id_does_not_create_record() -> void:
	var catalog_records: Array = _catalog_fixture()
	_equal(
		VNextCatalogContract.record_by_id(catalog_records, "person:missing_person"),
		null,
		"unknown valid id returns null rather than a default record"
	)


func _test_input_order_does_not_change_id_semantics() -> void:
	var first_catalog: Array = _catalog_fixture()
	var second_catalog: Array = [first_catalog[2], first_catalog[0], first_catalog[1]]
	_check(VNextCatalogContract.validate(first_catalog), "first catalog order is valid")
	_check(VNextCatalogContract.validate(second_catalog), "second catalog order is valid")
	_equal(
		VNextCatalogContract.record_by_id(first_catalog, "organization:parliament_france"),
		VNextCatalogContract.record_by_id(second_catalog, "organization:parliament_france"),
		"input order does not change canonical id lookup semantics"
	)


func _catalog_fixture() -> Array:
	return [
		{"id": "person:alice_example", "display_name": "Alice Example"},
		{"id": "place:country_fra", "display_name": "France"},
		{"id": "organization:parliament_france", "display_name": "Parliament"},
	]


func _dictionary_field(candidate_value: Variant, field_name: String) -> Variant:
	if typeof(candidate_value) != TYPE_DICTIONARY:
		return null
	var dictionary_value: Dictionary = candidate_value
	return dictionary_value.get(field_name)


func _check(condition: bool, label: String) -> void:
	vnext_identity_checks += 1
	if condition:
		print("PASS: " + label)
		return
	vnext_identity_failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
