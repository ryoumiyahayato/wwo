extends RefCounted
## Bounded 10-second living-battle evidence. No files, uploads or gameplay changes.
const CAPACITY:=4096
var rows:Array[PackedFloat64Array]=[]
var cursor:=0
var generation:=-1
var frozen:=false
var summary:Dictionary={}
var last_usec:=0
var last_physics:=0
var last_input:=0.0
var last_direction:=Vector3.ZERO
var muzzle:Node3D
var next_summary_usec:=0
func observe(controls:Control,now:int)->void:
 var main=controls.main
 if generation!=main.stage_generation:
  generation=main.stage_generation;rows.clear();cursor=0;frozen=false;summary={};last_usec=0;muzzle=null;next_summary_usec=0
 if main.battle_finished:
  if not frozen:
   summarize(now);frozen=true
  return
 if not controls.initialized or main.ai_started_generation!=generation:return
 if not is_instance_valid(muzzle):muzzle=main.weapon_muzzle()
 var direction:Vector3=-muzzle.global_basis.z.normalized() if is_instance_valid(muzzle) else Vector3.ZERO
 var input_total:float=controls.look_input_radians
 var physics:=Engine.get_physics_frames()
 if last_usec>0:
  var moved:=last_direction.angle_to(direction) if last_direction.length_squared()>.5 and direction.length_squared()>.5 else 0.0
  var row:=PackedFloat64Array([now/1000000.0,(now-last_usec)/1000.0,maxi(0,physics-last_physics),maxf(0,input_total-last_input),moved])
  if rows.size()<CAPACITY:rows.append(row)
  else:rows[cursor]=row;cursor=(cursor+1)%CAPACITY
 last_usec=now;last_physics=physics;last_input=input_total;last_direction=direction
 if now>=next_summary_usec:
  summarize(now);next_summary_usec=now+1000000
func summarize(now:int)->void:
 var cutoff:=now/1000000.0-10.0
 var times:Array[float]=[]
 var wall:=0.0;var ticks:=0;var max_steps:=0;var input_angle:=0.0;var muzzle_angle:=0.0
 for row in rows:
  if row[0]<cutoff:continue
  times.append(row[1]);wall+=row[1]/1000.0;ticks+=int(row[2]);max_steps=maxi(max_steps,int(row[2]));input_angle+=row[3];muzzle_angle+=row[4]
 if times.is_empty():return
 times.sort()
 summary={'seconds':wall,'frames':times.size(),'fps':times.size()/wall,'p95_ms':times[mini(times.size()-1,ceili(times.size()*.95)-1)],'simulation_hz':ticks/wall,'max_steps':max_steps,'input_degrees_per_second':rad_to_deg(input_angle)/wall,'muzzle_degrees_per_second':rad_to_deg(muzzle_angle)/wall}
