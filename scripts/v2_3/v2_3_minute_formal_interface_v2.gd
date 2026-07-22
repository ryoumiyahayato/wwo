class_name V23MinuteFormalInterfaceV2
extends V23MinuteFormalInterface
## Final player-facing interface. Internal IDs, raw enums, review toggles and
## implementation-time explanations stay out of the normal game surface.

var _selected_contact_id: String = ""


func _draw_system_menu() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	var items: Array = [
		["保存游戏", "system_save", "保存当前进度"],
		["载入游戏", "system_load", "载入最近保存的进度"],
		["导入旧版存档", "v2_3_migrate", "保留原文件并导入旧版进度"],
	]
	if binding != null and binding.developer_mode:
		items.append(["开发工具", "open_developer", "打开独立开发诊断窗口"])
	items.append(["返回主菜单", "system_return", "退出当前世界并返回主菜单"])
	var rect := Rect2(990.0, 78.0, 272.0, 14.0 + float(items.size()) * 29.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.3), 10)
	_register(rect, "consume")
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(
			rect.position.x + 9.0,
			rect.position.y + 7.0 + float(index) * 29.0,
			rect.size.x - 18.0,
			26.0
		)
		_text(row.position + Vector2(10.0, 18.0), str(item[0]), 11, INK)
		_register(row, str(item[1]), null, str(item[2]))


func _draw_v2_3_navigation() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		return
	var person: Dictionary = binding.person_view()
	var unread: int = int(person.get("unread_message_count", 0))
	var items: Array = [
		["旅行", "v2_3_travel"],
		["消息%s" % (" %d" % unread if unread > 0 else ""), "v2_3_messages"],
		["见闻", "v2_3_knowledge"],
		["关系", "v2_3_social"],
		["财务", FINANCE_PANEL_ID],
		["行动", "v2_3_sandbox"],
	]
	var bar := Rect2(318.0, 52.0, 610.0, 34.0)
	_surface(bar, Color(0.025, 0.055, 0.06, 0.92), Color(GOLD, 0.24), 8)
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(
			bar.position.x + 7.0 + float(index) * 98.0,
			bar.position.y + 4.0,
			91.0,
			26.0
		)
		_compact_action(
			row,
			str(item[0]),
			open_panel == str(item[1]),
			"v2_3_open",
			str(item[1]),
			"打开人物信息面板"
		)


func _draw_time_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(0.0, -24.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_text(rect.position + Vector2(14.0, 25.0), "时间速度", 14, INK)
	_compact_action(
		Rect2(rect.position.x + 8.0, rect.position.y + 38.0, rect.size.x - 16.0, 28.0),
		"Ⅱ  暂停",
		paused,
		"pause",
		null,
		"暂停或继续游戏"
	)
	var labels: Array[String] = ["慢速", "正常", "快速", "很快", "最快"]
	for index: int in range(5):
		var option: int = index + 1
		_compact_action(
			Rect2(
				rect.position.x + 8.0,
				rect.position.y + 71.0 + float(index) * 31.0,
				rect.size.x - 16.0,
				28.0
			),
			labels[index],
			not paused and speed == option,
			"speed",
			option,
			"调整游戏时间流逝速度"
		)


func _draw_v2_3_messages_panel() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		return
	var mailbox: Dictionary = binding.messages_view()
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 34.0), "消息", 22, INK)
	_text(
		rect.position + Vector2(20.0, 59.0),
		"%d 封未读" % int(mailbox.get("unread_count", 0)),
		11,
		GOLD
	)
	var selected: Dictionary = mailbox.get("selected_message", {}) as Dictionary
	var inbox: Array = mailbox.get("inbox", []) as Array
	var list_width: float = 244.0
	_section_heading(rect.position + Vector2(20.0, 90.0), "收件箱")
	if inbox.is_empty():
		_text(rect.position + Vector2(20.0, 118.0), "目前没有收到消息。", 10, INK_DIM)
	for index: int in range(mini(7, inbox.size())):
		var message: Dictionary = inbox[index] as Dictionary
		var row_y: float = rect.position.y + 108.0 + float(index) * 52.0
		var row := Rect2(rect.position.x + 18.0, row_y, list_width, 44.0)
		var is_selected: bool = (
			str(selected.get("message_id", "")) == str(message.get("message_id", ""))
		)
		_surface(
			row,
			Color(GOLD, 0.10) if is_selected else Color(INK, 0.035),
			Color(GOLD, 0.42) if is_selected else Color(INK_DIM, 0.12),
			6
		)
		_text(row.position + Vector2(9.0, 18.0), str(message.get("display_title", "消息")), 10, INK)
		_text(
			row.position + Vector2(9.0, 35.0),
			"%s · %s" % [
				str(message.get("display_status", "")),
				str(message.get("display_time", "")),
			],
			8,
			GOLD if str(message.get("status", "")) == "delivered" else INK_DIM
		)
		_register(row, "message_open", str(message.get("message_id", "")), "打开这封消息")
	_divider(Vector2(rect.position.x + 280.0, rect.position.y + 88.0), rect.size.y - 120.0, true)
	if selected.is_empty():
		_text(rect.position + Vector2(304.0, 122.0), "选择一封消息查看正文。", 11, INK_DIM)
	else:
		_text(rect.position + Vector2(304.0, 104.0), str(selected.get("display_title", "消息")), 15, INK)
		_text(
			rect.position + Vector2(304.0, 130.0),
			"%s · %s" % [
				str(selected.get("display_status", "")),
				str(selected.get("display_time", "")),
			],
			9,
			GOLD
		)
		_surface(
			Rect2(rect.position.x + 296.0, rect.position.y + 154.0, 288.0, 224.0),
			Color(INK, 0.035),
			Color(INK_DIM, 0.14),
			7
		)
		_text(
			rect.position + Vector2(312.0, 184.0),
			str(selected.get("display_body", "")),
			12,
			INK,
			260.0
		)
		if bool(selected.get("can_reply", false)):
			_primary_action(
				Rect2(rect.position.x + 304.0, rect.end.y - 72.0, 132.0, 36.0),
				"回复",
				"message_reply",
				null,
				"回复当前消息"
			)
	var outbox: Array = mailbox.get("outbox", []) as Array
	_text(
		rect.position + Vector2(20.0, rect.end.y - 24.0),
		"已寄出 %d 封" % outbox.size(),
		9,
		INK_DIM
	)


func _draw_v2_3_knowledge_panel() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		return
	var records: Array[Dictionary] = binding.knowledge_view()
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 34.0), "人物见闻", 22, INK)
	_text(
		rect.position + Vector2(20.0, 59.0),
		"人物只会根据亲自经历、通信和可靠转述采取行动。",
		10,
		GOLD
	)
	if records.is_empty():
		_text(rect.position + Vector2(20.0, 104.0), "当前没有值得记录的见闻。", 11, INK_DIM)
		return
	for index: int in range(mini(8, records.size())):
		var record: Dictionary = records[index]
		var row_y: float = rect.position.y + 88.0 + float(index) * 52.0
		_surface(
			Rect2(rect.position.x + 18.0, row_y, rect.size.x - 36.0, 45.0),
			Color(INK, 0.035),
			Color(INK_DIM, 0.12),
			6
		)
		_text(
			Vector2(rect.position.x + 30.0, row_y + 19.0),
			str(record.get("display_title", "已知事实")),
			11,
			INK
		)
		_text(
			Vector2(rect.position.x + 30.0, row_y + 37.0),
			"%s · %s · %s · %s" % [
				str(record.get("display_source", "")),
				str(record.get("display_status", "")),
				str(record.get("display_confidence", "")),
				str(record.get("display_freshness", "")),
			],
			9,
			GOLD if str(record.get("display_status", "")) == "已确认" else INK_MUTED
		)


func _draw_v2_3_social_panel() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		return
	var contacts: Array[Dictionary] = binding.contact_options()
	if _selected_contact_id.is_empty() and not contacts.is_empty():
		_selected_contact_id = str(contacts[0].get("target_id", ""))
	var selected: Dictionary = {}
	for contact: Dictionary in contacts:
		if str(contact.get("target_id", "")) == _selected_contact_id:
			selected = contact
			break
	if selected.is_empty() and not contacts.is_empty():
		selected = contacts[0]
		_selected_contact_id = str(selected.get("target_id", ""))
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 34.0), "人物关系", 22, INK)
	_text(rect.position + Vector2(20.0, 59.0), "关系来自实际接触、承诺和冲突。", 10, GOLD)
	_section_heading(rect.position + Vector2(20.0, 90.0), "认识的人")
	if contacts.is_empty():
		_text(rect.position + Vector2(20.0, 119.0), "当前人物还没有可联系的人。", 11, INK_DIM)
		return
	for index: int in range(mini(5, contacts.size())):
		var contact: Dictionary = contacts[index]
		var row := Rect2(rect.position.x + 18.0, rect.position.y + 108.0 + float(index) * 42.0, 208.0, 35.0)
		var chosen: bool = str(contact.get("target_id", "")) == _selected_contact_id
		_surface(
			row,
			Color(GOLD, 0.10) if chosen else Color(INK, 0.035),
			Color(GOLD, 0.42) if chosen else Color(INK_DIM, 0.12),
			6
		)
		_text(row.position + Vector2(10.0, 16.0), str(contact.get("display_name_zh", "")), 11, INK)
		_text(row.position + Vector2(10.0, 31.0), str(contact.get("role", "")), 8, INK_MUTED)
		_register(row, "relationship_select", str(contact.get("target_id", "")), "查看这段关系")
	_divider(Vector2(rect.position.x + 246.0, rect.position.y + 88.0), rect.size.y - 120.0, true)
	_text(rect.position + Vector2(270.0, 108.0), str(selected.get("display_name_zh", "")), 17, INK)
	_text(rect.position + Vector2(270.0, 132.0), str(selected.get("role", "")), 10, GOLD)
	_text(
		rect.position + Vector2(270.0, 170.0),
		str(selected.get("relationship_summary", "")),
		11,
		INK,
		300.0
	)
	_text(
		rect.position + Vector2(270.0, 224.0),
		str(selected.get("expectation_summary", "")),
		10,
		INK_MUTED,
		300.0
	)
	_text(
		rect.position + Vector2(270.0, 267.0),
		str(selected.get("last_contact_label", "")),
		9,
		INK_DIM
	)
	_section_heading(rect.position + Vector2(270.0, 306.0), "可以做什么")
	_compact_action(
		Rect2(rect.position.x + 270.0, rect.position.y + 326.0, 132.0, 31.0),
		"写信问候",
		false,
		"v2_3_send_greeting",
		str(selected.get("target_id", "")),
		"寄出一封问候信"
	)
	_compact_action(
		Rect2(rect.position.x + 410.0, rect.position.y + 326.0, 132.0, 31.0),
		"邀请见面",
		false,
		"v2_3_invite_contact",
		str(selected.get("target_id", "")),
		"提出一次具体约见"
	)
	var introductions: Array[Dictionary] = binding.introduction_options()
	var related_options: Array[Dictionary] = []
	for option: Dictionary in introductions:
		if str(option.get("intermediary_id", "")) == str(selected.get("target_id", "")):
			related_options.append(option)
	if not related_options.is_empty():
		_section_heading(rect.position + Vector2(270.0, 390.0), "通过此人认识别人")
		for index: int in range(mini(2, related_options.size())):
			var option: Dictionary = related_options[index]
			_text_link(
				Rect2(rect.position.x + 270.0, rect.position.y + 410.0 + float(index) * 31.0, 270.0, 27.0),
				"请求介绍：%s" % str(option.get("target_name", "")),
				"introduction_request",
				{
					"intermediary_id": option.get("intermediary_id", ""),
					"target_id": option.get("target_id", ""),
				},
				"中间人可以接受或拒绝，不会立即解锁关系"
			)


func _draw_formal_finance_panel() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		return
	var view: Dictionary = binding.finance_view()
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 34.0), "个人财务", 22, INK)
	_surface(Rect2(rect.position.x + 18.0, rect.position.y + 52.0, 270.0, 64.0), Color(GOLD, 0.07), Color(GOLD, 0.28), 8)
	_surface(Rect2(rect.position.x + 300.0, rect.position.y + 52.0, 288.0, 64.0), Color(INK, 0.035), Color(INK_DIM, 0.14), 8)
	_text(rect.position + Vector2(32.0, 78.0), "现金", 10, INK_MUTED)
	_text(rect.position + Vector2(32.0, 103.0), "%d 生丁" % int(view.get("cash_centimes", 0)), 18, GOLD)
	_text(rect.position + Vector2(314.0, 78.0), "需要偿还", 10, INK_MUTED)
	_text(rect.position + Vector2(314.0, 103.0), "%d 生丁" % int(view.get("total_debt_centimes", 0)), 18, INK)
	_text(
		rect.position + Vector2(20.0, 138.0),
		"当前位置：%s" % str(view.get("current_location_name", "未知地点")),
		10,
		INK_MUTED
	)
	var lenders: Array = view.get("lenders", []) as Array
	if lenders.is_empty():
		_text(rect.position + Vector2(20.0, 180.0), "目前没有已知的借款机构。", 11, INK_DIM)
		return
	var lender: Dictionary = lenders[0] as Dictionary
	var accessible: bool = bool(lender.get("at_location", false))
	var open_now: bool = bool(lender.get("open_now", false))
	_section_heading(rect.position + Vector2(20.0, 170.0), str(lender.get("display_name", "借款机构")))
	_text(
		rect.position + Vector2(20.0, 194.0),
		"%s · %s" % [
			str(lender.get("location_name", "未知地点")),
			("现在可以办理" if accessible and open_now else ("需要先到办理地点" if not accessible else "目前没有营业")),
		],
		10,
		GREEN if accessible and open_now else AMBER
	)
	var products: Array = lender.get("products", []) as Array
	for product_index: int in range(mini(2, products.size())):
		var product: Dictionary = products[product_index] as Dictionary
		var card_y: float = rect.position.y + 215.0 + float(product_index) * 105.0
		_surface(Rect2(rect.position.x + 18.0, card_y, rect.size.x - 36.0, 96.0), Color(INK, 0.035), Color(INK_DIM, 0.14), 7)
		_text(Vector2(rect.position.x + 30.0, card_y + 24.0), str(product.get("display_name", "")), 13, INK)
		_text(
			Vector2(rect.position.x + 30.0, card_y + 48.0),
			"期限 %d 日 · 年利率 %.2f%%" % [
				int(product.get("term_days", 0)),
				float(product.get("annual_rate_bp", 0)) / 100.0,
			],
			10,
			INK_MUTED
		)
		var amounts: Array = product.get("amount_options_centimes", []) as Array
		if accessible and open_now:
			for amount_index: int in range(mini(3, amounts.size())):
				var amount: int = int(amounts[amount_index])
				_compact_action(
					Rect2(rect.position.x + 300.0 + float(amount_index) * 88.0, card_y + 52.0, 80.0, 29.0),
					"借 %d" % amount,
					false,
					"v2_3_finance_apply",
					{"product_id": product.get("product_id", ""), "amount_centimes": amount},
					"提交申请，审查后才会形成借款"
				)
	var applications: Array = view.get("applications", []) as Array
	var contracts: Array = view.get("contracts", []) as Array
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 432.0), rect.size.x - 40.0)
	if not contracts.is_empty():
		var contract: Dictionary = contracts[0] as Dictionary
		var outstanding: int = int(contract.get("outstanding_centimes", 0))
		_text(rect.position + Vector2(20.0, 458.0), "%s · 尚需偿还 %d 生丁" % [str(contract.get("product_name", "借款")), outstanding], 11, INK)
		_text(rect.position + Vector2(20.0, 480.0), "到期：%s" % str(contract.get("due_datetime", "")), 9, INK_MUTED)
		if outstanding > 0:
			_compact_action(Rect2(rect.end.x - 250.0, rect.position.y + 447.0, 100.0, 31.0), "偿还 500", false, "v2_3_finance_repay", {"contract_id": contract.get("contract_id", ""), "amount_centimes": 500}, "从现有现金偿还")
			_compact_action(Rect2(rect.end.x - 142.0, rect.position.y + 447.0, 110.0, 31.0), "全部偿还", false, "v2_3_finance_repay", {"contract_id": contract.get("contract_id", ""), "amount_centimes": outstanding}, "现金足够时结清")
	elif not applications.is_empty():
		var application: Dictionary = applications[0] as Dictionary
		_text(rect.position + Vector2(20.0, 458.0), "%s · %s" % [str(application.get("product_name", "借款申请")), _application_status_label(str(application.get("status", "")))], 11, INK)
		_text(rect.position + Vector2(20.0, 480.0), "申请金额：%d 生丁" % int(application.get("amount_centimes", 0)), 9, INK_MUTED)
		if str(application.get("status", "")) == "offered":
			_primary_action(Rect2(rect.end.x - 176.0, rect.position.y + 448.0, 144.0, 36.0), "接受借款条件", "v2_3_finance_accept", str(application.get("application_id", "")), "接受后才会放款")
	else:
		_text(rect.position + Vector2(20.0, 466.0), "目前没有申请或借款合同。", 10, INK_DIM)


func _draw_v2_3_sandbox_panel() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		return
	var view: Dictionary = binding.sandbox_view()
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 34.0), "当前处境", 22, INK)
	var goals: Array = view.get("goals", []) as Array
	var selected_goal_id: String = str(view.get("selected_goal_id", ""))
	if goals.is_empty():
		_text(rect.position + Vector2(20.0, 78.0), "目前没有需要主动处理的处境。", 11, INK_DIM)
		return
	_section_heading(rect.position + Vector2(20.0, 70.0), "需要关注什么")
	for index: int in range(mini(4, goals.size())):
		var goal: Dictionary = goals[index] as Dictionary
		var row := Rect2(rect.position.x + 18.0, rect.position.y + 89.0 + float(index) * 54.0, 250.0, 47.0)
		var selected: bool = selected_goal_id == str(goal.get("goal_id", ""))
		_surface(row, Color(GOLD, 0.10) if selected else Color(INK, 0.035), Color(GOLD, 0.42) if selected else Color(INK_DIM, 0.12), 6)
		_text(row.position + Vector2(10.0, 19.0), str(goal.get("title_zh", "处境")), 11, INK)
		_text(row.position + Vector2(10.0, 38.0), str(goal.get("urgency_label", "")), 8, AMBER)
		_register(row, "sandbox_plan_goal", str(goal.get("goal_id", "")), str(goal.get("player_summary", "")))
	var selected_goal: Dictionary = {}
	for goal: Dictionary in goals:
		if str(goal.get("goal_id", "")) == selected_goal_id:
			selected_goal = goal
			break
	_divider(Vector2(rect.position.x + 286.0, rect.position.y + 68.0), 316.0, true)
	_text(rect.position + Vector2(310.0, 86.0), str(selected_goal.get("title_zh", "")), 16, INK)
	_text(rect.position + Vector2(310.0, 116.0), str(selected_goal.get("player_summary", "")), 10, INK_MUTED, 270.0)
	_section_heading(rect.position + Vector2(310.0, 164.0), "准备怎样处理")
	var methods: Array = view.get("methods", []) as Array
	var selected_method_id: String = str(view.get("selected_method_id", ""))
	for index: int in range(mini(5, methods.size())):
		var method: Dictionary = methods[index] as Dictionary
		var row_y: float = rect.position.y + 184.0 + float(index) * 46.0
		var chosen: bool = selected_method_id == str(method.get("method_id", ""))
		_surface(Rect2(rect.position.x + 304.0, row_y, 282.0, 39.0), Color(GOLD, 0.10) if chosen else Color(INK, 0.035), Color(GOLD, 0.42) if chosen else Color(INK_DIM, 0.12), 6)
		_text(Vector2(rect.position.x + 314.0, row_y + 17.0), str(method.get("label_zh", "")) + (" · 风险较高" if bool(method.get("illegal", false)) else ""), 10, INK)
		_text(Vector2(rect.position.x + 314.0, row_y + 33.0), str(method.get("player_explanation", "")), 8, INK_MUTED, 258.0)
		_register(Rect2(rect.position.x + 304.0, row_y, 282.0, 39.0), "sandbox_plan_method", str(method.get("method_id", "")), str(method.get("preparation_hint", "")))
	var targets: Array = view.get("targets", []) as Array
	var selected_target_id: String = str(view.get("selected_target_id", ""))
	var controls_y: float = rect.position.y + 324.0
	if not targets.is_empty():
		_section_heading(rect.position + Vector2(20.0, 324.0), "涉及谁")
		for index: int in range(mini(3, targets.size())):
			var target: Dictionary = targets[index] as Dictionary
			_compact_action(Rect2(rect.position.x + 18.0, rect.position.y + 344.0 + float(index) * 32.0, 250.0, 27.0), "%s · %s" % [str(target.get("display_name", "")), str(target.get("role", ""))], selected_target_id == str(target.get("person_id", "")), "sandbox_plan_target", str(target.get("person_id", "")), "选择具体行动对象")
		controls_y = rect.position.y + 448.0
	_section_heading(Vector2(rect.position.x + 20.0, controls_y), "时间与准备")
	_text(Vector2(rect.position.x + 20.0, controls_y + 26.0), str(view.get("selected_start_datetime", "")), 10, INK)
	_compact_action(Rect2(rect.position.x + 190.0, controls_y + 8.0, 70.0, 28.0), "提前", false, "sandbox_plan_time", -1, "将计划提前一小时")
	_compact_action(Rect2(rect.position.x + 266.0, controls_y + 8.0, 70.0, 28.0), "推后", false, "sandbox_plan_time", 1, "将计划推后一小时")
	var prep_values: Array[int] = [150, 400, 700]
	var prep_labels: Array[String] = ["直接行动", "确认条件", "充分准备"]
	for index: int in range(3):
		_compact_action(Rect2(rect.position.x + 350.0 + float(index) * 78.0, controls_y + 8.0, 72.0, 28.0), prep_labels[index], int(view.get("preparation", 400)) == prep_values[index], "sandbox_plan_preparation", prep_values[index], "准备会改变成本、时间和成功机会，但不会保证结果")
	var preview: Dictionary = view.get("preview", {}) as Dictionary
	var preview_data: Dictionary = preview.get("data", {}) as Dictionary
	if bool(preview.get("success", false)):
		_text(rect.position + Vector2(20.0, rect.end.y - 48.0), "%s · %s · %d小时" % [str(preview_data.get("location_name", "地点待定")), str(preview_data.get("start_datetime", "")), int(preview_data.get("duration_hours", 0))], 9, GREEN)
		_primary_action(Rect2(rect.end.x - 166.0, rect.end.y - 61.0, 142.0, 37.0), "建立计划", "sandbox_plan_confirm", null, "建立实际日程、行程和社会行动")
	else:
		_text(rect.position + Vector2(20.0, rect.end.y - 43.0), str(preview.get("message", "请选择完整的应对方式。")), 9, AMBER)


func _activate(action: String, payload: Variant) -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	var result: V2LifeLoopResult
	match action:
		"message_open":
			result = binding.open_message(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"message_reply":
			result = binding.reply_selected_message()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"relationship_select":
			_selected_contact_id = str(payload)
		"introduction_request":
			var request: Dictionary = payload as Dictionary
			result = binding.request_introduction_option(str(request.get("intermediary_id", "")), str(request.get("target_id", "")))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_goal":
			result = binding.select_sandbox_goal(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_method":
			result = binding.select_sandbox_method(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_target":
			result = binding.select_sandbox_target(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_time":
			result = binding.shift_sandbox_start(int(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_preparation":
			result = binding.set_sandbox_preparation(int(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_confirm":
			result = binding.submit_selected_sandbox_plan()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		_:
			super._activate(action, payload)
	queue_redraw()


func _planning_binding() -> V23ControlledUiBindingV2:
	return life_binding as V23ControlledUiBindingV2
