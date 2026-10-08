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
	print("Formal world integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_historical_catalog() -> void:
	var provenance := HistoricalProvenanceFoundation.new()
	_check(provenance.load_current(), "historical catalog provenance admission loads")
	var historical := FormalWorldEconomicEvidenceCatalog.new()
	_check(
		historical.configure(provenance.gate()),
		"历史经济数据可加载：%s" % historical.initialization_error
	)
	if failures > 0:
		return
	var evidence := historical.economic_snapshot()
	_check(
		(evidence["countries"] as Array).size() == 50,
		"50个主要政权进入高细节经济目录"
	)
	_check(
		(evidence["formal_verified_countries"] as Array).size()
		<= (evidence["countries"] as Array).size(),
		"严格验证目录不宽于有界主要政权目录"
	)


func _check_formal_economy() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(
		simulation.success,
		"正式世界经济可通过唯一时间源初始化：%s" % simulation.error
	)
	if failures > 0:
		return
	var initial_view := FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot())
	var initial := simulation.world.economy_state.world_summary().merged({"world_political_unit_count": simulation.world.political_registry.entity_count(), "historical_political_record_count": simulation.world.historical_evidence.record_count(), "formal_person_count": simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, simulation.world.political_registry.entity_count() - int(simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))})
	_check_world_roster(initial, initial_view, simulation)
	var first_polity_id := simulation.world.political_registry.entity_ids()[0]
	_check(not first_polity_id.is_empty(), "正式组合根暴露确定性首个政治单元")
	_check(
		simulation.world.political_registry.has_entity(first_polity_id),
		"正式组合根可查询首个政治单元"
	)
	_check(
		not simulation.world.political_registry.has_entity("missing_formal_polity"),
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
	simulation.simulation_step.advance_minutes(90 * 24 * 60)
	var final_view := FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot())
	var after := simulation.world.economy_state.world_summary()
	_check(int(after.get("total_hour", 0)) == 90 * 24, "90日结算完成")
	_check(
		int(after.get("fulfillment_bp", -1)) >= 0,
		"主要政权长期需求满足率有效"
	)
	_check(
		_no_negative_inventory(final_view.country_states),
		"所有高细节政权库存非负"
	)
	var saved := simulation.persistence.snapshot()
	var restored := WorldBootstrap.new().build()
	_check(restored.success, "恢复目标可初始化")
	var candidate_1 := restored.persistence.restore_candidate(saved)
	if candidate_1.success:
		restored = candidate_1
	_check(candidate_1.success, "正式经济存档可通过组合根恢复")
	_check(
		restored.world.economy_state.world_summary().merged({"world_political_unit_count": restored.world.political_registry.entity_count(), "historical_political_record_count": restored.world.historical_evidence.record_count(), "formal_person_count": restored.world.person_overlay.person_count(), "background_polity_count": maxi(0, restored.world.political_registry.entity_count() - int(restored.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))}) == simulation.world.economy_state.world_summary().merged({"world_political_unit_count": simulation.world.political_registry.entity_count(), "historical_political_record_count": simulation.world.historical_evidence.record_count(), "formal_person_count": simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, simulation.world.political_registry.entity_count() - int(simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))}),
		"正式经济恢复后摘要等价"
	)
	_check_economy_restore_is_atomic(restored)


func _check_world_roster(
	initial: Dictionary,
	economy: FormalWorldEconomyView,
	simulation: WorldBuildResult
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
	var background := CurrentWorldPoliticalProjection.polity_summary("state:cshapes_gw_31", RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view, FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()))
	_check(not background.is_empty(), "背景政治单元仍可在半球选择")
	_check(
		not bool(background.get("has_detailed_economy", true)),
		"背景政治单元不运行高细节经济"
	)


func _check_australia_crosswalk(economy: FormalWorldEconomyView) -> void:
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
	var simulation := WorldBootstrap.new().build()
	_check(
		simulation.success,
		"正式世界组合根可初始化：%s" % simulation.error
	)
	if failures > 0:
		return
	simulation.simulation_step.advance_minutes(48 * 60)
	var state := simulation.persistence.snapshot()
	var restored_simulation := WorldBootstrap.new().build()
	_check(restored_simulation.success, "恢复组合根可初始化")
	var candidate_2 := restored_simulation.persistence.restore_candidate(state)
	if candidate_2.success:
		restored_simulation = candidate_2
	_check(
		candidate_2.success,
		"正式世界组合根可恢复"
	)
	_check(
		restored_simulation.world.economy_state.world_summary().merged({"world_political_unit_count": restored_simulation.world.political_registry.entity_count(), "historical_political_record_count": restored_simulation.world.historical_evidence.record_count(), "formal_person_count": restored_simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, restored_simulation.world.political_registry.entity_count() - int(restored_simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))}) == simulation.world.economy_state.world_summary().merged({"world_political_unit_count": simulation.world.political_registry.entity_count(), "historical_political_record_count": simulation.world.historical_evidence.record_count(), "formal_person_count": simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, simulation.world.political_registry.entity_count() - int(simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))}),
		"组合根恢复后世界摘要等价"
	)


func _check_formal_atomic_save_recovery() -> void:
	var primary_path := FormalPersistence.SAVE_PATH
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

	var source := WorldBootstrap.new().build()
	_check(source.success, "正式原子存档测试源可初始化")
	if source.success:
		var first_save := source.persistence.save_to_user()
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
		var expected_first := WorldBootstrap.new().build()
		_check(expected_first.success, "首次主档规范化恢复目标可初始化")
		var expected_first_state: Dictionary = {}
		if expected_first.success:
			var candidate_3 := expected_first.persistence.load_from_user()
			if candidate_3.success:
				expected_first = candidate_3
			var expected_first_load := candidate_3.operation
			_check(expected_first_load.success, "首次主档可由统一读取接口恢复")
			if expected_first_load.success:
				expected_first_state = expected_first.persistence.snapshot().duplicate(true)

		source.simulation_step.advance_minutes(60)
		var second_save := source.persistence.save_to_user()
		_check(second_save.success, "正式世界第二次原子保存成功")
		_check(FileAccess.file_exists(backup_path), "第二次保存生成安全备份")
		_check(
			FileAccess.get_file_as_string(backup_path) == first_primary_text,
			"安全备份逐字保留上一份有效主档"
		)

		_write_text_file(primary_path, "{broken")
		var recovered := WorldBootstrap.new().build()
		_check(recovered.success, "坏主档恢复目标可初始化")
		if recovered.success:
			var candidate_4 := recovered.persistence.load_from_user()
			if candidate_4.success:
				recovered = candidate_4
			var recovered_result := candidate_4.operation
			_check(recovered_result.success, "主档损坏后可读取安全备份")
			_check(
				recovered_result.message == "主存档不可用，已读取安全备份",
				"备份恢复返回明确统一结果"
			)
			_check(
				recovered.persistence.snapshot() == expected_first_state,
				"备份恢复得到上一份有效正式状态"
			)

		_remove_text_file(primary_path)
		_remove_text_file(backup_path)
		_remove_text_file(temporary_path)
		var verification_source := WorldBootstrap.new().build()
		_check(verification_source.success, "临时校验失败测试源可初始化")
		if verification_source.success:
			var valid_save := verification_source.persistence.save_to_user()
			_check(valid_save.success, "临时校验失败测试先建立有效主档")
			var primary_before := FileAccess.get_file_as_string(primary_path)
			var invalid_candidate := verification_source.persistence.snapshot()
			_check(
				_corrupt_first_inventory(invalid_candidate),
				"临时校验失败测试可构造无效候选快照"
			)
			var candidate_5 := verification_source.persistence.restore_candidate(invalid_candidate)
			if candidate_5.success:
				verification_source = candidate_5
			_check(
				not candidate_5.success,
				"无效经济候选在进入活动实例前被拒绝"
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
		var current := WorldBootstrap.new().build()
		_check(current.success, "双坏档测试目标可初始化")
		if current.success:
			current.simulation_step.advance_minutes(25 * 60)
			var before_failed_load := current.persistence.snapshot().duplicate(true)
			var candidate_6 := current.persistence.load_from_user()
			if candidate_6.success:
				current = candidate_6
			var failed_load := candidate_6.operation
			_check(
				not failed_load.success,
				"主档和备份都损坏时统一读取结果失败"
			)
			_check(
				failed_load.error_code == "load_error",
				"双坏档返回明确加载错误代码"
			)
			_check(
				current.persistence.snapshot() == before_failed_load,
				"读取失败不改变当前正式模拟"
			)

	_remove_text_file(primary_path)
	_remove_text_file(backup_path)
	_remove_text_file(temporary_path)
	_restore_text_file(primary_path, preserved[primary_path] as Dictionary)
	_restore_text_file(backup_path, preserved[backup_path] as Dictionary)
	_restore_text_file(temporary_path, preserved[temporary_path] as Dictionary)


func _check_economy_restore_is_atomic(simulation: WorldBuildResult) -> void:
	var before := simulation.persistence.snapshot()
	var rejected := before.duplicate(true)
	var rejected_economy := rejected.get("economy", {}) as Dictionary
	var candidate_states := rejected_economy.get("market_states", {}) as Dictionary
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
	rejected_economy["market_states"] = candidate_states
	rejected["economy"] = rejected_economy
	var candidate_7 := simulation.persistence.restore_candidate(rejected)
	if candidate_7.success:
		simulation = candidate_7
	_check(
		not candidate_7.success,
		"正式经济拒绝负库存恢复候选"
	)
	_check(
		simulation.persistence.snapshot() == before,
		"正式经济失败恢复前后持久状态完全一致"
	)


func _corrupt_first_inventory(snapshot: Dictionary) -> bool:
	var economy_state := snapshot.get("economy", {}) as Dictionary
	var country_states := economy_state.get("market_states", {}) as Dictionary
	var economy_ids: Array[String] = []
	for raw_id: Variant in country_states:
		economy_ids.append(str(raw_id))
	economy_ids.sort()
	if economy_ids.is_empty():
		return false
	var economy_id := economy_ids[0]
	var country_state := country_states[economy_id] as Dictionary
	var inventory := country_state.get("inventory", {}) as Dictionary
	var commodity_ids: Array[String] = []
	for raw_id: Variant in inventory:
		commodity_ids.append(str(raw_id))
	commodity_ids.sort()
	if commodity_ids.is_empty():
		return false
	inventory[commodity_ids[0]] = -1.0
	country_state["inventory"] = inventory
	country_states[economy_id] = country_state
	economy_state["market_states"] = country_states
	snapshot["economy"] = economy_state
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
