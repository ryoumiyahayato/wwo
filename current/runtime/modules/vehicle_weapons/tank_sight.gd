extends RefCounted
## Manual gun sight. It owns no target identity, camera ray, launch or damage.
const Ballistics=preload("res://modules/vehicle_weapons/tank_ballistics.gd")
var distance:=0.0
func active(main)->bool:
 return not main.garage and main.unit<2 and main.primary_weapon()=="cannon" and not main.artillery_mode() and not is_instance_valid(main.weapon_override) and not (is_instance_valid(main.player_infantry_controller) and main.player_infantry_controller.active())
func reset():distance=0.0
func set_distance(main,value:float)->bool:
 if not active(main) or not is_finite(value):return false
 var muzzle:Node3D=main.weapon_muzzle()
 var previous_view:Vector3=view_axis(main,-muzzle.global_basis.z) if is_instance_valid(muzzle) else Vector3.FORWARD
 distance=clampf(value,0.0,Ballistics.ZERO_STEPS.back())
 # Changing the setting moves the real barrel relative to the prior sight line,
 # rather than merely shifting the sight or feeding the correction back each tick.
 if is_instance_valid(muzzle):
  for refinement in range(3):main.aim_weapon(muzzle.global_position+previous_view*260.0,true)
  if is_instance_valid(main.battle_controls):
   var actual_view:=view_axis(main,-muzzle.global_basis.z)
   main.battle_controls.camera_yaw=atan2(-actual_view.x,-actual_view.z)
   main.battle_controls.camera_pitch=asin(clampf(actual_view.y,-1,1))
 main.message="标尺 %.0fm · 人工距离，下坠补偿（游戏参数）"%distance;main.refresh_hud()
 return true
func cycle(main):
 var index:=Ballistics.ZERO_STEPS.find(distance)
 set_distance(main,Ballistics.ZERO_STEPS[(index+1)%Ballistics.ZERO_STEPS.size()])
func aim_point(main,point:Vector3)->Vector3:
 if not active(main) or distance<=0:return point
 var muzzle:Node3D=main.weapon_muzzle()
 if not is_instance_valid(muzzle):return point
 var axis:Vector3=point-muzzle.global_position
 if axis.length_squared()<.001:return point
 return muzzle.global_position+Ballistics.bore_axis(axis,distance,Ballistics.configuration(main.catalog_entry()))*axis.length()
func view_axis(main,bore:Vector3)->Vector3:
 return Ballistics.sight_axis(bore,distance,Ballistics.configuration(main.catalog_entry())) if active(main) else bore.normalized()
func view_pose(main,pose:Transform3D)->Transform3D:
 if not active(main) or distance<=0:return pose
 var axis:=view_axis(main,-pose.basis.z)
 return Transform3D(Basis.looking_at(axis,Vector3.RIGHT if absf(axis.dot(Vector3.UP))>.99 else Vector3.UP),pose.origin)
