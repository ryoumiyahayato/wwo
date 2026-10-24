extends Node
## Local, lightweight diagnostics; no uploads and no per-frame file writes.
var live_history=preload("res://scripts/battle_live_history.gd").new()
var controls:Control
var label:Label
var clock:=0.0
var frame_count:=0
var sample:Dictionary={}
var frame_times:Array[float]=[]
var last_frame_usec:=0
var last_physics_frame:=0
var physics_steps_in_sample:=0
var max_steps_in_frame:=0
var multi_step_frames:=0
func setup(owner_controls:Control)->void:
 name="BattlePerformanceStatus"
 controls=owner_controls
 controls.add_child(self)
 label=Label.new()
 label.custom_minimum_size.x=220
 label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label.add_theme_font_size_override('font_size',12)
 label.add_theme_font_override('font',controls.main.font)
 label.modulate=Color(.7,.78,.8)
 controls.menu.get_child(0).add_child(label)
func _process(_delta:float)->void:
 if not is_instance_valid(controls) or not controls.active():clock=0;frame_count=0;frame_times.clear();last_frame_usec=0;physics_steps_in_sample=0;max_steps_in_frame=0;multi_step_frames=0;return
 var now:=Time.get_ticks_usec()
 live_history.observe(controls,now)
 var physics_frame:=Engine.get_physics_frames()
 if last_frame_usec==0:last_frame_usec=now;last_physics_frame=physics_frame;return
 var steps:=maxi(0,physics_frame-last_physics_frame)
 last_physics_frame=physics_frame
 physics_steps_in_sample+=steps
 max_steps_in_frame=maxi(max_steps_in_frame,steps)
 if steps>1:multi_step_frames+=1
 var seconds:=float(now-last_frame_usec)/1000000.0
 last_frame_usec=now
 clock+=seconds;frame_count+=1;frame_times.append(seconds*1000.0)
 if clock<1.0:return
 frame_times.sort()
 var p95:float=frame_times[mini(frame_times.size()-1,ceili(frame_times.size()*.95)-1)]
 var viewport:=get_viewport()
 var pixels:Vector2i=viewport.get_texture().get_size()
 var root_pixels:Vector2i=get_tree().root.size
 var scale_3d:float=viewport.scaling_3d_scale
 sample={'frame_p95_ms':p95,'sample_seconds':clock,'sample_frames':frame_count,'fps':float(frame_count)/clock,'frame_ms':clock*1000.0/frame_count,'physics_peak_previous_window_ms':Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,'draw_calls':int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),'root_pixels':[root_pixels.x,root_pixels.y],'viewport_pixels':[pixels.x,pixels.y],'window_pixels':[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y],'scale_3d':scale_3d,'device':OS.get_model_name()}
 sample.merge(memory_snapshot())
 sample['render_primitives']=int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
 sample['render_objects']=int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
 sample['physics_active_objects']=int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
 sample['physics_collision_pairs']=int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
 sample['physics_islands']=int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
 sample.engine_memory_counter_available=OS.is_debug_build()
 sample.orphan_counter_available=OS.is_debug_build()
 sample.merge({'physics_ticks_observed':physics_steps_in_sample,'physics_hz_observed':physics_steps_in_sample/clock,'max_physics_steps_per_render':max_steps_in_frame,'multi_step_render_frames':multi_step_frames,'physics_hz_configured':Engine.physics_ticks_per_second,'max_physics_steps_configured':Engine.max_physics_steps_per_frame,'debug_build':OS.is_debug_build(),'process_peak_previous_window_ms':Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
 update_label()
 clock=0;frame_count=0;frame_times.clear()
 physics_steps_in_sample=0;max_steps_in_frame=0;multi_step_frames=0

func update_label()->void:
 var root_pixels:Vector2i=Vector2i(sample.root_pixels[0],sample.root_pixels[1])
 var scale_3d:float=sample.scale_3d
 label.text='Now %.0f FPS · p95 %.1f ms\nPhysics peak(1s) %.1f ms · %d draws\nRoot %d×%d · 3D %.0f%%'%[sample.fps,sample.frame_p95_ms,sample.physics_peak_previous_window_ms,sample.draw_calls,root_pixels.x,root_pixels.y,scale_3d*100.0]
 label.text+='\n%d primitives · %d visible objects\nPhysics %d active · %d pairs'%[sample.render_primitives,sample.render_objects,sample.physics_active_objects,sample.physics_collision_pairs]
 label.text+='\nEngine %s · %d nodes · %d resources'%[('%.0f MiB'%(sample.engine_static_bytes/1048576.0)) if sample.engine_memory_counter_available else 'N/A',sample.nodes,sample.resources]
 label.text+='\nSim %.0fHz · x%d max · %s'%[sample.physics_hz_observed,sample.max_physics_steps_per_render,'Debug' if sample.debug_build else 'Release']

 var history:Dictionary=live_history.summary
 if not history.is_empty():
  label.text+='\n%s %.0fs: %.0fFPS p95 %.0fms x%d'%['Battle frozen' if live_history.frozen else 'Battle recent',minf(10,history.seconds),history.fps,history.p95_ms,history.max_steps]
  label.text+='\nInput %.0f°/s · muzzle %.0f°/s'%[history.input_degrees_per_second,history.muzzle_degrees_per_second]
  var main=controls.main
  var muzzle:Node3D=main.weapon_muzzle()
  if is_instance_valid(muzzle):
   var intended:=Vector3(-sin(controls.camera_yaw)*cos(controls.camera_pitch),sin(controls.camera_pitch),-cos(controls.camera_yaw)*cos(controls.camera_pitch))
   var gap:=rad_to_deg(intended.angle_to(-muzzle.global_basis.z.normalized()))
   label.text+=' · gap %.0f°'%gap
  if main.aim_contact_blocked:label.text+='\nBarrel blocked by contact'
  elif main.aim_limited:label.text+='\n'+main.aim_limit_reason

static func memory_snapshot() -> Dictionary:
 # Engine allocations differ from process RSS; renderer counters are estimates.
 return {"engine_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"engine_peak_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"render_buffer_estimate_bytes":int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),"render_texture_estimate_bytes":int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))}
