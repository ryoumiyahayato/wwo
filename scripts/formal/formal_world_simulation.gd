class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. Immutable evidence, current political
## identity, and economic aggregates remain separate owned boundaries.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v4"
const EVIDENCE_STATE_SCHEMA_ID: String = "historical_political_evidence_v1"

var _provenance := HistoricalProvenanceFoundation.new()
var _historical_evidence := HistoricalPoliticalEvidenceCatalog.new()
var _political_registry := RuntimePoliticalEntityRegistry.new()
var _historical_evidence_view := HistoricalPoliticalEvidenceView.new()
var _political_registry_view := RuntimePoliticalEntityView.new()
var _economic_evidence := FormalWorldEconomicEvidenceCatalog.new()
var _economic_static_view := FormalWorldEconomicStaticView.new()
var _population_input_view := FormalWorldPopulationInputView.new()
var _market_registry := FormalWorldMarketRegistry.new()
var _market_registry_view := FormalWorldMarketView.new()
var _economy := FormalWorldEconomyService.new()
var economy: FormalWorldEconomyView:
	get:
		return economy_view()
var initialized: bool = false
var initialization_error: String = ""
var total_minutes: int = 0
var _initialization_attempted: bool = false
var _minute_remainder: int:
	get:
		return total_minutes % 60


func _init() -> void:
	_economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)


func initialize() -> bool:
	if _initialization_attempted:
		initialization_error = "Formal world composition is already initialized"
		return false
	_initialization_attempted = true
	initialization_error = ""
	total_minutes = 0
	if not _provenance.load_current():
		initialization_error = _provenance.initialization_error
		initialized = false
		return false
	if not _historical_evidence.configure(
		HistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,
		_provenance.gate()
	):
		initialization_error = _historical_evidence.initialization_error
		initialized = false
		return false
	if not _political_registry.configure(_historical_evidence):
		initialization_error = _political_registry.initialization_error
		initialized = false
		return false
	if not _economic_evidence.configure(_provenance.gate()):
		initialization_error = _economic_evidence.initialization_error
		initialized = false
		return false
	_refresh_read_only_views()
	if not _configure_market_registry():
		initialization_error = _market_registry.initialization_error
		initialized = false
		return false
	_refresh_read_only_views()
	if not _economy.configure(
		_political_registry_view,
		_market_registry_view,
		_economic_static_view,
		_population_input_view
	):
		initialization_error = _economy.initialization_error
		initialized = false
		return false
	initialized = true
	state_changed.emit({"initialized": true})
	return true


func historical_evidence_view() -> HistoricalPoliticalEvidenceView:
	return _historical_evidence_view


func provenance_gate() -> HistoricalProvenanceGate:
	return _provenance.gate()


func political_registry_view() -> RuntimePoliticalEntityView:
	return _political_registry_view


func market_registry_view() -> FormalWorldMarketView:
	return _market_registry_view


func economy_view() -> FormalWorldEconomyView:
	if not _economy.is_configured():
		return FormalWorldEconomyView.new()
	return FormalWorldEconomyView.new(_economy.read_only_snapshot())


func economy_regression_snapshot() -> Dictionary:
	return _economy.legacy_regression_snapshot()


func advance_minutes(minutes: int) -> Dictionary:
	if not initialized or minutes <= 0:
		return _economy.world_summary()
	var previous_total_hour := _authoritative_total_hour()
	total_minutes += minutes
	var current_total_hour := _authoritative_total_hour()
	var elapsed_hours := current_total_hour - previous_total_hour
	if elapsed_hours > 0:
		var summary := _economy.settle_hour_range(
			previous_total_hour, current_total_hour
		)
		state_changed.emit({
			"time": true,
			"economy": true,
			"hours": elapsed_hours,
		})
		return summary
	state_changed.emit({"time": true, "economy": false, "hours": 0})
	return _economy.world_summary()


func world_summary() -> Dictionary:
	var result := _economy.world_summary()
	result["world_political_unit_count"] = _political_registry.entity_count()
	result["historical_political_record_count"] = _historical_evidence.record_count()
	result["background_polity_count"] = maxi(
		0,
		_political_registry.entity_count()
		- int(result.get("detailed_polity_unit_count", 0))
	)
	return result


func country_summary(entity_id: String) -> Dictionary:
	return _economy.country_summary(entity_id)


func polity_summary(entity_id: String) -> Dictionary:
	var result := CurrentWorldPoliticalProjection.polity_summary(
		entity_id, _political_registry_view, _historical_evidence_view
	)
	if result.is_empty():
		return {}
	var economy_id := _economy.economy_entity_for_polity(entity_id)
	var detailed := not economy_id.is_empty()
	result["has_detailed_economy"] = detailed
	result["economy_entity_id"] = economy_id
	result["major_roster"] = detailed
	result["primary_playable"] = false
	result["playability_tier"] = "background_npc"
	result["playability_tier_zh"] = "背景政治单元"
	if detailed:
		var economy_summary := _economy.country_summary(economy_id)
		result["economy"] = economy_summary
		result["rank"] = int(economy_summary.get("rank", 0))
		result["playability_tier"] = str(
			economy_summary.get("playability_tier", "secondary_roster")
		)
		result["playability_tier_zh"] = str(
			economy_summary.get("playability_tier_zh", "次要政权候选")
		)
		result["primary_playable"] = bool(
			economy_summary.get("primary_playable", false)
		)
	return result


func has_polity(entity_id: String) -> bool:
	return _political_registry.has_entity(entity_id)


func first_polity_id() -> String:
	var ids := _political_registry.entity_ids()
	return ids[0] if not ids.is_empty() else ""


func current_world_political_units() -> Array[Dictionary]:
	return CurrentWorldPoliticalProjection.map_units(
		_political_registry_view, _historical_evidence_view
	)


func historical_political_evidence_units() -> Array[Dictionary]:
	return _historical_evidence_view.records()


func historical_record(source_historical_id: String) -> Dictionary:
	return _historical_evidence_view.record(source_historical_id)


func historical_records_active_on(date: String) -> Array[Dictionary]:
	return _historical_evidence_view.records_active_on(date)


func date_time() -> Dictionary:
	var value := V2DateTime.from_total_hour(_authoritative_total_hour())
	value["minute"] = _minute_remainder
	return value


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"total_minutes": total_minutes,
		"minute_remainder": _minute_remainder,
		"historical_evidence": {
			"schema_id": EVIDENCE_STATE_SCHEMA_ID,
			"fingerprint": _historical_evidence.fingerprint(),
		},
		"runtime_politics": _political_registry.snapshot(),
		"markets": _market_registry.get_persistent_state(),
		"economy": _economy.get_persistent_state(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var candidate := FormalWorldSimulation.new()
	if not candidate.initialize():
		return false
	if not candidate._restore_candidate_state(state):
		return false
	_adopt_candidate(candidate)
	state_changed.emit({"restored": true})
	return true


func _restore_candidate_state(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in [
			"formal_world_simulation_v1",
			"formal_world_simulation_v2",
			"formal_world_simulation_v3",
			SCHEMA_ID,
		]
		or not state.get("economy", {}) is Dictionary
	):
		return false
	var validated_time := _validated_time_state(state, schema_id)
	if validated_time.is_empty():
		return false
	if schema_id in ["formal_world_simulation_v3", SCHEMA_ID]:
		if (
			not state.get("historical_evidence", {}) is Dictionary
			or not state.get("runtime_politics", {}) is Dictionary
		):
			return false
		var evidence_state := state.get("historical_evidence", {}) as Dictionary
		if (
			str(evidence_state.get("schema_id", ""))
			!= EVIDENCE_STATE_SCHEMA_ID
			or str(evidence_state.get("fingerprint", ""))
			!= _historical_evidence.fingerprint()
			or not _political_registry.restore_snapshot(
				state.get("runtime_politics", {}) as Dictionary,
				_historical_evidence
			)
		):
			return false
		_refresh_read_only_views()
		if not _economy.bind_runtime_political_view(_political_registry_view):
			return false
	if schema_id == SCHEMA_ID:
		if (
			not state.get("markets", {}) is Dictionary
			or not _market_registry.validate_persistent_state(
				state.get("markets", {}) as Dictionary
			)
		):
			return false
	total_minutes = int(validated_time.get("total_minutes", -1))
	if not _economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	):
		return false
	initialized = true
	return true


func _adopt_candidate(candidate: FormalWorldSimulation) -> void:
	total_minutes = candidate.total_minutes
	_provenance = candidate._provenance
	_historical_evidence = candidate._historical_evidence
	_political_registry = candidate._political_registry
	_historical_evidence_view = candidate._historical_evidence_view
	_political_registry_view = candidate._political_registry_view
	_economic_evidence = candidate._economic_evidence
	_economic_static_view = candidate._economic_static_view
	_population_input_view = candidate._population_input_view
	_market_registry = candidate._market_registry
	_market_registry_view = candidate._market_registry_view
	_economy = candidate._economy
	_economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)
	initialized = true
	initialization_error = ""


func _refresh_read_only_views() -> void:
	_historical_evidence_view = HistoricalPoliticalEvidenceView.new(
		_historical_evidence.read_only_snapshot()
	)
	_political_registry_view = RuntimePoliticalEntityView.new(
		_political_registry.snapshot()
	)
	_economic_static_view = FormalWorldEconomicStaticView.new(
		_economic_evidence.economic_snapshot()
	)
	_population_input_view = FormalWorldPopulationInputView.new(
		_economic_evidence.population_snapshot()
	)
	_market_registry_view = FormalWorldMarketView.new(
		_market_registry.read_only_snapshot()
	)


func _configure_market_registry() -> bool:
	var economic_aggregate_ids: Array[String] = []
	for record: Dictionary in _economic_static_view.countries():
		var economic_aggregate_id := str(record.get("entity_id", ""))
		if not economic_aggregate_id.is_empty():
			economic_aggregate_ids.append(economic_aggregate_id)
	return _market_registry.configure(
		economic_aggregate_ids, _political_registry_view.entity_ids()
	)


func save_to_user() -> SaveOperationResult:
	if not initialized:
		return SaveOperationResult.fail(
			"not_initialized",
			"正式世界尚未初始化，无法保存。",
			SAVE_PATH
		)
	var snapshot := get_persistent_state()
	var write_error := AtomicJsonFileStore.write_verified(
		SAVE_PATH,
		snapshot,
		Callable(self, "_verify_temporary_save"),
		true
	)
	if not write_error.is_empty():
		return SaveOperationResult.fail(
			"write_error",
			"正式世界保存失败：%s" % write_error,
			SAVE_PATH
		)
	state_changed.emit({"saved": true})
	var result := SaveOperationResult.ok(SAVE_PATH, snapshot)
	result.message = "正式世界已保存。"
	return result


func _verify_temporary_save(absolute_path: String) -> String:
	var loaded := _read_snapshot_file(absolute_path)
	if not loaded.success:
		return "临时存档校验失败：%s" % loaded.message
	var candidate := FormalWorldSimulation.new()
	if not candidate.initialize():
		return "临时存档校验失败：正式世界初始化失败：%s" % (
			candidate.initialization_error
		)
	if not candidate.restore_persistent_state(loaded.snapshot):
		return "临时存档校验失败：正式世界状态无效"
	return ""


func load_from_user() -> SaveOperationResult:
	var primary := _restore_snapshot_file(SAVE_PATH)
	if primary.success:
		primary.message = "正式世界存档已恢复。"
		return primary
	var backup_path := SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	var backup := _restore_snapshot_file(backup_path)
	if backup.success:
		backup.path = SAVE_PATH
		backup.message = "主存档不可用，已读取安全备份"
		return backup
	return SaveOperationResult.fail(
		"load_error",
		"主存档不可用：%s；安全备份不可用：%s" % [
			primary.message,
			backup.message,
		],
		SAVE_PATH
	)


func _restore_snapshot_file(path: String) -> SaveOperationResult:
	var loaded := _read_snapshot_file(path)
	if not loaded.success:
		return loaded
	if not restore_persistent_state(loaded.snapshot):
		return SaveOperationResult.fail(
			"restore_error",
			"存档状态校验或恢复失败",
			path
		)
	return loaded


func _read_snapshot_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "存档不存在", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error",
			error_string(FileAccess.get_open_error()),
			path
		)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			],
			path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"存档根节点必须是对象",
			path
		)
	return SaveOperationResult.ok(path, parser.data as Dictionary)


func _authoritative_total_hour() -> int:
	return int(total_minutes / 60)


func _validated_time_state(state: Dictionary, schema_id: String) -> Dictionary:
	var economy_state := state.get("economy", {}) as Dictionary
	var saved_total_hour := int(economy_state.get("total_hour", -1))
	if saved_total_hour < 0:
		return {}
	if schema_id in [
		"formal_world_simulation_v2",
		"formal_world_simulation_v3",
		SCHEMA_ID,
	] and (
		not state.has("total_minutes") or not state.has("minute_remainder")
	):
		return {}
	var has_total_minutes := state.has("total_minutes")
	var has_minute_remainder := state.has("minute_remainder")
	var total := int(state.get("total_minutes", saved_total_hour * 60))
	var remainder := int(state.get("minute_remainder", posmod(total, 60)))
	if not has_total_minutes and has_minute_remainder:
		total = saved_total_hour * 60 + remainder
	if (
		total < 0
		or remainder < 0
		or remainder > 59
		or posmod(total, 60) != remainder
		or int(total / 60) != saved_total_hour
	):
		return {}
	return {
		"total_minutes": total,
		"minute_remainder": remainder,
	}
