extends SceneTree
## The single requested local continuity exercise. No repository-wide suite.
var checks: Dictionary = {}
var shell: Node
var output_path := "user://continuity_result.json"
var capture_directory := ""

func _initialize() -> void:
	run.call_deferred()

func expect(key: String, value: bool) -> void:
	checks[key]=value
	if not value: push_error("CONTINUITY: "+key)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_directory=arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(capture_directory)
	shell=load("res://triple/main.tscn").instantiate()
	root.add_child(shell)
	for i: int in 90:
		await physics_frame
		if shell.ready_battle: break
	expect("native_host_input_installed",shell.ready_battle)
	if not shell.ready_battle:
		finish();return
	var battle: Node=shell.battle
	var before: Dictionary=shell.port.snapshot(battle)
	await save_step("01_region_50km")
	expect("original_five_bodies",battle.ai_host.actors.size()==5 and battle.crew_host.registry._people.size()==5)
	expect("shared_commander_body",is_same(battle.player_combat.crew[0],battle.crew_host.registry._people["player_vehicle:person:0"]))
	expect("native_position_restored",Vector2(before.position_local[0]-shell.port.request.position_local[0],before.position_local[2]-shell.port.request.position_local[2]).length()<.001)
	if "--restore-only" in OS.get_cmdline_user_args():
		# JSON numbers arrive as doubles; the native owner uses integer counters.
		# Compare canonical JSON values, including every reserve/loading/spent field.
		expect("ammo_return_reinstalled",JSON.parse_string(JSON.stringify(before.native_ammo))==shell.port.request.native_ammo)
		expect("injury_return_reinstalled",before.crew[0].hp==shell.port.request.crew[0].hp and before.crew[0].parts==shell.port.request.crew[0].parts)
		expect("event_return_reinstalled",before.shot_sequence==shell.port.request.shot_sequence and before.shot_audit==shell.port.request.shot_audit)
		expect("time_return_reinstalled",is_equal_approx(before.absolute_seconds,shell.port.request.absolute_seconds))
		expect("settlement_ids_restored",before.native_settled==shell.port.request.native_settled)
		shell.export_to_host()
		expect("cold_return_written",shell.port.closed)
		finish();return
	shell.enter_selected()
	expect("50_to_25",shell.level==25)
	await save_step("02_sector_25km")
	shell.enter_selected()
	expect("25_to_5",shell.level==5)
	await save_step("03_battle_5km_entry")
	# Exercise the existing driving controller through its regular input, real
	# terrain support and contact resolver. No position assignment in this step.
	battle.battle_controls.drive=Vector2(0,-1)
	for i: int in 90: await physics_frame
	battle.battle_controls.reset_pointers()
	var moved: Dictionary=shell.port.snapshot(battle)
	expect("native_driving_over_2m",Vector2(moved.position_local[0]-before.position_local[0],moved.position_local[2]-before.position_local[2]).length()>2)
	# Real native body operation, explicitly controlled rather than an enemy hit.
	battle.player_combat.hit_person(battle.player_combat.crew[0],"right_arm")
	battle.fire_cannon()
	expect("native_cannon_consumed_one",battle.vehicle_ammo.status("player_vehicle","primary").spent==before.native_ammo.vehicles.player_vehicle.primary.spent+1)
	expect("physical_projectile_created",not get_nodes_in_group("tank_projectile").is_empty())
	shell.go_back()
	var paused: Dictionary=shell.port.snapshot(battle)
	await save_step("04_back_25km_projectile_paused")
	for i: int in 15: await physics_frame
	expect("upper_view_pauses_all_state",paused==shell.port.snapshot(battle))
	shell.enter_selected()
	for i: int in 300:
		await physics_frame
		if get_nodes_in_group("artillery_projectile").is_empty(): break
	expect("native_projectile_finished",get_nodes_in_group("artillery_projectile").is_empty())
	await save_step("05_battle_5km_after_movement_and_fire")
	shell.go_back()
	var after: Dictionary=shell.port.snapshot(battle)
	shell.go_back()
	expect("back_to_50",shell.level==50)
	await save_step("06_back_50km_state_retained")
	shell.select_point(Vector2(27500,22500))
	shell.enter_selected()
	expect("adjacent_sector_selected",shell.sector==Vector2i(1,0))
	await save_step("07_adjacent_sector_S10")
	expect("selection_did_not_move_actor",after==shell.port.snapshot(battle))
	shell.show_level(5)
	expect("unbuilt_adjacent_tile_rejected",shell.level==25)
	expect("half_open_25km_boundary",shell.space.sector_at(Vector2(24999.999,22500))==Vector2i(0,0) and shell.space.sector_at(Vector2(25000,22500))==Vector2i(1,0))
	shell.locate_vehicle()
	shell.enter_selected()
	expect("reenter_original_5km",shell.level==5)
	expect("same_objects_state_and_events",after==shell.port.snapshot(battle))
	await save_step("08_reentered_same_5km")
	shell.go_back()
	expect("injury_persists",battle.player_combat.crew[0].hp==4 and battle.player_combat.crew[0].parts.right_arm=="injured")
	shell.export_to_host()
	expect("external_return_written",shell.port.closed)
	expect("duplicate_local_return_rejected",not shell.port.export_return(battle,shell.return_path))
	shell.show_level(5)
	expect("closed_lease_cannot_resume",shell.level!=5)
	await save_step("09_return_to_external_host")
	shell.admin_mode=true
	shell.show_level(50)
	await save_step("10_existing_WWO_admin_references")
	finish()

func save_step(label: String) -> void:
	if capture_directory.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory+"/"+label+".png")

func finish() -> void:
	var failed: Array=[]
	for key: String in checks:
		if not checks[key]: failed.append(key)
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"snapshot":shell.port.snapshot(shell.battle) if shell.ready_battle else {},"transitions":shell.transitions,"memory":shell.memory_frames},"\t"))
	file.close()
	print("CONTINUITY_RESULT "+JSON.stringify({"checks":checks.size(),"failed":failed,"output":ProjectSettings.globalize_path(output_path)}))
	paused=false
	shell.queue_free()
	await process_frame
	quit(0 if failed.is_empty() else 1)
