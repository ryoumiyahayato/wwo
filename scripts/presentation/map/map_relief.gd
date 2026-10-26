class_name MapRelief
extends RefCounted
## Shared global/native LODs and bounded geographic surface packs.
const PREWARM_MPP: float = 8500.0
const RELEASE_MPP: float = 11000.0
var textures: Dictionary = {}
var errors: Array[String] = []
var decode_asset: Callable
var _assets: Dictionary = {}
var _wanted: Array[String] = []
var _attempted: Dictionary = {}
var _thread: Thread
var _level: String = ""
var _demand_key: Array = []
var _window: String = ""
var _desired_window: String = ""
var _surface_wanted: Array[String] = []
var _surface_active: Array[String] = []
var _surface_view := Rect2()
var _surface_refinement_weight: float = 0.0

func request(visible: bool, mpp: float, center: Vector2 = Vector2(INF,INF), radius_km: float = 0.0, regional: bool = true, footprint: Dictionary = {}) -> bool:
	var key: Array = [visible,mpp,center,radius_km,regional,footprint,_assets.size()]
	var previous_mpp := float(_demand_key[1]) if not _demand_key.is_empty() else mpp
	var previous_refinement := _surface_refinement_weight
	var previous_longitude := _surface_view.get_center().x
	var changed := false
	if _demand_key!=key:
		_demand_key = key
		_wanted.assign(["world"] if visible else [])
		if visible and (mpp <= PREWARM_MPP or (textures.has("region") and mpp < RELEASE_MPP)):
			_wanted.append("region")
		_desired_window = _choose_window(center,radius_km,mpp) if visible and regional and center.is_finite() else ""
		if not _desired_window.is_empty(): _wanted.append(_desired_window)
		var active := _window
		if textures.has(_desired_window): _window = _desired_window
		elif not visible or not regional or not center.is_finite() or not _window_intersects(_window,center,radius_km,mpp): _window = ""
		if not _window.is_empty() and _window not in _wanted: _wanted.append(_window)
		changed = active!=_window
		_surface_wanted = _choose_surface(visible,mpp,center,radius_km,regional,footprint)
		_wanted.append_array(_surface_wanted)
	var previous_surface := _surface_active.duplicate()
	_refresh_surface_active()
	changed = changed or previous_surface!=_surface_active
	# Sampler weights/longitude frames also change without a new texture ID.
	# Publish those changes on the same camera update, not the next upload.
	changed = changed or previous_refinement!=_surface_refinement_weight or absf(previous_longitude-_surface_view.get_center().x)>180.0
	if previous_mpp!=mpp and (not _surface_active.is_empty() or not _window.is_empty()): changed = true
	changed = _retire_textures() or changed
	# Failed or cancelled old demands may be retried on a later visit, while
	# staying on the same failed view never causes a background polling loop.
	for level: String in _attempted.keys():
		if level not in _wanted and (_thread==null or level!=_level): _attempted.erase(level)
	_start_decode()
	return changed

func _start_decode() -> void:
	if _thread == null and decode_asset.is_valid():
		for level: String in _wanted:
			if not textures.has(level) and not _attempted.has(level):
				_level = level
				_attempted[level] = true
				# Asset records are immutable; only the worker catalogue dictionary changes.
				# Copying every nested record blocks wheel input as the library grows.
				_thread = Thread.new()
				var error := _thread.start(decode_asset.bind(level, _assets.duplicate()))
				if error!=OK:
					errors.append("无法启动地貌读取："+error_string(error))
					_thread = null
				break

func _retire_textures() -> bool:
	var changed := false
	for level: String in textures.keys():
		if level not in _wanted and level not in _surface_active:
			textures.erase(level)
			_attempted.erase(level)
			changed = true
	return changed

func _choose_surface(visible: bool, mpp: float, center: Vector2, radius_km: float, regional: bool, footprint: Dictionary = {}, explanation: Dictionary = {}) -> Array[String]:
	var wanted: Array[String] = []
	_surface_view = Rect2()
	_surface_refinement_weight = 0.0
	if not visible or not center.is_finite() or mpp>60000.0: return wanted
	var latitude_margin := minf(90.0,radius_km/111.195)
	var longitude_margin := rad_to_deg(asin(clampf(sin(radius_km/6371.0088)/maxf(0.000001,cos(deg_to_rad(center.y))),0.0,1.0)))
	if absf(center.y)+latitude_margin>=90.0: longitude_margin = 180.0
	var margin := Vector2(longitude_margin,latitude_margin)
	var view := Rect2(center-margin,margin*2.0)
	if not footprint.is_empty(): view = projected_footprint(footprint,center)
	_surface_view = view
	# The same R57 catalogue admits continental foundation metadata only in
	# REGION. WORLD and country selection never preload continental images.
	if regional and mpp<=4500.0 and not _assets.has("global_region_r57_oceania_base0"):
		for domain: Rect2 in [Rect2(104,-56,75.25,56),Rect2(-88,-56,56,72),Rect2(-179.25,0,131.25,84),Rect2(-20,-36,76,48),Rect2(56,-16,123.25,56),Rect2(64,32,115.25,52)]:
			if _overlap(domain,view)>0.0: return ["sampling_catalog"]
	# Current shared material admission precedes image requests in this domain.
	# This also makes source-only old derivatives unnecessary in the export.
	# The physical globe remains visible while optional metadata is admitted.
	if regional and _overlap(Rect2(-28,10,104,76),view)>0.0 and not _assets.has("euro_afro_russia_r57_base"):
		return ["sampling_catalog"]
	if regional and _overlap(Rect2(-16,32,64,32),view)>0.0 and not _assets.has("mid8_r56_32_-16"):
		wanted.append("sampling_catalog")
	var shared_base := "euro_afro_russia_r57_continuity_base" if _assets.has("euro_afro_russia_r57_continuity_base") else "euro_afro_russia_r57_base" if _assets.has("euro_afro_russia_r57_base") else "euro_afro_russia_r56_base" if _assets.has("euro_afro_russia_r56_base") else "euro_afro_russia_r55_base"
	var domains: Array[Dictionary] = [
		{"id":shared_base,"catalog":"sampling_catalog","bounds":Rect2(-28,10,104,76)},
		{"id":"greenland_r52_base","catalog":"northern_catalog","bounds":Rect2(-76,58,66,28),"macro_world":true,"max_mpp":60000.0},
		{"id":"canary_r45_base","catalog":"northern_catalog","bounds":Rect2(-20,26,8,4)},
		{"id":"asia_west_r51_base","catalog":"asian_catalog","bounds":Rect2(44,30,84,54)},
		{"id":"asia_east_r51_base","catalog":"asian_catalog","bounds":Rect2(120,40,72,44)}]
	var bases: Array[Dictionary] = []
	# Preserve established overviews wherever they support the whole view.
	# Gap overviews are additional bounded consumers, not replacements for
	# European or Asian high-source inputs.
	var established_full := false
	for domain: Dictionary in domains:
		if (domain.bounds as Rect2).encloses(view): established_full = true
	if not established_full:
		for asset: Dictionary in _assets.values():
			if not bool(asset.get("foundation_domain",false)): continue
			var b := asset.core_bounds_lon_lat as Array
			domains.append({"id":str(asset.id).get_slice(":",1),"catalog":"sampling_catalog","bounds":Rect2(float(b[0]),float(b[1]),float(b[2])-float(b[0]),float(b[3])-float(b[1]))})
	for domain: Dictionary in domains:
		if mpp>float(domain.get("max_mpp",4500.0)): continue
		# A permitted macro surface is optional and focus-bounded in WORLD.
		# The default country globe never opens regional image catalogues.
		if not regional and (not bool(domain.get("macro_world",false)) or not (domain.bounds as Rect2).has_point(center)): continue
		var area: float = _surface_overlap(domain.bounds as Rect2)
		if area<=0.0: continue
		if not _assets.has(str(domain.id)):
			if str(domain.catalog) not in wanted: wanted.append(str(domain.catalog))
		else: bases.append({"id":domain.id,"area":area,"ice_reference":str(domain.id)=="greenland_r52_base"})
	bases.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if bool(a.ice_reference)!=bool(b.ice_reference): return bool(a.ice_reference)
		return str(a.id)<str(b.id) if is_equal_approx(float(a.area),float(b.area)) else float(a.area)>float(b.area))
	for base: Dictionary in bases.slice(0,2): wanted.append(str(base.id))
	if wanted.is_empty(): return wanted
	if not regional or mpp>3500.0: return wanted
	# One geographic grid, independent of catalogue or country. Prefer the
	# smaller, fully supported core for duplicate/collar candidates.
	var cells: Dictionary = {}
	var replaced: Dictionary = {}
	for candidate: Dictionary in _assets.values():
		for old_id: String in candidate.get("surface_replaces",[]) as Array:
			replaced[old_id] = true
	var nearby := view.grow_individual(view.size.x*0.5,view.size.y*0.5,view.size.x*0.5,view.size.y*0.5)
	for level: String in _assets:
		var asset := _assets[level] as Dictionary
		if str(asset.get("surface_role",""))!="detail": continue
		if replaced.has(level): continue
		var b := asset.core_bounds_lon_lat as Array
		var bounds := Rect2(float(b[0]),float(b[1]),float(b[2])-float(b[0]),float(b[3])-float(b[1]))
		if _overlap(bounds,nearby)<=0.0: continue
		var span := int(asset.get("surface_lod_degrees",2))
		if mpp>float(asset.get("surface_display_max_mpp",750.0)): continue
		# Identify the actual normalized geographic core, including page sizes
		# such as16 degrees that do not divide360 into an integer grid.
		var cell := Vector3i(span,roundi(wrapf(bounds.position.x,-180.0,180.0)*1024.0),roundi(bounds.position.y*1024.0))
		var delta := bounds.get_center()-center
		delta.x = wrapf(delta.x,-180.0,180.0)
		var distance := delta*Vector2(cos(deg_to_rad(center.y)),1.0)
		var row := {"id":level,"span":span,"distance":distance.length_squared(),"area":bounds.get_area(),"overlap":_surface_overlap(bounds),"visible":_surface_overlap(bounds)>0.0,"resident":textures.has(level),"support":float(asset.get("surface_support_fraction",1.0))}
		row["source_step"] = source_step(asset,bounds.intersection(view))
		if not cells.has(cell) or float(row.support)>float(cells[cell].support) or is_equal_approx(float(row.support),float(cells[cell].support)) and (float(row.source_step)<float(cells[cell].source_step) or is_equal_approx(float(row.source_step),float(cells[cell].source_step)) and level<str(cells[cell].id)): cells[cell] = row
	var candidates: Array = cells.values()
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if bool(a.visible)!=bool(b.visible): return bool(a.visible)
		if bool(a.visible) and not is_equal_approx(float(a.overlap),float(b.overlap)): return float(a.overlap)>float(b.overlap)
		if not bool(a.visible) and bool(a.resident)!=bool(b.resident): return bool(a.resident)
		return str(a.id)<str(b.id) if is_equal_approx(float(a.distance),float(b.distance)) else float(a.distance)<float(b.distance))
	# Choose one real geographic page level that fits the same four slots.
	# A wide screen can use intermediate material rather than falling directly
	# from four 2-degree cores to the 120-arcsecond overview. No runtime atlas.
	var has_middle := false
	for row: Dictionary in candidates:
		if int(row.span)>2 and bool(row.visible): has_middle = true
	# The padded admission/prewarm frame is not the set of visible pixels.
	# A bounded proof may admit a complete four-core screen even when that
	# larger frame has gaps. Uncertain/polar/clipped charts keep the old rule.
	var screen_view := certified_screen_footprint(footprint,center) if not footprint.is_empty() else Rect2()
	if explanation.has("groups"): explanation["certified_screen_bounds"] = [screen_view.position.x,screen_view.position.y,screen_view.end.x,screen_view.end.y] if screen_view.has_area() else []
	var chosen: Array = []
	var chosen_covers_screen := false
	var best_step := INF
	if explanation.has("groups"): explanation["replaced_ids"] = replaced.keys()
	for span: int in [2,8,16]:
		var same: Array = candidates.filter(func(row: Dictionary) -> bool: return int(row.span)==span)
		if same.is_empty(): continue
		var area := 0.0
		var count := 0
		var source_total := 0.0
		var cores: Array[Rect2] = []
		for row: Dictionary in same:
			if bool(row.visible) and count<4:
				area += float(row.overlap)
				var asset := _assets[str(row.id)] as Dictionary
				cores.append(_surface_frame(asset.core_bounds_lon_lat as Array))
				var output_step := float((asset.display_spacing_degrees as Array)[1])*111195.0
				source_total += float(row.overlap)*(float(row.source_step)+output_step*.05)
				count += 1
		var covers_screen := screen_view.has_area() and cores_cover_view(cores,screen_view)
		if explanation.has("groups"):
			(explanation.groups as Array).append({"span_degrees":span,"visible_candidates":same.filter(func(row: Dictionary) -> bool: return bool(row.visible)).size(),"first_four_view_coverage":area/maxf(_overlap(view,view),.000001),"screen_coverage_certified":covers_screen,"source_score_m":source_total/maxf(area,.000001),"ids":same.map(func(row: Dictionary) -> String: return str(row.id))})
		if covers_screen or area>=_overlap(view,view)*.995 or not has_middle:
			var step := source_total/maxf(area,.000001)
			# A smaller rectangle is not evidence of a better measurement. For
			# equal source information prefer the continuous page, not more uploads.
			if step<=best_step*1.02:
				chosen = same
				chosen_covers_screen = covers_screen
				best_step = step
	if chosen.is_empty(): return wanted
	candidates = chosen
	var visible_count := 0
	for row: Dictionary in candidates:
		if bool(row.visible): visible_count += 1
	# A complete geographic overview owns wide views. Do not install four
	# arbitrary crisp islands where this LOD cannot cover the current screen.
	_surface_refinement_weight = 1.0
	if visible_count>4 and not chosen_covers_screen:
		var all_area := 0.0
		var selected_area := 0.0
		for index: int in range(visible_count):
			all_area += float(candidates[index].overlap)
			if index<4: selected_area += float(candidates[index].overlap)
		_surface_refinement_weight = smoothstep(.92,.999,selected_area/maxf(all_area,.000001))
		if _surface_refinement_weight<=0.001: return wanted
	var selected_asset := _assets[str(candidates[0].id)] as Dictionary
	_surface_refinement_weight *= 1.0-smoothstep(float(selected_asset.get("surface_fade_mpp",300.0)),float(selected_asset.get("surface_display_max_mpp",750.0)),mpp)
	var spare := mini(2,maxi(0,4-visible_count))
	var admitted := 0
	for row: Dictionary in candidates:
		if bool(row.visible) and admitted<4:
			wanted.append(str(row.id))
			admitted += 1
		elif spare>0:
			wanted.append(str(row.id))
			spare -= 1
	return wanted

func explain_selection() -> Dictionary:
	if _demand_key.size()<7: return {}
	var view := _surface_view
	var strength := _surface_refinement_weight
	var result := {"groups":[]}
	var d := _demand_key
	result["replayed_demand"] = _choose_surface(bool(d[0]),float(d[1]),d[2] as Vector2,float(d[3]),bool(d[4]),d[5] as Dictionary,result)
	_surface_view = view
	_surface_refinement_weight = strength
	return result

static func source_step(asset: Dictionary, view: Rect2) -> float:
	var output := float((asset.get("display_spacing_degrees",[1,1]) as Array)[1])*111195.0
	var p := asset.get("precision",{}) as Dictionary
	var known := float(p.get("dem_extract_m_ns",0))
	if known<=0:
		var source := str(asset.get("dem_source",""))
		known = 185.325 if "GLO90" in source else 1853.25 if "ETOPO" in source else output
	var cells := p.get("dem_cells",[]) as Array
	if cells.is_empty(): return maxf(output,known)
	var fallback := maxf(output,float(p.get("dem_fallback_m_ns",1853.25)))
	var improvement := 0.0
	for cell: Dictionary in cells:
		var b := cell.bounds as Array
		var bounds := Rect2(float(b[0]),float(b[1]),float(b[2])-float(b[0]),float(b[3])-float(b[1]))
		improvement += _overlap(bounds,view)*(fallback-maxf(output,float(cell.m)))
	return maxf(output,fallback-improvement/maxf(_overlap(view,view),.000000000001))

func minimum_observation_mpp(ll: Vector2) -> float:
	# At most four screen pixels per real DEM/output sample. Inspect actual
	# source coverage, including finer pages not resident yet; never load here.
	# The global REGION image has a 4096x2048 grid (~9.77km), although
	# its ETOPO input was ~1.85km. Output spacing also bounds useful zoom.
	var best := float((_assets.get("region",{}) as Dictionary).get("equatorial_pixel_m",9773.0051))
	var replaced := {}
	for asset: Dictionary in _assets.values():
		for old: String in asset.get("surface_replaces",[]) as Array: replaced[old]=true
	for id: String in _assets:
		var asset := _assets[id] as Dictionary
		if str(asset.get("surface_role","")) not in ["base","detail"] or replaced.has(id): continue
		var b := asset.get("core_bounds_lon_lat",asset.get("bounds_lon_lat",[])) as Array
		if b.size()!=4: continue
		var x := ll.x+360.0*roundf(((float(b[0])+float(b[2]))*.5-ll.x)/360.0)
		if x<float(b[0]) or x>float(b[2]) or ll.y<float(b[1]) or ll.y>float(b[3]): continue
		best = minf(best,source_step(asset,Rect2(Vector2(x,ll.y)-Vector2.ONE*.00001,Vector2.ONE*.00002)))
	return maxf(2.0,best*.25)

static func projected_footprint(chart: Dictionary, center: Vector2) -> Rect2:
	# Use the real azimuthal-equidistant chart, including its pan and bearing.
	# Interior samples include high-latitude extrema that four corners miss.
	var output := Rect2()
	var initialized := false
	var viewport := chart.size as Vector2
	var axes := RegionProjection.screen_axes(float(chart.bearing))
	for y: int in range(9):
		for x: int in range(9):
			var pixel := viewport*Vector2(x/8.0,y/8.0)
			var km := axes.basis_xform_inv(pixel-(chart.origin as Vector2))*float(chart.step)
			if km.length()>float(chart.extent): continue
			var ll := RegionProjection.lon_lat(RegionProjection.inverse(km,chart.frame as Basis))
			ll.x += 360.0*roundf((center.x-ll.x)/360.0)
			output = output.expand(ll) if initialized else Rect2(ll,Vector2.ZERO)
			initialized = true
	for pole: float in [-1.0,1.0]:
		var km := RegionProjection.forward(Vector3(0,pole,0),chart.frame as Basis)
		if not km.is_finite() or km.length()>float(chart.extent): continue
		var pixel := (chart.origin as Vector2)+axes*(km/float(chart.step))
		if Rect2(Vector2.ZERO,viewport).has_point(pixel):
			output = output.expand(Vector2(center.x-180.0,pole*90.0)).expand(Vector2(center.x+180.0,pole*90.0))
	# Small conservative collar for sampled curved extrema, not fixed degrees.
	return output.grow_individual(output.size.x*.02,output.size.y*.02,output.size.x*.02,output.size.y*.02)

static func certified_screen_footprint(chart: Dictionary, center: Vector2) -> Rect2:
	# Certificate, not a tighter guessed bbox: exp on the sphere is 1-Lipschitz
	# in chart kilometres. Any boundary point lies within half a sampled edge
	# segment of a sample. Add one screen pixel and a floating-point collar.
	# Away from poles, lat/continuous lon have no interior chart extrema.
	var viewport := chart.size as Vector2
	var origin := chart.origin as Vector2
	var step := float(chart.step)
	if step<=0.0 or not viewport.is_finite() or viewport.x<=0.0 or viewport.y<=0.0: return Rect2()
	var axes := RegionProjection.screen_axes(float(chart.bearing))
	var frame := chart.frame as Basis
	var corners: Array[Vector2] = [Vector2.ZERO,Vector2(viewport.x,0.0),viewport,Vector2(0.0,viewport.y)]
	for corner: Vector2 in corners:
		var distance := corner.distance_to(origin)*step
		if distance>float(chart.extent) or distance>=PI*6371.0088: return Rect2()
	for pole: float in [-1.0,1.0]:
		var km := RegionProjection.forward(Vector3(0,pole,0),frame)
		if km.is_finite() and Rect2(Vector2.ZERO,viewport).grow(1.0).has_point(origin+axes*(km/step)): return Rect2()
	var output := Rect2()
	var initialized := false
	var longest_segment := 0.0
	for edge: int in range(4):
		var start := corners[edge]
		var delta := corners[(edge+1)%4]-start
		# At most512 inverse projections per changed demand, never pixel scans.
		var segments := clampi(ceili(delta.length()/8.0),8,128)
		longest_segment = maxf(longest_segment,delta.length()/segments)
		for i: int in range(segments):
			var pixel := start+delta*(float(i)/segments)
			var km := axes.basis_xform_inv(pixel-origin)*step
			var ll := RegionProjection.lon_lat(RegionProjection.inverse(km,frame))
			if not ll.is_finite(): return Rect2()
			ll.x += 360.0*roundf((center.x-ll.x)/360.0)
			output = output.expand(ll) if initialized else Rect2(ll,Vector2.ZERO)
			initialized = true
	var latitude_error := rad_to_deg((longest_segment*0.5+1.0)*step/6371.0088)+0.0001
	var absolute_latitude := maxf(absf(output.position.y),absf(output.end.y))+latitude_error
	# Near poles or ambiguous longitude turns, retain established admission.
	if absolute_latitude>=80.0 or output.size.x>=180.0: return Rect2()
	var longitude_error := latitude_error/cos(deg_to_rad(absolute_latitude))
	return output.grow_individual(longitude_error,latitude_error,longitude_error,latitude_error)

static func cores_cover_view(cores: Array[Rect2], view: Rect2) -> bool:
	# Exact rectangle-union containment, not summed areas (which can double
	# count overlaps). The certificate must leave no positive-area gap.
	if not view.has_area(): return false
	var remaining: Array[Rect2] = [view]
	for core: Rect2 in cores:
		var next: Array[Rect2] = []
		for gap: Rect2 in remaining:
			var hit := gap.intersection(core)
			if not hit.has_area():
				next.append(gap)
				continue
			for part: Rect2 in [Rect2(gap.position,Vector2(hit.position.x-gap.position.x,gap.size.y)),Rect2(Vector2(hit.end.x,gap.position.y),Vector2(gap.end.x-hit.end.x,gap.size.y)),Rect2(Vector2(hit.position.x,gap.position.y),Vector2(hit.size.x,hit.position.y-gap.position.y)),Rect2(Vector2(hit.position.x,hit.end.y),Vector2(hit.size.x,gap.end.y-hit.end.y))]:
				if part.has_area(): next.append(part)
		remaining = next
		if remaining.is_empty(): return true
	return false

func surface_description(mpp: float) -> Dictionary:
	var bases: Array[Dictionary] = []
	for level: String in _surface_active:
		if str((_assets.get(level,{}) as Dictionary).get("surface_role",""))=="base": bases.append(_surface_asset(level))
	if bases.is_empty(): return {}
	# The secondary sampler overlays the primary. Established valid terrain
	# therefore goes last; the continental foundation only fills its gaps.
	if bases.size()==2:
		var first_ice := str(bases[0].id)=="greenland_r52_base"
		var second_ice := str(bases[1].id)=="greenland_r52_base"
		var first_foundation := bool((_assets[str(bases[0].id)] as Dictionary).get("foundation_domain",false))
		var second_foundation := bool((_assets[str(bases[1].id)] as Dictionary).get("foundation_domain",false))
		if first_ice or not second_ice and not first_foundation and second_foundation: bases.reverse()
	var weight := 0.0
	for base: Dictionary in bases:
		base["opacity"] = 1.0-smoothstep(float(base.fade_mpp),float(base.max_mpp),mpp)
		weight = maxf(weight,float(base.opacity))
	for base: Dictionary in bases: base["opacity"] = float(base.opacity)/maxf(weight,0.000001)
	var result := {"base":bases[0],"secondary":bases[1] if bases.size()>1 else {},"detail_weight":_surface_refinement_weight,"weight":weight}
	var tiles: Array[Dictionary] = []
	for level: String in _surface_active:
		if str((_assets[level] as Dictionary).get("surface_role",""))!="detail": continue
		var tile := _surface_asset(level)
		var core := _surface_frame((_assets[level] as Dictionary).core_bounds_lon_lat as Array)
		tile["core"] = Vector4(core.position.x,core.position.y,core.end.x,core.end.y)
		tile["edges"] = _detail_edges(level,core)
		tiles.append(tile)
	result["tiles"] = tiles
	return result

func _detail_edges(level: String, core: Rect2) -> Vector4:
	var edge := Vector4(.35,.35,.35,.35)
	for other: String in _surface_active:
		var asset := _assets[other] as Dictionary
		if other==level or str(asset.get("surface_role",""))!="detail": continue
		# An installed neighbour owns the shared edge even when its worst source
		# cell has a different resolution. Returning BOTH sides to the base made
		# a zero-contribution stripe at 8E/-8E/48N despite valid overlap gutters.
		# Blend the actual neighbouring inputs there; only exposed edges fade.
		var adjacent := _surface_frame(asset.core_bounds_lon_lat as Array)
		if is_equal_approx(adjacent.position.y,core.position.y) and is_equal_approx(adjacent.end.y,core.end.y):
			if is_equal_approx(adjacent.end.x,core.position.x): edge.x = 0.0
			if is_equal_approx(adjacent.position.x,core.end.x): edge.z = 0.0
		if is_equal_approx(adjacent.position.x,core.position.x) and is_equal_approx(adjacent.end.x,core.end.x):
			if is_equal_approx(adjacent.end.y,core.position.y): edge.y = 0.0
			if is_equal_approx(adjacent.position.y,core.end.y): edge.w = 0.0
	return edge

func _refresh_surface_active() -> void:
	# A rendered set is a publication, not a list of images that happened to
	# finish first. Keep the previous compatible set until every VISIBLE
	# successor is resident. Spare-slot prefetch never blocks publication.
	var bases: Array[Dictionary] = []
	var details: Array[Dictionary] = []
	var waiting_base := false
	var waiting_detail := false
	if not _surface_view.has_area():
		_surface_active.clear()
		return
	for level: String in _surface_wanted:
		if level.ends_with("_catalog"): waiting_base = true
		var asset := _assets.get(level,{}) as Dictionary
		var role := str(asset.get("surface_role",""))
		if role not in ["base","detail"]: continue
		var b := asset.get("core_bounds_lon_lat",asset.get("bounds_lon_lat",[])) as Array
		if b.size()!=4: continue
		var bounds := _surface_frame(b)
		if _surface_overlap(bounds)<=0.0: continue
		if not textures.has(level):
			if role=="base": waiting_base = true
			else: waiting_detail = true
			continue
		var row := {"id":level,"distance":bounds.get_center().distance_squared_to(_surface_view.get_center())}
		if role=="base": bases.append(row)
		else: details.append(row)
	if waiting_base or waiting_detail:
		var previous_bases: Array[Dictionary] = []
		var previous_details: Array[Dictionary] = []
		for level: String in _surface_active:
			if not textures.has(level): continue
			var asset := _assets[level] as Dictionary
			# The actual source collar remains useful just beyond its core.
			# A moving camera never waits; uncovered space uses the legal base.
			var bounds := _surface_frame(asset.bounds_lon_lat as Array)
			if _surface_overlap(bounds)<=0.0: continue
			var row := {"id":level,"distance":bounds.get_center().distance_squared_to(_surface_view.get_center())}
			if str(asset.surface_role)=="base": previous_bases.append(row)
			elif str(asset.surface_role)=="detail": previous_details.append(row)
		# First entry may publish a complete overview while detail is loading.
		if not previous_bases.is_empty() or waiting_base: bases = previous_bases
		details = previous_details
	var order := func(a: Dictionary,b: Dictionary) -> bool:
		return str(a.id)<str(b.id) if is_equal_approx(float(a.distance),float(b.distance)) else float(a.distance)<float(b.distance)
	bases.sort_custom(order)
	details.sort_custom(order)
	_surface_active.clear()
	for row: Dictionary in bases.slice(0,2): _surface_active.append(str(row.id))
	for row: Dictionary in details.slice(0,4): _surface_active.append(str(row.id))

func _surface_overlap(bounds: Rect2) -> float:
	return _overlap(bounds,_surface_view)

static func _overlap(bounds: Rect2, view: Rect2) -> float:
	var area := 0.0
	for offset: float in [-360.0,0.0,360.0]:
		var wrapped := Rect2(bounds.position+Vector2(offset,0.0),bounds.size)
		var overlap := wrapped.intersection(view)
		if overlap.has_area(): area += overlap.get_area()*maxf(0.01,cos(deg_to_rad(overlap.get_center().y)))
	return area

func _surface_asset(level: String) -> Dictionary:
	var asset := _assets[level] as Dictionary
	var b := asset.bounds_lon_lat as Array
	var feather := asset.get("surface_feather_degrees",[0,0,0,0]) as Array
	var frame := _surface_frame(b)
	var cover_step := float((asset.get("precision",{}) as Dictionary).get("cover_m_ns_max",0.0))
	# A148m source baked into an869m page no longer carries148m boundaries.
	# Both production resampling and original classification limit its detail.
	if cover_step>0: cover_step=maxf(cover_step,float((asset.display_spacing_degrees as Array)[1])*111195.0)
	var mpp := float(_demand_key[1]) if _demand_key.size()>1 else 1000.0
	var cover_weight := smoothstep(cover_step/8.0,cover_step/2.0,mpp) if cover_step>0 else 1.0
	return {"id":level,"texture":textures[level],"bounds":Vector4(frame.position.x,frame.position.y,frame.end.x,frame.end.y),"inset":float(asset.core_inset_degrees),"encoding":int(asset.get("surface_encoding",0)),"cover_weight":cover_weight,"feather":Vector4(float(feather[0]),float(feather[1]),float(feather[2]),float(feather[3])),"max_mpp":float(asset.get("surface_display_max_mpp",4500.0)),"fade_mpp":float(asset.get("surface_fade_mpp",2500.0))}

func _surface_frame(bounds: Array) -> Rect2:
	# The four neighbouring cores share the same longitude turn. Merging
	# -180 and +178 must produce a four-degree frame, never a 360-degree one.
	var frame := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2])-float(bounds[0]),float(bounds[3])-float(bounds[1]))
	frame.position.x += 360.0*roundf((_surface_view.get_center().x-frame.get_center().x)/360.0)
	return frame

func _choose_window(center: Vector2, radius_km: float, mpp: float) -> String:
	var chosen := ""
	var nearest := INF
	for level: String in _assets:
		var asset := _assets[level] as Dictionary
		if not _window_intersects(level,center,radius_km,mpp): continue
		var a := asset.anchor_lon_lat as Array
		var distance := Vector2((center.x-float(a[0]))*cos(deg_to_rad(center.y)),center.y-float(a[1])).length_squared()
		if distance<nearest:
			chosen = level
			nearest = distance
	return chosen

func _window_intersects(level: String, center: Vector2, radius_km: float, mpp: float) -> bool:
	if not _assets.has(level): return false
	var asset := _assets[level] as Dictionary
	if asset.has("surface_role"): return false
	if not asset.has("bounds_lon_lat"): return false
	var limit := float(asset.release_mpp) if textures.has(level) else float(asset.display_max_mpp)
	if mpp>limit: return false
	# Native kilometre cells add an intermediate cartographic band. Do not
	# magnify the residual into supposed fine LOCAL terrain indefinitely.
	var native_step := float((asset.native_spacing_m_approx as Array)[1])
	if mpp<native_step*0.05*(0.65 if textures.has(level) else 1.0): return false
	var latitude_margin := radius_km/111.195
	var longitude_margin := latitude_margin/maxf(0.15,cos(deg_to_rad(center.y)))
	var b := asset.bounds_lon_lat as Array
	return center.x+longitude_margin>=float(b[0]) and center.x-longitude_margin<=float(b[2]) and center.y+latitude_margin>=float(b[1]) and center.y-latitude_margin<=float(b[3])

func window_description(mpp: float) -> Dictionary:
	if _window.is_empty() or not textures.has(_window): return {}
	var asset := _assets[_window] as Dictionary
	var b := asset.bounds_lon_lat as Array
	var native_step := float((asset.native_spacing_m_approx as Array)[1])
	var weight := (1.0-smoothstep(550.0,float(asset.release_mpp),mpp))*smoothstep(native_step*0.05,native_step*0.20,mpp)
	return {"texture":textures[_window],"bounds":Vector4(float(b[0]),float(b[1]),float(b[2]),float(b[3])),"weight":weight,"edge":float(asset.edge_fraction)}

func preparing() -> bool:
	return _thread != null

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var result := _thread.wait_to_finish() as Dictionary
	_thread = null
	errors.append_array(result.errors as Array[String])
	if result.has("assets"):
		_assets.merge(result.assets as Dictionary)
		# Precision enriches immutable source records even if an older regional
		# catalogue arrived first. Never relabel a texture with another path/codec.
		for id: String in result.assets as Dictionary:
			var incoming := result.assets[id] as Dictionary
			if incoming.has("precision") and (_assets[id] as Dictionary).get("path")==incoming.get("path"):
				(_assets[id] as Dictionary)["precision"] = incoming.precision

	if not result.errors.is_empty():
		_start_decode()
		return false
	if _level not in _wanted:
		_attempted.erase(_level)
		# A cancelled image produces no appearance invalidation. Drain the
		# current bounded demand here; otherwise the last stale result leaves
		# wanted images idle until another mouse/geometry event happens.
		_start_decode()
		return false
	if not result.has("image"):
		_start_decode()
		return true # Catalogue changes demand, not pixels.
	var texture := ImageTexture.create_from_image(result.image as Image)
	textures[_level] = texture
	_refresh_surface_active()
	_retire_textures()
	if _level==_desired_window: _window = _level
	for level: String in _wanted.duplicate():
		if level.begins_with("native_") and level!=_window and level!=_desired_window: _wanted.erase(level)
	# At most one active window and its in-flight replacement. Retire the
	# previous texture only after the replacement is actually available.
	for level: String in textures.keys():
		if level.begins_with("native_") and level!=_window and level!=_desired_window:
			textures.erase(level)
			_attempted.erase(level)
	_start_decode()
	return true

func dispose() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	textures.clear()
	_assets.clear()
	_attempted.clear()
	_wanted.clear()
	_demand_key.clear()
	_window = ""
	_desired_window = ""
	_surface_wanted.clear()
	_surface_active.clear()
	_surface_view = Rect2()

