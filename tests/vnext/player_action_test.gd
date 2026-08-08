extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_player_identity_validation()
	_test_player_snapshot_restore()
	_test_player_json_round_trip()
	_test_wait_advances_runtime()
	_test_wait_validation_failures()
	_test_null_boundaries()
	_test_no_second_time_or_session_owner()
	print("VNext player action: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_player_identity_validation() -> void:
	var valid_player := VNextPlayerState.new("person:player_one")
	_check(valid_player.is_valid(), "valid person ID is accepted as player identity")
	_check(
		VNextStableId.is_valid(valid_player.player_id),
		"player identity is validated by the shared stable ID contract"
	)
	_equal(
		VNextStableId.kind_of(valid_player.player_id),
		"person",
		"player identity is restricted to the person kind"
	)

	var non_person_player := VNextPlayerState.new("place:country_fra")
	_check(not non_person_player.is_valid(), "non-person stable ID is rejected as player identity")
	var malformed_player := VNextPlayerState.new("person:Player One")
	_check(not malformed_player.is_valid(), "malformed person ID is rejected as player identity")


func _test_player_snapshot_restore() -> void:
	var source := VNextPlayerState.new("person:player_one")
	var saved: Dictionary = source.snapshot()
	_equal(saved.size(), 2, "player snapshot contains exactly schema_id and player_id")
	_equal(saved.get("schema_id"), "vnext_player_state_v1", "player snapshot schema is correct")
	_equal(saved.get("player_id"), "person:player_one", "player snapshot contains the authoritative ID")

	var restored := VNextPlayerState.new("person:other_player")
	_check(restored.restore(saved), "valid player snapshot restore succeeds")
	_equal(restored.snapshot(), saved, "player snapshot round trip preserves complete state")

	_expect_player_restore_failure(
		restored,
		{"schema_id": "vnext_player_state_v0", "player_id": "person:third_player"},
		"wrong player schema"
	)
	_expect_player_restore_failure(
		restored,
		{"schema_id": "vnext_player_state_v1"},
		"missing player_id"
	)
	_expect_player_restore_failure(
		restored,
		{"schema_id": "vnext_player_state_v1", "player_id": 42},
		"non-string player_id"
	)
	_expect_player_restore_failure(
		restored,
		{"schema_id": "vnext_player_state_v1", "player_id": "place:country_fra"},
		"non-person player_id"
	)
	_expect_player_restore_failure(
		restored,
		{"schema_id": "vnext_player_state_v1", "player_id": "person:Player"},
		"malformed player_id"
	)


func _test_player_json_round_trip() -> void:
	var source := VNextPlayerState.new("person:json_player")
	var source_snapshot: Dictionary = source.snapshot()
	var serialized_snapshot: String = JSON.stringify(source_snapshot)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized_snapshot)
	_equal(parse_error, OK, "player snapshot JSON parses successfully")
	if parse_error != OK:
		return

	var parsed_value: Variant = parser.data
	_check(typeof(parsed_value) == TYPE_DICTIONARY, "player JSON round trip returns a Dictionary")
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return

	var restored := VNextPlayerState.new()
	_check(restored.restore(parsed_value as Dictionary), "JSON-parsed player snapshot restores")
	_equal(restored.snapshot(), source_snapshot, "JSON round trip preserves player state")


func _test_wait_advances_runtime() -> void:
	var runtime := VNextWorldRuntime.new()
	_check(runtime.advance_minutes(10), "WAIT fixture can establish initial runtime time")
	var player := VNextPlayerState.new("person:player_one")
	var player_before: Dictionary = player.snapshot()
	var service := VNextPlayerActionService.new()
	var result: VNextActionResult = service.wait(runtime, player, 25)

	_check(result.success, "positive WAIT succeeds")
	_equal(result.code, "ok", "successful WAIT returns explicit ok code")
	_check(not result.message.is_empty(), "successful WAIT returns a message")
	_equal(result.elapsed_minutes, 25, "successful WAIT reports elapsed minutes")
	_equal(runtime.total_minutes(), 35, "WAIT advances authoritative runtime time exactly once")
	_equal(player.snapshot(), player_before, "WAIT does not mutate player identity")


func _test_wait_validation_failures() -> void:
	var service := VNextPlayerActionService.new()
	var valid_player := VNextPlayerState.new("person:player_one")

	var zero_runtime := _runtime_at(40)
	_expect_wait_failure(
		service, zero_runtime, valid_player, 0, "invalid_minutes", "WAIT zero minutes"
	)

	var negative_runtime := _runtime_at(40)
	_expect_wait_failure(
		service, negative_runtime, valid_player, -5, "invalid_minutes", "WAIT negative minutes"
	)

	var non_person_runtime := _runtime_at(40)
	_expect_wait_failure(
		service,
		non_person_runtime,
		VNextPlayerState.new("place:country_fra"),
		5,
		"invalid_player_id",
		"WAIT non-person player"
	)

	var malformed_runtime := _runtime_at(40)
	_expect_wait_failure(
		service,
		malformed_runtime,
		VNextPlayerState.new("person:Player"),
		5,
		"invalid_player_id",
		"WAIT malformed player"
	)


func _test_null_boundaries() -> void:
	var service := VNextPlayerActionService.new()
	var valid_player := VNextPlayerState.new("person:player_one")
	var null_runtime_result: VNextActionResult = service.wait(null, valid_player, 5)
	_check(not null_runtime_result.success, "WAIT rejects null runtime")
	_equal(null_runtime_result.code, "invalid_runtime", "null runtime has explicit failure code")
	_equal(null_runtime_result.elapsed_minutes, 0, "null runtime failure reports zero elapsed minutes")

	var runtime := _runtime_at(40)
	_expect_wait_failure(
		service, runtime, null, 5, "invalid_player", "WAIT null player"
	)


func _test_no_second_time_or_session_owner() -> void:
	var player := VNextPlayerState.new("person:player_one")
	var forbidden_time_members: Array[String] = [
		"total_minutes",
		"current_minutes",
		"current_hour",
		"total_hours",
		"world_clock",
		"clock",
	]
	var found_player_id: bool = false
	for property_value: Dictionary in player.get_property_list():
		var property_name: String = str(property_value.get("name", ""))
		if property_name == "player_id":
			found_player_id = true
		_check(
			not forbidden_time_members.has(property_name),
			"player state does not own second time member: %s" % property_name
		)
	_check(found_player_id, "player state exposes player_id as its only business identity member")

	var service_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/player/player_action_service.gd"
	)
	_check(not service_source.is_empty(), "player action service source is readable for boundary guard")
	_check(
		not service_source.contains("GameSessionService"),
		"vNext player action service does not depend on legacy GameSessionService"
	)
	_check(
		service_source.contains("runtime.advance_minutes(minutes)"),
		"WAIT mutates time only through VNextWorldRuntime.advance_minutes"
	)
	_check(
		not service_source.contains("_total_minutes"),
		"player action service never accesses runtime private time state"
	)


func _runtime_at(minutes: int) -> VNextWorldRuntime:
	var runtime := VNextWorldRuntime.new()
	if minutes > 0:
		_check(runtime.advance_minutes(minutes), "failure fixture can establish runtime time")
	return runtime


func _expect_player_restore_failure(
	player: VNextPlayerState, rejected: Dictionary, label: String
) -> void:
	var before: Dictionary = player.snapshot()
	_check(not player.restore(rejected), "%s is rejected" % label)
	_equal(player.snapshot(), before, "%s rejection is transactional" % label)


func _expect_wait_failure(
	service: VNextPlayerActionService,
	runtime: VNextWorldRuntime,
	player: VNextPlayerState,
	minutes: int,
	expected_code: String,
	label: String
) -> void:
	var before: Dictionary = runtime.snapshot()
	var result: VNextActionResult = service.wait(runtime, player, minutes)
	_check(not result.success, "%s is rejected" % label)
	_equal(result.code, expected_code, "%s returns expected failure code" % label)
	_check(not result.message.is_empty(), "%s returns a failure message" % label)
	_equal(result.elapsed_minutes, 0, "%s reports zero elapsed minutes" % label)
	_equal(runtime.snapshot(), before, "%s leaves runtime unchanged" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
