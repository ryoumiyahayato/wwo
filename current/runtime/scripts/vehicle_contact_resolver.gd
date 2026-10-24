extends RefCounted
## Metric hull/turret boxes plus articulated full-length barrel capsule.
const CONTACT_MASK := 1 | 8 | 16 | 32 | 128
const SWEEP_STEP := 0.045
var main: Node3D
var encounters: Dictionary = {}
var last_debug: Dictionary = {}

func setup(owner_node: Node3D) -> void:
	main=owner_node

func capture_pose(vehicle: Node3D) -> Dictionary:
	var pose: Dictionary={"root":vehicle.global_transform,"nodes":{},"shapes":[]}
	for key in ["Turret","Barrel"]:
		var node:=vehicle.find_child(key,true,false) as Node3D
		if node!=null:pose.nodes[key]={"node":node,"transform":node.transform}
	pose.layout=_capture_layout(vehicle)
	pose.shapes=_shape_pose(pose,pose,1.0)
	return pose

func _apply(vehicle: Node3D,a: Dictionary,b: Dictionary,weight: float) -> void:
	vehicle.global_transform=a.root if weight==0.0 else (a.root as Transform3D).interpolate_with(b.root,weight)
	for key in a.nodes:
		if b.nodes.has(key):
			var item:Dictionary=a.nodes[key]
			if is_instance_valid(item.node):item.node.transform=item.transform if weight==0.0 else (item.transform as Transform3D).interpolate_with(b.nodes[key].transform,weight)

## Capture topology once per sweep; substeps never recurse or mutate physics bodies.
## No persistent node cache: replacement, death and newly attached collision shapes
## are observed on the very next capture.
func _path_from(vehicle:Node3D,node:Node3D)->Array:
	var path:Array=[]
	var cursor:Node=node
	while cursor!=vehicle and cursor!=null:
		if cursor is Node3D:path.push_front({"node":cursor,"transform":cursor.transform})
		cursor=cursor.get_parent()
	return path

func _capture_layout(vehicle:Node3D)->Array:
	var layout:Array=[]
	for node in vehicle.find_children("*","CollisionShape3D",true,false):
		var body:=node.get_parent() as CollisionObject3D
		if body==null or node.disabled or node.shape==null:continue
		if str(body.get_meta("kind","")) not in ["armor","armor_group"]:continue
		layout.append({"shape":node.shape,"path":_path_from(vehicle,node),"barrel":false})
	var barrel:=vehicle.find_child("Barrel",true,false) as Node3D
	var muzzle:=vehicle.find_child("Muzzle",true,false) as Node3D
	if barrel!=null and muzzle!=null and barrel.global_position.distance_to(muzzle.global_position)>0.05:
		layout.append({"shape":CapsuleShape3D.new(),"path":_path_from(vehicle,barrel),"muzzle_path":_path_from(vehicle,muzzle),"radius":float(barrel.get_meta("contact_radius",0.075)),"barrel":true})
	return layout

## Memoize only within this interpolated pose. No cross-frame topology, motion,
## shape or visibility cache: all live geometry is captured again next call.
func _path_pose(path:Array,root_pose:Transform3D,locals:Dictionary,resolved:Dictionary)->Transform3D:
	var transform:=root_pose
	for entry in path:
		var id:int=entry.node.get_instance_id()
		if resolved.has(id):
			transform=resolved[id]
		else:
			transform=transform*(locals[id] if locals.has(id) else entry.transform)
			resolved[id]=transform
	return transform

func _shape_pose(a:Dictionary,b:Dictionary,weight:float)->Array:
	var result:Array=[]
	var root_pose:Transform3D=(a.root as Transform3D).interpolate_with(b.root,weight)
	var locals:Dictionary={}
	var resolved:Dictionary={}
	for key in a.nodes:
		if b.nodes.has(key):
			locals[a.nodes[key].node.get_instance_id()]=(a.nodes[key].transform as Transform3D).interpolate_with(b.nodes[key].transform,weight)
	for entry in a.layout:
		var transform:=_path_pose(entry.path,root_pose,locals,resolved)
		if entry.barrel:
			var end:=_path_pose(entry.muzzle_path,root_pose,locals,resolved).origin
			var start:=transform.origin
			var axis:Vector3=(end-start).normalized()
			var right:Vector3=axis.cross(Vector3.RIGHT if absf(axis.dot(Vector3.UP))>0.95 else Vector3.UP).normalized()
			if not is_equal_approx(entry.shape.radius,entry.radius):entry.shape.radius=entry.radius
			var height:float=start.distance_to(end)+entry.radius*2.0
			if not is_equal_approx(entry.shape.height,height):entry.shape.height=height
			transform=Transform3D(Basis(right,axis,right.cross(axis)).orthonormalized(),(start+end)*0.5)
		result.append({"shape":entry.shape,"transform":transform,"barrel":entry.barrel})
	return result

func _shapes(vehicle:Node3D)->Array:
	return capture_pose(vehicle).shapes

func _exclusions(vehicle:Node3D,exclude_ground:bool=true) -> Array[RID]:
	var excluded:Array[RID]=[]
	for body in vehicle.find_children("*","CollisionObject3D",true,false):excluded.append(body.get_rid())
	if not exclude_ground:return excluded
	for ground in vehicle.get_tree().get_nodes_in_group("drivable_ground"):
		if ground is CollisionObject3D:excluded.append(ground.get_rid())
	if is_instance_valid(main) and is_instance_valid(main.get("terrain_damage")):
		var terrain:Node=main.get("terrain_damage")
		if is_instance_valid(terrain.get("body")):excluded.append(terrain.get("body").get_rid())
	return excluded

func resolve_pose(vehicle:Node3D,previous:Dictionary,speed:float,_delta:float) -> Dictionary:
	# The caller changes only transforms between capture and resolve. Reuse the
	# captured topology within this synchronous sweep, never across frames.
	var desired:Dictionary={"root":vehicle.global_transform,"nodes":{},"layout":previous.layout}
	for key in previous.nodes:
		var node:Node3D=previous.nodes[key].node
		if not is_instance_valid(node):return {"blocked":true,"fraction":0.0,"contacts":[]}
		desired.nodes[key]={"node":node,"transform":node.transform}
	desired.shapes=_shape_pose(desired,desired,1.0)
	var before:Array=previous.shapes
	var after:Array=desired.shapes
	if before.size()!=after.size():return {"blocked":false,"fraction":1.0,"contacts":[]}
	var travel:=0.0
	for i in before.size():
		var ta:Transform3D=before[i].transform
		var tb:Transform3D=after[i].transform
		travel=maxf(travel,ta.origin.distance_to(tb.origin)+ta.basis.get_rotation_quaternion().angle_to(tb.basis.get_rotation_quaternion())*_radius(before[i].shape))
	if travel<0.000001:return {"blocked":false,"fraction":1.0,"contacts":[]}
	# No substep cap: large rotations must not tunnel between clear endpoints.
	var count:=maxi(1,int(ceil(travel/SWEEP_STEP)))
	var exclusions:=_exclusions(vehicle)
	var barrel_exclusions:=_exclusions(vehicle,false)
	var space:=vehicle.get_world_3d().direct_space_state
	var contacts:Array=[]
	var seen:Dictionary={}
	var old_shapes:Array=before
	var accepted:=0.0
	var direction:Vector3=(desired.root.origin-previous.root.origin).normalized()
	for step in range(1,count+1):
		var fraction:=float(step)/count
		var current:=_shape_pose(previous,desired,fraction)
		for i in current.size():
			var item:Dictionary=current[i]
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=item.shape;query.transform=item.transform
			query.collision_mask=CONTACT_MASK
			query.exclude=barrel_exclusions if item.barrel else exclusions
			query.margin=SWEEP_STEP*0.55
			var hits:=space.intersect_shape(query,32)
			query.transform=old_shapes[i].transform
			query.motion=(item.transform as Transform3D).origin-query.transform.origin
			var sweep:=space.cast_motion(query) if query.motion.length_squared()>0.000000000001 else PackedFloat32Array([1.0,1.0])
			if sweep.size()==2 and sweep[0]<1.0:
				query.transform.origin+=query.motion*minf(1.0,sweep[1]+0.001)
				query.motion=Vector3.ZERO
				hits.append_array(space.intersect_shape(query,32))
			for hit in hits:
				var collider:Object=hit.collider
				if not is_instance_valid(collider):continue
				var id:=collider.get_instance_id()
				seen[id]=true
				var contact_direction:=direction
				if contact_direction.length_squared()<0.01:
					contact_direction=((item.transform as Transform3D).origin-(old_shapes[i].transform as Transform3D).origin).normalized()
				if contact_direction.length_squared()<0.01:contact_direction=-(previous.root as Transform3D).interpolate_with(desired.root,fraction).basis.z
				var cleared:=false
				if collider.has_method("receive_vehicle_contact"):
					var crush:bool=not item.barrel and absf(speed)>=3.0 and not encounters.has(id)
					cleared=bool(collider.call("receive_vehicle_contact",contact_direction,absf(speed),crush))
					encounters[id]=true
					if cleared and collider is CollisionObject3D and collider.collision_layer!=0:
						query.transform=item.transform;query.motion=Vector3.ZERO
						for remaining in space.intersect_shape(query,32):
							if remaining.collider==collider:cleared=false
				elif collider is Node and collider.has_meta("contact_tree"):
					cleared=_tree_contact(collider,contact_direction,speed,not item.barrel)
				if not cleared and not collider.has_method("receive_vehicle_contact"):
					cleared=_relieves_overlap(space,item,old_shapes[i],collider,query.exclude,query.margin)
				contacts.append({"collider":id,"barrel":item.barrel,"cleared":cleared,"path":str(collider.get_path()) if collider is Node else ""})
				if not cleared:
					_apply(vehicle,previous,desired,accepted)
					last_debug={"before":before,"requested":after,"accepted":_shape_pose(previous,desired,accepted),"contacts":contacts}
					return {"blocked":true,"fraction":accepted,"contacts":contacts}
		accepted=fraction;old_shapes=current
	# Desired pose is already installed by the caller; no physical rewrite needed.
	for id in encounters.keys():
		if not seen.has(id):encounters.erase(id)
	last_debug={"before":before,"requested":after,"accepted":desired.shapes,"contacts":contacts}
	return {"blocked":false,"fraction":1.0,"contacts":contacts}

func _radius(shape:Shape3D) -> float:
	if shape is BoxShape3D:return shape.size.length()*0.5
	if shape is CapsuleShape3D:return shape.height*0.5
	if shape is CylinderShape3D:return shape.height*0.5+shape.radius
	return 1.0

## Only physically relieving an already-existing overlap is permitted.
func _relieves_overlap(space:PhysicsDirectSpaceState3D,current:Dictionary,old:Dictionary,target:Object,excluded:Array[RID],margin:float) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=current.shape;query.transform=old.transform
	query.collision_mask=CONTACT_MASK;query.exclude=excluded;query.margin=margin
	var previous_hits:=space.intersect_shape(query,64)
	var was_overlapping:=false
	var isolate:Array[RID]=excluded.duplicate()
	for hit in previous_hits:
		if hit.collider==target:was_overlapping=true
		elif hit.collider is CollisionObject3D:isolate.append(hit.collider.get_rid())
	if not was_overlapping:return false
	query.transform=current.transform
	for hit in space.intersect_shape(query,64):
		if hit.collider!=target and hit.collider is CollisionObject3D:isolate.append(hit.collider.get_rid())
	query.exclude=isolate;query.transform=old.transform
	var old_points:=space.collide_shape(query,64)
	var before_depth:=_contact_depth(old_points)
	var old_transform:Transform3D=old.transform
	var new_transform:Transform3D=current.transform
	for index in range(0,old_points.size()-1,2):
		var normal:=old_points[index]-old_points[index+1]
		var moved_point:=new_transform*(old_transform.affine_inverse()*old_points[index])
		if (moved_point-old_points[index]).dot(normal)>0.0000001:return false
	query.transform=current.transform
	var after_depth:=_contact_depth(space.collide_shape(query,64))
	return before_depth>0.000001 and after_depth<before_depth-0.0000001

func _contact_depth(points:PackedVector3Array) -> float:
	var depth:=0.0
	for i in range(0,points.size()-1,2):depth=maxf(depth,points[i].distance_to(points[i+1]))
	return depth

func register_tree(visual:Node3D,radius:float,height:float,breakable:bool) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="ContactTrunk"
	body.collision_layer=8;body.collision_mask=0
	body.set_meta("contact_tree",true);body.set_meta("breakable",breakable);body.set_meta("tree_visual",visual)
	var shape:=CollisionShape3D.new();var cylinder:=CylinderShape3D.new()
	cylinder.radius=radius;cylinder.height=height
	shape.shape=cylinder;shape.position.y=height*0.5
	body.add_child(shape);visual.add_child(body)
	return body

func _tree_contact(body:Node,direction:Vector3,speed:float,hull:bool) -> bool:
	if bool(body.get_meta("fallen",false)):return true
	if not hull or not bool(body.get_meta("breakable",false)) or absf(speed)<1.4:return false
	if bool(body.get_meta("falling",false)):return false
	body.set_meta("falling",true)
	var visual:Node3D=body.get_meta("tree_visual")
	var axis:=Vector3.UP.cross(Vector3(direction.x,0,direction.z).normalized()).normalized()
	if axis.length_squared()<0.5:axis=Vector3.RIGHT
	var initial:=visual.quaternion
	var tween:=visual.create_tween()
	tween.tween_method(func(angle:float):visual.quaternion=Quaternion(axis,angle)*initial,0.0,1.48,0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_callback(func():body.collision_layer=0;body.set_meta("fallen",true)).set_delay(0.4)
	return false

## Original colliders are untouched unless this mesh has verified tree metadata.
func install_terrain_trees(terrain:Node3D) -> int:
	var installed:=0
	for mesh in terrain.find_children("*","MeshInstance3D",true,false):
		var extras:Dictionary=mesh.get_meta("extras",{})
		if not extras.has("tree_base_local") or bool(mesh.get_meta("tree_contact_installed",false)):continue
		var data:Variant=extras.tree_base_local
		var base:Vector3=data if data is Vector3 else Vector3(float(data[0]),float(data[1]),float(data[2]))
		var old_parent:Node3D=mesh.get_parent()
		var original:Transform3D=mesh.transform
		var pivot:=Node3D.new();pivot.name=str(mesh.name)+"FallPivot"
		old_parent.add_child(pivot);pivot.transform=original*Transform3D(Basis.IDENTITY,base)
		mesh.reparent(pivot,false);mesh.transform=Transform3D(Basis.IDENTITY,-base)
		mesh.set_meta("tree_contact_installed",true)
		for body in mesh.find_children("*","CollisionObject3D",true,false):
			body.collision_layer=0;body.collision_mask=0
		register_tree(pivot,float(extras.get("trunk_radius",0.1)),float(extras.get("trunk_height",1.0)),bool(extras.get("breakable",false)))
		installed+=1
	return installed

## Explicit QA-only overlay, never installed during ordinary play.
func build_debug_snapshot(parent:Node3D) -> Node3D:
	var root:=Node3D.new();root.name="ContactSweepDebug";parent.add_child(root)
	for key in ["before","requested","accepted"]:
		var color:=Color(.2,.6,1,.28) if key=="before" else Color(1,.2,.2,.28) if key=="requested" else Color(.2,1,.4,.4)
		for item in last_debug.get(key,[]):
			var mesh:=MeshInstance3D.new();var shape:Shape3D=item.shape
			if shape is BoxShape3D:
				var box:=BoxMesh.new();box.size=shape.size;mesh.mesh=box
			elif shape is CapsuleShape3D:
				var capsule:=CapsuleMesh.new();capsule.radius=shape.radius;capsule.height=shape.height;mesh.mesh=capsule
			else:continue
			var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.material_override=mat;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mesh);mesh.global_transform=item.transform
	return root
