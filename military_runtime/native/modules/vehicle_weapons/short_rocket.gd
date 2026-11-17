extends Node3D
## One fictional short-range rocket. Damage, salvo timing and effects belong to the host.
## No target IDs, camera aiming, homing, gravity or real-world ballistics are used.

signal impacted(event: Dictionary)

const SPEED: float = 18.0
const MAX_LIFETIME: float = 4.0
const MAX_DISTANCE: float = 72.0
const COLLISION_MASK: int = 1 | 8 | 128

var source_id: String = "player"
var _launch_transform := Transform3D.IDENTITY
var _origin := Vector3.ZERO
var _direction := Vector3.FORWARD
var _owner_exclusions: Array[RID] = []
var _age: float = 0.0
var _distance: float = 0.0
var _configured: bool = false
var _ended: bool = false

@warning_ignore("shadowed_variable")
func setup(muzzle_transform: Transform3D, exclusions: Array[RID] = [], source_id: String = "player") -> void:
	# Each instance is a single launch. Reconfiguration cannot retarget an active rocket.
	if _configured:
		return
	_launch_transform = muzzle_transform
	_origin = muzzle_transform.origin
	_direction = -muzzle_transform.basis.z.normalized()
	self.source_id = source_id
	_owner_exclusions = exclusions.duplicate()
	_owner_exclusions.make_read_only()
	_configured = true
	if is_inside_tree():
		set_as_top_level(true)
		global_transform = _launch_transform
	set_physics_process(true)

func _ready() -> void:
	# Parent movement/rotation after launch must not move or steer the projectile.
	set_as_top_level(true)
	if _configured:
		global_transform = _launch_transform
	_build_visual()
	set_physics_process(_configured)

func _physics_process(delta: float) -> void:
	if not _configured or _ended or delta <= 0.0:
		return
	var active_delta: float = minf(delta, maxf(0.0, MAX_LIFETIME - _age))
	var step_distance: float = minf(SPEED * active_delta, maxf(0.0, MAX_DISTANCE - _distance))
	if step_distance > 0.0:
		var segment_start: Vector3 = global_position
		var segment_end: Vector3 = segment_start + _direction * step_distance
		var query := PhysicsRayQueryParameters3D.create(segment_start, segment_end, COLLISION_MASK, _owner_exclusions)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.hit_from_inside = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			_distance += segment_start.distance_to(hit.position)
			_age += segment_start.distance_to(hit.position) / SPEED
			_ended = true
			set_physics_process(false)
			impacted.emit({
				"position": hit.position,
				"normal": hit.normal,
				"collider": hit.collider,
				"origin": _origin,
				"direction": _direction,
			})
			queue_free()
			return
		global_position = segment_end
		_distance += step_distance
	_age += active_delta
	if _age >= MAX_LIFETIME - 0.000001 or _distance >= MAX_DISTANCE - 0.000001:
		_ended = true
		set_physics_process(false)
		queue_free()

func get_launch_origin() -> Vector3:
	return _origin

func get_launch_direction() -> Vector3:
	return _direction

func get_distance_travelled() -> float:
	return _distance

func get_age_seconds() -> float:
	return _age

func _build_visual() -> void:
	# A compact warm tip and 0.36-unit tail, never a camera-facing beam or billboard.
	var tip := MeshInstance3D.new()
	tip.name = "WarmTip"
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	tip.mesh = sphere
	tip.material_override = _warm_material(Color(1.0, 0.76, 0.28), 1.7)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tip)
	var trail := MeshInstance3D.new()
	trail.name = "ShortTrail"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.012
	cone.bottom_radius = 0.038
	cone.height = 0.36
	cone.radial_segments = 8
	trail.mesh = cone
	trail.rotation.x = PI / 2.0
	trail.position.z = 0.20
	trail.material_override = _warm_material(Color(0.98, 0.36, 0.09), 1.1)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)

func _warm_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
