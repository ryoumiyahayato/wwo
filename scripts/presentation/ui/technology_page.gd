extends RefCounted

const Pilot = preload("res://scripts/content/technology_pilot.gd")
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")

var _country: String = ""
var _public_country: String = ""
var _selected: String = ""
var _section: String = "capacity"
var _project: Dictionary = {}
var milestones: Array = []

func set_country(country: String) -> bool:
	if _country==country: return false
	_country=country
	_selected=""
	_section="capacity"
	return true

func set_project(project: Dictionary) -> bool:
	if _project==project: return false
	_project=project
	milestones=project.get("milestones",[])
	return true

func project_firm() -> String:
	return str(_project.get("firm",""))

func set_public_country(country: String) -> void:
	_public_country=country if country!=_country and Pilot.FOUNDATIONS.has(country) else ""
	if _public_country.is_empty() and _section=="public": _section="capacity"

func track_progress() -> float:
	if _project.get("adopted",false):
		for index: int in milestones.size():
			if milestones[index].id=="drive": return milestone_position(index)
	return 0.0

func milestone_position(index: int) -> float:
	var span := maxf(21.0*1440,float(milestones.back().minute)+7.0*1440)
	return clampf(float(milestones[index].minute)/span,.05,.93)

func panel_height() -> float:
	if _section=="chronicle": return 318.0 if not milestones.is_empty() else 188.0
	if _section=="public" or _project.is_empty(): return 344.0
	return 465.0

func show_section(section: String) -> void:
	_section=section

func select_milestone(id: String) -> void:
	_selected=id
	_section="chronicle"

func draw(shell: MainShell, rect: Rect2) -> void:
	var p := rect.position+Vector2(23,0)
	var width := rect.size.x-46
	var country := "法兰西" if _country==Pilot.FRANCE else str(Pilot.COUNTRIES.get(_country,"本国"))
	shell.folio_title(rect,country+" · 科技",24)
	shell.button(Rect2(p+Vector2(0,62),Vector2(122,28)),"工程与能力","technology:capacity",true,_section=="capacity",13,"folio_tab")
	shell.button(Rect2(p+Vector2(131,62),Vector2(104,28)),"发展纪事","technology:chronicle",true,_section=="chronicle",13,"folio_tab")
	if not _public_country.is_empty():
		shell.button(Rect2(p+Vector2(width-158,62),Vector2(158,28)),str(Pilot.COUNTRIES[_public_country])+" · 公开资料","technology:public",true,_section=="public",12,"folio_tab")
	UIDrawing.folio_rail(shell,Rect2(p+Vector2(0,96),Vector2(width,3)))
	var body := Rect2(p+Vector2(0,105),Vector2(width,rect.size.y-122))
	if _section=="chronicle":
		_draw_chronicle(shell,body)
	elif _section=="public":
		_draw_reference_plate(shell,body,_public_country,true)
	elif _project.is_empty():
		_draw_reference_plate(shell,body,_country,false)
	else:
		_draw_engineering_plate(shell,body)

func _draw_reference_plate(shell: MainShell, body: Rect2, country: String, public_record: bool) -> void:
	var foundation: Dictionary = Pilot.FOUNDATIONS.get(country,{})
	var p := body.position
	shell.label(p+Vector2(0,18),"公开的开局能力" if public_record else "1900 年 · 开局技术底册",15,UIDrawing.FOLIO_INK,body.size.x)
	if foundation.is_empty():
		shell.label(p+Vector2(0,60),"尚无该国的科技基础资料。",12,UIDrawing.FOLIO_MUTED,body.size.x)
		return
	var plates := Rect2(p+Vector2(0,32),Vector2(body.size.x,148))
	_grid(shell,plates)
	var step := plates.size.x/float(foundation.size())
	var index := 0
	for key: String in foundation:
		var parts := str(foundation[key]).split(" · ",true,1)
		var x := plates.position.x+step*index
		var center := Vector2(x+step*.5,plates.position.y+42)
		if index>0: shell.draw_line(Vector2(x,plates.position.y),Vector2(x,plates.end.y),Color(UIDrawing.FOLIO_RULE,.54),1.0)
		var kind := "rail" if key.begins_with("urban_") else "rollers" if key=="roller_milling" else "motor"
		_engraving(shell,center,kind,UIDrawing.FOLIO_INK)
		shell.label(Vector2(x+9,plates.position.y+82),parts[0],13,UIDrawing.FOLIO_INK,step-18)
		if parts.size()>1: shell.wrapped(Vector2(x+9,plates.position.y+105),parts[1],step-18,12,2,UIDrawing.FOLIO_MUTED)
		index+=1
	if public_record:
		UIDrawing.technology_marker(shell,p+Vector2(5,201),"public",5.0)
		shell.label(p+Vector2(17,206),"开局公开资料",11,UIDrawing.FOLIO_MUTED,body.size.x-17)
	else:
		shell.label(p+Vector2(0,206),"本局暂无可查看的工程项目。",11,UIDrawing.FOLIO_MUTED,body.size.x)

func _draw_engineering_plate(shell: MainShell, body: Rect2) -> void:
	var p := body.position
	var width := body.size.x
	var ink := UIDrawing.FOLIO_INK
	var muted := UIDrawing.FOLIO_MUTED
	var adopted := bool(_project.adopted)
	var validated := milestones.any(func(record: Dictionary) -> bool: return record.id=="motor")
	var historic_install := milestones.any(func(record: Dictionary) -> bool: return record.id=="drive")
	var status := str(_project.status)
	if _project.opportunity=="build_lab": status=UILocale.text("试验台待建设")
	var work := int(_project.work)
	if work>0: status+="  ·  "+UILocale.text("%d / 4 人时")%work
	shell.label(p+Vector2(1,18),"巴黎磨坊 · 磨粉动力",19,ink,width-92)
	shell.number(p+Vector2(width-66,18),"01",62,17,UIDrawing.BRASS_LIGHT)
	var plate_height := clampf(body.size.y-146.0,144.0,191.0)
	var plate := Rect2(p+Vector2(0,31),Vector2(width*.53,plate_height))
	_grid(shell,plate)
	shell.label(plate.position+Vector2(12,22),"动力传动 · 示意图",12,muted,plate.size.x-24)
	_drive_diagram(shell,plate,validated,adopted)
	var ledger := Rect2(plate.end.x+12,plate.position.y,body.end.x-plate.end.x-12,plate_height)
	var step_height := ledger.size.y/3.0
	var section_names: Array[String] = ["知识基础","研究与验证","工业应用"]
	var descriptions: Array[String] = [
		"工场电气化 · 辊式磨粉",
		UILocale.text("样机已验证") if validated else status,
		"电力设备在用" if adopted else "设备当前不可用" if historic_install else "尚未投用",
	]
	for i: int in range(3):
		var line := ledger.position+Vector2(0,step_height*i)
		var active := i==0 or (i==1 and validated) or (i==2 and adopted)
		var mark := line+Vector2(13,23)
		shell.draw_circle(mark,10.5,UIDrawing.FOLIO_SHADE,true)
		shell.draw_arc(mark,10.5,0,TAU,20,UIDrawing.BRASS_LIGHT if active else UIDrawing.FOLIO_RULE,1.0,true)
		shell.label(mark+Vector2(-3,4),str(i+1),12,UIDrawing.BRASS_LIGHT if active else muted,8)
		shell.label(line+Vector2(31,20),section_names[i],14,ink,ledger.size.x-35)
		shell.wrapped(line+Vector2(31,40),descriptions[i],ledger.size.x-35,11,2,muted)
		if i<2: UIDrawing.folio_rail(shell,Rect2(line+Vector2(31,step_height-3),Vector2(ledger.size.x-35,2)))
	var metric := Vector2(p.x,plate.end.y+10)
	var half := width*.5
	shell.draw_rect(Rect2(metric,Vector2(width,48)),UIDrawing.FOLIO_SHADE)
	shell.draw_line(metric+Vector2(half,6),metric+Vector2(half,42),UIDrawing.FOLIO_RULE,1.0)
	shell.label(metric+Vector2(10,18),"有效日生产能力",11,muted,half-20)
	shell.label(metric+Vector2(11,38),UILocale.text("常规 %d")%int(_project.base_capacity),11,muted,half-70)
	shell.number(metric+Vector2(half-65,36),str(_project.capacity),54,29,UIDrawing.BRASS_LIGHT)
	shell.label(metric+Vector2(half+10,18),"累计面粉 · 千克",11,muted,half-70)
	shell.number(metric+Vector2(width-65,36),str(_project.flour),54,29,UIDrawing.BRASS_LIGHT)
	_draw_project_actions(shell,Rect2(metric+Vector2(0,58),Vector2(width,32)))

func _drive_diagram(shell: MainShell, plate: Rect2, validated: bool, adopted: bool) -> void:
	var tint := UIDrawing.BRASS_LIGHT if validated else UIDrawing.FOLIO_MUTED
	var power := Color("95c4ae") if adopted else UIDrawing.FOLIO_RULE
	var center := plate.position+Vector2(plate.size.x*.31,plate.size.y*.49)
	var radius := minf(35.0,plate.size.y*.21)
	var shaft := plate.position+Vector2(plate.size.x*.76,center.y-plate.position.y)
	var floor_y := center.y+radius+11
	shell.draw_line(Vector2(plate.position.x+14,center.y),Vector2(plate.end.x-14,center.y),Color(power,.36),1)
	for ratio: float in [1.0,.83,.54,.22]:
		shell.draw_arc(center,radius*ratio,0,TAU,40,tint,1.25,true)
	for i: int in range(8):
		var mount := center+Vector2.from_angle(float(i)*TAU/8.0)*radius*.92
		shell.draw_circle(mount,1.6,tint,true)
	shell.draw_rect(Rect2(center+Vector2(-radius,-radius-10),Vector2(radius*2,11)),tint,false,1)
	shell.draw_rect(Rect2(Vector2(center.x-radius-6,floor_y-8),Vector2(radius*2+12,8)),tint,false,1)
	for y: float in [-10.0,10.0]:
		shell.draw_rect(Rect2(shaft+Vector2(-21,y-6),Vector2(42,12)),power,false,1.2)
		shell.draw_line(shaft+Vector2(-26,y),shaft+Vector2(26,y),power,1.1,true)
		shell.draw_line(center+Vector2(radius*.55,y*.55),shaft+Vector2(-26,y),power,1.1,true)
	shell.draw_line(Vector2(plate.position.x+12,floor_y),Vector2(plate.end.x-12,floor_y),UIDrawing.FOLIO_RULE,1)
	shell.label(Vector2(plate.position.x+13,floor_y+19),"电动机",11,tint,plate.size.x*.47)
	shell.label(Vector2(shaft.x-24,floor_y+19),"磨辊",11,power,plate.size.x*.23)

func _draw_project_actions(shell: MainShell, row: Rect2) -> void:
	var opportunity := str(_project.opportunity)
	if not opportunity.is_empty():
		var label := ""
		var action := ""
		match opportunity:
			"authorize_trial":
				label="批准样机试制"
				action="native:business_activity:%s|%s|%s|1"%[_project.firm,_project.site,Pilot.TRIAL]
			"install_drive":
				label="安装电力传动"
				action="native:invest:"+Pilot.INSTALL
			"build_lab":
				label="建设试验台"
				action="native:invest:"+Pilot.LAB
		var blocker := str(_project.blocker)
		if not blocker.is_empty(): label="缺少现场材料" if blocker=="CAPITAL_GOODS_NOT_AT_SITE" else "可用预算不足"
		shell.button(Rect2(row.position,Vector2(minf(row.size.x*.5,184.0),row.size.y)),label,action,blocker.is_empty(),false,12,"folio_primary")
	shell.button(Rect2(row.end.x-132,row.position.y,132,row.size.y),"查看磨坊经营","work:firm:"+project_firm(),true,false,12,"folio_control")

static func _grid(shell: MainShell, rect: Rect2) -> void:
	shell.draw_rect(rect,UIDrawing.FOLIO_BINDING)
	var line := Color("bcbab3",.18)
	for x: int in range(16,int(rect.size.x),16):
		var p := rect.position+Vector2(x,0)
		shell.draw_line(p,p+Vector2(0,rect.size.y),line)
	for y: int in range(16,int(rect.size.y),16):
		var p := rect.position+Vector2(0,y)
		shell.draw_line(p,p+Vector2(rect.size.x,0),line)
	shell.draw_rect(rect,Color(UIDrawing.FOLIO_RULE,.58),false)

static func _engraving(shell: MainShell, at: Vector2, kind: String, ink: Color) -> void:
	match kind:
		"motor":
			shell.draw_arc(at,10,0,TAU,24,ink,1.1,true)
			shell.draw_arc(at,5,0,TAU,14,ink,1.0,true)
			shell.draw_line(at-Vector2(14,0),at+Vector2(14,0),ink,1.0,true)
			shell.draw_line(at-Vector2(9,-13),at+Vector2(9,13),ink,1.0,true)
		"rollers":
			for offset: float in [-6.0,6.0]:
				var axle := at+Vector2(0,offset)
				shell.draw_rect(Rect2(axle-Vector2(10,4),Vector2(20,8)),ink,false,1.0)
				shell.draw_line(axle-Vector2(14,0),axle+Vector2(14,0),ink,1.0,true)
		"rail":
			shell.draw_line(at-Vector2(13,7),at+Vector2(13,-7),ink,1.2,true)
			shell.draw_line(at-Vector2(13,-7),at+Vector2(13,7),ink,1.2,true)
			for x: int in range(-10,13,5): shell.draw_line(at+Vector2(x,-10),at+Vector2(x,10),ink,1.0,true)
		_:
			shell.draw_polyline(PackedVector2Array([at+Vector2(-13,13),at+Vector2(-13,-10),at+Vector2(13,-10),at+Vector2(13,13)]),ink,1.1,true)
			shell.draw_arc(at+Vector2(0,-3),6,0,TAU,16,ink,1.0,true)
			shell.draw_line(at+Vector2(-17,13),at+Vector2(17,13),ink,1.1,true)

func _draw_chronicle(shell: MainShell, body: Rect2) -> void:
	var p := body.position
	var width := body.size.x
	if milestones.is_empty():
		shell.label(p+Vector2(0,26),"本局还没有科技里程碑。",13,UIDrawing.FOLIO_MUTED,width)
		return
	var selected: Dictionary = milestones.back()
	var span := 43.0*float(milestones.size())
	if milestones.size()>1: shell.draw_line(p+Vector2(9,22),p+Vector2(9,span-21),UIDrawing.FOLIO_RULE,1.0,true)
	for index: int in milestones.size():
		var row: Dictionary = milestones[index]
		if row.id==_selected: selected=row
		var date := GameCalendar.from_total_hour(int(row.minute)/60)
		var date_label := "%04d-%02d-%02d"%[date.year,date.month,date.day]
		var center := p+Vector2(9,22+index*43)
		UIDrawing.technology_marker(shell,center,str(row.id),7.0)
		var highlighted: bool = row.id==_selected or (_selected.is_empty() and row==milestones.back())
		shell.label(center+Vector2(20,0),date_label,12,UIDrawing.FOLIO_MUTED,100)
		shell.button(Rect2(center+Vector2(113,-17),Vector2(width-122,29)),str(row.title),"technology:record:"+str(row.id),true,highlighted,14,"folio_row")
	var detail := p+Vector2(0,span+12)
	shell.draw_line(detail,detail+Vector2(width,0),UIDrawing.FOLIO_RULE,1.0,true)
	shell.label(detail+Vector2(0,22),str(selected.kind),12,UIDrawing.FOLIO_MUTED,width)
	shell.wrapped(detail+Vector2(0,45),str(selected.effect),width,13,3,UIDrawing.FOLIO_INK)
