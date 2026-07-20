class_name V23SaveMigration
extends RefCounted
## Deterministic in-memory V2.2 to V2.3 migration; source is never modified.


func migrate_snapshot(v2_2_snapshot: Dictionary) -> V2LifeLoopResult:
	var source_errors: Array[String] = GameSaveService.new().validate_v2_2_snapshot(
		v2_2_snapshot
	)
	if not source_errors.is_empty():
		return V2LifeLoopResult.fail(
			"invalid_v2_2_save", "V2.2 存档无法迁移", "; ".join(source_errors)
		)
	var simulation := V23ProductSimulation.new()
	if not simulation.initialize():
		return V2LifeLoopResult.fail(
			"migration_initialization_failed", "无法建立 V2.3 迁移环境",
			simulation.initialization_error
		)
	var saved_hour: int = V2DateTime.total_hour_from_iso(
		str(v2_2_snapshot.get("current_datetime", ""))
	)
	if saved_hour < 0:
		return V2LifeLoopResult.fail("invalid_v2_2_time", "V2.2 存档时间无效")
	var saved_value: Dictionary = V2DateTime.from_total_hour(saved_hour)
	if not simulation.clock.set_datetime_for_debug(
		int(saved_value.get("year", 1900)),
		int(saved_value.get("month", 1)),
		int(saved_value.get("day", 1)),
		int(saved_value.get("hour", 0))
	):
		return V2LifeLoopResult.fail("migration_clock_failed", "无法迁移权威时间")
	if (
		not simulation.employment.restore_persistent_state(
			v2_2_snapshot["pay_period_states"] as Dictionary
		)
		or not simulation.households.restore_persistent_state(
			v2_2_snapshot["household_state"] as Dictionary
		)
		or not simulation.ledger.restore_persistent_state(
			v2_2_snapshot["ledgers"] as Dictionary
		)
		or not simulation.conditions.restore_persistent_state(
			v2_2_snapshot["condition_state"] as Dictionary
		)
		or not simulation.relationships.restore_persistent_state(
			v2_2_snapshot["relationships"] as Dictionary
		)
		or not simulation.organizations.restore_persistent_state(
			v2_2_snapshot["union_participation"] as Dictionary
		)
		or not simulation.notifications.restore_persistent_state(
			v2_2_snapshot["notifications"] as Dictionary
		)
	):
		return V2LifeLoopResult.fail(
			"migration_restore_failed", "V2.2 领域状态无法迁移"
		)
	simulation.random.set_seed(int(v2_2_snapshot.get("random_seed", 2201900)))
	simulation.random.restore_state(int(
		v2_2_snapshot.get("random_state", simulation.random.get_state())
	))
	simulation.selected_person_id = str(
		v2_2_snapshot.get("selected_person_id", V2LifeLoopSimulation.PIERRE_ID)
	)
	simulation.processed_idempotency_keys = (
		v2_2_snapshot["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	simulation.hours_processed = int(v2_2_snapshot.get("hours_processed", 0))
	simulation._configure_shared_schedule(
		simulation.v2_3_config.social_people(), saved_hour
	)
	_migrate_past_activities(
		v2_2_snapshot, simulation.schedule, saved_hour
	)
	_migrate_positions(v2_2_snapshot, simulation, saved_hour)
	_migrate_relationships(v2_2_snapshot, simulation)
	simulation._replace_fixed_commutes(saved_hour, "scenario_initialization")
	simulation._sync_formal_person_states()
	var snapshot: Dictionary = simulation.get_persistent_state()
	snapshot["migration"] = {
		"source_schema_version": "v2_2_life_loop_1",
		"target_schema_version": V23LifeLoopSimulation.V2_3_SCHEMA_VERSION,
		"migrated_datetime": V2DateTime.iso_from_total_hour(saved_hour),
		"source_digest": str(
			(v2_2_snapshot.get("integrity", {}) as Dictionary).get("digest", "")
		),
		"past_activities_preserved": simulation.schedule.recent_completed_activities.size(),
		"future_fixed_commutes_replaced": true,
		"source_file_modified": false,
	}
	snapshot["integrity"] = {
		"algorithm": "sha256",
		"digest": _snapshot_digest(snapshot),
	}
	var validation_errors: Array[String] = V23SaveService.new().validate_snapshot(snapshot)
	if not validation_errors.is_empty():
		return V2LifeLoopResult.fail(
			"migration_validation_failed", "迁移结果未通过 V2.3 校验",
			"; ".join(validation_errors)
		)
	return V2LifeLoopResult.ok(
		"V2.2 存档已在内存中确定性迁移，原文件未修改",
		{"snapshot": snapshot, "summary": snapshot["migration"]},
		["v2_2_life_loop_1", V23LifeLoopSimulation.V2_3_SCHEMA_VERSION]
	)


func migrate_file(
	source_path: String = GameSaveService.V2_2_REVIEW_PATH,
	target_path: String = V23SaveService.REVIEW_PATH
) -> SaveOperationResult:
	var source: SaveOperationResult = GameSaveService.new().load_v2_2_review(source_path)
	if not source.success:
		return source
	var migrated: V2LifeLoopResult = migrate_snapshot(source.snapshot)
	if not migrated.success:
		return SaveOperationResult.fail(
			migrated.error_code, migrated.user_message, target_path
		)
	return V23SaveService.new().save_snapshot(
		migrated.data.get("snapshot", {}) as Dictionary, target_path
	)


func _migrate_positions(
	source: Dictionary,
	simulation: V23LifeLoopSimulation,
	saved_hour: int
) -> void:
	var source_states: Dictionary = source.get("person_states", {}) as Dictionary
	for person_id: String in V23LifeLoopSimulation.FORMAL_PERSON_IDS:
		var old_state: Dictionary = source_states.get(person_id, {}) as Dictionary
		var old_location: String = str(old_state.get("current_location_id", ""))
		var new_location: String = str(
			V23LifeLoopSimulation.LOCATION_ALIASES.get(
				old_location, simulation._home_for(person_id)
			)
		)
		simulation.spatial_locations.force_set_at_location(
			person_id, new_location, saved_hour
		)


func _migrate_relationships(
	source: Dictionary, simulation: V23LifeLoopSimulation
) -> void:
	var source_relationship_state: Dictionary = source.get("relationships", {}) as Dictionary
	var source_relationships: Dictionary = source_relationship_state.get(
		"relationships", {}
	) as Dictionary
	for raw_relation: Variant in source_relationships.values():
		if not raw_relation is Dictionary:
			continue
		var relation: Dictionary = raw_relation as Dictionary
		var person_id: String = str(relation.get("person_id", ""))
		var target_id: String = str(relation.get("target_id", ""))
		if not simulation.dynamic_relationships.has_relationship(person_id, target_id):
			continue
		simulation.dynamic_relationships.set_dimensions(
			person_id, target_id,
			{
				"familiarity": int(relation.get("familiarity", 0)),
				"trust": int(relation.get("trust", 0)),
			}
		)


func _migrate_past_activities(
	source: Dictionary,
	target_schedule: V2ScheduleService,
	saved_hour: int
) -> void:
	var source_schedule: Dictionary = source.get("schedule_state", {}) as Dictionary
	var schedules: Dictionary = source_schedule.get("schedules", {}) as Dictionary
	var preserved: Array[Dictionary] = []
	for raw_person_id: Variant in schedules.keys():
		for raw_activity: Variant in schedules[raw_person_id] as Array:
			if not raw_activity is Dictionary:
				continue
			var activity: Dictionary = raw_activity as Dictionary
			if int(activity.get("end_hour", 0)) > saved_hour:
				continue
			var migrated: Dictionary = activity.duplicate(true)
			migrated["activity_id"] = "migrated:%s" % str(activity.get("activity_id", ""))
			preserved.append(migrated)
	preserved.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_end: int = int(left.get("end_hour", 0))
		var right_end: int = int(right.get("end_hour", 0))
		if left_end != right_end:
			return left_end < right_end
		return str(left.get("activity_id", "")) < str(right.get("activity_id", ""))
	)
	var limit: int = 256
	if preserved.size() > limit:
		preserved = preserved.slice(preserved.size() - limit)
	target_schedule.recent_completed_activities = preserved


static func _snapshot_digest(snapshot: Dictionary) -> String:
	var payload: Dictionary = snapshot.duplicate(true)
	payload.erase("integrity")
	return JSON.stringify(V23SaveService._canonical(payload), "", true).sha256_text()
