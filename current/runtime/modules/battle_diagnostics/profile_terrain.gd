extends "res://modules/terrain_damage/streamed_battle_terrain.gd"
var probe_update_usec:=0
var probe_update_calls:=0
var probe_sample_usec:=0
var probe_sample_calls:=0
var probe_focus_usec:=0
var probe_focus_calls:=0
func _process(delta:float)->void:
 var start:=Time.get_ticks_usec()
 super._process(delta)
 probe_update_usec+=Time.get_ticks_usec()-start;probe_update_calls+=1
func sample_height(x:float,z:float)->float:
 var start:=Time.get_ticks_usec()
 var value:=super.sample_height(x,z)
 probe_sample_usec+=Time.get_ticks_usec()-start;probe_sample_calls+=1
 return value
func set_focus(position:Vector3)->void:
 var start:=Time.get_ticks_usec()
 super.set_focus(position)
 probe_focus_usec+=Time.get_ticks_usec()-start;probe_focus_calls+=1
func set_simulation_anchors(positions:Array)->void:
 var start:=Time.get_ticks_usec()
 super.set_simulation_anchors(positions)
 probe_focus_usec+=Time.get_ticks_usec()-start;probe_focus_calls+=1
