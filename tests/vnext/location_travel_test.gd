extends SceneTree

var checks: int = 0
var failures: int = 0

const PLAYER_ID: String = "person:player_001"
const ORIGIN_ID: String = "place:lille_home"
const DESTINATION_ID: String = "place:lille_factory"
const OTHER_ID: String = "place:lille_station"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_location_initialization()
	_test_invalid_player_and_place_ids()
	_test_quote_validation()
	_test_successful_travel()
	_test_origin_mismatch_is_atomic()
	_test_invalid_quote_execution_is_atomic()
	_test_invalid_runtime_is_rejected()
	_test_location_snapshot_restore()
	_test_location_json_round_trip()
	print("VNext location travel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_location_initialization() -> void:
	var location := VNextLocationState.new()
	_check(location.initialize(PLAYER_ID, ORIGIN_ID), "legal player and place initialize location")
	_equal(location.player_id(), PLAYER_ID, "location owns the player stable ID")
	_equal(location.place_id(), ORIGIN_ID, "location owns the place stable ID")
	_check(location.is_valid(), "initialized location state is valid")


func _test_invalid_player_and_place_ids() -> void:
	var location := VNextLocationState.new()
	_check(not location.initialize("place:not_a_person", ORIGIN_ID), "non-person player ID is rejected")
	_check(not location.is_valid(), "rejected initialization does not create valid state")
	_check(not location.initialize(PLAYER_ID, "person:not_a_place"), "non-place location ID is rejected")
	_check(not location.initialize(PLAYER_ID, "place:BadCase"), "malformed place stable ID is rejected")

	_check(location.initialize(PLAYER_ID, ORIGIN_ID), "valid location can initialize after rejected attempts")
	var before: Dictionary = location.snapshot()
	_check(not location.initialize("person:BadCase", DESTINATION_ID), "invalid reinitialization is rejected")
	_equal(location.snapshot(), before, "invalid reinitialization leaves location unchanged")
	_check(not location.move_to("event:not_a_place"), "move rejects non-place stable ID")
	_equal(location.snapshot(), before, "rejected move leaves location unchanged")


func _test_quote_validation() -> void:
	var valid := VNextTravelQuote.new()
	_check(valid.configure(ORIGIN_ID, DESTINATION_ID, 75, 125), "valid travel quote is accepted")
	_check(valid.is_valid(), "accepted quote reports valid")
	_equal(valid.origin_place_id(), ORIGIN_ID, "quote records origin")
	_equal(valid.destination_place_id(), DESTINATION_ID, "quote records destination")
	_equal(valid.duration_minutes(), 75, "quote records positive integer duration")
	_equal(valid.cost_minor(), 125, "quote records non-negative integer cost")
	_equal(valid.as_dictionary().size(), 4, "quote contains only the four confirmed plan fields")

	_expect_quote_rejection("person:not_a_place", DESTINATION_ID, 75, 125, "origin must be place ID")
	_expect_quote_rejection(ORIGIN_ID, "organization:not_a_place", 75, 125, "destination must be place ID")
	_expect_quote_rejection(ORIGIN_ID, ORIGIN_ID, 75, 125, "origin and destination must differ")
	_expect_quote_rejection(ORIGIN_ID, DESTINATION_ID, 0, 125, "zero duration is rejected")
	_expect_quote_rejection(ORIGIN_ID, DESTINATION_ID, -1, 125, "negative duration is rejected")
	_expect_quote_rejection(ORIGIN_ID, DESTINATION_ID, 75, -1, "negative cost is rejected")
	_expect_quote_rejection(ORIGIN_ID, DESTINATION_ID, 75.0, 125, "float duration is rejected")
	_expect_quote_rejection(ORIGIN_ID, DESTINATION_ID, 75, 125.0, "float money is rejected")


func _test_successful_travel() -> void:
	var runtime := _runtime_at(30)
	var location := _location_at(ORIGIN_ID)
	var quote := _quote(ORIGIN_ID, DESTINATION_ID, 75, 125)
	var service := VNextTravelService.new()

	_check(service.execute(runtime, location, quote), "validated quote executes")
	_equal(runtime.total_minutes(), 105, "successful travel advances authoritative runtime by quote duration")
	_equal(location.place_id(), DESTINATION_ID, "successful travel moves location to destination")
	_equal(quote.cost_minor(), 125, "travel execution does not alter quoted cost")


func _test_origin_mismatch_is_atomic() -> void:
	var runtime := _runtime_at(12)
	var location := _location_at(OTHER_ID)
	var quote := _quote(ORIGIN_ID, DESTINATION_ID, 20, 0)
	var before_runtime: Dictionary = runtime.snapshot()
	var before_location: Dictionary = location.snapshot()

	_check(not VNextTravelService.new().execute(runtime, location, quote), "origin mismatch is rejected")
	_equal(runtime.snapshot(), before_runtime, "origin mismatch leaves time unchanged")
	_equal(location.snapshot(), before_location, "origin mismatch leaves location unchanged")


func _test_invalid_quote_execution_is_atomic() -> void:
	var runtime := _runtime_at(44)
	var location := _location_at(ORIGIN_ID)
	var invalid_quote := VNextTravelQuote.new()
	_check(not invalid_quote.configure(ORIGIN_ID, DESTINATION_ID, 0, 10), "invalid execution quote is not configurable")
	var before_runtime: Dictionary = runtime.snapshot()
	var before_location: Dictionary = location.snapshot()

	_check(not VNextTravelService.new().execute(runtime, location, invalid_quote), "invalid quote execution is rejected")
	_equal(runtime.snapshot(), before_runtime, "invalid quote leaves time unchanged")
	_equal(location.snapshot(), before_location, "invalid quote leaves location unchanged")


func _test_invalid_runtime_is_rejected() -> void:
	var location := _location_at(ORIGIN_ID)
	var quote := _quote(ORIGIN_ID, DESTINATION_ID, 10, 0)
	var before: Dictionary = location.snapshot()
	_check(not VNextTravelService.new().execute(null, location, quote), "null runtime is rejected")
	_equal(location.snapshot(), before, "null runtime rejection leaves location unchanged")


func _test_location_snapshot_restore() -> void:
	var source := _location_at(DESTINATION_ID)
	var saved: Dictionary = source.snapshot()
	_equal(saved.size(), 3, "location snapshot contains exactly schema, player and place")
	_equal(saved.get("schema_id"), "vnext_location_state_v1", "location snapshot schema is correct")

	var target := _location_at(OTHER_ID)
	_check(target.restore(saved), "valid location snapshot restores")
	_equal(target.player_id(), PLAYER_ID, "restore recovers player ID")
	_equal(target.place_id(), DESTINATION_ID, "restore recovers place ID")
	_equal(target.snapshot(), saved, "location snapshot round trip preserves complete state")

	_expect_location_restore_failure(target, {"schema_id": "vnext_location_state_v0", "player_id": PLAYER_ID, "place_id": ORIGIN_ID}, "wrong schema")
	_expect_location_restore_failure(target, {"schema_id": "vnext_location_state_v1", "player_id": "place:not_person", "place_id": ORIGIN_ID}, "wrong player kind")
	_expect_location_restore_failure(target, {"schema_id": "vnext_location_state_v1", "player_id": PLAYER_ID, "place_id": "person:not_place"}, "wrong place kind")
	_expect_location_restore_failure(target, {"schema_id": "vnext_location_state_v1", "player_id": PLAYER_ID}, "missing place")


func _test_location_json_round_trip() -> void:
	var source := _location_at(DESTINATION_ID)
	var expected: Dictionary = source.snapshot()
	var serialized: String = JSON.stringify(expected)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized)
	_equal(parse_error, OK, "location snapshot JSON parses")
	if parse_error != OK:
		return
	_check(parser.data is Dictionary, "location JSON root remains a dictionary")
	if not parser.data is Dictionary:
		return
	var restored := VNextLocationState.new()
	_check(restored.restore(parser.data as Dictionary), "JSON-parsed location snapshot restores")
	_equal(restored.snapshot(), expected, "location JSON round trip preserves state")


func _runtime_at(minutes: int) -> VNextWorldRuntime:
	var runtime := VNextWorldRuntime.create(PLAYER_ID, ORIGIN_ID)
	_check(runtime != null, "travel fixture creates a valid v2 runtime")
	if runtime == null:
		return null
	if minutes > 0:
		_check(runtime.advance_minutes(minutes), "travel fixture establishes runtime time")
	return runtime


func _location_at(place_id_value: String) -> VNextLocationState:
	var location := VNextLocationState.new()
	_check(location.initialize(PLAYER_ID, place_id_value), "location fixture initializes at %s" % place_id_value)
	return location


func _quote(
	origin_id: String, destination_id: String, duration_minutes: int, cost_minor: int
) -> VNextTravelQuote:
	var quote := VNextTravelQuote.new()
	_check(quote.configure(origin_id, destination_id, duration_minutes, cost_minor), "quote fixture configures")
	return quote


func _expect_quote_rejection(
	origin_value: Variant,
	destination_value: Variant,
	duration_value: Variant,
	cost_value: Variant,
	label: String
) -> void:
	var quote := VNextTravelQuote.new()
	_check(not quote.configure(origin_value, destination_value, duration_value, cost_value), label)
	_check(not quote.is_valid(), "%s leaves quote invalid" % label)


func _expect_location_restore_failure(
	location: VNextLocationState, rejected: Dictionary, label: String
) -> void:
	var before: Dictionary = location.snapshot()
	_check(not location.restore(rejected), "%s is rejected" % label)
	_equal(location.snapshot(), before, "%s restore rejection is transactional" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
