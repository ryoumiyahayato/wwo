class_name UIDrawing
extends RefCounted

const FOLIO_PAPER := Color("eee5cf")
const FOLIO_SHADE := Color("36393a")
const FOLIO_INK := Color("eee5cf")
const FOLIO_MUTED := Color("b6bcba")
const FOLIO_RULE := Color("8e7751")
const FOLIO_BINDING := Color("282b2d")
const FOLIO_BRASS := Color("bd9858")
const FOLIO_BACKGROUND := Color(0.13,0.13,0.14,0.86)
const ENAMEL := Color("142532")
const BRASS_SHADOW := Color("594022")
const BRASS_LIGHT := Color("e6c888")
const FOLIO_HEADER_HEIGHT := 54.0
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
enum Folio { GENERAL, MARKET, POLITICS }
const FOLIO_ART := {
	Folio.GENERAL: {"texture":"folio","crest":Rect2(186,0,715,202)},
	Folio.MARKET: {"texture":"market","crest":Rect2(138,0,810,190)},
	Folio.POLITICS: {"texture":"politics","crest":Rect2(130,0,820,190)},
}
## Shared drawing primitives; no world data or input state.
static var _history_light_texture: GradientTexture2D

static func create_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "Microsoft JhengHei", "SimSun"])
	return font

static func panel(canvas: CanvasItem, rect: Rect2, fill: Color, border: Color) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(rect, border, false, 1.0)

static func label(canvas: CanvasItem, font: Font, point: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0), width: float = -1.0) -> void:
	canvas.draw_string(font, point, UILocale.text(text), HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

# Present an already configured information dialog; content stays with its caller.
static func present_information_dialog(parent: Control, dialog: AcceptDialog) -> void:
	dialog.theme = system_theme()
	dialog.title = UILocale.text(dialog.title)
	dialog.dialog_text = UILocale.text(dialog.dialog_text)
	dialog.dialog_autowrap = true
	parent.add_child(dialog)
	dialog.get_ok_button().text = UILocale.text("关闭")
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(620,int(parent.size.x)-40),mini(440,int(parent.size.y)-40)))

static func archive_drawer(canvas: CanvasItem, rect: Rect2) -> void:
	folio(canvas,rect,0.0)
	folio_rail(canvas,Rect2(rect.position+Vector2(16,66),Vector2(rect.size.x-52,1)))

static func archive_handle(canvas: CanvasItem, rect: Rect2, opened: bool, hovered: bool) -> void:
	var tint := Color.WHITE if hovered or opened else Color("e1d8c6")
	_art(canvas,_theme_art("message_handle"),rect,Rect2(379,125,370,1265),Vector2(1024,1536),tint)

static func archive_notice(canvas: CanvasItem, rect: Rect2, style: Dictionary, attention: bool) -> void:
	folio_frame(canvas,rect,style.body)
	canvas.draw_line(rect.position+Vector2(9,14),Vector2(rect.position.x+9,rect.end.y-14),style.status if attention else style.teal,2,true)

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

static func _closed_outline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline,color,width,true)

static func quarter_clock_frame(canvas: CanvasItem, corner: Vector2, radius: float, palette: Dictionary, angles: Array[float]) -> void:
	var dial := _theme_art("dial_compact" if radius<=132.0 else "dial_large")
	canvas.draw_texture_rect(dial,Rect2(corner-Vector2(radius,0),Vector2.ONE*radius),false)
	for degrees: float in angles:
		var direction := Vector2.from_angle(deg_to_rad(degrees))
		var tangent := direction.orthogonal()
		var inner := corner+direction*(radius*.775)
		var outer := corner+direction*(radius*.895)
		var marker := PackedVector2Array([inner-tangent,outer-tangent*1.6,outer+tangent*1.6,inner+tangent])
		canvas.draw_colored_polygon(marker,palette.metal as Color)
		_closed_outline(canvas,marker,palette.seam as Color,0.8)

static func clock_menu_gear(canvas: CanvasItem, center: Vector2, radius: float, palette: Dictionary, active: bool) -> void:
	canvas.draw_colored_polygon(_gear_segment(center,radius,PI*.5,PI,32),palette.highlight as Color if active else palette.metal as Color)
	canvas.draw_arc(center,radius*.59,PI*.5,PI,32,palette.bronze as Color,1.3,true)
	canvas.draw_circle(center,radius*.26,palette.body as Color)
	for hole: int in range(3):
		var at := center+Vector2.from_angle(deg_to_rad(105.0+30.0*hole))*radius*.51
		canvas.draw_circle(at,radius*.055,palette.body as Color)

static func _gear_segment(center: Vector2, radius: float, from: float, to: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array([center])
	for index: int in range(segments+1):
		var angle := lerpf(from,to,float(index)/segments)
		var reach := radius*(1.0 if index%4 in [1,2] else .84)
		points.append(center+Vector2.from_angle(angle)*reach)
	return points

static func clock_speed_hand(canvas: CanvasItem, pivot: Vector2, length: float, angle: float, palette: Dictionary, dragging: bool, stopped: bool) -> void:
	var direction := Vector2.from_angle(angle)
	var tangent := direction.orthogonal()
	var factor := length/143.0
	var metal := (palette.metal as Color).lerp(palette.highlight as Color,0.65 if dragging else 0.25 if stopped else 0.4)
	metal.a=1.0
	# A continuous lancet hand; the gear covers its root, with no central ring.
	var hand := PackedVector2Array()
	for point: Vector2 in [Vector2(0,-3.5),Vector2(.22,-3.5),Vector2(.35,-2.3),Vector2(.77,-1.5),Vector2(1,0),Vector2(.77,1.5),Vector2(.35,2.3),Vector2(.22,3.5),Vector2(0,3.5)]:
		hand.append(pivot+direction*(point.x*length)+tangent*(point.y*factor))
	_closed_outline(canvas,hand,palette.seam as Color,2.8*factor)
	canvas.draw_colored_polygon(hand,metal)
	canvas.draw_line(pivot+direction*(length*.22),pivot+direction*(length*.9),palette.highlight as Color,maxf(0.6,factor),true)

static func workspace_surface(canvas: CanvasItem, rect: Rect2, face: Color, accent: Color) -> void:
	var p := rect.position
	var e := rect.end
	var shape := PackedVector2Array([p+Vector2(10,0),Vector2(e.x,p.y),e-Vector2(0,10),e-Vector2(10,0),Vector2(p.x,e.y),p+Vector2(0,10)])
	canvas.draw_colored_polygon(shape,face)
	_closed_outline(canvas,shape,Color(accent,.29),1.0)
	canvas.draw_line(p+Vector2(10,0),p+Vector2(80,0),accent,2.0,true)

static func _art(canvas: CanvasItem, texture: Texture2D, dest: Rect2, source: Rect2, original_size: Vector2, tint: Color = Color.WHITE) -> void:
	var scale_to_texture := texture.get_size()/original_size
	canvas.draw_texture_rect_region(texture,dest,Rect2(source.position*scale_to_texture,source.size*scale_to_texture),tint)

static func _theme_art(key: String) -> Texture2D:
	return InterfaceSettings.theme_parameters().art[key] as Texture2D

static func folio_frame(canvas: CanvasItem, rect: Rect2, fill: Color = FOLIO_BACKGROUND) -> void:
	var corner := minf(12.0,minf(rect.size.x,rect.size.y)*0.25)
	var rim := _folio_outline(rect.grow(-4.0),corner)
	canvas.draw_colored_polygon(rim,fill)
	_closed_outline(canvas,rim,BRASS_SHADOW,4.0)
	_closed_outline(canvas,rim,FOLIO_BRASS,1.5)
	if minf(rect.size.x,rect.size.y)>=48.0:
		_closed_outline(canvas,_folio_outline(rect.grow(-9.0),corner-3.0),Color(FOLIO_RULE,.68),1.0)

static func folio(canvas: CanvasItem, rect: Rect2, header_height: float, skin: Folio = Folio.GENERAL) -> void:
	folio_frame(canvas,rect)
	if rect.size.y>=150.0:
		var pivot := Vector2(rect.get_center().x,rect.end.y-9.0)
		var radius := clampf(minf(rect.size.x,rect.size.y)*.047,12.0,17.0)
		canvas.draw_colored_polygon(_gear_segment(pivot,radius,PI,TAU,32),FOLIO_BRASS)
		canvas.draw_arc(pivot,radius*.88,PI,TAU,24,BRASS_LIGHT,1.0,true)
		canvas.draw_arc(pivot,radius*.46,PI,TAU,18,BRASS_SHADOW,2.0,true)
	if header_height<=0.0: return
	var art: Dictionary = FOLIO_ART[skin]
	var source: Rect2 = art.crest
	var ornament_width := minf(194.0 if skin==Folio.GENERAL else 224.0,rect.size.x*.44)
	var ornament_size := source.size*(ornament_width/source.size.x)
	var ornament_position := Vector2(rect.get_center().x-ornament_size.x*.5,rect.position.y-ornament_size.y+5.0)
	_art(canvas,_theme_art(str(art.texture)),Rect2(ornament_position,ornament_size),source,Vector2(1086,1448))
	_closed_outline(canvas,_folio_outline(_folio_plaque(rect),10.0),FOLIO_RULE,1.2)
	folio_rail(canvas,Rect2(rect.position+Vector2(16,header_height),Vector2(rect.size.x-32,3)))

static func _folio_plaque(rect: Rect2) -> Rect2:
	return Rect2(rect.position+Vector2(18,11),Vector2(rect.size.x-36,FOLIO_HEADER_HEIGHT-16))

static func _folio_outline(rect: Rect2, corner: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([
		Vector2(p.x+corner,p.y),Vector2(e.x-corner,p.y),Vector2(e.x,p.y+corner),Vector2(e.x,e.y-corner),
		Vector2(e.x-corner,e.y),Vector2(p.x+corner,e.y),Vector2(p.x,e.y-corner),Vector2(p.x,p.y+corner)])

static func folio_title(canvas: CanvasItem, font: Font, rect: Rect2, text: String, font_size: int) -> void:
	var plaque := _folio_plaque(rect)
	# Use the opening between the engraved laurels as the text area.
	centered_fit_text(canvas,font,plaque.grow_individual(-plaque.size.x*.12,-3,-plaque.size.x*.12,-3),text,font_size,15,FOLIO_PAPER)

static func text_row_height(font_size: int) -> float:
	return ceilf(float(font_size)*1.65)+2.0

static func centered_fit_text(canvas: CanvasItem, font: Font, rect: Rect2, text: String, font_size: int, min_font_size: int, color: Color) -> void:
	var measured := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	while font_size>min_font_size and (measured>rect.size.x or font.get_height(font_size)>rect.size.y):
		font_size-=1
		measured=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var line := TextLine.new()
	line.add_string(text,font,font_size)
	line.width=rect.size.x
	line.alignment=HORIZONTAL_ALIGNMENT_CENTER
	line.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	line.draw(canvas.get_canvas_item(),Vector2(rect.position.x,rect.get_center().y-line.get_size().y*.5),color)

static func folio_rail(canvas: CanvasItem, rect: Rect2) -> void:
	var y := rect.get_center().y
	canvas.draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),FOLIO_RULE,1.0,true)

static func folio_button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

static func _draw_history_light(canvas: CanvasItem, rect: Rect2, strength: float) -> void:
	if strength<=0.0: return
	if _history_light_texture==null:
		var falloff := Gradient.new()
		falloff.offsets = PackedFloat32Array([0.0,0.22,0.50,0.76,1.0])
		falloff.colors = PackedColorArray([Color.WHITE,Color(1,1,1,.68),Color(1,1,1,.30),Color(1,1,1,.065),Color(1,1,1,0)])
		_history_light_texture = GradientTexture2D.new()
		_history_light_texture.width = 192
		_history_light_texture.height = 192
		_history_light_texture.gradient = falloff
		_history_light_texture.fill = GradientTexture2D.FILL_RADIAL
		_history_light_texture.fill_from = Vector2(0.5,0.5)
		_history_light_texture.fill_to = Vector2(0.5,1.0)
	var source := Vector2(rect.get_center().x+rect.size.x*0.06,-6.0)
	var halo := Vector2(rect.size.x*1.12,196.0)
	var shaft := Vector2(rect.size.x*0.38,244.0)
	canvas.draw_texture_rect(_history_light_texture,Rect2(source-halo*0.5,halo),false,Color(Color("edb97d"),0.17*strength))
	canvas.draw_texture_rect(_history_light_texture,Rect2(source-shaft*0.5,shaft),false,Color(Color("fff0c7"),0.09*strength))

static func history_track_frame(canvas: CanvasItem, rect: Rect2, palette: Dictionary, progress: float, sunlight: float) -> void:
	_draw_history_light(canvas,rect,sunlight)
	var brass := palette.metal as Color
	var light := palette.ivory as Color
	_history_trail(canvas,rect,1.0,Color(brass,.025),Color(brass,.12),4.6)
	_history_trail(canvas,rect,1.0,Color(brass,.08),Color(light,.52),1.55)
	var head := history_point(rect,1.0)
	canvas.draw_circle(head,3.5,Color(light,.15),true,-1.0,true)
	canvas.draw_circle(head,1.8,Color(light,.65),true,-1.0,true)
	if progress>0.0:
		_history_trail(canvas,rect,progress,Color(0.42,0.66,0.63,0.15),Color(Color("a8d6ca"),.56),1.35)

static func _history_trail(canvas: CanvasItem, rect: Rect2, end: float, tail: Color, head: Color, width: float) -> void:
	const SAMPLES := 49
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(SAMPLES*2)
	colors.resize(SAMPLES*2)
	for index: int in range(SAMPLES):
		var fraction := float(index)/float(SAMPLES-1)
		var t := fraction*end
		var point := history_point(rect,t)
		var normal := Vector2(-rect.size.y*4.0*(1.0-2.0*t),rect.size.x).normalized()
		var offset := normal*lerpf(0.12,width,pow(fraction,1.4))
		var color := tail.lerp(head,smoothstep(0.04,1.0,fraction))
		var opposite := SAMPLES*2-1-index
		vertices[index] = point+offset
		vertices[opposite] = point-offset
		colors[index] = color
		colors[opposite] = color
	canvas.draw_polygon(vertices,colors)

static func history_point(rect: Rect2, t: float) -> Vector2:
	return rect.position+Vector2(rect.size.x*t,rect.size.y*4.0*t*(1.0-t))

static func technology_marker(canvas: CanvasItem, center: Vector2, shape: String, radius: float, light: float = 1.0) -> void:
	var points := PackedVector2Array()
	var color := Color("f1d49a")
	match shape:
		"drive":
			color = Color("a8d6ca")
			points = PackedVector2Array([Vector2(-.76,-.72),Vector2(.9,0),Vector2(-.76,.72),Vector2(-.38,0)])
		"public":
			color = Color("96b5d2")
			points = PackedVector2Array([Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT])
		_:
			points = PackedVector2Array([Vector2(0,-1),Vector2(.24,-.24),Vector2(.8,0),Vector2(.24,.24),Vector2(0,1),Vector2(-.24,.24),Vector2(-.8,0),Vector2(-.24,-.24)])
	for index: int in points.size():
		points[index] = center+points[index]*radius
	canvas.draw_colored_polygon(points,Color(color,light))
	_closed_outline(canvas,points,Color(.035,.067,.09,.85),.75)

static func portrait_cameo(canvas: CanvasItem, rect: Rect2, active: bool) -> void:
	_art(canvas,_theme_art("portrait"),rect,Rect2(27,12,954,1446),Vector2(1024,1536),Color.WHITE if active else Color("f2ece0"))

static func portrait_action(canvas: CanvasItem, center: Vector2, kind: String, active: bool) -> void:
	var art := _theme_art("belongings" if kind=="details" else kind)
	_art(canvas,art,Rect2(center-Vector2(19,21),Vector2(38,42)),Rect2(77,24,1100,1200),Vector2(1254,1254),Color.WHITE if active else Color("e7dece"))

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

static func system_theme() -> Theme:
	var theme := shell_theme()
	var palette := InterfaceSettings.theme_parameters()
	var hud := palette.hud as Dictionary
	for state: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		var fill := hud.body as Color
		var border := hud.metal as Color
		match state:
			"hover": fill = fill.lightened(0.08)
			"pressed","hover_pressed": fill = hud.teal as Color
			"disabled": border = Color(border,0.45)
			"focus": fill = Color.TRANSPARENT
		if state in ["hover","pressed","hover_pressed","focus"]: border = hud.highlight as Color
		var box := folio_button_style(fill,border)
		box.set_corner_radius_all(3)
		for type: String in ["Button","OptionButton","CheckButton"]:
			theme.set_stylebox(state,type,box)
	for type: String in ["Button","OptionButton","CheckButton"]:
		theme.set_color("font_color",type,FOLIO_INK)
		theme.set_color("font_disabled_color",type,FOLIO_MUTED)
	theme.set_stylebox("hover","PopupMenu",theme.get_stylebox("hover","Button"))
	var rule := StyleBoxLine.new()
	rule.color = FOLIO_RULE
	theme.set_stylebox("separator","HSeparator",rule)
	theme.set_stylebox("slider","HSlider",_system_slider_track(hud.seam as Color,FOLIO_RULE))
	theme.set_stylebox("grabber_area","HSlider",_system_slider_track(FOLIO_RULE,FOLIO_RULE))
	theme.set_stylebox("grabber_area_highlight","HSlider",_system_slider_track(FOLIO_BRASS,FOLIO_RULE))
	theme.set_icon("grabber","HSlider",_system_indicator(14,3,FOLIO_BRASS))
	theme.set_icon("grabber_highlight","HSlider",_system_indicator(14,3,BRASS_LIGHT))
	theme.set_icon("grabber_disabled","HSlider",_system_indicator(14,3,FOLIO_MUTED))
	theme.set_icon("checked","CheckButton",_system_indicator(30,19,BRASS_LIGHT))
	theme.set_icon("unchecked","CheckButton",_system_indicator(30,3,FOLIO_MUTED))
	theme.set_icon("checked_disabled","CheckButton",_system_indicator(30,19,FOLIO_MUTED))
	theme.set_icon("unchecked_disabled","CheckButton",_system_indicator(30,3,FOLIO_MUTED))
	var dialog_panel := folio_button_style(palette.panel as Color,FOLIO_BRASS)
	for side: Side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		dialog_panel.set_content_margin(side,18)
	theme.set_stylebox("panel","AcceptDialog",dialog_panel)
	var title_frame := folio_button_style(ENAMEL,FOLIO_RULE)
	title_frame.set_expand_margin(SIDE_TOP,32)
	theme.set_stylebox("embedded_border","Window",title_frame)
	theme.set_stylebox("embedded_unfocused_border","Window",title_frame)
	theme.set_constant("title_height","Window",32)
	theme.set_color("title_color","Window",FOLIO_INK)
	return theme

static func _system_slider_track(fill: Color, border: Color) -> StyleBoxFlat:
	var track := folio_button_style(fill,border)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	track.content_margin_left = 0
	track.content_margin_right = 0
	return track

static func _system_indicator(width: int, knob_x: int, face: Color) -> ImageTexture:
	var image := Image.create_empty(width,14,false,Image.FORMAT_RGBA8)
	image.fill(FOLIO_RULE)
	image.fill_rect(Rect2i(1,1,width-2,12),ENAMEL)
	image.fill_rect(Rect2i(knob_x,3,8,8),face)
	return ImageTexture.create_from_image(image)

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
