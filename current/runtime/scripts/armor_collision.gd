extends RefCounted
## Cached, source-derived game collision proxy. No per-frame mesh work.
static var kestrel:Dictionary={}
static var heavy:Dictionary={}
static func install_hull(parent:Node3D) -> bool:
 var geometry:Dictionary={}
 if str(parent.scene_file_path).ends_with("/kestrel_scout.glb"):
  if kestrel.is_empty():kestrel=JSON.parse_string(FileAccess.get_file_as_string("res://assets/armor_geometry/kestrel_scout.json"))
  geometry=kestrel
 elif str(parent.scene_file_path).ends_with("/user_heavy_mbt_aimable.glb"):
  if heavy.is_empty():
   heavy=JSON.parse_string(FileAccess.get_file_as_string("res://assets/armor_geometry/user_heavy_mbt.json"))
   heavy["_source_matches"]=FileAccess.get_sha256(str(heavy.source))==str(heavy.source_sha256)
  if not bool(heavy.get("_source_matches",false)):return false
  geometry=heavy
 else:return false
 var body:=StaticBody3D.new()
 body.set_meta("kind","armor_group");body.set_meta("key","hull")
 body.set_meta("armor_face_overrides",geometry.face_overrides)
 for part in geometry.hull_shapes:
  var points:=PackedVector3Array()
  for p in part.vertices:points.append(Vector3(p[0],p[1],p[2]))
  var shape:=ConvexPolygonShape3D.new();shape.points=points
  var collision:=CollisionShape3D.new();collision.shape=shape
  body.add_child(collision)
 parent.add_child(body)
 return true
