extends Node3D
const CedarArt = preload("res://cedar/cedar_art.gd")
const GroundSupport = preload("res://scripts/vehicle_ground_support.gd")
const SmokeCloud = preload("res://scripts/smoke_cloud.gd")
const CombatEffects = preload("res://scripts/combat_effects.gd")
const VehicleContacts = preload("res://scripts/vehicle_contact_resolver.gd")
var vehicle_contacts = VehicleContacts.new()
const VehicleAmmo = preload("res://modules/vehicle_ammo/vehicle_ammo.gd")
var vehicle_ammo = VehicleAmmo.new()
const PLAYER_VEHICLE_ID := "player_vehicle"
var fire_input_epoch := 0
var fire_control = preload("res://modules/vehicle_fire_control/gunner_intent.gd").new()
var combat_effects: Node3D
var armor_host: Node
var combined_battle_enabled := true
var player_infantry_controller: Node
var battle_finished := false
var battle_result := ""
var incoming_audit:Array=[]
var shot_audit:Array=[]
var shot_sequence:=0
var simulation_anchor_timer:=0.0
var terrain_explosion_outbox:Array=[]
var requested_terrain_events:=0
var accepted_terrain_events:=0
var failed_terrain_events:=0
var deferred_terrain_events:=0
var suppressed_shot_visuals:=0
const AmmoProfiles = preload("res://scripts/ammo_profiles.gd")
const Combat = preload("res://scripts/combat.gd")
const Visibility = preload("res://scripts/visibility.gd")
var battle_controls: Control
var combat = Combat.new()
var player_combat = Combat.new(20261017)
var incoming_message:=""
var game_mode := "skirmish"
var ai_host:Node
var crew_host:Node
var vehicle_selector:Control
var bottom_bar:Panel
var last_tank_selection:=0
var selected_catalog_id:="user_heavy_mbt"
var catalog_vehicles:Array=[]
var catalog_proxies:Dictionary={}
var stage_generation:=0
var ai_started_generation:=-1
var camera: Camera3D
var stage: Node3D
var hero: Node3D
var target: Node3D
var decor: Node3D
var hud: CanvasLayer
var font: Font
var labels := {}
var buttons := {}
var garage := true
var unit := 0
var ammo := 0
var target_infantry := false
var target_tank := 1
var terrain_index := 0
var aim_limited := false
var aim_limit_reason := ""
var weather_index := 0
var terrain_damage: Node3D
var construction_host: Node
var weapon_override: Node3D
var reload_remaining := 0.0
var mg_remaining := 0.0
var desired_yaw := 0.0
var desired_pitch := 0.0
var aiming_pending := false
var weather_root: Node3D
var weather_overlay: ColorRect
var damage_overlay:ColorRect
var visibility_reason := "visible"
var terrain_root: Node3D
var high_pen := false
var mg_ammo := 0
var artillery_launch_speed:float=preload("res://modules/artillery/arc_solution.gd").MIN_SPEED
var mortar_adapter=preload("res://modules/artillery/mortar_adapter.gd").new()
var mlrs_adapter:Node
var indirect_sampler=preload("res://modules/artillery/terrain_sampler.gd").new()
var artillery_aim=preload("res://modules/artillery/artillery_aim.gd").new()
var tank_sight=preload("res://modules/vehicle_weapons/tank_sight.gd").new()
var tank_shell_fire=preload("res://modules/vehicle_weapons/tank_shell_fire.gd").new()
var artillery_fire=preload("res://modules/artillery/artillery_fire.gd").new()
var dual_machineguns = preload("res://scripts/dual_machinegun_mounts.gd").new()
var aim_kind := "armor"
var aim_contact_blocked := false
var scoped := false
var reticle: Node2D
var observer_transform: Transform3D
var last_impact := Vector3.ZERO
var last_muzzle := Vector3.ZERO
var smoke_root: Node3D
var tarp_root: Node3D
var thin_plate: Node3D
var crew_mode := false
var crew_index := 0
var part := "left_arm"
var module_name := "front"
var dragging := false
var drag_start := Vector2.ZERO
var last_pointer := Vector2.ZERO
var drag_distance := 0.0
var hero_angle := 0.0
var flash_time := 0.0
var effect_nodes: Array = []
var elapsed := 0.0
var hud_tick := 0.0
var message := "拖动查看模型 · 选择载具后进入战斗"
var models := ["res://assets/user_derived/models/user_heavy_mbt_aimable.glb", "res://assets/models/kestrel_scout.glb", "res://assets/user_derived/models/user_rifleman_armed.glb"]
const PART_CN = {"head":"头部", "torso":"躯干", "left_arm":"左臂", "right_arm":"右臂", "left_leg":"左腿", "right_leg":"右腿"}
const MODULE_CN = {"front":"车体正面","rear":"车体背面","left":"车体左侧","right":"车体右侧","top":"车体顶部","bottom":"车体底部","turret_front":"炮塔正面","turret_rear":"炮塔背面","turret_left":"炮塔左侧","turret_right":"炮塔右侧","turret_top":"炮塔顶部","turret_bottom":"炮塔底部","track_left":"左履带","track_right":"右履带"}

func _ready():
	Input.use_accumulated_input=false
	vehicle_contacts.setup(self)
	fire_control.setup(self)
	load_catalog()
	get_viewport().msaa_3d=Viewport.MSAA_2X
	font = load("res://cedar/system_font.tres")
	stage = Node3D.new(); add_child(stage)
	decor = Node3D.new(); add_child(decor)
	camera = Camera3D.new(); add_child(camera)
	camera.fov = 47
	camera.near = .08
	camera.far = 3200
	camera.current = true
	setup_environment()
	build_hangar()
	build_hud()
	load_display()
	if ResourceLoader.exists("res://modules/construction/construction_host.gd"):
		construction_host=Node.new();construction_host.set_script(load("res://modules/construction/construction_host.gd"));add_child(construction_host);construction_host.setup(self)
	if ResourceLoader.exists("res://modules/infantry_ai/skirmish_host.gd"):
		ai_host=Node.new();ai_host.set_script(load("res://modules/infantry_ai/skirmish_host.gd"));add_child(ai_host);ai_host.setup(self)
	if ResourceLoader.exists("res://modules/vehicle_crew/vehicle_crew_host.gd"):
		crew_host=Node.new();crew_host.set_script(load("res://modules/vehicle_crew/vehicle_crew_host.gd"));add_child(crew_host);crew_host.setup(self)
	if ResourceLoader.exists("res://modules/vehicle_selector/vehicle_selector.gd"):
		vehicle_selector=load("res://modules/vehicle_selector/vehicle_selector.gd").new();vehicle_selector.setup(self)
	if ResourceLoader.exists("res://modules/ai_armor/armor_host.gd"):
		armor_host=load("res://modules/ai_armor/armor_host.gd").new();add_child(armor_host);armor_host.setup(self)
	if ResourceLoader.exists("res://modules/vehicle_crew/player_infantry_controller.gd"):
		player_infantry_controller=load("res://modules/vehicle_crew/player_infantry_controller.gd").new();add_child(player_infantry_controller);player_infantry_controller.setup(self)
		player_infantry_controller.control_changed.connect(func(_on_foot):
			fire_control.cancel("车长上下车，指示已撤销")
			clear_vehicle_fire_input()
			scoped=false;hero.show()
			if is_instance_valid(battle_controls):
				battle_controls.reset_pointers()
				battle_controls.request_camera_snap())
	battle_controls=load("res://scripts/mobile_battle.gd").new();battle_controls.setup(self)
	var render_budget=load("res://scripts/mobile_render_budget.gd").new()
	add_child(render_budget);render_budget.setup(self)
	load("res://scripts/battle_simulation_rate.gd").new().setup(self)
	if "--engagement-observe" in OS.get_cmdline_user_args():
		var observer=load("res://scripts/engagement_observer.gd").new();observer.main=self;add_child(observer)
	if "--qa-capture" in OS.get_cmdline_user_args():
		var capture=load("res://scripts/qa_capture.gd").new();capture.main=self;add_child(capture)
	refresh_hud()

func material(color: Color, roughness: float = .7, metal: float = .0, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = roughness; m.metallic = metal
	if emission > 0:
		m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = emission
	return m

func box(parent: Node3D, pos: Vector3, dimensions: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new(); shape.size = dimensions
	mesh.mesh = shape; mesh.material_override = mat; mesh.position = pos
	if dimensions.y<.05:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new(); shape.top_radius=radius;shape.bottom_radius=radius;shape.height=height;shape.radial_segments=24
	mesh.mesh=shape;mesh.material_override=mat;mesh.position=pos
	parent.add_child(mesh)
	return mesh

func setup_environment():
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("91a7b1")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9baec0")
	env.environment.ambient_light_energy = .45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.fog_enabled=true
	env.environment.fog_light_color=Color("aab8bb")
	env.environment.fog_density=.0016
	env.environment.fog_light_energy=.5
	add_child(env)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_color=Color("fff5e6");sun.light_energy=.85;sun.shadow_enabled=true
	sun.directional_shadow_max_distance=45
	sun.shadow_bias=.08
	sun.shadow_normal_bias=1.4
	add_child(sun)
	for location in [Vector3(-6,5,-3),Vector3(5,5,4),Vector3(-4,5,7)]:
		var light := OmniLight3D.new();light.position=location;light.omni_range=15;light.light_energy=2.0;light.light_color=Color("b7d6e5")
		add_child(light)

func build_hangar():
	var floor_mat := material(Color("343d40"),.88,.15)
	var wall := material(Color("37464e"),.85)
	var steel := material(Color("1c2c34"),.5,.65)
	var concrete := material(Color("616a6b"),.95)
	var yellow := material(Color("bd9952"),.9)
	var light := material(Color("b8dbdf"),.2,0,3)
	box(decor,Vector3(0,-.18,1),Vector3(30,.35,28),floor_mat)
	# Real geometry hangar bay: concrete plinth, wall panels and exposed steel.
	box(decor,Vector3(0,3.8,10),Vector3(30,7.6,.4),wall)
	box(decor,Vector3(-14,3.8,0),Vector3(.4,7.6,20),wall)
	box(decor,Vector3(14,3.8,0),Vector3(.4,7.6,20),wall)
	box(decor,Vector3(0,.5,9.72),Vector3(30,1,.25),concrete)
	for x in [-12,-6,0,6,12]:
		box(decor,Vector3(x,3.8,9.6),Vector3(.3,7.6,.5),steel)
		box(decor,Vector3(x,7.5,0),Vector3(.3,.4,20),steel)
		if abs(x)==12:box(decor,Vector3(x,3.8,-9),Vector3(.3,7.6,.5),steel)
		box(decor,Vector3(x+2,6.6,9.6),Vector3(3,.12,.15),light)
		for y in [2,3,4,5,6]: box(decor,Vector3(x+3,y,9.74),Vector3(5.7,.025,.025),steel)
	for z in [-6,0,6]:
		box(decor,Vector3(0,7.4,z),Vector3(28,.25,.32),steel)
		for x in [-7,7]: box(decor,Vector3(x,7.1,z),Vector3(3,.08,.35),light)
	# Floor seams and painted parking enclosure.
	for i in range(-6,7):
		box(decor,Vector3(i*2,.002,0),Vector3(.025,.006,22),material(Color("263237")))
		box(decor,Vector3(0,.002,i*2),Vector3(28,.006,.025),material(Color("263237")))
	for x in [-3.3,3.3]: box(decor,Vector3(x,.012,0),Vector3(.1,.015,8.5),yellow)
	for z in [-4.2,4.2]: box(decor,Vector3(0,.012,z),Vector3(6.7,.015,.1),yellow)
	for x in range(-3,4):
		var stripe := box(decor,Vector3(x,.013,-5.1),Vector3(.25,.017,1),yellow)
		stripe.rotation.y = -.6
	# Side workbench and stores keep the vehicle as the focal point.
	box(decor,Vector3(-8,.9,4),Vector3(4,.18,1.4),steel)
	for x in [-9.5,-6.5]: box(decor,Vector3(x,.45,4),Vector3(.15,.9,1.2),steel)
	for i in range(5):
		box(decor,Vector3(6+i%3*1.1,.45+(i/3)*.9,6.5),Vector3(.95,.85,.95),material(Color("625d49")))
	for x in [-10,10]:
		for z in [-3,3]: cylinder(decor,Vector3(x,.55,z),.38,1.1,material(Color("4e5d58"),.55,.35))
	# Wall bay sign is actual in-scene lettering, not an overlay card.
	var sign := Label3D.new();sign.text="BAY  01";sign.font=font;sign.font_size=80;sign.pixel_size=.009;sign.position=Vector3(2.8,5.4,9.45);sign.modulate=Color("c5b682");sign.no_depth_test=false;sign.rotation.y=PI
	decor.add_child(sign)

func load_model(index: int, player_model:bool=false) -> Node3D:
	if player_model and selected_catalog_id=="mlrs_prototype":return preload("res://modules/mlrs/launcher_visual.gd").new()
	var path:String=str(catalog_entry().get("model_path",models[index])) if player_model and index<2 else models[index]
	if player_model and "armored_car_" in path:
		path="res://assets/running_gear/"+path.get_file()
	if ResourceLoader.exists(path):
		var instance = load(path).instantiate()
		if index<2 and ResourceLoader.exists("res://scripts/running_gear.gd"):
			load("res://scripts/running_gear.gd").install(instance,selected_catalog_id if player_model else "user_heavy_mbt" if index==0 else "kestrel_scout")
		if index<2 and not (player_model and selected_catalog_id=="artillery_open") and ResourceLoader.exists("res://scripts/machinegun_mount.gd"):
			load("res://scripts/machinegun_mount.gd").install(instance,selected_catalog_id if player_model else "user_heavy_mbt" if index==0 else "kestrel_scout")
		if player_model and selected_catalog_id=="artillery_open":
			var lod=preload("res://modules/artillery/vehicle_lod.gd").new();instance.add_child(lod);lod.setup(instance)
		CedarArt.dress_vehicle(instance, selected_catalog_id if player_model else "user_heavy_mbt" if index == 0 else "kestrel_scout")
		return instance
	var placeholder := Node3D.new()
	box(placeholder,Vector3(0,.6,0),Vector3(2.8,1.2,5),material(Color("626e64")))
	message="正在等待精细模型导入；占位物不作为验收画面"
	return placeholder

func clear_stage():
	if is_instance_valid(mlrs_adapter):mlrs_adapter.queue_free()
	mlrs_adapter=null
	tank_sight.reset()
	artillery_aim.reset()
	dual_machineguns.mounts.clear()
	clear_vehicle_fire_input()
	fire_control.cancel("新场景，手动操炮")
	if is_instance_valid(player_infantry_controller):player_infantry_controller.clear_input()
	if is_instance_valid(armor_host):armor_host.on_stage_reset()
	terrain_explosion_outbox.clear()
	stage_generation+=1
	incoming_message=""
	if is_instance_valid(damage_overlay):damage_overlay.color=Color(1,.35,.1,0)
	if is_instance_valid(crew_host):crew_host.on_stage_reset()
	if is_instance_valid(ai_host):ai_host.on_stage_reset()
	if is_instance_valid(construction_host):construction_host.on_stage_reset()
	weapon_override=null
	combat.smoke_remaining=0
	combat.tarp_burning=false
	terrain_damage=null;combat_effects=null;smoke_root=null
	for child in stage.get_children():
		stage.remove_child(child);child.queue_free()
	effect_nodes.clear()

func exterior_fov() -> float:
	return 55.0 if not garage and str(catalog_entry().get("fictional_stats",""))=="car" else 47.0

func load_display():
	battle_finished=false;battle_result="";reload_remaining=0;mg_remaining=0;aiming_pending=false
	stage.process_mode=Node.PROCESS_MODE_INHERIT
	if is_instance_valid(battle_controls):battle_controls.reset_pointers()
	if unit==2 and not garage:game_mode="engineering"
	scoped=false
	camera.fov=exterior_fov()
	clear_stage()
	if not garage and unit<2:
		vehicle_ammo.new_battle(stage_generation)

		ammo=0;mg_ammo=0
	decor.visible=garage
	for light in get_children():
		if light is OmniLight3D:light.visible=garage
		if light is WorldEnvironment:
			light.environment.background_color=Color("101923") if garage else Color("91a7b1")
			light.environment.fog_enabled=not garage
	CedarArt.grade_environment(self, not garage)
	if garage:weather_overlay.color=Color(0,0,0,0)
	if garage:
		hero=load_model(unit,true);stage.add_child(hero);hero.rotation.y=hero_angle
		camera.position=Vector3(7.6,3.8,-9.4) if unit<2 else Vector3(3.2,2.1,-4.2)
		camera.look_at(Vector3(0,1.1,0) if unit<2 else Vector3(0,.95,0))
	else:
		if game_mode=="skirmish":player_combat.configure_tank(str(catalog_entry().get("fictional_stats","heavy" if unit==0 else "light")))
		build_range()
		# Prewarm bounded cosmetics during scene load, never on the first MG round.
		combat_effects=CombatEffects.new();stage.add_child(combat_effects)
		build_weather()
		if target_infantry:update_person_visuals()
		call_deferred("settle_on_terrain",true,stage_generation)
	refresh_hud()

func build_range():
	var ground := material(Color("626953"),.95)
	load_terrain()
	target=load_model(2 if target_infantry else target_tank);stage.add_child(target)
	target.position=Vector3(-7 if terrain_index==2 else 0,0,4)
	if target_infantry:
		add_person_hitboxes(target)
	else:
		add_armor_hitboxes(target)
		add_internal_crew(target)
		if crew_mode:
			build_crew_hologram(target.position+Vector3(-4,0,-1))
			camera.position=target.position+Vector3(7,5.3,-14);camera.look_at(target.position+Vector3(-1,1,-1))
	tarp_root=Node3D.new();stage.add_child(tarp_root);tarp_root.position=target.position+Vector3(4,0,1)
	box(tarp_root,Vector3(0,.45,0),Vector3(1.2,.9,1),material(Color("5e6251")))
	box(tarp_root,Vector3(0,.94,0),Vector3(1.3,.12,1.1),material(Color("65794f")))
	hitbox(tarp_root,Vector3(0,.5,0),Vector3(1.3,1.1,1.1),"tarp","外置油布")
	thin_plate=Node3D.new();stage.add_child(thin_plate);thin_plate.position=target.position+Vector3(3,0,-1.5)
	box(thin_plate,Vector3(0,1.1,0),Vector3(1.2,1.1,.08),material(Color("7e99a0"),.4,.4))
	box(thin_plate,Vector3(0,.4,.07),Vector3(.1,.8,.1),material(Color("665a42")))
	hitbox(thin_plate,Vector3(0,1.1,0),Vector3(1.2,1.1,.08),"thin_plate","thin_plate")
	var label:=Label3D.new();label.text="薄板试片 10";label.font=font;label.font_size=36;label.pixel_size=.006;label.position=Vector3(0,1.95,0);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;thin_plate.add_child(label)
	# An off-axis foreground weapon silhouette anchors the firing position.
	hero=load_model(unit,true);stage.add_child(hero);hero.position=target.position+(Vector3(-6,0,-11) if unit<2 else Vector3(-2,0,-7));hero.rotation.y=PI
	if artillery_mode():ammo=1
	dual_machineguns.bind(hero)
	if unit<2:vehicle_ammo.register_vehicle(PLAYER_VEHICLE_ID,dual_machineguns.loadout(vehicle_loadout(),float(catalog_entry().get("hull_mg_ammo_fraction",0.5))))
	if not crew_mode or target_infantry:
		camera.position=target.position+(Vector3(-1,7,-20) if unit<2 else Vector3(-.5,3.3,-11))
		camera.look_at(range_focus())
	aim_weapon(target.position+Vector3(0,1.0,0),true)
	if game_mode=="skirmish":
		set_collision_layers(target,0)
		target.visible=false
		tarp_root.hide();thin_plate.hide();set_collision_layers(tarp_root,0);set_collision_layers(thin_plate,0)
		add_armor_hitboxes(hero,unit)
		add_internal_crew(hero,player_combat)
		tag_actor_colliders(hero,"player")

func hitbox(parent: Node3D, pos: Vector3, dimensions: Vector3, kind: String, key: String):
	if kind=="armor_group" and key=="hull" and preload("res://scripts/armor_collision.gd").install_hull(parent):return
	var body := StaticBody3D.new();body.position=pos
	body.set_meta("kind",kind);body.set_meta("key",key)
	var collider := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=dimensions;collider.shape=shape
	body.add_child(collider);parent.add_child(body)
func add_armor_hitboxes(parent: Node3D, model_index:int=-1):
	if model_index>=0 and catalog_proxies.has(selected_catalog_id):
		var proxies:Dictionary=catalog_proxies[selected_catalog_id]
		for key in ["hull","turret","tracks_left","tracks_right"]:
			var proxy:Dictionary=proxies[key]
			var mount:Node3D=parent.find_child("Turret",true,false) if key=="turret" else parent
			hitbox(mount,array_vector(proxy.center),array_vector(proxy.size),"armor" if key.begins_with("tracks") else "armor_group",("track_left" if key=="tracks_left" else "track_right") if key.begins_with("tracks") else key)
		return
	if (target_tank if model_index<0 else model_index)==0:
		hitbox(parent,Vector3(0,.745,0),Vector3(2.18,.91,5.31),"armor_group","hull")
		var turret:Node3D=parent.find_child("Turret",true,false)
		hitbox(turret,Vector3(0,.25,.07),Vector3(2.25,.51,3.28),"armor_group","turret")
		for x in [-1.42,1.42]:hitbox(parent,Vector3(x,.411,.005),Vector3(.56,.7975,5.223),"armor","track_left" if x<0 else "track_right")
	else:
		hitbox(parent,Vector3(0,.95,0),Vector3(2.7,1.05,4.6),"armor_group","hull")
		var turret:Node3D=parent.find_child("Turret",true,false)
		hitbox(turret,Vector3(0,.33,0),Vector3(2.25,.7,2.3),"armor_group","turret")
		for x in [-1.5,1.5]:hitbox(parent,Vector3(x,.55,.2),Vector3(.55,1.0,4.5),"armor","track_left" if x<0 else "track_right")
func body_key(name:String) -> String:
	if "Head" in name or "Helmet" in name:return "head"
	if "Arm_L" in name or "Hand_L" in name:return "left_arm"
	if "Arm_R" in name or "Hand_R" in name:return "right_arm"
	if "Thigh_L" in name or "Shin_L" in name or "Foot_L" in name:return "left_leg"
	if "Thigh_R" in name or "Shin_R" in name or "Foot_R" in name:return "right_leg"
	return "torso"
func add_person_hitboxes(parent: Node3D):
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/rifleman_hitboxes.json"))
	for key in data:
		if key=="Rifle":continue
		var c:Array=data[key].center;var size:Array=data[key].size
		hitbox(parent,Vector3(c[0],c[1],c[2]),Vector3(size[0],size[1],size[2]),"person",body_key(key))
func person_boxes() -> Dictionary:
	return {"head":[Vector3(0,1.65,0),Vector3(.3,.35,.35)],"torso":[Vector3(0,1.19,0),Vector3(.5,.58,.32)],"left_arm":[Vector3(-.37,1.15,0),Vector3(.2,.65,.25)],"right_arm":[Vector3(.37,1.15,0),Vector3(.2,.65,.25)],"left_leg":[Vector3(-.15,.47,0),Vector3(.22,.85,.3)],"right_leg":[Vector3(.15,.47,0),Vector3(.22,.85,.3)]}
func build_crew_hologram(pos: Vector3):
	var root := Node3D.new();root.set_meta("crew_hologram",true);stage.add_child(root);root.position=pos
	for key in person_boxes():
		var b: Array=person_boxes()[key]
		var color := Color("70c6b1") if combat.crew[crew_index].alive else Color("4b575b")
		if combat.crew[crew_index].parts[key]=="injured" and combat.crew[crew_index].alive: color=Color("e8b269")
		box(root,b[0],b[1]*.9,material(color,.3,.2,.4))
		if key==part: box(root,b[0]+Vector3(0,0,-.18),Vector3(b[1].x,.025,.025),material(Color("f1cf82"),.3,0,2))
	# Inspection silhouette has no collision: it does not choose bullet victims.
	var sign:=Label3D.new();sign.font=font;sign.text=combat.crew_roles[crew_index];sign.font_size=44;sign.pixel_size=.009;sign.position=Vector3(0,2.1,0);sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(sign)

func ui_style(color: Color, border: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=border;style.set_border_width_all(1);style.set_corner_radius_all(5)
	return style
func ui_label(key: String, text: String, pos: Vector2, size: int, color: Color):
	var label:=Label.new();label.text=text;label.position=pos;label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color);label.add_theme_color_override("font_shadow_color",Color(0,0,0,.8));label.add_theme_constant_override("shadow_offset_x",1);label.add_theme_constant_override("shadow_offset_y",2)
	hud.add_child(label);labels[key]=label
func ui_button(key: String, text: String, rect: Rect2, action: Callable):
	var button:=Button.new();button.text=text;button.position=rect.position;button.size=rect.size;button.add_theme_font_override("font",font);button.add_theme_font_size_override("font_size",17)
	button.pressed.connect(action);hud.add_child(button);buttons[key]=button
func build_hud():
	hud=CanvasLayer.new();add_child(hud)
	weather_overlay=ColorRect.new();weather_overlay.size=Vector2(1280,600);weather_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;weather_overlay.color=Color(0,0,0,0);hud.add_child(weather_overlay)
	damage_overlay=ColorRect.new();damage_overlay.size=Vector2(1280,720);damage_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;damage_overlay.color=Color(1,.35,.1,0);hud.add_child(damage_overlay)
	reticle=Node2D.new();reticle.set_script(load("res://scripts/reticle.gd"));reticle.visible=false;hud.add_child(reticle)
	bottom_bar=Panel.new();var bottom:=bottom_bar;bottom.position=Vector2(0,600);bottom.size=Vector2(1280,120);bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_stylebox_override("panel",ui_style(Color(.045,.065,.08,.92),Color(.3,.35,.37,.6)));hud.add_child(bottom)
	ui_label("title","WWO沙盒",Vector2(32,21),27,Color("f2eee2"))
	ui_label("subtitle","军事系统测试",Vector2(33,57),12,Color("a4b5b9"))
	ui_label("name","",Vector2(33,105),25,Color("e6d0a2"))
	ui_label("spec","",Vector2(34,143),15,Color("b7c4c7"))
	ui_label("hint","",Vector2(34,541),17,Color("e7d5ae"))
	ui_label("outcome","",Vector2(34,570),16,Color("f0e8d2"))
	ui_label("selection","我方单位",Vector2(27,610),12,Color("9caeb3"))
	ui_label("shells","武器弹种",Vector2(32,610),12,Color("9caeb3"))
	ui_label("status","",Vector2(1050,90),14,Color("e9dfca"))
	ui_button("mode","进入战斗 →",Rect2(1070,25,183,46),switch_mode)
	ui_button("heavy","堡垒 · 重型\n5 人乘组",Rect2(25,636,140,61),func(): select_unit(0))
	ui_button("light","红隼 · 轻型\n3 人乘组",Rect2(174,636,140,61),func(): select_unit(1))
	ui_button("infantry","野战步枪兵\n人员单位",Rect2(323,636,140,61),func(): select_unit(2))
	ui_button("ap","穿甲弹 AP",Rect2(32,636,137,61),func(): select_ammo(0))
	ui_button("he","高爆弹 HE",Rect2(178,636,137,61),func(): select_ammo(1))
	ui_button("smoke","烟幕弹 SMK",Rect2(324,636,137,61),func(): select_ammo(2))
	ui_button("mg_type","机枪 · 曳光弹 ⇄",Rect2(486,636,214,61),cycle_mg)
	ui_button("reset","重置",Rect2(1164,636,88,61),reset_range)
	ui_button("target","目标：红隼 ⇄",Rect2(32,192,206,43),cycle_target)
	ui_button("crew","乘员检视",Rect2(248,192,142,43),toggle_crew)
	ui_button("role","车长 ⇄",Rect2(400,192,154,43),cycle_crew)
	ui_button("inspect","翻看底部",Rect2(565,192,142,43),flip_target)
	ui_button("terrain","平原地块 ⇄",Rect2(718,192,172,43),cycle_terrain)
	ui_button("weather","晴天 ⇄",Rect2(900,192,139,43),cycle_weather)
	ui_button("scope","开镜",Rect2(1070,402,182,55),toggle_scope)
	ui_button("fire","主炮射击",Rect2(1070,474,182,61),fire_cannon)
	ui_button("mg","机枪射击",Rect2(1070,545,182,46),fire_mg)
	ui_button("practice_mode","交战 / 练习 ⇄",Rect2(730,636,189,61),func():choose_game_mode("practice" if garage or game_mode=="skirmish" else "skirmish"))
	ui_button("engineer_mode","工程指令演示",Rect2(930,636,221,61),func():choose_game_mode("engineering"))
	# No side report panel or six-part button grid. Aim is on the 3D subject.

func refresh_hud():
	if not garage and not buttons.is_empty():
		buttons.terrain.position=Vector2(718,192);buttons.terrain.size=Vector2(172,43)
		buttons.weather.position=Vector2(900,192);buttons.weather.size=Vector2(139,43)
		buttons.practice_mode.position=Vector2(730,636);buttons.practice_mode.size=Vector2(189,61)
		buttons.engineer_mode.position=Vector2(930,636);buttons.engineer_mode.size=Vector2(221,61)
	for label in labels.values():label.show()
	buttons.mg_type.position.x=486;buttons.he.position.x=178;buttons.he.text="高爆弹 HE";labels.shells.text="武器弹种"
	if hud==null:return
	for key in buttons:
		var b: Button=buttons[key]
		var active: bool=(key==["heavy","light","infantry"][unit] or (mounted_kind()!="mg" and key==["ap","he","smoke"][1 if mounted_kind()=="mortar" else ammo]))
		b.add_theme_stylebox_override("normal",ui_style(Color(.13,.17,.18,.88),Color("c8a66e") if active else Color("45545b")))
		b.add_theme_stylebox_override("hover",ui_style(Color("3b4848"),Color("c8a66e")))
		b.add_theme_stylebox_override("pressed",ui_style(Color("5a6152"),Color("e5bf77")))
		b.add_theme_color_override("font_color",Color("e7cb95") if active else Color("ced8d8"))
	labels.name.text=(str(catalog_entry().get("display_name","战车")) if unit<2 else "野战步枪兵") if garage else ("步兵靶位" if target_infantry else ["目标 · 堡垒 5人","目标 · 红隼 3人"][target_tank])
	labels.spec.text=("重型战车 · 固定穿深 110" if unit==0 else "轻型战车 · 固定穿深 90") if unit<2 else "步兵试验单位 · 无数字生命条"
	if not garage: labels.spec.text="点选转炮 · 拖靶检视 · 开镜微调后射击"
	labels.hint.text="拖动旋转查看  /  滚轮缩放" if garage else ("烟幕遮挡：无法识别和锁定目标  %.1fs" % combat.smoke_remaining if not combat.can_identify_target() else ("外置油布 · 可燃目标" if aim_kind=="tarp" else ("乘员："+combat.crew_roles[crew_index]+" / "+PART_CN[part] if crew_mode and not target_infantry else ("瞄准："+PART_CN[part] if target_infantry else "入口："+MODULE_CN[module_name]))))
	if not garage and aim_kind=="thin_plate":labels.hint.text="瞄准：薄板试片 10 · 机枪穿甲弹可穿透"
	labels.outcome.text=message
	labels.status.text="" if garage else crew_status()
	buttons.mode.text=("进入交战 →" if game_mode=="skirmish" else "进入练习 →") if garage else "← 返回车库"
	buttons.target.text="目标："+("步兵" if target_infantry else ["堡垒","红隼"][target_tank])+" ⇄"
	buttons.crew.text="收起乘员" if crew_mode else "乘员检视"
	buttons.role.text=combat.crew_roles[crew_index]+" ⇄"
	buttons.mg_type.text=("步枪" if unit==2 else "机枪")+" · "+["曳光弹","穿甲弹","燃烧弹"][mg_ammo]+" ⇄"
	buttons.mg.text="步枪射击" if unit==2 else "机枪射击"
	for key in ["target","fire","mg","reset","crew","role","inspect","scope","terrain","weather"]:buttons[key].visible=not garage
	buttons.crew.visible=not garage and not target_infantry
	buttons.role.visible=not garage and not target_infantry and crew_mode
	buttons.inspect.visible=not garage and not target_infantry
	buttons.weather.text=["晴天","雨天","雾天"][weather_index]+" ⇄"
	buttons.terrain.text=["平原地块","丘陵梯田","风蚀岩地"][terrain_index]+" ⇄"
	buttons.fire.disabled=(unit==2 and not is_instance_valid(weapon_override)) or mounted_kind()=="mg"
	buttons.mg.disabled=mounted_kind() in ["at","mortar"]
	for key in ["ap","he","smoke"]:buttons[key].disabled=mounted_kind() in ["mg","mortar"] or (artillery_mode() and key!="he")
	buttons.fire.text="装填 %.1fs" % reload_remaining if reload_remaining>0 else ("迫击炮射击" if mounted_kind()=="mortar" else "主炮射击")
	buttons.scope.text="退出瞄准镜" if scoped else "开镜"
	reticle.visible=scoped and not garage
	for key in ["heavy","light","infantry"]:buttons[key].hide()
	labels.selection.hide()
	bottom_bar.visible=not garage
	labels.shells.visible=not garage
	for key in ["ap","he","smoke","mg_type","practice_mode","engineer_mode"]:buttons[key].visible=not garage
	buttons.practice_mode.text="转为练习" if game_mode=="skirmish" else "进入交战"
	if is_instance_valid(vehicle_selector):vehicle_selector.visible=game_mode!="engineering" or garage;vehicle_selector.refresh()
	if game_mode=="skirmish" and not garage:
		for key in ["target","crew","role","inspect"]:buttons[key].hide()
		labels.name.text="有限交战 · "+str(catalog_entry().get("display_name","战车"))
		labels.spec.text="友军蓝标 / 敌军红标 · 瞄准真实炮口 · 可回车库选车"
		labels.hint.text="外镜拖动车体原地转向 · 炮架左右8度 · 驾驶员须在岗" if str(catalog_entry().get("aim_mode","turret"))=="limited_mount" else "点选可见对手转炮 · 开镜微调 · 烟雾中可盲射"
		labels.status.text=player_status_text()
	elif game_mode=="engineering" and not garage:
		labels.name.text="工程指令演示"
		labels.spec.text="给工程班下达施工/入位指令 · 步兵交战由AI接管"
	if not garage and game_mode!="skirmish" and visibility_reason!="visible":
		labels.name.text="目标不可见"
		labels.spec.text={"range":"超出当前天气可视距离","smoke":"烟幕遮挡视线","obstacle":"地形或工事遮挡视线","observer_unavailable":"观察人员不可用"}[visibility_reason]
		labels.status.text=""
		labels.hint.text=("烟幕遮挡 %.1fs · 无法识别部位" % combat.smoke_remaining) if visibility_reason=="smoke" else "无法识别部位或锁定目标"
		labels.outcome.text="已沿炮口方向发射 · 目标不可见，结果未确认" if reload_remaining>0 or mg_remaining>0 else "目标无法识别；仍可沿现有炮口方向盲射。"

	if unit<2:
		var weapon:String=primary_weapon()
		buttons.mg_type.position.x=32 if weapon=="mg" else 486
		buttons.he.position.x=32 if weapon=="short_rocket" else 178
		buttons.he.text="短火箭 · 高爆" if weapon=="short_rocket" else "高爆弹 HE"
		if not garage and not is_instance_valid(weapon_override):
			if weapon=="mg":
				for key in ["ap","he","smoke","mg"]:buttons[key].hide()
				buttons.fire.text="主机枪射击";labels.shells.text="机枪弹种"
			elif weapon=="short_rocket":
				for key in ["ap","smoke","mg","mg_type"]:buttons[key].hide()
				buttons.he.disabled=true;buttons.fire.text="装填 %.1fs" % reload_remaining if reload_remaining>0 else "三发短火箭"
				labels.shells.text="固定三发高爆 / 7秒装填"
			else:labels.shells.text="武器弹种"
		if garage and str(catalog_entry().get("fictional_stats",""))=="car":labels.spec.text="装甲车 · 固定3人乘组 · "+{"mg":"机枪","short_rocket":"三发短火箭","cannon":"加农炮 AP90"}.get(weapon,weapon)

	if not garage and game_mode=="skirmish":
		for b in buttons.values():b.hide()
		for l in labels.values():l.hide()
		bottom_bar.hide()
		if is_instance_valid(vehicle_selector):vehicle_selector.hide()
	elif garage:
		for i in range(4):
			var key=["terrain","weather","practice_mode","engineer_mode"][i]
			buttons[key].show();buttons[key].position=Vector2(1070,90+i*52);buttons[key].size=Vector2(183,43)
		buttons.practice_mode.text="固定靶场"
		buttons.engineer_mode.text="工程训练"

	if garage:
		buttons.mode.show();buttons.practice_mode.hide();buttons.engineer_mode.hide()

func crew_status() -> String:
	if target_infantry:
		return "人员状态\n"+("正常" if combat.infantry.hp==10 else "受伤") if combat.infantry.alive else "人员状态\n失去行动能力"
	var result: String=MODULE_CN[module_name]+"\n厚度 "+str(combat.modules[module_name].thickness)+"  /  完整度 "+str(combat.modules[module_name].integrity)+"%\n\n"
	for i in range(combat.crew.size()):
		result+=combat.crew_roles[i]+"  "+("正常" if combat.crew[i].hp==10 else "受伤")+"\n" if combat.crew[i].alive else combat.crew_roles[i]+"  失能\n"
	return result
func select_unit(index: int):
	if index<2 and (str(catalog_entry().get("fictional_stats","heavy"))=="heavy")!=(index==0):selected_catalog_id="user_heavy_mbt" if index==0 else "kestrel_scout"
	unit=index
	if index<2:last_tank_selection=index
	else:game_mode="engineering"
	hero_angle=0
	message="已更换车辆，本场重新开始。"
	load_display()
func select_ammo(index: int):
	if artillery_mode() and index!=1:return
	ammo=index
	if not garage and not is_instance_valid(weapon_override):
		vehicle_ammo.select_next(PLAYER_VEHICLE_ID,"primary",["ap","he","smoke"][index],primary_reload()*player_reload_multiplier())
	refresh_hud()
func cycle_mg():
	mg_ammo=(mg_ammo+1)%3
	if not garage and not is_instance_valid(weapon_override):vehicle_ammo.select_next(PLAYER_VEHICLE_ID,"mg",["tracer","ap","incendiary"][mg_ammo])
	if not garage and dual_machineguns.mounts.size()==2:vehicle_ammo.select_next(PLAYER_VEHICLE_ID,"mg_hull",["tracer","ap","incendiary"][mg_ammo])
	refresh_hud()
func switch_mode():
	if is_instance_valid(battle_controls):battle_controls.set_menu(false);battle_controls.reset_pointers()
	get_tree().paused=false
	garage=not garage;game_mode="skirmish"
	if unit==2:unit=0
	load_display()

func choose_game_mode(mode:String):
	game_mode=mode;garage=false;crew_mode=false
	unit=2 if mode=="engineering" else last_tank_selection
	message="工程指令演示：下达施工命令。" if mode=="engineering" else ("固定靶场练习" if mode=="practice" else "有限交战：自主步兵已进入战场。")
	load_display()

func cycle_target():
	if target_infantry:target_infantry=false;target_tank=0
	elif target_tank==0:target_tank=1
	else:target_infantry=true
	combat.configure_tank("heavy" if target_tank==0 else "light");crew_index=0;module_name="front";aim_kind="infantry" if target_infantry else "armor"
	message="目标已更换并重置；我方载具保持不变。";load_display()
func toggle_crew():
	crew_mode=not crew_mode;refresh_hologram();refresh_hud()
func cycle_crew():
	crew_index=(crew_index+1)%combat.crew.size();refresh_hologram();refresh_hud()
func reset_range():
	combat.reset();reload_remaining=0;mg_remaining=0;message="靶场已重置。";load_display()
func flip_target():
	if target!=null:target.rotation.x=0 if absf(target.rotation.x)>0.1 else PI*.75
	message="检视旋转仅改变朝向；点选局部装甲面后按该面结算。";refresh_hud()

func weapon_muzzle(machinegun:bool=false) -> Node3D:
	if is_instance_valid(player_infantry_controller) and player_infantry_controller.active():return player_infantry_controller.actor().muzzle
	if is_instance_valid(weapon_override):return weapon_override
	if not is_instance_valid(hero):return null
	if machinegun and not dual_machineguns.mounts.is_empty():return dual_machineguns.mounts[0].node if is_instance_valid(dual_machineguns.mounts[0].node) else null
	return hero.find_child("MG_Muzzle" if machinegun else "Muzzle",true,false) as Node3D
func aim_weapon(point:Vector3, immediate:bool=false, delta:float=1.0/60):
	point=tank_sight.aim_point(self,point)
	if indirect_fire_mode() and artillery_aim.selected and not artillery_aim.manual:
		if not artillery_aim.target.is_finite():return
		point=artillery_aim.target
	aim_limited=false
	aim_limit_reason=""
	if is_instance_valid(weapon_override):
		if mounted_kind()=="mortar":
			if artillery_aim.manual:mortar_adapter.aim_manual(self,point,delta)
			else:mortar_adapter.aim(self,point,artillery_aim.pitch,delta)
			return
		var view:Node=weapon_override.get_parent()
		while view!=null and not view.has_method("aim_at"):view=view.get_parent()
		if view!=null:view.aim_at(point)
		return
	if not is_instance_valid(hero):return
	var turret:Node3D=hero.find_child("Turret",true,false)
	var barrel:Node3D=hero.find_child("Barrel",true,false)
	if turret!=null and barrel!=null:
		var local:Vector3=hero.to_local(point)-turret.position
		var raw_yaw:float=atan2(-local.x,-local.z)
		if artillery_mode() and not artillery_aim.manual:
			var arc_muzzle:Node3D=weapon_muzzle()
			var arc_direction:Vector3=preload("res://modules/artillery/arc_solution.gd").solve(arc_muzzle.global_position,point,artillery_aim.pitch).direction
			var mount_direction:Vector3=turret.get_parent().global_basis.inverse()*arc_direction
			raw_yaw=atan2(-mount_direction.x,-mount_direction.z)
		desired_yaw=clampf(raw_yaw,-catalog_yaw_limit(),catalog_yaw_limit())
		aim_limited=absf(raw_yaw-desired_yaw)>.001
		if aim_limited:aim_limit_reason="炮架水平限位，请转动车体"
		var prior:float=turret.rotation.y
		turret.rotation.y=desired_yaw
		var barrel_local:Vector3=turret.to_local(point)-barrel.position
		var raw_pitch:float=atan2(barrel_local.y,Vector2(barrel_local.x,barrel_local.z).length())
		if artillery_mode() and not artillery_aim.manual:
			var muzzle:Node3D=hero.find_child("Muzzle",true,false)
			var solution:Dictionary=preload("res://modules/artillery/arc_solution.gd").solve(muzzle.global_position,point,artillery_aim.pitch)
			artillery_launch_speed=float(solution.speed)
			var local_direction:Vector3=turret.global_basis.inverse()*solution.direction
			raw_pitch=atan2(local_direction.y,Vector2(local_direction.x,local_direction.z).length())
			if not bool(solution.valid):aim_limited=true;aim_limit_reason="曲射目标超出试验配置范围，仍可沿炮口方向射击"
		desired_pitch=clampf(raw_pitch,catalog_pitch_limits().x,catalog_pitch_limits().y)
		if absf(raw_pitch-desired_pitch)>.001:
			aim_limited=true
			aim_limit_reason="已到最低俯角，请抬高瞄准" if raw_pitch<catalog_pitch_limits().x else "已到最高仰角，请降低瞄准"
		if immediate:barrel.rotation.x=desired_pitch
		else:turret.rotation.y=prior
		aiming_pending=not immediate
	else:
		var rifle:Node3D=hero.find_child("Rifle",true,false)
		if rifle!=null:
			for iteration in range(3):
				var muzzle:Node3D=weapon_muzzle()
				if muzzle!=null:rifle.look_at(rifle.global_position+(point-muzzle.global_position),Vector3.UP)
func toggle_scope():
	scoped=not scoped
	if scoped and indirect_fire_mode():artillery_aim.enter_manual(self)
	if scoped:observer_transform=camera.global_transform
	else:
		if is_instance_valid(battle_controls) and battle_controls.active():
			battle_controls.request_camera_snap()
		else:camera.global_transform=observer_transform
		camera.fov=exterior_fov()
	hero.visible=not scoped and not (is_instance_valid(construction_host) and construction_host.model.occupied!="")
	refresh_hud()
func muzzle_trace(machinegun:bool=false, explicit_muzzle:Node3D=null) -> Dictionary:
	var muzzle:Node3D=explicit_muzzle if is_instance_valid(explicit_muzzle) else weapon_muzzle(machinegun)
	if muzzle==null:return {}
	last_muzzle=muzzle.global_position
	var direction:Vector3=-muzzle.global_basis.z.normalized()
	var shot_range:float=160.0 if machinegun else (220.0 if primary_weapon()=="short_rocket" else 260.0)
	var query:=PhysicsRayQueryParameters3D.create(last_muzzle,last_muzzle+direction*shot_range,1|8|128)
	query.hit_from_inside=true
	var exclusions:Array[RID]=[]
	for body in hero.find_children("*","CollisionObject3D",true,false):exclusions.append(body.get_rid())
	query.exclude=exclusions
	var result:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	last_impact=result.position if not result.is_empty() else last_muzzle+direction*shot_range
	if not result.is_empty():result["direction"]=direction
	return result
func interpret_hit(hit:Dictionary) -> String:
	if hit.is_empty():return "miss"
	var collider:Node=hit.collider
	if not collider.has_meta("kind"):return "obstacle"
	var kind:String=collider.get_meta("kind")
	if is_instance_valid(armor_host) and armor_host.units.has(armor_host.actor_id(collider)):return "ai_armor"
	if game_mode=="skirmish" and str(collider.get_meta("actor_id",""))=="player":return "obstacle"
	if kind=="ai_person":part=str(collider.get_meta("key","torso"));return "ai_person"
	if kind=="armor_group":
		module_name=Combat.face_from_hit(collider,hit.normal);return "armor"
	if kind=="armor":module_name=collider.get_meta("key");return "armor"
	if kind=="person":part=collider.get_meta("key");return "infantry"
	return kind
func trace_internal_crew(hit:Dictionary) -> Dictionary:
	var muzzle:Node3D=weapon_muzzle()
	var direction:Vector3=hit.get("direction",-muzzle.global_basis.z.normalized())
	var query:=PhysicsRayQueryParameters3D.create(hit.position+direction*.02,hit.position+direction*8,2)
	return get_world_3d().direct_space_state.intersect_ray(query)
func mounted_kind() -> String:
	if not is_instance_valid(weapon_override) or not is_instance_valid(construction_host):return ""
	var id:String=construction_host.model.occupied
	return str(construction_host.model.structures[id].preset) if construction_host.model.structures.has(id) else ""
func fire_cannon():
	if is_instance_valid(player_infantry_controller) and player_infantry_controller.active():return
	if selected_catalog_id=="mlrs_prototype" and unit<2 and not garage and not battle_finished and not is_instance_valid(weapon_override):
		if not is_instance_valid(mlrs_adapter):
			mlrs_adapter=preload("res://modules/mlrs/host_adapter.gd").new();stage.add_child(mlrs_adapter)
			mlrs_adapter.attach(self,hero,hero.rails)
		mlrs_adapter.begin(artillery_launch_speed);return
	if not is_instance_valid(weapon_override) and primary_weapon()=="mg":fire_mg();return
	if not is_instance_valid(weapon_override) and primary_weapon()=="short_rocket":fire_rocket_salvo();return
	if artillery_mode() and not is_instance_valid(weapon_override):artillery_fire.fire(self);return
	if not player_can_fire():message="炮手不在岗位或已失能，无法开火";refresh_hud();return
	if garage or (unit==2 and not is_instance_valid(weapon_override)):return
	if mounted_kind()=="mg":message="机枪阵地仅可使用机枪弹";refresh_hud();return
	if mounted_kind()=="mortar":fire_mortar(weapon_override);return
	if not is_instance_valid(weapon_override):tank_shell_fire.fire(self);return
	if reload_remaining>0:
		message="装填中 %.1fs" % reload_remaining
		if is_instance_valid(battle_controls):battle_controls.show_notice(message)
		refresh_hud();return
	var muzzle:Node3D=weapon_muzzle()
	if not is_instance_valid(muzzle) or not muzzle.is_inside_tree():vehicle_fire_denied("muzzle_unavailable");return
	var fired_ammo:=ammo
	var commit_id:=-1
	if not is_instance_valid(weapon_override):
		var commit:Dictionary=vehicle_ammo.commit_fire(PLAYER_VEHICLE_ID,"primary",vehicle_ammo.request_id(),primary_reload()*player_reload_multiplier(),player_can_fire(),true)
		if not bool(commit.ok):vehicle_fire_denied(str(commit.reason));return
		fired_ammo=["ap","he","smoke"].find(str(commit.round))
		commit_id=int(commit.commit)
	shot_sequence+=1
	reload_remaining=(5.0 if is_instance_valid(weapon_override) else primary_reload())*player_reload_multiplier()+minf(0.0,reload_remaining)
	if not is_instance_valid(weapon_override):reload_remaining=float(vehicle_ammo.status(PLAYER_VEHICLE_ID,"primary").remaining)
	var hit:Dictionary=muzzle_trace()
	var kind:String=interpret_hit(hit)
	if not hit.is_empty():hit["ammo_commit"]=commit_id;hit["feedback_id"]=shot_sequence
	shot_audit.append({"id":shot_sequence,"accepted":true,"ammo":fired_ammo,"ammo_commit":commit_id,"vehicle_id":PLAYER_VEHICLE_ID,"origin":last_muzzle,"impact":last_impact,"hit_kind":kind,"distance":last_muzzle.distance_to(last_impact)})
	if shot_audit.size()>128:shot_audit.pop_front()
	if fired_ammo==2:
		spawn_shot(false,true,false,fired_ammo);combat.deploy_smoke();spawn_smoke();smoke_root.global_position=last_impact;message="烟幕部署于炮口弹着点 · 36秒遮挡瞄准识别";refresh_hud();return
	var hit_feedback:Dictionary=preload("res://scripts/hit_feedback.gd").contact(hit,kind,shot_sequence,last_impact-last_muzzle)
	spawn_shot(false,true,not hit.is_empty(),fired_ammo,str(hit_feedback.surface),hit_feedback)
	if fired_ammo==0 and not hit.is_empty():explode_terrain(last_impact,AmmoProfiles.explosive_mass("cannon_ap"))
	if fired_ammo==1:
		if kind=="ai_armor":armor_host.handle_player_projectile(hit,"cannon","he",15)
		if kind in ["ai_person","ai_fortification"] and is_instance_valid(ai_host):ai_host.handle_player_projectile(hit,"cannon","he",part)
		elif kind=="infantry":combat.hit_person(combat.infantry,part)
		elif kind=="armor":record_hit_feedback(shot_sequence,combat.hit_armor(module_name,15,-1,"",null,{"normal":hit.normal,"direction":last_impact-last_muzzle}),true)
		if game_mode=="skirmish" and is_instance_valid(ai_host):ai_host.apply_player_blast(last_impact)
		var distance:float=last_impact.distance_to(target.global_position+Vector3(0,1,0))
		var result:Dictionary=combat.high_explosive("infantry" if target_infantry else "armor",distance,blast_occluded(last_impact))
		explode_terrain(last_impact,AmmoProfiles.explosive_mass("cannon_he"))
		message="高爆弹已在实际弹着点爆炸" if game_mode=="skirmish" else ("高爆弹爆炸 · 开放人员范围伤害已结算" if result.kind=="blast" and result.damage>0 else "高爆弹爆炸 · 未伤及人员（范围外或封闭装甲）")
	elif kind=="ai_armor":
		message=armor_host.handle_player_projectile(hit,"cannon","ap",primary_penetration())
	elif kind in ["ai_person","ai_fortification"] and is_instance_valid(ai_host):
		message=ai_host.handle_player_projectile(hit,"cannon",["ap","he","smoke"][fired_ammo],part)
	elif kind=="infantry":
		combat.hit_person(combat.infantry,part);message="炮口射线直击"+PART_CN[part]+" · "+("受伤" if combat.infantry.alive else "失去行动能力")
	elif kind=="armor":
		var direct:Dictionary=trace_internal_crew(hit)
		var index:int=-1
		var direct_part:String=""
		if not direct.is_empty():index=direct.collider.get_meta("crew_index");direct_part=direct.collider.get_meta("key")
		var result:Dictionary=combat.hit_armor(module_name,110 if is_instance_valid(weapon_override) else primary_penetration(),index,direct_part,null,{"normal":hit.normal,"direction":last_impact-last_muzzle})
		record_hit_feedback(shot_sequence,result,true)
		message=("穿透" if result.kind in ["penetrated","external_penetrated"] else "未穿透")+" · "+MODULE_CN[module_name]+" · 厚度 "+str(combat.modules[module_name].thickness)
		if result.kind=="external_penetrated":message+=" · 外置履带，未进入乘员舱"
		if result.kind=="penetrated" and index>=0:message+=" · 弹道直击"+combat.crew_roles[index]+PART_CN[direct_part]
	elif kind=="thin_plate":message="主炮穿透薄板试片 · 未命中乘员舱"
	else:message="炮口弹道"+("未命中目标" if kind=="miss" else "被前方障碍截住")
	update_person_visuals();refresh_hud()
func player_can_fire_any_mg() -> bool:
	if dual_machineguns.mounts.size()!=2 or is_instance_valid(weapon_override):return player_can_fire()
	if garage or battle_finished:return false
	for mount in dual_machineguns.mounts:
		if not is_instance_valid(mount.node) or not mount.node.is_inside_tree() or bool(mount.node.get_meta("disabled",false)):continue
		if game_mode!="skirmish" or dual_machineguns.role_available(player_combat,player_onboard_indices(),str(mount.role)):return true
	return false

func machinegun_cooldown() -> float:
	var remaining:float=float(vehicle_ammo.status(PLAYER_VEHICLE_ID,"mg").get("cooldown",0.0))
	if dual_machineguns.mounts.size()==2:
		remaining=minf(remaining,float(vehicle_ammo.status(PLAYER_VEHICLE_ID,"mg_hull").get("cooldown",0.0)))
	return remaining

func fire_mg():
	if dual_machineguns.mounts.size()!=2 or is_instance_valid(weapon_override):
		fire_mg_single()
		return
	# One input, two independently gated real weapon transactions; never duplicate a hit.
	if garage or battle_finished or mounted_kind() in ["at","mortar"] or primary_weapon()=="short_rocket":return
	if is_instance_valid(player_infantry_controller) and player_infantry_controller.active():return
	for mount in dual_machineguns.mounts:
		var available:bool=game_mode!="skirmish" or dual_machineguns.role_available(player_combat,player_onboard_indices(),str(mount.role))
		if not available or not is_instance_valid(mount.node) or not mount.node.is_inside_tree():continue
		if bool(mount.node.get_meta("disabled",false)):continue
		var committed:Dictionary=vehicle_ammo.commit_fire(PLAYER_VEHICLE_ID,str(mount.id),vehicle_ammo.request_id(),.2,available,true)
		if not bool(committed.ok):continue
		fire_mg_single(mount.node,str(mount.id),int(committed.commit))

func fire_mg_single(explicit_muzzle:Node3D=null,mount_id:String="mg",precommitted:int=-1):
	if is_instance_valid(player_infantry_controller) and player_infantry_controller.active():return
	if precommitted<0 and weapon_muzzle(true)==null:message="当前载具没有可用机枪炮口";refresh_hud();return
	if precommitted<0 and not player_can_fire():message="炮手不在岗位或已失能，无法开火";refresh_hud();return
	if garage or mounted_kind() in ["at","mortar"] or (primary_weapon()=="short_rocket" and not is_instance_valid(weapon_override)):return
	if precommitted<0 and mg_remaining>0:return
	var commit_id:=precommitted
	if precommitted<0 and not is_instance_valid(weapon_override):
		var commit:Dictionary=vehicle_ammo.commit_fire(PLAYER_VEHICLE_ID,"mg",vehicle_ammo.request_id(),.2,player_can_fire(),is_instance_valid(weapon_muzzle(true)) and weapon_muzzle(true).is_inside_tree())
		if not bool(commit.ok):vehicle_fire_denied(str(commit.reason));return
		commit_id=int(commit.commit)
	mg_remaining=.2+minf(0.0,mg_remaining)
	var hit:Dictionary=muzzle_trace(true,explicit_muzzle)
	var kind:String=interpret_hit(hit)
	if not hit.is_empty():hit["ammo_commit"]=commit_id
	shot_sequence+=1
	shot_audit.append({"id":shot_sequence,"accepted":true,"weapon":"mg","mount":mount_id,"ammo":mg_ammo,"ammo_commit":commit_id,"vehicle_id":PLAYER_VEHICLE_ID,"origin":last_muzzle,"impact":last_impact,"hit_kind":kind})
	if shot_audit.size()>128:shot_audit.pop_front()
	if not hit.is_empty():hit["feedback_id"]=shot_sequence
	var hit_feedback:Dictionary=preload("res://scripts/hit_feedback.gd").contact(hit,kind,shot_sequence,last_impact-last_muzzle)
	hit_feedback["visual_weapon"]=preload("res://scripts/weapon_vfx_profile.gd").describe(catalog_entry(),"mg",mount_id)
	spawn_shot(true,true,not hit.is_empty(),-1,str(hit_feedback.surface),hit_feedback)
	if kind=="ai_armor":
		message=armor_host.handle_player_projectile(hit,"mg","ap",9);refresh_hud();return
	if kind=="ai_person" and is_instance_valid(ai_host):
		message=ai_host.handle_player_projectile(hit,"mg",["tracer","ap","incendiary"][mg_ammo],part);refresh_hud();return
	if kind in ["miss","obstacle"]:message="枪口弹道未命中有效目标或被障碍截住。";refresh_hud();return
	var result:Dictionary=combat.machine_gun(["tracer","ap","incendiary"][mg_ammo],kind,part)
	record_hit_feedback(shot_sequence,result,true)
	match result.kind:
		"ignited":message="燃烧弹点燃外置油布 · 不向装甲内传递伤害";spawn_fire()
		"plate_penetrated":message="机枪穿甲弹穿过薄板 10 · 穿深 15";mark_plate()
		"plate_stopped":message="机枪弹未穿过薄板 10 · 穿深 5"
		"armor_stopped":message="机枪弹被装甲阻挡 · 穿深 "+str(result.penetration)+" · 舱内乘员无伤"
		"lethal":message="枪口弹道命中"+PART_CN[part]+" · 失去行动能力"
		"limb":message="枪口弹道命中"+PART_CN[part]+" · 部位受伤"
		_:message="目标受击 · "+str(result.kind)
	update_person_visuals();refresh_hud()

func update_person_visuals():
	# Color the actual body groups, not a numerical health bar.
	if target_infantry:
		update_body_materials(target)
	elif crew_mode:
		# Rebuild only the inspection silhouettes after a hit.
		for node in stage.get_children():
			if node.has_meta("crew_hologram"):node.queue_free()
		build_crew_hologram(target.position+Vector3(-4,0,-1))
func tint_meshes(node:Node, mat:Material):
	if node is MeshInstance3D:node.material_override=mat
	for child in node.get_children():tint_meshes(child,mat)

func _unhandled_input(event:InputEvent):
	if not garage and game_mode=="skirmish":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode==KEY_SPACE:fire_cannon()
			if event.keycode==KEY_M:fire_mg()
		return
	if not garage and game_mode=="skirmish":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode==KEY_SPACE:fire_cannon()
			if event.keycode==KEY_M:fire_mg()
		return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging=true;drag_start=event.position;last_pointer=event.position;drag_distance=0
			else:
				if dragging and drag_distance<8 and not garage:pick_target(event.position)
				dragging=false
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.fov=clampf(camera.fov+(-2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 2),30,65)
	if event is InputEventMouseMotion and dragging:
		drag_distance+=event.relative.length()
		if garage and is_instance_valid(hero):hero.rotation.y+=event.relative.x*.008;hero_angle=hero.rotation.y
		elif scoped:
			if indirect_fire_mode() and not artillery_aim.manual:artillery_aim.enter_manual(self)
			if is_instance_valid(weapon_override):
				var direction:Vector3=-weapon_override.global_basis.z
				direction=direction.rotated(Vector3.UP,-event.relative.x*.002)
				direction=direction.rotated(weapon_override.global_basis.x,-event.relative.y*.002)
				aim_weapon(weapon_override.global_position+direction*50)
				return
			var turret:Node3D=hero.find_child("Turret",true,false)
			var barrel:Node3D=hero.find_child("Barrel",true,false)
			if turret!=null and barrel!=null:turret.rotation.y=clampf(turret.rotation.y-event.relative.x*.002,-catalog_yaw_limit(),catalog_yaw_limit());barrel.rotation.x=clampf(barrel.rotation.x-event.relative.y*.002,catalog_pitch_limits().x,catalog_pitch_limits().y)
			else:
				var rifle:Node3D=hero.find_child("Rifle",true,false)
				if rifle!=null:rifle.rotation.y-=event.relative.x*.002;rifle.rotation.x=clampf(rifle.rotation.x-event.relative.y*.002,-.6,.8)
			aiming_pending=false
		elif game_mode=="skirmish" and str(catalog_entry().get("aim_mode","turret"))=="limited_mount":rotate_limited_hull(event.relative.x*.008)
		elif is_instance_valid(target):target.rotation.y+=event.relative.x*.008
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_SPACE:fire_cannon()
		if event.keycode==KEY_M:fire_mg()
## Camera rays may select scenery, but may not furnish hidden entity coordinates.
## This affects input assistance only. Blind muzzle collision/damage is unchanged.
func player_hit_observable(hit:Dictionary) -> bool:
	if hit.is_empty():return true
	var node:Node=hit.get("collider") as Node
	var id:=""
	while is_instance_valid(node):
		if node.has_meta("actor_id"):
			id=str(node.get_meta("actor_id"));break
		node=node.get_parent()
	if is_instance_valid(ai_host):
		if ai_host.actors.has(id):return ai_host.is_identified(id)
		if ai_host.fortifications.has(id):return visibility_for_node(ai_host.fortifications[id].node)=="visible"
	if is_instance_valid(armor_host) and armor_host.units.has(id):return visibility_for_node(armor_host.units[id].model)=="visible"
	return true

func camera_aim_point(fallback:Vector3,hit:Dictionary) -> Vector3:
	return hit.position if not hit.is_empty() and player_hit_observable(hit) else fallback

func pick_target(screen:Vector2):
	if not target_is_visible():message="视线被烟幕遮挡，无法识别部位。";refresh_hud();return
	var origin:=camera.project_ray_origin(screen)
	var query:=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*100,1|8|128)
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return
	if not player_hit_observable(hit):return # Same feedback as an empty ray; no hidden-entity oracle.
	var collider:Node=hit.collider
	if not collider.has_meta("kind"):
		aim_weapon(hit.position);message="炮管朝向地形命中点。";refresh_hud();return
	var kind:String=collider.get_meta("kind")
	if kind=="ai_person":
		if not is_instance_valid(ai_host) or not ai_host.is_identified(str(collider.get_meta("actor_id",""))):message="对手不可识别，可沿原炮口方向盲射";refresh_hud();return
		part=str(collider.get_meta("key","torso"));aim_kind="ai_person"
	elif kind=="person":part=collider.get_meta("key");aim_kind="infantry" if target_infantry else "armor"
	elif kind=="armor_group":module_name=Combat.face_from_hit(collider,hit.normal);aim_kind="armor"
	elif kind=="armor":module_name=collider.get_meta("key");aim_kind="armor"
	elif kind=="tarp":aim_kind="tarp"
	elif kind=="thin_plate":aim_kind="thin_plate"
	aim_weapon(hit.position)
	message="炮塔/炮管转向点选位置；射击仍以实际炮口方向为准。";refresh_hud()

func spawn_shot(mg:bool,recoil_player:bool=true,contact:bool=true,round_index:int=-1,surface:String="ground",feedback:Dictionary={}):
	feedback=feedback.duplicate()
	if not feedback.has("visual_weapon"):feedback["visual_weapon"]=preload("res://scripts/weapon_vfx_profile.gd").describe(catalog_entry(),"mg" if mg else "cannon","mg" if mg else "primary")
	var visual:Dictionary=preload("res://scripts/weapon_vfx_profile.gd").resolve(feedback.visual_weapon,"mg" if mg else "cannon")
	if round_index<0:round_index=ammo
	if recoil_player and is_instance_valid(battle_controls):
		battle_controls.record_shot("mg" if mg else "smoke" if round_index==2 else "cannon", contact and effect_point_visible(last_impact-(last_impact-last_muzzle).normalized()*.22))
	if recoil_player and is_instance_valid(ai_host) and ai_host.has_method("suppress_near_segment"):
		ai_host.suppress_near_segment(last_muzzle,last_impact,"blue","mg" if mg else "cannon")

	if recoil_player and not mg:
		var barrel:Node3D=hero.find_child("Barrel",true,false)
		if is_instance_valid(barrel):
			if not barrel.has_meta("rest_position"):barrel.set_meta("rest_position",barrel.position)
			var rest:Vector3=barrel.get_meta("rest_position")
			barrel.position=rest+barrel.basis.z.normalized()*float(visual.recoil_distance)
			var tween:=create_tween();tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS);tween.tween_property(barrel,"position",rest,float(visual.recoil_time))
	if not is_instance_valid(combat_effects):combat_effects=CombatEffects.new();stage.add_child(combat_effects)
	var direction:Vector3=(last_impact-last_muzzle).normalized()
	if not combat_effects.fire(last_muzzle,last_impact,"mg" if mg else "smoke" if round_index==2 else "cannon",contact and effect_point_visible(last_impact-direction*.22),surface,not(scoped and recoil_player),recoil_player,Callable(self,"effect_point_visible"),"mg" if mg else ["ap","he","smoke"][round_index] if round_index>=0 and round_index<3 else "kinetic",feedback):suppressed_shot_visuals+=1

func spawn_smoke():
	if is_instance_valid(smoke_root):smoke_root.queue_free()
	smoke_root=SmokeCloud.new();stage.add_child(smoke_root);smoke_root.global_position=last_impact

func spawn_fire():
	if not is_instance_valid(tarp_root):return
	# Idempotent: repeated incendiary impacts never add unbounded flame nodes.
	if tarp_root.get_node_or_null("BurningVFX")!=null:return
	var flame=preload("res://scripts/battle_vfx_fire.gd").new()
	flame.name="BurningVFX";tarp_root.add_child(flame)
## Fixed-step weapon slew prevents render stalls producing one huge sweep.
## Battle controls submit intent once each physics tick before calling this.
func weapon_aim_speed_radians() -> float:
	return deg_to_rad(float({"mg":75,"cannon":50,"short_rocket":30}.get(primary_weapon(),50)) if str(catalog_entry().get("fictional_stats",""))=="car" else (60 if unit==0 else 85))

func advance_weapon_aim(delta:float):
	aim_contact_blocked=false
	if game_mode=="skirmish" and not garage and not is_instance_valid(weapon_override) and not player_can_fire():
		aiming_pending=false;return
	if aiming_pending and is_instance_valid(hero):
		var turret:Node3D=hero.find_child("Turret",true,false)
		var barrel:Node3D=hero.find_child("Barrel",true,false)
		if turret!=null and barrel!=null:
			var contact_before:Dictionary=vehicle_contacts.capture_pose(hero)
			var speed:float=weapon_aim_speed_radians()*delta
			turret.rotation.y+=clampf(wrapf(desired_yaw-turret.rotation.y,-PI,PI),-speed,speed)
			barrel.rotation.x=move_toward(barrel.rotation.x,desired_pitch,speed)
			aim_contact_blocked=bool(vehicle_contacts.resolve_pose(hero,contact_before,0.0,delta).get("blocked",false))
			if absf(wrapf(desired_yaw-turret.rotation.y,-PI,PI))<.001 and absf(desired_pitch-barrel.rotation.x)<.001:aiming_pending=false
func _advance_game_clock(delta:float):
	elapsed+=delta
	if not garage and not battle_finished:vehicle_ammo.advance(delta)
	var held_fire:bool=is_instance_valid(battle_controls) and battle_controls.fire_held
	var held_mg:bool=is_instance_valid(battle_controls) and (battle_controls.mg_held or (held_fire and primary_weapon()=="mg"))
	reload_remaining=maxf(-delta if held_fire else 0.0,reload_remaining-delta)
	mg_remaining=maxf(-delta if held_mg else 0.0,mg_remaining-delta)
	if not garage and unit<2 and not is_instance_valid(weapon_override):
		var primary_state:Dictionary=vehicle_ammo.status(PLAYER_VEHICLE_ID,"primary")
		if primary_weapon()=="cannon":reload_remaining=float(primary_state.remaining)
		elif primary_weapon()=="short_rocket":reload_remaining=float(primary_state.get("cooldown",0.0))
		mg_remaining=machinegun_cooldown()
	mortar_adapter.tick(self,delta)
	combat.advance_time(delta)
	if is_instance_valid(smoke_root):
		smoke_root.advance(delta)
		if smoke_root.age>=SmokeCloud.DURATION:smoke_root.queue_free();smoke_root=null

func _physics_process(delta:float):
	if not garage and not battle_finished:
		if mounted_kind()=="mortar" and artillery_aim.selected and not artillery_aim.manual:aim_weapon(artillery_aim.target,false,delta)
		artillery_aim.tick(self,delta)
	if is_battle_active():_advance_game_clock(delta)
	if not battle_finished and not is_battle_active():advance_weapon_aim(delta)

func _process(delta:float):
	if is_battle_active() and ai_started_generation==stage_generation and not player_combat.crew.is_empty() and not player_combat.crew[0].alive:
		end_battle("车长阵亡")
	if battle_finished:return
	_retry_terrain_events()
	simulation_anchor_timer-=delta
	if simulation_anchor_timer<=0 and is_instance_valid(terrain_damage) and terrain_damage.has_method("set_simulation_anchors"):
		simulation_anchor_timer=.5
		var anchors:Array=[]
		if is_instance_valid(hero):anchors.append(hero.global_position)
		if is_instance_valid(ai_host):
			for actor in ai_host.actors.values():
				if is_instance_valid(actor) and not actor.embarked and actor.brain.hp>0:anchors.append(actor.global_position)
		if is_instance_valid(armor_host):
			for entry in armor_host.units.values():
				if is_instance_valid(entry.model):anchors.append(entry.model.global_position)
		terrain_damage.set_simulation_anchors(anchors)
	if not garage and is_instance_valid(hero) and is_instance_valid(terrain_damage) and terrain_damage.has_method("set_focus"):
		terrain_damage.set_focus(player_infantry_controller.actor().global_position if is_instance_valid(player_infantry_controller) and player_infantry_controller.active() else hero.global_position)
	if not is_battle_active():_advance_game_clock(delta)
	if scoped:
		var muzzle:Node3D=weapon_muzzle()
		if muzzle!=null:
			var view_pose:Transform3D=muzzle.get_global_transform_interpolated() if get_tree().is_physics_interpolation_enabled() else muzzle.global_transform
			view_pose=tank_sight.view_pose(self,view_pose)
			camera.global_transform=view_pose
			camera.position+=-view_pose.basis.z*.15
			camera.fov=32
	if is_instance_valid(weather_root) and weather_index==1:
		for drop in weather_root.get_children():
			drop.position.y-=delta*9
			if drop.position.y<0:drop.position.y=8
	if not garage:update_visibility()
	hud_tick+=delta
	if not garage and hud_tick>=.1:
		hud_tick=0;refresh_hud()
	for child in stage.get_children():
		if child is Node3D and child.has_meta("combat_vfx"):child.visible=effect_point_visible(child.global_position)
	for effect in effect_nodes.duplicate():
		if is_instance_valid(effect.node):
			for part_node in effect.node.get_children():
				if part_node is Node3D:part_node.visible=effect_point_visible(part_node.global_position)
		effect.life-=delta
		if effect.life<=0:
			if is_instance_valid(effect.node):effect.node.queue_free()
			effect_nodes.erase(effect)

func add_internal_crew(parent:Node3D,state=null):
	# Prototype has no documented crew layout; retain role state without invented internal hit volumes.
	if parent==hero and artillery_mode():return
	if state==null:state=combat
	var locations:Array=[Vector3(0,.3,.7),Vector3(.65,.2,-.3),Vector3(-.65,.0,-1.7),Vector3(-.65,.25,.6),Vector3(.65,.0,-1.6)]
	var body_scale:=.65
	if parent==hero and catalog_proxies.has(selected_catalog_id):
		var proxy:Dictionary=catalog_proxies[selected_catalog_id].hull
		var center:=array_vector(proxy.center)
		var dimensions:=array_vector(proxy.size)
		body_scale=minf(.45,dimensions.y/1.9)
		locations=[]
		for i in range(state.crew.size()):
			locations.append(center+Vector3((i%2-.5)*dimensions.x*.4,-.8*body_scale,(float(i)/maxf(1,state.crew.size()-1)-.5)*dimensions.z*.55))
	if parent==hero:
		for i in range(state.crew.size()):
			var seat:Node3D=hero.find_child("CrewSeat"+str(i),true,false)
			if seat!=null:locations[i]=hero.to_local(seat.global_position)-Vector3(0,1.19,0)*body_scale
	for i in range(state.crew.size()):
		for key in person_boxes():
			var spec:Array=person_boxes()[key]
			var body:=StaticBody3D.new();body.collision_layer=2;body.collision_mask=0
			body.set_meta("crew_index",i);body.set_meta("key",key);body.position=locations[i]+spec[0]*body_scale
			var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=spec[1]*body_scale;collider.shape=shape;body.add_child(collider);parent.add_child(body)

func cycle_terrain():
	terrain_index=(terrain_index+1)%3
	message="独立地形质量检查："+["平原","丘陵梯田","风蚀岩地"][terrain_index]+"；不与其他地块拼接。"
	load_display()
func load_terrain():
	if CedarArt.enabled() and game_mode == "skirmish":
		# Rivergate is an opt-in comparison map profile, never a second combat authority.
		# The authored Cedar version and unchanged legacy terrain remain selectable.
		var rivergate := bool(ProjectSettings.get_setting("rivergate/enabled", true)) and not "--cedar-original" in OS.get_cmdline_user_args()
		var ridgevale := "--ridgevale" in OS.get_cmdline_user_args()
		var terrain_script := "res://ridgevale/terrain.gd" if ridgevale else "res://rivergate/terrain.gd" if rivergate else "res://cedar/terrain.gd"
		var scenery_script := "res://ridgevale/world.gd" if ridgevale else "res://rivergate/world.gd" if rivergate else "res://cedar/world.gd"
		terrain_damage = load(terrain_script).new()
		stage.add_child(terrain_damage)
		terrain_root = terrain_damage
		var map_result: Dictionary = terrain_damage.configure(Vector3.ZERO, null)
		if not map_result.get("ok", false):
			push_error("Authored map failed: " + str(map_result))
			get_tree().quit(2)
			return
		var scenery = load(scenery_script).new()
		stage.add_child(scenery)
		scenery.build(terrain_damage)
		return
	var paths=["plains","hills_terraces","rock_arch"]
	var path:String="res://assets/terrain_contact/"+paths[terrain_index]+".glb"
	if ResourceLoader.exists(path):
		terrain_root=load(path).instantiate();stage.add_child(terrain_root);terrain_root.scale=Vector3.ONE*5;terrain_root.position.z=6
		prepare_terrain(terrain_root)
		vehicle_contacts.install_terrain_trees(terrain_root)
		configure_terrain_damage()
	else:
		box(stage,Vector3(0,-.16,6),Vector3(65,.3,70),material(Color("626953")))
		var body:=StaticBody3D.new();body.collision_layer=8
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(65,.3,70);collision.shape=shape;body.add_child(collision);stage.add_child(body);body.position=Vector3(0,-.16,6)
func prepare_terrain(node:Node):
	if "Plinth" in node.name and node is Node3D:node.visible=false
	if node is StaticBody3D:node.collision_layer=8;node.collision_mask=0
	if node is MeshInstance3D and not "Plinth" in node.name:
		# Runtime-only presentation grade; source vertex colors and GLB are unchanged.
		var source_mat:Material=node.get_active_material(0)
		if source_mat is StandardMaterial3D:
			var graded:StandardMaterial3D=source_mat.duplicate()
			graded.albedo_color*=Color(.50,.55,.46,1)
			node.material_override=graded
		var has_collision:=false
		for child in node.get_children():
			if child is StaticBody3D:has_collision=true
		if not has_collision:node.create_trimesh_collision()
	for child in node.get_children():prepare_terrain(child)
func indirect_surface_height(x:float,z:float)->float:
	return indirect_sampler.sample(terrain_damage,x,z)
func terrain_height(x:float,z:float) -> float:
	if is_instance_valid(terrain_damage) and terrain_damage.has_method("sample_height"):
		return terrain_damage.sample_height(x,z)
	var query:=PhysicsRayQueryParameters3D.create(Vector3(x,40,z),Vector3(x,-40,z),8)
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else 0.0
func settle_on_terrain(align_weapon:bool=true,generation:int=-1):
	await get_tree().physics_frame
	await get_tree().physics_frame
	if garage or not is_instance_valid(target) or (generation>=0 and generation!=stage_generation):return
	if align_weapon and terrain_index!=0 and is_instance_valid(terrain_damage):
		var spot:=find_clear_range_spot()
		var delta:=Vector3(spot.x-target.position.x,0,spot.z-target.position.z)
		for object in [target,hero,tarp_root,thin_plate]:
			if is_instance_valid(object):object.position+=delta
		camera.position+=delta
		for object in stage.get_children():
			if object.has_meta("crew_hologram"):object.position+=delta
	var previous_y:float=target.position.y
	for object in [target,hero,tarp_root,thin_plate]:
		if is_instance_valid(object):
			object.position.y=terrain_height(object.position.x,object.position.z)
			if object==target and not target_infantry or object==hero and unit<2:
				align_vehicle_ground(object,align_weapon)
			elif object==tarp_root:
				object.position.y=minf(terrain_height(object.position.x-.5,object.position.z),terrain_height(object.position.x+.5,object.position.z))
	if align_weapon and unit<2 and not crew_mode:camera.position.y=(target.position.y+hero.position.y)*.5+7
	else:camera.position.y+=target.position.y-previous_y
	if (game_mode=="skirmish" or terrain_index==2) and align_weapon and unit<2:
		camera.position=target.position+Vector3(1,9,-25)
		camera.position.y=(target.position.y+hero.position.y)*.5+9
	camera.look_at(range_focus())
	if align_weapon:aim_weapon(target.position+Vector3(0,1.05,0),true)
	if game_mode=="skirmish" and align_weapon and ai_started_generation!=stage_generation:
		ai_started_generation=stage_generation
		if is_instance_valid(ai_host):ai_host.spawn(stage)
		if is_instance_valid(crew_host):crew_host.bind_player()
		if combined_battle_enabled and is_instance_valid(armor_host):armor_host.spawn(stage)

func heightfield_height(x:float,z:float) -> float:
	if is_instance_valid(terrain_damage) and terrain_damage.has_method("sample_height"):
		return terrain_damage.sample_height(x,z)
	var query:=PhysicsRayQueryParameters3D.create(Vector3(x,40,z),Vector3(x,-40,z),64)
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else NAN

func find_clear_range_spot() -> Vector3:
	# Choose a genuine low-slope heightfield footprint, never an arch/tree roof.
	var best:=Vector3(12,0,12)
	var best_score:float=INF
	for x in range(-10,13,2):
		for z in range(2,17,2):
			var low:float=INF;var high:float=-INF;var valid:=true
			for offset in [Vector2(-1.5,-2.5),Vector2(1.5,-2.5),Vector2(-1.5,2.5),Vector2(1.5,2.5),Vector2.ZERO,Vector2(4,1),Vector2(3,-1.5),Vector2(-6,-11)]:
				var q:=Vector3(float(x)+offset.x,0,float(z)+offset.y)
				var surface:float=heightfield_height(q.x,q.z)
				if not is_finite(surface) or absf(terrain_height(q.x,q.z)-surface)>.16:valid=false;break
				if absf(offset.x)<2 and absf(offset.y)<3:low=minf(low,surface);high=maxf(high,surface)
			if not valid:continue
			# Verify the whole player footprint and the initial viewing corridor.
			for offset in [Vector2(-8,-13),Vector2(-4,-13),Vector2(-8,-9),Vector2(-4,-9)]:
				var px:float=x+offset.x;var pz:float=z+offset.y
				var floor_y:float=heightfield_height(px,pz)
				if not is_finite(floor_y) or absf(terrain_height(px,pz)-floor_y)>.16:valid=false;break
			if not valid:continue
			var target_eye:=Vector3(x,heightfield_height(x,z)+1.5,z)
			var hero_eye:=Vector3(x-6,heightfield_height(x-6,z-11)+1.8,z-11)
			var camera_eye:=Vector3(x+1,(target_eye.y+hero_eye.y)*.5+7.5,z-25)
			for pair in [[camera_eye,target_eye],[camera_eye,hero_eye],[hero_eye,target_eye]]:
				if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pair[0],pair[1],8)).is_empty():valid=false;break
			if not valid:continue
			var score:float=(high-low)*10+Vector2(x,z-8).length()*.01
			if score<best_score:best_score=score;best=Vector3(x,0,z)
	return best

func align_vehicle_ground(vehicle:Node3D,fit_orientation:bool=true):
	return GroundSupport.fit(self,vehicle,fit_orientation)

func range_focus() -> Vector3:
	if crew_mode and not target_infantry:return target.position+Vector3(-1,1.1,0)
	return (target.position+hero.position)*.5+Vector3(0,1.3,0) if unit<2 else target.position+Vector3(0,1,-1)

func cycle_weather():
	weather_index=(weather_index+1)%3;build_weather();update_visibility();refresh_hud()
func build_weather():
	CedarArt.grade_weather(self)
	if is_instance_valid(weather_root):weather_root.queue_free()
	weather_root=Node3D.new();stage.add_child(weather_root)
	weather_overlay.color=Color(.42,.48,.51,.0 if weather_index==0 else (.10 if weather_index==1 else .3))
	if weather_index==1:
		var mat:=material(Color("829ba3"),.7,0,.3)
		for i in range(65):
			var drop:=box(weather_root,Vector3((i%9-4)*1.8,float((i*7)%8),float(i/9)*2-4),Vector3(.018,.55,.018),mat)
			drop.rotation.z=.1
func target_is_visible() -> bool:
	if game_mode=="skirmish":return true
	update_visibility()
	return visibility_reason=="visible"
## Player knowledge is sourced from the controlled person or their existing optic,
## never from the orbit camera. This is geometric LOS, not a simulated optical cabin.
func observation_context() -> Dictionary:
	var subject:Node3D=hero
	var origin:=Vector3.ZERO
	var sensor:="vehicle_commander"
	if is_instance_valid(player_infantry_controller) and player_infantry_controller.active():
		subject=player_infantry_controller.actor()
		origin=subject.global_position+Vector3.UP*subject.aim_height
		sensor="commander_on_foot"
	elif is_instance_valid(hero) and game_mode in ["practice","engineering"]:
		# These existing training modes have no crew registry; bind to their real
		# controlled display actor, never carry this adapter into skirmish.
		if unit==2 and not bool(player_combat.infantry.alive):return {}
		if unit<2 and (player_combat.crew.is_empty() or not bool(player_combat.crew[0].alive)):return {}
		origin=hero.global_position+Vector3.UP*(1.1 if unit==2 else 1.6)
		sensor="training_person"
	elif is_instance_valid(hero) and game_mode=="skirmish":
		if not is_instance_valid(crew_host):return {}
		var person:Dictionary=crew_host.registry.person_ref(crew_host.commander_person_id())
		if person.is_empty() or not bool(person.get("alive",false)) or float(person.get("hp",0))<=0 or person.get("location",{}).get("kind","")!="vehicle":return {}
		# Existing vehicle observation height used by the team sensor/minimap.
		origin=hero.global_position+Vector3.UP*1.6
	else:return {}
	if scoped:
		var optic:Node3D=weapon_muzzle()
		if not is_instance_valid(optic):return {}
		# Same authored muzzle socket and .15 offset as the existing scope camera.
		origin=optic.global_position-optic.global_basis.z*.15
		sensor="weapon_optic"
	var excluded:Array[RID]=[]
	_collect_observation_rids(subject,excluded)
	return {"origin":origin,"exclude":excluded,"sensor":sensor,"range_multiplier":crew_host.observation_multiplier() if is_instance_valid(crew_host) and sensor!="commander_on_foot" else 1.0}

func _collect_observation_rids(node:Node,output:Array[RID]) -> void:
	if node is CollisionObject3D:output.append(node.get_rid())
	for child in node.get_children():_collect_observation_rids(child,output)

func observation_reason(point:Vector3,subject:Node3D=null,endpoint_margin:float=0.0) -> String:
	var observer:Dictionary=observation_context()
	if observer.is_empty():return "observer_unavailable"
	var origin:Vector3=observer.origin
	var weather:String=["clear","rain","fog"][weather_index]
	if origin.distance_to(point)>Visibility.WEATHER[weather].distance*float(observer.range_multiplier):return "range"
	var direction:Vector3=(point-origin).normalized()
	var query:=PhysicsRayQueryParameters3D.create(origin,point-direction*minf(endpoint_margin,origin.distance_to(point)),1|8|16|32|128,observer.exclude)
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	var blocked:bool=not hit.is_empty()
	if blocked and is_instance_valid(subject):blocked=hit.collider!=subject and not subject.is_ancestor_of(hit.collider)
	var center:Vector3=smoke_root.obscuration_center() if is_instance_valid(smoke_root) else Vector3.ZERO
	return Visibility.reason(origin,point,weather,center,is_instance_valid(smoke_root) and combat.smoke_remaining>0,blocked,smoke_root.obscuration_radius() if is_instance_valid(smoke_root) else 0.0)

func visibility_for_node(subject:Node3D) -> String:
	if not is_instance_valid(subject):return "range"
	return observation_reason(subject.global_position+Vector3.UP*1.1,subject)
func update_visibility():
	if garage or not is_instance_valid(target):return
	visibility_reason=visibility_for_node(target)
	target.visible=visibility_reason=="visible" and game_mode!="skirmish"
	for node in stage.get_children():
		if node.has_meta("crew_hologram"):node.visible=target.visible
	if is_instance_valid(thin_plate):
		for label in thin_plate.get_children():
			if label is Label3D:
				label.visible=not scoped and camera.global_position.distance_to(thin_plate.global_position)>5 and visibility_for_node(thin_plate)=="visible" and not (is_instance_valid(construction_host) and construction_host.model.occupied!="")
	if is_instance_valid(construction_host) and is_instance_valid(construction_host.tester):
		construction_host.tester.visible=visibility_for_node(construction_host.tester)=="visible"

func terrain_mesh(node:Node) -> MeshInstance3D:
	if node is MeshInstance3D and "Terrain" in node.name:return node
	for child in node.get_children():
		var found:=terrain_mesh(child)
		if found!=null:return found
	return null
func configure_terrain_damage():
	var source:MeshInstance3D=terrain_mesh(terrain_root)
	if source==null:return
	if game_mode=="skirmish":
		terrain_damage=load("res://modules/terrain_damage/streamed_battle_terrain.gd").new();stage.add_child(terrain_damage)
		var world_result:Dictionary=terrain_damage.configure(Vector3.ZERO,source)
		if not world_result.ok:message="战场地形加载失败："+str(world_result.get("error","unknown"))
		return
	terrain_damage=Node3D.new();terrain_damage.set_script(load("res://modules/terrain_damage/terrain_damage.gd"));stage.add_child(terrain_damage)
	var result:Dictionary=terrain_damage.configure_from_mesh(source)
	if not result.ok:message="此地块破坏暂不可用："+str(result.error)
	else:terrain_damage.body.collision_layer=8|64
func explode_terrain(position:Vector3,explosive_mass_kg:float) -> Dictionary:
	if is_instance_valid(ai_host) and ai_host.has_method("apply_blast_suppression") and explosive_mass_kg>0:ai_host.apply_blast_suppression(position,"blue",6.5)
	requested_terrain_events+=1
	if not position.is_finite() or not is_finite(explosive_mass_kg) or explosive_mass_kg<=0 or not is_instance_valid(terrain_damage):failed_terrain_events+=1;return {"ok":false,"error":"invalid_terrain_event"}
	# The bounded practice controller retains its original crater command API.
	# Only the streamed battle controller accepts charge-mass explosions.
	var result:Dictionary
	if terrain_damage.has_method("apply_explosion"):
		result=terrain_damage.apply_explosion(position,explosive_mass_kg)
	else:
		result=damage_terrain(position,"crater")
	if result.get("ok",false):accepted_terrain_events+=1
	elif result.get("error","")=="edit_queue_full":
		terrain_explosion_outbox.append({"position":position,"mass":explosive_mass_kg});deferred_terrain_events+=1
		return {"ok":true,"deferred":true}
	else:failed_terrain_events+=1
	return result

func damage_terrain(position:Vector3,kind:String) -> Dictionary:
	if not is_instance_valid(terrain_damage):return {"ok":false,"error":"no_terrain_controller"}
	var center:=Vector3(position.x,terrain_height(position.x,position.z),position.z)
	var result:Dictionary=terrain_damage.apply_command(center,kind)
	if result.get("ok",false):
		terrain_damage.flush_updates()
		call_deferred("settle_on_terrain",false)
	return result
func fire_mortar(muzzle:Node3D):
	mortar_adapter.fire(self,muzzle)

func spawn_arc(points:Array):
	var root:=Node3D.new();stage.add_child(root)
	for i in range(points.size()-1):
		if i%2!=0 or points[i].distance_to(camera.global_position)<1.4:continue
		var a:Vector3=points[i];var b:Vector3=points[i+1]
		if a.distance_to(b)<.01:continue
		var segment:=cylinder(root,(a+b)*.5,.025,a.distance_to(b),material(Color("ead79e"),.3,0,3))
		segment.look_at(b,Vector3.UP);segment.rotate_object_local(Vector3.RIGHT,PI*.5);segment.visible=effect_point_visible(segment.global_position)
	effect_nodes.append({"node":root,"life":.65})

func update_body_materials(node:Node):
	if node is MeshInstance3D:
		var name:String=node.name
		var key:="torso"
		if "Head" in name or "Helmet" in name:key="head"
		elif "Arm_L" in name or "Hand_L" in name:key="left_arm"
		elif "Arm_R" in name or "Hand_R" in name:key="right_arm"
		elif "Thigh_L" in name or "Shin_L" in name or "Foot_L" in name:key="left_leg"
		elif "Thigh_R" in name or "Shin_R" in name or "Foot_R" in name:key="right_leg"
		if not combat.infantry.alive:node.material_override=material(Color("515d62"))
		elif combat.infantry.parts[key]!="healthy":node.material_override=material(Color("b39455"))
	for child in node.get_children():update_body_materials(child)

func refresh_hologram():
	for node in stage.get_children():
		if node.has_meta("crew_hologram"):
			stage.remove_child(node);node.queue_free()
	if crew_mode and not target_infantry and not garage:build_crew_hologram(target.position+Vector3(-4,0,-1))

func mark_plate():
	if not is_instance_valid(thin_plate):return
	var local:Vector3=thin_plate.to_local(last_impact)
	box(thin_plate,local+Vector3(0,0,-.01),Vector3(.14,.14,.03),material(Color("17252b")))

func blast_occluded(origin:Vector3) -> bool:
	if not target_infantry:return false
	var destination:Vector3=target.global_position+Vector3(0,1.15,0)
	var query:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP*.035,destination,9)
	query.hit_from_inside=true
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and not target.is_ancestor_of(hit.collider)

func set_collision_layers(node:Node,layer:int):
	if node is CollisionObject3D:node.collision_layer=layer
	for child in node.get_children():set_collision_layers(child,layer)
func tag_actor_colliders(node:Node,id:String):
	if node is CollisionObject3D:node.set_meta("actor_id",id)
	for child in node.get_children():tag_actor_colliders(child,id)
func player_onboard_indices() -> Array:
	if is_instance_valid(crew_host) and crew_host.has_method("onboard_indices"):return crew_host.onboard_indices()
	return range(player_combat.crew.size())
func player_can_fire() -> bool:
	if battle_finished:return false
	if is_instance_valid(player_infantry_controller) and player_infantry_controller.active():return not player_infantry_controller.actor().weapon.is_empty()
	if game_mode!="skirmish" or garage:return true
	if is_instance_valid(crew_host):return not crew_host.person_ids.is_empty() and crew_host.can_fire()
	return player_combat.crew.size()>1 and preload("res://modules/vehicle_crew/role_capability.gd").capable(player_combat.crew[1],"gunner")
func player_reload_multiplier() -> float:
	return float(crew_host.reload_multiplier()) if game_mode=="skirmish" and is_instance_valid(crew_host) else 1.0
func player_status_text() -> String:
	var text:String="我方前甲完整度 %d%%\n" % player_combat.modules.front.integrity
	var onboard:Array=player_onboard_indices()
	for i in range(player_combat.crew.size()):
		text+=player_combat.crew_roles[i]+" · "+("离车" if not i in onboard else (("受伤在岗" if player_combat.crew[i].hp<10 else "在岗") if player_combat.crew[i].alive else "失能"))+"\n"
	return text+incoming_message
func apply_ai_hit(event:Dictionary):
	if garage or game_mode!="skirmish" or battle_finished:return
	var hit:Dictionary=event.get("hit",{})
	if hit.is_empty():return
	var body:Node=hit.collider
	if str(body.get_meta("actor_id",""))!="player":return
	var kind:String=str(body.get_meta("kind",""))
	if not kind in ["armor","armor_group"]:return
	var entry:String=str(body.get_meta("key","front"))
	if kind=="armor_group":entry=Combat.face_from_hit(body,hit.normal)
	var penetration:int=int(event.get("penetration",5))
	var small_arms:bool=str(event.get("weapon","rifle")) in ["pistol","rifle","sniper","smg","hmg","mg"]
	if small_arms:penetration=9
	if str(event.get("round",event.get("ammo",""))) in ["he","high_explosive"]:penetration=15
	if str(event.get("round",event.get("ammo","")))=="smoke":penetration=0
	var thickness:int=int(player_combat.modules.get(entry,{"thickness":100}).thickness)
	var impact:Dictionary={"normal":hit.get("normal",Vector3.ZERO),"direction":event.get("direction",Vector3.ZERO)} if event.has("direction") else {}
	var geometry:Dictionary=Combat.armor_geometry(thickness,impact)
	if small_arms and (penetration<=geometry.effective_thickness or not geometry.valid):
		incoming_message=preload("res://scripts/battle_hud_events.gd").impact_side(entry)+" · 轻武器被装甲挡住";record_incoming_hud();show_incoming_flash(.035);refresh_hud();return
	var onboard:Array=player_onboard_indices()
	var direction:Vector3=event.get("direction",Vector3.FORWARD)
	var index:=-1;var body_part:=""
	var exclude:Array[RID]=[]
	for attempt in range(12):
		var query:=PhysicsRayQueryParameters3D.create(hit.position+direction*.025,hit.position+direction*8,2)
		query.exclude=exclude
		var internal:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
		if internal.is_empty():break
		var candidate:int=int(internal.collider.get_meta("crew_index",-1))
		if str(internal.collider.get_meta("actor_id",""))=="player" and candidate in onboard:index=candidate;body_part=str(internal.collider.get_meta("key","torso"));break
		exclude.append(internal.collider.get_rid())
	var before_crew:Array=[]
	for member in player_combat.crew:before_crew.append({"hp":float(member.hp),"alive":bool(member.alive)})
	var result:Dictionary=player_combat.hit_armor(entry,penetration,index,body_part,onboard,impact)
	if is_instance_valid(armor_host) and armor_host.has_method("record_player_impact"):
		var after_crew:Array=[]
		for member in player_combat.crew:after_crew.append({"hp":float(member.hp),"alive":bool(member.alive)})
		armor_host.record_player_impact(event,{"entry":entry,"penetration":penetration,"thickness":thickness,"crew_index":index,"part":body_part,"onboard":onboard.duplicate(),"before_crew":before_crew,"after_crew":after_crew,"result":result})
	show_incoming_flash(.1 if result.kind=="penetrated" else .04)
	incoming_message=preload("res://scripts/battle_hud_events.gd").impact_side(entry)+(" · 装甲被穿透，检查车组" if result.kind=="penetrated" else " · 装甲挡住")
	record_incoming_hud()
	refresh_hud()
func record_incoming_hud() -> void:
	if is_instance_valid(battle_controls):battle_controls.record_incoming(incoming_message)

func spawn_ai_shot(origin:Vector3,impact:Vector3,weapon:String,contact:bool=true,visual_weapon:Dictionary={}):
	if not effect_point_visible(origin) and not effect_point_visible(impact):return
	if not is_instance_valid(combat_effects):combat_effects=CombatEffects.new();stage.add_child(combat_effects)
	var kind:="rocket" if weapon in ["at","rocket","grenade"] else ("cannon" if weapon=="cannon" else "mg")
	combat_effects.fire(origin,impact,kind,contact and effect_point_visible(impact),"ground",true,false,Callable(self,"effect_point_visible"),"kinetic",{"visual_weapon":visual_weapon})

func spawn_combat_vfx(effect:String,position:Vector3,direction:Vector3=Vector3.FORWARD,visual_weapon:Dictionary={}):
	if effect=="muzzle_pulse" and camera.global_position.distance_to(position)<1.4:return
	if effect in ["impact_explosion","muzzle_pulse","smoke_aftershot"]:
		# Mortar's following smoke callback is already part of the layered impact.
		if effect=="smoke_aftershot":return
		if not is_instance_valid(combat_effects):combat_effects=CombatEffects.new();stage.add_child(combat_effects)
		if effect=="impact_explosion":combat_effects.impact_at(position,Callable(self,"effect_point_visible"),visual_weapon)
		else:combat_effects.muzzle_at(position,direction,Callable(self,"effect_point_visible"),visual_weapon)
		return
	var path:String="res://assets/reused_combat/"+effect+".tscn"
	if not ResourceLoader.exists(path):return
	var count:=0
	for child in stage.get_children():
		if child.has_meta("combat_vfx"):count+=1
	if count>=18:return
	var instance:Node3D=load(path).instantiate();instance.set_meta("combat_vfx",true);stage.add_child(instance);instance.global_position=position;instance.visible=effect_point_visible(position)

func effect_point_visible(point:Vector3) -> bool:
	return observation_reason(point,null,.15)=="visible"

func array_vector(values:Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])
func load_catalog():
	var proxy_path:="res://assets/catalog_tanks/collision_proxies.json"
	if FileAccess.file_exists(proxy_path):catalog_proxies=JSON.parse_string(FileAccess.get_file_as_string(proxy_path)).get("vehicles",{})
	var path:="res://assets/catalog_tanks/catalog.json"
	if FileAccess.file_exists(path):
		var data=JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:catalog_vehicles=data.get("vehicles",[])
	var car_manifest:="res://assets/vehicles/manifest.json"
	if FileAccess.file_exists(car_manifest):
		var cars=JSON.parse_string(FileAccess.get_file_as_string(car_manifest))
		if cars is Dictionary:catalog_vehicles.append_array(cars.get("vehicles",[]))
	var car_proxies:="res://assets/vehicles/collision_proxies.json"
	if FileAccess.file_exists(car_proxies):
		var proxies=JSON.parse_string(FileAccess.get_file_as_string(car_proxies))
		if proxies is Dictionary:catalog_proxies.merge(proxies.get("vehicles",{}),true)
	var metric_proxies:="res://assets/metric_vehicles/collision_proxies.json"
	if FileAccess.file_exists(metric_proxies):
		var calibrated=JSON.parse_string(FileAccess.get_file_as_string(metric_proxies))
		if calibrated is Dictionary:
			var calibrated_vehicles:Dictionary=calibrated.get("vehicles",{})
			catalog_proxies.merge(calibrated_vehicles,true)
			for entry in catalog_vehicles:
				var id:String=str(entry.id)
				if calibrated_vehicles.has(id):entry.model_path="res://assets/metric_vehicles/"+id+".glb"
	var artillery_path:="res://assets/artillery_open/manifest.json"
	if FileAccess.file_exists(artillery_path):
		var artillery_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(artillery_path))
		catalog_vehicles.append(artillery_data.vehicle)
		catalog_proxies[str(artillery_data.vehicle.id)]=artillery_data.collision_proxy

	var mlrs_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/mlrs/manifest.json"))
	catalog_vehicles.append(mlrs_data.vehicle)
	catalog_proxies["mlrs_prototype"]=mlrs_data.collision_proxy

func catalog_entry() -> Dictionary:
	for vehicle in catalog_vehicles:
		if str(vehicle.id)==selected_catalog_id:return vehicle
	return {}
func catalog_yaw_limit() -> float:
	return deg_to_rad(float(catalog_entry().get("turret_yaw_limit_degrees",180)))
func catalog_pitch_limits() -> Vector2:
	var limits:Array=catalog_entry().get("barrel_pitch_degrees",[-12.6,31.5])
	return Vector2(deg_to_rad(limits[0]),deg_to_rad(limits[1]))
func select_catalog(id:String):
	for vehicle in catalog_vehicles:
		if str(vehicle.id)==id:
			selected_catalog_id=id
			ammo=1 if str(vehicle.get("weapon_class","cannon"))=="short_rocket" or str(vehicle.get("fire_profile",""))=="game_high_arc" else 0
			select_unit(0 if str(vehicle.fictional_stats)=="heavy" else 1)
			return

func rotate_limited_hull(amount:float) -> bool:
	if garage or unit>=2 or str(catalog_entry().get("aim_mode","turret"))!="limited_mount":return false
	if game_mode=="skirmish" and is_instance_valid(crew_host) and not crew_host.can_drive():
		message="驾驶员不在岗或失能，不能原地转向";refresh_hud();return false
	var previous:Transform3D=hero.transform
	var contact:Dictionary=vehicle_contacts.capture_pose(hero)
	hero.rotation.y+=amount
	align_vehicle_ground(hero)
	if vehicle_contacts.resolve_pose(hero,contact,0,.016).get("blocked",false):
		message="车体转向受阻";refresh_hud();return false
	aiming_pending=false
	return true

func hull_pose_clear() -> bool:
	var exclude:Array[RID]=[]
	for body in hero.find_children("*","CollisionObject3D",true,false):exclude.append(body.get_rid())
	if is_instance_valid(terrain_damage) and is_instance_valid(terrain_damage.body):exclude.append(terrain_damage.body.get_rid())
	for ground_body in get_tree().get_nodes_in_group("drivable_ground"):
		if ground_body is CollisionObject3D:exclude.append(ground_body.get_rid())
	for shape in hero.find_children("*","CollisionShape3D",true,false):
		if shape.disabled or not (shape.get_parent().collision_layer&1):continue
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=shape.global_transform;query.collision_mask=9|128;query.exclude=exclude;query.margin=.01
		var overlaps:Array=get_world_3d().direct_space_state.intersect_shape(query,1)
		if not overlaps.is_empty():hero.set_meta("turn_blocker",str(overlaps[0].collider.get_path()));return false
	return true

func show_incoming_flash(strength:float):
	if not is_instance_valid(damage_overlay):return
	damage_overlay.color=Color(1,.35,.1,strength)
	create_tween().tween_property(damage_overlay,"color:a",0.0,.35)

func select_artillery_target(point:Vector3)->bool:
	return artillery_aim.select(self,point) if indirect_fire_mode() else false

func indirect_fire_mode()->bool:
	return artillery_mode() or mounted_kind()=="mortar"

func artillery_mode() -> bool:
	return unit<2 and str(catalog_entry().get("fire_profile",""))=="game_high_arc"

func vehicle_loadout() -> Dictionary:
	if selected_catalog_id=="mlrs_prototype":return preload("res://modules/mlrs/host_adapter.gd").loadout()
	var config:Dictionary=VehicleAmmo.Config.loadout(primary_weapon())
	if artillery_mode():config.primary={"kind":"chamber","rounds":{"he":40},"initial":"he"}
	return config

func primary_weapon() -> String:
	return str(catalog_entry().get("weapon_class","cannon")) if unit<2 else "rifle"
func primary_reload() -> float:
	if str(catalog_entry().get("fictional_stats",""))=="car":return 7.0 if primary_weapon()=="short_rocket" else 2.5
	return 5.0 if unit==0 else 3.0
func primary_penetration() -> int:
	return 110 if str(catalog_entry().get("fictional_stats","heavy" if unit==0 else "light"))=="heavy" else 90
func fire_rocket_salvo():
	if garage or not player_can_fire():vehicle_fire_denied("role_unavailable");return
	if reload_remaining>0:return
	var script_path:="res://modules/vehicle_weapons/short_rocket.gd"
	if not ResourceLoader.exists(script_path):message="火箭组件尚未就绪";refresh_hud();return
	for name in ["Muzzle","Muzzle2","Muzzle3"]:
		if hero.find_child(name,true,false)==null:vehicle_fire_denied("muzzle_unavailable");return
	var begun:Dictionary=vehicle_ammo.begin_burst(PLAYER_VEHICLE_ID,"primary")
	if not bool(begun.ok):vehicle_fire_denied(str(begun.reason));return
	var token:int=int(begun.token)
	var generation:=stage_generation
	var input_epoch:=fire_input_epoch
	var index:=0
	for name in ["Muzzle","Muzzle2","Muzzle3"]:
		if generation!=stage_generation or input_epoch!=fire_input_epoch or garage or battle_finished or not player_can_fire():break
		var muzzle:Node3D=hero.find_child(name,true,false)
		var committed:Dictionary=vehicle_ammo.commit_burst_round(PLAYER_VEHICLE_ID,"primary",token,index,primary_reload()*player_reload_multiplier(),player_can_fire(),is_instance_valid(muzzle) and muzzle.is_inside_tree())
		if not bool(committed.ok):vehicle_fire_denied(str(committed.reason));break
		reload_remaining=float(vehicle_ammo.status(PLAYER_VEHICLE_ID,"primary").cooldown)
		var exclusions:Array[RID]=[]
		for body in hero.find_children("*","CollisionObject3D",true,false):exclusions.append(body.get_rid())
		var projectile:Node3D=load(script_path).new();stage.add_child(projectile)
		projectile.setup(muzzle.global_transform,exclusions,"player")
		projectile.set_meta("ammo_commit",committed.commit)
		shot_sequence+=1
		shot_audit.append({"id":shot_sequence,"accepted":true,"weapon":"rocket","ammo_commit":committed.commit,"vehicle_id":PLAYER_VEHICLE_ID,"origin":muzzle.global_position,"salvo_index":index})
		if shot_audit.size()>128:shot_audit.pop_front()
		if is_instance_valid(battle_controls):battle_controls.record_shot("rocket",false)
		var visual_weapon:Dictionary=preload("res://scripts/weapon_vfx_profile.gd").describe(catalog_entry(),"rocket","primary")
		visual_weapon["mount_id"]=name
		projectile.impacted.connect(_on_rocket_impact.bind(generation,int(committed.commit),visual_weapon))
		spawn_combat_vfx("muzzle_pulse",muzzle.global_position,-muzzle.global_basis.z,visual_weapon)
		message="短火箭逐枚发射 · 余 %d 枚"%vehicle_ammo.total(PLAYER_VEHICLE_ID,"primary");refresh_hud()
		index+=1
		await get_tree().create_timer(.18,false,true).timeout
	# A pre-reset coroutine must never clear a new battle/restore burst whose
	# numeric token happens to be reused. All emits above and cleanup share ownership.
	if generation==stage_generation and input_epoch==fire_input_epoch:
		vehicle_ammo.cancel_burst(PLAYER_VEHICLE_ID,"primary",token)
func _on_rocket_impact(event:Dictionary,generation:int=-1,ammo_commit:int=-1,visual_weapon:Dictionary={}):
	if garage or (generation>=0 and generation!=stage_generation):return
	var at:Vector3=event.position
	event["ammo_commit"]=ammo_commit
	var kind:String=interpret_hit(event)
	for record in shot_audit:
		if int(record.get("ammo_commit",-2))==ammo_commit:record["impact"]=at;record["hit_kind"]=kind;break
	if kind=="ai_armor":armor_host.handle_player_projectile(event,"rocket","he",15)
	if kind in ["ai_person","ai_fortification"] and is_instance_valid(ai_host):ai_host.handle_player_projectile(event,"rocket","he",part)
	elif kind=="infantry":combat.hit_person(combat.infantry,part)
	if effect_point_visible(at):spawn_combat_vfx("impact_explosion",at,Vector3.FORWARD,visual_weapon)
	if game_mode=="skirmish" and is_instance_valid(ai_host):ai_host.apply_player_blast(at)
	else:combat.high_explosive("infantry" if target_infantry else "armor",at.distance_to(target.global_position+Vector3.UP),blast_occluded(at))
	explode_terrain(at,AmmoProfiles.explosive_mass("short_rocket"))
	message="火箭在实际碰撞点爆炸" if effect_point_visible(at) else "火箭已发射，远处结果无法确认"
	update_person_visuals();refresh_hud()

func player_module_name(key:String) -> String:
	if str(catalog_entry().get("fictional_stats",""))=="car" and key.begins_with("track_"):return "左轮组" if key=="track_left" else "右轮组"
	return MODULE_CN.get(key,key)

func spawn_mg_sparks(at:Vector3,outward:Vector3):
	# Short visible contact sparks; this is not a damage marker or aiming reticle.
	var burst:=Node3D.new();stage.add_child(burst)
	for i in range(5):
		var spread:Vector3=(outward+Vector3(sin(i*2.4)*.8,.25+float(i%3)*.3,cos(i*2.4)*.8)).normalized()
		var a:Vector3=at+outward*.22
		var b:Vector3=a+spread*.18
		var spark:=cylinder(burst,(a+b)*.5,.012,.18,material(Color("ffc46a"),.3,0,2))
		spark.look_at(b,Vector3.UP);spark.rotate_object_local(Vector3.RIGHT,PI*.5);spark.visible=effect_point_visible(spark.global_position)
		create_tween().tween_property(spark,"position",spark.position+spread*.22,.4)
	effect_nodes.append({"node":burst,"life":.45})

func is_battle_active()->bool:
	return not garage and game_mode=="skirmish" and not battle_finished
func end_battle(reason:String)->void:
	if battle_finished:return
	battle_finished=true;battle_result=reason
	if is_instance_valid(battle_controls) and is_instance_valid(battle_controls.minimap):battle_controls.minimap.cancel()
	if is_instance_valid(battle_controls):battle_controls.set_menu(false);battle_controls.reset_pointers()
	if is_instance_valid(player_infantry_controller):player_infantry_controller.clear_input()
	stage.process_mode=Node.PROCESS_MODE_DISABLED
func _retry_terrain_events()->void:
	if terrain_explosion_outbox.is_empty() or not is_instance_valid(terrain_damage):return
	var event:Dictionary=terrain_explosion_outbox[0]
	var result:Dictionary=terrain_damage.apply_explosion(event.position,event.mass)
	if result.get("ok",false):accepted_terrain_events+=1;terrain_explosion_outbox.pop_front()
	elif result.get("error","")!="edit_queue_full":failed_terrain_events+=1;terrain_explosion_outbox.pop_front()

func clear_vehicle_fire_input() -> void:
	fire_input_epoch+=1
	vehicle_ammo.cancel_burst(PLAYER_VEHICLE_ID,"primary")

func vehicle_fire_denied(reason:String) -> void:
	message={"unregistered":"车载弹药状态不可用","muzzle_unavailable":"真实炮口不可用","role_unavailable":"炮手不在岗或已失能","loading":"装填未完成","empty_selected":"所选弹药已耗尽，请换弹种、机枪或撤离","cooldown":"武器冷却中","duplicate":"此次击发已处理"}.get(reason,"无法击发："+reason)
	if is_instance_valid(battle_controls):battle_controls.show_notice(message)
	refresh_hud()

func machinegun_total() -> int:
	return vehicle_ammo.total(PLAYER_VEHICLE_ID,"mg") + (vehicle_ammo.total(PLAYER_VEHICLE_ID,"mg_hull") if dual_machineguns.mounts.size()==2 else 0)

func ammunition_status_text() -> String:
	var mount:="mg" if primary_weapon()=="mg" else "primary"
	var state:Dictionary=vehicle_ammo.status(PLAYER_VEHICLE_ID,mount)
	var names:={"ap":"AP","he":"HE","smoke":"SMK","tracer":"曳光","incendiary":"燃烧","":"空膛"}
	if primary_weapon()=="cannon":
		var current:String=str(state.loading) if state.loading!="" else str(state.loaded)
		var counts:Dictionary=state.reserve.duplicate()
		for round_type in [state.loaded,state.loading]:
			if round_type!="":counts[round_type]=int(counts.get(round_type,0))+1
		return "%s%s · AP%d HE%d S%d · 下%s · MG%d"%[names.get(current,current),"填%.1fs"%float(state.remaining) if state.loading!="" else "在膛" if state.loaded!="" else "",int(counts.get("ap",0)),int(counts.get("he",0)),int(counts.get("smoke",0)),names.get(str(state.next),str(state.next)),machinegun_total()]
	return "%s · 余%d · %s"%["火箭" if primary_weapon()=="short_rocket" else names.get(str(state.next),str(state.next)),int(state.total),"冷却%.1fs"%float(state.get("cooldown",0)) if float(state.get("cooldown",0))>0 else "无自动补给"]

func restore_vehicle_ammunition(snapshot_data:Dictionary) -> Dictionary:
	var payload=snapshot_data.get("vehicle_ammo",{})
	if not payload is Dictionary:return {"ok":false,"reason":"ammo_snapshot_missing_or_incompatible"}
	var result:Dictionary=vehicle_ammo.restore(payload,true)
	if bool(result.ok):
		clear_vehicle_fire_input()
		if is_instance_valid(battle_controls):battle_controls.reset_pointers()
		var primary_state:Dictionary=vehicle_ammo.status(PLAYER_VEHICLE_ID,"primary")
		reload_remaining=float(primary_state.remaining) if primary_weapon()=="cannon" else float(primary_state.get("cooldown",0.0))
		mg_remaining=machinegun_cooldown()
		ammo=maxi(0,["ap","he","smoke"].find(str(primary_state.next)))
		mg_ammo=maxi(0,["tracer","ap","incendiary"].find(str(vehicle_ammo.status(PLAYER_VEHICLE_ID,"mg").next)))
	return result

func record_hit_feedback(shot_id:int,result:Dictionary,observable:bool)->void:
	if is_instance_valid(combat_effects):combat_effects.set_impact_result(shot_id,result,observable)
