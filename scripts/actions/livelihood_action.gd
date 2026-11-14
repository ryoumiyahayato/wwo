class_name LivelihoodAction
extends RefCounted
## Same current-player/alive boundary used by host DefendAction. Economic checks
## remain in the injected slice and never mutate the clock.
## buy locks seller_site and buyer_site; households specify need_category.
## transfer_goods and set_site_status require the existing explicit firm manager.
## query_firm returns each site's stock and operations plus the shared money view.

static func execute(world: WorldState, person_id: String, command: Dictionary) -> Dictionary:
	if world == null: return {"accepted": false, "reason": "FEATURE_OFF"}
	if person_id != world.player_state.player_id() or not world.person_overlay.has_person(person_id) or not world.person_overlay.is_alive(person_id):
		return {"accepted": false, "reason": "NOT_CURRENT_ACTIVE_PERSON"}
	if command.get("kind") == "work" and not world.rust_character_work_allowed:
		return {"accepted": false, "reason": "身体状况无法承担工作"}
	if command.get("kind") in ["terminate_legacy_wage", "cancel_legacy_arrangement", "convert_legacy_arrangement"]:
		return world.personal_economy_state.request_livelihood_change(person_id, command)
	if world.economy_r1 == null: return {"accepted": false, "reason": "FEATURE_OFF"}
	return world.economy_r1.submit(person_id, command)

static func query(world: WorldState, person_id: String) -> Dictionary:
	if world == null or world.economy_r1 == null or person_id != world.player_state.player_id() or not world.person_overlay.has_person(person_id) or not world.person_overlay.is_alive(person_id):
		return {}
	return world.economy_r1.visible(person_id)

static func query_exchange_input(world: WorldState, person_id: String, quote_id: String, target_amount: int) -> Dictionary:
	if world == null or world.economy_r1 == null or person_id != world.player_state.player_id() or not world.person_overlay.has_person(person_id) or not world.person_overlay.is_alive(person_id):
		return {}
	return world.economy_r1.exchange_input(person_id, quote_id, target_amount)


static func query_firm(world: WorldState, person_id: String, firm_id: String) -> Dictionary:
	if world == null or world.economy_r1 == null or person_id != world.player_state.player_id() or not world.person_overlay.has_person(person_id) or not world.person_overlay.is_alive(person_id):
		return {}
	return world.economy_r1.managed_firm(person_id, firm_id)

static func execute_current(world: WorldState, kind: String, payload: Dictionary) -> Dictionary:
	if world == null: return {"accepted": false, "reason": "FEATURE_OFF"}
	var person := world.player_state.player_id()
	var id := "livelihood:"+person+":"+str(world.personal_economy_state._livelihood_changes.size()+1) if kind in ["terminate_legacy_wage", "cancel_legacy_arrangement", "convert_legacy_arrangement"] else world.economy_r1.next_person_action_id() if world.economy_r1 != null else ""
	return execute(world, person, {"action_id": id, "minute": world.game_clock.total_minutes(), "kind": kind, "payload": payload})

static func query_business(world: WorldState, person_id: String, firm_id: String, site_id: String, quantity: int=1, offset: int=0) -> Dictionary:
	if world==null or world.economy_r1==null or person_id!=world.player_state.player_id() or not world.person_overlay.is_alive(person_id): return {}
	return world.economy_r1.business_view(person_id,firm_id,site_id,quantity,offset)
