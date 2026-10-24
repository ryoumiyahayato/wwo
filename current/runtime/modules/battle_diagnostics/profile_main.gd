extends "res://scripts/main.gd"
var probe_process_usec:=0
var probe_process_calls:=0
var probe_hud_usec:=0
var probe_hud_calls:=0
var probe_visibility_usec:=0
var probe_visibility_calls:=0
var probe_aim_usec:=0
var probe_aim_calls:=0
func _process(delta:float):
 var start:=Time.get_ticks_usec()
 super._process(delta)
 probe_process_usec+=Time.get_ticks_usec()-start;probe_process_calls+=1
func refresh_hud():
 var start:=Time.get_ticks_usec()
 super.refresh_hud()
 probe_hud_usec+=Time.get_ticks_usec()-start;probe_hud_calls+=1
func update_visibility():
 var start:=Time.get_ticks_usec()
 super.update_visibility()
 probe_visibility_usec+=Time.get_ticks_usec()-start;probe_visibility_calls+=1
func advance_weapon_aim(delta:float):
 var start:=Time.get_ticks_usec()
 super.advance_weapon_aim(delta)
 probe_aim_usec+=Time.get_ticks_usec()-start;probe_aim_calls+=1
