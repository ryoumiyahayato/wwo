extends RefCounted
## Host supplies world query and any exclusions. Position is actor feet.
static func is_safe(space: PhysicsDirectSpaceState3D, feet: Vector3, exclusions: Array[RID] = [], mask: int = 1, radius: float = 0.35, height: float = 1.8) -> bool:
	if space == null or not feet.is_finite(): return false
	var ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.3, feet - Vector3.UP * 0.4, mask, exclusions)
	var floor_hit := space.intersect_ray(ray)
	if floor_hit.is_empty() or Vector3(floor_hit.normal).dot(Vector3.UP) < 0.65: return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (capsule.height * 0.5 + 0.05))
	query.collision_mask = mask
	query.exclude = exclusions
	return space.intersect_shape(query, 1).is_empty()
