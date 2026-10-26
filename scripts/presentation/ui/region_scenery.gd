extends Node3D
## Read-only military art, adapted from ridgevale/world.gd and continuous/region_world.gd.
## No combatants, inventory, town identities or official ownership are created.
signal changed
var terrain: Node3D
var base_path := "res://assets/terrain/region_slice/"
var _native_document: Dictionary = {}
var _region_document: Dictionary = {}
var _pending: Dictionary = {}
var _native := Node3D.new()
var _native_ready := false
var _native_wanted := false
var _groups: Dictionary = {}
var _materials: Dictionary = {}
var _center := Vector2.ZERO
var _span := 50000.0
var _collisions: Dictionary = {}

func begin(source: Node3D) -> void:
	terrain=source
	var native: Variant=JSON.parse_string(FileAccess.get_file_as_string(base_path+"ridgevale/assets/map.json"))
	var broad: Variant=JSON.parse_string(FileAccess.get_file_as_string(base_path+"continuous/assets/region.json"))
	if not native is Dictionary or not broad is Dictionary: return
	_native_document=native as Dictionary
	_region_document=broad as Dictionary
	add_child(_native)
	_native.hide()
	_build_region_water()
	_build_region_roads()

func update_view(center: Vector2, span: float) -> void:
	_center=center
	_span=span
	_native_wanted=span<8500
	_native.visible=_native_wanted
	for child: Node in get_children():
		if child.has_meta("regional_only"): (child as Node3D).visible=not _native_wanted
	if _native_wanted and not _native_ready:
		_native_ready=true
		for row: Dictionary in _native_document.get("placements",[]):
			var kind:=str(row.kind)
			if not _groups.has(kind): _groups[kind]=[]
			(_groups[kind] as Array).append(row)
		for kind: String in _groups:
			var path:=base_path+"cedar/assets/"+kind+".glb"
			if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path)==OK:
				_pending[kind]=path
	set_process(not _pending.is_empty())
	_sync_collisions()

func _process(_delta: float) -> void:
	# Install one small original asset group per frame, not a world of objects on click.
	for kind: String in _pending.keys():
		var path:=str(_pending[kind])
		var status:=ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_FAILED or status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.erase(kind)
			continue
		if status!=ResourceLoader.THREAD_LOAD_LOADED: continue
		var packed:=ResourceLoader.load_threaded_get(path) as PackedScene
		_pending.erase(kind)
		if packed!=null: _install_group(kind,packed)
		changed.emit()
		break
	if _pending.is_empty(): set_process(false)

func _install_group(kind: String, packed: PackedScene) -> void:
	var prototype:=packed.instantiate() as Node3D
	if prototype==null: return
	var meshes:=prototype.find_children("*","MeshInstance3D",true,false)
	if prototype is MeshInstance3D: meshes.append(prototype)
	for item: Node in meshes:
		var mesh_node:=item as MeshInstance3D
		if mesh_node.mesh==null: continue
		var transform_in_asset:=Transform3D.IDENTITY
		var cursor: Node3D=mesh_node
		while cursor!=null:
			transform_in_asset=cursor.transform*transform_in_asset
			if cursor==prototype: break
			cursor=cursor.get_parent() as Node3D
		var batches: Dictionary={}
		for row: Dictionary in _groups[kind]:
			var p: Array=row.position
			var position:=Vector3(float(p[0]),0,float(p[2]))
			position.y=float(terrain.call("sample_height",position.x,position.z))
			if not is_finite(position.y): continue
			var key:=Vector2i(floori(position.x/250),floori(position.z/250))
			if not batches.has(key): batches[key]=[]
			var pose:=Transform3D(Basis(Vector3.UP,float(row.yaw)).scaled(Vector3.ONE*float(row.scale)),position)
			(batches[key] as Array).append(pose*transform_in_asset)
		for key: Vector2i in batches:
			var multi:=MultiMesh.new()
			multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=mesh_node.mesh
			multi.instance_count=(batches[key] as Array).size()
			for i: int in range(multi.instance_count): multi.set_instance_transform(i,batches[key][i])
			var visual:=MultiMeshInstance3D.new()
			visual.multimesh=multi
			visual.material_override=_art_material()
			visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			visual.visibility_range_end=1800 if kind.begins_with("tree") else 7000
			_native.add_child(visual)
	prototype.free()

func _art_material() -> StandardMaterial3D:
	if _materials.has("art"): return _materials.art as StandardMaterial3D
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=0.95
	_materials.art=material
	return material

func _flat_material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=0.97
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return material

func _ribbon(points: PackedVector3Array, width: float, color: Color) -> void:
	if points.size()<2: return
	var vertices:=PackedVector3Array()
	var indices:=PackedInt32Array()
	var normals:=PackedVector3Array()
	for i: int in range(points.size()):
		var tangent:=points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
		var side:=Vector3(-tangent.z,0,tangent.x).normalized()*width*0.5
		vertices.append(points[i]-side)
		vertices.append(points[i]+side)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if i>0:
			var a: int=(i-1)*2
			indices.append_array([a,a+1,a+2,a+1,a+3,a+2])
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance:=MeshInstance3D.new()
	instance.mesh=mesh
	instance.set_meta("regional_only",true)
	instance.material_override=_flat_material(color)
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _build_region_water() -> void:
	var points:=PackedVector3Array()
	for p: Array in _region_document.get("river",[]): points.append(Vector3(float(p[0]),float(p[1])+0.2,float(p[2])))
	_ribbon(points,80,Color("437c8b"))

func _build_region_roads() -> void:
	for road: Dictionary in _region_document.get("roads",[]):
		var points:=PackedVector3Array()
		for p: Array in road.points:
			var h:=float(terrain.call("sample_height",float(p[0]),float(p[1])))
			if is_finite(h): points.append(Vector3(float(p[0]),h+0.6,float(p[1])))
		_ribbon(points,12,Color("c1ab83"))

func _sync_collisions() -> void:
	# Buildings only in the immediate inspection neighbourhood; no per-tree physics.
	var wanted: Dictionary={}
	if _native_wanted and _span<250:
		for row: Dictionary in _native_document.get("placements",[]):
			var kind:=str(row.kind)
			if not kind.begins_with("house") and kind not in ["barn","chapel"]: continue
			var p: Array=row.position
			if Vector2(float(p[0]),float(p[2])).distance_to(_center)>100: continue
			wanted[str(row.id)]=true
			if _collisions.has(str(row.id)): continue
			var spec: Dictionary=(_native_document.get("colliders",{}) as Dictionary).get(kind,{}) as Dictionary
			var body:=StaticBody3D.new()
			body.collision_layer=1
			body.collision_mask=0
			body.position=Vector3(float(p[0]),float(terrain.call("sample_height",float(p[0]),float(p[2]))),float(p[2]))
			body.rotation.y=float(row.yaw)
			_native.add_child(body)
			for box: Dictionary in spec.get("boxes",[]): _box(body,box)
			if spec.get("shape","")=="box": _box(body,spec)
			_collisions[str(row.id)]=body
	for id: String in _collisions.keys():
		if not wanted.has(id):
			(_collisions[id] as Node).queue_free()
			_collisions.erase(id)

func _box(body: StaticBody3D, spec: Dictionary) -> void:
	var dimensions: Array=spec.get("size",[1,1,1])
	var offset: Array=spec.get("center",[0,0,0])
	var shape:=BoxShape3D.new()
	shape.size=Vector3(float(dimensions[0]),float(dimensions[1]),float(dimensions[2]))
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	collider.position=Vector3(float(offset[0]),float(offset[1]),float(offset[2]))
	body.add_child(collider)
