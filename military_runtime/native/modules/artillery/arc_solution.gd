extends RefCounted
## Abstract game trajectories, not weapon performance or a firing table.
const GRAVITY := 12.0
const MIN_SPEED := 14.0
const MAX_SPEED := 180.0
const PREFERRED_PITCH := PI/3.0
static func solve(origin:Vector3,target:Vector3,pitch:float=PREFERRED_PITCH) -> Dictionary:
 var delta:=target-origin
 var distance:=Vector2(delta.x,delta.z).length()
 var horizontal:=Vector3(delta.x,0,delta.z).normalized()
 var denom:=2.0*pow(cos(pitch),2)*(distance*tan(pitch)-delta.y)
 var speed:=MIN_SPEED
 var valid:=distance>.1 and denom>.001
 if valid:speed=sqrt(GRAVITY*distance*distance/denom)
 valid=valid and speed>=MIN_SPEED and speed<=MAX_SPEED
 speed=clampf(speed,MIN_SPEED,MAX_SPEED)
 var direction:=horizontal*cos(pitch)+Vector3.UP*sin(pitch)
 return {"speed":speed,"direction":direction,"valid":valid}
