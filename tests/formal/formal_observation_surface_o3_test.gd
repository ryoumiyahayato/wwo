extends SceneTree
## O3 contracts: OrganizationCore, Authority, and Responsibility are exposed as
## detached read-only observations without fixture or personal-task leakage.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in range(30):
		await process_frame
	var simulation := application.formal_simulation
	_check(simulation.initialized, "Formal world initializes for O3")
	if not simulation.initialized:
		_finish(application)
		return
	var organizations := simulation.organization_view()
	var catalog := simulation.organization_observation_catalog()
	var rows := catalog.get("rows", []) as Array
	_equal(catalog.get("owner"), "VNextOrganizationCore", "organization catalogue declares the Formal structural owner")
	_equal(int(catalog.get("organization_count", -1)), organizations.organization_count(), "world organization browser count matches Formal query")
	_equal(rows.size(), organizations.organization_count(), "browser contains every Formal organization once")
	_check(not rows.is_empty(), "production Organization browser is non-empty")

	var first_row := rows[0] as Dictionary
	var organization_id := str(first_row.get("organization_id", ""))
	var detail := simulation.organization_observation(organization_id)
	_check(bool(detail.get("available", false)), "organization detail is available")
	_equal(detail.get("organization_kind"), organizations.organization_kind(organization_id), "organization kind matches OrganizationCore")
	_equal(detail.get("parent_organization_id"), organizations.parent_organization_id(organization_id), "organization parent matches OrganizationCore")
	_equal(detail.get("child_organization_ids"), organizations.subordinate_organization_ids(organization_id), "organization children match detached query")
	_equal(detail.get("member_ids"), organizations.member_ids(organization_id), "organization members match OrganizationCore")
	_equal((detail.get("appointments", []) as Array).size(), organizations.appointment_ids(organization_id).size(), "organization appointments match OrganizationCore")
	_equal(detail.get("declared_capability_ids"), organizations.capability_ids(organization_id), "declared capabilities match OrganizationCore")
	_equal(detail.get("responsibilities"), simulation.organization_responsibility_view().responsibilities_for_organization(organization_id), "responsibility detail matches Formal responsibility view")
	var authority_snapshot := simulation.get_persistent_state().get("organization_authority", {}) as Dictionary
	_equal(_expected_grants_for_organization(authority_snapshot, organization_id), detail.get("current_authority_grants"), "authority grants match the Formal Authority owner snapshot")

	var tampered := simulation.organization_observation(organization_id)
	(tampered.get("member_ids", []) as Array).append("person:tampered")
	(tampered.get("composition_evidence", {}) as Dictionary)["basis_class"] = "prototype"
	_check(not (simulation.organization_observation(organization_id).get("member_ids", []) as Array).has("person:tampered"), "organization detail is detached")
	_check(str((simulation.organization_observation(organization_id).get("composition_evidence", {}) as Dictionary).get("basis_class", "")) != "prototype", "composition evidence is detached")

	var person_id := simulation.player_person_id()
	var player_org := simulation.player_organization_observation()
	_equal(player_org.get("person_id"), person_id, "My Records binds the authoritative player")
	_equal(player_org.get("memberships"), organizations.memberships_for_person(person_id), "My Records memberships match Formal query")
	_equal(player_org.get("appointments"), organizations.appointments_for_person(person_id), "My Records appointments match Formal query")
	if organizations.memberships_for_person(person_id).is_empty() and organizations.appointments_for_person(person_id).is_empty():
		_equal(player_org.get("effective_capabilities"), [], "player with no Formal records has no fabricated capability")
		_equal(player_org.get("current_authority_grants"), [], "player with no Formal records has no fabricated Authority grant")

	var responsibilities := simulation.organization_responsibility_observation()
	_equal(responsibilities.get("owner"), "FormalWorldOrganizationResponsibilityService", "responsibility surface declares its Formal owner")
	_equal(responsibilities.get("label"), "organization_world_observation", "responsibility is labelled institution/world observation")
	_equal(int(responsibilities.get("responsibility_count", -1)), simulation.organization_responsibility_view().responsibility_count(), "responsibility browser count matches Formal query")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_ORGANIZATION)
	_check(application._set_organization_tab(FormalWorldApplication.ORGANIZATION_TAB_MY_RECORDS), "My Records tab is available")
	_check(application._set_organization_tab(FormalWorldApplication.ORGANIZATION_TAB_BROWSER), "Organizations tab is available")
	_check(application._select_organization(organization_id), "organization detail selection is available")
	_equal(application.selected_organization_observation().get("organization_id"), organization_id, "selected detail uses the Formal organization ID")
	_check(application._set_organization_tab(FormalWorldApplication.ORGANIZATION_TAB_RESPONSIBILITY), "Responsibility tab is available")
	var refresh_count := application.organization_refresh_count()
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_PERSON)
	for _index: int in range(5):
		application.queue_redraw()
		await process_frame
	_equal(application.organization_refresh_count(), refresh_count, "closed Organization page performs no repeated full scan")

	var all_production_ids := true
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if not str(row.get("organization_id", "")).begins_with("organization:gov_"):
			all_production_ids = false
			break
	_check(all_production_ids, "fixture organizations do not enter the production browser")
	var ui_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_application.gd")
	_check(not ui_source.contains("我的任务：") and not ui_source.contains("我的通知：") and not ui_source.contains("我的信件："), "responsibility is not packaged as personal task, notification, or mail")
	_equal(application.formal_page_execution_actions(), [], "Organization observation exposes no fabricated execution action")
	_finish(application)


func _expected_grants_for_organization(snapshot: Dictionary, organization_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in snapshot.get("authority_grants", []) as Array:
		var grant := value as Dictionary
		var holder := grant.get("holder", {}) as Dictionary
		if str(grant.get("represented_entity", "")) == organization_id or str(holder.get("organization_id", "")) == organization_id:
			output.append(grant.duplicate(true))
	return output


func _finish(application: FormalWorldApplication) -> void:
	print("Formal Observation Surface O3: %d checks, %d failures" % [checks, failures])
	application.queue_free()
	quit(1 if failures > 0 or checks <= 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label if actual == expected else "%s | actual=%s expected=%s" % [label, var_to_str(actual), var_to_str(expected)])
