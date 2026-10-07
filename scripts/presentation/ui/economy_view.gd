class_name EconomyPage
extends RefCounted

var _polity: Dictionary = {}
var _summary: Dictionary = {}
var _market: Dictionary = {}
var _selected_id: String = ""

func refresh(polity: Dictionary, summary: Dictionary, economy: FormalWorldEconomyView, polity_id: String) -> void:
	_selected_id = polity_id
	_polity = polity.duplicate(true)
	_summary = summary.duplicate(true)
	var aggregate_id := economy.economy_entity_for_polity(polity_id)
	var market_id := economy.market_id_for_economic_aggregate(aggregate_id)
	_market = economy.market_states.get(market_id, {}) as Dictionary

func draw(shell: MainShell, rect: Rect2) -> void:
	shell.heading(rect, "经济 / 市场", "当前政治实体与正式市场的经济记录")
	var top := rect.position.y + 116.0
	var left := Rect2(rect.position.x + 28.0, top, rect.size.x * 0.52 - 36.0, rect.size.y - 150.0)
	var right := Rect2(left.end.x + 18.0, top, rect.end.x - left.end.x - 46.0, left.size.y)
	shell.card(left, str(_polity.get("name_zh", _selected_id)))
	var country := _polity.get("economy", {}) as Dictionary
	if country.is_empty():
		shell.lines(left.position + Vector2(18.0, 70.0), ["该政治实体没有高细节经济记录。"], left.size.x - 36.0)
	else:
		var totals := country.get("daily_totals", {}) as Dictionary
		shell.lines(left.position + Vector2(18.0, 70.0), [
			"人口：%d" % int(country.get("population", 0)),
			"人均产出锚：%d（2011国际元）" % int(country.get("income_per_capita", 0)),
			"城市化率：%.1f%%" % (float(country.get("urban_share_bp", 0)) / 100.0),
			"当日满足率：" + ("尚未日结" if totals.is_empty() else "%.1f%%" % (float(totals.get("fulfillment_bp", 0)) / 100.0)),
			"关联在途运输：%d" % int(country.get("active_shipments", 0)),
			"数据状态：" + str(country.get("admission_status", "")),
		], left.size.x - 36.0)
	shell.card(right, "当前市场")
	if not _market.is_empty():
		shell.lines(right.position + Vector2(18.0, 70.0), [
			"市场 ID：" + str(_market.get("market_id", "")),
			"经济单元：" + str(_market.get("source_economic_aggregate_id", "")),
		], right.size.x - 36.0)
	shell.lines(right.position + Vector2(18.0, 160.0), [
		"世界政治实体：%d" % int(_summary.get("world_political_unit_count", 0)),
		"高细节经济：%d" % int(_summary.get("major_economy_count", 0)),
	], right.size.x - 36.0)
	shell.button(Rect2(rect.position.x + 28.0, rect.end.y - 38.0, 150.0, 26.0), "在世界地图中选择", "page:map")
