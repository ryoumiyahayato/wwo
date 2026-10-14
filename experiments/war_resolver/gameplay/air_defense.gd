extends RefCounted
## Only admitted real weapon holders participate in an aircraft's contact event.
var _owner: WeakRef
var defenders: Dictionary = {}
const MAX_DEFENDERS: int = 2

func configure(gameplay: RefCounted) -> void:
	_owner = weakref(gameplay)

func admit(unit: String, recipient: String, parameters: Dictionary) -> bool:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	if g._state.time != 0.0 or defenders.size() >= MAX_DEFENDERS or defenders.has(unit) or not g._state.units.has(unit) or not s._people.has(recipient) or not s._contains(str(s.command_person(recipient).formation_id), str(s._unit_nodes[unit])):
		return false
	for key: String in ["detect_range_km", "range_km", "minimum_altitude", "maximum_altitude", "rounds", "damage_per_round", "interval_seconds", "tracking_seconds", "bearing_degrees", "arc_degrees", "minimum_equipment"]:
		if not parameters.has(key) or not (parameters[key] is float or parameters[key] is int) or not is_finite(float(parameters[key])):
			return false
	if float(parameters.range_km) <= 0.0 or float(parameters.detect_range_km) < float(parameters.range_km) or float(parameters.maximum_altitude) <= float(parameters.minimum_altitude) or float(parameters.minimum_altitude) < 0.0 or float(parameters.rounds) <= 0.0 or float(parameters.interval_seconds) <= 0.0 or float(parameters.damage_per_round) <= 0.0 or float(parameters.minimum_equipment) <= 0.0 or float(parameters.tracking_seconds) < 0.0 or float(parameters.arc_degrees) <= 0.0 or float(parameters.arc_degrees) > 360.0:
		return false
	var field: bool = g.operations._field_sources.has(unit)
	if not field and not g._state.information_port.get_ref().register_platform_source("aa_" + unit, str(s._unit_nodes[unit]), self):
		return false
	g._state.units[unit].weapon.air_defense = parameters.duplicate(true)
	defenders[unit] = {"unit_ref": unit, "recipient": recipient, "tracks": {}, "next_fire": 0.0, "field_reporting": field}
	return true

func engage(asset: Dictionary, cause: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var air: RefCounted = g.air
	var changed: Array = []
	var retired: Array = []
	for id: String in defenders:
		if not air.airborne(str(asset.id)):
			break
		if not g._state.knows_unit(id):
			continue
		var holder: Dictionary = g._state.units[id] if g._state.units.has(id) else g._lod.preview_leaf(id)
		var defender: Dictionary = defenders[id]
		var weapon: Dictionary = holder.weapon.get("air_defense", {})
		if weapon.is_empty() or holder.side == g._state.structure_port.get_ref()._nodes[asset.owner].side or holder.action in ["disabled", "withdrawn"] or float(holder.effective) <= 0.0 or float(holder.get("serviceable_equipment", holder.equipment)) < float(weapon.minimum_equipment):
			continue
		var point: Array = air.position(str(asset.id))
		var origin: Array = g._space.xy(holder)
		var distance: float = air._distance(origin, point)
		var height: float = air.altitude(str(asset.id))
		var visibility: float = float(g._space.terrain(holder).visibility) * float(asset.cloud_visibility)
		var lane: Dictionary = g._space._lanes.get(str(holder.spatial.node) + ":" + air.contact_node(str(asset.id)), {})
		var bearing: float = rad_to_deg(atan2(float(point[1]) - float(origin[1]), float(point[0]) - float(origin[0])))
		if distance > float(weapon.detect_range_km) or height < float(weapon.minimum_altitude) or height > float(weapon.maximum_altitude) or visibility <= 0.0 or not lane.get("observe", false):
			defender.tracks.erase(asset.id)
			continue
		if not defender.tracks.has(asset.id) or g._state.time - float(defender.tracks[asset.id].get("observed_at", 0.0)) > float(air.rules.contact_seconds) * 2.0:
			defender.tracks[asset.id] = {"started_at": g._state.time, "next_report": 0.0}
		var track: Dictionary = defender.tracks[asset.id]
		track.xy = point
		track.observed_at = g._state.time
		if g._state.time >= float(track.next_report):
			if defender.get("field_reporting", false):
				g.operations.report_air_track(self, id, str(defender.recipient), "aa_report_" + cause + "_" + id, air.track_claim("aa_" + id, str(asset.id), cause + "_" + id, visibility, "GROUND_AIR_VISUAL"))
			else:
				g._state.information_port.get_ref().send_platform_report(self, "aa_" + id, str(defender.recipient), "aa_report_" + cause + "_" + id, [air.track_claim("aa_" + id, str(asset.id), cause + "_" + id, visibility, "GROUND_AIR_VISUAL")])
			track.next_report = g._state.time + float(air.rules.report_interval_seconds)
		if distance > float(weapon.range_km) or not lane.get("fire", false) or absf(wrapf(bearing - float(weapon.bearing_degrees), -180.0, 180.0)) > float(weapon.arc_degrees) * 0.5 or g._state.time < float(defender.next_fire) or g._state.time - float(track.started_at) < float(weapon.tracking_seconds) or float(holder.ammunition) <= 0.0:
			continue
		if not g._state.units.has(id):
			var materialized: Dictionary = g._lod.materialize_leaf(id, "actual_air_defense_fire")
			changed.append_array(materialized.get("changed", []))
			retired.append_array(materialized.get("retired", []))
			holder = g._state.units[id]
		var rounds: float = minf(g.tactics._unreserved(holder), float(weapon.rounds))
		if rounds <= 0.000001:
			continue
		holder.ammunition -= rounds
		holder.ammo_spent += rounds
		g._state.totals.ammo_spent += rounds
		defender.next_fire = g._state.time + float(weapon.interval_seconds)
		var slant: float = sqrt(distance * distance + height * height)
		var aim: float = visibility * (1.0 - 0.5 * distance / float(weapon.range_km)) / (1.0 + slant + air.speed(asset) * 10.0 + float(asset.maneuver))
		aim *= maxf(0.0, 1.0 - float(holder.suppression))
		air.damage(str(asset.id), rounds * float(weapon.damage_per_round) * aim, cause + "_aa_" + id)
		if id not in changed:
			changed.append(id)
		g._state.wake(str(holder.area_id))
	return {"changed": changed, "retired": retired}

const RUNTIME_FIELDS: Array[String] = ["defenders"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
