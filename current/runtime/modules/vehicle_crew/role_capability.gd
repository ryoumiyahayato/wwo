extends RefCounted
## Pure read-only projection of the existing person record, shared by player and AI.
const ROLE_NAMES := {"炮手":"gunner", "驾驶员":"driver", "装填手":"loader", "车长":"commander", "无线电员":"radio", "通讯员":"radio"}
static func capable(person: Dictionary, role: String) -> bool:
	if not bool(person.get("alive", false)) or float(person.get("hp", 0.0)) <= 0.0 or bool(person.get("incapacitated", false)): return false
	var parts: Dictionary = person.get("parts", {})
	if parts.get("head", "healthy") == "disabled" or parts.get("torso", "healthy") == "disabled": return false
	role = str(ROLE_NAMES.get(role, role))
	if role in ["gunner", "loader"] and parts.get("left_arm") == "disabled" and parts.get("right_arm") == "disabled": return false
	if role == "driver" and parts.get("left_leg") == "disabled" and parts.get("right_leg") == "disabled": return false
	return true
