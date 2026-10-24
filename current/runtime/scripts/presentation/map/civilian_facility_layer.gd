class_name CivilianFacilityLayer
extends Control
## Display miniatures attached to existing place anchors. No building coordinates,
## land identities, resource capacity or economic state are created here.
const ROOT: String = "res://assets/civilian/"
signal facility_selected(row: Dictionary)
const MODELS: Dictionary = {
	"firm:regional_food": ["factories", "civ.factory.food.bakery_industrial", "食品企业"],
	"firm:regional_textile": ["factories", "civ.factory.textile.spinning", "纺织企业"],
	"firm:regional_upstream": ["factories", "civ.factory.food.flour_mill", "上游加工 · 外观代理"],
	"firm:regional_household": ["factories", "civ.factory.chemical.soap", "日用品企业"]}
var rows: Array[Dictionary] = []
var _cards: Dictionary = {}
var _points: Dictionary = {}
var _regional: bool = false
var _font: Font

static func observation(world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var e := world.economy_r1
	if e == null: return result
	for firm: String in MODELS:
		if not e._spec["firms"].has(firm): continue
		for site: String in e._spec["firms"][firm]["sites"]:
			if (e._spec["sites"][site].get("activities", []) as Array).is_empty(): continue
			var place_id := e._place(site)
			var place := world.spatial_world.get_place(place_id)
			var coordinates := place.get("lon_lat", []) as Array
			if coordinates.size() != 2: continue
			result.append({"id":site,"firm":firm,"place_id":place_id,"lon_lat":coordinates.duplicate(),
				"model":MODELS[firm],"title":MODELS[firm][2],"capacity":e.site_capacity(site),
				"base":e._spec["sites"][site]["capacity"],"produced":e._physical_totals[site]["produced"].duplicate(),
				"source":"economy_native.sites / capital_formation","basis":"GENERATED_SIMULATION_ASSUMPTION"})
	for task: Dictionary in e._capital_transport.tasks.values():
		if task["offer_id"] != "capital_carriage:lyon_paris": continue
		for anchor: String in ["place:lyon","place:paris"]:
			var coordinates := world.spatial_world.get_place(anchor).get("lon_lat",[]) as Array
			if coordinates.size()!=2: continue
			result.append({"id":str(task["id"])+anchor,"place_id":anchor,"lon_lat":coordinates.duplicate(),"model":["transport","civ.transport.rail.freight_station","物流货台 · 外观代理"],"title":"物流 · "+str(task["stage"]),"proxy":true,"source":str(task["id"]),"basis":"GENERATED_SIMULATION_ASSUMPTION"})
		var asset := e._capital.asset_state(task["asset_id"])
		if not str(asset.get("vehicle_id","")).is_empty() and task["stage"] in ["LOADING","TRANSIT","UNLOADING"]:
			# A connection marker at the origin anchor, never a claimed train GPS.
			var coordinates := world.spatial_world.get_place("place:lyon").get("lon_lat",[]) as Array
			result.append({"id":str(task["id"])+":vehicle","place_id":"place:lyon","lon_lat":coordinates.duplicate(),"model":["transport","civ.transport.rail.steam_freight_locomotive","实际载具 · 外观代理"],"title":"载具 · "+str(task["stage"]),"proxy":true,"source":str(task["id"])+" / "+str(asset["vehicle_id"]),"basis":"GENERATED_SIMULATION_ASSUMPTION"})
	return result

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/map/SourceHanSerifCN-Regular.otf") as Font

func present(points: Dictionary, regional: bool, near: bool) -> void:
	_points = points
	_regional = regional
	var wanted: Dictionary = {}
	var occupied: Array[Rect2] = []
	for row: Dictionary in rows:
		if not points.has(row["id"]): continue
		var point: Vector2 = points[row["id"]]
		if not Rect2(Vector2.ZERO,size).grow(-35).has_point(point): continue
		if not regional: continue
		var area := Rect2()
		for offset: Vector2 in [Vector2(18,-150),Vector2(-192,-150),Vector2(18,16),Vector2(-192,16),Vector2(206,-150),Vector2(-380,-150),Vector2(206,16),Vector2(-380,16),Vector2(18,-316),Vector2(-192,-316)]:
			var candidate := Rect2(point+offset,Vector2(174,142))
			if not Rect2(Vector2(20,70),size-Vector2(40,150)).encloses(candidate): continue
			var blocked := false
			for previous: Rect2 in occupied:
				if candidate.grow(5).intersects(previous): blocked = true; break
			if not blocked: area = candidate; break
		if not area.has_area(): continue
		occupied.append(area)
		wanted[row["id"]] = true
		var lod := "lod0" if near else "lod1"
		if _cards.has(row["id"]) and _cards[row["id"]]["lod"] != lod:
			(_cards[row["id"]]["node"] as Control).queue_free()
			_cards.erase(row["id"])
		if not _cards.has(row["id"]): _cards[row["id"]] = _card(row,lod)
		var card := _cards[row["id"]] as Dictionary
		(card["node"] as Control).position = area.position
		(card["label"] as Label).text = "%s\n%s\n显示假设 · 非建筑坐标" % [row["title"],"连接示意 · 非途中定位" if row.get("proxy",false) else "基础 %d · 有效 %d" % [row["base"],row["capacity"]]]
	for id: String in _cards.keys():
		if not wanted.has(id):
			(_cards[id]["node"] as Control).queue_free()
			_cards.erase(id)
	queue_redraw()

func _card(row: Dictionary, lod: String) -> Dictionary:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(174,142)
	add_child(box)
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = str(row["id"])+"\n"+str(row["source"])+"\n"+str(row["model"][1])+"\n显示假设，非历史厂址"
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index==MOUSE_BUTTON_LEFT: facility_selected.emit(row.duplicate(true)))
	panel.size = box.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06,0.13,0.14,0.94)
	style.border_color = Color(0.65,0.61,0.44)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel",style)
	box.add_child(panel)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192,108)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	box.add_child(viewport)
	var spec := row["model"] as Array
	var path := ROOT+str(spec[0])+"/"+str(spec[1])+"/"+str(spec[1])+"_"+lod+".glb"
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var model: Node3D
	# Prefer Godot's imported/remapped PackedScene, including exported builds.
	# Fresh source checkouts can display a raw GLB before the editor imports it.
	var packed := ResourceLoader.load(path,"PackedScene") as PackedScene if ResourceLoader.exists(path,"PackedScene") else null
	var error: Error = OK
	if packed != null: model = packed.instantiate() as Node3D
	elif FileAccess.file_exists(path):
		error = document.append_from_file(path,state)
		if error == OK: model = document.generate_scene(state)
	else: error = ERR_FILE_NOT_FOUND
	if model != null:
		viewport.add_child(model)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		viewport.add_child(camera)
		var bounds := AABB()
		var pending: Array[Node] = [model]
		var found := false
		while not pending.is_empty():
			var child := pending.pop_back() as Node
			for nested: Node in child.get_children(): pending.append(nested)
			if child is MeshInstance3D:
				var mesh := child as MeshInstance3D
				var box_bounds: AABB = mesh.global_transform*mesh.get_aabb()
				bounds = bounds.merge(box_bounds) if found else box_bounds
				found = true
		var extent := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		camera.size = maxf(8.0,extent*0.95)
		camera.position = bounds.get_center()+Vector3(1.3,1.0,1.6)*extent
		camera.look_at(bounds.get_center())
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50,-35,0)
		light.light_energy = 1.5
		viewport.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.8,0.85,0.9)
		environment.environment.ambient_light_energy = 0.6
		environment.environment.sky = Sky.new()
		environment.environment.sky.sky_material = ProceduralSkyMaterial.new()
		environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		viewport.add_child(environment)
	else: push_warning("Civilian model import failed: "+path+" error="+str(error))
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.size = Vector2(174,86)
	box.add_child(image)
	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.position = Vector2(8,82)
	caption.add_theme_font_override("font",_font)
	caption.add_theme_font_size_override("font_size",13)
	caption.add_theme_color_override("font_color",Color(0.96,0.94,0.82))
	box.add_child(caption)
	return {"node":box,"label":caption,"lod":lod}

func _draw() -> void:
	if not _regional and not _points.is_empty():
		draw_string(_font,Vector2(22,92),"民用设施 · 城市锚点代理，非厂址",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.93,0.89,0.70))
	for row: Dictionary in rows:
		if not _points.has(row["id"]): continue
		var point: Vector2 = _points[row["id"]]
		if _regional and _cards.has(row["id"]):
			var box := _cards[row["id"]]["node"] as Control
			draw_line(point,box.position+Vector2(0,70),Color(0.78,0.72,0.51,0.8),1.0,true)
		elif not _regional:
			# WORLD has a cheap facility symbol; no GLBs stay resident.
			draw_rect(Rect2(point+Vector2(6,-6),Vector2(10,7)),Color(0.90,0.80,0.51))
			draw_line(point+Vector2(14,-5),point+Vector2(14,-11),Color(0.90,0.80,0.51),2.0)
