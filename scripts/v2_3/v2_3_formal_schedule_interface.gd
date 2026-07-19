class_name V23FormalScheduleInterface
extends V23FormalInterface
## Formal schedule UI: leave releases work obligations and never occupies the released time.


func _draw_schedule_panel() -> void:
	var binding: V23FormalUiBinding = _formal_binding()
	if binding == null:
		super._draw_schedule_panel()
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var person: Dictionary = _identity_data()
	_text(rect.position + Vector2(20.0, 34.0), "安排活动与工作豁免", 22, INK)
	_text(
		rect.position + Vector2(20.0, 57.0),
		"%s · 活动占用时间；请假只解除对应劳动义务" % str(
			person.get("display_name_zh", "")
		),
		10,
		INK_MUTED
	)
	_section_heading(rect.position + Vector2(20.0, 82.0), "今日实际日程")
	var timeline: Array[Dictionary] = binding.today_schedule()
	var y: float = rect.position.y + 108.0
	for index: int in range(mini(5, timeline.size())):
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

	var leave_records: Array[Dictionary] = binding.leave_view()
	var active_leave: Dictionary = {}
	for record: Dictionary in leave_records:
		if (
			int(record.get("end_hour", 0)) > binding.simulation.clock.total_hours
			and str(record.get("status", "")) == "approved"
		):
			active_leave = record
			break
	_section_heading(rect.position + Vector2(20.0, 210.0), "已批准的工作豁免")
	if active_leave.is_empty():
		_text(
			rect.position + Vector2(20.0, 231.0),
			"没有未来请假记录。",
			9,
			INK_DIM
		)
	else:
		_text(
			rect.position + Vector2(20.0, 231.0),
			"%s—%s · 解除 %d 小时合同义务" % [
				str(active_leave.get("start_display", "")),
				str(active_leave.get("end_display", "")),
				int(active_leave.get("covered_hour_count", 0)),
			],
			9,
			AMBER
		)
		_text(
			rect.position + Vector2(20.0, 248.0),
			"该时段仍可安排旅行、休息或其他行为；请假本身不占用日程。",
			8,
			INK_MUTED
		)

	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 266.0), rect.size.x - 40.0)
	_section_heading(Vector2(rect.position.x + 20.0, rect.position.y + 286.0), "选择行为")
	var actions: Array[Dictionary] = [
		{"label":"购买食品", "type":"purchase_food", "tip":"1小时 · 560生丁 · +7人日"},
		{"label":"购买用品", "type":"purchase_essentials", "tip":"1小时 · 140生丁 · +7人日"},
		{"label":"休息", "type":"rest", "tip":"1小时 · 恢复疲劳与压力"},
		{"label":"睡眠", "type":"sleep", "tip":"8小时 · 优先恢复"},
		{"label":"加班", "type":"overtime", "tip":"实际占用时间并产生加班工资"},
		{"label":"请假", "type":"authorized_leave", "tip":"解除所选合同工时；不占用时间"},
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
			rect.position.y + 304.0 + float(row_index) * 31.0,
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
			rect.position + Vector2(20.0, 378.0),
			"活动需要选择时间；请假只选择要解除的合同工时。",
			9,
			INK_DIM
		)
		return

	var start_hour: int = int(schedule_form.get("start_hour", 0))
	var duration: int = int(schedule_form.get("duration_hours", 1))
	var activity_type: String = str(schedule_form.get("activity_type", ""))
	var is_leave: bool = activity_type == "authorized_leave"
	var activity_label: String = "请假" if is_leave else _schedule_form_label(schedule_form, binding)
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 370.0), rect.size.x - 40.0)
	_text(rect.position + Vector2(20.0, 392.0), activity_label, 11, INK)
	var detail: String = (
		"不指定地点 · 解除所选时段内的合同工作义务" if is_leave
		else "地点：%s · 现金：%d 生丁 · %s" % [
			binding.simulation.config.location_name(
				str(schedule_form.get("location_id", ""))
			),
			int(schedule_form.get("required_cash_centimes", 0)),
			str(schedule_form.get("expected_effects", "")),
		]
	)
	_text(rect.position + Vector2(20.0, 413.0), detail, 8, INK_MUTED)

	var time_box := Rect2(rect.position.x + 20.0, rect.position.y + 430.0, rect.size.x - 40.0, 68.0)
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
				time_box.position.y + 36.0,
				74.0,
				24.0
			),
			str(control[0]), false, "schedule_adjust", int(control[1]),
			"时间调整仍由权威层检查合同义务与冲突"
		)
	_text(time_box.position + Vector2(420.0, 21.0), "%d小时" % duration, 9, GOLD)

	_primary_action(
		Rect2(rect.position.x + 20.0, rect.position.y + 506.0, 160.0, 30.0),
		"确认请假" if is_leave else "确认安排",
		"schedule_confirm",
		null,
		"请假只解除劳动义务" if is_leave else "提交到正式日程服务"
	)
	_text_link(
		Rect2(rect.position.x + 194.0, rect.position.y + 508.0, 82.0, 26.0),
		"取消编辑", "schedule_cancel_edit", null, "放弃尚未提交的编辑"
	)
	if not binding.last_command_result.success:
		_text(
			rect.position + Vector2(292.0, 526.0),
			"× %s" % binding.last_command_result.user_message,
			8,
			RED
		)
	elif is_leave:
		_text(
			rect.position + Vector2(292.0, 526.0),
			"批准后该时间可继续安排其他行为",
			8,
			AMBER
		)
