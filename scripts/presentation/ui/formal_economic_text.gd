class_name FormalEconomicText
extends RefCounted
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
const FranceMarketGoods = preload("res://scripts/content/france_market_goods.gd")
## Display vocabulary only. IDs, permissions, quantities and money stay in the domain.
const GOODS = {"grain":"粮食","bread":"面包","flour":"面粉","beans":"豆类","fiber":"纤维","oil":"油料","clothes":"衣服","soap":"肥皂","building_material":"建材","production_tool":"生产工具","machine":"机器","cloth":"布料","coal":"煤炭","iron_ore":"铁矿石","steel":"钢材","tools":"工具","electric_mill_motor":"磨粉电机样机","electric_trial_components":"电工试制件"}
const FIRMS = {"firm:opening_paris_workshop":"巴黎模拟工坊", "firm:opening_paris_bakery":"巴黎模拟面包坊"}

static func stock_quantities(values: Dictionary, units: Dictionary) -> String:
	var rows: Array[String]=[]
	for good: String in values:
		if int(values[good])<=0: continue
		var unit := str(units.get(good,""))
		var label := "kg" if unit in ["kg","kilogram","mass_kg","unit:kg","development_kg"] else "t" if unit in ["t","tonne","mass_tonne"] else "m" if unit in ["m","development_m"] else UILocale.text("件") if unit in ["piece","development_piece"] else UILocale.text("单位") if unit.begins_with("development_good_unit:") else UILocale.text("（原商品单位）")
		if unit == "development_m2": label = "m²"
		rows.append(UILocale.text(FranceMarketGoods.display_name(good,str(GOODS.get(good,good))))+" "+str(values[good])+" "+label)
		if rows.size()>=3: break
	if values.size()>3: rows.append(UILocale.text("等"))
	return " · ".join(rows) if not rows.is_empty() else UILocale.text("无现存商品")

static func logistics_brief(row: Dictionary, units: Dictionary) -> String:
	var lines: Array[String]=[]
	if int(row.get("stock_sites",0))>0: lines.append(UILocale.text("可查库存：")+stock_quantities(row.get("stock",{}),units))
	if not (row.get("reserved",{}) as Dictionary).is_empty(): lines.append(UILocale.text("其中预留：")+stock_quantities(row.reserved,units))
	if int(row.get("warehouses",0))>0: lines.append(UILocale.text("已知仓储 %d 处")%int(row.warehouses))
	if not (row.get("custody",{}) as Dictionary).is_empty(): lines.append(UILocale.text("寄存记录：")+stock_quantities(row.custody,units))
	if int(row.get("pending_orders",0))+int(row.get("transit_orders",0))>0: lines.append(UILocale.text("待发 %d 单 · 运送中 %d 单")%[int(row.get("pending_orders",0)),int(row.get("transit_orders",0))])
	return "\n".join(lines)

static func firm(id: String) -> String:
	if id=="cohort:opening:rouen_farm":return UILocale.text("鲁昂自营农户")
	if id=="cohort:regional:rouen_miller":return "鲁昂家庭加工者（开发）"
	if id.begins_with("firm:network:"):return _network_alias(id.trim_prefix("firm:network:"))+"（开发代号）"
	return str(FIRMS.get(id,"企业（名称未记录）"))

static func _network_alias(code:String) -> String:
	var name:=str(code.split(":")[0])
	var number:=""
	if name.ends_with("1") or name.ends_with("2"):number=name.right(1);name=name.left(name.length()-1)
	var label := str({"grain":"粮食供货企业","fiber":"纤维供货企业","coal":"煤炭供货企业","ore":"矿石供货企业","mill":"磨坊","bakery":"面包企业","weave":"织布企业","steel":"炼钢企业","tools":"工具企业","tailor":"制衣企业","wholesale":"批发企业","retail":"零售企业"}.get(name,name))
	return UILocale.text(label)+(" "+number if UILocale.english() and not number.is_empty() else number)

static func site(id: String) -> String:
	if id=="cohort:opening:rouen_farm":return firm(id)
	if id=="cohort:regional:rouen_miller":return "鲁昂家庭加工点（开发）"
	if id.begins_with("site:regional:station:"):
		return str({"paris":"巴黎","rouen":"鲁昂","lyon":"里昂"}.get(id.trim_prefix("site:regional:station:"),"已知城市"))+"铁路场站（开发）"
	if id.begins_with("site:network:"):return _network_alias(id.trim_prefix("site:network:"))+" · "+("港口站点" if id.contains("le_havre_port") else "站点")+"（开发）"
	if id=="site:opening_paris_workshop:paris": return "巴黎模拟工坊门市"
	if id=="site:opening_paris_bakery:paris": return "巴黎模拟面包坊门市"
	return "已知站点（名称未记录）"

static func job(id: String) -> String:
	if id=="job:opening_paris_mill": return UILocale.text("工坊磨粉与门市工作")
	if id.begins_with("job:network:"):return UILocale.text("%s工作")%_network_alias(id.trim_prefix("job:network:"))
	if id.begins_with("job:regional:station:"):return site(id.replace("job:","site:"))+"装卸工作"
	return "面包制作与门市工作" if id in ["job:opening_paris_workshop","job:opening_paris_bakery"] else "已知岗位（名称未记录）"

static func activity(row: Dictionary) -> String:
	var outputs: Dictionary=row.get("outputs",{})
	if outputs.has("flour"):return "研磨面粉"
	if outputs.has("bread"):return "烘焙面包"
	if outputs.has("coal"):return "开采煤炭"
	if outputs.has("iron_ore"):return "开采铁矿"
	var names: PackedStringArray=[]
	for id: String in outputs:names.append(good(id))
	return "生产"+"、".join(names) if not names.is_empty() else "生产活动"

static func good(id: String) -> String:
	var key := id.trim_prefix("native:")
	return FranceMarketGoods.display_name(key,str(GOODS.get(key,"商品（名称未记录）")))

static func trade_origin(id: String) -> String:
	var group := FranceMarketGoods.group(id)
	if not group.is_empty(): return group
	match id:
		"grain", "beans": return FranceMarketGoods.STAPLES
		"fiber", "oil": return FranceMarketGoods.RAW
		"bread", "cloth", "building_material", "production_tool", "electric_mill_motor", "electric_trial_components": return FranceMarketGoods.INDUSTRIAL
		_: return ""

static func currency(id: String) -> String:
	if id==FormalLedgerState.FRANC_1900: return "生丁（100生丁＝1法郎）"
	return "模拟记账单位" if id==FormalLedgerState.DENOMINATION else "原记账单位（名称未记录）"

static func node_kind(id: String) -> String:
	return str({"place":"合法聚落/地点","site":"企业站点","firm":"企业身份","local_producer":"地方生产者","transport_node":"物流中转节点","country_statistics":"国家统计"}.get(id,"已知身份"))

static func identity(basis: String) -> String:
	if basis.contains("DEVELOPMENT"):return "开发配置身份 · 非历史企业/参数假设"
	if basis.contains("GENERATED_OPENING"):return "普通开局模拟身份 · 非历史企业"
	if basis.contains("MANAGER"):return "当前经营授权可知"
	if basis.contains("RECEIVED"):return "本人/获准主体已收到的身份信息"
	if basis.contains("HOST_COMMERCIAL") or basis.contains("PUBLIC"):return "当前正式组织的公开身份（不含私账）"
	if basis.contains("CATALOG") or basis=="HOST_WORLD":return "正式目录地点参考（不推定人口/市场）"
	if basis=="CONFIGURED_TRANSFER_THROUGHPUT_NOT_STOCK":return "配置物流节点；不是公共仓库或实货库存"
	return "现有来源 · "+basis if not basis.is_empty() else "身份依据未记录"

static func cargo_stage(id: String) -> String:
	return str({"WAITING":"候装/等待中转","WAITING_TRANSFER":"等待中转","LOADING":"实际装载中","TRANSIT":"已进入运输段","WAITING_UNLOAD":"到站候卸","UNLOADING":"实际卸载中","AWAITING_RECIPIENT":"等待收货人正式领取","LOSS_RECORD":"损失记录","PENDING_DISPATCH":"已受理待发","DELIVERED":"已到货","CANCELLED":"已取消"}.get(id,"状态未记录" if id in ["","UNKNOWN"] else id))

static func constraint(id: String) -> String:
	if id.begins_with("CURRENT_MATERIAL_SHORTAGE:"):return "当前原料不足："+good(id.trim_prefix("CURRENT_MATERIAL_SHORTAGE:"))
	if id.begins_with("MATERIAL_SHORTAGE:"):return "下一批缺少"+good(id.trim_prefix("MATERIAL_SHORTAGE:"))
	var operating: Dictionary={"SITE_NOT_OPERATING":"站点已暂停经营","NO_CURRENT_LEASE_USE_RIGHT":"当前没有有效场地使用权","PRODUCTION_PAUSED":"本站生产已暂停","ACTIVITY_DISABLED":"此项生产活动已暂停","NO_COMPATIBLE_EQUIPMENT":"缺少当前可用的兼容设备"}
	if operating.has(id):return str(operating[id])
	return str({"LABOR_HOURS_BOUND":"劳动工时不足","CAPACITY_BOUND":"可用产能不足","MINERAL_RESERVE_EXHAUSTED":"有限矿藏已耗尽","OUTSIDE_SEASON":"不在生产季节","SEASON_CLOSED":"不在生产季节","CYCLE_NOT_READY":"生产周期尚未完成","ELIGIBLE":"本期可采用","LEGACY_UNSPECIFIED":"未声明工艺限制"}.get(id,"存在已报告的工艺限制（研发细节可查原码）"))

static func reason(id: String) -> String:
	if id=="COLLECTION_REQUIRES_STORAGE_OR_SMALLER_QUANTITY": return "所选数量超过可携额度，到货地没有可用寄存点。"
	var trade: Dictionary={"UNCONFIGURED_SHARED_WEIGHT_OR_SERVICE_WINDOW":"已知供货联系，但当前没有匹配的Shared重量口径或剩余服务窗口。","NO_ROUTE":"当前没有本人已知且可执行的运输路线。","NO_STOCK":"卖方未锁定现货不足以满足本次数量；旧报价不保证还能买到。","FIRM_STOPPED_NEW_PROCUREMENT":"本站或企业已停止接受新采购；旧合同不因此消失。","CUMULATIVE_BUDGET_OR_WINDOW":"采购授权的累计额度或有效期不足。","QUANTITY_EXCEEDS_CURRENT_OFFER":"所选数量超过当前可执行报价，请少买或重新询价。","KNOWN_ENTERPRISE_QUOTE_UNAVAILABLE":"数量或报价已改变，请刷新后重新确认。","NOT_PROCUREMENT_MANAGER":"当前人物没有本企业的采购权限。","NOT_ORDER_OWNER":"这不是本人或当前获权企业的采购单，不能取消。","NO_PENDING_QUANTITY":"没有尚未发运的数量可取消；已采用的运输不能借此撤回。","LOSS_REQUIRES_CONFIRMED_DISPOSITION":"订单有待确认的损失责任，须先按原规则处置。","STALE_QUOTE":"原报价已变化，请重新取得当前报价。","RESERVATION_ERROR":"资金预留无法按原合同处理，本次未受理。","CAPITAL_GOODS_NOT_AT_SITE":"维修材料尚未实际到达本站，不能完成维修。"}
	trade.merge({"NO_KNOWN_PATH":"供货主体已知，但没有当前可执行的已知运输通路。","TRANSPORT_LIMIT_OR_CLOSED":"原运输额度不足或连接已关闭；名义到货日不能替代实际采用。","FIRM_STOPPED_NEW_BUSINESS":"卖方当前不再接受新交易，旧合同仍须按原责任处理。","CANCEL_PENDING_AVAILABLE":"可申请取消未发运部分；执行时仍复核预留、实物和责任。","CANCELLATION_AMOUNT_BOUNDS":"原合同待释放金额无法合法表示，不能确认本次取消。"})
	if trade.has(id):return str(trade[id])
	return str({"NO_VACANCY":"本人已知该岗位没有空额。", "ALREADY_EMPLOYED":"已有劳动合同；须先正式离职生效。", "EMPLOYMENT_END_PENDING":"离职尚未生效，当前岗位仍占用。", "UNQUALIFIED":"本人技能不满足岗位要求。", "UNKNOWN_JOB":"本人尚未收到此岗位消息。", "STALE_JOB_NOTICE":"岗位通知已更新，原通知不能继续使用。", "WORK_PERIOD_ALREADY_CLAIMED":"本期工作已经登记，不能重复登记。", "OUTSIDE_JOB_PLACE_OR_TRAVELLING":"人物不在工作地点或正在旅行。", "WORK_SITE_STOPPED":"当前工作站点不能采用劳动。", "EMPLOYMENT_REQUIRED":"尚未取得劳动合同。", "STORE_PREMISES_OR_BUSINESS_UNAVAILABLE":"该站点当前不能开展销售。", "OFFER":"当前报价可提交；仍需正式裁决。", "ONSITE_REAL_STOCK_HANDOVER":"现场实际交付。", "STORE_NO_ACTUAL_STAFFING":"该店当日尚无已完成的销售工作，暂不能现场交付。", "STORE_DAILY_SALES_CAPACITY_EXHAUSTED":"该店当日交付能力已用完。", "STORE_CLOSED_AT_CURRENT_TIME":"当前不在营业时间。", "ONSITE_CUSTOMER_NOT_AT_STORE":"人物不在门市所在地，不能现场取货。", "ONSITE_CUSTOMER_ACTIVITY_CONFLICT":"本人已有工作预约，当前不能办理现场购买。", "NO_UNCOMMITTED_STOCK":"卖方没有未被预占的可售商品。", "INSUFFICIENT_AVAILABLE_CASH":"本次付款账户的可用资金不足。"}.get(id,"当前条件不允许；未提供更具体的可知原因。" if id==id.to_upper() and "_" in id else id))
