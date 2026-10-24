extends SceneTree
## One offline Crete shard. No gameplay scene, viewport, clock or save access.

func _init() -> void:
	call_deferred("_compile")

func _compile() -> void:
	var provenance := HistoricalProvenanceFoundation.new()
	if not provenance.load_current(): push_error(provenance.initialization_error); quit(1); return
	var geography := GeographyLoader.new()
	if not geography.load_current(provenance.gate()): push_error(str(geography.errors)); quit(1); return
	var geometry := MapGeometryContent.new(geography.parts_by_feature,geography.presentation)
	var frames: Dictionary = {}
	for id: String in geometry.feature_ids():
		var source := GlobeProjection.source_reference(geometry.parts(id),id)
		frames[id] = {"frame":source.uv_bounds,"flag":source.flag_bounds,"components":source.parts}
	var errors: Array[String] = []
	var regions := ContentDocument.read(HistoricalLoader.REGIONS_PATH,errors)
	for region: Dictionary in regions.get("political_map_regions",[]) as Array:
		var f := region.flag_frame as Array
		frames[str(region.id)] = Rect2(Vector2(float(f[0]),float(f[1])),Vector2(float(f[2])-float(f[0]),float(f[3])-float(f[1])))
	var index := ContentDocument.read(StrategicSpatialLoader.INDEX_PATH,errors)
	var descriptor := ContentDocument.read("res://local-artifacts/terrain-r56/coast/descriptor.json",errors)
	if not errors.is_empty(): push_error(str(errors)); quit(1); return
	var content := StrategicSpatialLoader._load(index,[descriptor],Callable(),null,true)
	if not content.errors.is_empty() or not (content.metadata.get("optional_errors",[]) as Array).is_empty():
		push_error(str(content.errors)+str(content.metadata.get("optional_errors",[]))); quit(1); return
	var prepared := LocalSpatialLod.prepare(content,["medium"],Callable(),frames)
	if prepared.has("error"): push_error(str(prepared.error)); quit(1); return
	var chunks := prepared.chunks as Array
	var faces := 0
	for chunk: Dictionary in chunks: faces += int(chunk.get("face_count",0))
	var path := "res://data/strategic/physical_2_4_mid_1_0_r56.display"
	var source_path := "res://data/strategic/physical_2_4_mid_1_0_r56.geom"
	var file := FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_DEFLATE)
	if file==null: push_error(error_string(FileAccess.get_open_error())); quit(1); return
	file.store_var({"schema_id":"physical_political_display_r37","physical_shard_id":descriptor.id,"lod":"medium","bounds":descriptor.bounds,"role":"DISPLAY_ONLY_NOT_SOVEREIGNTY","component_uv":true,"source_geometry":source_path,"source_ink":descriptor.ink_asset,"chunks":chunks})
	file.close()
	descriptor["compiled_asset"] = {"path":path,"encoding":"GODOT_COMPRESSED_VARIANT_R37","bytes":FileAccess.get_file_as_bytes(path).size(),"faces":faces,"batches":chunks.size(),"source_geometry":source_path}
	var result := StrategicSpatialLoader.read_display(descriptor.compiled_asset,str(descriptor.id),"medium")
	if result.has("error"): push_error(str(result.error)); quit(1); return
	var out := FileAccess.open("res://local-artifacts/terrain-r56/coast/descriptor.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(descriptor,"\t")); out.close()
	for parent: Dictionary in index.coast_regions as Array:
		var children := parent.medium_regions as Array
		for i: int in range(children.size()):
			if str((children[i] as Dictionary).id)==str(descriptor.id): children[i] = descriptor
	var total_faces := 0
	var total_batches := 0
	var total_bytes := 0
	var count := 0
	for parent: Dictionary in index.coast_regions as Array:
		var descriptors: Array = [parent]
		descriptors.append_array(parent.medium_regions as Array)
		for row: Dictionary in descriptors:
			var asset := row.compiled_asset as Dictionary
			total_faces += int(asset.faces)
			total_batches += int(asset.batches)
			total_bytes += int(asset.bytes)
			count += 1
	index.prepared_political_display.merge({"files":count,"faces":total_faces,"batches":total_batches,"bytes":total_bytes,"r56_finite_update":"Crete medium only; matching physical query/fill/coast; GSHHG2.3.7 LGPL3-or-later with original CShapes notices"},true)
	out = FileAccess.open(StrategicSpatialLoader.INDEX_PATH,FileAccess.WRITE)
	out.store_string(JSON.stringify(index)); out.close()
	print("R56 single Crete shard faces=",faces," batches=",chunks.size()," bytes=",descriptor.compiled_asset.bytes)
	quit(0)
