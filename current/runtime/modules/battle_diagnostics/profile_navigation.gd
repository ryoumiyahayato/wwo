extends "res://modules/infantry_ai/infantry_navigation.gd"
var probe_usec:=0
var probe_calls:=0
func plan(body:CharacterBody3D,destination:Vector3)->Array[Vector3]:
 var start:=Time.get_ticks_usec()
 var result:=super.plan(body,destination)
 probe_usec+=Time.get_ticks_usec()-start;probe_calls+=1
 return result
