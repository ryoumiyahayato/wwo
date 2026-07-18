class_name V2LifeLoopInterfaceFinal
extends V2LifeLoopInterface
## Final V2.2 presentation fixes after visible-window review.

const V2_MENU_SCENE: String = "res://scenes/v2_2/v2_2_life_loop_menu.tscn"
const RELATIONSHIP_FIRST_ROW_OFFSET: float = 58.0
const SUMMARY_HEADING_OFFSET: float = 8.0


func _draw_system_menu() -> void:
	var live: bool = life_binding != null
	var items: Array = [
		["返回原型菜单", "system_return", "返回 V2.2 人物生活闭环菜单"],
	]
	if live:
		items = [
			["保存进度", "system_save", "保存到 V2.2 固定评审槽"],
			["载入最近存档", "system_load", "只载入 V2.2 人物生活闭环存档"],
			["设置", "system_settings", "设置入口占位"],
			["返回原型菜单", "system_return", "返回 V2.2 人物生活闭环菜单"],
		]
		if review_mode or life_binding.developer_mode:
			items.insert(
				3,
				["开发者工具", "open_developer", "打开权威时间、账本与结算工具"]
			)
	var rect := Rect2(1018.0, 78.0, 244.0, 14.0 + float(items.size()) * 29.0)
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


func _draw_character_summary(rect: Rect2, person: Dictionary) -> void:
	_section_heading(
		rect.position + Vector2(0.0, SUMMARY_HEADING_OFFSET),
		"当前状态"
	)
	var indicators: Array = person.get("status_indicators", []) as Array
	for index: int in range(mini(3, indicators.size())):
		_draw_status_indicator(
			Rect2(
				rect.position.x + float(index) * 82.0,
				rect.position.y + 31.0,
				74.0,
				28.0
			),
			indicators[index] as Dictionary
		)
	_divider(rect.position + Vector2(0.0, 66.0), rect.size.x)
	_text(rect.position + Vector2(0.0, 90.0), "职业", 10, INK_DIM)
	_text(rect.position + Vector2(62.0, 90.0), str(person.get("occupation", "")), 11, INK)
	_text(
		rect.position + Vector2(0.0, 116.0),
		"雇主" if identity == "worker" else "所属机构",
		10,
		INK_DIM
	)
	_text(
		rect.position + Vector2(62.0, 116.0),
		str(person.get("employer", ""))
		if identity == "worker"
		else str(person.get("institution", "")),
		11,
		INK
	)
	_text(
		rect.position + Vector2(0.0, 142.0),
		"工会职位" if identity == "worker" else "机构职位",
		10,
		INK_DIM
	)
	_text(
		rect.position + Vector2(62.0, 142.0),
		str(person.get("union_position", ""))
		if identity == "worker"
		else str(person.get("institution_position", "")),
		11,
		GOLD
	)
	_status_line(
		rect.position + Vector2(0.0, 173.0),
		"当前工作",
		str(person.get("current_work", "")),
		INK
	)
	_status_line(
		rect.position + Vector2(0.0, 215.0),
		"主要问题",
		str(person.get("primary_concern", "")),
		AMBER
	)
	_status_line(
		rect.position + Vector2(0.0, 257.0),
		"主要计划",
		str(person.get("plan", "")),
		GREEN
	)
	_primary_action(
		Rect2(rect.position.x, rect.end.y - 38.0, 118.0, 30.0),
		"安排活动" if life_binding != null else "查看当前计划",
		"open_schedule" if life_binding != null else "action_detail",
		str(person.get("plan", "")),
		"打开日期、时间、成本、效果与冲突检查"
		if life_binding != null
		else "查看目标、效果、资源、权限与下一步骤"
	)


func _draw_relationships(rect: Rect2) -> void:
	var binding: V2LifeLoopUiBindingPolish = _polish_binding()
	if binding == null:
		super._draw_relationships(rect)
		return
	var contacts: Array[Dictionary] = binding.contact_options()
	_section_heading(rect.position + Vector2(0.0, 10.0), "关系人物")
	if contacts.is_empty():
		_text(
			rect.position + Vector2(0.0, RELATIONSHIP_FIRST_ROW_OFFSET),
			"当前人物没有可用的关系行动",
			10,
			INK_MUTED
		)
		_text(
			rect.position + Vector2(0.0, RELATIONSHIP_FIRST_ROW_OFFSET + 24.0),
			"联系人只来自当前人物真实认识的关系记录。",
			9,
			INK_DIM
		)
		return
	for index: int in range(mini(contacts.size(), 3)):
		var contact: Dictionary = contacts[index]
		var row_y: float = (
			rect.position.y + RELATIONSHIP_FIRST_ROW_OFFSET + float(index) * 116.0
		)
		var target_name: String = str(contact.get("display_name_zh", "关系人物"))
		_text(Vector2(rect.position.x, row_y), target_name, 13, INK)
		var native_name: String = str(contact.get("native_name", ""))
		if not native_name.is_empty():
			_text(Vector2(rect.position.x, row_y + 21.0), native_name, 9, INK_MUTED)
		_text(
			Vector2(rect.position.x, row_y + 46.0),
			"熟悉度 %d · 信任 %d" % [
				int(contact.get("familiarity", 0)),
				int(contact.get("trust", 0)),
			],
			10,
			GOLD
		)
		var last_contact: String = str(contact.get("last_contact_datetime", ""))
		_text(
			Vector2(rect.position.x, row_y + 66.0),
			"最近联系：%s" % (
				"尚未联系" if last_contact.is_empty() else last_contact
			),
			8,
			INK_DIM
		)
		_primary_action(
			Rect2(rect.position.x, row_y + 79.0, 160.0, 28.0),
			"联系%s" % target_name,
			"schedule_contact",
			str(contact.get("target_id", "")),
			"耗时1小时；熟悉度+5、信任+2、压力-20"
		)


func _activate(action: String, payload: Variant) -> void:
	if action == "system_return":
		system_menu_open = false
		var error: Error = get_tree().change_scene_to_file(V2_MENU_SCENE)
		if error != OK:
			_show_toast("× 无法返回 V2.2 原型菜单：%s" % error_string(error))
		return
	super._activate(action, payload)


func debug_state() -> Dictionary:
	var state: Dictionary = super()
	state["v2_menu_scene"] = V2_MENU_SCENE
	state["system_menu_heading_visible"] = false
	state["relationship_first_row_offset"] = RELATIONSHIP_FIRST_ROW_OFFSET
	state["summary_heading_offset"] = SUMMARY_HEADING_OFFSET
	return state


func show_launch_result(result: V2LifeLoopResult) -> void:
	_show_toast(("✓ " if result.success else "× ") + result.user_message)
