extends Node2D
## Schematic direction pulses for confirmed historical receipts, NOT cargo positions.
## Receives detached screen paths and authoritative world minutes. No processing,
## wall clock, world reference, simulation or SubViewport update mode changes.
var paths: Array[Dictionary] = []
var world_minute: int = 0
var enabled: bool = true

func update_paths(value: Array[Dictionary]) -> void:
	if paths==value:return
	paths=value
	queue_redraw()

func set_world_minute(value: int) -> void:
	if world_minute==value:return
	world_minute=value
	if enabled and not paths.is_empty():queue_redraw()

func set_enabled(value: bool) -> void:
	if enabled==value:return
	enabled=value;queue_redraw()

func _draw() -> void:
	if not enabled:return
	for path:Dictionary in paths:
		var points:PackedVector2Array=path.get("points",PackedVector2Array())
		if points.size()<2:continue
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
