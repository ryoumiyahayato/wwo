class_name VNextWorldTransactionCoordinator
extends RefCounted

var _world_revision: int = 0
var _participants: Dictionary = {}
var _cross_domain_validators: Array[VNextTransactionValidator] = []
var _conservation_validators: Array[VNextTransactionValidator] = []
var _commit_barrier_active: bool = false


func world_revision() -> int:
	return _world_revision


func register_participant(participant: VNextTransactionParticipant) -> bool:
	if participant == null:
		return false
	var participant_id: String = participant.participant_id()
	if not VNextTransactionContract.is_valid_identity(participant_id):
		return false
	if _participants.has(participant_id):
		return false
	_participants[participant_id] = participant
	return true


func add_cross_domain_validator(validator: VNextTransactionValidator) -> bool:
	if validator == null:
		return false
	_cross_domain_validators.append(validator)
	return true


func add_conservation_validator(validator: VNextTransactionValidator) -> bool:
	if validator == null:
		return false
	_conservation_validators.append(validator)
	return true


func execute(command: VNextTransactionCommand) -> VNextTransactionResult:
	var revision_before: int = _world_revision
	if command == null:
		return _failure(null, VNextTransactionContract.FAILURE_MALFORMED_COMMAND, [], "", {})
	var participant_ids: Array[String] = command.required_participant_ids()
	if command.validation_failure() != VNextTransactionContract.FAILURE_NONE:
		return _failure(command, command.validation_failure(), participant_ids, "", {})
	if command.expected_world_revision() != _world_revision:
		return _failure(command, VNextTransactionContract.FAILURE_STALE_REVISION, participant_ids, "", {})
	for participant_id: String in participant_ids:
		if not _participants.has(participant_id):
			return _failure(command, VNextTransactionContract.FAILURE_MISSING_PARTICIPANT, participant_ids, "", {})

	var before_snapshots: Dictionary = {}
	var candidates: Dictionary = {}
	for participant_id: String in participant_ids:
		var participant: VNextTransactionParticipant = _participants[participant_id]
		var before_snapshot: Variant = participant.authoritative_snapshot()
		if not VNextTransactionContract.is_detachable_value(before_snapshot):
			return _failure(command, VNextTransactionContract.FAILURE_PREPARE, participant_ids, "", {})
		before_snapshots[participant_id] = VNextTransactionContract.detached_copy(before_snapshot)
		var prepared: Dictionary = participant.prepare_candidate(command)
		if not bool(prepared.get("ok", false)) or not prepared.has("candidate"):
			return _failure(command, VNextTransactionContract.FAILURE_PREPARE, participant_ids, "", {})
		var candidate: Variant = prepared.get("candidate")
		if not VNextTransactionContract.is_detachable_value(candidate):
			return _failure(command, VNextTransactionContract.FAILURE_PREPARE, participant_ids, "", {})
		candidates[participant_id] = VNextTransactionContract.detached_copy(candidate)

	var bundle := VNextTransactionCandidateBundle.new()
	if not bundle.configure(command, participant_ids, before_snapshots, candidates):
		return _failure(command, VNextTransactionContract.FAILURE_PREPARE, participant_ids, "", {})
	var fingerprint: String = bundle.fingerprint()
	var detached_bundle: Dictionary = bundle.to_detached_dict()

	for participant_id: String in participant_ids:
		var participant: VNextTransactionParticipant = _participants[participant_id]
		if not participant.validate_candidate(bundle.candidate_for(participant_id), command):
			return _failure(command, VNextTransactionContract.FAILURE_LOCAL_VALIDATION, participant_ids, fingerprint, detached_bundle)
	for validator: VNextTransactionValidator in _cross_domain_validators:
		if not validator.validate(command, bundle):
			return _failure(command, VNextTransactionContract.FAILURE_CROSS_DOMAIN_VALIDATION, participant_ids, fingerprint, detached_bundle)
	for validator: VNextTransactionValidator in _conservation_validators:
		if not validator.validate(command, bundle):
			return _failure(command, VNextTransactionContract.FAILURE_CONSERVATION_VALIDATION, participant_ids, fingerprint, detached_bundle)

	# No participant may observe another participant half-adopted: synchronous adopt
	# runs behind this barrier and participant implementations may not callback or fail.
	_commit_barrier_active = true
	for participant_id: String in participant_ids:
		var participant: VNextTransactionParticipant = _participants[participant_id]
		participant.adopt_candidate(bundle.candidate_for(participant_id))
	_commit_barrier_active = false
	_world_revision = revision_before + 1
	var result := VNextTransactionResult.new()
	result.configure(
		VNextTransactionContract.STATUS_COMMITTED,
		VNextTransactionContract.FAILURE_NONE,
		command.transaction_id(),
		command.command_id(),
		revision_before,
		_world_revision,
		participant_ids,
		fingerprint,
		detached_bundle
	)
	return result


func authoritative_fingerprint() -> String:
	var participant_ids: Array[String] = []
	for participant_id: Variant in _participants.keys():
		participant_ids.append(str(participant_id))
	participant_ids.sort()
	var snapshots: Dictionary = {}
	for participant_id: String in participant_ids:
		var participant: VNextTransactionParticipant = _participants[participant_id]
		snapshots[participant_id] = VNextTransactionContract.detached_copy(
			participant.authoritative_snapshot()
		)
	return VNextTransactionContract.fingerprint_for(
		{"participants": snapshots, "world_revision": _world_revision}
	)


func commit_barrier_active() -> bool:
	return _commit_barrier_active


func _failure(
	command: VNextTransactionCommand,
	failure_code: String,
	participant_ids: Array[String],
	candidate_fingerprint: String,
	candidate_bundle: Dictionary
) -> VNextTransactionResult:
	var result := VNextTransactionResult.new()
	result.configure(
		VNextTransactionContract.STATUS_REJECTED,
		failure_code,
		"" if command == null else command.transaction_id(),
		"" if command == null else command.command_id(),
		_world_revision,
		_world_revision,
		participant_ids,
		candidate_fingerprint,
		candidate_bundle
	)
	return result
