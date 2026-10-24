extends Node
## Bound only Android battle 3D pixel cost; 2D controls retain native output.
## Explicit fixed budget, not an FPS controller (CPU stalls must not blur graphics).
const MAX_SHORT_EDGE := 900.0
const MAX_PIXELS := 1800000.0
var main: Node
var force_for_testing := false
var low_pixel_mode := false
const LOW_PIXEL_SCALE := 0.67
var _elapsed := 0.0
var _last_scale := -1.0
var changes := 0

func setup(owner_main: Node) -> void:
 name = "MobileRenderBudget"
 main = owner_main
 var preferences:=ConfigFile.new()
 if preferences.load("user://graphics.cfg")==OK:low_pixel_mode=bool(preferences.get_value("rendering","low_pixel_mode",false))
 refresh()

static func scale_for_size(output_size: Vector2i) -> float:
 if output_size.x <= 0 or output_size.y <= 0: return 1.0
 var short_edge := float(mini(output_size.x, output_size.y))
 var pixels := float(output_size.x) * float(output_size.y)
 return minf(1.0, minf(MAX_SHORT_EDGE / short_edge, sqrt(MAX_PIXELS / pixels)))

func _process(delta: float) -> void:
 _elapsed += delta
 if _elapsed < 0.25: return
 _elapsed = 0.0
 refresh()

func refresh() -> void:
 if not is_instance_valid(main): return
 var window := get_tree().root
 var enabled := (OS.get_name() == "Android" or force_for_testing) and not bool(main.get("garage"))
 var next_scale := scale_for_size(window.size) if enabled else 1.0
 if low_pixel_mode and not bool(main.get("garage")):next_scale=minf(next_scale,LOW_PIXEL_SCALE)
 window.msaa_3d=Viewport.MSAA_DISABLED if low_pixel_mode and not bool(main.get("garage")) else Viewport.MSAA_2X
 if is_equal_approx(next_scale, _last_scale): return
 window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
 window.scaling_3d_scale = next_scale
 _last_scale = next_scale
 changes += 1

func set_low_pixel_mode(value: bool, persist := true) -> void:
 low_pixel_mode=value
 refresh()
 if persist:
  var preferences:=ConfigFile.new()
  preferences.set_value("rendering","low_pixel_mode",value)
  preferences.save("user://graphics.cfg")

func snapshot() -> Dictionary:
 var window := get_tree().root
 return {"window_pixels":window.size,"logical_ui_size":window.get_visible_rect().size,"scale_3d":window.scaling_3d_scale,"estimated_3d_pixels":Vector2i(Vector2(window.size) * window.scaling_3d_scale),"budget_short_edge":MAX_SHORT_EDGE,"budget_pixels":MAX_PIXELS,"changes":changes,"low_pixel_mode":low_pixel_mode,"msaa_3d":window.msaa_3d,"renderer":RenderingServer.get_current_rendering_method()}
