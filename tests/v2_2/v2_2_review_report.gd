extends SceneTree
## Writes compact, reproducible review summaries without committing artifacts.

const OUTPUT_DIRECTORY: String = "res://artifacts/v2_2_life_loop_review"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(
		OUTPUT_DIRECTORY
	)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_directory
	)
	if directory_error != OK:
		push_error("Cannot create review directory: %s" % error_string(directory_error))
		quit(1)
		return
	var direct := V2LifeLoopSimulation.new()
	if not direct.initialize():
		push_error("Cannot initialize direct review simulation")
		quit(1)
		return
	var started_usec: int = Time.get_ticks_usec()
	direct.run_days(30)
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var final_state: Dictionary = _build_final_state(direct, elapsed_usec)
	if not _write_json(
		"%s/30_day_final_state.json" % absolute_directory, final_state
	):
		quit(1)
		return
	var split := V2LifeLoopSimulation.new()
	if not split.initialize():
		push_error("Cannot initialize split review simulation")
		quit(1)
		return
	split.run_days(10)
	var resumed := V2LifeLoopSimulation.new()
	if not resumed.initialize():
		push_error("Cannot initialize resumed review simulation")
		quit(1)
		return
	var restore_result: V2LifeLoopResult = resumed.restore_persistent_state(
		split.get_persistent_state()
	)
	if not restore_result.success:
		push_error("Cannot restore 10-day review state: %s" % restore_result.error_code)
		quit(1)
		return
	resumed.run_days(20)
	var determinism: Dictionary = _build_determinism_summary(direct, resumed)
	if not _write_json(
		"%s/determinism_comparison.json" % absolute_directory, determinism
	):
		quit(1)
		return
	var performance: Dictionary = {
		"record_type": "headless_life_loop_and_map_architecture_guard",
		"godot_version": Engine.get_version_info().get("string", ""),
		"scenario_id": direct.scenario_id,
		"days": 30,
		"hours_processed": direct.hours_processed,
		"elapsed_usec": elapsed_usec,
		"average_hour_processing_usec": float(elapsed_usec) / 720.0,
		"maximum_hour_processing_usec": direct.maximum_hour_processing_usec,
		"map_maximum_zoom": 96,
		"metropolitan_department_count": 96,
		"life_loop_calls_map_queue_redraw": false,
		"window_drag_metrics": "recorded separately by actual-window performance harness",
	}
	if not _write_json(
		"%s/30_day_headless_performance.json" % absolute_directory,
		performance
	):
		quit(1)
		return
	print("V2.2 review summaries written to %s" % absolute_directory)
	print(
		"30-day final=%s, ledger=%s, determinism=%s"
		% [
			final_state.get("current_datetime", ""),
			final_state.get("ledger_consistent", false),
			determinism.get("all_fields_equal", false),
		]
	)
	quit(0 if bool(determinism.get("all_fields_equal", false)) else 1)


func _build_final_state(
	simulation: V2LifeLoopSimulation, elapsed_usec: int
) -> Dictionary:
	var people: Dictionary = {}
	for person_id: String in [
		V2LifeLoopSimulation.PIERRE_ID,
		V2LifeLoopSimulation.ALBERT_ID,
	]:
		var household: Dictionary = simulation.households.household_for_person(
			person_id
		)
		var contract: Dictionary = simulation.employment.contract_for_person(
			person_id
		)
		people[person_id] = {
			"condition": simulation.conditions.get_state(person_id),
			"cash_centimes": household.get("cash_centimes", 0),
			"food_stock_person_days": household.get(
				"food_stock_person_days", 0
			),
			"essentials_stock_person_days": household.get(
				"essentials_stock_person_days", 0
			),
			"rent_arrears_centimes": household.get(
				"rent_arrears_centimes", 0
			),
			"next_rent_datetime": household.get(
				"next_rent_due_datetime", ""
			),
			"next_pay_datetime": contract.get("next_pay_datetime", ""),
			"employment_risk": simulation.employment.employment_risk(
				person_id
			),
			"future_schedule_hours": simulation.schedule.get_future_horizon(
				person_id, simulation.clock.total_hours
			),
		}
	var category_counts: Dictionary = {}
	for transaction: Dictionary in simulation.ledger.transactions:
		var category: String = str(transaction.get("category", ""))
		category_counts[category] = int(category_counts.get(category, 0)) + 1
	return {
		"record_type": "v2_2_30_day_final_state",
		"schema_version": V2LifeLoopSimulation.SCHEMA_VERSION,
		"scenario_id": simulation.scenario_id,
		"current_datetime": V2DateTime.iso_from_total_hour(
			simulation.clock.total_hours
		),
		"hours_processed": simulation.hours_processed,
		"elapsed_usec": elapsed_usec,
		"ledger_consistent": simulation.ledger_consistency().success,
		"uncovered_person_hours": _count_uncovered_person_hours(simulation),
		"same_priority_overlap_count": _count_schedule_overlaps(simulation),
		"transaction_count": simulation.ledger.transactions.size(),
		"transaction_category_counts": category_counts,
		"processed_pay_period_count": (
			simulation.employment.processed_pay_period_ids.size()
		),
		"processed_household_key_count": (
			simulation.households.processed_idempotency_keys.size()
		),
		"notification_count": simulation.notifications.notifications.size(),
		"causal_event_count": simulation.conditions.causal_events.size(),
		"people": people,
	}


func _build_determinism_summary(
	direct: V2LifeLoopSimulation, resumed: V2LifeLoopSimulation
) -> Dictionary:
	var comparison: Dictionary = V2DeterminismAudit.comparison(direct, resumed)
	return {
		"record_type": "v2_2_direct_30_vs_10_restore_20",
		"schema_version": V2LifeLoopSimulation.SCHEMA_VERSION,
		"comparison_fields": comparison.get("fields", {}),
		"all_fields_equal": comparison.get("all_fields_equal", false),
		"direct_ledger_consistent": direct.ledger_consistency().success,
		"resumed_ledger_consistent": resumed.ledger_consistency().success,
		"direct_current_datetime": V2DateTime.iso_from_total_hour(
			direct.clock.total_hours
		),
		"resumed_current_datetime": V2DateTime.iso_from_total_hour(
			resumed.clock.total_hours
		),
	}


func _count_uncovered_person_hours(simulation: V2LifeLoopSimulation) -> int:
	var uncovered: int = 0
	for person_id: String in [
		V2LifeLoopSimulation.PIERRE_ID,
		V2LifeLoopSimulation.ALBERT_ID,
	]:
		for hour: int in range(
			simulation.clock.total_hours,
			simulation.clock.total_hours + 48
		):
			if simulation.schedule.activity_for_hour(person_id, hour).is_empty():
				uncovered += 1
	return uncovered


func _count_schedule_overlaps(simulation: V2LifeLoopSimulation) -> int:
	var overlaps: int = 0
	for person_id: String in [
		V2LifeLoopSimulation.PIERRE_ID,
		V2LifeLoopSimulation.ALBERT_ID,
	]:
		for hour: int in range(
			simulation.clock.total_hours - 72,
			simulation.clock.total_hours + 72
		):
			var active_count: int = 0
			var best_priority: int = -1
			for raw_activity: Variant in (
				simulation.schedule.schedules.get(person_id, []) as Array
			):
				var activity: Dictionary = raw_activity as Dictionary
				if str(activity.get("status", "")) in [
					"cancelled", "completed", "missed", "interrupted",
				]:
					continue
				if (
					hour >= int(activity.get("start_hour", -1))
					and hour < int(activity.get("end_hour", -1))
				):
					var priority: int = int(
						V2ScheduleService.SOURCE_PRIORITY.get(
							str(activity.get("source", "")), 0
						)
					)
					if priority > best_priority:
						best_priority = priority
						active_count = 1
					elif priority == best_priority:
						active_count += 1
			if active_count > 1:
				overlaps += active_count - 1
	return overlaps


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write review JSON: %s" % path)
		return false
	file.store_string(JSON.stringify(value, "\t", false))
	file.close()
	return true
