extends Node3D
## Visual drivetrain, all coordinates in the imported model frame (+Y up, -Z forward).
## No rigid bodies or per-link physics. One MultiMesh per track, shared wheel meshes.
var wheels:Array[Dictionary]=[]
var belts:Array[Dictionary]=[]
var is_car:=false
var wheel_cache:Dictionary={}
var wheel_batches:Array=[]
@export var wheel_batching_enabled:=true
@export var optimization_enabled:=true
@export var force_full_rate:=false
# Set to the player for gameplay distance; standalone previews use their camera.
var lod_focus:Node3D
const FULL_RATE_DISTANCE:=30.0
const MEDIUM_RATE_DISTANCE:=70.0
const MEDIUM_INTERVAL:=1.0/20.0
const FAR_INTERVAL:=1.0/10.0
var _visual_elapsed:=0.0
var _pending_left:=0.0
var _pending_right:=0.0
var _applied_steering:=0.0
var _was_moving:=false
var _last_interval:=0.0
var visual_updates:=0
var belt_transform_writes:=0
var wheel_transform_writes:=0
var steering_transform_writes:=0
var skipped_visual_ticks:=0
var idle_visual_ticks:=0

static func install(model:Node3D, vehicle_id:String="") -> Node3D:
	if model.has_node("RunningGear"):return model.get_node("RunningGear")
	var gear=load("res://scripts/running_gear.gd").new()
	gear.name="RunningGear"
	model.add_child(gear)
	gear.build(vehicle_id)
	return gear

func build(vehicle_id:String):
	is_car=vehicle_id.begins_with("armored_car_") or str(get_parent().name).begins_with("armored_car_")
	var floor_y:=0.0
	var half_width:=1.34
	var half_length:=2.45
	if is_car:
		floor_y=.035
		for side in [-1,1]:
			for z in [-2.45,-1.05,.85,2.25]:
				add_wheel(Vector3(side*1.34,.595,z),.56,.40,side,z<0,true)
	else:
		var old_left=get_parent().find_child("TracksLeft",true,false)
		var old_right=get_parent().find_child("TracksRight",true,false)
		if not old_left is MeshInstance3D or not old_right is MeshInstance3D:
			return
		for old in [old_left,old_right]:
			var bounds:AABB=old.transform*old.get_aabb()
			# Existing track component bounds are authoritative; no hull overlays.
			old.visible=false
			var center:=bounds.get_center()
			var side: int=-1 if center.x<0 else 1
			var radius:=bounds.size.y*.5-.035
			var straight:=maxf(.2,bounds.size.z-2.0*radius)
			var width:=bounds.size.x
			var count:int={"user_heavy_mbt":7,"kestrel_scout":5,"t90m":6,"king_tiger":9,"leopard2":7,"tiger1":8,"t35":8,"assault152":6,"ft17":5}.get(vehicle_id,6)
			for i in range(count):
				var z:=center.z-straight*.5+straight*float(i)/float(count-1)
				add_wheel(Vector3(center.x,center.y,z),radius*.91,width*.80,side,false,false)
			add_belt(center,radius,straight,width,side)
			floor_y=bounds.position.y
			half_width=absf(center.x)
			half_length=straight*.5
	get_parent().set_meta("ground_contact_y",floor_y)
	get_parent().set_meta("contact_half_width",half_width)
	get_parent().set_meta("contact_half_length",half_length)
	for x in [-half_width,half_width]:
		for z in [-half_length,half_length]:
			var marker:=Marker3D.new();marker.name="GroundContact_%s_%s"%["L" if x<0 else "R","F" if z<0 else "B"]
			marker.position=Vector3(x,floor_y,z);add_child(marker)

	_build_wheel_batches()

func add_wheel(pos:Vector3,radius:float,width:float,side:int,steering:bool,car:bool):
	var steer:=Node3D.new();steer.position=pos;add_child(steer)
	var rotor:=MeshInstance3D.new();rotor.name="WheelRotor";steer.add_child(rotor)
	var key:="%.3f_%.3f_%s"%[radius,width,car]
	if not wheel_cache.has(key):wheel_cache[key]=wheel_mesh(radius,width,car)
	rotor.mesh=wheel_cache[key]
	wheels.append({"node":rotor,"steer":steer,"radius":radius,"side":side,"steering":steering})

## Exact original wheel mesh/material; only the number of render submissions changes.
## Logical rotor/steering nodes remain authoritative for animation and regression.
func _build_wheel_batches()->void:
	var groups:Dictionary={}
	for wheel in wheels:
		var key:int=wheel.node.mesh.get_instance_id()
		if not groups.has(key):groups[key]=[]
		groups[key].append(wheel)
	for group in groups.values():
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=group[0].node.mesh;multi.instance_count=group.size()
		# Conservative rotation-invariant bounds include every wheel and steering
		# angle, so a center outside the frustum never hides a visible edge wheel.
		var wheel_bounds:AABB=multi.mesh.get_aabb()
		var radius:float=wheel_bounds.position.abs().max(wheel_bounds.end.abs()).length()
		var bounds:AABB=AABB(group[0].steer.position-Vector3.ONE*radius,Vector3.ONE*radius*2.0)
		for wheel in group:bounds=bounds.merge(AABB(wheel.steer.position-Vector3.ONE*radius,Vector3.ONE*radius*2.0))
		multi.custom_aabb=bounds
		var instance:=MultiMeshInstance3D.new();instance.name="WheelBatch%d"%wheel_batches.size()
		instance.multimesh=multi;add_child(instance)
		wheel_batches.append({"mesh":multi,"instance":instance,"wheels":group})
	_sync_wheel_batches()
	set_wheel_batching(wheel_batching_enabled)

func set_wheel_batching(enabled:bool)->void:
	wheel_batching_enabled=enabled
	for wheel in wheels:wheel.node.visible=not enabled
	for batch in wheel_batches:batch.instance.visible=enabled
	if enabled:_sync_wheel_batches()

func _sync_wheel_batches()->void:
	if not wheel_batching_enabled:return
	for batch in wheel_batches:
		for i in batch.wheels.size():
			var wheel:Dictionary=batch.wheels[i]
			batch.mesh.set_instance_transform(i,wheel.steer.transform*wheel.node.transform)

func wheel_mesh(r:float,w:float,car:bool) -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rubber:=Color("20262a");var rim:=Color("889080");var metal:=Color("b5b9ad")
	# Beveled tire shoulder, recessed rim, raised hub; hard silhouette with smooth normals.
	lathe(st,[Vector2(-w*.5,r*.76),Vector2(-w*.42,r*.95),Vector2(-w*.28,r),Vector2(w*.28,r),Vector2(w*.42,r*.95),Vector2(w*.5,r*.76)],rubber)
	for side in [-1,1]:
		var face_profile:=[Vector2(side*w*.5,r*.76),Vector2(side*w*.53,r*.66),Vector2(side*w*.53,r*.28),Vector2(side*w*.62,r*.23),Vector2(side*w*.62,0)]
		if side<0:face_profile.reverse()
		lathe(st,face_profile,rim)
		for i in range(8):
			var a:=TAU*i/8.0
			var p:=Vector3(side*w*.535,sin(a)*r*.49,cos(a)*r*.49)
			append_box(st,p,Vector3(w*.025,r*.10,r*.19),Basis(Vector3.RIGHT,-a),rubber)
			p=Vector3(side*w*.56,sin(a)*r*.32,cos(a)*r*.32)
			append_box(st,p,Vector3(w*.08,r*.065,r*.065),Basis.IDENTITY,metal)
	if car:
		for i in range(28):
			var a:=TAU*i/28.0
			append_box(st,Vector3(0,sin(a)*r*.985,cos(a)*r*.985),Vector3(w*.75,r*.085,r*.045),Basis(Vector3.RIGHT,-a),Color("333a3e"))
	st.generate_normals()
	var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=.85
	st.set_material(mat)
	return st.commit()

func lathe(st:SurfaceTool,profile:Array,color:Color):
	for j in range(profile.size()-1):
		for i in range(24):
			var a:=TAU*i/24.0;var b:=TAU*(i+1)/24.0
			var p:Vector2=profile[j];var q:Vector2=profile[j+1]
			var points:=[Vector3(p.x,sin(a)*p.y,cos(a)*p.y),Vector3(q.x,sin(a)*q.y,cos(a)*q.y),Vector3(q.x,sin(b)*q.y,cos(b)*q.y),Vector3(p.x,sin(b)*p.y,cos(b)*p.y)]
			for index in [0,2,1,0,3,2]:st.set_color(color);st.add_vertex(points[index])

func append_box(st:SurfaceTool,p:Vector3,size:Vector3,basis:Basis,color:Color):
	var points:Array[Vector3]=[]
	for x in [-.5,.5]:
		for y in [-.5,.5]:
			for z in [-.5,.5]:points.append(p+basis*(Vector3(x,y,z)*size))
	for i in [0,3,1,0,2,3,4,7,6,4,5,7,0,5,4,0,1,5,2,7,3,2,6,7,0,6,2,0,4,6,1,7,5,1,3,7]:
		st.set_color(color);st.add_vertex(points[i])

func add_belt(center:Vector3,r:float,length:float,width:float,side:int):
	var perimeter:=2.0*length+TAU*r
	var count:=clampi(int(perimeter/.17),40,100)
	var mesh:=BoxMesh.new();mesh.size=Vector3(width,.07,perimeter/count*.91)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("42494a");mat.roughness=.92;mesh.material=mat
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh;multi.instance_count=count
	var instance:=MultiMeshInstance3D.new();instance.name="LeftTreadLinks" if side<0 else "RightTreadLinks";instance.multimesh=multi;add_child(instance)
	var belt:={"mesh":multi,"center":center,"radius":r,"length":length,"perimeter":perimeter,"count":count,"phase":0.0,"side":side,"dirty":false}
	belts.append(belt);update_belt(belt)

func update_belt(belt:Dictionary):
	for i in range(belt.count):belt.mesh.set_instance_transform(i,belt_transform(belt,i))
	belt_transform_writes+=int(belt.count)
	belt.dirty=false

func belt_transform(belt:Dictionary,i:int) -> Transform3D:
	var length:float=belt.length;var r:float=belt.radius
	var s:=fposmod(float(i)*float(belt.perimeter)/float(belt.count)+float(belt.phase),float(belt.perimeter))
	var y:float;var z:float;var angle:float
	if s<length:y=-r;z=-length*.5+s;angle=0.0
	elif s<length+PI*r:
		var a:float=(s-length)/r;y=-r*cos(a);z=length*.5+r*sin(a);angle=-a
	elif s<2.0*length+PI*r:y=r;z=length*.5-(s-length-PI*r);angle=-PI
	else:
		var a:float=(s-2.0*length-PI*r)/r;y=r*cos(a);z=-length*.5-r*sin(a);angle=-PI-a
	return Transform3D(Basis(Vector3.RIGHT,angle),belt.center+Vector3(0,y,z))

func visual_update_interval() -> float:
	if not optimization_enabled or force_full_rate:return 0.0
	var focus:Node3D=lod_focus if is_instance_valid(lod_focus) else get_viewport().get_camera_3d()
	# A model inspected without a camera retains full-rate visual animation.
	if not is_instance_valid(focus):return 0.0
	var distance_sq:=global_position.distance_squared_to(focus.global_position)
	if distance_sq<=FULL_RATE_DISTANCE*FULL_RATE_DISTANCE:return 0.0
	if distance_sq<=MEDIUM_RATE_DISTANCE*MEDIUM_RATE_DISTANCE:return MEDIUM_INTERVAL
	return FAR_INTERVAL

func _physics_process(delta:float):
	if not is_visible_in_tree():return
	var model:=get_parent()
	var left:=float(model.get_meta("track_left_speed",0.0))
	var right:=float(model.get_meta("track_right_speed",0.0))
	if absf(left)<=.001:left=0.0
	if absf(right)<=.001:right=0.0
	var moving:=left!=0.0 or right!=0.0
	var just_stopped:=_was_moving and not moving
	_was_moving=moving
	var steering:=float(model.get_meta("steering_input",0.0))*.38 if is_car else 0.0
	var steering_dirty:=steering!=_applied_steering
	# Integrate both independent phases every tick, including speed reversals
	# between visual updates. Only renderer/node transforms are throttled.
	_pending_left+=left*delta
	_pending_right+=right*delta
	for belt in belts:
		var speed:float=left if belt.side<0 else right
		if speed!=0.0:
			belt.phase=fposmod(float(belt.phase)+speed*delta,float(belt.perimeter))
			belt.dirty=true
	var dirty:=_pending_left!=0.0 or _pending_right!=0.0 or steering_dirty
	for belt in belts:
		if belt.dirty:dirty=true
	if not dirty:
		_visual_elapsed=0.0
		idle_visual_ticks+=1
		return
	_visual_elapsed+=delta
	_last_interval=visual_update_interval()
	if not just_stopped and _last_interval>0.0 and _visual_elapsed+0.00000001<_last_interval:
		skipped_visual_ticks+=1
		return
	# Flush once on stopping so the final sub-interval travel is not stranded.
	if _last_interval>0.0 and not just_stopped:
		# Consume the same tolerance used above; plain fposmod can retain almost
		# a full interval after 6 * (1 / 60) due to floating-point rounding.
		var intervals:=floorf((_visual_elapsed+0.00000001)/_last_interval)
		_visual_elapsed=maxf(0.0,_visual_elapsed-intervals*_last_interval)
	else:_visual_elapsed=0.0
	for wheel in wheels:
		var travel:float=_pending_left if wheel.side<0 else _pending_right
		if travel!=0.0:
			wheel.node.rotate_x(-travel/float(wheel.radius))
			wheel_transform_writes+=1
		if wheel.steering and steering_dirty:
			wheel.steer.rotation.y=steering
			steering_transform_writes+=1
	_sync_wheel_batches()
	for belt in belts:
		if belt.dirty:update_belt(belt)
	_pending_left=0.0
	_pending_right=0.0
	_applied_steering=steering
	visual_updates+=1

func reset_performance_counters() -> void:
	visual_updates=0
	belt_transform_writes=0
	wheel_transform_writes=0
	steering_transform_writes=0
	skipped_visual_ticks=0
	idle_visual_ticks=0

func performance_snapshot() -> Dictionary:
	return {"optimization_enabled":optimization_enabled,"force_full_rate":force_full_rate,
		"visual_updates":visual_updates,"belt_transform_writes":belt_transform_writes,
		"wheel_transform_writes":wheel_transform_writes,"steering_transform_writes":steering_transform_writes,
		"skipped_visual_ticks":skipped_visual_ticks,"idle_visual_ticks":idle_visual_ticks,
		"visual_interval_seconds":_last_interval}
