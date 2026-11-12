class_name TerrainPixelSource
extends RefCounted
## Explicit one-point query. No polling, cache, camera, or automatic file output.

static func serial(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Vector4: return [value.x,value.y,value.z,value.w]
	if value is Color: return [value.r,value.g,value.b,value.a]
	if value is Array: return (value as Array).map(serial)
	if value is Dictionary:
		var out := {}
		for key: Variant in value: out[str(key)] = serial(value[key])
		return out
	if value is Object: return value.get_class() if value!=null else null
	return value

static func sample(image: Image, uv: Vector2, mip: int) -> Color:
	var level := image
	var index := clampi(mip,0,image.get_mipmap_count())
	if index>0:
		var bytes := image.get_data()
		var start := image.get_mipmap_offset(index)
		var end := image.get_mipmap_offset(index+1) if index<image.get_mipmap_count() else bytes.size()
		level = Image.create_from_data(maxi(1,image.get_width()>>index),maxi(1,image.get_height()>>index),false,image.get_format(),bytes.slice(start,end))
	var p := uv*Vector2(level.get_width(),level.get_height())-Vector2.ONE*.5
	var base := p.floor()
	var f := p-base
	var x := clampi(int(base.x),0,level.get_width()-1)
	var y := clampi(int(base.y),0,level.get_height()-1)
	var x1 := clampi(int(base.x)+1,0,level.get_width()-1)
	var y1 := clampi(int(base.y)+1,0,level.get_height()-1)
	return level.get_pixel(x,y).lerp(level.get_pixel(x1,y),f.x).lerp(level.get_pixel(x,y1).lerp(level.get_pixel(x1,y1),f.x),f.y)

static func decode(v: Color, encoding: int, cover_weight: float) -> Dictionary:
	var coverage := v.a
	var rgb := Vector3(v.r,v.g,v.b)
	if encoding==6:
		coverage = smoothstep(.01,.075,v.a)
		rgb = (Vector3(1.015,1,.88)*v.a).lerp(rgb,cover_weight)
	elif encoding in [1,2,3,4]:
		coverage = smoothstep(.01,.075,v.a)
		rgb *= .4+v.a
	elif encoding==0:
		rgb = Vector3(.57,.57,.46).lerp(Vector3(.70,.68,.62),smoothstep(.2,.95,v.r)).lerp(Vector3(.27,.38,.27),v.b*.78)*(.4+v.g)
	return {"rgb":rgb,"coverage":coverage}

static func rim_weight(ll: Vector2, bounds: Vector4, widths: Vector4) -> float:
	var distances := Vector4(ll.x-bounds.x,ll.y-bounds.y,bounds.z-ll.x,bounds.w-ll.y)
	var weight := 1.0
	for axis: int in range(4):
		if widths[axis]>0: weight *= smoothstep(0,widths[axis],distances[axis])
	return weight

static func inspect(relief: MapRelief, batch: Dictionary, ll: Vector2, mpp: float, context: Dictionary) -> Dictionary:
	var material := batch.get("material") as ShaderMaterial
	if material==null: return context.merged({"error":"No installed visible land material"})
	var result := context.duplicate()
	result.merge({"lon_lat":serial(ll),"mpp":mpp,"gpu_implicit_mip":"无法直接取得","colour_measurement":"CPU reconstruction of actual bound inputs; not final framebuffer or GPU timer","layers":[],"candidates":[]})
	var layers := result.layers as Array
	var bindings := {}
	for entry: Dictionary in material.shader.get_shader_uniform_list():
		var name := str(entry.name)
		if not name.begins_with("surface_"): continue
		var bound: Variant = material.get_shader_parameter(name)
		if bound is Texture2D:
			var texture_id := ""
			for key: String in relief.textures:
				if relief.textures[key]==bound: texture_id=key; break
			bindings[name] = {"id":texture_id,"path":(relief._assets.get(texture_id,{}) as Dictionary).get("path"),"width":(bound as Texture2D).get_width(),"height":(bound as Texture2D).get_height()}
		else: bindings[name]=serial(bound)
	result["bound_uniforms"] = bindings
	var gates := {"shader":material.shader.resource_path}
	for name: String in ["region_mode","relief_weight","flag_weight","political_weight","reference_opacity","local_strength","cartographic_relief_weight"]:
		gates[name] = serial(material.get_shader_parameter(name))
	result["shader_gates"] = gates
	result["selector_explanation"] = relief.call("explain_selection") if relief.has_method("explain_selection") else {"version":"R56 selector, no explanation API"}
	var colour := Vector3.ZERO
	var base_coverage := 0.0
	var total := Vector3.ZERO
	var sum := 0.0
	var strength := 0.0
	for slot: String in ["base","secondary","0","1","2","3","4","5"]:
		var detail := slot not in ["base","secondary"]
		var prefix := "surface_"+slot if not detail else "surface_tile_"+slot
		var texture := material.get_shader_parameter(prefix) as Texture2D
		if texture==null: continue
		var id := ""
		for key: String in relief.textures:
			if relief.textures[key]==texture: id=key; break
		var asset := relief._assets.get(id,{}) as Dictionary
		var bounds_name := "surface_bounds_"+slot if detail else prefix+"_bounds"
		var bounds := material.get_shader_parameter(bounds_name) as Vector4
		var point := ll
		point.x += 360.0*roundf(((bounds.x+bounds.z)*.5-point.x)/360.0)
		if bounds.z<=bounds.x or point.x<bounds.x or point.x>bounds.z or point.y<bounds.y or point.y>bounds.w: continue
		var uv := Vector2((point.x-bounds.x)/(bounds.z-bounds.x),(bounds.w-point.y)/(bounds.w-bounds.y))
		var encoding := int(material.get_shader_parameter("surface_encoding_"+slot if detail else prefix+"_encoding"))
		var cover_value: Variant = material.get_shader_parameter("surface_cover_"+slot)
		var cover := float(cover_value) if cover_value!=null else 1.0
		var image := texture.get_image()
		if image==null: continue
		var grid := float((asset.get("display_spacing_degrees",[1,1]) as Array)[1])*111195.0
		# Isotropic CPU estimate only. The GPU uses projected UV derivatives.
		var estimate := maxf(0.0,log(maxf(mpp/grid,1.0))/log(2.0))
		var mip := mini(image.get_mipmap_count(),int(floor(estimate)))
		var value := sample(image,uv,mip)
		var decoded := decode(value,encoding,cover)
		var weight := float(decoded.coverage)
		if detail:
			var inset := float(material.get_shader_parameter("surface_inset_"+slot))
			weight *= rim_weight(point,bounds,Vector4.ONE*inset)*rim_weight(point,material.get_shader_parameter("surface_core_"+slot) as Vector4,material.get_shader_parameter("surface_edges_"+slot) as Vector4)*float(material.get_shader_parameter("surface_detail_weight")) if inset>0 else 0.0
			total += (decoded.rgb as Vector3)*weight
			sum += weight
			strength = maxf(strength,weight)
		else:
			weight *= rim_weight(point,bounds,material.get_shader_parameter(prefix+"_feather") as Vector4)*float(material.get_shader_parameter(prefix+"_opacity"))
			if slot=="base": colour=decoded.rgb; base_coverage=weight
			else:
				var combined := base_coverage+weight*(1-base_coverage)
				colour=colour.lerp(decoded.rgb,weight/maxf(combined,.000001)); base_coverage=combined
		layers.append({"slot":slot,"id":id,"path":asset.get("path"),"bounds":serial(bounds),"uv":serial(uv),"encoding":encoding,"precision":asset.get("precision",{}),"display_grid_m_ns":grid,"cpu_isotropic_mip_estimate":estimate,"cpu_sample_mip":mip,"mip0_rgba":serial(sample(image,uv,0)),"sample_rgba":serial(value),"decoded":serial(decoded),"cover_weight":cover,"spatial_weight":weight})
	if sum>0: colour=colour.lerp(total/sum,minf(sum,1.0))
	result["cpu_surface_rgb"] = serial(colour)
	result["cpu_surface_coverage"] = base_coverage*float(material.get_shader_parameter("surface_weight"))
	var selected := layers.map(func(row: Dictionary) -> String: return str(row.id))
	for id: String in relief._assets:
		var a := relief._assets[id] as Dictionary
		if str(a.get("surface_role","")) not in ["detail","base","source_detail","source_base"]: continue
		var b := a.get("core_bounds_lon_lat",a.get("bounds_lon_lat",[])) as Array
		if b.size()!=4 or ll.y<float(b[1]) or ll.y>float(b[3]): continue
		var x := ll.x+360*roundf(((float(b[0])+float(b[2]))*.5-ll.x)/360)
		if x<float(b[0]) or x>float(b[2]): continue
		var reason := "bound to material at this point" if id in selected else "awaiting decode/upload" if id in relief._wanted else "source-only predecessor, superseded" if str(a.get("surface_role","")).begins_with("source_") else "outside admitted scale" if mpp>float(a.get("surface_display_max_mpp",750)) else "not in chosen coverage/precision group; see selector_explanation"
		(result.candidates as Array).append({"id":id,"path":a.path,"precision":a.get("precision",{}),"display_grid":a.get("display_spacing_degrees"),"selected_here":id in selected,"wanted":id in relief._wanted,"installed":relief.textures.has(id),"max_mpp":a.get("surface_display_max_mpp",750),"role":a.get("surface_role"),"reason":reason})
	return result
