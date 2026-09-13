extends SceneTree

var checks: int = 0
var failures: int = 0
var _population_totals: Dictionary = {
	"country_fra": 3,
	"country_zero": 0,
}
var _known_places: Dictionary = {
	"place:paris": true,
	"place:lille": true,
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_materialization_validation()
	_test_population_coverage_and_anonymous_count()
	_test_snapshot_round_trip_and_fail_closed_restore()
	_test_player_authority_binding()
	_test_legacy_unbound_player_compatibility()
	print("Named person overlay: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_materialization_validation() -> void:
	var overlay := _make_overlay("population-source-a")
	_check(overlay != null and overlay.is_configured(), "named overlay configures against detached population/place queries")
	if overlay == null:
		return
	_check(
		_materialize(overlay, "person:alice", "claim:alice", "country_fra", "place:paris"),
		"valid named person materializes"
	)
	_equal(overlay.person_ids(), ["person:alice"], "materialized person exposes stable person ID")
	var alice := overlay.person("person:alice")
	_equal(alice.get("population_territory_id"), "country_fra", "person retains population aggregate claim")
	_equal(alice.get("current_place_id"), "place:paris", "person retains validated current place")
	_check(bool(alice.get("alive", false)), "materialized person starts alive")

	var before := overlay.snapshot()
	_check(
		not _materialize(overlay, "place:not_a_person", "claim:wrong_kind", "country_fra", "place:paris"),
		"non-person stable ID is rejected"
	)
	_equal(overlay.snapshot(), before, "wrong-kind person rejection is atomic")
	_check(
		not _materialize(overlay, "person:alice", "claim:duplicate_person", "country_fra", "place:paris"),
		"duplicate person ID is rejected"
	)
	_check(
		not _materialize(overlay, "person:bob", "claim:alice", "country_fra", "place:paris"),
		"duplicate population claim ID is rejected"
	)
	_check(
		not _materialize(overlay, "person:bob", "claim:bob", "country_fra", "place:missing"),
		"unknown current place is rejected"
	)
	_check(
		not _materialize(overlay, "person:bob", "claim:bob", "country_missing", "place:paris"),
		"unknown population aggregate is rejected"
	)
	_check(
		not _materialize(overlay, "person:bob", "claim:bob", "country_zero", "place:paris"),
		"zero population aggregate is rejected"
	)
	_equal(overlay.snapshot(), before, "all invalid materializations leave live overlay unchanged")


func _test_population_coverage_and_anonymous_count() -> void:
	var overlay := _make_overlay("population-source-a")
	if overlay == null:
		_check(false, "coverage fixture configures")
		return
	_check(_materialize(overlay, "person:one", "claim:one", "country_fra", "place:paris"), "first population share is claimed")
	_equal(
		overlay.anonymous_population_for_territory("country_fra"),
		2,
		"anonymous population equals authoritative population minus active named coverage"
	)
	_check(_materialize(overlay, "person:two", "claim:two", "country_fra", "place:lille"), "second population share is claimed")
	_check(_materialize(overlay, "person:three", "claim:three", "country_fra", "place:paris"), "third population share reaches authoritative total")
	_equal(overlay.anonymous_population_for_territory("country_fra"), 0, "full named coverage leaves zero anonymous population")
	var before := overlay.snapshot()
	_check(
		not _materialize(overlay, "person:four", "claim:four", "country_fra", "place:paris"),
		"named coverage cannot exceed authoritative population total"
	)
	_equal(overlay.snapshot(), before, "coverage overflow rejection is atomic")


func _test_snapshot_round_trip_and_fail_closed_restore() -> void:
	var source := _make_overlay("population-source-a")
	if source == null:
		_check(false, "snapshot source configures")
		return
	_check(_materialize(source, "person:alice", "claim:alice", "country_fra", "place:paris"), "snapshot source person materializes")
	_check(_materialize(source, "person:bob", "claim:bob", "country_fra", "place:lille"), "snapshot source second person materializes")
	var saved := source.snapshot()

	var restored := _make_overlay("population-source-a")
	_check(restored != null and restored.restore(saved), "valid named overlay snapshot restores")
	if restored != null:
		_equal(restored.snapshot(), saved, "snapshot restore preserves IDs, claims, places, demographics and provenance exactly")
		_equal(restored.state_fingerprint(), source.state_fingerprint(), "restored named overlay fingerprint is identical")

	var wrong_source := _make_overlay("population-source-b")
	_check(
		wrong_source != null and not wrong_source.restore(saved),
		"population source fingerprint mismatch fails closed"
	)
	if wrong_source != null:
		_equal(wrong_source.person_count(), 0, "source fingerprint rejection does not import persons")

	var live := _make_overlay("population-source-a")
	if live == null:
		_check(false, "atomic restore fixture configures")
		return
	_check(_materialize(live, "person:resident", "claim:resident", "country_fra", "place:paris"), "atomic restore live state materializes")
	var live_before := live.snapshot()

	var malformed := saved.duplicate(true)
	var persons := malformed.get("persons") as Array
	(persons[1] as Dictionary)["current_place_id"] = "place:missing"
	_check(not live.restore(malformed), "malformed snapshot is rejected")
	_equal(live.snapshot(), live_before, "malformed restore does not partially pollute live overlay")

	var extra_field := saved.duplicate(true)
	(extra_field.get("persons") as Array)[0]["unexpected"] = true
	_check(not live.restore(extra_field), "snapshot records with extra fields fail closed")
	_equal(live.snapshot(), live_before, "extra-field rejection preserves live overlay")

	var bad_alive := saved.duplicate(true)
	(bad_alive.get("persons") as Array)[0]["alive"] = 1
	_check(not live.restore(bad_alive), "non-boolean alive field fails strict restore validation")
	_equal(live.snapshot(), live_before, "bad alive type rejection preserves live overlay")


func _test_player_authority_binding() -> void:
	var overlay := _make_overlay("population-source-a")
	if overlay == null:
		_check(false, "player binding overlay configures")
		return
	_check(_materialize(overlay, "person:alice", "claim:alice", "country_fra", "place:paris"), "player binding person materializes")
	var player := VNextPlayerState.new()
	_check(player.bind_person_authority(overlay), "PlayerState binds named Person authority")
	_check(player.set_player_id("person:alice"), "bound PlayerState accepts existing Person")
	_equal(player.player_id(), "person:alice", "bound PlayerState stores existing Person ID")
	_check(not player.set_player_id("person:unknown"), "bound PlayerState rejects unknown Person")
	_equal(player.player_id(), "person:alice", "unknown Player Person rejection preserves current selection")

	var saved := player.snapshot()
	var invalid_restore := saved.duplicate(true)
	invalid_restore["player_id"] = "person:unknown"
	_check(not player.restore(invalid_restore), "bound PlayerState restore rejects unknown Person")
	_equal(player.snapshot(), saved, "failed bound Player restore is atomic")

	var other_overlay := _make_overlay("population-source-a")
	_check(other_overlay != null and not player.bind_person_authority(other_overlay), "PlayerState cannot silently switch Person authority owners")


func _test_legacy_unbound_player_compatibility() -> void:
	var legacy := VNextPlayerState.new("person:legacy_player")
	_check(legacy.is_valid(), "legacy unbound PlayerState constructor remains compatible")
	_equal(legacy.player_id(), "person:legacy_player", "legacy unbound player ID is retained")
	var target := VNextPlayerState.new()
	_check(target.restore(legacy.snapshot()), "legacy unbound PlayerState snapshot still restores")
	_equal(target.snapshot(), legacy.snapshot(), "legacy unbound PlayerState round trip is unchanged")


func _make_overlay(source_fingerprint: String) -> VNextNamedPersonOverlay:
	return VNextNamedPersonOverlay.create(
		Callable(self, "_population_total"),
		Callable(self, "_place_exists"),
		source_fingerprint
	)


func _population_total(territory_id: String) -> int:
	return int(_population_totals.get(territory_id, -1))


func _place_exists(place_id: String) -> bool:
	return bool(_known_places.get(place_id, false))


func _materialize(
	overlay: VNextNamedPersonOverlay,
	person_id: String,
	claim_id: String,
	territory_id: String,
	place_id: String
) -> bool:
	return overlay.materialize(
		person_id,
		claim_id,
		territory_id,
		{
			"birth_year": 1870,
			"sex": "unspecified",
			"basis": "test_fixture",
		},
		place_id,
		{
			"kind": "test_fixture",
			"population_source_fingerprint": "population-source-a",
		}
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
