extends SceneTree
## Read or migrate a copy through the selected project's real Persistence reader.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var source:=""
	var destination:=""
	var portable:=""
	var report:=""
	var expect_rejection:=false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--portable="):portable=arg.trim_prefix("--portable=")
		if arg.begins_with("--destination="):destination=arg.trim_prefix("--destination=")
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
		if arg=="--expect-rejection":expect_rejection=true
	if source.is_empty():push_error("需要显式--source；不会读取或替换默认存档槽。");quit(2);return
	if not destination.is_empty() and (ProjectSettings.globalize_path(source)==ProjectSettings.globalize_path(destination) or FileAccess.file_exists(destination)):
		push_error("迁移只允许写入新的副本路径。");quit(2);return
	var begin:=Time.get_ticks_msec()
	var decoded: Dictionary={}
	var outer: Variant=JSON.parse_string(FileAccess.get_file_as_string(source))
	if outer is Dictionary:decoded=FormalWorldPersistenceDocument.decode(outer)
	var loaded:=FormalPersistence.new()._restore_snapshot_file(source)
	var result: Dictionary={"reader_project":ProjectSettings.globalize_path("res://"),"pid":OS.get_process_id(),"source":source,"destination":destination,"accepted":loaded.success,"error":loaded.error,"read_ms":Time.get_ticks_msec()-begin,"source_unchanged":true,"source_world_schema":decoded.get("snapshot",{}).get("schema_id",""),"source_military_schema":decoded.get("snapshot",{}).get("military_state",{}).get("schema_id","")}
	if loaded.success:
		var snapshot:=loaded.persistence.snapshot()
		result.output_military_schema=snapshot.military_state.schema_id
		result.material_registry_exactly_preserved=snapshot.military_state.get("material_registry",{})==decoded.get("snapshot",{}).get("military_state",{}).get("material_registry",{})
		result.duty_exactly_preserved=snapshot.military_state.get("duty_operations",{})==decoded.get("snapshot",{}).get("military_state",{}).get("duty_operations",{})
		result.named_units=snapshot.military_state.formations
		result.training_group_exactly_preserved=snapshot.military_state.get("training_group",{})==decoded.get("snapshot",{}).get("military_state",{}).get("training_group",{})
		result.persons_exactly_preserved=snapshot.persons==decoded.snapshot.persons
		result.population_exactly_preserved=snapshot.population==decoded.snapshot.population
		result.organization_exactly_preserved=snapshot.organization==decoded.snapshot.organization
		result.person_count=loaded.world.person_overlay.person_count()
		result.material_counts=snapshot.military_state.get("material_registry",{}).get("view",{}).get("lot",{})
		result.material_registry_status="UNKNOWN_UNMODELED" if loaded.world.military_state.material_registry.is_empty() else "REGISTERED"
		result.military_appointment_count=loaded.world.organization_state.appointments_for_person(loaded.world.player_state.player_id()).size()
		result.world_minute=loaded.world.game_clock.total_minutes()
		result.person_id=loaded.world.player_state.player_id()
		var local: Dictionary=snapshot.military_state.get("local_operations",{})
		var before: Dictionary=decoded.get("snapshot",{}).get("military_state",{}).get("local_operations",{})
		result.local_schema=local.get("schema","")
		result.lease_and_events_preserved=local.get("active",{})==before.get("active",{}) and local.get("adoptions",{})==before.get("adoptions",{}) and local.get("interruptions",[])==before.get("interruptions",[])
		result.participants=[]
		for id: String in local.get("participants",{}):
			var p: Dictionary=local.participants[id]
			result.participants.append({"person_id":id,"vehicle_id":p.vehicle_id,"pending_seconds":p.pending_seconds,"pending_usec":p.get("pending_usec"),"adoption_count":p.adoption_count,"native_state_preserved":p.local==before.get("participants",{}).get(id,{}).get("local",{})})
		result.migration_history=loaded.persistence._save_metadata.get("migration_history",[])
		if ResourceLoader.exists("res://formal_link/authority.gd"):
			result.formal_resource_provenance=load("res://formal_link/authority.gd").assess(loaded.world,loaded.world.player_state.player_id())
		if not portable.is_empty():
			if FileAccess.file_exists(portable):push_error("Portable destination already exists");quit(2);return
			var portable_error: String=load("res://practice/recovery.gd").export_portable(portable,loaded.persistence)
			result.portable_written=portable_error.is_empty();result.portable_error=portable_error
		if not destination.is_empty():
			var document:=FormalWorldPersistenceDocument.encode(snapshot,loaded.persistence._save_metadata)
			var reason:=AtomicJsonFileStore.write_verified(destination,document,Callable(loaded.persistence,"_verify_temporary_save"),true)
			result.written=reason.is_empty();result.write_error=reason
	if not report.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report).get_base_dir())
		FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MILITARY_SAVE_READ "+JSON.stringify({"accepted":loaded.success,"source_military_schema":result.source_military_schema,"output_military_schema":result.get("output_military_schema",""),"written":result.get("written",false),"read_ms":result.read_ms}))
	quit(0 if (loaded.success!=expect_rejection and result.get("written",true)) else 1)
