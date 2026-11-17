extends RefCounted
## Deliberately abstract GAME units, not real weapon data or a firing table.
const DEFAULT_SPEED:=160.0
const DEFAULT_GRAVITY:=12.0
const DEFAULT_RANGE:=260.0
const DEFAULT_LIFETIME:=6.0
const ZERO_STEPS:=[0.0,50.0,100.0,150.0,200.0,250.0]
static func configuration(entry:Dictionary)->Dictionary:
 var values:Dictionary=entry.get("game_shell",{})
 return {"speed":float(values.get("speed",DEFAULT_SPEED)),"gravity":float(values.get("gravity",DEFAULT_GRAVITY)),"range":float(values.get("range",DEFAULT_RANGE)),"lifetime":float(values.get("lifetime",DEFAULT_LIFETIME))}
## A manual distance setting only, never a target range measurement. Low solution
## compensates the same abstract gravity as the live entity. 0 means no correction.
static func valid(config:Dictionary)->bool:
 return is_finite(float(config.speed)) and float(config.speed)>=14.0 and float(config.speed)<=180.0 and is_finite(float(config.gravity)) and float(config.gravity)>=0 and is_finite(float(config.range)) and float(config.range)>0 and is_finite(float(config.lifetime)) and float(config.lifetime)>0 and float(config.lifetime)<=36.0
static func bore_axis(sight:Vector3,setting:float,config:Dictionary)->Vector3:
 var axis:=sight.normalized()
 var horizontal:=Vector3(axis.x,0,axis.z)
 if not valid(config) or setting<=0 or float(config.gravity)<=0 or horizontal.length_squared()<.0001:return axis
 var speed:float=config.speed;var gravity:float=config.gravity
 var height:float=setting*axis.y/horizontal.length()
 var square:=speed*speed
 var discriminant:=square*square-gravity*(gravity*setting*setting+2.0*height*square)
 if discriminant<0:return axis
 # Rationalized low-angle root avoids cancellation; never select the high arc.
 var pitch:=atan2(gravity*setting*setting+2.0*height*square,setting*(square+sqrt(discriminant)))
 return horizontal.normalized()*cos(pitch)+Vector3.UP*sin(pitch)
static func sight_axis(bore:Vector3,setting:float,config:Dictionary)->Vector3:
 var axis:=bore.normalized()
 var horizontal:=Vector3(axis.x,0,axis.z)
 if not valid(config) or setting<=0 or float(config.gravity)<=0 or horizontal.length_squared()<.0001:return axis
 var time:float=setting/(float(config.speed)*horizontal.length())
 var height:float=float(config.speed)*axis.y*time-.5*float(config.gravity)*time*time
 return (horizontal.normalized()*setting+Vector3.UP*height).normalized()
