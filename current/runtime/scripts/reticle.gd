extends Node2D
func _draw():
	var center:=get_viewport_rect().size*.5
	var viewport_size:=get_viewport_rect().size
	var radius:=viewport_size.y*.43
	for i in range(64):
		var a:=TAU*i/64.0;var b:=TAU*(i+1)/64.0
		var va:=Vector2(cos(a),sin(a));var vb:=Vector2(cos(b),sin(b))
		draw_colored_polygon(PackedVector2Array([center+va*radius,center+vb*radius,center+vb*viewport_size.length(),center+va*viewport_size.length()]),Color(0,0,0,.92))
	draw_arc(center,radius,0,TAU,96,Color(.18,.21,.19),8,true)
	var color:=Color(.9,.94,.84,.9)
	for offset in range(8,69,12):
		for direction in [-1,1]:
			draw_line(center+Vector2(offset*direction,0),center+Vector2((offset+6)*direction,0),color,1.5)
			draw_line(center+Vector2(0,offset*direction),center+Vector2(0,(offset+6)*direction),color,1.5)

func _process(_delta:float):
	if visible:queue_redraw()
