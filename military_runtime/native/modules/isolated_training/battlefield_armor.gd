extends "res://military_runtime/native/modules/isolated_training/opponent.gd"
## Optional unoptimized field profile. Infantry and terrain remain their hosts' work.
const Registry = preload("res://military_runtime/native/modules/vehicle_crew/crew_registry.gd")
const AI_COUNT: int = 19
const BLUE_COUNT: int = 9
const RED_COUNT: int = 10
const BUILD_BATCH: int = 2
const CREW_ROLES: Array[String] = ["commander", "gunner", "driver"]
var _registry: Registry
var _preparing: bool = false
var _prepared: bool = false
var _preparation_error: String = ""
var _deployment_rows: Array[Dictionary] = []
var _adopted_position: Vector3 = Vector3.ZERO

func prepare_battlefield(rows: Array[Dictionary], registry: Registry) -> Dictionary:
	if _preparing or _prepared or _bound or not units.is_empty():
		return {"ok": false, "reason": "battlefield_already_bound"}
	var checked: Dictionary = _preflight(rows, registry)
	if not bool(checked.get("ok", false)):
		return _fail_preparation(str(checked.get("reason", "battlefield_preflight_failed")))
	_registry = registry
	_deployment_rows = checked.rows
	_preparing = true
	var generation: int = int(main.stage_generation)
	var stage: Node3D = main.stage
	var existing: Dictionary = _deployment_rows[int(checked.existing_index)]
	_adopted_position = existing.position
	var adopted: Dictionary = _bind_existing_unit(main.target, main.combat, str(existing.id), existing.position)
	if not bool(adopted.get("ok", false)):
		return _fail_preparation(str(adopted.get("reason", "original_opponent_unavailable")))
	var bound: Dictionary = _bind_unit_crew(units[str(existing.id)])
	if not bool(bound.get("ok", false)):
		return _fail_preparation(str(bound.get("reason", "crew_bind_failed")))
	var unit_index: int = 1
	var batch: int = 0
	for row: Dictionary in _deployment_rows:
		if bool(row.existing):
			continue
		if not _same_preparing_stage(stage, generation):
			return _fail_preparation("battlefield_stage_changed")
		if main.vehicle_ammo.vehicles.has(str(row.id)) or not _registry.vehicle(str(row.id)).is_empty():
			return _fail_preparation("battlefield_identity_changed_during_creation")
		var model: Node3D = spawn_unit(str(row.id), str(row.team), row.position, stage, 1, unit_index)
		if not is_instance_valid(model) or not units.has(str(row.id)):
			return _fail_preparation("vehicle_creation_failed")
		for socket: String in ["Turret", "Barrel", "Muzzle", "MG_Muzzle"]:
			if not is_instance_valid(model.find_child(socket, true, false)):
				return _fail_preparation("vehicle_socket_unavailable")
		var unit: Dictionary = units[str(row.id)]
		unit["ballistics"] = Ballistics.configuration({})
		bound = _bind_unit_crew(unit)
		if not bool(bound.get("ok", false)):
			return _fail_preparation(str(bound.get("reason", "crew_bind_failed")))
		unit_index += 1
		batch += 1
		if batch >= BUILD_BATCH:
			batch = 0
			await get_tree().process_frame
	if not _same_preparing_stage(stage, generation) or units.size() != AI_COUNT:
		return _fail_preparation("battlefield_creation_incomplete")
	_preparing = false
	_prepared = true
	return {"ok": true, "ai_vehicles": units.size(), "vehicles_including_player": units.size() + 1, "requires_deployment_check": true}

func _preflight(rows: Array[Dictionary], registry: Registry) -> Dictionary:
	if not is_instance_valid(main) or not is_instance_valid(main.stage) or not is_instance_valid(main.target) or not is_instance_valid(main.ai_host):
		return {"ok": false, "reason": "battlefield_owner_unavailable"}
	if not is_instance_valid(main.crew_host) or registry == null or main.crew_host.registry != registry:
		return {"ok": false, "reason": "battlefield_registry_not_current"}
	if registry.vehicle(main.PLAYER_VEHICLE_ID).is_empty() or main.player_combat.crew.size() != 5:
		return {"ok": false, "reason": "original_player_crew_not_bound"}
	if bool(main.get("session_ready")):
		return {"ok": false, "reason": "battlefield_requires_preparing_session"}
	if rows.size() != AI_COUNT or main.combat.crew.size() != 3:
		return {"ok": false, "reason": "battlefield_vehicle_count_mismatch"}
	if main.models.size() < 2 or not ResourceLoader.exists(str(main.models[1])):
		return {"ok": false, "reason": "scout_model_unavailable"}
	var source: Resource = load(str(main.models[1]))
	if not source is PackedScene or not (source as PackedScene).can_instantiate():
		return {"ok": false, "reason": "scout_model_unavailable"}
	for socket: String in ["Turret", "Barrel", "Muzzle", "MG_Muzzle"]:
		if not is_instance_valid(main.target.find_child(socket, true, false)):
			return {"ok": false, "reason": "original_opponent_muzzle_unavailable"}
	var normalised: Array[Dictionary] = []
	var identifiers: Dictionary = {}
	var blue: int = 0
	var red: int = 0
	var existing_index: int = -1
	var first_red: int = -1
	for row: Dictionary in rows:
		if not row.get("id") is String or not row.get("team") is String or not row.get("position") is Vector3:
			return {"ok": false, "reason": "invalid_battlefield_row"}
		var id: String = str(row.id)
		var team: String = str(row.team)
		var position: Vector3 = row.position
		if id.is_empty() or id in ["player", str(main.PLAYER_VEHICLE_ID)] or identifiers.has(id):
			return {"ok": false, "reason": "duplicate_or_empty_vehicle_id"}
		if not team in ["blue", "red"] or not position.is_finite():
			return {"ok": false, "reason": "invalid_battlefield_deployment"}
		if not main.terrain_damage.in_bounds(position.x, position.z):
			return {"ok": false, "reason": "battlefield_deployment_out_of_bounds"}
		if main.vehicle_ammo.vehicles.has(id) or not registry.vehicle(id).is_empty() or not registry.person(id).is_empty() or _host_identity_exists(id):
			return {"ok": false, "reason": "battlefield_identity_already_registered"}
		if row.has("existing") and not row.existing is bool:
			return {"ok": false, "reason": "invalid_existing_vehicle_row"}
		var existing: bool = bool(row.get("existing", false))
		if existing:
			if existing_index >= 0 or team != "red":
				return {"ok": false, "reason": "invalid_existing_vehicle_row"}
			existing_index = normalised.size()
		if team == "blue":
			blue += 1
		else:
			red += 1
			if first_red < 0:
				first_red = normalised.size()
		identifiers[id] = true
		normalised.append({"id": id, "team": team, "position": position, "existing": existing})
	if blue != BLUE_COUNT or red != RED_COUNT:
		return {"ok": false, "reason": "battlefield_team_count_mismatch"}
	if existing_index < 0:
		existing_index = first_red
		normalised[existing_index].existing = true
	# Validate all vehicle and person namespaces before allocating any new model.
	for row_index: int in range(normalised.size()):
		var id: String = str(normalised[row_index].id)
		for seat: int in range(CREW_ROLES.size()):
			var person: Dictionary = main.combat.crew[seat] if row_index == existing_index else {}
			var pid: String = str(person.get("person_id", "%s:person:%d" % [id, seat]))
			if pid.is_empty() or identifiers.has(pid) or not registry.person(pid).is_empty() or not registry.vehicle(pid).is_empty() or _host_identity_exists(pid):
				return {"ok": false, "reason": "duplicate_or_empty_crew_id"}
			identifiers[pid] = true
	return {"ok": true, "rows": normalised, "existing_index": existing_index}

func _host_identity_exists(id: String) -> bool:
	return main.ai_host.actors.has(id) or main.ai_host.persons.has(id) or main.ai_host.fortifications.has(id)

func _bind_unit_crew(unit: Dictionary) -> Dictionary:
	if unit.combat.crew.size() != CREW_ROLES.size():
		return {"ok": false, "reason": "scout_crew_size_mismatch"}
	# bind_vehicle stores these exact Combat dictionaries and supplies stable IDs,
	# original seat occupancy and canonical roles. It does not spawn any actors.
	return _registry.bind_vehicle(str(unit.id), CREW_ROLES, unit.combat.crew, {"requires_loader": false})

func _same_preparing_stage(stage: Node3D, generation: int) -> bool:
	return is_instance_valid(main) and is_instance_valid(stage) and main.stage == stage and int(main.stage_generation) == generation and is_instance_valid(main.crew_host) and main.crew_host.registry == _registry and not bool(main.get("session_ready"))

func _fail_preparation(reason: String) -> Dictionary:
	_preparation_error = reason
	_preparing = false
	_prepared = false
	_bound = false
	# The owning controller must close a failed session; never refill, retry-spawn
	# or pretend partially-created units satisfied the requested force.
	return {"ok": false, "reason": reason, "created_ai_vehicles": units.size(), "close_session": true}

func deployment_ready() -> bool:
	if not _prepared or not _bound or units.size() != AI_COUNT or not is_instance_valid(main.crew_host) or main.crew_host.registry != _registry:
		return false
	for unit: Dictionary in units.values():
		if not _unit_deployment_ready(unit):
			return false
	return true

func _crew_links(vehicle_id: String, crew: Array, roles: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for seat: int in range(crew.size()):
		var person: Dictionary = crew[seat]
		var pid: String = str(person.get("person_id", ""))
		result.append({"person_id": pid, "vehicle_id": vehicle_id, "seat_id": str(seat),
			"role": str(roles[seat]) if seat < roles.size() else "",
			"location": person.get("location", {}).duplicate(true),
			"shared_combat_record": _registry != null and is_same(person, _registry.person_ref(pid))})
	return result

func encounter_snapshot() -> Dictionary:
	var result: Dictionary = super.encounter_snapshot()
	result["profile"] = "battlefield"
	result["prepared"] = _prepared
	result["preparing"] = _preparing
	result["preparation_error"] = _preparation_error
	result["setup_position_xz"] = Vector2(_adopted_position.x, _adopted_position.z)
	result["adopted_vehicle_id"] = _bound_unit_id
	result["ai_vehicle_count"] = units.size()
	result["vehicles_including_player"] = units.size() + int(is_instance_valid(main.hero))
	result["ai_crew_count"] = 0
	for id: String in result.units:
		var unit: Dictionary = units[id]
		result.units[id]["crew_links"] = _crew_links(id, unit.combat.crew, CREW_ROLES)
		result["ai_crew_count"] += unit.combat.crew.size()
	var player_roles: Array[String] = ["commander", "gunner", "driver", "loader", "radio"]
	result["player_vehicle"] = {"vehicle_id": str(main.PLAYER_VEHICLE_ID),
		"crew_links": _crew_links(str(main.PLAYER_VEHICLE_ID), main.player_combat.crew, player_roles)}
	result["crew_count_including_player"] = int(result.ai_crew_count) + main.player_combat.crew.size()
	result["registry_current"] = is_instance_valid(main.crew_host) and main.crew_host.registry == _registry
	return result

func battlefield_snapshot() -> Dictionary:
	# Driver facts only, like the original encounter snapshot. Never HUD intel.
	return encounter_snapshot()
