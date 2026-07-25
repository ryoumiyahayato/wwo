extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_runtime.gd"
## Final integration layer: complete flag differentiation and player-country detail rules.

const FOREIGN_ADMIN1_NOTICE := "外国视角停留在一级行政区；只有当前人物所属国家开放下一级本地细节。"


func _on_flag_timer_timeout() -> void:
	if space_level != WORLD or world_mode != WORLD_COUNTRIES or not is_visible_in_tree():
		return
	super._on_flag_timer_timeout()


func _prewarm_distinctive_flag_textures() -> void:
	for entity_key: Variant in _history_entity_by_id.keys():
		var entity_id := str(entity_key)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		if entity.is_empty() or bool(entity.get("provisional", false)):
			continue
		if int(entity.get("label_rank", 9)) <= 2:
			_flag_texture_for_entity(entity_id, _resolved_flag_palette(str(entity.get("iso_a3", ""))))


func _distinctive_pattern_for_entity(entity_id: String, fallback: String) -> String:
	match entity_id:
		"british_isles_1900", "british_empire_overseas": return "union"
		"united_states_1900", "united_states_overseas", "republic_of_liberia": return "stripes_canton"
		"qing_empire": return "dragon_disc"
		"empire_of_japan": return "sun_disc"
		"ottoman_empire": return "crescent"
		"austria_hungary": return "dual_monarchy"
		"kingdom_of_nepal": return "double_pennant"
		"kingdom_of_bhutan": return "dragon_diagonal"
		"korean_empire": return "taegeuk"
		"kingdom_of_portugal", "portuguese_empire": return "armillary"
		"congo_free_state": return "single_star"
		"sweden_norway_union": return "union_cross"
		"kingdom_of_denmark": return "nordic_cross"
		"swiss_confederation": return "swiss_cross"
		"kingdom_of_greece": return "cross_stripes"
		"persia_qajar": return "lion_sun"
		"kingdom_of_siam": return "elephant"
		"moroccan_sultanate": return "morocco_star"
		"united_states_of_brazil", "brazil": return "diamond_disc"
		_:
			var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
			if bool(entity.get("provisional", false)):
				return fallback
			return "sealed|%s|%d" % [fallback, abs(entity_id.hash()) % 63]


func _distinctive_flag_color(pattern: String, colors: PackedColorArray, u: float, v: float) -> Color:
	if pattern.begins_with("sealed|"):
		var parts := pattern.split("|")
		var base_pattern := str(parts[1]) if parts.size() > 1 else "solid"
		var variant := int(parts[2]) if parts.size() > 2 else 0
		var base := super._distinctive_flag_color(base_pattern, colors, u, v)
		return _apply_generic_seal(base, colors, variant, u, v)
	if pattern == "taegeuk": return _taegeuk_color(colors, u, v)
	if pattern == "armillary": return _armillary_color(colors, u, v)
	if pattern == "single_star": return _single_star_color(colors, u, v)
	if pattern == "union_cross": return _union_cross_color(colors, u, v)
	if pattern == "nordic_cross": return _nordic_cross_color(colors, u, v)
	if pattern == "swiss_cross": return _swiss_cross_color(colors, u, v)
	if pattern == "cross_stripes": return _cross_stripes_color(colors, u, v)
	if pattern == "lion_sun": return _lion_sun_color(colors, u, v)
	if pattern == "elephant": return _elephant_color(colors, u, v)
	if pattern == "morocco_star": return _morocco_star_color(colors, u, v)
	if pattern == "diamond_disc": return _diamond_disc_color(colors, u, v)
	return super._distinctive_flag_color(pattern, colors, u, v)


func _apply_generic_seal(base: Color, colors: PackedColorArray, variant: int, u: float, v: float) -> Color:
	var ink := _contrast_color(colors, base)
	var shape := variant % 7
	var x_slot := int(variant / 7) % 3
	var y_slot := int(variant / 21) % 3
	var center := Vector2(0.5 + float(x_slot - 1) * 0.13, 0.5 + float(y_slot - 1) * 0.11)
	var p := Vector2(u, v) - center
	match shape:
		0:
			if p.length() < 0.105: return ink
		1:
			if _star_distance(p, 5) < 0.050: return ink
		2:
			if (absf(p.x) < 0.030 and absf(p.y) < 0.16) or (absf(p.y) < 0.030 and absf(p.x) < 0.16): return ink
		3:
			if absf(p.x) + absf(p.y) < 0.145: return ink
		4:
			var ring := p.length()
			if ring > 0.080 and ring < 0.125: return ink
		5:
			if absf(p.y - absf(p.x) * 0.75) < 0.030 and p.y > -0.10: return ink
		6:
			if absf(p.x) < 0.12 and absf(p.y) < 0.075: return ink
	return base


func _taegeuk_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var p := Vector2(u, v) - Vector2(0.5, 0.5)
	if p.length() > 0.235: return colors[0]
	return colors[mini(1, colors.size() - 1)] if p.y < sin(p.x * 16.0) * 0.035 else colors[mini(2, colors.size() - 1)]


func _armillary_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var base := super._distinctive_flag_color("vertical", colors, u, v)
	var p := Vector2(u, v) - Vector2(0.48, 0.5)
	if (p.length() > 0.12 and p.length() < 0.165) or (absf(p.x) < 0.022 and absf(p.y) < 0.19) or (absf(p.y) < 0.022 and absf(p.x) < 0.19): return Color("#c5a64a")
	return base


func _single_star_color(colors: PackedColorArray, u: float, v: float) -> Color:
	return colors[mini(1, colors.size() - 1)] if _star_distance(Vector2(u, v) - Vector2(0.5, 0.5), 5) < 0.075 else colors[0]


func _union_cross_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var base := colors[0]
	if absf(u - 0.38) < 0.09 or absf(v - 0.5) < 0.12: base = colors[mini(1, colors.size() - 1)]
	if absf(u - 0.38) < 0.035 or absf(v - 0.5) < 0.045: base = colors[mini(2, colors.size() - 1)]
	return base


func _nordic_cross_color(colors: PackedColorArray, u: float, v: float) -> Color:
	return colors[mini(1, colors.size() - 1)] if absf(u - 0.36) < 0.055 or absf(v - 0.5) < 0.075 else colors[0]


func _swiss_cross_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var p := Vector2(u, v) - Vector2(0.5, 0.5)
	return colors[mini(1, colors.size() - 1)] if (absf(p.x) < 0.055 and absf(p.y) < 0.20) or (absf(p.y) < 0.055 and absf(p.x) < 0.20) else colors[0]


func _cross_stripes_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var blue := colors[0]
	var white := colors[mini(1, colors.size() - 1)]
	if u < 0.38 and v < 0.55: return white if absf(u - 0.19) < 0.045 or absf(v - 0.275) < 0.06 else blue
	return white if int(floor(v * 9.0)) % 2 == 0 else blue


func _lion_sun_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var base := super._distinctive_flag_color("horizontal", colors, u, v)
	var p := Vector2(u, v) - Vector2(0.5, 0.5)
	return Color("#c4a248") if p.length() < 0.105 or (absf(p.y) < 0.025 and p.x > -0.18 and p.x < 0.20) else base


func _elephant_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var p := Vector2(u, v) - Vector2(0.5, 0.52)
	return colors[mini(1, colors.size() - 1)] if (absf(p.x) < 0.17 and absf(p.y) < 0.09) or (p.x > 0.10 and p.x < 0.18 and p.y > -0.02 and p.y < 0.18) else colors[0]


func _morocco_star_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var distance := _star_distance(Vector2(u, v) - Vector2(0.5, 0.5), 5)
	return colors[mini(1, colors.size() - 1)] if distance > 0.04 and distance < 0.075 else colors[0]


func _diamond_disc_color(colors: PackedColorArray, u: float, v: float) -> Color:
	var p := Vector2(u, v) - Vector2(0.5, 0.5)
	if p.length() < 0.13: return colors[mini(2, colors.size() - 1)]
	if absf(p.x) / 0.34 + absf(p.y) / 0.25 < 1.0: return colors[mini(1, colors.size() - 1)]
	return colors[0]


func _contrast_color(colors: PackedColorArray, base: Color) -> Color:
	for color: Color in colors:
		if absf(color.r - base.r) + absf(color.g - base.g) + absf(color.b - base.b) > 0.55: return color
	return Color(1.0 - base.r * 0.65, 1.0 - base.g * 0.65, 1.0 - base.b * 0.65, 1.0)


func _star_distance(point: Vector2, points: int) -> float:
	return absf(point.length() - (0.085 + 0.045 * cos(float(points) * atan2(point.y, point.x))))


func flag_coverage_report() -> Dictionary:
	var explicit_count := 0
	var generated_count := 0
	var signatures: Dictionary = {}
	for entity_key: Variant in _history_entity_by_id.keys():
		var entity_id := str(entity_key)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		if entity.is_empty() or bool(entity.get("provisional", false)): continue
		explicit_count += 1
		var texture := _flag_texture_for_entity(entity_id, _resolved_flag_palette(str(entity.get("iso_a3", ""))))
		if texture != null:
			generated_count += 1
			var signature := _visual_flag_signature(texture)
			if not signature.is_empty(): signatures[signature] = true
	return {"explicit_count":explicit_count, "generated_count":generated_count, "unique_signatures":signatures.size()}


func _visual_flag_signature(texture: ImageTexture) -> String:
	if texture == null: return ""
	var image := texture.get_image()
	if image == null or image.is_empty(): return ""
	var parts := PackedStringArray()
	for row: int in range(8):
		for column: int in range(12):
			var x := mini(image.get_width() - 1, int((float(column) + 0.5) * float(image.get_width()) / 12.0))
			var y := mini(image.get_height() - 1, int((float(row) + 0.5) * float(image.get_height()) / 8.0))
			parts.append(image.get_pixel(x, y).to_html(false))
	return "-".join(parts)


func _focus_selected_country() -> void:
	if selected_country_id == FOCUS_COUNTRY_ID and _home_historical_entity_id() != FOCUS_COUNTRY_ID:
		_enter_generic_historical_focus()
		_sync_moon_visibility()
		return
	super._focus_selected_country()


func _enter_region() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and not _is_home_historical_entity(selected_country_id):
		var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
		if selected_historical_territory_iso.is_empty() and territories.size() == 1:
			selected_historical_territory_iso = str((territories[0] as Dictionary).get("iso_a3", ""))
		if selected_historical_territory_iso.is_empty(): return
		space_level = REGION
		_set_info_open(false)
		viewport_container.visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()
		_sync_moon_visibility()
		return
	super._enter_region()


func _enter_selected_world_admin1() -> void:
	super._enter_selected_world_admin1()


func _activate_button(action: String) -> void:
	if action == "history_enter_admin1" and world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and not _is_home_historical_entity(selected_country_id):
		queue_redraw()
		return
	super._activate_button(action)


func _draw_world_admin1_layer() -> void:
	super._draw_world_admin1_layer()
	if _is_home_historical_entity(selected_country_id): return
	for index: int in range(_button_hits.size() - 1, -1, -1):
		if str((_button_hits[index] as Dictionary).get("action", "")) == "history_enter_admin1": _button_hits.remove_at(index)
	var rect := _main_content_rect(110.0, 166.0, 104.0)
	var button_rect := Rect2(rect.end.x - 156.0, rect.end.y - 40.0, 132.0, 28.0)
	_panel(button_rect, Color(0.045, 0.050, 0.047, 0.92), Color(0.36, 0.34, 0.28, 0.24))
	_draw_label(button_rect.position + Vector2(10.0, 18.0), "外国省级视图", 10, Color(0.58, 0.60, 0.56, 1.0))
	_draw_label(rect.position + Vector2(24.0, rect.size.y - 42.0), FOREIGN_ADMIN1_NOTICE, 10, Color(0.72, 0.77, 0.72, 0.88))


func _enter_generic_historical_focus() -> void:
	if selected_country_id.is_empty() or not _history_entity_by_id.has(selected_country_id): return
	space_level = WORLD
	world_mode = WORLD_HISTORICAL_ENTITY_FOCUS
	selected_historical_territory_iso = ""
	hover_historical_territory_iso = ""
	selected_event_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	viewport_container.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_info_open(false)
	_history_focus_dirty = true
	queue_redraw()


func _home_historical_entity_id() -> String:
	var profile: Dictionary = _character_profiles.get(active_character_key, {}) as Dictionary
	var nationality_id := str(profile.get("nationality_id", FOCUS_COUNTRY_ID))
	if _history_entity_by_id.has(nationality_id): return nationality_id
	var iso := nationality_id.trim_prefix("country_").to_upper() if nationality_id.begins_with("country_") else nationality_id.to_upper()
	if iso.is_empty(): return FOCUS_COUNTRY_ID
	var fallback := ""
	for entity_key: Variant in _history_territories_by_entity.keys():
		var entity_id := str(entity_key)
		var config: Dictionary = _history_entity_by_id.get(entity_id, {}) as Dictionary
		for core_value: Variant in (config.get("core_members", []) as Array):
			if str(core_value).to_upper() == iso: return entity_id
		for territory_value: Variant in (_history_territories_by_entity.get(entity_id, []) as Array):
			if str((territory_value as Dictionary).get("iso_a3", "")).to_upper() == iso: fallback = entity_id
	return fallback if not fallback.is_empty() else FOCUS_COUNTRY_ID


func _is_home_historical_entity(entity_id: String) -> bool:
	return entity_id == _home_historical_entity_id()


func home_country_detail_report() -> Dictionary:
	return {"active_character_key":active_character_key, "home_entity_id":_home_historical_entity_id(), "selected_entity_id":selected_country_id, "selected_is_home":_is_home_historical_entity(selected_country_id)}
