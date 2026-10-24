extends RefCounted
## Player tank cannon adapter: only collision during elapsed flight owns damage.
const Shell=preload("res://modules/artillery/artillery_shell.gd")
const Ballistics=preload("res://modules/vehicle_weapons/tank_ballistics.gd")
const Feedback=preload("res://scripts/hit_feedback.gd")
const AmmoProfiles=preload("res://scripts/ammo_profiles.gd")
const WeaponVFX=preload("res://scripts/weapon_vfx_profile.gd")
const MAX_ACTIVE:=8
var settled:Dictionary={}
func fire(main)->Dictionary:
 if main.garage or main.battle_finished or not main.player_can_fire():return {"ok":false,"reason":"actor_unavailable"}
 if main.get_tree().get_nodes_in_group("artillery_projectile").size()>=MAX_ACTIVE:return _deny(main,"projectile_limit")
 var muzzle:Node3D=main.weapon_muzzle()
 if not is_instance_valid(muzzle) or not muzzle.is_inside_tree():return _deny(main,"muzzle_unavailable")
 var config:=Ballistics.configuration(main.catalog_entry())
 if not Ballistics.valid(config):return _deny(main,"invalid_launch")
 var exclusions:Array[RID]=[]
 for body in main.hero.find_children("*","CollisionObject3D",true,false):exclusions.append(body.get_rid())
 var shell:=Shell.new()
 shell.gravity=config.gravity;shell.lifetime_limit=config.lifetime;shell.horizontal_limit=config.range
 main.stage.add_child(shell)
 # Validate launch before spending the one canonical chamber round. No frame
 # elapses between setup and commit; a rejected transaction destroys this node.
 if not shell.setup(muzzle.global_transform,config.speed,exclusions,Callable(main,"effect_point_visible"),Callable(main,"indirect_surface_height")):
  main.stage.remove_child(shell);shell.queue_free();return _deny(main,"invalid_launch")
 var commit:Dictionary=main.vehicle_ammo.commit_fire(main.PLAYER_VEHICLE_ID,"primary",main.vehicle_ammo.request_id(),main.primary_reload()*main.player_reload_multiplier(),main.player_can_fire(),true)
 if not bool(commit.ok):
  main.stage.remove_child(shell);shell.queue_free();return _deny(main,str(commit.reason))
 var round_index:int=["ap","he","smoke"].find(str(commit.round))
 main.shot_sequence+=1
 var shot:int=main.shot_sequence
 var generation:int=main.stage_generation
 var penetration:int=main.primary_penetration()
 var visual_weapon:Dictionary=WeaponVFX.describe(main.catalog_entry(),"cannon","primary")
 shell.add_to_group("tank_projectile")
 shell.impacted.connect(_impact.bind(main,generation,int(commit.commit),shot,round_index,penetration,visual_weapon))
 shell.expired.connect(_expired.bind(main,generation,shot))
 main.last_muzzle=muzzle.global_position
 main.shot_audit.append({"id":shot,"accepted":true,"weapon":"tank_cannon","ammo":round_index,"ammo_commit":commit.commit,"vehicle_id":main.PLAYER_VEHICLE_ID,"origin":muzzle.global_position,"direction":-muzzle.global_basis.z.normalized(),"speed":config.speed,"gravity":config.gravity,"horizontal_limit":config.range,"flight_state":"flying"})
 if main.shot_audit.size()>128:main.shot_audit.pop_front()
 main.reload_remaining=float(main.vehicle_ammo.status(main.PLAYER_VEHICLE_ID,"primary").remaining)
 _launch_feedback(main,muzzle,round_index,visual_weapon)
 main.message="主炮实体弹飞行中 · 接触后结算";main.refresh_hud()
 return {"ok":true,"shell":shell,"shot":shot,"ammo_commit":commit.commit}
func _deny(main,reason:String)->Dictionary:
 main.vehicle_fire_denied(reason)
 return {"ok":false,"reason":reason}
func _launch_feedback(main,muzzle:Node3D,round_index:int,visual_weapon:Dictionary):
 var visual:Dictionary=WeaponVFX.resolve(visual_weapon,"cannon")
 var direction:Vector3=-muzzle.global_basis.z.normalized()
 # Muzzle only. The mesh is the sole in-flight projectile, not a second tracer.
 if main.combat_effects.fire(muzzle.global_position,muzzle.global_position+direction*.5,"smoke" if round_index==2 else "cannon",false,"ground",not main.scoped,true,Callable(main,"effect_point_visible"),"muzzle_only",{"visual_weapon":visual_weapon}):
  var event:Dictionary=main.combat_effects.events.back();event.tracer=false;event.projectile.hide()
 if is_instance_valid(main.battle_controls):main.battle_controls.record_shot("smoke" if round_index==2 else "cannon",false)
 var barrel:Node3D=main.hero.find_child("Barrel",true,false)
 if is_instance_valid(barrel):
  if not barrel.has_meta("rest_position"):barrel.set_meta("rest_position",barrel.position)
  var rest:Vector3=barrel.get_meta("rest_position")
  barrel.position=rest+barrel.basis.z.normalized()*float(visual.recoil_distance)
  var tween:Tween=main.create_tween();tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS);tween.tween_property(barrel,"position",rest,float(visual.recoil_time))
func _finish_audit(main,shot:int,state:String,event:Dictionary,kind:String=""):
 for row in main.shot_audit:
  if int(row.get("id",-1))!=shot:continue
  row["flight_state"]=state;row["flight_seconds"]=event.flight_seconds;row["impact"]=event.position
  row["distance"]=row.origin.distance_to(event.position)
  if not kind.is_empty():row["hit_kind"]=kind;row["impact_direction"]=event.direction;row["impact_normal"]=event.normal
  break
func _expired(event:Dictionary,main,generation:int,shot:int):
 if not is_instance_valid(main) or generation!=main.stage_generation:return
 _finish_audit(main,shot,"expired",event)
func _impact(event:Dictionary,main,generation:int,commit:int,shot:int,round_index:int,penetration:int,visual_weapon:Dictionary={}):
 if not is_instance_valid(main) or main.garage or main.battle_finished or generation!=main.stage_generation:return
 var key:=str(generation)+":"+str(shot)
 if settled.has(key):return
 settled[key]=true
 if settled.size()>128:settled.erase(settled.keys()[0])
 event["ammo_commit"]=commit;event["feedback_id"]=shot
 var at:Vector3=event.position
 var kind:String="obstacle" if bool(event.get("terrain_sample",false)) else main.interpret_hit(event)
 _finish_audit(main,shot,"impacted",event,kind)
 main.last_muzzle=event.origin;main.last_impact=at
 if is_instance_valid(main.ai_host) and main.ai_host.has_method("suppress_near_segment"):main.ai_host.suppress_near_segment(event.origin,at,"blue","cannon")
 if round_index==2:
  main.combat.deploy_smoke();main.spawn_smoke();main.smoke_root.global_position=at
  main.message="烟幕弹实际接触后展开 · 36秒遮挡瞄准识别";main.refresh_hud();return
 var feedback:Dictionary=Feedback.contact(event,kind,shot,event.direction)
 feedback["visual_weapon"]=visual_weapon
 if bool(event.get("terrain_sample",false)):feedback.surface="ground"
 if main.combat_effects.fire(at,at,"cannon",true,str(feedback.surface),false,false,Callable(main,"effect_point_visible"),["ap","he"][round_index],feedback):
  main.combat_effects.begin_impact(main.combat_effects.events.back());main.combat_effects._apply_visibility(main.combat_effects.events.back())
 if round_index==1:
  if kind=="ai_armor":main.armor_host.handle_player_projectile(event,"cannon","he",15)
  if kind in ["ai_person","ai_fortification"] and is_instance_valid(main.ai_host):main.ai_host.handle_player_projectile(event,"cannon","he",main.part)
  elif kind=="infantry":main.combat.hit_person(main.combat.infantry,main.part)
  elif kind=="armor":main.record_hit_feedback(shot,main.combat.hit_armor(main.module_name,15,-1,"",null,{"normal":event.normal,"direction":event.direction}),true)
  if main.game_mode=="skirmish" and is_instance_valid(main.ai_host):main.ai_host.apply_player_blast(at)
  else:main.combat.high_explosive("infantry" if main.target_infantry else "armor",at.distance_to(main.target.global_position+Vector3.UP),main.blast_occluded(at))
  main.explode_terrain(at,AmmoProfiles.explosive_mass("cannon_he"));main.message="高爆弹已在实际接触点爆炸"
 else:
  main.explode_terrain(at,AmmoProfiles.explosive_mass("cannon_ap"))
  if kind=="ai_armor":main.message=main.armor_host.handle_player_projectile(event,"cannon","ap",penetration)
  elif kind in ["ai_person","ai_fortification"] and is_instance_valid(main.ai_host):main.message=main.ai_host.handle_player_projectile(event,"cannon","ap",main.part)
  elif kind=="infantry":
   main.combat.hit_person(main.combat.infantry,main.part);main.message="实体炮弹直击"+main.PART_CN[main.part]
  elif kind=="armor":
   var direct:Dictionary=main.trace_internal_crew(event)
   var index:int=-1;var direct_part:String=""
   if not direct.is_empty():index=direct.collider.get_meta("crew_index");direct_part=direct.collider.get_meta("key")
   var result:Dictionary=main.combat.hit_armor(main.module_name,penetration,index,direct_part,null,{"normal":event.normal,"direction":event.direction})
   main.record_hit_feedback(shot,result,true)
   main.message=("穿透" if result.kind in ["penetrated","external_penetrated"] else "未穿透")+" · "+main.MODULE_CN[main.module_name]+" · 厚度 "+str(main.combat.modules[main.module_name].thickness)
   if result.kind=="external_penetrated":main.message+=" · 外置履带，未进入乘员舱"
   if result.kind=="penetrated" and index>=0:main.message+=" · 弹道直击"+main.combat.crew_roles[index]+main.PART_CN[direct_part]
  elif kind=="thin_plate":main.message="主炮穿透薄板试片 · 未命中乘员舱"
  else:main.message="实体炮弹被地形或障碍截住"
 main.update_person_visuals();main.refresh_hud()
