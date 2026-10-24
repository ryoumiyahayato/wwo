extends SceneTree
var failures:=0
var events:Dictionary={}
var damage_sources:Dictionary={"blue":0,"red":0}
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func tally(event:Dictionary):
 var kind:String=str(event.get("kind","unknown"))
 events[kind]=int(events.get(kind,0))+1
 if kind in ["infantry_hit","infantry_damage"]:
  var source:String=str(event.get("source_actor_id",""))
  if source.begins_with("friendly_") or source.begins_with("armor_blue_"):damage_sources.blue+=1
  elif source.begins_with("enemy_") or source.begins_with("armor_red_"):damage_sources.red+=1
func living(host)->Dictionary:
 var result:={"blue":0,"red":0}
 for actor in host.actors.values():
  if actor.get_meta("initial_dismounted",false) and actor.brain.hp>0:result[actor.brain.team_id]+=1
 return result
func _initialize():call_deferred("run")
func run():
 seed(20261017)
 var main=load("res://main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.combined_battle_enabled=true
 main.switch_mode()
 for i in 20:await physics_frame
 check(is_instance_valid(main.terrain_damage),"actual streamed terrain loaded")
 if not is_instance_valid(main.terrain_damage):quit(1);return
 check(main.ai_host.initial_infantry_counts()=={"blue":15,"red":15,"total":30},"thirty initial dismounted infantry")
 check(main.armor_host.units.size()==9,"nine AI armor plus player")
 main.ai_host.event_emitted.connect(tally)
 main.hero.global_position+=Vector3(1000,0,1000)
 var checkpoints:Dictionary={}
 for frame in 3600:
  await physics_frame
  if frame in [719,1799,3599]:
   var key:String=str((frame+1)/60)
   checkpoints[key]={"living":living(main.ai_host),"events":events.duplicate(),"armor_shots":main.armor_host.shots_fired}
   print("RECONSTRUCTED_CHECKPOINT ",key," ",JSON.stringify(checkpoints[key]))
 var grounded:=true
 var infantry_shots:=0
 var positions:Dictionary={}
 for id in main.ai_host.actors:
  var actor=main.ai_host.actors[id]
  if not actor.get_meta("initial_dismounted",false):continue
  infantry_shots+=actor.shot_sequence
  positions[id]=[actor.global_position.x,actor.global_position.y,actor.global_position.z]
  if actor.brain.hp>0 and absf(actor.global_position.y-main.terrain_damage.sample_height(actor.global_position.x,actor.global_position.z))>3:grounded=false
 check(grounded,"living troops retain physical ground while player far away")
 check(infantry_shots>0 and main.armor_host.shots_fired>0,"infantry and armor autonomously fire")
 check(damage_sources.blue>0 and damage_sources.red>0,"both teams inflict canonical damage")
 var perf:Dictionary=main.ai_host.performance_snapshot()
 check(perf.peak_perception_rays_per_frame<=64 and perf.peak_path_plans_per_frame<=1,"perception and route budgets bounded")
 var report:={"reconstructed":true,"checkpoints":checkpoints,"grounded":grounded,"positions":positions,"damage_sources":damage_sources,"events":events,"infantry_shots":infantry_shots,"armor":main.armor_host.snapshot(),"performance":perf,"streaming":main.terrain_damage.simulation_stream_snapshot(),"failures":failures}
 var file=FileAccess.open("res://reports/reconstructed_ai/far_battle.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  "))
 print("RECONSTRUCTED_FAR_FAILURES=",failures)
 main.queue_free()
 quit(1 if failures else 0)
