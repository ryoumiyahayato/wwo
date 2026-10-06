extends RefCounted
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")


static func hierarchy() -> Dictionary:
	var nodes: Dictionary = {}
	for side: String in ["blue", "red"]:
		var suffix: String = "_" + side
		var parent: String = ""
		for echelon: String in ["division", "regiment", "battalion"]:
			var id: String = echelon + suffix
			nodes[id] = {"echelon": echelon, "parent": parent, "side": side}
			parent = id
		for company: int in range(2):
			var company_id: String = "company" + suffix + str(company)
			nodes[company_id] = {"echelon": "company", "parent": parent, "side": side}
			for platoon: int in range(2):
				var platoon_id: String = "platoon" + suffix + str(company) + str(platoon)
				nodes[platoon_id] = {"echelon": "platoon", "parent": company_id, "side": side}
		var count: int = 6 if side == "blue" else 4
		for index: int in range(count):
			var unit_id: String = ("attack_" if side == "blue" else "defend_") + "%02d" % index
			var company: int = index / (3 if side == "blue" else 2)
			var platoon: int = 0 if side == "blue" and index % 3 < 2 else 1
			nodes["squad_" + unit_id] = {"echelon": "squad", "parent": "platoon" + suffix + str(company) + str(platoon), "side": side, "unit_id": unit_id}
	return nodes


static func people() -> Dictionary:
	var result: Dictionary = {}
	var positions: Array[String] = ["squad_attack_00", "squad_attack_00", "platoon_blue00",
		"company_blue0", "battalion_blue", "regiment_blue", "division_blue"]
	for index: int in range(Roles.ROLES.size()):
		result[Roles.ROLES[index]] = {"role": Roles.ROLES[index], "formation_id": positions[index]}
	return result


static func command(id: String, kind: String, target: String, values: Dictionary) -> Dictionary:
	return {"id": id, "kind": kind, "target": target, "values": values}


static func mission_values(posture: String = "advance", objective: float = 2.0) -> Dictionary:
	return {"posture": posture, "objective": objective, "direction": 1.0}


static func scripted(role: String, policy: String, sleeping_areas: int = 0, mission_objective: float = 1.75) -> Dictionary:
	var state: RefCounted = Scenarios.create("open_field_attack", 71, sleeping_areas)
	var service: RefCounted = Roles.new()
	assert(service.configure(state, hierarchy(), people(), role))
	var result: Dictionary
	if role == "ordinary_soldier":
		result = service.apply(command("script", "local_action", role, {"action": "take_cover"}))
	elif role == "squad_leader":
		result = service.apply(command("script", "tactical_intent", "squad_attack_00", {"posture": "support"}))
	else:
		var targets: Dictionary = {"platoon_leader": "squad_attack_00", "company_commander": "platoon_blue00",
			"battalion_commander": "company_blue0", "regiment_commander": "battalion_blue", "division_commander": "regiment_blue"}
		result = service.apply(command("script", "mission", targets[role], mission_values("advance", mission_objective)))
	return {"state": state, "service": service, "command": result, "policy": policy}
