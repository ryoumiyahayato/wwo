extends RefCounted
## Fictional prototype constants shared by the three armored-car variants.
## These are game values, not historical or engineering specifications.

const ARMOR_CAR_PROFILE: Dictionary = {
	"front": 40, "left": 25, "right": 25, "rear": 20, "top": 15, "bottom": 15,
	"turret_front": 35, "turret_left": 25, "turret_right": 25,
	"turret_rear": 20, "turret_top": 15, "turret_bottom": 15,
	# Existing Combat external-mobility keys are reused for the car's wheel groups.
	"track_left": 12, "track_right": 12,
}

const MG_AMMO: Dictionary = {
	"tracer": {"name": "曳光弹", "penetration": 5, "incendiary": false},
	"ap": {"name": "穿甲弹", "penetration": 15, "incendiary": false},
	"incendiary": {"name": "燃烧弹", "penetration": 5, "incendiary": true},
}

const MG_INTERVAL: float = 0.2
const CANNON_AP_PENETRATION: int = 90
const CANNON_RELOAD: float = 2.5
const ROCKET_ROUNDS: int = 3
const ROCKET_SALVO_GAP: float = 0.18
const ROCKET_RELOAD: float = 7.0
const ROCKET_HE_GRAMS: float = 100.0
const ROCKET_HE_RADIUS: float = 10.0
const MG_TURRET_DEGREES_PER_SECOND: float = 75.0
const CANNON_TURRET_DEGREES_PER_SECOND: float = 50.0
const ROCKET_TURRET_DEGREES_PER_SECOND: float = 30.0

const WEAPON_PRESETS: Dictionary = {
	"mg": {"kind": "mg", "interval": MG_INTERVAL, "ammo": MG_AMMO,
		"turret_degrees_per_second": MG_TURRET_DEGREES_PER_SECOND},
	"cannon": {"kind": "cannon", "ap_penetration": CANNON_AP_PENETRATION,
		"reload_seconds": CANNON_RELOAD, "turret_degrees_per_second": CANNON_TURRET_DEGREES_PER_SECOND},
	"short_rocket": {"kind": "short_rocket", "rounds": ROCKET_ROUNDS, "gap": ROCKET_SALVO_GAP,
		"reload_seconds": ROCKET_RELOAD, "he_grams": ROCKET_HE_GRAMS, "he_radius": ROCKET_HE_RADIUS,
		"turret_degrees_per_second": ROCKET_TURRET_DEGREES_PER_SECOND},
}

static func armor_profile() -> Dictionary:
	return ARMOR_CAR_PROFILE.duplicate(true)

static func weapon_preset(kind: String) -> Dictionary:
	return WEAPON_PRESETS.get(kind, {}).duplicate(true)
