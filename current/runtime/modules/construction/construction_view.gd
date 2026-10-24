extends Node3D
## Optional procedural Godot presentation adapter. Model remains engine-scene independent.
const Rules = preload("res://modules/construction/construction_system.gd")
var construction_id := ""
var muzzle: Marker3D
var observation: Marker3D
var use_position: Marker3D
var _geometry: Node3D
var weapon_group: Node3D
var _draw_parent: Node3D
var _preset := ""
var _signature := ""

func sync(state: Dictionary) -> void:
 construction_id = str(state.id)
 var p: Array = state.position
 position = Vector3(p[0], p[1], p[2])
 rotation.y = float(state.yaw)
 var preset: Dictionary = Rules.PRESETS[state.preset]
 var progress := clampf(float(state.elapsed_ms) / float(preset.time_ms), 0.0, 1.0)
 var signature := "%s:%s:%d" % [state.preset, state.state, int(progress * 20.0)]
 if signature == _signature: return
 _signature = signature
 if is_instance_valid(_geometry):
  remove_child(_geometry)
  _geometry.queue_free()
 _geometry = Node3D.new()
 add_child(_geometry)
 _draw_parent = _geometry
 var complete: bool = state.state in ["finished", "occupied", "armed", "consumed"]
 var earth := Color("7d7250")
 var sand := Color("c5ac75")
 var steel := Color("405951")
 var wood := Color("735941")
 var k := 1.0 if complete else maxf(0.08, progress)
 var kind := str(state.preset)
 _preset = kind
 if kind.begins_with("mine_"):
  if state.state != "consumed":
   _box(Vector3(0,0.1,0),Vector3(0.55,0.2,0.55),steel,false)
   _box(Vector3(0,0.21,0),Vector3(0.3,0.03,0.3),Color("efad4e"),false)
   var area := Area3D.new()
   area.name = "GameTrigger"
   area.collision_layer = 0
   area.collision_mask = 16 | 32
   area.set_meta("construction_id",construction_id)
   var hit := CollisionShape3D.new()
   var sphere := SphereShape3D.new()
   sphere.radius = 0.7
   hit.shape = sphere
   area.add_child(hit)
   _geometry.add_child(area)
 elif kind == "barricade":
  for x in [-1.1,0.0,1.1]:
   for tilt in [-0.65,0.65]:
    var beam := _box(Vector3(x,0.65*k,0),Vector3(0.18,1.8*k,0.18),wood,complete)
    beam.rotation.z = tilt
  _box(Vector3(0,0.7*k,0),Vector3(3.4,0.18,0.18),wood,complete)
  # Invisible broad collision envelope stops both character and vehicle bodies.
  if complete:
   var barrier := StaticBody3D.new()
   barrier.collision_layer = 1
   barrier.set_meta("construction_id",construction_id)
   var hit := CollisionShape3D.new()
   var shape := BoxShape3D.new()
   shape.size = Vector3(3.6,1.5,0.8)
   hit.shape = shape
   hit.position.y = 0.75
   barrier.add_child(hit)
   _geometry.add_child(barrier)
 elif kind == "foxhole":
  # The terrain adapter supplies an actual opening and floor, not a dark surface decal.
  for x in [-1.0, 1.0]: _box(Vector3(x * 1.45, 0.2*k, 0), Vector3(0.5,0.4*k,3.3), earth, complete)
  for z in [-1.0,1.0]: _box(Vector3(0,0.08*k,z*1.45), Vector3(2.4,0.16*k,0.5), earth, complete)
 else:
  _box(Vector3(0,0.04,0), Vector3(3.5,0.08,3.2), earth, false)
  if kind != "tower":
   for row in range(2):
    for block in range(5):
     _box(Vector3((block-2)*0.65, (0.22+row*0.38)*k,-1.35),Vector3(0.62,0.36*k,0.5),sand,complete)
   for side in [-1.0,1.0]:
    for block in range(3): _box(Vector3(side*1.6,0.24*k, -0.75+block*0.6),Vector3(0.5,0.45*k,0.57),sand,complete)
 weapon_group = Node3D.new()
 _geometry.add_child(weapon_group)
 _draw_parent = weapon_group
 if kind == "mg":
  _box(Vector3(0,0.6*k,0),Vector3(0.16,1.2*k,0.16),steel,complete)
  _box(Vector3(0,1.2*k,-0.35),Vector3(0.3,0.22,1.15),steel,complete)
  _box(Vector3(-0.26,1.12*k,0),Vector3(0.25,0.3,0.36),Color("ac8d3f"),false)
 elif kind == "mortar":
  _box(Vector3(0,0.1,0),Vector3(0.8,0.16,0.8),steel,complete)
  var tube := _box(Vector3(0,0.65*k,-0.15),Vector3(0.25,1.1*k,0.25),steel,complete)
  tube.rotation.x = -0.4
 elif kind == "at":
  for side in [-1.0,1.0]:
   _box(Vector3(side*0.9,0.4*k,0),Vector3(0.25,0.75*k,0.75),Color("292f2e"),complete)
   var trail := _box(Vector3(side*0.5,0.2,0.65),Vector3(0.13,0.2,1.4),steel,complete)
   trail.rotation.y = side*0.4
  _box(Vector3(0,0.9*k,-0.2),Vector3(1.7,1.1*k,0.16),steel,complete)
  _box(Vector3(0,1.05*k,-1.0),Vector3(0.2,0.2,2.0),steel,complete)
 elif kind == "tower":
  _draw_parent = _geometry
  for x in [-1.0,1.0]:
   for z in [-1.0,1.0]: _box(Vector3(x,1.6*k,z),Vector3(0.18,3.2*k,0.18),wood,complete)
  _box(Vector3(0,3.1*k,0),Vector3(2.5,0.2,2.5),wood,complete)
  for side in [-1.0,1.0]:
   _box(Vector3(side*1.15,3.65*k,0),Vector3(0.12,0.8,2.4),sand,complete)
   _box(Vector3(0,3.65*k,side*1.15),Vector3(2.3,0.8,0.12),sand,complete)
  for side in [-1.0,1.0]: _box(Vector3(side*0.34,1.6,1.3),Vector3(0.1,3.2,0.12),wood,false)
  for rung in range(8): _box(Vector3(0,0.25+rung*0.37,1.3),Vector3(0.6,0.07,0.1),wood,false)
 _draw_parent = _geometry
 if not complete:
  # Orange posts, partially erected structure, progress beam, and animated digging tool.
  for side in [-1.0,1.0]: _box(Vector3(side*1.8,0.45,1.55),Vector3(0.09,0.9,0.09),Color("efad4e"),false)
  _box(Vector3(-1.5+1.5*progress,1.1,1.65),Vector3(maxf(0.03,3.0*progress),0.13,0.12),Color("7fd5bd"),false)
  var tool := _box(Vector3(0.6,0.6,0.4),Vector3(0.08,1.1,0.08),wood,false)
  tool.rotation.z = sin(progress*45.0)*0.45
  _box(Vector3(0.6,0.1,0.4),Vector3(0.32,0.3,0.08),steel,false)
 muzzle = _anchor("Muzzle", Vector3(0, 0.0, 0))
 muzzle.reparent(weapon_group,false)
 match kind:
  "mg": muzzle.position = Vector3(0,1.2,-1.0)
  "mortar":
   muzzle.position = Vector3(0,1.2,-0.4)
   muzzle.rotation.x = PI/2.0-0.4
  "at": muzzle.position = Vector3(0,1.05,-2.08)
 observation = _anchor("Observation", Vector3(0,preset.observe_y,0.3))
 use_position = _anchor("UsePosition", Vector3(0,preset.use_y,0.45))

func _anchor(label: String, at: Vector3) -> Marker3D:
 var marker := Marker3D.new()
 marker.name = label
 marker.position = at
 _geometry.add_child(marker)
 return marker

func _box(at: Vector3, size: Vector3, color: Color, solid: bool) -> Node3D:
 var root := Node3D.new()
 root.position = at
 _draw_parent.add_child(root)
 var mesh := MeshInstance3D.new()
 var box := BoxMesh.new()
 box.size = size
 mesh.mesh = box
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = 0.92
 mesh.material_override = mat
 root.add_child(mesh)
 if solid:
  var body := StaticBody3D.new()
  body.set_meta("construction_id",construction_id)
  body.collision_layer = 1
  var collision := CollisionShape3D.new()
  var shape := BoxShape3D.new()
  shape.size = size
  collision.shape = shape
  body.add_child(collision)
  root.add_child(body)
 return root

func aim_at(world_target: Vector3) -> void:
 if not is_instance_valid(weapon_group): return
 if _preset == "mortar":
  var horizontal := world_target
  horizontal.y = weapon_group.global_position.y
  if horizontal.distance_to(weapon_group.global_position)>0.01: weapon_group.look_at(horizontal)
 elif _preset in ["mg","at"]:
  if world_target.distance_to(weapon_group.global_position)>0.01: weapon_group.look_at(world_target)
