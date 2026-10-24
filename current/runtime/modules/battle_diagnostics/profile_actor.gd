extends "res://modules/infantry_ai/infantry_actor.gd"
## DIAGNOSTIC SESSION ONLY: direct damage/crush survival, without removing real colliders.
func receive_damage(amount:float)->void:
 var person:=person_state.duplicate(true)
 var hp:float=brain.hp
 var state:String=brain.state
 var timer:float=brain.state_time
 var order:Dictionary=brain.order.duplicate(true)
 var motion:=velocity
 super.receive_damage(amount)
 person_state.clear();person_state.merge(person,true)
 brain.hp=hp;brain.state=state;brain.state_time=timer
 brain.order.clear();brain.order.merge(order,true);velocity=motion
func receive_vehicle_contact(direction:Vector3,speed:float,crush:bool)->bool:
 var layer:=collision_layer
 var mask:=collision_mask
 var processing:=is_physics_processing()
 var motion:=velocity
 var result:=super.receive_vehicle_contact(direction,speed,crush)
 collision_layer=layer;collision_mask=mask;set_physics_process(processing)
 if crush:velocity=motion
 return result

var probe_actor_calls:=0
var probe_perception_usec:=0
var probe_perception_calls:=0
var probe_actor_usec:=0
var probe_path_usec:=0
var probe_path_calls:=0
func _physics_process(delta:float)->void:
 var start:=Time.get_ticks_usec()
 super._physics_process(delta)
 probe_actor_usec+=Time.get_ticks_usec()-start
 probe_actor_calls+=1
func _path_blocked(direction:Vector3,probe_distance:=0.65)->bool:
 var start:=Time.get_ticks_usec()
 var result:=super._path_blocked(direction,probe_distance)
 probe_path_usec+=Time.get_ticks_usec()-start
 probe_path_calls+=1
 return result

func _scheduled_observations()->Array:
 var start:=Time.get_ticks_usec()
 var result:=super._scheduled_observations()
 probe_perception_usec+=Time.get_ticks_usec()-start;probe_perception_calls+=1
 return result
