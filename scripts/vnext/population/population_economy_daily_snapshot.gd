class_name VNextPopulationEconomyDailySnapshot
extends RefCounted
## Immutable pair of Population projections for one Economy settlement day.

const SNAPSHOT_SCHEMA_ID: String = "vnext_population_economy_daily_snapshot_v1"

var _initialized: bool = false
var _labor_snapshot: VNextLaborSnapshot = null
var _demand_population_snapshot: VNextDemandPopulationSnapshot = null


static func create(
	labor_snapshot: VNextLaborSnapshot,
	demand_population_snapshot: VNextDemandPopulationSnapshot
) -> VNextPopulationEconomyDailySnapshot:
	var snapshot := VNextPopulationEconomyDailySnapshot.new()
	if not snapshot._configure(labor_snapshot, demand_population_snapshot):
		return null
	return snapshot


func _configure(
	labor_snapshot: VNextLaborSnapshot,
	demand_population_snapshot: VNextDemandPopulationSnapshot
) -> bool:
	if (
		labor_snapshot == null
		or demand_population_snapshot == null
		or not labor_snapshot.is_valid()
		or not demand_population_snapshot.is_valid()
		or labor_snapshot.settlement_period() != demand_population_snapshot.settlement_period()
		or labor_snapshot.source_population_period() != demand_population_snapshot.source_population_period()
		or labor_snapshot.covered_population() != demand_population_snapshot.covered_population()
	):
		return false
	_labor_snapshot = labor_snapshot
	_demand_population_snapshot = demand_population_snapshot
	_initialized = true
	return true


func is_valid() -> bool:
	return (
		_initialized
		and _labor_snapshot != null
		and _demand_population_snapshot != null
		and _labor_snapshot.is_valid()
		and _demand_population_snapshot.is_valid()
		and _labor_snapshot.settlement_period() == _demand_population_snapshot.settlement_period()
		and _labor_snapshot.source_population_period() == _demand_population_snapshot.source_population_period()
		and _labor_snapshot.covered_population() == _demand_population_snapshot.covered_population()
	)


func settlement_period() -> int:
	return -1 if not is_valid() else _labor_snapshot.settlement_period()


func source_population_period() -> int:
	return -1 if not is_valid() else _labor_snapshot.source_population_period()


func labor_snapshot() -> VNextLaborSnapshot:
	return _labor_snapshot if is_valid() else null


func demand_population_snapshot() -> VNextDemandPopulationSnapshot:
	return _demand_population_snapshot if is_valid() else null


func snapshot() -> Dictionary:
	if not is_valid():
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"settlement_period": settlement_period(),
		"source_population_period": source_population_period(),
		"labor": _labor_snapshot.snapshot(),
		"demand_population": _demand_population_snapshot.snapshot(),
	}
