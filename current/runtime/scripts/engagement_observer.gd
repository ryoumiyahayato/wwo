extends Node
## Opt-in, local passive QA evidence. Never drives, aims, fires, damages or stops the world.
var main:Node
var interval:=0.0
var started:=0
var previous_sample_cpu_usec:=0
var file:FileAccess
func _ready():
 started=Time.get_ticks_msec()
 var folder:="res://reports/camera_flow_052/normal_%d"%Time.get_unix_time_from_system()
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 file=FileAccess.open(folder+"/passive.jsonl",FileAccess.WRITE)
 print("ENGAGEMENT_OBSERVER_PATH=",folder)
func _process(delta:float):
 interval+=delta
 if interval<2.0 or file==null:return
 interval=0.0
 var sample_started:=Time.get_ticks_usec()
 var row:Dictionary={"wall_ms":Time.get_ticks_msec()-started,"previous_sample_cpu_usec":previous_sample_cpu_usec,"garage":main.garage,"battle_finished":main.battle_finished,"result":main.battle_result,"fps":Engine.get_frames_per_second(),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"normal_unmodified_battle":true}
 var budget=main.get_node_or_null("MobileRenderBudget")
 if budget!=null:row["render_budget"]=budget.snapshot()
 if is_instance_valid(main.hero):row["player_position"]=str(main.hero.global_position)
 if is_instance_valid(main.battle_controls):
  row["travel"]=main.battle_controls.travel
  row["speed"]=main.battle_controls.speed
  row["scope"]=main.scoped
  row["camera_yaw"]=main.battle_controls.camera_yaw
  row["hull_yaw"]=main.hero.rotation.y
  row["camera_position"]=str(main.camera.global_position)
  row["camera_obstructed"]=main.battle_controls.camera_obstructed
  row["aim_status"]=main.battle_controls.aim_status_text()
  var perf=main.battle_controls.get_node_or_null("BattlePerformanceStatus")
  if perf!=null:row["performance"]=perf.sample.duplicate(true)
  row["hud_events"]=main.battle_controls.hud_events.lines(Time.get_ticks_msec())
 if is_instance_valid(main.crew_host):
  row["commander_id"]=main.crew_host.commander_person_id()
  row["can_drive"]=main.crew_host.can_drive()
 row["player_crew"]=main.player_combat.crew.duplicate(true)
 if is_instance_valid(main.armor_host):
  row["armor"]=main.armor_host.snapshot()
  row["recent_shots"]=main.armor_host.recent_shots()
 if is_instance_valid(main.ai_host):
  row["initial_infantry"]=main.ai_host.initial_infantry_counts()
  var actors:Dictionary={}
  for id in main.ai_host.actors:
   var actor=main.ai_host.actors[id]
   if is_instance_valid(actor):actors[id]={"state":actor.brain.state,"hp":actor.brain.hp,"shots":actor.shot_sequence,"embarked":actor.embarked}
  row["infantry"]=actors
 file.store_line(JSON.stringify(row))
 file.flush()
 previous_sample_cpu_usec=Time.get_ticks_usec()-sample_started
