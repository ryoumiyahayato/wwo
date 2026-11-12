class_name FormalWorldPresenter
extends RefCounted
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")

static func refresh_player_marker(world: WorldState, renderer: GlobeRenderer) -> void:
	var place := world.spatial_world.get_place(world.person_overlay.current_place(world.player_state.player_id()))
	renderer.set_player_place(place)
## Builds detached page/map inputs. Holds no world state and writes no domain owner.

static func refresh_ui(world: WorldState, shell: MainShell, controller: GlobeController, politics: RuntimePoliticalEntityView, economy: FormalWorldEconomyView, organizations: FormalWorldOrganizationView, responsibilities: FormalWorldOrganizationResponsibilityView) -> Dictionary:
	shell.set_date(world.game_clock.current_date())
	var person_id := world.player_state.player_id()
	var person: Dictionary = {}
	var place: Dictionary = {}
	var local_id := ""
	var work_drawer := shell.current_page=="organization" and shell.organization_page.work_open()
	if shell.current_page in ["person","economy"] or work_drawer:
		person = world.person_overlay.person(person_id)
		place = world.spatial_world.get_place(str(person.get("current_place_id","")))
		var source_id := str(place.get("parent_country_id",person.get("population_territory_id","")))
		if politics.runtime_id_for_source(source_id).is_empty():
			var mapped_source := world.population_state.unit_for_place(str(person.get("current_place_id","")))
			if not politics.runtime_id_for_source(mapped_source).is_empty(): source_id = mapped_source
		local_id = politics.runtime_id_for_source(source_id)
	var memberships: Array[Dictionary] = []
	var organization_rows: Array[Dictionary] = []
	if shell.current_page in ["person","organization","world"]:
		var appointments := organizations.appointments_for_person(person_id)
		var member_records := organizations.memberships_for_person(person_id)
		var member_ids: Dictionary = {}
		for member: Dictionary in member_records: member_ids[str(member.organization_id)] = true
		var status_names := {"MONITORING":"正在观察","ATTENTION_REQUIRED":"需要关注","NO_DETAILED_ECONOMY":"无高细节经济资料","ORGANIZATION_INACTIVE":"组织非活跃"}
		var organization_ids: Array[String] = []
		if shell.current_page in ["organization","world"]: organization_ids.assign(organizations.organization_ids())
		if shell.current_page=="person":
			for relation: Dictionary in member_records+appointments:
				var id := str(relation.organization_id)
				if not id in organization_ids: organization_ids.append(id)
		for organization_id: String in organization_ids:
			if shell.current_page=="world" and organizations.organization_kind(organization_id)!="government_body": continue
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
			row["player_positions"]=roles
			organization_rows.append(row)
		shell.organization_page.refresh(organization_rows,memberships)
		if shell.current_page=="organization":
			var work_view := world.personal_economy_state.person_economy(person_id)
			shell.organization_page.has_personal_work=bool(work_view.get("native",false)) or not (work_view.get("handover",[]) as Array).is_empty()
	if shell.current_page=="person" or work_drawer:
		var section := "native" if work_drawer else shell.person_page.section
		var personal := world.personal_economy_state.person_economy(person_id)
		personal["opening_participation"] = world.economy_r1.opening_participation(person_id) if world.economy_r1!=null else {}
		personal["handover"] = world.economy_r1.responsibility_handover_view(person_id) if world.economy_r1 != null else []
		if section=="situation": personal["livelihood_state"] = world.personal_economy_state.livelihood_view(person_id)
		if section in ["situation","native"]: personal["residence"] = world.population_state.residence_view(world, person_id)
		if section=="native":
			personal["native_lifecycle"] = world.economy_r1.person_management_view(person_id) if world.economy_r1 != null else {"active": false, "future_authority": "LEGACY_RESIDENT_MACRO_AND_FORMAL_PERSONAL"}
			personal["travel"] = world.person_travel.view(person_id) if world.person_travel != null else {}
			personal["travel_destinations"] = world.person_travel.destinations(person_id) if world.person_travel != null else []
			var native_view := LivelihoodAction.query(world, person_id)
			personal["totals"] = native_view.get("totals",{})
			personal["income_by_currency"] = native_view.get("income_by_currency",{})
			personal["minute"] = native_view.get("minute",world.game_clock.total_minutes())
			personal["wage_rows"] = world.economy_r1.personal_wage_rows(person_id,4,shell.person_page.native_wage_page*3) if world.economy_r1 != null and shell.person_page.native_tab=="wages" else []
			personal["workplace_handovers"] = world.economy_r1.personal_material_handovers(person_id) if world.economy_r1 != null and shell.person_page.native_tab=="wages" else []
			personal["wage_outstanding"] = native_view.get("wage_outstanding",0)
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
			if not work_drawer and shell.person_page.business_mode and not managers.is_empty():
				var firm_ids:Array=managers.map(func(row:Dictionary)->String:return str(row["firm_id"]))
				if shell.person_page.business_firm_id.is_empty():shell.person_page.business_firm_id=str(firm_ids[clampi(shell.person_page.business_firm_index,0,firm_ids.size()-1)])
				var index:=firm_ids.find(shell.person_page.business_firm_id)
				if index>=0:
					shell.person_page.business_firm_index=index
					var firm_id:=shell.person_page.business_firm_id
					var sites := world.economy_r1._spec["firms"][firm_id]["sites"] as Array
					if shell.person_page.business_site_id.is_empty():shell.person_page.business_site_id=str(sites[clampi(shell.person_page.business_site_index,0,sites.size()-1)])
					var site_index:=sites.find(shell.person_page.business_site_id)
					if site_index>=0:
						shell.person_page.business_site_index=site_index
						business=LivelihoodAction.query_business(world,person_id,firm_id,shell.person_page.business_site_id,shell.person_page.quantity_milli,shell.person_page.business_offer_page)
						if shell.person_page.business_offer_page>0 and business.get("offers",[]).is_empty():
							shell.person_page.business_offer_page=0
							business=LivelihoodAction.query_business(world,person_id,firm_id,shell.person_page.business_site_id,shell.person_page.quantity_milli)
			shell.person_page.refresh_business(business)
		var account := str(personal.get("account_id",""))
		var receipt_rows := PersonView.receipt_page_size(shell.workspace_rect().size.y)
		var receipts: Array[Dictionary] = []
		if section in ["situation","accounts"]:
			var count := 3 if section=="situation" else receipt_rows+1
			var offset := 0 if section=="situation" else shell.person_page.account_page*receipt_rows
			receipts = world.economy_r1.personal_transaction_rows(person_id,count,offset) if world.economy_r1 != null and world.economy_r1.personal_accounts().has(person_id) else world.ledger_state.transactions_for_account(account,count,offset)
		var property_view: Dictionary = {}
		var goods := world.personal_economy_state
		if section in ["situation","goods"]:
			var count := PersonView.inventory_page_size(shell.person_inventory_height())
			property_view["rows"] = goods.holding_rows(person_id,count+1,shell.person_page.inventory_page*count if section=="goods" else 0)
		if section=="records":
			property_view["records"] = goods.living_records(person_id,receipt_rows+1,shell.person_page.living_page*receipt_rows)
			property_view["record"] = goods.living_record(person_id,shell.person_page.selected_record_id)
		if section=="goods" and not shell.person_page.selected_commodity_id.is_empty():
			property_view["selected"] = goods.holding(person_id,shell.person_page.selected_commodity_id)
			property_view["capability"] = goods.commodity_capability(person_id,shell.person_page.selected_commodity_id)
			property_view["quote"] = goods.consumption_quote(person_id,shell.person_page.selected_commodity_id,shell.person_page.quantity_milli)
			property_view["arrangement"] = goods.arrangement(person_id,shell.person_page.selected_commodity_id)
			property_view["conversion_quote"] = goods.arrangement_conversion_quote(person_id, shell.person_page.selected_commodity_id) if not goods.manages_native(person_id) else {}
			if goods.manages_native(person_id): property_view["custody_quote"] = world.economy_r1.personal_custody_quote(person_id, shell.person_page.selected_commodity_id, shell.person_page.quantity_milli)
		if personal.get("native",false):
			for row: Dictionary in property_view.get("rows",[])+property_view.get("records",[]):
				if str(row.get("commodity_id","")).begins_with("native:"): row["name_zh"]=EconomicText.good(row["commodity_id"])
			for key: String in ["selected","capability","record"]:
				var row:=property_view.get(key,{}) as Dictionary
				if str(row.get("commodity_id","")).begins_with("native:"): row["name_zh"]=EconomicText.good(row["commodity_id"])
		shell.person_page.refresh(person,place,memberships,personal,receipts,property_view)
	if shell.current_page=="economy":
		var selected_id: String=shell.economy_page.polity_id
		if not politics.has_entity(selected_id): selected_id=controller.player_polity_id if politics.has_entity(controller.player_polity_id) else local_id
		var managed: bool=world.personal_economy_state.manages_native(person_id)
		var polity: Dictionary=CurrentWorldPoliticalProjection.polity_summary(selected_id,politics,world.historical_evidence_view)
		var market: Dictionary=world.economy_r1.market_display_view(person_id,shell.economy_page.content in ["quotes","activity"]) if managed and world.economy_r1!=null else {}
		if managed and world.economy_r1!=null and shell.economy_page.content=="transport":
			var places: Array[String]=[]
			for hub: Dictionary in world.economy_r1.market_hub_view(person_id,[],96).get("hubs",[]):
				var id := str(hub.get("place_id",""))
				if shell.economy_page._in_scope(id): places.append(id)
			market["logistics"]=world.economy_r1.logistics_map_view(person_id,places,true)
		var countries: Array[Dictionary]=[]
		var seen: Dictionary={}
		for region: Dictionary in market.get("places",[]):
			var id: String=politics.runtime_id_for_source(str(region.parent_country_id))
			if id.is_empty() or seen.has(id): continue
			seen[id]=true
			var country: Dictionary=CurrentWorldPoliticalProjection.polity_summary(id,politics,world.historical_evidence_view)
			countries.append({"id":id,"name_zh":country.get("name_zh",id)})
		market["countries"]=countries
		if shell.economy_page.market_scope!="regional":
			var region_valid: bool=false
			var candidate: String=""
			for region: Dictionary in shell.economy_page.region_choices():
				if region.has("polity_id") and str(region.polity_id)!=selected_id: continue
				if str(region.place_id)==shell.economy_page.region_id: region_valid=true
				if candidate.is_empty() or str(region.place_id)==str(person.get("current_place_id","")): candidate=str(region.place_id)
			if not region_valid: shell.economy_page.region_id=candidate
		var offer: Dictionary={}
		var selected_item: Dictionary={}
		if managed and not shell.economy_page.selected_commodity_id.is_empty():
			var good: String=shell.economy_page.selected_commodity_id
			var site: String=shell.economy_page.selected_seller_site_id
			selected_item=world.personal_economy_state.commodity_capability(person_id,good,site)
			for row: Dictionary in market.get("offers",[]):
				if row.commodity_id==good and row.seller_site==site: selected_item.merge(row,true);break
			offer=world.personal_economy_state.purchase_quote(person_id,site,good,shell.economy_page.quantity_milli)
			if offer.get("success",false):
				selected_item["price"]=offer["unit_price"];selected_item["denomination"]=offer["denomination"]
		shell.economy_page.refresh(polity,economy,selected_id,[],offer,selected_item,managed,{"market":market})
	# The application also needs this already-prepared personal location; it
	# must not query the person and place again after consuming the page.
	return place

static func map_units(world: WorldState, politics: RuntimePoliticalEntityView) -> Array[Dictionary]:
	return CurrentWorldPoliticalProjection.map_units(politics,world.historical_evidence_view)

static func refresh_map(world: WorldState, renderer: GlobeRenderer, content: ResolvedMapContent, politics: RuntimePoliticalEntityView, economy: FormalWorldEconomyView) -> void:
	var places: Array[Dictionary] = []
	for place_id: String in world.spatial_catalog.place_map_ids():
		var place := world.spatial_world.get_place(place_id)
		if str(place.get("spatial_kind", "")) in ["city", "port"]:
			places.append(place)
	renderer.refresh(politics,world.historical_evidence_view,economy,places,world.game_clock.current_date(),content)
	renderer.bind_current_politics(world.spatial_world,world.territory_state)
	renderer.refresh_civilian_facilities(preload("res://scripts/presentation/map/civilian_facility_layer.gd").observation(world))

static func show_initialization_error(shell: MainShell, message: String) -> void:
	shell.show_feedback("正式世界初始化失败：" + message,"","system","error")

static func show_new_world(shell: MainShell) -> void:
	shell.show_feedback("新的1900正式世界已建立。")

static func show_advance_error(shell: MainShell, message: String) -> void:
	shell.show_feedback("正式时间推进失败：" + message,"","system","error")

static func show_save_result(shell: MainShell, result: SaveOperationResult) -> void:
	shell.show_feedback(result.message if not result.message.is_empty() else ("正式世界已保存。" if result.success else "正式世界保存失败。"),"","system","info" if result.success else "error")

static func show_load_result(shell: MainShell, result: SaveOperationResult) -> void:
	shell.show_feedback(result.message if not result.message.is_empty() else ("正式世界存档已恢复。" if result.success else "没有可恢复的正式世界存档。"),"","system","info" if result.success else "error")
