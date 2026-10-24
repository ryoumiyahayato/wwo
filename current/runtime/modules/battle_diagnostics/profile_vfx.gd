extends "res://scripts/combat_effects.gd"
var probe_update_usec:=0
var probe_update_calls:=0
var probe_spawn_usec:=0
var probe_spawn_calls:=0
func _process(delta:float)->void:
 var start:=Time.get_ticks_usec()
 super._process(delta)
 probe_update_usec+=Time.get_ticks_usec()-start;probe_update_calls+=1
func fire(origin:Vector3,endpoint:Vector3,kind:String="cannon",contact:bool=true,surface:String="ground",show_muzzle:bool=true,priority:bool=false,point_visibility:Callable=Callable(),profile:String="kinetic",feedback:Dictionary={})->bool:
 var start:=Time.get_ticks_usec()
 var result:=super.fire(origin,endpoint,kind,contact,surface,show_muzzle,priority,point_visibility,profile,feedback)
 probe_spawn_usec+=Time.get_ticks_usec()-start;probe_spawn_calls+=1
 return result
