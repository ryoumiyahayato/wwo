class_name PersonView
extends RefCounted
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
var business_firm_index: int = 0
var business_site_index: int = 0
var business_offer_page: int = 0
var business_activity_page: int = 0
var _business: Dictionary = {}
var capital_page: int = 0
var native_jobs_page: int = 0
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
	return "现金 "+str(cash)+(" "+str(_personal.get("denomination",""))+" · 可用 "+str(_personal.get("available",cash))+" · 预留 "+str(_personal.get("reserved",0)) if _personal.get("native",false) else " 模拟单位") if typeof(cash)==TYPE_INT else "现金资料不可用"

func livelihood_text() -> String:
	return "原生实际劳动" if _personal.get("native", false) and not (_personal.get("employment", {}) as Dictionary).is_empty() else "旧工资已终止" if int(_personal.get("legacy_wage_end_minute", -1)) >= 0 else "一般工资劳动" if not (_personal.get("employment",{}) as Dictionary).is_empty() else "暂无正式就业"

func employer_text() -> String:
	return "雇主："+str((_personal.get("employer",{}) as Dictionary).get("label","无记录"))

func next_pay_text() -> String:
	if not _personal.get("native", false) and int(_personal.get("legacy_wage_end_minute", -1)) >= 0: return "历史欠付待结" if _personal.get("wage_unpaid", false) else "未来旧工资已停止"
	var employment := _personal.get("employment",{}) as Dictionary
	return boundary_text(int(employment.next_pay_boundary)) if employment.has("next_pay_boundary") else ("按实际工作到期" if _personal.get("native",false) and not employment.is_empty() else "无安排")

static func boundary_text(minute: int) -> String:
	var date := GameCalendar.from_total_hour(minute / 60)
	return "%04d-%02d-%02d %02d:%02d" % [date.year,date.month,date.day,date.hour,minute%60]

func set_location_context(spatial: VNextSpatialWorld, control: TerritoryState, polity: Dictionary) -> void:
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
	shell.label(Vector2(cash_x,rect.position.y+119),str(_personal.get("denomination","模拟单位")),10,Color(0.76,0.79,0.70))
	var employment := _personal.get("employment",{}) as Dictionary
	var wage := livelihood_text()
	if not employment.is_empty():
		wage = "工资 %s / 小时 · %s" % [employment.get("wage_per_hour","未记录"),employment.get("denomination","")] if _personal.get("native",false) else "工资 %s / %d 天" % [employment.get("wage_amount","未记录"),int(employment.get("pay_period_minutes",1440))/(24*60)]
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
	if _personal.get("native",false) or not _personal.get("handover", []).is_empty(): shell.button(Rect2(rect.position.x+260,rect.end.y-34,112,24),"岗位与订单","person:native")

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
		shell.label(Vector2(area.position.x,y),boundary_text(int(receipt.effective_minute))+" · "+kind+" · "+str(receipt.get("denomination", "")),11,Color(0.82,0.86,0.79),area.size.x*0.64)
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
	shell.label(right.position+Vector2(0,42),"持有 %.3f %s · 已消费 %.3f" % [float(owned.quantity_milli)/float(owned.get("quantity_scale",1000)),unit,float(owned.get("consumed_milli",0))/float(owned.get("quantity_scale",1000))],11,Color(0.82,0.86,0.79),right.size.x)
	var capability := _property.get("capability",{}) as Dictionary
	var plan := _property.get("arrangement",{}) as Dictionary
	if bool(capability.get("daily_supported",capability.get("consumable",false))):
		shell.quantity_input(Rect2(right.position+Vector2(0,53),Vector2(132,26)),quantity_milli,"person:"+selected_commodity_id,int(capability.get("quantity_scale",1000)))
		var quote := _property.get("quote",{}) as Dictionary
		shell.button(Rect2(right.position.x+144,right.position.y+53,100,26),"消费","consume",bool(quote.get("success",false)))
		var reason := str(quote.get("error","")) if not bool(quote.get("success",false)) else ""
		if not plan.is_empty(): reason = "每日 %.3f %s · 下次 %s" % [float(plan.quantity_milli)/float(plan.get("quantity_scale",1000)),unit,boundary_text(int(plan.next_due_minute))]
		shell.wrapped(right.position+Vector2(0,100),reason,right.size.x,10,2)
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
		if record.has("amount"): info.append("金额 "+str(record.amount)+" "+str(record.get("denomination","模拟单位")))
		if not str(record.get("reason","")).is_empty(): info.append(str(record.reason))
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

func _draw_native(shell: MainShell, rect: Rect2) -> void:
	shell.heading(rect, "岗位 / 个人订单", cash_text())
	var left := Rect2(rect.position.x+20, rect.position.y+104, rect.size.x*0.48-28, rect.size.y-152)
	var right := Rect2(left.end.x+16, left.position.y, rect.end.x-left.end.x-36, left.size.y)
	shell.card(left, "已知岗位 / 当前需要")
	var y := left.position.y+50
	if native_scope_expanded and business_mode:
		_draw_native_scope(shell,left,y)
	else:
		shell.label(Vector2(left.position.x+14,y), "管理："+str(_personal.get("management_scope_id", ""))+" · 所在地："+str(_personal.get("current_place_id", "")), 10, Color(0.82,0.86,0.79), left.size.x-28)
		y += 22
		shell.label(Vector2(left.position.x+14,y), "常住统计："+str(_personal.get("resident_population_unit_id", ""))+" · 活动统计："+str(_personal.get("activity_population_unit_id", "")), 10, Color(0.82,0.86,0.79), left.size.x-28)
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
		shell.button(Rect2(left.position.x+12,y,left.size.x-24,24), "岗位与需要" if native_scope_expanded else "经营资料", "person:native_scope")
		y += 30
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
				shell.label(Vector2(left.position.x+14,y), "工作地点："+str(employment.get("work_place_id", ""))+" · "+str(employment.get("site_id", "")), 10, Color(0.82,0.86,0.79), left.size.x-28)
				y += 12
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,26), "已登记本期工作" if not booking.is_empty() else "登记工作 %d 小时" % int(employment.get("work_hours_available", employment.get("work_hours_limit",0))), "native:work", booking.is_empty() and bool(employment.get("can_work_now",false)))
				y += 30
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,24), "申请结束未来劳动合同", "native:leave_job")
				y += 32
			var jobs: Array = _personal.get("known_jobs", [])
			var job_page_size := maxi(1, int((left.end.y-y-42)/44))
			native_jobs_page = clampi(native_jobs_page, 0, maxi(0, (jobs.size()-1)/job_page_size))
			for index: int in range(native_jobs_page*job_page_size, mini(jobs.size(), (native_jobs_page+1)*job_page_size)):
				var job := jobs[index] as Dictionary
				if y+40 > left.end.y-36: break
				shell.label(Vector2(left.position.x+14,y), str(job["employer"])+" · "+str(job["place"]), 10, Color(0.82,0.86,0.79), left.size.x-28)
				y += 10
				shell.button(Rect2(left.position.x+12,y,left.size.x-24,25), "申请：%s · 名额 %d · 工资 %d / 小时" % [job["id"],int(job["positions"]),int(job["wage_per_hour"])], "native:apply:"+str(job["id"]), employment.is_empty() and int(job["positions"])>0)
				y += 44
			shell.button(Rect2(left.position.x+12,left.end.y-30,90,24), "岗位上一页", "person:native_jobs_previous", native_jobs_page>0)
			shell.button(Rect2(left.position.x+110,left.end.y-30,90,24), "岗位下一页", "person:native_jobs_next", (native_jobs_page+1)*job_page_size<jobs.size())
	shell.card(right, "个人订单 / 在途")
	shell.quantity_input(Rect2(right.position+Vector2(12,40),Vector2(144,26)),quantity_milli,"person:collection",1)
	shell.label(right.position+Vector2(164,56), "领取 / 企业采购数量" if business_mode else "本次领取数量", 10)
	y = right.position.y+86
	var orders := _personal.get("orders", []) as Array
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
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "停止生产采购，出售现有库存", "native:wind_down:"+str(firm["firm_id"]), lifecycle.get("status") != "FINISHED_NATIVE_IDENTITY_RETAINED")
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
		lines.append("新增产能："+str(row["capacity"])+" · 兼容 "+str(row["activities"]))
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
		lines.append("设备能力："+str(row["capacity"])+" · "+str(row["activities"]))
		lines.append("投入使用："+boundary_text(int(row["in_service_minute"])))
		lines.append("形成项目："+str(row["project_id"]))
	for line: String in lines:
		if y+18 > rect.end.y-92: break
		shell.label(Vector2(rect.position.x+14,y), line, 10, Color(0.82,0.86,0.79), rect.size.x-28)
		y += 19
	if entry["kind"] == "projects" and row["status"] not in ["COMPLETED", "CANCELLED"]:
		for offer: Dictionary in entry["credit_offers"]:
			var amount := mini(int(offer["available_quantity"]), int(row["budget_remaining"]))
			if amount <= 0 or offer["denomination"] != row["terms"]["denomination"] or y+28 > rect.end.y-92: continue
			shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,24), "企业借款 "+str(amount)+" · 利息 "+str(offer["interest"]), "native:investment_credit:"+str(row["id"])+"|"+str(offer["id"])+"|"+str(amount))
			break
	var action_y := rect.end.y-86
	if entry["kind"] == "options":
		shell.button(Rect2(rect.position.x+12,action_y,rect.size.x-24,24), "按许可预算提出投资", "native:invest:"+str(row["id"]), row["site_ready"])
	elif entry["kind"] == "projects" and row["status"] not in ["COMPLETED", "CANCELLED"]:
		shell.button(Rect2(rect.position.x+12,action_y,108,24), "恢复" if row["status"] == "PAUSED" else "暂停", "native:project:"+str(row["id"])+"|"+("ACTIVE" if row["status"] == "PAUSED" else "PAUSED"))
		shell.button(Rect2(rect.position.x+128,action_y,108,24), "取消施工", "native:project:"+str(row["id"])+"|CANCELLED")
	elif entry["kind"] == "assets" and row["status"] in ["ACTIVE", "PAUSED"]:
		shell.button(Rect2(rect.position.x+12,action_y,88,24), "停用" if row["status"] == "ACTIVE" else "启用", "native:equipment:"+str(row["id"])+"|"+("PAUSED" if row["status"] == "ACTIVE" else "ACTIVE"))
		shell.button(Rect2(rect.position.x+108,action_y,88,24), "维修", "native:maintain:"+str(row["id"]))
		shell.button(Rect2(rect.position.x+204,action_y,88,24), "退役保管", "native:equipment:"+str(row["id"])+"|RETIRED")
	shell.button(Rect2(rect.position.x+12,rect.end.y-52,88,24), "上一项", "person:capital_previous", capital_page > 0)
	shell.button(Rect2(rect.position.x+108,rect.end.y-52,88,24), "下一项", "person:capital_next", capital_page+1 < rows.size())
	shell.label(Vector2(rect.position.x+206,rect.end.y-36), str(capital_page+1)+" / "+str(rows.size()), 10)

func refresh_business(view: Dictionary) -> void:
	_business=view

func business_request(index: int) -> Dictionary:
	var offers := _business.get("offers",[]) as Array
	return (offers[index].get("request",{}) as Dictionary).duplicate(true) if index>=0 and index<offers.size() else {}

func _draw_business(shell: MainShell, rect: Rect2, start: float) -> void:
	var y := start
	if _business.is_empty():
		shell.label(Vector2(rect.position.x+14,y),"没有当前合法经营权或经营地点。",11)
		return
	var sites := _business["sites"] as Array
	var firms := _personal.get("managed_firms",[]) as Array
	shell.label(Vector2(rect.position.x+14,y),str(_business["firm_id"])+" · "+str(_business["identity_basis"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=20
	shell.button(Rect2(rect.position.x+12,y,100,23),"上一企业","person:business_firm_previous",business_firm_index>0)
	shell.button(Rect2(rect.position.x+122,y,100,23),"下一企业","person:business_firm_next",business_firm_index+1<firms.size())
	y+=26
	shell.label(Vector2(rect.position.x+14,y),str(_business["site_id"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
	y+=16
	shell.button(Rect2(rect.position.x+12,y,100,23),"上一地点","person:business_site_previous",business_site_index>0)
	shell.button(Rect2(rect.position.x+122,y,100,23),"下一地点","person:business_site_next",business_site_index+1<sites.size())
	y+=26
	for currency: String in _business["finance"]["account_cash"]:
		var cash := _business["finance"]["account_cash"][currency] as Dictionary
		shell.label(Vector2(rect.position.x+14,y),"可用 %d · 预留 %d · %s" % [int(cash["available"]),int(cash["reserved"]),currency],10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=18
	var site := _business["site"] as Dictionary
	shell.label(Vector2(rect.position.x+14,y),"有效产能 %d · 实际工时 %d · 本日生产工时 %d" % [int(site["shared_capacity"]),int(site.get("plan",{}).get("labor_hours",0)),int(site.get("plan",{}).get("used_hours",0))],10)
	y+=18
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
	shell.label(Vector2(rect.position.x+14,y),"企业采购数量 %d（右侧输入）" % quantity_milli,10)
	y+=20
	var offers := _business["offers"] as Array
	for i: int in offers.size():
		if y+62>rect.end.y-34: break
		var offer := offers[i] as Dictionary
		shell.button(Rect2(rect.position.x+12,y,rect.size.x-24,23),"采购 %s · %d + 运费 %d %s" % [offer["good"],int(offer["price"]),int(offer["freight_per_unit"]),offer["denomination"]],"native:business_buy:"+str(i),offer["can_order"])
		y+=26
		shell.label(Vector2(rect.position.x+14,y),str(offer["seller_site"])+" · "+str(offer["order_reason"]),10,Color(0.82,0.86,0.79),rect.size.x-28)
		y+=24
	if offers.is_empty() and y+20<rect.end.y-34: shell.label(Vector2(rect.position.x+14,y),"尚无已知供应商报价。",11)
	shell.button(Rect2(rect.position.x+12,rect.end.y-28,100,23),"报价上一页","person:business_offer_previous",business_offer_page>0)
	shell.button(Rect2(rect.position.x+122,rect.end.y-28,100,23),"报价下一页","person:business_offer_next",business_offer_page+1<int(_business["offer_total"]))
