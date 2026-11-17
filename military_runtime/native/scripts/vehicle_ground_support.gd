extends RefCounted
## Rigid track support; terrain stays physical and narrow holes can be bridged.
const MAX_GRADE:=0.8390996 # 40-degree fictional gameplay traction limit.
const TRACK_STATIONS:=7
static func fit(host:Node3D,vehicle:Node3D,fit_orientation:bool=true)->Dictionary:
	var half_length:float=float(vehicle.get_meta("contact_half_length",1.8))
	var half_width:float=float(vehicle.get_meta("contact_half_width",1.25))
	var floor_y:float=float(vehicle.get_meta("ground_contact_y",.035))
	var world=host.get("terrain_damage")
	# Only terrains with explicit invalidation participate. Other providers refit.
	var cacheable: bool=is_instance_valid(world) and world.has_method("ground_support_revision")
	var signature: Array=[]
	if cacheable:
		signature=[world.get_instance_id(),world.ground_support_revision(),fit_orientation,half_length,half_width,floor_y,float(vehicle.get_meta("belly_clearance",.30))]
		var cached: Dictionary=vehicle.get_meta("rigid_support_cache",{})
		if cached.get("signature",[])==signature and cached.get("pose") == vehicle.transform:
			vehicle.set_meta("ground_support",cached.result)
			return cached.result
	var yaw_basis:=Basis(Vector3.UP,vehicle.rotation.y)
	var points:Array[Vector3]=[]
	var loaded:=true
	var xx:=0.0;var zz:=0.0;var xh:=0.0;var zh:=0.0
	for side in [-1.0,1.0]:
		for i in range(TRACK_STATIONS):
			var local:=Vector3(side*half_width,floor_y,lerpf(-half_length,half_length,float(i)/(TRACK_STATIONS-1)))
			points.append(local)
			var at:Vector3=vehicle.position+yaw_basis*local
			if is_instance_valid(world) and world.has_method("is_position_loaded"):
				loaded=loaded and world.in_bounds(at.x,at.z) and world.is_position_loaded(at)
			var h:float=host.terrain_height(at.x,at.z)
			if not is_finite(h):loaded=false;h=vehicle.position.y+floor_y
			xx+=local.x*local.x;zz+=local.z*local.z;xh+=local.x*h;zh+=local.z*h
	var gradient:=Vector2(xh/maxf(xx,.01),zh/maxf(zz,.01))
	var grade:float=gradient.length()
	if fit_orientation:
		var safe_gradient:Vector2=gradient.limit_length(tan(deg_to_rad(42.0)))
		var right:Vector3=yaw_basis.x
		var back:Vector3=yaw_basis.z
		var up:Vector3=(Vector3.UP-right*safe_gradient.x-back*safe_gradient.y).normalized()
		var z_axis:Vector3=right.cross(up).normalized()
		vehicle.basis=Basis(up.cross(z_axis).normalized(),up,z_axis)
	var support:float=-INF
	for local in points:
		var contact:Vector3=vehicle.basis*local
		if is_instance_valid(world) and world.has_method("is_position_loaded"):
			loaded=loaded and world.is_position_loaded(vehicle.position+contact)
		var h:float=host.terrain_height(vehicle.position.x+contact.x,vehicle.position.z+contact.z)
		if not is_finite(h):loaded=false;continue
		support=maxf(support,h-contact.y)
	if not is_finite(support):support=vehicle.position.y
	var track_support:=support
	var clearance:float=float(vehicle.get_meta("belly_clearance",.30))
	for sx in [-.65,0.0,.65]:
		for sz in [-.75,0.0,.75]:
			var belly:Vector3=vehicle.basis*Vector3(sx*half_width,floor_y+clearance,sz*half_length)
			if is_instance_valid(world) and world.has_method("is_position_loaded"):
				loaded=loaded and world.is_position_loaded(vehicle.position+belly)
			var h:float=host.terrain_height(vehicle.position.x+belly.x,vehicle.position.z+belly.z)
			if not is_finite(h):loaded=false;continue
			support=maxf(support,h-belly.y)
	vehicle.position.y=support
	var result:={"loaded":loaded,"grade":grade,"height":support,"belly_lift":support-track_support,"driveable":loaded and grade<=MAX_GRADE and support-track_support<=.18,"samples":points.size()}
	vehicle.set_meta("ground_support",result)
	if cacheable: vehicle.set_meta("rigid_support_cache",{"signature":signature,"pose":vehicle.transform,"result":result})
	return result

static func transition_allowed(previous:Dictionary,next:Dictionary,horizontal_distance:float,yaw_distance:float=0.0)->bool:
	if not bool(next.get("loaded",false)):return false
	var grade:float=float(next.get("grade",INF))
	var old_grade:float=float(previous.get("grade",grade))
	var rise:float=float(next.get("height",0))-float(previous.get("height",0))
	if grade>MAX_GRADE:
		var improving:bool=grade<old_grade-.00001
		var retreating:bool=rise<=.001 and grade<=old_grade+.001
		var pivoting:bool=horizontal_distance<.0001 and grade<=old_grade+.001
		if not (improving or retreating or pivoting):return false
	var belly:float=float(next.get("belly_lift",0.0))
	if belly>.18 and belly>float(previous.get("belly_lift",0.0))+.001:return false
	return absf(rise)<=.035+horizontal_distance*.85+yaw_distance*.5
