extends "res://military_runtime/native/triple/local_host.gd"
## One deployment into the original host; inherited spawn still only registers player.
## No clear/rebind after Port, no alternate person/weapon/AI or camera-based simulation.
const DEPLOY_BATCH_SIZE: int = 8
var field_roster: Array[String] = []
var _field_deploying: bool = false
var _field_active: bool = false
# Explicit A/B setting; only newly deployed field_roster actors receive it.
var field_locomotion_hz: float = 20.0

func deploy_infantry(rows: Array[Dictionary]) -> Dictionary:
	if _field_deploying or not field_roster.is_empty():
		return {"ok": false, "reason": "field_already_deployed_or_deploying"}
	if not is_inside_tree() or not is_instance_valid(main) or not is_instance_valid(main.stage):
		return {"ok": false, "reason": "original_stage_unavailable"}
	# Validate the entire request before touching any original actor or adding people.
	var ids: Dictionary = {}
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var id: String = str(row.get("id", ""))
		var team: String = str(row.get("team", ""))
		var point: Variant = row.get("position")
		var route: Variant = row.get("route", [])
		if id.is_empty() or ids.has(id) or actors.has(id) or id == player_id:
			return {"ok": false, "reason": "field_id_not_unique", "row": index}
		if team not in ["blue", "red"] or not point is Vector3 or not route is Array:
			return {"ok": false, "reason": "invalid_field_row", "row": index}
		if not point.is_finite():
			return {"ok": false, "reason": "invalid_field_position", "row": index}
		for waypoint: Variant in route:
			if not waypoint is Vector3:
				return {"ok": false, "reason": "invalid_field_route", "row": index}
			if not waypoint.is_finite():
				return {"ok": false, "reason": "invalid_field_route", "row": index}
		ids[id] = true
	_field_deploying = true
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var id: String = str(row.id)
		var point: Vector3 = row.position
		var route: Array = row.get("route", [])
		var actor: CharacterBody3D = spawn_actor(id, str(row.team), point, route, [])
		# No physics tick can intervene between spawn_actor and this call (no await).
		actor.set_physics_process(false)
		actor.set_meta("initial_dismounted", true)
		actor.set_meta("battlefield_infantry", true)
		actor.locomotion_hz = clampf(field_locomotion_hz, 20.0, 60.0)
		actor.locomotion_lod_enabled = actor.locomotion_hz < 60.0
		if row.has("squad_id"):
			actor.set_meta("fireteam", row.squad_id)
			actor.set_meta("squad_id", row.squad_id)
		if row.has("member"):
			actor.set_meta("member", row.member)
		field_roster.append(id)
		if (index + 1) % DEPLOY_BATCH_SIZE == 0 and index + 1 < rows.size():
			await get_tree().physics_frame
			if not is_inside_tree() or not is_instance_valid(main) or not is_instance_valid(main.stage):
				_field_deploying = false
				return {"ok": false, "reason": "original_stage_removed", "deployed": field_roster.size()}
	_field_deploying = false
	return {"ok": true, "deployed": field_roster.size(), "active": false}

func activate_battlefield() -> Dictionary:
	if _field_deploying:
		return {"ok": false, "reason": "field_deployment_pending"}
	if _field_active:
		return {"ok": true, "already_active": true, "deployed": field_roster.size()}
	var activated: int = 0
	for id: String in field_roster:
		var actor: CharacterBody3D = actors.get(id) as CharacterBody3D
		if not is_instance_valid(actor):
			continue
		# Exactly the original actor, timers and person/weapon records; no state reset.
		actor.set_physics_process(not actor.embarked)
		activated += 1
	_field_active = true
	return {"ok": true, "activated": activated, "deployed": field_roster.size()}

func battlefield_snapshot() -> Dictionary:
	var people: Dictionary = {}
	var by_team: Dictionary = {"blue": 0, "red": 0}
	var alive_by_team: Dictionary = {"blue": 0, "red": 0}
	var physics_active: int = 0
	var missing_ids: Array[String] = []
	for id: String in field_roster:
		var actor: CharacterBody3D = actors.get(id) as CharacterBody3D
		if not is_instance_valid(actor):
			missing_ids.append(id)
			continue
		var team: String = str(actor.brain.team_id)
		by_team[team] = int(by_team.get(team, 0)) + 1
		if actor.brain.hp > 0.0:
			alive_by_team[team] = int(alive_by_team.get(team, 0)) + 1
		if actor.is_physics_processing() and actor.can_process():
			physics_active += 1
		var row: Dictionary = actor.snapshot()
		row["person_id"] = str(actor.person_state.get("person_id", ""))
		row["weapon_id"] = actor.weapon_id
		row["weapon"] = actor.weapon
		row["embarked"] = actor.embarked
		row["physics_processing"] = actor.is_physics_processing()
		row["can_process"] = actor.can_process()
		row["instance_id"] = actor.get_instance_id()
		row["parts"] = actor.person_state.get("parts", {}).duplicate(true)
		row["squad_id"] = actor.get_meta("squad_id", "")
		row["member"] = actor.get_meta("member", -1)
		if _battle_timing_enabled:
			row["performance"] = actor.performance_snapshot()
		people[id] = row
	return {"deployed": field_roster.size(), "deploying": _field_deploying,
		"active": _field_active, "by_team": by_team, "alive_by_team": alive_by_team,
		"physics_active": physics_active, "missing_ids": missing_ids,
		"actors": people, "performance": performance_snapshot()}
