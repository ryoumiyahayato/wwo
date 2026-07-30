extends SceneTree
## Save/restore equivalence and compact first-difference diagnostics for Alpha.

const HOURS: int = 30 * 24

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := AlphaSimulationService.new()
	test.expect(simulation.initialize(), "Alpha equivalence source initializes")
	simulation.advance_hours(HOURS)
	var source_state: Dictionary = simulation.get_alpha_persistent_state()
	var source_summary: Dictionary = simulation.commodity_market.world_summary()

	var restored := AlphaSimulationService.new()
	test.expect(restored.initialize(), "Alpha equivalence restore target initializes")
	var restore_result: V2LifeLoopResult = restored.restore_alpha_state(
		source_state
	)
	test.expect(restore_result.success, "Alpha state restores after 30 days")
	var restored_state: Dictionary = restored.get_alpha_persistent_state()
	var restored_summary: Dictionary = restored.commodity_market.world_summary()

	var state_difference: Dictionary = _first_difference(
		source_state, restored_state, "$"
	)
	var summary_difference: Dictionary = _first_difference(
		source_summary, restored_summary, "$.world_summary"
	)
	if not state_difference.is_empty():
		print(
			"ALPHA_STATE_FIRST_DIFFERENCE=%s"
			% JSON.stringify(state_difference)
		)
	if not summary_difference.is_empty():
		print(
			"ALPHA_SUMMARY_FIRST_DIFFERENCE=%s"
			% JSON.stringify(summary_difference)
		)
	test.expect(
		state_difference.is_empty(),
		"restored Alpha persistent state is exactly equivalent"
	)
	test.expect(
		summary_difference.is_empty(),
		"restored Alpha world summary is exactly equivalent"
	)
	var normalized_source: Variant = _normalized_state(source_state)
	var normalized_restored: Variant = _normalized_state(restored_state)
	var normalized_source_json: String = JSON.stringify(normalized_source)
	var normalized_restored_json: String = JSON.stringify(normalized_restored)
	test.expect(
		normalized_source_json == normalized_restored_json,
		"normalized deterministic Alpha state is save/restore equivalent"
	)
	print("ALPHA_STATE_EQUIVALENCE=%s" % JSON.stringify({
		"hours": HOURS,
		"source_bytes": JSON.stringify(source_state).to_utf8_buffer().size(),
		"restored_bytes": JSON.stringify(restored_state).to_utf8_buffer().size(),
		"source_sha256": JSON.stringify(source_state).sha256_text(),
		"restored_sha256": JSON.stringify(restored_state).sha256_text(),
		"normalized_source_sha256": normalized_source_json.sha256_text(),
		"normalized_restored_sha256": normalized_restored_json.sha256_text(),
		"first_difference": state_difference,
		"world_summary": source_summary,
	}))
	test.finish(self, "Alpha state equivalence")


func _first_difference(
	expected: Variant, actual: Variant, path: String
) -> Dictionary:
	if typeof(expected) != typeof(actual):
		return _difference(path, expected, actual, "type")
	match typeof(expected):
		TYPE_DICTIONARY:
			var expected_dictionary: Dictionary = expected as Dictionary
			var actual_dictionary: Dictionary = actual as Dictionary
			if expected_dictionary.size() != actual_dictionary.size():
				return _difference(
					path,
					expected_dictionary.size(),
					actual_dictionary.size(),
					"dictionary_size"
				)
			for key: Variant in expected_dictionary:
				if not actual_dictionary.has(key):
					return _difference(
						"%s.%s" % [path, str(key)],
						expected_dictionary[key],
						null,
						"missing_key"
					)
				var nested: Dictionary = _first_difference(
					expected_dictionary[key],
					actual_dictionary[key],
					"%s.%s" % [path, str(key)]
				)
				if not nested.is_empty():
					return nested
		TYPE_ARRAY:
			var expected_array: Array = expected as Array
			var actual_array: Array = actual as Array
			if expected_array.size() != actual_array.size():
				return _difference(
					path,
					expected_array.size(),
					actual_array.size(),
					"array_size"
				)
			for index: int in range(expected_array.size()):
				var nested: Dictionary = _first_difference(
					expected_array[index],
					actual_array[index],
					"%s[%d]" % [path, index]
				)
				if not nested.is_empty():
					return nested
		_:
			if expected != actual:
				return _difference(path, expected, actual, "value")
	return {}


func _difference(
	path: String, expected: Variant, actual: Variant, reason: String
) -> Dictionary:
	return {
		"path": path,
		"reason": reason,
		"expected_type": typeof(expected),
		"actual_type": typeof(actual),
		"expected": expected,
		"actual": actual,
	}


func _normalized_state(value: Variant, key_name: String = "") -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value as Dictionary
			var normalized: Dictionary = {}
			for key: Variant in source:
				var normalized_key: String = str(key)
				if normalized_key == "alpha_maximum_hour_usec":
					continue
				normalized[normalized_key] = _normalized_state(
					source[key], normalized_key
				)
			return normalized
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value as Array:
				normalized_array.append(_normalized_state(item))
			if key_name == "processed_keys":
				normalized_array.sort()
			return normalized_array
		_:
			return value
