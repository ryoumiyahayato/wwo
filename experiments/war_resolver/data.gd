extends RefCounted
## EXPERIMENT ONLY. Plain snapshot records, never formal world authorities.

static func area(id: String, cover: float = 0.1, frontage: float = 40.0) -> Dictionary:
	return {"id": id, "movement_modifier": 1.0, "cover": cover,
		"concealment": cover * 0.5, "frontage": frontage, "visibility": 1.0,
		"links": {}, "control": "", "size_km": 5.0}


static func mission(id: String, posture: String = "hold", direction: float = 1.0,
		objective: float = 4.0) -> Dictionary:
	return {"id": id, "objective": objective, "direction": direction,
		"posture": posture, "priority": 1, "stop_suppression": 0.55,
		"withdraw_cohesion": 0.25, "status": "active", "destination": ""}


static func unit(id: String, side: String, area_id: String, mission_id: String,
		position: float = 0.0, personnel: float = 12.0) -> Dictionary:
	return {"id": id, "side": side, "echelon": "squad", "type": "infantry",
		"parent_id": "", "area_id": area_id, "position": position,
		"personnel_total": personnel, "effective": personnel, "casualties": 0.0,
		"ammunition": personnel * 80.0, "ammo_spent": 0.0,
		"equipment": personnel, "equipment_lost": 0.0,
		"fatigue": 0.0, "cohesion": 0.95, "suppression": 0.0,
		"mobility": 0.08, "readiness": 1.0, "mission_id": mission_id,
		"weapon": {"rounds_per_minute": 1.2, "lethality": 0.008, "range_km": 5.0},
		"action": "idle", "distance_moved": 0.0}
