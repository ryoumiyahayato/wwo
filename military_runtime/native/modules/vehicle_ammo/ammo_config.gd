extends RefCounted
## Fictional prototype loadouts, not historical equipment data. All live stock starts here.
const VERSION := "prototype_vehicle_ammo_v1"
static func loadout(primary: String, fixed_ai := false) -> Dictionary:
	var result: Dictionary = {}
	if primary == "cannon":
		result.primary = {"kind":"chamber", "rounds":{"ap":40} if fixed_ai else {"ap":24,"he":12,"smoke":4}, "initial":"ap"}
	elif primary == "short_rocket":
		result.primary = {"kind":"burst", "rounds":{"he":12}, "initial":"he"}
	if primary != "short_rocket":
		result.mg = {"kind":"belt", "rounds":{"ap":300} if fixed_ai else {"tracer":180,"ap":90,"incendiary":30}, "initial":"ap" if fixed_ai else "tracer"}
	return result
