extends SceneTree
## Offline asset compiler, invoked by build_geographic_foundation.py.
## No game scene, simulation, viewport, user data or save slot is created.

func _init() -> void:
	call_deferred("_compile")

func _compile() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "res://local-artifacts/political-display-r37"
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create display output: "+output); quit(1); return
	var provenance := HistoricalProvenanceFoundation.new()
	if not provenance.load_current():
		push_error(provenance.initialization_error); quit(1); return
	var geography := GeographyLoader.new()
	if not geography.load_current(provenance.gate()):
		push_error("; ".join(geography.errors)); quit(1); return
	var geometry := MapGeometryContent.new(geography.parts_by_feature,geography.presentation)
	var frames: Dictionary = {}
	var query_meshes: Dictionary = {}
	for id: String in geometry.feature_ids():
		var source := GlobeProjection.source_reference(geometry.parts(id),id)
		query_meshes[id] = source
		frames[id] = {"frame":source.uv_bounds,"flag":source.flag_bounds,"components":source.parts}
	var errors: Array[String] = []
	var regions := ContentDocument.read(HistoricalLoader.REGIONS_PATH,errors)
	if not errors.is_empty(): push_error("; ".join(errors)); quit(1); return
	for region: Dictionary in regions.get("political_map_regions",[]) as Array:
		var f := region.flag_frame as Array
		frames[str(region.id)] = Rect2(Vector2(float(f[0]),float(f[1])),Vector2(float(f[2])-float(f[0]),float(f[3])-float(f[1])))
	var index := ContentDocument.read(StrategicSpatialLoader.INDEX_PATH,errors)
	var descriptors: Array[Dictionary] = []
	for parent: Dictionary in index.coast_regions as Array:
		descriptors.append(parent)
		for child: Dictionary in parent.get("medium_regions",[]) as Array: descriptors.append(child)
	var total_faces := 0
	var total_batches := 0
	var total_bytes := 0
	var entries: Array[Dictionary] = []
	for descriptor: Dictionary in descriptors:
		if args.size()>1 and str(descriptor.id) not in args.slice(1): continue
		# Always compile from the existing original derivatives, even on rerun.
		var raw := descriptor.duplicate()
		raw.erase("compiled_asset")
		var sources: Array[Dictionary] = [raw]
		var content := StrategicSpatialLoader._load(index,sources,Callable(),null,true)
		if not content.errors.is_empty() or not (content.metadata.get("optional_errors",[]) as Array).is_empty():
			push_error(str(descriptor.id)+": "+str(content.errors)+str(content.metadata.get("optional_errors",[]))); quit(1); return
		var lods: Array[String] = [str(descriptor.lod)]
		var prepared := LocalSpatialLod.prepare(content,lods,Callable(),frames)
		if prepared.has("error"):
			push_error(str(descriptor.id)+": "+str(prepared.error)); quit(1); return
		var chunks := prepared.chunks as Array
		if args.size()>1: chunks = chunks.filter(func(c: Dictionary) -> bool: return str(c.kind) in ["land_reference","coast"])
		var faces := 0
		for chunk: Dictionary in chunks: faces += int(chunk.get("face_count",0))
		var name := str(descriptor.id)+".display"
		var path := output.path_join(name)
		var file := FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_DEFLATE)
		if file==null: push_error("Cannot write "+path); quit(1); return
		var source_geometry := str(descriptor.path).get_base_dir().path_join(str(descriptor.id)+".geom")
		file.store_var({"schema_id":"physical_political_display_r37","physical_shard_id":descriptor.id,"lod":descriptor.lod,"bounds":descriptor.bounds,"role":"DISPLAY_ONLY_NOT_SOVEREIGNTY","component_uv":true,"source_geometry":source_geometry,"source_document":descriptor.path,"source_ink":descriptor.get("ink_asset",{}),"chunks":chunks})
		file.close()
		var size := FileAccess.get_file_as_bytes(path).size()
		descriptor["compiled_asset"] = {"path":output.path_join(name) if args.size()>1 else "res://data/strategic/"+name,"encoding":"GODOT_COMPRESSED_VARIANT_R37","source_geometry":source_geometry,"bytes":size,"faces":faces,"batches":chunks.size()}
		entries.append({"id":descriptor.id,"file":name,"bytes":size,"faces":faces,"batches":chunks.size(),"lod":descriptor.lod})
		total_faces += faces
		total_batches += chunks.size()
		total_bytes += size
		print("Compiled ",descriptor.id," faces=",faces," batches=",chunks.size()," bytes=",size)
	if args.size()>1:
		for field: String in ["bytes","faces","batches"]:
			var total := 0
			for descriptor: Dictionary in descriptors: total+=int((descriptor.get("compiled_asset",{}) as Dictionary).get(field,0))
			index.prepared_political_display[field]=total
		var selected_index := FileAccess.open(output.path_join("index.json"),FileAccess.WRITE)
		selected_index.store_string(JSON.stringify(index)); selected_index.close()
		print("SELECTED_COMPLETE files=",entries.size()," faces=",total_faces," bytes=",total_bytes)
		quit(0); return
	index["prepared_political_display"] = {"schema_id":"physical_political_display_r37","date":"1900-01-01","method":"Existing R27 physical/ink partition; original connected historical polygon UV; unchanged 2-degree spherical subdivision and native face/boundary encoder; bounded runtime LOD selection.","source":"Natural Earth 5.1.2 modern physical reference + existing 1900 CShapes/Arabia display intersections","license":"Physical Natural Earth public domain; CShapes derivatives CC BY-NC-SA 4.0; existing source notices remain applicable.","generator":"tools/map/build_geographic_foundation.py --compile-display --apply --godot <Godot 4.6.3 console>","files":entries.size(),"bytes":total_bytes,"faces":total_faces,"batches":total_batches}
	var query_path := output.path_join("historical_reference_1900.display")
	var query_file := FileAccess.open_compressed(query_path,FileAccess.WRITE,FileAccess.COMPRESSION_DEFLATE)
	if query_file==null: push_error("Cannot write "+query_path); quit(1); return
	# Native Variant serialization does not preserve shared packed-array
	# references. Store component borders once; runtime rejoins their lists.
	for reference: Dictionary in query_meshes.values(): reference.erase("borders")
	query_file.store_var({"schema_id":"historical_query_display_r37","role":"HISTORICAL_QUERY_AND_BORDER_ONLY_NOT_CURRENT_SOVEREIGNTY","source_paths":["res://data/world_map/historical/cshapes_1900_snapshot.json","res://data/world_map/historical/arabia_gulf_geography_1900.json"],"meshes":query_meshes})
	query_file.close()
	index.prepared_political_display["historical_query_bytes"] = FileAccess.get_file_as_bytes(query_path).size()
	var out_index := FileAccess.open(output.path_join("index.json"),FileAccess.WRITE)
	out_index.store_string(JSON.stringify(index)); out_index.close()
	var manifest := FileAccess.open(output.path_join("political_display_r37.json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"metadata":index.prepared_political_display,"assets":entries})); manifest.close()
	print("COMPLETE files=",entries.size()," faces=",total_faces," batches=",total_batches," bytes=",total_bytes)
	quit(0)
