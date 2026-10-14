class_name FormalPersistence
extends RefCounted
## Exact save representation and isolated candidate validation. No domain actions.

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v15"
const ORGANIZATION_COMPOSITION_STATE_SCHEMA_ID: String = "formal_organization_composition_state_v1"
const EVIDENCE_STATE_SCHEMA_ID: String = "historical_political_evidence_v1"

var error: String = ""
var _economy_r1: EconomyR1Slice
var _step_ref: WeakRef
var _step: SimulationStep:
	get:
		return _step_ref.get_ref() as SimulationStep if _step_ref != null else null
	set(value):
		_step_ref = weakref(value) if value != null else null
var _pending_save: bool = false
var _pending_slot: int = 1
var queued_save_result: SaveOperationResult
var _game_clock: GameClock
var _historical_evidence: HistoricalPoliticalEvidenceCatalog
var _political_registry: RuntimePoliticalEntityRegistry
var _market_registry: FormalWorldMarketRegistry
var _economy_state: FormalWorldEconomyState
var _spatial_world: VNextSpatialWorld
var _territory_state: TerritoryState
var _population_state: FormalWorldPopulationState
var _person_overlay: VNextNamedPersonOverlay
var _person_travel: FormalPersonTravel
var _player_state: VNextPlayerState
var _ledger_state: FormalLedgerState
var _personal_economy_state: FormalPersonalEconomyState
var _organization_state: OrganizationState
var _organization_evidence: FormalWorldOrganizationEvidenceCatalog
var _organization_responsibility: FormalWorldOrganizationResponsibilityService
var _military_state: VNextMilitaryState
var _organization_person_reference_ids: Array[String] = []
var _organization_place_reference_ids: Array[String] = []
var _explicit_organization_reference_injection: bool

func _init(world: WorldState = null, person_reference_ids: Array[String] = [], place_reference_ids: Array[String] = [], explicit_reference_injection: bool = false) -> void:
	# A menu load needs only the existing isolated candidate restoration path.
	if world == null: return
	_economy_r1 = world.economy_r1
	if _economy_r1 != null: _economy_r1.safe_boundary.connect(_complete_pending_save)
	_game_clock = world.game_clock
	_historical_evidence = world.historical_evidence
	_political_registry = world.political_registry
	_market_registry = world.market_registry
	_economy_state = world.economy_state
	_spatial_world = world.spatial_world
	_territory_state = world.territory_state
	_population_state = world.population_state
	_person_overlay = world.person_overlay
	_person_travel = world.person_travel
	_player_state = world.player_state
	_ledger_state = world.ledger_state
	_personal_economy_state = world.personal_economy_state
	_organization_state = world.organization_state
	_organization_evidence = world.organization_evidence
	_organization_responsibility = world.organization_responsibility
	_military_state = world.military_state
	_organization_person_reference_ids = person_reference_ids.duplicate()
	_organization_place_reference_ids = place_reference_ids.duplicate()
	_explicit_organization_reference_injection = explicit_reference_injection

func snapshot() -> Dictionary:
	var time_state := _game_clock.snapshot()
	var state := {
		"schema_id": SCHEMA_ID,
		"total_minutes": time_state["total_minutes"],
		"minute_remainder": time_state["minute_remainder"],
		"historical_evidence": {
			"schema_id": EVIDENCE_STATE_SCHEMA_ID,
			"fingerprint": _historical_evidence.fingerprint(),
		},
		"runtime_politics": _political_registry.snapshot(),
		"markets": _market_registry.get_persistent_state(),
		"economy": _economy_state.get_persistent_state(),
		"spatial": _spatial_world.snapshot(),
		"territory": _territory_state.snapshot(),
		"population": _population_state.snapshot(),
		"persons": _person_overlay.snapshot(),
		"player": _player_state.snapshot(),
		"ledger": _ledger_state.snapshot(),
		"personal_economy": _personal_economy_state.snapshot(),
		"organization": _organization_state.snapshot(),
		"organization_composition": {
			"schema_id": ORGANIZATION_COMPOSITION_STATE_SCHEMA_ID,
			"fingerprint": _organization_evidence.fingerprint(),
		},
		"organization_responsibilities": _organization_responsibility.snapshot(),
		"military_state": _military_state.snapshot(),
	}
	if _economy_r1 != null: state["economy_native"] = _economy_r1.snapshot()
	if _person_travel != null: state["person_travel"] = _person_travel.snapshot()
	return state

func authoritative_fingerprint() -> String:
	return JSON.stringify({
		"schema_id": "formal_world_authoritative_fingerprint_v9",
		"total_minutes": _game_clock.total_minutes(),
		"historical_evidence": _historical_evidence.fingerprint(),
		"runtime_politics": JSON.stringify(_political_registry.snapshot()).sha256_text(),
		"markets": JSON.stringify(_market_registry.get_persistent_state()).sha256_text(),
		"economy": JSON.stringify(_economy_state.get_persistent_state()).sha256_text(),
		"spatial": JSON.stringify(_spatial_world.snapshot()).sha256_text(),
		"territory": _territory_state.snapshot(),
		"population": _population_state.snapshot(),
		"persons": _person_overlay.state_fingerprint(),
		"player": JSON.stringify(_player_state.snapshot()).sha256_text(),
		"ledger": _ledger_state.snapshot(),
		"personal_economy": _personal_economy_state.snapshot(),
		"organization": _organization_state.state_fingerprint(),
		"organization_composition": _organization_evidence.fingerprint(),
		"organization_responsibilities": _organization_responsibility.state_fingerprint(),
		"military_state": _military_state.state_fingerprint(),
	}).sha256_text()

func save_version_error(found: String) -> String:
	return "SAVE FORMAT VERSION MISMATCH\nExpected: %s\nFound: %s\nReason: Formal land identity, topology, sovereignty, control and split lineage require spatial land fields; old saves cannot infer fine land." % [SCHEMA_ID, found]

func restore_candidate(state: Dictionary) -> WorldBuildResult:
	var r := WorldBuildResult.new()
	if str(state.get("schema_id", "")) != SCHEMA_ID:
		return _reject(r, save_version_error(str(state.get("schema_id", "missing"))))
	r = _new_candidate(state)
	if not r.success:
		return r
	if not _restore_candidate_state(r, state):
		return _reject(r, r.error)
	r.simulation_step = SimulationStep.new(r.world.game_clock, r.world.spatial_world, r.world.economy_state, r.economy_simulation, r.world.organization_responsibility, r.world.organization_state, r.world.political_registry_view, r.world.personal_economy_state, r.world.economy_r1, r.world.person_travel)
	r.persistence = FormalPersistence.new(r.world, r.organization_person_reference_ids, r.organization_place_reference_ids, r.explicit_organization_reference_injection)
	r.persistence.bind_step(r.simulation_step)
	return r

func _new_candidate(state: Dictionary) -> WorldBuildResult:
	if _explicit_organization_reference_injection:
		return WorldBootstrap.new().build(null, _organization_person_reference_ids, _organization_place_reference_ids,FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false)
	var opening_source := WorldBootstrap.DEFAULT_FORMAL_PERSON_TERRITORY_ID
	var persons: Variant = state.get("persons",{})
	var records: Variant = persons.get("persons",[]) if persons is Dictionary else []
	for raw: Variant in records if records is Array else []:
		if not raw is Dictionary: continue
		var person := raw as Dictionary
		var provenance: Variant = person.get("provenance",{})
		if not provenance is Dictionary: continue
		var source := str(provenance.get("opening_polity_source_id",""))
		var opening := WorldBootstrap.opening_profile(source)
		if not opening.is_empty() and str(person.get("person_id",""))==str(opening.person_id):
			opening_source = source
			break
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{},opening_source)

func _reject(r: WorldBuildResult, message: String) -> WorldBuildResult:
	r.success = false
	r.error = message
	error = message
	push_error("FORMAL PERSISTENCE ERROR: " + message)
	return r

func _restore_candidate_state(r: WorldBuildResult, state: Dictionary) -> bool:
	if str(state.get("schema_id", "")) != SCHEMA_ID:
		r.error = save_version_error(str(state.get("schema_id", "missing")))
		return false
	if state.size() != 18 + int(state.has("economy_native")) + int(state.has("person_travel")) or (state.has("economy_native") and not state["economy_native"] is Dictionary) or (state.has("person_travel") and not state["person_travel"] is Dictionary):
		r.error = "UNSUPPORTED SAVE FIELDS: personal money and employment require independent fields"
		push_error(r.error)
		return false
	for key: String in ["economy", "historical_evidence", "runtime_politics", "markets", "persons", "player", "ledger", "personal_economy", "organization", "organization_composition", "spatial", "territory", "population", "military_state", "organization_responsibilities"]:
		if not state.has(key) or not state[key] is Dictionary:
			r.error = "MISSING OR INVALID SAVE FIELD: %s" % key
			return false
	if not state.has("total_minutes") or not state.has("minute_remainder"):
		r.error = "MISSING SAVE CLOCK FIELDS: total_minutes / minute_remainder"
		return false
	if not r.world.game_clock.restore({"total_minutes": state["total_minutes"], "minute_remainder": state["minute_remainder"]}):
		r.error = r.world.game_clock.error
		return false
	if r.world.game_clock.current_hour() != int((state["economy"] as Dictionary).get("total_hour", -1)):
		r.error = "SAVE TIME CONFLICT: clock hour %d differs from economy hour %s" % [r.world.game_clock.current_hour(), (state["economy"] as Dictionary).get("total_hour", "missing")]
		return false
	var evidence: Dictionary = state["historical_evidence"]
	if str(evidence.get("schema_id", "")) != EVIDENCE_STATE_SCHEMA_ID:
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Unsupported historical evidence schema"
		return false
	if not r.world.political_registry.restore_snapshot(state["runtime_politics"], r.world.historical_evidence):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Invalid runtime_politics snapshot"
		return false
	r.world.political_registry_view = RuntimePoliticalEntityView.new(r.world.political_registry.snapshot())
	if not r.world.economy_state.bind_runtime_political_view(r.world.political_registry_view) or not r.world.market_registry.validate_persistent_state(state["markets"]):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Invalid markets snapshot or runtime political binding"
		return false
	if not r.world.population_state.restore(state["population"]):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: " + r.world.population_state.error
		return false
	if not r.world.person_overlay.restore(state["persons"]) or not _bind_restored_person_references(r) or not r.world.player_state.restore(state["player"]):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Invalid persons/player snapshot or organization reference catalog"
		return false
	if state.has("economy_native"):
		r.world.ledger_state.enable_economy_r1()
	if not r.world.ledger_state.restore(state["ledger"]):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: " + (r.world.ledger_state.error if not r.world.ledger_state.error.is_empty() else r.world.personal_economy_state.error)
		return false
	var composition: Dictionary = state["organization_composition"]
	if str(composition.get("schema_id", "")) != ORGANIZATION_COMPOSITION_STATE_SCHEMA_ID:
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Unsupported Organization composition schema"
		return false
	if not r.world.organization_state.restore(state["organization"]) or not _bind_restored_authorization(r):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Invalid organization snapshot or authorization dependencies"
		return false
	if not r.world.spatial_world.restore(state["spatial"]) or r.world.spatial_world.current_hour() != r.world.game_clock.current_hour():
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Spatial snapshot hour differs from the restored GameClock or spatial facts are invalid"
		return false
	var land := r.world.spatial_world.land_topology()
	var opening_controllers := r.world.territory_state.snapshot().controllers as Dictionary
	r.world.territory_state.bind_land_scope(land,r.world.political_registry)
	var control_ids := r.world.spatial_catalog.place_map_ids()
	control_ids.append_array(land.land_ids())
	if not r.world.territory_state.restore(state["territory"], control_ids, opening_controllers):
		r.error = r.world.territory_state.error
		return false
	if not r.world.spatial_world.apply_historical_land_administration(r.world.territory_state,HistoricalLoader._date_key(r.world.game_clock.current_date())):
		r.error = "Historical land administration could not be restored"
		return false
	if not r.world.military_state.restore(state["military_state"], r.world.military_map, r.world.spatial_world, r.world.territory_state):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Invalid military_state snapshot"
		return false
	if r.world.military_state.last_simulated_hour > r.world.game_clock.current_hour():
		r.error = "Military settlement cursor exceeds formal current hour"
		push_error(r.error)
		return false
	for action_id: String in r.world.military_state.active_actions:
		var action: Dictionary = r.world.military_state.active_actions[action_id]
		if str(action.get("kind", "")) == "defend" and int(action["start_hour"]) > r.world.game_clock.current_hour():
			r.error = "Defend action exceeds formal current hour: " + action_id
			push_error(r.error)
			return false
	if not r.world.economy_state.restore_persistent_state(state["economy"]) or not _bind_restored_responsibilities(r):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: Invalid economy snapshot or organization responsibility baseline"
		return false
	if state.has("economy_native"):
		var saved_native := state["economy_native"] as Dictionary
		if not saved_native.get("config") is Dictionary or not saved_native.get("subject_activation", {}) is Dictionary:
			r.error = "Native configuration is missing"
			return false
		var native := EconomyR1Slice.new()
		# Host identities, Ledger, Spatial and macro facts have already restored.
		# Loading binds and validates state; initialization is never invoked.
		if not native.bind(r.world, saved_native["config"], saved_native.get("subject_activation", {})) or not native.uses_host_accounts() or not native.restore(saved_native):
			r.error = "Native economic restore failed: " + native.error
			return false
		if not r.world.personal_economy_state.bind_native(native, r.world.ledger_state, r.world.game_clock, r.world.person_overlay, r.world.population_state) or not r.world.population_state.bind_native_background(native.background_responsibilities(), native):
			r.error = "Native personal/population binding failed"
			return false
		r.world.economy_r1 = native
		r.world.economy_state.bind_native_economy(native)
		if not r.world.player_state.lock_current_player():
			r.error = "Restored native player lock failed"
			return false
	if not r.world.personal_economy_state.restore(state["personal_economy"],r.world.player_state.player_id()):
		r.error = "Personal property restore failed: "+r.world.personal_economy_state.error
		return false
	if r.world.economy_r1 != null and not r.world.economy_r1.finalize_physical_restore():
		r.error = "Physical batch restore failed: "+r.world.economy_r1.error
		return false
	if state.has("person_travel") and not r.world.person_travel.restore(state["person_travel"]):
		r.error = "Host travel restore failed: "+r.world.person_travel.error
		return false
	if r.world.economy_r1 != null and not r.world.economy_r1.validate_transport_references():
		r.error = "Shared transport candidate references failed: "+r.world.economy_r1.error
		return false
	if not state.has("person_travel"):
		if r.world.economy_r1 != null and r.world.economy_r1.has_person_travel_responsibilities():
			r.error = "Passenger actions require their saved host journeys"
			return false
		for transaction: Dictionary in r.world.ledger_state.transactions():
			if transaction["kind"] == "person_travel":
				r.error = "Passenger payment has no saved travel authority"
				return false
	if not r.world.population_state.validate_residence_state(r.world) or (r.world.economy_r1 != null and (not r.world.economy_r1.validate_completed_exits() or not r.world.economy_r1.validate_business_continuity())):
		r.error = "Residence or economic responsibility handover restore failed: "+r.world.population_state.error+" "+(r.world.economy_r1.error if r.world.economy_r1 != null else "")
		return false
	if not r.world.organization_responsibility.restore(state["organization_responsibilities"], FormalWorldOrganizationView.new(r.world.organization_state.snapshot()), r.world.organization_evidence_view, r.world.political_registry_view, FormalWorldEconomyView.new(r.world.economy_state.read_only_snapshot()), r.world.game_clock.current_hour()):
		r.error = "SAVE CANDIDATE VALIDATION FAILED: " + (r.world.organization_responsibility.initialization_error if not r.world.organization_responsibility.initialization_error.is_empty() else "Invalid organization_responsibilities snapshot")
		return false
	return true

func _bind_restored_person_references(r: WorldBuildResult) -> bool:
	# Additional named population does not implicitly enlarge Organization's
	# configured reference scope. Every existing Organization reference must resolve.
	if not r.explicit_organization_reference_injection:
		if r.organization_person_reference_ids.is_empty(): return false
		var person := r.world.person_overlay.person(r.organization_person_reference_ids[0])
		if person.is_empty(): return false
		var origin := str((person.provenance as Dictionary).get("opening_place_id",WorldBootstrap.DEFAULT_FORMAL_PERSON_PLACE_ID))
		if not r.world.spatial_catalog.has_place(origin): return false
		r.organization_place_reference_ids = [origin]
	for person_id: String in r.organization_person_reference_ids:
		if not r.world.person_overlay.has_person(person_id):
			return false
	r.world.organization_state = OrganizationState.new()
	if not r.world.organization_state.configure_reference_catalog(r.organization_person_reference_ids, r.organization_place_reference_ids):
		return false
	r.world.player_state = VNextPlayerState.new()
	return r.world.player_state.bind_person_authority(r.world.person_overlay)

func _bind_restored_authorization(r: WorldBuildResult) -> bool:
	if not r.world.organization_state.is_valid():
		return false
	r.world.authorization_check = AuthorizationCheck.new(r.world.organization_state)
	return true

func _bind_restored_responsibilities(r: WorldBuildResult) -> bool:
	r.world.organization_responsibility = FormalWorldOrganizationResponsibilityService.new()
	return r.world.organization_responsibility.configure(
		FormalWorldOrganizationView.new(r.world.organization_state.snapshot()),
		r.world.organization_evidence_view, r.world.political_registry_view,
		FormalWorldEconomyView.new(r.world.economy_state.read_only_country_observation_snapshot()),
		r.world.game_clock.current_hour()
	)

func save_to_user(slot: int = 1) -> SaveOperationResult:
	var path := slot_path(slot)
	if path.is_empty(): return SaveOperationResult.fail("invalid_slot","请选择存档槽。","")
	if (_step != null and _step.processing) or (_economy_r1 != null and _economy_r1.processing):
		_pending_save = true
		_pending_slot = slot
		return SaveOperationResult.fail("queued", "保存已排队，等待正式世界完成当前推进。", path)
	var snapshot := snapshot()
	var persistence_document := FormalWorldPersistenceDocument.encode(snapshot)
	if persistence_document.is_empty():
		return SaveOperationResult.fail(
			"encode_error",
			"正式世界精确持久化载荷编码失败",
			path
		)
	var player := _person_overlay.person(_player_state.player_id())
	var politics := RuntimePoliticalEntityView.new(_political_registry.snapshot())
	var polity := CurrentWorldPoliticalProjection.polity_summary(politics.runtime_id_for_source(str(player.get("population_territory_id",""))),politics,HistoricalPoliticalEvidenceView.new(_historical_evidence.read_only_snapshot()))
	persistence_document["ui_summary"] = {"game_date":_game_clock.current_date(),"saved_at_unix":int(Time.get_unix_time_from_system()),"person_name":str(player.get("name_zh",player.get("name","姓名未记录"))),"country_name":str(polity.get("name_zh",""))}
	var write_error := AtomicJsonFileStore.write_verified(
		path,
		persistence_document,
		Callable(self, "_verify_temporary_save"),
		true
	)
	if not write_error.is_empty():
		return SaveOperationResult.fail(
			"write_error",
			"正式世界保存失败：%s" % write_error,
			path
		)
	var result := SaveOperationResult.ok(path, snapshot)
	result.message = "正式世界已保存。"
	return result

func _verify_temporary_save(absolute_path: String) -> String:
	var loaded := _read_snapshot_file(absolute_path)
	if not loaded.success:
		return "临时存档校验失败：%s" % loaded.message
	var candidate := restore_candidate(loaded.snapshot)
	if not candidate.success:
		return "Temporary save candidate validation failed: " + candidate.error
	return ""

func load_from_user(slot: int = 1) -> WorldBuildResult:
	var path := existing_slot_path(slot)
	if path.is_empty():
		var empty := WorldBuildResult.new()
		empty.error = "空存档"
		empty.operation = SaveOperationResult.fail("not_found",empty.error,slot_path(slot))
		return empty
	var primary := _restore_snapshot_file(path)
	if primary.success or primary.operation.error_code == "save_format_version_mismatch":
		if primary.success:
			primary.operation.message = "正式世界存档已恢复。"
		return primary
	var backup := _restore_snapshot_file(path + AtomicJsonFileStore.BACKUP_SUFFIX)
	if backup.success or backup.operation.error_code == "save_format_version_mismatch":
		if backup.success:
			backup.operation.path = path
			backup.operation.message = "主存档不可用，已读取安全备份"
		return backup
	primary.operation = SaveOperationResult.fail("load_error", "主存档不可用：%s；安全备份不可用：%s" % [primary.operation.message, backup.operation.message], path)
	primary.error = primary.operation.message
	return primary

static func slot_path(slot: int) -> String:
	if slot==0: return "user://formal_world_1900_auto.json"
	return "user://formal_world_1900_manual_%d.json" % slot if slot in [1,2,3,4] else ""

static func slot_name(slot: int) -> String:
	return "自动存档" if slot==0 else "手动存档 %d" % slot

static func existing_slot_path(slot: int) -> String:
	var path := slot_path(slot)
	if path.is_empty(): return ""
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+AtomicJsonFileStore.BACKUP_SUFFIX): return path
	# The old file is only read through the first manual slot; it is never overwritten.
	if slot==1 and (FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_PATH+AtomicJsonFileStore.BACKUP_SUFFIX)): return SAVE_PATH
	return ""

static func slot_summaries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for slot: int in range(5):
		var path := existing_slot_path(slot)
		var row := {"slot":slot,"name":slot_name(slot),"empty":path.is_empty(),"summary":{},"legacy":path==SAVE_PATH}
		if not path.is_empty():
			var actual := path if FileAccess.file_exists(path) else path+AtomicJsonFileStore.BACKUP_SUFFIX
			var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(actual))
			if value is Dictionary: row.summary = (value as Dictionary).get("ui_summary",{})
			row["saved_at_unix"] = FileAccess.get_modified_time(actual)
		rows.append(row)
	return rows

static func summary_text(row: Dictionary) -> String:
	if bool(row.get("empty",true)): return "空存档"
	var info := row.get("summary",{}) as Dictionary
	var parts: Array[String] = []
	var date := info.get("game_date",{}) as Dictionary
	if not date.is_empty(): parts.append("%04d-%02d-%02d %02d:%02d" % [date.year,date.month,date.day,date.hour,date.minute])
	for key: String in ["person_name","country_name"]:
		if not str(info.get(key,"")).is_empty(): parts.append(str(info[key]))
	var unix := int(info.get("saved_at_unix",row.get("saved_at_unix",0)))
	if unix>0:
		var saved := Time.get_datetime_dict_from_unix_time(unix+int(Time.get_time_zone_from_system().bias)*60)
		parts.append("保存于 %04d-%02d-%02d %02d:%02d" % [saved.year,saved.month,saved.day,saved.hour,saved.minute])
	if bool(row.get("legacy",false)): parts.append("已有存档")
	return " · ".join(parts)

func _restore_snapshot_file(path: String) -> WorldBuildResult:
	var loaded := _read_snapshot_file(path)
	var r := WorldBuildResult.new()
	r.operation = loaded
	if not loaded.success:
		r.error = loaded.message
		return r
	r = restore_candidate(loaded.snapshot)
	r.operation = loaded if r.success else SaveOperationResult.fail("restore_error", r.error, path)
	return r

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
	var decoded := FormalWorldPersistenceDocument.decode(parser.data as Dictionary)
	if not bool(decoded.get("success", false)):
		return SaveOperationResult.fail(
			str(decoded.get("error_code", "invalid_snapshot")),
			str(decoded.get("error", "正式世界持久化文档无效")),
			path
		)
	var snapshot: Variant = decoded.get("snapshot", {})
	if not snapshot is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"正式世界持久化载荷不是快照对象",
			path
		)
	return SaveOperationResult.ok(path, snapshot as Dictionary)

func bind_step(step: SimulationStep) -> void:
	_step = step
	if not step.safe_boundary.is_connected(_complete_pending_save):
		step.safe_boundary.connect(_complete_pending_save)

func _complete_pending_save() -> void:
	if (_step != null and _step.processing) or (_economy_r1 != null and _economy_r1.processing): return
	if _pending_save:
		_pending_save = false
		queued_save_result = save_to_user(_pending_slot)
