extends SceneTree

const TIME_SUPPORT := preload("res://tests/variable_state/formal_time_test_support.gd")

var checks: int = 0
var failures: int = 0
var _save_backup: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save_backup = TIME_SUPPORT.backup_formal_save()
	_check(not bool(_save_backup.get("read_error", false)), "existing Formal save can be isolated")
	if failures > 0 or not TIME_SUPPORT.cleanup_formal_save():
		_finish()
		return
	await _test_menu_load_failure_boundary()
	_test_catalog_and_preview_purity()
	_test_validation_and_stale_tokens()
	_test_atomic_non_paris_creation_and_round_trip()
	_finish()


func _test_menu_load_failure_boundary() -> void:
	var menu := (
		load("res://scenes/formal/formal_world_menu.tscn") as PackedScene
	).instantiate() as FormalWorldMenu
	root.add_child(menu)
	for _index: int in 3:
		await process_frame
	menu._on_load_pressed()
	_check(menu.is_inside_tree(), "missing save leaves player at Formal entry")
	_check(menu.status_label.text.contains("没有可读取"), "missing save shows explicit reason")
	var corrupt := FileAccess.open(FormalWorldSimulation.SAVE_PATH, FileAccess.WRITE)
	_check(corrupt != null, "corrupt-save fixture opens")
	if corrupt != null:
		corrupt.store_string("{not valid formal json")
		corrupt.close()
	menu._on_load_pressed()
	_check(menu.is_inside_tree(), "corrupt save leaves player at Formal entry")
	_check(menu.status_label.text.contains("读取失败"), "corrupt save shows explicit reason")
	_check(
		not has_meta(FormalWorldMenu.LAUNCH_WORLD_META),
		"failed load does not publish a live world"
	)
	TIME_SUPPORT.cleanup_formal_save()
	menu.queue_free()
	await process_frame


func _finish() -> void:
	_check(TIME_SUPPORT.restore_formal_save(_save_backup), "existing Formal save artifacts restored")
	print("Formal new game Phase B: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_catalog_and_preview_purity() -> void:
	var service := FormalNewGameService.new()
	var catalog := service.start_catalog()
	_check(bool(catalog.get("available", false)), "start catalog is available")
	_equal(catalog.get("rules_version"), FormalNewGameService.RULES_VERSION, "catalog rules version")
	_check(not str(catalog.get("population_fingerprint", "")).is_empty(), "catalog has population fingerprint")
	_check(not str(catalog.get("place_mapping_fingerprint", "")).is_empty(), "catalog has place mapping fingerprint")
	var france := _origin(catalog, "country_fra")
	_check(not france.is_empty(), "France is a population-backed origin")
	_check(_has_place(france, "place:lille"), "catalog has a legal non-Paris start place")
	_check(
		"occupation" in (catalog.get("unsupported_fields", []) as Array),
		"unsupported employment field is explicit"
	)
	var request := _request("country_fra", "place:lille", 77123, 0)
	var first := service.preview_player_candidates(request)
	var second_service := FormalNewGameService.new()
	var second := second_service.preview_player_candidates(request)
	_equal(
		first.get("candidates"), second.get("candidates"),
		"same seed, rules, and constraints are deterministic"
	)
	var before_artifacts := TIME_SUPPORT.backup_formal_save()
	for draft_index: int in 100:
		var preview_request := request.duplicate(true)
		preview_request["draft_index"] = draft_index
		var preview := service.preview_player_candidates(preview_request)
		_check(bool(preview.get("success", false)), "preview/cancel %d succeeds" % draft_index)
	var after_artifacts := TIME_SUPPORT.backup_formal_save()
	_equal(after_artifacts, before_artifacts, "100 previews do not mutate Formal save artifacts")

	var locked_request := request.duplicate(true)
	locked_request["locked_fields"] = {
		"population_origin_id": "country_fra",
		"start_place_id": "place:lille",
		"birth_year": 1874,
	}
	var locked_first := service.preview_player_candidates(locked_request)
	locked_request["draft_index"] = 1
	var locked_reroll := service.preview_player_candidates(locked_request)
	for preview: Dictionary in [locked_first, locked_reroll]:
		for candidate: Dictionary in preview.get("candidates", []):
			_equal(candidate.get("population_origin_id"), "country_fra", "locked origin survives reroll")
			_equal(candidate.get("start_place_id"), "place:lille", "locked place survives reroll")
			_equal(candidate.get("birth_year"), 1874, "locked birth year survives reroll")


func _test_validation_and_stale_tokens() -> void:
	var service := FormalNewGameService.new()
	var unknown_source := service.preview_player_candidates(
		_request("missing_origin", "place:lille", 1, 0)
	)
	_check(not bool(unknown_source.get("success", false)), "unknown source is rejected")
	var unknown_place := service.preview_player_candidates(
		_request("country_fra", "place:missing", 1, 0)
	)
	_check(not bool(unknown_place.get("success", false)), "unknown place is rejected")
	var incompatible := service.preview_player_candidates(
		_request("country_fra", "place:berlin", 1, 0)
	)
	_check(not bool(incompatible.get("success", false)), "incompatible source/place is rejected")
	var unsupported_request := _request("country_fra", "place:lille", 1, 0)
	unsupported_request["occupation"] = "officer"
	var unsupported := service.preview_player_candidates(unsupported_request)
	_check(not bool(unsupported.get("success", false)), "unsupported hard field is rejected")

	var preview := service.preview_player_candidates(_request("country_fra", "place:lille", 2, 0))
	var stale_token := str(((preview.get("candidates", []) as Array)[0] as Dictionary).get("candidate_token", ""))
	service.preview_player_candidates(_request("country_fra", "place:lille", 2, 1))
	var stale := service.create_new_game(stale_token, "request:stale")
	_equal(stale.get("code"), "stale_candidate", "reroll invalidates prior candidate token")

	var changed_service := FormalNewGameService.new()
	var changed_preview := changed_service.preview_player_candidates(
		_request("country_fra", "place:lille", 3, 0)
	)
	var changed_token := str(((changed_preview.get("candidates", []) as Array)[0] as Dictionary).get("candidate_token", ""))
	changed_service._catalog["population_fingerprint"] = "changed_population_fingerprint"
	var changed := changed_service.create_new_game(changed_token, "request:changed")
	_equal(changed.get("code"), "stale_candidate", "changed population fingerprint invalidates token")

	var exhausted_service := FormalNewGameService.new()
	var exhausted_preview := exhausted_service.preview_player_candidates(
		_request("country_fra", "place:lille", 4, 0)
	)
	var exhausted_token := str(((exhausted_preview.get("candidates", []) as Array)[0] as Dictionary).get("candidate_token", ""))
	for origin: Dictionary in exhausted_service._catalog.get("origins", []):
		if str(origin.get("id", "")) == "country_fra":
			origin["anonymous_population"] = 0
	var exhausted := exhausted_service.create_new_game(exhausted_token, "request:exhausted")
	_equal(exhausted.get("code"), "population_exhausted", "zero anonymous population is rejected")


func _test_atomic_non_paris_creation_and_round_trip() -> void:
	var service := FormalNewGameService.new()
	var preview := service.preview_player_candidates(
		_request("country_fra", "place:lille", 919191, 0)
	)
	_check(bool(preview.get("success", false)), "non-Paris preview succeeds")
	if not bool(preview.get("success", false)):
		return
	var candidate := (preview.get("candidates", []) as Array)[0] as Dictionary
	var token := str(candidate.get("candidate_token", ""))
	var created := service.create_new_game(token, "request:create-lille")
	_check(bool(created.get("success", false)), "non-Paris Formal new game succeeds")
	if not bool(created.get("success", false)):
		return
	var world := created.get("world") as FormalWorldSimulation
	var player_id := world.player_person_id()
	_equal(world.formal_person_count(), 1, "new game materializes exactly one Person")
	_check(player_id != FormalWorldSimulation.DEFAULT_FORMAL_PERSON_ID, "new game has no default ghost Person")
	_equal(world.formal_person_ids(), [player_id], "only selected Person exists")
	_equal(
		world.formal_person(player_id).get("current_place_id"),
		"place:lille",
		"selected non-Paris place is authoritative"
	)
	var claim := world.formal_person_population_claim(player_id)
	_equal(claim.get("territory_id"), "country_fra", "claim uses selected population source")
	_equal(created.get("active_claim_count"), 1, "creation increments active named claims once")
	_equal(
		int(created.get("anonymous_population", 0)) + int(created.get("active_claim_count", 0)),
		created.get("population_total"),
		"A + C = N after creation"
	)
	var context := world.player_context_view()
	_equal(
		(context.get("economic_observation", {}) as Dictionary).get("population"),
		created.get("population_total"),
		"Economy aggregate population is unchanged by named coverage"
	)
	var duplicate := service.create_new_game(token, "request:create-lille")
	_equal(duplicate.get("world"), world, "same request_id is idempotent")
	var double_confirm := service.create_new_game(token, "request:double-click")
	_equal(double_confirm.get("code"), "stale_candidate", "duplicate confirm cannot create a second player")

	var save_result := world.save_to_user()
	_check(save_result.success, "selected player saves through production port")
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "load candidate initializes")
	var load_result := restored.load_from_user()
	_check(load_result.success, "selected player loads through production port")
	if load_result.success:
		_equal(restored.player_person_id(), player_id, "load restores same player without reroll")
		_equal(restored.formal_person_count(), 1, "load does not append a default Person")
		_equal(
			restored.formal_person(player_id).get("current_place_id"),
			"place:lille",
			"load rebuilds non-Paris references"
		)
		_equal(
			restored.organization_place_reference_ids(),
			["place:lille"],
			"Organization reference catalog rebuilds actual restored place"
		)


func _request(origin_id: String, place_id: String, seed_value: int, draft_index: int) -> Dictionary:
	return {
		"population_origin_id": origin_id,
		"start_place_id": place_id,
		"birth_year_min": 1860,
		"birth_year_max": 1882,
		"random_origin": false,
		"locked_fields": {},
		"seed": seed_value,
		"rules_version": FormalNewGameService.RULES_VERSION,
		"draft_index": draft_index,
	}


func _origin(catalog: Dictionary, origin_id: String) -> Dictionary:
	for origin: Dictionary in catalog.get("origins", []):
		if str(origin.get("id", "")) == origin_id:
			return origin
	return {}


func _has_place(origin: Dictionary, place_id: String) -> bool:
	for place: Dictionary in origin.get("places", []):
		if str(place.get("id", "")) == place_id:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(
		actual == expected,
		label if actual == expected else "%s | actual=%s expected=%s" % [
			label, var_to_str(actual), var_to_str(expected)
		]
	)
