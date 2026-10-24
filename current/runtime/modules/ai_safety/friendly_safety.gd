extends RefCounted
## Local collision safety, never enemy acquisition or aiming information.
static func collider_team(collider:Object,player_team:String="blue")->String:
 var node:=collider as Node
 while is_instance_valid(node):
  if node.has_meta("team_id"):return str(node.get_meta("team_id"))
  if str(node.get_meta("actor_id",""))=="player":return player_team
  node=node.get_parent()
 return ""
static func friendly_corridor(space:PhysicsDirectSpaceState3D,origin:Vector3,endpoint:Vector3,exclude:Array[RID],team:String,player_team:String="blue")->bool:
 var segment:Vector3=endpoint-origin
 var length:=minf(segment.length(),12.0)
 if length<.01:return false
 var shape:=CapsuleShape3D.new();shape.radius=.3;shape.height=length+.6
 var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape
 query.transform=Transform3D(Basis(Quaternion(Vector3.UP,segment.normalized())),origin+segment.normalized()*length*.5)
 query.collision_mask=1|8|128;query.exclude=exclude
 for hit in space.intersect_shape(query,16):
  if collider_team(hit.collider,player_team)==team:return true
 return false
static func nearby_friendly_vehicles(actor:Node3D,host:Node,team:String)->Array[Node3D]:
 var result:Array[Node3D]=[]
 if not is_instance_valid(host) or not is_instance_valid(host.main):return result
 var main:Node3D=host.main
 if is_instance_valid(main.armor_host):
  for u in main.armor_host.units.values():
   if str(u.team)==team and is_instance_valid(u.model) and actor.global_position.distance_squared_to(u.model.global_position)<144.0:result.append(u.model)
 if int(main.unit)!=2 and is_instance_valid(host.player_actor) and host.player_team==team and actor.global_position.distance_squared_to(host.player_actor.global_position)<144.0:result.append(host.player_actor)
 return result
static func corridor_contains(vehicle:Node3D,point:Vector3,include_motion:bool=true)->bool:
 var p:=vehicle.to_local(point)
 if absf(p.y)>3.0 or absf(p.x)>2.35:return false
 var speed:=float(vehicle.get_meta("vehicle_speed",0.0))
 var ahead:=minf(absf(speed)*1.8,7.0) if include_motion else 0.0
 return p.z>=-3.7-(ahead if speed>0 else 0.0) and p.z<=3.7+(ahead if speed<0 else 0.0)
