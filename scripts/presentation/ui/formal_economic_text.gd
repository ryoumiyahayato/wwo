class_name FormalEconomicText
extends RefCounted
## Display vocabulary only. IDs, permissions, quantities and money stay in the domain.
const GOODS = {"grain":"粮食","bread":"面包","flour":"面粉","beans":"豆类","fiber":"纤维","oil":"油料","clothes":"衣服","soap":"肥皂","building_material":"建材","production_tool":"生产工具","machine":"机器","cloth":"布料","coal":"煤炭","iron_ore":"铁矿石","steel":"钢材","tools":"工具"}
const FIRMS = {"firm:opening_paris_workshop":"巴黎模拟工坊", "firm:opening_paris_bakery":"巴黎模拟面包坊"}

static func firm(id: String) -> String:
	if id=="cohort:regional:rouen_miller":return "鲁昂家庭加工者（开发）"
	if id.begins_with("firm:network:"):return _network_alias(id.trim_prefix("firm:network:"))+"（开发代号）"
	return str(FIRMS.get(id,"企业（名称未记录）"))

static func _network_alias(code:String) -> String:
	var name:=str(code.split(":")[0])
	var number:=""
	if name.ends_with("1") or name.ends_with("2"):number=name.right(1);name=name.left(name.length()-1)
	return str({"grain":"粮食供货企业","fiber":"纤维供货企业","coal":"煤炭供货企业","ore":"矿石供货企业","mill":"磨坊","bakery":"面包企业","weave":"织布企业","steel":"炼钢企业","tools":"工具企业","tailor":"制衣企业","wholesale":"批发企业","retail":"零售企业"}.get(name,name))+number

static func site(id: String) -> String:
	if id=="cohort:regional:rouen_miller":return "鲁昂家庭加工点（开发）"
	if id.begins_with("site:regional:station:"):
		return str({"paris":"巴黎","rouen":"鲁昂","lyon":"里昂"}.get(id.trim_prefix("site:regional:station:"),"已知城市"))+"铁路场站（开发）"
	if id.begins_with("site:network:"):return _network_alias(id.trim_prefix("site:network:"))+" · "+("港口站点" if id.contains("le_havre_port") else "站点")+"（开发）"
	if id=="site:opening_paris_workshop:paris": return "巴黎模拟工坊门市"
	if id=="site:opening_paris_bakery:paris": return "巴黎模拟面包坊门市"
	return "已知站点（名称未记录）"

static func job(id: String) -> String:
	return "面包制作与门市工作" if id in ["job:opening_paris_workshop","job:opening_paris_bakery"] else "已知岗位（名称未记录）"

static func good(id: String) -> String:
	return str(GOODS.get(id.trim_prefix("native:"),"商品（名称未记录）"))

static func currency(id: String) -> String:
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
	return str({"LABOR_HOURS_BOUND":"劳动工时不足","CAPACITY_BOUND":"可用产能不足","MINERAL_RESERVE_EXHAUSTED":"有限矿藏已耗尽","OUTSIDE_SEASON":"不在生产季节","SEASON_CLOSED":"不在生产季节","CYCLE_NOT_READY":"生产周期尚未完成","ELIGIBLE":"本期可采用","LEGACY_UNSPECIFIED":"未声明工艺限制"}.get(id,"存在已报告的工艺限制（研发细节可查原码）"))

static func reason(id: String) -> String:
	return str({"NO_VACANCY":"本人已知该岗位没有空额。", "ALREADY_EMPLOYED":"已有劳动合同；须先正式离职生效。", "EMPLOYMENT_END_PENDING":"离职尚未生效，当前岗位仍占用。", "UNQUALIFIED":"本人技能不满足岗位要求。", "UNKNOWN_JOB":"本人尚未收到此岗位消息。", "STALE_JOB_NOTICE":"岗位通知已更新，原通知不能继续使用。", "WORK_PERIOD_ALREADY_CLAIMED":"本期工作已经登记，不能重复登记。", "OUTSIDE_JOB_PLACE_OR_TRAVELLING":"人物不在工作地点或正在旅行。", "WORK_SITE_STOPPED":"当前工作站点不能采用劳动。", "EMPLOYMENT_REQUIRED":"尚未取得劳动合同。", "STORE_PREMISES_OR_BUSINESS_UNAVAILABLE":"该站点当前不能开展销售。", "OFFER":"当前报价可提交；仍需正式裁决。", "ONSITE_REAL_STOCK_HANDOVER":"现场实际交付。", "STORE_NO_ACTUAL_STAFFING":"该店当日尚无已完成的销售工作，暂不能现场交付。", "STORE_DAILY_SALES_CAPACITY_EXHAUSTED":"该店当日交付能力已用完。", "STORE_CLOSED_AT_CURRENT_TIME":"当前不在营业时间。", "ONSITE_CUSTOMER_NOT_AT_STORE":"人物不在门市所在地，不能现场取货。", "ONSITE_CUSTOMER_ACTIVITY_CONFLICT":"本人已有工作预约，当前不能办理现场购买。", "NO_UNCOMMITTED_STOCK":"卖方没有未被预占的可售商品。", "INSUFFICIENT_AVAILABLE_CASH":"本人可用资金不足。"}.get(id,"当前条件不允许；未提供更具体的可知原因。" if id==id.to_upper() and "_" in id else id))
