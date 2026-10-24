extends "res://scripts/mobile_battle.gd"
var probe_physics_usec:=0
var probe_physics_calls:=0
var probe_camera_usec:=0
var probe_camera_calls:=0
func _physics_process(delta:float)->void:
 var start:=Time.get_ticks_usec()
 super._physics_process(delta)
 probe_physics_usec+=Time.get_ticks_usec()-start;probe_physics_calls+=1
func _camera_update(delta:float,view_direction:Vector3)->void:
 var start:=Time.get_ticks_usec()
 super._camera_update(delta,view_direction)
 probe_camera_usec+=Time.get_ticks_usec()-start;probe_camera_calls+=1
