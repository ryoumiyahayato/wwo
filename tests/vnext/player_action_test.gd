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
	_test_wait_current_player_helper()
	_test_typed_wait_source_boundary()
	_test_wait_validation_failures()
	_test_null_boundaries()
	_test_no_second_time_or_session_owner()
	print("VNext player action: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_player_identity_validation() -> void:
	var valid_player := VNextPlayerState.new("person:player_one")
	_check(valid_player.is_valid(), "valid person ID creates a valid player authority")
	_equal(valid_player.player_id(), "person:player_one", "valid player exposes canonical ID through getter")
	_check(
		VNextStableId.is_valid(valid_player.player_id()),
		"player identity is validated by the shared stable ID contract"
	)
	_equal(
		VNextStableId.kind_of(valid_player.player_id()),
		"person",
		"player identity is restricted to the person kind"
	)

	var non_person_player := VNextPlayerState.new("place:country_fra")
	_check(not non_person_player.is_valid(), "non-person constructor input does not create player authority")
	_equal(non_person_player.player_id(), "", "non-person constructor input is not stored as player fact")

	var malformed_player := VNextPlayerState.new("person:Player One")
	_check(not malformed_player.is_valid(), "malformed constructor input does not create player authority")
	_equal(malformed_player.player_id(), "", "malformed constructor input is not stored as player fact")

	var empty_shell := VNextPlayerState.new()
	_check(not empty_shell.is_valid(), "empty restore shell is invalid until a valid restore commits")
	_equal(empty_shell.player_id(), "", "empty restore shell owns no player fact")


func _test_player_snapshot_restore() -> void:
	var source := VNextPlayerState.new("person:player_one")
	var saved: Dictionary = source.snapshot()
	_equal(saved.size(), 2, "player snapshot contains exactly schema_id and player_id")
	_equal(saved.get("schema_id"), "vnext_player_state_v1", "player snapshot schema is correct")
	_equal(saved.get("player_id"), "person:player_one", "player snapshot contains the authoritative ID")

	var restored := VNextPlayerState.new("person:other_player")
	_check(restored.restore(saved), "valid player snapshot restore succeeds")
	_equal(restored.player_id(), "person:player_one", "restore commits validated player identity")
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
	_equal(restored.player_id(), "person:json_player", "JSON restore establishes valid player authority")
	_equal(restored.snapshot(), source_snapshot, "JSON round trip preserves player state")


func _test_wait_advances_runtime() -> void:
	var runtime := _runtime_at(10)
	var player := VNextPlayerState.new("person:player_one")
	var player_before: Dictionary = player.snapshot()
	var service := VNextPlayerActionService.new()
	var result: VNextActionResult = service.wait(runtime, player, 25)

	_check(result.success, "positive WAIT succeeds for valid player authority")
	_equal(result.code, "ok", "successful WAIT returns explicit ok code")
	_check(not result.message.is_empty(), "successful WAIT returns a message")
	_equal(result.elapsed_minutes, 25, "successful WAIT reports elapsed minutes")
	_equal(runtime.total_minutes(), 35, "WAIT advances authoritative runtime time exactly once")
	_equal(player.snapshot(), player_before, "WAIT does not mutate player identity")


func _test_wait_current_player_helper() -> void:
	var runtime := _runtime_at(10)
	if runtime == null:
		return
	var service := VNextPlayerActionService.new()
	var result: VNextActionResult = service.wait_current_player(runtime, 20)
	_check(result.success, "current-player WAIT helper succeeds")
	_equal(result.elapsed_minutes, 20, "current-player WAIT helper reports elapsed minutes")
	_equal(runtime.total_minutes(), 30, "current-player WAIT helper advances the shared runtime")
	var null_runtime_result: VNextActionResult = service.wait_current_player(null, 5)
	_check(not null_runtime_result.success, "current-player WAIT helper rejects null runtime")
	_equal(null_runtime_result.code, "invalid_runtime", "current-player helper keeps typed failure behavior")

func _test_typed_wait_source_boundary() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/player/player_action_service.gd"
	)
	_check(source.contains("func wait("), "WAIT exposes the typed wait entry point")
	_check(source.contains("runtime: VNextWorldRuntime"), "WAIT types the runtime parameter")
	_check(source.contains("player: VNextPlayerState"), "WAIT types the player parameter")
	_check(source.contains("minutes: int"), "WAIT types the minutes parameter")
	_check(source.contains("func wait_current_player"), "WAIT exposes the current-player helper")
	_check(source.contains("runtime.player()"), "current-player helper reads the runtime player")
	_check(source.contains("wait(runtime, player, minutes)"), "current-player helper calls the typed WAIT entry point")
	_check(not source.contains("Variant"), "WAIT has no Variant dynamic overload")
	_check(not source.contains("requested_minutes"), "WAIT has no dynamic requested-minutes sentinel")
	_check(not source.contains("-1"), "WAIT has no -1 player sentinel")

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

	var non_person_player := VNextPlayerState.new("place:country_fra")
	_equal(non_person_player.player_id(), "", "non-person WAIT fixture remains an empty invalid shell")
	var non_person_runtime := _runtime_at(40)
	_expect_wait_failure(
		service,
		non_person_runtime,
		non_person_player,
		5,
		"invalid_player_id",
		"WAIT non-person player"
	)

	var malformed_player := VNextPlayerState.new("person:Player")
	_equal(malformed_player.player_id(), "", "malformed WAIT fixture remains an empty invalid shell")
	var malformed_runtime := _runtime_at(40)
	_expect_wait_failure(
		service,
		malformed_runtime,
		malformed_player,
		5,
		"invalid_player_id",
		"WAIT malformed player"
	)

	var empty_runtime := _runtime_at(40)
	_expect_wait_failure(
		service,
		empty_runtime,
		VNextPlayerState.new(),
		5,
		"invalid_player_id",
		"WAIT empty restore shell"
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
	var found_internal_player_id: bool = false
	var found_public_writable_player_id: bool = false
	for property_value: Dictionary in player.get_property_list():
		var property_name: String = str(property_value.get("name", ""))
		if property_name == "_player_id":
			found_internal_player_id = true
		if property_name == "player_id":
			found_public_writable_player_id = true
		_check(
			not forbidden_time_members.has(property_name),
			"player state does not own second time member: %s" % property_name
		)
	_check(found_internal_player_id, "player state owns one internal player identity field")
	_check(not found_public_writable_player_id, "player state exposes no public writable player_id member")

	var player_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/player/player_state.gd"
	)
	_check(not player_source.is_empty(), "player state source is readable for authority guard")
	_check(player_source.contains("var _player_id: String"), "player identity storage is internal")
	_check(player_source.contains("func player_id() -> String"), "player identity has a query getter")
	_check(not player_source.contains("var player_id: String"), "public writable player_id storage is absent")

	var service_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/player/player_action_service.gd"
	)
	_check(not service_source.is_empty(), "player action service source is readable for boundary guard")
	_check(
		not service_source.contains("GameSessionService"),
		"vNext player action service does not depend on legacy GameSessionService"
	)
	_check(
		service_source.contains("player.player_id()"),
		"WAIT reads player identity through the public getter"
	)
	_check(
		not service_source.contains("player._player_id"),
		"WAIT does not read internal player identity storage directly"
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
	var runtime := VNextWorldRuntime.create("person:player_one", "place:player_home")
	_check(runtime != null, "failure fixture creates a valid v2 runtime")
	if runtime == null:
		return null
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
