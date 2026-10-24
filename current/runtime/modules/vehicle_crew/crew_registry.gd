extends RefCounted
## Portable identity/occupancy authority. Hosts own actors, navigation and physics.
signal transferred(person_id: String, location: Dictionary)
const SCHEMA_VERSION := 1
var _people: Dictionary = {}
var _vehicles: Dictionary = {}

func register_person(person: Dictionary) -> Dictionary:
	var id := str(person.get("person_id", ""))
	if id.is_empty() or _people.has(id) or _vehicles.has(id): return _fail("duplicate_or_empty_id")
	var p := person
	p["person_id"] = id
	p["hp"] = p.get("hp", 10.0)
	p["max_hp"] = p.get("max_hp", 10.0)
	p["alive"] = p.get("alive", true)
	p["parts"] = p.get("parts", {})
	p["ammo"] = p.get("ammo", 30)
	p["state"] = p.get("state", {})
	p["location"] = {"kind": "world", "position": p.get("position", [0.0, 0.0, 0.0])}
	_people[id] = p
	return {"ok": true}

func register_vehicle(vehicle_id: String, seats: Dictionary, config: Dictionary = {}) -> Dictionary:
	if vehicle_id.is_empty() or _vehicles.has(vehicle_id) or _people.has(vehicle_id): return _fail("duplicate_or_empty_id")
	if seats.is_empty(): return _fail("no_seats")
	var slots: Dictionary = {}
	for seat_id in seats:
		if str(seat_id).is_empty() or str(seats[seat_id]).is_empty(): return _fail("invalid_seat")
		slots[str(seat_id)] = {"role": str(seats[seat_id]), "person_id": ""}
	var cfg := {"loader_policy": "slow", "missing_loader_reload_multiplier": 1.5, "requires_loader": false}
	cfg.merge(config, true)
	if not cfg.loader_policy in ["slow", "block"] or float(cfg.missing_loader_reload_multiplier) < 1.0: return _fail("invalid_loader_config")
	_vehicles[vehicle_id] = {"seats": slots, "config": cfg}
	return {"ok": true}

func person(person_id: String) -> Dictionary:
	return _people.get(person_id, {}).duplicate(true)

func vehicle(vehicle_id: String) -> Dictionary:
	return _vehicles.get(vehicle_id, {}).duplicate(true)

func update_person(person_id: String, changes: Dictionary) -> Dictionary:
	if not _people.has(person_id): return _fail("unknown_person")
	if changes.has("person_id") or changes.has("location"): return _fail("identity_or_location_immutable")
	_people[person_id].merge(changes.duplicate(true), true)
	return {"ok": true}

func embark(person_id: String, vehicle_id: String, seat_id: String, boarding_allowed: Callable, state_patch: Dictionary = {}) -> Dictionary:
	if not _people.has(person_id) or not _vehicles.has(vehicle_id): return _fail("unknown_identity")
	var p: Dictionary = _people[person_id]
	var seats: Dictionary = _vehicles[vehicle_id].seats
	if not _living(p): return _fail("dead_person")
	if p.location.kind != "world": return _fail("already_aboard")
	if not seats.has(seat_id): return _fail("unknown_seat")
	if not str(seats[seat_id].person_id).is_empty(): return _fail("occupied_seat")
	if state_patch.has("person_id") or state_patch.has("location"): return _fail("identity_or_location_immutable")
	var candidate := p.duplicate(true)
	candidate.merge(state_patch.duplicate(true), true)
	if not _living(candidate): return _fail("dead_person")
	if not boarding_allowed.is_valid() or not bool(boarding_allowed.call(person_id, vehicle_id, seat_id)): return _fail("boarding_denied")
	candidate.location = {"kind": "vehicle", "vehicle_id": vehicle_id, "seat_id": seat_id}
	p.merge(state_patch.duplicate(true), true)
	p.location = candidate.location
	seats[seat_id].person_id = person_id
	transferred.emit(person_id, p.location.duplicate(true))
	return {"ok": true, "person": candidate.duplicate(true)}

func disembark(person_id: String, exit_position: Vector3, safe_exit: Callable) -> Dictionary:
	if not _people.has(person_id): return _fail("unknown_person")
	var p: Dictionary = _people[person_id]
	if not _living(p): return _fail("dead_person")
	if p.location.kind != "vehicle": return _fail("not_aboard")
	if not exit_position.is_finite(): return _fail("invalid_exit")
	if not safe_exit.is_valid() or not bool(safe_exit.call(person_id, str(p.location.vehicle_id), exit_position)): return _fail("unsafe_exit")
	var vehicle_id := str(p.location.vehicle_id)
	var seat_id := str(p.location.seat_id)
	_vehicles[vehicle_id].seats[seat_id].person_id = ""
	p.location = {"kind": "world", "position": [exit_position.x, exit_position.y, exit_position.z]}
	transferred.emit(person_id, p.location.duplicate(true))
	return {"ok": true, "person": p.duplicate(true)}

func functional_status(vehicle_id: String) -> Dictionary:
	if not _vehicles.has(vehicle_id): return {"can_drive": false, "can_fire": false, "can_reload": false, "reload_multiplier": 1.0}
	var v: Dictionary = _vehicles[vehicle_id]
	var roles: Dictionary = {}
	for seat in v.seats.values():
		var id := str(seat.person_id)
		if _people.has(id):
			var effective_role := str(_people[id].get("state",{}).get("assigned_role",seat.role))
			if _role_capable(_people[id], effective_role): roles[effective_role] = true
	var loader_missing := bool(v.config.requires_loader) and not roles.has("loader")
	return {"can_drive": roles.has("driver"), "can_fire": roles.has("gunner"), "can_reload": not (loader_missing and v.config.loader_policy == "block"), "reload_multiplier": float(v.config.missing_loader_reload_multiplier) if loader_missing and v.config.loader_policy == "slow" else 1.0}

func serialize() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "people": _people.duplicate(true), "vehicles": _vehicles.duplicate(true)}

## Validate a complete snapshot before replacing state. Restoring does not spawn actors.
func restore(snapshot: Dictionary) -> Dictionary:
	if not _people.is_empty() or not _vehicles.is_empty(): return _fail("restore_requires_empty_registry")
	if int(snapshot.get("schema_version", -1)) != SCHEMA_VERSION: return _fail("unsupported_schema")
	if not snapshot.get("people") is Dictionary or not snapshot.get("vehicles") is Dictionary: return _fail("invalid_snapshot")
	var people: Dictionary = snapshot.people.duplicate(true)
	var vehicles: Dictionary = snapshot.vehicles.duplicate(true)
	var occupants: Dictionary = {}
	for vid in vehicles:
		if people.has(vid) or not vehicles[vid] is Dictionary or not vehicles[vid].get("seats") is Dictionary: return _fail("invalid_vehicle")
		if not vehicles[vid].get("config") is Dictionary: return _fail("invalid_config")
		var cfg: Dictionary = vehicles[vid].config
		if not cfg.get("loader_policy", "") in ["slow", "block"] or float(cfg.get("missing_loader_reload_multiplier", 0)) < 1.0 or not cfg.has("requires_loader"): return _fail("invalid_config")
		for sid in vehicles[vid].seats:
			var seat = vehicles[vid].seats[sid]
			if not seat is Dictionary or not seat.has("role") or not seat.has("person_id"): return _fail("invalid_seat")
			var pid := str(seat.person_id)
			if pid.is_empty(): continue
			if not people.has(pid) or occupants.has(pid): return _fail("duplicate_or_unknown_occupant")
			occupants[pid] = {"kind": "vehicle", "vehicle_id": vid, "seat_id": sid}
	for pid in people:
		var p = people[pid]
		if not p is Dictionary or str(p.get("person_id", "")) != str(pid) or not p.get("location") is Dictionary: return _fail("invalid_person")
		if not p.has("hp") or not p.has("alive"): return _fail("invalid_person")
		var loc: Dictionary = p.location
		if loc.get("kind") == "vehicle":
			if not occupants.has(pid) or loc != occupants[pid]: return _fail("occupancy_mismatch")
		elif loc.get("kind") == "world":
			if occupants.has(pid) or not loc.get("position") is Array or loc.position.size() != 3: return _fail("invalid_world_location")
		else: return _fail("invalid_location")
	_people = people
	_vehicles = vehicles
	return {"ok": true}

func _living(p: Dictionary) -> bool:
	return bool(p.get("alive", false)) and float(p.get("hp", 0)) > 0.0

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

## Live shared combat record. Never replace this Dictionary during a scene.
func person_ref(person_id: String) -> Dictionary:
	return _people.get(person_id, {})

func occupied_person(vehicle_id: String, seat_id: String) -> Dictionary:
	if not _vehicles.has(vehicle_id) or not _vehicles[vehicle_id].seats.has(seat_id): return {}
	return person_ref(str(_vehicles[vehicle_id].seats[seat_id].person_id))

func can_fire(vehicle_id: String) -> bool:
	return bool(functional_status(vehicle_id).can_fire)

func can_drive(vehicle_id: String) -> bool:
	return bool(functional_status(vehicle_id).can_drive)

func reload_multiplier(vehicle_id: String) -> float:
	return float(functional_status(vehicle_id).reload_multiplier)

## Bind existing Combat.crew references. roles use canonical English names.
func bind_vehicle(vehicle_id: String, roles: Array, crew: Array, config: Dictionary = {}) -> Dictionary:
	if roles.size() != crew.size(): return _fail("crew_size_mismatch")
	if vehicle_id.is_empty() or _vehicles.has(vehicle_id) or _people.has(vehicle_id): return _fail("duplicate_or_empty_id")
	var seats: Dictionary = {}
	var ids: Dictionary = {}
	for i in roles.size():
		if not crew[i] is Dictionary or str(roles[i]).is_empty(): return _fail("invalid_crew")
		var pid := str(crew[i].get("person_id", "%s:person:%d" % [vehicle_id, i]))
		if pid.is_empty() or pid == vehicle_id or ids.has(pid) or _people.has(pid) or _vehicles.has(pid): return _fail("duplicate_or_empty_id")
		ids[pid] = true
		seats[str(i)] = str(roles[i])
	var result := register_vehicle(vehicle_id, seats, config)
	if not result.ok: return result
	for i in crew.size():
		var p: Dictionary = crew[i]
		p["person_id"] = str(p.get("person_id", "%s:person:%d" % [vehicle_id, i]))
		register_person(p)
		p.location = {"kind": "vehicle", "vehicle_id": vehicle_id, "seat_id": str(i)}
		_vehicles[vehicle_id].seats[str(i)].person_id = p.person_id
	return {"ok": true}

func _role_capable(p: Dictionary, role: String) -> bool:
	return preload("res://modules/vehicle_crew/role_capability.gd").capable(p, role)

## Changes duty without changing identity, original seat, injury or health records.
func assign_role(person_id: String, role: String) -> Dictionary:
	if not _people.has(person_id): return _fail("unknown_person")
	if role not in ["commander","gunner","driver","loader","radio"]: return _fail("unknown_role")
	var p: Dictionary = _people[person_id]
	if not _role_capable(p,role): return _fail("incapable_person")
	if p.location.kind!="vehicle": return _fail("not_aboard")
	if not p.has("state"): p.state = {}
	p.state["assigned_role"] = role
	return {"ok":true,"person_id":person_id,"role":role}
