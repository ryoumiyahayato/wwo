extends SceneTree
## Offline ArrayMesh conversion. Not installed in a world or player scene.
const CityStorage = preload("res://scripts/presentation/map/city_surface_storage.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()==3 and args[0]=="--pack-ground":
		pack_ground(args[1],args[2])
		return
	if args.size()<2 or args.size()>3: quit(2); return
	var source := args[0]
	var output := args[1]
	var index: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("index.json")))
	var context := str(index.get("schema",""))=="national_cartographic_context_v1"
	var context_tiles: Dictionary={}
	var required: Dictionary={"overview":true}
	if context:
		for tile: Dictionary in (index.tiles as Dictionary).values():
			context_tiles[str(tile.name)]=tile;required[str(tile.name)]=true
		for tile: Dictionary in context_tiles.values():
			if not tile.has("texture_source") or (args.size()==3 and not str(tile.name).begins_with(args[2])): continue
			var image := Image.load_from_file(source.path_join(str(tile.texture_source)))
			if image==null or image.is_empty(): quit(5);return
			image.convert(Image.FORMAT_RG8 if bool(tile.get("street_print",false)) or bool(tile.get("woodland_mask",false)) else Image.FORMAT_R8)
			image.generate_mipmaps()
			var texture := ImageTexture.create_from_image(image)
			var b: Array=tile.bounds
			var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector2Array([Vector2(b[0],b[3]),Vector2(b[2],b[3]),Vector2(b[2],b[1]),Vector2(b[0],b[1])])
			arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)])
			arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.set_meta("building_print",texture)
			mesh.set_meta("resident_bytes",image.get_data_size()+128)
			if ResourceSaver.save(mesh,output.path_join(str(tile.name)+".res"),ResourceSaver.FLAG_COMPRESS)!=OK: quit(4);return
	for part: Dictionary in index.get("foundation",[]): required[str(part.path).get_file().get_basename()]=true
	for part: Dictionary in index.get("water_lods",{}).get("levels",[]): required[str(part.path).get_file().get_basename()]=true
	if not context:
		for tile: Dictionary in index.get("tiles",[]):
			for part: Dictionary in tile.lods.values(): required[str(part.path).get_file().get_basename()]=true
	var anchor := Vector2(float(index.anchor[0]),float(index.anchor[1]))
	var frame := RegionProjection.frame(anchor)
	var metres_per_degree := Vector2(111195.0*cos(deg_to_rad(anchor.y)),111195.0)
	for name: String in DirAccess.get_files_at(source):
		if not name.ends_with(".bin") or (args.size()==3 and not name.begins_with(args[2])): continue
		if name.begins_with("overview_") or not required.has(name.get_basename()): continue
		var tile: Dictionary=context_tiles.get(name.get_basename(),{})
		if context and (tile.is_empty() or tile.has("texture_source")): continue
		if context:
			anchor=Vector2(float(tile.anchor[0]),float(tile.anchor[1]))
			frame=RegionProjection.frame(anchor)
			metres_per_degree=Vector2(111195.0*cos(deg_to_rad(anchor.y)),111195.0)
		var file := FileAccess.open(source.path_join(name),FileAccess.READ)
		var version := file.get_buffer(8).get_string_from_ascii()
		if version not in ["CITYMSH1","CITYMSH2"]: quit(3); return
		var mesh := ArrayMesh.new()
		for surface: int in 2:
			var count := file.get_32()
			var indices := file.get_32()
			var positions := file.get_buffer(count*12).to_float32_array()
			var elements := file.get_buffer(indices*4).to_int32_array()
			var colors := file.get_buffer(count*16).to_float32_array() if version=="CITYMSH2" else PackedFloat32Array()
			if count==0: continue
			var vertices := PackedVector3Array();vertices.resize(count)
			var geographic := PackedVector2Array()
			if context: geographic.resize(count)
			for i: int in count:
				var ll := anchor+Vector2(positions[i*3],-positions[i*3+2])/metres_per_degree
				var chart := RegionProjection.forward(GlobeProjection.lon_lat_to_unit(ll),frame)*1000.0
				vertices[i]=Vector3(chart.x,positions[i*3+1],-chart.y)
				if context:
					geographic[i]=ll
			var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=geographic if context else vertices;arrays[Mesh.ARRAY_INDEX]=elements
			if not colors.is_empty():
				var tints := PackedColorArray();tints.resize(count)
				for i: int in count: tints[i]=Color(colors[i*4],colors[i*4+1],colors[i*4+2],colors[i*4+3])
				arrays[Mesh.ARRAY_COLOR]=tints
			# Native 16-bit position packing: <5cm quantisation per 3km tile,
			# below the 3m source-derived display grid. No normals are required.
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},0 if context else Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		var destination := output.path_join(name.get_basename()+".res")
		if ResourceSaver.save(mesh,destination,ResourceSaver.FLAG_COMPRESS)!=OK: quit(4);return
	print("City numeric meshes saved to ",output)
	quit()

func pack_ground(source: String, output: String) -> void:
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(6);return
	var paths: Array[String] = []
	var before := 0
	var after := 0
	var all := 0
	var times: Array[int] = []
	for name in DirAccess.get_files_at(source):
		if not name.begins_with("context_") or not name.ends_with(".res"): continue
		var path := source.path_join(name)
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null: quit(7);return
		var source_bytes := file.get_length()
		all+=source_bytes
		var mesh := ResourceLoader.load(path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if mesh==null or mesh.get_surface_count()!=1 or mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES: continue
		if mesh.surface_get_material(0)!=null or not mesh.get_meta_list().is_empty() or mesh.get_blend_shape_count()!=0 or not mesh.surface_get_lods(0).is_empty(): continue
		var arrays := mesh.surface_get_arrays(0)
		if not arrays[Mesh.ARRAY_VERTEX] is PackedVector2Array or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray or not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array: continue
		var encoded := CityStorage.encode(arrays)
		if encoded.is_empty() or encoded.size()>=source_bytes: continue
		var start := Time.get_ticks_usec()
		var decoded := CityStorage.decode(encoded)
		times.append(Time.get_ticks_usec()-start)
		if decoded!=arrays:
			printerr("Ground mesh differs after conversion: ",path)
			quit(8);return
		var dest := FileAccess.open(output.path_join(name.get_basename()+".ctm"),FileAccess.WRITE)
		if dest==null: quit(9);return
		dest.store_buffer(encoded)
		paths.append(name)
		before+=source_bytes
		after+=encoded.size()
	var manifest := FileAccess.open(output.path_join("ground.json"),FileAccess.WRITE)
	if manifest==null or paths.is_empty(): quit(10);return
	manifest.store_string(JSON.stringify({"schema":1,"tiles":paths},"\t")+"\n")
	times.sort()
	print("Ground tiles ",paths.size()," before ",before," after ",after," full ground ",all," median decode us ",times[times.size()/2]," p95 decode us ",times[floori(times.size()*.95)])
	quit()
