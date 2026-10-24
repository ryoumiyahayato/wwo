extends Node3D
## Independent visual smoke-test host; main game supplies actual infantry control.
const Model = preload("res://modules/construction/construction_system.gd")
const View = preload("res://modules/construction/construction_view.gd")
const Patch = preload("res://modules/construction/excavation_patch.gd")
func _ready() -> void:
 var camera := Camera3D.new()
 add_child(camera)
 camera.position = Vector3(33,49,61)
 camera.look_at(Vector3(0,0,0))
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 76
 camera.current = true
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55,-30,0)
 light.shadow_enabled = true
 add_child(light)
 var env := WorldEnvironment.new()
 var environment := Environment.new()
 environment.background_mode = Environment.BG_COLOR
 environment.background_color = Color("202b32")
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("b8d1de")
 environment.ambient_light_energy = 0.7
 env.environment = environment
 add_child(env)
 var index := 0
 for preset in Model.PRESETS:
  var model := Model.new()
  var at := Vector3((index % 5-2)*14,0,(index/5)*16-8)
  var e := model.command({"op":"place","preset":preset,"position":[at.x,at.y,at.z],"site_valid":true,"slope_degrees":0,"excavation_ready":true})
  model.command({"op":"start","id":e.id})
  model.advance(20000)
  var view := View.new()
  add_child(view)
  view.sync(model.structures[e.id])
  var label := Label3D.new()
  label.text = Model.PRESETS[preset].label + " / " + preset
  label.font_size = 40
  label.pixel_size = 0.015
  label.position = at + Vector3(0,0.2,3.5)
  label.rotation_degrees.x = -65
  add_child(label)
  if preset == "foxhole":
   var patch := Patch.new()
   add_child(patch)
   patch.position = at
   patch.reserve(at)
   patch.set_progress(1.0)
  index += 1
 var overlay := CanvasLayer.new()
 add_child(overlay)
 var title := Label.new()
 title.text = "CONSTRUCTION LAB  /  10 fixed fictional game presets\nIndependent model + mesh/collision adapters · Main game handles combat and visibility"
 title.position = Vector2(24,20)
 title.add_theme_font_size_override("font_size",22)
 overlay.add_child(title)
