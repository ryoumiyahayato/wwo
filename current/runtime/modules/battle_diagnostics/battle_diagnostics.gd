extends Node
## Explicit opt-in diagnostic session. No instrumentation in ordinary battle.
const PREFIX:="res://modules/battle_diagnostics/"
const NAMES:=["idle","exterior_sweep","ads_sweep","mg_sweep"]
const LABELS:=["静止","外镜转头","开镜转头","机枪扫射"]
const OUTPUT:="user://battle_diagnostic.json"
var controls:Control
var main:Node3D
var panel:PanelContainer
var text_label:Label
var copy_button:Button
var cancel_button:Button
var running:=false
var ready_session:=false
var installed:Array=[]
var instruments:Array=[]
var saved_settings:Dictionary={}
var result:Dictionary={}
var json_text:=""
var phase_seconds:=4.0
var warmup_seconds:=4.0
var wall_limit_seconds:=60.0
var started:=0
var warmup_until:=0
var phase_started:=0
var last_frame:=0
var last_physics:=0
var phase_index:=-1
var phase_frames:Array[float]=[]
var phase_ticks:=0
var phase_max_steps:=0
var phase_cpu_start:Dictionary={}
var phase_counts_start:Dictionary={}
var bucket_started:=0
var bucket_cpu_start:Dictionary={}
var bucket_frames:=0
var bucket_ticks:=0
var bucket_wall:=0.0
var base_yaw:=0.0
var overhead_usec:=0
var overhead_calls:=0
var timer_pair_usec:=0.0
func setup(owner_controls:Control)->void:
 controls=owner_controls;main=controls.main;name="BattleDiagnostics"
 controls.add_child(self);process_priority=1000
 var entry:=Button.new();entry.text="性能诊断（重开演示）";entry.custom_minimum_size=Vector2(220,42)
 entry.add_theme_font_override('font',main.font);controls.menu.get_child(0).add_child(entry)
 entry.pressed.connect(start)
 panel=PanelContainer.new();var background:=StyleBoxFlat.new();background.bg_color=Color(.025,.035,.045,.98);background.content_margin_left=16;background.content_margin_right=16;background.content_margin_top=12;background.content_margin_bottom=12;panel.add_theme_stylebox_override("panel",background);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.offset_left=100;panel.offset_right=-100;panel.offset_top=80;panel.offset_bottom=-70;panel.z_index=100;main.hud.add_child(panel);panel.hide()
 var col:=VBoxContainer.new();col.add_theme_constant_override('separation',10);panel.add_child(col)
 text_label=Label.new();text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text_label.size_flags_vertical=Control.SIZE_EXPAND_FILL;text_label.add_theme_font_override('font',main.font);text_label.add_theme_font_size_override('font_size',16);col.add_child(text_label)
 copy_button=Button.new();copy_button.text="复制诊断 JSON";copy_button.pressed.connect(copy_result);col.add_child(copy_button)
 cancel_button=Button.new();cancel_button.text="随时取消并回车库";cancel_button.pressed.connect(cancel);col.add_child(cancel_button)
 set_process(false)
func replace_script(object:Object,path:String)->void:
 installed.append({'reference':weakref(object),'script':object.get_script()})
 swap_script(object,load(path))
func swap_script(object:Object,script:Script)->void:
 var saved:Dictionary={}
 for property in object.get_property_list():
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:saved[str(property.name)]=object.get(str(property.name))
 object.set_script(script)
 for property in object.get_property_list():
  var key:=str(property.name)
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and saved.has(key):object.set(key,saved[key])
func instrument(object:Object,kind:String,fields:Dictionary)->void:
 replace_script(object,PREFIX+'profile_'+kind+'.gd')
 instruments.append({'reference':weakref(object),'fields':fields})
func counters()->Dictionary:
 var values:Dictionary={}
 for entry in instruments:
  var object=entry.reference.get_ref()
  if not is_instance_valid(object):continue
  for key in entry.fields:
   var fields:Array=entry.fields[key]
   var current:Array=values.get(key,[0,0])
   current[0]+=int(object.get(fields[0]));current[1]+=int(object.get(fields[1]));values[key]=current
 return values
func difference(after:Dictionary,before:Dictionary)->Dictionary:
 var delta:Dictionary={}
 for key in after:
  var old:Array=before.get(key,[0,0]);delta[key]=[after[key][0]-old[0],after[key][1]-old[1]]
 return delta
func counts()->Dictionary:
 var d:={'infantry_alive':0,'infantry_collidable':0,'infantry_processing':0,'armor_alive':0,'player_crew_alive':0}
 for actor in main.ai_host.actors.values():
  if actor.embarked:continue
  d.infantry_alive+=int(actor.brain.hp>0);d.infantry_collidable+=int(actor.collision_layer!=0 and not actor.get_node('BodyCollision').disabled);d.infantry_processing+=int(actor.is_physics_processing())
 for unit in main.armor_host.units.values():d.armor_alive+=int(main.armor_host._alive(unit))
 for person in main.player_combat.crew:d.player_crew_alive+=int(person.alive)
 return d
func start()->void:
 if running:return
 saved_settings={'selected_catalog_id':main.selected_catalog_id,'last_tank_selection':main.last_tank_selection,'unit':main.unit,'terrain_index':main.terrain_index,'weather_index':main.weather_index}
 running=true;ready_session=false;phase_index=-1;installed.clear();instruments.clear();overhead_usec=0;overhead_calls=0;json_text=''
 result={'schema':1,'purpose':'DIAGNOSTIC SURVIVAL FIXTURE, not normal gameplay or GPU profiling','seed':20261017,'fixed_terrain':0,'fixed_weather':0,'fixed_vehicle':'user_heavy_mbt','max_fps':Engine.max_fps,'configured_physics_hz':Engine.physics_ticks_per_second,'configured_max_steps':Engine.max_physics_steps_per_frame,'renderer_gpu_time':'unknown','controls':'four sequential baselines, no causal ablation or equivalent replay','phases':[],'buckets':[],'debug':OS.is_debug_build(),'device':OS.get_model_name(),'engine':Engine.get_version_info().string,'scope_note':'microseconds and call counts accumulated across every callback/catch-up tick; parent/child timers overlap, never sum all groups; controller overhead excludes final cleanup; timer-pair calibration is not total profiler overhead','phase_seconds_requested':phase_seconds,'wall_limit_seconds':wall_limit_seconds}
 var begin:=Time.get_ticks_usec()
 for i in 5000:var stamp:=Time.get_ticks_usec();var ignored:=Time.get_ticks_usec()-stamp
 timer_pair_usec=(Time.get_ticks_usec()-begin)/5000.0
 started=Time.get_ticks_usec();controls.set_menu(false);controls.reset_pointers();controls.set_process_input(false)
 panel.anchor_bottom=0;panel.offset_top=10;panel.offset_bottom=175;panel.show();copy_button.hide();copy_button.disabled=true;cancel_button.text='随时取消并回车库';text_label.text='诊断演示准备中。保留全部兵力/碰撞，临时保活，不影响正常模式。最多60秒。'
 main.selected_catalog_id='user_heavy_mbt';main.last_tank_selection=0;main.terrain_index=0;main.weather_index=0
 seed(20261017);main.choose_game_mode('skirmish');set_process(true)
func install()->void:
 result.configured_physics_hz_at_entry=result.configured_physics_hz
 result.configured_physics_hz=Engine.physics_ticks_per_second
 instrument(main,'main',{'main_process_inclusive':['probe_process_usec','probe_process_calls'],'hud_child':['probe_hud_usec','probe_hud_calls'],'visibility_child':['probe_visibility_usec','probe_visibility_calls'],'player_aim_child':['probe_aim_usec','probe_aim_calls']})
 replace_script(main.ai_host.rules,PREFIX+'profile_combat.gd');replace_script(main.player_combat,PREFIX+'profile_combat.gd')
 for unit in main.armor_host.units.values():replace_script(unit.combat,PREFIX+'profile_combat.gd')
 for actor in main.ai_host.actors.values():
  instrument(actor,'actor',{'infantry_inclusive':['probe_actor_usec','probe_actor_calls'],'infantry_path_child':['probe_path_usec','probe_path_calls'],'perception_child':['probe_perception_usec','probe_perception_calls']})
  instrument(actor.brain,'brain',{'brain_decision_child':['probe_usec','probe_calls']})
  instrument(actor._route_planner,'navigation',{'route_planner_child':['probe_usec','probe_calls']})
 instrument(main.armor_host,'armor',{'armor_inclusive':['probe_physics_usec','probe_physics_calls']})
 instrument(main.vehicle_contacts,'contacts',{'vehicle_contacts_child':['probe_usec','probe_calls']})
 instrument(main.terrain_damage,'terrain',{'terrain_update':['probe_update_usec','probe_update_calls'],'terrain_height_child':['probe_sample_usec','probe_sample_calls'],'terrain_focus':['probe_focus_usec','probe_focus_calls']})
 instrument(main.combat_effects,'vfx',{'vfx_update':['probe_update_usec','probe_update_calls'],'vfx_spawn_child':['probe_spawn_usec','probe_spawn_calls']})
 instrument(controls,'controls',{'player_physics_inclusive':['probe_physics_usec','probe_physics_calls'],'exterior_camera':['probe_camera_usec','probe_camera_calls']})
 ready_session=true;warmup_until=Time.get_ticks_usec()+int(warmup_seconds*1000000);base_yaw=controls.camera_yaw
 result.start_counts=counts();result.root_pixels=[get_tree().root.size.x,get_tree().root.size.y];result.scale_3d=get_viewport().scaling_3d_scale
func _process(_delta:float)->void:
 if not running:return
 var begin:=Time.get_ticks_usec()
 tick(begin)
 overhead_usec+=Time.get_ticks_usec()-begin;overhead_calls+=1
func tick(now:int)->void:
 if now-started>=wall_limit_seconds*1000000:finish('wall_limit');return
 if main.garage or main.battle_finished:finish('unexpected_stage_end');return
 if not ready_session:
  if main.ai_started_generation==main.stage_generation and is_instance_valid(main.armor_host) and main.ai_host.actors.size()>=30:install()
  return
 if now<warmup_until:return
 if phase_index<0:begin_phase(0,now);return
 var elapsed:float=(now-phase_started)/1000000.0
 var dt:=float(now-last_frame)/1000.0
 var steps:=Engine.get_physics_frames()-last_physics
 last_frame=now;last_physics=Engine.get_physics_frames()
 if phase_frames.size()<4096:phase_frames.append(dt)
 phase_ticks+=steps;phase_max_steps=maxi(phase_max_steps,steps);bucket_frames+=1;bucket_ticks+=steps;bucket_wall+=dt/1000.0
 var target:=base_yaw+(0.0 if phase_index==0 else sin(elapsed*1.4)*.55)
 controls.look_input_radians+=absf(target-controls.camera_yaw);controls.camera_yaw=target;controls.camera_pitch=-.035;controls.drive=Vector2.ZERO
 controls.fire_held=false;controls.mg_held=phase_index==3
 if now-bucket_started>=1000000:record_bucket(now)
 if elapsed>=phase_seconds:
  record_phase(now)
  if phase_index==NAMES.size()-1:finish('complete')
  else:begin_phase(phase_index+1,now)
func begin_phase(index:int,now:int)->void:
 phase_index=index;phase_started=now;last_frame=now;last_physics=Engine.get_physics_frames();phase_frames.clear();phase_ticks=0;phase_max_steps=0
 controls.camera_yaw=base_yaw;controls.camera_pitch=-.035;controls.reset_pointers()
 var scoped:bool=index>=2
 if main.scoped!=scoped:main.toggle_scope()
 phase_cpu_start=counters();phase_counts_start=counts();bucket_started=now;bucket_cpu_start=phase_cpu_start.duplicate(true);bucket_frames=0;bucket_ticks=0;bucket_wall=0
 text_label.text='诊断演示 %d/4：%s\n每段约%.0f秒，保持30步兵+10装甲、完整碰撞和伤害计算，临时恢复生命。\nCPU分组是重叠计时，GPU/渲染线程未知。可随时取消。'%[index+1,LABELS[index],phase_seconds]
func record_bucket(now:int)->void:
 var cpu:=counters()
 if result.buckets.size()<60:result.buckets.append({'phase':NAMES[phase_index],'seconds':bucket_wall,'frames':bucket_frames,'physics_ticks':bucket_ticks,'cpu_us_calls':difference(cpu,bucket_cpu_start)})
 bucket_started=now;bucket_cpu_start=cpu;bucket_frames=0;bucket_ticks=0;bucket_wall=0
func record_phase(now:int)->void:
 if phase_frames.is_empty():return
 phase_frames.sort()
 var seconds:=float(now-phase_started)/1000000.0
 var current:=counts()
 result.phases.append({'name':NAMES[phase_index],'seconds':seconds,'frames':phase_frames.size(),'fps':phase_frames.size()/seconds,'p95_ms':phase_frames[mini(phase_frames.size()-1,ceili(phase_frames.size()*.95)-1)],'max_ms':phase_frames[-1],'physics_ticks':phase_ticks,'sim_hz':phase_ticks/seconds,'max_steps_per_render':phase_max_steps,'cpu_us_calls':difference(counters(),phase_cpu_start),'counts_start':phase_counts_start,'counts_end':current,'draws_end':int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),'primitives_end':int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),'accepted_player_cannon_shots':main.shot_audit.size(),'player_effect_sequence':main.combat_effects.player_shot_sequence})
 if bucket_frames>0:record_bucket(now)
func finish(reason:String)->void:
 if not running:return
 if ready_session and phase_index>=0 and reason!='complete':record_phase(Time.get_ticks_usec())
 running=false;set_process(false);controls.reset_pointers();controls.set_process_input(true)
 result.status=reason;result.wall_seconds=(Time.get_ticks_usec()-started)/1000000.0;result.instrumentation_controller_usec=overhead_usec;result.instrumentation_controller_calls=overhead_calls;result.timer_pair_calibration_usec=timer_pair_usec
 for i in range(installed.size()-1,-1,-1):
  var object=installed[i].reference.get_ref()
  if is_instance_valid(object):swap_script(object,installed[i].script)
 installed.clear();instruments.clear()
 for key in saved_settings:main.set(key,saved_settings[key])
 if not main.garage:main.switch_mode()
 json_text=JSON.stringify(result)
 if json_text.to_utf8_buffer().size()>65536:result.buckets=[];result.detail_truncated=true;json_text=JSON.stringify(result)
 var file:=FileAccess.open(OUTPUT,FileAccess.WRITE)
 if file!=null:file.store_string(json_text);file.close()
 var lines:='诊断结束：'+reason+'（演示模式，不是正常战斗）\n'
 for phase in result.phases:lines+='%s: %.1f FPS / p95 %.0fms / Sim %.1fHz / x%d\n'%[LABELS[NAMES.find(phase.name)],phase.fps,phase.p95_ms,phase.sim_hz,phase.max_steps_per_render]
 if not result.phases.is_empty():
  var worst:Dictionary=result.phases[0]
  for phase in result.phases:
   if phase.p95_ms>worst.p95_ms:worst=phase
  lines+='最慢段CPU ms/帧（包含子项，不能相加）：\n'
  for key in ['infantry_inclusive','armor_inclusive','terrain_update','vfx_update']:
   lines+='%s %.1f  '%[{'infantry_inclusive':'步兵','armor_inclusive':'装甲','terrain_update':'地形','vfx_update':'特效'}[key],float(worst.cpu_us_calls[key][0])/1000.0/maxi(1,worst.frames)]
  lines+='\n'
 lines+='GPU和渲染线程耗时未知。已保存应用内JSON；按复制后粘贴给助手。\n无需USB/开发者模式/存储权限。'
 panel.anchor_bottom=1;panel.offset_top=80;panel.offset_bottom=-70;copy_button.show();text_label.text=lines;copy_button.disabled=not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD);cancel_button.text='关闭结果';panel.show()
func copy_result()->void:
 if json_text.is_empty() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):return
 DisplayServer.clipboard_set(json_text);copy_button.text='已复制 JSON'
func cancel()->void:
 if running:finish('cancelled')
 else:panel.hide()
