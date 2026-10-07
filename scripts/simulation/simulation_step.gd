class_name SimulationStep
extends RefCounted
## Cross-domain boundary order only. Domain algorithms remain in their owners.

var _clock: GameClock
var _spatial: VNextSpatialWorld
var _economy_state: FormalWorldEconomyState
var _economy: FormalWorldEconomySimulation
var _responsibilities: FormalWorldOrganizationResponsibilityService
var _organization: OrganizationState
var _politics: RuntimePoliticalEntityView
var _personal_economy: FormalPersonalEconomyState

func _init(clock: GameClock, spatial: VNextSpatialWorld, economy_state: FormalWorldEconomyState, economy: FormalWorldEconomySimulation, responsibilities: FormalWorldOrganizationResponsibilityService, organization: OrganizationState, politics: RuntimePoliticalEntityView, personal_economy: FormalPersonalEconomyState) -> void:
	_clock = clock
	_spatial = spatial
	_economy_state = economy_state
	_economy = economy
	assert(_economy == null or _economy._state == _economy_state, "Economy computation and observation must share one state")
	_responsibilities = responsibilities
	_organization = organization
	_politics = politics
	_personal_economy = personal_economy

func advance_minutes(minutes: int) -> Dictionary:
	if _clock == null or _spatial == null or _economy == null or _economy_state == null or _responsibilities == null or _organization == null or _politics == null or _personal_economy == null:
		return _error("Missing GameClock / Spatial / Economy / Organization dependencies")
	if minutes < 0 or minutes > 9223372036854775807 - _clock.total_minutes():
		return _error("Invalid advance %d at minute %d" % [minutes, _clock.total_minutes()])
	if minutes == 0:
		return {"time": false, "economy": false}
	var starting_total_hour := _clock.current_hour()
	var target_total_minutes := _clock.total_minutes() + minutes
	var target_total_hour := int(target_total_minutes / 60)
	var settled_through_hour := starting_total_hour
	var responsibility_review_days := 0
	var wages_paid: int = 0
	var wages_failed: int = 0
	var responsibility_organization_view: FormalWorldOrganizationView = null

	# This scheduler owns causal cross-domain ordering. Each crossed day is
	# settled by Economy first, then observed through detached read views by
	# Organization responsibilities. The structural Organization view is immutable
	# during one advance call, so build it once on first review and never cache it
	# across calls. Economy observations remain fresh for every settled day.
	while true:
		var next_day_boundary_hour := (
			int(settled_through_hour / FormalWorldEconomyState.HOURS_PER_DAY) + 1
		) * FormalWorldEconomyState.HOURS_PER_DAY
		if next_day_boundary_hour > target_total_hour:
			break
		if not _clock.advance_minutes(next_day_boundary_hour * 60 - _clock.total_minutes()):
			return {"success": false, "error": _clock.error}
		if not _synchronize_spatial_to_authoritative_hour():
			return _error("Spatial failed at day boundary hour %d" % next_day_boundary_hour)
		_economy.settle_hour_range(
			settled_through_hour, next_day_boundary_hour
		)
		if responsibility_organization_view == null:
			responsibility_organization_view = FormalWorldOrganizationView.new(_organization.snapshot())
		var reviewed := _responsibilities.review_settled_day(
			next_day_boundary_hour,
			responsibility_organization_view,
			_politics,
			FormalWorldEconomyView.new(_economy_state.read_only_country_observation_snapshot())
		)
		if not reviewed:
			return _error("Organization responsibility review failed at hour %d" % next_day_boundary_hour)
		responsibility_review_days += 1
		var wages := _personal_economy.settle_due_wages()
		wages_paid += int(wages["paid_periods"])
		wages_failed += int(wages["failed_periods"])
		settled_through_hour = next_day_boundary_hour

	if not _clock.advance_minutes(target_total_minutes - _clock.total_minutes()):
		return {"success": false, "error": _clock.error}
	var current_total_hour := _clock.current_hour()
	if current_total_hour > settled_through_hour:
		if not _synchronize_spatial_to_authoritative_hour():
			return _error("Spatial failed at hour %d" % current_total_hour)
		_economy.settle_hour_range(
			settled_through_hour, current_total_hour
		)
	var elapsed_hours := current_total_hour - starting_total_hour
	var final_wages := _personal_economy.settle_due_wages()
	wages_paid += int(final_wages["paid_periods"])
	wages_failed += int(final_wages["failed_periods"])
	return {
		"time": true,
		"economy": elapsed_hours > 0,
		"organization_responsibilities": responsibility_review_days > 0,
		"hours": elapsed_hours,
		"responsibility_review_days": responsibility_review_days,
		"wages_paid": wages_paid,
		"wages_failed": wages_failed,
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
