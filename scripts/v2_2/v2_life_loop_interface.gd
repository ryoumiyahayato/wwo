class_name V2LifeLoopInterface
extends PrototypeV2Interface
## V2.2.1 UI polish: compact schedule editor, data-driven relationship contacts,
## and a bounded system menu.


func _draw_system_menu() -> void:
	var live: bool = life_binding != null
	var items: Array = [
		["保存", "system_save", "原型不会写入存档"],
		["设置", "system_settings", "静态设置入口占位"],
		["返回主菜单", "system_return", "返回项目主菜单"],
	]
	if live:
		items = [
			["保存进度", "system_save", "保存到 V2.2 固定评审槽"],
			["载入最近存档", "system_load", "验证后事务式恢复最近评审存档"],
			["设置", "system_settings", "设置入口占位"],
			["返回主菜单", "system_return", "返回项目主菜单"],
		]
		if review_mode or life_binding.developer_mode:
			items.insert(
				3,
				["开发者工具", "open_developer", "打开权威时间、账本与结算工具"]
			)
	var rect := Rect2(1018.0, 78.0, 244.0, 18.0 + float(items.size()) * 29.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.3), 10)
	_register(rect, "consume")
	_text(rect.position + Vector2(14.0, 23.0), "系统工具", 12, INK_MUTED)
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(
			rect.position.x + 9.0,
			rect.position.y + 34.0 + float(index) * 29.0,
			rect.size.x - 18.0,
			26.0
		)
		_text(row.position + Vector2(10.0, 18.0), str(item[0]), 11, INK)
		_register(row, str(item[1]), null, str(item[2]))


func _draw_schedule_panel() -> void:
	var binding: V2LifeLoopUiBindingPolish = _polish_binding()
	if binding == null:
		super._draw_schedule_panel()
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var person: Dictionary = _identity_data()
	_text(rect.position + Vector2(20.0, 34.0), "安排活动", 22, INK)
	_text(
		rect.position + Vector2(20.0, 57.0),
		"%s · 打开时自动暂停，关闭后恢复原速度" % str(
			person.get("display_name_zh", "")
		),
		10,
		INK_MUTED
	)
	_section_heading(rect.position + Vector2(20.0, 82.0), "今日连续日程")
	var timeline: Array[Dictionary] = binding.today_schedule()
	var y: float = rect.position.y + 108.0
	for index: int in range(mini(6, timeline.size())):
		var segment: Dictionary = timeline[index]
		var start_value: Dictionary = V2DateTime.from_total_hour(
			int(segment.get("start_hour", 0))
		)
		var end_value: Dictionary = V2DateTime.from_total_hour(
			int(segment.get("end_hour", 0))
		)
		var source: String = str(segment.get("source", "default_routine"))
		var status: String = str(segment.get("display_status", "planned"))
		_text(
			Vector2(rect.position.x + 20.0, y),
			"%02d:00—%02d:00" % [
				int(start_value.get("hour", 0)), int(end_value.get("hour", 0)),
			],
			9,
			INK_DIM
		)
		_text(
			Vector2(rect.position.x + 105.0, y),
			"%s · %s · %s" % [
				_schedule_activity_label(segment, binding),
				_source_label(source),
				_schedule_status_label(status),
			],
			9,
			INK if status != "completed" else INK_MUTED
		)
		if source == "player" and status == "planned":
			_register(
				Rect2(rect.position.x + 16.0, y - 15.0, rect.size.x - 32.0, 18.0),
				"schedule_cancel_activity",
				str(segment.get("activity_id", "")),
				"点击取消尚未开始的玩家活动"
			)
		y += 19.0

	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 226.0), rect.size.x - 40.0)
	_section_heading(Vector2(rect.position.x + 20.0, rect.position.y + 246.0), "选择活动")
	var actions: Array[Dictionary] = [
		{"label":"购买食品", "type":"purchase_food", "tip":"1小时 · 560生丁 · +7人日"},
		{"label":"购买用品", "type":"purchase_essentials", "tip":"1小时 · 140生丁 · +7人日"},
		{"label":"休息", "type":"rest", "tip":"1小时 · 恢复疲劳与压力"},
		{"label":"睡眠", "type":"sleep", "tip":"8小时 · 优先恢复"},
		{"label":"加班", "type":"overtime", "tip":"17:00后 · 最多2小时"},
		{"label":"上午请假", "type":"authorized_leave", "tip":"Demo：无薪自动批准"},
		{"label":"工会例会", "type":"union_activity", "tip":"星期三19:00—21:00"},
	]
	var contacts: Array[Dictionary] = binding.contact_options()
	for contact: Dictionary in contacts:
		actions.append({
			"label": "联系%s" % str(contact.get("display_name_zh", "关系人物")),
			"type": "social_contact",
			"target_id": str(contact.get("target_id", "")),
			"tip": "18:00—21:00 · 24小时冷却",
		})
	if contacts.is_empty():
		actions.append({
			"label": "暂无联系人", "type": "", "tip": "当前人物没有可联系的关系人物",
		})
	for index: int in range(mini(actions.size(), 8)):
		var item: Dictionary = actions[index]
		var column: int = index % 4
		var row_index: int = index / 4
		var row := Rect2(
			rect.position.x + 20.0 + float(column) * 128.0,
			rect.position.y + 264.0 + float(row_index) * 31.0,
			120.0,
			25.0
		)
		var activity_type: String = str(item.get("type", ""))
		var target_id: String = str(item.get("target_id", ""))
		var selected: bool = (
			str(schedule_form.get("activity_type", "")) == activity_type
			and (
				activity_type != "social_contact"
				or str(schedule_form.get("related_entity_id", "")) == target_id
			)
		)
		if activity_type.is_empty():
			_surface(row, Color(INK_DIM, 0.06), Color(INK_DIM, 0.18), 5)
			_text(row.position + Vector2(10.0, 17.0), str(item.get("label", "")), 10, INK_DIM)
			_register(row, "consume", null, str(item.get("tip", "")))
		elif activity_type == "social_contact":
			_compact_action(
				row, str(item.get("label", "")), selected,
				"schedule_contact", target_id, str(item.get("tip", ""))
			)
		else:
			_compact_action(
				row, str(item.get("label", "")), selected,
				"schedule_activity", activity_type, str(item.get("tip", ""))
			)

	if schedule_form.is_empty():
		_text(
			rect.position + Vector2(20.0, 352.0),
			"选择一项活动后，在同一时间框内调整开始、结束与持续时长。",
			9,
			INK_DIM
		)
		return

	var start_hour: int = int(schedule_form.get("start_hour", 0))
	var duration: int = int(schedule_form.get("duration_hours", 1))
	var activity_type: String = str(schedule_form.get("activity_type", ""))
	var activity_label: String = _schedule_form_label(schedule_form, binding)
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 330.0), rect.size.x - 40.0)
	_text(rect.position + Vector2(20.0, 353.0), activity_label, 11, INK)
	_text(
		rect.position + Vector2(20.0, 374.0),
		"地点：%s · 现金：%d 生丁 · %s" % [
			binding.simulation.config.location_name(
				str(schedule_form.get("location_id", ""))
			),
			int(schedule_form.get("required_cash_centimes", 0)),
			str(schedule_form.get("expected_effects", "")),
		],
		8,
		INK_MUTED
	)

	var time_box := Rect2(rect.position.x + 20.0, rect.position.y + 392.0, rect.size.x - 40.0, 82.0)
	_surface(time_box, Color(GOLD, 0.055), Color(GOLD, 0.24), 7)
	_text(time_box.position + Vector2(12.0, 21.0), "开始", 9, INK_DIM)
	_text(
		time_box.position + Vector2(52.0, 21.0),
		V2DateTime.display_from_total_hour(start_hour), 9, INK
	)
	_text(time_box.position + Vector2(270.0, 21.0), "结束", 9, INK_DIM)
	_text(
		time_box.position + Vector2(310.0, 21.0),
		V2DateTime.display_from_total_hour(start_hour + duration), 9, INK
	)
	var controls: Array = [
		["日−", -24], ["日+", 24], ["时−", -1], ["时+", 1],
		["时长−", -1001], ["时长+", 1001],
	]
	for index: int in range(controls.size()):
		var control: Array = controls[index] as Array
		_compact_action(
			Rect2(
				time_box.position.x + 12.0 + float(index) * 81.0,
				time_box.position.y + 42.0,
				74.0,
				26.0
			),
			str(control[0]), false, "schedule_adjust", int(control[1]),
			"所有调整仍由权威层检查营业时间、关系、工作义务与冲突"
		)
	_text(
		time_box.position + Vector2(420.0, 21.0), "%d小时" % duration, 9, GOLD
	)

	_primary_action(
		Rect2(rect.position.x + 20.0, rect.position.y + 482.0, 160.0, 30.0),
		"确认安排", "schedule_confirm", null, "提交到正式日程服务"
	)
	_text_link(
		Rect2(rect.position.x + 194.0, rect.position.y + 484.0, 82.0, 26.0),
		"取消编辑", "schedule_cancel_edit", null, "放弃尚未提交的编辑"
	)
	if not binding.last_command_result.success:
		_text(
			rect.position + Vector2(292.0, 502.0),
			"× %s" % binding.last_command_result.user_message,
			8,
			RED
		)
	elif activity_type in ["authorized_leave", "absence"]:
		_text(
			rect.position + Vector2(292.0, 502.0),
			"将替换对应合同工作义务",
			8,
			AMBER
		)


func _draw_relationships(rect: Rect2) -> void:
	var binding: V2LifeLoopUiBindingPolish = _polish_binding()
	if binding == null:
		super._draw_relationships(rect)
		return
	var contacts: Array[Dictionary] = binding.contact_options()
	_section_heading(rect.position + Vector2(0.0, 15.0), "关系人物")
	if contacts.is_empty():
		_text(rect.position + Vector2(0.0, 48.0), "当前人物没有可用的关系行动", 10, INK_MUTED)
		_text(rect.position + Vector2(0.0, 72.0), "联系人只来自当前人物真实认识的关系记录。", 9, INK_DIM)
		return
	for index: int in range(mini(contacts.size(), 3)):
		var contact: Dictionary = contacts[index]
		var row_y: float = rect.position.y + 36.0 + float(index) * 112.0
		var target_name: String = str(contact.get("display_name_zh", "关系人物"))
		_text(Vector2(rect.position.x, row_y), target_name, 13, INK)
		var native_name: String = str(contact.get("native_name", ""))
		if not native_name.is_empty():
			_text(Vector2(rect.position.x, row_y + 18.0), native_name, 9, INK_MUTED)
		_text(
			Vector2(rect.position.x, row_y + 42.0),
			"熟悉度 %d · 信任 %d" % [
				int(contact.get("familiarity", 0)), int(contact.get("trust", 0)),
			],
			10,
			GOLD
		)
		var last_contact: String = str(contact.get("last_contact_datetime", ""))
		_text(
			Vector2(rect.position.x, row_y + 62.0),
			"最近联系：%s" % ("尚未联系" if last_contact.is_empty() else last_contact),
			8,
			INK_DIM
		)
		_primary_action(
			Rect2(rect.position.x, row_y + 72.0, 150.0, 28.0),
			"联系%s" % target_name,
			"schedule_contact",
			str(contact.get("target_id", "")),
			"耗时1小时；熟悉度+5、信任+2、压力-20"
		)


func _activate(action: String, payload: Variant) -> void:
	var binding: V2LifeLoopUiBindingPolish = _polish_binding()
	match action:
		"system_return":
			system_menu_open = false
			var error: Error = get_tree().change_scene_to_file(
				"res://scenes/menu/main_menu.tscn"
			)
			if error != OK:
				_show_toast("× 无法返回主菜单：%s" % error_string(error))
		"schedule_contact":
			if binding == null:
				return
			var proposal: V2LifeLoopResult = binding.contact_activity_proposal(
				str(payload)
			)
			if proposal.success:
				schedule_form = proposal.data.duplicate(true)
				_show_toast("✓ 已载入联系人和建议时间")
			else:
				schedule_form.clear()
				binding.last_command_result = proposal
				_show_toast("× " + proposal.user_message)
			queue_redraw()
		"schedule_confirm":
			if (
				binding != null
				and not schedule_form.is_empty()
				and str(schedule_form.get("activity_type", "")) == "social_contact"
			):
				var confirmed: V2LifeLoopResult = binding.submit_contact_activity(
					str(schedule_form.get("related_entity_id", "")),
					int(schedule_form.get("start_hour", -1)),
					int(schedule_form.get("duration_hours", 1))
				)
				_show_toast(
					("✓ " if confirmed.success else "× ") + confirmed.user_message
				)
				if confirmed.success:
					schedule_form.clear()
				queue_redraw()
			else:
				super._activate(action, payload)
		"person_action":
			if binding != null and str(payload) == "联系":
				var target_id: String = detail_person_id
				if target_id.is_empty():
					var contacts: Array[Dictionary] = binding.contact_options()
					target_id = "" if contacts.is_empty() else str(
						contacts[0].get("target_id", "")
					)
				var result: V2LifeLoopResult = binding.schedule_contact_next(target_id)
				_show_toast(("✓ " if result.success else "× ") + result.user_message)
				person_more_menu_open = false
			else:
				super._activate(action, payload)
		_:
			super._activate(action, payload)


func _polish_binding() -> V2LifeLoopUiBindingPolish:
	return life_binding as V2LifeLoopUiBindingPolish


func _schedule_activity_label(
	activity: Dictionary, binding: V2LifeLoopUiBindingPolish
) -> String:
	if str(activity.get("activity_type", "")) != "social_contact":
		return V2LifeLoopUiBinding._activity_label(
			str(activity.get("activity_type", ""))
		)
	var target_id: String = str(activity.get("related_entity_id", ""))
	var target_name: String = binding.contact_name(
		target_id, str(activity.get("person_id", binding.selected_person_id()))
	)
	return "联系关系人物" if target_name.is_empty() else "联系%s" % target_name


func _schedule_form_label(
	form: Dictionary, binding: V2LifeLoopUiBindingPolish
) -> String:
	if str(form.get("activity_type", "")) != "social_contact":
		return V2LifeLoopUiBinding._activity_label(str(form.get("activity_type", "")))
	var stored_name: String = str(form.get("related_entity_name", ""))
	if not stored_name.is_empty():
		return "联系%s" % stored_name
	var target_name: String = binding.contact_name(
		str(form.get("related_entity_id", ""))
	)
	return "联系关系人物" if target_name.is_empty() else "联系%s" % target_name
