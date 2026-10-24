class_name EconomyPage
extends RefCounted
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
var _polity: Dictionary = {}
var _market: Dictionary = {}
var _rows: Array[Dictionary] = []
var polity_id: String = ""
var scope_label: String = ""
var personal_market: bool = false
var _market_status: String = "暂无市场数据。"
var commodity_page: int = 0
var selected_commodity_id: String = ""
var selected_seller_site_id: String = ""
var quantity_milli: int = 1
var quote: Dictionary = {}
var item: Dictionary = {}
var native_managed: bool = false
var _native_observation: Dictionary = {}
var show_native_statistics: bool = false
var native_statistics_page: int = 0
var cohort_statistics_page: int = 0

static func market_page_size(height: float) -> int:
	return clampi(int((height-264)/28),1,12)

func refresh(polity: Dictionary, economy: FormalWorldEconomyView, selected_id: String, rows: Array[Dictionary], offer: Dictionary, selected_item: Dictionary, native_person: bool = false, native_observation: Dictionary = {}) -> void:
	native_managed = native_person
	_native_observation = native_observation
	polity_id = selected_id
	_polity = polity
	_rows = rows
	quote = offer
	item = selected_item
	_market = {}
	_market_status = "暂无市场数据。"
	if economy == null: return
	var aggregate_id := economy.economy_entity_for_polity(selected_id)
	var market_id := economy.market_id_for_economic_aggregate(aggregate_id)
	_market = economy.market_state(market_id)
	if aggregate_id.is_empty(): _market_status = "该国家暂无已关联的市场统计。"
	elif market_id.is_empty(): _market_status = "该统计范围暂无已关联的市场。"

func draw(shell: MainShell, rect: Rect2) -> void:
	shell.draw_rect(rect,Color(0.022,0.032,0.028,0.97))
	shell.heading(rect,"已知生活商品" if native_managed else "市场",("本人所在地："+str(_native_observation.get("person_place_name","地点名称未记录"))+" · 只含已获知报价") if native_managed else "国家统计范围 · "+str(_polity.get("name_zh","未记录")))
	if not selected_commodity_id.is_empty():
		_draw_commodity(shell,rect)
		return
	if show_native_statistics and not _dictionary(_native_observation.get("management")).is_empty():
		_draw_native_summary(shell,rect)
		return
	if native_managed:
		_draw_known_market(shell,rect)
		return
	var country := _dictionary(_polity.get("economy"))
	var totals := _dictionary(_market.get("daily_totals"))
	var top := rect.position.y+103
	var stat_width := (rect.size.x-40)/3.0
	var stats: Array[Dictionary] = [{"label":"统计人口","value":str(country.population) if country.get("population")!=null else "未记录"},{"label":"商品种类","value":str((_market.get("inventory",{}) as Dictionary).size()) if _market.get("inventory") is Dictionary else "未记录"},{"label":"供应满足率","value":"%.1f%%" % (float(totals.fulfillment_bp)/100.0) if _is_number(totals.get("fulfillment_bp")) and float(totals.fulfillment_bp)>=0 else "尚无日结"}]
	for index: int in range(stats.size()):
		var x := rect.position.x+20+index*stat_width
		shell.label(Vector2(x,top+13),str(stats[index].label),11,Color(0.72,0.78,0.71))
		shell.label(Vector2(x,top+42),str(stats[index].value),23,Color(0.94,0.84,0.61),stat_width-14)
	var table := Rect2(rect.position.x+20,top+70,rect.size.x-40,rect.size.y-213)
	shell.label(table.position+Vector2(0,16),"商品行情",14)
	if native_managed:
		var notices:=_native_observation.get("commercial_information",[]) as Array
		if not notices.is_empty():
			var last:=notices.back() as Dictionary
			shell.label(table.position+Vector2(100,16),"已收公告：%s · %s" % [str(last["item"]),"有效" if last["current_notice"] else "已失效"],10,Color(0.82,0.86,0.79),table.size.x-260)
			if last["kind"]=="GOODS": shell.button(Rect2(table.end.x-148,table.position.y-2,146,23),"核对该店当前报价","commodity:select:native:"+str(last["item"])+"|"+str(last["site_id"]))
	var y := table.position.y+39
	shell.label(Vector2(table.position.x,y),"商品",11)
	shell.label(Vector2(table.position.x+table.size.x*0.34,y),"单位",11)
	shell.number(Vector2(table.position.x+table.size.x*0.45,y),"可接受数量" if native_managed else "库存",table.size.x*0.18,11)
	shell.number(Vector2(table.position.x+table.size.x*0.66,y),"单价 / 币种" if native_managed else "单价（模拟分币）",table.size.x*0.18,11)
	shell.label(Vector2(table.position.x+table.size.x*0.87,y),"供需",11)
	shell.draw_line(Vector2(table.position.x,y+7),Vector2(table.end.x,y+7),Color(0.59,0.53,0.34,0.35))
	var count := market_page_size(rect.size.y)
	var metrics := _dictionary(_market.get("daily_metrics"))
	for index: int in range(mini(count,_rows.size())):
		var row := _rows[index]
		var row_y := y+17+index*28
		if index%2==0: shell.draw_rect(Rect2(table.position.x,row_y,table.size.x,26),Color(0.08,0.11,0.09,0.40))
		shell.button(Rect2(table.position.x+2,row_y,table.size.x*0.32-6,24),str(row.get("name_zh","名称未记录")),"commodity:select:"+str(row.get("commodity_id",""))+("|"+str(row.get("seller_site","")) if native_managed else ""))
		shell.label(Vector2(table.position.x+table.size.x*0.34,row_y+19),str(row.get("unit_name_zh","未记录")),11,Color(0.75,0.80,0.72),table.size.x*0.10)
		shell.number(Vector2(table.position.x+table.size.x*0.45,row_y+19),"未记录" if not _is_number(row.get("inventory")) else "%.3f" % float(row.inventory),table.size.x*0.18,12)
		shell.number(Vector2(table.position.x+table.size.x*0.66,row_y+19),"未记录" if row.get("price")==null else str(row.price)+(" "+str(row.get("denomination","")) if native_managed else ""),table.size.x*0.18,12,Color(0.94,0.84,0.61))
		var metric := _dictionary(metrics.get(str(row.get("commodity_id",""))))
		var demand := float(metric.demand) if _is_number(metric.get("demand")) else -1.0
		if not native_managed and demand>0 and _is_number(metric.get("unmet")):
			var ratio := clampf(1.0-float(metric.get("unmet",0.0))/demand,0,1)
			var bar := Rect2(table.position.x+table.size.x*0.87,row_y+10,table.size.x*0.12,7)
			shell.draw_rect(bar,Color(0.20,0.23,0.18))
			shell.draw_rect(Rect2(bar.position,Vector2(bar.size.x*ratio,bar.size.y)),Color(0.50,0.66,0.45))
		else: shell.label(Vector2(table.position.x+table.size.x*0.87,row_y+19),"—",11)
	if _rows.is_empty():
		shell.label(Vector2(table.position.x,y+37),"暂无已知报价。" if native_managed else _market_status if _market.is_empty() else "本页暂无商品行情。",12)
	if commodity_page>0 or _rows.size()>count:
		shell.button(Rect2(rect.position.x+20,rect.end.y-35,74,25),"上一页","economy:previous",commodity_page>0)
		shell.button(Rect2(rect.position.x+104,rect.end.y-35,74,25),"下一页","economy:next",_rows.size()>count)
	if not _dictionary(_native_observation.get("management")).is_empty():
		shell.button(Rect2(rect.end.x-154,rect.end.y-35,134,25),"区域经营数据","economy:native_statistics")

static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _is_number(value: Variant) -> bool:
	return value is int or value is float

static func known_market_page_size(height: float) -> int:
	return maxi(1,int((height-186)/84))

func _draw_known_market(shell: MainShell, rect: Rect2) -> void:
	shell.label(rect.position+Vector2(22,117),"仅展示本人已知的供应报价；查看不会移动人物或执行交易。",13)
	var count := known_market_page_size(rect.size.y)
	for index: int in range(mini(count,_rows.size())):
		var row := _rows[index]
		var y := rect.position.y+139+index*84
		var card := Rect2(rect.position.x+20,y,rect.size.x-40,76)
		shell.panel(card,Color(0.025,0.039,0.033,0.98),Color(0.51,0.45,0.29,0.6))
		shell.label(card.position+Vector2(12,24),EconomicText.good(str(row.get("commodity_id","")))+" · "+EconomicText.site(str(row.get("seller_site",""))),15,Color(0.96,0.88,0.67),card.size.x-175)
		shell.label(card.position+Vector2(12,48),"单价 %s %s · 当前报价数量 %s %s" % [str(row.get("price","未知")),EconomicText.currency(str(row.get("denomination",FormalLedgerState.DENOMINATION))),str(row.get("inventory","未知")),str(row.get("unit_name_zh","配置单位"))],13,Color(0.86,0.89,0.81),card.size.x-175)
		if row.get("inventory",0)==0: shell.label(card.position+Vector2(12,67),EconomicText.reason(str(row.get("reason",""))),12,Color(0.82,0.86,0.79),card.size.x-175)
		shell.button(Rect2(card.end.x-145,y+22,132,30),"查看当前报价","commodity:select:"+str(row["commodity_id"])+"|"+str(row["seller_site"]),true,false,13)
	if _rows.is_empty(): shell.label(rect.position+Vector2(22,158),"尚未收到合法商品报价；不能从地图推知企业全部库存。",14)
	if commodity_page>0 or _rows.size()>count:
		shell.button(Rect2(rect.position.x+20,rect.end.y-35,110,27),"上一页报价","economy:previous",commodity_page>0)
		shell.button(Rect2(rect.position.x+140,rect.end.y-35,110,27),"下一页报价","economy:next",_rows.size()>count)

func _draw_commodity(shell: MainShell, rect: Rect2) -> void:
	var x := rect.position.x+24
	var y := rect.position.y+118
	var price: Variant = item.get("price")
	shell.label(Vector2(x,y),EconomicText.good(selected_commodity_id) if native_managed else str(item.get("name_zh","商品未记录")),24,Color(0.96,0.86,0.59),rect.size.x-48)
	shell.label(Vector2(x,y+32),"单位 "+str(item.get("unit_name_zh","未记录"))+" · 单价 "+(str(price) if price!=null else "未记录")+" "+(EconomicText.currency(str(item.get("denomination",FormalLedgerState.DENOMINATION))) if native_managed else str(item.get("denomination","模拟分币"))),13)
	shell.label(Vector2(x,y+60),"人物已知卖方报价" if native_managed else "国家统计库存池",11,Color(0.73,0.79,0.71))
	shell.quantity_input(Rect2(x,y+76,154,29),quantity_milli,"economy:"+selected_commodity_id,int(item.get("quantity_scale",1000)))
	shell.label(Vector2(x+174,y+99),"应付 "+str(quote.get("amount","未取得报价"))+" "+EconomicText.currency(str(quote.get("denomination",FormalLedgerState.DENOMINATION))),19,Color(0.94,0.84,0.61),rect.size.x-224)
	if bool(item.get("sale_supported",false)): shell.button(Rect2(x,y+119,132,29),"购买","purchase",bool(quote.get("success",false)))
	if not bool(quote.get("success",false)):
		var reason := str(quote.get("error","当前不可购买。"))
		var reasons := {"STORE_NO_ACTUAL_STAFFING":"该店当日没有已完成的销售工作，尚不能现场交付。", "STORE_DAILY_SALES_CAPACITY_EXHAUSTED":"该店当日可交付数量已用完。", "STORE_CLOSED_AT_CURRENT_TIME":"当前不在该店营业时间。", "ONSITE_CUSTOMER_NOT_AT_STORE":"人物不在该店所在地，不能现场取货。", "ONSITE_CUSTOMER_ACTIVITY_CONFLICT":"人物已预约其他工作，当前不能办理现场购买。", "NO_UNCOMMITTED_STOCK":"该卖方没有未被预占的可售商品。", "INSUFFICIENT_AVAILABLE_CASH":"个人可用资金不足。"}
		shell.wrapped(Vector2(x,y+172),EconomicText.reason(reason),rect.size.x-48,12,3)
	elif native_managed: shell.label(Vector2(x,y+172),"现场交付后取得；消费须另行选择，不会在下单时满足需要。" if quote.get("fulfilment")=="ONSITE_REAL_STOCK_HANDOVER" else "接受后预留资金；实际到货后取得物品。",11)
	if native_managed and quote.get("success",false):
		shell.label(Vector2(x,y+198),"卖方："+EconomicText.firm(str(quote.get("seller","")))+" · "+EconomicText.site(str(quote.get("seller_site",""))),10,Color(0.82,0.86,0.79),rect.size.x-48)

func _draw_native_summary(shell: MainShell, rect: Rect2) -> void:
	var area := Rect2(rect.position.x+20,rect.position.y+97,rect.size.x-40,rect.size.y-146)
	shell.block_panel(area)
	var info := _native_statistics_lines()
	var count := maxi(1,int((area.size.y-52)/20))
	native_statistics_page = clampi(native_statistics_page,0,maxi(0,(info.size()-1)/count))
	for index: int in range(native_statistics_page*count,mini(info.size(),(native_statistics_page+1)*count)):
		shell.label(area.position+Vector2(10,24+(index-native_statistics_page*count)*20),info[index],11,Color(0.82,0.86,0.79),area.size.x-20)
	if info.size()>count:
		shell.button(Rect2(area.position.x+10,area.end.y-30,78,24),"上一页","economy:native_previous",native_statistics_page>0)
		shell.button(Rect2(area.position.x+98,area.end.y-30,78,24),"下一页","economy:native_next",(native_statistics_page+1)*count<info.size())

	var cohorts := _native_observation.get("cohort_observation", {}) as Dictionary
	if int(cohorts.get("total", 0)) > 16:
		shell.button(Rect2(area.position.x+190,area.end.y-30,90,24),"前组人口","economy:cohort_previous",cohort_statistics_page>0)
		shell.button(Rect2(area.position.x+286,area.end.y-30,90,24),"后组人口","economy:cohort_next",(cohort_statistics_page+1)*16<int(cohorts["total"]))

static func _quantities(values: Dictionary) -> String:
	var rows: Array[String] = []
	for good: String in values:
		if int(values[good]) > 0: rows.append(good+":"+str(values[good]))
	return "、".join(rows) if not rows.is_empty() else "0"

func _native_statistics_lines() -> Array[String]:
	var scope := _native_observation["management"] as Dictionary
	var info: Array[String] = ["范围："+str(scope["scope_id"])+" · "+str(scope["status"]), "具名 %d · 背景 %d · 企业 %d · 地点 %d" % [(scope["named_people"] as Array).size(),int(scope["background_population"]),(scope["firms"] as Array).size(),(scope["sites"] as Array).size()], "观察口径："+("配置公开的区域汇总" if _native_observation.get("coverage")=="PUBLISHED_REGION_TOTALS" else "本人及有管理权限的企业"), "各商品与币种分别统计"]
	info.append("当日决策调度："+str(_native_observation.get("activity_schedule", {})))
	var cohorts := _native_observation.get("cohort_observation", {}) as Dictionary
	info.append("分层人口："+str(cohorts.get("offset", 0))+" 起 / 共 "+str(cohorts.get("total", 0))+" 组；劳动人数不等于总人数")
	for row: Dictionary in cohorts.get("rows", []):
		info.append(str(row["place_id"])+" · "+str(row["label"])+" · 总人数 "+str(row["members"])+" · 可劳动 "+str(row["labor_members"])+" · 就业 "+str(row["employed"])+" · 未就业 "+str(row["unemployed"]))
		info.append("已付工资（按币种）："+str(row["paid_wages_by_currency"])+" · 到期未付："+str(row["matured_unpaid_by_currency"]))
		info.append("当期生活结果："+str(row["needs"])+" · 来源 "+str(row["basis"]))
	info.append("常住迁居："+str(_native_observation.get("residence_statistics", {})))
	info.append("旧宏观与原生消费："+str(_native_observation.get("population_responsibility", {})))
	var crosswalk := _native_observation.get("commodity_crosswalk", {}) as Dictionary
	for mapping: Dictionary in crosswalk.get("mappings", []):
		info.append("商品口径："+str(mapping["legacy_commodity_id"])+"（"+str(mapping["legacy_unit_name_zh"])+"）→ "+str(mapping["native_good_id"])+" · 比例 "+str(mapping["native_units_numerator"])+"/"+str(mapping["legacy_units_denominator"])+" · "+str(mapping["basis"]))
	info.append("未映射统计商品："+str(crosswalk.get("unmapped_legacy_goods", [])))
	info.append("统计库存交接："+str(crosswalk.get("macro_inventory_handover", "尚无所有权接收依据")))
	for fact: Dictionary in _native_observation.get("property_handovers", []):
		info.append("本人或已授权接管物资："+str(fact["legacy_commodity_id"])+" · 旧毫单位 "+str(fact["legacy_quantity_milli"])+" → "+str(fact["good"])+" · "+str(fact["quantity"])+" · 寄存 "+str(fact["place_id"]))
	for handover: Dictionary in _native_observation.get("handover", []):
		info.append("责任交接："+str(handover["subject_id"])+" · "+str(handover["status"])+" · "+str(handover["reason"]))
	info.append("常住消费责任："+str(_native_observation.get("resident_population_by_unit", {})))
	for region: Dictionary in _native_observation.get("regions", []):
		info.append(str(region["region_id"])+" · 在场具名 "+str(region["named_people"])+" · 旅行中 "+str(region.get("travelling_named_people", 0))+" · 背景 "+str(region["background_population"])+" · 工时 "+str(region["labor_hours"]))
		info.append("背景可劳动 "+str(region.get("labor_population", 0))+" · 就业 "+str(region.get("employed_people", 0))+" · 未就业 "+str(region.get("unemployed_people", 0)))
		info.append("各分层人数："+str(region.get("cohort_strata", {}))+"；当期需要结果："+str(region.get("need_results", {})))
		info.append("背景累计需要："+str(region.get("cohort_need_history", {})))
		info.append("已安装设备："+str(region.get("installed_capital_assets", 0))+" · 可用产能 "+str(region.get("effective_production_capacity", 0))+" · 建设工时 "+str(region.get("construction_hours", 0)))
		info.append("实际生产："+_quantities(region["produced"])+"；经营地点库存："+_quantities(region["site_inventory"]))
		info.append("可售未承诺："+_quantities(region["free_sale_stock"])+"；承诺："+_quantities(region["committed"]))
		info.append("已接受订单："+str(region["accepted_orders"])+"；在途 / 待领取："+_quantities(region["in_transit"]))
		info.append("实际消耗："+_quantities(region["consumed"])+"；当前缺需："+str(region["current_unmet"]))
		info.append("工资已付 / 未付："+str(region["wages_by_currency"]))
		info.append("实际销售收入："+str(region["revenue_by_currency"])+"；信用余额："+str(region["credit_by_currency"]))
	for site: Dictionary in _native_observation.get("managed_sites", []):
		info.append(str(site["site_id"])+" · "+str(site["place_id"])+(" · 经营中" if site["operating"] else " · 停止"))
		info.append("自身库存："+_quantities(site["inventory"])+"；可售："+_quantities(site["free_inventory"])+"；承诺："+_quantities(site["committed_inventory"]))
		for job: Dictionary in site["job_postings"]: info.append("地点岗位："+str(job["id"])+" · 名额 "+str(job["positions"]))
		info.append("原料缺量："+str(site["input_needs"])+"；已订在途："+_quantities(site["incoming"]))
		for activity: Dictionary in site["activities"]:
			var plan := activity.get("plan", {}) as Dictionary
			info.append(str(activity["id"])+(" · 尚无生产日结" if plan.is_empty() else " · 本日实际产出："+_quantities(plan["actual_outputs_today"])))
	for lifecycle: Dictionary in _native_observation.get("enterprise_lifecycles", []):
		info.append("经营管理："+str(lifecycle.get("manager", ""))+" · "+str(lifecycle.get("status", "")))
		for asset: Dictionary in lifecycle.get("capital", {}).get("assets", []): info.append("设备："+str(asset["id"])+" · "+str(asset["status"])+" · 能力 "+str(asset["capacity"]))
		for project: Dictionary in lifecycle.get("capital", {}).get("projects", []): info.append("投资："+str(project["id"])+" · "+str(project["status"])+" · 已投入工时 "+str(project["labor_hours"])+" · 缺量 "+str(project["missing"]))
		info.append("结束经营条件："+str(lifecycle.get("finish_reason", "")))
		for change: Dictionary in lifecycle.get("changes", []): info.append("经营变更："+str(change["kind"])+" · "+str(change["status"])+" · "+str(change["reason"]))
		for site: Dictionary in lifecycle.get("sites", []): info.append("经营地点："+str(site["id"])+" · "+str(site["status"])+" · "+str(site["close_reason"]))
	for firm: Dictionary in scope["firms"]:
		info.append(str(firm["id"])+" · "+("商业组织："+str(firm["host_organization_id"]) if not str(firm["host_organization_id"]).is_empty() else "经营单位")+" · 管理 "+str(firm.get("manager", ""))+" · "+("已结束经营" if firm.get("finished", false) else "收尾中" if firm.get("winding_down", false) else "经营中" if firm.get("operating", true) else "已暂停"))
	for site: Dictionary in scope["sites"]:
		info.append(str(site["id"])+" → "+str(site["place_id"])+" · "+str(site["facility_basis"]))
	for worker: Dictionary in _native_observation.get("employees", []):
		info.append("岗位履约："+str(worker["worker_id"])+" · "+str(worker["site_id"])+" · 工作地点 "+str(worker["work_place_id"]))
	for request: Dictionary in _native_observation.get("scope_requests", []):
		info.append("范围申请："+str(request["status"])+" · 生效分钟 "+str(request["effective_minute"])+" · "+str(request["reason"]))
		if request.get("kind") == "EXIT": info.append("原权威保留的实际责任："+str(request.get("responsibilities", {})))
	return info
