class_name AlphaSaveMigration
extends RefCounted
## Read-only V2.2/V2.3 to Alpha migration; obsolete geometry is intentionally rebuilt.


func migrate_v2_3_snapshot(source: Dictionary) -> V2LifeLoopResult:
	var source_errors: Array[String] = V23SaveService.new().validate_snapshot(
		source
	)
	if not source_errors.is_empty():
		return V2LifeLoopResult.fail(
			"invalid_v2_3_save",
			"V2.3 存档无法迁移",
			"; ".join(source_errors)
		)
	var simulation := AlphaSimulationService.new()
	if not simulation.initialize():
		return V2LifeLoopResult.fail(
			"migration_initialization_failed",
			"无法建立 Alpha 迁移环境",
			simulation.initialization_error
		)
	var saved_hour: int = V2DateTime.total_hour_from_iso(
		str(source.get("current_datetime", ""))
	)
	if saved_hour < 0:
		return V2LifeLoopResult.fail(
			"invalid_v2_3_time", "V2.3 存档时间无效"
		)
	var saved_value: Dictionary = V2DateTime.from_total_hour(saved_hour)
	if not simulation.clock.set_datetime_for_debug(
		int(saved_value.get("year", 1900)),
		int(saved_value.get("month", 1)),
		int(saved_value.get("day", 1)),
		int(saved_value.get("hour", 0))
	):
		return V2LifeLoopResult.fail(
			"migration_clock_failed", "无法迁移权威时间"
		)
	if not _restore_compatible_v2_domains(source, simulation):
		return V2LifeLoopResult.fail(
			"migration_domain_failed",
			"V2.3 兼容生活领域无法迁移"
		)
	simulation.random.set_seed(int(source.get("random_seed", 2301900)))
	simulation.random.restore_state(int(
		source.get("random_state", simulation.random.get_state())
	))
	simulation.selected_person_id = simulation.roster.player_character_id
	simulation.processed_idempotency_keys = (
		source.get("processed_idempotency_keys", {}) as Dictionary
	).duplicate(true)
	simulation.hours_processed = int(source.get("hours_processed", 0))
	simulation._configure_shared_schedule(
		simulation.v2_3_config.social_people(), saved_hour
	)
	_migrate_past_activities(source, simulation.schedule, saved_hour)
	simulation._replace_fixed_commutes(saved_hour, "alpha_migration")
	simulation._sync_formal_person_states()
	_migrate_legacy_cash(source, simulation, saved_hour)
	var snapshot: Dictionary = simulation.get_alpha_persistent_state()
	snapshot["migration"] = {
		"source_schema_version": V23LifeLoopSimulation.V2_3_SCHEMA_VERSION,
		"target_schema_version": AlphaSimulationService.ALPHA_SCHEMA_VERSION,
		"migrated_datetime": V2DateTime.iso_from_total_hour(saved_hour),
		"source_digest": str(
			(source.get("integrity", {}) as Dictionary).get("digest", "")
		),
		"preserved": [
			"time",
			"past_schedule",
			"household",
			"legacy_ledger",
			"conditions",
			"employment",
			"relationships",
			"notifications",
			"rng",
			"idempotency",
		],
		"rebuilt": [
			"obsolete_map_geometry",
			"future_commutes",
			"spatial_locations",
			"routes",
			"alpha_economy",
			"alpha_organizations",
		],
		"source_file_modified": false,
	}
	snapshot["integrity"] = {
		"algorithm": "sha256",
		"digest": AlphaSaveService._digest(snapshot),
	}
	var errors: Array[String] = AlphaSaveService.new().validate_snapshot(snapshot)
	if not errors.is_empty():
		return V2LifeLoopResult.fail(
			"migration_validation_failed",
			"迁移结果未通过 Alpha 校验",
			"; ".join(errors)
		)
	return V2LifeLoopResult.ok(
		"V2.3 存档已在内存中确定性迁移，原文件未修改",
		{"snapshot": snapshot, "summary": snapshot["migration"]},
		[
			V23LifeLoopSimulation.V2_3_SCHEMA_VERSION,
			AlphaSimulationService.ALPHA_SCHEMA_VERSION,
		]
	)


func migrate_v2_2_snapshot(source: Dictionary) -> V2LifeLoopResult:
	var to_v2_3: V2LifeLoopResult = V23SaveMigration.new().migrate_snapshot(
		source
	)
	if not to_v2_3.success:
		return to_v2_3
	var result: V2LifeLoopResult = migrate_v2_3_snapshot(
		to_v2_3.data.get("snapshot", {}) as Dictionary
	)
	if result.success:
		var snapshot: Dictionary = result.data.get("snapshot", {}) as Dictionary
		var migration: Dictionary = snapshot.get("migration", {}) as Dictionary
		migration["source_schema_version"] = V2LifeLoopSimulation.SCHEMA_VERSION
		migration["migration_chain"] = [
			V2LifeLoopSimulation.SCHEMA_VERSION,
			V23LifeLoopSimulation.V2_3_SCHEMA_VERSION,
			AlphaSimulationService.ALPHA_SCHEMA_VERSION,
		]
		snapshot["migration"] = migration
		snapshot["integrity"] = {
			"algorithm": "sha256",
			"digest": AlphaSaveService._digest(snapshot),
		}
		result.data["snapshot"] = snapshot
		result.data["summary"] = migration
	return result


func migrate_v2_3_file(
	source_path: String = V23SaveService.REVIEW_PATH,
	target_path: String = AlphaSaveService.REVIEW_PATH
) -> SaveOperationResult:
	var source: SaveOperationResult = V23SaveService.new().load(source_path)
	if not source.success:
		return source
	var migrated: V2LifeLoopResult = migrate_v2_3_snapshot(source.snapshot)
	if not migrated.success:
		return SaveOperationResult.fail(
			migrated.error_code, migrated.user_message, target_path
		)
	return AlphaSaveService.new().save_snapshot(
		migrated.data.get("snapshot", {}) as Dictionary, target_path
	)


func _restore_compatible_v2_domains(
	source: Dictionary, simulation: AlphaSimulationService
) -> bool:
	return (
		simulation.employment.restore_persistent_state(
			source["pay_period_states"] as Dictionary
		)
		and simulation.households.restore_persistent_state(
			source["household_state"] as Dictionary
		)
		and simulation.ledger.restore_persistent_state(
			source["ledgers"] as Dictionary
		)
		and simulation.conditions.restore_persistent_state(
			source["condition_state"] as Dictionary
		)
		and simulation.relationships.restore_persistent_state(
			source["relationships"] as Dictionary
		)
		and simulation.organizations.restore_persistent_state(
			source["union_participation"] as Dictionary
		)
		and simulation.notifications.restore_persistent_state(
			source["notifications"] as Dictionary
		)
	)


func _migrate_legacy_cash(
	source: Dictionary, simulation: AlphaSimulationService, saved_hour: int
) -> void:
	var household_state: Dictionary = source.get(
		"household_state", {}
	) as Dictionary
	var household_index: Dictionary = household_state.get(
		"households", {}
	) as Dictionary
	var person_index: Dictionary = household_state.get(
		"person_to_household", {}
	) as Dictionary
	for person_id: String in [
		V2LifeLoopSimulation.PIERRE_ID,
		V2LifeLoopSimulation.ALBERT_ID,
	]:
		if not simulation.economy.entity_profiles.has(person_id):
			continue
		var household_id: String = str(person_index.get(person_id, ""))
		var household: Dictionary = household_index.get(
			household_id, {}
		) as Dictionary
		var desired: int = int(household.get("cash_centimes", 0))
		var actual: int = simulation.economy.ledger.owner_cash(person_id)
		var delta: int = desired - actual
		if delta == 0:
			continue
		var account_id: String = simulation.economy.ledger.cash_account_id(
			person_id
		)
		var entries: Array = [
			{
				"account_id": AlphaLedgerService.SYSTEM_OPENING_ACCOUNT,
				"delta_centimes": -delta,
			},
			{"account_id": account_id, "delta_centimes": delta},
		]
		simulation.economy.ledger.post(
			"migration:cash:%s" % person_id,
			saved_hour,
			"migration_opening_cash",
			"fact:migration_cash:%s" % person_id,
			entries,
			"迁移既有人物现金"
		)


func _migrate_past_activities(
	source: Dictionary,
	target_schedule: V2ScheduleService,
	saved_hour: int
) -> void:
	var source_schedule: Dictionary = source.get(
		"schedule_state", {}
	) as Dictionary
	var schedules: Dictionary = source_schedule.get("schedules", {}) as Dictionary
	var preserved: Array[Dictionary] = []
	for raw_person_id: Variant in schedules:
		for raw_activity: Variant in schedules[raw_person_id] as Array:
			if not raw_activity is Dictionary:
				continue
			var activity: Dictionary = raw_activity as Dictionary
			if int(activity.get("end_hour", 0)) > saved_hour:
				continue
			var migrated: Dictionary = activity.duplicate(true)
			migrated["activity_id"] = "alpha_migrated:%s" % str(
				activity.get("activity_id", "")
			)
			preserved.append(migrated)
	preserved.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_end: int = int(left.get("end_hour", 0))
		var right_end: int = int(right.get("end_hour", 0))
		return (
			str(left.get("activity_id", "")) < str(right.get("activity_id", ""))
			if left_end == right_end else left_end < right_end
		)
	)
	if preserved.size() > 256:
		preserved = preserved.slice(preserved.size() - 256)
	target_schedule.recent_completed_activities = preserved
