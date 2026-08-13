class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. It owns the 151-unit historical political
## world and the separate 50-polity high-detail economy roster.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v3"

var economy := FormalWorldEconomyService.new()
var player_session := FormalPlayerSession.new()
var initialized: bool = false
var initialization_error: String = ""
var total_minutes: int = 0
var _minute_remainder: int:
	get:
		return total_minutes % 60


func _init() -> void:
	economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)


func initialize() -> bool:
	initialization_error = ""
	total_minutes = 0
	if not economy.configure():
		initialization_error = economy.initialization_error
		initialized = false
		return false
	if not player_session.configure():
		initialization_error = player_session.initialization_error
		initialized = false
		return false
	initialized = true
	state_changed.emit({"initialized": true})
	return true


func advance_minutes(minutes: int) -> Dictionary:
	if not initialized or minutes <= 0:
		return economy.world_summary()
	var previous_total_hour := _authoritative_total_hour()
	total_minutes += minutes
	var current_total_hour := _authoritative_total_hour()
	var elapsed_hours := current_total_hour - previous_total_hour
	if elapsed_hours > 0:
		var summary := economy.settle_hour_range(
			previous_total_hour, current_total_hour
		)
		state_changed.emit({
			"time": true,
			"economy": true,
			"hours": elapsed_hours,
		})
		return summary
	state_changed.emit({"time": true, "economy": false, "hours": 0})
	return economy.world_summary()


func world_summary() -> Dictionary:
	return economy.world_summary()


func country_summary(entity_id: String) -> Dictionary:
	return economy.country_summary(entity_id)


func polity_summary(entity_id: String) -> Dictionary:
	return economy.polity_summary(entity_id)


func has_polity(entity_id: String) -> bool:
	return economy.has_polity(entity_id)


func first_polity_id() -> String:
	return economy.first_polity_id()


func player_summary() -> Dictionary:
	return player_session.player_summary()


func vertical_slice_summary() -> Dictionary:
	var decision := player_session.decision_summary()
	var route_id := str(decision.get("route_id", ""))
	var commodity_id := str(decision.get("commodity_id", ""))
	var destination_id := str(decision.get("destination_entity_id", ""))
	var route := economy.route_summary(route_id)
	var destination := economy.country_summary(destination_id)
	var metrics := destination.get("daily_metrics", {}) as Dictionary
	var commodity_metrics := metrics.get(commodity_id, {}) as Dictionary
	var inventory := destination.get("inventory", {}) as Dictionary
	var prices := destination.get("prices", {}) as Dictionary
	var shipment: Dictionary = {}
	var last_action := decision.get("last_action", {}) as Dictionary
	if not last_action.is_empty():
		shipment = economy.shipment_summary(str(last_action.get("shipment_id", "")))
	else:
		for candidate: Dictionary in economy.shipments:
			if (
				str(candidate.get("route_id", "")) == route_id
				and str(candidate.get("commodity_id", "")) == commodity_id
			):
				shipment = candidate.duplicate(true)
				break
	var shipment_status := "not_scheduled"
	var eta_hours := -1
	var progress_bp := 0
	if not shipment.is_empty():
		shipment_status = str(shipment.get("status", "in_transit"))
		eta_hours = maxi(0, int(shipment.get("arrival_hour", 0)) - _authoritative_total_hour())
		var dispatch_hour := int(shipment.get("dispatch_hour", 0))
		var duration := maxi(1, int(shipment.get("arrival_hour", 0)) - dispatch_hour)
		progress_bp = int(round(clampf(
			float(_authoritative_total_hour() - dispatch_hour) / float(duration),
			0.0,
			1.0
		) * 10000.0))
	elif not last_action.is_empty() and (
		_authoritative_total_hour() >= int(last_action.get("arrival_hour", 0))
	):
		shipment_status = "delivered"
		eta_hours = 0
		progress_bp = 10000
	return {
		"player": player_session.player_summary(),
		"decision": decision,
		"route": route,
		"shipment": shipment,
		"shipment_status": shipment_status,
		"eta_hours": eta_hours,
		"progress_bp": progress_bp,
		"destination": {
			"entity_id": destination_id,
			"name_zh": "埃及赫迪夫国",
			"commodity_id": commodity_id,
			"commodity_name_zh": "面包",
			"price_centimes": int(prices.get(commodity_id, 0)),
			"inventory_units": float(inventory.get(commodity_id, 0.0)),
			"demand_units": float(commodity_metrics.get("demand", 0.0)),
			"produced_units": float(commodity_metrics.get("produced", 0.0)),
			"unmet_units": float(commodity_metrics.get("unmet", 0.0)),
			"fulfillment_bp": int(
				(destination.get("daily_totals", {}) as Dictionary).get(
					"fulfillment_bp", 0
				)
			),
		},
	}


func authorize_supply_transport_priority() -> Dictionary:
	if not initialized:
		return {"success": false, "code": "not_initialized", "message": "正式世界尚未初始化。"}
	if not player_session.is_authorized_for_decision():
		return {"success": false, "code": "not_authorized", "message": "当前岗位没有供应运输优先权。"}
	var decision := player_session.decision_summary()
	if not (decision.get("last_action", {}) as Dictionary).is_empty():
		return {"success": false, "code": "already_authorized", "message": "当前运输已经完成优先授权。"}
	var before := vertical_slice_summary()
	var economy_before := economy.get_persistent_state()
	var prioritized := economy.prioritize_in_transit_shipment(
		str(decision.get("route_id", "")),
		str(decision.get("commodity_id", "")),
		_authoritative_total_hour()
	)
	if prioritized.is_empty():
		return {"success": false, "code": "shipment_unavailable", "message": "当前没有可优先处理的面包运输。"}
	var destination := before.get("destination", {}) as Dictionary
	var action := {
		"action_id": str(decision.get("action_id", "")),
		"shipment_id": str(prioritized.get("shipment_id", "")),
		"authorized_hour": _authoritative_total_hour(),
		"original_arrival_hour": int(prioritized.get("original_arrival_hour", 0)),
		"arrival_hour": int(prioritized.get("arrival_hour", 0)),
		"inventory_before": float(destination.get("inventory_units", 0.0)),
		"unmet_before": float(destination.get("unmet_units", 0.0)),
	}
	if not player_session.record_action(action):
		economy.restore_persistent_state(economy_before)
		return {"success": false, "code": "record_rejected", "message": "授权记录未通过会话校验。"}
	state_changed.emit({"player_action": true, "economy": true, "transport": true})
	return {
		"success": true,
		"code": "priority_authorized",
		"message": "已批准面包运输优先通关，预计提前 1 日抵达亚历山大港。",
		"action": action.duplicate(true),
	}


func date_time() -> Dictionary:
	var value := V2DateTime.from_total_hour(_authoritative_total_hour())
	value["minute"] = _minute_remainder
	return value


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"total_minutes": total_minutes,
		"minute_remainder": _minute_remainder,
		"economy": economy.get_persistent_state(),
		"player_session": player_session.snapshot(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in ["formal_world_simulation_v1", "formal_world_simulation_v2", SCHEMA_ID]
		or not state.get("economy", {}) is Dictionary
		or (schema_id == SCHEMA_ID and not state.get("player_session", {}) is Dictionary)
	):
		return false
	var validated_time := _validated_time_state(state, schema_id)
	if validated_time.is_empty():
		return false
	var previous_total_minutes := total_minutes
	var previous_initialized := initialized
	var previous_economy := economy.get_persistent_state()
	var previous_player_session := player_session.snapshot()
	total_minutes = int(validated_time.get("total_minutes", -1))
	if not economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	) or (
		schema_id == SCHEMA_ID
		and not player_session.restore(state.get("player_session", {}) as Dictionary)
	):
		total_minutes = previous_total_minutes
		economy.restore_persistent_state(previous_economy)
		player_session.restore(previous_player_session)
		initialized = previous_initialized
		return false
	initialized = true
	state_changed.emit({"restored": true})
	return true


func save_to_user() -> SaveOperationResult:
	if not initialized:
		return SaveOperationResult.fail(
			"not_initialized",
			"正式世界尚未初始化，无法保存。",
			SAVE_PATH
		)
	var snapshot := get_persistent_state()
	var write_error := AtomicJsonFileStore.write_verified(
		SAVE_PATH,
		snapshot,
		Callable(self, "_verify_temporary_save"),
		true
	)
	if not write_error.is_empty():
		return SaveOperationResult.fail(
			"write_error",
			"正式世界保存失败：%s" % write_error,
			SAVE_PATH
		)
	state_changed.emit({"saved": true})
	var result := SaveOperationResult.ok(SAVE_PATH, snapshot)
	result.message = "正式世界已保存。"
	return result


func _verify_temporary_save(absolute_path: String) -> String:
	var loaded := _read_snapshot_file(absolute_path)
	if not loaded.success:
		return "临时存档校验失败：%s" % loaded.message
	var candidate := FormalWorldSimulation.new()
	if not candidate.initialize():
		return "临时存档校验失败：正式世界初始化失败：%s" % (
			candidate.initialization_error
		)
	if not candidate.restore_persistent_state(loaded.snapshot):
		return "临时存档校验失败：正式世界状态无效"
	return ""


func load_from_user() -> SaveOperationResult:
	var primary := _restore_snapshot_file(SAVE_PATH)
	if primary.success:
		primary.message = "正式世界存档已恢复。"
		return primary
	var backup_path := SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	var backup := _restore_snapshot_file(backup_path)
	if backup.success:
		backup.path = SAVE_PATH
		backup.message = "主存档不可用，已读取安全备份"
		return backup
	return SaveOperationResult.fail(
		"load_error",
		"主存档不可用：%s；安全备份不可用：%s" % [
			primary.message,
			backup.message,
		],
		SAVE_PATH
	)


func _restore_snapshot_file(path: String) -> SaveOperationResult:
	var loaded := _read_snapshot_file(path)
	if not loaded.success:
		return loaded
	if not restore_persistent_state(loaded.snapshot):
		return SaveOperationResult.fail(
			"restore_error",
			"存档状态校验或恢复失败",
			path
		)
	return loaded


func _read_snapshot_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "存档不存在", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error",
			error_string(FileAccess.get_open_error()),
			path
		)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			],
			path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"存档根节点必须是对象",
			path
		)
	return SaveOperationResult.ok(path, parser.data as Dictionary)


func _authoritative_total_hour() -> int:
	return int(total_minutes / 60)


func _validated_time_state(state: Dictionary, schema_id: String) -> Dictionary:
	var economy_state := state.get("economy", {}) as Dictionary
	var saved_total_hour := int(economy_state.get("total_hour", -1))
	if saved_total_hour < 0:
		return {}
	if schema_id == SCHEMA_ID and (
		not state.has("total_minutes") or not state.has("minute_remainder")
	):
		return {}
	var has_total_minutes := state.has("total_minutes")
	var has_minute_remainder := state.has("minute_remainder")
	var total := int(state.get("total_minutes", saved_total_hour * 60))
	var remainder := int(state.get("minute_remainder", posmod(total, 60)))
	if not has_total_minutes and has_minute_remainder:
		total = saved_total_hour * 60 + remainder
	if (
		total < 0
		or remainder < 0
		or remainder > 59
		or posmod(total, 60) != remainder
		or int(total / 60) != saved_total_hour
	):
		return {}
	return {
		"total_minutes": total,
		"minute_remainder": remainder,
	}
