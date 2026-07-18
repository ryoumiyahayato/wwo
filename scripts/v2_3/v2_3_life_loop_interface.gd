class_name V23LifeLoopInterface
extends V2LifeLoopInterfaceFinal
## V2.3 panels layered over the retained four-corner world-map interface.

const V2_3_MENU_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_menu.tscn"
const V2_3_PANEL_IDS: PackedStringArray = [
	"v2_3_travel", "v2_3_messages", "v2_3_knowledge", "v2_3_social",
]


func _draw() -> void:
	super._draw()
	if data == null:
		return
	_draw_v2_3_navigation()
	if panel_progress <= 0.01:
		return
	match open_panel:
		"v2_3_travel":
			_draw_v2_3_travel_panel()
		"v2_3_messages":
			_draw_v2_3_messages_panel()
		"v2_3_knowledge":
			_draw_v2_3_knowledge_panel()
		"v2_3_social":
			_draw_v2_3_social_panel()


func get_panel_rect() -> Rect2:
	if open_panel in V2_3_PANEL_IDS:
		return Rect2(654.0, 86.0, 608.0, 528.0)
	return super.get_panel_rect()


func _draw_system_menu() -> void:
	var items: Array = [
		["保存 V2.3 进度", "system_save", "原子写入并保留上一份有效备份"],
		["载入 V2.3 进度", "system_load", "校验后恢复正式 V2.3 状态"],
		["迁移 V2.2 存档", "v2_3_migrate", "原文件保持不变，生成并载入 V2.3 存档"],
		["开发者工具", "open_developer", "时间、结算与真相视图工具"],
		["返回 V2.3 菜单", "system_return", "返回空间与认知闭环菜单"],
	]
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
	var binding: V23LifeLoopUiBinding = _v2_3_binding()
	if binding == null:
		return
	var person: Dictionary = binding.person_view()
	var unread: int = int(person.get("unread_message_count", 0))
	var items: Array = [
		["旅行", "v2_3_travel"],
		["消息%s" % (" %d" % unread if unread > 0 else ""), "v2_3_messages"],
		["认知", "v2_3_knowledge"],
		["关系", "v2_3_social"],
	]
	var bar := Rect2(376.0, 52.0, 494.0, 34.0)
	_surface(bar, Color(0.025, 0.055, 0.06, 0.92), Color(GOLD, 0.24), 8)
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(
			bar.position.x + 7.0 + float(index) * 91.0,
			bar.position.y + 4.0,
			84.0,
			26.0
		)
		_compact_action(
			row, str(item[0]), open_panel == str(item[1]),
			"v2_3_open", str(item[1]), "打开 V2.3 正式面板"
		)
	var truth_rect := Rect2(bar.end.x - 116.0, bar.position.y + 4.0, 108.0, 26.0)
	_compact_action(
		truth_rect,
		"真相视图" if binding.v2_3_simulation.truth_view else "人物认知",
		binding.v2_3_simulation.truth_view,
		"v2_3_truth_toggle",
		null,
		"评审开关：普通人物视图不会泄露未知地点和人物位置"
	)


func _draw_v2_3_travel_panel() -> void:
	var binding: V23LifeLoopUiBinding = _v2_3_binding()
	if binding == null:
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var person: Dictionary = binding.person_view()
	_text(rect.position + Vector2(20.0, 34.0), "地点与旅行", 22, INK)
	_text(
		rect.position + Vector2(20.0, 58.0),
		"当前位置：%s · %s" % [
			str(person.get("current_location", "未知地点")),
			_location_state_label(str(person.get("location_state", ""))),
		],
		10,
		GOLD
	)
	if not str(person.get("expected_arrival_datetime", "")).is_empty():
		_text(
			rect.position + Vector2(20.0, 78.0),
			"前往 %s · 预计 %s 到达 · %d 生丁" % [
				str(person.get("travel_destination", "")),
				str(person.get("expected_arrival_datetime", "")),
				int(person.get("travel_cost_centimes", 0)),
			],
			9,
			AMBER
		)
	_section_heading(rect.position + Vector2(20.0, 106.0), "已知目的地")
	var destinations: Array[Dictionary] = binding.travel_destination_options()
	for index: int in range(mini(9, destinations.size())):
		var destination: Dictionary = destinations[index]
		var row_y: float = rect.position.y + 126.0 + float(index) * 31.0
		var row := Rect2(rect.position.x + 20.0, row_y, 360.0, 26.0)
		_text(
			row.position + Vector2(9.0, 18.0),
			str(destination.get("display_name", "")),
			10,
			INK
		)
		_register(
			row, "v2_3_preview_route",
			{"destination_id": destination.get("location_id", ""), "preference": "fastest"},
			"预览确定性的最快路线"
		)
		_compact_action(
			Rect2(rect.position.x + 396.0, row_y, 82.0, 26.0),
			"最快", false, "v2_3_preview_route",
			{"destination_id": destination.get("location_id", ""), "preference": "fastest"},
			"以到达时间、成本、稳定路径键依次决胜"
		)
		_compact_action(
			Rect2(rect.position.x + 486.0, row_y, 82.0, 26.0),
			"最省", false, "v2_3_preview_route",
			{"destination_id": destination.get("location_id", ""), "preference": "cheapest"},
			"以成本、到达时间、稳定路径键依次决胜"
		)
	var preview: Dictionary = binding.route_preview
	if preview.is_empty():
		_text(
			rect.position + Vector2(20.0, rect.end.y - 60.0),
			"选择目的地后才会生成路线；未知地点不会出现在列表中。",
			9,
			INK_DIM
		)
		return
	_surface(
		Rect2(rect.position.x + 20.0, rect.end.y - 98.0, 548.0, 70.0),
		Color(GOLD, 0.055),
		Color(GOLD, 0.24),
		7
	)
	_text(
		Vector2(rect.position.x + 32.0, rect.end.y - 73.0),
		"路线：%d 小时 · %d 生丁 · %s" % [
			int(preview.get("total_duration_hours", 0)),
			int(preview.get("total_cost_centimes", 0)),
			" / ".join(preview.get("transport_modes", []) as Array),
		],
		10,
		INK
	)
	_text(
		Vector2(rect.position.x + 32.0, rect.end.y - 50.0),
		"%s → %s" % [
			str(preview.get("departure_datetime", "")),
			str(preview.get("arrival_datetime", "")),
		],
		9,
		INK_MUTED
	)
	_primary_action(
		Rect2(rect.end.x - 164.0, rect.end.y - 86.0, 132.0, 38.0),
		"确认出发",
		"v2_3_travel_confirm",
		null,
		"在现有日程中原子预留等待与逐段旅行"
	)


func _draw_v2_3_messages_panel() -> void:
	var binding: V23LifeLoopUiBinding = _v2_3_binding()
	if binding == null:
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var mailbox: Dictionary = binding.messages_view()
	_text(rect.position + Vector2(20.0, 34.0), "消息与通信", 22, INK)
	_text(
		rect.position + Vector2(20.0, 58.0),
		"未读 %d · 投递与阅读分离 · 本地信件按地址延迟" % int(
			mailbox.get("unread_count", 0)
		),
		10,
		GOLD
	)
	_section_heading(rect.position + Vector2(20.0, 91.0), "收件箱")
	var inbox: Array = mailbox.get("inbox", []) as Array
	for index: int in range(mini(8, inbox.size())):
		var message: Dictionary = inbox[index] as Dictionary
		var row_y: float = rect.position.y + 112.0 + float(index) * 43.0
		_text(
			Vector2(rect.position.x + 20.0, row_y + 15.0),
			"%s · %s" % [
				str(message.get("sender_name", "")),
				_message_type_label(str(message.get("content_type", ""))),
			],
			10,
			INK
		)
		_text(
			Vector2(rect.position.x + 20.0, row_y + 32.0),
			"%s · %s" % [
				str(message.get("status", "")),
				str(message.get("expected_delivery_datetime", "")),
			],
			8,
			INK_DIM
		)
		if str(message.get("status", "")) == "delivered":
			_primary_action(
				Rect2(rect.end.x - 124.0, row_y + 5.0, 92.0, 28.0),
				"阅读",
				"v2_3_read_message",
				str(message.get("message_id", "")),
				"只有实际阅读后，消息内容才进入人物认知"
			)
	_divider(Vector2(rect.position.x + 20.0, rect.end.y - 92.0), rect.size.x - 40.0)
	var outbox: Array = mailbox.get("outbox", []) as Array
	_text(
		rect.position + Vector2(20.0, rect.end.y - 64.0),
		"发件箱 %d 封 · 最近状态：%s" % [
			outbox.size(),
			"无" if outbox.is_empty() else str(
				(outbox.back() as Dictionary).get("status", "")
			),
		],
		10,
		INK_MUTED
	)


func _draw_v2_3_knowledge_panel() -> void:
	var binding: V23LifeLoopUiBinding = _v2_3_binding()
	if binding == null:
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var records: Array[Dictionary] = binding.knowledge_view()
	_text(rect.position + Vector2(20.0, 34.0), "人物认知", 22, INK)
	_text(
		rect.position + Vector2(20.0, 58.0),
		"共 %d 条 · 来源、置信度、新鲜度与矛盾状态均独立保存" % records.size(),
		10,
		GOLD
	)
	for index: int in range(mini(11, records.size())):
		var record: Dictionary = records[index]
		var row_y: float = rect.position.y + 90.0 + float(index) * 36.0
		_text(
			Vector2(rect.position.x + 20.0, row_y),
			"%s · %s" % [
				str(record.get("fact_type", "")),
				str(record.get("subject_id", "")),
			],
			9,
			INK
		)
		_text(
			Vector2(rect.position.x + 330.0, row_y),
			"%s / %s / %d" % [
				str(record.get("status", "")),
				str(record.get("freshness", "")),
				int(record.get("confidence", 0)),
			],
			9,
			GOLD if str(record.get("status", "")) == "confirmed" else INK_MUTED
		)
		_text(
			Vector2(rect.position.x + 20.0, row_y + 17.0),
			"来源 %s · %s" % [
				str(record.get("source_kind", "")),
				str(record.get("acquired_datetime", "")),
			],
			8,
			INK_DIM
		)


func _draw_v2_3_social_panel() -> void:
	var binding: V23LifeLoopUiBinding = _v2_3_binding()
	if binding == null:
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var contacts: Array[Dictionary] = binding.contact_options()
	_text(rect.position + Vector2(20.0, 34.0), "动态关系与约见", 22, INK)
	_text(
		rect.position + Vector2(20.0, 58.0),
		"关系变化只来自已结算互动；联系、介绍和约见均受认知约束。",
		10,
		GOLD
	)
	for index: int in range(mini(3, contacts.size())):
		var contact: Dictionary = contacts[index]
		var row_y: float = rect.position.y + 92.0 + float(index) * 120.0
		_text(
			Vector2(rect.position.x + 20.0, row_y),
			str(contact.get("display_name_zh", "")),
			13,
			INK
		)
		_text(
			Vector2(rect.position.x + 20.0, row_y + 23.0),
			"熟悉 %d  信任 %d  亲近 %d" % [
				int(contact.get("familiarity", 0)),
				int(contact.get("trust", 0)),
				int(contact.get("affinity", 0)),
			],
			9,
			GREEN
		)
		_text(
			Vector2(rect.position.x + 20.0, row_y + 43.0),
			"紧张 %d  义务 %d  互惠 %d" % [
				int(contact.get("tension", 0)),
				int(contact.get("obligation", 0)),
				int(contact.get("reciprocity", 0)),
			],
			9,
			AMBER
		)
		_compact_action(
			Rect2(rect.position.x + 20.0, row_y + 63.0, 128.0, 28.0),
			"写信问候",
			false,
			"v2_3_send_greeting",
			str(contact.get("target_id", "")),
			"写信、邮资、投递与阅读均正式结算"
		)
		_compact_action(
			Rect2(rect.position.x + 156.0, row_y + 63.0, 128.0, 28.0),
			"邀请约见",
			false,
			"v2_3_invite_contact",
			str(contact.get("target_id", "")),
			"向公共广场的下一晚约见发送邀请"
		)
	var introductions: Array[Dictionary] = binding.introduction_options()
	_divider(Vector2(rect.position.x + 20.0, rect.end.y - 82.0), rect.size.x - 40.0)
	if introductions.is_empty():
		_text(
			rect.position + Vector2(20.0, rect.end.y - 51.0),
			"当前没有可用中间人介绍链。",
			9,
			INK_DIM
		)
	else:
		var option: Dictionary = introductions[0]
		_primary_action(
			Rect2(rect.position.x + 20.0, rect.end.y - 64.0, 220.0, 34.0),
			"请 %s 介绍 %s" % [
				str(option.get("intermediary_name", "")),
				str(option.get("target_name", "")),
			],
			"v2_3_request_introduction",
			null,
			"必须等待中间人阅读、决定、回信，再由请求者阅读后解锁"
		)


func _activate(action: String, payload: Variant) -> void:
	var binding: V23LifeLoopUiBinding = _v2_3_binding()
	match action:
		"v2_3_open":
			open_panel_named(str(payload))
		"v2_3_preview_route":
			var request: Dictionary = payload as Dictionary
			var result: V2LifeLoopResult = binding.preview_travel(
				str(request.get("destination_id", "")),
				str(request.get("preference", "fastest"))
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_travel_confirm":
			var result: V2LifeLoopResult = binding.submit_travel()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_read_message":
			var result: V2LifeLoopResult = binding.read_message(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_send_greeting":
			var result: V2LifeLoopResult = binding.send_greeting(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_invite_contact":
			var result: V2LifeLoopResult = binding.invite_contact(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_request_introduction":
			var result: V2LifeLoopResult = binding.request_first_introduction()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_truth_toggle":
			var result: V2LifeLoopResult = binding.set_truth_view(
				not binding.v2_3_simulation.truth_view
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"v2_3_migrate":
			system_menu_open = false
			var result: V2LifeLoopResult = binding.migrate_v2_2_review()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"system_return":
			system_menu_open = false
			var error: Error = get_tree().change_scene_to_file(V2_3_MENU_SCENE)
			if error != OK:
				_show_toast("× 无法返回 V2.3 菜单：%s" % error_string(error))
		_:
			super._activate(action, payload)
	queue_redraw()


func debug_state() -> Dictionary:
	var state: Dictionary = super.debug_state()
	state["v2_3_panels"] = Array(V2_3_PANEL_IDS)
	state["v2_3_navigation_visible"] = _v2_3_binding() != null
	state["v2_3_truth_view_visible"] = true
	state["v2_menu_scene"] = V2_3_MENU_SCENE
	return state


func _v2_3_binding() -> V23LifeLoopUiBinding:
	return life_binding as V23LifeLoopUiBinding


static func _location_state_label(state: String) -> String:
	match state:
		"at_location":
			return "在地点"
		"waiting":
			return "等待交通"
		"in_transit":
			return "途中"
		"interrupted":
			return "旅程中断"
	return state


static func _message_type_label(content_type: String) -> String:
	match content_type:
		"greeting":
			return "问候"
		"appointment_invitation":
			return "约见邀请"
		"appointment_acceptance":
			return "约见接受"
		"appointment_rejection":
			return "约见拒绝"
		"introduction_request":
			return "介绍请求"
		"introduction":
			return "正式介绍"
	return content_type
