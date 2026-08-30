class_name VNextSyntheticObservationProvider
extends VNextObservationQueryPort

## Deterministic in-memory fixture. Only filtered detached DTOs cross the port;
## the fixture itself has no owner or state escape hatch.

const FIELD = preload("res://scripts/vnext/observation/observed_field.gd")
const RECORD = preload("res://scripts/vnext/observation/observation_record.gd")
const INVALIDATION = preload("res://scripts/vnext/observation/observation_invalidation.gd")

const OBSERVER_A_ID: String = "person:observer_a"
const OBSERVER_B_ID: String = "person:observer_b"
const QA_OBSERVER_ID: String = "person:qa_observer"
const SUBJECT_X_ID: String = "person:subject_x"

const PUBLIC_FIELD_ID: String = "public_field"
const RESTRICTED_FIELD_ID: String = "restricted_field"
const HIDDEN_FIELD_ID: String = "hidden_field"

const INITIAL_WORLD_REVISION: int = 10
const INITIAL_OBSERVED_AT: int = 1000

var _visibility_resolver: VNextObservationVisibilityResolver = null
var _world_revision: int = INITIAL_WORLD_REVISION
var _observed_at: int = INITIAL_OBSERVED_AT
var _truth_by_subject: Dictionary = {}
var _capture_hook: Callable = Callable()


func _init(visibility_resolver: VNextObservationVisibilityResolver = null) -> void:
	_visibility_resolver = visibility_resolver
	_truth_by_subject = _build_fixture()


func query(request: VNextObservationRequest) -> VNextObservationResponse:
	if request == null or not request.is_valid():
		return VNextObservationResponse.failure(
			CONTRACT.STATUS_INVALID_REQUEST,
			"" if request == null else request.observer_actor_id(),
			_world_revision,
			_observed_at,
			"request_invalid"
		)
	var observer_actor_id: String = request.observer_actor_id()
	if request.scope() != "person":
		return VNextObservationResponse.failure(
			CONTRACT.STATUS_INVALID_REQUEST,
			observer_actor_id,
			_world_revision,
			_observed_at,
			"unsupported_scope"
		)
	if _visibility_resolver == null:
		return VNextObservationResponse.failure(
			CONTRACT.STATUS_VISIBILITY_UNAVAILABLE,
			observer_actor_id,
			_world_revision,
			_observed_at,
			"visibility_resolver_required"
		)
	if not _visibility_resolver.is_known_observer(observer_actor_id):
		return VNextObservationResponse.failure(
			CONTRACT.STATUS_UNKNOWN_OBSERVER,
			observer_actor_id,
			_world_revision,
			_observed_at,
			"observer_not_registered"
		)
	if (
		request.expected_world_revision() != CONTRACT.UNSPECIFIED_WORLD_REVISION
		and request.expected_world_revision() != _world_revision
	):
		return VNextObservationResponse.failure(
			CONTRACT.STATUS_REVISION_MISMATCH,
			observer_actor_id,
			_world_revision,
			_observed_at,
			"expected_world_revision_mismatch"
		)

	# Capture one revision and one detached truth copy before any hook can run.
	var captured_revision: int = _world_revision
	var captured_observed_at: int = _observed_at
	var captured_truth: Dictionary = _truth_by_subject.duplicate(true)
	if _capture_hook.is_valid():
		_capture_hook.call()

	var records: Array[VNextObservationRecord] = []
	for subject_id: String in request.subject_ids():
		var subject_fields_value: Variant = captured_truth.get(subject_id, {})
		if typeof(subject_fields_value) != TYPE_DICTIONARY:
			continue
		var subject_fields: Dictionary = subject_fields_value as Dictionary
		var field_ids: Array = subject_fields.keys()
		field_ids.sort()
		var visible_fields: Array[VNextObservedField] = []
		for field_id_value: Variant in field_ids:
			if typeof(field_id_value) != TYPE_STRING:
				continue
			var field_id: String = field_id_value as String
			if not request.requests_field(field_id):
				continue
			var field_definition: Dictionary = subject_fields.get(field_id, {}) as Dictionary
			if not _can_return_field(request, subject_id, field_id, field_definition):
				continue
			var field: VNextObservedField = _field_from_definition(field_id, field_definition)
			if field != null:
				visible_fields.append(field)
		if visible_fields.is_empty():
			continue
		var record := VNextObservationRecord.new()
		if record.configure(subject_id, captured_revision, visible_fields):
			records.append(record)

	var stale_after_capture: bool = _world_revision != captured_revision
	return VNextObservationResponse.success(
		captured_revision,
		observer_actor_id,
		captured_observed_at,
		records,
		stale_after_capture
	)


func advance_world_revision(new_revision: int) -> VNextObservationInvalidation:
	if new_revision <= _world_revision:
		return null
	_world_revision = new_revision
	_observed_at += 1
	var invalidation := VNextObservationInvalidation.new()
	if not invalidation.configure(
		_world_revision,
		["person"],
		"event:synthetic_revision_change"
	):
		return null
	return invalidation


func current_world_revision() -> int:
	return _world_revision


func set_capture_hook(hook: Callable) -> bool:
	if not hook.is_valid():
		return false
	_capture_hook = hook
	return true


func clear_capture_hook() -> void:
	_capture_hook = Callable()


func invalidation_for_change(
	changed_scopes: Array[String],
	cause_id: String
) -> VNextObservationInvalidation:
	var invalidation := VNextObservationInvalidation.new()
	if not invalidation.configure(_world_revision, changed_scopes, cause_id):
		return null
	return invalidation


func _can_return_field(
	request: VNextObservationRequest,
	subject_id: String,
	field_id: String,
	field_definition: Dictionary
) -> bool:
	var required_capability: String = str(field_definition.get("required_capability", ""))
	if not required_capability.is_empty() and not request.requests_capability(required_capability):
		return false
	return _visibility_resolver.can_observe(
		request.observer_actor_id(),
		subject_id,
		field_id,
		required_capability
	)


func _field_from_definition(field_id: String, field_definition: Dictionary) -> VNextObservedField:
	var field := VNextObservedField.new()
	if not field.configure(
		field_id,
		field_definition.get("perceived_value"),
		field_definition.get("confidence", 0.0),
		field_definition.get("acquired_at", 0),
		field_definition.get("observed_state_at", 0),
		field_definition.get("provenance_references", []),
		field_definition.get("freshness", CONTRACT.FRESHNESS_UNKNOWN),
		field_definition.get("extensions", {})
	):
		return null
	return field


func _build_fixture() -> Dictionary:
	return {
		SUBJECT_X_ID: {
			PUBLIC_FIELD_ID: {
				"perceived_value": {
					"label": "public-value",
					"nested": {"counter": 1},
				},
				"confidence": 0.98,
				"acquired_at": 200,
				"observed_state_at": 150,
				"provenance_references": ["synthetic.source.public"],
				"freshness": CONTRACT.FRESHNESS_FRESH,
				"required_capability": "",
				"visibility": "public",
			},
			RESTRICTED_FIELD_ID: {
				"perceived_value": {
					"label": "restricted-value",
					"nested": {"counter": 2},
				},
				"confidence": 0.81,
				"acquired_at": 210,
				"observed_state_at": 180,
				"provenance_references": ["synthetic.source.restricted"],
				"freshness": CONTRACT.FRESHNESS_STALE,
				"required_capability": CONTRACT.RESTRICTED_CAPABILITY,
				"visibility": "restricted",
			},
			HIDDEN_FIELD_ID: {
				"perceived_value": "hidden-authoritative-value",
				"confidence": 1.0,
				"acquired_at": 220,
				"observed_state_at": 190,
				"provenance_references": ["synthetic.source.hidden"],
				"freshness": CONTRACT.FRESHNESS_FRESH,
				"required_capability": CONTRACT.TRUTH_CAPABILITY,
				"visibility": "hidden",
			},
		},
	}
