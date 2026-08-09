extends SceneTree

const PLAYER_ID: String = "person:runtime_player"
const OTHER_PLAYER_ID: String = "person:other_player"
const START_PLACE_ID: String = "place:runtime_home"
const OTHER_PLACE_ID: String = "place:runtime_factory"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_empty_restore_shell()
	_test_composition_and_identity()
	_test_advance_minutes_and_json_safe_bound()
	_test_snapshot_contract()
	_test_snapshot_round_trip()
	_test_json_snapshot_round_trip()
	_test_event_occurrence_uses_runtime_time()
	_test_identity_mismatch_is_rejected_transactionally()
	_test_v1_snapshot_is_not_migrated()
	print("VNext world runtime v2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_empty_restore_shell() -> void:
	var runtime := VNextWorldRuntime.new()
	_check(not runtime.is_valid(), "empty runtime shell is not a valid composition")
	_check(not runtime.advance_minutes(1), "empty runtime cannot advance time")
	_equal(runtime.total_minutes(), 0, "empty runtime shell starts at zero minutes")
	_equal(
		runtime.snapshot().get("schema_id"),
		"vnext_world_runtime_v2",
		"empty runtime still exposes the v2 snapshot schema"
	)


func _test_composition_and_identity() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return

	_check(runtime.is_valid(), "created runtime is a valid composition")
	_check(runtime.is_initialized(), "created runtime reports initialized")
	_equal(runtime.player_id(), PLAYER_ID, "runtime exposes the player owner ID")
	_equal(runtime.player().player_id(), PLAYER_ID, "player owner keeps the person ID")
	_equal(runtime.wallet().owner_id(), PLAYER_ID, "wallet owner matches the player ID")
	_equal(runtime.location().player_id(), PLAYER_ID, "location owner matches the player ID")
	_equal(
		runtime.event_knowledge().player_id(),
		PLAYER_ID,
		"event knowledge owner matches the player ID"
	)
	_equal(runtime.location().place_id(), START_PLACE_ID, "location owner starts at the configured place")

	var invalid := VNextWorldRuntime.create("place:not_a_person", START_PLACE_ID)
	_check(invalid == null, "invalid person identity cannot create a runtime")
	var invalid_place := VNextWorldRuntime.create(PLAYER_ID, "person:not_a_place")
	_check(invalid_place == null, "invalid place identity cannot create a runtime")


func _test_advance_minutes_and_json_safe_bound() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return

	_check(runtime.advance_minutes(15), "positive minute advance succeeds")
	_equal(runtime.total_minutes(), 15, "positive minute advance accumulates")
	_check(runtime.advance_minutes(45), "second minute advance succeeds")
	_equal(runtime.total_minutes(), 60, "multiple advances use one runtime clock")
	_check(not runtime.advance_minutes(0), "zero minute advance is rejected")
	_check(not runtime.advance_minutes(-1), "negative minute advance is rejected")

	var maximum_runtime := _new_runtime()
	if maximum_runtime == null:
		return
	_check(
		maximum_runtime.advance_minutes(VNextWorldRuntime.MAX_JSON_SAFE_INTEGER),
		"JSON-safe maximum total_minutes is accepted"
	)
	_equal(
		maximum_runtime.total_minutes(),
		VNextWorldRuntime.MAX_JSON_SAFE_INTEGER,
		"runtime stores the JSON-safe maximum exactly"
	)
	_check(
		not maximum_runtime.advance_minutes(1),
		"advancement beyond JSON-safe maximum is rejected"
	)
	_equal(
		maximum_runtime.total_minutes(),
		VNextWorldRuntime.MAX_JSON_SAFE_INTEGER,
		"overflow rejection leaves total_minutes unchanged"
	)


func _test_snapshot_contract() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.advance_minutes(75), "snapshot fixture can advance")
	_check(runtime.wallet().credit(1250), "snapshot fixture can fund the wallet")
	_check(runtime.record_event("event:runtime_snapshot"), "snapshot fixture can record an event")
	var value: Dictionary = runtime.snapshot()

	_equal(value.size(), 6, "v2 snapshot contains exactly six top-level fields")
	for field_name: String in [
		"schema_id", "total_minutes", "player", "wallet", "location", "event_knowledge",
	]:
		_check(value.has(field_name), "v2 snapshot contains %s" % field_name)
	_equal(value.get("schema_id"), "vnext_world_runtime_v2", "v2 snapshot schema is correct")
	_equal(value.get("total_minutes"), 75, "v2 snapshot contains current total_minutes")
	_equal(
		(value.get("player") as Dictionary).get("player_id"),
		PLAYER_ID,
		"v2 snapshot contains the authoritative player snapshot"
	)
	_equal(
		(value.get("wallet") as Dictionary).get("balance_minor"),
		1250,
		"v2 snapshot contains the wallet snapshot"
	)


func _test_snapshot_round_trip() -> void:
	var source := _new_runtime()
	if source == null:
		return
	_check(source.advance_minutes(137), "round-trip source can advance")
	_check(source.wallet().credit(9876), "round-trip source can fund wallet")
	_check(source.record_event("event:round_trip"), "round-trip source can record event")
	_check(source.reveal_event("event:round_trip"), "round-trip source can reveal event")
	_check(source.mark_event_read("event:round_trip"), "round-trip source can read event")
	var saved: Dictionary = source.snapshot()

	var restored := VNextWorldRuntime.new()
	_check(restored.restore(saved), "valid v2 composition snapshot restore succeeds")
	_equal(restored.total_minutes(), 137, "restore recovers total_minutes")
	_equal(restored.player_id(), PLAYER_ID, "restore recovers player identity")
	_equal(restored.wallet().balance_minor(), 9876, "restore recovers wallet balance")
	_equal(restored.location().place_id(), START_PLACE_ID, "restore recovers location")
	_check(
		restored.event_knowledge().has_read_event("event:round_trip"),
		"restore recovers event knowledge"
	)
	_equal(restored.snapshot(), saved, "v2 snapshot round trip preserves complete state")


func _test_json_snapshot_round_trip() -> void:
	var source := _new_runtime()
	if source == null:
		return
	_check(source.advance_minutes(137), "JSON round-trip source can advance")
	_check(source.wallet().credit(9000000000000), "JSON round-trip source can fund wallet")
	_check(source.record_event("event:json_round_trip"), "JSON round-trip source can record event")
	_check(source.reveal_event("event:json_round_trip"), "JSON round-trip source can reveal event")
	var source_snapshot: Dictionary = source.snapshot()
	var serialized_snapshot: String = JSON.stringify(source_snapshot)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized_snapshot)
	_equal(parse_error, OK, "JSON.stringify v2 snapshot parses with JSON.parse")
	if parse_error != OK:
		return

	var parsed_value: Variant = parser.data
	_check(typeof(parsed_value) == TYPE_DICTIONARY, "JSON.parse returns a v2 snapshot Dictionary")
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return
	var parsed_snapshot: Dictionary = parsed_value
	_equal(
		typeof(parsed_snapshot.get("total_minutes")),
		TYPE_FLOAT,
		"JSON-parsed total_minutes crosses the boundary as float"
	)
	_equal(
		typeof((parsed_snapshot.get("wallet") as Dictionary).get("balance_minor")),
		TYPE_FLOAT,
		"JSON-parsed wallet balance crosses the boundary as float"
	)

	var restored := VNextWorldRuntime.new()
	_check(restored.restore(parsed_snapshot), "JSON-parsed v2 snapshot restore succeeds")
	_equal(restored.total_minutes(), 137, "JSON round trip recovers total_minutes")
	_equal(restored.wallet().balance_minor(), 9000000000000, "JSON round trip recovers wallet balance")
	_equal(
		restored.snapshot(),
		source_snapshot,
		"JSON round trip preserves complete composed business state"
	)


func _test_event_occurrence_uses_runtime_time() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.advance_minutes(35), "event fixture advances through the runtime clock")
	_check(runtime.record_event("event:runtime_clock"), "runtime records event at its current time")
	var event_snapshot: Dictionary = runtime.event_knowledge().snapshot()
	var records: Array = event_snapshot.get("event_records") as Array
	_check(records.size() == 1, "runtime event fixture contains one event record")
	if records.is_empty():
		return
	var record: Dictionary = records[0] as Dictionary
	_equal(
		record.get("occurred_at_minutes"),
		35,
		"event occurrence uses runtime.total_minutes()"
	)
	_check(
		not runtime.event_knowledge().record_event("event:runtime_clock", 999),
		"duplicate event cannot overwrite runtime occurrence"
	)


func _test_identity_mismatch_is_rejected_transactionally() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.advance_minutes(90), "identity mismatch fixture can advance")
	var before: Dictionary = runtime.snapshot()
	var mismatched: Dictionary = before.duplicate(true)
	var mismatched_wallet: Dictionary = mismatched.get("wallet") as Dictionary
	mismatched_wallet["owner_person_id"] = OTHER_PLAYER_ID
	_check(not runtime.restore(mismatched), "cross-owner wallet identity mismatch is rejected")
	_equal(
		runtime.snapshot(),
		before,
		"cross-owner identity mismatch leaves the complete runtime unchanged"
	)

	var mismatched_location: Dictionary = before.duplicate(true)
	var location_snapshot: Dictionary = mismatched_location.get("location") as Dictionary
	location_snapshot["player_id"] = OTHER_PLAYER_ID
	_check(not runtime.restore(mismatched_location), "cross-owner location identity mismatch is rejected")
	_equal(
		runtime.snapshot(),
		before,
		"location identity mismatch leaves the complete runtime unchanged"
	)


func _test_v1_snapshot_is_not_migrated() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.advance_minutes(42), "v1 migration fixture can establish current state")
	var before: Dictionary = runtime.snapshot()
	var legacy_snapshot := {
		"schema_id": "vnext_world_runtime_v1",
		"total_minutes": 12,
	}
	_check(not runtime.restore(legacy_snapshot), "v1 runtime snapshot is rejected without migration")
	_equal(runtime.snapshot(), before, "rejected v1 snapshot leaves v2 state unchanged")


func _new_runtime(
	player_id: String = PLAYER_ID, place_id: String = START_PLACE_ID
) -> VNextWorldRuntime:
	var runtime := VNextWorldRuntime.create(player_id, place_id)
	_check(runtime != null, "runtime fixture creates a v2 composition")
	return runtime


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
