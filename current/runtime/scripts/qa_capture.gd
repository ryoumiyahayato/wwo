extends Node
var main:Node
var tick:=0.0
var index:=0
var capture_path:=""
func _ready():
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_window().size=Vector2i(1280,575)
	get_window().position=Vector2i(40,180)
	capture_path="res://review/gui_%d"%Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_path))
	print("GUI_CAPTURE_PATH=",capture_path)
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().size=Vector2i(1280,575)
func _process(delta:float):
	tick+=delta
	if tick<2.0:return
	tick=0;index+=1
	await RenderingServer.frame_post_draw
	if index<=16:get_viewport().get_texture().get_image().save_png(capture_path+"/frame_%04d.png"%index)
	var file:=FileAccess.open(capture_path+"/live_state.jsonl",FileAccess.READ_WRITE)
	if file==null:file=FileAccess.open(capture_path+"/live_state.jsonl",FileAccess.WRITE)
	file.seek_end()
	var c=main.battle_controls
	var actors:Dictionary={}
	if is_instance_valid(main.ai_host):
		for id in main.ai_host.actors:
			var a=main.ai_host.actors[id]
			if is_instance_valid(a):actors[id]={"position":str(a.position),"hp":a.brain.hp,"state":a.brain.state,"weapon":a.weapon,"weapon_id":a.weapon_id,"shots":a.shot_sequence,"embarked":a.embarked}
	file.store_line(JSON.stringify({"time_msec":Time.get_ticks_msec(),"capture_interval":2.0,"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"engine_fps":Engine.get_frames_per_second(),"actors":actors,"terrain_job":main.construction_host.terrain_job.duplicate(),"frame":index,"garage":main.garage,"position":str(main.hero.position),"yaw":main.hero.rotation.y,"speed":c.speed,"blocked":c.drive_blocked,"travel":c.travel,"camera_yaw":c.camera_yaw,"scope":main.scoped,"muzzle":str(main.last_muzzle),"impact":str(main.last_impact),"fire_held":c.fire_held,"can_drive":main.crew_host.can_drive()}))
