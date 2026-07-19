class_name AlphaSaveService
extends RefCounted
## Atomic Alpha save: verified temporary file, backup, checksum and reference scan.

const SCHEMA_VERSION: String = "prototype_0_001_alpha_1"
const REVIEW_PATH: String = "user://saves/prototype_0_001_alpha_1_slot.json"


func build_snapshot(simulation: AlphaSimulationService) -> Dictionary:
	if simulation == null or not simulation.initialized:
		return {}
	var snapshot: Dictionary = _canonical(
		simulation.get_alpha_persistent_state()
	) as Dictionary
	snapshot["integrity"] = {
		"algorithm": "sha256",
		"digest": _digest(snapshot),
	}
	return snapshot


func save(
	simulation: AlphaSimulationService,
	path: String = REVIEW_PATH
) -> SaveOperationResult:
	return save_snapshot(build_snapshot(simulation), path)


func save_snapshot(
	snapshot: Dictionary, path: String = REVIEW_PATH
) -> SaveOperationResult:
	var canonical_snapshot: Dictionary = _canonical(snapshot) as Dictionary
	var errors: Array[String] = validate_snapshot(canonical_snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail(
			"invalid_snapshot", "; ".join(errors), path
		)
	if not _safe_path(path):
		return SaveOperationResult.fail(
			"unsafe_path", "Alpha 存档只能写入 user:// 下的 JSON 文件", path
		)
	var error_message: String = _write_atomic(path, canonical_snapshot)
	if not error_message.is_empty():
		return SaveOperationResult.fail("write_error", error_message, path)
	return SaveOperationResult.ok(path, canonical_snapshot)


func load(path: String = REVIEW_PATH) -> SaveOperationResult:
	if not _safe_path(path):
		return SaveOperationResult.fail(
			"unsafe_path", "Alpha 存档只能从 user:// 下的 JSON 文件读取", path
		)
	var primary: SaveOperationResult = _load_file(path)
	if primary.success:
		return primary
	var backup_path: String = path + ".bak"
	if FileAccess.file_exists(backup_path):
		var backup: SaveOperationResult = _load_file(backup_path)
		if backup.success:
			backup.path = path
			backup.message = "主存档不可用，已读取 Alpha 安全备份"
			return backup
	return primary


func restore(
	snapshot: Dictionary, simulation: AlphaSimulationService
) -> SaveOperationResult:
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty() or simulation == null:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"; ".join(errors) if not errors.is_empty() else "Alpha 模拟不可用"
		)
	var result: V2LifeLoopResult = simulation.restore_alpha_state(snapshot)
	if not result.success:
		return SaveOperationResult.fail(result.error_code, result.user_message)
	return SaveOperationResult.ok(REVIEW_PATH, snapshot)


func validate_snapshot(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(snapshot.get("schema_version", "")) != SCHEMA_VERSION:
		errors.append("不支持的 Alpha 存档版本")
	for field: String in [
		"person_states",
		"schedule_state",
		"household_state",
		"ledgers",
		"condition_state",
		"spatial_state",
		"travel_graph_state",
		"travel_state",
		"communication_state",
		"knowledge_state",
		"dynamic_relationship_state",
		"alpha_world_state",
		"alpha_roster_state",
		"alpha_economy_state",
		"alpha_labor_state",
		"alpha_enterprise_state",
		"alpha_character_state",
		"alpha_politics_state",
		"alpha_ai_state",
		"alpha_world_dynamics_state",
		"current_intent",
		"integrity",
	]:
		if not snapshot.get(field) is Dictionary:
			errors.append("Alpha 字段 %s 必须是对象" % field)
	for field: String in [
		"alpha_organization_state",
		"alpha_events",
		"detailed_enterprise_ids",
		"background_person_ids",
	]:
		if not snapshot.get(field) is Array:
			errors.append("Alpha 字段 %s 必须是数组" % field)
	for field: String in [
		"current_datetime", "selected_person_id", "alpha_world_id",
	]:
		if str(snapshot.get(field, "")).is_empty():
			errors.append("Alpha 字段 %s 不能为空" % field)
	if errors.is_empty():
		errors.append_array(_validate_cross_references(snapshot))
	if errors.is_empty():
		var integrity: Dictionary = snapshot["integrity"] as Dictionary
		if (
			str(integrity.get("algorithm", "")) != "sha256"
			or str(integrity.get("digest", "")) != _digest(snapshot)
		):
			errors.append("Alpha 存档完整性校验失败")
	return errors


func _validate_cross_references(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var roster_state: Dictionary = snapshot["alpha_roster_state"] as Dictionary
	var background: Array = roster_state.get("background", []) as Array
	var active: Array = roster_state.get("active", []) as Array
	var exited: Array = roster_state.get("exited", []) as Array
	var activation_seeds: Dictionary = roster_state.get(
		"activation_seeds", {}
	) as Dictionary
	if active.size() > 20:
		errors.append("Alpha 高精度人物超过二十人")
	if activation_seeds.size() != background.size() + active.size() + exited.size():
		errors.append("Alpha 人物激活种子索引不闭合")
	var player_id: String = str(roster_state.get("player_character_id", ""))
	var active_ids: Dictionary = {}
	for raw_character: Variant in active:
		if raw_character is Dictionary:
			active_ids[str((raw_character as Dictionary).get("id", ""))] = true
	if player_id.is_empty() or not active_ids.has(player_id):
		errors.append("Alpha 玩家人物未处于高精度层")
	var organization_ids: Dictionary = {}
	for raw_organization: Variant in snapshot["alpha_organization_state"] as Array:
		if not raw_organization is Dictionary:
			errors.append("Alpha 组织记录格式无效")
			continue
		var organization_id: String = str(
			(raw_organization as Dictionary).get("id", "")
		)
		if organization_id.is_empty() or organization_ids.has(organization_id):
			errors.append("Alpha 组织 ID 缺失或重复")
		organization_ids[organization_id] = true
	var enterprises: Dictionary = (
		snapshot["alpha_enterprise_state"] as Dictionary
	).get("enterprises", {}) as Dictionary
	for raw_id: Variant in enterprises:
		if not organization_ids.has(str(raw_id)):
			errors.append("Alpha 企业没有对应统一组织：%s" % str(raw_id))
	var economy_state: Dictionary = snapshot["alpha_economy_state"] as Dictionary
	var ledger_state: Dictionary = economy_state.get("ledger", {}) as Dictionary
	var accounts: Dictionary = ledger_state.get("accounts", {}) as Dictionary
	var contracts_state: Dictionary = economy_state.get(
		"contracts", {}
	) as Dictionary
	var contracts: Dictionary = contracts_state.get("contracts", {}) as Dictionary
	var contract_ids: Dictionary = {}
	for raw_id: Variant in contracts:
		var contract_id: String = str(raw_id)
		if contract_id.is_empty() or contract_ids.has(contract_id):
			errors.append("Alpha 合同 ID 缺失或重复")
		contract_ids[contract_id] = true
	var enterprise_states: Dictionary = enterprises
	for raw_state: Variant in enterprise_states.values():
		if not raw_state is Dictionary:
			continue
		for raw_contract_id: Variant in (
			(raw_state as Dictionary).get("contract_ids", []) as Array
		):
			if not contract_ids.has(str(raw_contract_id)):
				errors.append("Alpha 企业引用未知合同：%s" % str(raw_contract_id))
	for raw_account: Variant in accounts.values():
		if not raw_account is Dictionary:
			errors.append("Alpha 账本账户格式无效")
	return errors


func _write_atomic(path: String, snapshot: Dictionary) -> String:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if make_error != OK:
		return error_string(make_error)
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(snapshot, "\t", false))
	file.flush()
	file.close()
	var verification: SaveOperationResult = _load_absolute_for_verification(
		temporary_path
	)
	if not verification.success:
		DirAccess.remove_absolute(temporary_path)
		return "临时 Alpha 存档校验失败：%s" % verification.message
	var had_primary: bool = FileAccess.file_exists(absolute_path)
	if had_primary:
		if FileAccess.file_exists(backup_path):
			var remove_backup: Error = DirAccess.remove_absolute(backup_path)
			if remove_backup != OK:
				DirAccess.remove_absolute(temporary_path)
				return error_string(remove_backup)
		var backup_error: Error = DirAccess.rename_absolute(
			absolute_path, backup_path
		)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return error_string(backup_error)
	var replace_error: Error = DirAccess.rename_absolute(
		temporary_path, absolute_path
	)
	if replace_error != OK:
		if had_primary and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(temporary_path)
		return error_string(replace_error)
	return ""


func _load_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "Alpha 存档不存在", path)
	return _load_absolute_for_verification(
		ProjectSettings.globalize_path(path), path
	)


func _load_absolute_for_verification(
	absolute_path: String, display_path: String = ""
) -> SaveOperationResult:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error",
			error_string(FileAccess.get_open_error()),
			absolute_path if display_path.is_empty() else display_path
		)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [
				parser.get_error_line(), parser.get_error_message(),
			],
			absolute_path if display_path.is_empty() else display_path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot", "Alpha 存档根节点必须是对象"
		)
	var snapshot: Dictionary = _canonical(parser.data) as Dictionary
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail(
			"invalid_snapshot", "; ".join(errors)
		)
	return SaveOperationResult.ok(
		absolute_path if display_path.is_empty() else display_path,
		snapshot
	)


static func _safe_path(path: String) -> bool:
	return path.begins_with("user://") and path.ends_with(".json")


static func _digest(snapshot: Dictionary) -> String:
	var payload: Dictionary = snapshot.duplicate(true)
	payload.erase("integrity")
	return JSON.stringify(_canonical(payload), "", true).sha256_text()


static func _canonical(value: Variant) -> Variant:
	# JSON numbers cannot exactly preserve arbitrary signed 64-bit RNG states.
	# Decimal strings remain lossless and restore paths intentionally call int().
	if value is Dictionary:
		var source: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for raw_key: Variant in source.keys():
			keys.append(str(raw_key))
		keys.sort()
		var dictionary_result: Dictionary = {}
		for key: String in keys:
			dictionary_result[key] = _canonical(source[key])
		return dictionary_result
	if value is Array:
		var array_result: Array = []
		for item: Variant in value as Array:
			array_result.append(_canonical(item))
		return array_result
	if typeof(value) == TYPE_INT:
		var integer: int = int(value)
		if integer > 9_007_199_254_740_991 or integer < -9_007_199_254_740_991:
			return str(integer)
	if (
		typeof(value) == TYPE_FLOAT
		and is_equal_approx(float(value), roundf(float(value)))
	):
		return int(roundf(float(value)))
	return value
