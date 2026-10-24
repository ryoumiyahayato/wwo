extends Control
signal selected(point: Vector2)
var space: RefCounted
var bounds := Rect2(0,0,50000,50000)
var selected_point := Vector2(22500,22500)
var unit_point := Vector2(22500,22500)
var font: Font
var admin_mode := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	font=load("res://cedar/system_font.tres")

func project(point: Vector2) -> Vector2:
	return (point-bounds.position)/bounds.size*size

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not admin_mode:
		selected_point=bounds.position+event.position/size*bounds.size
		selected.emit(selected_point)
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("172322"))
	if space==null: return
	if admin_mode:
		_draw_admin()
		return
	var step := 25000.0 if bounds.size.x>25000 else 5000.0
	for tile: Dictionary in space.tiles:
		var world_rect: Rect2=space.rect(tile)
		if not bounds.encloses(world_rect): continue
		var screen_rect:=Rect2(project(world_rect.position),world_rect.size/bounds.size*size)
		if space.textures.has(tile.id): draw_texture_rect(space.textures[tile.id],screen_rect,false)
		for road: Variant in space.roads(tile):
			var points:=PackedVector2Array()
			var source: Array=road.get("points",road.get("points_uv",[])) if road is Dictionary else road
			for p: Array in source:
				var local:=Vector2(p[0],p[1])
				if tile.profile=="atlas15": local=(local-Vector2.ONE*.5)*5000
				points.append(project(world_rect.get_center()+local))
			if points.size()>1: draw_polyline(points,Color("d4b273"),1.7,true)
		if tile.profile=="rivergate": _draw_river(world_rect)
		draw_rect(screen_rect,Color("a5b69b"),false,1.2)
		draw_string(font,screen_rect.position+Vector2(5,16),tile.name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("f3ebce"))
	for i: int in int(bounds.size.x/step)+1:
		var x:=i*step/bounds.size.x*size.x
		var y:=i*step/bounds.size.y*size.y
		draw_line(Vector2(x,0),Vector2(x,size.y),Color("52635b"),1)
		draw_line(Vector2(0,y),Vector2(size.x,y),Color("52635b"),1)
	var selected_size:=Vector2.ONE*step
	var origin: Vector2=(selected_point/step).floor()*step
	var selected_rect:=Rect2(project(origin),selected_size/bounds.size*size)
	draw_rect(selected_rect,Color(.91,.74,.38,.12))
	draw_rect(selected_rect,Color("e7bd68"),false,3)
	if bounds.has_point(unit_point):
		var p:=project(unit_point)
		draw_circle(p,6,Color("71e0dd"))
		draw_arc(p,11,0,TAU,32,Color("132b2c"),2)
		draw_string(font,p+Vector2(-110,-17),"原车 / 5人车组",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("96efeb"))
	for row: int in int(bounds.size.y/step):
		for col: int in int(bounds.size.x/step):
			var p:=Vector2(col+.5,row+.5)*step+bounds.position
			if step==25000:
				var id: Vector2i=space.sector_at(p)
				draw_string(font,project(p)-Vector2(78,34),"战区 S%d%d · 25×25 km"%[id.x,id.y],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("b4c5b5"))
			elif space.tile_at(p).is_empty():
				draw_string(font,project(p)-Vector2(21,0),"未制作",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("53675f"))
	draw_string(font,Vector2(10,size.y-12),"N ↑     X 向东 / Z 向南    米制训练坐标",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("dee4d4"))

func _draw_river(world_rect: Rect2) -> void:
	var bridge: Dictionary=space.hydro.get("bridge",{})
	if not bridge.is_empty():
		var p:=project(world_rect.get_center()+Vector2(bridge.center_x,bridge.center_z))
		draw_circle(p,4,Color("8fd4df"))

func _draw_admin() -> void:
	var center:=size*.5
	var radius:=minf(size.x,size.y)*.43
	draw_circle(center,radius,Color("263e43"))
	for latitude: int in [-60,-30,0,30,60]:
		var y:=sin(deg_to_rad(float(latitude)))
		var width:=sqrt(1-y*y)*radius
		draw_line(center+Vector2(-width,-y*radius),center+Vector2(width,-y*radius),Color("486466"),1)
	for city: Dictionary in space.admin.get("cities",[]):
		var ll: Array=city.lon_lat
		var lat:=deg_to_rad(float(ll[1]))
		var lon:=deg_to_rad(float(ll[0])-10.0)
		if cos(lat)*cos(lon)<0: continue
		var point:=center+Vector2(cos(lat)*sin(lon),-sin(lat))*radius
		draw_circle(point,3 if city.id!="paris" else 6,Color("e3c582"))
		if city.id in ["paris","lyon","berlin","london","moscow","istanbul"]:
			draw_string(font,point+Vector2(8,3),city.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e6e6d2"))
	draw_string(font,Vector2(15,size.y-14),"WWO现有行政地点引用 / 只读球面示意",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("ccd6c9"))
