extends Node3D
## Dedicated 12 x 12 game-unit training platform. Host MUST NOT put uncut ground
## collision across its central opening. Mount outside the main terrain footprint.
## One fixed center foxhole; no arbitrary terrain mutation or fake painted hole.
var depth := 0.0
var reserved := false
var _parts: Node3D

func _ready() -> void:
 _rebuild()

func reserve(world_position: Vector3) -> bool:
 if reserved: return false
 var local := to_local(world_position)
 if Vector2(local.x, local.z).length() > 0.2 or absf(local.y) > 0.2: return false
 reserved = true
 return true

func set_progress(progress: float) -> void:
 var next_depth := roundf(clampf(progress,0.0,1.0)*20.0)/20.0 * 0.9
 if is_equal_approx(next_depth, depth): return
 depth = next_depth
 _rebuild()

func reset_patch() -> void:
 reserved = false
 depth = 0.0
 _rebuild()

func _rebuild() -> void:
 if is_instance_valid(_parts):
  remove_child(_parts)
  _parts.queue_free()
 _parts = Node3D.new()
 add_child(_parts)
 # Four solid slabs surround a real 2.4 x 2.4 gap. Center slab sinks as digging advances.
 _slab(Vector3(-3.6,-0.65,0),Vector3(4.8,1.3,12),Color("89935e"))
 _slab(Vector3(3.6,-0.65,0),Vector3(4.8,1.3,12),Color("89935e"))
 _slab(Vector3(0,-0.65,-3.6),Vector3(2.4,1.3,4.8),Color("89935e"))
 _slab(Vector3(0,-0.65,3.6),Vector3(2.4,1.3,4.8),Color("89935e"))
 _slab(Vector3(0,-depth-0.15,0),Vector3(2.4,0.3,2.4),Color("78694a") if depth > 0 else Color("89935e"))

func _slab(at: Vector3, size: Vector3, tint: Color) -> void:
 var body := StaticBody3D.new()
 body.position = at
 body.collision_layer = 1
 body.set_meta("excavation_patch",true)
 _parts.add_child(body)
 var mesh := MeshInstance3D.new()
 var box := BoxMesh.new()
 box.size = size
 mesh.mesh = box
 var mat := StandardMaterial3D.new()
 mat.albedo_color = tint
 mat.roughness = 1.0
 mesh.material_override = mat
 body.add_child(mesh)
 var collision := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = size
 collision.shape = shape
 body.add_child(collision)
