extends RefCounted
## Shared live/preview segment collision. Terrain sampling closes streamed-collider gaps.
static func segment(space:PhysicsDirectSpaceState3D,a:Vector3,b:Vector3,exclude:Array[RID],height:Callable=Callable(),static_preview:bool=false)->Dictionary:
 var excluded:Array[RID]=exclude.duplicate()
 var hit:Dictionary={}
 for attempt in range(12):
  var query:=PhysicsRayQueryParameters3D.create(a,b,1|8|128,excluded);query.hit_from_inside=true
  hit=space.intersect_ray(query)
  if hit.is_empty() or not static_preview:break
  var node=hit.collider
  var actor:=false
  while is_instance_valid(node) and node is Node:
   if node.has_meta("actor_id"):actor=true;break
   node=node.get_parent()
  if not actor:break
  excluded.append(hit.rid);hit={}
 if not height.is_valid():return hit
 var count:=maxi(1,int(ceil(a.distance_to(b)/2.0)))
 var previous:=a
 for i in range(1,count+1):
  var point:=a.lerp(b,float(i)/count)
  var ground:float=float(height.call(point.x,point.z))
  if point.y<=ground:
   var lo:=previous;var hi:=point
   for iteration in range(10):
    var mid:=lo.lerp(hi,.5)
    if mid.y>float(height.call(mid.x,mid.z)):lo=mid
    else:hi=mid
   var at:=lo.lerp(hi,.5);at.y=float(height.call(at.x,at.z))
   if hit.is_empty() or a.distance_squared_to(at)<a.distance_squared_to(hit.position):
    var dx:=float(height.call(at.x+.25,at.z))-float(height.call(at.x-.25,at.z))
    var dz:=float(height.call(at.x,at.z+.25))-float(height.call(at.x,at.z-.25))
    return {"position":at,"normal":Vector3(-dx,.5,-dz).normalized(),"collider":null,"terrain_sample":true}
   break
  previous=point
 return hit
