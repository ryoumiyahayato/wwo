extends RefCounted
## Explicit, ephemeral LOCAL test load. Never participates in world or save data.

const PATH: String = "res://assets/landmarks/internal_preview_r41/shared_facilities.glb"
const TYPES: Array[String] = ["rail_goods_shed","engine_workshop","farm_granary","quarry_derrick"]
var enabled: bool = false
var _pending: bool = false
var _failed: bool = false
var _templates: Dictionary = {}
var _copies: Array[Dictionary] = []
var _prototypes: Array[MeshInstance3D] = []
var _composition: Array = []
var base_instances: int = 0
var extra_instances: int = 0
var _prototype_anchor := Vector3.ZERO

func preparing() -> bool:
	return _pending

func poll() -> bool:
	if not _pending: return false
	var status := ResourceLoader.load_threaded_get_status(PATH)
	if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	_pending = false
	if status!=ResourceLoader.THREAD_LOAD_LOADED:
		_failed = true
		return true
	var packed := ResourceLoader.load_threaded_get(PATH) as PackedScene
	if packed==null:
		_failed = true
		return true
	if not enabled: return true
	var root := packed.instantiate()
	for node: Node in root.get_children():
		if node is MeshInstance3D: _templates[str(node.name)] = (node as MeshInstance3D).mesh
	root.free() # Mesh resources are shared by this bounded composition.
	_composition.clear()
	return true

func update(view: RegionView, camera: RegionCamera, size: Vector2) -> void:
	if not enabled or not camera.local_active or view._landmark_root==null:
		clear()
		return
	var sources: Array[MultiMeshInstance3D] = []
	base_instances = 0
	for instance: Node3D in view._landmark_instances.values():
		if instance.visible: base_instances += 1
	for source: MultiMeshInstance3D in view._settlement_nodes.values():
		if source.visible and source.multimesh!=null: sources.append(source)
	for source: MultiMeshInstance3D in view._woodland_nodes:
		if source.visible and source.multimesh!=null: sources.append(source)
	var key: Array = [camera.local_place_id,view._local_surface_key,camera.km_per_pixel*1000.0<=4.0]
	for source: MultiMeshInstance3D in sources:
		base_instances += source.multimesh.instance_count
		key.append([source.get_instance_id(),source.multimesh.mesh.get_instance_id(),source.multimesh.instance_count])
	# Single monuments are not duplicated. The comparable extra tier is for
	# already populated city/woodland windows, not artificial heritage copies.
	if base_instances<8 or sources.is_empty():
		_clear_nodes()
		return
	if _templates.is_empty():
		if not _pending and not _failed:
			_pending = ResourceLoader.load_threaded_request(PATH,"PackedScene")==OK
		return
	if key!=_composition:
		_clear_nodes()
		_composition = key
		_prototype_anchor = camera.valid_anchor(size).unit as Vector3
		var budget := mini(128,maxi(4,roundi(base_instances*0.8)))
		var groups: Dictionary = {}
		for i: int in range(budget-4):
			var source := sources[i%sources.size()]
			var source_index := (i/sources.size())%source.multimesh.instance_count
			if not groups.has(source): groups[source] = []
			(groups[source] as Array).append(source_index)
		for source: MultiMeshInstance3D in groups:
			var indices := groups[source] as Array
			var node := MultiMeshInstance3D.new()
			node.name = "R41_TEST_INSTANCES_"+str(source.name)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.use_colors = source.multimesh.use_colors
			node.multimesh.mesh = source.multimesh.mesh
			node.multimesh.instance_count = indices.size()
			for i: int in range(indices.size()):
				var transform := source.multimesh.get_instance_transform(int(indices[i]))
				transform.origin += Vector3(22,0,-18)
				node.multimesh.set_instance_transform(i,transform)
				if node.multimesh.use_colors: node.multimesh.set_instance_color(i,source.multimesh.get_instance_color(int(indices[i])))
			view._landmark_root.add_child(node)
			_copies.append({"source":source,"node":node})
			extra_instances += indices.size()
		for type: String in TYPES:
			var node := MeshInstance3D.new()
			node.name = "R41_TEST_INSTANCE_"+type
			node.mesh = _templates[type+("_near" if bool(key[2]) else "_far")] as Mesh
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			view._landmark_root.add_child(node)
			_prototypes.append(node)
			extra_instances += 1
	for copy: Dictionary in _copies:
		(copy.node as MultiMeshInstance3D).transform = (copy.source as MultiMeshInstance3D).transform
	var unit := _prototype_anchor
	var common := view._chart_transform(unit,camera,size)
	var coordinates := RegionProjection.lon_lat(unit)
	var ground := view._surface_ground_y(coordinates) if view._surface_contains(coordinates) else 0.0
	var basis := view._geographic_basis(unit,camera,0.0)
	for i: int in range(_prototypes.size()):
		_prototypes[i].transform = common*Transform3D(basis,Vector3(-120+i*80,ground,110))

func render_bounds(view: RegionView) -> Rect2:
	var bounds := Rect2()
	var initialized := false
	var nodes: Array[GeometryInstance3D] = []
	for copy: Dictionary in _copies: nodes.append(copy.node as MultiMeshInstance3D)
	for node: MeshInstance3D in _prototypes: nodes.append(node)
	for node: GeometryInstance3D in nodes:
		for corner: int in range(8):
			var point := view._chart_pixel(node.transform*node.get_aabb().get_endpoint(corner))
			bounds = bounds.expand(point) if initialized else Rect2(point,Vector2.ZERO)
			initialized = true
	return bounds

func _clear_nodes() -> void:
	for copy: Dictionary in _copies:
		var node := copy.node as MultiMeshInstance3D
		node.visible = false
		node.multimesh = null
		node.queue_free()
	for node: MeshInstance3D in _prototypes:
		node.visible = false
		node.mesh = null
		node.queue_free()
	_copies.clear()
	_prototypes.clear()
	_composition.clear()
	extra_instances = 0

func clear() -> void:
	_clear_nodes()
	_templates.clear()
	base_instances = 0
