class_name V2LifeLoopUiBindingPolish
extends V2LifeLoopUiBinding
## V2.2.1 presentation additions for data-driven contacts and explicit blocking-panel
## time feedback.


func begin_blocking_panel() -> void:
	super.begin_blocking_panel()
	view_changed.emit()


func end_blocking_panel() -> void:
	super.end_blocking_panel()
	view_changed.emit()


func contact_options(person_id: String = "") -> Array[Dictionary]:
	var resolved_person_id: String = (
		simulation.selected_person_id if person_id.is_empty() else person_id
	)
	var result: Array[Dictionary] = []
	for relation: Dictionary in simulation.relationships.contact_candidates(
		resolved_person_id
	):
		var target_id: String = str(relation.get("target_id", ""))
		result.append({
			"target_id": target_id,
			"display_name_zh": simulation.relationships.contact_display_name(relation),
			"native_name": str(relation.get("target_native_name", "")),
			"familiarity": int(relation.get("familiarity", 0)),
			"trust": int(relation.get("trust", 0)),
			"last_contact_datetime": str(
				relation.get("last_contact_datetime", "")
			),
			"recent_interactions": (
				relation.get("recent_interactions", []) as Array
			).duplicate(true),
		})
	return result


func person_view(person_id: String = "") -> Dictionary:
	var view: Dictionary = super.person_view(person_id)
	var resolved_person_id: String = str(view.get("person_id", ""))
	var contacts: Array[Dictionary] = contact_options(resolved_person_id)
	view["relationships"] = contacts
	view["relationship"] = contacts[0].duplicate(true) if not contacts.is_empty() else {}
	_decorate_contact_activity(view.get("current_activity", {}) as Dictionary, resolved_person_id)
	_decorate_contact_activity(view.get("next_activity", {}) as Dictionary, resolved_person_id)
	return view


func contact_activity_proposal(target_id: String) -> V2LifeLoopResult:
	var polish: V2LifeLoopSimulationPolish = simulation as V2LifeLoopSimulationPolish
	if polish == null:
		return V2LifeLoopResult.fail(
			"contact_scheduler_unavailable", "联系人日程服务不可用"
		)
	return polish.suggest_contact_activity(simulation.selected_person_id, target_id)


func submit_contact_activity(
	target_id: String, start_hour: int, duration_hours: int
) -> V2LifeLoopResult:
	var polish: V2LifeLoopSimulationPolish = simulation as V2LifeLoopSimulationPolish
	if polish == null:
		last_command_result = V2LifeLoopResult.fail(
			"contact_scheduler_unavailable", "联系人日程服务不可用"
		)
	else:
		last_command_result = polish.request_contact_activity(
			simulation.selected_person_id, target_id, start_hour, duration_hours
		)
	view_changed.emit()
	return last_command_result


func schedule_contact_next(target_id: String) -> V2LifeLoopResult:
	var polish: V2LifeLoopSimulationPolish = simulation as V2LifeLoopSimulationPolish
	if polish == null:
		last_command_result = V2LifeLoopResult.fail(
			"contact_scheduler_unavailable", "联系人日程服务不可用"
		)
	else:
		last_command_result = polish.request_next_contact(
			simulation.selected_person_id, target_id
		)
	view_changed.emit()
	return last_command_result


func contact_name(target_id: String, person_id: String = "") -> String:
	var resolved_person_id: String = (
		simulation.selected_person_id if person_id.is_empty() else person_id
	)
	return simulation.relationships.target_display_name(
		resolved_person_id, target_id
	)


func _decorate_contact_activity(activity: Dictionary, person_id: String) -> void:
	if str(activity.get("activity_type", "")) != "social_contact":
		return
	var target_id: String = str(activity.get("related_entity_id", ""))
	if target_id.is_empty():
		target_id = simulation.relationships.first_contact_target(person_id)
	var target_name: String = simulation.relationships.target_display_name(
		person_id, target_id
	)
	activity["label"] = (
		"联系关系人物" if target_name.is_empty() else "联系%s" % target_name
	)
