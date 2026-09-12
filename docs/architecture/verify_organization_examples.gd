extends SceneTree

## Verifies the existing core structure only, not proposed governance behavior.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var path: String = "res://docs/architecture/organization_scenario_examples_20260908.json"
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary:
		printerr("Fixture is not a JSON object")
		quit(1)
		return
	var root: Dictionary = raw as Dictionary
	var examples: Array = root.get("examples", []) as Array
	_check(examples.size() == 5, "five scenarios")
	for item: Variant in examples:
		var sample: Dictionary = item as Dictionary
		var label: String = str(sample.get("id", "missing"))
		var people: Array[String] = []
		people.assign(sample.get("known_person_ids", []))
		var places: Array[String] = []
		places.assign(sample.get("known_place_ids", []))
		var core: VNextOrganizationCore = VNextOrganizationCore.create(people, places)
		_check(core != null, label + " catalogs")
		if core == null:
			continue
		_check(core.restore(sample.get("core_v1", {}) as Dictionary), label + " restore")
		_check(core.is_valid(), label + " valid")
		var saved: Dictionary = core.snapshot()
		var restored: VNextOrganizationCore = VNextOrganizationCore.create(people, places)
		_check(restored.restore(saved), label + " round trip restore")
		_check(restored.snapshot() == saved, label + " round trip identical")
		var shuffled: Dictionary = saved.duplicate(true)
		var organizations: Array = shuffled.get("organizations", []) as Array
		organizations.reverse()
		for org_value: Variant in organizations:
			var organization: Dictionary = org_value as Dictionary
			for key: String in ["member_ids", "capability_ids", "positions", "appointments"]:
				var entries: Array = organization.get(key, []) as Array
				entries.reverse()
		_check(restored.restore(shuffled) and restored.snapshot() == saved, label + " order independent")
		for case_value: Variant in sample.get("core_capability_checks", []) as Array:
			var expected_case: Dictionary = case_value as Dictionary
			var actual: bool = core.has_capability(
				str(expected_case.get("person_id")),
				str(expected_case.get("organization_id")),
				str(expected_case.get("capability_id"))
			)
			_check(actual == bool(expected_case.get("expected")), label + " coarse capability")
		print("Scenario structure checked: " + label)
	print("Organization scenario STRUCTURE ONLY: %d checks, %d failures" % [checks, failures])
	print("Proposed governance procedures and domain execution are NOT implemented or tested here.")
	quit(1 if failures > 0 else 0)
