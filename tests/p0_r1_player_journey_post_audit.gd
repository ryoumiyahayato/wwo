extends "res://tests/p0_r1_player_journey_current.gd"
## Final post-audit journey entry. Option selection and signal emission are
## synchronous, so this override avoids returning a coroutine from a bool helper.


func _start_action_via_ui(
	action_id: String,
	target_id: String,
	extra_funding: int
) -> bool:
	var action_option: OptionButton = _action_panel.find_child(
		"ActionOption", true, false
	) as OptionButton
	if not _select_option_by_metadata(action_option, action_id):
		return false
	if action_id in ["action:promote_policy", "action:support_control"]:
		_action_panel.set_target(target_id)
	var target_option: OptionButton = _action_panel.find_child(
		"TargetOption", true, false
	) as OptionButton
	if not target_id.is_empty() and not _select_option_by_metadata(
		target_option, target_id
	):
		return false
	var investment: SpinBox = _action_panel.find_child(
		"InvestmentSpin", true, false
	) as SpinBox
	if investment != null:
		investment.value = minf(
			float(extra_funding), investment.max_value
		)
		investment.value_changed.emit(investment.value)
	var begin_button: Button = _action_panel.get_node_or_null(
		"Margin/Root/BeginButton"
	) as Button
	if (
		begin_button == null
		or begin_button.disabled
		or not begin_button.is_visible_in_tree()
	):
		return false
	begin_button.pressed.emit()
	return (
		GameSessionService.current_action != null
		and GameSessionService.current_action.definition_id == action_id
	)
