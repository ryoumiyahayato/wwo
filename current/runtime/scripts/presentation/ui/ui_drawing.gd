class_name UIDrawing
extends RefCounted
## Shared drawing primitives; no world data or input state.

static func create_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "Microsoft JhengHei", "SimSun"])
	return font

static func panel(canvas: CanvasItem, rect: Rect2, fill: Color, border: Color) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(rect, border, false, 1.0)

static func label(canvas: CanvasItem, font: Font, point: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0), width: float = -1.0) -> void:
	canvas.draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

static func archive_drawer(canvas: CanvasItem, rect: Rect2, style: Dictionary) -> void:
	canvas.draw_rect(rect,style.body as Color)
	var edge := style.metal as Color
	edge.a = 0.55
	canvas.draw_line(rect.position+Vector2(1,6),Vector2(rect.position.x+1,rect.end.y-6),edge,1,true)
	canvas.draw_line(rect.position+Vector2(9,3),Vector2(rect.end.x,rect.position.y+3),style.seam,3,true)
	canvas.draw_line(Vector2(rect.position.x+9,rect.end.y-3),rect.end-Vector2(0,3),style.seam,3,true)
	canvas.draw_line(rect.position+Vector2(14,59),Vector2(rect.end.x-36,rect.position.y+59),Color(0.39,0.57,0.56,0.25),1,true)
	for y: float in [12.0,rect.size.y-12.0]:
		canvas.draw_circle(rect.position+Vector2(7,y),1.7,style.bronze)
		canvas.draw_line(rect.position+Vector2(6,y),rect.position+Vector2(8,y),style.highlight,0.7,true)

static func archive_handle(canvas: CanvasItem, rect: Rect2, style: Dictionary, opened: bool, hovered: bool) -> void:
	var shape := PackedVector2Array([Vector2(7,0),Vector2(rect.size.x,0),rect.size,Vector2(7,rect.size.y),Vector2(0,rect.size.y-8),Vector2(0,8)])
	canvas.draw_colored_polygon(shape,Color(0.07,0.12,0.14,0.98) if hovered else style.body)
	canvas.draw_polyline(PackedVector2Array([Vector2(7,1),Vector2(1,8),Vector2(1,rect.size.y-8),Vector2(7,rect.size.y-1)]),style.highlight if hovered else style.metal,1,true)
	var middle := rect.get_center()
	for offset: float in [-9.0,0.0,9.0]: canvas.draw_line(middle+Vector2(-3,offset),middle+Vector2(3,offset),style.muted,1,true)
	var sign := 1.0 if opened else -1.0
	canvas.draw_polyline(PackedVector2Array([middle+Vector2(-sign*2,-23),middle+Vector2(sign*2,-19),middle+Vector2(-sign*2,-15)]),style.highlight,1,true)

static func archive_notice(canvas: CanvasItem, rect: Rect2, style: Dictionary, attention: bool) -> void:
	canvas.draw_rect(rect,style.body)
	canvas.draw_line(Vector2(2,10),Vector2(2,rect.size.y-10),style.status if attention else style.teal,2,true)
	canvas.draw_line(Vector2(12,rect.size.y-2),Vector2(rect.size.x-12,rect.size.y-2),Color(0.58,0.47,0.29,0.24),1,true)

static func nautical_globe(canvas: CanvasItem, center: Vector2, radius: float, glow: float = 0.0) -> void:
	var brass := InterfaceSettings.theme_parameters().brass as Color
	brass.a = 1.0
	var bronze := Color(0.22,0.15,0.075,1.0)
	var gold := brass.lerp(Color(0.72,0.51,0.23,1.0),0.45)
	var glint := Color(0.87,0.75,0.48,0.86)
	var seam := Color(0.045,0.037,0.025,0.94)
	var scale := radius/64.0
	if glow>0.001:
		canvas.draw_arc(center,radius+1,PI,TAU,48,Color(0.47,0.71,0.61,0.08*glow),5,true)

	# The oblique meridian stays at the limb, leaving the moving land surface clear.
	var tilt := deg_to_rad(18.0)
	var meridian := Vector2(radius*0.94,radius*1.08)
	var crossing := atan2(meridian.x*sin(tilt),meridian.y*cos(tilt))
	_nautical_band(canvas,center,meridian,PI-crossing+0.10,PI*1.58,2.8*scale,bronze,gold.darkened(0.35),glint.darkened(0.42),tilt)
	_nautical_band(canvas,center,Vector2.ONE*(radius+0.8*scale),PI,TAU,2.0*scale,seam,bronze,gold)

	# A cast outer yoke and its inset graduation track have separate bevels.
	var yoke_radius := radius+14.0*scale
	_nautical_band(canvas,center,Vector2.ONE*yoke_radius,PI,TAU,7.0*scale,bronze,gold,glint)
	canvas.draw_arc(center,radius+8.8*scale,PI+0.07,TAU-0.07,56,seam,1.1*scale,true)
	canvas.draw_arc(center,radius+9.5*scale,PI+0.07,TAU-0.07,56,gold.darkened(0.22),0.8*scale,true)
	for index: int in range(1,24):
		var angle := PI+PI*float(index)/24.0
		var direction := Vector2(cos(angle),sin(angle))
		var major := index%4==0
		var inner := center+direction*(radius+(10.7 if major else 12.5)*scale)
		var outer := center+direction*(radius+15.4*scale)
		canvas.draw_line(inner+Vector2(0.4,0.5)*scale,outer+Vector2(0.4,0.5)*scale,seam,1.6*scale if major else 1.0*scale,true)
		canvas.draw_line(inner,outer,glint if major else gold.lightened(0.12),1.0*scale if major else 0.65*scale,true)
	_nautical_band(canvas,center,meridian,PI*1.58,TAU-crossing-0.10,3.0*scale,bronze,gold,glint,tilt)

	# Only the polar spindle is exposed; there is no bar through the globe face.
	var axis := Vector2(sin(tilt),-cos(tilt))
	var axle_start := center+axis*(radius-0.6*scale)
	var axle_end := center+axis*(radius+18.0*scale)
	var tangent := Vector2(-axis.y,axis.x)
	canvas.draw_line(axle_start+Vector2(1,1)*scale,axle_end+Vector2(1,1)*scale,seam,5.8*scale,true)
	canvas.draw_line(axle_start,axle_end,bronze,4.6*scale,true)
	canvas.draw_line(axle_start,axle_end,gold,2.8*scale,true)
	canvas.draw_line(axle_start-tangent*0.7*scale,axle_end-tangent*0.7*scale,glint,0.9*scale,true)
	var collar := center+axis*(radius+5.2*scale)
	canvas.draw_line(collar-tangent*3.6*scale,collar+tangent*3.6*scale,bronze,3.4*scale,true)
	canvas.draw_line(collar-tangent*3.3*scale-axis*0.7*scale,collar+tangent*3.3*scale-axis*0.7*scale,glint,1.0*scale,true)
	var polar_hub := center+axis*(radius+14.0*scale)
	canvas.draw_circle(polar_hub,4.4*scale,bronze)
	canvas.draw_arc(polar_hub,3.4*scale,0,TAU,20,gold,1.4*scale,true)
	canvas.draw_circle(polar_hub,1.3*scale,seam)
	canvas.draw_arc(polar_hub,4.1*scale,PI*1.06,PI*1.80,12,glint,0.8*scale,true)

	# Side journals connect the yoke to a low curved shoe at the screen edge.
	for side: float in [-1.0,1.0]:
		var bearing := center+Vector2(side*(radius+13.6*scale),-8.2*scale)
		var foot := center+Vector2(side*(radius+17.0*scale),-0.8*scale)
		canvas.draw_line(bearing,foot,seam,8.0*scale,true)
		canvas.draw_line(bearing,foot,bronze,6.0*scale,true)
		canvas.draw_line(bearing-Vector2(0.6,0),foot-Vector2(0.6,0),gold,2.5*scale,true)
		canvas.draw_circle(bearing+Vector2(0.8,0.9)*scale,6.4*scale,seam)
		canvas.draw_circle(bearing,5.7*scale,bronze)
		canvas.draw_circle(bearing,4.4*scale,gold)
		canvas.draw_arc(bearing,5.2*scale,PI*1.06,PI*1.88,18,glint,0.9*scale,true)
		canvas.draw_circle(bearing,2.9*scale,seam)
		canvas.draw_circle(bearing,2.1*scale,gold.darkened(0.12))
		canvas.draw_line(bearing+Vector2(-1.1,-0.3)*scale,bearing+Vector2(1.1,0.3)*scale,seam,0.8*scale,true)
		canvas.draw_circle(bearing+Vector2(-0.6,-0.7)*scale,0.7*scale,glint)
	var base_center := center+Vector2(0,5.0*scale)
	var base_radii := Vector2(radius+22.0*scale,12.0*scale)
	var shoe := PackedVector2Array()
	for index: int in range(33):
		var angle := PI+PI*float(index)/32.0
		shoe.append(base_center+Vector2(cos(angle)*base_radii.x,sin(angle)*base_radii.y))
	canvas.draw_colored_polygon(shoe,bronze.darkened(0.26))
	_nautical_band(canvas,base_center,base_radii,PI+0.30,TAU-0.30,3.8*scale,seam,gold.darkened(0.18),glint)

static func _nautical_band(canvas: CanvasItem, center: Vector2, radii: Vector2, start: float, end: float, width: float, dark: Color, face: Color, edge: Color, tilt: float = 0.0) -> void:
	var steps := clampi(int(ceil((end-start)*maxf(radii.x,radii.y)/4.0)),12,72)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var middle := PackedVector2Array()
	var outside_colors := PackedColorArray()
	var inside_colors := PackedColorArray()
	var light := Vector2(-0.55,-0.84)
	for index: int in range(steps+1):
		var angle := lerpf(start,end,float(index)/float(steps))
		var normal := Vector2(cos(angle)/radii.x,sin(angle)/radii.y).rotated(tilt).normalized()
		var point := center+Vector2(cos(angle)*radii.x,sin(angle)*radii.y).rotated(tilt)
		var reflection := clampf(normal.dot(light)*0.5+0.5,0.0,1.0)
		outer.append(point+normal*width*0.5)
		inner.append(point-normal*width*0.5)
		middle.append(point+Vector2(0.6,0.9))
		outside_colors.append(face.lerp(edge,reflection*0.30))
		inside_colors.append(dark.lerp(face,0.45+reflection*0.32))
	canvas.draw_polyline(middle,Color(0.025,0.021,0.014,0.8),width+1.6,true)
	var surface := outer.duplicate()
	var colors := outside_colors.duplicate()
	for index: int in range(inner.size()-1,-1,-1):
		surface.append(inner[index])
		colors.append(inside_colors[index])
	canvas.draw_polygon(surface,colors)
	canvas.draw_polyline(inner,dark,0.8,true)
	canvas.draw_polyline(outer,edge,0.8,true)

static func _ellipse_points(center: Vector2, radii: Vector2, steps: int = 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in range(steps):
		var angle := TAU*float(index)/float(steps)
		points.append(center+Vector2(cos(angle)*radii.x,sin(angle)*radii.y))
	return points

static func _closed_outline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline,color,width,true)

static func _instrument_hub(canvas: CanvasItem, center: Vector2, radius: float, palette: Dictionary) -> void:
	canvas.draw_circle(center+Vector2(0.6,1.0),radius+1.0,palette.seam as Color)
	canvas.draw_circle(center,radius,palette.bronze as Color)
	canvas.draw_circle(center,radius-1.2,palette.metal as Color)
	canvas.draw_arc(center,radius-0.5,PI*1.10,PI*1.95,12,palette.highlight as Color,0.9,true)
	canvas.draw_circle(center,1.3,palette.seam as Color)
	canvas.draw_line(center+Vector2(-1.6,-0.3),center+Vector2(1.6,0.3),palette.bronze as Color,0.8,true)

static func quarter_clock_frame(canvas: CanvasItem, corner: Vector2, radius: float, palette: Dictionary) -> void:
	# A face-on quadrant: its centre is at the top-right screen edge.
	var face := PackedVector2Array([corner])
	for index: int in range(65):
		var angle := PI*0.5+PI*0.5*float(index)/64.0
		face.append(corner+Vector2(cos(angle),sin(angle))*radius)
	canvas.draw_colored_polygon(face,palette.body as Color)
	canvas.draw_arc(corner+Vector2(-1,1),radius,PI*0.5,PI,64,palette.seam as Color,10.0,true)
	canvas.draw_arc(corner,radius-1,PI*0.5,PI,64,palette.bronze as Color,8.0,true)
	canvas.draw_arc(corner,radius-2.0,PI*0.5,PI,64,palette.metal as Color,4.5,true)
	canvas.draw_arc(corner,radius,PI*0.5,PI,64,palette.highlight as Color,0.9,true)
	canvas.draw_arc(corner,radius-11,PI*0.5+0.025,PI-0.025,64,palette.bronze as Color,0.8,true)
	for index: int in range(1,40):
		var angle := PI*0.5+PI*0.5*float(index)/40.0
		var direction := Vector2(cos(angle),sin(angle))
		var major := index%5==0
		canvas.draw_line(corner+direction*(radius-(18.0 if major else 13.5)),corner+direction*(radius-5),palette.highlight as Color if major else palette.metal as Color,1.2 if major else 0.65,true)
	_instrument_hub(canvas,corner+Vector2(-10,10),5.0,palette)
	_instrument_hub(canvas,corner+Vector2(-radius+8,4),3.0,palette)
	_instrument_hub(canvas,corner+Vector2(-4,radius-8),3.0,palette)

static func quarter_clock_indicator(canvas: CanvasItem, corner: Vector2, radius: float, palette: Dictionary, minute_of_day: int, paused: bool) -> void:
	# The indicator travels along the rim; no hand crosses the date or controls.
	var phase := float(posmod(minute_of_day,1440))/1440.0
	var angle := PI-PI*0.5*phase
	var direction := Vector2(cos(angle),sin(angle))
	var tangent := Vector2(-direction.y,direction.x)
	var tip := corner+direction*(radius-20)
	canvas.draw_colored_polygon(PackedVector2Array([tip,tip+direction*12+tangent*3,tip+direction*12-tangent*3]),palette.status as Color if paused else palette.highlight as Color)

static func history_track_frame(canvas: CanvasItem, rect: Rect2, palette: Dictionary) -> void:
	var line := PackedVector2Array()
	var echo := PackedVector2Array()
	for index: int in range(49):
		var t := float(index)/48.0
		var point := rect.position+Vector2(rect.size.x*t,rect.size.y*4.0*t*(1.0-t))
		line.append(point)
		echo.append(point-Vector2(0,4))
	var teal := palette.teal as Color
	teal.a = 0.24
	canvas.draw_polyline(echo,teal,0.7,true)
	canvas.draw_polyline(line,palette.metal as Color,1.0,true)
	# These short graduations belong to the instrument, not to event records.
	for index: int in range(1,12):
		var t := float(index)/12.0
		var point := rect.position+Vector2(rect.size.x*t,rect.size.y*4.0*t*(1.0-t))
		var normal := Vector2(-rect.size.y*4.0*(1.0-2.0*t),rect.size.x).normalized()
		canvas.draw_line(point,point+normal*(4.0 if index%3==0 else 2.0),teal,0.8,true)
	var end := Vector2(rect.end.x,rect.position.y)
	canvas.draw_arc(end,6.0,0,TAU,24,palette.bronze as Color,2.0,true)
	canvas.draw_arc(end,5.0,0,TAU,24,palette.highlight as Color,0.8,true)
	canvas.draw_circle(end,2.0,palette.ivory as Color)
	canvas.draw_line(end+Vector2(0,8),end+Vector2(0,13),palette.metal as Color,0.8,true)

static func history_track_indicator(canvas: CanvasItem, rect: Rect2, palette: Dictionary, minute_of_day: int) -> void:
	var end := Vector2(rect.end.x,rect.position.y)
	var angle := -PI*0.5+TAU*float(posmod(minute_of_day,1440))/1440.0
	canvas.draw_line(end,end+Vector2(cos(angle),sin(angle))*4.0,palette.teal as Color,1.0,true)

static func portrait_cameo(canvas: CanvasItem, rect: Rect2, palette: Dictionary, active: bool) -> void:
	var center := rect.get_center()
	var radii := rect.size*0.5-Vector2(4,4)
	var outer := _ellipse_points(center,radii)
	canvas.draw_colored_polygon(_ellipse_points(center+Vector2(1,2),radii+Vector2(2,2)),palette.seam as Color)
	canvas.draw_colored_polygon(outer,palette.bronze as Color)
	canvas.draw_colored_polygon(_ellipse_points(center,radii-Vector2(3,3)),palette.metal as Color)
	canvas.draw_colored_polygon(_ellipse_points(center,radii-Vector2(6,6)),palette.body as Color)
	_closed_outline(canvas,outer,palette.highlight as Color if active else palette.metal as Color,1.1)
	_closed_outline(canvas,_ellipse_points(center,radii-Vector2(5,5)),palette.highlight as Color,0.7)
	# Only a centred head and connected shoulders occupy the interior.
	var figure := palette.muted as Color
	figure.a = 0.90
	canvas.draw_colored_polygon(_ellipse_points(center+Vector2(0,-12),Vector2(8,10),24),figure)
	var body := PackedVector2Array([Vector2(-4,-4),Vector2(4,-4),Vector2(5,3),Vector2(16,9),Vector2(19,22),Vector2(10,27),Vector2(-10,27),Vector2(-19,22),Vector2(-16,9),Vector2(-5,3)])
	for index: int in range(body.size()): body[index] += center
	canvas.draw_colored_polygon(body,figure)

static func portrait_action(canvas: CanvasItem, center: Vector2, palette: Dictionary, kind: String, active: bool) -> void:
	var color := palette.highlight as Color if active else palette.muted as Color
	canvas.draw_circle(center,13,palette.body as Color)
	canvas.draw_arc(center,12,0,TAU,24,palette.metal as Color,0.8,true)
	match kind:
		"details":
			canvas.draw_arc(center+Vector2(0,-4),3,0,TAU,12,color,1.2,true)
			canvas.draw_arc(center+Vector2(0,6),6,PI,TAU,16,color,1.2,true)
		"accounts":
			canvas.draw_rect(Rect2(center-Vector2(6,7),Vector2(12,14)),color,false,1.1)
			canvas.draw_line(center+Vector2(-2,-7),center+Vector2(-2,7),color,0.8,true)
			canvas.draw_line(center+Vector2(1,-3),center+Vector2(4,-3),color,0.8,true)
			canvas.draw_line(center+Vector2(1,2),center+Vector2(4,2),color,0.8,true)
		"relations":
			for point: Vector2 in [Vector2(-6,4),Vector2(0,-6),Vector2(6,4)]:
				canvas.draw_line(center,center+point,color,0.8,true)
				canvas.draw_arc(center+point,2.3,0,TAU,12,color,1.0,true)

static func instrument_button(canvas: CanvasItem, rect: Rect2, palette: Dictionary, hovered: bool, selected: bool) -> void:
	var p := rect.position
	var e := rect.end
	var shape := PackedVector2Array([p+Vector2(5,0),Vector2(e.x-5,p.y),Vector2(e.x,p.y+5),e-Vector2(0,5),e-Vector2(5,0),Vector2(p.x+5,e.y),Vector2(p.x,e.y-5),p+Vector2(0,5)])
	canvas.draw_colored_polygon(shape,palette.teal as Color if selected else (palette.body as Color).lightened(0.08) if hovered else palette.body as Color)
	_closed_outline(canvas,shape,palette.highlight as Color if hovered or selected else palette.bronze as Color,0.9)
	if selected: canvas.draw_line(p+Vector2(8,rect.size.y-3),e-Vector2(8,3),palette.highlight as Color,1.0,true)

static func shell_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf")
	theme.default_font_size = 15
	var palette := InterfaceSettings.theme_parameters()
	for type: String in ["Button","OptionButton"]:
		for state: String in ["normal","hover","pressed","disabled","focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = palette.button as Color if state=="normal" else palette.button_hover as Color
			box.border_color = palette.brass as Color if state in ["hover","pressed","focus"] else Color(0.48,0.43,0.28,0.38)
			box.set_border_width_all(1)
			box.set_corner_radius_all(3)
			box.content_margin_left = 14
			box.content_margin_right = 14
			box.content_margin_top = 9
			box.content_margin_bottom = 9
			theme.set_stylebox(state,type,box)
		for key: String in ["font_color","font_hover_color","font_pressed_color"]: theme.set_color(key,type,palette.ink as Color)
		theme.set_color("font_disabled_color",type,Color(0.46,0.49,0.43))
	theme.set_color("font_color","Label",Color(0.86,0.83,0.73))
	var popup := StyleBoxFlat.new()
	popup.bg_color = palette.panel as Color
	popup.border_color = Color(0.60,0.51,0.31,0.65)
	popup.set_border_width_all(1)
	popup.content_margin_left = 8
	popup.content_margin_right = 8
	popup.content_margin_top = 8
	popup.content_margin_bottom = 8
	theme.set_stylebox("panel","PopupMenu",popup)
	theme.set_stylebox("hover","PopupMenu",theme.get_stylebox("hover","Button"))
	theme.set_color("font_color","PopupMenu",Color(0.86,0.83,0.73))
	theme.set_color("font_hover_color","PopupMenu",Color(0.96,0.89,0.69))
	theme.set_color("font_color","CheckButton",Color(0.86,0.83,0.73))
	return theme

static func location_diagram(canvas: CanvasItem, rect: Rect2, lon_lat: Vector2) -> void:
	canvas.draw_rect(rect,Color(0.06,0.12,0.12,0.65))
	for index: int in range(1,6):
		var x := rect.position.x+rect.size.x*float(index)/6.0
		canvas.draw_line(Vector2(x,rect.position.y),Vector2(x,rect.end.y),Color(0.49,0.65,0.57,0.24))
	for index: int in range(1,4):
		var y := rect.position.y+rect.size.y*float(index)/4.0
		canvas.draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),Color(0.49,0.65,0.57,0.24))
	var point := rect.position+Vector2((wrapf(lon_lat.x,-180,180)+180)/360.0,(90-lon_lat.y)/180.0)*rect.size
	canvas.draw_circle(point,3,Color(0.97,0.80,0.42))
	canvas.draw_arc(point,7,0,TAU,24,Color(0.97,0.80,0.42,0.65),1,true)
