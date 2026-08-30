extends SceneTree

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")
const REQUEST = preload("res://scripts/vnext/observation/observation_request.gd")
const FIELD = preload("res://scripts/vnext/observation/observed_field.gd")
const RECORD = preload("res://scripts/vnext/observation/observation_record.gd")
const RESPONSE = preload("res://scripts/vnext/observation/observation_response.gd")
const QUERY_PORT = preload("res://scripts/vnext/observation/observation_query_port.gd")
const INVALIDATION = preload("res://scripts/vnext/observation/observation_invalidation.gd")
const RESOLVER = preload("res://scripts/vnext/observation/synthetic_visibility_resolver.gd")
const PROVIDER = preload("res://scripts/vnext/observation/synthetic_observation_provider.gd")

const OBSERVER_A_ID: String = PROVIDER.OBSERVER_A_ID
const OBSERVER_B_ID: String = PROVIDER.OBSERVER_B_ID
const QA_OBSERVER_ID: String = PROVIDER.QA_OBSERVER_ID
const SUBJECT_X_ID: String = PROVIDER.SUBJECT_X_ID
const PUBLIC_FIELD_ID: String = PROVIDER.PUBLIC_FIELD_ID
const RESTRICTED_FIELD_ID: String = PROVIDER.RESTRICTED_FIELD_ID
const HIDDEN_FIELD_ID: String = PROVIDER.HIDDEN_FIELD_ID

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_request_requires_observer_identity()
	_test_observer_and_subject_are_distinct()
	_test_malformed_observer_id_rejected()
	_test_unknown_observer_rejected()
	_test_public_field_visible()
	_test_restricted_field_filtered_for_unauthorized_observer()
	_test_hidden_field_does_not_leak_metadata()
	_test_different_observers_receive_different_observations()
	_test_same_observer_is_semantically_consistent()
	_test_missing_resolver_fails_closed()
	_test_truth_observer_requires_explicit_capability()
	_test_fake_truth_request_is_filtered()
	_test_expected_revision_match_is_accepted()
	_test_stale_expected_revision_is_explicit()
	_test_response_revision_is_consistent()
	_test_capture_uses_one_revision()
	_test_response_contains_observer_and_observed_at()
	_test_acquisition_and_observed_state_times_are_distinct()
	_test_provenance_references_are_retained()
	_test_stale_status_is_retained()
	_test_response_mutation_is_detached()
	_test_nested_record_mutation_is_detached()
	_test_no_runtime_snapshot_or_owner_bypass()
	_test_deterministic_record_and_field_ordering()
	_test_deterministic_observation_fingerprint()
	_test_invalidation_is_small_and_detached()
	_test_query_port_fails_closed()
	print("VNext observation contract: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_request_requires_observer_identity() -> void:
	var request := REQUEST.new()
	_check(
		not request.configure("", "person", [SUBJECT_X_ID], -1, [PUBLIC_FIELD_ID], []),
		"request requires a non-empty observer identity"
	)
	_check(request.validation_error() == "observer_actor_id_invalid", "missing identity reports a request validation error")
	_check(_request(OBSERVER_A_ID) != null, "valid observer identity creates an observation request")


func _test_observer_and_subject_are_distinct() -> void:
	var request = _request(OBSERVER_A_ID)
	_check(request.observer_actor_id() != request.subject_ids()[0], "observer and subject are distinct fields")
	_equal(request.observer_actor_id(), OBSERVER_A_ID, "request retains observer actor identity")
	_equal(request.subject_ids()[0], SUBJECT_X_ID, "request retains subject identity separately")


func _test_malformed_observer_id_rejected() -> void:
	_check(
		_request("person:BadObserver") == null,
		"malformed observer ID is rejected"
	)
	_check(
		_request("place:observer_a") == null,
		"non-person observer ID is rejected"
	)


func _test_unknown_observer_rejected() -> void:
	var response = _provider().query(_request("person:unknown_observer"))
	_equal(response.status(), CONTRACT.STATUS_UNKNOWN_OBSERVER, "valid but unregistered observer is rejected")
	_equal(response.records().size(), 0, "unknown observer receives no records")


func _test_public_field_visible() -> void:
	var response = _provider().query(_request(OBSERVER_B_ID, [PUBLIC_FIELD_ID]))
	_check(response.is_success(), "public field query succeeds")
	_check(_response_has_field(response, PUBLIC_FIELD_ID), "public field is visible to a known observer")


func _test_restricted_field_filtered_for_unauthorized_observer() -> void:
	var provider = _provider()
	var restricted_for_a = provider.query(
		_request(OBSERVER_A_ID, [RESTRICTED_FIELD_ID], [CONTRACT.RESTRICTED_CAPABILITY])
	)
	var restricted_for_b = provider.query(
		_request(OBSERVER_B_ID, [RESTRICTED_FIELD_ID], [CONTRACT.RESTRICTED_CAPABILITY])
	)
	_check(_response_has_field(restricted_for_a, RESTRICTED_FIELD_ID), "restricted field is visible to authorized observer A")
	_check(not _response_has_field(restricted_for_b, RESTRICTED_FIELD_ID), "restricted field is filtered for unauthorized observer B")


func _test_hidden_field_does_not_leak_metadata() -> void:
	var response = _provider().query(
		_request(OBSERVER_B_ID, [HIDDEN_FIELD_ID], [CONTRACT.TRUTH_CAPABILITY])
	)
	var response_text: String = JSON.stringify(response.to_detached_dict())
	_check(not _response_has_field(response, HIDDEN_FIELD_ID), "hidden field is not returned without resolver permission")
	_check(not response_text.contains(HIDDEN_FIELD_ID), "hidden field key is absent from unauthorized response metadata")
	_check(not response_text.contains("hidden-authoritative-value"), "hidden authoritative value is absent from unauthorized response")


func _test_different_observers_receive_different_observations() -> void:
	var provider = _provider()
	var response_a = provider.query(_request(OBSERVER_A_ID, [], [CONTRACT.RESTRICTED_CAPABILITY]))
	var response_b = provider.query(_request(OBSERVER_B_ID, [], [CONTRACT.RESTRICTED_CAPABILITY]))
	_check(response_a.fingerprint() != response_b.fingerprint(), "different observers receive different observations")
	_check(
		_response_has_field(response_a, RESTRICTED_FIELD_ID)
		and not _response_has_field(response_b, RESTRICTED_FIELD_ID),
		"observer-specific visibility changes returned records"
	)


func _test_same_observer_is_semantically_consistent() -> void:
	var provider = _provider()
	var request = _request(OBSERVER_A_ID)
	var first = provider.query(request)
	var second = provider.query(request)
	_equal(first.fingerprint(), second.fingerprint(), "same observer and request produce semantically consistent results")
	_equal(
		JSON.stringify(first.to_detached_dict()),
		JSON.stringify(second.to_detached_dict()),
		"same observer receives deterministic envelope ordering"
	)


func _test_missing_resolver_fails_closed() -> void:
	var response = PROVIDER.new().query(_request(OBSERVER_A_ID))
	_equal(response.status(), CONTRACT.STATUS_VISIBILITY_UNAVAILABLE, "missing visibility resolver fails closed")
	_equal(response.records().size(), 0, "missing visibility resolver returns no records")


func _test_truth_observer_requires_explicit_capability() -> void:
	var provider = _provider()
	var response_without_grant = provider.query(_request(QA_OBSERVER_ID, [HIDDEN_FIELD_ID]))
	_check(not _response_has_field(response_without_grant, HIDDEN_FIELD_ID), "truth observer without requested truth capability cannot see hidden field")
	var response_with_grant = provider.query(
		_request(QA_OBSERVER_ID, [HIDDEN_FIELD_ID], [CONTRACT.TRUTH_CAPABILITY])
	)
	_check(_response_has_field(response_with_grant, HIDDEN_FIELD_ID), "truth observer with explicit truth capability can see hidden field")


func _test_fake_truth_request_is_filtered() -> void:
	var response = _provider().query(
		_request(OBSERVER_B_ID, [PUBLIC_FIELD_ID, HIDDEN_FIELD_ID], [CONTRACT.TRUTH_CAPABILITY])
	)
	_check(_response_has_field(response, PUBLIC_FIELD_ID), "fake truth request still returns permitted public field")
	_check(not _response_has_field(response, HIDDEN_FIELD_ID), "fake truth request cannot grant hidden capability")


func _test_expected_revision_match_is_accepted() -> void:
	var provider = _provider()
	var response = provider.query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID], [], provider.current_world_revision())
	)
	_check(response.is_success(), "matching expected world revision is accepted")
	_equal(response.world_revision(), provider.current_world_revision(), "accepted response uses current requested revision")


func _test_stale_expected_revision_is_explicit() -> void:
	var provider = _provider()
	var old_revision: int = provider.current_world_revision()
	var request = _request(OBSERVER_A_ID, [PUBLIC_FIELD_ID], [], old_revision)
	var invalidation = provider.advance_world_revision(old_revision + 1)
	_check(invalidation != null, "synthetic provider emits invalidation on revision change")
	var response = provider.query(request)
	_equal(response.status(), CONTRACT.STATUS_REVISION_MISMATCH, "stale expected revision is rejected explicitly")
	_check(response.is_revision_mismatch(), "revision mismatch is marked explicitly")
	_check(response.is_stale(), "revision mismatch retains stale status")
	_equal(response.records().size(), 0, "revision mismatch does not return new revision data")


func _test_response_revision_is_consistent() -> void:
	var response = _provider().query(_request(QA_OBSERVER_ID))
	for record: VNextObservationRecord in response.records():
		_equal(record.world_revision(), response.world_revision(), "every returned record belongs to envelope world revision")


func _test_capture_uses_one_revision() -> void:
	var provider = _provider()
	var request = _request(OBSERVER_A_ID)
	var hook := func() -> void:
		_check(provider.advance_world_revision(provider.current_world_revision() + 1) != null, "capture hook advances world revision")
	_check(provider.set_capture_hook(hook), "synthetic provider accepts a capture hook")
	var response = provider.query(request)
	provider.clear_capture_hook()
	_check(response.is_success(), "query remains successful from captured revision")
	_check(response.is_stale(), "query marks data stale when world changes during capture")
	_equal(response.world_revision(), CONTRACT.UNSPECIFIED_WORLD_REVISION + 11, "response keeps the captured revision")
	for record: VNextObservationRecord in response.records():
		_equal(record.world_revision(), 10, "capture hook cannot mix a newer record revision")


func _test_response_contains_observer_and_observed_at() -> void:
	var response = _provider().query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID]))
	var envelope: Dictionary = response.to_detached_dict()
	_equal(envelope.get("schema_id"), CONTRACT.SCHEMA_ID, "response contains schema ID")
	_check(not str(envelope.get("observation_id", "")).is_empty(), "response contains observation ID")
	_equal(envelope.get("observer_actor_id"), OBSERVER_A_ID, "response contains observer actor ID")
	_check(int(envelope.get("observed_at", -1)) >= 0, "response contains logical observed_at")


func _test_acquisition_and_observed_state_times_are_distinct() -> void:
	var field: VNextObservedField = _provider().query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])).records()[0].field_by_id(PUBLIC_FIELD_ID)
	_check(field.acquired_at() != field.observed_state_at(), "acquired_at differs from observed_state_at")
	_equal(field.acquired_at(), 200, "acquired_at is retained")
	_equal(field.observed_state_at(), 150, "observed_state_at is retained")


func _test_provenance_references_are_retained() -> void:
	var field: VNextObservedField = _provider().query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])).records()[0].field_by_id(PUBLIC_FIELD_ID)
	_equal(field.provenance_references(), ["synthetic.source.public"], "synthetic provenance reference is retained without owning evidence")


func _test_stale_status_is_retained() -> void:
	var field: VNextObservedField = _provider().query(
		_request(OBSERVER_A_ID, [RESTRICTED_FIELD_ID], [CONTRACT.RESTRICTED_CAPABILITY])
	).records()[0].field_by_id(RESTRICTED_FIELD_ID)
	_equal(field.freshness_state(), CONTRACT.FRESHNESS_STALE, "field freshness state is retained")
	_check(field.is_stale(), "field stale status is retained")


func _test_response_mutation_is_detached() -> void:
	var provider = _provider()
	var returned: Dictionary = provider.query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])).to_detached_dict()
	var records: Array = returned.get("records", []) as Array
	var fields: Array = (records[0] as Dictionary).get("fields", []) as Array
	(fields[0] as Dictionary)["confidence"] = 0.0
	var fresh_field: VNextObservedField = provider.query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])).records()[0].field_by_id(PUBLIC_FIELD_ID)
	_equal(fresh_field.confidence(), 0.98, "mutating returned response does not mutate provider state")


func _test_nested_record_mutation_is_detached() -> void:
	var provider = _provider()
	var detached_record: VNextObservationRecord = provider.query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])).records()[0]
	var detached_field: VNextObservedField = detached_record.field_by_id(PUBLIC_FIELD_ID)
	var perceived: Dictionary = detached_field.perceived_value() as Dictionary
	var nested: Dictionary = perceived.get("nested", {}) as Dictionary
	nested["counter"] = 999
	perceived["nested"] = nested
	perceived["label"] = "tampered"
	_check(detached_field.replace_perceived_value(perceived), "detached nested field can be mutated locally")
	var fresh_field: VNextObservedField = provider.query(_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])).records()[0].field_by_id(PUBLIC_FIELD_ID)
	_equal((fresh_field.perceived_value() as Dictionary).get("label"), "public-value", "mutating nested perceived value does not mutate provider state")
	_equal((fresh_field.perceived_value() as Dictionary).get("nested", {}).get("counter"), 1, "nested value remains detached")


func _test_no_runtime_snapshot_or_owner_bypass() -> void:
	var provider = _provider()
	_check(not provider.has_method("snapshot"), "query provider exposes no runtime snapshot method")
	_check(not provider.has_method("get_internal_state"), "query provider exposes no internal state method")
	_check(not provider.has_method("authoritative_owner"), "query provider exposes no authoritative owner")
	_check(not provider.has_method("economy_owner"), "query provider exposes no economy owner")
	_check(not provider.has_method("polity_registry_owner"), "query provider exposes no polity registry owner")
	_check(not provider.has_method("organization_core_owner"), "query provider exposes no organization owner")
	_check(not provider.has_method("military_owner"), "query provider exposes no military owner")
	var response_text: String = JSON.stringify(provider.query(_request(OBSERVER_B_ID, [HIDDEN_FIELD_ID])).to_detached_dict())
	_check(not response_text.contains("authoritative"), "filtered envelope exposes no authoritative truth payload")


func _test_deterministic_record_and_field_ordering() -> void:
	var response = _provider().query(
		_request(
			QA_OBSERVER_ID,
			[RESTRICTED_FIELD_ID, HIDDEN_FIELD_ID, PUBLIC_FIELD_ID],
			[CONTRACT.TRUTH_CAPABILITY, CONTRACT.RESTRICTED_CAPABILITY]
		)
	)
	var record: VNextObservationRecord = response.records()[0]
	_equal(record.field_ids(), [HIDDEN_FIELD_ID, PUBLIC_FIELD_ID, RESTRICTED_FIELD_ID], "fields are emitted in deterministic key order")
	var reordered = _provider().query(
		_request(
			QA_OBSERVER_ID,
			[PUBLIC_FIELD_ID, HIDDEN_FIELD_ID, RESTRICTED_FIELD_ID],
			[CONTRACT.RESTRICTED_CAPABILITY, CONTRACT.TRUTH_CAPABILITY]
		)
	)
	_equal(response.fingerprint(), reordered.fingerprint(), "requested field input order does not change result")


func _test_deterministic_observation_fingerprint() -> void:
	var first = _provider().query(_request(QA_OBSERVER_ID, [], [CONTRACT.TRUTH_CAPABILITY, CONTRACT.RESTRICTED_CAPABILITY]))
	var second = _provider().query(_request(QA_OBSERVER_ID, [], [CONTRACT.RESTRICTED_CAPABILITY, CONTRACT.TRUTH_CAPABILITY]))
	_check(not first.observation_id().is_empty(), "deterministic response has an observation ID")
	_equal(first.observation_id(), second.observation_id(), "same state and request produce deterministic observation ID")
	_equal(first.fingerprint(), second.fingerprint(), "same state and request produce deterministic fingerprint")


func _test_invalidation_is_small_and_detached() -> void:
	var invalidation: VNextObservationInvalidation = _provider().invalidation_for_change(
		["z_scope", "a_scope"], "event:synthetic_revision_change"
	)
	var payload: Dictionary = invalidation.to_detached_dict()
	_equal(payload.get("schema_id"), CONTRACT.INVALIDATION_SCHEMA_ID, "invalidation carries its own schema")
	_equal(payload.get("changed_scopes"), ["a_scope", "z_scope"], "invalidation scopes are deterministic")
	_equal(payload.get("cause_id"), "event:synthetic_revision_change", "invalidation carries cause ID")
	_check(not payload.has("records"), "invalidation does not carry replacement truth")
	(payload.get("changed_scopes") as Array).append("tampered")
	_equal(invalidation.changed_scopes(), ["a_scope", "z_scope"], "invalidation payload is detached")


func _test_query_port_fails_closed() -> void:
	var response: VNextObservationResponse = QUERY_PORT.new().query(null)
	_equal(response.status(), CONTRACT.STATUS_QUERY_UNAVAILABLE, "base query port has no owner bypass")
	_equal(response.records().size(), 0, "base query port returns no records")


func _provider() -> VNextSyntheticObservationProvider:
	return PROVIDER.new(RESOLVER.new())


func _request(
	observer_actor_id: String,
	requested_fields: Array[String] = [],
	requested_capabilities: Array[String] = [],
	expected_world_revision: int = CONTRACT.UNSPECIFIED_WORLD_REVISION
) -> VNextObservationRequest:
	var fields: Array[String] = requested_fields
	if fields.is_empty():
		fields = [PUBLIC_FIELD_ID, RESTRICTED_FIELD_ID, HIDDEN_FIELD_ID]
	return REQUEST.create(
		observer_actor_id,
		"person",
		[SUBJECT_X_ID],
		expected_world_revision,
		fields,
		requested_capabilities
	)


func _response_has_field(response: VNextObservationResponse, field_id: String) -> bool:
	for record: VNextObservationRecord in response.records():
		if record.has_field(field_id):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
