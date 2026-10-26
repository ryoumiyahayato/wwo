extends RefCounted
## Fictional movement/pose values. One source for physical envelope, view and weapon.
## Crawl is prone + real displacement, not a separate scaled whole-body model.
const NAMES := ["stand", "crouch", "prone"]
const TRANSITION_SECONDS := 0.4
const PROFILES := {
 "stand": {"height":1.75,"length":0.54,"eye":1.1,"speed":1.0,"hip":0.9,"pitch":0.0,"weapon_y":0.0,"weapon_z":0.0,"crouch":0.0,"prone":0.0},
 "crouch": {"height":1.25,"length":1.0,"eye":0.65,"speed":0.58,"hip":0.40,"pitch":-0.28,"weapon_y":-0.50,"weapon_z":-0.04,"crouch":1.0,"prone":0.0},
 "prone": {"height":0.61,"length":1.85,"eye":0.20,"speed":0.23,"hip":0.14,"pitch":-1.57,"weapon_y":-0.96,"weapon_z":-0.24,"crouch":0.0,"prone":1.0}
}
static func profile(name: String) -> Dictionary:
 return PROFILES.get(name,PROFILES.stand).duplicate()
static func blend(from: Dictionary, to: Dictionary, amount: float) -> Dictionary:
 var result: Dictionary = {}
 var t := clampf(amount,0.0,1.0)
 # Smooth endpoint velocity, with no duration-dependent overshoot.
 t = t*t*(3.0-2.0*t)
 for key in PROFILES.stand: result[key] = lerpf(float(from[key]),float(to[key]),t)
 # Analytic two-link sole constraint from this rig's authored .40/.39 m legs.
 # Important during transitions: linear hip lowering + angular knees tunnels feet.
 var c := float(result.crouch)
 var p := float(result.prone)
 var pitch := float(result.pitch)
 var thigh := -1.4*c
 var shin := 2.4*c+0.18*p
 var foot := -c
 var angle := pitch-thigh-shin-foot
 var sole := minf(-0.07*cos(angle),0.015*cos(angle))+minf(-0.067*sin(angle),0.151*sin(angle))
 var required_hip := 0.04*cos(pitch)+0.40*cos(pitch-thigh)+0.39*cos(pitch-thigh-shin)-sole+0.01
 var raise := maxf(0.0,required_hip-float(result.hip))*(1.0-p)
 result.hip += raise
 result.height += raise
 result.eye += raise
 result.weapon_y += raise
 return result
static func envelope(pose: Dictionary) -> Vector3:
 return Vector3(0.54,float(pose.height),float(pose.length))
