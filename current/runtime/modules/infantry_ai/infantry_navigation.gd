extends RefCounted
## Bounded local grid routing for actual capsules. Never moves or teleports an actor.
const STEP := 0.9
const LIMIT := 22
const MAX_EXPANSIONS := 220
var actor: CharacterBody3D
var origin := Vector3.ZERO
var cells: Dictionary = {}
var edges: Dictionary = {}
var edge_queries := 0
var capsule := CapsuleShape3D.new()
func plan(body: CharacterBody3D, destination: Vector3) -> Array[Vector3]:
 actor = body
 origin = body.global_position
 cells.clear()
 edges.clear()
 edge_queries = 0
 capsule.radius = 0.31
 capsule.height = 1.65
 var offset := Vector2(destination.x-origin.x,destination.z-origin.z)
 if offset.length()>STEP*(LIMIT-2): offset = offset.normalized()*STEP*(LIMIT-2)
 var goal := Vector2i(roundi(offset.x/STEP),roundi(offset.y/STEP))
 var zero := Vector2i.ZERO
 cells[zero] = {"ok":true,"position":origin}
 if not _cell(goal).ok:
  var found := false
  for radius in range(1,5):
   for offset_goal in [Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,radius),Vector2i(0,-radius)]:
    var alternative: Vector2i = goal+offset_goal
    if absi(alternative.x)<=LIMIT and absi(alternative.y)<=LIMIT and _cell(alternative).ok:
     goal=alternative
     found=true
     break
   if found: break
  if not found: return []
 var open: Array[Vector2i] = [zero]
 var costs := {zero:0.0}
 var previous := {}
 var closed := {}
 for _iteration in MAX_EXPANSIONS:
  if open.is_empty(): return []
  var best := 0
  var best_score := INF
  for index in open.size():
   var key: Vector2i = open[index]
   var score: float = float(costs[key])+Vector2(key-goal).length()
   if score<best_score:
    best = index
    best_score = score
  var current: Vector2i = open[best]
  open.remove_at(best)
  # Lazy edge validation: at most one capsule sweep per popped node, not
  # eight sweeps per expansion. Clear endpoints alone miss thin barriers.
  if current!=zero and not _edge_clear(previous[current],current):
   costs.erase(current)
   previous.erase(current)
   # Another already-expanded neighbor may reach this cell safely. Re-parent
   # lazily rather than forgetting that alternative when its first edge fails.
   var alternative_cost := INF
   var alternative := current
   for dx in [-1,0,1]:
    for dz in [-1,0,1]:
     var neighbor := current+Vector2i(dx,dz)
     if not closed.has(neighbor): continue
     var edge_key := Vector4i(neighbor.x,neighbor.y,current.x,current.y)
     if edges.has(edge_key) and not edges[edge_key]: continue
     if absf(float(_cell(neighbor).position.y)-float(_cell(current).position.y))>0.65: continue
     if dx!=0 and dz!=0 and (not _cell(current+Vector2i(dx,0)).ok or not _cell(current+Vector2i(0,dz)).ok): continue
     var cost: float = float(costs[neighbor])+(1.414214 if dx!=0 and dz!=0 else 1.0)
     if cost<alternative_cost:
      alternative_cost=cost
      alternative=neighbor
   if alternative!=current:
    costs[current]=alternative_cost
    previous[current]=alternative
    open.append(current)
   continue
  if current==goal:
   var path: Array[Vector3] = []
   while current!=zero:
    path.push_front(_cell(current).position)
    current = previous[current]
   return path
  closed[current] = true
  for dx in [-1,0,1]:
   for dz in [-1,0,1]:
    if dx==0 and dz==0: continue
    var next := current+Vector2i(dx,dz)
    if absi(next.x)>LIMIT or absi(next.y)>LIMIT or closed.has(next): continue
    var edge_key := Vector4i(current.x,current.y,next.x,next.y)
    if edges.has(edge_key) and not edges[edge_key]: continue
    var next_cell := _cell(next)
    if not next_cell.ok: continue
    if absf(float(next_cell.position.y)-float(_cell(current).position.y))>0.65: continue
    # A diagonal may not cut through an occupied corner.
    if dx!=0 and dz!=0 and (not _cell(current+Vector2i(dx,0)).ok or not _cell(current+Vector2i(0,dz)).ok): continue
    var score: float = float(costs[current])+(1.414214 if dx!=0 and dz!=0 else 1.0)
    if costs.has(next) and score>=float(costs[next]): continue
    costs[next] = score
    previous[next] = current
    if not open.has(next): open.append(next)
 return []
func _cell(key: Vector2i) -> Dictionary:
 if cells.has(key): return cells[key]
 var position := origin+Vector3(key.x*STEP,0,key.y*STEP)
 var space := actor.get_world_3d().direct_space_state
 var ground_query := PhysicsRayQueryParameters3D.create(position+Vector3.UP*3.0,position-Vector3.UP*4.0,8,[actor.get_rid()])
 var ground := space.intersect_ray(ground_query)
 var result := {"ok":false,"position":position}
 if ground.is_empty() or ground.normal.dot(Vector3.UP)<cos(actor.floor_max_angle):
  cells[key] = result
  return result
 position.y = ground.position.y+0.04
 var query := PhysicsShapeQueryParameters3D.new()
 query.shape = capsule
 query.transform = Transform3D(Basis.IDENTITY,position+Vector3.UP*0.93)
 query.collision_mask = actor.collision_mask
 query.exclude = [actor.get_rid()]
 result.position = position
 result.ok = space.intersect_shape(query,1).is_empty()
 cells[key] = result
 return result

func _edge_clear(from: Vector2i, to: Vector2i) -> bool:
 var key := Vector4i(from.x,from.y,to.x,to.y)
 if edges.has(key): return edges[key]
 var start: Vector3 = _cell(from).position+Vector3.UP*0.93
 var finish: Vector3 = _cell(to).position+Vector3.UP*0.93
 var query := PhysicsShapeQueryParameters3D.new()
 query.shape = capsule
 query.transform = Transform3D(Basis.IDENTITY,start)
 query.motion = finish-start
 query.collision_mask = actor.collision_mask
 query.exclude = [actor.get_rid()]
 edge_queries += 1
 var safe: PackedFloat32Array = actor.get_world_3d().direct_space_state.cast_motion(query)
 var clear := safe[0]>=0.999
 edges[key] = clear
 edges[Vector4i(to.x,to.y,from.x,from.y)] = clear
 return clear
