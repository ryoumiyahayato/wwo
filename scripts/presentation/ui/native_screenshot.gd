extends Node
## On-demand root-viewport PNG. No processing loop, retained Image or extra viewport.
const Catalog = preload("res://scripts/presentation/ui/map_resource_catalog.gd")
const OUTPUT: String = "user://screenshots"
signal completed(result: Dictionary)
var renderer: GlobeRenderer
var busy: bool = false
var last_result: Dictionary = {}

func _ready() -> void:
	set_process(false)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F12:
		get_viewport().set_input_as_handled()
		if not busy: capture.call_deferred()

func _pending() -> bool:
	if not renderer.is_visible_in_tree(): return false
	return renderer._has_pending_preparation() or renderer.region_view._landmark_render_pending or renderer._map_canvas_dirty or renderer._view_dirty or renderer._local_display_dirty or renderer._resource_demand_dirty or renderer._strategic_content_dirty or renderer._transition_elapsed>=0.0 or renderer.controller.camera_motion_active()

func capture(label: String = "F12") -> Dictionary:
	if busy: return {"ok":false,"error":"capture_busy"}
	busy = true
	var began := Time.get_ticks_usec()
	var root := get_tree().root
	var result: Dictionary = {"ok":false,"label":label,"window":{"visible":root.visible,"mode":root.mode,"focused":root.has_focus()}}
	if renderer.controller==null:
		busy=false
		return {"ok":false,"error":"map_controller_unavailable"}
	# Reject unavailable roots. Native-hidden main windows can still be drawable
	# on Compatibility; the finite driver tests that separately against a visible
	# control. Never restore, show, raise or focus a window for a screenshot.
	if not root.visible or root.mode==Window.MODE_MINIMIZED or not root.can_draw():
		result["error"]="root_hidden_or_minimized"
	else:
		var deadline := Time.get_ticks_msec()+30000
		var stable := 0
		while Time.get_ticks_msec()<deadline and stable<3:
			await get_tree().process_frame
			if not root.visible or root.mode==Window.MODE_MINIMIZED or not root.can_draw(): break
			# Complete the existing LOCAL child, then allow its ready signal to
			# publish into REGION and the root on subsequent process/draw cycles.
			RenderingServer.force_draw(false)
			stable = 0 if _pending() else stable+1
		if stable<3:
			result["error"]="map_not_drawn_or_window_unavailable"
		else:
			var readback := Time.get_ticks_usec()
			var image := root.get_texture().get_image()
			result["readback_us"]=Time.get_ticks_usec()-readback
			if image==null or image.is_empty(): result["error"]="empty_root_image"
			else:
				var stem := Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_usec())
				var folder := ProjectSettings.globalize_path(OUTPUT)
				var error := DirAccess.make_dir_recursive_absolute(folder)
				var png := folder.path_join(stem+".png")
				var json := folder.path_join(stem+".json")
				var report := metadata()
				report["label"]=label
				report["viewport_pixels"]=[image.get_width(),image.get_height()]
				var write_began := Time.get_ticks_usec()
				if error==OK: error=image.save_png(png)
				result["png_write_us"]=Time.get_ticks_usec()-write_began
				result["image_bytes"]=image.get_data_size()
				result["capture_us"]=Time.get_ticks_usec()-began
				report["capture"]={"readback_us":result.readback_us,"png_write_us":result.png_write_us,"elapsed_us":result.capture_us,"image_bytes":result.image_bytes}
				if error==OK:
					var file := FileAccess.open(json,FileAccess.WRITE)
					if file==null: error=FileAccess.get_open_error()
					else:
						file.store_string(JSON.stringify(report,"\t"))
						file.close()
				result.merge({"ok":error==OK,"error":error_string(error),"png":png,"json":json,"metadata":report},true)
	result["elapsed_us"]=Time.get_ticks_usec()-began
	busy = false
	last_result = result
	completed.emit(result)
	print("WWO_SCREENSHOT ",JSON.stringify(result))
	return result

func metadata() -> Dictionary:
	var controller := renderer.controller
	var camera := controller.region_camera
	var view := renderer.region_view
	var center := renderer.unit_at(renderer.size*.5)
	var ll := RegionProjection.lon_lat(center) if not center.is_zero_approx() else Vector2(INF,INF)
	var q := controller.orientation().get_rotation_quaternion()
	var local_camera := view._landmark_camera
	return {"schema_id":"wwo_native_screenshot_v1","captured_at":Time.get_datetime_string_from_system(),"timezone":Time.get_time_zone_from_system(),"project":Catalog.project_version(false),
		"map_mode":controller.map_mode,"camera":{"mode":"LOCAL" if camera.local_active else "REGION" if camera.active else "WORLD","center_lon_lat":[ll.x,ll.y] if ll.is_finite() else [],"world_orientation_quaternion":[q.x,q.y,q.z,q.w],"world_zoom":controller.zoom,"chart_basis":[TerrainPixelSource.serial(camera.tangent_frame.x),TerrainPixelSource.serial(camera.tangent_frame.y),TerrainPixelSource.serial(camera.tangent_frame.z)],"origin_pixels":[camera.origin.x,camera.origin.y],"metres_per_pixel":camera.km_per_pixel*1000.0,"bearing_radians":camera.bearing,"elevation_radians":view.elevation_at(camera),"local_place_id":camera.local_place_id,"native_position":TerrainPixelSource.serial(local_camera.position) if local_camera!=null else [],"native_rotation":TerrainPixelSource.serial(local_camera.rotation) if local_camera!=null else [],"view_only":true},
		"window":{"visible":get_tree().root.visible,"mode":get_tree().root.mode,"focused":get_tree().root.has_focus(),"visibility_source":"Godot Window; native HWND state is recorded separately by the finite launcher"},"display":{"surface_path":view._local_surface_key,"surface_presented":view._surface_presented_key,"local_rect":[view._local_render_rect.position.x,view._local_render_rect.position.y,view._local_render_rect.size.x,view._local_render_rect.size.y],"relief_textures":renderer.relief.textures.keys(),"pending":_pending()},
		"memory":{"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}}
