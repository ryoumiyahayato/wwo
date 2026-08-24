extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_historical_catalog()
	_check_formal_economy()
	_check_formal_simulation()
	_check_formal_atomic_save_recovery()
	await _check_product_scenes()
	print("Formal world integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_historical_catalog() -> void:
	var historical := AlphaHistoricalWorldEconomyData.new()
	_check(
		historical.configure(),
		"历史经济数据可加载：%s" % historical.initialization_error
	)
	if failures > 0:
		return
	_check(
		historical.simulation_countries().size() == 50,
		"50个主要政权进入高细节经济目录"
	)
	_check(
		historical.formal_countries().size()
		<= historical.simulation_countries().size(),
		"严格验证目录不宽于有界主要政权目录"
	)


func _check_formal_economy() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(
		simulation.initialize(),
		"正式世界经济可通过唯一时间源初始化：%s" % simulation.initialization_error
	)
	if failures > 0:
		return
	var economy := simulation.economy
	var initial := simulation.world_summary()
	_check_world_roster(initial, economy, simulation)
	var first_polity_id := simulation.first_polity_id()
	_check(not first_polity_id.is_empty(), "正式组合根暴露确定性首个政治单元")
	_check(
		simulation.has_polity(first_polity_id),
		"正式组合根可查询首个政治单元"
	)
	_check(
		not simulation.has_polity("missing_formal_polity"),
		"正式组合根拒绝未知政治单元"
	)
	_check(first_polity_id.begins_with("state:"), "正式组合根暴露runtime政治ID")
	_check(
		int(initial.get("commodity_count", 0)) >= 60,
		"正式经济直接读取完整商品目录"
	)
	_check(
		int(initial.get("route_count", 0)) >= 30,
		"正式经济使用历史稀疏航路"
	)
	var after := simulation.advance_minutes(90 * 24 * 60)
	_check(int(after.get("total_hour", 0)) == 90 * 24, "90日结算完成")
	_check(
		int(after.get("fulfillment_bp", -1)) >= 0,
		"主要政权长期需求满足率有效"
	)
	_check(
		_no_negative_inventory(economy.country_states),
		"所有高细节政权库存非负"
	)
	var saved := simulation.get_persistent_state()
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "恢复目标可初始化")
	_check(restored.restore_persistent_state(saved), "正式经济存档可通过组合根恢复")
	_check(
		restored.world_summary() == simulation.world_summary(),
		"正式经济恢复后摘要等价"
	)
	_check_economy_restore_is_atomic(restored.economy)


func _check_world_roster(
	initial: Dictionary,
	economy: FormalWorldEconomyService,
	simulation: FormalWorldSimulation
) -> void:
	_check(
		int(initial.get("world_political_unit_count", 0)) == 146,
		"当前世界包含146个1900-01-01运行时政治实体"
	)
	_check(
		int(initial.get("historical_political_record_count", 0)) == 151,
		"历史证据目录独立保留151条记录"
	)
	_check(
		int(initial.get("major_economy_count", 0)) == 50,
		"50个主要政权经济聚合体使用高细节模拟"
	)
	_check(
		int(initial.get("detailed_polity_unit_count", 0)) == 55,
		"50个经济聚合体明确覆盖55个地图政治单元"
	)
	_check(
		int(initial.get("primary_playable_count", 0)) == 30,
		"前30个经济聚合体进入当前核心可玩层"
	)
	_check(
		int(initial.get("secondary_roster_count", 0)) == 20,
		"第31至50位保留为次要政权候选"
	)
	_check(
		int(initial.get("background_polity_count", 0)) == 91,
		"其余91个运行时政治实体作为纯背景世界存在"
	)
	_check(
		not economy.country_states.has("country:loran_federation")
		and not economy.country_states.has("country:vesta_union"),
		"正式世界不包含两国八地区架空夹具"
	)
	_check_australia_crosswalk(economy)
	_check(
		economy.economy_entity_for_polity("state:grand_duchy_of_luxembourg")
		== "kingdom_of_luxembourg",
		"卢森堡经济旧名显式映射到卢森堡大公国地图单元"
	)
	var background := simulation.polity_summary("state:cshapes_gw_31")
	_check(not background.is_empty(), "背景政治单元仍可在半球选择")
	_check(
		not bool(background.get("has_detailed_economy", true)),
		"背景政治单元不运行高细节经济"
	)


func _check_australia_crosswalk(economy: FormalWorldEconomyService) -> void:
	var polity_ids := economy.polity_ids_for_economy("australia_colonies_1900")
	_check(polity_ids.size() == 6, "澳大利亚经济聚合体覆盖六个自治殖民地")
	for index: int in range(901, 907):
		var polity_id := "state:cshapes_gw_%d" % index
		_check(
			economy.economy_entity_for_polity(polity_id)
			== "australia_colonies_1900",
			"%s映射到澳大利亚殖民地经济聚合体" % polity_id
		)


func _check_formal_simulation() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(
		simulation.initialize(),
		"正式世界组合根可初始化：%s" % simulation.initialization_error
	)
	if failures > 0:
		return
	simulation.advance_minutes(48 * 60)
	var state := simulation.get_persistent_state()
	var restored_simulation := FormalWorldSimulation.new()
	_check(restored_simulation.initialize(), "恢复组合根可初始化")
	_check(
		restored_simulation.restore_persistent_state(state),
		"正式世界组合根可恢复"
	)
	_check(
		restored_simulation.world_summary() == simulation.world_summary(),
		"组合根恢复后世界摘要等价"
	)


func _check_formal_atomic_save_recovery() -> void:
	var primary_path := FormalWorldSimulation.SAVE_PATH
	var backup_path := primary_path + AtomicJsonFileStore.BACKUP_SUFFIX
	var temporary_path := primary_path + AtomicJsonFileStore.TEMPORARY_SUFFIX
	var preserved := {
		primary_path: _capture_text_file(primary_path),
		backup_path: _capture_text_file(backup_path),
		temporary_path: _capture_text_file(temporary_path),
	}
	_remove_text_file(primary_path)
	_remove_text_file(backup_path)
	_remove_text_file(temporary_path)

	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "正式原子存档测试源可初始化")
	if source.initialized:
		var first_save := source.save_to_user()
		_check(first_save.success, "正式世界可通过统一原子接口保存")
		_check(
			first_save.path == primary_path,
			"正式原子保存结果返回正式存档路径"
		)
		_check(FileAccess.file_exists(primary_path), "首次原子保存生成主档")
		_check(
			not FileAccess.file_exists(temporary_path),
			"首次原子保存完成后不残留临时文件"
		)
		var first_primary_text := FileAccess.get_file_as_string(primary_path)
		var expected_first := FormalWorldSimulation.new()
		_check(expected_first.initialize(), "首次主档规范化恢复目标可初始化")
		var expected_first_state: Dictionary = {}
		if expected_first.initialized:
			var expected_first_load := expected_first.load_from_user()
			_check(expected_first_load.success, "首次主档可由统一读取接口恢复")
			if expected_first_load.success:
				expected_first_state = expected_first.get_persistent_state().duplicate(true)

		source.advance_minutes(60)
		var second_save := source.save_to_user()
		_check(second_save.success, "正式世界第二次原子保存成功")
		_check(FileAccess.file_exists(backup_path), "第二次保存生成安全备份")
		_check(
			FileAccess.get_file_as_string(backup_path) == first_primary_text,
			"安全备份逐字保留上一份有效主档"
		)

		_write_text_file(primary_path, "{broken")
		var recovered := FormalWorldSimulation.new()
		_check(recovered.initialize(), "坏主档恢复目标可初始化")
		if recovered.initialized:
			var recovered_result := recovered.load_from_user()
			_check(recovered_result.success, "主档损坏后可读取安全备份")
			_check(
				recovered_result.message == "主存档不可用，已读取安全备份",
				"备份恢复返回明确统一结果"
			)
			_check(
				recovered.get_persistent_state() == expected_first_state,
				"备份恢复得到上一份有效正式状态"
			)

		_remove_text_file(primary_path)
		_remove_text_file(backup_path)
		_remove_text_file(temporary_path)
		var verification_source := FormalWorldSimulation.new()
		_check(verification_source.initialize(), "临时校验失败测试源可初始化")
		if verification_source.initialized:
			var valid_save := verification_source.save_to_user()
			_check(valid_save.success, "临时校验失败测试先建立有效主档")
			var primary_before := FileAccess.get_file_as_string(primary_path)
			_check(
				_corrupt_first_inventory(verification_source),
				"临时校验失败测试可构造无效候选快照"
			)
			var rejected_save := verification_source.save_to_user()
			_check(
				not rejected_save.success,
				"临时文件状态校验失败时原子保存返回失败"
			)
			_check(
				FileAccess.get_file_as_string(primary_path) == primary_before,
				"临时校验失败时原主档完全不变"
			)
			_check(
				not FileAccess.file_exists(temporary_path),
				"临时校验失败后清理临时文件"
			)

		_write_text_file(primary_path, "{broken")
		_write_text_file(backup_path, "[]")
		var current := FormalWorldSimulation.new()
		_check(current.initialize(), "双坏档测试目标可初始化")
		if current.initialized:
			current.advance_minutes(25 * 60)
			var before_failed_load := current.get_persistent_state().duplicate(true)
			var failed_load := current.load_from_user()
			_check(
				not failed_load.success,
				"主档和备份都损坏时统一读取结果失败"
			)
			_check(
				failed_load.error_code == "load_error",
				"双坏档返回明确加载错误代码"
			)
			_check(
				current.get_persistent_state() == before_failed_load,
				"读取失败不改变当前正式模拟"
			)

	_remove_text_file(primary_path)
	_remove_text_file(backup_path)
	_remove_text_file(temporary_path)
	_restore_text_file(primary_path, preserved[primary_path] as Dictionary)
	_restore_text_file(backup_path, preserved[backup_path] as Dictionary)
	_restore_text_file(temporary_path, preserved[temporary_path] as Dictionary)


func _check_product_scenes() -> void:
	_check(
		str(ProjectSettings.get_setting("application/run/main_scene", ""))
		== "res://scenes/formal/formal_world_menu.tscn",
		"产品默认入口已迁移到正式半球目录"
	)
	var application_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_application.gd"
	)
	_check(
		not application_source.contains("formal_simulation.economy.polity_records"),
		"正式UI不再绕过组合根读取经济服务政治单元字典"
	)
	var menu_scene := load(
		"res://scenes/formal/formal_world_menu.tscn"
	) as PackedScene
	_check(menu_scene != null, "正式世界标题场景可加载")
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		_check(menu is FormalWorldMenu, "标题场景不再使用V2.3菜单类")
		menu.free()
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "正式半球场景可加载")
	if scene == null:
		return
	var instance := scene.instantiate()
	_check(
		instance is FormalWorldApplication,
		"正式场景使用FormalWorldApplication而非V2.3产品模拟"
	)
	get_root().add_child(instance)
	await process_frame
	await process_frame
	var application := instance as FormalWorldApplication
	_check_runtime_application(application)
	application.queue_free()
	await process_frame


func _check_runtime_application(application: FormalWorldApplication) -> void:
	_check(
		application.formal_simulation.initialized,
		"正式半球执行ready后初始化统一正式世界"
	)
	var runtime_summary := application.formal_simulation.world_summary()
	_check(
		int(runtime_summary.get("world_political_unit_count", 0)) == 146,
		"正式半球运行时持有146个当前政治实体"
	)
	_check(
		int(runtime_summary.get("major_economy_count", 0)) == 50,
		"正式半球运行时持有50个主要经济聚合体"
	)
	_check(
		int(runtime_summary.get("detailed_polity_unit_count", 0)) == 55,
		"正式半球运行时将高细节经济绑定到55个地图单元"
	)
	var first_polity_id := application.formal_simulation.first_polity_id()
	_check(first_polity_id.begins_with("state:"), "正式UI选择使用runtime政治ID")
	application.selected_country_id = first_polity_id
	_check(
		application._selected_polity_entity_id() == first_polity_id,
		"正式UI通过组合根解析已选政治单元"
	)
	_check(
		application.get_node_or_null("PrototypeMap") == null,
		"正式运行场景不再包含旧平面PrototypeMap"
	)
	_check(
		application.get_node_or_null(
			"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D"
		) != null,
		"正式运行场景以真实三维半球作为地图"
	)
	application.sim_paused = false
	application.sim_speed = 1
	var before_hour := application.formal_simulation.economy.total_hour
	for _tick: int in range(4):
		application._on_clock_timer_timeout()
	_check(
		application.formal_simulation.economy.total_hour >= before_hour + 1,
		"解除暂停后半球时钟与正式经济使用同一推进源"
	)
	application.economy_panel_open = false
	application._activate_button("formal_economy_toggle")
	_check(
		application.economy_panel_open,
		"正式半球政经面板可由正式按钮命令打开"
	)
	application._toggle_formal_economy_panel()
	_check(
		not application.economy_panel_open,
		"正式半球政经面板统一命令保持切换行为"
	)


func _check_economy_restore_is_atomic(
	economy: FormalWorldEconomyService
) -> void:
	var before := economy.get_persistent_state()
	var rejected := before.duplicate(true)
	var candidate_states := rejected.get("country_states", {}) as Dictionary
	var economy_ids: Array[String] = []
	for raw_id: Variant in candidate_states:
		economy_ids.append(str(raw_id))
	economy_ids.sort()
	_check(not economy_ids.is_empty(), "原子恢复测试存在正式经济候选")
	if economy_ids.is_empty():
		return
	var economy_id := economy_ids[0]
	var candidate_state := candidate_states[economy_id] as Dictionary
	var inventory := candidate_state.get("inventory", {}) as Dictionary
	var commodity_ids: Array[String] = []
	for raw_id: Variant in inventory:
		commodity_ids.append(str(raw_id))
	commodity_ids.sort()
	_check(not commodity_ids.is_empty(), "原子恢复测试存在库存候选")
	if commodity_ids.is_empty():
		return
	inventory[commodity_ids[0]] = -1.0
	candidate_state["inventory"] = inventory
	candidate_states[economy_id] = candidate_state
	rejected["country_states"] = candidate_states
	_check(
		not economy.restore_persistent_state(rejected),
		"正式经济拒绝负库存恢复候选"
	)
	_check(
		economy.get_persistent_state() == before,
		"正式经济失败恢复前后持久状态完全一致"
	)


func _corrupt_first_inventory(simulation: FormalWorldSimulation) -> bool:
	var economy_ids: Array[String] = []
	for raw_id: Variant in simulation.economy.country_states:
		economy_ids.append(str(raw_id))
	economy_ids.sort()
	if economy_ids.is_empty():
		return false
	var economy_id := economy_ids[0]
	var country_state := simulation.economy.country_states[economy_id] as Dictionary
	var inventory := country_state.get("inventory", {}) as Dictionary
	var commodity_ids: Array[String] = []
	for raw_id: Variant in inventory:
		commodity_ids.append(str(raw_id))
	commodity_ids.sort()
	if commodity_ids.is_empty():
		return false
	inventory[commodity_ids[0]] = -1.0
	country_state["inventory"] = inventory
	simulation.economy.country_states[economy_id] = country_state
	return true


func _capture_text_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "content": ""}
	return {
		"exists": true,
		"content": FileAccess.get_file_as_string(path),
	}


func _restore_text_file(path: String, preserved: Dictionary) -> void:
	if bool(preserved.get("exists", false)):
		_write_text_file(path, str(preserved.get("content", "")))


func _write_text_file(path: String, content: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var make_error := DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if make_error != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	return true


func _remove_text_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _parse_dictionary_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _no_negative_inventory(states: Dictionary) -> bool:
	for raw_state: Variant in states.values():
		var state := raw_state as Dictionary
		for value: Variant in (state.get("inventory", {}) as Dictionary).values():
			if float(value) < 0.0:
				return false
	return true


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
