extends RefCounted
## Fictional, abstract game rules. No real-world ballistics.
const BODY_PARTS = ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]
var rng := RandomNumberGenerator.new()
var forced_roll: int = -1 # Deterministic test injection, clamped to requested range.
var limb_damage: int = 3 # Fixed prototype value, not user-specified.
var penetration_module_damage: int = 15 # Prototype-only, separate from thickness.
var explosive_grams: float = 100.0
var crew_distance_m: float = 2.0
var modules: Dictionary
var crew: Array
var infantry: Dictionary

func _init(seed_value: int = 20261016):
	rng.seed = seed_value
	reset()

func reset():
	modules = {}
	var armor: Dictionary = ARMOR_CONFIG[tank_kind]
	for key in armor: modules[key] = {"thickness":armor[key], "integrity":100}
	crew_roles = CREW_CONFIG[tank_kind].duplicate()
	crew = []
	for role in crew_roles: crew.append(person())
	smoke_remaining = 0.0
	tarp_burning = false
	infantry = person()

func person() -> Dictionary:
	var parts := {}
	for part in BODY_PARTS:
		parts[part] = "healthy"
	return {"hp": 10, "alive": true, "parts": parts}

func roll(low: int, high: int) -> int:
	return clampi(forced_roll, low, high) if forced_roll >= 0 else rng.randi_range(low, high)

func hit_person(target: Dictionary, part: String) -> Dictionary:
	if not target.alive:
		return {"kind": "inactive", "part": part}
	if not part in BODY_PARTS:
		return {"kind": "invalid"}
	if part in ["head", "torso"]:
		target.hp = 0
		target.alive = false
		target.parts[part] = "disabled"
		return {"kind": "lethal", "part": part}
	target.hp = maxi(0, target.hp - limb_damage)
	target.parts[part] = "injured"
	target.alive = target.hp > 0
	return {"kind": "limb", "part": part, "alive": target.alive}

func explode(target: Dictionary, grams: float, distance_m: float) -> float:
	if not target.alive or distance_m > 10.0 or distance_m < 0.0 or grams <= 0.0:
		return 0.0
	var damage: float = roll(1, 5) * grams / 100.0
	target.hp = maxf(0.0, target.hp - damage)
	target.alive = target.hp > 0
	target.parts.torso = "injured" if target.alive else "disabled"
	return damage

func hit_armor(module_name: String, penetration: int, crew_index: int = -1, direct_part: String = "", occupants = null, impact: Dictionary = {}) -> Dictionary:
	if not modules.has(module_name):
		return {"kind": "invalid"}
	var module: Dictionary = modules[module_name]
	# Integrity never reduces effective thickness, including at 0%.
	# Equal penetration stops; prototype penetration threshold is strictly greater.
	var geometry := armor_geometry(float(module.thickness),impact)
	if penetration <= geometry.effective_thickness or not geometry.valid:
		var damage := roll(0, 10)
		module.integrity = maxi(0, module.integrity - damage)
		return {"kind": "stopped", "damage": damage, "module": module_name, "armor_geometry":geometry}
	module.integrity = maxi(0, module.integrity - penetration_module_damage)
	if module_name.begins_with("track_"):
		return {"kind":"external_penetrated", "damage":penetration_module_damage, "module":module_name, "crew_damage":[], "direct_hit":{}, "armor_geometry":geometry}
	var direct_hit: Dictionary = {}
	if crew_index >= 0 and crew_index < crew.size() and direct_part in BODY_PARTS and (occupants==null or crew_index in occupants):
		direct_hit = hit_person(crew[crew_index], direct_part)
	var damages: Array = []
	for i in range(crew.size()):
		damages.append(explode(crew[i], explosive_grams, crew_distance_m) if occupants==null or i in occupants else 0.0)
	return {"kind": "penetrated", "damage": penetration_module_damage, "module": module_name, "crew_damage": damages, "direct_hit": direct_hit, "armor_geometry":geometry}

# Upgrade rules: explicitly fictional, fixed preset tables.
const CREW_CONFIG = {
	"heavy": ["车长", "炮手", "驾驶员", "装填手", "通讯员"],
	"light": ["车长", "炮手", "驾驶员"],
	"car": ["车长", "炮手", "驾驶员"]
}
const MG_AMMO = {
	"tracer": {"name":"曳光弹", "penetration":5, "incendiary":false},
	"ap": {"name":"穿甲弹", "penetration":15, "incendiary":false},
	"incendiary": {"name":"燃烧弹", "penetration":5, "incendiary":true}
}
var crew_roles: Array = []
var tank_kind := "light"
var smoke_remaining := 0.0
var smoke_duration := 36.0
var tarp_burning := false
var he_mass_grams := 100.0

func configure_tank(kind: String):
	if not CREW_CONFIG.has(kind): return
	tank_kind = kind
	reset()

func high_explosive(target_kind: String, distance_m: float, occluded: bool = false) -> Dictionary:
	# Closed armor remains sealed even if integrity is0; no inferred hole.
	if target_kind == "armor":
		return {"kind":"sealed_armor", "damage":0.0}
	if target_kind == "infantry":
		if occluded:return {"kind":"covered", "damage":0.0}
		return {"kind":"blast", "damage":explode(infantry,he_mass_grams,distance_m)}
	return {"kind":"outside", "damage":0.0}

func deploy_smoke():
	smoke_remaining = smoke_duration
func advance_time(delta: float):
	smoke_remaining=maxf(0.0,smoke_remaining-maxf(0.0,delta))
func can_identify_target() -> bool:
	return smoke_remaining <= 0.0

func machine_gun(ammo_name: String, target_kind: String, body_part: String = "torso") -> Dictionary:
	if not MG_AMMO.has(ammo_name): return {"kind":"invalid"}
	var config: Dictionary = MG_AMMO[ammo_name]
	if target_kind == "infantry":
		return hit_person(infantry,body_part)
	if target_kind == "thin_plate":
		return {"kind":"plate_penetrated" if config.penetration>10 else "plate_stopped", "penetration":config.penetration, "thickness":10}
	if target_kind == "tarp":
		if config.incendiary:
			tarp_burning=true
			return {"kind":"ignited"}
		return {"kind":"material_hit"}
	# No crew injury or ignition through closed steel; MG AP remains below100.
	return {"kind":"armor_stopped", "penetration":config.penetration, "ignited":false}

const ARMOR_CONFIG = {
	"car": {"front":40,"rear":20,"left":25,"right":25,"top":15,"bottom":15,"turret_front":35,"turret_rear":20,"turret_left":25,"turret_right":25,"turret_top":15,"turret_bottom":15,"track_left":12,"track_right":12},
	"heavy": {"front":100,"rear":60,"left":75,"right":75,"top":35,"bottom":30,"turret_front":120,"turret_rear":60,"turret_left":85,"turret_right":85,"turret_top":40,"turret_bottom":30,"track_left":25,"track_right":25},
	"light": {"front":100,"rear":35,"left":50,"right":50,"top":25,"bottom":20,"turret_front":90,"turret_rear":40,"turret_left":55,"turret_right":55,"turret_top":30,"turret_bottom":20,"track_left":20,"track_right":20}
}

static func face_from_normal(global_basis: Basis, world_normal: Vector3, group: String = "hull") -> String:
	var n: Vector3 = global_basis.transposed() * world_normal
	var axis := ""
	if absf(n.x) >= absf(n.y) and absf(n.x) >= absf(n.z): axis = "right" if n.x>0 else "left"
	elif absf(n.y) >= absf(n.z): axis = "top" if n.y>0 else "bottom"
	else: axis = "rear" if n.z>0 else "front"
	return ("turret_" if group=="turret" else "") + axis

# Pure fictional line-of-sight plate geometry, evaluated only on an impact.
# Old calls without geometry remain normal-incidence; missing/invalid real rays
# are never guessed from vehicle yaw or a fixed whole-vehicle slope.
const MIN_INCIDENCE_COSINE := 0.05 # Bounded grazing multiplier: at most 20x.
static func armor_geometry(thickness: float, impact: Dictionary = {}) -> Dictionary:
	var result := {"nominal_thickness":thickness,"effective_thickness":thickness,"incidence_cosine":1.0,"incidence_degrees":0.0,"valid":true,"legacy":impact.is_empty(),"grazing_limited":false}
	if impact.is_empty():return result
	var normal: Vector3=impact.get("normal",Vector3.ZERO)
	var direction: Vector3=impact.get("direction",Vector3.ZERO)
	if not normal.is_finite() or not direction.is_finite() or normal.length_squared()<0.000001 or direction.length_squared()<0.000001:
		result.valid=false
		return result
	var signed_dot := normal.normalized().dot(direction.normalized())
	var cosine := clampf(absf(signed_dot),0.0,1.0)
	result.incidence_cosine=cosine
	result.incidence_degrees=rad_to_deg(acos(cosine))
	result.grazing_limited=cosine<MIN_INCIDENCE_COSINE
	result.effective_thickness=thickness/maxf(cosine,MIN_INCIDENCE_COSINE)
	# A ray leaving an outward-facing surface is not a fresh entry penetration.
	result.valid=signed_dot<=0.0
	return result

static func face_from_hit(collider:Node3D,world_normal:Vector3) -> String:
	var basis:Basis=collider.get_parent().global_basis
	var group:String=str(collider.get_meta("key","hull"))
	var local:Vector3=(basis.transposed()*world_normal).normalized()
	for override in collider.get_meta("armor_face_overrides",[]):
		var v:Array=override.normal
		if local.dot(Vector3(v[0],v[1],v[2]).normalized())>.9999:return str(override.face)
	return face_from_normal(basis,world_normal,group)
