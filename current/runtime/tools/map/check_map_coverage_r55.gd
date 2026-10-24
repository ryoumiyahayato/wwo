extends SceneTree
## Finite offline source/selection check requested for R55. No gameplay, saves,
## simulation, rendering viewport, GPU texture installation or performance run.

func _init() -> void:
	call_deferred("_check")

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary

func _check() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "res://local-artifacts/r55_coverage.json"
	if "--political-only" in args:
		var file := FileAccess.open(out,FileAccess.WRITE)
		file.store_string(JSON.stringify(_political(),"\t"))
		print("R55 political source/compiled check: ",out)
		quit(0)
		return
	var assets: Dictionary = {}
	for catalogue: String in ["asian_catalog","northern_catalog","european_catalog"]:
		var result := GeographyLoader.decode_relief(catalogue,assets)
		if not (result.errors as Array).is_empty(): push_error(str(result.errors)); quit(1); return
		assets = result.assets
	var relief := MapRelief.new()
	relief._assets = assets
	var cases: Array = [
		["france_germany",8.0,49.0,750.0], ["germany_austria",14.0,48.0,450.0],
		["central_russia",37.6,55.8,180.0], ["poland_belarus_ukraine",26.0,52.0,300.0],
		["urals_siberia",58.0,60.0,180.0], ["siberian_coarse_fine",80.0,56.0,180.0],
		["nordic_north_russia",30.0,66.0,500.0], ["africa_political",27.0,-14.0,1000.0],
		["far_east_date_line",179.0,66.0,180.0], ["paris",2.35,48.86,180.0],
		["central_russia_wide",37.6,55.8,1200.0], ["date_line_high_latitude",179.0,78.0,300.0],
		["moscow_fine",37.6,55.8,75.0], ["valdai_fine",35.0,59.0,50.0],
		["crimea_fine",35.0,45.0,50.0], ["urals_fine",59.0,63.0,50.0],
		["siberian_fine_edge",81.0,57.0,75.0], ["date_line_fine",179.0,67.0,75.0]]
	var rows: Array[Dictionary] = []
	var resident := MapRelief.new()
	resident._assets = assets
	var peak_slots := 0
	for spec: Array in cases:
		var center := Vector2(float(spec[1]),float(spec[2]))
		var mpp := float(spec[3])
		var viewport := Vector2(2560,1080) if str(spec[0]).ends_with("wide") else Vector2(1280,720)
		var bearing := .61
		var frame := RegionProjection.frame(center)
		var chart := {"frame":frame,"origin":viewport*.5,"bearing":bearing,"size":viewport,"step":mpp*.001,"extent":9000.0}
		var wanted := relief._choose_surface(true,mpp,center,viewport.length()*mpp*.0005,true,chart)
		var ids: Array[Dictionary] = []
		var decoded := 0
		for id: String in wanted:
			if not assets.has(id): continue
			var a := assets[id] as Dictionary
			decoded += int(a.decoded_bytes)
			var b := a.get("core_bounds_lon_lat",a.bounds_lon_lat) as Array
			var core := Rect2(float(b[0]),float(b[1]),float(b[2])-float(b[0]),float(b[3])-float(b[1]))
			ids.append({"id":id,"role":a.surface_role,"bounds":b,"prefetch":str(a.surface_role)=="detail" and relief._surface_overlap(core)<=0.0,"source":a.get("dem_source","GLO90 upstream"),"decoded_bytes":a.decoded_bytes})
		var view := relief._surface_view
		# Null texture sentinels exercise the real ownership/retirement state
		# machine without creating a GPU resource or pretending to measure one.
		resident.request(true,mpp,center,viewport.length()*mpp*.0005,true,chart)
		for id: String in resident._wanted.duplicate():
			if not assets.has(id) or str((assets[id] as Dictionary).get("surface_role","")) not in ["base","detail"]: continue
			resident.textures[id] = null
			peak_slots = maxi(peak_slots,resident.textures.size())
			resident._refresh_surface_active()
			resident._retire_textures()
		var installed_ids := resident.textures.keys()
		var points: Array = []
		for y: int in range(19):
			for x: int in range(33):
				var pixel := viewport*Vector2(x/32.0,y/18.0)
				var km := RegionProjection.screen_axes(bearing).basis_xform_inv(pixel-(chart.origin as Vector2))*float(chart.step)
				var ll := RegionProjection.lon_lat(RegionProjection.inverse(km,frame))
				ll.x += 360.0*roundf((center.x-ll.x)/360.0)
				points.append([ll.x,ll.y])
		rows.append({"name":spec[0],"center":[center.x,center.y],"mpp":mpp,"viewport":[viewport.x,viewport.y],"bearing":bearing,"view":[view.position.x,view.position.y,view.end.x,view.end.y],"selected":ids,"selected_decoded_bytes":decoded,"refinement_weight":relief._surface_refinement_weight,"simulated_resident_ids":installed_ids,"points":points,"fallback":"existing global ETOPO world/region remains; no freeze"})
	var scale_chart := {"frame":RegionProjection.frame(Vector2(37.6,55.8)),"origin":Vector2(640,360),"bearing":0.0,"size":Vector2(1280,720),"step":3.0,"extent":9000.0}
	resident.request(true,3000,Vector2(37.6,55.8),2200,true,scale_chart)
	for id: String in resident._wanted.duplicate():
		if assets.has(id) and str((assets[id] as Dictionary).get("surface_role",""))=="base": resident.textures[id] = null
	resident._refresh_surface_active()
	resident._retire_textures()
	var old_ids := resident._surface_active.duplicate()
	var before_weight := float(resident.surface_description(3000).get("weight",0.0))
	scale_chart.step = 3.001
	var rebound := resident.request(true,3001,Vector2(37.6,55.8),2201,true,scale_chart)
	var after_weight := float(resident.surface_description(3001).get("weight",0.0))
	var scale_change := {"same_texture_ids":old_ids==resident._surface_active,"request_publishes":rebound,"before_weight":before_weight,"after_weight":after_weight}
	resident.request(true,9000,Vector2(10,48),10000,false)
	var remaining := resident.textures.size()
	var political := _political()
	var file := FileAccess.open(out,FileAccess.WRITE)
	file.store_string(JSON.stringify({"windows":rows,"political":political,"runtime_test":false,"ownership_simulation":{"null_texture_sentinels":true,"peak_slots_including_successor":peak_slots,"regional_slots_after_world":remaining,"scale_change":scale_change}},"\t"))
	print("R55 offline windows=",rows.size()," political records=",political.records.size()," output=",out)
	quit(0)

func _political() -> Dictionary:
	var units := _read("res://data/world_map/historical/political_units_1900.json")
	var geo := _read("res://data/world_map/historical/cshapes_1900_snapshot.json")
	var auth := _read("res://data/world_map/historical/historical_authorities_1900.json")
	var borders := _read("res://data/presentation/political_border_display_r39.json")
	var flags := _read("res://data/world_map/historical/flags_1900.json")
	var resolver := HistoricalVisualResolver.new()
	resolver.configure(flags.records as Dictionary)
	var features: Dictionary = {}
	for f: Dictionary in geo.features: features[str(f.id)] = f
	var supplement := _read(GeographyLoader.SUPPLEMENT_PATH)
	for f: Dictionary in supplement.features: features[str(f.id)] = f
	var display := _read(HistoricalLoader.REGIONS_PATH)
	var layer := PoliticalLayer.new()
	layer.display_date = "1900-01-01"
	var occupied: Dictionary = {}
	for u: Dictionary in units.units:
		if str(u.valid_from)<=layer.display_date and layer.display_date<str(u.valid_to):
			layer.records[str(u.id)] = u
			occupied[str(u.geometry_feature_id)] = true
	for u: Dictionary in auth.assignments:
		if u.has("geometry_component_indices"): continue
		if str(u.valid_from)<=layer.display_date and layer.display_date<str(u.valid_to) and not occupied.has(str(u.geometry_feature_id)) and features.has(str(u.geometry_feature_id)):
			var record := u.duplicate()
			record["display_only"] = true
			layer.records[str(u.id)] = record
	for id: String in layer.records.keys():
		var f := str(layer.records[id].geometry_feature_id)
		if f in (display.scope_feature_ids as Array) and not (display.partial_scope_masks as Dictionary).has(f): layer.records.erase(id)
	for region: Dictionary in display.political_map_regions:
		layer.records[str(region.id)] = {"id":region.id,"source_historical_id":region.historical_authority_id,"geometry_feature_id":"arabia_undelimited_desert_1900","representative_visual_id":region.representative_visual_id,"name_zh":region.name_zh,"display_only":true,"valid_from":display.valid_from,"valid_to":display.valid_to}
	var counts: Dictionary = {}
	var caps: Dictionary = {}
	var index := _read(StrategicSpatialLoader.INDEX_PATH)
	for shard: Dictionary in index.coast_regions:
		var packed := FileAccess.open_compressed(str(shard.compiled_asset.path),FileAccess.READ,FileAccess.COMPRESSION_DEFLATE)
		var data := packed.get_var() as Dictionary
		packed.close()
		for chunk: Dictionary in data.chunks:
			if str(chunk.kind)!="land_reference": continue
			var feature := str(chunk.get("ink_reference",""))
			if not counts.has(feature): counts[feature] = {"batches":0,"faces":0}
			counts[feature].batches += 1
			counts[feature].faces += int(chunk.get("face_count",0))
			caps[feature] = float(chunk.get("cull_angle",PI))
	var records: Array[Dictionary] = []
	for owner: String in layer.records:
		var u := layer.records[owner] as Dictionary
		var feature := str(u.geometry_feature_id)
		var period := (borders.get("feature_validity",{}) as Dictionary).get(feature,{}) as Dictionary
		var old_dated := period.is_empty() or layer.display_date>=str(period.valid_from) and layer.display_date<str(period.valid_to)
		var visual := resolver.resolve(u,features.has(feature),layer.display_date,str(u.get("representative_visual_id","")))
		var reference := owner if owner.begins_with("political_map_region:") else feature
		records.append({"id":owner,"name":u.get("name_zh",""),"feature":feature,"valid_from":u.valid_from,"valid_to":u.valid_to,"display_only":u.get("display_only",false),"relation":u.get("relationship",u.get("authority_type","")),"geometry":features.has(feature),"compiled":counts.get(reference,{}),"old_dated":old_dated,"new_dated":layer.display_active(owner,period),"visual":visual.get("id",""),"visual_kind":visual.get("presentation_visual_kind",""),"asset":visual.get("display_asset","")})
	return {"records":records,"compiled_features":counts.size(),"flag_errors":resolver.errors,"source_geometry_date":geo.snapshot_date}
