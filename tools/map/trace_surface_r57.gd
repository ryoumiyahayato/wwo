extends SceneTree
## Finite source queries using the production selector, decoder and binder.
## No game scene, save, simulation, GPU measurement or user camera assumptions.

func _init() -> void:
	if "--local-continuity" in OS.get_cmdline_user_args():
		call_deferred("_local_continuity")
		return
	if "--queue" in OS.get_cmdline_user_args():
		call_deferred("_queue_check")
		return
	call_deferred("_trace")

func _local_continuity() -> void:
	# Requested two-site diagnosis using the production loader and CPU mesh.
	# No viewport, simulated world, framebuffer claim or new test entry.
	var rows: Array = []
	var before_root: String = ""
	var worker: GDScript = preload("res://scripts/presentation/map/local_spatial_lod.gd")
	var view_script: GDScript = preload("res://scripts/presentation/map/region_view.gd")
	var content_script: GDScript
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--before-source="):before_root=arg.trim_prefix("--before-source=")
	if not before_root.is_empty():
		worker=GDScript.new();worker.source_code=FileAccess.get_file_as_string(before_root+"/scripts/presentation/map/local_spatial_lod.gd").replace("class_name LocalSpatialLod","")
		view_script=GDScript.new();view_script.source_code=FileAccess.get_file_as_string(before_root+"/scripts/presentation/map/region_view.gd").replace("class_name RegionView","")
		content_script=GDScript.new();content_script.source_code=FileAccess.get_file_as_string(before_root+"/scripts/content/local_spatial_content.gd").replace("class_name LocalSpatialContent","")
		if worker.reload()!=OK or view_script.reload()!=OK or content_script.reload()!=OK:quit(1);return
	for source: Dictionary in LocalSpatialLoader.SOURCES:
		if source.anchor_id not in ["place:london","geographic_region:zermatt_west_reference"]: continue
		var source_path: String = str(source.path) if before_root.is_empty() else before_root+"/"+str(source.path).trim_prefix("res://")
		var content := LocalSpatialLoader._load(source_path,func()->bool:return true,str(source.anchor_id))
		if not content.errors.is_empty():push_error(str(content.errors));quit(1);return
		var surface := content.surface_reference
		var frame := RegionProjection.frame(source.anchor)
		var started := Time.get_ticks_usec()
		var memory_before := OS.get_static_memory_usage()
		var prepared := worker.call("prepare_terrain",surface,frame,content.features,content.surface_covers,func()->bool:return true) as Dictionary
		var elapsed := Time.get_ticks_usec()-started
		if prepared.has("error"):push_error(str(prepared.error));quit(1);return
		var points := prepared.ray_vertices as PackedVector3Array
		var bounds := AABB(points[0],Vector3.ZERO)
		for point: Vector3 in points:bounds=bounds.expand(point)
		var limit := float(view_script.call("_terrain_limit_mpp",surface))
		var strengths: Dictionary = {}
		for mpp: float in [2,4,8,12,24]:strengths[str(mpp)]=1.0-smoothstep(limit*.75,limit*1.35,mpp)
		var native_unchanged: bool = true
		var base: float = float(surface.height_rows_m[0][0])-(prepared.vertices[0] as Vector3).y
		for index: int in prepared.vertices.size():
			native_unchanged=native_unchanged and absf((prepared.vertices[index] as Vector3).y+base-float(surface.height_rows_m[index/int(surface.width)][index%int(surface.width)]))<0.002
		var kinds: Dictionary = {};var placements: int = 0
		for feature: Dictionary in content.features:
			kinds[str(feature.kind)]=int(kinds.get(str(feature.kind),0))+1
			placements+=(feature.get("miniature_layout",{}) as Dictionary).get("placements",[]).size()
		var zoom: Dictionary = {}
		var zoom_content: RefCounted=content
		if content_script!=null:
			zoom_content=content_script.new()
			for property: String in ["metadata","surface_reference","features","has_content"]:zoom_content.set(property,content.get(property))
		for distance: float in [0,1500,5000]:
			var ll:=RegionProjection.lon_lat(RegionProjection.inverse(Vector2(distance*.001,0),frame))
			var floor_mpp:=float(zoom_content.call("minimum_observation_mpp",ll,"1900-01-01"))
			zoom[str(distance)]=floor_mpp if is_finite(floor_mpp) else "UNAVAILABLE"
		rows.append({"place":source.anchor_id,"source_path":source.path,"source_grid":[surface.width,surface.height],"native_step_m":surface.get("display_spacing_m_approx",[]),"native_vertices":prepared.vertices.size(),"render_vertices":points.size(),"triangles":prepared.indices.size()/3,"render_bounds_metres":[bounds.position.x,bounds.position.z,bounds.end.x,bounds.end.z],"native_samples_unchanged":native_unchanged,"terrain_limit_mpp":limit,"display_strength":strengths,"zoom_east_offset_metres":zoom,"feature_kinds":kinds,"existing_miniature_placements":placements,"river_chart_only":surface.get("river_chart_only",false),"surface_covers":content.surface_covers.size(),"cpu_prepare_wall_us":elapsed,"retained_cpu_allocation_delta":OS.get_static_memory_usage()-memory_before,"prepared_variant_bytes":var_to_bytes(prepared).size(),"context_water_mask_bytes":(prepared.get("context_water_bytes",PackedByteArray()) as PackedByteArray).size(),"scope":"PRODUCTION_CPU_GEOMETRY_NOT_RENDERED_SCREENSHOTS"})
		var context: Dictionary=(surface.get("presentation",{}) as Dictionary).get("context_height_asset",{})
		if not context.is_empty():
			var decoded:=GeographyLoader.decode_relief("context",{"context":context})
			var image:=decoded.image as Image
			var b:=context.bounds_lon_lat as Array
			var samples: Array=[]
			for offset: Vector2 in [Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2),Vector2(-5,0),Vector2(5,0),Vector2(0,-5),Vector2(0,5)]:
				var ll:=RegionProjection.lon_lat(RegionProjection.inverse(offset,frame))
				var pixel:=Vector2i((ll.x-float(b[0]))/(float(b[2])-float(b[0]))*image.get_width(),(float(b[3])-ll.y)/(float(b[3])-float(b[1]))*image.get_height()).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)
				var value:=image.get_pixelv(pixel)
				samples.append({"offset_km":[offset.x,offset.y],"height_m":200.0*(pow(26.0,value.r)-1.0),"support":value.a})
			rows[-1]["source_context_samples"]=samples
			decoded.clear();image=null
		prepared.clear();points=PackedVector3Array()
	var destination := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--destination="):destination=arg.trim_prefix("--destination=")
	if not destination.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
		FileAccess.open(destination,FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("LOCAL_CONTINUITY_CPU ",JSON.stringify(rows));quit(0)

func _queue_decode(level: String, assets: Dictionary) -> Dictionary:
	OS.delay_msec(80) # Finite worker interleaving, not a performance measurement.
	return GeographyLoader.decode_relief(level,assets)

func _queue_check() -> void:
	var data := GeographyLoader.decode_relief("sampling_catalog",{})
	var relief := MapRelief.new()
	relief._assets=data.assets
	relief.decode_asset=_queue_decode
	# Null references represent the already-installed unchanged global/base
	# inputs. Real geographic detail files use the production decoder below.
	for id: String in ["world","region","euro_afro_russia_r57_base"]: relief.textures[id]=null
	var viewport := Vector2(1280,720)
	var request := func(ll: Vector2) -> void:
		var chart := {"frame":RegionProjection.frame(ll),"origin":viewport*.5,"bearing":0.0,"size":viewport,"step":.5,"extent":9000.0}
		relief.request(true,500,ll,viewport.length()*.25,true,chart)
	request.call(Vector2(16.4,48))
	var superseded := relief._level
	request.call(Vector2(21.0122,52.2297))
	var deadline := Time.get_ticks_msec()+1800
	while Time.get_ticks_msec()<deadline:
		relief.poll()
		await process_frame
	var missing: Array = []
	for id: String in relief._wanted:
		if not relief.textures.has(id): missing.append(id)
	var result := {"fixture":"finite 80ms decoder interleaving, production files; not player framebuffer","center":[21.0122,52.2297],"mpp":500,"mode":"geographic","superseded":superseded,"wanted":relief._wanted,"active":relief._surface_active,"missing":missing,"preparing":relief.preparing(),"errors":relief.errors}
	var floors := {}
	for point: Array in [["new_york",-74.0,40.7],["sao_paulo",-46.63,-23.55],["sydney",151.21,-33.87],["petersburg",30.3351,59.9343],["warsaw",21.0122,52.2297]]:
		floors[point[0]]=relief.minimum_observation_mpp(Vector2(point[1],point[2]))
	result["metadata_only_zoom_floors_mpp"] = floors
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--destination="): FileAccess.open(arg.trim_prefix("--destination="),FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify(result))
	relief.dispose()
	quit(0)

func _trace() -> void:
	var output := "before"
	var destination := ""
	var pixel_script := "res://scripts/presentation/map/terrain_pixel_source.gd"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--destination="): destination=arg.trim_prefix("--destination=")
		if arg.begins_with("--pixel-script="): pixel_script=arg.trim_prefix("--pixel-script=")
	var pixel_source: Variant = load(pixel_script)
	var rows: Array = []
	var decoded := GeographyLoader.decode_relief("sampling_catalog",{})
	if not (decoded.errors as Array).is_empty(): push_error(str(decoded.errors)); quit(1); return
	for place: Array in [["moscow",37.3,55.4],["german_polesia_edge",24.0,51.2],["alps",11.0,46.0],["crete",24.5,35.3],["france",2.5,47.0],["spain",-3.7,40.4],["pyrenees",1.3,42.5],["baltic",24.1,56.9],["warsaw",21.0,52.2],["germany_austria",12.6,47.6]]:
		for mpp: float in [800.0,250.0,75.0,35.0]:
			var relief := MapRelief.new()
			relief._assets = (decoded.assets as Dictionary).duplicate()
			var center := Vector2(float(place[1]),float(place[2]))
			var viewport := Vector2(1280,720)
			var chart := {"frame":RegionProjection.frame(center),"origin":viewport*.5,"bearing":0.0,"size":viewport,"step":mpp*.001,"extent":9000.0}
			relief.request(true,mpp,center,viewport.length()*mpp*.0005,true,chart)
			for id: String in relief._wanted:
				if not relief._assets.has(id): continue
				if str((relief._assets[id] as Dictionary).get("surface_role","")) not in ["base","detail"]: continue
				var asset := GeographyLoader.decode_relief(id,relief._assets)
				if not (asset.errors as Array).is_empty(): push_error(str(asset.errors)); quit(1); return
				relief.textures[id]=ImageTexture.create_from_image(asset.image as Image)
			relief._refresh_surface_active()
			var material := ShaderMaterial.new()
			material.shader=load("res://shaders/presentation/map/political_surface.gdshader") as Shader
			var batch := {"material":material}
			GlobeRenderer._surface_uniforms(batch,relief.surface_description(mpp))
			# Explicit geographical input fixture. Without these production gates
			# the shader's default relief_weight=0 would skip material sampling.
			for name: String in ["region_mode","relief_weight","flag_weight","political_weight","reference_opacity","region_km_per_pixel","region_bearing","globe_center","globe_basis"]:
				var values := {"region_mode":true,"relief_weight":MapScaleStyle.relief_weight(mpp,"geographic"),"flag_weight":0.0,"political_weight":0.0,"reference_opacity":1.0,"region_km_per_pixel":mpp*.001,"region_bearing":Vector2(1,0),"globe_center":viewport*.5,"globe_basis":(chart.frame as Basis).transposed()}
				GlobeRenderer._parameter(batch,name,values[name])
			for pixel: Vector2 in [Vector2(320,360),Vector2(640,360),Vector2(960,360)]:
				var km := RegionProjection.screen_axes(0).basis_xform_inv(pixel-viewport*.5)*mpp*.001
				var ll := RegionProjection.lon_lat(RegionProjection.inverse(km,chart.frame as Basis))
				var context := {"place":place[0],"screen_xy":pixel_source.serial(pixel),"camera_center":pixel_source.serial(center),"bearing":0,"viewport":[1280,720],"build_label":ProjectSettings.get_setting("application/config/build_label"),"mode":"offline production selector + actual ShaderMaterial binding, not player framebuffer","selected":relief._surface_active.duplicate(),"wanted":relief._surface_wanted.duplicate(),"detail_weight":relief._surface_refinement_weight}
				rows.append(pixel_source.inspect(relief,batch,ll,mpp,context))
			GlobeRenderer._surface_uniforms(batch,{})
			relief.dispose()
	var path := destination if not destination.is_empty() else "res://local-artifacts/terrain-r57/"+output+"_points.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("R57 source queries ",rows.size()," -> ",path)
	quit(0)
