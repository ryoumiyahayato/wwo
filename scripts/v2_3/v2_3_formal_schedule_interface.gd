class_name V23FormalScheduleInterface
extends V23FormalInterface
## One activity entry, contextual leave confirmation, and no duplicate character tab.

var leave_confirmation: Dictionary = {}


func _draw() -> void:
	super._draw()
	if not leave_confirmation.is_empty():
		_draw_leave_confirmation()


func close_top_layer() -> bool:
	if not leave_confirmation.is_empty():
		leave_confirmation.clear()
		queue_redraw()
		return true
	return super.close_top_layer()


func _draw_character_navigation(rect: Rect2) -> void:
	var items: Array = [
		["summary", "概览"],
		["life_work", "生活与工作"],
		["relationships", "关系人物"],
		["owned_orgs", "我的组织"],
		["discover_orgs", "探索组织"],
	]
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(
			rect.position.x,
			rect.position.y + float(index) * 45.0,
			rect.size.x,
			34.0
		)
		if character_section == str(item[0]):
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), GOLD)
		_text(
			row.position + Vector2(12.0, 22.0),
			str(item[1]),
			11,
			INK if character_section == str(item[0]) else INK_MUTED
		)
		_register(
			row,
			"character_section",
			str(item[0]),
			"人物中心只显示人物信息；活动统一从概览底部进入"
		)


func _draw_schedule_panel() -> void:
	var binding: V23ControlledUiBinding = _controlled_binding()
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
		"%s · 玩家安排覆盖重叠的自动行为" % str(
			person.get("display_name_zh", "")
		),
		10,
		INK_MUTED
	)
	_section_heading(rect.position + Vector2(20.0, 82.0), "今日实际日程")
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
				int(start_value.get("hour", 0)),
				int(end_value.get("hour", 0)),
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
				Rect2(
					rect.position.x + 16.0,
					y - 15.0,
					rect.size.x - 32.0,
					18.0
				),
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
	_section_heading(rect.position + Vector2(20.0, 220.0), "工作义务")
	if active_leave.is_empty():
		_text(
			rect.position + Vector2(20.0, 242.0),
			"当前没有未来请假记录。",
			9,
			INK_DIM
		)
	else:
		_text(
			rect.position + Vector2(20.0, 242.0),
			"%s—%s · 已解除 %d 小时合同义务" % [
				str(active_leave.get("start_display", "")),
				str(active_leave.get("end_display", "")),
				int(active_leave.get("covered_hour_count", 0)),
			],
			9,
			AMBER
		)
	_text_link(
		Rect2(rect.end.x - 126.0, rect.position.y + 224.0, 92.0, 26.0),
		"预先请假",
		"schedule_preplanned_leave",
		null,
		"只用于提前解除未来合同工时；安排冲突行为时会自动询问"
	)

	_divider(
		Vector2(rect.position.x + 20.0, rect.position.y + 270.0),
		rect.size.x - 40.0
	)
	_section_heading(
		Vector2(rect.position.x + 20.0, rect.position.y + 290.0),
		"选择行为"
	)
	var actions: Array[Dictionary] = [
		{"label":"购买食品", "type":"purchase_food", "tip":"必须到提供食品交易的地点"},
		{"label":"购买用品", "type":"purchase_essentials", "tip":"必须到提供用品交易的地点"},
		{"label":"休息", "type":"rest", "tip":"必须位于本人住所"},
		{"label":"睡眠", "type":"sleep", "tip":"必须位于本人住所"},
		{"label":"加班", "type":"overtime", "tip":"必须位于工作地点"},
		{"label":"工会例会", "type":"union_activity", "tip":"必须位于工会会所"},
	]
	var contacts: Array[Dictionary] = binding.contact_options()
	for contact: Dictionary in contacts:
		actions.append({
			"label": "联系%s" % str(
				contact.get("display_name_zh", "关系人物")
			),
			"type": "social_contact",
			"target_id": str(contact.get("target_id", "")),
			"tip": "面对面行为仍需双方实际同地",
		})
	if contacts.is_empty():
		actions.append({
			"label": "暂无联系人",
			"type": "",
			"tip": "当前人物没有可联系的关系人物",
		})
	for index: int in range(mini(actions.size(), 8)):
		var item: Dictionary = actions[index]
		var column: int = index % 4
		var row_index: int = index / 4
		var row := Rect2(
			rect.position.x + 20.0 + float(column) * 128.0,
			rect.position.y + 308.0 + float(row_index) * 31.0,
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
			_text(
				row.position + Vector2(10.0, 17.0),
				str(item.get("label", "")),
				10,
				INK_DIM
			)
			_register(row, "consume", null, str(item.get("tip", "")))
		elif activity_type == "social_contact":
			_compact_action(
				row,
				str(item.get("label", "")),
				selected,
				"schedule_contact",
				target_id,
				str(item.get("tip", ""))
			)
		else:
			_compact_action(
				row,
				str(item.get("label", "")),
				selected,
				"schedule_activity",
				activity_type,
				str(item.get("tip", ""))
			)

	if schedule_form.is_empty():
		_text(
			rect.position + Vector2(20.0, 382.0),
			"先选择行为。地点不符合时不会远程执行；与工作冲突时再询问请假。",
			9,
			INK_DIM
		)
		return

	var start_hour: int = int(schedule_form.get("start_hour", 0))
	var duration: int = int(schedule_form.get("duration_hours", 1))
	var activity_type: String = str(schedule_form.get("activity_type", ""))
	var is_leave: bool = activity_type == "authorized_leave"
	var activity_label: String = (
		"预先请假"
		if is_leave
		else _schedule_form_label(schedule_form, binding)
	)
	_divider(
		Vector2(rect.position.x + 20.0, rect.position.y + 370.0),
		rect.size.x - 40.0
	)
	_text(rect.position + Vector2(20.0, 392.0), activity_label, 11, INK)
	var detail: String = (
		"不指定地点 · 只解除所选时段内的合同工作义务"
		if is_leave
		else "地点与冲突将在提交时按人物实际位置检查 · %s" % str(
			schedule_form.get("expected_effects", "")
		)
	)
	_text(rect.position + Vector2(20.0, 413.0), detail, 8, INK_MUTED)

	var time_box := Rect2(
		rect.position.x + 20.0,
		rect.position.y + 430.0,
		rect.size.x - 40.0,
		68.0
	)
	_surface(time_box, Color(GOLD, 0.055), Color(GOLD, 0.24), 7)
	_text(time_box.position + Vector2(12.0, 21.0), "开始", 9, INK_DIM)
	_text(
		time_box.position + Vector2(52.0, 21.0),
		V2DateTime.display_from_total_hour(start_hour),
		9,
		INK
	)
	_text(time_box.position + Vector2(270.0, 21.0), "结束", 9, INK_DIM)
	_text(
		time_box.position + Vector2(310.0, 21.0),
		V2DateTime.display_from_total_hour(start_hour + duration),
		9,
		INK
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
			str(control[0]),
			false,
			"schedule_adjust",
			int(control[1]),
			"时间调整仍由权威层检查地点、合同义务与冲突"
		)
	_text(
		time_box.position + Vector2(420.0, 21.0),
		"%d小时" % duration,
		9,
		GOLD
	)

	_primary_action(
		Rect2(rect.position.x + 20.0, rect.position.y + 506.0, 160.0, 30.0),
		"确认请假" if is_leave else "确认安排",
		"schedule_confirm",
		null,
		"提交后先检查实际地点，再处理工作冲突"
	)
	_text_link(
		Rect2(rect.position.x + 194.0, rect.position.y + 508.0, 82.0, 26.0),
		"取消编辑",
		"schedule_cancel_edit",
		null,
		"放弃尚未提交的编辑"
	)
	if not binding.last_command_result.success:
		_text(
			rect.position + Vector2(292.0, 526.0),
			"× %s" % binding.last_command_result.user_message,
			8,
			RED
		)


func _draw_leave_confirmation() -> void:
	_register(Rect2(Vector2.ZERO, size), "consume", null, "")
	var rect := Rect2(386.0, 214.0, 508.0, 276.0)
	_surface(rect, PANEL_SOLID, Color(AMBER, 0.62), 12)
	_register(rect, "consume")
	_text(rect.position + Vector2(24.0, 38.0), "该行为需要请假", 22, INK)
	var covered_count: int = int(
		leave_confirmation.get("covered_hour_count", 0)
	)
	_text(
		rect.position + Vector2(24.0, 73.0),
		"所选行为与 %d 小时合同工作义务重叠。" % covered_count,
		11,
		AMBER
	)
	_text(
		rect.position + Vector2(24.0, 101.0),
		"确认后：解除这些工作义务，并立即保留玩家安排的行为。",
		10,
		INK
	)
	_text(
		rect.position + Vector2(24.0, 126.0),
		"拒绝后：不请假，也不安排该行为。不会自动替玩家选择。",
		10,
		INK_MUTED
	)
	var start_hour: int = int(leave_confirmation.get("start_hour", 0))
	var duration: int = int(leave_confirmation.get("duration_hours", 1))
	_divider(rect.position + Vector2(24.0, 153.0), rect.size.x - 48.0)
	_text(
		rect.position + Vector2(24.0, 181.0),
		"时间：%s—%s" % [
			V2DateTime.display_from_total_hour(start_hour),
			V2DateTime.display_from_total_hour(start_hour + duration),
		],
		9,
		INK_MUTED
	)
	_primary_action(
		Rect2(rect.position.x + 24.0, rect.end.y - 58.0, 172.0, 34.0),
		"请假并安排",
		"leave_confirm_activity",
		null,
		"原子执行请假与玩家活动；任一步失败都会回滚"
	)
	_text_link(
		Rect2(rect.position.x + 222.0, rect.end.y - 56.0, 106.0, 30.0),
		"不安排",
		"leave_cancel_activity",
		null,
		"关闭确认，不改变日程"
	)


func _activate(action: String, payload: Variant) -> void:
	var binding: V23ControlledUiBinding = _controlled_binding()
	match action:
		"schedule_preplanned_leave":
			if binding == null:
				return
			var proposal: V2LifeLoopResult = binding.activity_proposal(
				"authorized_leave"
			)
			if proposal.success:
				schedule_form = proposal.data.duplicate(true)
				_show_toast("已载入下一段合同工时，可调整后预先请假")
			else:
				schedule_form.clear()
				binding.last_command_result = proposal
				_show_toast("× " + proposal.user_message)
			queue_redraw()
		"schedule_confirm":
			if (
				binding == null
				or schedule_form.is_empty()
				or str(schedule_form.get("activity_type", "")) == "social_contact"
			):
				super._activate(action, payload)
				return
			var confirmed: V2LifeLoopResult = binding.submit_activity(
				str(schedule_form.get("activity_type", "")),
				int(schedule_form.get("start_hour", -1)),
				int(schedule_form.get("duration_hours", 1))
			)
			if (
				not confirmed.success
				and confirmed.error_code == "requires_leave_authorization"
			):
				leave_confirmation = confirmed.data.duplicate(true)
				_show_toast("该行为与工作冲突，请确认是否请假")
			elif confirmed.success:
				schedule_form.clear()
				_show_toast("✓ " + confirmed.user_message)
			else:
				_show_toast("× " + confirmed.user_message)
			queue_redraw()
		"leave_confirm_activity":
			if binding == null or leave_confirmation.is_empty():
				return
			var result: V2LifeLoopResult = binding.submit_activity_with_leave(
				str(leave_confirmation.get("activity_type", "")),
				int(leave_confirmation.get("start_hour", -1)),
				int(leave_confirmation.get("duration_hours", 1))
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
			if result.success:
				schedule_form.clear()
				leave_confirmation.clear()
			queue_redraw()
		"leave_cancel_activity":
			leave_confirmation.clear()
			_show_toast("未请假，所选行为未安排")
			queue_redraw()
		_:
			super._activate(action, payload)


func _controlled_binding() -> V23ControlledUiBinding:
	return life_binding as V23ControlledUiBinding
