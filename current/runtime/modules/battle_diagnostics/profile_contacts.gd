extends "res://scripts/vehicle_contact_resolver.gd"
## DIAGNOSTIC SESSION ONLY: preserve every query, avoid counting nested capture twice.
var probe_usec:=0
var probe_calls:=0
var probe_depth:=0
func capture_pose(vehicle:Node3D)->Dictionary:
 var start:=Time.get_ticks_usec()
 var result:=super.capture_pose(vehicle)
 if probe_depth==0:probe_usec+=Time.get_ticks_usec()-start
 return result
func resolve_pose(vehicle:Node3D,previous:Dictionary,speed:float,delta:float)->Dictionary:
 var start:=Time.get_ticks_usec()
 probe_depth+=1
 var result:=super.resolve_pose(vehicle,previous,speed,delta)
 probe_depth-=1
 probe_usec+=Time.get_ticks_usec()-start;probe_calls+=1
 return result
