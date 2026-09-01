class_name VNextMilitaryFormation
extends RefCounted
## One strategic formation. Individual soldiers are never represented as objects.

const ACTION_IDLE: String = "idle"
const ACTION_MOVING: String = "moving"
const ACTION_CONCENTRATING: String = "concentrating"
const ACTION_ATTACKING: String = "attacking"
const ACTION_DEFENDING: String = "defending"
const STATUS_ACTIVE: String = "active"
const STATUS_DESTROYED: String = "destroyed"
const RESOURCE_IDS: PackedStringArray = ["food", "ammunition", "equipment", "transport_capacity"]
const SUPPLY_STATUSES: PackedStringArray = ["full", "strained", "low", "cut"]

var formation_id: String = ""
var unit_organization_id: String = ""
var country_id: String = ""
var service_branch: String = "army"
var personnel: int = 0
var equipment_sets: Dictionary = {}
var training: float = 0.0
var morale: float = 0.0
var organization: float = 0.0
var current_city_id: String = ""
var action_state: String = ACTION_IDLE
var formation_status: String = STATUS_ACTIVE
var supply_status: String = "full"
var supply_level: float = 1.0
var supply_fill: Dictionary = {}
var defense_posture: float = 1.0
var daily_requirements: Dictionary = {}


func configure(
	id: String,
	owner_country_id: String,
	branch: String,
	starting_personnel: int,
	starting_equipment: Dictionary,
	starting_training: float,
	starting_morale: float,
	starting_organization: float,
	starting_city_id: String,
	requirements: Dictionary = {},
	organization_id: String = ""
) -> bool:
	if (
		VNextStableId.kind_of(id) != "formation"
		or VNextStableId.kind_of(organization_id) != "organization"
		or owner_country_id.is_empty()
		or starting_city_id.is_empty()
	):
		return false
	if starting_personnel < 0:
		return false
	if not _is_unit_float_valid(starting_training) or not _is_unit_float_valid(starting_morale) or not _is_unit_float_valid(starting_organization):
		return false
	formation_id = id
	unit_organization_id = organization_id
	country_id = owner_country_id
	service_branch = branch if not branch.is_empty() else "army"
	personnel = starting_personnel
	equipment_sets = starting_equipment.duplicate(true)
	training = clampf(starting_training, 0.0, 1.0)
	morale = clampf(starting_morale, 0.0, 1.0)
	organization = clampf(starting_organization, 0.0, 1.0)
	current_city_id = starting_city_id
	daily_requirements = _normalize_requirements(requirements, starting_personnel)
	supply_fill = {
		"food": 1.0,
		"ammunition": 1.0,
		"equipment": 1.0,
		"transport_capacity": 1.0,
	}
	supply_level = 1.0
	supply_status = "full"
	action_state = ACTION_IDLE
	formation_status = STATUS_DESTROYED if starting_personnel == 0 else STATUS_ACTIVE
	if formation_status == STATUS_DESTROYED:
		organization = 0.0
		morale = 0.0
	return is_valid()


func is_valid() -> bool:
	if (
		VNextStableId.kind_of(formation_id) != "formation"
		or VNextStableId.kind_of(unit_organization_id) != "organization"
		or country_id.is_empty()
		or current_city_id.is_empty()
		or personnel < 0
	):
		return false
	if formation_status not in [STATUS_ACTIVE, STATUS_DESTROYED]:
		return false
	if formation_status == STATUS_ACTIVE and personnel <= 0:
		return false
	if formation_status == STATUS_DESTROYED and (personnel != 0 or action_state != ACTION_IDLE):
		return false
	if not is_finite(training) or not is_finite(morale) or not is_finite(organization):
		return false
	if training < 0.0 or training > 1.0 or morale < 0.0 or morale > 1.0 or organization < 0.0 or organization > 1.0:
		return false
	if not is_finite(supply_level) or supply_level < 0.0 or supply_level > 1.0:
		return false
	if not is_finite(defense_posture) or defense_posture < 1.0 or defense_posture > 2.5:
		return false
	if not SUPPLY_STATUSES.has(supply_status) or not [
		ACTION_IDLE,
		ACTION_MOVING,
		ACTION_CONCENTRATING,
		ACTION_ATTACKING,
		ACTION_DEFENDING,
	].has(action_state):
		return false
	var configured_equipment: float = float(equipment_sets.get("equipment_factor", 1.0))
	if not is_finite(configured_equipment) or configured_equipment < 0.0 or configured_equipment > 1.5:
		return false
	for resource_id: String in RESOURCE_IDS:
		var fill_value: float = float(supply_fill.get(resource_id, 0.0))
		var requirement: float = float(daily_requirements.get(resource_id, -1.0))
		if not is_finite(fill_value) or fill_value < 0.0 or fill_value > 1.0:
			return false
		if not is_finite(requirement) or requirement < 0.0:
			return false
	return true


func can_receive_orders() -> bool:
	return formation_status == STATUS_ACTIVE and personnel > 0 and action_state == ACTION_IDLE


func equipment_factor() -> float:
	var configured: float = float(equipment_sets.get("equipment_factor", 1.0))
	return clampf(configured, 0.0, 1.5) if is_finite(configured) else 0.0


func movement_efficiency() -> float:
	if formation_status != STATUS_ACTIVE or personnel <= 0:
		return 0.0
	var supply_component: float = clampf(supply_level, 0.0, 1.0)
	var organization_component: float = clampf(organization, 0.0, 1.0)
	var equipment_component: float = clampf(equipment_factor(), 0.0, 1.0)
	var morale_component: float = clampf(morale, 0.0, 1.0)
	# Bounded floor preserves a recovery path, while equipment and organization
	# remain strong enough that stripping equipment cannot make a formation faster.
	return clampf(
		0.15
		+ supply_component * 0.30
		+ organization_component * 0.25
		+ equipment_component * 0.25
		+ morale_component * 0.05,
		0.20,
		1.0
	)


func apply_losses(losses: int) -> int:
	var applied: int = clampi(losses, 0, personnel)
	personnel -= applied
	if personnel <= 0:
		personnel = 0
		organization = 0.0
		morale = 0.0
		action_state = ACTION_IDLE
		formation_status = STATUS_DESTROYED
		defense_posture = 1.0
	return applied


func update_supply(
	new_supply_fill: Dictionary,
	new_supply_level: float,
	new_supply_status: String
) -> void:
	supply_fill = {
		"food": _safe_unit(new_supply_fill.get("food", 0.0)),
		"ammunition": _safe_unit(new_supply_fill.get("ammunition", 0.0)),
		"equipment": _safe_unit(new_supply_fill.get("equipment", 0.0)),
		"transport_capacity": _safe_unit(new_supply_fill.get("transport_capacity", 0.0)),
	}
	supply_level = _safe_unit(new_supply_level)
	supply_status = new_supply_status if SUPPLY_STATUSES.has(new_supply_status) else "cut"


func to_dict() -> Dictionary:
	return {
		"formation_id": formation_id,
		"unit_organization_id": unit_organization_id,
		"country_id": country_id,
		"service_branch": service_branch,
		"personnel": personnel,
		"equipment_sets": equipment_sets.duplicate(true),
		"training": training,
		"morale": morale,
		"organization": organization,
		"current_city_id": current_city_id,
		"action_state": action_state,
		"formation_status": formation_status,
		"supply_status": supply_status,
		"supply_level": supply_level,
		"supply_fill": supply_fill.duplicate(true),
		"defense_posture": defense_posture,
		"daily_requirements": daily_requirements.duplicate(true),
	}


func restore(data: Dictionary) -> bool:
	var restored_equipment: Variant = data.get("equipment_sets", {})
	var restored_fill: Variant = data.get("supply_fill", {})
	var restored_requirements: Variant = data.get("daily_requirements", {})
	var restored_level: float = float(data.get("supply_level", 0.0))
	var restored_posture: float = float(data.get("defense_posture", 1.0))
	var restored_status: String = str(data.get("formation_status", STATUS_ACTIVE))
	if not restored_equipment is Dictionary or not restored_fill is Dictionary or not restored_requirements is Dictionary:
		return false
	if restored_status not in [STATUS_ACTIVE, STATUS_DESTROYED]:
		return false
	if not is_finite(restored_level) or restored_level < 0.0 or restored_level > 1.0:
		return false
	if not is_finite(restored_posture) or restored_posture < 1.0 or restored_posture > 2.5:
		return false
	if not configure(
		str(data.get("formation_id", "")),
		str(data.get("country_id", "")),
		str(data.get("service_branch", "army")),
		int(data.get("personnel", -1)),
		restored_equipment as Dictionary,
		float(data.get("training", -1.0)),
		float(data.get("morale", -1.0)),
		float(data.get("organization", -1.0)),
		str(data.get("current_city_id", "")),
		restored_requirements as Dictionary,
		str(data.get("unit_organization_id", ""))
	):
		return false
	action_state = str(data.get("action_state", ACTION_IDLE))
	formation_status = restored_status
	supply_status = str(data.get("supply_status", "cut"))
	defense_posture = restored_posture
	update_supply(restored_fill as Dictionary, restored_level, supply_status)
	if formation_status == STATUS_DESTROYED:
		if personnel != 0:
			return false
		action_state = ACTION_IDLE
		organization = 0.0
		morale = 0.0
	elif personnel <= 0:
		return false
	return is_valid()


func _normalize_requirements(source: Dictionary, starting_personnel: int) -> Dictionary:
	var defaults: Dictionary = {
		"food": float(starting_personnel) * 0.7,
		"ammunition": float(starting_personnel) * 0.12,
		"equipment": float(starting_personnel) * 0.025,
		"transport_capacity": float(starting_personnel) * 0.08,
	}
	for resource_id: String in defaults:
		if source.has(resource_id):
			var configured: float = float(source[resource_id])
			if is_finite(configured):
				defaults[resource_id] = maxf(0.0, configured)
	return defaults


func _is_unit_float_valid(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


func _safe_unit(value: Variant) -> float:
	var numeric: float = float(value)
	return clampf(numeric, 0.0, 1.0) if is_finite(numeric) else 0.0
