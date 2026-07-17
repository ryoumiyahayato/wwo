class_name V2LifeLoopUiBinding
extends RefCounted
## Read-only presentation snapshots plus authoritative commands for the V2 shell.

signal view_changed

var simulation: V2LifeLoopSimulation
var save_service := GameSaveService.new()
var developer_mode: bool = false
var last_command_result := V2LifeLoopResult.ok()
var _panel_pause_depth: int = 0
var _panel_previous_paused: bool = true
var _panel_previous_speed: int = 1


func _init(life_simulation: V2LifeLoopSimulation, enable_developer_mode: bool = false) -> void:
	simulation = life_simulation
	developer_mode = enable_developer_mode
	if simulation != null and not simulation.state_changed.is_connected(_on_state_changed):
		simulation.state_changed.connect(_on_state_changed)


func selected_person_id() -> String:
	return simulation.selected_person_id


func identity_id() -> String:
	return (
		"official"
		if simulation.selected_person_id == V2LifeLoopSimulation.ALBERT_ID
		else "worker"
	)


func select_identity(identity: String) -> V2LifeLoopResult:
	var person_id: String = (
		V2LifeLoopSimulation.ALBERT_ID
		if identity == "official"
		else V2LifeLoopSimulation.PIERRE_ID
	)
	last_command_result = simulation.select_person(person_id)
	return last_command_result


func time_view() -> Dictionary:
	var value: Dictionary = V2DateTime.from_total_hour(simulation.clock.total_hours)
	return {
		"total_hour": simulation.clock.total_hours,
		"datetime": V2DateTime.iso_from_total_hour(simulation.clock.total_hours),
		"display": V2DateTime.display_from_total_hour(simulation.clock.total_hours),
		"date_display": "%04d年%d月%d日" % [
			int(value["year"]), int(value["month"]), int(value["day"]),
		],
		"weekday_display": V2DateTime.WEEKDAY_NAMES[int(value["weekday"])],
		"hour_display": "%02d:00" % int(value["hour"]),
		"paused": simulation.clock.is_paused,
		"speed": simulation.clock.speed_multiplier,
		"allowed_speeds": simulation.clock.get_allowed_speeds(),
	}


func set_paused(paused: bool) -> bool:
	simulation.clock.set_paused(paused)
	view_changed.emit()
	return true


func toggle_pause() -> void:
	set_paused(not simulation.clock.is_paused)


func set_speed(multiplier: int) -> bool:
	var changed: bool = simulation.clock.set_speed(multiplier)
	if changed:
		simulation.clock.set_paused(false)
		view_changed.emit()
	return changed


func begin_blocking_panel() -> void:
	if _panel_pause_depth == 0:
		_panel_previous_paused = simulation.clock.is_paused
		_panel_previous_speed = simulation.clock.speed_multiplier
		simulation.clock.set_paused(true)
	_panel_pause_depth += 1


func end_blocking_panel() -> void:
	if _panel_pause_depth <= 0:
		return
	_panel_pause_depth -= 1
	if _panel_pause_depth == 0:
		simulation.clock.set_speed(_panel_previous_speed)
		simulation.clock.set_paused(_panel_previous_paused)


func person_view(person_id: String = "") -> Dictionary:
	var resolved_person_id: String = (
		simulation.selected_person_id if person_id.is_empty() else person_id
	)
	var person: Dictionary = simulation.config.person_record(resolved_person_id)
	var runtime: Dictionary = simulation.get_person_state(resolved_person_id)
	var household: Dictionary = simulation.households.household_for_person(resolved_person_id)
	var contract: Dictionary = simulation.employment.contract_for_person(resolved_person_id)
	var condition: Dictionary = simulation.conditions.get_state(resolved_person_id)
	var current: Dictionary = simulation.schedule.activity_for_hour(
		resolved_person_id, simulation.clock.total_hours
	)
	var next: Dictionary = simulation.schedule.next_activity(
		resolved_person_id, simulation.clock.total_hours
	)
	var attendance: Dictionary = simulation.employment.today_summary(
		resolved_person_id, simulation.clock.total_hours
	)
	var household_id: String = str(household.get("household_id", ""))
	var indicators: Array[Dictionary] = [
		simulation.conditions.indicator(
			resolved_person_id, "health", simulation.clock.total_hours
		),
		simulation.conditions.indicator(
			resolved_person_id, "fatigue", simulation.clock.total_hours
		),
		simulation.conditions.indicator(
			resolved_person_id, "stress", simulation.clock.total_hours
		),
		_employment_indicator(resolved_person_id),
	]
	var next_pay_hour: int = int(contract.get("next_pay_hour", -1))
	var next_rent_hour: int = int(household.get("next_rent_due_hour", -1))
	var is_official: bool = resolved_person_id == V2LifeLoopSimulation.ALBERT_ID
	var period_label: String = (
		"月薪 %s" % _money(int(contract.get("base_wage_centimes", 0)))
		if is_official
		else "周薪 %s" % _money(int(contract.get("base_wage_centimes", 0)))
	)
	return {
		"person_id": resolved_person_id,
		"identity_id": str(person.get("identity_id", "worker")),
		"display_name_zh": str(person.get("display_name_zh", "")),
		"native_name": str(person.get("native_name", "")),
		"occupation": str(person.get("occupation", "")),
		"employer": str(person.get("organization_name", "")),
		"institution": str(person.get("institution_name", person.get("organization_name", ""))),
		"union": str(person.get("union_name", "")),
		"union_position": str(person.get("union_position", "")),
		"institution_position": str(person.get("position_name", "")),
		"position": str(person.get("position_name", "")),
		"current_activity": _activity_view(current),
		"next_activity": _activity_view(next),
		"current_location_id": str(runtime.get("current_location_id", "")),
		"current_location": simulation.config.location_name(
			str(runtime.get("current_location_id", ""))
		),
		"current_work": "%s · %s" % [
			_activity_label(str(current.get("activity_type", "free_time"))),
			simulation.config.location_name(str(current.get("location_id", ""))),
		],
		"primary_concern": _primary_concern(condition),
		"plan": "下一活动：%s" % _activity_label(
			str(next.get("activity_type", "free_time"))
		),
		"plan_status": _activity_condition_symbol(next),
		"status_indicators": indicators,
		"health": int(condition.get("health", 0)),
		"fatigue": int(condition.get("fatigue", 0)),
		"stress": int(condition.get("stress", 0)),
		"employment_risk": simulation.employment.employment_risk(resolved_person_id),
		"household": "%d 人住户 · %s" % [
			(household.get("member_ids", []) as Array).size(),
			simulation.config.location_name(str(household.get("home_location_id", ""))),
		],
		"household_id": household_id,
		"cash": _money(int(household.get("cash_centimes", 0))),
		"cash_centimes": int(household.get("cash_centimes", 0)),
		"income": "本期收入 %s" % _money(
			int(household.get("income_current_period_centimes", 0))
		),
		"expenses": "本期支出 %s" % _money(
			int(household.get("expense_current_period_centimes", 0))
		),
		"income_current_period_centimes": int(
			household.get("income_current_period_centimes", 0)
		),
		"expense_current_period_centimes": int(
			household.get("expense_current_period_centimes", 0)
		),
		"weekly_wage": period_label,
		"monthly_salary": period_label,
		"pay_cycle": "下次 %s" % (
			V2DateTime.display_from_total_hour(next_pay_hour)
			if next_pay_hour >= 0 else "无"
		),
		"next_pay_hour": next_pay_hour,
		"allowance": (
			"交通津贴 %s/月" % _money(int(contract.get("allowance_centimes", 0)))
			if is_official else "加班 %s/小时" % _money(
				int(contract.get("overtime_rate_centimes_per_hour", 0))
			)
		),
		"food_stock": int(household.get("food_stock_person_days", 0)),
		"essentials_stock": int(household.get("essentials_stock_person_days", 0)),
		"next_rent": (
			V2DateTime.display_from_total_hour(next_rent_hour)
			if next_rent_hour >= 0 else "无"
		),
		"next_rent_hour": next_rent_hour,
		"rent_amount_centimes": int(household.get("rent_amount_centimes", 0)),
		"rent_arrears_centimes": int(household.get("rent_arrears_centimes", 0)),
		"debt_burden": "房租欠款 %s · 其他债务 %s" % [
			_money(int(household.get("rent_arrears_centimes", 0))),
			_money(int(household.get("other_debt_centimes", 0))),
		],
		"work_contract": "%s · %s" % [
			str(contract.get("position_name", "")),
			"周结" if str(contract.get("wage_period", "")) == "weekly" else "月结",
		],
		"today_attendance": attendance,
		"recent_transactions": simulation.ledger.recent_for_household(household_id, 5),
		"institution_budget_source": str(person.get("institution_budget_display", "")),
		"personal_and_institution_budget_separated": true,
		"relationship": simulation.relationships.get_relationship(
			resolved_person_id, V2LifeLoopSimulation.JEANNE_ID
		),
		"union_membership": simulation.organizations.get_membership(
			resolved_person_id, V2LifeLoopSimulation.UNION_ID
		),
	}


func today_schedule(person_id: String = "") -> Array[Dictionary]:
	var resolved: String = simulation.selected_person_id if person_id.is_empty() else person_id
	return simulation.schedule.timeline_for_day(
		resolved, simulation.clock.total_hours, simulation.clock.total_hours
	)


func notifications_view(limit: int = 16) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in simulation.notifications.latest(limit):
		result.append({
			"id": record.get("notification_id", ""),
			"kind": record.get("kind", "notification"),
			"category": record.get("category", "personal"),
			"title": record.get("title", ""),
			"detail": record.get("detail", ""),
			"time": V2DateTime.display_from_total_hour(int(record.get("total_hour", 0))),
			"source": _notification_source(str(record.get("category", "personal"))),
			"group_count": record.get("group_count", 1),
			"object_id": (record.get("affected_entity_ids", []) as Array).front()
			if not (record.get("affected_entity_ids", []) as Array).is_empty() else "",
		})
	return result


func schedule_next(activity_type: String) -> V2LifeLoopResult:
	last_command_result = simulation.request_next_activity(
		simulation.selected_person_id, activity_type
	)
	view_changed.emit()
	return last_command_result


func activity_proposal(activity_type: String) -> V2LifeLoopResult:
	return simulation.suggest_next_activity(
		simulation.selected_person_id, activity_type
	)


func submit_activity(
	activity_type: String, start_hour: int, duration_hours: int
) -> V2LifeLoopResult:
	last_command_result = simulation.request_activity(
		simulation.selected_person_id,
		activity_type,
		start_hour,
		duration_hours
	)
	view_changed.emit()
	return last_command_result


func cancel_activity(activity_id: String) -> V2LifeLoopResult:
	last_command_result = simulation.cancel_activity(
		simulation.selected_person_id, activity_id
	)
	view_changed.emit()
	return last_command_result


func save_review() -> V2LifeLoopResult:
	var saved: SaveOperationResult = save_service.save_v2_2_review(simulation)
	if saved.success:
		simulation.notifications.add(
			"personal", "event", "保存完成", saved.path,
			simulation.clock.total_hours, "save", [simulation.selected_person_id]
		)
		last_command_result = V2LifeLoopResult.ok("保存完成：%s" % saved.path)
	else:
		simulation.notifications.add(
			"personal", "notification", "存档错误", saved.message,
			simulation.clock.total_hours, "save_error", [simulation.selected_person_id]
		)
		last_command_result = V2LifeLoopResult.fail(
			saved.error_code, saved.message, saved.path
		)
	view_changed.emit()
	return last_command_result


func load_review() -> V2LifeLoopResult:
	var loaded: SaveOperationResult = save_service.load_v2_2_review()
	if not loaded.success:
		last_command_result = V2LifeLoopResult.fail(
			loaded.error_code, loaded.message, loaded.path
		)
		view_changed.emit()
		return last_command_result
	var restored: SaveOperationResult = save_service.restore_v2_2_review(
		loaded.snapshot, simulation
	)
	if restored.success:
		simulation.notifications.add(
			"personal", "event", "载入完成", loaded.path,
			simulation.clock.total_hours, "load", [simulation.selected_person_id]
		)
		last_command_result = V2LifeLoopResult.ok("载入完成")
	else:
		last_command_result = V2LifeLoopResult.fail(
			restored.error_code, restored.message, restored.path
		)
	view_changed.emit()
	return last_command_result


func developer_command(command: String) -> V2LifeLoopResult:
	if not developer_mode:
		return V2LifeLoopResult.fail("developer_disabled", "开发者模式未启用")
	if command.begins_with("set_date:"):
		last_command_result = simulation.advance_to_datetime(
			command.trim_prefix("set_date:")
		)
		view_changed.emit()
		return last_command_result
	match command:
		"step_hour":
			simulation.advance_hours(1)
			last_command_result = V2LifeLoopResult.ok("已推进 1 小时")
		"step_day":
			simulation.advance_hours(24)
			last_command_result = V2LifeLoopResult.ok("已推进 1 日")
		"force_pay":
			var contract: Dictionary = simulation.employment.contract_for_person(
				simulation.selected_person_id
			)
			last_command_result = simulation.employment.force_settle(
				str(contract.get("contract_id", "")), simulation.clock.total_hours,
				simulation.households, simulation.ledger, simulation.notifications
			)
		"force_rent":
			var household_id: String = simulation.households.household_id_for_person(
				simulation.selected_person_id
			)
			var household: Dictionary = (
				simulation.households.households[household_id] as Dictionary
			)
			household["next_rent_due_hour"] = simulation.clock.total_hours
			simulation.households.households[household_id] = household
			var results: Array[V2LifeLoopResult] = simulation.households.settle_due_rent(
				simulation.clock.total_hours, simulation.ledger,
				simulation.conditions, simulation.notifications
			)
			last_command_result = (
				results[0] if not results.is_empty()
				else V2LifeLoopResult.fail("rent_not_due", "没有可结算房租")
			)
		"cash_zero":
			last_command_result = simulation.set_household_cash(
				simulation.selected_person_id, 0
			)
		"food_zero":
			last_command_result = simulation.set_inventory(
				simulation.selected_person_id, "food", 0
			)
		"essentials_zero":
			last_command_result = simulation.set_inventory(
				simulation.selected_person_id, "essentials", 0
			)
		"health_low":
			last_command_result = simulation.set_condition(
				simulation.selected_person_id, "health", 400
			)
		"fatigue_max":
			last_command_result = simulation.set_condition(
				simulation.selected_person_id, "fatigue", 950
			)
		"stress_high":
			last_command_result = simulation.set_condition(
				simulation.selected_person_id, "stress", 700
			)
		"absence":
			last_command_result = simulation.request_next_activity(
				simulation.selected_person_id, "absence"
			)
		"clear_schedule":
			var count: int = simulation.schedule.clear_future_player_schedule(
				simulation.selected_person_id, simulation.clock.total_hours
			)
			last_command_result = V2LifeLoopResult.ok("已清除 %d 项未来玩家活动" % count)
		"save":
			return save_review()
		"load":
			return load_review()
		"reset":
			last_command_result = simulation.reset_scenario()
		_:
			last_command_result = V2LifeLoopResult.fail(
				"unknown_developer_command", "未知开发者命令", command
			)
	view_changed.emit()
	return last_command_result


func debug_state() -> Dictionary:
	var state: Dictionary = simulation.get_debug_state()
	state["identity"] = identity_id()
	state["last_command_result"] = last_command_result.to_dict()
	state["review_save_path"] = GameSaveService.V2_2_REVIEW_PATH
	state["time_is_static_prototype"] = false
	state["ui_live_fields"] = [
		"current_activity", "current_location", "next_activity", "cash", "income",
		"expenses", "wage", "next_pay", "food", "essentials", "next_rent",
		"arrears", "health", "fatigue", "stress", "employment_risk",
		"attendance",
	]
	return state


func _on_state_changed(_change_set: Dictionary) -> void:
	view_changed.emit()


func _employment_indicator(person_id: String) -> Dictionary:
	var risk: int = simulation.employment.employment_risk(person_id)
	var symbol: String = "✓" if risk < 300 else "!"
	var state_label: String = (
		"正常" if risk < 300 else ("严重风险" if risk >= 700 else "需要注意")
	)
	return {
		"label": "就业",
		"symbol": symbol,
		"state": "%s · %d/1000" % [state_label, risk],
		"reason": "无故缺勤会逐小时增加风险；完整出勤日降低风险",
		"trend": "实时",
		"impact": "本轮不会自动解雇",
		"suggestion": "按合同出勤或提前安排授权无薪请假",
		"value": risk,
	}


func _activity_view(activity: Dictionary) -> Dictionary:
	if activity.is_empty():
		return {}
	var result: Dictionary = activity.duplicate(true)
	result["label"] = _activity_label(str(activity.get("activity_type", "")))
	result["location_name"] = simulation.config.location_name(
		str(activity.get("location_id", ""))
	)
	result["start_display"] = V2DateTime.display_from_total_hour(
		int(activity.get("start_hour", 0))
	)
	result["end_display"] = V2DateTime.display_from_total_hour(
		int(activity.get("end_hour", 0))
	)
	return result


static func _activity_label(activity_type: String) -> String:
	var labels: Dictionary = {
		"sleep": "睡眠",
		"commute_to_work": "通勤上班",
		"work": "工作",
		"meal_break": "用餐休息",
		"commute_home": "通勤回家",
		"rest": "休息",
		"free_time": "自由时间",
		"household_chores": "家务",
		"purchase_food": "购买食品",
		"purchase_essentials": "购买生活用品",
		"social_contact": "联系让娜",
		"union_activity": "工会例会",
		"overtime": "加班",
		"authorized_leave": "授权无薪请假",
		"absence": "无故缺勤",
	}
	return str(labels.get(activity_type, activity_type))


static func _activity_condition_symbol(activity: Dictionary) -> String:
	if activity.is_empty():
		return "× 无下一活动"
	return "✓ 已安排"


static func _primary_concern(condition: Dictionary) -> String:
	if int(condition.get("fatigue", 0)) >= 950:
		return "疲劳过高，必须优先恢复"
	if int(condition.get("stress", 0)) >= 600:
		return "压力较高，需要休息或关系支持"
	if int(condition.get("health", 1000)) < 700:
		return "健康需要注意"
	return "当前生活状态稳定"


static func _notification_source(category: String) -> String:
	var labels: Dictionary = {
		"personal": "个人提醒",
		"organization": "组织信息",
		"public": "公开背景新闻",
	}
	return str(labels.get(category, "个人提醒"))


static func _money(centimes: int) -> String:
	return "%d.%02d 法郎" % [centimes / 100, posmod(centimes, 100)]
