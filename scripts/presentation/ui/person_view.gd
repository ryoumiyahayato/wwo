class_name PersonView
extends RefCounted
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
var _person: Dictionary = {}
var _place: Dictionary = {}
var _memberships: Array[Dictionary] = []
var _personal: Dictionary = {}
var _receipts: Array[Dictionary] = []
var section: String = "situation"
var account_page: int = 0
var native_scope_expanded: bool = false
var capital_mode: bool = false
var business_mode: bool = false
var business_procurement_mode: bool = true
var business_finance_mode: bool = false
var business_finance_page: int = 0
var lease_mode: bool = false
var business_leases_mode: bool = false
var lease_page: int = 0
var resident_services_mode: bool = false
var resident_service_page: int = 0
var business_services_mode: bool = false
var business_service_page: int = 0
var business_firm_index: int = 0
var business_site_index: int = 0
var business_firm_id: String = ""
var business_site_id: String = ""
var business_offer_page: int = 0
var business_activity_page: int = 0
var _business: Dictionary = {}
var capital_page: int = 0
var business_capital_mode: bool = false
var business_capital_page: int = 0
var business_capital_action_page: int = 0
var native_jobs_page: int = 0
var native_tab: String = "jobs"
var selected_job_id: String = ""
var native_wage_page: int = 0
var native_diagnostics: bool = false
var _place_names: Dictionary = {}
var native_order_page: int = 0
var inventory_page: int = 0
var living_page: int = 0
var selected_commodity_id: String = ""
var selected_record_id: String = ""
var quantity_milli: int = 1
var _property: Dictionary = {}
var _location_country: String = ""
var _location_admin: String = ""
var daily_enabled: bool = false
var available_market: bool = false
const RECEIPT_PAGE_SIZE: int = 6

static func receipt_page_size(height: float) -> int:
	return clampi(int((height-240)/28),1,RECEIPT_PAGE_SIZE)

func refresh(person: Dictionary, place: Dictionary, memberships: Array[Dictionary], personal: Dictionary, receipts: Array[Dictionary], property_view: Dictionary) -> void:
	if not _person.is_empty() and _person.get("person_id") != person.get("person_id"):
		selected_job_id = ""
		native_wage_page = 0
	_person = person
	_place = place
	_memberships = memberships
	_personal = personal
	_receipts = receipts
	_property = property_view
	daily_enabled = not (property_view.get("arrangement",{}) as Dictionary).is_empty()

func identity_name() -> String:
	return str(_person.get("name_zh",_person.get("name",_person.get("display_name","姓名未记录"))))

func place_name() -> String:
	return str(_place.get("name","所在地资料未记录"))

func cash_text() -> String:
	var cash: Variant = _personal.get("cash")
	return "现金 %s · 可用 %s · 预留 %s %s" % [str(cash),str(_personal.get("available",cash)),str(_personal.get("reserved",0)),EconomicText.currency(str(_personal.get("denomination",FormalLedgerState.DENOMINATION)))] if typeof(cash)==TYPE_INT else "现金资料不可用"

func livelihood_text() -> String:
	return "原生实际劳动" if _personal.get("native", false) and not (_personal.get("employment", {}) as Dictionary).is_empty() else "旧工资已终止" if int(_personal.get("legacy_wage_end_minute", -1)) >= 0 else "一般工资劳动" if not (_personal.get("employment",{}) as Dictionary).is_empty() else "暂无正式就业"

func employer_text() -> String:
	return "雇主："+(EconomicText.firm(str(_personal.get("employer",{}).get("employer_id",""))) if _personal.get("native",false) and not (_personal.get("employment",{}) as Dictionary).is_empty() else "暂无正式雇主" if _personal.get("native",false) else str((_personal.get("employer",{}) as Dictionary).get("label","无记录")))

func next_pay_text() -> String:
	if not _personal.get("native", false) and int(_personal.get("legacy_wage_end_minute", -1)) >= 0: return "历史欠付待结" if _personal.get("wage_unpaid", false) else "未来旧工资已停止"
	var employment := _personal.get("employment",{}) as Dictionary
	return boundary_text(int(employment.next_pay_boundary)) if employment.has("next_pay_boundary") else ("按实际工作到期" if _personal.get("native",false) and not employment.is_empty() else "无安排")

static func boundary_text(minute: int) -> String:
	var date := GameCalendar.from_total_hour(minute / 60)
	return "%04d-%02d-%02d %02d:%02d" % [date.year,date.month,date.day,date.hour,minute%60]

func set_location_context(spatial: VNextSpatialWorld, control: TerritoryState, polity: Dictionary) -> void:
	_place_names.clear()
	var places: Array = [_personal.get("current_place_id", "")]
	for job: Dictionary in _personal.get("known_jobs", []): places.append(job["place"])
	for order: Dictionary in _personal.get("orders", []): places.append(order.get("to_place_id", ""))
	for id: String in places:
		if _place_names.has(id): continue
		var record := spatial.get_place(id)
		_place_names[id] = record.get("name_zh",record.get("name","地点名称未记录"))
	_location_country = str(polity.get("name_zh","国家未知"))
	_location_admin = "行政归属未确定"
	var coordinates := _place.get("lon_lat",[]) as Array
	if coordinates.size()!=2 or spatial.land_topology()==null: return
	var id := spatial.land_topology().pick_geographic(Vector2(float(coordinates[0]),float(coordinates[1])))
	var land := spatial.land_details(id,control)
	var region: Variant = land.get("administrative_region_id")
	if region!=null:
		_location_admin = str(spatial.administrative_identity(str(region)).get("name_zh","行政名称未记录"))

func draw(shell: MainShell, rect: Rect2) -> void:
	shell.draw_rect(rect, Color(0.022,0.032,0.028,0.97))
	if section=="native":
		_draw_native(shell,rect)
		return
	shell.label(rect.position+Vector2(20,34),identity_name(),23,Color(0.96,0.88,0.67),rect.size.x-110)
	var place_rect := Rect2(rect.position+Vector2(20,50),Vector2(rect.size.x*0.47-24,96))
	shell.draw_rect(place_rect,Color(0.055,0.072,0.060,0.62))
	shell.label(place_rect.position+Vector2(12,24),place_name(),18)
	shell.label(place_rect.position+Vector2(12,47),_location_admin,11,Color(0.80,0.82,0.73),place_rect.size.x-110)
	shell.label(place_rect.position+Vector2(12,68),_location_country,11,Color(0.80,0.82,0.73),place_rect.size.x-110)
	shell.button(Rect2(place_rect.position+Vector2(10,73),Vector2(74,21)),"地图定位","person:focus")
	var coordinates := _place.get("lon_lat",[]) as Array
	if coordinates.size()==2:
		UIDrawing.location_diagram(shell,Rect2(place_rect.end.x-100,place_rect.position.y+12,88,66),Vector2(float(coordinates[0]),float(coordinates[1])))
	var cash_x := rect.position.x+rect.size.x*0.50
	shell.label(Vector2(cash_x,rect.position.y+66),"现金余额",11)
	var cash: Variant = _personal.get("cash")
	shell.label(Vector2(cash_x,rect.position.y+98),str(cash) if cash!=null else "未记录",28,Color(0.96,0.86,0.59),rect.end.x-cash_x-20)
	shell.label(Vector2(cash_x,rect.position.y+119),EconomicText.currency(str(_personal.get("denomination",FormalLedgerState.DENOMINATION))),10,Color(0.76,0.79,0.70))
	var employment := _personal.get("employment",{}) as Dictionary
	var wage := livelihood_text()
	if not employment.is_empty():
		wage = "工资 %s / 小时 · %s" % [employment.get("wage_per_hour","未记录"),EconomicText.currency(str(employment.get("denomination",FormalLedgerState.DENOMINATION)))] if _personal.get("native",false) else "工资 %s / %d 天" % [employment.get("wage_amount","未记录"),int(employment.get("pay_period_minutes",1440))/(24*60)]
	if not _personal.get("native", false) and int(_personal.get("legacy_wage_end_minute", -1)) >= 0: wage = "旧工资已终止；历史欠付保留"
	shell.label(Vector2(cash_x,rect.position.y+141),wage,11,Color(0.82,0.86,0.79),rect.end.x-cash_x-20)
	var tabs: Array[Dictionary] = [{"name":"财务摘要","id":"situation"},{"name":"物品与消费","id":"goods"},{"name":"近期账务","id":"accounts"},{"name":"消费记录","id":"records"}]
	for index: int in range(tabs.size()):
		shell.button(Rect2(rect.position.x+20+index*108,rect.position.y+157,100,25),str(tabs[index].name),"person:"+str(tabs[index].id),true,section==str(tabs[index].id))
	var area := Rect2(rect.position+Vector2(20,195),Vector2(rect.size.x-40,rect.size.y-239))
	match section:
		"accounts": _draw_accounts(shell,area)
		"records": _draw_records(shell,area)
		"goods": _draw_goods(shell,area)
		_: _draw_summary(shell,area)
	if available_market: shell.button(Rect2(rect.position.x+20,rect.end.y-34,124,24),"查看可用市场","person:market")
	shell.button(Rect2(rect.position.x+140,rect.end.y-34,112,24),"组织关系","person:organizations")
	if _personal.get("native",false) or not _personal.get("handover", []).is_empty(): shell.button(Rect2(rect.position.x+260,rect.end.y-34,112,24),"就业与生活","person:native")

func _draw_summary(shell: MainShell, area: Rect2) -> void:
	var left := Rect2(area.position,Vector2(area.size.x*0.48,area.size.y))
	var right := Rect2(left.end.x+16,area.position.y,area.end.x-left.end.x-16,area.size.y)
	shell.label(left.position+Vector2(0,15),"个人持有",13)
	var rows := _property.get("rows",[]) as Array
	for index: int in range(mini(rows.size(),maxi(0,int((area.size.y-30)/27)))):
		var row := rows[index] as Dictionary
		shell.button(Rect2(left.position+Vector2(0,25+index*27),Vector2(left.size.x*0.58,23)),str(row.name_zh),"holding:select:"+str(row.commodity_id))
		shell.number(Vector2(left.position.x+left.size.x*0.60,left.position.y+43+index*27),"%.3f %s" % [float(row.quantity_milli)/float(row.get("quantity_scale",1000)),row.unit_name_zh],left.size.x*0.40-6,11)
	if rows.is_empty(): shell.label(left.position+Vector2(0,46),"暂无个人持有物品。",12)
	shell.label(right.position+Vector2(0,15),"最近收支",13)
	var livelihood := _personal.get("livelihood_state", {}) as Dictionary
	if not (livelihood.get("legacy_wage", {}) as Dictionary).is_empty():
		shell.label(Vector2(right.position.x, area.end.y-74), "旧欠付周期："+str(livelihood.get("overdue_legacy_periods", 0))+" · 截止 "+str(livelihood.get("legacy_wage_end_minute", -1)), 10, Color(0.82,0.86,0.79), right.size.x)
		shell.button(Rect2(right.position.x, area.end.y-62, right.size.x, 24), "申请在原周期结束旧工资", "livelihood:terminate_wage", bool(livelihood.get("can_terminate_legacy_wage", false)))
	for change: Dictionary in livelihood.get("changes", []):
		if change["command"]["kind"] == "terminate_legacy_wage" and change["status"] == "QUEUED": shell.label(Vector2(right.position.x, area.end.y-26), "待终止："+boundary_text(int(change["boundary_minute"])), 10, Color(0.82,0.86,0.79), right.size.x)
	var residence := _personal.get("residence", {}) as Dictionary
	shell.label(Vector2(area.position.x, area.end.y-12), "常住："+str(residence.get("resident_population_unit_id", ""))+" · 活动："+str(residence.get("activity_population_unit_id", ""))+" · "+str(_personal.get("management_scope_id", "旧经济")), 10, Color(0.82,0.86,0.79), area.size.x)
	_draw_receipt_rows(shell,Rect2(right.position+Vector2(0,26),right.size-Vector2(0,26)),mini(3,_receipts.size()))
	if _receipts.is_empty(): shell.label(right.position+Vector2(0,46),"暂无账务记录。",12)

func _draw_receipt_rows(shell: MainShell, area: Rect2, count: int) -> void:
	var account_id := str(_personal.get("account_id",""))
	var own_accounts: Dictionary = {account_id: true}
	for account: Dictionary in _personal.get("accounts", []): own_accounts[account["account_id"]] = true
	for index: int in range(count):
		var receipt := _receipts[index]
		var y := area.position.y+19+index*28
		var incoming := own_accounts.has(str(receipt.get("to_account_id","")))
		var kind := str({"wage":"工资","opening_cash":"开局现金","purchase":"购买","native_purchase":"购买","person_travel":"旅费"}.get(str(receipt.get("kind","")),receipt.get("kind","交易")))
		shell.label(Vector2(area.position.x,y),boundary_text(int(receipt.effective_minute))+" · "+kind+" · "+EconomicText.currency(str(receipt.get("denomination",FormalLedgerState.DENOMINATION))),11,Color(0.82,0.86,0.79),area.size.x*0.64)
		shell.number(Vector2(area.position.x+area.size.x*0.66,y),("+" if incoming else "−")+str(receipt.amount),area.size.x*0.34,12,Color(0.78,0.86,0.70) if incoming else Color(0.92,0.73,0.57))

func _draw_accounts(shell: MainShell, area: Rect2) -> void:
	var count := receipt_page_size(shell.workspace_rect().size.y)
	_draw_receipt_rows(shell,area,mini(count,_receipts.size()))
	if _receipts.is_empty(): shell.label(area.position+Vector2(0,21),"暂无账务记录。",12)
	if account_page>0 or _receipts.size()>count:
		shell.button(Rect2(area.position.x,area.end.y-25,78,23),"较新记录","person:previous",account_page>0)
		shell.button(Rect2(area.position.x+88,area.end.y-25,78,23),"较早记录","person:next",_receipts.size()>count)

func _draw_goods(shell: MainShell, area: Rect2) -> void:
	var left := Rect2(area.position,Vector2(area.size.x*0.46,area.size.y))
	var right := Rect2(left.end.x+16,area.position.y,area.end.x-left.end.x-16,area.size.y)
	var rows := _property.get("rows",[]) as Array
	var count := EconomyPage.market_page_size(shell.workspace_rect().size.y)
	for index: int in range(mini(count,rows.size())):
		var row := rows[index] as Dictionary
		var y := left.position.y+index*27
		shell.button(Rect2(left.position.x,y,left.size.x*0.58,23),str(row.name_zh),"holding:select:"+str(row.commodity_id),true,selected_commodity_id==str(row.commodity_id))
		shell.number(Vector2(left.position.x+left.size.x*0.60,y+18),"%.3f %s" % [float(row.quantity_milli)/float(row.get("quantity_scale",1000)),row.unit_name_zh],left.size.x*0.40-4,11)
	if rows.is_empty(): shell.label(left.position+Vector2(0,20),"暂无个人持有物品。",12)
	if inventory_page>0 or rows.size()>count:
		shell.button(Rect2(left.position.x,left.end.y-25,70,23),"上一页","inventory:previous",inventory_page>0)
		shell.button(Rect2(left.position.x+80,left.end.y-25,70,23),"下一页","inventory:next",rows.size()>count)
	var owned := _property.get("selected",{}) as Dictionary
	if owned.is_empty():
		shell.label(right.position+Vector2(0,20),"选择物品查看消费及持有记录。",11,Color(0.78,0.82,0.73),right.size.x)
		return
	var unit := str(owned.get("unit_name_zh",""))
	shell.label(right.position+Vector2(0,19),str(owned.get("name_zh","物品")),16)
	shell.label(right.position+Vector2(0,42),"实际持有 %.3f %s · 已消费 %.3f" % [float(owned.quantity_milli)/float(owned.get("quantity_scale",1000)),unit,float(owned.get("consumed_milli",0))/float(owned.get("quantity_scale",1000))],11,Color(0.82,0.86,0.79),right.size.x)
	var capability := _property.get("capability",{}) as Dictionary
	var plan := _property.get("arrangement",{}) as Dictionary
	if bool(capability.get("daily_supported",capability.get("consumable",false))):
		shell.quantity_input(Rect2(right.position+Vector2(0,53),Vector2(132,26)),quantity_milli,"person:"+selected_commodity_id,int(capability.get("quantity_scale",1000)))
		var quote := _property.get("quote",{}) as Dictionary
		shell.button(Rect2(right.position.x+144,right.position.y+53,100,26),"消费","consume",bool(quote.get("success",false)))
		var reason := str(quote.get("error","")) if not bool(quote.get("success",false)) else ""
		if not plan.is_empty(): reason = "每日 %.3f %s · 下次 %s" % [float(plan.quantity_milli)/float(plan.get("quantity_scale",1000)),unit,boundary_text(int(plan.next_due_minute))]
		shell.wrapped(right.position+Vector2(0,100),reason,right.size.x,13,2)
		var food:=_personal.get("need_today",{}).get("categories",{}).get("food",{}) as Dictionary
		if not food.is_empty(): shell.label(right.position+Vector2(0,160),"今日食物需要：满足%d／需要%d · 未满足%d" % [int(food.get("satisfied",0)),int(food.get("required",0)),int(food.get("unmet",0))],13,Color(0.94,0.84,0.61),right.size.x)
		shell.button(Rect2(right.position.x,right.end.y-25,145,23),"停止每日安排" if not plan.is_empty() else "设为每日消费","consumption:daily")
		if not plan.is_empty(): shell.button(Rect2(right.position.x+153,right.end.y-25,right.size.x-153,23),"停止缺量采购" if plan.get("auto_buy_missing",false) else "允许缺量采购","consumption:autobuy")
	else: shell.label(right.position+Vector2(0,75),"该物品暂无消费操作。",11)

	if not selected_commodity_id.begins_with("native:") and not plan.is_empty():
		shell.button(Rect2(right.position.x, right.position.y+152, right.size.x, 24), "申请停止旧每日安排", "livelihood:cancel_plan")
		var conversion := _property.get("conversion_quote", {}) as Dictionary
		shell.button(Rect2(right.position.x, right.position.y+180, right.size.x, 24), "接管时转换安排（保留补购授权）", "livelihood:convert_plan", bool(conversion.get("success", false)))
		if not conversion.get("success", false): shell.label(right.position+Vector2(0,220), str(conversion.get("reason", "没有原生安排接收者")), 10, Color(0.82,0.86,0.79), right.size.x)

func _draw_records(shell: MainShell, area: Rect2) -> void:
	var record := _property.get("record",{}) as Dictionary
	if not record.is_empty():
		var info: Array[String] = [boundary_text(int(record.effective_minute))+" · "+str(record.name_zh),"数量 %.3f %s" % [float(record.quantity_milli)/float(record.get("quantity_scale",1000)),record.get("unit_name_zh","")]]
		if record.has("amount"): info.append("金额 "+str(record.amount)+" "+EconomicText.currency(str(record.get("denomination",FormalLedgerState.DENOMINATION))))
		if not str(record.get("reason","")).is_empty():
			var reason:=str(record.reason)
			if reason!=reason.to_upper() or "_" not in reason: info.append(reason)
			else:
				shell.button(Rect2(area.position.x,area.end.y-30,180,26),"收起技术依据" if native_diagnostics else "技术依据（折叠）","person:job_diagnostics")
				if native_diagnostics: info.append(reason)
		shell.lines(area.position+Vector2(0,20),info,area.size.x)
		return
	var rows := _property.get("records",[]) as Array
	var count := receipt_page_size(shell.workspace_rect().size.y)
	for index: int in range(mini(count,rows.size())):
		var row := rows[index] as Dictionary
		var kind := str({"purchase":"购买","consume":"消费","arrangement_failed":"安排失败","arrangement_set":"每日消费","arrangement_cancelled":"停止安排","native_order":"订单","native_delivery":"到货","native_consume":"消费","native_loss":"确认货损","legacy_handover":"物品口径交接","native_handover":"承接个人物品"}.get(str(row.kind),row.kind))
		shell.button(Rect2(area.position+Vector2(0,index*28),Vector2(area.size.x,24)),boundary_text(int(row.effective_minute))+" · "+kind+" · "+str(row.name_zh),"living:record:"+str(row.record_id))
	if rows.is_empty(): shell.label(area.position+Vector2(0,20),"暂无消费记录。",12)
	if living_page>0 or rows.size()>count:
		shell.button(Rect2(area.position.x,area.end.y-25,78,23),"较新记录","living:previous",living_page>0)
		shell.button(Rect2(area.position.x+88,area.end.y-25,78,23),"较早记录","living:next",rows.size()>count)

func job_row(id: String) -> Dictionary:
	for row: Dictionary in _personal.get("known_jobs", []):
		if row["id"]==id: return row
	return {}

func job_reason(job: Dictionary) -> String:
	if job.is_empty(): return "尚未收到此岗位消息。"
	var employment := _personal.get("employment", {}) as Dictionary
	if employment.get("end_pending",false): return "离职待生效；现有合同仍占用岗位。"
	if not employment.is_empty(): return "已有劳动合同；先离职生效再申请。"
	if not job.get("qualified",false): return "本人技能不符合此岗位要求。"
	if not job.get("quote_current",true): return "岗位消息已过期或已更新。"
	if not job.get("recruiting",true): return "该岗位当前不接受申请。"
	if job.get("vacancies",-1)==0: return "本地已知空额为0，暂不能录用。"
	return "可提交申请；录用仍由正式规则裁决。"

func can_apply(job: Dictionary) -> bool:
	return not job.is_empty() and (_personal.get("employment",{}) as Dictionary).is_empty() and job.get("qualified",false) and job.get("quote_current",true) and job.get("recruiting",true) and job.get("vacancies",1)>0

func place_label(id: String) -> String:
	return str(_place_names.get(id,"地点名称未记录"))

func _draw_native(shell: MainShell, rect: Rect2) -> void:
	if business_mode or lease_mode or resident_services_mode or native_tab=="other":
		_draw_native_legacy(shell,rect)
		return
	var employment := _personal.get("employment",{}) as Dictionary
	var role := "获授权经营者／顾客" if not (_personal.get("managed_firms",[]) as Array).is_empty() and employment.is_empty() else "求职者／顾客" if employment.is_empty() else "离职待生效的雇员" if employment.get("end_pending",false) else "受雇者／顾客"
	shell.label(rect.position+Vector2(20,34),"就业与生活",21,Color(0.96,0.88,0.67))
	shell.label(rect.position+Vector2(20,59),cash_text(),14,Color(0.90,0.91,0.84),rect.size.x-42)
	shell.label(rect.position+Vector2(20,83),"所在地："+place_label(str(_personal.get("current_place_id","")))+" · "+role+" · 雇佣不授予企业经营权",13,Color(0.82,0.86,0.79),rect.size.x-42)
	var tabs := [{"id":"jobs","name":"比较岗位"},{"id":"wages","name":"合同与工资"},{"id":"orders","name":"个人订单"}]
	for i: int in tabs.size():
		shell.button(Rect2(rect.position.x+20+i*132,rect.position.y+96,124,29),tabs[i].name,"person:living_tab:"+tabs[i].id,true,native_tab==tabs[i].id,13)
	var body := Rect2(rect.position+Vector2(20,138),Vector2(rect.size.x-40,rect.size.y-183))
	if native_tab=="wages": _draw_wages(shell,body)
	elif native_tab=="orders": _draw_living_orders(shell,body)
	elif native_tab=="job_detail": _draw_job_detail(shell,body)
	else: _draw_job_comparison(shell,body)
	shell.button(Rect2(rect.position.x+20,rect.end.y-35,144,28),"物品与消费","person:goods",true,false,13)
	shell.button(Rect2(rect.position.x+174,rect.end.y-35,154,28),"已知商品报价","person:market",true,false,13)
	shell.button(Rect2(rect.end.x-160,rect.end.y-35,140,28),"其他安排与诊断","person:living_tab:other",true,false,12)

func _draw_job_comparison(shell: MainShell, area: Rect2) -> void:
	var jobs := _personal.get("known_jobs",[]) as Array
	if jobs.is_empty():
		shell.label(area.position+Vector2(12,26),"尚未收到可展示的工作机会。",14)
		return
	native_jobs_page=clampi(native_jobs_page,0,maxi(0,(jobs.size()-1)/2))
	var width := (area.size.x-14)/2
	for index: int in range(native_jobs_page*2,mini(jobs.size(),native_jobs_page*2+2)):
		var row := jobs[index] as Dictionary
		var card := Rect2(area.position+Vector2((index%2)*(width+14),0),Vector2(width,area.size.y-(30 if jobs.size()>2 else 0)))
		shell.panel(card,Color(0.025,0.039,0.033,0.98),Color(0.51,0.45,0.29,0.7))
		var x := card.position.x+12;var y := card.position.y+25
		shell.label(Vector2(x,y),EconomicText.firm(row["employer"]),16,Color(0.96,0.88,0.67),width-24)
		shell.label(Vector2(x,y+25),EconomicText.job(row["id"])+" · "+place_label(row["place"]),13,Color(0.86,0.89,0.81),width-24)
		shell.label(Vector2(x,y+51),"每期%d小时 × 时薪%d ＝ 应计%d" % [int(row["hours"]),int(row["wage_per_hour"]),int(row["hours"])*int(row["wage_per_hour"])],14,Color(0.94,0.84,0.61),width-24)
		shell.label(Vector2(x,y+73),EconomicText.currency(row["denomination"])+"；完成工作后形成工资",12,Color(0.82,0.86,0.79),width-24)
		shell.label(Vector2(x,y+97),"每日结算；完成后延迟%d日到期" % int(row["wage_delay"]),13,Color(0.86,0.89,0.81),width-24)
		var vacancy := "已知空额%d／容量%d" % [int(row["vacancies"]),int(row["positions"])] if row.has("vacancies") else "空额尚未获知；仅知岗位容量%d" % int(row["positions"])
		shell.label(Vector2(x,y+121),vacancy,13,Color(0.86,0.89,0.81),width-24)
		shell.label(Vector2(x,y+141),"本地观察："+boundary_text(int(row["vacancy_observed_minute"])) if row.has("vacancy_observed_minute") else "没有当前本地空额观察",12,Color(0.82,0.86,0.79),width-24)
		shell.label(Vector2(x,y+164),"技能要求%d · 本人%s" % [int(row["skill"]),"符合" if row.get("qualified",false) else "不符合"],13,Color(0.86,0.89,0.81),width-24)
		shell.wrapped(Vector2(x,y+185),job_reason(row),width-24,12,2)
		shell.button(Rect2(x,card.end.y-36,(width-34)/2,28),"查看详情","person:job_select:"+row["id"],true,selected_job_id==row["id"],13)
		shell.button(Rect2(x+(width-34)/2+10,card.end.y-36,(width-34)/2,28),"申请此岗位","person:job_request:"+row["id"],can_apply(row),false,13)
	if jobs.size()>2:
		shell.button(Rect2(area.position.x,area.end.y-26,110,26),"上一组岗位","person:native_jobs_previous",native_jobs_page>0)
		shell.button(Rect2(area.position.x+120,area.end.y-26,110,26),"下一组岗位","person:native_jobs_next",(native_jobs_page+1)*2<jobs.size())

func _draw_job_detail(shell: MainShell, area: Rect2) -> void:
	var job := job_row(selected_job_id)
	if job.is_empty():
		shell.label(area.position+Vector2(12,24),"所选岗位已不在本人已知列表，请重新选择。",14)
		return
	var lines: Array[String] = [EconomicText.firm(job["employer"])+" · "+EconomicText.job(job["id"]),"地点："+place_label(job["place"]),"完成每期%d小时后应计%d %s；不是立即到账承诺。" % [int(job["hours"]),int(job["hours"])*int(job["wage_per_hour"]),EconomicText.currency(job["denomination"])],"每日结算，工作完成后延迟%d日到期；实际到账取决于雇主履约。" % int(job["wage_delay"]),job_reason(job),"申请只签订劳动合同；还须本人登记实际工作。"]
	for i: int in lines.size(): shell.label(area.position+Vector2(12,26+i*27),lines[i],14,Color(0.86,0.89,0.81),area.size.x-24)
	if native_diagnostics: shell.label(area.position+Vector2(12,203),"岗位 "+selected_job_id+" · 雇主 "+str(job["employer"]),10,Color(0.82,0.86,0.79),area.size.x-24)
	shell.button(Rect2(area.position.x+12,area.end.y-36,160,29),"正式申请","person:job_request:"+selected_job_id,can_apply(job),false,13)
	shell.button(Rect2(area.position.x+185,area.end.y-36,140,29),"比较两个岗位","person:living_tab:jobs",true,false,13)
	shell.button(Rect2(area.end.x-158,area.end.y-36,146,29),"收起技术标识" if native_diagnostics else "技术标识（折叠）","person:job_diagnostics",true,false,12)

func _draw_wages(shell: MainShell, area: Rect2) -> void:
	var employment := _personal.get("employment",{}) as Dictionary
	var booking := _personal.get("work_booking",{}) as Dictionary
	var left := Rect2(area.position,Vector2(area.size.x*.47,105))
	var right := Rect2(left.end.x+16,area.position.y,area.end.x-left.end.x-16,105)
	if employment.is_empty():
		shell.label(left.position+Vector2(0,19),"当前没有劳动合同；已有工资责任继续保留。",13)
	else:
		shell.label(left.position+Vector2(0,19),EconomicText.firm(str(_personal.get("employer",{}).get("employer_id",""))),15,Color(0.96,0.88,0.67),left.size.x)
		shell.label(left.position+Vector2(0,42),"每期%d小时 · 时薪%d · 延迟%d日到期" % [int(employment.get("work_hours_limit",0)),int(employment.get("wage_per_hour",0)),int(employment.get("wage_delay",0))],13,Color(0.86,0.89,0.81),left.size.x)
		var ending: bool=employment.get("end_pending",false)
		var reason := "离职将在"+boundary_text(int(employment.get("end_boundary_minute",0)))+"生效；此前仍占岗" if ending else "已登记%d小时，尚未完成" % int(booking.get("hours",0)) if not booking.is_empty() else "可登记实际工作" if employment.get("can_work_now",false) else str(employment.get("work_unavailable_reason","当前不能登记；具体原因尚未获知。"))
		shell.wrapped(left.position+Vector2(0,65),reason,left.size.x,12,2)
		shell.button(Rect2(left.position.x,area.position.y+110,168,28),"已登记，等待日结" if not booking.is_empty() else "登记%d小时工作" % int(employment.get("work_hours_available",0)),"native:work",employment.get("can_work_now",false) and booking.is_empty(),false,13)
		shell.button(Rect2(left.position.x+180,area.position.y+110,130,28),"离职待生效" if ending else "申请离职","person:leave_request",not ending,false,13)
	var income: int=int(_personal.get("income_by_currency",{}).get(FormalLedgerState.DENOMINATION,0))
	var unpaid: int=int(_personal.get("matured_wages",{}).get(FormalLedgerState.DENOMINATION,0))
	var outstanding: int=int(_personal.get("wage_outstanding",0))
	shell.label(right.position+Vector2(0,19),"本记账单位 · 已完成工资%d" % (income+outstanding),14)
	shell.label(right.position+Vector2(0,43),"实际到账%d · 尚未到期%d · 到期未付%d" % [income,maxi(0,outstanding-unpaid),unpaid],13,Color(0.94,0.84,0.61),right.size.x)
	shell.label(right.position+Vector2(0,67),"已登记的工作尚未计入已完成工资。",12,Color(0.82,0.86,0.79),right.size.x)
	var food := _personal.get("need_today",{}).get("categories",{}).get("food",{}) as Dictionary
	shell.label(right.position+Vector2(0,92),"食物需要：尚未到结算边界" if food.is_empty() else "今日食物需要：满足%d／需要%d · 未满足%d" % [int(food.get("satisfied",0)),int(food.get("required",0)),int(food.get("unmet",0))],13,Color(0.86,0.89,0.81),right.size.x)
	var rows := _personal.get("wage_rows",[]) as Array
	var y := area.position.y+164
	var handovers: Array=_personal.get("workplace_handovers",[])
	if not handovers.is_empty():
		var handover: Dictionary=handovers[0]
		shell.label(Vector2(area.position.x,y),"本人参与的站点交接：%s%d → %s · 已交付" % [EconomicText.good(handover.good),int(handover.quantity),EconomicText.firm(handover.buyer)],12,Color(0.86,0.89,0.81),area.size.x)
		y+=22
	if rows.is_empty(): shell.label(Vector2(area.position.x,y),"本页尚无已完成工作形成的工资；登记不等于领薪。",13)
	for row: Dictionary in rows.slice(0,3):
		var status := str({"PAID":"已付清","NOT_DUE":"尚未到期","MATURED_UNPAID":"已到期未付"}[row["status"]])
		shell.label(Vector2(area.position.x,y),EconomicText.firm(row["employer_id"])+" · %d小时应计%d · 已付%d／余%d · %s" % [int(row["hours"]),int(row["amount"]),int(row["paid"]),int(row["remaining"]),status],13,Color(0.94,0.84,0.61),area.size.x)
		shell.label(Vector2(area.position.x,y+20),"实际工作结算 "+boundary_text(row["work_minute"])+" · 到期 "+boundary_text(row["due_minute"])+" · "+EconomicText.currency(row["denomination"]),12,Color(0.82,0.86,0.79),area.size.x)
		y+=44
	if native_wage_page>0 or rows.size()>3:
		shell.button(Rect2(area.end.x-230,area.end.y-26,106,25),"较新工资","person:wage_previous",native_wage_page>0)
		shell.button(Rect2(area.end.x-112,area.end.y-26,106,25),"较早工资","person:wage_next",rows.size()>3)

func _draw_living_orders(shell: MainShell, area: Rect2) -> void:
	var orders := _personal.get("orders",[]) as Array
	if orders.is_empty():
		shell.label(area.position+Vector2(12,28),"尚无个人订单。可先查看本人已知的商品报价。",15)
		shell.label(area.position+Vector2(12,58),"购买、取得和消费是不同阶段；下单不会提前满足需要。",13)
		return
	native_order_page=clampi(native_order_page,0,orders.size()-1)
	var order := orders[orders.size()-1-native_order_page] as Dictionary
	shell.label(area.position+Vector2(12,28),EconomicText.good(order["good"])+" · "+("已实际交付" if order["delivered"]==order["quantity"] else "尚未全部交付"),16,Color(0.96,0.88,0.67))
	shell.label(area.position+Vector2(12,58),"订单数量%d · 待发%d · 在途／待领%d · 已取得%d · 预留%d" % [int(order["quantity"]),int(order["pending"]),int(order["transit"]),int(order["delivered"]),int(order["reserved_amount"])],14)
	shell.label(area.position+Vector2(12,86),"锁定到货地点："+place_label(str(order["to_place_id"])),13)
	var y := area.position.y+105
	for cargo: Dictionary in order.get("shipments",[]):
		if cargo["stage"]!="AWAITING_RECIPIENT": continue
		shell.quantity_input(Rect2(area.position.x+12,y,138,28),quantity_milli,"person:collection",1)
		shell.button(Rect2(area.position.x+166,y,180,28),"本人现场领取","native:collect:"+str(cargo["id"]),order.get("can_collect",false) and quantity_milli<=int(cargo["quantity"]),false,13)
		y+=36
	shell.button(Rect2(area.position.x+12,area.end.y-35,130,28),"较新订单","person:native_order_previous",native_order_page>0)
	shell.button(Rect2(area.position.x+154,area.end.y-35,130,28),"较早订单","person:native_order_next",native_order_page+1<orders.size())
	shell.button(Rect2(area.end.x-194,area.end.y-35,180,28),"原运输与处置详情","person:living_tab:other",true,false,12)

func _draw_native_legacy(shell: MainShell, rect: Rect2) -> void:
	shell.button(Rect2(rect.end.x-250,rect.position.y+12,154,26),"返回就业与生活","person:living_tab:jobs")
	shell.heading(rect, "企业经营" if native_scope_expanded and business_mode else "岗位 / 个人订单", ("个人：" if native_scope_expanded and business_mode else "")+cash_text())
	if not _personal.get("opening_participation",{}).is_empty():
		shell.label(rect.position+Vector2(20,86),"本地已知岗位 · 自愿应聘 · 工资由实际雇主账户支付 · 本人无企业经营权",11,Color(0.82,0.86,0.79),rect.size.x-40)
	if native_scope_expanded and business_mode and business_capital_mode and not _business.is_empty():
		var area:=Rect2(rect.position+Vector2(20,104),Vector2(rect.size.x-40,rect.size.y-152))
		shell.card(area,"企业设备与资本交易 · "+str(_business["firm_id"]))
		shell.button(Rect2(area.end.x-174,area.position.y+8,160,25),"返回企业经营","capital_ui:toggle")
		_draw_business_capital(shell,area,area.position.y+52)
		return
	if native_scope_expanded and business_mode:
		# The purchase quote and its confirmation must fit the ordinary 720p page.
		# Keep the existing business controls together instead of squeezing them
		# below personal employment controls in a half-width card.
		var area:=Rect2(rect.position+Vector2(20,96),Vector2(rect.size.x-40,rect.size.y-116))
		shell.card(area,"当前获准企业 / 所选经营站点")
		_draw_business(shell,area,area.position.y+42)
		return
	var left := Rect2(rect.position.x+20, rect.position.y+104, rect.size.x*0.48-28, rect.size.y-152)
	var right := Rect2(left.end.x+16, left.position.y, rect.end.x-left.end.x-36, left.size.y)
	shell.card(left, "已知岗位 / 当前需要")
	var y := left.position.y+50
	var notices:=_personal.get("commercial_information",[]) as Array
	if not notices.is_empty():
		var last:=notices.back() as Dictionary
		shell.label(Vector2(left.position.x+14,y),"已收到：%s · %s · %s" % [str(last["item"]),str(last["place_id"]),"公告有效" if last["current_notice"] else "历史公告"],10,Color(0.82,0.86,0.79),left.size.x-28)
		y+=20
		shell.button(Rect2(left.position.x+12,y,left.size.x-24,24),"查看本人已知的当前商品报价","person:market")
		y+=30
	if not _personal.get("leases",{}).get("enabled",false): lease_mode=false
	if _personal.get("leases",{}).get("enabled",false):
		shell.button(Rect2(left.position.x+12,y,left.size.x-24,24),"返回个人经济" if lease_mode else "住房使用与租金责任","lease_ui:personal_toggle")
		y+=30
	if not _personal.get("resident_services",{}).get("enabled",false): resident_services_mode=false
	if _personal.get("resident_services",{}).get("enabled",false):
		shell.button(Rect2(left.position.x+12,y,left.size.x-24,24),"返回岗位与需要" if resident_services_mode else "现场餐饮与个人服务","resident_service_ui:toggle")
		y+=30
	if lease_mode:
		_draw_leases(shell,left,y,_personal.get("leases",{}),false)
	elif resident_services_mode:
		_draw_resident_services(shell,left,y)
	elif native_scope_expanded and business_mode:
		_draw_native_scope(shell,left,y)
	else:
		shell.label(Vector2(left.position.x+14,y), "诊断范围（非经营授权）："+str(_personal.get("management_scope_id", ""))+" · 所在地："+str(_personal.get("current_place_id", "")), 10, Color(0.82,0.86,0.79), left.size.x-28)
		y += 22
		shell.label(Vector2(left.position.x+14,y), "诊断常住统计："+str(_personal.get("resident_population_unit_id", ""))+" · 活动统计："+str(_personal.get("activity_population_unit_id", "")), 10, Color(0.82,0.86,0.79), left.size.x-28)
		y += 24
		var residence := _personal.get("residence", {}) as Dictionary
		for request: Dictionary in residence.get("pending", []):
			shell.label(Vector2(left.position.x+14,y), "迁居："+str(request["destination_unit_id"])+" · "+str(request["status"])+" · "+boundary_text(int(request["boundary_minute"])), 10, Color(0.82,0.86,0.79), left.size.x-28)
			y += 22
			if not str(request["reason"]).is_empty():
				shell.label(Vector2(left.position.x+14,y), str(request["reason"]), 10, Color(0.82,0.86,0.79), left.size.x-28)
				y += 22
		if residence.get("can_request", false):
			shell.button(Rect2(left.position.x+12,y,left.size.x-24,24), "申请常住迁居至 "+str(residence["target_unit_id"])+"（开发许可）", "native:residence")
			y += 28
		var trip := _personal.get("travel", {}) as Dictionary
		if trip.get("status", "") in ["TRAVELLING", "BLOCKED"]:
			shell.label(Vector2(left.position.x+14,y), "旅行："+str(trip["destination"])+" · "+str(trip["status"])+" · 下一阶段 "+str(trip["next_minute"])+" 分钟", 10, Color(0.82,0.86,0.79), left.size.x-28)
			y += 24
			var timing := "等待："+str(trip.get("reason", "")) if trip["status"] == "BLOCKED" else "剩余约 %d 分钟 · 最早到达 %s" % [int(trip.get("remaining_minutes", 0)),boundary_text(int(trip["earliest_arrival_minute"]))]
			shell.label(Vector2(left.position.x+14,y), timing, 10, Color(0.82,0.86,0.79), left.size.x-28)
			y += 24
			if trip.has("shared_capacity"):
				shell.label(Vector2(left.position.x+14,y), "共用线路：%s · %s · 用量 %s" % [trip["shared_capacity"]["link_id"],trip["shared_capacity"]["unit"],str(trip["shared_capacity"]["amount"])],10,Color(0.82,0.86,0.79),left.size.x-28)
				y+=20
		else:
			for offer: Dictionary in _personal.get("travel_destinations", []):
				if y+28 > left.end.y-120: break
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,24), "前往 %s · %d 分钟 · 票款 %d" % [offer["to_place_id"],int(offer["minutes"]),int(offer["fare"])], "native:travel:"+str(offer["to_place_id"]), (_personal.get("work_booking", {}) as Dictionary).is_empty())
				y += 28
		shell.button(Rect2(left.position.x+12,y,left.size.x-24,24), "岗位与需要" if native_scope_expanded else "更多技术资料", "person:native_scope")
		y += 44
		if native_scope_expanded:
			_draw_native_scope(shell, left, y)
		if not native_scope_expanded:
			var needs := (_personal.get("need_today", {}) as Dictionary).get("categories", {}) as Dictionary
			if needs.is_empty():
				shell.label(Vector2(left.position.x+14,y), "当前需要尚未到日结边界。", 11)
				y += 24
			for category: String in needs:
				var need := needs[category] as Dictionary
				shell.label(Vector2(left.position.x+14,y), "%s：已满足 %d / %d；缺量 %d" % [category,int(need.get("satisfied",0)),int(need.get("required",0)),int(need.get("unmet",0))], 11, Color(0.82,0.86,0.79), left.size.x-28)
				y += 24
			var employment := _personal.get("employment", {}) as Dictionary
			var booking := _personal.get("work_booking", {}) as Dictionary
			if not employment.is_empty():
				shell.label(Vector2(left.position.x+14,y),"已接受时薪 %d · 每期%d小时 · 日结后延迟%d日" % [int(employment.get("wage_per_hour",0)),int(employment.get("work_hours_limit",0)),int(employment.get("wage_delay",0))],10,Color(0.82,0.86,0.79),left.size.x-28)
				y+=20
				shell.label(Vector2(left.position.x+14,y), "工作地点："+str(employment.get("work_place_id", ""))+" · "+str(employment.get("site_id", "")), 10, Color(0.82,0.86,0.79), left.size.x-28)
				y += 20
				var totals:=_personal.get("totals",{}) as Dictionary
				shell.label(Vector2(left.position.x+14,y), "实际工作 %s小时 · 已付收入 %s · 未付 %s"%[str(totals.get("work_hours",0)),str(totals.get("income",0)),str(_personal.get("wage_outstanding",0))], 10, Color(0.82,0.86,0.79), left.size.x-28)
				y += 12
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,26), "已登记本期工作" if not booking.is_empty() else "登记工作 %d 小时" % int(employment.get("work_hours_available", employment.get("work_hours_limit",0))), "native:work", booking.is_empty() and bool(employment.get("can_work_now",false)))
				y += 30
				var ending := bool(employment.get("end_pending",false))
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,24), "离职待生效：%s分钟" % str(employment.get("end_boundary_minute",0)) if ending else "申请结束未来劳动合同", "native:leave_job", not ending)
				y += 32
			for index: int in range((_personal.get("labor_market",{}).get("actions",[]) as Array).size()):
				var row:=_personal["labor_market"]["actions"][index] as Dictionary
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,24),row["label"],"native:labor_action:"+str(index),row["can_execute"])
				y+=28
			var jobs: Array = _personal.get("known_jobs", [])
			var job_page_size := maxi(1, int((left.end.y-y-42)/57))
			native_jobs_page = clampi(native_jobs_page, 0, maxi(0, (jobs.size()-1)/job_page_size))
			for index: int in range(native_jobs_page*job_page_size, mini(jobs.size(), (native_jobs_page+1)*job_page_size)):
				var job := jobs[index] as Dictionary
				if y+53 > left.end.y-36: break
				shell.label(Vector2(left.position.x+14,y), str(job["employer"])+" · "+str(job["place"]), 10, Color(0.82,0.86,0.79), left.size.x-28)
				y += 14
				shell.label(Vector2(left.position.x+14,y), "每期%d小时 · 日结后延迟%d日 · 技能%d：%s" % [int(job["hours"]),int(job["wage_delay"]),int(job["skill"]),"符合" if job.get("qualified",false) else "不符"],10,Color(0.82,0.86,0.79),left.size.x-28)
				y += 6
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,25), "申请 · 时薪%d · 空额%d · %s" % [int(job["wage_per_hour"]),int(job.get("vacancies",job["positions"])),"面包生产与销售" if str(job["id"]).begins_with("job:opening_paris_") else str(job["id"])], "native:apply:"+str(job["id"])+"|"+str(job.get("job_quote_id","")), employment.is_empty() and int(job.get("vacancies",job["positions"]))>0 and bool(job.get("quote_current",true)) and bool(job.get("recruiting",true)) and bool(job.get("qualified",false)))
				y += 37
			shell.button(Rect2(left.position.x+12,left.end.y-30,90,24), "岗位上一页", "person:native_jobs_previous", native_jobs_page>0)
			shell.button(Rect2(left.position.x+110,left.end.y-30,90,24), "岗位下一页", "person:native_jobs_next", (native_jobs_page+1)*job_page_size<jobs.size())
	shell.card(right, "个人订单 / 在途")
	var orders := _personal.get("orders", []) as Array
	var collection: bool = orders.any(func(order: Dictionary)->bool:return bool(order.get("can_collect",false)) or bool(order.get("can_collect_to_storage",false)) or not (order.get("cargo_fulfilment",{}).get("losses",[]) as Array).is_empty())
	if collection:
		shell.quantity_input(Rect2(right.position+Vector2(12,40),Vector2(144,26)),quantity_milli,"person:collection",1)
		shell.label(right.position+Vector2(164,56),"本次领取／处置数量",12)
	y = right.position.y+(86 if collection else 55)
	native_order_page = clampi(native_order_page, 0, maxi(0, orders.size()-1))
	for index: int in range(orders.size()-1-native_order_page, maxi(-1, orders.size()-2-native_order_page), -1):
		if y+88 > right.end.y-36: break
		var order := orders[index] as Dictionary
		shell.label(Vector2(right.position.x+14,y), str(order["id"])+" · "+str(order["good"])+" · "+str({"AWAITING_RECIPIENT":"待本人到锁定地点领取"}.get(order["stage"],order["stage"])), 11, Color(0.82,0.86,0.79), right.size.x-28)
		y += 20
		shell.label(Vector2(right.position.x+14,y), "待发 %d · 在途/待领 %d · 已领 %d · 预留 %d" % [int(order["pending"]),int(order["transit"]),int(order["delivered"]),int(order["reserved_amount"])], 10, Color(0.82,0.86,0.79), right.size.x-28)
		y += 18
		shell.label(Vector2(right.position.x+14,y), "锁定到货地点："+str(order["to_place_id"]), 10, Color(0.82,0.86,0.79), right.size.x-28)
		y += 10
		if int(order["pending"]) > 0:
			shell.button(Rect2(right.position.x+12,y,130,23), "取消未发运数量", "native:cancel:"+str(order["id"]), order.get("unresolved_loss_quantity") == 0)
		for cargo: Dictionary in order.get("shipments", []):
			if cargo["stage"] in ["WAITING_UNLOAD","UNLOADING"] and y+22 < right.end.y-36:
				shell.label(Vector2(right.position.x+14,y), str(cargo["stage"])+" · "+str(cargo.get("waiting_reason","")),10,Color(0.82,0.86,0.79),right.size.x-28)
				y+=20
			if cargo["stage"] != "AWAITING_RECIPIENT" or y+26 > right.end.y-36: continue
			var width := (right.size.x-32)/2
			shell.button(Rect2(right.position.x+12,y,width,23), "领取 %d / 余 %d" % [quantity_milli,int(cargo["quantity"])], "native:collect:"+str(cargo["id"]), bool(order.get("can_collect",false)) and quantity_milli<=int(cargo["quantity"]))
			shell.button(Rect2(right.position.x+20+width,y,width,23), "领取并寄存", "native:collect_store:"+str(cargo["id"]), bool(order.get("can_collect_to_storage",false)) and quantity_milli<=int(cargo["quantity"]))
			y += 26
		var fulfilment := order.get("cargo_fulfilment", {}) as Dictionary
		for loss: Dictionary in fulfilment.get("losses", []):
			if loss["order_id"] != order["id"] or y+46 > right.end.y-36: continue
			shell.label(Vector2(right.position.x+14,y), "货损 %d · %s · 未处置 %d" % [int(loss["quantity"]),loss["status"],int(loss["quantity"])-int(loss["resolved"])], 10)
			y += 18
			if loss["status"] == "OBSERVED": shell.button(Rect2(right.position.x+12,y,200,23), "确认本人有权确认的保管事实", "native:loss_confirm:"+str(loss["id"]), bool(loss.get("can_confirm",false)))
			elif int(loss["resolved"]) < int(loss["quantity"]):
				var allowed: bool = bool(loss.get("can_propose_release",loss.get("can_propose",false))) and quantity_milli<=int(loss["quantity"])-int(loss["resolved"])
				shell.button(Rect2(right.position.x+12,y,110,23), "提议解除 %d" % quantity_milli, "native:loss_release:"+str(loss["id"]), allowed)
				shell.button(Rect2(right.position.x+130,y,right.size.x-142,23), "提议补运（新增运费0）", "native:loss_replace:"+str(loss["id"]), bool(loss.get("can_propose_replace",loss.get("can_propose",false))) and quantity_milli<=int(loss["quantity"])-int(loss["resolved"]))
			y += 26
		for d: Dictionary in fulfilment.get("dispositions", []):
			if d.get("order_id") != order["id"] or y+64 > right.end.y-36: continue
			shell.label(Vector2(right.position.x+14,y), "处置 %s · 数量 %d · %s%s" % [d["terms"]["mode"],int(d["terms"]["quantity"]),d["status"]," · 组织专项授权" if d.get("scoped_authority_required",false) else ""], 10)
			y += 18
			var terms_visible := true
			if d["terms"]["mode"] == "REPLACE":
				var fees := d["terms"].get("fees", []) as Array
				shell.label(Vector2(right.position.x+14,y), "新增运费条款：%d 笔；仍需各承运方同意" % fees.size(), 10)
				y += 18
				for fee: Dictionary in fees:
					if y+44 > right.end.y-36: terms_visible = false; break
					shell.label(Vector2(right.position.x+14,y), "%s → %s · %d %s" % [fee["payer"],fee["recipient"],int(fee["amount"]),fee["denomination"]], 10, Color(0.82,0.86,0.79), right.size.x-28)
					y += 18
			var payment := d["terms"].get("payment", {}) as Dictionary
			if not payment.is_empty():
				shell.label(Vector2(right.position.x+14,y), "%s → %s · %d %s" % [payment["payer"],payment["recipient"],int(payment["amount"]),payment["denomination"]], 10, Color(0.82,0.86,0.79), right.size.x-28)
				y += 18
			if d["status"] != "EXECUTED":
				shell.button(Rect2(right.position.x+12,y,100,23), "确认条款", "native:disposition_confirm:"+str(d["id"]), bool(d.get("can_consent",false)) and terms_visible)
				shell.button(Rect2(right.position.x+120,y,100,23), "执行已同意处置", "native:disposition_execute:"+str(d["id"]), d["confirmed"].size()==d["parties"].size())
			y += 26
		y += 40
	if orders.is_empty(): shell.label(Vector2(right.position.x+14,y), "尚无个人订单。", 11)
	shell.button(Rect2(right.position.x+12,right.end.y-30,90,24), "较新订单", "person:native_order_previous", native_order_page>0)
	shell.button(Rect2(right.position.x+110,right.end.y-30,90,24), "较早订单", "person:native_order_next", native_order_page+1<orders.size())
	shell.button(Rect2(rect.end.x-170,rect.end.y-36,148,26), "已知商品报价", "person:market")

func _draw_native_scope(shell: MainShell, rect: Rect2, start_y: float) -> void:
	var y := start_y
	shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "返回经营责任" if business_mode else "生产与企业采购", "person:business")
	y+=28
	if business_mode:
		_draw_business(shell,rect,y)
		return
	shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "返回经营责任" if capital_mode else "投资与设备", "person:capital")
	y += 28
	if capital_mode:
		_draw_capital(shell, rect, y)
		return
	var state := _personal.get("native_lifecycle", {}) as Dictionary
	shell.label(Vector2(rect.position.x+14,y), "未来责任："+str(state.get("future_authority", "")), 10, Color(0.82,0.86,0.79), rect.size.x-28)
	y += 22
	if state.has("last_entry_minute"):
		shell.label(Vector2(rect.position.x+14,y), "最近进入："+boundary_text(int(state["last_entry_minute"])), 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 22
	if _personal.get("can_reenter", false):
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "申请重新接入（不重发资源）", "native:reenter")
		y += 28
	for proposal: Dictionary in _personal.get("management_incoming", []):
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "接受管理："+str(proposal["firm"]), "native:management_accept:"+str(proposal["id"]))
		y += 28
	shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "申请本人退出原生接管", "native:exit:"+str(_person.get("person_id", "")), _personal.get("native", false))
	y += 28
	for option: Dictionary in _personal.get("scope_options", []):
		if y+28 > rect.end.y-100: break
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), str(option["label"]), "native:expand:"+str(option["id"]))
		y += 28
	for firm: Dictionary in _personal.get("managed_firms", []):
		if y+60 > rect.end.y-70: break
		shell.label(Vector2(rect.position.x+14,y), str(firm["firm_id"])+(" · 经营中" if firm["operating"] else " · 已暂停"), 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 10
		shell.button(Rect2(rect.position.x+12,y,110,24), "暂停经营" if firm["operating"] else "恢复经营", ("native:pause:" if firm["operating"] else "native:resume:")+str(firm["firm_id"]))
		shell.button(Rect2(rect.position.x+132,y,110,24), "申请退出接管", "native:exit:"+str(firm["firm_id"]))
		y += 32
		var cargo := _personal.get("cargo_fulfilment", {}) as Dictionary
		for loss: Dictionary in cargo.get("losses", []):
			if loss["owner"] != firm["firm_id"] or int(loss["quantity"]) == int(loss["resolved"]) or y+50 > rect.end.y-70: continue
			shell.label(Vector2(rect.position.x+14,y), "货损 %s · %s · 缺口 %d" % [loss["order_id"],loss["status"],int(loss["quantity"])-int(loss["resolved"])], 10, Color(0.82,0.86,0.79), rect.size.x-28)
			y += 18
			if loss["status"] == "OBSERVED": shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "确认有权采用的保管事实", "native:loss_confirm:"+str(loss["id"]), bool(loss.get("can_confirm",false)))
			else:
				var allowed: bool = bool(loss.get("can_propose_release",loss.get("can_propose",false))) and quantity_milli<=int(loss["quantity"])-int(loss["resolved"])
				shell.button(Rect2(rect.position.x+12,y,110,24), "提议解除 %d" % quantity_milli, "native:loss_release:"+str(loss["id"]), allowed)
				shell.button(Rect2(rect.position.x+132,y,rect.size.x-144,24), "提议补运（新增运费0）", "native:loss_replace:"+str(loss["id"]), bool(loss.get("can_propose_replace",loss.get("can_propose",false))) and quantity_milli<=int(loss["quantity"])-int(loss["resolved"]))
			y += 28
			break
		for d: Dictionary in cargo.get("dispositions", []):
			if firm["firm_id"] not in d["parties"] or d["status"] == "EXECUTED" or y+50 > rect.end.y-70: continue
			shell.label(Vector2(rect.position.x+14,y), "处置 %s · 数量 %d · %s%s" % [d["terms"]["mode"],int(d["terms"]["quantity"]),d["status"]," · 组织专项授权" if d.get("scoped_authority_required",false) else ""], 10, Color(0.82,0.86,0.79), rect.size.x-28)
			y += 18
			var terms_visible := true
			for fee: Dictionary in d["terms"].get("fees",[]):
				if y+46 > rect.end.y-70: terms_visible=false; break
				shell.label(Vector2(rect.position.x+14,y), "新增运费：%s → %s · %d %s" % [fee["payer"],fee["recipient"],int(fee["amount"]),fee["denomination"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
				y+=18
			var payment := d["terms"].get("payment",{}) as Dictionary
			if not payment.is_empty():
				if y+46 > rect.end.y-70: terms_visible=false
				else:
					shell.label(Vector2(rect.position.x+14,y), "%s：%s → %s · %d %s" % [d["terms"]["mode"],payment["payer"],payment["recipient"],int(payment["amount"]),payment["denomination"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
					y+=18
			if d["terms"]["mode"] == "REPLACE" and d["terms"].get("fees", []).is_empty():
				shell.label(Vector2(rect.position.x+14,y), "条款：新增运费0；原锁定付款责任保留", 10)
				y += 18
			shell.button(Rect2(rect.position.x+12,y,110,24), "确认条款", "native:disposition_confirm:"+str(d["id"]), bool(d.get("can_consent",false)) and terms_visible)
			shell.button(Rect2(rect.position.x+132,y,110,24), "执行已同意处置", "native:disposition_execute:"+str(d["id"]), d["confirmed"].size()==d["parties"].size())
			y += 28
			break
		var lifecycle := firm.get("lifecycle", {}) as Dictionary
		if y+28 < rect.end.y-70:
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "停止生产采购，出售现有库存", "native:wind_down:"+str(firm["firm_id"]), (lifecycle.get("wind_down",{}).get("actions",[{}])[0].get("can_execute",false) if lifecycle.get("wind_down",{}).get("enabled",false) else lifecycle.get("status") != "FINISHED_NATIVE_IDENTITY_RETAINED"))
			y += 28
		shell.label(Vector2(rect.position.x+14,y), "管理者："+str(lifecycle.get("manager", ""))+" · "+str(lifecycle.get("status", "")), 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 12
		for successor: String in lifecycle.get("successors", []):
			if y+28 > rect.end.y-70: break
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "转交经营权："+successor, "native:management:"+str(firm["firm_id"])+"|"+successor)
			y += 28
		for site: Dictionary in lifecycle.get("sites", []):
			if y+60 > rect.end.y-70: break
			shell.label(Vector2(rect.position.x+14,y), str(site["id"])+" · "+str(site["status"]), 10, Color(0.82,0.86,0.79), rect.size.x-28)
			y += 12
			var suffix := str(firm["firm_id"])+"|"+str(site["id"])
			shell.button(Rect2(rect.position.x+12,y,110,24), "暂停" if site["status"] == "OPERATING" else "恢复", ("native:site_pause:" if site["status"] == "OPERATING" else "native:site_resume:")+suffix, site["status"] != "CLOSED")
			shell.button(Rect2(rect.position.x+132,y,110,24), "申请关闭", "native:site_close:"+suffix, site["status"] != "CLOSED")
			y += 28
			shell.label(Vector2(rect.position.x+14,y), str(site.get("close_reason", "")), 10, Color(0.82,0.86,0.79), rect.size.x-28)
			y += 20
		if lifecycle.get("status") in ["WINDING_DOWN", "PAUSED"] and y+28 < rect.end.y-70:
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "申请结束经营（保留身份与资产）", "native:finish:"+str(firm["firm_id"]))
			y += 28
	for handover: Dictionary in _personal.get("handover", []):
		if y+42 > rect.end.y-20: break
		shell.label(Vector2(rect.position.x+14,y), "本人责任："+str(handover["status"])+" · "+str(handover["future_consumption_receiver"]), 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 22
	var requests: Array = _personal.get("scope_changes", [])
	for index: int in range(requests.size()-1,-1,-1):
		if y+40 > rect.end.y-20: break
		var request := requests[index] as Dictionary
		shell.label(Vector2(rect.position.x+14,y), "接管："+str(request["status"])+" · "+str(request["reason"]), 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 20
		shell.label(Vector2(rect.position.x+14,y), "生效："+boundary_text(int(request["effective_minute"])) if int(request["effective_minute"])>=0 else "下一边界："+boundary_text(int(request["boundary_minute"])), 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 22
		if request["kind"] == "EXIT" and request["status"] == "DEFERRED" and y+28 < rect.end.y-20:
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "责任处理后重新申请退出", "native:retry_exit:"+str(request["id"]))
			y += 28

func _draw_native_custody(shell: MainShell, rect: Rect2, owned: Dictionary) -> void:
	shell.label(rect.position+Vector2(14,52), "所有 %d · 当前可用 %d · 已消费 %d" % [int(owned.get("owned_quantity",0)),int(owned.get("quantity",0)),int(owned.get("consumed",0))],11,Color(0.82,0.86,0.79),rect.size.x-28)
	shell.quantity_input(Rect2(rect.position+Vector2(14,66),Vector2(144,26)),quantity_milli,"person:"+selected_commodity_id,1)
	var quote := _property.get("quote",{}) as Dictionary
	shell.button(Rect2(rect.position.x+168,rect.position.y+66,104,26),"实际消费","consume",bool(quote.get("success",false)))
	var custody := _property.get("custody_quote",{}) as Dictionary
	var width := (rect.size.x-32)/2
	shell.button(Rect2(rect.position.x+12,rect.position.y+100,width,24),"寄存所填数量","native:store",bool(custody.get("can_store",false)))
	shell.button(Rect2(rect.position.x+20+width,rect.position.y+100,width,24),"取为随身物品","native:withdraw",bool(custody.get("can_withdraw",false)))
	var y := rect.position.y+146
	for row: Dictionary in owned.get("custody",[]):
		if y+20 > rect.end.y-112: break
		var location := str(row.get("place_id",""))
		if row["state"] == "FREIGHT": location = str(row.get("origin_place_id",""))+" → "+str(row.get("destination_place_id",""))+" · "+str(row.get("stage",""))
		shell.label(Vector2(rect.position.x+14,y), "%s · %d · %s" % [str({"CARRIED":"随身","STORED":"寄存","FREIGHT":"货运占用"}.get(row["state"],row["state"])),int(row["quantity"]),location],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y += 22
	var offers := custody.get("freight_options",[]) as Array
	for index: int in range(mini(2,offers.size())):
		if y+28 > rect.end.y-70: break
		var offer := offers[index] as Dictionary
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "寄运到 %s · 单位运费 %d %s" % [offer["to_place_id"],int(offer["freight_per_unit"]),offer["denomination"]],"native:freight:"+str(index),quantity_milli<=int(offer["quantity_limit"]))
		y += 28
	var plan := _property.get("arrangement",{}) as Dictionary
	if bool(_property.get("capability",{}).get("daily_supported",false)):
		shell.button(Rect2(rect.position.x+12,rect.end.y-60,rect.size.x-24,24),"停止每日安排" if not plan.is_empty() else "每日使用所填数量","consumption:daily")
		if not plan.is_empty(): shell.button(Rect2(rect.position.x+12,rect.end.y-30,rect.size.x-24,24),"停止缺量采购" if plan.get("auto_buy_missing",false) else "允许缺量采购","consumption:autobuy")


func _draw_capital(shell: MainShell, rect: Rect2, y: float) -> void:
	var rows: Array[Dictionary] = []
	for firm: Dictionary in _personal.get("managed_firms", []):
		var capital := firm.get("lifecycle", {}).get("capital", {}) as Dictionary
		for kind: String in ["options", "projects", "assets"]:
			for row: Dictionary in capital.get(kind, []): rows.append({"kind": kind, "firm": firm["firm_id"], "row": row, "sites": firm.get("lifecycle", {}).get("sites", []), "accounts": capital.get("accounts", []), "credit_offers": capital.get("credit_offers", [])})
	if rows.is_empty():
		shell.label(Vector2(rect.position.x+14,y), "没有本人可管理的投资项目或开发建设许可。", 11, Color(0.82,0.86,0.79), rect.size.x-28)
		return
	capital_page = clampi(capital_page, 0, rows.size()-1)
	var entry := rows[capital_page] as Dictionary
	var row := entry["row"] as Dictionary
	var lines: Array[String] = [str(entry["firm"]), str(row.get("id", ""))+" · "+str(row.get("status", row.get("kind", ""))), "地点："+str(row["site_id"])]
	for account: Dictionary in entry["accounts"]: lines.append("可用资金："+str(account.get("available", account.get("balance", 0)))+" · "+str(account["denomination"]))
	for site: Dictionary in entry["sites"]:
		if site["id"] == row["site_id"]: lines.append("现时产能："+str(site["effective_capacity"])+" · 基础 "+str(site["base_capacity"]))
	if entry["kind"] == "options":
		if row.has("building"):
			lines.append("新增可租空间："+str(row["capacity"])+" "+str(row["building"]["object"]["unit"]))
			lines.append("建设依据："+str(row["building"]["permit"]["id"])+" · "+str(row.get("construction_reason","")))
			lines.append("已知建造估算："+str(row.get("known_estimate",{})))
		else:lines.append("新增产能："+str(row["capacity"])+" · 兼容 "+str(row["activities"]))
		lines.append("所需资本品："+str(row["materials"]))
		lines.append("施工："+str(row["hours"])+" 工时 · 最少 "+str(row["duration_minutes"])+" 分钟")
		lines.append("预算上限："+str(row["budget"])+" · 保留资金 "+str(row["cash_floor"]))
	elif entry["kind"] == "projects":
		lines.append("已投入："+str(row["materials"])+" · 尚缺 "+str(row["missing"]))
		lines.append("施工工时："+str(row["labor_hours"])+" / "+str(row["terms"]["hours"]))
		lines.append("已承诺成本："+str(row["committed_cost"])+" / "+str(row["budget"]))
		lines.append("原订单："+str(row["orders"]))
		lines.append("施工工资责任："+str(row["wage_liability"])+" · "+str(row["reason"]))
	else:
		if row.has("rental_use"):
			var use:=row["rental_use"] as Dictionary
			lines.append("建筑空间："+str(use["capacity"])+" "+str(use["unit"])+" · 当前可租 "+str(use["available"]))
			lines.append("履约租金："+str(use["fulfilled_rent"])+" · 已收 "+str(use["received_cash"])+" · 欠收 "+str(use["rent_receivable"]))
			lines.append("建设投入："+str(use.get("construction_cost",{}))+" · 未计折旧")
		else:
			lines.append("设备能力："+str(row["capacity"])+" · "+str(row.get("current_use",{}).get("activities",row["activities"])))
			var use:=row.get("current_use",{}) as Dictionary
			lines.append("当前产权："+str(use.get("owner",row["firm"]))+" · 保管 "+str(use.get("custodian",row["firm"]))+" · 载具 "+str(use.get("vehicle_id","")))
			lines.append("所在地："+str(use.get("site_id",row["site_id"]))+" · 安装 "+str(use.get("installed_site","")))
			lines.append("维修配方："+str(row.get("maintenance_recipe",""))+" · 适用 "+str(row.get("internal_maintenance_ready",false)))
			for task: Dictionary in row.get("mobility",{}).get("transport",[]):
				lines.append("设备运输："+str(task["stage"])+" · 段 "+str(task["leg_index"])+" · 已付 "+str(task["paid"])+" / "+str(task["total_fee"]))
				lines.append(str(task["id"])+" · "+str(task["reason"]))
				lines.append("路线："+str(task["contract"]["legs"])+" · 节点 "+str(task["nodes"]))
			lines.append("拆装记录 "+str(row.get("mobility",{}).get("work",[]).size())+" · 交易 "+str(row.get("mobility",{}).get("transactions",[]).size()))
		lines.append("投入使用："+boundary_text(int(row["in_service_minute"])))
		lines.append("形成项目："+str(row["project_id"]))
	for line: String in lines:
		if y+18 > rect.end.y-92: break
		shell.label(Vector2(rect.position.x+14,y), line, 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 19
	if entry["kind"] == "projects" and row["status"] not in ["COMPLETED", "CANCELLED"] and row["kind"] not in ["DISMANTLE","HANDOVER","REINSTALL"]:
		for offer: Dictionary in entry["credit_offers"]:
			var amount := mini(int(offer["available_quantity"]), int(row["budget_remaining"]))
			if amount <= 0 or offer["denomination"] != row["terms"]["denomination"] or y+28 > rect.end.y-92: continue
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "企业借款 "+str(amount)+" · 利息 "+str(offer["interest"]), "native:investment_credit:"+str(row["id"])+"|"+str(offer["id"])+"|"+str(amount))
			break
	var action_y := rect.end.y-86
	if entry["kind"] == "options":
		shell.button(Rect2(rect.position.x+12,action_y,rect.size.x-24,24), "按许可预算提出投资", "native:invest:"+str(row["id"]), row["site_ready"])
	elif entry["kind"] == "projects" and row["status"] not in ["COMPLETED", "CANCELLED"] and row["kind"] not in ["DISMANTLE","HANDOVER","REINSTALL"]:
		shell.button(Rect2(rect.position.x+12,action_y,108,24), "恢复" if row["status"] == "PAUSED" else "暂停", "native:project:"+str(row["id"])+"|"+("ACTIVE" if row["status"] == "PAUSED" else "PAUSED"))
		shell.button(Rect2(rect.position.x+128,action_y,108,24), "取消施工", "native:project:"+str(row["id"])+"|CANCELLED")
	elif entry["kind"] == "assets" and row["status"] in ["ACTIVE", "PAUSED"]:
		shell.button(Rect2(rect.position.x+12,action_y,88,24), "停用" if row["status"] == "ACTIVE" else "启用", "native:equipment:"+str(row["id"])+"|"+("PAUSED" if row["status"] == "ACTIVE" else "ACTIVE"))
		shell.button(Rect2(rect.position.x+108,action_y,88,24), "维修", "native:maintain:"+str(row["id"]),row.get("internal_maintenance_ready",true))
		shell.button(Rect2(rect.position.x+204,action_y,88,24), "退役保管", "native:equipment:"+str(row["id"])+"|RETIRED")
	shell.button(Rect2(rect.position.x+12,rect.end.y-52,88,24), "上一项", "person:capital_previous", capital_page > 0)
	shell.button(Rect2(rect.position.x+108,rect.end.y-52,88,24), "下一项", "person:capital_next", capital_page+1 < rows.size())
	shell.label(Vector2(rect.position.x+206,rect.end.y-36), str(capital_page+1)+" / "+str(rows.size()), 10)

func refresh_business(view: Dictionary) -> void:
	_business=view

func business_request(index: int) -> Dictionary:
	var offers := _business.get("offers",[]) as Array
	if index<0 or index>=offers.size():return {}
	var request:=offers[index].get("request",{}) as Dictionary
	# A changed input must be quoted again before the player confirms it.
	return request.duplicate(true) if int(request.get("quantity",-1))==quantity_milli else {}

func business_finance_request() -> Dictionary:
	var rows := _business.get("financial_actions",[]) as Array
	return (rows[business_finance_page]["request"] as Dictionary).duplicate(true) if business_finance_page>=0 and business_finance_page<rows.size() else {}

func _business_service_actions() -> Array:
	var rows: Array=(_business.get("services",{}).get("actions",[]) as Array).duplicate(true)
	rows.append_array(_business.get("commercial_information",{}).get("actions",[]))
	rows.append_array(_business.get("labor_market",{}).get("actions",[]))
	rows.append_array(_business.get("wind_down",{}).get("actions",[]))
	rows.append_array(_business.get("capital_resale",{}).get("actions",[]))
	return rows

func labor_request(index: int) -> Dictionary:
	var rows:=_personal.get("labor_market",{}).get("actions",[]) as Array
	return rows[index].duplicate(true) if index>=0 and index<rows.size() else {}

func business_service_request(index: int) -> Dictionary:
	var rows:=_business_service_actions()
	return rows[index].duplicate(true) if index>=0 and index<rows.size() else {}

func capital_request(key: String) -> Dictionary:
	for action: Dictionary in _business.get("capital_resale",{}).get("actions",[]):
		if action.get("key")==key: return action.duplicate(true)
	return {}

static func capital_reason(reason: String) -> String:
	return str({"ORIGINAL_CAPITAL_ACCEPTANCE_CHECK_READY":"可提交；资金与权限在执行时复核", "CAPITAL_QUOTATION_NOT_YET_RECEIVED":"报价尚未实际送达", "ASSET_EXCLUSIVE_TRADE_ALREADY_ACCEPTED":"设备已被其他合同锁定", "CAPITAL_QUOTATION_ALREADY_ACCEPTED":"此报价已经接受", "CAPITAL_OFFER_STALE_OR_BUYER_CLOSED":"报价失效、设备不可售或接收场地不可用", "SEPARATE_ASSET_PURCHASE_AND_PAYMENT_AUTHORITY_REQUIRED":"缺少独立设备购置或付款授权", "SEPARATE_CAPITAL_FREIGHT_AUTHORITY_AND_BUDGET_REQUIRED":"缺少独立运费授权或预算", "PURCHASE_AND_FREIGHT_CASH_UNAVAILABLE":"可用现金不足以承担货款与运费", "CAPITAL_PURCHASE_CASH_OR_HISTORY_LIMIT":"货款可用现金不足或历史容量已满", "CURRENT_CAPITAL_OWNER_DISPOSAL_AUTHORITY_REQUIRED":"当前人物无设备所有企业的处分资格", "NO_SEPARATE_CAPITAL_DISASSEMBLE_AUTHORITY":"缺少设备拆卸授权", "WAITING_ACTUAL_LOADING_LABOR_OR_FINAL_ADOPTION":"等待真实装载工时与最终运力采用", "EXECUTION_RECHECK_REQUIRED":"执行时复核权限、资金、材料和资源", "AVAILABLE":"仍可接受", "QUOTATION_EXPIRED":"报价已过期", "QUOTATION_WITHDRAWN":"报价已撤回", "ASSET_NO_LONGER_OWNED_BY_QUOTING_SELLER":"卖方已不拥有该设备", "CUMULATIVE_BUDGET_EXCEEDED":"累计采购预算不足", "KNOWN_CAPITAL_ACTION_NO_LONGER_AVAILABLE":"此报价或操作已经失效，请刷新", "ACTUAL_FREIGHT_CASH_REQUIRED":"当前可用运费资金不足", "WAITING_SELLER_DISPATCH_AUTHORITY":"等待卖方明确授权发运", "WAITING_ACTUAL_LOADING_WINDOW":"等待真实装载窗口", "ACTUAL_TRANSIT":"设备实际在途", "WAITING_ACTUAL_DESTINATION_UNLOADING":"等待目的地实际卸货", "ORIGINAL_FREIGHT_COMMISSION_CHECK_READY":"可委托；执行时复核运费资金和权限", "NO_KNOWN_LEGAL_CARRIAGE_WITH_COMPARABLE_COST_AND_HANDLING":"尚无费用和装卸条件明确的合法承运路线"}.get(reason,reason))

static func capital_amount(value: Variant) -> String:
	return "未知" if value==null else str(value)

func _draw_business_capital(shell: MainShell, rect: Rect2, y: float) -> void:
	var capital:=_business.get("capital_resale",{}) as Dictionary
	var entries: Array[Dictionary]=[]
	for kind: String in ["offers","equipment","trades","work"]:
		for row: Dictionary in capital.get(kind,[]): entries.append({"kind":kind,"row":row})
	shell.label(Vector2(rect.position.x+14,y),"本企业基础 / 有效产能：%d / %d" % [int(_business["site"]["base_capacity"]),int(_business["site"]["shared_capacity"])],10)
	y+=22
	for currency: String in _business["finance"]["account_cash"]:
		var cash:=_business["finance"]["account_cash"][currency] as Dictionary
		shell.label(Vector2(rect.position.x+14,y),"企业可用 %d · 预留 %d · %s" % [cash["available"],cash["reserved"],currency],10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=24
	if entries.is_empty():
		shell.label(Vector2(rect.position.x+14,y),"尚无本人企业设备、已收报价或资本合同。",11)
		return
	business_capital_page=clampi(business_capital_page,0,entries.size()-1)
	var entry:=entries[business_capital_page] as Dictionary;var row:=entry["row"] as Dictionary
	var title: String={"offers":"已收设备报价" if row.get("buyer")==_business["firm_id"] else "本企业提出的报价","equipment":"本企业唯一设备","trades":"原资本交易合同","work":"实际资本施工"}[entry["kind"]]
	shell.label(Vector2(rect.position.x+14,y),title+" · "+str(business_capital_page+1)+" / "+str(entries.size()),12)
	y+=22
	shell.wrapped(Vector2(rect.position.x+14,y),str(row["id"]),rect.size.x-28,9,2)
	y+=22
	var lines: Array[String]=[]
	if entry["kind"]=="offers":
		var estimate:=row.get("estimate",{}) as Dictionary
		lines.append("卖方 "+str(row["seller"])+" → "+str(row["buyer"]))
		lines.append(str(row.get("equipment",{}).get("asset_type",""))+" · 设备产能 "+str(row.get("equipment",{}).get("capacity","未知")))
		lines.append("货款 "+str(row["price"])+" · "+str(row["denomination"]))
		lines.append("获知 "+(boundary_text(row["received_minute"]) if row["received_minute"]>=0 else "尚未送达")+" · 到期 "+boundary_text(row["expires_minute"]))
		lines.append("状态 "+capital_reason(row["availability"])+" · 安装 "+str(row["target_site"])+("（场地有效）" if estimate.get("site_allowed",false) else ""))
		if not estimate.is_empty():
			lines.append("按已知条款、工资和材料报价预计：运费 "+capital_amount(estimate["freight"])+" · 本企业装卸 "+capital_amount(estimate["handling"])+" · 交接与重装 "+capital_amount(estimate["installation"]))
			lines.append("预计完整取得费用 "+(str(estimate["total"]) if estimate["known"] else "未知："+str(estimate["unknown"])))
			lines.append("施工 "+str(estimate["hours"])+" 工时 · 材料 "+str(estimate["materials"])+("（当前足够）" if estimate["materials_available"] else "（当前不足，施工须等待）"))
			if not estimate["site_allowed"]: lines.append("安装场地当前不可使用")
	elif entry["kind"] in ["equipment","trades"]:
		var use:=row["current_use"] as Dictionary
		lines.append("产权 "+str(use["owner"])+" · 保管 "+str(use["custodian"]))
		lines.append("实物 "+str(use["status"])+" · "+str(use["place_id"])+" · "+str(use["transport"]))
		lines.append("安装地点 "+str(use["installed_site"]))
		if entry["kind"]=="equipment":
			lines.append("原建设 "+str(row["original_firm"])+" · "+str(row["original_site"]))
			lines.append("设备能力 "+str(row["capacity"])+" · 独占责任 "+str(row["exclusive"]))
			lines.append("当前维护配方 "+str(row["maintenance_recipe"]))
		else:
			lines.append("合同 "+str(row["state"])+" · 货款预留 "+str(row["purchase_reserved"])+" · 交割 "+(boundary_text(row["delivered_minute"]) if row["delivered_minute"]>=0 else "未完成"))
			for task: Dictionary in row["carriage"]:
				if task["trade_id"]!=row["id"]: continue
				lines.append("运输 "+str(task["stage"])+" · 实付运费 "+str(task["paid"])+" / "+str(task["total_fee"]))
				lines.append("载具 "+str(use.get("vehicle_id",""))+" · 完成运输段 "+str(task["completed_legs"].size()))
				lines.append(capital_reason(task["reason"]))
	else:
		lines.append(str(row["kind"])+" · "+str(row["status"])+" · "+str(row["site_id"]))
		lines.append("实际工时 %d / %d · 已耗材料 %s" % [row["hours"],row["required_hours"],str(row["materials"])])
		lines.append("实际已发生费用 "+str(row["cost"])+" · "+str(row["reason"]))
	for line: String in lines:
		if y+20>rect.end.y-148: break
		shell.label(Vector2(rect.position.x+14,y),line,10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=21
	var actions: Array[Dictionary]=[]
	for action: Dictionary in capital.get("actions",[]):
		var payload:=action["payload"] as Dictionary
		if payload.get("offer_id")==row["id"] or payload.get("asset_id")==row["id"] or payload.get("trade_id")==row["id"] or (entry["kind"]=="trades" and row["carriage"].any(func(t:Dictionary)->bool:return payload.get("transport_id")==t["id"])): actions.append(action)
	business_capital_action_page=clampi(business_capital_action_page,0,maxi(0,actions.size()-1))
	if not actions.is_empty():
		var action:=actions[business_capital_action_page] as Dictionary
		shell.button(Rect2(rect.position.x+12,rect.end.y-140,rect.size.x-24,26),action["label"],"native:capital_action:"+action["key"],action["can_execute"])
		shell.wrapped(Vector2(rect.position.x+14,rect.end.y-106),capital_reason(action["reason"]),rect.size.x-28,10,2)
		shell.button(Rect2(rect.position.x+12,rect.end.y-68,105,23),"上一个动作","capital_ui:action_previous",business_capital_action_page>0)
		shell.button(Rect2(rect.position.x+124,rect.end.y-68,105,23),"下一个动作","capital_ui:action_next",business_capital_action_page+1<actions.size())
	shell.button(Rect2(rect.position.x+12,rect.end.y-34,105,23),"上一项设备资料","capital_ui:previous",business_capital_page>0)
	shell.button(Rect2(rect.position.x+124,rect.end.y-34,105,23),"下一项设备资料","capital_ui:next",business_capital_page+1<entries.size())

func _draw_business(shell: MainShell, rect: Rect2, start: float) -> void:
	var y := start
	if _business.is_empty():
		shell.label(Vector2(rect.position.x+14,y),"没有当前合法经营权或经营地点。",11)
		if not _personal.get("managed_firms",[]).is_empty():shell.button(Rect2(rect.position.x+12,y+16,220,24),"重新选择获准企业","person:business_reset")
		return
	var sites := _business["sites"] as Array
	var firms := _personal.get("managed_firms",[]) as Array
	shell.label(Vector2(rect.position.x+14,y),str(_business["firm_id"])+" · "+str(_business["identity_basis"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=20
	shell.button(Rect2(rect.position.x+12,y,100,23),"上一企业","person:business_firm_previous",business_firm_index>0)
	shell.button(Rect2(rect.position.x+122,y,100,23),"下一企业","person:business_firm_next",business_firm_index+1<firms.size())
	y+=34
	shell.label(Vector2(rect.position.x+14,y),str(_business["site_id"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=20
	shell.button(Rect2(rect.position.x+12,y,100,23),"上一地点","person:business_site_previous",business_site_index>0)
	shell.button(Rect2(rect.position.x+122,y,100,23),"下一地点","person:business_site_next",business_site_index+1<sites.size())
	y+=34
	for currency: String in _business["finance"]["account_cash"]:
		var cash := _business["finance"]["account_cash"][currency] as Dictionary
		shell.label(Vector2(rect.position.x+14,y),"可用 %d · 预留 %d · %s" % [int(cash["available"]),int(cash["reserved"]),currency],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
	shell.button(Rect2(rect.position.x+12,y,100,23),"采购报价","person:business_procurement",not business_procurement_mode)
	shell.button(Rect2(rect.position.x+122,y,100,23),"生产及其他经营","person:business_operations",business_procurement_mode)
	y+=28
	if business_procurement_mode:
		_draw_business_procurement(shell,rect,y)
		return
	var site := _business["site"] as Dictionary
	if _business.get("capital_resale",{}).get("enabled",false):
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"返回经营信息" if business_capital_mode else "设备、已收报价与资本合同","capital_ui:toggle")
		y+=28
		if business_capital_mode:
			_draw_business_capital(shell,rect,y)
			return
	if not _business.get("leases",{}).get("enabled",false): business_leases_mode=false
	if _business.get("leases",{}).get("enabled",false):
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"返回经营信息" if business_leases_mode else "经营场地租约与出租责任","lease_ui:business_toggle")
		y+=28
		if business_leases_mode:
			_draw_leases(shell,rect,y,_business["leases"],true)
			return
	if _business.get("services",{}).get("enabled",false) or _business.get("labor_market",{}).get("enabled",false) or _business.get("capital_resale",{}).get("enabled",false):
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"返回经营信息" if business_services_mode else "服务、用工与经营处置" if _business.get("wind_down",{}).get("enabled",false) else "服务、招聘与商业公告" if _business.get("labor_market",{}).get("enabled",false) else "服务、商业公告与宣传","service_ui:toggle")
		y+=28
		if business_services_mode:
			_draw_business_services(shell,rect,y)
			return
	shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"生产与采购" if business_finance_mode else "现金、欠薪与企业信用","person:business_finance")
	y+=28
	if business_finance_mode:
		_draw_business_finance(shell,rect,y)
		return
	shell.label(Vector2(rect.position.x+14,y),"有效产能 %d · 实际工时 %d · 本日生产工时 %d" % [int(site["shared_capacity"]),int(site.get("plan",{}).get("labor_hours",0)),int(site.get("plan",{}).get("used_hours",0))],10)
	y+=18
	var retail:=_business.get("retail",{}) as Dictionary
	if not retail.is_empty():
		shell.label(Vector2(rect.position.x+14,y),"门店营业余量 %d · 已分配工时 %d · 场地 %s" % [int(retail["available_sales_units"]),int(retail["allocated_hours"]),"有效" if retail["premises_allowed"] else "不可使用"],10)
		y+=18
		shell.label(Vector2(rect.position.x+14,y),"可售 %s · 在途 %s" % [str(retail["inventory"]),str(retail["incoming"])],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
		shell.label(Vector2(rect.position.x+14,y),"近期销量 %s · 商品已知贡献 %s（未扣营业工资和租金）" % [str(retail["recent_sales"]),str(retail["operating_result"]["known_goods_contribution"])],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"暂停门店地点" if site["site_status"]["enabled"] else "恢复门店地点",("native:site_pause:" if site["site_status"]["enabled"] else "native:site_resume:")+str(_business["firm_id"])+"|"+str(_business["site_id"]))
		y+=26
	var activities := site["activities"] as Array
	business_activity_page=clampi(business_activity_page,0,maxi(0,activities.size()-1))
	for i: int in range(business_activity_page,mini(activities.size(),business_activity_page+1)):
		if y+54>rect.end.y-150: break
		var a := activities[i] as Dictionary
		shell.label(Vector2(rect.position.x+14,y),str(a["id"])+" · 本日批次 "+str(a.get("plan",{}).get("actual",0)),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=16
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"停止此活动" if a["state"]["enabled"] else "启用此活动","native:business_activity:"+str(_business["firm_id"])+"|"+str(_business["site_id"])+"|"+str(a["id"])+"|"+("0" if a["state"]["enabled"] else "1"))
		y+=26
		if not a.get("next_batch_constraints",[]).is_empty():
			shell.label(Vector2(rect.position.x+14,y),"当前下一批限制："+" / ".join(a["next_batch_constraints"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=18
	if activities.size()>1:
		shell.button(Rect2(rect.position.x+12,y,100,23),"活动上一页","person:business_activity_previous",business_activity_page>0)
		shell.button(Rect2(rect.position.x+122,y,100,23),"活动下一页","person:business_activity_next",business_activity_page+1<activities.size())
		y+=26
	_draw_business_procurement(shell,rect,y)

func _draw_business_procurement(shell:MainShell, rect:Rect2, start:float) -> void:
	var y:=start
	shell.quantity_input(Rect2(rect.end.x-168,start-26,144,26),quantity_milli,"person:collection",1)
	shell.label(Vector2(rect.position.x+14,y),"企业采购数量 %d（右侧输入）" % quantity_milli,10)
	y+=20
	var offers := _business["offers"] as Array
	for i: int in offers.size():
		if y+62>rect.end.y-34: break
		var offer := offers[i] as Dictionary
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"采购 %s · %d + 运费 %d %s" % [offer["good"],int(offer["price"]),int(offer["freight_per_unit"]),offer["denomination"]],"native:business_buy:"+str(i),offer["can_order"])
		y+=40
		shell.label(Vector2(rect.position.x+14,y),str(offer["seller_site"])+" · "+str(offer["order_reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=10
	if offers.is_empty() and y+20<rect.end.y-34: shell.label(Vector2(rect.position.x+14,y),"尚无已知供应商报价。",11)
	shell.button(Rect2(rect.position.x+12,rect.end.y-28,100,23),"报价上一页","person:business_offer_previous",business_offer_page>0)
	shell.button(Rect2(rect.position.x+122,rect.end.y-28,100,23),"报价下一页","person:business_offer_next",business_offer_page+1<int(_business["offer_total"]))

func _draw_business_finance(shell: MainShell, rect: Rect2, start: float) -> void:
	var y := start
	var finance := _business["finance"] as Dictionary
	var costs := finance.get("direct_costs",{}) as Dictionary
	if costs.get("enabled",false):
		for currency: String in costs.get("sales_revenue",{}):
			shell.label(Vector2(rect.position.x+14,y),"履约收入 %d · 已售已知直接成本 %d" % [int(costs["sales_revenue"][currency]),int(costs["sold_known_cost"].get(currency,0))],10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=19
			shell.label(Vector2(rect.position.x+14,y),"可比部分贡献 %d · %s" % [int(costs["contribution_after_known_refunds"].get(currency,0)),currency],10)
			y+=19
		shell.label(Vector2(rect.position.x+14,y),"未知 %d 笔 · 跨币不可比 %d 笔；非净利润。" % [int(costs.get("unknown_sales",0)),int(costs.get("incomparable_sales",0))],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=23
		var currencies: Dictionary={}
		for field: String in ["separate_transport_expense","handling_wages_incurred","loss_known_cost","refunds_confirmed_payable","damages_confirmed_payable"]:
			for currency: String in costs.get(field,{}): currencies[currency]=true
		for currency: String in currencies:
			if y+42>rect.end.y-160: break
			shell.label(Vector2(rect.position.x+14,y),"独立物流 %d · 装卸工资 %d · 已知物损 %d %s" % [int(costs.get("separate_transport_expense",{}).get(currency,0)),int(costs.get("handling_wages_incurred",{}).get(currency,0)),int(costs.get("loss_known_cost",{}).get(currency,0)),currency],10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=19
			shell.label(Vector2(rect.position.x+14,y),"待付退款 %d · 待付赔偿 %d；物损不指定最终责任方。" % [int(costs.get("refunds_confirmed_payable",{}).get(currency,0)),int(costs.get("damages_confirmed_payable",{}).get(currency,0))],10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=23
	for currency: String in finance.get("matured_wages",{}):
		var wages := finance["matured_wages"][currency] as Dictionary
		shell.label(Vector2(rect.position.x+14,y),"到期欠薪 %d · 最久 %d 日 · %s" % [int(wages["amount"]),int(wages["arrears_days"]),currency],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
	for loan: Dictionary in finance["credit_responsibilities"]["loans"]:
		if y+38>rect.end.y-160: break
		shell.label(Vector2(rect.position.x+14,y),str(loan["id"])+" · "+str(loan["status"])+" · 借方 "+str(loan["borrower"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
		shell.label(Vector2(rect.position.x+14,y),"剩余本金 %d · 利息 %d · 到期日 %d" % [int(loan["remaining_principal"]),int(loan["remaining_interest"]),int(loan["due_day"])],10)
		y+=20
	var rows := _business.get("financial_actions",[]) as Array
	if rows.is_empty():
		shell.label(Vector2(rect.position.x+14,y),"没有本人可执行的企业借款或还款候选。",11)
		return
	business_finance_page=clampi(business_finance_page,0,rows.size()-1)
	var row := rows[business_finance_page] as Dictionary
	shell.label(Vector2(rect.position.x+14,y),"金额 %d（右侧数量输入） · %s" % [int(row["amount"]),row["denomination"]],10)
	y+=24
	shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24),("借款 " if row["kind"]=="BORROW" else "偿还 ")+str(row["id"]),"native:business_finance",row["can_execute"])
	y+=28
	shell.label(Vector2(rect.position.x+14,y),str(row["reason"]),10)
	if row["kind"]=="BORROW": shell.label(Vector2(rect.position.x+14,y+20),"固定利息 %d · 期限 %d 日" % [int(row["interest"]),int(row["duration_days"])],10)
	shell.button(Rect2(rect.position.x+12,rect.end.y-28,100,23),"信用上一项","person:business_credit_previous",business_finance_page>0)
	shell.button(Rect2(rect.position.x+122,rect.end.y-28,100,23),"信用下一项","person:business_credit_next",business_finance_page+1<rows.size())

func _draw_business_services(shell: MainShell, rect: Rect2, start: float) -> void:
	var y:=start
	var service:=_business["services"] as Dictionary
	var closing:=_business.get("wind_down",{}) as Dictionary
	if closing.get("enabled",false) and y+60<rect.end.y-100:
		shell.label(Vector2(rect.position.x+14,y),"经营收尾："+str(closing["phase"])+" · "+str(closing["finish_reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=24
		for claim: Dictionary in (closing.get("obligations",[]) as Array).slice(0,2):
			if y+22>rect.end.y-100: break
			shell.label(Vector2(rect.position.x+14,y),str(claim["kind"])+" · "+str(claim["remaining"])+" "+str(claim["currency"])+" · "+str(claim["state"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=22
	for quote: Dictionary in (_business.get("capital_resale",{}).get("offers",[]) as Array).slice(-2):
		if y+42>rect.end.y-130: break
		shell.label(Vector2(rect.position.x+14,y),"设备报价 "+str(quote["price"])+" · "+str(quote["seller"])+" → "+str(quote["buyer"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
		shell.label(Vector2(rect.position.x+14,y),("获知时刻 "+str(quote["received_minute"]) if quote["received_minute"]>=0 else "尚未送达")+" · "+str(quote.get("availability",""))+" · 有效至 "+str(quote["expires_minute"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
	var acquisition: Dictionary=_business.get("capital_resale",{}).get("acquisition_review",{})
	if not acquisition.is_empty() and y+22<rect.end.y-130:
		shell.label(Vector2(rect.position.x+14,y),"本企业设备评估："+str(acquisition.get("execution_result",acquisition.get("reason",""))),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
	for trade: Dictionary in _business.get("capital_resale",{}).get("trades",[]):
		if y+60>rect.end.y-130: break
		shell.label(Vector2(rect.position.x+14,y),"设备合同 "+str(trade["state"])+" · 货款预留 "+str(trade["purchase_reserved"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
		shell.label(Vector2(rect.position.x+14,y),"产权 "+str(trade["current_use"]["owner"])+" · 保管 "+str(trade["current_use"]["custodian"])+" · "+str(trade["current_use"]["place_id"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
		for task: Dictionary in trade["carriage"]:
			if y+40>rect.end.y-130: break
			shell.label(Vector2(rect.position.x+14,y),str(task["stage"])+" · 运费 "+str(task["paid"])+" / "+str(task["total_fee"])+" · "+str(task["reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=20
			shell.label(Vector2(rect.position.x+14,y),"路线 "+str(task["contract"]["legs"])+" · 完成 "+str(task["completed_legs"].size()),10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=20
	var operating:=_business.get("finance",{}).get("direct_costs",{}).get("services",{}) as Dictionary
	var currencies: Dictionary={}
	for key: String in ["fulfilled_revenue","client_expense_incurred"]:
		for currency: String in operating.get(key,{}): currencies[currency]=true
	for currency: String in currencies:
		if y+42>rect.end.y-130: break
		shell.label(Vector2(rect.position.x+14,y),"服务履约收入 %d · 费用 %d · %s" % [int(operating.get("fulfilled_revenue",{}).get(currency,0)),int(operating.get("client_expense_incurred",{}).get(currency,0)),currency],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
		shell.label(Vector2(rect.position.x+14,y),"已收 %d · 已付 %d；完整已结合同的已知直接贡献 %d，非净利润。" % [int(_business["finance"].get("service_fees_received",{}).get(currency,0))+int(_business["finance"].get("publication_fees_received",{}).get(currency,0)),int(_business["finance"].get("service_fees_paid",{}).get(currency,0))+int(_business["finance"].get("advertising_paid",{}).get(currency,0)),int(operating.get("known_contract_contribution",{}).get(currency,0))],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=24
	var publicity:=_business.get("commercial_information",{}) as Dictionary
	if publicity.get("enabled",false):
		shell.label(Vector2(rect.position.x+14,y),"宣传费用 %s · 已付 %s（期间费用，非商品进价）" % [str(operating.get("advertising_expense_incurred",{})),str(operating.get("advertising_cash_paid",{}))],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=22
		var notices:=publicity.get("announcements",[]) as Array
		if not notices.is_empty():
			var last:=notices.back() as Dictionary
			shell.label(Vector2(rect.position.x+14,y),"最近公告：%s · 安排 %d · 送达主体 %d；送达不代表成交。" % [str(last["item"]),int(last["scheduled_recipients"]),int(last["delivered_recipients"])],10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=20
			var observed:=last.get("own_sales_observation",{}) as Dictionary
			if last["kind"]=="GOODS":
				shell.label(Vector2(rect.position.x+14,y),"公告后有限窗口交付 %d；不作为广告归因销量。" % int(observed.get("delivered_goods_quantity",0)),10,Color(0.82,0.86,0.79),rect.size.x-28)
				y+=24
	for job: Dictionary in _business.get("labor_market",{}).get("jobs",[]):
		if y+44>rect.end.y-130: break
		shell.label(Vector2(rect.position.x+14,y),"用工 %s：聘用 %d · 空缺 %d · 未来时薪 %d；旧合同另计。" % [job["job_id"],job["employed_workers"],job["vacancies"],job["current_quote"]["wage_per_hour"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=26
		for accepted: Dictionary in job["contracts"]:
			if y+24>rect.end.y-130: break
			var c:=accepted["contract"] as Dictionary
			shell.label(Vector2(rect.position.x+14,y),"实际合同 %s · %d人份 · 时薪 %d · %s" % [accepted["worker"],c["workers"],c.get("terms",{}).get("wage_per_hour",job["current_quote"]["wage_per_hour"]),c["denomination"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
			y+=22
	var actions:=_business_service_actions()
	business_service_page=clampi(business_service_page,0,maxi(0,actions.size()-1))
	if not actions.is_empty():
		var row:=actions[business_service_page] as Dictionary
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24),row["label"],"native:service_action:"+str(business_service_page),row["can_execute"])
		y+=28
		shell.label(Vector2(rect.position.x+14,y),str(row["reason"])+" · 执行时重新检查资金、授权、物资和设施。",10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=24
	else:
		shell.label(Vector2(rect.position.x+14,y),"尚无当前地点可执行的已知服务候选。",11)
		y+=24
	for c: Dictionary in service.get("contracts",[]):
		if y+70>rect.end.y-36: break
		shell.label(Vector2(rect.position.x+14,y),str(c["kind"])+" · "+str(c["status"])+" · "+str(c["id"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
		shell.label(Vector2(rect.position.x+14,y),"履约 %d · 已付 %d · 未付 %d · 保管 %d · %s" % [int(c["earned"]),int(c["paid"]),int(c["payable"]),int(c["remaining_custody_quantity"]),c["denomination"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
		shell.label(Vector2(rect.position.x+14,y),str(c["reason"])+(" · 实际服务份数 "+str(c["resident"]["fulfilled"])+" / "+str(c["quantity"]) if c.has("resident") else " · 发布工作与投递分开，不保证成交。" if c["kind"]=="ANNOUNCEMENT" else " · 商品及设备产权保留。"),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=26
	shell.button(Rect2(rect.position.x+12,rect.end.y-28,100,23),"经营上一项","service_ui:previous",business_service_page>0)
	shell.button(Rect2(rect.position.x+122,rect.end.y-28,100,23),"经营下一项","service_ui:next",business_service_page+1<actions.size())

func resident_service_request(index: int) -> Dictionary:
	var rows:=_personal.get("resident_services",{}).get("actions",[]) as Array
	return rows[index].duplicate(true) if index>=0 and index<rows.size() else {}
func _draw_resident_services(shell: MainShell,rect: Rect2,start: float) -> void:
	var view:=_personal.get("resident_services",{}) as Dictionary
	var y:=start
	shell.label(Vector2(rect.position.x+14,y),"同地预约 · 下个日界履行 · 不与本人劳动重叠",10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=24
	shell.label(Vector2(rect.position.x+14,y),"预约后仍需真实食品和人员；未履行不产生满足。",10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=24
	for target: Dictionary in view.get("targets",[]):
		shell.label(Vector2(rect.position.x+14,y),str(target["need_id"])+"："+str(target["satisfied_people"])+" / "+str(target["required_people"])+" · 有效至 "+boundary_text(target["window_end"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=24
	var actions:=view.get("actions",[]) as Array
	resident_service_page=clampi(resident_service_page,0,maxi(0,actions.size()-1))
	if not actions.is_empty():
		var row:=actions[resident_service_page] as Dictionary
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,25),row["label"],"native:resident_service_action:"+str(resident_service_page),row["can_execute"])
		y+=32
		for offer: Dictionary in view.get("offers",[]):
			if offer["id"]==row["payload"].get("offer_id"):
				shell.label(Vector2(rect.position.x+14,y),str(offer["place_id"])+" · 下期可预约 "+str(offer["available_capacity"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
				y+=24
		shell.label(Vector2(rect.position.x+14,y),str(row["reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=34
	for c: Dictionary in view.get("contracts",[]):
		if y+54>rect.end.y-36: break
		shell.label(Vector2(rect.position.x+14,y),str(c["kind"])+" · "+str(c["status"])+" · 已履行 "+str(c["resident"]["fulfilled"])+" / "+str(c["quantity"]),11,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=22
		shell.label(Vector2(rect.position.x+14,y),"已付 "+str(c["paid"])+" / "+str(c["earned"])+" "+str(c["denomination"])+" · "+str(c["reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=32
	shell.button(Rect2(rect.position.x+12,rect.end.y-28,100,23),"服务上一项","resident_service_ui:previous",resident_service_page>0)
	shell.button(Rect2(rect.position.x+122,rect.end.y-28,100,23),"服务下一项","resident_service_ui:next",resident_service_page+1<actions.size())

func lease_request(index:int,business:bool)->Dictionary:
	var view:Dictionary=_business.get("leases",{}) if business else _personal.get("leases",{})
	var rows:=view.get("actions",[]) as Array
	return rows[index].duplicate(true) if index>=0 and index<rows.size() else {}
func _draw_leases(shell:MainShell,rect:Rect2,start:float,view:Dictionary,business:bool)->void:
	var y:=start
	var housing:=view.get("housing",{}) as Dictionary
	if not housing.is_empty():
		shell.label(Vector2(rect.position.x+14,y),"住房目标 %d · 当前可用 %d · 上个日界满足 %d" % [housing["required_people"],housing["current_usable_people"],housing["last_day_satisfied"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=22
		shell.label(Vector2(rect.position.x+14,y),"仅明确开发目标；不推断无家可归，不办理常住迁居。",10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=26
	var actions:=view.get("actions",[]) as Array
	lease_page=clampi(lease_page,0,maxi(0,actions.size()-1))
	if not actions.is_empty():
		var row:=actions[lease_page] as Dictionary
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,25),row["label"],"native:lease_action:"+("business:" if business else "personal:")+str(lease_page),row["can_execute"])
		y+=32
		for q:Dictionary in view.get("quotes",[]):
			if q["id"]==row["payload"].get("offer_id"):
				shell.label(Vector2(rect.position.x+14,y),str(q["place_id"])+" · 可用 "+str(q["available"])+" "+str(q["unit"])+" · "+str(row["payload"].get("term_days",q["period_days"]))+"日",10,Color(0.82,0.86,0.79),rect.size.x-28)
				y+=24
		shell.label(Vector2(rect.position.x+14,y),str(row["reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=30
	for c:Dictionary in view.get("contracts",[]):
		if y+64>rect.end.y-38:break
		shell.label(Vector2(rect.position.x+14,y),str(c["place_id"])+" · "+str(c["state"])+" · 使用份额 "+str(c["quantity"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
		shell.label(Vector2(rect.position.x+14,y),"锁定 %d · 已发生 %d · 已付 %d · 到期未付 %d" % [c["total"],c["accrued"],c["paid"],c["payable"]],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=20
		shell.label(Vector2(rect.position.x+14,y),str(c["reason"])+" · "+str(c["denomination"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=24
		if not c.get("asset_available",true) and y+24<rect.end.y-38:
			shell.label(Vector2(rect.position.x+14,y),"建筑暂不可用；原合同、占用和欠款保留。",10,Color(0.85,0.73,0.65),rect.size.x-28)
			y+=24
	shell.button(Rect2(rect.position.x+12,rect.end.y-28,100,23),"租约上一项","lease_ui:previous",lease_page>0)
	shell.button(Rect2(rect.position.x+122,rect.end.y-28,100,23),"租约下一项","lease_ui:next",lease_page+1<actions.size())

