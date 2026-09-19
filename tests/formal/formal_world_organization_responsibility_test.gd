extends SceneTree

const MINUTES_PER_DAY: int = 24 * 60
const TOTAL_DAYS: int = 365
const STEP_INVARIANCE_DAYS: int = 21

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_formal_save()
	_test_production_composition_and_detached_boundary()
	_test_focused_case_lifecycle()
	_test_step_size_invariance()
	_test_v8_migration_without_fabricated_history()
	_test_reset_lifecycle()
	_test_production_zero_player_persistence_and_trajectory()
	_cleanup_formal_save()
	print(
		"Formal organization standing responsibilities: %d checks, %d failures"
		% [checks, failures]
	)
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_production_composition_and_detached_boundary() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "production responsibility world initializes")
	if not world.initialized:
		return
	var organizations := world.organization_view()
	var evidence := world.organization_evidence_view()
	var responsibilities := world.organization_responsibility_view()
	_equal(
		responsibilities.responsibility_count(),
		evidence.organization_count(),
		"every production governing Organization receives exactly one responsibility"
	)
	var coverage := responsibilities.coverage_summary()
	_equal(
		int(coverage.get("responsibility_count", -1)),
		evidence.organization_count(),
		"responsibility coverage derives from production Organization composition"
	)
	_check(
		int(coverage.get("detailed_economy_count", 0)) > 0,
		"production responsibilities include detailed Economy mappings"
	)
	_equal(
		int(coverage.get("detailed_economy_count", 0))
		+ int(coverage.get("no_detailed_economy_count", 0)),
		responsibilities.responsibility_count(),
		"detailed and no-detail Economy coverage accounts for every responsibility"
	)
	for organization_id: String in evidence.organization_ids():
		var state := responsibilities.responsibility_state(organization_id)
		_equal(
			str(state.get("responsibility_id", "")),
			FormalWorldOrganizationResponsibilityService.RESPONSIBILITY_ID,
			"production responsibility kind is controlled: %s" % organization_id
		)
		_equal(
			str(state.get("basis_class", "")),
			FormalWorldOrganizationResponsibilityService.BASIS_CLASS,
			"standing responsibility is classified as generated simulation assumption: %s"
			% organization_id
		)
		_equal(
			str(state.get("represented_polity_id", "")),
			evidence.represented_polity_id(organization_id),
			"responsibility preserves represented polity: %s" % organization_id
		)
		_equal(
			organizations.member_ids(organization_id),
			[],
			"monitoring fabricates no Organization member: %s" % organization_id
		)
		_equal(
			organizations.position_ids(organization_id),
			[],
			"monitoring fabricates no Organization position: %s" % organization_id
		)
		_equal(
			organizations.appointment_ids(organization_id),
			[],
			"monitoring fabricates no Organization appointment: %s" % organization_id
		)
		if str(state.get("economy_entity_id", "")).is_empty():
			_equal(
				str(state.get("status", "")),
				FormalWorldOrganizationResponsibilityService.STATUS_NO_DETAILED_ECONOMY,
				"missing detailed Economy is explicit rather than treated as healthy: %s"
				% organization_id
			)
	var first_id := responsibilities.organization_ids()[0]
	var detached := responsibilities.responsibility_state(first_id)
	detached["status"] = "MUTATED"
	var detached_snapshot := responsibilities.snapshot()
	(detached_snapshot.get("responsibilities", []) as Array).clear()
	_check(
		world.organization_responsibility_view().responsibility_status(first_id)
		!= "MUTATED",
		"responsibility query results are deeply detached"
	)
	_check(
		world.organization_responsibility_query_port()
		is FormalWorldOrganizationResponsibilityView,
		"Formal exposes one detached Organization responsibility query port"
	)


func _test_focused_case_lifecycle() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "focused lifecycle fixture world initializes")
	if not world.initialized:
		return
	var selected := _first_detailed_responsibility(world)
	_check(not selected.is_empty(), "focused lifecycle finds a detailed Economy responsibility")
	if selected.is_empty():
		return
	var organization_id := str(selected.get("organization_id", ""))
	var represented_polity_id := str(selected.get("represented_polity_id", ""))
	var runtime_polity_id := world.political_registry_view().runtime_id_for_source(
		represented_polity_id
	)
	var economy_entity_id := str(selected.get("economy_entity_id", ""))
	var service := FormalWorldOrganizationResponsibilityService.new()
	_check(
		service.configure(
			world.organization_view(),
			world.organization_evidence_view(),
			world.political_registry_view(),
			_economy_fixture(0, runtime_polity_id, economy_entity_id, [], 10000),
			0
		),
		"focused responsibility owner configures from detached inputs"
	)
	if not service.is_configured():
		return

	var shortage_a := [{"commodity_id": "fixture_food", "unmet_units": 10.0}]
	var shortage_b := [{"commodity_id": "fixture_food", "unmet_units": 12.0}]
	var previous := _record_from_service(service, organization_id)
	_check(
		service.review_settled_day(
			24,
			world.organization_view(),
			world.political_registry_view(),
			_economy_fixture(24, runtime_polity_id, economy_entity_id, shortage_a, 9200)
		),
		"shortage day opens institutional attention"
	)
	var opened := _record_from_service(service, organization_id)
	_assert_transition(previous, opened, "open")
	_equal(
		str(opened.get("status", "")),
		FormalWorldOrganizationResponsibilityService.STATUS_ATTENTION_REQUIRED,
		"shortage transitions MONITORING to ATTENTION_REQUIRED"
	)
	var opened_case := opened.get("current_case", {}) as Dictionary
	_equal(int(opened_case.get("duration_days", 0)), 1, "new case starts at one attention day")
	var case_id := str(opened_case.get("case_id", ""))
	_check(not case_id.is_empty(), "opened case has deterministic identity")

	previous = opened
	_check(
		service.review_settled_day(
			48,
			world.organization_view(),
			world.political_registry_view(),
			_economy_fixture(48, runtime_polity_id, economy_entity_id, shortage_b, 9000)
		),
		"sustained shortage reviews same case"
	)
	var sustained := _record_from_service(service, organization_id)
	_assert_transition(previous, sustained, "sustain")
	_equal(
		str((sustained.get("current_case", {}) as Dictionary).get("case_id", "")),
		case_id,
		"sustained shortage does not create a daily duplicate case"
	)
	_equal(
		int((sustained.get("current_case", {}) as Dictionary).get("duration_days", 0)),
		2,
		"sustained case duration advances by settled day"
	)

	previous = sustained
	_check(
		service.review_settled_day(
			72,
			world.organization_view(),
			world.political_registry_view(),
			_economy_fixture(72, runtime_polity_id, economy_entity_id, [], 10000)
		),
		"recovery closes active case"
	)
	var closed := _record_from_service(service, organization_id)
	_assert_transition(previous, closed, "close")
	_equal(
		str(closed.get("status", "")),
		FormalWorldOrganizationResponsibilityService.STATUS_MONITORING,
		"recovery returns responsibility to MONITORING"
	)
	_check((closed.get("current_case", {}) as Dictionary).is_empty(), "recovery clears current case")
	_equal(int(closed.get("closed_episode_count", 0)), 1, "closure counter advances")
	_equal(int(closed.get("recovered_episode_count", 0)), 1, "natural recovery counter advances")
	_equal(
		str((closed.get("last_closed_case", {}) as Dictionary).get("case_id", "")),
		case_id,
		"compact last-closed summary retains the closed case identity"
	)

	previous = closed
	_check(
		service.review_settled_day(
			96,
			world.organization_view(),
			world.political_registry_view(),
			_economy_fixture(96, runtime_polity_id, economy_entity_id, shortage_a, 9100)
		),
		"recurrent shortage opens a new episode"
	)
	var reopened := _record_from_service(service, organization_id)
	_assert_transition(previous, reopened, "reopen")
	var reopened_case := reopened.get("current_case", {}) as Dictionary
	_check(
		str(reopened_case.get("case_id", "")) != case_id,
		"recurrence has a distinct deterministic case identity"
	)
	_equal(int(reopened.get("episode_count", 0)), 2, "episode sequence advances exactly once")
	_equal(
		int(reopened.get("cumulative_attention_days", 0)),
		3,
		"attention-day counter includes open and sustained shortage reviews only"
	)

	var saved := service.snapshot()
	var restored_service := FormalWorldOrganizationResponsibilityService.new()
	var current_fixture := _economy_fixture(
		96, runtime_polity_id, economy_entity_id, shortage_a, 9100
	)
	_check(
		restored_service.configure(
			world.organization_view(),
			world.organization_evidence_view(),
			world.political_registry_view(),
			current_fixture,
			96
		),
		"responsibility restore candidate configures"
	)
	_check(
		restored_service.restore(
			saved,
			world.organization_view(),
			world.organization_evidence_view(),
			world.political_registry_view(),
			current_fixture,
			96
		),
		"responsibility snapshot restores candidate-first"
	)
	_equal(restored_service.snapshot(), saved, "responsibility snapshot restores exactly")
	var malformed := saved.duplicate(true)
	var malformed_records := malformed.get("responsibilities", []) as Array
	malformed_records.append((malformed_records[0] as Dictionary).duplicate(true))
	var rejected := FormalWorldOrganizationResponsibilityService.new()
	_check(
		rejected.configure(
			world.organization_view(),
			world.organization_evidence_view(),
			world.political_registry_view(),
			current_fixture,
			96
		),
		"malformed restore candidate configures"
	)
	_check(
		not rejected.restore(
			malformed,
			world.organization_view(),
			world.organization_evidence_view(),
			world.political_registry_view(),
			current_fixture,
			96
		),
		"duplicate responsibility snapshot fails closed"
	)


func _test_step_size_invariance() -> void:
	var bulk := FormalWorldSimulation.new()
	var daily := FormalWorldSimulation.new()
	var hourly := FormalWorldSimulation.new()
	_check(bulk.initialize(), "bulk step-size world initializes")
	_check(daily.initialize(), "daily step-size world initializes")
	_check(hourly.initialize(), "hourly step-size world initializes")
	if not bulk.initialized or not daily.initialized or not hourly.initialized:
		return
	bulk.advance_minutes(STEP_INVARIANCE_DAYS * MINUTES_PER_DAY)
	for _day: int in range(STEP_INVARIANCE_DAYS):
		daily.advance_minutes(MINUTES_PER_DAY)
	for _hour: int in range(STEP_INVARIANCE_DAYS * 24):
		hourly.advance_minutes(60)
	var bulk_state := bulk.get_persistent_state()
	var daily_state := daily.get_persistent_state()
	var hourly_state := hourly.get_persistent_state()
	_equal(
		bulk_state.get("economy"),
		daily_state.get("economy"),
		"Economy state is invariant between bulk and daily advancement"
	)
	_equal(
		bulk_state.get("economy"),
		hourly_state.get("economy"),
		"Economy state is invariant between bulk and hourly advancement"
	)
	_equal(
		bulk_state.get("organization_responsibilities"),
		daily_state.get("organization_responsibilities"),
		"responsibility history is invariant between bulk and daily advancement"
	)
	_equal(
		bulk_state.get("organization_responsibilities"),
		hourly_state.get("organization_responsibilities"),
		"responsibility history is invariant between bulk and hourly advancement"
	)
	_equal(
		bulk.authoritative_fingerprint(),
		daily.authoritative_fingerprint(),
		"complete world fingerprint is invariant between bulk and daily advancement"
	)
	_equal(
		bulk.authoritative_fingerprint(),
		hourly.authoritative_fingerprint(),
		"complete world fingerprint is invariant between bulk and hourly advancement"
	)


func _test_v8_migration_without_fabricated_history() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "v8 migration source initializes")
	if not source.initialized:
		return
	source.advance_minutes(20 * MINUTES_PER_DAY)
	var legacy := source.get_persistent_state().duplicate(true)
	legacy["schema_id"] = FormalWorldSimulation.PREVIOUS_SCHEMA_ID
	legacy.erase("organization_responsibilities")
	var migrated := FormalWorldSimulation.new()
	_check(migrated.initialize(), "v8 migration target initializes")
	_check(
		migrated.restore_persistent_state(legacy),
		"v8 world migrates to responsibility baseline"
	)
	if not migrated.initialized:
		return
	var migrated_snapshot := migrated.organization_responsibility_view().snapshot()
	var migrated_coverage := migrated.organization_responsibility_view().coverage_summary()
	_equal(
		int(migrated_snapshot.get("baseline_hour", -1)),
		20 * 24,
		"v8 migration baseline starts at saved authoritative hour"
	)
	_equal(
		int(migrated_coverage.get("total_review_count", -1)),
		0,
		"v8 migration fabricates no past responsibility reviews"
	)
	_equal(
		int(migrated_coverage.get("attention_episodes_opened", -1)),
		0,
		"v8 migration fabricates no historical shortage episodes"
	)
	_equal(
		int(migrated_coverage.get("cumulative_attention_days", -1)),
		0,
		"v8 migration fabricates no historical attention days"
	)
	for organization_id: String in migrated.organization_responsibility_view().organization_ids():
		var record := migrated.organization_responsibility_view().responsibility_state(
			organization_id
		)
		_equal(
			int(record.get("last_reviewed_day", -2)),
			-1,
			"v8 migration does not claim a historical review: %s" % organization_id
		)
	migrated.advance_minutes(MINUTES_PER_DAY)
	_equal(
		int(
			migrated.organization_responsibility_view().coverage_summary().get(
				"total_review_count", -1
			)
		),
		migrated.organization_responsibility_view().responsibility_count(),
		"first post-migration day boundary begins normal review lifecycle"
	)


func _test_reset_lifecycle() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "reset responsibility world initializes")
	if not world.initialized:
		return
	world.advance_minutes(15 * MINUTES_PER_DAY)
	_check(
		int(world.organization_responsibility_view().coverage_summary().get("total_review_count", 0))
		> 0,
		"pre-reset responsibility state has review history"
	)
	_check(world.reset_world(), "Formal reset replaces responsibility lifecycle owner")
	var view := world.organization_responsibility_view()
	_equal(
		view.responsibility_count(),
		world.organization_evidence_view().organization_count(),
		"reset recomposes deterministic production responsibility coverage"
	)
	_equal(
		int(view.coverage_summary().get("total_review_count", -1)),
		0,
		"reset leaks no responsibility review history"
	)
	_equal(
		int(view.coverage_summary().get("attention_episodes_opened", -1)),
		0,
		"reset leaks no old case history"
	)


func _test_production_zero_player_persistence_and_trajectory() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "zero-player production world initializes")
	if not world.initialized:
		return
	var initial := world.get_persistent_state()
	var initial_player := (initial.get("player", {}) as Dictionary).duplicate(true)
	var initial_organization := (
		initial.get("organization", {}) as Dictionary
	).duplicate(true)
	var initial_authority := (
		initial.get("organization_authority", {}) as Dictionary
	).duplicate(true)
	var initial_military := (
		initial.get("military_state", {}) as Dictionary
	).duplicate(true)
	var initial_politics := (
		initial.get("runtime_politics", {}) as Dictionary
	).duplicate(true)

	var midpoint_day := -1
	for day: int in range(1, TOTAL_DAYS + 1):
		world.advance_minutes(MINUTES_PER_DAY)
		var coverage := world.organization_responsibility_view().coverage_summary()
		if (
			int(coverage.get("attention_episodes_opened", 0)) > 0
			and int(coverage.get("open_case_count", 0)) > 0
		):
			midpoint_day = day
			break
	_check(
		midpoint_day > 0,
		"real production Economy shortage opens an institutional case without player action"
	)
	if midpoint_day <= 0:
		return

	var pre_save_world_fingerprint := world.authoritative_fingerprint()
	var pre_save_responsibility_fingerprint := (
		world.organization_responsibility_view().state_fingerprint()
	)
	var midpoint_state := world.get_persistent_state()
	print("RESPONSIBILITY_PRE_SAVE_FINGERPRINT=%s" % pre_save_world_fingerprint)
	print(
		"RESPONSIBILITY_PRE_SAVE_STATE_FINGERPRINT=%s"
		% pre_save_responsibility_fingerprint
	)
	_cleanup_formal_save()
	var save_result := world.save_to_user()
	_check(save_result.success, "nontrivial responsibility world saves through production save_to_user")
	var restored := FormalWorldSimulation.new()
	var load_result := restored.load_from_user()
	_check(load_result.success, "nontrivial responsibility world loads through production load_from_user")
	if not load_result.success:
		return
	var post_load_world_fingerprint := restored.authoritative_fingerprint()
	var post_load_responsibility_fingerprint := (
		restored.organization_responsibility_view().state_fingerprint()
	)
	print("RESPONSIBILITY_POST_LOAD_FINGERPRINT=%s" % post_load_world_fingerprint)
	print(
		"RESPONSIBILITY_POST_LOAD_STATE_FINGERPRINT=%s"
		% post_load_responsibility_fingerprint
	)
	_equal(
		post_load_world_fingerprint,
		pre_save_world_fingerprint,
		"production save/load preserves complete authoritative fingerprint exactly"
	)
	_equal(
		post_load_responsibility_fingerprint,
		pre_save_responsibility_fingerprint,
		"production save/load preserves responsibility owner fingerprint exactly"
	)
	_equal(
		restored.get_persistent_state(),
		midpoint_state,
		"production save/load preserves nontrivial responsibility snapshot exactly"
	)

	restored.advance_minutes((TOTAL_DAYS - midpoint_day) * MINUTES_PER_DAY)
	var final_state := restored.get_persistent_state()
	var final_fingerprint := restored.authoritative_fingerprint()
	var reference := FormalWorldSimulation.new()
	_check(reference.initialize(), "uninterrupted responsibility reference initializes")
	if not reference.initialized:
		return
	reference.advance_minutes(TOTAL_DAYS * MINUTES_PER_DAY)
	var reference_state := reference.get_persistent_state()
	var reference_fingerprint := reference.authoritative_fingerprint()
	print("RESPONSIBILITY_RESTORED_FINAL_FINGERPRINT=%s" % final_fingerprint)
	print("RESPONSIBILITY_UNINTERRUPTED_FINAL_FINGERPRINT=%s" % reference_fingerprint)
	_equal(
		final_fingerprint,
		reference_fingerprint,
		"save-restored and uninterrupted responsibility trajectories are exact"
	)
	_equal(
		final_state.get("economy"),
		reference_state.get("economy"),
		"responsibility observer does not create a divergent Economy trajectory"
	)
	_equal(
		final_state.get("organization_responsibilities"),
		reference_state.get("organization_responsibilities"),
		"responsibility continuation matches uninterrupted institutional history"
	)

	var final_view := restored.organization_responsibility_view()
	var final_coverage := final_view.coverage_summary()
	_check(
		int(final_coverage.get("total_review_count", 0)) > 0,
		"zero-player production world performs standing-responsibility reviews"
	)
	_check(
		int(final_coverage.get("detailed_economy_count", 0)) > 0,
		"zero-player production world observes detailed economies"
	)
	_check(
		int(final_coverage.get("attention_episodes_opened", 0)) > 0,
		"real production shortages leave institutional attention episodes"
	)
	_check(
		int(final_coverage.get("cumulative_attention_days", 0)) > 0,
		"real production shortages accumulate institutional attention days"
	)
	_check(
		int(final_coverage.get("max_episode_duration_days", 0)) > 1,
		"at least one production shortage case persists across multiple reviews"
	)
	_equal(
		final_state.get("player"),
		initial_player,
		"zero-player Organization monitoring leaves PlayerState unchanged"
	)
	_equal(
		final_state.get("organization"),
		initial_organization,
		"zero-player Organization monitoring leaves OrganizationCore unchanged"
	)
	_equal(
		final_state.get("organization_authority"),
		initial_authority,
		"routine monitoring leaves OrganizationAuthority unchanged"
	)
	_equal(
		final_state.get("military_state"),
		initial_military,
		"routine monitoring leaves Military unchanged"
	)
	_equal(
		final_state.get("runtime_politics"),
		initial_politics,
		"routine monitoring leaves runtime politics unchanged"
	)

	var diagnostic := {
		"midpoint_day": midpoint_day,
		"responsibility_count": final_view.responsibility_count(),
		"detailed_economy_count": int(final_coverage.get("detailed_economy_count", 0)),
		"no_detailed_economy_count": int(final_coverage.get("no_detailed_economy_count", 0)),
		"total_review_count": int(final_coverage.get("total_review_count", 0)),
		"attention_episodes_opened": int(final_coverage.get("attention_episodes_opened", 0)),
		"cumulative_attention_days": int(final_coverage.get("cumulative_attention_days", 0)),
		"open_case_count": int(final_coverage.get("open_case_count", 0)),
		"recovered_episode_count": int(final_coverage.get("recovered_episode_count", 0)),
		"max_episode_duration_days": int(final_coverage.get("max_episode_duration_days", 0)),
		"pre_save_fingerprint": pre_save_world_fingerprint,
		"post_load_fingerprint": post_load_world_fingerprint,
		"restored_final_fingerprint": final_fingerprint,
		"uninterrupted_final_fingerprint": reference_fingerprint,
	}
	print("FORMAL_ORGANIZATION_RESPONSIBILITY_PRODUCTION=%s" % JSON.stringify(diagnostic))


func _first_detailed_responsibility(world: FormalWorldSimulation) -> Dictionary:
	var view := world.organization_responsibility_view()
	for organization_id: String in view.organization_ids():
		var record := view.responsibility_state(organization_id)
		if not str(record.get("economy_entity_id", "")).is_empty():
			return record
	return {}


func _record_from_service(
	service: FormalWorldOrganizationResponsibilityService,
	organization_id: String
) -> Dictionary:
	return FormalWorldOrganizationResponsibilityView.new(
		service.read_only_snapshot()
	).responsibility_state(organization_id)


func _economy_fixture(
	total_hour: int,
	runtime_polity_id: String,
	economy_entity_id: String,
	shortages: Array,
	fulfillment_bp: int
) -> FormalWorldEconomyView:
	return FormalWorldEconomyView.new({
		"schema_id": "formal_world_economy_observation_v2",
		"total_hour": total_hour,
		"economy_by_polity_id": {runtime_polity_id: economy_entity_id},
		"country_summaries": {
			economy_entity_id: {
				"economic_aggregate_id": economy_entity_id,
				"fulfillment_bp": fulfillment_bp,
				"top_shortages": shortages.duplicate(true),
				"active_shipments": 0,
			},
		},
	})


func _assert_transition(
	before: Dictionary,
	after: Dictionary,
	label: String
) -> void:
	if (
		str(before.get("status", "")) == str(after.get("status", ""))
		and before.get("current_case", {}) == after.get("current_case", {})
		and int(after.get("review_count", 0)) == int(before.get("review_count", 0)) + 1
	):
		return
	if int(after.get("review_count", 0)) == int(before.get("review_count", 0)) + 1:
		return
	_print_transition_diagnostic(before, after, label)
	_check(false, "%s transition advances exactly one review" % label)


func _print_transition_diagnostic(
	before: Dictionary,
	after: Dictionary,
	label: String
) -> void:
	print("RESPONSIBILITY_FAILURE_LABEL=%s" % label)
	print("RESPONSIBILITY_ORGANIZATION_ID=%s" % str(after.get("organization_id", "")))
	print("RESPONSIBILITY_POLITY_ID=%s" % str(after.get("represented_polity_id", "")))
	print("RESPONSIBILITY_ID=%s" % str(after.get("responsibility_id", "")))
	print("RESPONSIBILITY_ECONOMY_MAPPING=%s" % str(after.get("economy_entity_id", "")))
	print("RESPONSIBILITY_OBSERVED_FULFILLMENT=%s" % str(after.get("current_fulfillment_bp", -1)))
	print("RESPONSIBILITY_OBSERVED_SHORTAGES=%s" % JSON.stringify(after.get("current_shortages", [])))
	print("RESPONSIBILITY_PREVIOUS_STATUS=%s" % str(before.get("status", "")))
	print("RESPONSIBILITY_NEW_STATUS=%s" % str(after.get("status", "")))
	print("RESPONSIBILITY_PREVIOUS_CASE=%s" % JSON.stringify(before.get("current_case", {})))
	print("RESPONSIBILITY_NEW_CASE=%s" % JSON.stringify(after.get("current_case", {})))
	print("RESPONSIBILITY_FINGERPRINT_BEFORE=%s" % JSON.stringify(before).sha256_text())
	print("RESPONSIBILITY_FINGERPRINT_AFTER=%s" % JSON.stringify(after).sha256_text())


func _cleanup_formal_save() -> void:
	for path: String in [
		FormalWorldSimulation.SAVE_PATH,
		FormalWorldSimulation.SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s | expected=%s actual=%s" % [
		label,
		str(expected),
		str(actual),
	])
