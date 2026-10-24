extends "res://modules/ai_armor/armor_host.gd"
var probe_cannon:=0
var probe_mg:=0
func _fire(u:Dictionary,direction:Vector3,machinegun:=false)->void:
 super._fire(u,direction,machinegun)
 if machinegun:probe_mg+=1
 else:probe_cannon+=1
var probe_physics_calls:=0
var probe_physics_usec:=0
func _physics_process(delta:float)->void:
 var start:=Time.get_ticks_usec()
 super._physics_process(delta)
 probe_physics_usec+=Time.get_ticks_usec()-start
 probe_physics_calls+=1
