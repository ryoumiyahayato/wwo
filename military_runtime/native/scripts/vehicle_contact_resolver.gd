extends RefCounted
## Metric hull/turret boxes plus articulated full-length barrel capsule.
const CONTACT_MASK := 1 | 8 | 16 | 32 | 128
const SWEEP_STEP := 0.045
var main: Node3D
var encounters: Dictionary = {}
var last_debug: Dictionary = {}
# Same explicit opt-in as Armor. Fixed operation keys, no event/log buffer.
var _slow_timing_enabled: bool = OS.get_environment("WWO_BATTLE_SLOW_TIMING") == "1"
var _slow_timing_operations: Dictionary = {}
# Structural membership only. No cached Transform, shape resource/state or query result.
var _metadata_tree: SceneTree
var _vehicle_metadata: Dictionary = {}
var _metadata_roots: Dictionary = {}
var _metadata_members: Dictionary = {}
var _order_observers: Dictionary = {}
var _metadata_hits: int = 0
var _metadata_misses: int = 0
var _metadata_invalidations: int = 0
var _metadata_capture_hits: int = 0
var _metadata_cross_physics_capture_hits: int = 0
var _metadata_order_watch_failed: bool = false

func _timing_sample(operation: String, duration: int) -> void:
	var row: Dictionary = _slow_timing_operations.get(operation,{"calls":0,"total_usec":0,"max_usec":0})
	row.calls += 1
	row.total_usec += duration
	row.max_usec = maxi(int(row.max_usec),duration)
	_slow_timing_operations[operation] = row

func slow_timing_snapshot() -> Dictionary:
	return {"enabled":_slow_timing_enabled,"scope":"resolver_lifetime_all_callers","clock":"cpu_call_usec_not_gpu","operations_are_inclusive":true,"operations":_slow_timing_operations.duplicate(true),"metadata_cache":{"enabled":is_instance_valid(_metadata_tree) and not _metadata_order_watch_failed,"entries":_vehicle_metadata.size(),"hits":_metadata_hits,"misses":_metadata_misses,"invalidations":_metadata_invalidations,"capture_hits":_metadata_capture_hits,"cross_physics_capture_hits":_metadata_cross_physics_capture_hits}}

func _timed_intersect_shape(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, max_results: int) -> Array[Dictionary]:
	var started: int = Time.get_ticks_usec()
	var result: Array[Dictionary] = space.intersect_shape(query,max_results)
	_timing_sample("intersect_shape",Time.get_ticks_usec()-started)
	return result

func _timed_cast_motion(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> PackedFloat32Array:
	var started: int = Time.get_ticks_usec()
	var result: PackedFloat32Array = space.cast_motion(query)
	_timing_sample("cast_motion",Time.get_ticks_usec()-started)
	return result

func _timed_collide_shape(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, max_results: int) -> PackedVector3Array:
	var started: int = Time.get_ticks_usec()
	var result: PackedVector3Array = space.collide_shape(query,max_results)
	_timing_sample("collide_shape",Time.get_ticks_usec()-started)
	return result

func setup(owner_node: Node3D) -> void:
	if is_instance_valid(main) and main.is_connected("tree_exiting",_release_metadata_observers):
		main.disconnect("tree_exiting",_release_metadata_observers)
	_release_metadata_observers()
	main=owner_node
	if is_instance_valid(main):main.connect("tree_exiting",_release_metadata_observers)

func _invalidate_vehicle_metadata(ids: Dictionary) -> void:
	for id: int in ids:
		if _vehicle_metadata.has(id):
			_vehicle_metadata.erase(id)
			if _slow_timing_enabled:_metadata_invalidations+=1

func _invalidate_node_metadata(node: Node) -> void:
	if not is_instance_valid(node):
		# Unknown event relation: never assume an old structure is still valid.
		if _slow_timing_enabled:_metadata_invalidations+=_vehicle_metadata.size()
		_vehicle_metadata.clear()
		return
	var id: int=node.get_instance_id()
	var affected: Dictionary=_metadata_members.get(id,{}).duplicate()
	var cursor: Node=node
	while cursor!=null:
		var ancestor_id: int=cursor.get_instance_id()
		if _metadata_roots.has(ancestor_id):affected[ancestor_id]=true
		cursor=cursor.get_parent()
	_invalidate_vehicle_metadata(affected)

func _invalidate_order_metadata(parent_id: int) -> void:
	if not _order_observers.has(parent_id):
		if _slow_timing_enabled:_metadata_invalidations+=_vehicle_metadata.size()
		_vehicle_metadata.clear()
		return
	var record: Dictionary=_order_observers[parent_id]
	_invalidate_vehicle_metadata(record.vehicles)

func _metadata_node_removed(node: Node) -> void:
	_invalidate_node_metadata(node)
	if not is_instance_valid(node):return
	var id: int=node.get_instance_id()
	if _order_observers.has(id):
		var record: Dictionary=_order_observers[id]
		var callback: Callable=record.callback
		if node.is_connected("child_order_changed",callback):node.disconnect("child_order_changed",callback)
		_order_observers.erase(id)
	_metadata_members.erase(id)
	if _metadata_roots.has(id):
		_metadata_roots.erase(id)
		for member_id: int in _metadata_members.keys():
			var vehicles: Dictionary=_metadata_members[member_id]
			vehicles.erase(id)
			if vehicles.is_empty():_metadata_members.erase(member_id)
		for parent_id: int in _order_observers.keys():
			var record: Dictionary=_order_observers[parent_id]
			record.vehicles.erase(id)
			if record.vehicles.is_empty():
				var parent: Node=record.node
				var callback: Callable=record.callback
				if is_instance_valid(parent) and parent.is_connected("child_order_changed",callback):parent.disconnect("child_order_changed",callback)
				_order_observers.erase(parent_id)

func _release_metadata_observers() -> void:
	if is_instance_valid(_metadata_tree):
		for signal_name: String in ["node_added","node_renamed"]:
			if _metadata_tree.is_connected(signal_name,_invalidate_node_metadata):
				_metadata_tree.disconnect(signal_name,_invalidate_node_metadata)
		if _metadata_tree.is_connected("node_removed",_metadata_node_removed):
			_metadata_tree.disconnect("node_removed",_metadata_node_removed)
	for record: Dictionary in _order_observers.values():
		var parent: Node=record.node
		var callback: Callable=record.callback
		if is_instance_valid(parent) and parent.is_connected("child_order_changed",callback):
			parent.disconnect("child_order_changed",callback)
	_order_observers.clear()
	_vehicle_metadata.clear()
	_metadata_roots.clear()
	_metadata_members.clear()
	_metadata_tree=null
	_metadata_order_watch_failed=false

func _metadata_observation_ready(vehicle: Node3D) -> bool:
	if _metadata_order_watch_failed or not is_instance_valid(main) or not main.is_inside_tree() or not vehicle.is_inside_tree():return false
	var tree: SceneTree=vehicle.get_tree()
	if tree==_metadata_tree and tree.is_connected("node_added",_invalidate_node_metadata) and tree.is_connected("node_removed",_metadata_node_removed) and tree.is_connected("node_renamed",_invalidate_node_metadata):
		return true
	_release_metadata_observers()
	# Per-operation signals, not the potentially coalesced tree_changed signal.
	for signal_name: String in ["node_added","node_removed","node_renamed"]:
		if not tree.has_signal(signal_name):return false
	if tree.connect("node_added",_invalidate_node_metadata)!=OK:return false
	if tree.connect("node_removed",_metadata_node_removed)!=OK:
		tree.disconnect("node_added",_invalidate_node_metadata)
		return false
	if tree.connect("node_renamed",_invalidate_node_metadata)!=OK:
		tree.disconnect("node_added",_invalidate_node_metadata)
		tree.disconnect("node_removed",_metadata_node_removed)
		return false
	_metadata_tree=tree
	return true

func _watch_parent_order(parent: Node, vehicle_id: int) -> void:
	if parent==null or _metadata_order_watch_failed:return
	var id: int=parent.get_instance_id()
	if _order_observers.has(id):
		var record: Dictionary=_order_observers[id]
		record.vehicles[vehicle_id]=true
		return
	if not parent.has_signal("child_order_changed"):
		_metadata_order_watch_failed=true
		_vehicle_metadata.clear()
		return
	var callback: Callable=_invalidate_order_metadata.bind(id)
	if parent.connect("child_order_changed",callback)!=OK:
		_metadata_order_watch_failed=true
		_vehicle_metadata.clear()
		return
	_order_observers[id]={"node":parent,"callback":callback,"vehicles":{vehicle_id:true}}

func _path_nodes_from(vehicle: Node3D, node: Node, observe: bool) -> Array:
	var path: Array=[]
	var vehicle_id: int=vehicle.get_instance_id()
	var cursor: Node=node
	while cursor!=vehicle and cursor!=null:
		var parent: Node=cursor.get_parent()
		if observe:
			var members: Dictionary=_metadata_members.get(cursor.get_instance_id(),{})
			members[vehicle_id]=true
			_metadata_members[cursor.get_instance_id()]=members
			_watch_parent_order(parent,vehicle_id)
		if cursor is Node3D:path.push_front({"node":cursor,"id":cursor.get_instance_id()})
		cursor=parent
	return path

func _indexed_path_from(vehicle: Node3D, node: Node, observe: bool, topology: Dictionary) -> PackedInt32Array:
	var path: PackedInt32Array=PackedInt32Array()
	var nodes: Array[Node3D]=topology.nodes
	var ids: Array[int]=topology.ids
	var indices: Dictionary=topology.indices
	for entry: Dictionary in _path_nodes_from(vehicle,node,observe):
		var id: int=int(entry.id)
		if not indices.has(id):
			indices[id]=nodes.size()
			nodes.append(entry.node as Node3D)
			ids.append(id)
		path.append(int(indices[id]))
	return path

func _build_vehicle_metadata(vehicle: Node3D, observe: bool) -> Dictionary:
	# Published once, then never edited. Old poses retain this table on invalidation.
	var nodes: Array[Node3D]=[]
	var ids: Array[int]=[]
	var topology: Dictionary={"nodes":nodes,"ids":ids,"indices":{}}
	var named: Dictionary={}
	for key: String in ["Turret","Barrel","Muzzle"]:
		var found: Node=vehicle.find_child(key,true,false)
		named[key]=found as Node3D
		# Watch even a non-Node3D first match: reordering can change that match.
		if found!=null:_indexed_path_from(vehicle,found,observe,topology)
	var shapes: Array[Dictionary]=[]
	for shape_child: Node in vehicle.find_children("*","CollisionShape3D",true,false):
		var shape_node: CollisionShape3D=shape_child as CollisionShape3D
		var body: CollisionObject3D=shape_node.get_parent() as CollisionObject3D
		if body!=null:
			shapes.append({"node":shape_node,"body":body,"path":_indexed_path_from(vehicle,shape_node,observe,topology)})
	var own: Array[RID]=[]
	for body_child: Node in vehicle.find_children("*","CollisionObject3D",true,false):
		var body: CollisionObject3D=body_child as CollisionObject3D
		own.append(body.get_rid())
		if observe:_path_nodes_from(vehicle,body,true)
	var barrel_path: PackedInt32Array=PackedInt32Array()
	var muzzle_path: PackedInt32Array=PackedInt32Array()
	if named.Barrel!=null:barrel_path=_indexed_path_from(vehicle,named.Barrel,observe,topology)
	if named.Muzzle!=null:muzzle_path=_indexed_path_from(vehicle,named.Muzzle,observe,topology)
	return {"vehicle":vehicle,"named":named,"topology":topology,"shapes":shapes,"own":own,"barrel_path":barrel_path,"muzzle_path":muzzle_path}

func _metadata_for_vehicle(vehicle: Node3D, capture_lookup: bool=false) -> Dictionary:
	var observed: bool=_metadata_observation_ready(vehicle)
	var id: int=vehicle.get_instance_id()
	if observed:_metadata_roots[id]=vehicle
	if observed and _vehicle_metadata.has(id):
		var cached: Dictionary=_vehicle_metadata[id]
		if _slow_timing_enabled:
			_metadata_hits+=1
			if capture_lookup:
				_metadata_capture_hits+=1
				var physics_frame: int=Engine.get_physics_frames()
				if int(cached.get("_built_physics_frame",physics_frame))<physics_frame:_metadata_cross_physics_capture_hits+=1
		return cached
	if _slow_timing_enabled:_metadata_misses+=1
	var timing_started: int=Time.get_ticks_usec() if _slow_timing_enabled else 0
	var metadata: Dictionary=_build_vehicle_metadata(vehicle,observed)
	if _slow_timing_enabled:
		_timing_sample("metadata_build",Time.get_ticks_usec()-timing_started)
		# Diagnostic provenance only; never used to decide cache validity.
		metadata["_built_physics_frame"]=Engine.get_physics_frames()
	if observed and not _metadata_order_watch_failed:_vehicle_metadata[id]=metadata
	return metadata

func _snapshot_path(path: Array, captured: Dictionary) -> Array:
	var result: Array=[]
	for entry: Dictionary in path:
		var id: int=int(entry.id)
		if not captured.has(id):
			var node: Node3D=entry.node
			captured[id]={"node":node,"id":id,"transform":node.transform}
		result.append(captured[id])
	return result

func capture_pose(vehicle: Node3D) -> Dictionary:
	var timing_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	var metadata: Dictionary=_metadata_for_vehicle(vehicle,true)
	var pose: Dictionary={"root":vehicle.global_transform,"nodes":{},"shapes":[]}
	var local_transforms: Array[Transform3D]=[]
	# Zero means not captured; otherwise the compact snapshot index plus one.
	var local_indices: PackedInt32Array=PackedInt32Array()
	local_indices.resize(metadata.topology.nodes.size())
	pose["local_transforms"]=local_transforms
	pose["local_indices"]=local_indices
	pose["topology"]=metadata.topology
	for key: String in ["Turret","Barrel"]:
		var node: Node3D=metadata.named[key]
		if node!=null:pose.nodes[key]={"node":node,"id":node.get_instance_id(),"transform":node.transform}
	var barrel: Node3D=metadata.named.Barrel
	pose.layout=_capture_layout(vehicle,barrel,metadata,pose.nodes,local_transforms,local_indices)
	# Used by travel/substep and old-pose collision tests; not dead data.
	pose.shapes=_shape_pose(pose,pose,1.0)
	if _slow_timing_enabled: _timing_sample("capture_pose",Time.get_ticks_usec()-timing_started)
	return pose

func _apply(vehicle: Node3D,a: Dictionary,b: Dictionary,weight: float) -> void:
	vehicle.global_transform=a.root if weight==0.0 else (a.root as Transform3D).interpolate_with(b.root,weight)
	for key in a.nodes:
		if b.nodes.has(key):
			var item:Dictionary=a.nodes[key]
			if is_instance_valid(item.node):item.node.transform=item.transform if weight==0.0 else (item.transform as Transform3D).interpolate_with(b.nodes[key].transform,weight)

## A sweep still snapshots all geometry. Only tree membership/path nodes persist;
## each capture reads shape state, metadata and local transforms again.
func _path_from(vehicle:Node3D,node:Node3D)->Array:
	return _snapshot_path(_path_nodes_from(vehicle,node,false),{})

func _capture_local_path(path: PackedInt32Array, nodes: Array[Node3D], snapshot: Array[Transform3D], captured: PackedInt32Array) -> void:
	for index: int in path:
		if captured[index]==0:
			snapshot.append(nodes[index].transform)
			captured[index]=snapshot.size()

func _capture_layout(_vehicle:Node3D,barrel:Node3D,metadata:Dictionary,articulated:Dictionary,snapshot:Array[Transform3D],captured:PackedInt32Array)->Array:
	var timing_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	var layout:Array=[]
	var nodes: Array[Node3D]=metadata.topology.nodes
	var indices: Dictionary=metadata.topology.indices
	for record:Dictionary in articulated.values():
		var index: int=int(indices[int(record.id)])
		snapshot.append(record.transform)
		captured[index]=snapshot.size()
	for entry:Dictionary in metadata.shapes:
		var node:CollisionShape3D=entry.node
		var body:CollisionObject3D=entry.body
		if node.disabled or node.shape==null:continue
		if str(body.get_meta("kind","")) not in ["armor","armor_group"]:continue
		_capture_local_path(entry.path,nodes,snapshot,captured)
		layout.append({"shape":node.shape,"path":entry.path,"barrel":false})
	var muzzle:Node3D=metadata.named.Muzzle
	if barrel!=null and muzzle!=null and barrel.global_position.distance_to(muzzle.global_position)>0.05:
		var capsule: CapsuleShape3D=CapsuleShape3D.new()
		_capture_local_path(metadata.barrel_path,nodes,snapshot,captured)
		_capture_local_path(metadata.muzzle_path,nodes,snapshot,captured)
		layout.append({"shape":capsule,"path":metadata.barrel_path,"muzzle_path":metadata.muzzle_path,"radius":float(barrel.get_meta("contact_radius",0.075)),"barrel":true})
	if _slow_timing_enabled: _timing_sample("layout_including_path_capture",Time.get_ticks_usec()-timing_started)
	return layout

## World transforms are memoized only within this interpolated pose. Structural
## path IDs persist, but no Transform, shape state or visibility result does.
func _path_pose(path:Array,root_pose:Transform3D,locals:Dictionary,resolved:Dictionary)->Transform3D:
	var transform:=root_pose
	for entry in path:
		var id:int=int(entry.get("id",0))
		if id==0:id=entry.node.get_instance_id()
		if resolved.has(id):
			transform=resolved[id]
		else:
			transform=transform*(locals[id] if locals.has(id) else entry.transform)
			resolved[id]=transform
	return transform

func _indexed_path_pose(path:PackedInt32Array,root_pose:Transform3D,locals:Dictionary,resolved:Dictionary,snapshot:Array[Transform3D],captured:PackedInt32Array,ids:Array[int])->Transform3D:
	var transform: Transform3D=root_pose
	for index: int in path:
		var id: int=ids[index]
		if resolved.has(id):
			transform=resolved[id]
		else:
			transform=transform*(locals[id] if locals.has(id) else snapshot[captured[index]-1])
			resolved[id]=transform
	return transform

func _shape_pose(a:Dictionary,b:Dictionary,weight:float)->Array:
	var timing_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	var result:Array=[]
	var root_pose:Transform3D=(a.root as Transform3D).interpolate_with(b.root,weight)
	var snapshot: Array[Transform3D]=a.local_transforms
	var captured: PackedInt32Array=a.local_indices
	var ids: Array[int]=a.topology.ids
	var locals:Dictionary={}
	var resolved:Dictionary={}
	for key in a.nodes:
		if b.nodes.has(key):
			var id:int=int(a.nodes[key].get("id",0))
			if id==0:id=a.nodes[key].node.get_instance_id()
			locals[id]=(a.nodes[key].transform as Transform3D).interpolate_with(b.nodes[key].transform,weight)
	for entry in a.layout:
		var transform: Transform3D=_indexed_path_pose(entry.path,root_pose,locals,resolved,snapshot,captured,ids)
		if entry.barrel:
			var end: Vector3=_indexed_path_pose(entry.muzzle_path,root_pose,locals,resolved,snapshot,captured,ids).origin
			var start:=transform.origin
			var axis:Vector3=(end-start).normalized()
			var right:Vector3=axis.cross(Vector3.RIGHT if absf(axis.dot(Vector3.UP))>0.95 else Vector3.UP).normalized()
			if not is_equal_approx(entry.shape.radius,entry.radius):entry.shape.radius=entry.radius
			var height:float=start.distance_to(end)+entry.radius*2.0
			if not is_equal_approx(entry.shape.height,height):entry.shape.height=height
			transform=Transform3D(Basis(right,axis,right.cross(axis)).orthonormalized(),(start+end)*0.5)
		result.append({"shape":entry.shape,"transform":transform,"barrel":entry.barrel})
	if _slow_timing_enabled: _timing_sample("shape_pose_including_paths",Time.get_ticks_usec()-timing_started)
	return result

func _shapes(vehicle:Node3D)->Array:
	return capture_pose(vehicle).shapes

func _exclusions(vehicle:Node3D,exclude_ground:bool=true) -> Array[RID]:
	var timing_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	var metadata:Dictionary=_metadata_for_vehicle(vehicle)
	var own:Array[RID]=metadata.own.duplicate()
	if _slow_timing_enabled: _timing_sample("own_rid_collection",Time.get_ticks_usec()-timing_started)
	return _with_ground_exclusions(vehicle,own) if exclude_ground else own

func _with_ground_exclusions(vehicle:Node3D,own:Array[RID]) -> Array[RID]:
	var timing_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	# Copy current structural membership; never retain streamed ground/group RIDs.
	var excluded:Array[RID]=own.duplicate()
	for ground in vehicle.get_tree().get_nodes_in_group("drivable_ground"):
		if ground is CollisionObject3D:excluded.append(ground.get_rid())
	if is_instance_valid(main) and is_instance_valid(main.get("terrain_damage")):
		var terrain:Node=main.get("terrain_damage")
		if is_instance_valid(terrain.get("body")):excluded.append(terrain.get("body").get_rid())
	if _slow_timing_enabled: _timing_sample("ground_rid_collection",Time.get_ticks_usec()-timing_started)
	return excluded

func resolve_pose(vehicle:Node3D,previous:Dictionary,speed:float,_delta:float) -> Dictionary:
	var timing_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	# The caller changes only transforms between capture and resolve. Reuse the
	# captured topology within this synchronous sweep, never across frames.
	var desired:Dictionary={"root":vehicle.global_transform,"nodes":{},"layout":previous.layout,"local_transforms":previous.local_transforms,"local_indices":previous.local_indices,"topology":previous.topology}
	for key in previous.nodes:
		var node:Node3D=previous.nodes[key].node
		if not is_instance_valid(node):
			if _slow_timing_enabled: _timing_sample("resolve_pose",Time.get_ticks_usec()-timing_started)
			return {"blocked":true,"fraction":0.0,"contacts":[]}
		desired.nodes[key]={"node":node,"id":int(previous.nodes[key].get("id",0)),"transform":node.transform}
	desired.shapes=_shape_pose(desired,desired,1.0)
	var before:Array=previous.shapes
	var after:Array=desired.shapes
	if before.size()!=after.size():
		if _slow_timing_enabled: _timing_sample("resolve_pose",Time.get_ticks_usec()-timing_started)
		return {"blocked":false,"fraction":1.0,"contacts":[]}
	var travel:=0.0
	for i in before.size():
		var ta:Transform3D=before[i].transform
		var tb:Transform3D=after[i].transform
		travel=maxf(travel,ta.origin.distance_to(tb.origin)+ta.basis.get_rotation_quaternion().angle_to(tb.basis.get_rotation_quaternion())*_radius(before[i].shape))
	if travel<0.000001:
		if _slow_timing_enabled: _timing_sample("resolve_pose",Time.get_ticks_usec()-timing_started)
		return {"blocked":false,"fraction":1.0,"contacts":[]}
	# No substep cap: large rotations must not tunnel between clear endpoints.
	var count:=maxi(1,int(ceil(travel/SWEEP_STEP)))
	var barrel_exclusions:=_exclusions(vehicle,false)
	var exclusions:=_with_ground_exclusions(vehicle,barrel_exclusions)
	var space:=vehicle.get_world_3d().direct_space_state
	var query:PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new()
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
			# Reset every item, including state left by the preceding cast/contact.
			var query_setup_started: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
			query.shape=item.shape;query.transform=item.transform
			query.collision_mask=CONTACT_MASK
			query.exclude=barrel_exclusions if item.barrel else exclusions
			query.margin=SWEEP_STEP*0.55
			query.motion=Vector3.ZERO
			query.collide_with_bodies=true;query.collide_with_areas=false
			if _slow_timing_enabled: _timing_sample("query_setup",Time.get_ticks_usec()-query_setup_started)
			var hits:=(_timed_intersect_shape(space,query,32) if _slow_timing_enabled else space.intersect_shape(query,32))
			query.transform=old_shapes[i].transform
			query.motion=(item.transform as Transform3D).origin-query.transform.origin
			var sweep:=(_timed_cast_motion(space,query) if _slow_timing_enabled else space.cast_motion(query)) if query.motion.length_squared()>0.000000000001 else PackedFloat32Array([1.0,1.0])
			if sweep.size()==2 and sweep[0]<1.0:
				query.transform.origin+=query.motion*minf(1.0,sweep[1]+0.001)
				query.motion=Vector3.ZERO
				hits.append_array((_timed_intersect_shape(space,query,32) if _slow_timing_enabled else space.intersect_shape(query,32)))
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
						for remaining in (_timed_intersect_shape(space,query,32) if _slow_timing_enabled else space.intersect_shape(query,32)):
							if remaining.collider==collider:cleared=false
				elif collider is Node and collider.has_meta("contact_tree"):
					cleared=_tree_contact(collider,contact_direction,speed,not item.barrel)
				if not cleared and not collider.has_method("receive_vehicle_contact"):
					cleared=_relieves_overlap(space,item,old_shapes[i],collider,query.exclude,query.margin)
				contacts.append({"collider":id,"barrel":item.barrel,"cleared":cleared,"path":str(collider.get_path()) if collider is Node else ""})
				if not cleared:
					_apply(vehicle,previous,desired,accepted)
					last_debug={"before":before,"requested":after,"accepted":_shape_pose(previous,desired,accepted),"contacts":contacts}
					if _slow_timing_enabled: _timing_sample("resolve_pose",Time.get_ticks_usec()-timing_started)
					return {"blocked":true,"fraction":accepted,"contacts":contacts}
		accepted=fraction;old_shapes=current
	# Desired pose is already installed by the caller; no physical rewrite needed.
	for id in encounters.keys():
		if not seen.has(id):encounters.erase(id)
	last_debug={"before":before,"requested":after,"accepted":desired.shapes,"contacts":contacts}
	if _slow_timing_enabled: _timing_sample("resolve_pose",Time.get_ticks_usec()-timing_started)
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
	var previous_hits:=(_timed_intersect_shape(space,query,64) if _slow_timing_enabled else space.intersect_shape(query,64))
	var was_overlapping:=false
	var isolate:Array[RID]=excluded.duplicate()
	for hit in previous_hits:
		if hit.collider==target:was_overlapping=true
		elif hit.collider is CollisionObject3D:isolate.append(hit.collider.get_rid())
	if not was_overlapping:return false
	query.transform=current.transform
	for hit in (_timed_intersect_shape(space,query,64) if _slow_timing_enabled else space.intersect_shape(query,64)):
		if hit.collider!=target and hit.collider is CollisionObject3D:isolate.append(hit.collider.get_rid())
	query.exclude=isolate;query.transform=old.transform
	var old_points: PackedVector3Array = (_timed_collide_shape(space,query,64) if _slow_timing_enabled else space.collide_shape(query,64))
	var before_depth:=_contact_depth(old_points)
	var old_transform:Transform3D=old.transform
	var new_transform:Transform3D=current.transform
	for index in range(0,old_points.size()-1,2):
		var normal: Vector3 = old_points[index]-old_points[index+1]
		var moved_point: Vector3 = new_transform*(old_transform.affine_inverse()*old_points[index])
		if (moved_point-old_points[index]).dot(normal)>0.0000001:return false
	query.transform=current.transform
	var after_depth:=_contact_depth((_timed_collide_shape(space,query,64) if _slow_timing_enabled else space.collide_shape(query,64)))
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
