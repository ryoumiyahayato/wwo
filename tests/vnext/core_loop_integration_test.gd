extends SceneTree

const PLAYER_ID: String = "person:core_player"
const HOME_PLACE_ID: String = "place:core_home"
const DESTINATION_PLACE_ID: String = "place:core_destination"
const EVENT_AFTER_WAIT: String = "event:after_wait"
const EVENT_AFTER_TRAVEL: String = "event:after_travel"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_runtime_composition_and_wait()
	_test_paid_travel_end_to_end()
	_test_paid_travel_failures_are_atomic()
	_test_complete_json_round_trip()
	_test_no_second_runtime_time_owner()
	print("VNext core loop integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_runtime_composition_and_wait() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.wallet().credit(500), "core loop wallet receives starting funds")

	var action_service := VNextPlayerActionService.new()
	var wait_result: VNextActionResult = action_service.wait(runtime, 35)
	_check(wait_result.success, "WAIT succeeds through the composed runtime")
	_equal(wait_result.elapsed_minutes, 35, "WAIT reports its elapsed runtime minutes")
	_equal(runtime.total_minutes(), 35, "WAIT advances the one runtime clock exactly once")
	_check(runtime.record_event(EVENT_AFTER_WAIT), "runtime records an event after WAIT")
	var wait_event_record: Dictionary = _event_record(runtime, EVENT_AFTER_WAIT)
	_equal(
		wait_event_record.get("occurred_at_minutes"),
		35,
		"event occurrence after WAIT uses runtime.total_minutes()"
	)
	_equal(runtime.player_id(), PLAYER_ID, "WAIT preserves the composed person identity")


func _test_paid_travel_end_to_end() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.wallet().credit(500), "travel fixture wallet receives funds")
	var quote := _quote(HOME_PLACE_ID, DESTINATION_PLACE_ID, 75, 125)
	var travel_service := VNextTravelService.new()

	_check(
		travel_service.execute_paid(runtime, quote),
		"paid travel succeeds with valid funds and origin"
	)
	_equal(runtime.total_minutes(), 75, "paid travel advances the shared runtime clock")
	_equal(
		runtime.location().place_id(),
		DESTINATION_PLACE_ID,
		"paid travel moves the composed location"
	)
	_equal(runtime.wallet().balance_minor(), 375, "paid travel debits the wallet exactly once")

	var wait_result: VNextActionResult = VNextPlayerActionService.new().wait(runtime, 25)
	_check(wait_result.success, "WAIT succeeds after paid travel")
	_equal(runtime.total_minutes(), 100, "WAIT and travel accumulate one runtime time value")
	_check(runtime.record_event(EVENT_AFTER_TRAVEL), "runtime records an event after travel and WAIT")
	var travel_event_record: Dictionary = _event_record(runtime, EVENT_AFTER_TRAVEL)
	_equal(
		travel_event_record.get("occurred_at_minutes"),
		100,
		"event occurrence after travel uses the same runtime clock"
	)
	_check(runtime.reveal_event(EVENT_AFTER_TRAVEL), "composed event knowledge can reveal the event")
	_check(runtime.mark_event_read(EVENT_AFTER_TRAVEL), "composed event knowledge can mark the event read")


func _test_paid_travel_failures_are_atomic() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	_check(runtime.wallet().credit(50), "insufficient-funds fixture can fund wallet")
	var expensive_quote := _quote(HOME_PLACE_ID, DESTINATION_PLACE_ID, 20, 51)
	var before: Dictionary = runtime.snapshot()
	_check(
		not VNextTravelService.new().execute_paid(runtime, expensive_quote),
		"paid travel rejects insufficient funds"
	)
	_equal(
		runtime.snapshot(),
		before,
		"insufficient-funds travel leaves time, wallet, location and knowledge unchanged"
	)

	var overflow_runtime := _new_runtime()
	if overflow_runtime == null:
		return
	_check(
		overflow_runtime.wallet().credit(100),
		"overflow fixture can fund a rollback-sensitive travel"
	)
	_check(
		overflow_runtime.advance_minutes(VNextWorldRuntime.MAX_JSON_SAFE_INTEGER - 10),
		"overflow fixture can reach the JSON-safe time boundary"
	)
	var overflow_quote := _quote(HOME_PLACE_ID, DESTINATION_PLACE_ID, 11, 50)
	var overflow_before: Dictionary = overflow_runtime.snapshot()
	_check(
		not VNextTravelService.new().execute_paid(overflow_runtime, overflow_quote),
		"paid travel rejects runtime time overflow"
	)
	_equal(
		overflow_runtime.snapshot(),
		overflow_before,
		"runtime overflow rolls back the prior wallet debit atomically"
	)


func _test_complete_json_round_trip() -> void:
	var source := _new_runtime()
	if source == null:
		return
	_check(source.wallet().credit(321), "JSON fixture can fund the composed wallet")
	_check(source.advance_minutes(40), "JSON fixture can advance the composed runtime")
	var quote := _quote(HOME_PLACE_ID, DESTINATION_PLACE_ID, 15, 21)
	_check(
		VNextTravelService.new().execute_paid(source, quote),
		"JSON fixture can complete paid travel"
	)
	_check(source.record_event("event:json_core_loop"), "JSON fixture can record event")
	_check(source.reveal_event("event:json_core_loop"), "JSON fixture can reveal event")
	_check(source.mark_event_read("event:json_core_loop"), "JSON fixture can read event")
	var expected: Dictionary = source.snapshot()

	var parser := JSON.new()
	_check(parser.parse(JSON.stringify(expected)) == OK, "complete v2 snapshot serializes and parses")
	if parser.data is not Dictionary:
		_check(false, "complete JSON round trip has a Dictionary root")
		return

	var restored := VNextWorldRuntime.new()
	_check(
		restored.restore(parser.data as Dictionary),
		"complete JSON-parsed v2 composition restores"
	)
	_equal(
		restored.snapshot(),
		expected,
		"complete JSON round trip preserves player, wallet, location, knowledge and time"
	)


func _test_no_second_runtime_time_owner() -> void:
	var runtime := _new_runtime()
	if runtime == null:
		return
	var runtime_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/world_runtime.gd"
	)
	_check(runtime_source.contains("var _total_minutes: int"), "runtime owns total_minutes internally")
	_check(
		not runtime_source.contains("var _current_minutes"),
		"runtime has no second current-minutes field"
	)
	_check(
		not runtime_source.contains("var _total_hours"),
		"runtime has no second total-hours field"
	)
	_check(
		not runtime_source.contains("SimulationClock"),
		"vNext runtime does not depend on the legacy clock"
	)
	_check(
		runtime.total_minutes() == 0,
		"unmutated composed runtime begins at zero shared minutes"
	)


func _new_runtime() -> VNextWorldRuntime:
	var runtime := VNextWorldRuntime.create(PLAYER_ID, HOME_PLACE_ID)
	_check(runtime != null, "core loop fixture creates a valid v2 composition")
	return runtime


func _quote(
	origin_id: String, destination_id: String, duration_minutes: int, cost_minor: int
) -> VNextTravelQuote:
	var quote := VNextTravelQuote.new()
	_check(
		quote.configure(origin_id, destination_id, duration_minutes, cost_minor),
		"core loop quote configures"
	)
	return quote


func _event_record(runtime: VNextWorldRuntime, event_id: String) -> Dictionary:
	var event_snapshot: Dictionary = runtime.event_knowledge().snapshot()
	var records: Array = event_snapshot.get("event_records") as Array
	for raw_record: Variant in records:
		var record: Dictionary = raw_record as Dictionary
		if record.get("event_id") == event_id:
			return record
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
