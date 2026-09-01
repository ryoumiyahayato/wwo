extends SceneTree

const CONTRACT = preload("res://scripts/vnext/transactions/transaction_contract.gd")
const COMMAND = preload("res://scripts/vnext/transactions/transaction_command.gd")
const COORDINATOR = preload("res://scripts/vnext/transactions/world_transaction_coordinator.gd")
const PARTICIPANT = preload("res://scripts/vnext/transactions/synthetic_transaction_participant.gd")
const CROSS_VALIDATOR = preload("res://scripts/vnext/transactions/synthetic_cross_domain_validator.gd")
const CONSERVATION_VALIDATOR = preload("res://scripts/vnext/transactions/synthetic_conservation_validator.gd")

var checks: int = 0
var failures: int = 0
var transaction_sequence: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_single_participant_success()
	_test_multiple_participant_success_and_revision_once()
	_test_deterministic_participant_order_and_fingerprint()
	_test_detached_candidates_and_result()
	_test_prepare_failure_atomicity()
	_test_local_validation_failure_atomicity()
	_test_cross_domain_validation_failure_atomicity()
	_test_conservation_failure_atomicity()
	_test_stale_revision_atomicity()
	_test_missing_participant_atomicity()
	_test_duplicate_participant()
	_test_malformed_command()
	_test_failed_revision_unchanged()
	_test_no_half_committed_observable_state()
	print("VNext world transaction coordinator: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_single_participant_success() -> void:
	var fixture: Dictionary = _fixture(["account_a"])
	var coordinator: VNextWorldTransactionCoordinator = fixture.coordinator
	var participant: VNextSyntheticTransactionParticipant = fixture.participants["account_a"]
	var result: VNextTransactionResult = coordinator.execute(
		_command(
			coordinator.world_revision(),
			["account_a"],
			{"account_a": 0},
			"stable_single_transaction",
			"synthetic_transfer"
		)
	)
	_check(result.is_success(), "single participant transaction commits")
	_equal(result.transaction_id(), "stable_single_transaction", "result preserves stable transaction identity")
	_equal(result.command_id(), "synthetic_transfer", "result preserves stable command identity")
	_equal(result.failure_code(), CONTRACT.FAILURE_NONE, "successful result has explicit no-failure code")
	_equal(participant.value(), 100, "single participant candidate is adopted")
	_equal(result.world_revision_before(), 0, "successful result records base revision")
	_equal(result.world_revision_after(), 1, "successful result records advanced revision")


func _test_multiple_participant_success_and_revision_once() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	var coordinator: VNextWorldTransactionCoordinator = fixture.coordinator
	var participants: Dictionary = fixture.participants
	var result: VNextTransactionResult = coordinator.execute(
		_command(0, ["account_b", "account_a"], {"account_a": -20, "account_b": 20})
	)
	_check(result.is_success(), "multiple participant transfer commits")
	_equal(participants["account_a"].value(), 80, "transfer debits A")
	_equal(participants["account_b"].value(), 70, "transfer credits B")
	_equal(participants["account_a"].value() + participants["account_b"].value(), 150, "legal transfer conserves total")
	_equal(coordinator.world_revision(), 1, "successful commit advances world revision exactly once")
	_equal(participants["account_a"].adopt_count(), 1, "first participant adopts exactly once")
	_equal(participants["account_b"].adopt_count(), 1, "second participant adopts exactly once")


func _test_deterministic_participant_order_and_fingerprint() -> void:
	var forward: Dictionary = _fixture(["account_a", "account_b"])
	var reverse: Dictionary = _fixture(["account_b", "account_a"])
	var forward_order: Array[String] = []
	var reverse_order: Array[String] = []
	forward.participants["account_a"].use_shared_prepare_order_log(forward_order)
	forward.participants["account_b"].use_shared_prepare_order_log(forward_order)
	reverse.participants["account_a"].use_shared_prepare_order_log(reverse_order)
	reverse.participants["account_b"].use_shared_prepare_order_log(reverse_order)
	var forward_result: VNextTransactionResult = forward.coordinator.execute(
		_command(0, ["account_b", "account_a"], {"account_b": 20, "account_a": -20}, "stable_tx", "transfer")
	)
	var reverse_result: VNextTransactionResult = reverse.coordinator.execute(
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20}, "stable_tx", "transfer")
	)
	_equal(forward_result.participant_ids(), ["account_a", "account_b"], "participant execution order is canonical")
	_equal(reverse_result.participant_ids(), ["account_a", "account_b"], "registration order cannot change execution order")
	_equal(forward_order, ["account_a", "account_b"], "prepare calls follow canonical participant order")
	_equal(reverse_order, ["account_a", "account_b"], "registration order cannot change prepare call order")
	_equal(forward_result.candidate_fingerprint(), reverse_result.candidate_fingerprint(), "registration and input order do not affect candidate fingerprint")
	_equal(forward_result.to_detached_dict(), reverse_result.to_detached_dict(), "registration and input order do not affect result")


func _test_detached_candidates_and_result() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	var coordinator: VNextWorldTransactionCoordinator = fixture.coordinator
	var result: VNextTransactionResult = coordinator.execute(
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20})
	)
	var exposed_bundle: Dictionary = result.candidate_bundle()
	var exposed_candidates: Dictionary = exposed_bundle["candidates"]
	var exposed_a: Dictionary = exposed_candidates["account_a"]
	exposed_a["value"] = 999
	exposed_candidates["account_a"] = exposed_a
	exposed_bundle["candidates"] = exposed_candidates
	_equal(fixture.participants["account_a"].value(), 80, "mutating returned candidate cannot mutate authority")
	_equal(result.candidate_bundle()["candidates"]["account_a"]["value"], 80, "result returns a fresh detached candidate copy")
	_check(not result.candidate_fingerprint().is_empty(), "committed candidate has deterministic fingerprint")


func _test_prepare_failure_atomicity() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	fixture.participants["account_b"].set_prepare_failure(true)
	_assert_atomic_failure(
		fixture,
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20}),
		CONTRACT.FAILURE_PREPARE,
		"prepare failure"
	)


func _test_local_validation_failure_atomicity() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	fixture.participants["account_b"].set_local_validation_failure(true)
	_assert_atomic_failure(
		fixture,
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20}),
		CONTRACT.FAILURE_LOCAL_VALIDATION,
		"local validation failure"
	)


func _test_cross_domain_validation_failure_atomicity() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	var command: VNextTransactionCommand = _command(
		0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20}
	)
	var payload: Dictionary = command.payload()
	payload["reject_cross_domain"] = true
	command = _command_with_payload(0, ["account_a", "account_b"], payload)
	_assert_atomic_failure(fixture, command, CONTRACT.FAILURE_CROSS_DOMAIN_VALIDATION, "cross-domain validation failure")


func _test_conservation_failure_atomicity() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	_assert_atomic_failure(
		fixture,
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 30}),
		CONTRACT.FAILURE_CONSERVATION_VALIDATION,
		"conservation failure closes before manufactured resources commit"
	)


func _test_stale_revision_atomicity() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	_assert_atomic_failure(
		fixture,
		_command(7, ["account_a", "account_b"], {"account_a": -20, "account_b": 20}),
		CONTRACT.FAILURE_STALE_REVISION,
		"stale revision"
	)


func _test_missing_participant_atomicity() -> void:
	var fixture: Dictionary = _fixture(["account_a"])
	_assert_atomic_failure(
		fixture,
		_command(0, ["account_a", "account_missing"], {"account_a": -20, "account_missing": 20}),
		CONTRACT.FAILURE_MISSING_PARTICIPANT,
		"required participant gate"
	)


func _test_duplicate_participant() -> void:
	var fixture: Dictionary = _fixture(["account_a"])
	_check(not fixture.coordinator.register_participant(fixture.participants["account_a"]), "duplicate participant registration is rejected")
	var duplicate_command := COMMAND.new()
	_check(not duplicate_command.configure("duplicate_tx", "transfer", 0, ["account_a", "account_a"], {"deltas": {"account_a": 0}}), "duplicate required participant command is invalid")
	_assert_atomic_failure(fixture, duplicate_command, CONTRACT.FAILURE_DUPLICATE_PARTICIPANT, "duplicate required participant")


func _test_malformed_command() -> void:
	var fixture: Dictionary = _fixture(["account_a"])
	var malformed := COMMAND.new()
	_check(not malformed.configure("Bad Transaction", "transfer", 0, ["account_a"], {"deltas": {"account_a": 0}}), "malformed stable transaction identity is rejected")
	_assert_atomic_failure(fixture, malformed, CONTRACT.FAILURE_MALFORMED_COMMAND, "malformed command")


func _test_failed_revision_unchanged() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	var coordinator: VNextWorldTransactionCoordinator = fixture.coordinator
	var success: VNextTransactionResult = coordinator.execute(
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20})
	)
	_check(success.is_success(), "setup commit succeeds before revision failure check")
	var revision_before_failure: int = coordinator.world_revision()
	var result: VNextTransactionResult = coordinator.execute(
		_command(0, ["account_a", "account_b"], {"account_a": 20, "account_b": -20})
	)
	_equal(result.failure_code(), CONTRACT.FAILURE_STALE_REVISION, "second command fails on stale expected revision")
	_equal(coordinator.world_revision(), revision_before_failure, "failed transaction leaves nonzero revision unchanged")


func _test_no_half_committed_observable_state() -> void:
	var fixture: Dictionary = _fixture(["account_a", "account_b"])
	fixture.participants["account_b"].set_local_validation_failure(true)
	var result: VNextTransactionResult = fixture.coordinator.execute(
		_command(0, ["account_a", "account_b"], {"account_a": -20, "account_b": 20})
	)
	_check(not result.is_success(), "transaction fails before commit barrier")
	_equal(fixture.participants["account_a"].adopt_count(), 0, "earlier participant is never half-committed")
	_equal(fixture.participants["account_b"].adopt_count(), 0, "failing participant is never adopted")
	_check(not fixture.coordinator.commit_barrier_active(), "commit barrier is closed after transaction returns")


func _fixture(registration_order: Array[String]) -> Dictionary:
	var coordinator := COORDINATOR.new()
	var participants: Dictionary = {
		"account_a": _participant("account_a", 100),
		"account_b": _participant("account_b", 50),
	}
	for participant_id: String in registration_order:
		_check(coordinator.register_participant(participants[participant_id]), "fixture registers %s" % participant_id)
	_check(coordinator.add_cross_domain_validator(CROSS_VALIDATOR.new()), "fixture registers cross-domain validator")
	_check(coordinator.add_conservation_validator(CONSERVATION_VALIDATOR.new()), "fixture registers conservation validator")
	return {"coordinator": coordinator, "participants": participants}


func _participant(participant_id: String, value: int) -> VNextSyntheticTransactionParticipant:
	var participant := PARTICIPANT.new()
	_check(participant.configure(participant_id, value), "synthetic participant configures: %s" % participant_id)
	return participant


func _command(
	revision: int,
	participant_ids: Array[String],
	deltas: Dictionary,
	transaction_id: String = "",
	command_id: String = "transfer"
) -> VNextTransactionCommand:
	return _command_with_payload(revision, participant_ids, {"deltas": deltas}, transaction_id, command_id)


func _command_with_payload(
	revision: int,
	participant_ids: Array[String],
	payload: Dictionary,
	transaction_id: String = "",
	command_id: String = "transfer"
) -> VNextTransactionCommand:
	transaction_sequence += 1
	var resolved_transaction_id: String = transaction_id
	if resolved_transaction_id.is_empty():
		resolved_transaction_id = "transaction_%d" % transaction_sequence
	var command := COMMAND.new()
	_check(
		command.configure(resolved_transaction_id, command_id, revision, participant_ids, payload),
		"valid command configures: %s" % resolved_transaction_id
	)
	return command


func _assert_atomic_failure(
	fixture: Dictionary,
	command: VNextTransactionCommand,
	expected_failure: String,
	label: String
) -> void:
	var coordinator: VNextWorldTransactionCoordinator = fixture.coordinator
	var hash_before: String = coordinator.authoritative_fingerprint()
	var revision_before: int = coordinator.world_revision()
	var adopt_counts_before: Dictionary = {}
	for participant_id: Variant in fixture.participants.keys():
		adopt_counts_before[participant_id] = fixture.participants[participant_id].adopt_count()
	var result: VNextTransactionResult = coordinator.execute(command)
	_check(not result.is_success(), "%s returns rejected result" % label)
	_equal(result.failure_code(), expected_failure, "%s has explicit failure code" % label)
	_equal(coordinator.authoritative_fingerprint(), hash_before, "%s preserves authoritative hash" % label)
	_equal(coordinator.world_revision(), revision_before, "%s preserves world revision" % label)
	for participant_id: Variant in fixture.participants.keys():
		_equal(fixture.participants[participant_id].adopt_count(), adopt_counts_before[participant_id], "%s does not adopt %s" % [label, participant_id])


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
