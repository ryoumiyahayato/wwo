class_name V23FormalInterface
extends V23LifeLoopInterface
## Formal-map UI extension for objective personal-finance state and commands.

const FINANCE_PANEL_ID: String = "v2_3_finance"
const FORMAL_PANEL_IDS: PackedStringArray = [
	"v2_3_travel", "v2_3_messages", "v2_3_knowledge", "v2_3_social",
	FINANCE_PANEL_ID, "v2_3_sandbox",
]


func _draw() -> void:
	super._draw()
	if data == null or panel_progress <= 0.01:
		return
	if open_panel == FINANCE_PANEL_ID:
		_draw_formal_finance_panel()


func get_panel_rect() -> Rect2:
	if open_panel == FINANCE_PANEL_ID:
		return Rect2(654.0, 86.0, 608.0, 528.0)
	return super.get_panel_rect()


func _draw_v2_3_navigation() -> void:
	var binding: V23FormalUiBinding = _formal_binding()
	if binding == null:
		super._draw_v2_3_navigation()
		return
	var person: Dictionary = binding.person_view()
	var unread: int = int(person.get("unread_message_count", 0))
	var items: Array = [
		["旅行", "v2_3_travel"],
		["消息%s" % (" %d" % unread if unread > 0 else ""), "v2_3_messages"],
		["认知", "v2_3_knowledge"],
		["关系", "v2_3_social"],
		["财务", FINANCE_PANEL_ID],
		["处境/行动", "v2_3_sandbox"],
	]
	var bar := Rect2(318.0, 52.0, 610.0, 34.0)
	_surface(bar, Color(0.025, 0.055, 0.06, 0.92), Color(GOLD, 0.24), 8)
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(
			bar.position.x + 7.0 + float(index) * 75.0,
			bar.position.y + 4.0,
			68.0,
			26.0
		)
		_compact_action(
			row, str(item[0]), open_panel == str(item[1]),
			"v2_3_open", str(item[1]), "打开正式人物面板"
		)
	var truth_rect := Rect2(bar.end.x - 116.0, bar.position.y + 4.0, 108.0, 26.0)
	_compact_action(
		truth_rect,
		"真相视图" if binding.v2_3_simulation.truth_view else "人物认知",
		binding.v2_3_simulation.truth_view,
		"v2_3_truth_toggle",
		null,
		"评审开关：普通人物视图不泄露未知地点和人物位置"
	)


func _draw_formal_finance_panel() -> void:
	var binding: V23FormalUiBinding = _formal_binding()
	if binding == null:
		return
	var view: Dictionary = binding.finance_view()
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 34.0), "个人财务与借款", 22, INK)
	_text(
		rect.position + Vector2(20.0, 59.0),
		"现金 %d 生丁 · 已知应付债务 %d 生丁" % [
			int(view.get("cash_centimes", 0)),
			int(view.get("total_debt_centimes", 0)),
		],
		10,
		GOLD
	)
	_text(
		rect.position + Vector2(20.0, 79.0),
		"当前位置：%s" % str(view.get("current_location_name", "未知地点")),
		9,
		INK_MUTED
	)
	var lenders: Array = view.get("lenders", []) as Array
	if lenders.is_empty():
		_text(rect.position + Vector2(20.0, 112.0), "当前世界中没有已知放贷方。", 10, INK_DIM)
		return
	var lender: Dictionary = lenders[0] as Dictionary
	_section_heading(rect.position + Vector2(20.0, 110.0), str(lender.get("display_name", "放贷方")))
	var accessible: bool = bool(lender.get("at_location", false))
	var open_now: bool = bool(lender.get("open_now", false))
	_text(
		rect.position + Vector2(20.0, 132.0),
		"办理地点：%s · %s" % [
			str(lender.get("location_name", "未知地点")),
			("当前可以办理" if accessible and open_now else (
				"当前不在办理地点" if not accessible else "当前没有营业"
			)),
		],
		9,
		GREEN if accessible and open_now else AMBER
	)
	var products: Array = lender.get("products", []) as Array
	for product_index: int in range(mini(2, products.size())):
		var product: Dictionary = products[product_index] as Dictionary
		var y: float = rect.position.y + 158.0 + float(product_index) * 72.0
		_text(Vector2(rect.position.x + 20.0, y), str(product.get("display_name", "")), 11, INK)
		_text(
			Vector2(rect.position.x + 20.0, y + 17.0),
			"期限 %d 日 · 年利率 %.2f%%" % [
				int(product.get("term_days", 0)),
				float(product.get("annual_rate_bp", 0)) / 100.0,
			],
			8,
			INK_MUTED
		)
		var amount_options: Array = product.get("amount_options_centimes", []) as Array
		if accessible and open_now:
			for amount_index: int in range(mini(3, amount_options.size())):
				var amount: int = int(amount_options[amount_index])
				_compact_action(
					Rect2(rect.position.x + 300.0 + float(amount_index) * 86.0, y - 8.0, 80.0, 28.0),
					"申请 %d" % amount,
					false,
					"v2_3_finance_apply",
					{"product_id": product.get("product_id", ""), "amount_centimes": amount},
					"提交申请；审查结果在时间推进后形成"
				)
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 304.0), rect.size.x - 40.0)
	var applications: Array = view.get("applications", []) as Array
	_section_heading(rect.position + Vector2(20.0, 326.0), "最近申请")
	if applications.is_empty():
		_text(rect.position + Vector2(20.0, 349.0), "没有借款申请记录。", 9, INK_DIM)
	else:
		var application: Dictionary = applications[0] as Dictionary
		var application_status: String = str(application.get("status", ""))
		_text(
			rect.position + Vector2(20.0, 349.0),
			"%s · %d 生丁 · %s" % [
				str(application.get("product_name", "")),
				int(application.get("amount_centimes", 0)),
				_application_status_label(application_status),
			],
			10,
			INK
		)
		if application_status == "submitted":
			_text(
				rect.position + Vector2(20.0, 369.0),
				"预计审查时间：%s" % str(application.get("review_due_datetime", "")),
				8,
				INK_MUTED
			)
		elif application_status == "offered":
			var terms: Dictionary = application.get("offered_terms", {}) as Dictionary
			_text(
				rect.position + Vector2(20.0, 369.0),
				"提出条件：年利率 %.2f%% · %d 日 · %s 前有效" % [
					float(terms.get("annual_rate_bp", 0)) / 100.0,
					int(terms.get("term_days", 0)),
					str(application.get("offer_expires_datetime", "")),
				],
				8,
				AMBER
			)
			_primary_action(
				Rect2(rect.end.x - 164.0, rect.position.y + 334.0, 132.0, 36.0),
				"接受借款条件",
				"v2_3_finance_accept",
				str(application.get("application_id", "")),
				"接受后形成合同并通过住户账本放款"
			)
		elif application_status == "rejected":
			var reasons: Array = application.get("decision_reasons", []) as Array
			_text(
				rect.position + Vector2(20.0, 369.0),
				"已知审查事实：%s" % ("；".join(reasons) if not reasons.is_empty() else "未说明"),
				8,
				INK_MUTED
			)
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 402.0), rect.size.x - 40.0)
	var contracts: Array = view.get("contracts", []) as Array
	_section_heading(rect.position + Vector2(20.0, 424.0), "借款合同")
	if contracts.is_empty():
		_text(rect.position + Vector2(20.0, 447.0), "没有借款合同。", 9, INK_DIM)
		return
	var contract: Dictionary = contracts[0] as Dictionary
	var outstanding: int = int(contract.get("outstanding_centimes", 0))
	_text(
		rect.position + Vector2(20.0, 447.0),
		"%s · %s · 应付 %d 生丁" % [
			str(contract.get("product_name", "")),
			_contract_status_label(str(contract.get("status", ""))),
			outstanding,
		],
		10,
		INK
	)
	_text(
		rect.position + Vector2(20.0, 468.0),
		"本金 %d · 利息 %d · 到期 %s" % [
			int(contract.get("principal_outstanding_centimes", 0)),
			int(contract.get("interest_outstanding_centimes", 0)),
			str(contract.get("due_datetime", "")),
		],
		8,
		INK_MUTED
	)
	if outstanding > 0:
		_compact_action(
			Rect2(rect.end.x - 250.0, rect.position.y + 438.0, 100.0, 30.0),
			"偿还 500",
			false,
			"v2_3_finance_repay",
			{"contract_id": contract.get("contract_id", ""), "amount_centimes": 500},
			"从现有住户现金支付，现金不足时不会执行"
		)
		_compact_action(
			Rect2(rect.end.x - 142.0, rect.position.y + 438.0, 110.0, 30.0),
			"偿还全部应付额",
			false,
			"v2_3_finance_repay",
			{"contract_id": contract.get("contract_id", ""), "amount_centimes": outstanding},
			"从现有住户现金支付，现金不足时不会执行"
		)


func _activate(action: String, payload: Variant) -> void:
	var binding: V23FormalUiBinding = _formal_binding()
	match action:
		"v2_3_finance_apply":
			var request: Dictionary = payload as Dictionary
			var result: V2LifeLoopResult = binding.apply_for_loan(
				str(request.get("product_id", "")),
				int(request.get("amount_centimes", 0))
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_finance_accept":
			var result: V2LifeLoopResult = binding.accept_loan_offer(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_finance_repay":
			var request: Dictionary = payload as Dictionary
			var result: V2LifeLoopResult = binding.repay_loan(
				str(request.get("contract_id", "")),
				int(request.get("amount_centimes", 0))
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		_:
			super._activate(action, payload)
	queue_redraw()


func debug_state() -> Dictionary:
	var state: Dictionary = super.debug_state()
	state["v2_3_panels"] = Array(FORMAL_PANEL_IDS)
	state["formal_finance_visible"] = _formal_binding() != null
	return state


func _formal_binding() -> V23FormalUiBinding:
	return life_binding as V23FormalUiBinding


static func _application_status_label(status: String) -> String:
	return {
		"submitted": "等待审查",
		"offered": "已提出条件",
		"rejected": "已拒绝",
		"expired": "条件已过期",
		"accepted": "已形成合同",
	}.get(status, status)


static func _contract_status_label(status: String) -> String:
	return {
		"active": "履行中",
		"overdue": "逾期",
		"defaulted": "违约",
		"settled": "已结清",
	}.get(status, status)
