class_name V23ControlledUiBindingV2
extends V23ControlledUiBinding
## Explicit social-plan construction. The UI no longer submits the first goal
## with an implicit target and implicit time.

var _sandbox_selection_by_person: Dictionary = {}


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
	var methods: Array[Dictionary] = product.social_sandbox.methods_for(
		resolved_id, goal_id
	)
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
	var start_hour: int = int(selection.get("start_hour", current_hour + 2))
	if start_hour <= current_hour:
		start_hour = current_hour + 2
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
	return {
		"available": true,
		"person_id": resolved_id,
		"situations": product.social_sandbox.situations_for(resolved_id),
		"goals": goals,
		"selected_goal_id": goal_id,
		"methods": methods,
		"selected_method_id": method_id,
		"targets": targets,
		"selected_target_id": target_id,
		"selected_start_hour": start_hour,
		"selected_start_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"preparation": preparation,
		"preview": preview,
		"tasks": product.social_sandbox.tasks_for(resolved_id, true),
		"events": product.social_sandbox.visible_events_for(
			resolved_id, product.truth_view, 12
		),
		"explanation": (
			product.social_sandbox.explanation_for(resolved_id)
			if product.truth_view else {}
		),
	}


func select_sandbox_goal(goal_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "社会沙盒不可用")
	var person_id: String = selected_person_id()
	if not _contains_id(product.social_sandbox.goals_for(person_id), "goal_id", goal_id):
		return V2LifeLoopResult.fail("unknown_goal", "目标已经失效")
	var selection: Dictionary = _selection_for(person_id)
	selection["goal_id"] = goal_id
	selection["method_id"] = ""
	selection["target_id"] = ""
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已选择社会目标")


func select_sandbox_method(method_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "社会沙盒不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var methods: Array[Dictionary] = product.social_sandbox.methods_for(
		person_id, str(selection.get("goal_id", ""))
	)
	if not _contains_id(methods, "method_id", method_id):
		return V2LifeLoopResult.fail("unknown_method", "该方法不适用于当前目标")
	selection["method_id"] = method_id
	selection["target_id"] = ""
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已选择行动方法")


func select_sandbox_target(target_id: String) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "社会沙盒不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var method: Dictionary = product.social_sandbox.method_record(
		str(selection.get("method_id", ""))
	)
	if target_id.is_empty() and not product.social_sandbox._method_requires_target(method):
		selection["target_id"] = ""
		_sandbox_selection_by_person[person_id] = selection
		return _selection_changed("该行动不需要人物对象")
	var targets: Array[Dictionary] = _target_options(product, person_id, method)
	if not _contains_id(targets, "person_id", target_id):
		return V2LifeLoopResult.fail("unknown_target", "该人物不是当前可选对象")
	selection["target_id"] = target_id
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已选择行动对象")


func shift_sandbox_start(delta_hours: int) -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "社会沙盒不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var minimum: int = product.clock.total_hours + 1
	var maximum: int = product.clock.total_hours + 72
	selection["start_hour"] = clampi(
		int(selection.get("start_hour", minimum + 1)) + delta_hours,
		minimum,
		maximum
	)
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已调整行动时间")


func set_sandbox_preparation(value: int) -> V2LifeLoopResult:
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	selection["preparation"] = clampi(value, 0, 900)
	_sandbox_selection_by_person[person_id] = selection
	return _selection_changed("已调整准备程度")


func submit_selected_sandbox_plan() -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "社会沙盒不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var goal_id: String = str(selection.get("goal_id", ""))
	var method_id: String = str(selection.get("method_id", ""))
	if goal_id.is_empty() or method_id.is_empty():
		return V2LifeLoopResult.fail("incomplete_social_plan", "请先选择目标和行动方法")
	last_command_result = product.social_sandbox.submit_intent(
		person_id,
		goal_id,
		method_id,
		str(selection.get("target_id", "")),
		"player",
		{
			"current_hour": product.clock.total_hours,
			"start_hour": int(selection.get("start_hour", product.clock.total_hours + 2)),
			"preparation": int(selection.get("preparation", 400)),
			"location_id": str(selection.get("location_id", "")),
			"organization_id": str(selection.get("organization_id", "")),
		}
	)
	if last_command_result.success:
		selection["start_hour"] = product.clock.total_hours + 2
		_sandbox_selection_by_person[person_id] = selection
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func _selection_for(person_id: String) -> Dictionary:
	var value: Variant = _sandbox_selection_by_person.get(person_id, {})
	var selection: Dictionary = (
		(value as Dictionary).duplicate(true) if value is Dictionary else {}
	)
	if not selection.has("start_hour") and controlled_simulation != null:
		selection["start_hour"] = controlled_simulation.clock.total_hours + 2
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


func _selection_changed(message: String) -> V2LifeLoopResult:
	last_command_result = V2LifeLoopResult.ok(message)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


static func _contains_id(
	records: Array[Dictionary], field: String, value: String
) -> bool:
	if value.is_empty():
		return false
	for record: Dictionary in records:
		if str(record.get(field, "")) == value:
			return true
	return false
