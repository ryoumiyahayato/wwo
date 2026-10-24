extends Node3D
const DIR := "res://continuous/assets/"
var document: Dictionary
var heights := PackedFloat32Array()
var far_tiles: Dictionary = {}
var mid_tiles: Dictionary = {}
var waiting: Dictionary = {}
var roads: Array[Dictionary] = []
var river_points := PackedVector3Array()
var towns: Array[Dictionary] = []
var focus := Vector2.ZERO
var span := 14.0
var loaded_mid := 0
var request_ms := 0.0
var maximum_install_ms := 0.0
var build_ms := 0
var _tick := 0.0
var ground_material: ShaderMaterial

func build() -> void:
	var begin := Time.get_ticks_msec()
	document=JSON.parse_string(FileAccess.get_file_as_string(DIR+"region.json"))
	heights=FileAccess.get_file_as_bytes(DIR+"height_50m.f32").to_float32_array()
	ground_material=ShaderMaterial.new();ground_material.shader=preload("res://continuous/ground.gdshader")
	ground_material.set_shader_parameter("region_color",load(DIR+"region_color.png"))
	ground_material.set_shader_parameter("region_normal",load(DIR+"region_normal.png"))
	ground_material.set_shader_parameter("grass_detail",load("res://cedar/assets/grass_detail.png"))
	for z: int in 10:
		for x: int in 10:
			var key:=Vector2i(x,z)
			var node: Node3D=load(DIR+"terrain_%d_%d_far.glb"%[x,z]).instantiate()
			add_child(node);_apply_ground(node);far_tiles[key]=node
	var apron: Node3D=load(DIR+"outer_apron.glb").instantiate();add_child(apron)
	_apply_ground(apron)
	for source: Dictionary in document.roads:
		var points:=PackedVector3Array()
		for p: Array in source.points: points.append(Vector3(p[0],height(p[0],p[1])+1,p[1]))
		roads.append({"id":source.id,"points":points,"source":source.source})
	for p: Array in document.river: river_points.append(Vector3(p[0],p[1]+.1,p[2]))
	for town: Dictionary in document.towns: towns.append(town)
	_build_water()
	_build_settlements()
	_build_forests()
	build_ms=Time.get_ticks_msec()-begin

func _apply_ground(node: Node) -> void:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		mesh.material_override=ground_material
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func height(x: float,z: float) -> float:
	var u:=clampf((x+22500)/50,0,999.99999)
	var v:=clampf((z+22500)/50,0,999.99999)
	var ix:=floori(u);var iz:=floori(v)
	var a:=u-ix;var b:=v-iz;var i:=iz*1001+ix
	return lerpf(lerpf(heights[i],heights[i+1],a),lerpf(heights[i+1001],heights[i+1002],a),b)

func _build_water() -> void:
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
	for i: int in river_points.size():
		var p:=river_points[i]
		vertices.append(p+Vector3(-40,0,0));vertices.append(p+Vector3(40,0,0))
		if i>0:
			var a: int=(i-1)*2
			indices.append_array([a,a+2,a+1,a+1,a+2,a+3])
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("527f89");material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var water:=MeshInstance3D.new();water.mesh=mesh;water.material_override=material;add_child(water)

func _build_settlements() -> void:
	# Sparse visual geometry, no bodies, inventories or combatants outside Ridgevale.
	var box:=BoxMesh.new();box.size=Vector3(18,12,24)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("baab82")
	var roof:=PrismMesh.new();roof.size=Vector3(21,8,28)
	var roof_material:=StandardMaterial3D.new();roof_material.albedo_color=Color("785e4d")
	var houses:=MultiMesh.new();houses.transform_format=MultiMesh.TRANSFORM_3D;houses.mesh=box;houses.instance_count=towns.size()*30
	var roofs:=MultiMesh.new();roofs.transform_format=MultiMesh.TRANSFORM_3D;roofs.mesh=roof;roofs.instance_count=towns.size()*30
	for t: int in towns.size():
		var town: Dictionary=towns[t]
		for i: int in 30:
			var p:=Vector3(float(town.position[0])+(i%6-2.5)*40,0,float(town.position[2])+(i/6-2)*43)
			p.y=height(p.x,p.z)
			houses.set_instance_transform(t*30+i,Transform3D(Basis.IDENTITY,p+Vector3(0,6,0)))
			roofs.set_instance_transform(t*30+i,Transform3D(Basis.IDENTITY,p+Vector3(0,16,0)))
	for pair: Array in [[houses,material],[roofs,roof_material]]:
		var instance:=MultiMeshInstance3D.new();instance.multimesh=pair[0];instance.material_override=pair[1];instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;instance.set_meta("settlement",true);add_child(instance)
	# A visible deck at the actual imported Rivergate bridge location. It is
	# observation geometry only; distant cells deliberately have no driving collider.
	var deck:=MeshInstance3D.new();var deck_mesh:=BoxMesh.new();deck_mesh.size=Vector3(101.4,2,12)
	deck.mesh=deck_mesh;deck.position=Vector3(4669.407,13.36,220);deck.material_override=roof_material;add_child(deck)

func _build_forests() -> void:
	var tree:=CylinderMesh.new();tree.top_radius=0;tree.bottom_radius=6;tree.height=23;tree.radial_segments=5
	var material:=StandardMaterial3D.new();material.albedo_color=Color("324c32")
	var rng:=RandomNumberGenerator.new();rng.seed=20261022
	var multimesh:=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.mesh=tree;multimesh.instance_count=document.forests.size()*350
	var i:=0
	for forest: Array in document.forests:
		for k: int in 350:
			var angle:=rng.randf()*TAU;var radius:=sqrt(rng.randf())
			var p:=Vector3(forest[0]+cos(angle)*radius*float(forest[2]),0,forest[1]+sin(angle)*radius*float(forest[3]))
			p.y=height(p.x,p.z)+11.5
			multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,p));i+=1
	var instance:=MultiMeshInstance3D.new();instance.multimesh=multimesh;instance.material_override=material;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;instance.set_meta("settlement",true);add_child(instance)

func update_view(center: Vector2, width: float) -> void:
	focus=center;span=width
	for key: Vector2i in far_tiles:
		var native: bool=key==Vector2i(4,4) and span<8500
		var tile_center:=Vector2(-20000+key.x*5000,-20000+key.y*5000)
		var needs_mid: bool=span<32000 and tile_center.distance_to(focus)<minf(12500,maxf(5500,span*.65)) and not native
		far_tiles[key].visible=not native and not mid_tiles.has(key)
		if not needs_mid and mid_tiles.has(key):
			mid_tiles[key].queue_free();mid_tiles.erase(key)
			far_tiles[key].visible=not native
		if needs_mid and not mid_tiles.has(key) and not waiting.has(key):
			var path:=DIR+"terrain_%d_%d_mid.glb"%[key.x,key.y]
			ResourceLoader.load_threaded_request(path)
			waiting[key]=path
	for key: Vector2i in mid_tiles:
		far_tiles[key].hide()
	loaded_mid=mid_tiles.size()
	for child: Node in get_children():
		if child.has_meta("settlement"): child.visible=span<32000

func _process(delta: float) -> void:
	_tick+=delta
	if _tick<.08: return
	_tick=0
	for key: Vector2i in waiting.keys():
		var path: String=waiting[key]
		if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED: continue
		var begin:=Time.get_ticks_usec()
		var packed: PackedScene=ResourceLoader.load_threaded_get(path)
		waiting.erase(key)
		var tile_center:=Vector2(-20000+key.x*5000,-20000+key.y*5000)
		if span>=32000 or tile_center.distance_to(focus)>=minf(12500,maxf(5500,span*.65)) or key==Vector2i(4,4) and span<8500: continue
		var instance:=packed.instantiate();add_child(instance);_apply_ground(instance);mid_tiles[key]=instance
		far_tiles[key].hide();loaded_mid=mid_tiles.size()
		maximum_install_ms=maxf(maximum_install_ms,(Time.get_ticks_usec()-begin)/1000.0)
		break
