extends "res://global_link/tour.gd"
## Two recordings. The second process loads the real Formal save from disk.
var returning := false
var waiting_save := false
var preflight_stage := 0
var starting_elapsed := 0.0
var ready_local_time := 0.0

func _process(delta: float) -> void:
	if preflight_stage<2:
		clock+=delta
		if preflight_stage==0 and clock>.5:
			click_root(Vector2(1100,613));preflight_stage=1;clock=0
		elif preflight_stage==1:
			if clock>1:mark("formal_combat_conditions_denied")
			if clock>2:
				click_root(host.authority_close.get_global_rect().get_center());preflight_stage=2;clock=0
		return
	clock+=delta
	if phase==0:
		text("原WorldBootstrap / FormalPersistence → 当前WorldState → 同一SpatialCatalog")
		if clock>.5:mark("formal_earth_loaded" if host.boot_loaded else "formal_earth_new")
		if clock>2 and not marks.has("training_selected"):
			host.globe.focus_training(true);click_map(host.globe.project(host.globe.anchor_frame.z));mark("training_selected")
		if clock>4:
			click_root(host.enter_button.get_global_rect().get_center());phase=1;clock=0
	elif phase==1:
		if host.mode=="local":
			starting_elapsed=host.local_shell.battle.elapsed;phase=2;clock=0
		elif clock>30:
			fail_tour("正式租约进入失败")
	elif phase==2:
		var nav: Control=host.local_shell.navigation
		var battle: Node=host.local_shell.battle
		if host.formal_tour_mode=="restart":
			if clock<3:
				nav.set_range(50000);text("冷启动：从正式精确存档恢复；这是一份新的Godot战场实例")
				if clock>1:mark("cold_reentered_50km")
			elif clock<7:nav.set_range(exp(lerpf(log(50000),log(14),smoothstep(3,7,clock))))
			elif clock<10:
				text("原正式人物与同一训练资源：不补弹、不补血、不重放射击")
				if clock>8:mark("cold_same_person_vehicle")
			elif clock<14:
				if not marks.has("cold_return_tab"):
					marks["cold_return_tab"]=true;send_key(KEY_TAB)
				text("冷重入后回同一球面；原世界地点仍保留")
				if clock>12:mark("cold_globe_return")
			else:
				click_root(host.enter_button.get_global_rect().get_center());phase=4;clock=0
			return
		if clock<3:
			text("正式人物进入训练能力；其他四人为训练辅助，未授予军队命令权")
			if clock>1:mark("formal_50km")
		elif clock<6:nav.set_range(exp(lerpf(log(50000),log(25000),smoothstep(3,6,clock))))
		elif clock<8:
			text("保留原25公里同图观察")
			if clock>7:mark("formal_25km")
		elif clock<11:nav.set_range(exp(lerpf(log(25000),log(5000),smoothstep(8,11,clock))))
		elif clock<13:
			text("保留原5公里战场；训练地形未写入正式地理")
			if clock>12:mark("formal_5km")
		elif clock<18:nav.set_range(exp(lerpf(log(5000),log(14),smoothstep(13,18,clock))))
		elif clock<21:
			nav.set_range(14)
			if not marks.has("drive_start"):
				marks["drive_start"]=true;drive_input(battle,true)
			if clock>20 and not marks.has("drive_end"):
				marks["drive_end"]=true;drive_input(battle,false)
			if clock>20.2 and not fired:
				click_root(battle.battle_controls.center_fire());fired=true
		elif clock<23:
			text("原生摇杆与击发：训练弹药由原模块扣除")
			if clock>22:mark("formal_native_action")
		else:
			send_key(KEY_TAB);phase=3;clock=0
	elif phase==3:
		if clock>.2 and host.mode!="global":fail_tour("返回球面失败");return
		text("只是切换观察：局部仍推进，装填不会因球面模式冻结")
		if clock>.5:mark("formal_globe_pending")
		if clock>3.5:mark("formal_globe_reload_finished")
		if clock>4:
			click_root(host.enter_button.get_global_rect().get_center());phase=4;clock=0
	elif phase==4:
		if clock>.2 and host.mode!="local":fail_tour("同一租约再进入失败");return
		var battle: Node=host.local_shell.battle
		if clock>1:mark("formal_same_lease_reentered")
		if host.formal_tour_mode!="restart":
			if clock>3 and not walking:
				var result: Dictionary=battle.crew_host.disembark_person(battle.crew_host.commander_person_id())
				print("FORMAL_DISEMBARK "+JSON.stringify(result));walking=true
			if clock>4 and not marks.has("walk_start"):
				marks["walk_start"]=true;drive_input(battle,true)
			if clock>5.2 and not marks.has("walk_end"):
				marks["walk_end"]=true;drive_input(battle,false)
			if clock>6 and not boarded:
				var result: Dictionary=battle.player_infantry_controller.request_board()
				print("FORMAL_BOARD "+JSON.stringify(result));boarded=true
			if clock>8:mark("formal_original_crew_returned")
			text("等待局部满一分钟，再交还原Formal宿主，保存并销毁局部实例")
		else:text("冷启动重入没有重复开火；再次交还正式宿主")
		var ready_to_return: bool=battle.elapsed-starting_elapsed>61.0 if host.formal_tour_mode!="restart" else clock>3
		if ready_to_return and not returning:
			returning=true;mark("before_formal_commit")
			click_root(Vector2(1170,18));phase=5;clock=0
	elif phase==5:
		if host.saving:
			waiting_save=true;clock=0;text("唯一采用已完成；原正式保存正在后台核验，界面继续绘制");return
		if waiting_save:waiting_save=false;clock=0
		if clock>.3 and not host.last_adoption.get("ok",false):fail_tour("正式采用失败："+str(host.last_adoption));return
		text("已采用一次 → 原FormalPersistence保存 → 局部实例销毁")
		if clock>.5 and not marks.has("native_duplicate_checked"):
			marks["native_duplicate_checked"]=true;host.check_native_duplicate()
			if not host.last_duplicate.get("duplicate",false) or not host.last_duplicate.get("state_unchanged",false) or not host.last_duplicate.get("clock_unchanged",false):fail_tour("原生交还重复采用未被忽略");return
		if clock>1:mark("formal_saved_without_local_instance")
		if clock>3:
			host.record("formal_tour_finished");host.save_observations()
			print("FORMAL_TOUR_FINISHED "+host.formal_tour_mode)
			if host.formal_application!=null:
				host.close_to_formal();phase=6
			else:get_tree().quit()

func fail_tour(reason: String) -> void:
	host.record("formal_tour_failed");host.save_observations();push_error(reason);get_tree().quit(1)
