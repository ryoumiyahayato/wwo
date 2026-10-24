extends RefCounted
const Shell=preload("res://modules/artillery/artillery_shell.gd")
const Arc=preload("res://modules/artillery/arc_solution.gd")
const Feedback=preload("res://scripts/hit_feedback.gd")
const WeaponVFX=preload("res://scripts/weapon_vfx_profile.gd")
const MAX_ACTIVE:=8
var settled:Dictionary={}
func fire(main) -> void:
 if main.garage or main.battle_finished or not main.player_can_fire():return
 if main.get_tree().get_nodes_in_group("artillery_projectile").size()>=MAX_ACTIVE:return
 var muzzle:Node3D=main.weapon_muzzle()
 if not is_instance_valid(muzzle) or not muzzle.is_inside_tree():main.vehicle_fire_denied("muzzle_unavailable");return
 if not muzzle.global_position.is_finite() or not is_finite(main.artillery_launch_speed) or main.artillery_launch_speed<Arc.MIN_SPEED or main.artillery_launch_speed>Arc.MAX_SPEED:return
 var commit:Dictionary=main.vehicle_ammo.commit_fire(main.PLAYER_VEHICLE_ID,"primary",main.vehicle_ammo.request_id(),main.primary_reload()*main.player_reload_multiplier(),main.player_can_fire(),true)
 if not bool(commit.ok):main.vehicle_fire_denied(str(commit.reason));return
 var exclusions:Array[RID]=[]
 for body in main.hero.find_children("*","CollisionObject3D",true,false):exclusions.append(body.get_rid())
 var shell:=Shell.new();main.stage.add_child(shell)
 shell.setup(muzzle.global_transform,main.artillery_launch_speed,exclusions,Callable(main,"effect_point_visible"),Callable(main,"indirect_surface_height"))
 main.shot_sequence+=1
 var shot:int=main.shot_sequence
 var generation:int=main.stage_generation
 var visual_weapon:Dictionary=WeaponVFX.describe(main.catalog_entry(),"cannon","primary")
 var visual:Dictionary=WeaponVFX.resolve(visual_weapon,"cannon")
 shell.impacted.connect(_impact.bind(main,generation,int(commit.commit),shot,visual_weapon))
 shell.expired.connect(_expired.bind(main,generation,shot))
 main.shot_audit.append({"id":shot,"accepted":true,"weapon":"artillery","ammo":1,"ammo_commit":commit.commit,"vehicle_id":main.PLAYER_VEHICLE_ID,"origin":muzzle.global_position,"direction":-muzzle.global_basis.z.normalized(),"flight_state":"flying"})
 if main.shot_audit.size()>128:main.shot_audit.pop_front()
 main.reload_remaining=float(main.vehicle_ammo.status(main.PLAYER_VEHICLE_ID,"primary").remaining)
 main.spawn_combat_vfx("muzzle_pulse",muzzle.global_position,-muzzle.global_basis.z,visual_weapon)
 if is_instance_valid(main.battle_controls):main.battle_controls.record_shot("cannon",false)
 var barrel:Node3D=main.hero.find_child("Barrel",true,false)
 if is_instance_valid(barrel):
  if not barrel.has_meta("rest_position"):barrel.set_meta("rest_position",barrel.position)
  var rest:Vector3=barrel.get_meta("rest_position")
  barrel.position=rest+barrel.basis.z.normalized()*float(visual.recoil_distance)
  var tween:Tween=main.create_tween();tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS);tween.tween_property(barrel,"position",rest,float(visual.recoil_time))
 main.artillery_aim.status="装填"
 main.message="曲射弹飞行中 · 落点由实际碰撞决定";main.refresh_hud()
func _expired(event:Dictionary,main,generation:int,shot:int):
 if not is_instance_valid(main) or generation!=main.stage_generation:return
 for row in main.shot_audit:
  if int(row.get("id",-1))==shot:row["flight_state"]="expired";row["flight_seconds"]=event.flight_seconds;break
func _impact(event:Dictionary,main,generation:int,commit:int,shot:int,visual_weapon:Dictionary={}):
 if not is_instance_valid(main) or main.garage or main.battle_finished or generation!=main.stage_generation:return
 var key:=str(generation)+":"+str(shot)
 if settled.has(key):return
 settled[key]=true
 if settled.size()>128:settled.erase(settled.keys()[0])
 event["ammo_commit"]=commit;event["feedback_id"]=shot
 var at:Vector3=event.position
 var kind:String="obstacle" if bool(event.get("terrain_sample",false)) else main.interpret_hit(event)
 for row in main.shot_audit:
  if int(row.get("id",-1))==shot:row["impact"]=at;row["hit_kind"]=kind;row["flight_state"]="impacted";row["flight_seconds"]=event.flight_seconds;break
 var feedback:Dictionary=Feedback.contact(event,kind,shot,event.direction)
 feedback["visual_weapon"]=visual_weapon
 if bool(event.get("terrain_sample",false)):feedback.surface="ground"
 # Impact-only pool event. Never draw a straight launch-to-target tracer for an arc.
 if main.combat_effects.fire(at,at,"rocket",true,str(feedback.surface),false,false,Callable(main,"effect_point_visible"),"he",feedback):
  main.combat_effects.begin_impact(main.combat_effects.events.back())
  main.combat_effects._apply_visibility(main.combat_effects.events.back())
 if kind=="ai_armor":main.armor_host.handle_player_projectile(event,"cannon","he",15)
 if kind in ["ai_person","ai_fortification"] and is_instance_valid(main.ai_host):main.ai_host.handle_player_projectile(event,"cannon","he",main.part)
 elif kind=="infantry":main.combat.hit_person(main.combat.infantry,main.part)
 elif kind=="armor":main.record_hit_feedback(shot,main.combat.hit_armor(main.module_name,15,-1,"",null,{"normal":event.normal,"direction":event.direction}),true)
 if main.game_mode=="skirmish" and is_instance_valid(main.ai_host):main.ai_host.apply_player_blast(at)
 else:main.combat.high_explosive("infantry" if main.target_infantry else "armor",at.distance_to(main.target.global_position+Vector3.UP),main.blast_occluded(at))
 main.explode_terrain(at,preload("res://scripts/ammo_profiles.gd").explosive_mass("cannon_he"))
 main.message="曲射弹已在实际落点爆炸" if main.effect_point_visible(at) else "曲射弹已落地，远处结果无法确认"
 main.update_person_visuals();main.refresh_hud()
