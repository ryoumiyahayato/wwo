extends Node3D
# Fictional game balance; one clock drives both rendering and obscuration.
const PUFF_SHADER = preload("res://scripts/smoke_puff.gdshader")
const DURATION := 36.0
const GROW_SECONDS := 3.0
const FADE_START := 27.0
const MAX_RADIUS := 6.5
const CENTER_HEIGHT := 2.6
const PUFF_COUNT := 25
const CORE_COUNT := 9
const RIM_COUNT := PUFF_COUNT - CORE_COUNT
var age := 0.0
var puffs: Array[MeshInstance3D] = []
var puff_material: ShaderMaterial
var core_materials: Array[ShaderMaterial] = []
static func radius_at(seconds: float) -> float:
	return lerpf(1.4, MAX_RADIUS, smoothstep(0.0, GROW_SECONDS, seconds))
static func opacity_at(seconds: float) -> float:
	return smoothstep(0.0, .35, seconds) * (1.0 - smoothstep(FADE_START, DURATION, seconds))
static func obscures_at(seconds: float) -> bool:
	return seconds > 0.0 and seconds < DURATION
func obscuration_radius() -> float:
	return radius_at(age) if obscures_at(age) else 0.0
func obscuration_center() -> Vector3:
	return global_position + Vector3.UP * CENTER_HEIGHT
static func make_puff_material(tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new(); mat.shader = preload("res://scripts/battle_vfx_billows.gdshader")
	mat.set_shader_parameter("tint", tint)
	return mat
func _ready() -> void:
	name = "ContinuousSmokeCloud"
	puff_material = make_puff_material(Color(.60,.63,.65,.82))
	puff_material.set_shader_parameter("cloud_softness",0.55)
	puff_material.set_shader_parameter("soft_intersection",1.2)
	var quad := QuadMesh.new(); quad.size = Vector2.ONE * 5.6
	for i in range(RIM_COUNT):
		var puff := MeshInstance3D.new()
		puff.mesh = quad; puff.material_override = puff_material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var height := 1.0 - 2.0 * float(i) / float(RIM_COUNT - 1)
		var theta := float(i) * 2.399963
		var ring := sqrt(maxf(0.0, 1.0-height*height)) * 3.7
		puff.set_meta("offset", Vector3(cos(theta)*ring, height*3.7, sin(theta)*ring))
		add_child(puff); puffs.append(puff)
	# A shell of small puffs left visible holes through the center after its
	# radial falloff and soft intersections. Spend the same 25-puff budget on
	# a filled, overlapping core plus a softer outer shell, not a LOS shortcut.
	var core_quad := QuadMesh.new(); core_quad.size = Vector2.ONE * 9.0
	for i in range(CORE_COUNT):
		var material := make_puff_material(Color(.60,.63,.65,.98))
		material.set_shader_parameter("cloud_softness",1.0)
		material.set_shader_parameter("soft_intersection",1.2)
		# Independent low-frequency billows avoid aligned transparent patches.
		material.set_shader_parameter("seed",.73 if i == 0 else float(i)*1.731)
		core_materials.append(material)
		var puff := MeshInstance3D.new()
		puff.mesh = core_quad; puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var corner := i - 1
		var offset := Vector3.ZERO if i == 0 else Vector3(
			.8 if corner & 1 else -.8,
			.8 if corner & 2 else -.8,
			.8 if corner & 4 else -.8)
		puff.set_meta("offset", offset)
		puff.set_meta("dense_core", true)
		add_child(puff); puffs.append(puff)
	set_age(0.0)
func set_age(value: float) -> void:
	age = maxf(0.0, value)
	if puff_material == null: return
	puff_material.set_shader_parameter("opacity", opacity_at(age))
	puff_material.set_shader_parameter("age", age)
	for material in core_materials:
		material.set_shader_parameter("opacity", opacity_at(age))
		material.set_shader_parameter("age", age)
	var growth := radius_at(age) / MAX_RADIUS
	for puff in puffs:
		var base: Vector3 = puff.get_meta("offset")
		puff.position = Vector3.UP * CENTER_HEIGHT + base * growth
		# Cosmetic drift only; gameplay obscuration radius/clock above are unchanged.
		puff.position += Vector3(sin(age*.31+base.x)*.16,sin(age*.43+base.y)*.12,cos(age*.29+base.z)*.16)*growth
		puff.scale = Vector3.ONE * growth
func advance(delta: float) -> void:
	set_age(age + maxf(0.0, delta))
