extends SceneTree
## Regression gate for #85: Formal authoritative persistence must be exact.

const SAVE_RESTORE_DAYS: int = 180
const CONTINUATION_HOURS: int = 49
const MINUTES_PER_DAY: int = 24 * 60
const SPATIAL_LINK_ID: String = "rail_paris_lille"
const FIXTURE_PATH: String = "user://formal_exact_persistence_fixture.json"
const COUNTEREXAMPLE_1_BITS: String = "3f43f634dfb491bb"
const COUNTEREXAMPLE_2_BITS: String = "40c3169901b276ea"

var failures: int = 0
var checks: int = 0
var _fixture_snapshot: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_path(FIXTURE_PATH)
	_cleanup_formal_save()
	_check_known_counterexamples()
	var midpoint_snapshot := _check_real_180_day_roundtrip()
	if not midpoint_snapshot.is_empty():
		_check_legacy_raw_json_read(midpoint_snapshot)
	_cleanup_path(FIXTURE_PATH)
	_cleanup_formal_save()
	print("Formal Exact Persistence: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("FORMAL_EXACT_PERSISTENCE_COMPLETE=1")
	quit(0)


func _check_known_counterexamples() -> void:
	var first := _float_from_bits(COUNTEREXAMPLE_1_BITS)
	var second := _float_from_bits(COUNTEREXAMPLE_2_BITS)
	_fixture_snapshot = {
		"schema_id": "formal_exact_persistence_fixture_v1",
		"counterexample_1": first,
		"counterexample_2": second,
		"int_value": 120,
		"float_value": 120.0,
	}
	var document := FormalWorldPersistenceDocument.encode(_fixture_snapshot)
	_check(not document.is_empty(), "known float counterexamples encode through production Formal document")
	if document.is_empty():
		return
	var write_error := AtomicJsonFileStore.write_verified(
		FIXTURE_PATH,
		document,
		Callable(self, "_verify_fixture_temporary"),
		false
	)
	_check(write_error.is_empty(), "known float counterexamples write through production atomic JSON boundary")
	if not write_error.is_empty():
		return
	var read_result := _read_exact_document(FIXTURE_PATH)
	_check(bool(read_result.get("success", false)), "known float counterexamples read through production Formal document")
	if not bool(read_result.get("success", false)):
		return
	var restored := read_result.get("snapshot", {}) as Dictionary
	_check(_strict_equal(_fixture_snapshot, restored), "known float counterexamples preserve exact value and Variant numeric type")
	_check(
		_float_bits(float(restored.get("counterexample_1", 0.0))) == COUNTEREXAMPLE_1_BITS,
		"counterexample #1 preserves IEEE-754 bits"
	)
	_check(
		_float_bits(float(restored.get("counterexample_2", 0.0))) == COUNTEREXAMPLE_2_BITS,
		"counterexample #2 preserves IEEE-754 bits"
	)
	_check(typeof(restored.get("int_value")) == TYPE_INT, "integer Variant type remains TYPE_INT")
	_check(typeof(restored.get("float_value")) == TYPE_FLOAT, "float Variant type remains TYPE_FLOAT")


func _verify_fixture_temporary(absolute_path: String) -> String:
	var read_result := _read_exact_document(absolute_path)
	if not bool(read_result.get("success", false)):
		return str(read_result.get("error", "fixture read failed"))
	return (
		""
		if _strict_equal(_fixture_snapshot, read_result.get("snapshot", {}))
		else "fixture changed across exact persistence document"
	)


func _check_real_180_day_roundtrip() -> Dictionary:
	_cleanup_formal_save()
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "Formal world initializes for 180-day persistence gate")
	if not simulation.initialized:
		return {}
	simulation.advance_minutes(SAVE_RESTORE_DAYS * MINUTES_PER_DAY)
	_check(
		simulation.set_spatial_nominal_capacity(SPATIAL_LINK_ID, 640.0),
		"180-day gate mutates authoritative Spatial nominal capacity"
	)
	_check(
		simulation.set_spatial_infrastructure_condition(SPATIAL_LINK_ID, 0.8),
		"180-day gate mutates authoritative Spatial condition"
	)
	_check(
		simulation.set_spatial_infrastructure_status(SPATIAL_LINK_ID, "damaged"),
		"180-day gate mutates authoritative Spatial status"
	)
	var reservation := simulation.request_spatial_capacity(
		"formal_exact_persistence_reservation", SPATIAL_LINK_ID, 120.0
	)
	_check(
		bool(reservation.get("accepted", false)),
		"180-day gate creates an active authoritative Spatial capacity reservation"
	)
	var before_snapshot := simulation.get_persistent_state()
	var before_spatial := simulation.spatial_snapshot()
	var before_spatial_fingerprint := simulation.spatial_authoritative_fingerprint()
	var before_fingerprint := simulation.authoritative_fingerprint()
	_check(not before_fingerprint.is_empty(), "180-day authoritative fingerprint exists before save")
	_check(before_snapshot.has("spatial"), "Formal exact snapshot includes Spatial authority")
	_check(
		int(before_spatial.get("current_hour", -1))
		== int(simulation.total_minutes / 60),
		"Spatial snapshot hour equals Formal authoritative hour before save"
	)

	var save_result := simulation.save_to_user()
	_check(save_result.success, "180-day Formal world saves through production save_to_user")
	if not save_result.success:
		printerr("FORMAL_EXACT_SAVE_ERROR=%s" % save_result.message)
		return {}

	var disk_document := _read_json_dictionary(FormalWorldSimulation.SAVE_PATH)
	_check(bool(disk_document.get("success", false)), "production Formal save remains a valid JSON outer document")
	if bool(disk_document.get("success", false)):
		var root := disk_document.get("value", {}) as Dictionary
		_check(
			str(root.get(FormalWorldPersistenceDocument.FORMAT_FIELD, ""))
			== FormalWorldPersistenceDocument.FORMAT_ID,
			"production Formal save uses the exact persistence document discriminator"
		)

	var restored := FormalWorldSimulation.new()
	var load_result := restored.load_from_user()
	_check(load_result.success, "180-day Formal world loads through production load_from_user")
	if not load_result.success:
		printerr("FORMAL_EXACT_LOAD_ERROR=%s" % load_result.message)
		return {}
	_check(
		_strict_equal(before_snapshot, load_result.snapshot),
		"real 180-day authoritative snapshot preserves strict recursive value/type equality"
	)
	var after_spatial_fingerprint := restored.spatial_authoritative_fingerprint()
	var after_fingerprint := restored.authoritative_fingerprint()
	print("FORMAL_EXACT_180D_PRE_FINGERPRINT=%s" % before_fingerprint)
	print("FORMAL_EXACT_180D_POST_FINGERPRINT=%s" % after_fingerprint)
	_check(
		_strict_equal(restored.spatial_snapshot(), before_spatial),
		"real 180-day Spatial snapshot preserves infrastructure and active capacity window exactly"
	)
	_check(
		after_spatial_fingerprint == before_spatial_fingerprint,
		"real 180-day Spatial authoritative fingerprint is identical after persistence"
	)
	_check(
		after_fingerprint == before_fingerprint,
		"real 180-day authoritative fingerprint is identical after production persistence"
	)
	var restored_reservations := (
		restored.spatial_capacity_summary(SPATIAL_LINK_ID).get("reservations", []) as Array
	)
	_check(
		restored_reservations.size() == 1,
		"active current-hour Spatial capacity reservation survives production save/load"
	)
	var continuation_minutes := CONTINUATION_HOURS * 60
	simulation.advance_minutes(continuation_minutes)
	restored.advance_minutes(continuation_minutes)
	_check(
		_strict_equal(simulation.get_persistent_state(), restored.get_persistent_state()),
		"saved continuation equals uninterrupted continuation with Spatial authority"
	)
	_check(
		simulation.authoritative_fingerprint() == restored.authoritative_fingerprint(),
		"saved and uninterrupted continuation fingerprints remain exact"
	)
	_check(
		restored.spatial_capacity_summary(SPATIAL_LINK_ID).get("reservations", []).is_empty(),
		"Spatial capacity window rolls over deterministically after continuation"
	)
	return before_snapshot


func _check_legacy_raw_json_read(snapshot: Dictionary) -> void:
	_cleanup_formal_save()
	var file := FileAccess.open(FormalWorldSimulation.SAVE_PATH, FileAccess.WRITE)
	_check(file != null, "legacy raw JSON fixture opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify(snapshot, "", true, true))
	file.close()
	# No backup is allowed to mask a legacy primary-file failure.
	_cleanup_path(FormalWorldSimulation.SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX)
	var restored := FormalWorldSimulation.new()
	var load_result := restored.load_from_user()
	_check(load_result.success, "pre-envelope legacy raw JSON Formal save remains readable")
	if not load_result.success:
		printerr("FORMAL_LEGACY_LOAD_ERROR=%s" % load_result.message)
		return
	_check(
		str(load_result.snapshot.get("schema_id", "")) == str(snapshot.get("schema_id", "")),
		"legacy raw JSON read preserves the existing Formal snapshot schema"
	)


func _read_exact_document(path: String) -> Dictionary:
	var parsed := _read_json_dictionary(path)
	if not bool(parsed.get("success", false)):
		return parsed
	var decoded := FormalWorldPersistenceDocument.decode(parsed.get("value", {}) as Dictionary)
	if not bool(decoded.get("success", false)):
		return {"success": false, "snapshot": {}, "error": str(decoded.get("error", "decode failed"))}
	return {"success": true, "snapshot": decoded.get("snapshot", {}), "error": ""}


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"success": false, "value": {}, "error": "file missing: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"success": false, "value": {}, "error": error_string(FileAccess.get_open_error())}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		return {"success": false, "value": {}, "error": "invalid JSON dictionary"}
	return {"success": true, "value": parser.data as Dictionary, "error": ""}


func _strict_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_FLOAT:
			return _float_bits(float(left)) == _float_bits(float(right))
		TYPE_DICTIONARY:
			var left_dict := left as Dictionary
			var right_dict := right as Dictionary
			if left_dict.size() != right_dict.size():
				return false
			for key: Variant in left_dict.keys():
				if not right_dict.has(key) or not _strict_equal(left_dict[key], right_dict[key]):
					return false
			return true
		TYPE_ARRAY:
			var left_array := left as Array
			var right_array := right as Array
			if left_array.size() != right_array.size():
				return false
			for index: int in range(left_array.size()):
				if not _strict_equal(left_array[index], right_array[index]):
					return false
			return true
		_:
			return left == right


func _float_from_bits(bits: String) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	for index: int in range(8):
		bytes[index] = bits.substr((7 - index) * 2, 2).hex_to_int()
	return bytes.decode_double(0)


func _float_bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var result := ""
	for index: int in range(7, -1, -1):
		result += "%02x" % bytes[index]
	return result


func _cleanup_formal_save() -> void:
	_cleanup_path(FormalWorldSimulation.SAVE_PATH)
	_cleanup_path(FormalWorldSimulation.SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX)


func _cleanup_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: %s" % message)
