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
	_test_request_contract()
	_test_visibility_and_observers()
	_test_revision_contract()
	_test_field_contract()
	_test_provenance_boundary()
	_test_detachment_and_owner_boundary()
	_test_determinism_and_invalidation()
	_test_query_port_boundary()
	print("VNext observation contract: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_request_contract() -> void:
	var request := REQUEST.new()
	_check(
		not request.configure("", "person", [SUBJECT_X_ID], -1, [PUBLIC_FIELD_ID], []),
		"request requires observer identity"
	)
	_equal(
		request.validation_error(),
		"observer_actor_id_invalid",
		"missing observer identity reports a validation error"
	)
	_check(
		_request(OBSERVER_A_ID) != null,
		"valid observer identity creates a request"
	)
	var valid_request: VNextObservationRequest = _request(OBSERVER_A_ID)
	_equal(
		valid_request.observer_actor_id(),
		OBSERVER_A_ID,
		"request retains observer actor identity"
	)
	_equal(
		valid_request.subject_ids(),
		[SUBJECT_X_ID],
		"request retains subject identity separately"
	)
	_check(
		valid_request.observer_actor_id() != valid_request.subject_ids()[0],
		"observer and subject are distinct fields"
	)
	_check(
		_request("person:BadObserver") == null,
		"malformed observer ID is rejected"
	)
	_check(
		_request("place:observer_a") == null,
		"non-person observer ID is rejected"
	)
	_check(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID, PUBLIC_FIELD_ID]) == null,
		"duplicate requested fields are rejected"
	)


func _test_visibility_and_observers() -> void:
	var unknown_response = _provider().query(_request("person:unknown_observer"))
	_equal(
		unknown_response.status(),
		CONTRACT.STATUS_UNKNOWN_OBSERVER,
		"unknown observer is rejected by the resolver"
	)
	_equal(unknown_response.records().size(), 0, "unknown observer receives no records")

	var public_response = _provider().query(_request(OBSERVER_B_ID, [PUBLIC_FIELD_ID]))
	_check(public_response.is_success(), "public field query succeeds")
	_check(
		_response_has_field(public_response, PUBLIC_FIELD_ID),
		"public field is visible to a known observer"
	)

	var provider = _provider()
	var restricted_for_a = provider.query(
		_request(
			OBSERVER_A_ID,
			[RESTRICTED_FIELD_ID],
			[CONTRACT.RESTRICTED_CAPABILITY]
		)
	)
	var restricted_for_b = provider.query(
		_request(
			OBSERVER_B_ID,
			[RESTRICTED_FIELD_ID],
			[CONTRACT.RESTRICTED_CAPABILITY]
		)
	)
	_check(
		_response_has_field(restricted_for_a, RESTRICTED_FIELD_ID),
		"restricted field is visible to authorized observer A"
	)
	_check(
		not _response_has_field(restricted_for_b, RESTRICTED_FIELD_ID),
		"restricted field is filtered for unauthorized observer B"
	)

	var hidden_response = provider.query(
		_request(
			OBSERVER_B_ID,
			[HIDDEN_FIELD_ID],
			[CONTRACT.TRUTH_CAPABILITY]
		)
	)
	var hidden_response_text: String = JSON.stringify(hidden_response.to_detached_dict())
	_check(
		not _response_has_field(hidden_response, HIDDEN_FIELD_ID),
		"hidden field is not returned without permission"
	)
	_check(
		not hidden_response_text.contains(HIDDEN_FIELD_ID),
		"hidden field ID does not leak through unauthorized metadata"
	)
	_check(
		not hidden_response_text.contains("hidden-authoritative-value"),
		"hidden authoritative value does not leak through unauthorized metadata"
	)

	var response_a = provider.query(
		_request(OBSERVER_A_ID, [], [CONTRACT.RESTRICTED_CAPABILITY])
	)
	var response_b = provider.query(
		_request(OBSERVER_B_ID, [], [CONTRACT.RESTRICTED_CAPABILITY])
	)
	_check(
		response_a.fingerprint() != response_b.fingerprint(),
		"different observers receive different observations"
	)

	var consumer_one: VNextObservationQueryPort = provider
	var consumer_two: VNextObservationQueryPort = provider
	var consumer_request = _request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	var consumer_response_one = consumer_one.query(consumer_request)
	var consumer_response_two = consumer_two.query(consumer_request)
	_equal(
		consumer_response_one.fingerprint(),
		consumer_response_two.fingerprint(),
		"same observer is semantically consistent across consumers"
	)
	_equal(
		JSON.stringify(consumer_response_one.to_detached_dict()),
		JSON.stringify(consumer_response_two.to_detached_dict()),
		"same observer receives the same deterministic envelope"
	)

	var no_resolver_response = PROVIDER.new().query(_request(OBSERVER_A_ID))
	_equal(
		no_resolver_response.status(),
		CONTRACT.STATUS_VISIBILITY_UNAVAILABLE,
		"missing visibility resolver fails closed"
	)
	_equal(no_resolver_response.records().size(), 0, "missing resolver returns no records")

	var truth_without_capability = provider.query(
		_request(QA_OBSERVER_ID, [HIDDEN_FIELD_ID])
	)
	_check(
		not _response_has_field(truth_without_capability, HIDDEN_FIELD_ID),
		"truth observer still needs an explicit truth capability request"
	)
	var truth_with_capability = provider.query(
		_request(QA_OBSERVER_ID, [HIDDEN_FIELD_ID], [CONTRACT.TRUTH_CAPABILITY])
	)
	_check(
		_response_has_field(truth_with_capability, HIDDEN_FIELD_ID),
		"truth observer with explicit capability can see hidden field"
	)

	var fake_truth = provider.query(
		_request(
			OBSERVER_B_ID,
			[PUBLIC_FIELD_ID, HIDDEN_FIELD_ID],
			[CONTRACT.TRUTH_CAPABILITY]
		)
	)
	_check(_response_has_field(fake_truth, PUBLIC_FIELD_ID), "fake truth request retains public data")
	_check(
		not _response_has_field(fake_truth, HIDDEN_FIELD_ID),
		"fake truth request cannot grant hidden capability"
	)


func _test_revision_contract() -> void:
	var provider = _provider()
	var matching_response = provider.query(
		_request(
			OBSERVER_A_ID,
			[PUBLIC_FIELD_ID],
			[],
			provider.current_world_revision()
		)
	)
	_check(matching_response.is_success(), "matching expected revision is accepted")
	_equal(
		matching_response.world_revision(),
		provider.current_world_revision(),
		"matching response uses the requested current revision"
	)

	var stale_revision: int = provider.current_world_revision()
	var stale_request = _request(OBSERVER_A_ID, [PUBLIC_FIELD_ID], [], stale_revision)
	var invalidation: VNextObservationInvalidation = provider.advance_world_revision(stale_revision + 1)
	_check(invalidation != null, "world revision change emits an invalidation DTO")
	var stale_response = provider.query(stale_request)
	_equal(
		stale_response.status(),
		CONTRACT.STATUS_REVISION_MISMATCH,
		"stale expected revision is rejected explicitly"
	)
	_check(stale_response.is_revision_mismatch(), "revision mismatch is marked explicitly")
	_check(stale_response.is_stale(), "revision mismatch retains stale status")
	_equal(stale_response.records().size(), 0, "revision mismatch returns no newer data")

	var consistent_response = _provider().query(
		_request(QA_OBSERVER_ID, [], [CONTRACT.TRUTH_CAPABILITY])
	)
	for record: VNextObservationRecord in consistent_response.records():
		_equal(
			record.world_revision(),
			consistent_response.world_revision(),
			"every record belongs to the envelope revision"
		)

	var capture_provider = _provider()
	var capture_hook: Callable = func() -> void:
		_check(
			capture_provider.advance_world_revision(
				capture_provider.current_world_revision() + 1
			) != null,
			"capture hook advances the live world revision"
		)
	_check(capture_provider.set_capture_hook(capture_hook), "provider accepts a capture hook")
	var captured_response = capture_provider.query(_request(OBSERVER_A_ID))
	capture_provider.clear_capture_hook()
	_check(captured_response.is_success(), "capture remains successful from one revision")
	_check(captured_response.is_stale(), "capture marks data stale after a mid-query change")
	_equal(captured_response.world_revision(), 10, "capture preserves the original revision")
	for record: VNextObservationRecord in captured_response.records():
		_equal(record.world_revision(), 10, "capture cannot mix a newer record revision")

	var envelope: Dictionary = _provider().query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	).to_detached_dict()
	_equal(envelope.get("schema_id"), CONTRACT.SCHEMA_ID, "response contains schema ID")
	_check(
		not str(envelope.get("observation_id", "")).is_empty(),
		"response contains observation ID"
	)
	_equal(envelope.get("observer_actor_id"), OBSERVER_A_ID, "response contains observer ID")
	_check(int(envelope.get("observed_at", -1)) >= 0, "response contains observed_at")


func _test_field_contract() -> void:
	var provider = _provider()
	var public_record: VNextObservationRecord = provider.query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	).records()[0]
	var public_field: VNextObservedField = public_record.field_by_id(PUBLIC_FIELD_ID)
	_check(public_field != null, "visible record contains an observed field")
	_check(
		public_field.acquired_at() != public_field.observed_state_at(),
		"acquired_at and observed_state_at can differ"
	)
	_equal(public_field.acquired_at(), 200, "acquired_at is retained")
	_equal(public_field.observed_state_at(), 150, "observed_state_at is retained")
	_equal(
		public_field.provenance_references(),
		["synthetic.source.public"],
		"provenance references are retained without owning evidence"
	)

	var restricted_record: VNextObservationRecord = provider.query(
		_request(
			OBSERVER_A_ID,
			[RESTRICTED_FIELD_ID],
			[CONTRACT.RESTRICTED_CAPABILITY]
		)
	).records()[0]
	var restricted_field: VNextObservedField = restricted_record.field_by_id(RESTRICTED_FIELD_ID)
	_equal(
		restricted_field.freshness_state(),
		CONTRACT.FRESHNESS_STALE,
		"field freshness state is retained"
	)
	_check(restricted_field.is_stale(), "stale status is retained on the field")


func _test_provenance_boundary() -> void:
	var provider = _provider()
	_check(
		not provider.has_method("source_registry")
		and not provider.has_method("evidence_catalog")
		and not provider.has_method("provenance_gate"),
		"observation provider does not own provenance services"
	)

	var evidence_linked_field := FIELD.new()
	var bounded_estimate_field := FIELD.new()
	_check(
		evidence_linked_field.configure(
			"evidence_linked_field",
			"linked-value",
			0.75,
			300,
			250,
			["historical.fact.political_identity"],
			CONTRACT.FRESHNESS_FRESH,
			{"review_status": "EVIDENCE_LINKED"}
		)
		and bounded_estimate_field.configure(
			"bounded_estimate_field",
			"bounded-value",
			0.5,
			301,
			251,
			["historical.fact.population_aggregate"],
			CONTRACT.FRESHNESS_STALE,
			{"review_status": "BOUNDED_ESTIMATE"}
		),
		"observation retains provenance review metadata without resolving it"
	)
	_equal(
		evidence_linked_field.extensions().get("review_status"),
		"EVIDENCE_LINKED",
		"EVIDENCE_LINKED is retained and not promoted"
	)
	_equal(
		bounded_estimate_field.extensions().get("review_status"),
		"BOUNDED_ESTIMATE",
		"BOUNDED_ESTIMATE is retained and not promoted"
	)
	_check(
		evidence_linked_field.extensions().get("review_status") != "VERIFIED"
		and bounded_estimate_field.extensions().get("review_status") != "VERIFIED",
		"observation never promotes provenance verification status"
	)


func _test_detachment_and_owner_boundary() -> void:
	var provider = _provider()
	var returned: Dictionary = provider.query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	).to_detached_dict()
	var returned_records: Array = returned.get("records", []) as Array
	var returned_fields: Array = (returned_records[0] as Dictionary).get("fields", []) as Array
	(returned_fields[0] as Dictionary)["confidence"] = 0.0
	var fresh_field: VNextObservedField = provider.query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	).records()[0].field_by_id(PUBLIC_FIELD_ID)
	_equal(fresh_field.confidence(), 0.98, "response mutation cannot mutate provider state")

	var detached_record: VNextObservationRecord = provider.query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	).records()[0]
	var detached_field: VNextObservedField = detached_record.field_by_id(PUBLIC_FIELD_ID)
	var perceived: Dictionary = detached_field.perceived_value() as Dictionary
	var nested: Dictionary = perceived.get("nested", {}) as Dictionary
	nested["counter"] = 999
	perceived["nested"] = nested
	perceived["label"] = "tampered"
	_check(
		detached_field.replace_perceived_value(perceived),
		"detached nested record can be changed locally"
	)
	var fresh_perceived: Dictionary = provider.query(
		_request(OBSERVER_A_ID, [PUBLIC_FIELD_ID])
	).records()[0].field_by_id(PUBLIC_FIELD_ID).perceived_value() as Dictionary
	_equal(fresh_perceived.get("label"), "public-value", "nested mutation does not mutate provider value")
	_equal(
		(fresh_perceived.get("nested", {}) as Dictionary).get("counter"),
		1,
		"nested provider value remains detached"
	)

	_check(not provider.has_method("snapshot"), "provider exposes no runtime snapshot")
	_check(not provider.has_method("get_internal_state"), "provider exposes no internal state")
	_check(not provider.has_method("authoritative_owner"), "provider exposes no authoritative owner")
	_check(not provider.has_method("economy_owner"), "provider exposes no economy owner")
	_check(not provider.has_method("polity_registry_owner"), "provider exposes no polity owner")
	_check(not provider.has_method("organization_core_owner"), "provider exposes no organization owner")
	_check(not provider.has_method("military_owner"), "provider exposes no military owner")
	var filtered_text: String = JSON.stringify(
		provider.query(_request(OBSERVER_B_ID, [HIDDEN_FIELD_ID])).to_detached_dict()
	)
	_check(
		not filtered_text.contains("authoritative"),
		"filtered response exposes no authoritative truth payload"
	)


func _test_determinism_and_invalidation() -> void:
	var first_provider = _provider()
	var first = first_provider.query(
		_request(
			QA_OBSERVER_ID,
			[RESTRICTED_FIELD_ID, HIDDEN_FIELD_ID, PUBLIC_FIELD_ID],
			[CONTRACT.TRUTH_CAPABILITY, CONTRACT.RESTRICTED_CAPABILITY]
		)
	)
	var second_provider = _provider()
	var second = second_provider.query(
		_request(
			QA_OBSERVER_ID,
			[PUBLIC_FIELD_ID, HIDDEN_FIELD_ID, RESTRICTED_FIELD_ID],
			[CONTRACT.RESTRICTED_CAPABILITY, CONTRACT.TRUTH_CAPABILITY]
		)
	)
	_equal(first.observation_id(), second.observation_id(), "same state and request have deterministic observation IDs")
	_equal(first.fingerprint(), second.fingerprint(), "same state and request have deterministic fingerprints")
	_equal(
		first.records()[0].field_ids(),
		[HIDDEN_FIELD_ID, PUBLIC_FIELD_ID, RESTRICTED_FIELD_ID],
		"field ordering is deterministic"
	)
	_check(
		not first.observation_id().is_empty(),
		"deterministic response has an observation ID"
	)

	var invalidation: VNextObservationInvalidation = _provider().invalidation_for_change(
		["z_scope", "a_scope"],
		"event:synthetic_revision_change"
	)
	var invalidation_payload: Dictionary = invalidation.to_detached_dict()
	_equal(
		invalidation_payload.get("schema_id"),
		CONTRACT.INVALIDATION_SCHEMA_ID,
		"invalidation has an explicit schema"
	)
	_equal(
		invalidation_payload.get("changed_scopes"),
		["a_scope", "z_scope"],
		"invalidation scopes are deterministic"
	)
	_equal(
		invalidation_payload.get("cause_id"),
		"event:synthetic_revision_change",
		"invalidation retains its cause ID"
	)
	_check(not invalidation_payload.has("records"), "invalidation does not carry replacement truth")
	(invalidation_payload.get("changed_scopes") as Array).append("tampered")
	_equal(
		invalidation.changed_scopes(),
		["a_scope", "z_scope"],
		"invalidation payload is detached"
	)


func _test_query_port_boundary() -> void:
	var response: VNextObservationResponse = QUERY_PORT.new().query(null)
	_equal(response.status(), CONTRACT.STATUS_QUERY_UNAVAILABLE, "base query port fails closed")
	_equal(response.records().size(), 0, "base query port returns no records")
	_check(response.is_stale(), "unavailable base query is marked stale")


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
