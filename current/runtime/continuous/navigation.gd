extends Control
## One viewport and one observer camera. The native camera remains the aiming
## reference, so zoom/pan never becomes a turret command or a simulation pause.
var shell: Node
var camera: Camera3D
var span := 14.0
var target_span := 14.0
var center := Vector2.ZERO
var pan_offset := Vector2.ZERO
var dragging := false
var follow := true
var last_map_mode := false
var grid := false
var font: Font
var caption := ""
var observation_enabled := true

func setup(owner_shell: Node) -> void:
	shell=owner_shell;mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font=load("res://cedar/system_font.tres")
	camera=Camera3D.new();camera.name="ContinuousObserver";shell.battle.add_child(camera)
	camera.current=true;camera.far=150000
	process_priority=1000

func set_range(value: float) -> void:
	target_span=clampf(value,14,50000)

func locate(close: bool=false) -> void:
	pan_offset=Vector2.ZERO;follow=true
	if close: target_span=14

func controlled_position() -> Vector3:
	var controller: Node=shell.battle.player_infantry_controller
	if controller.active(): return controller.actor().global_position
	return shell.battle.hero.global_position

func _input(event: InputEvent) -> void:
	if not shell.ready_battle or not observation_enabled: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP or event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			set_range(target_span*(.72 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/.72))
			get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and (event.button_index==MOUSE_BUTTON_MIDDLE or span>160 and event.button_index==MOUSE_BUTTON_LEFT and event.position.y>80):
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:shell.battle.battle_controls._pointer(-1,event.position,false)
		dragging=event.pressed;get_viewport().set_input_as_handled();return
	if event is InputEventMouseMotion and dragging:
		pan_offset+=Vector2(-event.relative.x,-event.relative.y)*span/size.y
		pan_offset=pan_offset.clamp(Vector2(-21000,-21000),Vector2(26000,26000))
		get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: set_range(5000)
			KEY_2: set_range(25000)
			KEY_3: set_range(50000)
			KEY_HOME: locate(true)
			KEY_G: grid=not grid
			KEY_P: shell.toggle_pause()
			KEY_F9: shell.capture()
			KEY_ESCAPE: locate(true)
			KEY_TAB: shell.global_requested.emit()
			_: return
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not shell.ready_battle: return
	span=exp(lerpf(log(span),log(target_span),1-exp(-delta*5)))
	if absf(log(span/target_span))<.001: span=target_span
	var position:=controlled_position()
	center=Vector2(position.x,position.z)+pan_offset
	center+=Vector2(2500,2500)*smoothstep(30000,50000,span)
	center=center.clamp(Vector2(-22500,-22500),Vector2(27500,27500))
	var blend:=smoothstep(18,140,span)
	var pitch:=lerpf(deg_to_rad(28),deg_to_rad(89.98),smoothstep(log(80),log(13000),log(span)))
	var distance:=span/(2*tan(deg_to_rad(31)))
	var focus:=Vector3(center.x,lerpf(position.y,shell.region.height(center.x,center.y),blend)+1.5,center.y)
	var desired:=focus+Vector3(0,sin(pitch)*distance,cos(pitch)*distance)
	var native_camera: Camera3D=shell.battle.camera
	var target:=Transform3D.IDENTITY.looking_at((focus-desired).normalized(),Vector3.UP)
	camera.global_position=native_camera.global_position.lerp(desired,blend)
	camera.global_basis=Basis(native_camera.global_basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(),blend))
	camera.fov=lerpf(native_camera.fov,62,blend)
	camera.near=clampf(span/5000,.08,12)
	camera.far=maxf(3200,span*4)
	camera.current=true
	var map_mode:=span>160
	if map_mode!=last_map_mode:
		last_map_mode=map_mode
	shell.battle.battle_controls.map_observing=map_mode or not observation_enabled
	shell.battle.hud.visible=span<160
	var native_visible: bool=span<8500
	if shell.battle.terrain_damage.horizon.visible!=native_visible:
		# Change both sides of the native/regional handoff in this frame.
		# The periodic streaming update must not leave a briefly missing tile.
		shell.region.update_view(center,span)
		shell.battle.terrain_damage.horizon.visible=native_visible
	if is_instance_valid(shell.battle.battle_controls.minimap): shell.battle.battle_controls.minimap.hide()
	queue_redraw()

func _draw() -> void:
	if not shell.ready_battle: return
	if span>=500:
		draw_string(font,Vector2(size.x-70,280),"N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("fff4d4"))
		var fade:=smoothstep(500,3000,span)
		for road: Dictionary in shell.region.roads:
			_draw_line(road.points,Color(.87,.75,.48,fade*.9),1.4)
		_draw_line(shell.region.river_points,Color(.42,.75,.85,fade),3)
		for i: int in shell.region.towns.size():
			if span>32000 and i%2!=0: continue
			var town: Dictionary=shell.region.towns[i]
			var p:=Vector3(town.position[0],town.position[1]+8,town.position[2])
			if camera.is_position_behind(p): continue
			var point:=camera.unproject_position(p)
			if not Rect2(Vector2.ZERO,size).has_point(point):continue
			draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),Color("e5d7ad"))
			draw_string(font,point+Vector2(9,4),town.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff4d5"))
		if span<32000:
			for source: String in shell.region.document.source_offsets:
				var offset: Array=shell.region.document.source_offsets[source]
				var anchor:=Vector3(offset[0]-1800,shell.region.height(offset[0]-1800,offset[1]-1800)+10,offset[1]-1800)
				if camera.is_position_behind(anchor): continue
				var point:=camera.unproject_position(anchor)
				if Rect2(Vector2(15,90),size-Vector2(30,140)).has_point(point):
					var label: String={"ridgevale":"Ridgevale · 驾驶","rivergate":"Rivergate","cedar":"Cedar","atlas15_01":"Atlas15 / 01"}[source]
					draw_string(font,point,label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("d5e6c9"))
		var hero: Vector3=shell.battle.hero.global_position+Vector3(0,2,0)
		var marker:=camera.unproject_position(hero)
		draw_circle(marker,8,Color("133d40"));draw_arc(marker,11,0,TAU,40,Color("79f4e6"),2)
		draw_string(font,marker+Vector2(16,-5),"原车 · 车组5人",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("d8ffef"))
		if shell.battle.player_infantry_controller.active():
			var person:=controlled_position()
			var pp:=camera.unproject_position(person+Vector3.UP)
			draw_circle(pp,5,Color("f2cf76"));draw_string(font,pp+Vector2(8,19),"林澄 / 步战",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff0ca"))
		if grid:
			for i: int in 11:
				var x: float=-22500+i*5000
				_draw_line(PackedVector3Array([Vector3(x,0,-22500),Vector3(x,0,27500)]),Color(1,1,1,.18),1)
				_draw_line(PackedVector3Array([Vector3(-22500,0,x),Vector3(27500,0,x)]),Color(1,1,1,.18),1)
	var metre:=pow(10,floor(log(maxf(1,span*.18))/log(10)))
	if metre*5<span*.25:metre*=5
	elif metre*2<span*.25:metre*=2
	var pixels:=metre/span*size.y
	var base:=Vector2(30,size.y-37)
	draw_line(base,base+Vector2(pixels,0),Color("fff4d4"),3)
	draw_line(base+Vector2(0,-5),base+Vector2(0,5),Color("fff4d4"),2)
	draw_line(base+Vector2(pixels,-5),base+Vector2(pixels,5),Color("fff4d4"),2)
	draw_string(font,base+Vector2(0,-12),("%.0f km"%(metre/1000)) if metre>=1000 else "%.0f m"%metre,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff4d4"))
	if not caption.is_empty():
		draw_style_box(_caption_style(),Rect2(Vector2(size.x*.24,size.y-97),Vector2(size.x*.52,44)))
		draw_string(font,Vector2(size.x*.26,size.y-68),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("fff4d4"))

func _draw_line(points: PackedVector3Array,color: Color,width: float) -> void:
	var projected:=PackedVector2Array()
	for p: Vector3 in points:
		if not camera.is_position_behind(p):projected.append(camera.unproject_position(p))
	if projected.size()>1:draw_polyline(projected,color,width,true)

func _caption_style() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.08,.08,.86);style.set_corner_radius_all(8);return style
