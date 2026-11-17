extends Node
## Swaps shared Mesh resources on existing articulated nodes, never duplicates actors.
## Projected-size hysteresis and six-near cap; shared existing skeleton hierarchy.
const ENTER_PIXELS := 140.0
const EXIT_PIXELS := 105.0
const MAX_NEAR := 6
const UPDATE_INTERVAL := 0.25
const MIN_RESIDENCE := 1.0
var camera: Camera3D
var host: Node
var high_meshes: Dictionary = {}
var records: Dictionary = {}
var _clock := 0.0
var _next_update := 0.0
var swaps := 0

func setup(owner_host: Node, view_camera: Camera3D, high_scene: PackedScene) -> void:
 host = owner_host
 camera = view_camera
 var sample := high_scene.instantiate()
 for mesh_node in sample.find_children("*", "MeshInstance3D", true, false):
  high_meshes[str(mesh_node.name)] = mesh_node.mesh
 sample.free()

func register_actor(actor: Node3D) -> void:
 if not is_instance_valid(actor) or records.has(actor.get_instance_id()): return
 var visual := actor.get_node_or_null("InfantryVisual")
 if visual == null: return
 var pairs: Array = []
 for mesh_node in visual.find_children("*", "MeshInstance3D", true, false):
  if high_meshes.has(str(mesh_node.name)):
   pairs.append({"node":weakref(mesh_node), "low":mesh_node.mesh, "high":high_meshes[str(mesh_node.name)]})
 records[actor.get_instance_id()] = {"actor":weakref(actor), "pairs":pairs, "near":false, "since":-10.0, "eligible_since":-1.0, "pixels":0.0}

func _swap(record: Dictionary, near: bool) -> void:
 if record.near == near: return
 for pair in record.pairs:
  var node = pair.node.get_ref()
  if is_instance_valid(node): node.mesh = pair.high if near else pair.low
 record.near = near
 record.since = _clock
 swaps += 1

func projected_height(actor: Node3D) -> float:
 var center: Vector3 = actor.global_position + Vector3.UP * 0.85
 if camera.is_position_behind(center): return 0.0
 var screen: Vector2 = camera.unproject_position(center)
 var rect := camera.get_viewport().get_visible_rect()
 if not rect.grow(80).has_point(screen): return 0.0
 var top := camera.unproject_position(center + Vector3.UP * 0.85)
 var bottom := camera.unproject_position(center - Vector3.UP * 0.85)
 return top.distance_to(bottom)

func _process(delta: float) -> void:
 _clock += delta
 if _clock < _next_update or not is_instance_valid(camera) or not is_instance_valid(host): return
 _next_update = _clock + UPDATE_INTERVAL
 refresh()

func refresh() -> void:
 var actors: Dictionary = host.get("actors")
 for actor in actors.values():
  if is_instance_valid(actor): register_actor(actor)
 var candidates: Array = []
 var active: Array = []
 for id in records.keys():
  var record: Dictionary = records[id]
  var actor = record.actor.get_ref()
  if not is_instance_valid(actor):
   records.erase(id)
   continue
  record.pixels = projected_height(actor) if actor.is_visible_in_tree() else 0.0
  # Render poses only: physics, timers, reloads, firing and due-time perception remain live.
  # Accumulated real delta keeps locomotion phase correct when presentation is throttled.
  actor.set_meta("animation_interval",0.0 if bool(actor.get_meta("player_controlled",false)) or record.pixels>=ENTER_PIXELS else (0.05 if record.pixels>=45.0 else 0.125))
  if record.near:
   if record.pixels < EXIT_PIXELS and (_clock-record.since >= MIN_RESIDENCE or record.pixels == 0.0):
    _swap(record,false)
   else: active.append(record)
  elif record.pixels >= ENTER_PIXELS:
   if record.eligible_since < 0: record.eligible_since = _clock
   candidates.append(record)
  else: record.eligible_since = -1.0
 candidates.sort_custom(func(a,b): return a.pixels > b.pixels)
 for challenger in candidates:
  if active.size() < MAX_NEAR:
   _swap(challenger,true)
   active.append(challenger)
   continue
  active.sort_custom(func(a,b): return a.pixels < b.pixels)
  var incumbent: Dictionary = active[0]
  if challenger.pixels > incumbent.pixels * 1.2 and _clock-challenger.eligible_since >= 0.5 and _clock-incumbent.since >= MIN_RESIDENCE:
   _swap(incumbent,false)
   active.pop_front()
   _swap(challenger,true)
   active.append(challenger)

func restore_all() -> void:
 for record in records.values(): _swap(record,false)
 records.clear()

func snapshot() -> Dictionary:
 var near := 0
 for record in records.values():
  if record.near: near += 1
 return {"near":near,"registered":records.size(),"swaps":swaps,"cap":MAX_NEAR}
