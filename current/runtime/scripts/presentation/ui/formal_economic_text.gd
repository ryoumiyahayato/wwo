class_name FormalEconomicText
extends RefCounted
## Display vocabulary only. IDs, permissions, quantities and money stay in the domain.
const GOODS = {"grain":"粮食","bread":"面包","flour":"面粉","beans":"豆类","fiber":"纤维","oil":"油料","clothes":"衣服","soap":"肥皂","building_material":"建材","production_tool":"生产工具","machine":"机器"}
const FIRMS = {"firm:opening_paris_workshop":"巴黎模拟工坊", "firm:opening_paris_bakery":"巴黎模拟面包坊"}

static func firm(id: String) -> String:
	return str(FIRMS.get(id,"企业（名称未记录）"))

static func site(id: String) -> String:
	if id=="site:opening_paris_workshop:paris": return "巴黎模拟工坊门市"
	if id=="site:opening_paris_bakery:paris": return "巴黎模拟面包坊门市"
	return "已知站点（名称未记录）"

static func job(id: String) -> String:
	return "面包制作与门市工作" if id in ["job:opening_paris_workshop","job:opening_paris_bakery"] else "已知岗位（名称未记录）"

static func good(id: String) -> String:
	return str(GOODS.get(id.trim_prefix("native:"),"商品（名称未记录）"))

static func currency(id: String) -> String:
	return "模拟记账单位" if id==FormalLedgerState.DENOMINATION else "原记账单位（名称未记录）"

static func reason(id: String) -> String:
	return str({"NO_VACANCY":"本人已知该岗位没有空额。", "ALREADY_EMPLOYED":"已有劳动合同；须先正式离职生效。", "EMPLOYMENT_END_PENDING":"离职尚未生效，当前岗位仍占用。", "UNQUALIFIED":"本人技能不满足岗位要求。", "UNKNOWN_JOB":"本人尚未收到此岗位消息。", "STALE_JOB_NOTICE":"岗位通知已更新，原通知不能继续使用。", "WORK_PERIOD_ALREADY_CLAIMED":"本期工作已经登记，不能重复登记。", "OUTSIDE_JOB_PLACE_OR_TRAVELLING":"人物不在工作地点或正在旅行。", "WORK_SITE_STOPPED":"当前工作站点不能采用劳动。", "EMPLOYMENT_REQUIRED":"尚未取得劳动合同。", "STORE_PREMISES_OR_BUSINESS_UNAVAILABLE":"该站点当前不能开展销售。", "OFFER":"当前报价可提交；仍需正式裁决。", "ONSITE_REAL_STOCK_HANDOVER":"现场实际交付。", "STORE_NO_ACTUAL_STAFFING":"该店当日尚无已完成的销售工作，暂不能现场交付。", "STORE_DAILY_SALES_CAPACITY_EXHAUSTED":"该店当日交付能力已用完。", "STORE_CLOSED_AT_CURRENT_TIME":"当前不在营业时间。", "ONSITE_CUSTOMER_NOT_AT_STORE":"人物不在门市所在地，不能现场取货。", "ONSITE_CUSTOMER_ACTIVITY_CONFLICT":"本人已有工作预约，当前不能办理现场购买。", "NO_UNCOMMITTED_STOCK":"卖方没有未被预占的可售商品。", "INSUFFICIENT_AVAILABLE_CASH":"本人可用资金不足。"}.get(id,"当前条件不允许；未提供更具体的可知原因。" if id==id.to_upper() and "_" in id else id))
