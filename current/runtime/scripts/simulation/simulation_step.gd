class_name SimulationStep
extends RefCounted
## Cross-domain boundary order only. Domain algorithms remain in their owners.

signal safe_boundary

var processing: bool = false
var local_operation_guard: Callable
var _economy_r1: EconomyR1Slice
var _clock: GameClock
var _spatial: VNextSpatialWorld
var _economy_state: FormalWorldEconomyState
var _economy: FormalWorldEconomySimulation
var _responsibilities: FormalWorldOrganizationResponsibilityService
var _organization: OrganizationState
var _politics: RuntimePoliticalEntityView
var _personal_economy: FormalPersonalEconomyState
var _travel: FormalPersonTravel

func _init(clock: GameClock, spatial: VNextSpatialWorld, economy_state: FormalWorldEconomyState, economy: FormalWorldEconomySimulation, responsibilities: FormalWorldOrganizationResponsibilityService, organization: OrganizationState, politics: RuntimePoliticalEntityView, personal_economy: FormalPersonalEconomyState, economy_r1: EconomyR1Slice = null, travel: FormalPersonTravel = null) -> void:
	_clock = clock
	_spatial = spatial
	_economy_state = economy_state
	_economy = economy
	assert(_economy == null or _economy._state == _economy_state, "Economy computation and observation must share one state")
	_responsibilities = responsibilities
	_organization = organization
	_politics = politics
	_personal_economy = personal_economy
	_economy_r1 = economy_r1
	_travel = travel

func advance_minutes(minutes: int) -> Dictionary:
	if processing: return _error("Formal world is already advancing")
	if local_operation_guard.is_valid() and not bool(local_operation_guard.call()):return {"success":false,"error":"LOCAL_LEASE_ACTIVE"}
	processing = true
	var result := _advance_minutes(minutes)
	processing = false
	if bool(result.get("success", true)): safe_boundary.emit()
	return result

func _advance_minutes(minutes: int) -> Dictionary:
	if _clock == null or _spatial == null or _economy == null or _economy_state == null or _responsibilities == null or _organization == null or _politics == null or _personal_economy == null:
		return _error("Missing GameClock / Spatial / Economy / Organization dependencies")
	if minutes < 0 or minutes > 9223372036854775807 - _clock.total_minutes():
		return _error("Invalid advance %d at minute %d" % [minutes, _clock.total_minutes()])
	if minutes == 0:
		return {"time": false, "economy": false}
	if _economy_r1 != null and (_economy_r1.processing or _economy_r1.day != _clock.current_day()):
		return _error("Native day does not match the formal clock")
	var starting_total_hour := _clock.current_hour()
	var starting_native_day := _economy_r1.day if _economy_r1 != null else 0
	var starting_records := _personal_economy._next_record_sequence
	var target_total_minutes := _clock.total_minutes() + minutes
	var settled_through_hour := starting_total_hour
	var responsibility_review_days := 0
	var wages_paid: int = 0
	var wages_failed: int = 0
	var life_completed: int = 0
	var life_failed: int = 0
	var travellers_arrived: int = 0
	var residences_changed: int = 0
	var responsibility_organization_view: FormalWorldOrganizationView = null

	# Use the existing formal clock for both day boundaries and active personal
	# arrangements. Read only the next active due time, never transaction history.
	while true:
		var next_day_boundary_hour := (int(settled_through_hour/FormalWorldEconomyState.HOURS_PER_DAY)+1)*FormalWorldEconomyState.HOURS_PER_DAY
		var boundary_minute := next_day_boundary_hour*60
		var next_life := _personal_economy.next_consumption_minute()
		if next_life >= 0: boundary_minute = mini(boundary_minute,next_life)
		var next_livelihood := _personal_economy.next_livelihood_boundary()
		if next_livelihood >= 0: boundary_minute = mini(boundary_minute, next_livelihood)
		var next_transport := _economy_r1.next_transport_boundary() if _economy_r1 != null else -1
		if next_transport >= 0: boundary_minute = mini(boundary_minute, next_transport)
		var next_travel := _travel.next_boundary() if _travel != null else -1
		if next_travel >= 0: boundary_minute = mini(boundary_minute, next_travel)
		if boundary_minute > target_total_minutes: break
		if not _clock.advance_minutes(boundary_minute-_clock.total_minutes()): return {"success":false,"error":_clock.error}
		var boundary_hour := _clock.current_hour()
		if boundary_hour > settled_through_hour:
			if not _synchronize_spatial_to_authoritative_hour(): return _error("Spatial failed at formal hour %d" % boundary_hour)
		var arrived: Array[String] = _travel.advance_time() if _travel != null else []
		travellers_arrived += arrived.size()
		# Legacy wages use only their remaining persons. Native arrivals, wages,
		# labor, production and needs then finish before macro observation.
		var wages := _personal_economy.settle_due_wages()
		wages_paid += int(wages.paid_periods)
		wages_failed += int(wages.failed_periods)
		if _economy_r1 != null:
			if not _economy_r1.advance_time(): return _error(_economy_r1.error)
			if boundary_minute == next_day_boundary_hour*60 and not _economy_r1.settle_day(false):
				return _error(_economy_r1.error)
		if _economy_r1 != null and boundary_minute == next_transport and not _economy_r1.dispatch_shared_window(): return _error(_economy_r1.error)
		if _travel != null: _travel.notify_arrivals(arrived)
		var living := _personal_economy.settle_due_consumption()
		life_completed += int(living.completed)
		life_failed += int(living.failed)
		if boundary_hour > settled_through_hour:
			_economy.settle_hour_range(settled_through_hour,boundary_hour,false)
		_personal_economy.apply_livelihood_boundary()
		if boundary_minute == next_day_boundary_hour*60:
			# Finish the old day, commit residence, then admit/exit future economy scopes.
			if _economy_r1 != null: _economy_r1.propose_npc_residences()
			residences_changed += _personal_economy.apply_residence_boundary()
			if _economy_r1 != null: _economy_r1.apply_scope_boundary()
			if responsibility_organization_view == null: responsibility_organization_view = FormalWorldOrganizationView.new(_organization.snapshot())
			if not _responsibilities.review_settled_day(boundary_hour,responsibility_organization_view,_politics,FormalWorldEconomyView.new(_economy_state.read_only_country_observation_snapshot())): return _error("Organization responsibility review failed at hour %d" % boundary_hour)
			responsibility_review_days += 1
		settled_through_hour = boundary_hour

	if not _clock.advance_minutes(target_total_minutes - _clock.total_minutes()):
		return {"success": false, "error": _clock.error}
	var current_total_hour := _clock.current_hour()
	if current_total_hour > settled_through_hour:
		if not _synchronize_spatial_to_authoritative_hour():
			return _error("Spatial failed at hour %d" % current_total_hour)
		_economy.settle_hour_range(
			settled_through_hour, current_total_hour, false
		)
	if _economy_r1 != null and not _economy_r1.advance_time(): return _error(_economy_r1.error)
	var elapsed_hours := current_total_hour - starting_total_hour
	var final_wages := _personal_economy.settle_due_wages()
	wages_paid += int(final_wages["paid_periods"])
	wages_failed += int(final_wages["failed_periods"])
	return {
		"time": true,
		"persons_changed": (_travel != null and minutes > 0) or residences_changed > 0,
		"residences_changed": residences_changed,
		"travellers_arrived": travellers_arrived,
		"economy": elapsed_hours > 0,
		"organization_responsibilities": responsibility_review_days > 0,
		"hours": elapsed_hours,
		"responsibility_review_days": responsibility_review_days,
		"wages_paid": wages_paid,
		"wages_failed": wages_failed,
		"native_changed": _economy_r1 != null and minutes > 0,
		"native_days": (_economy_r1.day - starting_native_day) if _economy_r1 != null else 0,
		"personal_life_changed": _personal_economy._next_record_sequence != starting_records,
		"consumptions_completed":life_completed,
		"consumptions_failed":life_failed,
	}

func _error(message: String) -> Dictionary:
	push_error("SIMULATION STEP DATA ERROR: " + message)
	return {"success": false, "error": message}

func _synchronize_spatial_to_authoritative_hour() -> bool:
	return (
		_spatial != null
		and _spatial.is_valid()
		and _spatial.advance_to_hour(_clock.current_hour())
		and _spatial.current_hour() == _clock.current_hour()
	)
