extends RefCounted
# Exact source-triangle height lookup with a bounded XZ spatial index.
# No extrapolation outside the engineering scene's authored surface.
const CELL:=2.0
var owner_id:=0
var revision:=-1
var bins:Dictionary={}
var bounds:=AABB()
func sample(terrain:Node,x:float,z:float)->float:
 if not is_instance_valid(terrain) or not is_finite(x) or not is_finite(z):return NAN
 if terrain.has_method("sample_height"):
  return terrain.sample_height(x,z) if terrain.in_bounds(x,z) else NAN
 if not terrain.get("ready_surface"):return NAN
 var source_bounds:AABB=terrain.bounds
 if x<source_bounds.position.x or x>source_bounds.end.x or z<source_bounds.position.z or z>source_bounds.end.z:return NAN
 if owner_id!=terrain.get_instance_id() or revision!=terrain.rebuild_count:
  owner_id=terrain.get_instance_id();revision=terrain.rebuild_count;bounds=source_bounds;bins.clear()
  for surface in terrain.current_surfaces:
   var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
   for i in range(0,vertices.size(),3):
    var a:=vertices[i];var b:=vertices[i+1];var c:=vertices[i+2]
    var low:=Vector2i(floori(minf(a.x,minf(b.x,c.x))/CELL),floori(minf(a.z,minf(b.z,c.z))/CELL))
    var high:=Vector2i(floori(maxf(a.x,maxf(b.x,c.x))/CELL),floori(maxf(a.z,maxf(b.z,c.z))/CELL))
    for bx in range(low.x,high.x+1):
     for bz in range(low.y,high.y+1):
      var key:=Vector2i(bx,bz)
      if not bins.has(key):bins[key]=PackedVector3Array()
      var list:PackedVector3Array=bins[key];list.append(a);list.append(b);list.append(c);bins[key]=list
 var key:=Vector2i(floori(x/CELL),floori(z/CELL))
 if not bins.has(key):return NAN
 var vertices:PackedVector3Array=bins[key]
 for i in range(0,vertices.size(),3):
  var va:=vertices[i];var vb:=vertices[i+1];var vc:=vertices[i+2]
  var a:=Vector2(va.x,va.z);var b:=Vector2(vb.x,vb.z);var c:=Vector2(vc.x,vc.z);var p:=Vector2(x,z)
  var den:float=(b-a).cross(c-a)
  if absf(den)<.0000001:continue
  var v:float=(p-a).cross(c-a)/den;var w:float=(b-a).cross(p-a)/den;var u:=1.0-v-w
  if u>=-.00001 and v>=-.00001 and w>=-.00001:return va.y*u+vb.y*v+vc.y*w
 return NAN
