extends SceneTree
## Read the exported PCK directory and one native surface; no game scene.

func _init() -> void:
	var scope_path := ""
	var output := ""
	var foundation_only := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scope="): scope_path=arg.trim_prefix("--scope=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg=="--foundation-acceptance":foundation_only=true
	var scope := JSON.parse_string(FileAccess.get_file_as_string(scope_path)) as Dictionary
	var missing: Array = []
	var retained_exclusions: Array = []
	for path: String in scope.active_surface_paths+scope.preserved_outside_paths:
		if not FileAccess.file_exists(path): missing.append(path)
	for path: String in scope.excluded:
		if FileAccess.file_exists("res://"+path): retained_exclusions.append(path)
	var unexpected_research: Array = []
	for path: String in scope.get("research_paths",[]):
		if FileAccess.file_exists("res://"+path): unexpected_research.append(path)
	var decoded := GeographyLoader.decode_relief("sampling_catalog",{})
	var assets := decoded.get("assets",{}) as Dictionary
	if foundation_only:
		var rows:Array=[]
		for id:String in assets:
			var asset:Dictionary=assets[id]
			if not asset.has("foundation_batch"):continue
			var issues:Array=[]
			var path:String=asset.path
			var header:=FileAccess.open(path,FileAccess.READ)
			if header==null:issues.append("missing packed resource")
			else:
				if header.get_length()!=int(asset.bytes):issues.append("packed length differs")
				var bytes:=header.get_buffer(20)
				if bytes.size()!=20 or bytes.slice(0,5).get_string_from_ascii()!="FRT42" or bytes.decode_u32(8)!=int(asset.width) or bytes.decode_u32(12)!=int(asset.height) or bytes.decode_u32(16)!=int(asset.decoded_bytes):issues.append("header differs")
			var count:=0;var w:int=asset.width;var h:int=asset.height;var mips:=0
			while true:
				count+=w*h*4;mips+=1
				if w==1 and h==1:break
				w=maxi(1,w/2);h=maxi(1,h/2)
			if count!=int(asset.decoded_bytes):issues.append("RGBA full Mip length differs")
			if int(asset.surface_encoding)!=6 or str(asset.format)!="RGBA8_MIP_DEFLATE":issues.append("encoding/format differs")
			var b:Array=asset.bounds_lon_lat;var c:Array=asset.core_bounds_lon_lat;var s:Array=asset.display_spacing_degrees
			if b[0]>=b[2] or b[1]>=b[3] or b[0]>c[0] or b[1]>c[1] or b[2]<c[2] or b[3]<c[3]:issues.append("invalid bounds/core")
			if absf((float(b[2])-float(b[0]))/int(asset.width)-float(s[0]))>1e-10 or absf((float(b[3])-float(b[1]))/int(asset.height)-float(s[1]))>1e-10:issues.append("affine output grid differs")
			if str(asset.surface_role)=="detail" and (absf(float(c[0])-float(b[0])-32*float(s[0]))>1e-10 or absf(float(b[3])-float(c[3])-32*float(s[1]))>1e-10):issues.append("32pixel collar differs")
			if not (asset.surface_replaces as Array).is_empty():issues.append("unexpected replacement")
			if absf(float(asset.precision.dem_native_m_ns)-1853.25)>.001 or absf(float(asset.precision.output_m_ns)-float(s[1])*111195)>.001:issues.append("source/display precision differs")
			rows.append({"id":id,"path":path,"batch":asset.foundation_batch,"bytes":asset.bytes,"width":asset.width,"height":asset.height,"mips":mips,"decoded_rgba_bytes":count,"bounds":b,"core":c,"spacing":s,"encoding":asset.surface_encoding,"issues":issues})
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"catalog_errors":decoded.errors,"rows":rows,"missing_active":missing,"unexpected_exclusions":retained_exclusions,"unexpected_research":unexpected_research,"note":"All new headers and declared RGBA/Mip/collar contracts from frozen EXE. No all-pixel decompression, pixel equivalence or hashes."}))
		print("R57_ACCEPT packed foundation headers=",rows.size());quit();return
	var sample := GeographyLoader.decode_relief("repair_r57_european_r55_54_+36",assets)
	var mip_check := {}
	if sample.has("image"):
		var source := sample.image as Image
		mip_check["mip1_sample"] = TerrainPixelSource.serial(TerrainPixelSource.sample(source,Vector2(.5,.5),1))
		mip_check["last_mip_sample"] = TerrainPixelSource.serial(TerrainPixelSource.sample(source,Vector2(.5,.5),source.get_mipmap_count()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"build_label":ProjectSettings.get_setting("application/config/build_label"),"game_scene_run":false,"missing_active":missing,"unexpected_retained_exclusions":retained_exclusions,"unexpected_research_paths":unexpected_research,"catalog_errors":decoded.errors,"sample_errors":sample.errors,"mip_check":mip_check,"sample_size":TerrainPixelSource.serial(Vector2((sample.image as Image).get_size())) if sample.has("image") else [],"active_paths_checked":scope.active_surface_paths.size(),"outside_paths_checked":scope.preserved_outside_paths.size(),"research_paths_checked":scope.get("research_paths",[]).size()},"\t"));file.close()
	var good := missing.is_empty() and retained_exclusions.is_empty() and unexpected_research.is_empty() and (decoded.errors as Array).is_empty() and (sample.errors as Array).is_empty()
	print("R57 exported resource read ",good)
	quit(0 if good else 1)
