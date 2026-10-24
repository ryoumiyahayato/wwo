extends RefCounted
## Small integration surface. No control, ammo, role or combat ownership here.
static func enabled() -> bool:
	return bool(ProjectSettings.get_setting("cedar/enabled", true)) and not "--cedar-legacy" in OS.get_cmdline_user_args()

static func dress_vehicle(model: Node3D, id: String) -> void:
	if not enabled() or id != "user_heavy_mbt" or model.has_meta("cedar_dressed"): return
	model.set_meta("cedar_dressed", true)
	for pair in [["Hull", "tank_hull_dressing"], ["Turret", "tank_turret_dressing"]]:
		var mount: Node3D = model.find_child(pair[0], true, false)
		if mount == null: continue
		var packed: PackedScene = load("res://cedar/assets/" + pair[1] + ".glb")
		if packed == null: continue
		var addition := packed.instantiate()
		addition.name = "CedarVisualOnly"
		mount.add_child(addition)
		# No collisions, gun sockets, damage plates or functional equipment added.

static func grade_environment(main: Node3D, battle: bool) -> void:
	if not enabled(): return
	for child in main.get_children():
		if child is WorldEnvironment:
			var env: Environment = child.environment
			if battle:
				var sky_material := ProceduralSkyMaterial.new()
				sky_material.sky_top_color = Color("547b9b")
				sky_material.sky_horizon_color = Color("cbd3cc")
				sky_material.ground_bottom_color = Color("626c53")
				sky_material.ground_horizon_color = Color("c1c8b8")
				sky_material.sun_angle_max = 8.0
				var sky := Sky.new()
				sky.sky_material = sky_material
				sky.radiance_size = Sky.RADIANCE_SIZE_128
				env.sky = sky
				env.background_mode = Environment.BG_SKY
				env.ambient_light_color = Color("c1c8b0")
				env.ambient_light_energy = 0.35
				env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			else:
				env.background_mode = Environment.BG_COLOR
				env.ambient_light_color = Color("9baec0")
				env.ambient_light_energy = 0.45
		elif child is DirectionalLight3D:
			child.light_color = Color("fff0d5") if battle else Color("fff5e6")
			child.light_energy = 0.55 if battle else 0.85
			child.directional_shadow_max_distance = 65.0 if battle else 45.0

static func grade_weather(main: Node3D) -> void:
	# Clear-weather readability only; preserve existing rainy/foggy density.
	if not enabled() or bool(main.get("garage")): return
	var clear_weather: bool = int(main.get("weather_index")) == 0
	for child in main.get_children():
		if child is WorldEnvironment:
			child.environment.fog_density = 0.00045 if clear_weather else 0.0016
			child.environment.fog_sky_affect = 0.25 if clear_weather else 1.0
