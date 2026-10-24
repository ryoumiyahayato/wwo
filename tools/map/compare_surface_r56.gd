extends SceneTree
## Finite offline projection/selection input for the requested visual comparisons.
## Null sentinels exercise existing ownership without a renderer or GPU upload.

func _init() -> void:
	call_deferred("_compare")

func _compare() -> void:
	var rows: Array = []
	var peak_slots := 0
	for catalog: String in ["european_catalog","sampling_catalog"]:
		var decoded := GeographyLoader.decode_relief(catalog,{})
		if not (decoded.errors as Array).is_empty(): push_error(str(decoded.errors)); quit(1); return
		var assets := decoded.assets as Dictionary
		var relief := MapRelief.new()
		relief._assets = assets
		for place: Array in [["alps_po",11.0,46.0],["polesia",27.5,51.2],["crete",24.5,35.3]]:
			for mpp: float in [800.0,250.0,75.0]:
				var center := Vector2(float(place[1]),float(place[2]))
				var viewport := Vector2(1280,720)
				var chart := {"frame":RegionProjection.frame(center),"origin":viewport*.5,"bearing":0.0,"size":viewport,"step":mpp*.001,"extent":9000.0}
				relief.request(true,mpp,center,viewport.length()*mpp*.0005,true,chart)
				for id: String in relief._wanted:
					if assets.has(id) and str((assets[id] as Dictionary).get("surface_role","")) in ["base","detail"]:
						relief.textures[id] = null
						peak_slots = maxi(peak_slots,relief.textures.size())
						relief._refresh_surface_active()
						relief._retire_textures()
				relief._refresh_surface_active()
				relief._retire_textures()
				var selected: Array = []
				for id: String in relief._surface_active:
					var a := assets[id] as Dictionary
					var edges := Vector4.ZERO
					if str(a.surface_role)=="detail": edges = relief._detail_edges(id,relief._surface_frame(a.core_bounds_lon_lat as Array))
					selected.append({"id":id,"asset":a,"edges":[edges.x,edges.y,edges.z,edges.w]})
				rows.append({"catalog":catalog,"place":place[0],"center":[center.x,center.y],"viewport":[1280,720],"mpp":mpp,"bearing":0.0,"view":[relief._surface_view.position.x,relief._surface_view.position.y,relief._surface_view.end.x,relief._surface_view.end.y],"detail_weight":relief._surface_refinement_weight,"selected":selected,"resident_count":relief.textures.size()})
		# The same installed terrain is released by the existing WORLD demand.
		relief.request(true,9000,Vector2(10,48),10000,false)
		if not relief.textures.is_empty(): push_error("Regional references retained on WORLD exit"); quit(1); return
	var file := FileAccess.open("res://local-artifacts/terrain-r56/selection.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"game_run":false,"gpu_upload":false,"null_sentinel_peak_slots_including_successor":peak_slots,"rows":rows},"\t")); file.close()
	print("R56 finite projection/selection rows=",rows.size())
	quit(0)
