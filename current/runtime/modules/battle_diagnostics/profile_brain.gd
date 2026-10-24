extends "res://modules/infantry_ai/infantry_brain.gd"
var probe_usec:=0
var probe_calls:=0
func tick(delta:float,position:Vector3,observations:Array,commit_immediately:=true)->Dictionary:
 var start:=Time.get_ticks_usec()
 var result:=super.tick(delta,position,observations,commit_immediately)
 probe_usec+=Time.get_ticks_usec()-start;probe_calls+=1
 return result
