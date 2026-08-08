extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_event_stable_id_contract()
	_test_duplicate_rejection()
	_test_reveal_and_read_flow()
	_test_unknown_failures_do_not_pollute_state()
	_test_deterministic_snapshot()
	_test_snapshot_restore_round_trip()
	_test_json_round_trip()
	_test_transactional_restore()
	print("VNext event knowledge: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_event_stable_id_contract() -> void:
	var state := VNextEventKnowledgeState.new("person:player_one")
	_check(VNextStableId.is_valid("event:rail_delay"), "event stable ID is accepted by shared validator")
	_equal(VNextStableId.kind_of("event:rail_delay"), "event", "event stable ID keeps event kind")
	_check(state.record_event("event:rail_delay", 15), "valid event stable ID can be recorded")
	var before_invalid: Dictionary = state.snapshot()
	_check(not state.record_event("person:not_an_event", 16), "non-event stable ID is rejected")
	_check(not state.record_event("event:BadLocalId", 16), "invalid event local ID is rejected")
	_check(not state.record_event("event:negative_time", -1), "negative occurrence time is rejected")
	_equal(state.snapshot(), before_invalid, "invalid event records leave state unchanged")


func _test_duplicate_rejection() -> void:
	var state := VNextEventKnowledgeState.new("person:player_one")
	_check(state.record_event("event:market_open", 20), "duplicate fixture event is recorded once")
	var before_duplicate: Dictionary = state.snapshot()
	_check(not state.record_event("event:market_open", 99), "duplicate event ID is rejected")
	_equal(state.snapshot(), before_duplicate, "duplicate rejection preserves original event record")
	_equal(
		_event_record(state.snapshot(), "event:market_open").get("occurred_at_minutes"),
		20,
		"duplicate cannot overwrite occurrence time"
	)


func _test_reveal_and_read_flow() -> void:
	var state := VNextEventKnowledgeState.new("person:player_one")
	_check(state.record_event("event:factory_notice", 30), "reveal fixture event is recorded")
	_check(not state.knows_event("event:factory_notice"), "recorded event starts unknown to player")
	_check(not state.has_read_event("event:factory_notice"), "recorded event starts unread")
	_check(state.reveal_event("event:factory_notice"), "recorded event can be revealed")
	_check(state.knows_event("event:factory_notice"), "reveal makes event known")
	_check(not state.has_read_event("event:factory_notice"), "known event remains unread until explicit read")
	_check(state.mark_event_read("event:factory_notice"), "known event can be marked read")
	_check(state.has_read_event("event:factory_notice"), "read state is stored separately")
	_check(state.reveal_event("event:factory_notice"), "reveal is idempotent for an already-known event")
	_check(state.mark_event_read("event:factory_notice"), "read is idempotent for an already-read event")


func _test_unknown_failures_do_not_pollute_state() -> void:
	var state := VNextEventKnowledgeState.new("person:player_one")
	_check(state.record_event("event:known_truth", 40), "failure fixture contains one authoritative event")
	var before_failures: Dictionary = state.snapshot()
	_check(not state.reveal_event("event:not_recorded"), "unrecorded event cannot be revealed")
	_check(not state.mark_event_read("event:known_truth"), "unknown event cannot be marked read")
	_check(not state.mark_event_read("event:not_recorded"), "unrecorded event cannot be marked read")
	_equal(state.snapshot(), before_failures, "failed reveal/read operations do not pollute state")


func _test_deterministic_snapshot() -> void:
	var first := VNextEventKnowledgeState.new("person:player_one")
	var second := VNextEventKnowledgeState.new("person:player_one")
	_check(first.record_event("event:zeta", 80), "first deterministic state records zeta")
	_check(first.record_event("event:alpha", 10), "first deterministic state records alpha")
	_check(second.record_event("event:alpha", 10), "second deterministic state records alpha first")
	_check(second.record_event("event:zeta", 80), "second deterministic state records zeta second")
	_check(first.reveal_event("event:zeta"), "first deterministic state reveals zeta")
	_check(first.reveal_event("event:alpha"), "first deterministic state reveals alpha")
	_check(second.reveal_event("event:alpha"), "second deterministic state reveals alpha first")
	_check(second.reveal_event("event:zeta"), "second deterministic state reveals zeta second")
	_check(first.mark_event_read("event:zeta"), "first deterministic state reads zeta")
	_check(second.mark_event_read("event:zeta"), "second deterministic state reads zeta")
	_equal(first.snapshot(), second.snapshot(), "equivalent states produce equal deterministic snapshots")
	_equal(
		JSON.stringify(first.snapshot()),
		JSON.stringify(second.snapshot()),
		"deterministic snapshot also has stable JSON ordering"
	)
	var sorted_records: Array = first.snapshot().get("event_records", []) as Array
	_equal(
		(sorted_records[0] as Dictionary).get("event_id"),
		"event:alpha",
		"event records are emitted in event-ID order"
	)


func _test_snapshot_restore_round_trip() -> void:
	var source := VNextEventKnowledgeState.new("person:player_one")
	_check(source.record_event("event:letter_arrived", 120), "snapshot source records first event")
	_check(source.record_event("event:meeting_called", 121), "snapshot source records second event")
	_check(source.reveal_event("event:letter_arrived"), "snapshot source reveals first event")
	_check(source.mark_event_read("event:letter_arrived"), "snapshot source reads first event")
	_check(source.reveal_event("event:meeting_called"), "snapshot source reveals second event")
	var saved: Dictionary = source.snapshot()

	var restored := VNextEventKnowledgeState.new("person:other_player")
	_check(restored.record_event("event:temporary", 999), "restore target can start with different state")
	_check(restored.restore(saved), "valid event knowledge snapshot restores")
	_equal(restored.player_id(), "person:player_one", "restore recovers player owner")
	_equal(restored.snapshot(), saved, "snapshot restore preserves complete state")
	_check(restored.knows_event("event:meeting_called"), "known event survives restore")
	_check(restored.has_read_event("event:letter_arrived"), "read event survives restore")


func _test_json_round_trip() -> void:
	var source := VNextEventKnowledgeState.new("person:player_one")
	_check(source.record_event("event:json_boundary", 137), "JSON source records event")
	_check(source.reveal_event("event:json_boundary"), "JSON source reveals event")
	_check(source.mark_event_read("event:json_boundary"), "JSON source reads event")
	var source_snapshot: Dictionary = source.snapshot()
	var serialized_snapshot: String = JSON.stringify(source_snapshot)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized_snapshot)
	_equal(parse_error, OK, "event knowledge JSON snapshot parses")
	if parse_error != OK:
		return
	var parsed_value: Variant = parser.data
	_check(typeof(parsed_value) == TYPE_DICTIONARY, "JSON parse returns event knowledge Dictionary")
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return
	var parsed_snapshot: Dictionary = parsed_value
	var parsed_records: Array = parsed_snapshot.get("event_records", []) as Array
	_equal(
		typeof((parsed_records[0] as Dictionary).get("occurred_at_minutes")),
		TYPE_FLOAT,
		"JSON occurrence minutes cross serialization boundary as float"
	)
	var restored := VNextEventKnowledgeState.new("person:restore_target")
	_check(restored.restore(parsed_snapshot), "JSON-parsed event knowledge snapshot restores")
	_equal(restored.snapshot(), source_snapshot, "JSON round trip preserves event knowledge business state")


func _test_transactional_restore() -> void:
	var state := VNextEventKnowledgeState.new("person:player_one")
	_check(state.record_event("event:restore_guard", 200), "restore guard event is recorded")
	_check(state.reveal_event("event:restore_guard"), "restore guard event is known")
	var before: Dictionary = state.snapshot()

	var invalid_read: Dictionary = before.duplicate(true)
	invalid_read["read_event_ids"] = ["event:not_known"]
	_check(not state.restore(invalid_read), "restore rejects read event that is not known")
	_equal(state.snapshot(), before, "failed read-set restore is transactional")

	var invalid_player: Dictionary = before.duplicate(true)
	invalid_player["player_id"] = "place:not_a_person"
	_check(not state.restore(invalid_player), "restore rejects non-person player stable ID")
	_equal(state.snapshot(), before, "failed player restore is transactional")

	var fractional_time: Dictionary = before.duplicate(true)
	var fractional_records: Array = fractional_time.get("event_records", []) as Array
	(fractional_records[0] as Dictionary)["occurred_at_minutes"] = 200.5
	_check(not state.restore(fractional_time), "restore rejects fractional occurrence minutes")
	_equal(state.snapshot(), before, "failed numeric restore is transactional")


func _event_record(snapshot_value: Dictionary, event_id: String) -> Dictionary:
	for raw_record: Variant in snapshot_value.get("event_records", []) as Array:
		if raw_record is Dictionary and str((raw_record as Dictionary).get("event_id", "")) == event_id:
			return (raw_record as Dictionary).duplicate(true)
	return {}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
