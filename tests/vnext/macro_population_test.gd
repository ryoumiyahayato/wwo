extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_keyed_queries_and_ownership_boundary()
	_test_monthly_accounting_and_structure_consistency()
	_test_two_place_batch_settlement()
	_test_aggregation()
	_test_monthly_equivalence_and_calendar_boundary()
	_test_deterministic_replay()
	_test_snapshot_restore_and_malformed_rejection()
	_test_setup_mutation_boundary()
	_test_age_progression_and_partition_equivalence()
	_test_long_run_is_finite_and_bounded()
	print("VNext macro population: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_keyed_queries_and_ownership_boundary() -> void:
	var population := _new_population()
	if population == null:
		return
	_check(population.has_place("place:alpha"), "place key is registered")
	_check(population.has_place("region:beta"), "existing region key is accepted without a new ID kind")
	_check(
		not population.has_method("register_place"),
		"place registration is not a public population geography API"
	)
	_check(
		not population.has_method("settle_place"),
		"single-place settlement cannot double-advance the world"
	)
	_equal(population.population_at("place:unknown"), -1, "unknown place query fails closed")
	_equal(population.structure_at("place:unknown"), {}, "unknown structure query fails closed")
	_check(
		not VNextStableId.is_valid("population:alpha"),
		"shared stable ID contract remains unchanged and has no population kind"
	)

	_check(
		population.set_initial_state(
			"place:alpha",
			_state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
		),
		"place state can be seeded from a complete macro structure"
	)
	_equal(population.population_at("place:alpha"), 1000, "population_at returns the keyed total")
	_equal(population.working_age_at("place:alpha"), 650, "working_age_at derives 18-64 from coarse buckets")
	_equal(population.age_18_40_at("place:alpha"), 350, "age_18_40_at exposes the requested coarse bucket")
	_equal(
		(population.structure_at("place:alpha").get("sex_structure") as Dictionary).get("male"),
		500,
		"structure_at exposes sex structure"
	)


func _test_monthly_accounting_and_structure_consistency() -> void:
	var population := _new_population()
	if population == null:
		return
	_check(
		population.set_initial_state(
			"place:alpha",
			_state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
		),
		"accounting fixture is seeded"
	)
	_check(
		population.settle_elapsed_months(
			1,
			{"place:alpha": {"births": 20, "deaths": 5, "net_migration": -3}}
		),
		"one month with births, deaths and net migration settles"
	)
	_equal(population.population_at("place:alpha"), 1012, "previous + births - deaths + migration is authoritative")
	var structure: Dictionary = population.structure_at("place:alpha")
	_equal(structure.get("births"), 20, "births are retained as cumulative macro flow")
	_equal(structure.get("deaths"), 5, "deaths are retained as cumulative macro flow")
	_equal(structure.get("net_migration"), -3, "net migration is retained as signed cumulative macro flow")
	_equal(structure.get("last_settled_period"), 1, "one elapsed month advances the period cursor once")
	_equal(population.last_settled_period_at("region:beta"), 1, "all known places share the supplied world period")
	_check(_structure_is_coherent(structure), "all macro structure axes remain nonnegative and reconcile")

	var before: Dictionary = population.snapshot()
	_check(
		not population.settle_elapsed_months(
			1,
			{"place:alpha": {"births": 0, "deaths": 5000, "net_migration": 0}}
		),
		"a transition that would make population negative is rejected"
	)
	_equal(population.snapshot(), before, "rejected transition is transactional")


func _test_two_place_batch_settlement() -> void:
	var forward := _new_population()
	var reverse := _new_population()
	if forward == null or reverse == null:
		return
	var alpha_state: Dictionary = _state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
	var beta_state: Dictionary = _state(500, 100, 175, 150, 75, 240, 260, 300, 200)
	_check(forward.set_initial_state("place:alpha", alpha_state), "batch alpha fixture is seeded")
	_check(forward.set_initial_state("region:beta", beta_state), "batch beta fixture is seeded")
	_check(reverse.set_initial_state("place:alpha", alpha_state), "reordered alpha fixture is seeded")
	_check(reverse.set_initial_state("region:beta", beta_state), "reordered beta fixture is seeded")
	var forward_flows: Dictionary = {
		"place:alpha": {"births": 20, "deaths": 5, "net_migration": -3},
		"region:beta": {"births": 7, "deaths": 2, "net_migration": 4},
	}
	var reverse_flows: Dictionary = {
		"region:beta": {"births": 7, "deaths": 2, "net_migration": 4},
		"place:alpha": {"births": 20, "deaths": 5, "net_migration": -3},
	}
	_check(
		forward.settle_elapsed_months(1, forward_flows),
		"one canonical batch settles both places once"
	)
	_check(
		reverse.settle_elapsed_months(1, reverse_flows),
		"reordered canonical batch settles both places once"
	)
	_equal(
		forward.snapshot(),
		reverse.snapshot(),
		"two-place batch result is insertion-order independent"
	)
	_equal(
		forward.last_settled_period_at("place:alpha"),
		1,
		"batch advances alpha exactly one month"
	)
	_equal(
		forward.last_settled_period_at("region:beta"),
		1,
		"batch advances beta exactly one month"
	)


func _test_aggregation() -> void:
	var population := _new_population()
	if population == null:
		return
	_check(
		population.set_initial_state(
			"place:alpha",
			_state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
		),
		"aggregation alpha fixture is seeded"
	)
	_check(
		population.set_initial_state(
			"region:beta",
			_state(500, 100, 175, 150, 75, 240, 260, 300, 200)
		),
		"aggregation beta fixture is seeded"
	)
	_equal(
		population.aggregate_population(["place:alpha", "region:beta"]),
		1500,
		"aggregate_population sums keyed records"
	)
	var aggregate: Dictionary = population.aggregate_structure(["place:alpha", "region:beta"])
	_equal(
		aggregate.get("working_age_population"),
		975,
		"aggregate structure sums meaningful age-derived working population"
	)
	_equal(
		(aggregate.get("age_buckets") as Dictionary).get("under_18"),
		350,
		"aggregate structure sums age buckets"
	)
	_equal(
		(aggregate.get("urban_rural") as Dictionary).get("urban"),
		900,
		"aggregate structure sums urban/rural structure"
	)
	_check(
		aggregate.get("periods_aligned"),
		"aggregate period is meaningful when source periods are aligned"
	)
	_equal(
		population.aggregate_population(["place:alpha", "place:alpha"]),
		-1,
		"duplicate aggregation keys are rejected"
	)
	_equal(
		population.aggregate_population(["place:missing"]),
		-1,
		"unknown aggregation keys are rejected"
	)


func _test_monthly_equivalence_and_calendar_boundary() -> void:
	var one_call := _new_population()
	var twelve_calls := _new_population()
	if one_call == null or twelve_calls == null:
		return
	var seeded_state: Dictionary = _state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
	_check(one_call.set_initial_state("place:alpha", seeded_state), "12-month one-call fixture is seeded")
	_check(twelve_calls.set_initial_state("place:alpha", seeded_state), "12-month repeated-call fixture is seeded")
	var monthly_flow: Dictionary = {
		"place:alpha": {"births": 4, "deaths": 2, "net_migration": -1},
	}
	_check(
		one_call.settle_elapsed_months(12, monthly_flow),
		"12-month equivalent settlement succeeds in one call"
	)
	for _month_index: int in range(12):
		_check(
			twelve_calls.settle_elapsed_months(1, monthly_flow),
			"one-month settlement succeeds in repeated-call fixture"
		)
	_equal(
		one_call.snapshot(),
		twelve_calls.snapshot(),
		"12 x 1 month equals one 12-month equivalent settlement"
	)

	var boundary := _new_population()
	if boundary == null:
		return
	_check(boundary.settle_absolute_months(0, 11), "absolute months can advance to December 1900")
	_check(
		boundary.settle_year_month(
			1900,
			12,
			2,
			{"place:alpha": {"births": 1}}
		),
		"year/month settlement crosses December to January deterministically"
	)
	_equal(boundary.last_settled_period_at("place:alpha"), 13, "calendar boundary produces absolute cursor 13")
	_equal(
		boundary.next_settlement_year_month_at("place:alpha"),
		{"year": 1901, "month": 2},
		"next settlement period is February 1901 after two settled months"
	)
	_equal(
		VNextMacroPopulation.absolute_month_from_year_month(1900, 1),
		0,
		"January 1900 is absolute month zero"
	)
	_equal(
		VNextMacroPopulation.year_month_from_absolute_month(12),
		{"year": 1901, "month": 1},
		"absolute month conversion is deterministic across year boundary"
	)


func _test_deterministic_replay() -> void:
	var first := _new_population()
	var second := _new_population()
	if first == null or second == null:
		return
	var seeded_state: Dictionary = _state(10000, 2500, 3500, 3000, 1000, 5000, 5000, 6000, 4000)
	_check(first.set_initial_state("place:alpha", seeded_state), "determinism source is seeded")
	_check(second.set_initial_state("place:alpha", seeded_state), "determinism replay is seeded")
	var monthly_flows: Dictionary = {
		"place:alpha": {"births": 31, "deaths": 17, "migration": -4},
	}
	_check(first.settle_elapsed_months(24, monthly_flows), "determinism source settles 24 months")
	_check(second.settle_elapsed_months(24, monthly_flows), "determinism replay settles the same 24 months")
	_equal(first.snapshot(), second.snapshot(), "same seed and elapsed period replay exactly")
	_check(
		first.settle_absolute_months(
			24,
			1,
			{"place:alpha": {"births": 1}}
		),
		"absolute settlement accepts the current cursor"
	)
	_check(
		not first.settle_absolute_months(
			24,
			1,
			{"place:alpha": {"births": 1}}
		),
		"absolute settlement rejects an overlapping period"
	)


func _test_snapshot_restore_and_malformed_rejection() -> void:
	var source := _new_population()
	if source == null:
		return
	_check(
		source.set_initial_state(
			"place:alpha",
			_state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
		),
		"snapshot source is seeded"
	)
	_check(
		source.settle_elapsed_months(
			3,
			{"place:alpha": {"births": 5, "deaths": 2, "net_migration": 1}}
		),
		"snapshot source has settled state"
	)
	var saved: Dictionary = source.snapshot()
	var restored := VNextMacroPopulation.create(["place:alpha", "region:beta"])
	if restored == null:
		return
	_check(restored.restore(saved), "valid snapshot restores into an externally keyed target")
	_equal(restored.snapshot(), saved, "population snapshot round trip preserves complete state")
	_equal(restored.population_at("place:alpha"), 1012, "restored query recovers population total")

	var shell := VNextMacroPopulation.new()
	_check(not shell.restore(saved), "empty shell cannot establish an external key contract")

	var invalid_negative: Dictionary = saved.duplicate(true)
	(invalid_negative["records"] as Array)[0]["total_population"] = -1
	_expect_restore_failure(restored, invalid_negative, "negative population")

	var invalid_nonfinite: Dictionary = saved.duplicate(true)
	(invalid_nonfinite["records"] as Array)[0]["births"] = INF
	_expect_restore_failure(restored, invalid_nonfinite, "non-finite flow")

	var invalid_unknown_place: Dictionary = saved.duplicate(true)
	(invalid_unknown_place["records"] as Array)[0]["place_id"] = "place:unknown"
	_expect_restore_failure(restored, invalid_unknown_place, "unknown record place")

	var invalid_known_and_record: Dictionary = saved.duplicate(true)
	(invalid_known_and_record["known_place_ids"] as Array)[0] = "place:made_up"
	(invalid_known_and_record["records"] as Array)[0]["place_id"] = "place:made_up"
	_expect_restore_failure(
		restored,
		invalid_known_and_record,
		"snapshot key contract changed with record"
	)

	var invalid_region_syntax: Dictionary = saved.duplicate(true)
	(invalid_region_syntax["records"] as Array)[0]["place_id"] = "region:made_up"
	_expect_restore_failure(
		restored,
		invalid_region_syntax,
		"fabricated valid-syntax region key"
	)

	var invalid_age: Dictionary = saved.duplicate(true)
	var invalid_age_buckets: Dictionary = (
		(invalid_age["records"] as Array)[0]["age_buckets"] as Dictionary
	)
	invalid_age_buckets["under_18"] = int(invalid_age_buckets["under_18"]) + 1
	_expect_restore_failure(restored, invalid_age, "age bucket total mismatch")

	var invalid_sex: Dictionary = saved.duplicate(true)
	var invalid_sex_structure: Dictionary = (
		(invalid_sex["records"] as Array)[0]["sex_structure"] as Dictionary
	)
	invalid_sex_structure["male"] = int(invalid_sex_structure["male"]) + 1
	_expect_restore_failure(restored, invalid_sex, "sex total mismatch")

	var invalid_urban_rural: Dictionary = saved.duplicate(true)
	var invalid_urban: Dictionary = (
		(invalid_urban_rural["records"] as Array)[0]["urban_rural"] as Dictionary
	)
	invalid_urban["urban"] = int(invalid_urban["urban"]) + 1
	_expect_restore_failure(restored, invalid_urban_rural, "urban/rural total mismatch")

	var invalid_migration: Dictionary = saved.duplicate(true)
	(invalid_migration["records"] as Array)[0]["net_migration"] = "malformed"
	_expect_restore_failure(restored, invalid_migration, "malformed migration")

	var invalid_duplicate_key: Dictionary = saved.duplicate(true)
	var duplicate_known_ids: Array = invalid_duplicate_key["known_place_ids"] as Array
	duplicate_known_ids.append("place:alpha")
	_expect_restore_failure(
		restored,
		invalid_duplicate_key,
		"duplicate known place key"
	)

	var invalid_duplicate: Dictionary = saved.duplicate(true)
	var duplicate_records: Array = invalid_duplicate["records"] as Array
	duplicate_records[1]["place_id"] = duplicate_records[0]["place_id"]
	_expect_restore_failure(restored, invalid_duplicate, "duplicate place entry")

	var invalid_missing_record: Dictionary = saved.duplicate(true)
	(invalid_missing_record["records"] as Array).remove_at(1)
	_expect_restore_failure(restored, invalid_missing_record, "missing record key")

	var invalid_extra: Dictionary = saved.duplicate(true)
	invalid_extra["unexpected"] = true
	_check(not restored.restore(invalid_extra), "unknown snapshot field is rejected")
	_equal(
		restored.snapshot(),
		saved,
		"all malformed restore attempts leave live state unchanged"
	)


func _test_setup_mutation_boundary() -> void:
	var population := _new_population()
	if population == null:
		return
	var initial_state: Dictionary = _state(1000, 250, 350, 300, 100, 500, 500, 600, 400)
	_check(
		population.set_initial_state("place:alpha", initial_state),
		"setup state mutation succeeds before elapsed settlement"
	)
	_check(
		not population.initialize(["place:alpha", "region:gamma"]),
		"external place contract cannot be reinitialized after construction"
	)
	_check(
		population.settle_elapsed_months(1),
		"one elapsed month starts the immutable live phase"
	)
	var before: Dictionary = population.snapshot()
	_check(
		not population.set_initial_state("place:alpha", initial_state),
		"set_initial_state fails after elapsed settlement"
	)
	_equal(
		population.snapshot(),
		before,
		"late setup mutation leaves live state unchanged"
	)
	_check(
		not population.has_method("register_place"),
		"registering a new place is unavailable after settlement"
	)
	_check(
		not population.initialize(["place:alpha", "region:gamma"]),
		"late external key mutation remains rejected"
	)
	_equal(
		population.snapshot(),
		before,
		"late key mutation attempts leave live state unchanged"
	)


func _test_age_progression_and_partition_equivalence() -> void:
	var aging := _new_population()
	if aging == null:
		return
	var aging_state: Dictionary = _state(100000, 50000, 10000, 30000, 10000, 50000, 50000, 60000, 40000)
	_check(aging.set_initial_state("place:alpha", aging_state), "age progression fixture is seeded")
	var before: Dictionary = aging.structure_at("place:alpha")
	_check(aging.settle_elapsed_months(12), "zero-flow months still progress coarse age buckets")
	var after: Dictionary = aging.structure_at("place:alpha")
	_equal(after["total_population"], before["total_population"], "ageing alone conserves total population")
	_check(
		int(after["age_buckets"]["under_18"]) < int(before["age_buckets"]["under_18"]),
		"under-18 bucket ages forward"
	)
	_check(
		int(after["age_buckets"]["age_18_40"]) > int(before["age_buckets"]["age_18_40"]),
		"under-18 outflow enters working-age bucket"
	)
	_check(
		int(after["age_buckets"]["age_65_plus"]) > int(before["age_buckets"]["age_65_plus"]),
		"41-64 outflow enters terminal older bucket"
	)
	_check(
		int(after["working_age_population"]) != int(before["working_age_population"]),
		"working-age query changes as coarse ages progress"
	)
	_check(_structure_is_coherent(after), "age progression preserves bucket coherence")

	var large := _new_population()
	var sliced := _new_population()
	if large == null or sliced == null:
		return
	_check(large.set_initial_state("place:alpha", aging_state), "large-period fixture is seeded")
	_check(sliced.set_initial_state("place:alpha", aging_state), "sliced-period fixture is seeded")
	_check(large.settle_elapsed_months(120), "large elapsed period settles")
	for _slice: int in range(12):
		_check(sliced.settle_elapsed_months(10), "sliced elapsed period settles")
	_equal(
		large.snapshot(),
		sliced.snapshot(),
		"large elapsed period equals sliced elapsed periods"
	)

	var births := _new_population()
	if births == null:
		return
	var empty_state: Dictionary = _state(0, 0, 0, 0, 0, 0, 0, 0, 0)
	_check(births.set_initial_state("place:alpha", empty_state), "birth placement fixture is seeded")
	_check(
		births.settle_elapsed_months(
			1,
			{"place:alpha": {"births": 100}}
		),
		"birth-only month settles"
	)
	var birth_structure: Dictionary = births.structure_at("place:alpha")
	_equal(
		birth_structure["age_buckets"]["under_18"],
		100,
		"new births enter under-18 and do not skip age buckets"
	)


func _test_long_run_is_finite_and_bounded() -> void:
	var population := _new_population()
	if population == null:
		return
	_check(
		population.set_initial_state(
			"place:alpha",
			_state(100000, 25000, 35000, 30000, 10000, 50000, 50000, 60000, 40000)
		),
		"long-run fixture is seeded"
	)
	_check(
		population.settle_elapsed_months(
			120,
			{"place:alpha": {"births": 100, "deaths": 90, "net_migration": -3}}
		),
		"long-run monthly settlement remains bounded"
	)
	var structure: Dictionary = population.structure_at("place:alpha")
	_check(_structure_is_coherent(structure), "long-run structure remains coherent")
	_check(
		int(structure["total_population"]) < VNextMacroPopulation.MAX_JSON_SAFE_INTEGER,
		"long-run total remains inside JSON-safe bound"
	)
	_check(
		int(structure["net_migration"]) == -360,
		"long-run signed migration remains exact"
	)
	var before: Dictionary = population.snapshot()
	_check(
		not population.settle_elapsed_months(
			1,
			{"place:alpha": {"births": 0, "deaths": 999999999, "net_migration": 0}}
		),
		"impossible long-run death transition is rejected"
	)
	_equal(population.snapshot(), before, "impossible long-run transition is transactional")


func _new_population() -> VNextMacroPopulation:
	var population := VNextMacroPopulation.create(["place:alpha", "region:beta"])
	_check(population != null, "population fixture creates a keyed macro owner")
	return population


func _state(
	total: int,
	under_18: int,
	age_18_40: int,
	age_41_64: int,
	age_65_plus: int,
	female: int,
	male: int,
	urban: int,
	rural: int
) -> Dictionary:
	return {
		"total_population": total,
		"age_buckets": {
			"under_18": under_18,
			"age_18_40": age_18_40,
			"age_41_64": age_41_64,
			"age_65_plus": age_65_plus,
		},
		"sex_structure": {"female": female, "male": male},
		"urban_rural": {"urban": urban, "rural": rural},
	}


func _structure_is_coherent(structure: Dictionary) -> bool:
	if structure.is_empty():
		return false
	var total: int = int(structure.get("total_population", -1))
	var age: Dictionary = structure.get("age_buckets", {}) as Dictionary
	var sex: Dictionary = structure.get("sex_structure", {}) as Dictionary
	var urban_rural: Dictionary = structure.get("urban_rural", {}) as Dictionary
	if total < 0:
		return false
	if _sum(age) != total or _sum(sex) != total or _sum(urban_rural) != total:
		return false
	return (
		int(structure.get("working_age_population", -1))
		== int(age.get("age_18_40", 0)) + int(age.get("age_41_64", 0))
	)


func _sum(values: Dictionary) -> int:
	var result: int = 0
	for value: Variant in values.values():
		if typeof(value) != TYPE_INT or int(value) < 0:
			return -1
		result += int(value)
	return result


func _expect_restore_failure(
	population: VNextMacroPopulation, rejected: Dictionary, label: String
) -> void:
	var before: Dictionary = population.snapshot()
	_check(not population.restore(rejected), "%s snapshot is rejected" % label)
	_equal(population.snapshot(), before, "%s rejection is transactional" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
