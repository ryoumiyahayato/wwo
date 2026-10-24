class_name InterfaceSettings
extends RefCounted
## Audio/display preferences only. No world or save-state ownership.
const PATH: String = "user://interface_settings.cfg"
const PARIS_PAINTING = preload("res://assets/menu/paris_street_rainy_day_1877.jpg")

static func theme_parameters() -> Dictionary:
	# One actual theme: shared controls plus the Cabinet instrument palette.
	# The globe's brass and historical map strokes retain their existing values.
	return {"id":"paris_1877","name":"1900 · 巴黎","background":PARIS_PAINTING,
		"design_name":"Le Cabinet du Monde — 世界仪器室",
		"panel":Color(0.018,0.030,0.047,0.94),"ink":Color(0.91,0.86,0.73),
		"brass":Color(0.64,0.54,0.32,0.65),"button":Color(0.025,0.042,0.056,0.95),
		"button_hover":Color(0.08,0.12,0.14,0.97),
		"title_size":58,"menu_motion":0.012,
		"admin_line":Color(0.48,0.57,0.60,0.45),
		"hud":{"body":Color(0.025,0.043,0.061,0.94),
			"seam":Color(0.013,0.020,0.025,0.96),
			"bronze":Color(0.23,0.18,0.11,0.96),
			"metal":Color(0.58,0.47,0.29,0.96),
			"highlight":Color(0.82,0.72,0.49,0.90),
			"ivory":Color(0.93,0.89,0.79,1.0),
			"muted":Color(0.65,0.73,0.72,1.0),
			"teal":Color(0.39,0.57,0.56,0.72),
			"status":Color(0.53,0.23,0.22,0.90),
			"clock_radius":144.0,"title_size":16,"caption_size":11}}


static func load_preferences() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PATH)
	return {"volume":clampf(float(config.get_value("audio","volume",0.8)),0.0,1.0),"bgm":bool(config.get_value("audio","bgm",true)),"fullscreen":bool(config.get_value("display","fullscreen",false)),"theme":str(config.get_value("display","theme","paris_1877")),"labels":false}

static func apply(value: Dictionary) -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.0001,float(value.volume))))
	AudioServer.set_bus_mute(0,float(value.volume)<=0.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value.get("fullscreen",false)) else DisplayServer.WINDOW_MODE_WINDOWED)
	var bgm_bus := AudioServer.get_bus_index("BGM")
	if bgm_bus>=0: AudioServer.set_bus_mute(bgm_bus,not bool(value.bgm))

static func save(value: Dictionary) -> Error:
	apply(value)
	var config := ConfigFile.new()
	config.set_value("audio","volume",value.volume)
	config.set_value("audio","bgm",value.bgm)
	config.set_value("display","fullscreen",value.get("fullscreen",false))
	config.set_value("display","theme",value.get("theme","paris_1877"))
	return config.save(PATH)

