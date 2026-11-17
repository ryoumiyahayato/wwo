class_name WorldPage
extends RefCounted
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
const CityOverview = preload("res://scripts/presentation/map/city_miniature.gd")
const Structure = preload("res://scripts/presentation/map/economy/economic_structure_style.gd")
var _polity: Dictionary = {}
var _current_territory: Dictionary = {}
var _place: Dictionary = {}
var _flag: Dictionary = {}
var _profile: Dictionary = {}
var _administration: Dictionary = {}
var _texture: Texture2D
var _date: String = ""
var _formal_place: bool = false
var _economy_polity_id: String = ""
var _economy_label: String = ""
var index_open: bool = false
var index_category: String = "home"
var index_page: int = 0
var internal_load_active: bool = false
var _index_countries: Array[Dictionary] = []
var admin_page: int = 0
var admin_drawer_open: bool = false
var selected_admin_id: String = ""
var admin_member_page: int = 0
var _land_coverage: Dictionary = {}
const ADMIN_PAGE_SIZE: int = 12

func set_observation_date(date: String) -> void:
	_date = date

func set_current_territory(value: Dictionary, politics: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView) -> void:
	_current_territory = {}
	for field: String in ["sovereign_polity_id","controller_polity_id"]:
		if not value.has(field): continue
		var id := str(value[field]) if value[field]!=null else ""
		var polity := CurrentWorldPoliticalProjection.polity_summary(id,politics,evidence)
		_current_territory[field] = str(polity.get("name_zh",id)) if not id.is_empty() else "未知"

func refresh(polity: Dictionary, place: Dictionary, content: WorldPageContent, formal_place: bool = false, economy_polity_id: String = "", economy_label: String = "") -> void:
	var changed := str(_polity.get("id","")) != str(polity.get("id",""))
	_polity = polity
	_place = place
	_profile = content.profile()
	_administration = content.administration()
	_flag = content.flag()
	_texture = content.texture()
	_date = content.date()
	_formal_place = formal_place
	_economy_polity_id = economy_polity_id
	_economy_label = economy_label
	if changed:
		reset_administration()
		admin_drawer_open=false
	selected_admin_id = str(_place.get("place_id","")) if str(_place.get("spatial_kind",""))=="historical_administration" else ""

func reset_administration() -> void:
	admin_page = 0
	selected_admin_id = ""
	admin_member_page = 0

func set_display_visual(visual: Dictionary, texture: Texture2D) -> void:
	if _flag.is_empty(): _flag = visual.duplicate(true)
	_texture = texture

func set_spatial_context(spatial: VNextSpatialWorld) -> void:
	var topology := spatial.land_topology()
	_land_coverage = topology.coverage_summary() if topology != null else {}
	# Previously the second display-only refresh discarded formal enrichment.
	# Preserve that boundary without first merging and then copying it away.
	if bool(_polity.get("display_only",false)): return
	for unit: Dictionary in _administration.get("runtime_units",[]) as Array:
		if str(unit.id)==str(_place.get("place_id","")) and str(_place.get("spatial_kind",""))=="historical_administration": unit.merge(_place,true)

func set_index_context(countries: Array[Dictionary]) -> void:
	_index_countries = countries

func draw_index(shell: MainShell, rect: Rect2) -> void:
	shell.heading(rect,"百科",{"home":"","help":"基本操作","layers":"地图图层","countries":"历史国家与地区","administration":"行政区与正式土地"}.get(index_category,""))
	var x := rect.position.x+22
	var y := rect.position.y+112
	match index_category:
		"home":
			var categories: Array[Dictionary] = [{"name":"基本操作","id":"help"},{"name":"地图图层","id":"layers"},{"name":"历史国家与地区","id":"countries"},{"name":"行政区与正式土地","id":"administration"}]
			for index: int in range(categories.size()):
				shell.button(Rect2(x,y+index*44,rect.size.x*0.5-32,34),str(categories[index].name),"encyclopedia:category:"+str(categories[index].id))
			shell.button(Rect2(rect.position.x+rect.size.x*0.54,y,rect.size.x*0.46-22,34),"组织参考词条","encyclopedia:organizations")
		"help":
			shell.lines(Vector2(x,y),["滚轮：放大或缩小地图。","左键拖动：浏览地图；点击地理对象：查看资料。","右键拖动：调整地图方向。","Esc：关闭菜单或详情；无详情时呼出系统菜单。","Backspace：返回上一层。","保存与加载：系统菜单内选择存档槽。"],rect.size.x-44)
		"layers":
			shell.lines(Vector2(x,y),["政治地图：当前政治、历史旗帜及随尺度显示的行政界。","经济地图：按产业链查看日结模拟产值；主要城市标注已知仓储与在途订单。","历史铁路：尚缺已定位的 1900 年线路资料。","地理地图：物理地形与自然水文。","当前行政成员、法律主权和实际控制分别保存。"],rect.size.x-44)
			var pilot := LocalSpatialLoader.internal_landmark_sources()
			var count := 4
			index_page = clampi(index_page,0,maxi(0,(pilot.size()-1)/count))
			var column_width := (rect.size.x-56.0)*0.5
			for index: int in range(index_page*count,mini(pilot.size(),(index_page+1)*count)):
				var reference := pilot[index]
				var slot := index-index_page*count
				shell.button(Rect2(x+(slot%2)*(column_width+12),y+140+(slot/2)*32,column_width,26),"定位："+str(reference.display_name),"map:pilot_landmark:"+str(reference.anchor_id))
			if not pilot.is_empty():
				shell.button(Rect2(x,rect.end.y-35,82,25),"上一页","encyclopedia:previous",index_page>0)
				shell.button(Rect2(x+92,rect.end.y-35,82,25),"下一页","encyclopedia:next",(index_page+1)*count<pilot.size())
				shell.button(Rect2(rect.end.x-280,rect.end.y-35,258,25),"高负载："+("开" if internal_load_active else "关")+"（仅内部测试）","map:internal_load")
		"countries":
			var count := maxi(1,int((rect.size.y-160)/28))
			index_page = clampi(index_page,0,maxi(0,(_index_countries.size()-1)/count))
			for index: int in range(index_page*count,mini(_index_countries.size(),(index_page+1)*count)):
				var row := _index_countries[index]
				shell.button(Rect2(x,y-18+(index-index_page*count)*28,rect.size.x-44,24),str(row.get("name_zh","名称未记录")),"encyclopedia:country:"+str(row.id))
			if _index_countries.size()>count:
				shell.button(Rect2(x,rect.end.y-35,82,25),"上一页","encyclopedia:previous",index_page>0)
				shell.button(Rect2(x+92,rect.end.y-35,82,25),"下一页","encyclopedia:next",(index_page+1)*count<_index_countries.size())
		"administration":
			shell.wrapped(Vector2(x,y),"法国：1900 省、区、县区及市镇名录。英国：组成地域、历史郡与地方政府身份，辖界性质分别记录。德国：各邦及已有下级历史地图参考。俄罗斯帝国：1897 GIS 与 1900 上级隶属参考。",rect.size.x-44,12,3)
			shell.label(Vector2(x,y+76),UILocale.text("法国正式土地覆盖 %.2f km² · %d 个活动土地") % [float(_land_coverage.get("area_km2",0.0)),int(_land_coverage.get("active_units",0))],13)
			shell.label(Vector2(x,y+106),"参考边界与当前世界土地成员可能不同。",12)
			shell.label(Vector2(x,y+136),"各条资料保留年代、类型、来源及许可。",11)
			shell.button(Rect2(x,y+154,178,28),"本国历史行政名录","map:home_administration")

func has_selection() -> bool:
	var selected := _selected_administration()
	if selected.is_empty(): selected=_place
	if not selected.is_empty() and not UILocale.map_name_available(selected): return false
	return not _polity.is_empty() or not _place.is_empty()

func is_country_overview() -> bool:
	return _place.is_empty() and not _polity.is_empty()

func clear_selection() -> void:
	# A cancelled map observation owns no dossier. The player identity and
	# country flag are separate MainShell inputs and are not changed here.
	_polity = {}
	_place = {}
	_profile = {}
	_administration = {}
	_flag = {}
	_texture = null
	_formal_place = false
	_economy_polity_id = ""
	_economy_label = ""
	selected_admin_id = ""
	admin_member_page = 0

func administration_entry(id: String) -> Dictionary:
	for unit: Dictionary in _administration.get("runtime_units",[]) as Array:
		if str(unit.id) == id: return unit
	if str(_place.get("place_id",""))==id and _place.get("spatial_kind")=="historical_administration": return _place
	return {}

func _selected_administration() -> Dictionary:
	return administration_entry(selected_admin_id)

func selection_name() -> String:
	var administration := _selected_administration()
	if not administration.is_empty(): return UILocale.name(administration)
	return str(_place.get("name",_polity.get("name_zh","")))

func selection_kind() -> String:
	if not _selected_administration().is_empty(): return "历史行政区"
	if str(_place.get("spatial_kind","")) in ["historical_landmark","historic_site"]: return "历史地标"
	if str(_place.get("spatial_kind","")) == "historical settlement": return "历史聚落"
	if str(_place.get("display_kind",""))=="transport_node": return "历史交通地点"
	if str(_place.get("display_kind",""))=="settlement_miniature": return "城镇微缩表现参考"
	if str(_place.get("display_kind",""))=="historic_wharf": return "历史河岸码头地域"
	if _place.has("political_source_id"): return "历史地理地域"
	if _place.has("note_zh"): return "物理地理区域"
	if not _place.is_empty(): return "城市 / 地点"
	return "政治显示范围" if bool(_polity.get("display_only",false)) else "政治实体"

func _place_political_name() -> String:
	var historical := _place.get("historical_political_identity",{}) as Dictionary
	return str(historical.get("name_zh",_polity.get("name_zh","未知")))

func _scope_text() -> String:
	if not _selected_administration().is_empty():
		if _selected_administration().get("boundary_status")!="HISTORICAL_GIS_RECONSTRUCTION": return str(_selected_administration().get("temporal_note_zh","历史名称资料；没有已接入边界。"))
		if not bool(_selected_administration().get("historical_reference_active",true)): return "当前成员读取正式世界状态。历史参考已超出适用年份，不作为当年行政界线显示。"
		return str(_selected_administration().get("temporal_note_zh","历史参考边界；当前成员读取正式世界状态。")) if _selected_administration().get("boundary_status")=="HISTORICAL_GIS_RECONSTRUCTION" else "历史名称资料；没有已接入边界。"
	if str(_place.get("spatial_kind","")) == "historical_landmark": return str(_place.historical_reference_zh)
	if str(_place.get("display_kind",""))=="transport_node": return "1900 年存在记录 · 代表位置；不代表已恢复精确线路。"
	if str(_place.get("display_kind",""))=="physical_cover": return "现代物理范围参考；不作为 1900 年土地利用事实。"
	if _place.has("note_zh"): return str(_place.note_zh)
	if not _place.is_empty(): return "已有正式地点身份。" if _formal_place else "历史展示地点，尚无正式地点身份。"
	if bool(_polity.get("display_only",false)):
		return "历史政治范围参考；边界与代表图案不能单独确定法律主权或实际控制。"
	return str(_profile.get("brief_zh","暂无背景简介。"))

func draw_card(shell: MainShell, rect: Rect2) -> void:
	if not has_selection(): return
	shell.block_panel(rect)
	var x := rect.position.x+12
	shell.label(Vector2(x,rect.position.y+25),selection_kind(),11,Color(0.73,0.68,0.49),rect.size.x-84)
	shell.label(Vector2(x,rect.position.y+56),selection_name(),18,Color(0.94,0.87,0.67),rect.size.x-24)
	shell.label(Vector2(x,rect.position.y+78),_date,10,Color(0.67,0.75,0.69))
	var facts: Array[String] = []
	var administration := _selected_administration()
	if not administration.is_empty():
		facts.append("层级 · "+UILocale.field(administration,"unit_type_name","省（一级）" if str(administration.get("unit_type",""))=="departement" else "行政地域（一级）"))
		facts.append("首府 · "+UILocale.name(administration,"capital_name"))
		facts.append("参考年份 · "+str(administration.get("observation_year",1900))+"（历史 GIS）" if administration.get("boundary_status")=="HISTORICAL_GIS_RECONSTRUCTION" else "资料年份 · "+str(administration.get("observation_year",_date)))
		var members := administration.get("land_member_ids",[]) as Array
		facts.append("当前成员 · 无已关联土地" if members.is_empty() else UILocale.text("当前成员 · %d 块") % members.size())
		facts.append("来源 · "+str(administration.get("source_name_zh","Victor Gay / TRF-GIS")) if administration.get("boundary_status")=="HISTORICAL_GIS_RECONSTRUCTION" else "历史边界 · 尚未接入")
	elif str(_place.get("spatial_kind",""))=="historical_landmark":
		facts.append("所属地点 · "+str(_place.anchor_name_zh))
		facts.append(UILocale.text("模型高度 · %.2f 米") % float(_place.model_height_m))
		facts.append("地图表现 · 微缩地标")
		facts.append("来源 · "+str(_place.source_name_zh))
	elif not _place.is_empty():
		facts.append("地点身份 · "+("正式世界地点" if _formal_place else "仅供历史 / 地理显示"))
		facts.append("类型 · "+_place_type())
		facts.append("历史关系 · "+_place_political_name() if _place.has("historical_political_identity") else "当地政体 · "+_place_political_name())
		facts.append("来源 · "+str(_place.get("source_name_zh",_place.get("source_id","未知"))))
	else:
		facts.append("历史身份 · "+str(_polity.get("name_zh","未知")))
		facts.append("范围性质 · 历史显示参考" if bool(_polity.get("display_only",false)) else "权威关系 · "+("已有关系记录" if not (_polity.get("authority_relations",[]) as Array).is_empty() else "未提供额外关联资料"))
		facts.append("适用起始 · "+str(_polity.get("valid_from","未知")))
		if _texture == null: facts.append("当日旗帜资料 · 未提供")
	if _current_territory.has("sovereign_polity_id"): facts.append("当前主权 · "+str(_current_territory.sovereign_polity_id))
	if _current_territory.has("controller_polity_id"): facts.append("实际控制 · "+str(_current_territory.controller_polity_id))
	for index: int in range(facts.size()): shell.label(Vector2(x,rect.position.y+103+index*21),facts[index],12,Color(0.86,0.85,0.74),rect.size.x-24)
	if rect.size.y>174.0+facts.size()*21:
		shell.wrapped(Vector2(x,rect.position.y+110+facts.size()*21),_scope_text(),rect.size.x-24,11,maxi(1,int((rect.size.y-174-facts.size()*21)/20)))
	shell.button(Rect2(x,rect.end.y-34,82,24),"完整资料","page:world")
	if administration.is_empty(): shell.button(Rect2(rect.end.x-90,rect.end.y-34,78,24),"地图定位","map:focus")
	else: shell.button(Rect2(rect.end.x-90,rect.end.y-34,78,24),"地图定位","admin:focus",administration.get("boundary_status")=="HISTORICAL_GIS_RECONSTRUCTION" and bool(administration.get("historical_reference_active",true)))

func _place_type() -> String:
	if str(_place.get("spatial_kind",""))=="historic_site": return "历史地标"
	if str(_place.get("display_kind",""))=="transport_node": return "历史车站 / 桥梁位置参考"
	if str(_place.get("display_kind",""))=="settlement_miniature": return "有来源的城市地域 · 抽象建筑组合"
	if str(_place.get("display_kind",""))=="historic_wharf": return "历史河岸工业 / 码头地域参考"
	var kind := str(_place.get("spatial_kind",_place.get("kind","")))
	return str({"city":"城市","port":"港口","region":"地域","historical_landmark":"历史地标","historical settlement":"历史聚落","historical strategic settlement":"历史聚落","settlement":"聚落","island":"岛屿","continent":"大陆","geographic_region":"地理区域"}.get(kind,"物理地理区域" if _place.has("note_zh") else "未知"))

func draw_details(shell: MainShell, rect: Rect2) -> void:
	if not _selected_administration().is_empty():
		_draw_admin_members(shell,rect)
		return
	if not has_selection():
		shell.heading(rect,"对象资料","")
		shell.label(rect.position+Vector2(22,118),"请在地图中选择对象。",13)
		return
	if _place.is_empty() and not _polity.is_empty():
		_draw_country_overview(shell,rect)
		return
	shell.heading(rect,selection_name(),_scope_text())
	var x := rect.position.x+22
	var y := rect.position.y+114
	var width := rect.size.x*0.54-32
	var facts: Array[String] = ["日期："+_date]
	if not _place.is_empty():
		facts.append("资料范围："+("正式世界地点" if _formal_place else "历史展示 / 物理地理参考"))
		if _current_territory.has("sovereign_polity_id"): facts.append("当前主权："+str(_current_territory.sovereign_polity_id))
		if _current_territory.has("controller_polity_id"): facts.append("实际控制："+str(_current_territory.controller_polity_id))
		facts.append("地点类型："+(_place_type() if str(_place.get("spatial_kind","")) in ["historical_landmark","historic_site"] else str(_place.get("spatial_kind",_place.get("kind","未记录")))))
		facts.append("来源："+str(_place.get("source_name_zh",_place.get("source_id","正式空间目录" if _formal_place else "未记录"))))
		facts.append("历史政治关系："+_place_political_name())
		if _place.has("transport_evidence_class"):
			facts.append("资料类型："+("历史连接关系，线位未恢复" if str(_place.transport_evidence_class).begins_with("B_") else "存在及代表位置"))
			facts.append("历史参考："+str(_place.get("historical_reference_date","未记录")))
		var historical := _place.get("historical_political_identity",{}) as Dictionary
		if not historical.is_empty():
			facts.append("历史地位："+str(historical.get("status_zh","未记录")))
			facts.append("关系说明："+str(historical.get("relationship_zh","未记录")))
		if _place.has("political_source_id"):
			facts.append("历史归属参考："+str(_place.get("political_reference_date","未记录")))
			facts.append("岸线性质：现代物理参考；归属依据另列")
		if str(_place.get("spatial_kind",""))=="historical_landmark":
			var coordinates := (_place.geometry as Dictionary).coordinates as Array
			facts.append("所属地点："+str(_place.anchor_name_zh))
			facts.append(UILocale.text("位置参考：%.6f°, %.6f°") % [float(coordinates[0]),float(coordinates[1])])
			if str(_place.get("dimensions_type",""))=="SCHEMATIC_METRES":
				facts.append(UILocale.text("模型包络：高 %.1f 米；宽 %.1f 米") % [float(_place.model_height_m),float(_place.model_base_width_m)])
			else:
				facts.append(UILocale.text("建筑尺寸参考：高 %.2f 米；主基座 %.0f 米") % [float(_place.real_height_m),float(_place.real_base_width_m)])
	else:
		facts.append("历史身份："+str(_polity.get("name_zh","未记录")))
		facts.append("地位："+str(_polity.get("status","未记录")))
		facts.append("适用日期："+str(_polity.get("valid_from","未记录"))+" — "+str(_polity.get("valid_to","未记录")))
		facts.append("资料状态："+("已有历史身份资料" if str(_polity.get("historical_metadata_state",""))=="available" else "历史显示资料" if bool(_polity.get("display_only",false)) else "历史资料未提供"))
	var spacing := minf(24.0,maxf(15.0,(rect.size.y-190.0)/float(facts.size())))
	for index: int in range(facts.size()): shell.label(Vector2(x,y+float(index)*spacing),facts[index],10 if spacing<20.0 else 12,Color(0.82,0.86,0.79),width)
	var right := Vector2(rect.position.x+rect.size.x*0.56,y)
	var city := CityOverview.for_place(str(_place.get("place_id",_place.get("id",""))))
	if not city.is_empty():
		shell.label(right,"地图资料",13)
		shell.wrapped(right+Vector2(0,28),str(city.get("caption","")),rect.end.x-right.x-22,11,3)
		shell.wrapped(right+Vector2(0,91),str(city.get("water_reference_note_zh","")),rect.end.x-right.x-22,11,3)
		shell.wrapped(right+Vector2(0,154),str(city.get("attribution","")),rect.end.x-right.x-22,10,4)
		shell.wrapped(right+Vector2(0,226),str(city.get("source",{}).get("url","")),rect.end.x-right.x-22,10,3)
	elif str(_place.get("spatial_kind",""))=="historical_landmark":
		shell.wrapped(right,str(_place.historical_reference_zh),rect.end.x-right.x-22,12,3)
		shell.wrapped(right+Vector2(0,76),str(_place.coordinate_notice_zh),rect.end.x-right.x-22,11,3)
		shell.wrapped(right+Vector2(0,151),str(_place.get("real_dimensions_note_zh","")),rect.end.x-right.x-22,11,3)
		if _place.has("terrain_note_zh"): shell.wrapped(right+Vector2(0,217),str(_place.terrain_note_zh),rect.end.x-right.x-22,10,3)
	elif _place.has("display_kind"):
		shell.wrapped(right,str(_place.get("model_note_zh",_place.get("note_zh",""))),rect.end.x-right.x-22,11,6)
		shell.wrapped(right+Vector2(0,145),str(_place.get("model_source_reference",_place.get("source_reference",""))),rect.end.x-right.x-22,10,4)
		shell.wrapped(right+Vector2(0,240),str(_place.get("source_license","")),rect.end.x-right.x-22,10,2)
		if _place.has("miniature_layout"):
			var layout := _place.miniature_layout as Dictionary
			shell.wrapped(right+Vector2(0,294),str(layout.get("placement_notice_zh","")),rect.end.x-right.x-22,10,3)
	elif _place.has("political_source_id"):
		shell.wrapped(right,str(_place.get("note_zh","")),rect.end.x-right.x-22,11,6)
		shell.wrapped(right+Vector2(0,135),str(_place.get("source_reference","")),rect.end.x-right.x-22,10,4)
		if _place.has("source_license"): shell.wrapped(right+Vector2(0,228),str(_place.source_license),rect.end.x-right.x-22,10,3)
	elif _texture != null:
		shell.draw_country_flag(_texture,Rect2(right,Vector2(100,64)))
		shell.wrapped(right+Vector2(112,14),str(_flag.get("flag_type",_flag.get("visual_type","已有旗帜 / 视觉记录"))),rect.end.x-right.x-132,11,3)
	elif _place.has("note_zh"): shell.wrapped(right,str(_place.note_zh),rect.end.x-right.x-22,12,6)
	else: shell.wrapped(right,"当前日期暂无旗帜资料。",rect.end.x-right.x-22,12,3)
	var relations: Array[String] = []
	for relation: Dictionary in _polity.get("authority_relations",[]) as Array:
		relations.append(str(relation.get("relation_type","权威关系"))+"："+str(relation.get("target_name",relation.get("target_runtime_id",""))))
	if city.is_empty() and str(_place.get("spatial_kind",""))!="historical_landmark" and not _place.has("political_source_id"):
		if not relations.is_empty(): shell.lines(right+Vector2(0,91),relations.slice(0,3),rect.end.x-right.x-22)
		elif not _polity.is_empty(): shell.label(right+Vector2(0,112),"没有额外权威关系记录。",11)
	shell.button(Rect2(rect.end.x-120,rect.end.y-36,98,26),"地图定位","map:focus")

func _draw_country_overview(shell: MainShell, rect: Rect2) -> void:
	shell.folio_title(rect,UILocale.name(_polity)+" · 国家概况",23)
	if _texture!=null: shell.draw_country_flag(_texture,Rect2(rect.end.x-94,rect.position.y+72,64,42))
	var x := rect.position.x+26
	var y := rect.position.y+91
	var width := (rect.size.x-72)*0.5
	var status := str(_polity.get("status","未记录"))
	shell.label(Vector2(x,y),"地位："+str({"sovereign":"主权国家","dependent":"属地"}.get(status,status)),12)
	var government := _profile.get("government_summary",{}) as Dictionary
	var form := UILocale.field(government,"form")
	if not form.is_empty(): shell.label(Vector2(x,y+28),"制度："+form,14,Color(0.91,0.84,0.65),width)
	var roles := shell.organization_page.player_government_roles(str(_polity.get("id","")))
	if not roles.is_empty(): shell.wrapped(Vector2(x,y+58),"本人职务："+"、".join(roles),width,12,2)
	_draw_government(shell,Rect2(x+width+20,y-14,width-(80 if _texture!=null else 0),110))
	var economic: String=Structure.summary(str(_polity.get("source_historical_id","")))
	if not economic.is_empty(): shell.label(Vector2(x,rect.position.y+181),"经济概况 · 就业参考 · "+economic,11,UIDrawing.FOLIO_MUTED,rect.size.x-52)
	_draw_admin_list(shell,Rect2(x,rect.position.y+201,rect.size.x-52,rect.size.y-237))

func _draw_government(shell: MainShell, rect: Rect2) -> void:
	var government := _profile.get("government_summary",{}) as Dictionary
	var executive := UILocale.field(government,"executive")
	var legislature := UILocale.field(government,"legislature")
	if executive.is_empty() and legislature.is_empty() and (government.get("institutions",[]) as Array).is_empty(): return
	shell.label(rect.position+Vector2(0,14),"国家机构",13)
	var institutions := government.get("institutions",[]) as Array
	if not institutions.is_empty():
		for index: int in range(mini(3,institutions.size())):
			var row := institutions[index] as Dictionary
			shell.label(rect.position+Vector2(0,40+index*24),UILocale.field(row,"label")+"："+UILocale.field(row,"value"),12,Color(0.82,0.86,0.79),rect.size.x)
	else:
		if not executive.is_empty(): shell.label(rect.position+Vector2(0,40),"政府："+executive,12,Color(0.82,0.86,0.79),rect.size.x)
		if not legislature.is_empty(): shell.label(rect.position+Vector2(0,65),"议会："+legislature,12,Color(0.82,0.86,0.79),rect.size.x)

func _draw_admin_list(shell: MainShell, rect: Rect2) -> void:
	var units := _administration.get("runtime_units",[]) as Array
	var title := ("▾" if admin_drawer_open else "▸")+UILocale.text(" 行政区 · %d") % units.size()
	shell.button(Rect2(rect.position,Vector2(rect.size.x,28)),title,"admin:toggle",not units.is_empty(),admin_drawer_open,13,"folio_control" if shell.current_page=="world" else "")
	if admin_drawer_open and not units.is_empty():
		shell.draw_administration_drawer(Rect2(rect.position+Vector2(0,34),Vector2(rect.size.x,maxf(26,rect.size.y-34))),units)

func draw_administration(shell: MainShell, rect: Rect2) -> void:
	if not selected_admin_id.is_empty():
		_draw_admin_members(shell,rect)
		return
	shell.heading(rect,str(_polity.get("name_zh",""))+" · 历史行政名录",str(_administration.get("source_basis","历史名称资料；没有已接入边界。")))
	_draw_admin_list(shell,Rect2(rect.position+Vector2(22,106),rect.size-Vector2(44,158)))

func _draw_admin_members(shell: MainShell, rect: Rect2) -> void:
	var selected := _selected_administration()
	if selected.get("boundary_status")!="HISTORICAL_GIS_RECONSTRUCTION":
		shell.heading(rect,UILocale.name(selected),str(selected.get("temporal_note_zh","历史名称资料；没有已接入边界。")))
		var width := rect.size.x*0.54-32
		shell.lines(rect.position+Vector2(22,114),["类型："+UILocale.field(selected,"unit_type_name","历史身份"),"参考年份："+str(selected.get("observation_year","未记录")),"行政中心："+UILocale.name(selected,"capital_name"),"尚无该单位的独立辖区边界。","来源："+str(selected.get("source_name_zh","未记录"))],width)
		shell.wrapped(rect.position+Vector2(22,244),str(selected.get("authority_type_name_zh",""))+"\n"+str(selected.get("source_citation","")),width,11,4)
		_draw_admin_hierarchy(shell,rect,selected)
		return
	shell.heading(rect,UILocale.name(selected),str(selected.get("temporal_note_zh","")))
	var ids := selected.get("land_member_ids",[]) as Array
	var x := rect.position.x+22
	var width := rect.size.x*0.54-32
	var right := rect.position.x+rect.size.x*0.56
	var reference_area := float(selected.get("boundary_area_km2",0.0))
	var covered_area := float(selected.get("formal_coverage_area_km2",0.0))
	var facts: Array[String] = ["层级："+UILocale.field(selected,"unit_type_name","行政地域" if selected.get("unit_type")=="territoire" else "省"),"首府："+UILocale.name(selected,"capital_name"),UILocale.text("历史重建图形：约 %.2f km²") % reference_area,UILocale.text("当前正式成员：%d 块 · %.2f km²") % [ids.size(),float(selected.get("known_area_km2",0.0))],"历史范围内正式覆盖：正在计算" if bool(selected.get("formal_coverage_pending",false)) else UILocale.text("历史范围内正式覆盖：%.2f km²（%.1f%%）") % [covered_area,100.0*covered_area/maxf(reference_area,0.001)],"边界相交资料：正在计算" if bool(selected.get("formal_coverage_pending",false)) else UILocale.text("相交但当前成员待定：%d 块") % (selected.get("intersecting_unresolved_land_ids",[]) as Array).size(),"来源："+str(selected.get("source_name_zh","Victor Gay / TRF-GIS")),"参考年份："+str(selected.get("observation_year",1900)),"许可："+str(selected.get("source_license","CC BY 4.0"))]
	if selected.has("display_note_zh"): facts.append("显示：物理海岸遮罩；原历史 GIS 不变")
	var spacing := minf(24.0,maxf(14.0,(rect.size.y-200.0)/float(facts.size())))
	for index: int in range(facts.size()): shell.label(Vector2(x,rect.position.y+114+index*spacing),facts[index],11,Color(0.82,0.86,0.79),width)
	var note_y := 124.0+facts.size()*spacing
	var note_rows := mini(3,maxi(0,int((rect.size.y-60.0-note_y)/18.0)))
	if note_rows>0: shell.wrapped(Vector2(x,rect.position.y+note_y),str(selected.get("membership_basis_zh",""))+str(selected.get("accuracy_note_zh","")),width,11,note_rows)
	var has_hierarchy := not (selected.get("child_units",[]) as Array).is_empty() or not (selected.get("related_units",[]) as Array).is_empty() or not str(selected.get("parent_name_zh","")).is_empty()
	if has_hierarchy:
		_draw_admin_hierarchy(shell,rect,selected)
		shell.button(Rect2(x,rect.end.y-36,100,26),"定位辖区","admin:focus",bool(selected.get("historical_reference_active",true)))
		return
	var y := rect.position.y+114
	var rows := maxi(1,int((rect.size.y-174)/28))
	for index: int in range(admin_member_page*rows,mini(ids.size(),(admin_member_page+1)*rows)):
		shell.label(Vector2(right,y+17),"空间成员 · "+str(ids[index]),10,Color(0.73,0.76,0.70),rect.end.x-right-22)
		y += 28
	if ids.is_empty(): shell.wrapped(Vector2(right,y),"没有已确定的正式土地成员。",rect.end.x-right-22,12,2)
	var source_note := str(selected.get("classification_note_zh",""))+"\n"+str(selected.get("source_citation",""))+"\n"+str(selected.get("boundary_reference",""))
	if ids.is_empty(): shell.wrapped(Vector2(right,y+54),source_note,rect.end.x-right-22,10,maxi(1,int((rect.size.y-242)/18)))
	shell.button(Rect2(x+110,rect.end.y-36,100,26),"定位省界","admin:focus",bool(selected.get("historical_reference_active",true)))
	shell.button(Rect2(right,rect.end.y-36,82,26),"上一页","admin:members_previous",admin_member_page>0)
	shell.button(Rect2(right+90,rect.end.y-36,82,26),"下一页","admin:members_next",(admin_member_page+1)*rows<ids.size())

func _draw_admin_hierarchy(shell: MainShell, rect: Rect2, selected: Dictionary) -> void:
	var x := rect.position.x+rect.size.x*0.56
	var width := rect.end.x-x-22
	var y := rect.position.y+111
	var parent_name := str(selected.get("parent_name_zh",""))
	if not parent_name.is_empty(): parent_name=UILocale.name({"id":selected.get("parent_region_id",""),"name_zh":parent_name})
	if not parent_name.is_empty():
		shell.button(Rect2(x,y-18,width,25),str(selected.get("parent_relationship_name_zh","上级"))+" · "+parent_name,"admin:select:"+str(selected.parent_region_id))
		y += 34
	var authority := str(selected.get("authority_type_name_zh",""))
	if not authority.is_empty():
		shell.wrapped(Vector2(x,y),authority,width,10,2)
		y += 38
	var children := selected.get("child_units",[]) as Array
	var related := selected.get("related_units",[]) as Array
	var entries := children if not children.is_empty() else related
	var caption := "下级／所属单位" if not children.is_empty() else str(selected.get("related_relationship_name_zh","对应单位（合并几何参考）")) if not related.is_empty() else "暂无已接入的下级名录。"
	shell.label(Vector2(x,y),caption+" · "+str(entries.size()) if not entries.is_empty() else caption,12)
	y += 26
	if not entries.is_empty():
		shell.draw_administration_drawer(Rect2(x,y-8,width,maxf(26,rect.end.y-110-(y-8))),entries)
	else:
		shell.wrapped(Vector2(x,y+10),str(selected.get("classification_note_zh","")),width,11,3)
	shell.wrapped(Vector2(x,rect.end.y-94),str(selected.get("boundary_reference",selected.get("identity_reference",""))),width,10,3)

func card_height() -> float:
	if not _selected_administration().is_empty(): return 290
	return 270
