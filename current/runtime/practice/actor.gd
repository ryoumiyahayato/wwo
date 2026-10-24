extends "res://modules/infantry_ai/infantry_actor.gd"
## The existing infantry body and muzzle ray; no independent person or ammo pool.
var movement:=Vector2.ZERO
var aim_point:=Vector3(0,1.2,-22)
var trigger_pending:=false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(host) or host.busy:return
	var input_axis:=movement
	input_axis+=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	input_axis=input_axis.limit_length(1.0)
	velocity.x=input_axis.x*2.0;velocity.z=input_axis.y*2.0
	velocity.y= -0.1 if is_on_floor() else velocity.y-18.0*delta
	move_and_slide()
	position.x=clampf(position.x,-7.5,7.5);position.z=clampf(position.z,-4.5,11.5)
	aim_visible_weapon(aim_point)
	if trigger_pending:
		trigger_pending=false
		host.fire_from_input()

func _sync_person_state() -> void:
	pass # This body projects the installed formal person. No training person registry.
