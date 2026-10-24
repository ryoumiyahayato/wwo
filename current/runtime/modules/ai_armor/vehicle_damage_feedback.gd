extends RefCounted
const Capability = preload("res://modules/vehicle_crew/role_capability.gd")
## Presentation derives from existing simulation facts; never creates damage or explosions.
## Engine, ammunition cook-off and structural destruction are not simulated yet.
var abandoned_material: StandardMaterial3D

static func status(u: Dictionary) -> Dictionary:
	var combat = u.combat
	var living := 0
	for person in combat.crew:
		if bool(person.alive): living += 1
	var driver_index: int = combat.crew_roles.find("驾驶员")
	var gunner_index: int = combat.crew_roles.find("炮手")
	var driver := driver_index >= 0 and Capability.capable(combat.crew[driver_index],"driver")
	var gunner := gunner_index >= 0 and Capability.capable(combat.crew[gunner_index],"gunner")
	var tracks := float(combat.modules.track_left.integrity) > 0 and float(combat.modules.track_right.integrity) > 0
	var eliminated := living == 0
	var mobility_disabled := not driver or not tracks
	var firepower_disabled := not gunner
	var burning: bool = combat.tarp_burning # External tarp only, not internal ammunition.
	var labels: Array[String] = []
	if eliminated: labels.append("乘员全失能 · 废车")
	else:
		if mobility_disabled: labels.append("机动失能")
		if firepower_disabled: labels.append("火力失能")
	if burning: labels.append("外置油布燃烧")
	return {"crew_eliminated":eliminated,"mobility_disabled":mobility_disabled,
		"firepower_disabled":firepower_disabled,"burning":burning,
		"ammo_explosion":false,"destroyed":false,"text":" / ".join(labels)}

func setup(u: Dictionary) -> void:
	if abandoned_material == null:
		abandoned_material = StandardMaterial3D.new()
		abandoned_material.albedo_color = Color("515659")
		abandoned_material.roughness = 1.0
	var label := Label3D.new()
	label.name = "DamageStatus"
	label.font = preload("res://cedar/system_font.tres")
	label.position = Vector3(0, 3.5, 0)
	label.font_size = 36
	label.pixel_size = .012
	label.modulate = Color("f0bd72")
	label.outline_modulate = Color("202326")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false # Never reveal an occluded enemy through walls.
	label.visibility_range_end = 60.0
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.hide()
	u.model.add_child(label)
	u["damage_label"] = label
	u["damage_meshes"] = []
	for mesh in u.model.find_children("*", "GeometryInstance3D", true, false):
		if mesh is MeshInstance3D or mesh is MultiMeshInstance3D:
			u.damage_meshes.append({"node":mesh,"original":mesh.material_override})
	u["feedback_signature"] = ""
	u["feedback_abandoned"] = false
	sync(u)

func sync(u: Dictionary) -> void:
	var state := status(u)
	u["damage_status"] = state
	u.model.set_meta("disabled",state.crew_eliminated)
	# Opposing crew/role state is not observable merely because the hull is visible.
	var signature: String = state.text
	if signature == str(u.get("feedback_signature","")): return
	u["feedback_signature"] = signature
	if is_instance_valid(u.get("damage_label")):
		u.damage_label.text = public_text(u,state)
		u.damage_label.visible = not u.damage_label.text.is_empty()
	if bool(u.get("feedback_abandoned",false)) != bool(state.crew_eliminated):
		u["feedback_abandoned"] = state.crew_eliminated
		for item in u.get("damage_meshes",[]):
			if is_instance_valid(item.node):
				item.node.material_override = abandoned_material if state.crew_eliminated and str(u.get("team","blue"))=="blue" else item.original
	if state.crew_eliminated:
		u.target = {}
		u.focus_id = ""
		u.stable_aim = 0.0
		u.speed = 0.0
		for key in ["track_left_speed","track_right_speed","vehicle_speed","steering_input"]:
			u.model.set_meta(key,0.0)

static func public_text(u: Dictionary, state: Dictionary) -> String:
	return str(state.text) if str(u.get("team","blue"))=="blue" else ("外置油布燃烧" if state.burning else "")

static func hit_message(result: Dictionary, u: Dictionary) -> String:
	var kind := str(result.get("kind",""))
	var message := "装甲被击穿" if kind == "penetrated" else "履带命中" if kind == "external_penetrated" else "装甲未击穿"
	if kind == "friendly_blocked": return "友军装甲阻挡"
	var state := status(u)
	if not str(state.text).is_empty(): message += " · " + str(state.text)
	return message
