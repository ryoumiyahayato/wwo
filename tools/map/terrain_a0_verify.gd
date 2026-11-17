extends SceneTree
var Codec: Variant
var root_dir := "res://local-artifacts/terrain-a0-20261027/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--layer-flow" in arguments:
		_layer_flow(arguments[arguments.find("--layer-flow")+1],"--single-query" in arguments)
		return
	if "--pack-smoke" in arguments:
		_pack_smoke(arguments[arguments.find("--pack-smoke")+1])
		return
	if "--batch" in arguments:
		_verify_batch(arguments[arguments.find("--batch")+1],arguments[arguments.find("--packed")+1] if "--packed" in arguments else "")
		return
	Codec = load("res://tools/map/terrain_a0_codec.gd")
	var results: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root_dir+"results.json")) as Dictionary
	var selected := arguments[0] if arguments.size()>0 else ""
	var method_filter := arguments[1] if arguments.size()>1 else ""
	if selected=="guards":
		_format_guards(results)
		quit()
		return
	var rows: Array[Dictionary] = []
	for sample: Dictionary in results.samples:
		var a: Dictionary = sample.asset
		var name := str(a.id).get_slice(":",1)
		if not selected.is_empty() and selected!=name: continue
		var reference: Image
		if selected.is_empty():
			var reference_result := GeographyLoader.decode_relief(name,{name:a})
			assert(reference_result.has("image"),str(reference_result))
			reference=reference_result.image
		for method: String in ["original","zstd6","mip_png6","flat_png6","delta_planar_zstd6","flat_webp"]:
			if not method_filter.is_empty() and method!=method_filter: continue
			if method!="original" and not sample.candidates.has(method): continue
			if method!="original" and not (sample.candidates[method] as Dictionary).has("path"): continue
			var path := str(a.path) if method=="original" else str(sample.candidates[method].path)
			var bytes := FileAccess.get_file_as_bytes(path)
			var times: Array[int] = []
			var decoded: Image
			print("A0_BEGIN ",name," ",method," static=",OS.get_static_memory_usage())
			if not selected.is_empty(): await create_timer(.08).timeout
			for repetition: int in range(3 if method!="delta_planar_zstd6" else 1):
				decoded=null
				var began := Time.get_ticks_usec()
				if method=="original":
					if str(a.format)=="RGBA8_MIP_DEFLATE":
						var raw := bytes.slice(20).decompress(int(a.decoded_bytes),FileAccess.COMPRESSION_DEFLATE)
						decoded=Image.create_from_data(int(a.width),int(a.height),true,Image.FORMAT_RGBA8,raw)
					else:
						decoded=Image.new();assert(decoded.load_png_from_buffer(bytes)==OK)
						decoded.convert(Image.FORMAT_RG8 if str(a.format)=="RG8" else Image.FORMAT_R8)
				else:
					var result: Dictionary = GeographyLoader._decode_lossless_surface(bytes,a) if method in ["zstd6","flat_webp"] and str(a.format)=="RGBA8_MIP_DEFLATE" else Codec.decode(bytes)
					assert(result.has("image"),name+" "+method+" "+str(result))
					decoded=result.image
				times.append(Time.get_ticks_usec()-began)
			if not selected.is_empty():
				print("A0_MEASURE_END")
				var reference_result := GeographyLoader.decode_relief(name,{name:a})
				assert(reference_result.has("image"),str(reference_result))
				reference=reference_result.image
			var equal := decoded.get_data()==reference.get_data() and decoded.get_format()==reference.get_format() and decoded.has_mipmaps()==reference.has_mipmaps()
			assert(equal,name+" "+method+" byte mismatch")
			var row := {"id":name,"method":method,"us":times,"equal":equal,"raw_bytes":decoded.get_data().size(),"static_bytes_after":OS.get_static_memory_usage()}
			rows.append(row);print("A0_END ",JSON.stringify(row))
			decoded=null
	var output := root_dir+"godot-decode.json" if selected.is_empty() else root_dir+"profile-"+selected+"-"+method_filter+".json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("A0_GODOT_DONE ",rows.size())
	quit()

func _layer_flow(output: String, single_query: bool) -> void:
	# Isolate the production picking/publication calls, not a second renderer.
	# Actual admitted Paris features; GPU batches deliberately absent here.
	var content := LocalSpatialLoader._load(LocalSpatialLoader.PARIS_PATH,func() -> bool: return true)
	assert(content.errors.is_empty(),str(content.errors))
	var controller := GlobeController.new()
	var layer := LocalSpatialLayer.new()
	layer._content = content
	layer.strategic = true
	layer._resident = true
	layer.available_lods = {"coarse":true,"medium":true,"local":true}
	for feature: Dictionary in content.features:
		if str(feature.kind) in ["settlement","landmark","geographic_region"]:
			layer._labels.append({"feature":feature,"km":Vector2.ZERO,"projected":false})
	var counts := {"symbol_limit":0}
	layer.symbol_limit = func(_feature: Dictionary,_id: String) -> float:
		counts.symbol_limit += 1
		return 100000.0
	var viewport := Vector2(1280,720)
	var center := GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566))
	var world_view := {"center":viewport*.5,"radius":300.0,"mpp":4500.0,"display_lod":"coarse"}
	var cases: Array[Dictionary] = []
	for mode: String in ["world","region","local","expired","suppressed","selected"]:
		controller.region_camera.active = mode!="world"
		if mode!="world": controller.focus_region(center,viewport*.5,.1,.32,viewport)
		controller.region_camera.local_active = mode=="local"
		layer.local_projection = controller.region_camera.project
		var date := "2000-01-01" if mode=="expired" else "1900-01-01"
		layer.suppressed_places.clear()
		if mode=="suppressed" and not layer._labels.is_empty(): layer.suppressed_places[str(layer._labels[0].feature.id)] = true
		controller.selected_place_id = str(layer._labels[0].feature.id) if mode=="selected" and not layer._labels.is_empty() else ""
		counts.symbol_limit = 0
		var times: Array[int] = []
		for iteration: int in range(60):
			controller.region_camera.origin += Vector2(.125,-.0625)
			var began := Time.get_ticks_usec()
			layer.update(controller.region_camera,controller,date,viewport,false,world_view)
			var before := layer.visible_places.duplicate()
			if single_query: layer.call("update",controller.region_camera,controller,date,viewport,true,world_view,false)
			else: layer.update(controller.region_camera,controller,date,viewport,true,world_view)
			assert(before==layer.visible_places,"Publication changed already prepared picking positions")
			times.append(Time.get_ticks_usec()-began)
		cases.append({"mode":mode,"symbol_limit_calls":counts.symbol_limit,"us":times,"points":var_to_str(layer.visible_places),"lod":layer.active_lod})
	var result := {"single_query":single_query,"labels":layer._labels.size(),"cases":cases,"gpu_batches":0}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	controller.free()
	print("A0_LAYER_FLOW_OK labels=",layer._labels.size()," cases=",cases.size()," single_query=",single_query)
	quit()

func _pack_smoke(manifest_path: String) -> void:
	# Run this existing verifier outside --main-pack: dependencies must resolve
	# from the normal current export, not from the source project or old R59.
	var application := load("res://scripts/formal/formal_world_application.gd") as GDScript
	var presenter := load("res://scripts/presentation/formal_world_presenter.gd") as GDScript
	var shell := load("res://scripts/presentation/ui/main_shell.gd") as GDScript
	if not application.can_instantiate() or not shell.can_instantiate() or not presenter.can_instantiate():
		push_error("Current pack scripts cannot compile/instantiate")
		quit(1)
		return
	var methods: Dictionary = {}
	for method: Dictionary in application.get_script_method_list(): methods[str(method.name)] = true
	assert(methods.has("_refresh_dossier") and methods.has("_native_economy_mode"),"Current formal assembly interfaces missing")
	var prepared_return := false
	for method: Dictionary in presenter.get_script_method_list():
		if method.name=="refresh_ui": prepared_return = int((method.get("return",{}) as Dictionary).get("type",-1))==TYPE_DICTIONARY
	assert(prepared_return,"Old Presenter was exported")
	assert((shell.get_script_constant_map().get("Menu",{}) as Dictionary).size()==5,"Current menu ownership missing")
	var assets: Dictionary = {}
	for name: String in ["france","british","german","spain","canary","benelux","europe","siberian","asian","northern","arid","european","sampling"]:
		var admitted := GeographyLoader.decode_relief(name+"_catalog",{})
		assert((admitted.get("errors",[]) as Array).is_empty(),str(admitted))
		for asset: Dictionary in (admitted.assets as Dictionary).values(): assets[str(asset.path)] = asset
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) as Dictionary
	var sampled: Dictionary = {}
	for row: Dictionary in manifest.files:
		var asset: Dictionary = assets[str(row.asset.path)]
		assert(_packed_storage_matches(asset,row),"Packed catalogue storage mismatch")
		var format := str(asset.format)
		if sampled.has(format): continue
		var image := GeographyLoader.decode_relief("sample",{"sample":asset})
		assert(image.has("image"),str(image))
		sampled[format] = true
	for level: String in ["world","native_paris"]:
		var png := GeographyLoader.decode_relief(level,{})
		assert(png.has("image"),"Original PNG compatibility missing: "+level)
	var context: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/local/zermatt_west_physical_reference.json")) as Dictionary).metadata.surface_presentation.context_height_asset
	assert(GeographyLoader.decode_relief("legacy",{"legacy":context}).has("image"),"Legacy LOCAL missing")
	assert((load("res://scenes/formal/formal_world_main.tscn") as PackedScene)!=null,"Current formal scene missing")
	print("A0_CURRENT_PACK_SMOKE_OK storage_records=",manifest.files.size()," sampled_formats=",sampled.keys()," current_assembly_presenter_menu=true")
	quit()

func _packed_storage_matches(asset: Dictionary, row: Dictionary) -> bool:
	if asset.format == "RGBA8_MIP_WWOCM2" and row.chosen_format == "RGBA8_MIP_FRA0":
		var file := FileAccess.open(str(asset.path),FileAccess.READ)
		return file != null and file.get_length() == int(asset.bytes)
	return asset.format == row.chosen_format and int(asset.bytes) == int(row.chosen_bytes)

func _verify_batch(manifest_path: String, packed_path: String = "") -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) as Dictionary
	var packed_assets: Dictionary = {}
	var source_root := str(document.baseline).replace("\\","/").get_base_dir().get_base_dir().get_base_dir()
	if not packed_path.is_empty():
		if not ProjectSettings.load_resource_pack(packed_path,true):
			push_error("Cannot mount actual replacement PCK")
			quit(1)
			return
		for catalogue: String in ["france","british","german","spain","canary","benelux","europe","siberian","asian","northern","arid","european","sampling"]:
			var admitted := GeographyLoader.decode_relief(catalogue+"_catalog",{})
			if not admitted.get("errors",[]).is_empty():
				push_error("Packed catalogue admission failed: "+catalogue+" "+str(admitted.errors))
				quit(1)
				return
			for asset: Dictionary in (admitted.assets as Dictionary).values():
				packed_assets[str(asset.path)] = asset
	var rows: Array[Dictionary] = []
	for row: Dictionary in document.files:
		var asset: Dictionary = row.asset
		var id := str(asset.id).get_slice(":",1)
		var reference_asset: Dictionary = asset.duplicate()
		var chosen: Dictionary = asset.duplicate()
		if packed_path.is_empty():
			chosen["format"] = row.chosen_format
			chosen["path"] = "res://"+str(row.candidate_path)
		else:
			if not packed_assets.has(str(asset.path)):
				push_error("Actual packed catalogue lacks asset: "+id)
				quit(1)
				return
			chosen = (packed_assets[str(asset.path)] as Dictionary).duplicate()
			for key: String in asset:
				if key not in ["format","bytes"] and chosen.get(key)!=asset[key]:
					push_error("Packed geographic contract changed: "+id+" "+key)
					quit(1)
					return
			if not _packed_storage_matches(chosen,row):
				push_error("Actual packed metadata did not select encoding: "+id)
				quit(1)
				return
			reference_asset["path"] = source_root.path_join(str(asset.path).trim_prefix("res://"))
		var source_times: Array[int] = []
		var candidate_times: Array[int] = []
		var reference: Dictionary
		var candidate: Dictionary
		for repetition: int in range(3 if int(asset.decoded_bytes)>=16777216 else 1):
			var began := Time.get_ticks_usec()
			reference = GeographyLoader.decode_relief(id,{id:reference_asset})
			source_times.append(Time.get_ticks_usec()-began)
			began = Time.get_ticks_usec()
			candidate = GeographyLoader.decode_relief(id,{id:chosen})
			candidate_times.append(Time.get_ticks_usec()-began)
		source_times.sort()
		candidate_times.sort()
		var source_us := source_times[source_times.size()/2]
		var candidate_us := candidate_times[candidate_times.size()/2]
		if not reference.has("image") or not candidate.has("image"):
			push_error("Batch resource decode failed: "+id+" "+str(reference.get("errors",[]))+" "+str(candidate.get("errors",[])))
			quit(1)
			return
		var original_image: Image = reference.image
		var candidate_image: Image = candidate.image
		var equal := original_image.get_data()==candidate_image.get_data() and original_image.get_format()==candidate_image.get_format() and original_image.get_size()==candidate_image.get_size() and original_image.get_mipmap_count()==candidate_image.get_mipmap_count()
		if not equal:
			push_error("Batch full RGBA/Mip mismatch: "+id)
			quit(1)
			return
		rows.append({"id":id,"category":row.category,"format":row.chosen_format,"source_us":source_us,"candidate_us":candidate_us,"full_bytes_equal":equal,"raw_bytes":original_image.get_data().size(),"mip_levels":original_image.get_mipmap_count()+1})
		if rows.size()%25==0:
			print("A0_BATCH_VERIFIED ",rows.size())
	if not packed_path.is_empty():
		var local: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/local/zermatt_west_physical_reference.json")) as Dictionary
		var context: Dictionary = local.metadata.surface_presentation.context_height_asset
		var legacy := GeographyLoader.decode_relief("local_context",{"local_context":context})
		if str(context.path)!="res://assets/maps/relief/france_r42_46_+6.bin" or str(context.format)!="RGBA8_MIP_DEFLATE" or not legacy.has("image") or (legacy.image as Image).get_data().size()!=6313256:
			push_error("Actual packed LOCAL legacy height dependency failed")
			quit(1)
			return
		print("A0_PACKED_CATALOGUES_AND_LOCAL_OK")
	var output := manifest_path.get_base_dir().path_join("godot-batch-decode.json" if packed_path.is_empty() else "godot-packed-decode.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("A0_BATCH_GODOT_DONE ",rows.size()," full_rgba_and_mips=true packed=",not packed_path.is_empty())
	quit()


func _format_guards(results: Dictionary) -> void:
	var first: Dictionary = results.samples[0]
	var bytes := FileAccess.get_file_as_bytes(str(first.candidates.zstd6.path))
	var rejected := 0
	for kind: int in range(8):
		var bad := bytes.duplicate()
		if kind==0: bad.resize(27)
		elif kind==1: bad[0]=0
		elif kind==2: bad[8]=2
		elif kind==3: bad[9]=4
		elif kind==4: bad.encode_u16(10,1024)
		elif kind==5: bad.encode_u32(12,int(first.asset.width)+1)
		elif kind==6: bad.encode_u32(20,int(first.asset.decoded_bytes)-4)
		else: bad.encode_u32(24,0)
		assert(not GeographyLoader._decode_lossless_surface(bad,first.asset).has("image"),"Unsafe header accepted")
		rejected+=1
	var local: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/local/zermatt_west_physical_reference.json")) as Dictionary
	var context: Dictionary = local.metadata.surface_presentation.context_height_asset
	var original := GeographyLoader.decode_relief("local_context",{"local_context":context})
	assert(original.has("image") and (original.image as Image).get_data().size()==6313256,"Legacy LOCAL dependency failed")
	FileAccess.open(root_dir+"format-guards.json",FileAccess.WRITE).store_string(JSON.stringify({"malformed_headers_rejected":rejected,"legacy_zermatt_context_decoded":true},"\t"))
	print("A0_GUARDS_DONE ",rejected," legacy_context=true")
