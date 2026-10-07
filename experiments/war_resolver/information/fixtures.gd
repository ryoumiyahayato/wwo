extends RefCounted
const Base = preload("res://experiments/war_resolver/logistics/fixtures.gd")
const Structure = preload("res://experiments/war_resolver/structure/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Service = preload("res://experiments/war_resolver/information/service.gd")
const Reader = preload("res://experiments/war_resolver/information/reader.gd")
const Decision = preload("res://experiments/war_resolver/information/decision.gd")

static func setup(count: int = 40, sleeping: int = 0, aggregate: bool = true, seed_value: int = 71, enabled: bool = true) -> Dictionary:
	var env: Dictionary = Base.setup(count, sleeping, aggregate, true, 8.0, 0.75, 1200.0, seed_value)
	if not enabled:
		return env
	var sources: Dictionary = {}
	for person: String in env.people:
		sources["source_" + person] = {"observer_ref": person, "scope_ref": env.people[person].formation_id,
			"origin": "DIRECT" if person in ["soldier", "squad"] else "HQ_REPORT",
			"quality": 0.9 if person in ["soldier", "squad"] else 0.7,
			"precision_km": 0.02 if person in ["soldier", "squad"] else 0.5, "fact_kinds": Service.FACTS.duplicate()}
	sources.external_company = {"observer_ref": "company", "scope_ref": "blue_division", "origin": "EXTERNAL", "quality": 0.3, "precision_km": 0.5, "fact_kinds": Service.FACTS.duplicate()}
	sources.external_division = {"observer_ref": "division", "scope_ref": "blue_division", "origin": "EXTERNAL", "quality": 0.95, "precision_km": 1.0, "fact_kinds": Service.FACTS.duplicate()}
	sources.recon_division = {"observer_ref": "division", "scope_ref": "red_company", "origin": "SUBORDINATE_REPORT", "quality": 0.5, "precision_km": 1.0, "fact_kinds": ["position", "status"]}
	var people: Array[String] = State.sorted_ids(env.people)
	var channels: Dictionary = {}
	for pair: Array in [["instant", 0.0, true], ["delayed", 47.0, true], ["later", 100000.0, true], ["failed", 47.0, false]]:
		channels[pair[0]] = {"senders": people.duplicate(), "recipients": people.duplicate(), "latency": pair[1], "available": pair[2], "quality": 0.8, "command_scope": "blue_division"}
	var service: Service = Service.new()
	assert(service.configure(env.state, env.lod, env.service, env.logistics, env.roles, sources, channels))
	env.information = service
	env.readers = {}
	for person: String in people:
		var reader: Reader = Reader.new()
		assert(reader.configure(service, person))
		env.readers[person] = reader
	return env

static func observation(env: Dictionary, id: String = "observation", person: String = "company", kind: String = "formation", subject: String = "blue_company", fact: String = "position") -> Dictionary:
	return env.readers[person].observe({"id": id, "source_ref": "source_" + person, "subject_kind": kind, "subject_ref": subject, "fact_kind": fact})

static func report(env: Dictionary, id: String = "report", observation_id: String = "observation", sender: String = "company", recipient: String = "division", channel: String = "delayed") -> Dictionary:
	return env.readers[sender].send_report({"id": id, "recipient_ref": recipient, "channel_ref": channel, "observation_ids": [observation_id]})

static func command(env: Dictionary, id: String = "command", channel: String = "delayed", actor: String = "platoon", target: String = "node_unit_000") -> Dictionary:
	return env.readers[actor].issue_command({"id": id, "channel_ref": channel,
		"command": {"id": id, "kind": "mission", "target": target, "values": {"posture": "withdraw", "objective": 0.0, "direction": -1.0}}})

static func external(env: Dictionary, id: String, source: String = "external_company", kind: String = "position", value: Dictionary = {}, observed: float = 0.0, unit: String = "unit_000") -> Dictionary:
	var supplied: Dictionary = value if not value.is_empty() else {"area_ref": "claimed_old_area", "band_km": [1.0, 1.5], "precision_km": 0.5}
	return env.information.admit_external_observation({"id": id, "source_ref": source, "subject_kind": "unit", "subject_ref": unit, "fact_kind": kind, "value": supplied, "observed_at": observed})

static func causal(env: Dictionary) -> Dictionary:
	var snapshot: Dictionary = env.lod.snapshot()
	snapshot.current.erase("counters")
	return snapshot
