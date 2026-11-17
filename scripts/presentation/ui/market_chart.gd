extends RefCounted
## Draw-only chart. Sparse observations stay sparse; no interpolated history.
const Locale = preload("res://scripts/presentation/ui/ui_locale.gd")

static func date(minute: int) -> String:
	var d: Dictionary=GameCalendar.from_total_hour(maxi(0,minute)/60)
	return "%02d/%02d"%[int(d.month),int(d.day)]

static func draw(shell: Control, area: Rect2, samples: Array[Dictionary], now: int, days: int, supply: bool) -> void:
	var from: int=maxi(0,now-days*1440)
	var values: Array[Dictionary]=[]
	for sample: Dictionary in samples:
		if int(sample.minute)>=from and int(sample.minute)<=now: values.append(sample)
	var low: float=INF
	var high: float=-INF
	for sample: Dictionary in values:
		low=minf(low,float(sample.value));high=maxf(high,float(sample.value))
	if values.is_empty(): low=0.0;high=1.0
	var padding: float=maxf((high-low)*.18,maxf(absf(high)*.05,.1))
	low=maxf(0.0,low-padding);high+=padding
	if supply:
		low=floor(low);high=maxf(ceil(high),low+3.0)
	for i: int in 4:
		var y: float=area.position.y+area.size.y*i/3.0
		shell.draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(UIDrawing.FOLIO_RULE,.50),1.0)
		var value: String="—" if values.is_empty() else "%.0f"%(high-(high-low)*i/3.0) if supply else "%.2f"%(high-(high-low)*i/3.0)
		shell.label(Vector2(area.position.x-39,y+4),value,10,UIDrawing.FOLIO_MUTED,38)
	var ink: Color=Color("3f6f64") if supply else Color("895836")
	var points: PackedVector2Array=[]
	for sample: Dictionary in values:
		points.append(Vector2(lerpf(area.position.x,area.end.x,float(int(sample.minute)-from)/maxi(1,now-from)),lerpf(area.end.y,area.position.y,(float(sample.value)-low)/maxf(.0001,high-low))))
	if points.size()>1: shell.draw_polyline(points,ink,1.8,true)
	for point: Vector2 in points:
		shell.draw_circle(point,3.0,Color(.04,.07,.06))
		shell.draw_circle(point,2.2,ink)
	if points.size()==1:
		shell.draw_dashed_line(Vector2(area.position.x,points[0].y),points[0],Color(ink,.20),1.0,4.0)
		shell.label(area.position+Vector2(12,24),"仅有当前观察，尚无连续历史",11,UIDrawing.FOLIO_MUTED,area.size.x-28)
	elif points.is_empty(): shell.label(area.position+Vector2(12,24),"此期间暂无可见记录",12,UIDrawing.FOLIO_MUTED,area.size.x-24)
	shell.label(Vector2(area.position.x,area.end.y+19),date(from),10,UIDrawing.FOLIO_MUTED)
	if date(from)!=date(now):
		shell.label(Vector2(area.end.x-36,area.end.y+19),date(now),10,UIDrawing.FOLIO_MUTED)
