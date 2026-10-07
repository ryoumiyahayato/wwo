class_name FormalWorldPresenter
extends RefCounted
## Builds detached page/map inputs. Holds no world state and writes no domain owner.

static func refresh_ui(world: WorldState, shell: MainShell, controller: GlobeController, content: WorldPageContent) -> void:
	if world.game_clock == null:
		return
	var politics := RuntimePoliticalEntityView.new(world.political_registry.snapshot())
	var economy := FormalWorldEconomyView.new(world.economy_state.read_only_presentation_snapshot())
	var organizations := FormalWorldOrganizationView.new(world.organization_state.snapshot())
	var person_id := world.player_state.player_id()
	var person := world.person_overlay.person(person_id)
	var place := world.spatial_world.get_place(str(person.get("current_place_id", "")))
	var source_id := str(place.get("parent_country_id", person.get("population_territory_id", "")))
	var local_id := politics.runtime_id_for_source(source_id)
	var selected_id := controller.selected_polity_id if politics.has_entity(controller.selected_polity_id) else politics.runtime_id_for_source(str(person.get("population_territory_id", "")))
	shell.set_date(world.game_clock.current_date())
	shell.person_page.refresh(person, place, CurrentWorldPoliticalProjection.polity_summary(local_id, politics, world.historical_evidence_view, economy), organizations.memberships_for_person(person_id), Callable(world.personal_economy_state, "person_economy"))
	var summary := world.economy_state.world_summary()
	summary["world_political_unit_count"] = world.political_registry.entity_count()
	summary["historical_political_record_count"] = world.historical_evidence.record_count()
	summary["formal_person_count"] = world.person_overlay.person_count()
	summary["background_polity_count"] = maxi(0, world.political_registry.entity_count() - int(summary.get("detailed_polity_unit_count", 0)))
	shell.economy_page.refresh(CurrentWorldPoliticalProjection.polity_summary(selected_id, politics, world.historical_evidence_view, economy), summary, economy, selected_id)
	shell.organization_page.refresh(organizations, world.organization_evidence_view, FormalWorldOrganizationResponsibilityView.new(world.organization_responsibility.read_only_snapshot()), person_id)
	var selected_place: Dictionary = {}
	if not controller.selected_place_id.is_empty():
		selected_place = world.spatial_world.get_place(controller.selected_place_id)
		if selected_place.is_empty():
			selected_place = content.place()
	shell.world_page.refresh(CurrentWorldPoliticalProjection.polity_summary(controller.selected_polity_id, politics, world.historical_evidence_view, economy), selected_place, content)

static func selected_world_polity(world: WorldState, controller: GlobeController) -> Dictionary:
	return CurrentWorldPoliticalProjection.polity_summary(controller.selected_polity_id, RuntimePoliticalEntityView.new(world.political_registry.snapshot()), world.historical_evidence_view)

static func map_units(world: WorldState) -> Array[Dictionary]:
	return CurrentWorldPoliticalProjection.map_units(RuntimePoliticalEntityView.new(world.political_registry.snapshot()), world.historical_evidence_view)

static func refresh_map(world: WorldState, renderer: GlobeRenderer, content: ResolvedMapContent) -> void:
	var places: Array[Dictionary] = []
	for place_id: String in world.spatial_catalog.place_map_ids():
		var place := world.spatial_world.get_place(place_id)
		if str(place.get("spatial_kind", "")) in ["city", "port"]:
			places.append(place)
	renderer.refresh(RuntimePoliticalEntityView.new(world.political_registry.snapshot()), world.historical_evidence_view, FormalWorldEconomyView.new(world.economy_state.read_only_presentation_snapshot()), places, world.game_clock.current_date(), content)

static func show_initialization_error(shell: MainShell, message: String) -> void:
	shell.status_message = "正式世界初始化失败：" + message

static func show_new_world(shell: MainShell) -> void:
	shell.status_message = "新的1900正式世界已建立。"

static func show_advance_error(shell: MainShell, message: String) -> void:
	shell.status_message = "正式时间推进失败：" + message

static func show_save_result(shell: MainShell, result: SaveOperationResult) -> void:
	shell.status_message = result.message if not result.message.is_empty() else ("正式世界已保存。" if result.success else "正式世界保存失败。")

static func show_load_result(shell: MainShell, result: SaveOperationResult) -> void:
	shell.status_message = result.message if not result.message.is_empty() else ("正式世界存档已恢复。" if result.success else "没有可恢复的正式世界存档。")
