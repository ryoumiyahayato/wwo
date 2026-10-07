class_name PersonView
extends RefCounted

var _person: Dictionary = {}
var _place: Dictionary = {}
var _polity: Dictionary = {}
var _memberships: Array[Dictionary] = []
var _economy_query: Callable

func refresh(person: Dictionary, place: Dictionary, polity: Dictionary, memberships: Array[Dictionary], economy_query: Callable = Callable()) -> void:
	_person = person.duplicate(true)
	_place = place.duplicate(true)
	_polity = polity.duplicate(true)
	_memberships.assign(memberships.duplicate(true))
	_economy_query = economy_query

func personal_economy() -> Dictionary:
	if not _economy_query.is_valid():
		return {}
	return _economy_query.call(str(_person.get("person_id", ""))) as Dictionary

func draw(shell: MainShell, rect: Rect2) -> void:
	shell.heading(rect, "人物 / 当前处境", "从当前人物、所在地与组织关系观察世界")
	var top := rect.position.y + 110.0
	var gap: float = 16.0
	var width := (rect.size.x - 56.0 - gap * 2.0) / 3.0
	var now := Rect2(rect.position.x + 28.0, top, width, 138.0)
	var place := Rect2(now.end.x + gap, top, width, 138.0)
	var polity := Rect2(place.end.x + gap, top, width, 138.0)
	shell.card(now, "当前人物")
	shell.lines(now.position + Vector2(18.0, 67.0), [
		"人物 ID：" + str(_person.get("person_id", "")),
		"存活" if bool(_person.get("alive", false)) else "非存活",
	], width - 36.0)
	shell.card(place, "所在地")
	shell.label(place.position + Vector2(18.0, 60.0), str(_place.get("name", _place.get("place_id", ""))), 20)
	shell.lines(place.position + Vector2(18.0, 88.0), [str(_place.get("place_id", "")), "类型：" + str(_place.get("spatial_kind", ""))], width - 36.0)
	shell.card(polity, "当地政治实体")
	shell.label(polity.position + Vector2(18.0, 60.0), str(_polity.get("name_zh", _polity.get("id", ""))), 18)
	shell.lines(polity.position + Vector2(18.0, 88.0), ["地位：" + str(_polity.get("status", "")), "层级：" + str(_polity.get("playability_tier_zh", ""))], width - 36.0)
	var economy_rect := Rect2(rect.position.x + 28.0, top + 154.0, rect.size.x - 56.0, 176.0)
	_draw_personal_economy(shell, economy_rect)
	var records := Rect2(rect.position.x + 28.0, top + 346.0, rect.size.x - 56.0, maxf(88.0, rect.end.y - top - 366.0))
	shell.card(records, "当前组织记录")
	var y := records.position.y + 66.0
	for membership: Dictionary in _memberships:
		if y > records.end.y - 18.0:
			break
		shell.label(Vector2(records.position.x + 18.0, y), str(membership.get("organization_id", "")), 12)
		y += 24.0
	if _memberships.is_empty():
		shell.label(Vector2(records.position.x + 18.0, y), "当前人物没有组织成员记录。", 12)

func _draw_personal_economy(shell: MainShell, rect: Rect2) -> void:
	shell.card(rect, "个人经济 / 生计")
	var value := personal_economy()
	var cash: Variant = value.get("cash")
	var left := rect.position + Vector2(18.0, 63.0)
	var right := rect.position + Vector2(rect.size.x * 0.51, 63.0)
	var column_width := rect.size.x * 0.49 - 36.0
	shell.label(left, "现金 Cash：" + (str(cash) + " simulation units" if typeof(cash) == TYPE_INT else "不可用"), 18)
	var employment := value.get("employment", {}) as Dictionary
	if employment.is_empty():
		shell.lines(left + Vector2(0.0, 29.0), ["就业 Employment：暂无正式工作", "雇主 Employer：—", "开局现金为模拟假设，不代表历史财富。"], column_width)
		shell.lines(right, ["工资 Wage：—", "下次工资 Next Pay：—", "最近工资交易：—"], column_width)
		return
	var employer := value.get("employer", {}) as Dictionary
	shell.lines(left + Vector2(0.0, 29.0), ["就业 Employment：一般工资劳动", "雇主：" + str(employer.get("label", "")) + " · " + str(employer.get("population_unit_id", "")), "现金、工资和储备为模拟假设，不代表历史事实。"], column_width)
	var recent := value.get("recent_wage_transaction", {}) as Dictionary
	var recent_text := "最近工资交易：—"
	if not recent.is_empty():
		recent_text = "最近工资交易：+%s / 周期 %d" % [recent["amount"], (employment["settled_periods"] as Array).size()]
	shell.lines(right, [
		"工资 Wage：%s simulation units / 每 %d 天" % [employment["wage_amount"], int(employment["pay_period_minutes"]) / (24 * 60)],
		"下次工资 Next Pay：" + _boundary_text(int(employment["next_pay_boundary"])),
		recent_text,
		"到期未支付：雇主储备不足。" if bool(value.get("wage_unpaid", false)) else "",
	], column_width)

func _boundary_text(minute: int) -> String:
	var date := GameCalendar.from_total_hour(minute / 60)
	return "%04d-%02d-%02d %02d:%02d" % [date["year"], date["month"], date["day"], date["hour"], minute % 60]
