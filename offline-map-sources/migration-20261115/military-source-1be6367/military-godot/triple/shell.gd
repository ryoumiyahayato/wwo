extends Node
signal prepared
const Space = preload("res://triple/space.gd")
const Port = preload("res://triple/port.gd")
var space := Space.new()
var port := Port.new()
var battle: Node3D
var layer: CanvasLayer
var root: Control
var map_view: Control
var title: Label
var subtitle: Label
var details: Label
var status: Label
var enter_button: Button
var back_button: Button
var export_button: Button
var battle_info: Label
var panel: ColorRect
var level := 50
var sector := Vector2i.ZERO
var selection := Vector2(22500,22500)
var ready_battle := false
var admin_mode := false
var transitions: Array = []
var memory_frames: Array = []
var last_snapshot: Dictionary = {}
var return_path := "user://host_return.json"
var request_path := "res://triple/default_request.json"
var ui_tick := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit=false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--host-request="): request_path=arg.trim_prefix("--host-request=")
		if arg.begins_with("--host-return="): return_path=arg.trim_prefix("--host-return=")
	_build_ui()
	status.text="读取训练空间与宿主租约。"
	if not port.read_request(request_path):
		status.text=port.error
		return
	space.load_sources()
	map_view.space=space
	battle=preload("res://triple/battle.gd").new()
	add_child(battle)
	battle.process_mode=Node.PROCESS_MODE_PAUSABLE
	battle.map_requested.connect(func() -> void: show_level(25))
	var began:=Time.get_ticks_msec()
	battle.choose_game_mode("skirmish")
	# Native deferred terrain settling binds original crew and real physics first.
	for i: int in 20:
		await get_tree().physics_frame
		if battle.crew_host.person_ids.size()==5: break
	if battle.crew_host.person_ids.size()!=5 or not port.install(battle):
		status.text="载入拒绝："+port.error
		_pause_battle()
		return
	battle.battle_controls.request_camera_snap()
	ready_battle=true
	memory_frames.append({"kind":"cold_native_load","milliseconds":Time.get_ticks_msec()-began,"static_memory":OS.get_static_memory_usage(),"chunks":battle.terrain_damage.chunks.size()})
	show_level(50)
	status.text=("新建隔离样例。" if request_path.begins_with("res://") else "外部宿主传入完成。")+"选择S00战区，再选择Ridgevale进入。"
	prepared.emit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		# Closing never writes into the formal WWO save or silently commits a lease.
		get_tree().paused=false
		get_tree().quit()

func _build_ui() -> void:
	layer=CanvasLayer.new();layer.layer=100;add_child(layer)
	root=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(root)
	var theme:=Theme.new();theme.default_font=load("res://cedar/system_font.tres");theme.default_font_size=16;root.theme=theme
	panel=ColorRect.new();panel.color=Color("101a1a");panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(panel)
	var top:=ColorRect.new();top.color=Color("111d20");top.position=Vector2.ZERO;top.size=Vector2(1280,118);top.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(top)
	title=_label(Vector2(26,14),Vector2(960,32),25)
	subtitle=_label(Vector2(26,53),Vector2(1220,26),15)
	back_button=_button("← 上级地图",Vector2(26,83),Vector2(140,32),go_back)
	_button("行政地点",Vector2(180,83),Vector2(120,32),func() -> void:
		admin_mode=true;show_level(50))
	_button("军事区域 50km",Vector2(312,83),Vector2(160,32),func() -> void:
		admin_mode=false;show_level(50))
	_button("定位原车",Vector2(484,83),Vector2(130,32),locate_vehicle)
	_button("截图 F9",Vector2(1110,83),Vector2(135,32),capture)
	map_view=preload("res://triple/map_view.gd").new();map_view.position=Vector2(77,143);map_view.size=Vector2(535,535);root.add_child(map_view)
	map_view.selected.connect(select_point)
	details=_label(Vector2(667,153),Vector2(576,362),15);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enter_button=_button("进入选定25公里战区 →",Vector2(749,531),Vector2(492,45),enter_selected)
	export_button=_button("交还外部宿主（一次）",Vector2(749,586),Vector2(492,39),export_to_host)
	status=_label(Vector2(749,637),Vector2(494,68),14);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	battle_info=_label(Vector2(640,84),Vector2(440,30),14)

func _label(at: Vector2, extent: Vector2, pixels: int) -> Label:
	var label:=Label.new();label.position=at;label.size=extent;label.add_theme_font_size_override("font_size",pixels);label.add_theme_color_override("font_color",Color("dfdfca"));label.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(label);return label

func _button(text: String, at: Vector2, extent: Vector2, action: Callable) -> Button:
	var button:=Button.new();button.text=text;button.position=at;button.size=extent;button.pressed.connect(action);root.add_child(button);return button

func _pause_battle() -> void:
	if not is_instance_valid(battle): return
	# Legacy controls use ALWAYS to operate their own pause menu. Normalise this
	# bounded subtree so upper views also pause reload, actors and projectiles.
	for child: Node in battle.find_children("*","",true,false):
		if child.process_mode==Node.PROCESS_MODE_ALWAYS: child.process_mode=Node.PROCESS_MODE_PAUSABLE
	battle.battle_controls.reset_pointers()
	battle.clear_vehicle_fire_input()
	get_tree().paused=true
	battle.hide()
	battle.hud.hide()

func show_level(next: int) -> void:
	if not ready_battle: return
	var begin:=Time.get_ticks_usec()
	if next==5 and (port.closed or space.tile_at(selection).get("id","")!=Space.ACTIVE):
		status.text="该格仅有资料。原车未移动。请选择Ridgevale。"
		return
	if next!=5:
		_pause_battle()
	else:
		get_tree().paused=false
		battle.show();battle.hud.show()
		battle.battle_controls.request_camera_snap()
	level=next
	panel.visible=level!=5
	for node: CanvasItem in [map_view,details,enter_button,export_button,status]: node.visible=level!=5
	map_view.admin_mode=admin_mode
	map_view.bounds=Rect2(0,0,50000,50000) if level==50 else Rect2(Vector2(sector)*25000,Vector2.ONE*25000)
	map_view.selected_point=selection
	map_view.unit_point=Space.world_position(battle.hero.position)
	map_view.queue_redraw()
	var record: Dictionary=port.snapshot(battle)
	transitions.append({"level":level,"snapshot":record,"view_change_usec":Time.get_ticks_usec()-begin})
	if transitions.size()>64: transitions.pop_front()
	last_snapshot=record
	memory_frames.append({"kind":"view_%d"%level,"static_memory":OS.get_static_memory_usage(),"chunks":battle.terrain_damage.chunks.size(),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
	if memory_frames.size()>64: memory_frames.pop_front()
	_refresh()

func select_point(point: Vector2) -> void:
	selection=point
	map_view.selected_point=point
	_refresh()

func enter_selected() -> void:
	if admin_mode:
		admin_mode=false;show_level(50);return
	if level==50:
		sector=Space.sector_at(selection)
		show_level(25)
	elif level==25:
		show_level(5)

func go_back() -> void:
	admin_mode=false
	if level==5:
		selection=Space.world_position(battle.hero.position)
		sector=Space.sector_at(selection)
		show_level(25)
	else: show_level(50)

func locate_vehicle() -> void:
	if not ready_battle: return
	admin_mode=false
	selection=Space.world_position(battle.hero.position)
	sector=Space.sector_at(selection)
	if level==5: show_level(25)
	else: show_level(level)

func _refresh() -> void:
	if not ready_battle: return
	var point:=Space.world_position(battle.hero.position)
	var person: Dictionary=battle.player_combat.crew[0]
	var primary: Dictionary=battle.vehicle_ammo.status("player_vehicle","primary")
	title.text="%d × %d 公里  /  %s"%[level,level,"军事区域" if level==50 else "战区 S%d%d"%[sector.x,sector.y] if level==25 else "Ridgevale 可操作战场"]
	if admin_mode: title.text="行政地点引用  /  WWO现有目录"
	subtitle.text="训练空间 · %s  |  外部宿主隔离接续 · 未合入正式WWO"%Space.REGION_ID
	if level==5: subtitle.text="50km 区域 → S00 [0,25000) → C44 [20000,25000) m · ridgevale_5km_c1_20261020 · 训练场未地理配准"
	battle_info.text="林澄 HP %.0f · 炮弹 %d · t %.1fs"%[person.hp,primary.total,battle.elapsed]
	var tile: Dictionary=space.tile_at(selection)
	var region_cell:=Space.cell_at(selection)
	var current_cell:=Space.cell_at(point)
	var parts: Dictionary=person.parts
	var injured: Array=[]
	for key: String in parts:
		if parts[key]!="healthy": injured.append(key+":"+str(parts[key]))
	details.text=("区域ID  %s\n战区 S%d%d  /  X,Z [%d,%d] → [%d,%d] m\n选格 C%d%d · %s\n\n原车 player_vehicle · %s\n车长 %s\n人物ID %s\n全车5人 · 已登记 %d 人 · 原生Actor %d\n区域位置 X %.2f / Z %.2f m\n当前格 C%d%d · 本地 X %.2f / Z %.2f m\nHP %.0f · %s\n炮弹 %d · 已消耗 %d · 事件 %d\n绝对秒 %.2f · 局部秒 %.2f\n\n资料区间采用半开边界。\n选格只移动观察范围。\n相邻资料格未接缝、未开放驾驶。")%[Space.REGION_ID,sector.x,sector.y,sector.x*25000,sector.y*25000,(sector.x+1)*25000,(sector.y+1)*25000,region_cell.x,region_cell.y,tile.get("name","未制作"),battle.selected_catalog_id,person.get("display_name","林澄"),person.person_id,battle.crew_host.registry._people.size(),battle.ai_host.actors.size(),point.x,point.y,current_cell.x,current_cell.y,battle.hero.position.x,battle.hero.position.z,person.hp," / ".join(injured),primary.total,primary.spent,battle.shot_audit.size(),float(port.request.absolute_seconds)+battle.elapsed-float(port.request.get("local_elapsed",0)),battle.elapsed]
	# The region ID already appears in the header. Keep the status panel above
	# the real entry and return controls at the 1280x720 baseline.
	details.text=details.text.get_slice("\n",1)+"\n"+"\n".join(details.text.split("\n").slice(2,13))+"\n\n选格不移动原车。相邻资料格未接缝、未开放驾驶。"
	if admin_mode:
		details.text="来源：正式WWO data/world_map/cities.json\n\nplace:paris\n巴黎 · [2.3522,48.8566]\ncountry_fra / ile_de_france\n\n训练场使用独立米制坐标。\n此处只引用既有地点作宿主背景。\nCedar / Rivergate / Ridgevale均无史实地理配准，不写成巴黎真实地形。\n\n没有写入地点、人口、库存或经济。\n军事入口与行政地点页共享当前宿主。\n正式WWO原行政地图未修改。"
	enter_button.text="军事区域 →" if admin_mode else "进入选定25公里战区 →" if level==50 else "进入 Ridgevale 5公里战场 →" if tile.get("id","")==Space.ACTIVE else "该格未开放驾驶 · 选择原车所在格"
	enter_button.disabled=port.closed or (level==25 and tile.get("id","")!=Space.ACTIVE)
	export_button.disabled=port.closed
	back_button.text="← 返回25公里" if level==5 else "← 返回50公里"

func export_to_host() -> void:
	if not ready_battle or level==5: return
	if port.export_return(battle,return_path):
		status.text="状态已交还："+ProjectSettings.globalize_path(return_path)+"。局部租约已关闭。"
		write_session("user://session_continuity.json")
		_refresh()
	else: status.text=port.error

func write_session(path: String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"transitions":transitions,"memory":memory_frames,"last":port.snapshot(battle)},"\t"))

func _process(delta: float) -> void:
	if not ready_battle: return
	ui_tick+=delta
	if ui_tick>=.3:
		ui_tick=0
		_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F9: capture()
		if event.keycode==KEY_ESCAPE: go_back()

func capture() -> void:
	await RenderingServer.frame_post_draw
	var directory: String=ProjectSettings.globalize_path("user://screenshots")
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory+"/%s_%dkm.png"%[Time.get_datetime_string_from_system().replace(":","-"),level]
	get_viewport().get_texture().get_image().save_png(path)
	if ready_battle: write_session("user://session_continuity.json")
	status.text="截图已保存："+path
