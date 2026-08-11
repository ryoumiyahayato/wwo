extends SceneTree

const GENERATOR = preload("res://tests/vnext/politics_variable_state_generator.gd")
const FIXTURE_PATH: String = "res://data/vnext/politics/state_politics_1900.json"

var checks: int = 0
var failures: int = 0
var service := VNextPoliticsUpdateService.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_sustained_severe_pressure_does_not_become_timer_clock()
	print("VNext state politics R3 transition probe: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_sustained_severe_pressure_does_not_become_timer_clock() -> void:
	var first := VNextStatePolitics.create_from_config(_limited_challenger_config())
	var replay := VNextStatePolitics.create_from_config(_limited_challenger_config())
	_check(first != null and replay != null, "two-government sustained-pressure fixtures are valid")
	if first == null or replay == null:
		return
	var initial_group := first.government_group_id()
	var evidence: Array[Dictionary] = []
	for day: int in range(2200):
		var input := GENERATOR.severe_input(1)
		var before_count := first.government_change_history().size()
		var result := service.update(first, input)
		_check(bool(result.get("success", false)), "sustained severe update succeeds at day %d" % (day + 1))
		if not bool(result.get("success", false)):
			return
		if first.government_change_history().size() > before_count:
			var change := result.get("government_change", {}) as Dictionary
			evidence.append({
				"period": int(change.get("period", first.period_index())),
				"old": str(change.get("old_government_group_id", "")),
				"new": str(change.get("new_government_group_id", "")),
				"support": float(result.get("government_support", 0.0)),
				"mandate": float(change.get("mandate_score", 0.0)),
				"coalition": float(change.get("coalition_score", 0.0)),
				"procedure": float(change.get("procedure_score", 0.0)),
				"crisis": str(result.get("crisis_stage", "")),
			})
		service.update(replay, GENERATOR.severe_input(1))

	_check(evidence.size() >= 2, "sustained severe pressure permits multiple transition windows")
	var comeback := false
	for item: Dictionary in evidence:
		if str(item.get("new", "")) == initial_group:
			comeback = true
		_check(float(item.get("mandate", 0.0)) >= VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD, "transition has mandate evidence at day %d" % int(item.get("period", 0)))
		_check(float(item.get("coalition", 0.0)) > 0.0, "transition has coalition feasibility at day %d" % int(item.get("period", 0)))
		_check(float(item.get("procedure", 0.0)) > 0.0, "transition has procedural legality at day %d" % int(item.get("period", 0)))
	_check(comeback, "former government can still make a politically eligible comeback")

	var exact_cooldown_alternations := 0
	for index: int in range(1, evidence.size()):
		var previous := evidence[index - 1]
		var current := evidence[index]
		var gap := int(current.get("period", 0)) - int(previous.get("period", 0))
		var alternates := (
			str(previous.get("old", "")) == str(current.get("new", ""))
			and str(previous.get("new", "")) == str(current.get("old", ""))
		)
		if alternates and gap == VNextPoliticsUpdateService.TRANSITION_COOLDOWN_DAYS:
			exact_cooldown_alternations += 1
		else:
			exact_cooldown_alternations = 0
		_check(gap >= VNextPoliticsUpdateService.TRANSITION_COOLDOWN_DAYS, "transition spacing respects cooldown at evidence index %d" % index)
	_check(exact_cooldown_alternations < 3, "constant severe pressure does not settle into an endless exact-cooldown A/B timer attractor")
	_equal(_history_signature(first.government_change_history()), _history_signature(replay.government_change_history()), "sustained-pressure transition replay is deterministic")
	print("R3 transition evidence: %s" % JSON.stringify(evidence))


func _limited_challenger_config() -> Dictionary:
	var config := _load_fixture_config()
	var selected: Array = []
	for raw_force: Variant in config.get("forces", []) as Array:
		var force := (raw_force as Dictionary).duplicate(true)
		var force_id := str(force.get("force_id", ""))
		if force_id == "organization:loran_government_group":
			force["influence"] = 50.0
			force["government_support"] = 80.0
			force["base_government_support"] = 80.0
			selected.append(force)
		elif force_id == "organization:loran_labor_caucus":
			force["influence"] = 50.0
			force["government_support"] = -60.0
			force["base_government_support"] = -60.0
			selected.append(force)
	config["forces"] = selected
	return config


func _load_fixture_config() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		_check(false, "political fixture file can be opened")
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	_check(parse_error == OK and parser.data is Dictionary, "political fixture is valid JSON")
	if parse_error != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _history_signature(history: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for record: Dictionary in history:
		result.append("%d:%s>%s" % [
			int(record.get("period", 0)),
			str(record.get("old_government_group_id", "")),
			str(record.get("new_government_group_id", "")),
		])
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
