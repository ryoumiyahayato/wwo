class_name FormalWorldPresenter
extends RefCounted
## Builds detached page/map inputs. Holds no world state and writes no domain owner.

static func refresh_ui(world: WorldState, shell: MainShell, controller: GlobeController, content: WorldPageContent, politics: RuntimePoliticalEntityView, economy: FormalWorldEconomyView, organizations: FormalWorldOrganizationView, responsibilities: FormalWorldOrganizationResponsibilityView) -> void:
	shell.set_date(world.game_clock.current_date())
	var person_id := world.player_state.player_id()
	var person := world.person_overlay.person(person_id)
	var place := world.spatial_world.get_place(str(person.get("current_place_id","")))
	var source_id := str(place.get("parent_country_id",person.get("population_territory_id","")))
	if politics.runtime_id_for_source(source_id).is_empty():
		var mapped_source := world.population_state.unit_for_place(str(person.get("current_place_id","")))
		if not politics.runtime_id_for_source(mapped_source).is_empty(): source_id = mapped_source
	var local_id := politics.runtime_id_for_source(source_id)
	var memberships: Array[Dictionary] = []
	var organization_rows: Array[Dictionary] = []
	if shell.current_page in ["person","organization"]:
		var appointments := organizations.appointments_for_person(person_id)
		var member_records := organizations.memberships_for_person(person_id)
		var member_ids: Dictionary = {}
		for member: Dictionary in member_records: member_ids[str(member.organization_id)] = true
		var status_names := {"MONITORING":"正在观察","ATTENTION_REQUIRED":"需要关注","NO_DETAILED_ECONOMY":"无高细节经济资料","ORGANIZATION_INACTIVE":"组织非活跃"}
		var organization_ids: Array[String] = organizations.organization_ids() if shell.current_page=="organization" else []
		if shell.current_page=="person":
			for relation: Dictionary in member_records+appointments:
				var id := str(relation.organization_id)
				if not id in organization_ids: organization_ids.append(id)
		for organization_id: String in organization_ids:
			var row := organizations.organization(organization_id)
			var basis := world.organization_evidence_view.organization_basis(organization_id)
			var represented := politics.runtime_id_for_source(str(basis.get("represented_polity_id","")))
			var polity := CurrentWorldPoliticalProjection.polity_summary(represented,politics,world.historical_evidence_view)
			var name := str(row.get("name_zh",row.get("name","")))
			if name.is_empty(): name = str(polity.get("name_zh","未记录政体"))+"治理机构（规则推定）" if str(row.get("organization_kind",""))=="government_body" and not basis.is_empty() else "组织 · 名称未记录"
			row["label"] = name
			row["kind_label"] = "治理机构" if str(row.get("organization_kind",""))=="government_body" else str(row.get("organization_kind","未记录"))
			row["basis_label"] = "依据政治身份规则推定；不是历史专名" if str(basis.get("basis_class",""))=="B_INFERRED_INSTITUTION" or not bool(basis.get("historical_exact_name_claimed",true)) else str(basis.get("basis_class","未记录"))
			row["responsibility_label"] = str(status_names.get(responsibilities.responsibility_status(organization_id),"没有职责记录"))
			var current_case := responsibilities.current_case_summary(organization_id)
			row["case_text"] = "当前事项持续 %d 天，统计供应满足率 %.1f%%。" % [int(current_case.get("duration_days",0)),float(current_case.get("current_fulfillment_bp",0))/100.0] if not current_case.is_empty() else "暂无当前事项。"
			var location := world.spatial_world.get_place(str(row.get("primary_place_id","")))
			row["place_id"] = str(location.get("place_id",""))
			if not location.is_empty(): row["place_name"] = str(location.get("name","所在地名称未记录"))
			row["country_id"] = represented
			row["economy_polity_id"] = represented if not economy.economy_entity_for_polity(represented).is_empty() else ""
			var roles: Array[String] = []
			for appointment: Dictionary in appointments:
				if str(appointment.organization_id) == organization_id:
					var position := organizations.position(organization_id,str(appointment.get("position_id","")))
					roles.append(str(position.get("title","任职记录；职务名称未记录")))
			if member_ids.has(organization_id) or not roles.is_empty():
				var role_text := "、".join(roles) if not roles.is_empty() else "成员记录；未记录职务"
				row["player_roles"] = role_text
				memberships.append({"organization_id":organization_id,"label":name,"roles_text":role_text})
			organization_rows.append(row)
		shell.organization_page.refresh(organization_rows,memberships)
	if shell.current_page=="person":
		var personal := world.personal_economy_state.person_economy(person_id)
		personal["livelihood_state"] = world.personal_economy_state.livelihood_view(person_id)
		personal["native_lifecycle"] = world.economy_r1.person_management_view(person_id) if world.economy_r1 != null else {"active": false, "future_authority": "LEGACY_RESIDENT_MACRO_AND_FORMAL_PERSONAL"}
		personal["residence"] = world.population_state.residence_view(world, person_id)
		personal["handover"] = world.economy_r1.responsibility_handover_view(person_id) if world.economy_r1 != null else []
		personal["travel"] = world.person_travel.view(person_id) if world.person_travel != null else {}
		personal["travel_destinations"] = world.person_travel.destinations(person_id) if world.person_travel != null else []
		if shell.current_page == "person" and shell.person_page.section == "native":
			var native_view := LivelihoodAction.query(world, person_id)
			for key: String in ["known_jobs", "orders", "need_today", "managed_firms", "scope_changes", "management_incoming", "can_reenter"]:
				personal[key] = native_view.get(key, [] if key != "need_today" else {})
			personal["cargo_fulfilment"] = native_view.get("cargo_fulfilment", {})
			personal["resident_services"] = native_view.get("resident_services", {})
			personal["labor_market"] = native_view.get("labor_market", {})
			personal["leases"] = native_view.get("leases", {})
			personal["commercial_information"] = native_view.get("commercial_information", [])
			personal["scope_options"] = world.economy_r1.scope_options(person_id) if world.economy_r1 != null else []
			var managers := personal.get("managed_firms",[]) as Array
			var business: Dictionary={}
			if shell.person_page.business_mode and not managers.is_empty():
				shell.person_page.business_firm_index=clampi(shell.person_page.business_firm_index,0,managers.size()-1)
				var firm_id := str(managers[shell.person_page.business_firm_index]["firm_id"])
				var sites := world.economy_r1._spec["firms"][firm_id]["sites"] as Array
				shell.person_page.business_site_index=clampi(shell.person_page.business_site_index,0,sites.size()-1)
				business=LivelihoodAction.query_business(world,person_id,firm_id,sites[shell.person_page.business_site_index],shell.person_page.quantity_milli,shell.person_page.business_offer_page)
				if shell.person_page.business_offer_page>0 and business.get("offers",[]).is_empty():
					shell.person_page.business_offer_page=0
					business=LivelihoodAction.query_business(world,person_id,firm_id,sites[shell.person_page.business_site_index],shell.person_page.quantity_milli)
			shell.person_page.refresh_business(business)
		var account := str(personal.get("account_id",""))
		var receipt_rows := PersonView.receipt_page_size(shell.workspace_rect().size.y)
		var receipts := world.economy_r1.personal_transaction_rows(person_id, receipt_rows+1, shell.person_page.account_page*receipt_rows) if world.economy_r1 != null and world.economy_r1.personal_accounts().has(person_id) else world.ledger_state.transactions_for_account(account,receipt_rows+1,shell.person_page.account_page*receipt_rows)
		var property_view: Dictionary = {}
		if shell.current_page == "person":
			var goods := world.personal_economy_state
			var count := EconomyPage.market_page_size(shell.workspace_rect().size.y)
			property_view = {"rows":goods.holding_rows(person_id,count+1,shell.person_page.inventory_page*count),"selected":goods.holding(person_id,shell.person_page.selected_commodity_id),"records":goods.living_records(person_id,receipt_rows+1,shell.person_page.living_page*receipt_rows),"record":goods.living_record(person_id,shell.person_page.selected_record_id),"capability":goods.commodity_capability(person_id,shell.person_page.selected_commodity_id),"quote":goods.consumption_quote(person_id,shell.person_page.selected_commodity_id,shell.person_page.quantity_milli),"arrangement":goods.arrangement(person_id,shell.person_page.selected_commodity_id)}
			property_view["conversion_quote"] = goods.arrangement_conversion_quote(person_id, shell.person_page.selected_commodity_id) if not goods.manages_native(person_id) else {}
			if goods.manages_native(person_id): property_view["custody_quote"] = world.economy_r1.personal_custody_quote(person_id, shell.person_page.selected_commodity_id, shell.person_page.quantity_milli)
		shell.person_page.refresh(person,place,memberships,personal,receipts,property_view)
	if shell.current_page=="economy":
		var selected_id := shell.economy_page.polity_id
		if not politics.has_entity(selected_id):
			selected_id = controller.selected_polity_id if politics.has_entity(controller.selected_polity_id) else local_id
		var native_market := shell.economy_page.personal_market and world.personal_economy_state.manages_native(person_id)
		var market_rows: Array[Dictionary] = []
		if shell.current_page == "economy":
			var market_id := economy.market_id_for_economic_aggregate(economy.economy_entity_for_polity(selected_id))
			var count := EconomyPage.market_page_size(shell.workspace_rect().size.y)
			if native_market:
				market_rows = world.personal_economy_state.market_rows(person_id,market_id,count+1,shell.economy_page.commodity_page*count)
			else:
				market_rows = world.economy_state.read_only_market_rows(market_id,count+1,shell.economy_page.commodity_page*count)
		var selected_market := shell.economy_page.selected_seller_site_id if native_market else economy.market_id_for_economic_aggregate(economy.economy_entity_for_polity(selected_id))
		var offer: Dictionary = {}
		var selected_item: Dictionary = {}
		if shell.current_page == "economy" and not shell.economy_page.selected_commodity_id.is_empty():
			selected_item = world.personal_economy_state.commodity_capability(person_id,shell.economy_page.selected_commodity_id,selected_market)
			offer = world.personal_economy_state.purchase_quote(person_id,selected_market,shell.economy_page.selected_commodity_id,shell.economy_page.quantity_milli)
			if offer.get("quantity_scale") == 1 and offer.get("success",false):
				selected_item["price"] = offer["unit_price"]
				selected_item["denomination"] = offer["denomination"]
				selected_item["seller_site"] = offer["seller_site"]
		var native_observation: Dictionary = {}
		if shell.current_page == "economy":
			native_observation = world.economy_state.read_only_native_observation(person_id)
			native_observation["cohort_observation"] = world.economy_state.read_only_cohort_observation(person_id, 16, shell.economy_page.cohort_statistics_page*16)
			native_observation["commercial_information"] = world.economy_r1.commercial_information(person_id) if native_market and world.economy_r1 != null else []
			native_observation["managed_sites"] = []
			native_observation["employees"] = []
			native_observation["enterprise_lifecycles"] = []
			native_observation["scope_requests"] = world.economy_r1.scope_change_view(person_id) if world.economy_r1 != null else []
			native_observation["residence_statistics"] = world.population_state.residence_statistics()
			native_observation["commodity_crosswalk"] = world.economy_state.commodity_mapping_observation()
			native_observation["property_handovers"] = world.economy_r1.property_handover_view(person_id) if world.economy_r1 != null else []
			native_observation["handover"] = world.economy_r1.responsibility_handover_view(person_id) if world.economy_r1 != null else []
			var population_unit := economy.economy_entity_for_polity(selected_id)
			native_observation["population_responsibility"] = world.economy_state.read_only_population_responsibility(population_unit)
			native_observation["population_responsibility"]["present_named_people"] = world.population_state.present_named_count(population_unit, world.person_overlay)
			if world.economy_r1 != null:
				for firm: Dictionary in LivelihoodAction.query(world, person_id).get("managed_firms", []):
					var view := LivelihoodAction.query_firm(world, person_id, str(firm["firm_id"]))
					native_observation["employees"].append_array(view.get("employees", []))
					native_observation["enterprise_lifecycles"].append(view.get("lifecycle", {}))
					for site: Dictionary in view.get("operations", []):
						native_observation["managed_sites"].append({"site_id": site["site_id"], "place_id": site["stock_place_id"], "operating": site["operating"], "inventory": site["inventory"], "free_inventory": site["free_inventory"], "committed_inventory": site["committed_inventory"], "job_postings": site["job_postings"], "input_needs": site["input_needs"], "incoming": site["incoming"], "activities": site["activities"], "effective_capacity": site["shared_capacity"], "base_capacity": site["base_capacity"], "plan_day": site.get("plan", {}).get("day", -1)})
		shell.economy_page.refresh(CurrentWorldPoliticalProjection.polity_summary(selected_id,politics,world.historical_evidence_view,economy),economy,selected_id,market_rows,offer,selected_item,native_market,native_observation)
	if shell.current_page in ["world","administration"] or (shell.current_page=="map" and (not controller.selected_polity_id.is_empty() or not controller.selected_place_id.is_empty())):
		var selected_place := world.spatial_world.get_place(controller.selected_place_id)
		var formal_place := not selected_place.is_empty()
		if selected_place.is_empty() and controller.selected_place_id.begins_with("administrative_region:"):
			selected_place = world.spatial_world.administrative_land_summary(controller.selected_place_id,content.date())
		if selected_place.is_empty():
			for unit: Dictionary in content.administration().get("runtime_units",[]) as Array:
				if str(unit.id) == controller.selected_place_id:
					selected_place = unit.duplicate(true)
					selected_place.merge({"place_id":str(unit.id),"spatial_kind":"historical_administration"})
					break
		if selected_place.is_empty(): selected_place = content.place()
		var selected_polity := CurrentWorldPoliticalProjection.polity_summary(controller.selected_polity_id,politics,world.historical_evidence_view,economy)
		var economy_id := controller.selected_polity_id
		if not selected_place.is_empty():
			economy_id = politics.runtime_id_for_source(str(selected_place.get("parent_country_id","")))
		if economy.economy_entity_for_polity(economy_id).is_empty(): economy_id = ""
		var mapped := CurrentWorldPoliticalProjection.polity_summary(economy_id,politics,world.historical_evidence_view)
		shell.world_page.refresh(selected_polity,selected_place,content,formal_place,economy_id,str(mapped.get("name_zh","")))

static func map_units(world: WorldState, politics: RuntimePoliticalEntityView) -> Array[Dictionary]:
	return CurrentWorldPoliticalProjection.map_units(politics,world.historical_evidence_view)

static func refresh_map(world: WorldState, renderer: GlobeRenderer, content: ResolvedMapContent, politics: RuntimePoliticalEntityView, economy: FormalWorldEconomyView) -> void:
	var places: Array[Dictionary] = []
	for place_id: String in world.spatial_catalog.place_map_ids():
		var place := world.spatial_world.get_place(place_id)
		if str(place.get("spatial_kind", "")) in ["city", "port"]:
			places.append(place)
	renderer.refresh(politics,world.historical_evidence_view,economy,places,world.game_clock.current_date(),content)

static func show_initialization_error(shell: MainShell, message: String) -> void:
	shell.show_feedback("正式世界初始化失败：" + message)

static func show_new_world(shell: MainShell) -> void:
	shell.show_feedback("新的1900正式世界已建立。")

static func show_advance_error(shell: MainShell, message: String) -> void:
	shell.show_feedback("正式时间推进失败：" + message)

static func show_save_result(shell: MainShell, result: SaveOperationResult) -> void:
	shell.show_feedback(result.message if not result.message.is_empty() else ("正式世界已保存。" if result.success else "正式世界保存失败。"))

static func show_load_result(shell: MainShell, result: SaveOperationResult) -> void:
	shell.show_feedback(result.message if not result.message.is_empty() else ("正式世界存档已恢复。" if result.success else "没有可恢复的正式世界存档。"))
