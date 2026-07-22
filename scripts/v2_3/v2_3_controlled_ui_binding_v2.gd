class_name V23ControlledUiBindingV2
extends V23ControlledUiBinding
## Player-facing social-plan construction and readable projections.
## Internal IDs and raw enums remain available only through debug_state().

var _sandbox_selection_by_person: Dictionary = {}
var _selected_message_by_person: Dictionary = {}


func messages_view(person_id: String = "") -> Dictionary:
	var mailbox: Dictionary = super.messages_view(person_id)
	var inbox: Array = mailbox.get("inbox", []) as Array
	var outbox: Array = mailbox.get("outbox", []) as Array
	var readable_inbox: Array[Dictionary] = []
	var readable_outbox: Array[Dictionary] = []
	for raw_message: Variant in inbox:
		if raw_message is Dictionary:
			readable_inbox.append(_decorate_player_message(raw_message as Dictionary, true))
	for raw_message: Variant in outbox:
		if raw_message is Dictionary:
			readable_outbox.append(_decorate_player_message(raw_message as Dictionary, false))
	mailbox["inbox"] = readable_inbox
	mailbox["outbox"] = readable_outbox
	mailbox["selected_message"] = selected_message_view(person_id)
	return mailbox


func open_message(message_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("messages_unavailable", "通信服务不可用")
	var message: Dictionary = product.communication.get_message(message_id)
	if message.is_empty():
		return V2LifeLoopResult.fail("unknown_message", "找不到这封消息")
	if str(message.get("recipient_person_id", "")) == selected_person_id():
		var status: String = str(message.get("status", ""))
		if status == "delivered":
			var read_result: V2LifeLoopResult = read_message(message_id)
			if not read_result.success:
				return read_result
	_selected_message_by_person[selected_person_id()] = message_id
	_view_revision += 1
	view_changed.emit()
	return V2LifeLoopResult.ok("已打开消息", {}, [message_id])


func selected_message_view(person_id: String = "") -> Dictionary:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return {}
	var resolved_id: String = selected_person_id() if person_id.is_empty() else person_id
	var message_id: String = str(_selected_message_by_person.get(resolved_id, ""))
	if message_id.is_empty():
		return {}
	var message: Dictionary = product.communication.get_message(message_id)
	if message.is_empty():
		_selected_message_by_person.erase(resolved_id)
		return {}
	var incoming: bool = str(message.get("recipient_person_id", "")) == resolved_id
	return _decorate_player_message(message, incoming)


func reply_selected_message() -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("messages_unavailable", "通信服务不可用")
	var person_id: String = selected_person_id()
	var message_id: String = str(_selected_message_by_person.get(person_id, ""))
	if message_id.is_empty():
		return V2LifeLoopResult.fail("message_not_selected", "请先打开一封收到的消息")
	var original: Dictionary = product.communication.get_message(message_id)
	var original_type: String = str(original.get("content_type", ""))
	var reply_type: String = "private_reply"
	var reply_text: String = "已经收到你的消息，我会再与你联系。"
	if original_type in ["greeting", "greeting_reply", "private_reply"]:
		reply_type = "greeting_reply"
		reply_text = "谢谢你的问候。近日有机会时我们再见面交谈。"
	elif original_type.contains("appointment") or original_type.contains("meeting"):
		reply_type = "appointment_reply"
		reply_text = "我已经收到约见消息，会按时间安排作出回应。"
	last_command_result = product.communication.reply_message(
		person_id,
		message_id,
		reply_type,
		{"text": reply_text},
		product.clock.total_hours,
		product.spatial_locations,
		product.knowledge,
		product.dynamic_relationships,
		product.households,
		product.ledger
	)
	if last_command_result.success:
		product.state_changed.emit({"messages": true})
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func knowledge_view(person_id: String = "") -> Array[Dictionary]:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return []
	var result: Array[Dictionary] = []
	for raw_record: Variant in super.knowledge_view(person_id):
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		record["display_title"] = _knowledge_title(record, product)
		record["display_source"] = _knowledge_source_label(str(record.get("source_kind", "")))
		record["display_status"] = _knowledge_status_label(str(record.get("status", "")))
		record["display_freshness"] = _knowledge_freshness_label(str(record.get("freshness", "")))
		record["display_confidence"] = _confidence_label(int(record.get("confidence", 0)))
		result.append(record)
	return result


func contact_options(person_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = super.contact_options(person_id)
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return result
	for index: int in range(result.size()):
		var contact: Dictionary = result[index]
		var target_id: String = str(contact.get("target_id", ""))
		contact["role"] = _person_role(target_id, product)
		contact["relationship_summary"] = _relationship_summary(contact)
		contact["expectation_summary"] = _relationship_expectation(contact)
		contact["last_contact_label"] = _last_contact_label(str(contact.get("last_contact_datetime", "")))
		result[index] = contact
	return result


func request_introduction_option(
	intermediary_id: String,
	target_id: String
) -> V2LifeLoopResult:
	var available: bool = false
	for option: Dictionary in introduction_options():
		if (
			str(option.get("intermediary_id", "")) == intermediary_id
			and str(option.get("target_id", "")) == target_id
		):
			available = true
			break
	if not available:
		return V2LifeLoopResult.fail("introduction_unavailable", "这条介绍关系目前不可用")
	last_command_result = controlled_simulation.request_introduction(
		selected_person_id(), intermediary_id, target_id
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func sandbox_view(person_id: String = "") -> Dictionary:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return super.sandbox_view(person_id)
	var resolved_id: String = selected_person_id() if person_id.is_empty() else person_id
	var selection: Dictionary = _selection_for(resolved_id)
	var goals: Array[Dictionary] = product.social_sandbox.goals_for(resolved_id)
	var goal_id: String = str(selection.get("goal_id", ""))
	if not _contains_id(goals, "goal_id", goal_id):
		goal_id = "" if goals.is_empty() else str(goals.front().get("goal_id", ""))
		selection["goal_id"] = goal_id
		selection["method_id"] = ""
		selection["target_id"] = ""
	var methods: Array[Dictionary] = product.social_sandbox.methods_for(resolved_id, goal_id)
	var method_id: String = str(selection.get("method_id", ""))
	if not _contains_id(methods, "method_id", method_id):
		method_id = "" if methods.is_empty() else str(methods.front().get("method_id", ""))
		selection["method_id"] = method_id
		selection["target_id"] = ""
	var method: Dictionary = product.social_sandbox.method_record(method_id)
	var targets: Array[Dictionary] = _target_options(product, resolved_id, method)
	var target_id: String = str(selection.get("target_id", ""))
	if not target_id.is_empty() and not _contains_id(targets, "person_id", target_id):
		target_id = ""
		selection["target_id"] = ""
	var current_hour: int = product.clock.total_hours
	var start_hour: int = int(selection.get("start_hour", current_hour + 12))
	if start_hour <= current_hour:
		start_hour = current_hour + 12
		selection["start_hour"] = start_hour
	var preparation: int = clampi(int(selection.get("preparation", 400)), 0, 900)
	selection["preparation"] = preparation
	_sandbox_selection_by_person[resolved_id] = selection
	var preview: Dictionary = {}
	if not goal_id.is_empty() and not method_id.is_empty():
		var preview_result: V2LifeLoopResult = (
			product.social_sandbox as V23SocialSandboxServiceV2
		).preview_intent(
			resolved_id,
			goal_id,
			method_id,
			target_id,
			{
				"current_hour": current_hour,
				"start_hour": start_hour,
				"preparation": preparation,
				"location_id": str(selection.get("location_id", "")),
				"organization_id": str(selection.get("organization_id", "")),
			}
		)
		preview = {
			"success": preview_result.success,
			"message": preview_result.user_message,
			"data": preview_result.data.duplicate(true),
			"error_code": preview_result.error_code,
		}
	var readable_goals: Array[Dictionary] = []
	for raw_goal: Dictionary in goals:
		var goal: Dictionary = raw_goal.duplicate(true)
		goal["player_summary"] = _goal_player_summary(goal)
		goal["urgency_label"] = _urgency_label(int(goal.get("urgency", 0)))
		readable_goals.append(goal)
	var readable_methods: Array[Dictionary] = []
	for raw_method: Dictionary in methods:
		var readable_method: Dictionary = raw_method.duplicate(true)
		readable_method["player_explanation"] = _method_player_explanation(readable_method)
		readable_method["preparation_hint"] = _method_preparation_hint(readable_method)
		readable_methods.append(readable_method)
	return {
		"available": true,
		"person_id": resolved_id,
		"situations": product.social_sandbox.situations_for(resolved_id),
		"goals": readable_goals,
		"selected_goal_id": goal_id,
		"methods": readable_methods,
		"selected_method_id": method_id,
		"targets": targets,
		"selected_target_id": target_id,
		"selected_start_hour": start_hour,
		"selected_start_datetime": V2DateTime.display_from_total_hour(start_hour),
		"preparation": preparation,
		"preparation_label": _preparation_label(preparation),
		"preview": preview,
		"tasks": product.social_sandbox.tasks_for(resolved_id, true),
		"events": product.social_sandbox.visible_events_for(resolved_id, product.truth_view, 12),
		"explanation": product.social_sandbox.explanation_for(resolved_id) if developer_mode else {},
	}


func select_sandbox_goal(goal_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "行动计划不可用")
	var person_id: String = selected_person_id()
	if not _contains_id(product.social_sandbox.goals_for(person_id), "goal_id", goal_id):
		return V2LifeLoopResult.fail("unknown_goal", "这个处境已经发生变化")
	var selection: Dictionary = _selection_for(person_id)
	selection["goal_id"] = goal_id
	selection["method_id"] = ""
	selection["target_id"] = ""
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已选择要处理的处境")


func select_sandbox_method(method_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "行动计划不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var methods: Array[Dictionary] = product.social_sandbox.methods_for(person_id, str(selection.get("goal_id", "")))
	if not _contains_id(methods, "method_id", method_id):
		return V2LifeLoopResult.fail("unknown_method", "这种应对方式不适用于当前处境")
	selection["method_id"] = method_id
	selection["target_id"] = ""
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已选择应对方式")


func select_sandbox_target(target_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "行动计划不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var method: Dictionary = product.social_sandbox.method_record(str(selection.get("method_id", "")))
	if target_id.is_empty() and not product.social_sandbox._method_requires_target(method):
		selection["target_id"] = ""
		_sandbox_selection_by_person[person_id] = selection
		return _selection_changed("这个行动不需要指定人物")
	var targets: Array[Dictionary] = _target_options(product, person_id, method)
	if not _contains_id(targets, "person_id", target_id):
		return V2LifeLoopResult.fail("unknown_target", "当前无法把这个人物作为行动对象")
	selection["target_id"] = target_id
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已选择行动对象")


func shift_sandbox_start(delta_hours: int) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "行动计划不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var minimum: int = product.clock.total_hours + 1
	var maximum: int = product.clock.total_hours + 120
	selection["start_hour"] = clampi(
		int(selection.get("start_hour", product.clock.total_hours + 12)) + delta_hours,
		minimum,
		maximum
	)
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已调整计划时间")


func set_sandbox_preparation(value: int) -> V2LifeLoopResult:
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	selection["preparation"] = clampi(value, 0, 900)
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已调整准备方式")


func submit_selected_sandbox_plan() -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "行动计划不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var goal_id: String = str(selection.get("goal_id", ""))
	var method_id: String = str(selection.get("method_id", ""))
	if goal_id.is_empty() or method_id.is_empty():
		return V2LifeLoopResult.fail("incomplete_social_plan", "请先选择处境和应对方式")
	last_command_result = product.social_sandbox.submit_intent(
		person_id,
		goal_id,
		method_id,
		str(selection.get("target_id", "")),
		"player",
		{
			"current_hour": product.clock.total_hours,
			"start_hour": int(selection.get("start_hour", product.clock.total_hours + 12)),
			"preparation": int(selection.get("preparation", 400)),
			"location_id": str(selection.get("location_id", "")),
			"organization_id": str(selection.get("organization_id", "")),
		}
	)
	if last_command_result.success:
		selection["start_hour"] = product.clock.total_hours + 12
		_sandbox_selection_by_person[person_id] = selection
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func save_review() -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.save_review()
	if result.success:
		last_command_result = V2LifeLoopResult.ok("游戏已保存")
		return last_command_result
	return result


func load_review() -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.load_review()
	if result.success:
		last_command_result = V2LifeLoopResult.ok("游戏已载入")
		return last_command_result
	return result


func migrate_v2_2_review() -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.migrate_v2_2_review()
	if result.success:
		last_command_result = V2LifeLoopResult.ok("旧版存档已导入")
		return last_command_result
	return result


func _selection_for(person_id: String) -> Dictionary:
	var value: Variant = _sandbox_selection_by_person.get(person_id, {})
	var selection: Dictionary = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	if not selection.has("start_hour") and controlled_simulation != null:
		selection["start_hour"] = controlled_simulation.clock.total_hours + 12
	if not selection.has("preparation"):
		selection["preparation"] = 400
	return selection


func _target_options(
	product: V23ProductSimulationV2,
	person_id: String,
	method: Dictionary
) -> Array[Dictionary]:
	if method.is_empty() or not product.social_sandbox._method_requires_target(method):
		return []
	var result: Array[Dictionary] = []
	for person: Dictionary in product.v2_3_config.social_people():
		var target_id: String = str(person.get("person_id", ""))
		if (
			target_id.is_empty()
			or target_id == person_id
			or not product.knowledge.knows_person(person_id, target_id)
		):
			continue
		result.append({
			"person_id": target_id,
			"display_name": str(person.get("display_name_zh", target_id)),
			"role": str(person.get("role", "")),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("display_name", "")) < str(right.get("display_name", ""))
	)
	return result


func _decorate_player_message(message: Dictionary, incoming: bool) -> Dictionary:
	var decorated: Dictionary = message.duplicate(true)
	var content_type: String = str(message.get("content_type", ""))
	var payload: Dictionary = message.get("payload", {}) as Dictionary
	var other_name: String = str(
		message.get("sender_name", "") if incoming else message.get("recipient_name", "")
	)
	decorated["other_name"] = other_name
	decorated["display_title"] = "%s：%s" % [other_name, _message_type_label(content_type)]
	decorated["display_status"] = _message_status_label(str(message.get("status", "")))
	decorated["display_body"] = str(payload.get("text", _default_message_text(content_type)))
	decorated["display_time"] = str(
		message.get("delivered_datetime", message.get("expected_delivery_datetime", ""))
	)
	decorated["can_reply"] = incoming and str(message.get("status", "")) in ["read", "replied"]
	return decorated


func _knowledge_title(record: Dictionary, product: V23ProductSimulationV2) -> String:
	var fact_type: String = str(record.get("fact_type", ""))
	var subject_id: String = str(record.get("subject_id", ""))
	if fact_type == "location_identity":
		return "已知地点：%s" % product.spatial_locations.location_name(subject_id, selected_person_id(), false)
	if fact_type in ["person_identity", "private_reply", "relationship_contact"]:
		return "关于%s的消息" % _person_name(subject_id)
	if fact_type.contains("position") or fact_type.contains("organization"):
		return "组织与职位消息"
	if fact_type.contains("appointment"):
		return "约见安排"
	if fact_type.contains("message") or fact_type.contains("reply"):
		return "私人通信"
	return "已知事实"


func _person_role(person_id: String, product: V23ProductSimulationV2) -> String:
	for person: Dictionary in product.v2_3_config.social_people():
		if str(person.get("person_id", "")) == person_id:
			return str(person.get("role", ""))
	return ""


static func _relationship_summary(contact: Dictionary) -> String:
	var trust: int = int(contact.get("trust", 0))
	var affinity: int = int(contact.get("affinity", 0))
	var tension: int = int(contact.get("tension", 0))
	if tension >= 300:
		return "双方关系紧张，直接请求可能遭到拒绝。"
	if trust >= 350 and affinity >= 150:
		return "对方信任并亲近当前人物，愿意认真回应请求。"
	if trust >= 200:
		return "对方认为当前人物基本可靠，但关系仍需要维持。"
	return "双方只是一般相识，对方不会轻易承担额外义务。"


static func _relationship_expectation(contact: Dictionary) -> String:
	var obligation: int = int(contact.get("obligation", 0))
	var reciprocity: int = int(contact.get("reciprocity", 0))
	if obligation >= 100:
		return "当前人物对对方负有尚未偿还的人情。"
	if reciprocity >= 100:
		return "双方已有互相帮助的经历，可以提出有限请求。"
	return "目前没有明确的人情债务。"


static func _last_contact_label(datetime: String) -> String:
	return "尚无近期接触" if datetime.is_empty() else "最近接触：%s" % datetime


static func _goal_player_summary(goal: Dictionary) -> String:
	var consequence: String = str(goal.get("consequence_zh", goal.get("consequence", "")))
	if consequence.is_empty():
		consequence = str(goal.get("title_zh", "当前处境需要处理"))
	return consequence


static func _method_player_explanation(method: Dictionary) -> String:
	var effect: String = str(method.get("effect", ""))
	var explanations: Dictionary = {
		"work_reputation": "通过实际工作表现改变雇主和同事的判断。",
		"earn_cash": "投入时间换取临时收入，可能增加疲劳。",
		"relationship_positive": "尝试改善与具体人物的关系。",
		"relationship_negative": "明确对抗或拒绝对方，关系可能恶化。",
		"promise_create": "作出可被追踪和追责的承诺。",
		"promise_kept": "履行已经存在的承诺或人情。",
		"information": "从接触或观察中获得新的事实。",
		"evidence": "围绕当前问题取得可以核实的证据。",
		"claim_position": "通过组织程序与现实支持争取职位。",
		"join_organization": "申请成为组织成员，并接受相应义务。",
		"leave_organization": "退出组织，放弃成员权利与联系。",
		"sabotage": "干扰他人的具体计划，失败或暴露会产生后果。",
	}
	return str(explanations.get(effect, method.get("expected_consequence", "结果取决于现实条件和对方反应。")))


static func _method_preparation_hint(method: Dictionary) -> String:
	if bool(method.get("illegal", false)):
		return "准备重点：隐蔽、退路和暴露风险"
	var location_kind: String = str(method.get("location_kind", ""))
	if location_kind == "target":
		return "准备重点：了解对方态度并确认见面条件"
	if location_kind == "organization":
		return "准备重点：确认组织程序、身份与支持者"
	if str(method.get("effect", "")) in ["information", "evidence"]:
		return "准备重点：明确问题并核对消息来源"
	return "准备重点：预留时间、确认地点和承担成本"


static func _preparation_label(value: int) -> String:
	if value < 300:
		return "直接行动"
	if value < 600:
		return "确认对象与地点"
	return "收集信息并预留更多时间"


static func _urgency_label(value: int) -> String:
	if value >= 750:
		return "迫切"
	if value >= 450:
		return "需要处理"
	return "可以观察"


static func _message_type_label(content_type: String) -> String:
	return str({
		"greeting": "问候",
		"greeting_reply": "回复问候",
		"private_reply": "私人回信",
		"appointment_invitation": "约见邀请",
		"appointment_reply": "约见回复",
		"introduction_request": "介绍请求",
		"introduction_reply": "介绍回复",
		"organization_notice": "组织通知",
	}.get(content_type, "私人消息"))


static func _default_message_text(content_type: String) -> String:
	return str({
		"greeting": "对方向你致以问候，并希望近期交谈。",
		"greeting_reply": "对方回复了此前的问候。",
		"private_reply": "对方回复了此前的私人通信。",
		"appointment_invitation": "对方邀请你在约定时间见面。",
		"appointment_reply": "对方已经回应约见安排。",
		"introduction_request": "有人请求通过你认识另一位人物。",
		"introduction_reply": "中间人已经回应介绍请求。",
	}.get(content_type, "这是一封私人消息。"))


static func _message_status_label(status: String) -> String:
	return str({
		"drafted": "草稿",
		"queued": "等待寄出",
		"in_transit": "投递中",
		"delivered": "未读",
		"read": "已读",
		"replied": "已回复",
		"failed": "投递失败",
		"cancelled": "已取消",
	}.get(status, "状态未知"))


static func _knowledge_source_label(source: String) -> String:
	return str({
		"direct_observation": "亲自观察",
		"message": "私人通信",
		"reported": "他人转述",
		"public_notice": "公开消息",
		"organization_notice": "组织消息",
		"appointment": "实际约见",
		"inference": "人物推断",
	}.get(source, "来源未说明"))


static func _knowledge_status_label(status: String) -> String:
	return str({
		"confirmed": "已确认",
		"reported": "尚未核实",
		"contradicted": "存在矛盾",
		"uncertain": "不确定",
	}.get(status, "尚未核实"))


static func _knowledge_freshness_label(freshness: String) -> String:
	return str({
		"current": "仍然有效",
		"stale": "可能已经变化",
		"expired": "已经过时",
	}.get(freshness, "时间状态未知"))


static func _confidence_label(value: int) -> String:
	if value >= 850:
		return "很可信"
	if value >= 600:
		return "较可信"
	if value >= 350:
		return "可信度有限"
	return "未经证实"


func _selection_changed(message: String) -> V2LifeLoopResult:
	last_command_result = V2LifeLoopResult.ok(message)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


static func _contains_id(records: Array[Dictionary], field: String, value: String) -> bool:
	if value.is_empty():
		return false
	for record: Dictionary in records:
		if str(record.get(field, "")) == value:
			return true
	return false
