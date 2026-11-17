extends Node2D
## Detached direction display, never cargo positions. Cosmetic rail glow updates
## only this CanvasItem; it does not redraw terrain or advance the world clock.
var paths: Array[Dictionary] = []
var world_minute: int = 0
var enabled: bool = true
var ship_hits: Array[Rect2] = []
var _visual_phase: float = 0.0
var _redraw_elapsed: float = 0.0

func _ready() -> void:
	set_process(false)

func update_paths(value: Array[Dictionary]) -> void:
	if paths==value:return
	paths=value
	for path: Dictionary in paths:
		var points: PackedVector2Array=path.get("points",PackedVector2Array())
		var lengths := PackedFloat32Array([0.0])
		for index: int in range(1,points.size()): lengths.append(lengths[-1]+points[index-1].distance_to(points[index]))
		path["lengths"]=lengths
	set_process(enabled and paths.any(func(path: Dictionary)->bool: return bool(path.get("rail",false)) or bool(path.get("ship",false))))
	queue_redraw()

func set_world_minute(value: int) -> void:
	if world_minute==value:return
	world_minute=value
	if enabled and not paths.is_empty():queue_redraw()

func set_enabled(value: bool) -> void:
	if enabled==value:return
	enabled=value
	set_process(enabled and paths.any(func(path: Dictionary)->bool: return bool(path.get("rail",false)) or bool(path.get("ship",false))))
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_visual_phase=fmod(_visual_phase+delta*32.0,65536.0)
	_redraw_elapsed+=delta
	if _redraw_elapsed<1.0/30.0: return
	_redraw_elapsed=0.0
	queue_redraw()

func _point_at(path: Dictionary, distance: float) -> Vector2:
	var points: PackedVector2Array=path.points
	var lengths: PackedFloat32Array=path.lengths
	var low := 1
	var high := lengths.size()-1
	while low<high:
		var middle := (low+high)/2
		if lengths[middle]<distance: low=middle+1
		else: high=middle
	var segment := lengths[low]-lengths[low-1]
	return points[low-1].lerp(points[low],clampf((distance-lengths[low-1])/maxf(.001,segment),0.0,1.0))

func _draw_rail_glow(path: Dictionary) -> void:
	var length := float(path.length)
	if length<2.0: return
	for direction: int in path.get("directions",[1]):
		var distance := fmod(_visual_phase,180.0)
		var count := 0
		while distance<length and count<12:
			var along := distance if direction>0 else length-distance
			var point := _point_at(path,along)
			draw_circle(point,4.0,Color(.63,.84,.78,.09))
			draw_circle(point,2.5,Color(.69,.89,.82,.22))
			draw_circle(point,1.25,Color(.88,.96,.85,.90))
			distance+=180.0;count+=1

func _draw() -> void:
	ship_hits.clear()
	if not enabled:return
	for path:Dictionary in paths:
		var points:PackedVector2Array=path.get("points",PackedVector2Array())
		if points.size()<2:continue
		if bool(path.get("ship",false)):
			_draw_ship(path)
			continue
		if bool(path.get("rail",false)):
			_draw_rail_glow(path)
			continue
		var observed:=int(path.get("observed_minute",0))
		if observed>world_minute or world_minute-observed>7*1440:continue
		var phase:=float(posmod(world_minute-observed,240))/240.0
		var distance:=float(path.get("length",0.0))*phase
		for index:int in range(1,points.size()):
			var segment:=points[index-1].distance_to(points[index])
			if distance>segment:distance-=segment;continue
			if segment<.1:continue
			var direction:Vector2=(points[index]-points[index-1])/segment
			var tip:=points[index-1]+direction*distance
			var normal:=Vector2(-direction.y,direction.x)
			var color:=Color("8ec6a1")
			draw_line(tip-direction*4.0,tip+direction*4.0,color,2.4,true)
			draw_line(tip+direction*4.0,tip-direction+normal*3.0,color,1.8,true)
			draw_line(tip+direction*4.0,tip-direction-normal*3.0,color,1.8,true)
			break

func _draw_ship(path: Dictionary) -> void:
	var length := float(path.length)
	if length<24.0: return
	var margin := minf(18.0,length*.25)
	var distance := margin+fmod(_visual_phase*.40,length-2.0*margin)
	if int((path.get("directions",[1]) as Array)[0])<0: distance=length-distance
	var point := _point_at(path,distance)
	var direction := (_point_at(path,minf(length,distance+1.0))-_point_at(path,maxf(0,distance-1.0))).normalized()
	if int((path.get("directions",[1]) as Array)[0])<0: direction=-direction
	var normal := Vector2(-direction.y,direction.x)
	draw_line(point-direction*5.0+normal*1.2,point-direction*11.0+normal*2.5,Color(.73,.84,.81,.26),1,true)
	draw_line(point-direction*5.0-normal*1.2,point-direction*11.0-normal*2.5,Color(.73,.84,.81,.26),1,true)
	var hull := PackedVector2Array([point+direction*7.0,point+direction*3.0+normal*2.7,point-direction*5.0+normal*2.7,point-direction*6.0,point-direction*5.0-normal*2.7,point+direction*3.0-normal*2.7])
	draw_colored_polygon(hull,Color("c8c0a0"))
	var outline := hull.duplicate();outline.append(hull[0])
	draw_polyline(outline,Color("344343"),.8,true)
	draw_line(point-direction*3.0,point+direction*3.0,Color("7a5c43"),2.4,true)
	draw_circle(point-direction*1.5,1.0,Color("343f3f"))
	ship_hits.append(Rect2(point-Vector2(9,9),Vector2(18,18)))
