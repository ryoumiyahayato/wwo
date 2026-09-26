extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_context_projection_and_round_trip()
	await _test_formal_application_identity_boundary()
	print("Formal player context Phase A: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_context_projection_and_round_trip() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "default Formal world initializes: %s" % world.initialization_error)
	if not world.initialized:
		return
	var context := world.player_context_view()
	var person_id := world.player_person_id()
	var person := world.formal_person(person_id)
	_equal(context.get("person_id"), person_id, "context identity equals PlayerState identity")
	_equal(
		(context.get("current_place", {}) as Dictionary).get("id"),
		person.get("current_place_id"),
		"context place equals authoritative Person place"
	)
	_equal(
		(context.get("population_claim", {}) as Dictionary).get("claim_id"),
		world.formal_person_population_claim(person_id).get("claim_id"),
		"context carries the authoritative population claim"
	)
	_check(
		bool((context.get("political_observation", {}) as Dictionary).get("available", false)),
		"default place has a narrow political observation"
	)
	_check(
		bool((context.get("economic_observation", {}) as Dictionary).get("available", false)),
		"default population source has a narrow economic observation"
	)
	var unavailable := context.get("unsupported_personal_fields", {}) as Dictionary
	for field_name: String in [
		"name", "occupation", "wage", "cash", "health", "friends",
		"relationships", "plans", "messages", "skills", "military_rank",
	]:
		_equal(
			unavailable.get(field_name),
			"unavailable",
			"unsupported %s is explicit unavailable" % field_name
		)
	var saved := world.get_persistent_state()
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "v10 restore target initializes")
	_check(restored.restore_persistent_state(saved), "v10 default player restores")
	if restored.initialized:
		_equal(restored.player_person_id(), person_id, "v10 restore keeps the same player ID")
		_equal(
			restored.player_context_view().get("person_id"),
			person_id,
			"restored context keeps the same player ID"
		)


func _test_formal_application_identity_boundary() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	var application := packed.instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in range(20):
		await process_frame
	_check(application.formal_simulation.initialized, "Formal application initializes")
	if not application.formal_simulation.initialized:
		application.queue_free()
		await process_frame
		return
	var player_id := application.formal_simulation.player_person_id()
	_equal(application.player_card_person_id(), player_id, "player card uses PlayerState identity")
	_equal(
		application.character_detail_person_id(),
		player_id,
		"character detail uses PlayerState identity"
	)
	_check(application._character_profiles.is_empty(), "Formal product does not load prototype character profiles")
	_equal(application.activity_unread, 0, "Formal product has no fake unread counter")
	_check(application._world_events.is_empty(), "prototype institution agendas are not personal messages")
	_check(
		application._active_character_name() not in ["皮埃尔 · 勒费弗尔", "阿尔贝 · 杜瓦尔", "Pierre", "Albert"],
		"Formal active character label is not a prototype name"
	)
	var home_report := application.home_country_detail_report()
	_equal(home_report.get("player_person_id"), player_id, "home detail uses Formal player identity")
	_check(
		not home_report.has("active_character_key"),
		"home detail does not expose prototype character identity"
	)
	application._switch_character()
	_equal(application.formal_simulation.player_person_id(), player_id, "prototype switch cannot change Formal player")
	var other_polity := "state:german_empire"
	if not application.formal_simulation.has_polity(other_polity):
		other_polity = application.formal_simulation.first_polity_id()
	application.selected_country_id = other_polity
	application.queue_redraw()
	await process_frame
	_equal(application.formal_simulation.player_person_id(), player_id, "map selection does not change player identity")
	_equal(application.player_card_person_id(), player_id, "map selection leaves player card identity unchanged")
	application.queue_free()
	await process_frame


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
