extends RefCounted
const State = preload("res://experiments/war_resolver/battle_state.gd")
## Replaceable slice rules: severe fresh injury bleeds; one kit and timed care
## stabilize it. Treatment permits one partial recovery, never resurrection.
var _owner: WeakRef
var _trained: Dictionary = {}
var _tickets: Dictionary = {}
var _serial: int = 0
const MAX_TICKETS: int = 2048
const BLEED_PERIOD: float = 30.0
const BLEED_RATE: float = 0.001
const CARE_SECONDS: float = 30.0
const RECOVERY_SECONDS: float = 300.0
const RECOVERY_AMOUNT: float = 0.25

func configure(gameplay: RefCounted) -> void:
	_owner = weakref(gameplay)
	gameplay.participants.medical = self

func admit_healer(actor: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	if g._state.time != 0.0 or not g.participants._units.has(actor) or _trained.size() >= 2:
		return false
	_trained[actor] = true
	return true

func on_hurt(actor: String, dose: float, loss: float, cause_ref: String, cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var body: Dictionary = g.participants._member(actor)
	if g.participants.dead(actor):
		if body.has("bleeding"):
			body.bleeding.active = false
		if body.has("treatment"):
			body.treatment.status = "PATIENT_DEAD"
		return
	if cause == "bleeding":
		return
	if body.get("treatment", {}).get("status", "") == "RECOVERING":
		body.treatment.status = "RECOVERY_INTERRUPTED"
		body.care_version = int(body.get("care_version", 0)) + 1
	if loss < 0.25 and dose <= loss:
		return
	# A fresh severe wound interrupts care; minor new damage still blocks recovery.
	body.care_version = int(body.get("care_version", 0)) + 1
	if body.get("bleeding", {}).get("active", false):
		return
	body.bleeding = {"active": true, "rate": BLEED_RATE, "last_at": g._state.time, "cause_ref": cause_ref,
		"version": int(body.get("bleeding", {}).get("version", 0)) + 1}
	_schedule(actor, "bleed", g._state.time + BLEED_PERIOD, int(body.bleeding.version))

func validate(actor: String, values: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var p: RefCounted = g.participants
	if values.size() != 4 or values.get("action", "") != "aid" or values.get("mode", "") not in ["stabilize", "treat"] or not values.get("patient_ref") is String or not values.get("supply_unit") is String:
		return _reject("aid_requires_patient_mode_and_actual_supply_unit")
	var patient: String = str(values.patient_ref)
	var supply: String = str(values.supply_unit)
	if not _trained.has(actor) or not p.can_intend(actor) or not p._units.has(patient) or p.dead(patient) or actor == patient:
		return _reject("existing_qualified_helper_and_living_patient_required")
	if _tickets.size() >= MAX_TICKETS - 3 or p._actions.size() >= p.MAX_ACTIONS:
		return _reject("medical_record_capacity")
	if p._member(actor).state not in ["FOLLOWING", "COVERED", "STATIONARY"] or p._member(patient).get("treatment", {}).get("status", "") == "IN_PROGRESS":
		return _reject("conflicting_personal_action")
	if float(p._member(patient).injury) <= 0.0 and float(p._member(patient).trauma) <= 0.0:
		return _reject("no_existing_injury_to_treat")
	if not g._state.units.has(supply) or not g._lod.has_leaf(supply) or not g._state.units[supply].has("medical") or float(g._state.units[supply].medical) < 1.0:
		return _reject("one_existing_medical_kit_required")
	var unit: Dictionary = g._state.units[supply]
	if unit.side != p._physical_unit(actor).side or not str(unit.spatial.edge).is_empty() or not unit.spatial.path.is_empty() or not _near(actor, patient, supply):
		return _reject("helper_patient_and_medical_stock_must_be_at_actual_care_location")
	var leaves: Array[String] = [str(p._units[actor])]
	if p._units[patient] not in leaves:
		leaves.append(str(p._units[patient]))
	return g._state.structure_port.get_ref()._members._representation_capacity(leaves)

func _near(actor: String, patient: String, supply: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	var p: RefCounted = g.participants
	var helper: Dictionary = p.body_spatial(actor)
	var body: Dictionary = p.body_spatial(patient)
	var stock: Dictionary = g._state.units[supply].spatial
	return g._space.local_place(helper) == g._space.local_place(body) and g._space.local_place(helper) == g._space.local_place(stock) and str(helper.get("local_edge", "")) == "" and str(body.get("local_edge", "")) == "" and p._distance(p.position(actor), p.position(patient)) <= float(p.rules.local_radius_km) and p._distance(p.position(actor), g._space.xy(g._state.units[supply])) <= float(p.rules.local_radius_km)

func start(actor: String, id: String, values: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var valid: Dictionary = validate(actor, values)
	if not valid.ok:
		return valid
	var p: RefCounted = g.participants
	var changed: Dictionary = {}
	var retired: Dictionary = {}
	for leaf: String in [str(p._units[actor]), str(p._units[values.patient_ref])]:
		var expanded: Dictionary = g._lod.materialize_leaf(leaf, "actual_local_medical_care")
		for unit_id: String in expanded.get("changed", []):
			changed[unit_id] = true
		for unit_id: String in expanded.get("retired", []):
			retired[unit_id] = true
	var unit: Dictionary = g._state.units[values.supply_unit]
	unit.medical -= 1.0
	unit.medical_spent += 1.0
	g._state.logistics_ledger.medical_spent += 1.0
	p._start(actor, id, "MEDICATING", p.position(actor), "", CARE_SECONDS)
	var action: Dictionary = p._actions[p._member(actor).action_ref]
	action.medical = values.duplicate(true)
	action.medical.patient_version = int(p._member(str(values.patient_ref)).get("care_version", 0))
	p._member(str(values.patient_ref)).treatment = {"status": "IN_PROGRESS", "helper_ref": actor, "input_ref": id, "started_at": g._state.time, "due": action.due}
	g.focus_continuity.event_relation(actor, str(values.patient_ref), "medical_contact", id)
	changed[unit.id] = true
	changed[p._units[actor]] = true
	return {"ok": true, "status": "MEDICATING", "changed": State.sorted_ids(changed), "retired": State.sorted_ids(retired)}

func complete(action: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var p: RefCounted = g.participants
	var patient: String = str(action.medical.patient_ref)
	var body: Dictionary = p._member(patient)
	if p.dead(patient) or not g._state.units.has(action.medical.supply_unit) or not _near(str(action.actor_ref), patient, str(action.medical.supply_unit)) or int(body.get("care_version", 0)) != int(action.medical.patient_version):
		body.treatment.status = "INTERRUPTED"
		return {"status": "CARE_INTERRUPTED"}
	var changed: Array = []
	if body.get("bleeding", {}).get("active", false):
		# Include blood lost since the last ticket up to actual stabilization time.
		var dose: float = float(body.bleeding.rate) * (g._state.time - float(body.bleeding.last_at))
		body.bleeding.last_at = g._state.time
		changed = p.external_damage(patient, dose, str(action.id) + "_bleeding_until_care", "bleeding").changed
		if p.dead(patient):
			return {"status": "PATIENT_DIED_BEFORE_STABILIZATION", "changed": changed}
	body.treatment.status = "STABILIZED"
	body.care_version = int(body.get("care_version", 0)) + 1
	if body.has("bleeding"):
		body.bleeding.active = false
		body.bleeding.version += 1
	if action.medical.mode == "treat":
		body.treatment.status = "RECOVERING"
		_schedule(patient, "recover", g._state.time + RECOVERY_SECONDS, int(body.care_version))
	p._emit(patient, "personal_stabilized", str(action.input_ref), {"helper_ref": action.actor_ref, "mode": action.medical.mode})
	return {"status": body.treatment.status, "changed": changed}

func on_unit_merge(donor: String, survivor: String) -> void:
	var g: RefCounted = _owner.get_ref()
	# At most six bodies; only a current action referencing the retired stock moves.
	for actor: String in g.participants._bodies:
		var body: Dictionary = g.participants._member(actor)
		if body.state != "MEDICATING":
			continue
		var action: Dictionary = g.participants._actions[body.action_ref]
		if action.medical.supply_unit == donor:
			action.medical.supply_unit = survivor

func _schedule(actor: String, mode: String, due: float, version: int) -> void:
	if _tickets.size() >= MAX_TICKETS:
		return # Capacity limits stop new plans; existing body facts remain.
	_serial += 1
	var id: String = "medical_%d" % _serial
	_tickets[id] = {"actor": actor, "mode": mode, "due": due, "version": version}
	assert(_owner.get_ref()._state.schedule_event(id, due, "gameplay", {"care_id": id}))

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and payload.get("care_id", "") == id and _tickets.has(id) and _tickets[id].due == due

func process_event(event: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var ticket: Dictionary = _tickets[event.id]
	_tickets.erase(event.id)
	var p: RefCounted = g.participants
	var actor: String = str(ticket.actor)
	var body: Dictionary = p._member(actor)
	if p.dead(actor):
		return {"changed": [], "retired": [], "record": {"status": "OBSOLETE"}}
	if ticket.mode == "bleed":
		if not body.get("bleeding", {}).get("active", false) or int(body.bleeding.version) != int(ticket.version):
			return {"changed": [], "retired": [], "record": {"status": "STABILIZED"}}
		var dose: float = float(body.bleeding.rate) * (g._state.time - float(body.bleeding.last_at))
		body.bleeding.last_at = g._state.time
		var result: Dictionary = p.external_damage(actor, dose, str(event.id), "bleeding")
		if not p.dead(actor):
			_schedule(actor, "bleed", g._state.time + BLEED_PERIOD, int(ticket.version))
		result.record = {"kind": "injury_deterioration", "person_ref": actor, "time": g._state.time}
		return result
	if int(body.get("care_version", 0)) != int(ticket.version) or body.get("bleeding", {}).get("active", false):
		return {"changed": [], "retired": [], "record": {"status": "RECOVERY_INTERRUPTED"}}
	var ceiling: float = maxf(0.0, 1.0 - float(body.trauma) * 0.5)
	var amount: float = minf(RECOVERY_AMOUNT, maxf(0.0, ceiling - float(body.health)))
	body.treatment.status = "PARTIALLY_RECOVERED" if amount > 0.000001 else "NO_RESTORABLE_CAPACITY"
	var result: Dictionary = p.recover(actor, amount, str(event.id))
	result.record = {"kind": "partial_recovery", "person_ref": actor, "time": g._state.time}
	return result

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["_trained", "_tickets", "_serial"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
